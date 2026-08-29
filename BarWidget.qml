import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "gmickel.gno-recall"

  property var recallService: null

  function bindService() {
    if (!bar || !bar.shell || typeof bar.shell.serviceFor !== "function")
      return
    var svc = bar.shell.serviceFor("gmickel.gno-recall")
    if (!svc)
      return
    recallService = svc
    svc.settings = settings
  }

  onBarChanged: bindService()
  onSettingsChanged: {
    if (recallService)
      recallService.settings = settings
    else
      bindService()
  }

  implicitWidth: vertical ? barSize : glyph.implicitWidth + Style.space(14)
  implicitHeight: vertical ? glyph.implicitHeight + Style.space(10) : barSize

  Component.onCompleted: bindService()

  Timer {
    interval: 400
    repeat: true
    running: root.recallService === null
    onTriggered: root.bindService()
  }

  Text {
    id: glyph
    anchors.centerIn: parent
    text: "\uf1da"
    color: root.bar ? root.bar.barForeground : Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }
}
