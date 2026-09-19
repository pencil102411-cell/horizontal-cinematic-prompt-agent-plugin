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

from audit_fingerprint import build_fingerprint


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
# A temporal connector such as “随后” does not itself explain how a back-facing
# subject becomes face-visible.  Only orientation-changing wording can lift
# VIS-001, and only when it occurs between the back-facing and detail wording.
TRANSITION = re.compile(r"转身|转过身|回头|转过脸|转头|扭头|转过来|转向镜头|转向摄影机|露出正脸|面对镜头")

_TIME_RANGE = re.compile(
    r"(?P<start>\d+(?:\.\d+)?)\s*(?:s|秒)?\s*"
    r"(?:-|–|—|~|～|至)\s*"
    r"(?P<end>\d+(?:\.\d+)?)\s*(?:s|秒)",
    re.IGNORECASE,
)


def _time_range(line: str) -> tuple[str, str] | None:
    """Return a leading time range used as a logical timeline boundary.

    A continuation line normally has no range and stays in the current window.
    Repeated ranges are kept together so a writer can wrap one time segment over
    several labelled lines, while a changed range starts a new segment.
    """

    prefix = re.sub(r"^\s*(?:[-*•]\s*)?(?:\*\*)?(?:【\s*)?", "", line)
    match = _TIME_RANGE.match(prefix)
    if not match:
        return None
    return match.group("start"), match.group("end")


def _timeline_entries(text: str, timeline_match: re.Match[str] | None) -> list[tuple[int, str]]:
    """Return timeline lines with their original source line numbers."""

    lines = text.splitlines()
    if timeline_match is None:
        return list(enumerate(lines, 1))

    # The header regex is line anchored, so counting preceding newlines gives
    # the zero-based index without losing source line numbers during grouping.
    header_index = text[: timeline_match.start()].count("\n")
    return [(line_number, line) for line_number, line in enumerate(lines[header_index + 1 :], header_index + 2)]


def _timeline_windows(entries: list[tuple[int, str]]) -> list[list[tuple[int, str]]]:
    """Group adjacent timeline lines into conservative logical windows.

    Blank lines end a window.  A new leading time range ends the previous
    window unless it repeats that window's range.  This lets lexical checks see
    wrapped descriptions while preventing unrelated timestamped shots from
    being merged.
    """

    windows: list[list[tuple[int, str]]] = []
    current: list[tuple[int, str]] = []
    current_range: tuple[str, str] | None = None

    def flush() -> None:
        nonlocal current, current_range
        if current:
            windows.append(current)
        current = []
        current_range = None

    for line_number, line in entries:
        if not line.strip():
            flush()
            continue

        line_range = _time_range(line)
        if current and line_range is not None:
            if current_range is None or line_range != current_range:
                flush()
        if not current:
            current_range = line_range
        current.append((line_number, line))

    flush()
    return windows


def _window_text(window: list[tuple[int, str]]) -> str:
    return "\n".join(line for _, line in window)


def _window_evidence(window: list[tuple[int, str]]) -> str:
    return "；".join(f"时间轴第 {line_number} 行：{line}" for line_number, line in window)


def _back_and_face_conflict(window_text: str) -> bool:
    """Check ordering so only a real orientation change can resolve VIS-001."""

    back_matches = list(BACK.finditer(window_text))
    face_matches = list(FACE_DETAIL.finditer(window_text))
    transitions = list(TRANSITION.finditer(window_text))
    for back in back_matches:
        for detail in face_matches:
            if detail.start() < back.end():
                continue
            if not any(
                back.end() <= transition.start() and transition.end() <= detail.start()
                for transition in transitions
            ):
                return True
    return False


def _finding(code: str, evidence: str, impact: str) -> dict:
    return {"id": code, "evidence": evidence.strip(), "impact": impact}


def inspect(raw: bytes) -> dict:
    result = {
        "sha256": hashlib.sha256(raw).hexdigest(),
        "status": "INCOMPLETE",
        "scope": "lexical_visibility_only",
        "findings": [],
        "unchecked": [],
        "rule_fingerprint": build_fingerprint()["fingerprint"],
    }
    try:
        text = raw.decode("utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")
    except UnicodeDecodeError:
        result["unchecked"].append("无法按 UTF-8 读取稿件")
        return result

    timeline_match = re.search(r"^\s*【时间轴】\s*$", text, re.M)
    if not timeline_match:
        result["unchecked"].append("未找到时间轴区块，无法按时间段定位疑点")

    entries = _timeline_entries(text, timeline_match)

    for window in _timeline_windows(entries):
        window_text = _window_text(window)
        evidence = _window_evidence(window)
        if _back_and_face_conflict(window_text):
            result["findings"].append(_finding(
                "VIS-001", evidence,
                "背向镜头却要求读取同一主体的面部细节，模型可能把人物转向镜头或改变机位。"))
        if MEDIUM_FRONT.search(window_text) and REFLECTION.search(window_text):
            result["findings"].append(_finding(
                "VIS-002", evidence,
                "双人正面中近景同时要求眼内呈现另一人物面部反光，细节尺度可能迫使模型切到眼部特写。"))
        if NO_CUT.search(window_text) and CUT.search(window_text):
            result["findings"].append(_finding(
                "VIS-003", evidence,
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
                  "rule_fingerprint": build_fingerprint()["fingerprint"],
                  "findings": [], "unchecked": [f"无法读取稿件：{exc}"]}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["status"] == "NO_AUTOMATIC_FINDING" else 1


if __name__ == "__main__":
    sys.exit(main())
