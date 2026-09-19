"""Run the deterministic prompt checks for one audit bundle in one process."""

from __future__ import annotations

import argparse
import json
import sys
from decimal import Decimal
from pathlib import Path

from check_prompt import LIMITS, check
from check_visibility_conflicts import inspect as inspect_visibility


def batch_exit_code(results: list[dict]) -> int:
    """Return the batch contract code while retaining every item detail."""
    if not results:
        return 2

    statuses = []
    for item in results:
        statuses.append(item.get("status"))
        visibility = item.get("visibility")
        if isinstance(visibility, dict):
            statuses.append(visibility.get("status"))

    if any(status in {"FAIL", "REVIEW_REQUIRED"} for status in statuses):
        return 1
    if any(status == "INCOMPLETE" for status in statuses):
        return 2
    if all(item.get("status") == "MECHANICAL_OK"
           and isinstance(item.get("visibility"), dict)
           and item["visibility"].get("status") == "NO_AUTOMATIC_FINDING"
           for item in results):
        return 0
    return 2


def load_manifest(path: Path) -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError("审核清单必须是 JSON 数组")
    items = []
    for index, item in enumerate(data, 1):
        if not isinstance(item, dict):
            items.append({"id": str(index), "path": None,
                          "_manifest_error": f"第 {index} 项必须是对象"})
            continue
        item = dict(item)
        item.setdefault("id", str(index))
        if "path" not in item:
            item["path"] = None
            item["_manifest_error"] = f"第 {index} 项缺少 path"
        items.append(item)
    return items


def run(manifest: Path) -> list[dict]:
    items = load_manifest(manifest)
    if not items:
        raise ValueError("审核清单不能为空；没有候选稿时不能声称机械检查完成")
    results = []
    for index, item in enumerate(items, 1):
        raw_path = item.get("path")
        result = {"id": item.get("id", str(index)), "path": str(raw_path) if raw_path is not None else None,
                  "sha256": None, "scope": "mechanical_only",
                  "errors": [item["_manifest_error"]] if item.get("_manifest_error") else [],
                  "warnings": [],
                  "unchecked": []}
        try:
            if not isinstance(raw_path, (str, Path)) or not str(raw_path).strip():
                raise ValueError("path 必须是非空字符串")
            path = Path(raw_path)
            if not path.is_absolute():
                path = manifest.parent / path
            complexity = item.get("complexity", "simple")
            if not isinstance(complexity, str) or complexity not in LIMITS:
                raise ValueError("complexity 必须是 simple / complex / maximal")
            duration = item.get("duration")
            allow_user_duration = item.get("allow_user_duration", False)
            if not isinstance(allow_user_duration, bool):
                raise ValueError("allow_user_duration 必须是布尔值")
            result["path"] = str(path)
            raw = path.read_bytes()
            result.update(check(
                raw,
                complexity,
                duration=Decimal(str(duration)) if duration is not None else None,
                allow_user_duration=allow_user_duration,
            ))
            result["visibility"] = inspect_visibility(raw)
        except (OSError, ValueError, TypeError, ArithmeticError) as exc:
            result.update({"status": "INCOMPLETE", "errors": [f"无法读取或解析稿件：{exc}"],
                           "unchecked": ["未获得候选稿字节，无法计算 SHA-256"],
                           "visibility": {"status": "INCOMPLETE", "findings": [],
                                          "unchecked": ["未获得候选稿字节，无法执行可见性词面检查"]}})
        results.append(result)
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "manifest", type=Path,
        help="包含 id/path/complexity/duration/allow_user_duration 的 JSON 数组",
    )
    args = parser.parse_args()
    try:
        results = run(args.manifest)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(json.dumps({"status": "INCOMPLETE", "errors": [str(exc)]}, ensure_ascii=False, indent=2))
        return 2
    print(json.dumps(results, ensure_ascii=False, indent=2))
    return batch_exit_code(results)


if __name__ == "__main__":
    sys.exit(main())
