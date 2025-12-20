from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _load_cases(path: Path) -> List[Dict[str, Any]]:
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, list):
        raise ValueError(f"Expected a JSON list in {path}")
    for item in data:
        if not isinstance(item, dict) or "note_id" not in item or "cursor" not in item:
            raise ValueError(f"Invalid case entry in {path}: {item!r}")
    return data


def _source_preview(text: str, cursor: int, *, left: int = 180, right: int = 220) -> str:
    cursor = max(0, min(int(cursor), len(text)))
    start = max(0, cursor - left)
    end = min(len(text), cursor + right)
    snippet = text[start:end].replace("\r\n", "\n").replace("\r", "\n")
    return snippet.strip().replace("\n", "\n")


@dataclass(frozen=True)
class _Args:
    cases_path: Path
    out_json: Path
    out_md: Path
    limit: int


def _default_args() -> _Args:
    base = _repo_root() / "tests" / "backend"
    return _Args(
        cases_path=base / "semantic_backlinks_sample_cases.json",
        out_json=base / "semantic_backlinks_sample_report.json",
        out_md=base / "semantic_backlinks_sample_report.md",
        limit=3,
    )


def generate() -> Dict[str, Any]:
    import sys

    sys.path.insert(0, str(_repo_root() / "backend"))

    from app_state import GrimoireAppState  # type: ignore
    from context_models import ContextRequest  # type: ignore

    args = _default_args()
    cases = _load_cases(args.cases_path)

    state = GrimoireAppState()
    services = state.current()

    # Ensure indices exist and required models are available (no fallbacks).
    services.notes.rebuild_index()

    report: Dict[str, Any] = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "limit": int(args.limit),
        "cases": [],
    }

    for case in cases:
        note_id = str(case["note_id"])
        cursor = int(case["cursor"])
        record = services.storage.get_note(note_id)
        results = services.notes.semantic_context(
            ContextRequest(
                note_id=note_id,
                text=record.content,
                cursor_offset=cursor,
                limit=args.limit,
                include_debug=True,
            )
        )

        report_case = {
            "note_id": note_id,
            "cursor": cursor,
            "source_preview": _source_preview(record.content, cursor),
            "results": [
                {
                    "note_id": r.note_id,
                    "text": r.text,
                    "score": float(r.score),
                    "debug": r.debug or {},
                }
                for r in results
            ],
        }
        report["cases"].append(report_case)

    args.out_json.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    lines: List[str] = []
    lines.append("# Semantic Backlinks Sample Report")
    lines.append("")
    lines.append(f"Generated: {report['generated_at']}")
    lines.append("")
    lines.append(f"Cases: {len(report['cases'])} (limit={report['limit']})")
    lines.append("")

    for i, case in enumerate(report["cases"], 1):
        lines.append(f"## Case {i}")
        lines.append(f"- Source: `{case['note_id']}`")
        lines.append(f"- Cursor: `{case['cursor']}`")
        lines.append(f"- Source Preview: {case['source_preview']!r}")
        for j, res in enumerate(case["results"], 1):
            dbg = res.get("debug") or {}
            score = float(res["score"])
            quality = float(dbg["quality"])
            rel = float(dbg["relevance"])
            lex = float(dbg["lexical"])
            active_hits = dbg.get("active_label_hits")
            base = float(dbg["base"])
            lines.append(
                f"- Result {j}: `{res['note_id']}` | score={score:.3f} | "
                f"quality={quality:.3f} | rel={rel:.3f} | lex={lex:.3f} | "
                f"active_hits={active_hits} | base={base:.3f}"
            )
            lines.append(f"  - Excerpt: {res['text']!r}")
        lines.append("")

    args.out_md.write_text("\n".join(lines), encoding="utf-8")
    return report


if __name__ == "__main__":
    generate()
