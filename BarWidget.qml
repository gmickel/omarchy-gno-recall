import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "gmickel.gno-recall"

  property var recallService: null

  readonly property string glyphHistory: "\uf1da"
  readonly property string glyphSetup: "\uf059"
  readonly property string glyphInit: "\uf067"
  readonly property string glyphDegraded: "\uf071"
  readonly property string markPending: "\u25CF"
  readonly property string markFailed: "\u25C6"
  readonly property string markStale: "~"

  readonly property string serviceState: recallService ? String(recallService.state || "") : "loading"
  readonly property var liveSnapshot: recallService ? recallService.snapshot : null
  readonly property var lastGood: recallService ? recallService.lastGoodSnapshot : null
  readonly property bool isStale: recallService ? recallService.stale === true : false
  readonly property var displaySnapshot: liveSnapshot ? liveSnapshot : lastGood

  readonly property int pendingCount: backlogCount("pending")
  readonly property int failedCount: backlogCount("failed")
  readonly property string visualKind: resolveVisualKind()
  readonly property string glyphChar: glyphForKind(visualKind)
  readonly property string markerText: markerForKind(visualKind)
  readonly property string buttonText: root.vertical && root.markerText !== ""
    ? root.glyphChar + "\n" + root.markerText
    : (root.markerText !== "" ? root.glyphChar + " " + root.markerText : root.glyphChar)
  readonly property color glyphColor: colorForKind(visualKind)
  readonly property string tooltipText: tooltipForKind(visualKind)
  readonly property bool urgentVisual: visualKind === "degraded" || visualKind === "backlog-failed"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function bindService() {
    if (!bar || !bar.shell || typeof bar.shell.serviceFor !== "function")
      return
    var svc = bar.shell.serviceFor("gmickel.gno-recall")
    if (!svc)
      return
    recallService = svc
    svc.settings = settings
    svc.panelOpened = opened
  }

  // Nested KeyboardPanel identity: the bar's popout coordinator and
  // switchPanelFrom compare against this widget, so hostWidget is the
  // slot identity. manageIpc stays false on Panel.qml — overlay owns
  // `omarchy-shell shell toggle gmickel.gno-recall`.
  function injectPanel() {
    var target = panelLoader.item
    if (!target)
      return
    if ("bar" in target)
      target.bar = root.bar
    if ("settings" in target)
      target.settings = root.settings
    if ("service" in target)
      target.service = root.recallService
    if ("anchorItem" in target)
      target.anchorItem = button
    if ("hostWidget" in target)
      target.hostWidget = root
  }

  function open() {
    if (panelLoader.item && panelLoader.item.open)
      panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close)
      panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item && panelLoader.item.toggle)
      panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item && panelLoader.item.closeForPopoutSwitch)
      panelLoader.item.closeForPopoutSwitch()
  }

  function refresh() {
    if (recallService && typeof recallService.refresh === "function")
      recallService.refresh()
  }

  function formatCount(value) {
    var n = parseInt(value, 10)
    if (!isFinite(n) || n <= 0)
      return ""
    return n > 99 ? "99+" : String(n)
  }

  function backlogCount(field) {
    var snap = displaySnapshot
    if (!snap || snap.initialized !== true || !snap.backlog)
      return 0
    var n = parseInt(snap.backlog[field], 10)
    return isFinite(n) && n > 0 ? n : 0
  }

  function resolveVisualKind() {
    var st = serviceState
    if (st === "ready" && displaySnapshot && displaySnapshot.initialized === false)
      return "init-guidance"
    if (st === "not-found" || st === "not-executable" || st === "version-skew" || st === "unknown-command"
        || st === "runtime-error" || st === "timeout" || st === "malformed-json" || st === "spawn-failure") {
      if (isStale && lastGood && lastGood.initialized === true)
        return lastGood.backlog && parseInt(lastGood.backlog.failed, 10) > 0
          ? "backlog-failed"
          : (lastGood.backlog && parseInt(lastGood.backlog.pending, 10) > 0 ? "backlog-pending" : "stale")
      if (isStale && lastGood && lastGood.initialized === false)
        return "init-guidance"
      if (st === "not-found" || st === "not-executable" || st === "version-skew" || st === "unknown-command")
        return "setup-guidance"
      return "degraded"
    }
    if (st === "loading" && !displaySnapshot)
      return "loading"
    if (displaySnapshot && displaySnapshot.initialized === true) {
      if (failedCount > 0)
        return "backlog-failed"
      if (pendingCount > 0)
        return "backlog-pending"
      if (isStale)
        return "stale"
      return "healthy"
    }
    return st === "loading" ? "loading" : "degraded"
  }

  function glyphForKind(kind) {
    if (kind === "setup-guidance")
      return glyphSetup
    if (kind === "init-guidance")
      return glyphInit
    if (kind === "degraded")
      return glyphDegraded
    return glyphHistory
  }

  function markerForKind(kind) {
    var failed = formatCount(failedCount)
    var pending = formatCount(pendingCount)
    if (kind === "backlog-failed")
      return markFailed + failed + (isStale ? markStale : "")
    if (kind === "backlog-pending")
      return markPending + pending + (isStale ? markStale : "")
    if (kind === "stale")
      return markStale
    return ""
  }

  function colorForKind(kind) {
    if (kind === "degraded" || kind === "backlog-failed")
      return Color.urgent
    if (kind === "setup-guidance" || kind === "init-guidance" || kind === "stale" || kind === "loading" || kind === "backlog-pending")
      return Color.muted
    return root.bar ? root.bar.barForeground : Color.foreground
  }

  function tooltipForKind(kind) {
    var detail = recallService && recallService.message ? String(recallService.message) : ""
    if (kind === "healthy")
      return "GNO Recall — index ready"
    if (kind === "loading")
      return "GNO Recall — loading"
    if (kind === "backlog-pending")
      return "GNO Recall — " + pendingCount + " chunks waiting to embed"
        + (isStale ? " (stale snapshot)" : "")
    if (kind === "backlog-failed")
      return "GNO Recall — " + failedCount + " recent ingest errors"
        + (pendingCount > 0 ? "; " + pendingCount + " chunks waiting" : "")
        + (isStale ? " (stale snapshot)" : "")
    if (kind === "stale")
      return "GNO Recall — showing last good snapshot (refresh failed)"
        + (detail !== "" ? ": " + detail : "")
    if (kind === "setup-guidance")
      return "GNO Recall — set up gno" + (detail !== "" ? ": " + detail : "")
    if (kind === "init-guidance")
      return "GNO Recall — run gno init"
    if (kind === "degraded")
      return "GNO Recall — degraded" + (detail !== "" ? ": " + detail : "")
    return "GNO Recall"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: {
    bindService()
    injectPanel()
  }
  onSettingsChanged: {
    if (recallService) {
      recallService.settings = settings
      recallService.refresh()
    } else {
      bindService()
    }
    injectPanel()
  }
  onRecallServiceChanged: injectPanel()
  onOpenedChanged: {
    if (recallService)
      recallService.panelOpened = opened
    console.info("gmickel.gno-recall: panel " + (opened ? "opened" : "closed")
      + " (left-click toggles nested loader, not overlay)")
  }

  Component.onCompleted: {
    bindService()
    injectPanel()
  }

  Timer {
    interval: 400
    repeat: true
    running: root.recallService === null
    onTriggered: root.bindService()
  }

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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.buttonText
    foreground: root.glyphColor
    active: root.urgentVisual
    useActiveColor: root.urgentVisual
    tooltipText: root.tooltipText
    horizontalMargin: root.markerText !== "" && !root.vertical ? 8.75 : 8.5
    fixedHeight: root.vertical && root.markerText !== "" ? Style.bar.iconSlot * 2 : -1

    onPressed: function(b) {
      if (!root.bar)
        return
      if (b === Qt.MiddleButton)
        root.refresh()
      else if (b === Qt.LeftButton)
        root.toggle()
    }
  }
}
