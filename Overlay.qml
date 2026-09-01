import QtQuick
import QtQuick.Layouts
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
  property bool exportOpen: false
  property bool authenticated: false
  property bool waitingLogin: false
  property string statusText: "Log in to ChatGPT to export from the bar."
  property string filterText: ""
  property string projectId: ""
  property string datePreset: "all"
  property string customSince: ""
  property string customUntil: ""
  property string exportMode: "incremental"
  property int selectedIndex: 0
  property var conversations: []
  property var projects: []
  property string previewText: "Select a conversation to read it here."
  property string previewTitle: "Preview"
  property int conversationCount: 0
  property string importedAt: ""
  property string progressTitle: ""
  property int progressDone: 0
  property int progressTotal: 0
  property string tokenDraft: ""
  readonly property bool showLogin: !authenticated

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
  readonly property string configFile: home + "/.config/chatgpt-archive/config.env"

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.62)
  property color panelFill: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05)
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int cardWidth: Math.min(Style.space(1120), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(740), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(52), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)

  readonly property var dateOptions: [
    { value: "all", label: "All dates" },
    { value: "7d", label: "Last 7 days" },
    { value: "30d", label: "Last 30 days" },
    { value: "90d", label: "Last 90 days" },
    { value: "custom", label: "Custom range" }
  ]
  readonly property var projectOptions: {
    var options = [{ value: "", label: "All projects" }]
    for (var i = 0; i < projects.length; i++) {
      options.push({ value: String(projects[i].id || ""), label: String(projects[i].name || "Project") })
    }
    return options
  }
  readonly property string sinceValue: datePreset === "custom" ? customSince : sinceForPreset(datePreset)
  readonly property string untilValue: datePreset === "custom" ? customUntil : ""

  function pluginFile(name) {
    var url = Qt.resolvedUrl(name).toString()
    if (url.indexOf("file://") === 0) return decodeURIComponent(url.substring(7))
    return url
  }

  function pythonCmd() {
    var args = ["python3", pluginFile("archive.py"), "--out", archiveDir]
    for (var i = 0; i < arguments.length; i++) args.push(String(arguments[i]))
    return args
  }

  function sinceForPreset(preset) {
    if (preset === "all" || preset === "custom") return ""
    var days = preset === "7d" ? 7 : (preset === "90d" ? 90 : 30)
    var date = new Date()
    date.setDate(date.getDate() - days)
    return date.toISOString().slice(0, 10)
  }

  function parseJson(raw, fallback) {
    try {
      return JSON.parse(String(raw || "").trim() || "null") || fallback
    } catch (error) {
      return fallback
    }
  }

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    var payload = root.parseJson(payloadJson, {})
    root.exportOpen = !!(payload && payload.export)
    root.refresh()
    root.loadProjects()
    if (payload && payload.export && !root.authenticated) root.startLogin()
    Qt.callLater(function() { if (searchField) searchField.forceActiveFocus() })
  }

  function close() { root.opened = false }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function applyList(payload) {
    if (!payload || payload.ok === false) {
      root.statusText = payload && payload.error ? payload.error : "Could not read archive."
      return
    }
    root.conversations = payload.conversations || []
    root.conversationCount = Number(payload.total || root.conversations.length)
    root.importedAt = String(payload.imported_at || "")
    if (payload.authenticated !== undefined) root.authenticated = !!payload.authenticated
    if (root.selectedIndex >= root.conversations.length) root.selectedIndex = 0
    root.statusText = root.conversationCount + " conversations in archive"
    if (root.conversations.length > 0) root.loadPreview()
    else {
      root.previewTitle = "Preview"
      root.previewText = "Nothing here yet. Export from ChatGPT or import an official ZIP."
    }
  }

  function refresh() {
    root.busy = true
    var cmd = pythonCmd("list", "--limit", "400")
    if (root.filterText) { cmd.push("--query"); cmd.push(root.filterText) }
    if (root.projectId) { cmd.push("--project"); cmd.push(root.projectId) }
    if (root.sinceValue) { cmd.push("--since"); cmd.push(root.sinceValue) }
    if (root.untilValue) { cmd.push("--until"); cmd.push(root.untilValue) }
    listProc.running = false
    listProc.command = cmd
    listProc.running = true
    authProc.running = false
    authProc.running = true
  }

  function loadProjects() {
    projectsProc.running = false
    projectsProc.running = true
  }

  function loadPreview() {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.conversations.length) return
    var item = root.conversations[root.selectedIndex]
    root.previewTitle = String(item.title || "Untitled")
    previewProc.running = false
    previewProc.command = pythonCmd("preview", String(item.id || ""))
    previewProc.running = true
  }

  function pickExportZip() {
    if (root.busy) return
    root.busy = true
    root.statusText = "Choose a ChatGPT export ZIP…"
    pickProc.running = false
    pickProc.running = true
  }

  function runImport(path) {
    if (!path) { root.busy = false; return }
    root.busy = true
    root.statusText = "Importing ZIP…"
    importProc.running = false
    importProc.command = pythonCmd("import", path)
    importProc.running = true
  }

  function openSelected() {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.conversations.length) return
    var item = root.conversations[root.selectedIndex]
    if (!item || !item.markdown) return
    Quickshell.execDetached(["xdg-open", root.archiveDir + "/" + item.markdown])
  }

  function openFolder() {
    Quickshell.execDetached(["bash", "-lc", "mkdir -p " + JSON.stringify(root.archiveDir) + " && xdg-open " + JSON.stringify(root.archiveDir)])
  }

  function startLogin() {
    root.waitingLogin = true
    root.statusText = "ChatGPT is opening in the browser. Sign in there — this window will pick up the session."
    loginStartProc.running = false
    loginStartProc.running = true
    loginPollTimer.start()
  }

  function applyLogin(payload) {
    if (payload && payload.authenticated) {
      root.authenticated = true
      root.waitingLogin = false
      loginPollTimer.stop()
      root.statusText = "Signed in. Choose a project and date range, then export."
      root.loadProjects()
      root.refresh()
      return
    }
    root.waitingLogin = !!(payload && payload.waiting)
    if (root.waitingLogin)
      root.statusText = "Waiting for ChatGPT login in the browser…"
  }

  function startExport() {
    if (root.busy) return
    if (!root.authenticated) {
      root.startLogin()
      return
    }
    root.busy = true
    root.statusText = "Exporting from ChatGPT…"
    var cmd = pythonCmd("export")
    if (root.projectId) { cmd.push("--project"); cmd.push(root.projectId) }
    if (root.sinceValue) { cmd.push("--since"); cmd.push(root.sinceValue) }
    if (root.untilValue) { cmd.push("--until"); cmd.push(root.untilValue) }
    if (root.exportMode === "full") cmd.push("--full")
    exportProc.running = false
    exportProc.command = cmd
    exportProc.running = true
  }

  function moveSelection(delta) {
    if (root.conversations.length === 0) return
    var next = root.selectedIndex + delta
    if (next < 0) next = 0
    if (next >= root.conversations.length) next = root.conversations.length - 1
    root.selectedIndex = next
    root.loadPreview()
  }

  FileView {
    id: tokenFile
    path: root.configFile
    atomicWrites: true
    printErrors: false
  }

  FileView {
    id: progressFile
    path: root.archiveDir + "/.progress.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var payload = root.parseJson(text(), {})
      root.progressTitle = String(payload.title || "")
      root.progressDone = Number(payload.done || 0)
      root.progressTotal = Number(payload.total || 0)
      if (payload.phase && payload.phase !== "done")
        root.statusText = (payload.phase === "downloading" ? "Downloading" : "Listing") + " " + root.progressDone + "/" + root.progressTotal + " · " + root.progressTitle
    }
    onFileChanged: reload()
  }

  Process {
    id: listProc
    running: false
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    onExited: {
      root.applyList(root.parseJson(listOut.text, { ok: false }))
      root.busy = false
    }
  }

  Process {
    id: authProc
    running: false
    command: ["python3", root.pluginFile("archive.py"), "auth-status"]
    stdout: StdioCollector { id: authOut; waitForEnd: true }
    onExited: {
      var payload = root.parseJson(authOut.text, {})
      root.authenticated = !!payload.authenticated
      if (root.authenticated) root.waitingLogin = false
    }
  }

  Process {
    id: loginStartProc
    running: false
    command: ["python3", root.pluginFile("archive.py"), "login"]
    stdout: StdioCollector { id: loginStartOut; waitForEnd: true }
    onExited: root.applyLogin(root.parseJson(loginStartOut.text, {}))
  }

  Process {
    id: loginPollProc
    running: false
    command: ["python3", root.pluginFile("archive.py"), "login", "--poll"]
    stdout: StdioCollector { id: loginPollOut; waitForEnd: true }
    onExited: root.applyLogin(root.parseJson(loginPollOut.text, {}))
  }

  Timer {
    id: loginPollTimer
    interval: 2000
    repeat: true
    onTriggered: {
      if (root.authenticated) {
        stop()
        return
      }
      loginPollProc.running = false
      loginPollProc.running = true
    }
  }

  Process {
    id: projectsProc
    running: false
    command: ["python3", root.pluginFile("archive.py"), "projects"]
    stdout: StdioCollector { id: projectsOut; waitForEnd: true }
    onExited: {
      var payload = root.parseJson(projectsOut.text, {})
      if (payload && payload.ok) root.projects = payload.projects || []
    }
  }

  Process {
    id: previewProc
    running: false
    stdout: StdioCollector { id: previewOut; waitForEnd: true }
    onExited: {
      var payload = root.parseJson(previewOut.text, {})
      root.previewText = String(payload.preview || payload.error || "No preview.")
    }
  }

  Process {
    id: pickProc
    running: false
    command: ["omarchy", "file", "select", "--title", "Import ChatGPT export", "--extensions", "zip"]
    stdout: StdioCollector { id: pickOut; waitForEnd: true }
    onExited: function(code) {
      var path = String(pickOut.text || "").trim().split("\n")[0]
      if (path) root.runImport(path)
      else {
        root.busy = false
        root.statusText = code === 1 ? "Import cancelled." : "No ZIP selected."
      }
    }
  }

  Process {
    id: importProc
    running: false
    stdout: StdioCollector { id: importOut; waitForEnd: true }
    stderr: StdioCollector { id: importErr; waitForEnd: true }
    onExited: {
      var payload = root.parseJson(importOut.text, { ok: false, error: String(importErr.text || "Import failed.").trim() })
      root.busy = false
      root.statusText = payload.ok ? ("Imported " + payload.written + " conversations") : (payload.error || "Import failed")
      root.refresh()
    }
  }

  Process {
    id: exportProc
    running: false
    stdout: StdioCollector { id: exportOut; waitForEnd: true }
    stderr: StdioCollector { id: exportErr; waitForEnd: true }
    onExited: {
      var payload = root.parseJson(exportOut.text, { ok: false, error: String(exportErr.text || "Export failed.").trim() })
      root.busy = false
      root.exportOpen = false
      if (payload.ok)
        root.statusText = "Exported " + (payload.written || 0) + " conversations" + (payload.skipped ? (" · skipped " + payload.skipped) : "")
      else
        root.statusText = payload.error || "Export failed"
      root.refresh()
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

    Rectangle { anchors.fill: parent; color: root.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

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

      ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          Column {
            Layout.fillWidth: true
            spacing: 2
            Text {
              text: "ChatGPT Archive"
              color: root.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: root.authenticated ? "Session ready · export from the bar" : "Log in to ChatGPT in the browser. We'll fetch the session automatically."
              color: root.muted
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }
          }

          Button {
            text: root.authenticated ? (root.busy ? "Working…" : "Export") : (root.waitingLogin ? "Waiting…" : "Log in")
            active: true
            foreground: root.foreground
            accent: Color.accent
            onClicked: {
              if (root.authenticated) root.exportOpen = true
              else root.startLogin()
            }
          }
          Button {
            text: "Import ZIP"
            bordered: true
            foreground: root.foreground
            onClicked: root.pickExportZip()
          }
          Button {
            text: "Folder"
            bordered: true
            foreground: root.foreground
            onClicked: root.openFolder()
          }
        }

        Item {
          visible: root.showLogin
          Layout.fillWidth: true
          Layout.fillHeight: true

          Column {
            anchors.centerIn: parent
            width: Math.min(parent.width - Style.space(40), Style.space(420))
            spacing: Style.spacing.md

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "󰌆"
              color: Color.accent
              font.pixelSize: Style.font.display
              font.family: Style.font.family
            }
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "Log in to ChatGPT"
              color: root.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              width: parent.width
              wrapMode: Text.Wrap
              horizontalAlignment: Text.AlignHCenter
              text: root.waitingLogin
                ? "Sign in in the ChatGPT window. This app will catch the session in the background."
                : "Opens ChatGPT in a browser window. After you sign in, export projects and date ranges from the bar."
              color: root.muted
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }
            Button {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.waitingLogin ? "Waiting for login…" : "Log in to ChatGPT"
              active: true
              foreground: root.foreground
              accent: Color.accent
              onClicked: root.startLogin()
            }
            Button {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Import a ZIP instead"
              bordered: true
              foreground: root.foreground
              onClicked: root.pickExportZip()
            }
          }
        }

        RowLayout {
          visible: !root.showLogin
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          TextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: "Search conversations"
            text: root.filterText
            foreground: root.foreground
            accent: Color.accent
            onTextChanged: {
              root.filterText = text
              searchDebounce.restart()
            }
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                if (root.filterText) { root.filterText = ""; searchField.text = "" }
                else root.dismiss()
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                root.moveSelection(1)
                event.accepted = true
              }
            }
          }

          Dropdown {
            label: ""
            showLabel: false
            Layout.preferredWidth: Style.space(220)
            value: root.projectId
            options: root.projectOptions
            foreground: root.foreground
            onChanged: function(value) {
              root.projectId = value
              root.refresh()
            }
          }

          Dropdown {
            label: ""
            showLabel: false
            Layout.preferredWidth: Style.space(180)
            value: root.datePreset
            options: root.dateOptions
            foreground: root.foreground
            onChanged: function(value) {
              root.datePreset = value
              root.refresh()
            }
          }
        }

        RowLayout {
          visible: !root.showLogin && root.datePreset === "custom"
          Layout.fillWidth: true
          spacing: Style.spacing.sm
          TextField {
            Layout.fillWidth: true
            placeholderText: "Since YYYY-MM-DD"
            text: root.customSince
            foreground: root.foreground
            onEditingFinished: { root.customSince = text; root.refresh() }
          }
          TextField {
            Layout.fillWidth: true
            placeholderText: "Until YYYY-MM-DD"
            text: root.customUntil
            foreground: root.foreground
            onEditingFinished: { root.customUntil = text; root.refresh() }
          }
        }

        RowLayout {
          visible: !root.showLogin
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.spacing.md

          BorderSurface {
            Layout.preferredWidth: Style.space(360)
            Layout.fillHeight: true
            color: root.panelFill
            radius: root.cornerRadius
            borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10), 1)

            ListView {
              id: list
              anchors.fill: parent
              anchors.margins: Style.space(8)
              clip: true
              model: root.conversations
              currentIndex: root.selectedIndex
              boundsBehavior: Flickable.StopAtBounds
              delegate: Rectangle {
                required property var modelData
                required property int index
                width: ListView.view.width
                height: root.rowHeight
                radius: Style.space(8)
                color: index === root.selectedIndex ? root.selectedBackground : "transparent"

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: 3
                  Text {
                    width: parent.width
                    text: String(modelData.title || "Untitled")
                    elide: Text.ElideRight
                    color: index === root.selectedIndex ? root.selectedText : root.foreground
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.body
                    font.bold: index === root.selectedIndex
                  }
                  Text {
                    width: parent.width
                    text: String(modelData.updated || modelData.created || "").slice(0, 10) + " · " + String(modelData.messages || 0) + " messages"
                    elide: Text.ElideRight
                    color: index === root.selectedIndex ? root.selectedText : root.muted
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    root.selectedIndex = index
                    root.loadPreview()
                    searchField.forceActiveFocus()
                  }
                  onDoubleClicked: {
                    root.selectedIndex = index
                    root.openSelected()
                  }
                }
              }
            }
          }

          BorderSurface {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: root.panelFill
            radius: root.cornerRadius
            borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10), 1)

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: Style.space(16)
              spacing: Style.spacing.sm

              Text {
                text: root.previewTitle
                color: root.foreground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.heading
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: previewBody.height
                Text {
                  id: previewBody
                  width: parent.width
                  text: root.previewText
                  wrapMode: Text.Wrap
                  color: root.foreground
                  opacity: 0.92
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.body
                }
              }

              Button {
                visible: root.conversations.length > 0
                text: "Open Markdown"
                bordered: true
                foreground: root.foreground
                onClicked: root.openSelected()
              }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          text: root.statusText
          color: root.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Rectangle {
        visible: root.exportOpen
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)
        radius: root.cornerRadius
        MouseArea { anchors.fill: parent; onClicked: root.exportOpen = false }

        BorderSurface {
          width: Math.min(parent.width - Style.space(80), Style.space(560))
          height: Math.min(parent.height - Style.space(80), implicitHeight)
          implicitHeight: exportForm.implicitHeight + Style.space(36)
          anchors.centerIn: parent
          radius: root.cornerRadius
          color: root.background
          borderSpec: root.borderSpec
          MouseArea { anchors.fill: parent; onClicked: {} }

          Column {
            id: exportForm
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(22)
            spacing: Style.spacing.md

            Text {
              text: "Export from ChatGPT"
              color: root.foreground
              font.pixelSize: Style.font.title
              font.bold: true
              font.family: Style.font.menuFamily
            }
            Text {
              width: parent.width
              wrapMode: Text.Wrap
              text: root.authenticated
                ? "Export matching conversations into the local Markdown archive."
                : "Log in first. ChatGPT opens in the browser and this app fetches the session in the background."
              color: root.muted
              font.pixelSize: Style.font.caption
              font.family: Style.font.menuFamily
            }

            Button {
              visible: !root.authenticated
              text: root.waitingLogin ? "Waiting for login…" : "Log in to ChatGPT"
              active: true
              foreground: root.foreground
              accent: Color.accent
              onClicked: root.startLogin()
            }

            Dropdown {
              width: parent.width
              label: "Project"
              value: root.projectId
              options: root.projectOptions
              foreground: root.foreground
              onChanged: function(value) { root.projectId = value }
            }
            Dropdown {
              width: parent.width
              label: "Date range"
              value: root.datePreset
              options: root.dateOptions
              foreground: root.foreground
              onChanged: function(value) { root.datePreset = value }
            }
            Dropdown {
              width: parent.width
              label: "Mode"
              value: root.exportMode
              options: [
                { value: "incremental", label: "Incremental — skip unchanged" },
                { value: "full", label: "Full refresh of the match set" }
              ]
              foreground: root.foreground
              onChanged: function(value) { root.exportMode = value }
            }

            Row {
              spacing: Style.spacing.sm
              Button {
                text: "Start export"
                active: true
                foreground: root.foreground
                accent: Color.accent
                onClicked: root.startExport()
              }
              Button {
                text: "Cancel"
                bordered: true
                foreground: root.foreground
                onClicked: root.exportOpen = false
              }
            }
          }
        }
      }
    }
  }

  Timer {
    id: searchDebounce
    interval: 180
    repeat: false
    onTriggered: root.refresh()
  }

  Keys.onPressed: function(event) {
    if (!root.opened) return
    if (event.key === Qt.Key_Escape) {
      if (root.exportOpen) root.exportOpen = false
      else root.dismiss()
      event.accepted = true
    }
  }
}
