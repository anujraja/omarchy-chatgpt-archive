"""Live ChatGPT export using the signed-in browser session token.

The token is read from ~/.config/chatgpt-archive/config.env only. It is never
printed, never accepted as a CLI flag, and never written into the archive.
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path

BASE_URL = "https://chatgpt.com"
CONFIG_DIR = Path.home() / ".config" / "chatgpt-archive"
CONFIG_FILE = CONFIG_DIR / "config.env"
DEVICE_FILE = CONFIG_DIR / "device_id"


class LiveError(Exception):
    pass


def ensure_config_dir() -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(CONFIG_DIR, 0o700)
    except OSError:
        pass


def read_env() -> dict[str, str]:
    values: dict[str, str] = {}
    if not CONFIG_FILE.is_file():
        return values
    for line in CONFIG_FILE.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def write_token(token: str) -> dict:
    ensure_config_dir()
    cleaned = token.strip()
    if cleaned.lower().startswith("bearer "):
        cleaned = cleaned[7:].strip()
    if not cleaned:
        raise LiveError("session token is empty")
    CONFIG_FILE.write_text(f"CHATGPT_TOKEN={cleaned}\n", encoding="utf-8")
    os.chmod(CONFIG_FILE, 0o600)
    return {"ok": True, "authenticated": True}


def clear_token() -> dict:
    if CONFIG_FILE.is_file():
        CONFIG_FILE.unlink()
    return {"ok": True, "authenticated": False}


def auth_status() -> dict:
    token = read_env().get("CHATGPT_TOKEN", "")
    return {
        "ok": True,
        "authenticated": bool(token),
        "config": str(CONFIG_FILE),
    }


def device_id() -> str:
    ensure_config_dir()
    if DEVICE_FILE.is_file():
        value = DEVICE_FILE.read_text(encoding="utf-8").strip()
        if value:
            return value
    value = str(uuid.uuid4())
    DEVICE_FILE.write_text(value + "\n", encoding="utf-8")
    return value


def _headers(token: str) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Accept-Language": "en-US,en;q=0.9",
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        "Referer": "https://chatgpt.com/",
        "Origin": "https://chatgpt.com",
        "Oai-Device-Id": device_id(),
        "Oai-Language": "en-US",
    }


def request_json(path: str, token: str, retries: int = 4) -> dict:
    url = path if path.startswith("http") else f"{BASE_URL}{path}"
    last_error = "request failed"
    for attempt in range(retries):
        req = urllib.request.Request(url, headers=_headers(token), method="GET")
        try:
            with urllib.request.urlopen(req, timeout=45) as response:
                payload = json.loads(response.read().decode("utf-8"))
                return payload if isinstance(payload, dict) else {"items": payload}
        except urllib.error.HTTPError as error:
            if error.code in {401, 403}:
                raise LiveError("ChatGPT session expired. Paste a fresh token from chatgpt.com/api/auth/session.") from error
            if error.code == 429 and attempt < retries - 1:
                time.sleep(2 + attempt * 2)
                continue
            last_error = f"ChatGPT returned HTTP {error.code}"
        except urllib.error.URLError as error:
            last_error = f"network error: {error.reason}"
            if attempt < retries - 1:
                time.sleep(1)
                continue
    raise LiveError(last_error)


def require_token() -> str:
    token = read_env().get("CHATGPT_TOKEN", "")
    if not token:
        raise LiveError("No session token. Open Export and paste the accessToken from chatgpt.com/api/auth/session.")
    return token


def parse_time(value) -> float:
    if value in (None, ""):
        return 0.0
    if isinstance(value, (int, float)):
        stamp = float(value)
        return stamp / 1000.0 if stamp > 10_000_000_000 else stamp
    text = str(value).strip()
    if len(text) >= 10 and text[4] == "-":
        try:
            return datetime.strptime(text[:10], "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp()
        except ValueError:
            pass
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


def within_range(stamp: float, since: str, until: str) -> bool:
    if since:
        start = parse_time(since)
        if start and stamp and stamp < start:
            return False
    if until:
        end = parse_time(until)
        if end:
            if len(until) <= 10:
                end += 24 * 60 * 60 - 1
            if stamp and stamp > end:
                return False
    return True


def write_progress(archive: Path, payload: dict) -> None:
    path = archive / ".progress.json"
    archive.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")


def list_projects() -> dict:
    token = require_token()
    items = []
    cursor = None
    while True:
        path = "/backend-api/gizmos/snorlax/sidebar"
        if cursor:
            path += "?cursor=" + urllib.parse.quote(str(cursor))
        payload = request_json(path, token)
        for raw in payload.get("items") or []:
            gizmo = raw.get("gizmo") if isinstance(raw, dict) else None
            if not isinstance(gizmo, dict):
                continue
            display = gizmo.get("display") if isinstance(gizmo.get("display"), dict) else {}
            items.append(
                {
                    "id": str(gizmo.get("id") or ""),
                    "name": str(display.get("name") or gizmo.get("name") or "Untitled project"),
                    "archived": bool(gizmo.get("is_archived")),
                }
            )
        cursor = payload.get("cursor")
        if not cursor:
            break
        time.sleep(0.35)
    visible = [item for item in items if item.get("id") and not item.get("archived")]
    return {"ok": True, "projects": visible}


def _normalize_item(raw: dict) -> dict:
    return {
        "id": str(raw.get("id") or raw.get("conversation_id") or ""),
        "title": str(raw.get("title") or "Untitled").strip() or "Untitled",
        "create_time": raw.get("create_time"),
        "update_time": raw.get("update_time") or raw.get("create_time"),
    }


def list_remote(project: str, since: str, until: str, limit: int) -> dict:
    token = require_token()
    collected: list[dict] = []
    if project:
        cursor = "0"
        path_base = f"/backend-api/gizmos/{urllib.parse.quote(project)}/conversations"
        while cursor not in (None, ""):
            payload = request_json(path_base + "?cursor=" + urllib.parse.quote(str(cursor)), token)
            for raw in payload.get("items") or []:
                if isinstance(raw, dict):
                    collected.append(_normalize_item(raw))
            cursor = payload.get("cursor")
            time.sleep(0.35)
    else:
        offset = 0
        total = 10**9
        page = 100
        while offset < total and len(collected) < max(limit * 3, page):
            payload = request_json(
                f"/backend-api/conversations?offset={offset}&limit={page}&order=updated",
                token,
            )
            total = int(payload.get("total") or 0)
            batch = payload.get("items") or []
            for raw in batch:
                if isinstance(raw, dict):
                    collected.append(_normalize_item(raw))
            if not batch:
                break
            offset += page
            time.sleep(0.35)
            last_stamp = parse_time(collected[-1].get("update_time")) if collected else 0
            if since and last_stamp and last_stamp < parse_time(since):
                break

    filtered = []
    for item in collected:
        if not item.get("id"):
            continue
        if not within_range(parse_time(item.get("update_time")), since, until):
            continue
        filtered.append(item)
        if limit > 0 and len(filtered) >= limit:
            break
    return {"ok": True, "conversations": filtered, "total": len(filtered), "project": project}


def export_remote(archive: Path, ingest, project: str, since: str, until: str, incremental: bool, limit: int, existing: dict | None = None) -> dict:
    listing = list_remote(project, since, until, limit)
    items = listing.get("conversations") or []
    write_progress(
        archive,
        {"phase": "listing", "done": 0, "total": len(items), "title": "Listing conversations"},
    )
    token = require_token()
    if existing is None:
        existing = {}

    written = 0
    skipped = 0
    errors = 0
    for index, item in enumerate(items, start=1):
        conv_id = item["id"]
        write_progress(
            archive,
            {
                "phase": "downloading",
                "done": index - 1,
                "total": len(items),
                "title": item.get("title") or conv_id,
            },
        )
        if incremental:
            local = existing.get(conv_id) or {}
            local_updated = parse_time(local.get("updated"))
            remote_updated = parse_time(item.get("update_time"))
            if local_updated and remote_updated and remote_updated <= local_updated:
                skipped += 1
                continue
        try:
            payload = request_json(f"/backend-api/conversation/{urllib.parse.quote(conv_id)}", token)
            payload.setdefault("conversation_id", conv_id)
            payload.setdefault("title", item.get("title"))
            ingest(payload, archive, existing, project=project)
            written += 1
        except LiveError:
            errors += 1
        time.sleep(0.4)

    write_progress(archive, {"phase": "done", "done": len(items), "total": len(items), "title": "Export complete"})
    return {
        "ok": errors == 0,
        "written": written,
        "skipped": skipped,
        "errors": errors,
        "matched": len(items),
        "project": project,
        "since": since,
        "until": until,
        "conversations": len(existing),
    }
