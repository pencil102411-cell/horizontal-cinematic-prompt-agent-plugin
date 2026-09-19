"""Tests for the one-process mechanical audit bundle runner."""

import json
import tempfile
import unittest
from pathlib import Path

from check_prompt_batch import run


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


class BatchChecks(unittest.TestCase):
    def test_bundle_returns_each_id_and_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first, second = root / "a.txt", root / "b.txt"
            first.write_text(PROMPT, encoding="utf-8")
            second.write_text(PROMPT.replace("抬手", "转身"), encoding="utf-8")
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps([
                {"id": "a", "path": str(first), "complexity": "simple", "duration": 8},
                {"id": "b", "path": str(second), "complexity": "simple", "duration": 8},
            ], ensure_ascii=False), encoding="utf-8")
            results = run(manifest)
        self.assertEqual([item["id"] for item in results], ["a", "b"])
        self.assertEqual([item["status"] for item in results], ["MECHANICAL_OK", "MECHANICAL_OK"])
        self.assertNotEqual(results[0]["sha256"], results[1]["sha256"])
        self.assertEqual(results[0]["visibility"]["status"], "NO_AUTOMATIC_FINDING")

    def test_unreadable_item_is_incomplete_without_stopping_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            good = root / "good.txt"
            good.write_text(PROMPT, encoding="utf-8")
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps([
                {"id": "good", "path": str(good), "duration": 8},
                {"id": "missing", "path": str(root / "missing.txt"), "duration": 8},
            ]), encoding="utf-8")
            results = run(manifest)
        self.assertEqual(results[0]["status"], "MECHANICAL_OK")
        self.assertEqual(results[1]["status"], "INCOMPLETE")
        self.assertIsNone(results[1]["sha256"])
        self.assertTrue(results[1]["errors"])
        self.assertTrue(results[1]["unchecked"])
        self.assertEqual(results[1]["visibility"]["status"], "INCOMPLETE")

    def test_empty_bundle_is_incomplete(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "manifest.json"
            manifest.write_text("[]", encoding="utf-8")
            with self.assertRaises(ValueError):
                run(manifest)

    def test_bad_item_does_not_abort_following_items(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            good = root / "good.txt"
            good.write_text(PROMPT, encoding="utf-8")
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps([
                {"id": "bad", "path": None},
                {"id": "good", "path": str(good), "duration": 8},
            ]), encoding="utf-8")
            results = run(manifest)
        self.assertEqual(results[0]["status"], "INCOMPLETE")
        self.assertEqual(results[1]["status"], "MECHANICAL_OK")

    def test_bad_duration_does_not_abort_following_items(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            good = root / "good.txt"
            good.write_text(PROMPT, encoding="utf-8")
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps([
                {"id": "bad", "path": str(good), "duration": ""},
                {"id": "good", "path": str(good), "duration": 8},
            ]), encoding="utf-8")
            results = run(manifest)
        self.assertEqual(results[0]["status"], "INCOMPLETE")
        self.assertEqual(results[1]["status"], "MECHANICAL_OK")

    def test_relative_paths_are_resolved_from_manifest_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "审查包").mkdir()
            (root / "审查包" / "shot.txt").write_text(PROMPT, encoding="utf-8")
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps([{"id": "shot", "path": "审查包/shot.txt", "duration": 8}], ensure_ascii=False), encoding="utf-8")
            results = run(manifest)
        self.assertEqual(results[0]["status"], "MECHANICAL_OK")

    def test_malformed_complexity_does_not_abort_following_items(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            good = root / "good.txt"
            good.write_text(PROMPT, encoding="utf-8")
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps([
                {"id": "bad", "path": str(good), "complexity": []},
                {"id": "good", "path": str(good), "duration": 8},
            ]), encoding="utf-8")
            results = run(manifest)
        self.assertEqual(results[0]["status"], "INCOMPLETE")
        self.assertTrue(results[0]["errors"])
        self.assertEqual(results[1]["status"], "MECHANICAL_OK")

    def test_non_object_item_does_not_abort_following_items(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            good = root / "good.txt"
            good.write_text(PROMPT, encoding="utf-8")
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps([
                "bad item",
                {"id": "good", "path": str(good), "duration": 8},
            ]), encoding="utf-8")
            results = run(manifest)
        self.assertEqual(results[0]["status"], "INCOMPLETE")
        self.assertTrue(results[0]["errors"])
        self.assertEqual(results[1]["status"], "MECHANICAL_OK")


if __name__ == "__main__":
    unittest.main()
