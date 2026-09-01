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
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool exporting: panelLoader.item ? panelLoader.item.exporting === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property real openPanelIndicatorWidth: button.implicitWidth

  function open() { if (panelLoader.item) { panelLoader.item.open(); panelLoader.item.refresh(); panelLoader.item.loadProjects(); panelLoader.item.loadSchedule() } }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { opened ? close() : open() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("hostWidget" in target) target.hostWidget = root
    if ("anchorItem" in target) target.anchorItem = button
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.anujraja.chatgpt-archive"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function exportNow(): void { root.open(); if (panelLoader.item) panelLoader.item.startExport() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf1c6"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    active: root.exporting
    tooltipText: root.exporting ? "Downloading chats…" : "ChatGPT Archive"
    onPressed: function(mouseButton) {
      if (!root.bar) return
      if (mouseButton === Qt.RightButton)
        root.bar.run("mkdir -p " + JSON.stringify(root.archiveDir) + " && xdg-open " + JSON.stringify(root.archiveDir))
      else if (mouseButton === Qt.MiddleButton) {
        root.open()
        if (panelLoader.item) panelLoader.item.startExport()
      }
      else root.togglePanel()
    }
  }
}
