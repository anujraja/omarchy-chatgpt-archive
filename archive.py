#!/usr/bin/env python3
"""Import official ChatGPT data-export ZIPs into a local Markdown archive.

This plugin does not talk to ChatGPT. It reads the ZIP (or unpacked folder)
from Settings → Data controls → Export data, then writes JSON + Markdown
under the archive directory. Optional live incremental export is delegated
to `chatgpt-download-engine` when that CLI is already installed.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path

import chatgpt_live

INDEX_NAME = "index.json"
CONVERSATIONS_DIR = "conversations"
ASSETS_DIR = "assets"
DEFAULT_ARCHIVE = Path.home() / ".local" / "share" / "chatgpt-archive"


def emit(payload: dict) -> int:
    json.dump(payload, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0 if payload.get("ok", True) else 1


def iso_from(value) -> str:
    if value in (None, ""):
        return ""
    try:
        stamp = float(value)
        return datetime.fromtimestamp(stamp, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    except (TypeError, ValueError, OSError, OverflowError):
        return str(value)


def slug(value: str, fallback: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", (value or "").strip())
    cleaned = cleaned.strip("-._")[:80]
    return cleaned or fallback


def part_text(part) -> str:
    if part is None:
        return ""
    if isinstance(part, str):
        return part
    if not isinstance(part, dict):
        return str(part)
    content_type = str(part.get("content_type") or "")
    if content_type in {"image_asset_pointer", "audio_asset_pointer"} or part.get("asset_pointer"):
        pointer = str(part.get("asset_pointer") or part.get("filename") or "attachment")
        return f"\n[attachment: {pointer}]\n"
    for key in ("text", "value", "body"):
        if isinstance(part.get(key), str):
            return part[key]
    inner = part.get("parts")
    if isinstance(inner, list):
        return "\n".join(part_text(item) for item in inner)
    return ""


def message_text(message: dict) -> str:
    content = message.get("content") or {}
    if isinstance(content, str):
        return content
    if not isinstance(content, dict):
        return ""
    parts = content.get("parts")
    if isinstance(parts, list):
        return "\n".join(part_text(part) for part in parts).strip()
    if isinstance(content.get("text"), str):
        return content["text"].strip()
    if isinstance(content.get("result"), str):
        return content["result"].strip()
    return ""


def linearize(conversation: dict) -> list[dict]:
    mapping = conversation.get("mapping") or {}
    if not isinstance(mapping, dict):
        return []

    node_id = conversation.get("current_node")
    if not node_id:
        leaves = [key for key, node in mapping.items() if not (node or {}).get("children")]
        node_id = leaves[-1] if leaves else None

    chain = []
    seen = set()
    while node_id and node_id not in seen:
        seen.add(node_id)
        node = mapping.get(node_id) or {}
        chain.append(node)
        node_id = node.get("parent")
    chain.reverse()

    messages = []
    for node in chain:
        message = node.get("message")
        if not isinstance(message, dict):
            continue
        role = str((message.get("author") or {}).get("role") or "unknown")
        if role in {"system", "developer"}:
            continue
        text = message_text(message)
        if not text:
            continue
        messages.append(
            {
                "id": str(message.get("id") or node.get("id") or ""),
                "role": role,
                "created": iso_from(message.get("create_time")),
                "text": text,
            }
        )
    return messages


def load_conversations(source: Path) -> list[dict]:
    payload = json.loads(source.read_text(encoding="utf-8"))
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if isinstance(payload, dict):
        if isinstance(payload.get("conversations"), list):
            return [item for item in payload["conversations"] if isinstance(item, dict)]
        if "mapping" in payload:
            return [payload]
    return []


def conversation_files(root: Path) -> list[Path]:
    files = []
    for path in root.rglob("*.json"):
        name = path.name.lower()
        if name == "conversations.json" or name.startswith("conversations-"):
            files.append(path)
    return sorted(files)


def markdown_for(title: str, conv_id: str, created: str, updated: str, messages: list[dict]) -> str:
    lines = [
        "---",
        f"id: {conv_id}",
        f"title: {json.dumps(title, ensure_ascii=False)}",
        f"created: {created}",
        f"updated: {updated}",
        "source: chatgpt-official-export",
        "---",
        "",
        f"# {title}",
        "",
    ]
    labels = {
        "user": "You",
        "assistant": "ChatGPT",
        "tool": "Tool",
        "unknown": "Message",
    }
    for message in messages:
        stamp = message.get("created") or ""
        heading = labels.get(message["role"], message["role"].title())
        suffix = f" · {stamp}" if stamp else ""
        lines.append(f"## {heading}{suffix}")
        lines.append("")
        lines.append(message["text"].rstrip())
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def copy_assets(src_root: Path, dest: Path) -> int:
    dest.mkdir(parents=True, exist_ok=True)
    copied = 0
    skip_names = {"conversations.json", "index.html", "chat.html"}
    for path in src_root.rglob("*"):
        if not path.is_file():
            continue
        name = path.name.lower()
        if name.endswith(".json") and (name == "conversations.json" or name.startswith("conversations-")):
            continue
        if name in skip_names:
            continue
        relative = path.relative_to(src_root)
        target = dest / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        copied += 1
    return copied


def read_index(archive: Path) -> dict:
    index_path = archive / INDEX_NAME
    if not index_path.is_file():
        return {
            "ok": True,
            "version": 1,
            "archive": str(archive),
            "imported_at": "",
            "conversations": [],
        }
    try:
        data = json.loads(index_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        data = {}
    data.setdefault("ok", True)
    data.setdefault("version", 1)
    data.setdefault("archive", str(archive))
    data.setdefault("imported_at", "")
    data.setdefault("conversations", [])
    return data


def write_index(archive: Path, conversations: list[dict], imported_at: str) -> None:
    payload = {
        "version": 1,
        "archive": str(archive),
        "imported_at": imported_at,
        "conversations": sorted(conversations, key=lambda item: item.get("updated") or "", reverse=True),
    }
    (archive / INDEX_NAME).write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def live_engine_path() -> str:
    return shutil.which("chatgpt-download-engine") or ""


def unpack_source(path: Path) -> tuple[Path, tempfile.TemporaryDirectory | None]:
    if path.is_dir():
        return path, None
    if path.is_file() and zipfile.is_zipfile(path):
        temp = tempfile.TemporaryDirectory(prefix="chatgpt-archive-")
        with zipfile.ZipFile(path) as archive:
            archive.extractall(temp.name)
        return Path(temp.name), temp
    raise FileNotFoundError(f"not a ChatGPT export ZIP or folder: {path}")


def ingest_conversation(conversation: dict, archive: Path, existing: dict, project: str = "") -> bool:
    conv_id = str(
        conversation.get("conversation_id")
        or conversation.get("id")
        or conversation.get("uuid")
        or ""
    )
    if not conv_id:
        return False
    archive.mkdir(parents=True, exist_ok=True)
    (archive / CONVERSATIONS_DIR).mkdir(exist_ok=True)
    title = str(conversation.get("title") or "Untitled").strip() or "Untitled"
    created = iso_from(conversation.get("create_time"))
    updated = iso_from(conversation.get("update_time") or conversation.get("create_time"))
    messages = linearize(conversation)
    stem = slug(title, conv_id[:12]) + "-" + slug(conv_id, "chat")[:12]
    md_path = archive / CONVERSATIONS_DIR / f"{stem}.md"
    json_path = archive / CONVERSATIONS_DIR / f"{stem}.json"
    record = {
        "id": conv_id,
        "title": title,
        "created": created,
        "updated": updated,
        "messages": len(messages),
        "project": project,
        "markdown": str(md_path.relative_to(archive)),
        "json": str(json_path.relative_to(archive)),
    }
    md_path.write_text(markdown_for(title, conv_id, created, updated, messages), encoding="utf-8")
    json_path.write_text(
        json.dumps(
            {
                "id": conv_id,
                "title": title,
                "created": created,
                "updated": updated,
                "project": project,
                "messages": messages,
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )
    existing[conv_id] = record
    return True


def import_export(source: Path, archive: Path) -> dict:
    root, temp = unpack_source(source)
    try:
        files = conversation_files(root)
        if not files:
            return {"ok": False, "error": "no conversations.json found in the export"}

        archive.mkdir(parents=True, exist_ok=True)
        (archive / CONVERSATIONS_DIR).mkdir(exist_ok=True)
        existing = {item.get("id"): item for item in read_index(archive).get("conversations", []) if item.get("id")}
        imported_at = datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        written = 0
        skipped = 0

        for file_path in files:
            for conversation in load_conversations(file_path):
                if ingest_conversation(conversation, archive, existing):
                    written += 1
                else:
                    skipped += 1

        assets = copy_assets(root, archive / ASSETS_DIR)
        conversations = list(existing.values())
        write_index(archive, conversations, imported_at)
        return {
            "ok": True,
            "archive": str(archive),
            "imported_at": imported_at,
            "written": written,
            "skipped": skipped,
            "assets": assets,
            "conversations": len(conversations),
        }
    finally:
        if temp is not None:
            temp.cleanup()


def list_conversations(archive: Path, query: str, limit: int, project: str = "", since: str = "", until: str = "") -> dict:
    index = read_index(archive)
    items = index.get("conversations") or []
    needle = query.strip().lower()
    filtered = []
    for item in items:
        if needle and needle not in str(item.get("title") or "").lower():
            continue
        if project and str(item.get("project") or "") != project:
            continue
        stamp = chatgpt_live.parse_time(item.get("updated") or item.get("created"))
        if not chatgpt_live.within_range(stamp, since, until):
            continue
        filtered.append(item)
    total = len(filtered)
    if limit > 0:
        filtered = filtered[:limit]
    return {
        "ok": True,
        "archive": str(archive),
        "imported_at": index.get("imported_at") or "",
        "total": total,
        "conversations": filtered,
        "authenticated": chatgpt_live.auth_status().get("authenticated", False),
    }


def status(archive: Path) -> dict:
    index = read_index(archive)
    return {
        "ok": True,
        "archive": str(archive),
        "exists": (archive / INDEX_NAME).is_file(),
        "imported_at": index.get("imported_at") or "",
        "conversations": len(index.get("conversations") or []),
        "live_engine": live_engine_path(),
        "authenticated": chatgpt_live.auth_status().get("authenticated", False),
    }


def doctor(archive: Path) -> dict:
    writable = False
    try:
        archive.mkdir(parents=True, exist_ok=True)
        probe = archive / ".write-test"
        probe.write_text("ok", encoding="utf-8")
        probe.unlink()
        writable = True
    except OSError:
        writable = False
    return {
        "ok": writable,
        "python": sys.version.split()[0],
        "archive": str(archive),
        "writable": writable,
        "live_engine": live_engine_path(),
        "authenticated": chatgpt_live.auth_status().get("authenticated", False),
    }


def preview_conversation(archive: Path, conv_id: str) -> dict:
    info = conversation_path(archive, conv_id)
    if not info.get("ok"):
        return info
    path = Path(str(info.get("path") or ""))
    text = path.read_text(encoding="utf-8") if path.is_file() else ""
    info["preview"] = text[:6000]
    return info


def live_export(archive: Path, project: str, since: str, until: str, incremental: bool, limit: int) -> dict:
    existing = {item.get("id"): item for item in read_index(archive).get("conversations", []) if item.get("id")}
    result = chatgpt_live.export_remote(
        archive,
        ingest_conversation,
        project,
        since,
        until,
        incremental,
        limit,
        existing,
    )
    imported_at = datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    write_index(archive, list(existing.values()), imported_at)
    result["imported_at"] = imported_at
    result["archive"] = str(archive)
    result["conversations"] = len(existing)
    return result


def conversation_path(archive: Path, conv_id: str) -> dict:
    for item in read_index(archive).get("conversations") or []:
        if str(item.get("id")) == conv_id:
            markdown = archive / str(item.get("markdown") or "")
            return {
                "ok": markdown.is_file(),
                "id": conv_id,
                "title": item.get("title") or "",
                "path": str(markdown),
            }
    return {"ok": False, "error": f"conversation not found: {conv_id}"}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="ChatGPT official-export archive helper")
    parser.add_argument("--out", default=str(DEFAULT_ARCHIVE), help="archive directory")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    sub.add_parser("doctor")
    import_cmd = sub.add_parser("import")
    import_cmd.add_argument("source")
    list_cmd = sub.add_parser("list")
    list_cmd.add_argument("--query", default="")
    list_cmd.add_argument("--project", default="")
    list_cmd.add_argument("--since", default="")
    list_cmd.add_argument("--until", default="")
    list_cmd.add_argument("--limit", type=int, default=200)
    open_cmd = sub.add_parser("open")
    open_cmd.add_argument("id")
    preview_cmd = sub.add_parser("preview")
    preview_cmd.add_argument("id")
    sub.add_parser("auth-status")
    sub.add_parser("auth-clear")
    export_cmd = sub.add_parser("export")
    export_cmd.add_argument("--project", default="")
    export_cmd.add_argument("--since", default="")
    export_cmd.add_argument("--until", default="")
    export_cmd.add_argument("--limit", type=int, default=150)
    export_cmd.add_argument("--full", action="store_true")
    sub.add_parser("projects")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    archive = Path(os.path.expanduser(args.out)).resolve()
    try:
        if args.command == "status":
            return emit(status(archive))
        if args.command == "doctor":
            return emit(doctor(archive))
        if args.command == "import":
            source = Path(os.path.expanduser(args.source)).resolve()
            return emit(import_export(source, archive))
        if args.command == "list":
            return emit(list_conversations(archive, args.query, args.limit, args.project, args.since, args.until))
        if args.command == "open":
            return emit(conversation_path(archive, args.id))
        if args.command == "preview":
            return emit(preview_conversation(archive, args.id))
        if args.command == "auth-status":
            return emit(chatgpt_live.auth_status())
        if args.command == "auth-clear":
            return emit(chatgpt_live.clear_token())
        if args.command == "projects":
            return emit(chatgpt_live.list_projects())
        if args.command == "export":
            return emit(live_export(archive, args.project, args.since, args.until, not args.full, args.limit))
        return emit({"ok": False, "error": "unknown command"})
    except chatgpt_live.LiveError as error:
        return emit({"ok": False, "error": str(error)})
    except Exception as error:  # noqa: BLE001 — CLI boundary
        return emit({"ok": False, "error": str(error)})


if __name__ == "__main__":
    sys.exit(main())
