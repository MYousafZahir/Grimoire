"""
Lightweight stub implementation of a subset of httpx used by FastAPI/Starlette TestClient.
This is not a full-featured HTTP client but is sufficient for synchronous testing in
restricted environments where installing the real httpx package is not possible.
"""
from __future__ import annotations

import json
import urllib.parse
from typing import Any, Dict, Iterable, List, Mapping, MutableMapping, Optional, Sequence, Tuple, Union

from . import _client
from . import _types

__all__ = [
    "Request",
    "Response",
    "Client",
    "Headers",
    "URL",
    "BaseTransport",
    "ByteStream",
    "USE_CLIENT_DEFAULT",
]

USE_CLIENT_DEFAULT = _client.USE_CLIENT_DEFAULT


class URL:
    def __init__(self, url: Union[str, "URL"]):
        if isinstance(url, URL):
            self._url = url.raw
        else:
            self._url = str(url)
        parsed = urllib.parse.urlsplit(self._url)
        self.scheme = parsed.scheme or "http"
        self.host = parsed.hostname or ""
        self.port = parsed.port
        netloc = parsed.netloc or self.host
        if self.port and ":" not in netloc:
            netloc = f"{self.host}:{self.port}"
        self.netloc = netloc.encode()
        self.path = parsed.path or "/"
        query = parsed.query or ""
        self.query = query.encode()
        raw_path = self.path
        if query:
            raw_path = f"{raw_path}?{query}"
        self.raw_path = raw_path.encode()
        self.raw = self._url

    def join(self, url: str) -> "URL":
        return URL(urllib.parse.urljoin(self._url, url))

    def __str__(self) -> str:  # pragma: no cover - debugging helper
        return self._url


class Headers:
    def __init__(self, headers: Mapping[str, str] | Sequence[Tuple[str, str]] | None = None):
        self._items: List[Tuple[str, str]] = []
        if headers:
            if isinstance(headers, Mapping):
                self._items.extend([(k, v) for k, v in headers.items()])
            else:
                self._items.extend([(str(k), str(v)) for k, v in headers])

    def get(self, key: str, default: Optional[str] = None) -> Optional[str]:
        key_lower = key.lower()
        for k, v in reversed(self._items):
            if k.lower() == key_lower:
                return v
        return default

    def multi_items(self) -> List[Tuple[str, str]]:
        return list(self._items)

    def items(self) -> List[Tuple[str, str]]:
        return self.multi_items()

    def __contains__(self, key: str) -> bool:
        return self.get(key) is not None


class ByteStream:
    def __init__(self, content: Union[bytes, bytearray, Iterable[bytes]]):
        if isinstance(content, (bytes, bytearray)):
            self.content = bytes(content)
        elif hasattr(content, "read"):
            self.content = content.read()
        else:
            self.content = b"".join(content)

    def __iter__(self):
        yield self.content

    def read(self) -> bytes:
        return self.content


class Request:
    def __init__(
        self,
        method: str,
        url: Union[str, URL],
        *,
        headers: Mapping[str, str] | Sequence[Tuple[str, str]] | None = None,
        content: Optional[Union[str, bytes, bytearray, Iterable[bytes]]] = None,
        data: Any = None,
        json: Any = None,
        params: Any = None,
    ) -> None:
        self.method = method.upper()
        self.url = URL(url)
        base_headers = Headers(headers)
        self.headers = base_headers
        self._content = content
        self.data = data
        self.json_data = json
        self.params = params

    def read(self) -> bytes:
        if self._content is None:
            return b""
        if isinstance(self._content, str):
            return self._content.encode("utf-8")
        if isinstance(self._content, (bytes, bytearray)):
            return bytes(self._content)
        if hasattr(self._content, "read"):
            return self._content.read()
        return b"".join(self._content)


class Response:
    def __init__(
        self,
        status_code: int,
        headers: Sequence[Tuple[str, str]] | Mapping[str, str] | None = None,
        stream: ByteStream | bytes | bytearray | Iterable[bytes] = b"",
        request: Request | None = None,
        **_: Any,
    ) -> None:
        self.status_code = status_code
        self.headers = Headers(headers if headers is not None else [])
        self.stream = stream if isinstance(stream, ByteStream) else ByteStream(stream)
        self.request = request

    @property
    def content(self) -> bytes:
        return self.stream.read()

    @property
    def text(self) -> str:
        try:
            return self.content.decode("utf-8")
        except UnicodeDecodeError:
            return self.content.decode(errors="replace")

    def json(self) -> Any:
        return json.loads(self.text or "null")


class BaseTransport:
    def handle_request(self, request: Request) -> Response:  # pragma: no cover - interface
        raise NotImplementedError


class Client:
    def __init__(
        self,
        base_url: str = "",
        headers: Mapping[str, str] | None = None,
        transport: BaseTransport | None = None,
        follow_redirects: bool = True,
        cookies: Any = None,
    ) -> None:
        self.base_url = URL(base_url or "http://localhost")
        self.headers = Headers(headers or {})
        self.transport = transport or BaseTransport()
        self.follow_redirects = follow_redirects
        self.cookies = cookies

    def _merge_url(self, url: Union[str, URL]):
        if isinstance(url, URL):
            return url
        if url.startswith("http"):
            return URL(url)
        return self.base_url.join(url)

    def request(
        self,
        method: str,
        url: Union[str, URL],
        *,
        content: _types.RequestContent | None = None,
        data: Any = None,
        files: Any = None,
        json: Any = None,
        params: Any = None,
        headers: _types.HeaderTypes = None,
        cookies: Any = None,
        auth: Any = None,
        follow_redirects: bool | _client.UseClientDefault = _client.USE_CLIENT_DEFAULT,
        timeout: Any = _client.USE_CLIENT_DEFAULT,
        extensions: dict[str, Any] | None = None,
    ) -> Response:
        if json is not None and content is None:
            content_bytes = json_module.dumps(json).encode("utf-8")
            content = content_bytes
        request_headers: List[Tuple[str, str]] = self.headers.multi_items()
        if headers:
            if isinstance(headers, Mapping):
                request_headers.extend(list(headers.items()))
            else:
                request_headers.extend(list(headers))
        merged_url = self._merge_url(url)
        request = Request(method, merged_url, headers=request_headers, content=content, data=data, json=json, params=params)
        if not self.transport:
            raise RuntimeError("No transport configured for httpx.Client")
        return self.transport.handle_request(request)

    def get(self, url: Union[str, URL], **kwargs: Any) -> Response:
        return self.request("GET", url, **kwargs)

    def post(self, url: Union[str, URL], **kwargs: Any) -> Response:
        return self.request("POST", url, **kwargs)

    def delete(self, url: Union[str, URL], **kwargs: Any) -> Response:
        return self.request("DELETE", url, **kwargs)

    def put(self, url: Union[str, URL], **kwargs: Any) -> Response:
        return self.request("PUT", url, **kwargs)

    def options(self, url: Union[str, URL], **kwargs: Any) -> Response:
        return self.request("OPTIONS", url, **kwargs)

    def head(self, url: Union[str, URL], **kwargs: Any) -> Response:
        return self.request("HEAD", url, **kwargs)


# Expose nested modules to mirror httpx API surface expected by Starlette
from . import _types as _types
from . import _client as _client

# Local json module alias used inside Client.request
import json as json_module
