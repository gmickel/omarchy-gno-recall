import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Nested bar-anchored health panel. Not a manifest panel kind — BarWidget
// loads this via Loader. manageIpc must stay false so the plugin id's
// shell-toggle IPC remains the overlay's.
Panel {
  id: root
  moduleName: "gmickel.gno-recall"
  ipcTarget: ""
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null

  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.popups.text
  readonly property color dim: Qt.darker(contentForeground, 1.4)
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string serviceState: service ? String(service.state || "") : "loading"
  readonly property var liveSnapshot: service ? service.snapshot : null
  readonly property var lastGood: service ? service.lastGoodSnapshot : null
  readonly property bool isStale: service ? service.stale === true : false
  readonly property var displaySnapshot: liveSnapshot ? liveSnapshot : lastGood
  readonly property bool initialized: !!(displaySnapshot && displaySnapshot.initialized === true)
  readonly property int documentCount: countValue("documents")
  readonly property int collectionCount: countValue("collections")
  readonly property int pendingCount: backlogValue("pending")
  readonly property int failedCount: backlogValue("failed")
  readonly property var recentRows: recentList()
  readonly property bool serveRunning: !!(displaySnapshot && displaySnapshot.serve && displaySnapshot.serve.running === true)
  readonly property string serveUrl: serveRunning && displaySnapshot.serve && displaySnapshot.serve.url
    ? String(displaySnapshot.serve.url)
    : ""
  readonly property string bodyKind: resolveBodyKind()
  readonly property var cursorTargets: buildCursorTargets()

  property bool cursorActive: false
  property int cursorIndex: 0

  function open() {
    if (service && typeof service.refresh === "function")
      service.refresh()
    cursorActive = false
    cursorIndex = 0
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened)
        setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    cursorActive = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened)
      root.close()
    else
      root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function countValue(field) {
    if (!displaySnapshot || !displaySnapshot.counts)
      return 0
    var n = parseInt(displaySnapshot.counts[field], 10)
    return isFinite(n) && n > 0 ? n : 0
  }

  function backlogValue(field) {
    if (!displaySnapshot || !displaySnapshot.backlog)
      return 0
    var n = parseInt(displaySnapshot.backlog[field], 10)
    return isFinite(n) && n > 0 ? n : 0
  }

  function recentList() {
    if (!displaySnapshot || !displaySnapshot.recent || !displaySnapshot.recent.length)
      return []
    var rows = []
    var source = displaySnapshot.recent
    var limit = Math.min(source.length, 10)
    for (var i = 0; i < limit; i++) {
      if (source[i])
        rows.push(source[i])
    }
    return rows
  }

  function resolveBodyKind() {
    if (displaySnapshot && displaySnapshot.initialized === false)
      return "uninitialized"
    if (displaySnapshot && displaySnapshot.initialized === true && documentCount === 0)
      return "empty"
    if (displaySnapshot && displaySnapshot.initialized === true)
      return "index"
    if (serviceState === "loading")
      return "loading"
    return "plugin-error"
  }

  function healthLabel() {
    var st = serviceState
    if (st === "ready")
      return "Ready"
    if (st === "loading")
      return "Loading"
    if (st === "not-found" || st === "not-executable" || st === "unknown-command" || st === "version-skew")
      return "Setup needed"
    if (st === "timeout" || st === "malformed-json" || st === "spawn-failure" || st === "runtime-error")
      return "Degraded"
    return st !== "" ? st : "Unknown"
  }

  function healthLine() {
    var detail = service && service.message ? String(service.message) : ""
    var line = healthLabel()
    if (detail !== "")
      line += " — " + detail
    if (isStale)
      line += " · stale " + cacheAgeLabel()
    return line
  }

  function cacheStamp() {
    if (service && service.lastPeekAt)
      return String(service.lastPeekAt)
    if (displaySnapshot && displaySnapshot.generatedAt)
      return String(displaySnapshot.generatedAt)
    return ""
  }

  function cacheAgeLabel() {
    var rel = relativeTime(cacheStamp())
    return rel !== "" ? rel : "last good snapshot"
  }

  function relativeTime(value) {
    var then = new Date(String(value || "")).getTime()
    if (!isFinite(then))
      return ""
    var seconds = Math.max(0, Math.floor((Date.now() - then) / 1000))
    if (seconds < 60)
      return "just now"
    if (seconds < 3600)
      return Math.floor(seconds / 60) + "m ago"
    if (seconds < 86400)
      return Math.floor(seconds / 3600) + "h ago"
    if (seconds < 2592000)
      return Math.floor(seconds / 86400) + "d ago"
    return Math.floor(seconds / 2592000) + "mo ago"
  }

  function formatStamp(value) {
    var rel = relativeTime(value)
    if (rel !== "")
      return rel
    var text = String(value || "")
    return text !== "" ? text : "—"
  }

  function uriTail(uri) {
    var value = String(uri || "")
    if (value === "")
      return ""
    var slash = value.lastIndexOf("/")
    var tail = slash >= 0 ? value.slice(slash + 1) : value
    try {
      tail = decodeURIComponent(tail)
    } catch (error) {
    }
    return tail
  }

  function recentTitle(row) {
    var title = row && row.title !== undefined && row.title !== null ? String(row.title).trim() : ""
    if (title !== "")
      return title
    var tail = uriTail(row ? row.uri : "")
    return tail !== "" ? tail : "(untitled)"
  }

  function recentDetail(row) {
    var collection = row && row.collection ? String(row.collection) : ""
    var modified = formatStamp(row ? row.modifiedAt : "")
    if (collection !== "" && modified !== "—")
      return collection + " · " + modified
    if (collection !== "")
      return collection
    return modified
  }

  function bodyCopy() {
    if (bodyKind === "uninitialized")
      return "GNO is not initialized yet.\n\nRun gno init in a terminal, then middle-click this widget to refresh."
    if (bodyKind === "empty")
      return "The index is empty.\n\nAdd documents to a GNO collection so Recall has something to show."
    if (bodyKind === "loading")
      return "Loading GNO index status…"
    if (bodyKind === "plugin-error") {
      var detail = service && service.message ? String(service.message) : ""
      return "Could not read the GNO index."
        + (detail !== "" ? "\n\n" + detail : "")
        + "\n\nSet Path to gno in the widget settings, or install gno >= 1.36.0 on PATH."
    }
    return ""
  }

  function buildCursorTargets() {
    var targets = []
    targets.push({ kind: "webui", index: -1 })
    targets.push({ kind: "recall", index: -1 })
    for (var i = 0; i < recentRows.length; i++)
      targets.push({ kind: "recent", index: i })
    return targets
  }

  function selectedTarget() {
    if (cursorTargets.length === 0)
      return null
    return cursorTargets[Math.max(0, Math.min(cursorIndex, cursorTargets.length - 1))]
  }

  function selectedKind() {
    var target = selectedTarget()
    return target ? target.kind : ""
  }

  function selectedRecentIndex() {
    var target = selectedTarget()
    return target && target.kind === "recent" ? target.index : -1
  }

  function selectKind(kind, index) {
    for (var i = 0; i < cursorTargets.length; i++) {
      var target = cursorTargets[i]
      if (target.kind === kind && (index === undefined || target.index === index)) {
        cursorActive = true
        cursorIndex = i
        return
      }
    }
  }

  function ensureCursor() {
    if (cursorTargets.length === 0) {
      cursorIndex = 0
      return
    }
    cursorIndex = Math.max(0, Math.min(cursorIndex, cursorTargets.length - 1))
  }

  function moveCursor(delta) {
    cursorActive = true
    if (cursorTargets.length === 0)
      return
    cursorIndex = Math.max(0, Math.min(cursorTargets.length - 1, cursorIndex + delta))
  }

  function activateCursor() {
    var target = selectedTarget()
    if (!target)
      return
    if (target.kind === "webui")
      openWebUi()
    else if (target.kind === "recall")
      summonOverlay()
  }

  function openWebUi() {
    if (!serveRunning || serveUrl === "")
      return
    Qt.openUrlExternally(serveUrl)
  }

  function summonOverlay() {
    root.close()
    if (root.bar && root.bar.shell && typeof root.bar.shell.toggle === "function") {
      root.bar.shell.toggle("gmickel.gno-recall", "{}")
      return
    }
    if (root.bar && typeof root.bar.run === "function")
      root.bar.run("omarchy-shell shell toggle gmickel.gno-recall")
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      if (panelFlick)
        panelFlick.contentY = 0
      Qt.callLater(function() {
        if (keyCatcher)
          keyCatcher.forceActiveFocus()
      })
    }
  }
  onCursorTargetsChanged: ensureCursor()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        if (dy !== 0)
          root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: content
          width: panelFlick.width
          spacing: Style.space(12)

          Text {
            width: parent.width
            text: "GNO RECALL"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            width: parent.width
            text: root.healthLine()
            color: root.isStale || root.bodyKind === "plugin-error" ? Color.urgent : root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.isStale
            width: parent.width
            text: "Showing last good snapshot · " + root.cacheAgeLabel()
            color: Color.urgent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Row {
            visible: root.bodyKind === "index" || root.bodyKind === "empty"
            width: parent.width
            spacing: Style.space(24)

            Column {
              spacing: Style.space(4)
              Text {
                text: "DOCUMENTS"
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }
              Text {
                text: String(root.documentCount)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }
            }

            Column {
              spacing: Style.space(4)
              Text {
                text: "COLLECTIONS"
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }
              Text {
                text: String(root.collectionCount)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }
            }

            Column {
              spacing: Style.space(4)
              Text {
                text: "BACKLOG"
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }
              Text {
                text: root.pendingCount + " pending · " + root.failedCount + " failed"
                color: root.failedCount > 0 ? Color.urgent : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          Text {
            visible: root.bodyKind === "index" || root.bodyKind === "empty"
            width: parent.width
            text: "Last indexed " + root.formatStamp(root.displaySnapshot ? root.displaySnapshot.lastIndexedAt : "")
            color: root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: root.bodyKind !== "index"
            width: parent.width
            text: root.bodyCopy()
            color: root.bodyKind === "plugin-error" ? Color.urgent : root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          PanelSeparator {
            foreground: root.contentForeground
          }

          Column {
            width: parent.width
            spacing: Style.space(8)

            Button {
              width: parent.width
              text: root.serveRunning
                ? "Open GNO web UI"
                : "Open GNO web UI — start: gno serve --detach"
              enabled: root.serveRunning
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              fontSize: Style.font.caption
              hasCursor: root.cursorActive && root.selectedKind() === "webui"
              onClicked: root.openWebUi()
              onHovered: function(isHovered) {
                if (isHovered)
                  root.selectKind("webui")
              }
            }

            Text {
              visible: !root.serveRunning
              width: parent.width
              text: "Web UI is down. The plugin never starts gno serve."
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              visible: root.serveRunning && root.serveUrl !== ""
              width: parent.width
              text: root.serveUrl
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }

            Button {
              width: parent.width
              text: "Recall search"
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              fontSize: Style.font.caption
              hasCursor: root.cursorActive && root.selectedKind() === "recall"
              onClicked: root.summonOverlay()
              onHovered: function(isHovered) {
                if (isHovered)
                  root.selectKind("recall")
              }
            }
          }

          PanelSeparator {
            visible: root.bodyKind === "index" && root.recentRows.length > 0
            foreground: root.contentForeground
          }

          PanelSectionHeader {
            visible: root.bodyKind === "index"
            width: parent.width
            text: "RECENT  " + root.recentRows.length
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Column {
            visible: root.bodyKind === "index"
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: root.recentRows

              CursorSurface {
                required property var modelData
                required property int index
                width: parent.width
                implicitHeight: recentColumn.implicitHeight + Style.space(10)
                foreground: root.contentForeground
                hasCursor: root.cursorActive && root.selectedKind() === "recent" && root.selectedRecentIndex() === index

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.ArrowCursor
                  onEntered: root.selectKind("recent", index)
                  onClicked: root.selectKind("recent", index)
                }

                Column {
                  id: recentColumn
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    text: root.recentTitle(modelData)
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: root.recentDetail(modelData)
                    color: root.dim
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
