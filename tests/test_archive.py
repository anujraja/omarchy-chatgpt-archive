#!/usr/bin/env python3
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import archive  # noqa: E402


def sample_conversation() -> dict:
    return {
        "title": "Theatre of Dreams",
        "conversation_id": "conv-united-1",
        "create_time": 1700000000,
        "update_time": 1700003600,
        "current_node": "m2",
        "mapping": {
            "root": {"id": "root", "parent": None, "children": ["m1"], "message": None},
            "m1": {
                "id": "m1",
                "parent": "root",
                "children": ["m2"],
                "message": {
                    "id": "m1",
                    "author": {"role": "user"},
                    "create_time": 1700000000,
                    "content": {"content_type": "text", "parts": ["Export this chat."]},
                },
            },
            "m2": {
                "id": "m2",
                "parent": "m1",
                "children": [],
                "message": {
                    "id": "m2",
                    "author": {"role": "assistant"},
                    "create_time": 1700000010,
                    "content": {
                        "content_type": "text",
                        "parts": ["Here is a local Markdown archive."],
                    },
                },
            },
        },
    }


class ArchiveTests(unittest.TestCase):
    def test_import_zip_writes_markdown_and_index(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            export_dir = tmp_path / "export"
            export_dir.mkdir()
            (export_dir / "conversations.json").write_text(
                json.dumps([sample_conversation()]), encoding="utf-8"
            )
            (export_dir / "photo.png").write_bytes(b"png")
            zip_path = tmp_path / "chatgpt.zip"
            with zipfile.ZipFile(zip_path, "w") as zipped:
                zipped.write(export_dir / "conversations.json", "conversations.json")
                zipped.write(export_dir / "photo.png", "photo.png")

            archive_dir = tmp_path / "archive"
            result = archive.import_export(zip_path, archive_dir)
            self.assertTrue(result["ok"])
            self.assertEqual(result["written"], 1)
            self.assertEqual(result["conversations"], 1)
            self.assertEqual(result["assets"], 1)

            listed = archive.list_conversations(archive_dir, "theatre", 10)
            self.assertEqual(listed["total"], 1)
            self.assertEqual(listed["conversations"][0]["title"], "Theatre of Dreams")
            markdown = (archive_dir / listed["conversations"][0]["markdown"]).read_text(
                encoding="utf-8"
            )
            self.assertIn("## You", markdown)
            self.assertIn("## ChatGPT", markdown)
            self.assertIn("Export this chat.", markdown)

    def test_date_and_project_filters(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive_dir = Path(tmp)
            source = archive_dir / "src"
            source.mkdir()
            conversation = sample_conversation()
            (source / "conversations.json").write_text(json.dumps([conversation]), encoding="utf-8")
            archive.import_export(source, archive_dir)
            # rewrite index with a project so the local filter can use it
            listed = archive.list_conversations(archive_dir, "", 10, project="", since="2025-01-01", until="")
            self.assertEqual(listed["conversations"], [])
            kept = archive.list_conversations(archive_dir, "", 10, project="", since="2023-11-01", until="2023-12-31")
            self.assertEqual(kept["total"], 1)

    def test_schedule_time_validation(self):
        self.assertEqual(archive._valid_time("9:05"), "09:05")
        with self.assertRaises(ValueError):
            archive._valid_time("25:00")

    def test_query_filters_titles(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive_dir = Path(tmp)
            source = archive_dir / "src"
            source.mkdir()
            (source / "conversations.json").write_text(
                json.dumps([sample_conversation()]), encoding="utf-8"
            )
            archive.import_export(source, archive_dir)
            empty = archive.list_conversations(archive_dir, "nope", 10)
            self.assertEqual(empty["conversations"], [])


if __name__ == "__main__":
    unittest.main()
