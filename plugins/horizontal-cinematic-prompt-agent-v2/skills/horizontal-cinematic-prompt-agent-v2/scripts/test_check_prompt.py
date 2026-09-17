"""Regression tests for observable mechanical checks; no review-approval claims."""

import hashlib
import unittest
from decimal import Decimal

from check_prompt import check, count_visible


PROMPT = """【固定约束】
无字幕，无背景音乐。
【素材引用】
纯文生，无外部素材。
【光影设计】
晨间侧逆光，主体明暗自然。
【时间轴】
0-4s：固定近景，人物抬手。
4-8s：同镜连续，人物放下手。
"""


class Checks(unittest.TestCase):
    def result(self, text=PROMPT, **kwargs):
        return check(text.encode("utf-8"), "simple", **kwargs)

    def test_complete_is_only_mechanical(self):
        result = self.result(duration=Decimal(8))
        self.assertEqual(result["status"], "MECHANICAL_OK")
        self.assertEqual(result["scope"], "mechanical_only")
        self.assertEqual(result["end_seconds"], "8")

    def test_gap_overlap_and_reverse_fail(self):
        for invalid in ("5-8s", "3-8s", "4-3s"):
            with self.subTest(invalid=invalid):
                self.assertEqual(self.result(PROMPT.replace("4-8s", invalid))["status"], "FAIL")

    def test_time_and_length_limits_fail(self):
        self.assertEqual(self.result(duration=Decimal(10))["status"], "FAIL")
        self.assertEqual(self.result(PROMPT.replace("4-8s", "4-16s"))["status"], "FAIL")
        self.assertEqual(self.result(PROMPT + "动" * 2001)["status"], "FAIL")

    def test_missing_duplicate_or_wrong_section_fail(self):
        for invalid in (PROMPT.replace("【光影设计】", "【灯光】"),
                        PROMPT + "【时间轴】\n0-8s：静止。",
                        PROMPT.replace("【固定约束】", "")):
            self.assertEqual(self.result(invalid)["status"], "FAIL")

    def test_unparseable_or_mixed_timeline_never_ok(self):
        self.assertEqual(self.result(PROMPT.replace("0-4s", "零至四秒"))["status"], "FAIL")
        missing = PROMPT.replace("0-4s", "开始").replace("4-8s", "结束")
        self.assertEqual(self.result(missing)["status"], "INCOMPLETE")
        self.assertNotEqual(self.result(PROMPT + "9到10秒：停住。")["status"], "MECHANICAL_OK")

    def test_decimal_and_chinese_time_supported(self):
        candidate = PROMPT.replace("0-4s", "0s—3.5s").replace("4-8s", "3.5至8秒")
        self.assertEqual(self.result(candidate)["status"], "MECHANICAL_OK")

    def test_hidden_time_ranges_are_not_silently_ignored(self):
        for extra in ("- 8-16s：人物离开。", "（8-16s）：人物离开。",
                      "八至十六秒：人物离开。", "继续 8-16s：人物离开。"):
            with self.subTest(extra=extra):
                result = self.result(PROMPT + extra, duration=Decimal(8))
                self.assertEqual(result["status"], "INCOMPLETE")
                self.assertTrue(result["unchecked"])

    def test_content_hash_binds_exact_bytes(self):
        original = self.result()
        edited = self.result(PROMPT.replace("抬手", "转身"))
        self.assertEqual(original["sha256"], hashlib.sha256(PROMPT.encode()).hexdigest())
        self.assertNotEqual(original["sha256"], edited["sha256"])
        crlf = check(PROMPT.replace("\n", "\r\n").encode(), "simple")
        self.assertEqual(original["counted_characters"], crlf["counted_characters"])
        self.assertNotEqual(original["sha256"], crlf["sha256"])

    def test_count_scope_and_invalid_encoding(self):
        self.assertEqual(count_visible("甲，乙。 A1\n"), 4)
        extended = PROMPT.replace("晨间侧逆光", "光" * 2500)
        self.assertEqual(self.result()["counted_characters"], self.result(extended)["counted_characters"])
        self.assertEqual(check(b"\xff", "simple")["status"], "INCOMPLETE")


if __name__ == "__main__":
    unittest.main()
