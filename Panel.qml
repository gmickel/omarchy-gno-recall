import QtQuick

// Internal anchored popup. BarWidget.qml will load this in a later task.
// Not a manifest entry point — declaring kind: panel would steal
// `omarchy-shell shell toggle gmickel.gno-recall` from the overlay.
Item {
  id: root

  visible: false

  property var bar: null
  property var settings: ({})
  property var service: null
  property var hostWidget: null
  property var anchorItem: null
  property bool opened: false
  property bool popoutSwitchClosing: false

  function open() {
    opened = true
  }

  function close() {
    opened = false
  }

  function toggle() {
    if (opened)
      close()
    else
      open()
  }

  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() {
      popoutSwitchClosing = false
    })
  }
}
