import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.anujraja.chatgpt-archive"

  readonly property string pluginId: "io.github.anujraja.chatgpt-archive"
  readonly property string archiveDir: {
    var configured = String(setting("archivePath", "")).trim()
    return configured.length > 0 ? configured : (Quickshell.env("HOME") + "/.local/share/chatgpt-archive")
  }
  property bool authenticated: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: authProc
    running: false
    command: ["python3", Qt.resolvedUrl("archive.py").toString().replace("file://", ""), "auth-status"]
    stdout: StdioCollector {
      id: authOut
      waitForEnd: true
    }
    onExited: {
      try {
        var payload = JSON.parse(String(authOut.text || "{}"))
        root.authenticated = !!payload.authenticated
      } catch (error) {
        root.authenticated = false
      }
    }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      authProc.running = false
      authProc.running = true
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.authenticated ? "󰈹" : "󰌆"
    slotSize: Style.bar.statusSlot
    tooltipText: root.authenticated ? "ChatGPT Archive" : "Log in to ChatGPT"
    onPressed: function(mouseButton) {
      if (!root.bar) return
      if (mouseButton === Qt.RightButton)
        root.bar.run("mkdir -p " + JSON.stringify(root.archiveDir) + " && xdg-open " + JSON.stringify(root.archiveDir))
      else if (mouseButton === Qt.MiddleButton)
        root.bar.run("omarchy-shell shell toggle " + root.pluginId + " '{\"export\":true}'")
      else
        root.bar.run("omarchy-shell shell toggle " + root.pluginId)
    }
  }
}
