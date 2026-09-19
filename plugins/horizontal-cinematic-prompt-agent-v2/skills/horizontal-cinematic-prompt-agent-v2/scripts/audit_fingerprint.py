"""Compute the rule bundle fingerprint used to bind audit reports."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Iterable


RULE_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RULE_FILES = (
    RULE_ROOT / "SKILL.md",
    RULE_ROOT / "AGENTS.md",
    RULE_ROOT / "templates" / "标准输出模板.md",
    RULE_ROOT / "skills" / "生成前质检.md",
    RULE_ROOT / "skills" / "镜头可见性与矛盾审计.md",
    RULE_ROOT / "references" / "Seedance规范.md",
    RULE_ROOT / "config" / "limits.json",
)


def _file_record(path: Path) -> dict[str, str]:
    raw = path.read_bytes()
    return {
        "path": path.relative_to(RULE_ROOT).as_posix(),
        "sha256": hashlib.sha256(raw).hexdigest(),
    }


def build_fingerprint(paths: Iterable[Path] = DEFAULT_RULE_FILES) -> dict:
    """Return a stable digest plus the exact files that produced it."""

    records = [_file_record(Path(path)) for path in paths]
    payload = json.dumps(records, ensure_ascii=False, separators=(",", ":"))
    return {
        "fingerprint": hashlib.sha256(payload.encode("utf-8")).hexdigest(),
        "files": records,
    }


if __name__ == "__main__":
    print(json.dumps(build_fingerprint(), ensure_ascii=False, indent=2))
