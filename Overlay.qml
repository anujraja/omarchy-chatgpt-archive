import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool busy: false
  property string statusText: "Import an official ChatGPT export ZIP."
  property string filterText: ""
  property int selectedIndex: 0
  property var conversations: []
  property int conversationCount: 0
  property string importedAt: ""
  property string liveEngine: ""

  readonly property string pluginId: (manifest && manifest.id) ? String(manifest.id) : "io.github.anujraja.chatgpt-archive"
  readonly property string home: Quickshell.env("HOME")
  readonly property var userSettings: {
    var config = shell && shell.shellConfig ? shell.shellConfig : null
    var plugins = config && Array.isArray(config.plugins) ? config.plugins : []
    for (var i = 0; i < plugins.length; i++) {
      if (plugins[i] && String(plugins[i].id || "") === pluginId) return plugins[i]
    }
    return ({})
  }
  readonly property string archiveDir: {
    var configured = String(userSettings.archivePath || "").trim()
    return configured.length > 0 ? configured : (home + "/.local/share/chatgpt-archive")
  }
  readonly property string scriptPath: {
    var url = Qt.resolvedUrl("archive.py").toString()
    if (url.indexOf("file://") === 0) return decodeURIComponent(url.substring(7))
    return url
  }

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int cardWidth: Math.min(Style.space(760), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(44), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)

  readonly property var visibleConversations: {
    var needle = filterText.trim().toLowerCase()
    if (!needle) return conversations
    var out = []
    for (var i = 0; i < conversations.length; i++) {
      var title = String(conversations[i].title || "").toLowerCase()
      if (title.indexOf(needle) !== -1) out.push(conversations[i])
    }
    return out
  }

  function pluginFile(name) {
    var url = Qt.resolvedUrl(name).toString()
    if (url.indexOf("file://") === 0) return decodeURIComponent(url.substring(7))
    return url
  }

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function parseJson(raw, fallback) {
    try {
      return JSON.parse(String(raw || "").trim() || "null") || fallback
    } catch (error) {
      return fallback
    }
  }

  function applyStatus(payload) {
    if (!payload || payload.ok === false) {
      root.statusText = payload && payload.error ? payload.error : "Archive helper failed."
      return
    }
    root.conversationCount = Number(payload.conversations || payload.total || 0)
    root.importedAt = String(payload.imported_at || "")
    if (payload.live_engine !== undefined) root.liveEngine = String(payload.live_engine || "")
    if (payload.written !== undefined)
      root.statusText = "Imported " + payload.written + " conversations into " + root.archiveDir
    else if (root.conversationCount > 0)
      root.statusText = root.conversationCount + " conversations" + (root.importedAt ? " · last import " + root.importedAt : "")
    else
      root.statusText = "No archive yet. Import the ZIP from ChatGPT → Settings → Data controls → Export data."
  }

  function refresh() {
    root.busy = true
    listProc.running = false
    listProc.command = ["python3", root.pluginFile("archive.py"), "--out", root.archiveDir, "list", "--limit", "400"]
    listProc.running = true
  }

  function pickExport() {
    if (root.busy) return
    root.busy = true
    root.statusText = "Choose a ChatGPT export ZIP…"
    pickProc.running = false
    pickProc.running = true
  }

  function runImport(path) {
    if (!path) {
      root.busy = false
      return
    }
    root.busy = true
    root.statusText = "Importing " + path + "…"
    importProc.running = false
    importProc.command = ["python3", root.pluginFile("archive.py"), "--out", root.archiveDir, "import", path]
    importProc.running = true
  }

  function openSelected() {
    var items = root.visibleConversations
    if (root.selectedIndex < 0 || root.selectedIndex >= items.length) return
    var item = items[root.selectedIndex]
    var relative = String(item.markdown || "")
    if (!relative) return
    Quickshell.execDetached(["xdg-open", root.archiveDir + "/" + relative])
  }

  function openFolder() {
    Quickshell.execDetached(["bash", "-lc", "mkdir -p " + JSON.stringify(root.archiveDir) + " && xdg-open " + JSON.stringify(root.archiveDir)])
  }

  function runLiveExport() {
    if (!root.liveEngine || root.busy) return
    root.busy = true
    root.statusText = "Running chatgpt-download-engine export incremental…"
    liveProc.running = false
    liveProc.command = [root.liveEngine, "export", "incremental"]
    liveProc.running = true
  }

  function moveSelection(delta) {
    var count = root.visibleConversations.length
    if (count === 0) {
      root.selectedIndex = 0
      return
    }
    var next = root.selectedIndex + delta
    if (next < 0) next = 0
    if (next >= count) next = count - 1
    root.selectedIndex = next
  }

  Process {
    id: listProc
    running: false
    stdout: StdioCollector {
      id: listOut
      waitForEnd: true
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: {
      var payload = root.parseJson(listOut.text, { ok: false, error: "Could not read archive." })
      root.applyStatus(payload)
      root.conversations = payload.conversations || []
      if (root.selectedIndex >= root.visibleConversations.length) root.selectedIndex = 0
      statusProc.running = false
      statusProc.running = true
    }
  }

  Process {
    id: statusProc
    running: false
    command: ["python3", root.pluginFile("archive.py"), "--out", root.archiveDir, "status"]
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
    }
    onExited: {
      var payload = root.parseJson(statusOut.text, {})
      if (payload && payload.live_engine !== undefined) root.liveEngine = String(payload.live_engine || "")
      root.busy = false
    }
  }

  Process {
    id: pickProc
    running: false
    command: ["omarchy", "file", "select", "--title", "Import ChatGPT export", "--extensions", "zip"]
    stdout: StdioCollector {
      id: pickOut
      waitForEnd: true
    }
    onExited: function(code) {
      var path = String(pickOut.text || "").trim().split("\n")[0]
      if (path) root.runImport(path)
      else {
        root.busy = false
        if (code === 1) root.statusText = "Import cancelled."
        else root.statusText = "File picker did not return a ZIP."
      }
    }
  }

  Process {
    id: importProc
    running: false
    stdout: StdioCollector {
      id: importOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: importErr
      waitForEnd: true
    }
    onExited: {
      var payload = root.parseJson(importOut.text, { ok: false, error: String(importErr.text || "Import failed.").trim() })
      root.applyStatus(payload)
      root.busy = false
      root.refresh()
    }
  }

  Process {
    id: liveProc
    running: false
    stdout: StdioCollector {
      id: liveOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: liveErr
      waitForEnd: true
    }
    onExited: function(code) {
      root.busy = false
      var output = String(liveOut.text || liveErr.text || "").trim()
      if (code === 0) root.statusText = output || "Live export finished."
      else root.statusText = output || "Live export failed. Configure chatgpt-download-engine first."
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "chatgpt-archive"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.filterText = ""
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.moveSelection(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.moveSelection(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.openSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_I && event.modifiers & Qt.ControlModifier) {
            root.pickExport()
            event.accepted = true
          } else if (event.key === Qt.Key_O && event.modifiers & Qt.ControlModifier) {
            root.openFolder()
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.filterText += event.text
            root.selectedIndex = 0
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace) {
            root.filterText = root.filterText.slice(0, Math.max(0, root.filterText.length - 1))
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        Text {
          text: "ChatGPT Archive"
          color: root.foreground
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: root.statusText
          color: root.foreground
          opacity: 0.8
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: root.filterText.length > 0
          text: "Filter: " + root.filterText
          color: root.foreground
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          spacing: Style.spacing.sm

          WidgetButton {
            bar: null
            text: root.busy ? "Working…" : "Import ZIP"
            onPressed: root.pickExport()
          }
          WidgetButton {
            bar: null
            text: "Open folder"
            onPressed: root.openFolder()
          }
          WidgetButton {
            visible: root.liveEngine.length > 0
            bar: null
            text: "Live export"
            onPressed: root.runLiveExport()
          }
        }

        ListView {
          id: list
          width: parent.width
          height: parent.height - Style.space(140)
          clip: true
          model: root.visibleConversations
          currentIndex: root.selectedIndex
          delegate: Rectangle {
            required property var modelData
            required property int index
            width: list.width
            height: root.rowHeight
            color: index === root.selectedIndex ? root.selectedBackground : "transparent"
            radius: Style.space(4)

            Column {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: 2

              Text {
                width: parent.width
                text: String(modelData.title || "Untitled")
                elide: Text.ElideRight
                color: index === root.selectedIndex ? root.selectedText : root.foreground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
              }
              Text {
                width: parent.width
                text: String(modelData.updated || modelData.created || "") + " · " + String(modelData.messages || 0) + " messages"
                elide: Text.ElideRight
                color: index === root.selectedIndex ? root.selectedText : root.foreground
                opacity: 0.7
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              anchors.fill: parent
              onClicked: {
                root.selectedIndex = index
                keyCatcher.forceActiveFocus()
              }
              onDoubleClicked: {
                root.selectedIndex = index
                root.openSelected()
              }
            }
          }
        }
      }
    }
  }
}
