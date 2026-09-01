import QtQuick
import Quickshell
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

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf1c6"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "ChatGPT Archive"
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
