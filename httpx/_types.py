from typing import Any, Dict, Iterable, Mapping, MutableMapping, Sequence, Tuple, Union

URLTypes = Union[str, "URL"]
RequestContent = Union[str, bytes, bytearray, Iterable[bytes], None]
RequestFiles = Any
QueryParamTypes = Any
HeaderTypes = Union[Mapping[str, str], Sequence[Tuple[str, str]], None]
CookieTypes = Any
TimeoutTypes = Any
AuthTypes = Any
