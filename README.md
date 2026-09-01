# ChatGPT Archive

Omarchy plugin that turns an official ChatGPT data export into a local Markdown archive, then lets you search and open conversations from the bar.

It does **not** log into ChatGPT and it does **not** store a session token. The primary path is the official export ZIP from **ChatGPT → Settings → Data controls → Export data**.

If you already have [`chatgpt-download-engine`](https://github.com/anujraja/chatgpt-download-engine) installed, the overlay also offers **Live export**, which runs `chatgpt-download-engine export incremental` with that tool's own config.

## Install

```bash
omarchy plugin add https://github.com/anujraja/omarchy-chatgpt-archive.git --enable
```

Place the widget on the bar if it is not already there:

```bash
omarchy plugin enable io.github.anujraja.chatgpt-archive right
```

Left click the **Archive** badge to open the overlay. Right click opens the archive folder. In the overlay:

- **Import ZIP** — pick the ChatGPT export
- type to filter titles
- Enter or double-click opens the Markdown file
- Ctrl+I imports, Ctrl+O opens the folder, Escape closes

Default archive directory: `~/.local/share/chatgpt-archive`. Override with `archivePath` on the plugin entry in `~/.config/omarchy/shell.json`.

## Remove

```bash
omarchy plugin remove io.github.anujraja.chatgpt-archive
```

Removal does not delete `~/.local/share/chatgpt-archive` or any imported Markdown.

## How it works

`archive.py` reads `conversations.json` (and sharded `conversations-*.json` files) from the ZIP, walks each conversation's `mapping` from `current_node`, and writes:

```
~/.local/share/chatgpt-archive/
  index.json
  conversations/<title>-<id>.md
  conversations/<title>-<id>.json
  assets/   # extra files from the export, when present
```

Python 3 from Omarchy is the only runtime. No extra packages.

Live incremental download is optional and stays in `chatgpt-download-engine`. This plugin never writes `CHATGPT_TOKEN` and never passes a token on the command line.

## License

MIT. Official ChatGPT export files remain your data; this plugin only copies them into the local archive you choose.
