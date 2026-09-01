import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.anujraja.chatgpt-archive"
  ipcTarget: "io.github.anujraja.chatgpt-archive"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  property bool busy: false
  property bool authenticated: false
  property bool waitingLogin: false
  property bool exporting: false
  property string page: "archive"
  property string statusText: "ChatGPT Archive"
  property string filterText: ""
  property string projectId: ""
  property string datePreset: "30d"
  property string exportMode: "incremental"
  property string scheduleMode: "off"
  property string scheduleTime: "09:00"
  property string scheduleWeekday: "mon"
  property string scheduleLast: ""
  property int selectedIndex: 0
  property var conversations: []
  property var projects: []
  property int progressDone: 0
  property int progressTotal: 0
  property string progressTitle: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string archiveDir: {
    var configured = String(setting("archivePath", "")).trim()
    return configured.length > 0 ? configured : (home + "/.local/share/chatgpt-archive")
  }
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var dateOptions: [
    { value: "all", label: "All dates" },
    { value: "7d", label: "Last 7 days" },
    { value: "30d", label: "Last 30 days" },
    { value: "90d", label: "Last 90 days" }
  ]
  readonly property var projectOptions: {
    var options = [{ value: "", label: "All projects" }]
    for (var i = 0; i < projects.length; i++)
      options.push({ value: String(projects[i].id || ""), label: String(projects[i].name || "Project") })
    return options
  }
  readonly property real progressFraction: progressTotal > 0 ? Math.min(1, progressDone / progressTotal) : (exporting ? 0.15 : 0)

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

  function parseJson(raw, fallback) {
    try { return JSON.parse(String(raw || "").trim() || "null") || fallback }
    catch (error) { return fallback }
  }

  function sinceForPreset(preset) {
    if (preset === "all") return ""
    var days = preset === "7d" ? 7 : (preset === "90d" ? 90 : 30)
    var date = new Date()
    date.setDate(date.getDate() - days)
    return date.toISOString().slice(0, 10)
  }

  function refresh() {
    var cmd = pythonCmd("list", "--limit", "80")
    if (root.filterText) { cmd.push("--query"); cmd.push(root.filterText) }
    if (root.projectId) { cmd.push("--project"); cmd.push(root.projectId) }
    var since = sinceForPreset(root.datePreset)
    if (since) { cmd.push("--since"); cmd.push(since) }
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

  function loadSchedule() {
    scheduleGetProc.running = false
    scheduleGetProc.running = true
  }

  function startLogin() {
    root.waitingLogin = true
    root.statusText = "Sign in in the ChatGPT window…"
    loginStartProc.running = false
    loginStartProc.running = true
    loginPollTimer.start()
  }

  function applyLogin(payload) {
    if (payload && payload.authenticated) {
      root.authenticated = true
      root.waitingLogin = false
      loginPollTimer.stop()
      root.statusText = "Signed in"
      root.loadProjects()
      root.refresh()
      return
    }
    root.waitingLogin = !!(payload && payload.waiting)
  }

  function startExport() {
    if (root.exporting) return
    if (!root.authenticated) {
      root.startLogin()
      return
    }
    root.exporting = true
    root.busy = true
    root.progressDone = 0
    root.progressTotal = 0
    root.statusText = "Starting export…"
    var cmd = pythonCmd("export")
    if (root.projectId) { cmd.push("--project"); cmd.push(root.projectId) }
    var since = sinceForPreset(root.datePreset)
    if (since) { cmd.push("--since"); cmd.push(since) }
    if (root.exportMode === "full") cmd.push("--full")
    exportProc.running = false
    exportProc.command = cmd
    exportProc.running = true
  }

  function saveSchedule() {
    scheduleSetProc.running = false
    scheduleSetProc.command = pythonCmd("schedule-set", "--mode", root.scheduleMode, "--time", root.scheduleTime, "--weekday", root.scheduleWeekday)
    scheduleSetProc.running = true
  }

  function openSelected() {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.conversations.length) return
    var item = root.conversations[root.selectedIndex]
    if (!item || !item.markdown) return
    Quickshell.execDetached(["xdg-open", root.archiveDir + "/" + item.markdown])
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
        root.statusText = (payload.phase === "downloading" ? "Downloading" : "Listing") + " " + root.progressDone + "/" + root.progressTotal
    }
    onFileChanged: reload()
  }

  Process { id: listProc; running: false; stdout: StdioCollector { id: listOut; waitForEnd: true }
    onExited: {
      var payload = root.parseJson(listOut.text, { ok: false })
      root.conversations = payload.conversations || []
      if (payload.authenticated !== undefined) root.authenticated = !!payload.authenticated
      if (!root.exporting) root.statusText = String(payload.total || root.conversations.length) + " conversations"
      root.busy = false
    }
  }
  Process { id: authProc; running: false; command: ["python3", root.pluginFile("archive.py"), "auth-status"]; stdout: StdioCollector { id: authOut; waitForEnd: true }
    onExited: { var payload = root.parseJson(authOut.text, {}); root.authenticated = !!payload.authenticated }
  }
  Process { id: projectsProc; running: false; command: ["python3", root.pluginFile("archive.py"), "projects"]; stdout: StdioCollector { id: projectsOut; waitForEnd: true }
    onExited: { var payload = root.parseJson(projectsOut.text, {}); if (payload && payload.ok) root.projects = payload.projects || [] }
  }
  Process { id: loginStartProc; running: false; command: ["python3", root.pluginFile("archive.py"), "login"]; stdout: StdioCollector { id: loginStartOut; waitForEnd: true }
    onExited: root.applyLogin(root.parseJson(loginStartOut.text, {}))
  }
  Process { id: loginPollProc; running: false; command: ["python3", root.pluginFile("archive.py"), "login", "--poll"]; stdout: StdioCollector { id: loginPollOut; waitForEnd: true }
    onExited: root.applyLogin(root.parseJson(loginPollOut.text, {}))
  }
  Process { id: exportProc; running: false; stdout: StdioCollector { id: exportOut; waitForEnd: true }
    onExited: {
      var payload = root.parseJson(exportOut.text, { ok: false, error: "Export failed" })
      root.exporting = false
      root.busy = false
      root.statusText = payload.ok ? ("Exported " + (payload.written || 0) + " chats") : (payload.error || "Export failed")
      root.refresh()
      root.loadSchedule()
    }
  }
  Process { id: scheduleGetProc; running: false; command: ["python3", root.pluginFile("archive.py"), "schedule-get"]; stdout: StdioCollector { id: scheduleGetOut; waitForEnd: true }
    onExited: {
      var payload = root.parseJson(scheduleGetOut.text, {})
      if (!payload || !payload.ok) return
      root.scheduleMode = String(payload.mode || "off")
      root.scheduleTime = String(payload.time || "09:00")
      root.scheduleWeekday = String(payload.weekday || "mon")
      root.scheduleLast = String(payload.last_status || payload.last_run || "")
    }
  }
  Process { id: scheduleSetProc; running: false; stdout: StdioCollector { id: scheduleSetOut; waitForEnd: true }
    onExited: {
      var payload = root.parseJson(scheduleSetOut.text, { ok: false })
      root.statusText = payload.ok ? "Schedule saved" : (payload.error || "Could not save schedule")
      root.loadSchedule()
    }
  }

  Timer {
    id: loginPollTimer
    interval: 2000
    repeat: true
    onTriggered: {
      if (root.authenticated) { stop(); return }
      loginPollProc.running = false
      loginPollProc.running = true
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: root.openSelected()
      onTextKey: function(t) {
        if (t === "e" || t === "E") root.startExport()
        else if (t === "s" || t === "S") root.page = root.page === "settings" ? "archive" : "settings"
        else if (t === "l" || t === "L") root.startLogin()
      }

      Column {
        id: body
        width: parent.width
        spacing: Style.space(12)

        RowLayout {
          width: parent.width
          spacing: Style.space(8)
          Column {
            Layout.fillWidth: true
            spacing: 2
            Text {
              text: root.page === "settings" ? "Settings" : "ChatGPT Archive"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: root.exporting ? root.statusText : (root.authenticated ? root.statusText : "Not signed in")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          Button {
            text: root.page === "settings" ? "Back" : "Settings"
            bordered: true
            foreground: root.foreground
            onClicked: root.page = root.page === "settings" ? "archive" : "settings"
          }
        }

        Rectangle {
          visible: root.exporting
          width: parent.width
          height: Style.space(8)
          radius: height / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
          Rectangle {
            width: Math.max(Style.space(12), parent.width * root.progressFraction)
            height: parent.height
            radius: parent.radius
            color: Color.accent
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          }
        }
        Text {
          visible: root.exporting && root.progressTitle.length > 0
          width: parent.width
          text: root.progressTitle
          elide: Text.ElideRight
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Column {
          visible: root.page === "settings"
          width: parent.width
          spacing: Style.space(10)

          Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: "Scheduled exports run on this machine while you are logged in. They use the same ChatGPT session as the bar."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Dropdown {
            width: parent.width
            label: "Schedule"
            value: root.scheduleMode
            options: [
              { value: "off", label: "Off" },
              { value: "daily", label: "Daily" },
              { value: "weekly", label: "Weekly" }
            ]
            foreground: root.foreground
            onChanged: function(value) { root.scheduleMode = value }
          }
          Dropdown {
            visible: root.scheduleMode === "weekly"
            width: parent.width
            label: "Weekday"
            value: root.scheduleWeekday
            options: [
              { value: "mon", label: "Monday" },
              { value: "tue", label: "Tuesday" },
              { value: "wed", label: "Wednesday" },
              { value: "thu", label: "Thursday" },
              { value: "fri", label: "Friday" },
              { value: "sat", label: "Saturday" },
              { value: "sun", label: "Sunday" }
            ]
            foreground: root.foreground
            onChanged: function(value) { root.scheduleWeekday = value }
          }
          TextField {
            width: parent.width
            placeholderText: "Time HH:MM"
            text: root.scheduleTime
            foreground: root.foreground
            onEditingFinished: root.scheduleTime = text
          }
          Text {
            visible: root.scheduleLast.length > 0
            text: "Last run: " + root.scheduleLast
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Button {
            text: "Save schedule"
            active: true
            foreground: root.foreground
            accent: Color.accent
            onClicked: root.saveSchedule()
          }
        }

        Column {
          visible: root.page !== "settings" && !root.authenticated
          width: parent.width
          spacing: Style.space(10)

          Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: root.waitingLogin
              ? "Sign in in the ChatGPT window. This panel will catch the session automatically."
              : "Log in to ChatGPT in the browser, then export chats from this panel."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Button {
            text: root.waitingLogin ? "Waiting for login…" : "Log in to ChatGPT"
            active: true
            foreground: root.foreground
            accent: Color.accent
            onClicked: root.startLogin()
          }
        }

        Column {
          visible: root.page !== "settings" && root.authenticated
          width: parent.width
          spacing: Style.space(10)

          Dropdown {
            width: parent.width
            label: "Project"
            value: root.projectId
            options: root.projectOptions
            foreground: root.foreground
            onChanged: function(value) { root.projectId = value; root.refresh() }
          }
          Dropdown {
            width: parent.width
            label: "Date range"
            value: root.datePreset
            options: root.dateOptions
            foreground: root.foreground
            onChanged: function(value) { root.datePreset = value; root.refresh() }
          }
          Button {
            text: root.exporting ? "Downloading…" : "Export chats"
            active: true
            foreground: root.foreground
            accent: Color.accent
            onClicked: root.startExport()
          }

          Repeater {
            model: root.conversations
            delegate: Rectangle {
              required property var modelData
              required property int index
              width: body.width
              height: Style.space(44)
              radius: Style.space(8)
              color: index === root.selectedIndex ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : "transparent"
              MouseArea {
                anchors.fill: parent
                onClicked: root.selectedIndex = index
                onDoubleClicked: { root.selectedIndex = index; root.openSelected() }
              }
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
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  width: parent.width
                  text: String(modelData.updated || "").slice(0, 10)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }
      }
    }
  }
}
