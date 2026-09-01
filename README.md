# ChatGPT Archive

Omarchy app for a local ChatGPT conversation archive. Open it from the bar, export with a project and date range, or import an official ZIP.

## Install

```bash
omarchy plugin add https://github.com/anujraja/omarchy-chatgpt-archive.git --enable
```

A compact zip icon sits on the right of the bar. Click it to open a panel attached to the button, like the clock or audio popups.

- Left click — open the panel
- Middle click — start export
- Right click — open the archive folder

If you are not signed in, the icon is a login glyph. After ChatGPT login it becomes the archive box.

## Export from the bar

1. Click the icon. If there is no session, press **Log in to ChatGPT**.
2. Sign in in the ChatGPT window that opens. The app fetches the session in the background — no token paste.
3. Choose a project and date range, then **Export**.

Matching threads are written as Markdown under `~/.local/share/chatgpt-archive`. A progress bar shows listing and download as they happen. Incremental skips conversations that have not changed. The session is stored only in `~/.config/chatgpt-archive/config.env` (mode 600) and is never passed as a command-line flag.

## Schedule

Open the panel → **Settings**. Choose Off, Daily, or Weekly, set a time, and save. Omarchy uses a systemd user timer on this machine (`chatgpt-archive.timer`) so exports keep running while you are logged in.

You can still import ChatGPT’s official ZIP from **Settings → Data controls → Export data**.

## Remove

```bash
omarchy plugin remove io.github.anujraja.chatgpt-archive
```

Removal does not delete the archive folder or the saved session file.

## License

MIT. ChatGPT conversation files remain your data.
