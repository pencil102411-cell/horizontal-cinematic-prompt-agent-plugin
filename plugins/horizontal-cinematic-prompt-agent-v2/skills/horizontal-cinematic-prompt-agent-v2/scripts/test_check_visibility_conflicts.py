"""Regression tests for conservative visibility-conflict findings."""

import unittest

from check_visibility_conflicts import inspect


def prompt(timeline: str) -> bytes:
    return ("【固定约束】\n无字幕。\n【素材引用】\n纯文生。\n【光影设计】\n侧逆光。\n【时间轴】\n" + timeline + "\n").encode("utf-8")


class VisibilityChecks(unittest.TestCase):
    def test_back_facing_face_detail_requires_review(self):
        result = inspect(prompt("0-4s：女主背对镜头，清晰呈现她的眉毛和面部表情。"))
        self.assertEqual(result["status"], "REVIEW_REQUIRED")
        self.assertIn("VIS-001", [item["id"] for item in result["findings"]])

    def test_medium_front_reflection_requires_review(self):
        result = inspect(prompt("0-4s：双人正面中近景，看到男主眼中映出女主的面部表情。"))
        self.assertEqual(result["status"], "REVIEW_REQUIRED")
        self.assertIn("VIS-002", [item["id"] for item in result["findings"]])

    def test_user_wording_with_reflection_after_subject_requires_review(self):
        result = inspect(prompt("0-4s：双人正面中近景，看到男主的眼神里的女主表情的反光。"))
        self.assertEqual(result["status"], "REVIEW_REQUIRED")
        self.assertIn("VIS-002", [item["id"] for item in result["findings"]])

    def test_eye_sees_another_face_wording_requires_review(self):
        result = inspect(prompt("0-4s：双人正面中近景，男主眼内看到女主的表情。"))
        self.assertEqual(result["status"], "REVIEW_REQUIRED")
        self.assertIn("VIS-002", [item["id"] for item in result["findings"]])

    def test_fixed_shot_cut_requires_review(self):
        result = inspect(prompt("0-4s：固定机位同镜连续，随后切到眼部特写。"))
        self.assertEqual(result["status"], "REVIEW_REQUIRED")
        self.assertIn("VIS-003", [item["id"] for item in result["findings"]])

    def test_explicit_turn_can_resolve_back_to_face_transition(self):
        result = inspect(prompt("0-4s：女主背对镜头，随后回头露出正脸和克制的表情。"))
        self.assertEqual(result["status"], "NO_AUTOMATIC_FINDING")

    def test_clean_shot_has_no_automatic_finding_but_is_not_approval(self):
        result = inspect(prompt("0-4s：中近景，男主抬手挡住来光，保持侧脸。"))
        self.assertEqual(result["status"], "NO_AUTOMATIC_FINDING")
        self.assertEqual(result["scope"], "lexical_visibility_only")

    def test_invalid_encoding_is_incomplete(self):
        result = inspect(b"\xff")
        self.assertEqual(result["status"], "INCOMPLETE")
        self.assertTrue(result["unchecked"])

    def test_missing_timeline_is_incomplete_not_no_finding(self):
        result = inspect("【固定约束】\n无字幕。\n".encode("utf-8"))
        self.assertEqual(result["status"], "INCOMPLETE")
        self.assertTrue(result["unchecked"])


if __name__ == "__main__":
    unittest.main()
