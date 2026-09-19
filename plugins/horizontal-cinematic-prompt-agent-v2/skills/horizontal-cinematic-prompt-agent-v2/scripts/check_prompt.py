"""Read-only mechanical checks. MECHANICAL_OK is never independent review approval."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import unicodedata
from decimal import Decimal
from pathlib import Path

from audit_fingerprint import build_fingerprint


HEADINGS = ("固定约束", "素材引用", "光影设计", "时间轴")
CONFIG_PATH = Path(__file__).resolve().parents[1] / "config" / "limits.json"
LIMIT_CONFIG = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
LIMITS = {key: int(value) for key, value in LIMIT_CONFIG["character_limits"].items()}
DURATION_MIN = Decimal(str(LIMIT_CONFIG["duration_seconds"]["min"]))
DURATION_MAX = Decimal(str(LIMIT_CONFIG["duration_seconds"]["max"]))
RULE_FINGERPRINT = build_fingerprint()["fingerprint"]
RANGE = re.compile(
    r"^\s*(\d+(?:\.\d+)?)\s*(?:s|秒)?\s*[-—–~～至]\s*"
    r"(\d+(?:\.\d+)?)\s*(?:s|秒)\s*[:：]", re.I | re.M
)
TIME_NUMBER = r"(?:\d+(?:\.\d+)?|[零〇一二两三四五六七八九十百点]+)"
TIME_HINT = re.compile(
    TIME_NUMBER + r"\s*(?:s|秒)?\s*[-—–~～至到]\s*" + TIME_NUMBER + r"\s*(?:s|秒)",
    re.I,
)


def count_visible(text: str) -> int:
    return sum(not c.isspace() and unicodedata.category(c)[0] not in "PZC" for c in text)


def check(raw: bytes, complexity: str, duration: Decimal | None = None,
          allow_user_duration: bool = False) -> dict:
    result = {
        "sha256": hashlib.sha256(raw).hexdigest(),
        "status": "INCOMPLETE",
        "scope": "mechanical_only",
        "complexity": complexity,
        "character_limit": LIMITS[complexity],
        "errors": [],
        "warnings": [],
        "unchecked": [],
        "allow_user_duration": allow_user_duration,
        "rule_fingerprint": RULE_FINGERPRINT,
    }
    errors = result["errors"]
    warnings = result["warnings"]
    unchecked = result["unchecked"]
    if allow_user_duration and duration is None:
        errors.append("允许用户指定时长时必须同时提供明确的 duration")
    try:
        text = raw.decode("utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")
    except UnicodeDecodeError:
        unchecked.append("无法按 UTF-8 读取稿件")
        return result
    found = list(re.finditer(r"^\s*【([^】\n]+)】\s*$", text, re.M))
    names = [m.group(1) for m in found]
    result["headings"] = names
    if names != list(HEADINGS):
        errors.append("正文必须各有一次且按顺序包含：固定约束、素材引用、光影设计、时间轴")
    if "```" in text or "~~~" in text:
        errors.append("受检文件只放提示词正文，不放代码围栏")
    if names == list(HEADINGS):
        if text[:found[0].start()].strip():
            errors.append("四区块之前有非正文内容")
        bodies = {name: text[m.end():found[i + 1].start() if i + 1 < len(found) else len(text)].strip()
                  for i, (name, m) in enumerate(zip(names, found))}
        for name, body in bodies.items():
            if not body:
                errors.append(f"{name}为空")
        count = count_visible(bodies["素材引用"]) + count_visible(bodies["时间轴"])
        result["counted_characters"] = count
        if count > LIMITS[complexity]:
            errors.append(f"素材引用与时间轴共 {count} 字，超过 {LIMITS[complexity]} 字")
        timeline = bodies["时间轴"]
        ranges = list(RANGE.finditer(timeline))
        result["ranges"] = [[m.group(1), m.group(2)] for m in ranges]
        if not ranges:
            unchecked.append("未识别到明确时间范围，不能核对时间轴")
        else:
            # Unrecognised content before the first range may hide an earlier segment.
            if timeline[:ranges[0].start()].strip():
                unchecked.append("首个可识别时间范围之前有内容，需核对时间格式")
            end = Decimal(0)
            for index, match in enumerate(ranges, 1):
                start, stop = Decimal(match.group(1)), Decimal(match.group(2))
                if start != end:
                    errors.append(f"第 {index} 段起点 {start} 秒与前段终点 {end} 秒不接续")
                if stop <= start:
                    errors.append(f"第 {index} 段终点必须大于起点")
                end = stop
            result["end_seconds"] = str(end)
            if not DURATION_MIN <= end <= DURATION_MAX:
                message = f"总时长 {end} 秒不在本插件的 {DURATION_MIN}—{DURATION_MAX} 秒工作范围"
                (warnings if allow_user_duration else errors).append(message)
            if duration is not None and end != duration:
                errors.append(f"时间轴终点 {end} 秒与要求 {duration} 秒不一致")
            for line in timeline.splitlines():
                if re.match(r"^\s*\d", line) and not RANGE.match(line):
                    unchecked.append("存在无法识别的数字起始行，需核对是否遗漏时间段")
                    break
            for hint in TIME_HINT.finditer(timeline):
                if not any(m.start() <= hint.start() and hint.end() <= m.end() for m in ranges):
                    unchecked.append("存在未纳入核对的时间范围（可能有项目符号、括号或中文数字），需统一时间格式")
                    break
    else:
        unchecked.append("区块结构不完整，未执行分区字数和时间轴核对")
    result["status"] = "FAIL" if errors else "INCOMPLETE" if unchecked else "MECHANICAL_OK"
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prompt", type=Path)
    parser.add_argument("--complexity", required=True, choices=LIMITS)
    parser.add_argument("--duration", type=Decimal)
    parser.add_argument("--allow-user-duration", action="store_true",
                        help="允许用户明确指定 4—15 秒范围外时长；风险保留在 warnings")
    args = parser.parse_args()
    try:
        result = check(args.prompt.read_bytes(), args.complexity, args.duration,
                       args.allow_user_duration)
    except OSError as exc:
        result = {"status": "INCOMPLETE", "scope": "mechanical_only", "errors": [],
                  "warnings": [], "rule_fingerprint": RULE_FINGERPRINT,
                  "unchecked": [f"无法读取稿件：{exc}"]}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return {"MECHANICAL_OK": 0, "FAIL": 1, "INCOMPLETE": 2}[result["status"]]


if __name__ == "__main__":
    sys.exit(main())
