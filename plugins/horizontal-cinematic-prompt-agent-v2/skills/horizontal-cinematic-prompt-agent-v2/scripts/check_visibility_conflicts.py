"""Conservative lexical checks for shot visibility conflicts.

This script only raises review findings. It never grants semantic approval.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


BACK = re.compile(r"背对镜头|背向镜头|背影|背身|背对摄影机")
FACE_DETAIL = re.compile(r"面部表情|面部细节|神情|眉毛|眼神|眼睫|瞳孔|眼睛|面容|嘴角|唇形|泪珠|眼泪")
REFLECTION = re.compile(
    r"(?:眼神|眼中|瞳孔|眼睛).{0,16}(?:反光|映出|倒影|反射).{0,24}(?:女主|男主|人物|脸|面部|表情)"
    r"|(?:眼神|眼中|瞳孔|眼睛).{0,30}(?:女主|男主|人物).{0,16}(?:反光|映出|倒影|反射)"
    r"|(?:眼内|眼中|瞳孔|眼睛).{0,12}(?:看到|看见|呈现|出现).{0,20}(?:女主|男主|另一人|人物|脸|面部|表情)"
)
MEDIUM_FRONT = re.compile(r"(?:双人|二人).{0,12}(?:正面).{0,12}(?:中近景|中景|近景)|(?:中近景|中景|近景).{0,12}(?:双人|二人).{0,12}(?:正面)")
NO_CUT = re.compile(r"(?:固定机位|固定镜头|同镜连续|不切镜|不切换|一镜到底)")
CUT = re.compile(r"切至|切到|切换至|转为特写|变成特写|跳切|另一个镜头")
TRANSITION = re.compile(r"随后|然后|转身|回头|转过脸|转头|露出正脸|面对镜头")


def _finding(code: str, evidence: str, impact: str) -> dict:
    return {"id": code, "evidence": evidence.strip(), "impact": impact}


def inspect(raw: bytes) -> dict:
    result = {
        "sha256": hashlib.sha256(raw).hexdigest(),
        "status": "INCOMPLETE",
        "scope": "lexical_visibility_only",
        "findings": [],
        "unchecked": [],
    }
    try:
        text = raw.decode("utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")
    except UnicodeDecodeError:
        result["unchecked"].append("无法按 UTF-8 读取稿件")
        return result

    timeline_match = re.search(r"^\s*【时间轴】\s*$", text, re.M)
    timeline = text[timeline_match.end():] if timeline_match else text
    if not timeline_match:
        result["unchecked"].append("未找到时间轴区块，无法按时间段定位疑点")

    for line_number, line in enumerate(timeline.splitlines(), 1):
        if not line.strip():
            continue
        if BACK.search(line) and FACE_DETAIL.search(line) and not TRANSITION.search(line):
            result["findings"].append(_finding(
                "VIS-001", f"时间轴第 {line_number} 行：{line}",
                "背向镜头却要求读取同一主体的面部细节，模型可能把人物转向镜头或改变机位。"))
        if MEDIUM_FRONT.search(line) and REFLECTION.search(line):
            result["findings"].append(_finding(
                "VIS-002", f"时间轴第 {line_number} 行：{line}",
                "双人正面中近景同时要求眼内呈现另一人物面部反光，细节尺度可能迫使模型切到眼部特写。"))
        if NO_CUT.search(line) and CUT.search(line):
            result["findings"].append(_finding(
                "VIS-003", f"时间轴第 {line_number} 行：{line}",
                "连续固定视点与切镜/变为特写同时出现，镜头连续性和可见范围互相冲突。"))

    # Keep IDs stable and avoid repeated findings when a line matches aliases.
    unique = []
    seen = set()
    for finding in result["findings"]:
        key = (finding["id"], finding["evidence"])
        if key not in seen:
            seen.add(key)
            unique.append(finding)
    result["findings"] = unique
    if result["findings"]:
        result["status"] = "REVIEW_REQUIRED"
    elif result["unchecked"]:
        result["status"] = "INCOMPLETE"
    else:
        result["status"] = "NO_AUTOMATIC_FINDING"
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prompt", type=Path)
    args = parser.parse_args()
    try:
        result = inspect(args.prompt.read_bytes())
    except OSError as exc:
        result = {"sha256": None, "status": "INCOMPLETE", "scope": "lexical_visibility_only",
                  "findings": [], "unchecked": [f"无法读取稿件：{exc}"]}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["status"] == "NO_AUTOMATIC_FINDING" else 1


if __name__ == "__main__":
    sys.exit(main())
