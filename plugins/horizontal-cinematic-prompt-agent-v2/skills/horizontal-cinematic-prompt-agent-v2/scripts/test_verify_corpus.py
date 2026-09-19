"""Tests for the read-only corpus verifier."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from verify_corpus import DEFAULT_MANIFEST, verify_manifest


def _text_sha256(lines: list[str], start: int, end: int) -> str:
    kept = []
    for line in lines[start - 1 : end]:
        line = line.strip()
        if line and not (line.startswith("<<<PDF_PAGE:") and line.endswith(">>>")):
            kept.append(line)
    return hashlib.sha256("\n".join(kept).encode("utf-8")).hexdigest()


class VerifyCorpusTests(unittest.TestCase):
    def test_default_corpus_passes(self) -> None:
        result, code = verify_manifest(DEFAULT_MANIFEST)
        self.assertEqual(code, 0)
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["stats"]["episodes_checked"], 24)
        self.assertEqual(result["stats"]["scenes_checked"], 451)

    def _fixture(self) -> tuple[tempfile.TemporaryDirectory[str], Path, Path, dict]:
        temp = tempfile.TemporaryDirectory()
        root = Path(temp.name)
        (root / "episodes").mkdir()
        lines = ["<<<PDF_PAGE:001>>>", "  first line  ", "", " <<<PDF_PAGE:2>>> ", " second line "]
        episode_bytes = ("\n".join(lines) + "\n").encode("utf-8")
        episode_path = root / "episodes" / "episode-01.txt"
        episode_path.write_bytes(episode_bytes)
        scene = {
            "schema_version": "1.0",
            "corpus_version": "fixture",
            "episode": 1,
            "scene_id": "E01-S001",
            "scene_order": 1,
            "scene_label": "1",
            "heading": "fixture",
            "source_file": "episode-01.txt",
            "start_line": 1,
            "end_line": len(lines),
            "text_sha256": _text_sha256(lines, 1, len(lines)),
            "previous_scene_id": None,
            "next_scene_id": None,
        }
        scene_path = root / "scene-index.jsonl"
        scene_path.write_text(json.dumps(scene, ensure_ascii=False) + "\n", encoding="utf-8")
        manifest = {
            "project": "fixture",
            "episodes": [
                {
                    "episode": 1,
                    "file": "episode-01.txt",
                    "bytes": len(episode_bytes),
                    "sha256": hashlib.sha256(episode_bytes).hexdigest(),
                    "lines": len(lines),
                }
            ],
            "scene_index": {
                "file": "scene-index.jsonl",
                "sha256": hashlib.sha256(scene_path.read_bytes()).hexdigest(),
            },
        }
        manifest_path = root / "corpus-manifest.json"
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
        return temp, manifest_path, scene_path, scene

    def test_fixture_manifest_and_normalized_text_hash_pass(self) -> None:
        temp, manifest_path, _scene_path, _scene = self._fixture()
        self.addCleanup(temp.cleanup)
        result, code = verify_manifest(manifest_path)
        self.assertEqual(code, 0)
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["stats"]["scenes_checked"], 1)

    def test_bad_line_range_is_content_failure(self) -> None:
        temp, manifest_path, scene_path, scene = self._fixture()
        self.addCleanup(temp.cleanup)
        scene["end_line"] = 99
        scene_path.write_text(json.dumps(scene) + "\n", encoding="utf-8")
        result, code = verify_manifest(manifest_path)
        self.assertEqual(code, 1)
        self.assertEqual(result["status"], "FAIL")

    def test_missing_file_is_read_failure(self) -> None:
        temp, manifest_path, _scene_path, _scene = self._fixture()
        self.addCleanup(temp.cleanup)
        (Path(temp.name) / "episodes" / "episode-01.txt").unlink()
        result, code = verify_manifest(manifest_path)
        self.assertEqual(code, 2)
        self.assertEqual(result["status"], "ERROR")

    def test_wrong_episode_hash_is_content_failure(self) -> None:
        temp, manifest_path, _scene_path, _scene = self._fixture()
        self.addCleanup(temp.cleanup)
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["episodes"][0]["sha256"] = "0" * 64
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        result, code = verify_manifest(manifest_path)
        self.assertEqual(code, 1)
        self.assertEqual(result["status"], "FAIL")


if __name__ == "__main__":
    unittest.main()
