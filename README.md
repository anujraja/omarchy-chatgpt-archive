# ChatGPT Archive

Omarchy app for a local ChatGPT conversation archive. Open it from the bar, export with a project and date range, or import an official ZIP.

## Install

```bash
omarchy plugin add https://github.com/anujraja/omarchy-chatgpt-archive.git --enable
```

The **Archive** badge sits on the right of the bar:

- Left click — open the app
- Middle click — open the Export sheet
- Right click — open the archive folder

## Export from the bar

1. Click **Archive**, then **Export**.
2. Open [chatgpt.com/api/auth/session](https://chatgpt.com/api/auth/session) while signed in.
3. Copy `accessToken` and paste it once. It is stored only in `~/.config/chatgpt-archive/config.env` (mode 600).
4. Choose **All projects** or one project, a date range (7 / 30 / 90 days or custom), and Incremental or Full.
5. **Start export**. Matching threads are written as Markdown under `~/.local/share/chatgpt-archive`.

Incremental skips conversations that have not changed since the last archive. The token is never shown in the UI after save and never passed as a command-line flag.

You can still import ChatGPT’s official ZIP from **Settings → Data controls → Export data**.

## Remove

```bash
omarchy plugin remove io.github.anujraja.chatgpt-archive
```

Removal does not delete the archive folder or the saved session file.

## License

MIT. ChatGPT conversation files remain your data.
