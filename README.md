# ChatGPT Archive

An Omarchy bar plugin for a local ChatGPT archive. Click the zip icon on the right of the bar to open a panel next to it — the same pattern as clock and audio.

Live shots from this machine, including chats from the **Omarchy-Test** project.

![Panel attached to the bar](docs/screenshots/panel.jpg)

![Empty desktop with the bar icon](docs/screenshots/desktop.jpg)

![Download progress](docs/screenshots/progress.jpg)

![Settings — daily and weekly schedule](docs/screenshots/settings.jpg)

## Install

```bash
omarchy plugin add https://github.com/anujraja/omarchy-chatgpt-archive.git --enable
```

If the zip icon is not on the bar yet:

```bash
omarchy plugin enable io.github.anujraja.chatgpt-archive right
```

Reload the shell after an update:

```bash
omarchy plugin update io.github.anujraja.chatgpt-archive
omarchy restart shell
```

## Use

- **Left click** — open the panel under the icon
- **Middle click** — start an export
- **Right click** — open `~/.local/share/chatgpt-archive`
- In the panel, click a chat to open its Markdown. **Folder** is on the home screen and in Settings.

If you are not signed in, the panel shows **Log in to ChatGPT**. That opens ChatGPT in a browser window; the plugin reads the session in the background. No token paste.

Then pick a **project** (for example Omarchy-Test) and a **date range**, search, and **Export chats**. A progress bar tracks listing and download. Incremental mode skips chats that have not changed.

You can also import the official ZIP from ChatGPT **Settings → Data controls → Export data**.

## Settings

Open the panel → **Settings**:

- Schedule **Off**, **Daily**, or **Weekly**
- Time (`HH:MM`) and weekday for weekly runs
- **Save schedule** — installs a systemd user timer (`chatgpt-archive.timer`)
- **Open archive folder**

Scheduled exports use the same local session as the bar and run while you are logged in.

## Remove

```bash
omarchy plugin remove io.github.anujraja.chatgpt-archive
```

This does not delete the archive folder, the saved session, or the timer. To drop the timer as well:

```bash
systemctl --user disable --now chatgpt-archive.timer
```

## Privacy

- Session is stored only in `~/.config/chatgpt-archive/config.env` (mode `600`)
- Never passed as a command-line flag
- No extra packages; Python 3 from Omarchy is enough
- Plugins run unsandboxed, like every Omarchy plugin

## Marketplace

Plugin id: `io.github.anujraja.chatgpt-archive`  
License: MIT  
Kind: `bar-widget`  
Category: Productivity  
Tags: `bar`, `quickshell`

Submit from [plugins.omarchy.org/publish.html](https://plugins.omarchy.org/publish.html) with this repository URL.

## License

MIT. ChatGPT conversation files remain your data.
