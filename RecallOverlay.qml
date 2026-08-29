import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false

  function open(payloadJson) {
    opened = true
  }

  function close() {
    opened = false
  }

  function dismiss() {
    opened = false
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "gmickel.gno-recall")
  }

  function toggle() {
    if (opened)
      dismiss()
    else
      open("{}")
  }

  function peekState(arg) {
    if (!service)
      return JSON.stringify({ error: "service-unavailable", overlayOpened: root.opened })
    var payload = typeof service.debugSnapshot === "function"
      ? service.debugSnapshot()
      : JSON.stringify({
          state: service.state,
          resolvedGnoPath: service.resolvedGnoPath || "",
          generationId: service.generationId || 0,
          snapshot: service.snapshot
        })
    try {
      var parsed = JSON.parse(payload)
      parsed.overlayOpened = root.opened
      parsed.panelOpened = service.panelOpened === true
      return JSON.stringify(parsed)
    } catch (error) {
      return payload
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    WlrLayershell.namespace: "gmickel-gno-recall"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      width: Math.min(Style.space(280), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(88), panel.height - Style.gapsOut * 2)
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Text {
        anchors.fill: parent
        text: "GNO Recall"
        color: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.heading
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }
}
