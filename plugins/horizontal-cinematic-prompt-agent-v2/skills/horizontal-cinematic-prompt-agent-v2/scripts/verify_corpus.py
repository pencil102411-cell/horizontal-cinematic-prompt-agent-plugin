"""Verify the packaged screenplay corpus and canonical scene hashes."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


DEFAULT_MANIFEST = (
    Path(__file__).resolve().parents[1]
    / "references"
    / "风起玲珑骨"
    / "剧本"
    / "corpus-manifest.json"
)
PDF_PAGE = re.compile(r"^<<<PDF_PAGE:\d+>>>$")


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest().upper()


def _hash_matches(expected: Any, actual: str) -> bool:
    """Compare hexadecimal hashes without making case part of the contract."""

    return isinstance(expected, str) and expected.upper() == actual.upper()


def _canonical_scene_hash(lines: list[str], start_line: int, end_line: int) -> str:
    selected: list[str] = []
    for line in lines[start_line - 1 : end_line]:
        value = line.strip()
        if value and not PDF_PAGE.fullmatch(value):
            selected.append(value)
    return _sha256("\n".join(selected).encode("utf-8"))


def _result(manifest: Path) -> dict[str, Any]:
    return {
        "status": "PASS",
        "manifest": str(manifest),
        "errors": [],
        "warnings": [],
        "stats": {
            "episodes_checked": 0,
            "episodes_ok": 0,
            "scenes_checked": 0,
            "scenes_ok": 0,
        },
    }


def _issue(result: dict[str, Any], kind: str, message: str) -> None:
    result[kind].append(message)


def _episode_path(corpus_root: Path, value: Any) -> Path:
    if not isinstance(value, str) or not value.strip():
        raise ValueError("episode file 必须是非空字符串")
    relative = Path(value)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"episode file 路径越界：{value}")
    if relative.parts and relative.parts[0].lower() == "episodes":
        return corpus_root / relative
    return corpus_root / "episodes" / relative


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def verify_manifest(manifest: Path | str = DEFAULT_MANIFEST) -> tuple[dict[str, Any], int]:
    """Return a machine-readable result and process-style status code.

    Code 0 means every declared hash and scene range matches. Code 1 means
    readable content disagrees with the manifest. Code 2 means a required file
    or structure could not be read or parsed.
    """

    manifest_path = Path(manifest).resolve()
    result = _result(manifest_path)
    try:
        data = _load_json(manifest_path)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        result["status"] = "ERROR"
        _issue(result, "errors", f"无法读取或解析 manifest：{exc}")
        return result, 2

    if not isinstance(data, dict):
        result["status"] = "ERROR"
        _issue(result, "errors", "manifest 根节点必须是对象")
        return result, 2

    corpus_root = manifest_path.parent
    content_failed = False
    structural_failed = False
    episode_lines: dict[str, list[str]] = {}

    episodes = data.get("episodes")
    if not isinstance(episodes, list):
        result["status"] = "ERROR"
        _issue(result, "errors", "manifest 缺少 episodes 数组")
        return result, 2

    for item in episodes:
        result["stats"]["episodes_checked"] += 1
        if not isinstance(item, dict):
            structural_failed = True
            _issue(result, "errors", "episode 条目必须是对象")
            continue
        try:
            path = _episode_path(corpus_root, item.get("file"))
            raw = path.read_bytes()
            text = raw.decode("utf-8")
            lines = text.splitlines()
            episode_lines[str(item["file"])] = lines
        except (KeyError, OSError, UnicodeError, ValueError) as exc:
            structural_failed = True
            _issue(result, "errors", f"无法读取 episode {item.get('file')!r}：{exc}")
            continue

        actual = {
            "bytes": len(raw),
            "sha256": _sha256(raw),
            "chars": len(text),
            "lines": len(lines),
        }
        mismatches = []
        for key, value in actual.items():
            if key not in item:
                continue
            expected = item[key]
            matches = _hash_matches(expected, value) if key == "sha256" else expected == value
            if not matches:
                mismatches.append(f"{key} 期望 {expected!r}，实际 {value!r}")
        if mismatches:
            content_failed = True
            for mismatch in mismatches:
                _issue(result, "errors", f"episode {item.get('file')!r}：{mismatch}")
        else:
            result["stats"]["episodes_ok"] += 1

    scene_index = data.get("scene_index")
    if not isinstance(scene_index, dict) or not isinstance(scene_index.get("file"), str):
        result["status"] = "ERROR"
        _issue(result, "errors", "manifest 缺少 scene_index.file")
        return result, 2

    index_path = corpus_root / scene_index["file"]
    try:
        index_raw = index_path.read_bytes()
        index_text = index_raw.decode("utf-8")
    except (OSError, UnicodeError) as exc:
        result["status"] = "ERROR"
        _issue(result, "errors", f"无法读取 scene index：{exc}")
        return result, 2

    expected_index_hash = scene_index.get("sha256")
    if isinstance(expected_index_hash, str) and _sha256(index_raw) != expected_index_hash.upper():
        content_failed = True
        _issue(result, "errors", "scene index sha256 与 manifest 不一致")

    for line_number, raw_line in enumerate(index_text.splitlines(), 1):
        if not raw_line.strip():
            continue
        result["stats"]["scenes_checked"] += 1
        try:
            scene = json.loads(raw_line)
            if not isinstance(scene, dict):
                raise ValueError("场次记录必须是对象")
            source_file = scene["source_file"]
            start_line = scene["start_line"]
            end_line = scene["end_line"]
            expected_hash = scene["text_sha256"]
            if not isinstance(source_file, str) or not isinstance(start_line, int) or not isinstance(end_line, int):
                raise ValueError("source_file/start_line/end_line 类型不正确")
            if not isinstance(expected_hash, str):
                raise ValueError("text_sha256 必须是字符串")
            if source_file not in episode_lines:
                path = _episode_path(corpus_root, source_file)
                episode_lines[source_file] = path.read_text(encoding="utf-8").splitlines()
            lines = episode_lines[source_file]
            if start_line < 1 or end_line < start_line or end_line > len(lines):
                content_failed = True
                _issue(
                    result,
                    "errors",
                    f"场次 {scene.get('scene_id', line_number)!r}："
                    f"行范围 {start_line}-{end_line} 超出正文长度 {len(lines)}",
                )
                continue
            actual_hash = _canonical_scene_hash(lines, start_line, end_line)
            if actual_hash != expected_hash.upper():
                content_failed = True
                _issue(result, "errors", f"场次 {scene.get('scene_id', line_number)!r}：text_sha256 不一致")
            else:
                result["stats"]["scenes_ok"] += 1
        except (KeyError, OSError, UnicodeError, ValueError, json.JSONDecodeError) as exc:
            structural_failed = True
            _issue(result, "errors", f"scene-index 第 {line_number} 行无效：{exc}")

    if structural_failed:
        result["status"] = "ERROR"
        return result, 2
    if content_failed:
        result["status"] = "FAIL"
        return result, 1
    return result, 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    args = parser.parse_args()
    result, code = verify_manifest(args.manifest)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return code


if __name__ == "__main__":
    sys.exit(main())
