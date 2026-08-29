import QtQuick
import Quickshell
import Quickshell.Hyprland
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

  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property var targetScreen: null

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(720), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(72), Style.font.body + Style.font.caption * 2 + Style.spacing.rowPaddingX * 3)

  readonly property string pluginId: (manifest && manifest.id) ? String(manifest.id) : "gmickel.gno-recall"
  readonly property var liveSnapshot: service ? service.snapshot : null
  readonly property var lastGood: service ? service.lastGoodSnapshot : null
  readonly property var displaySnapshot: liveSnapshot ? liveSnapshot : lastGood
  readonly property bool isStale: service ? service.stale === true : false
  readonly property string searchState: service ? String(service.searchState || "idle") : "idle"
  readonly property bool searchLoading: service ? service.searchLoading === true : false
  readonly property string searchQuery: service ? String(service.searchQuery || "") : ""
  readonly property string searchMessage: service ? String(service.searchMessage || "") : ""
  readonly property int searchGenerationId: service ? (service.searchGenerationId || 0) : 0
  readonly property int searchHitCount: service ? (service.searchHitCount || 0) : 0
  readonly property bool showingSearch: filterText.trim() !== ""
    && filterText.trim() === searchQuery
    && (searchState === "ready" || searchState === "empty" || searchState === "error" || searchState === "timeout" || searchState === "loading")
  readonly property string emptyKind: resolveEmptyKind()
  readonly property string statusLine: resolveStatusLine()
  readonly property string actionStatus: service ? String(service.actionStatus || "") : ""

  function open(payloadJson) {
    root.targetScreen = root.resolveFocusedScreen()
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    if (service && typeof service.cancelSearch === "function")
      service.cancelSearch("open")
    root.rebuildDisplay()
    Qt.callLater(function() {
      if (keyCatcher)
        keyCatcher.forceActiveFocus()
    })
    console.info("gmickel.gno-recall: overlay opened screen="
      + (root.targetScreen ? String(root.targetScreen.name || "") : "(default)")
      + " stale=" + root.isStale
      + " recents=" + root.cachedRecents().length)
  }

  function close() {
    root.opened = false
    if (service && typeof service.cancelSearch === "function")
      service.cancelSearch("close")
  }

  function dismiss() {
    root.opened = false
    if (service && typeof service.cancelSearch === "function")
      service.cancelSearch("dismiss")
    if (shell && typeof shell.hide === "function") {
      shell.hide(root.pluginId)
      return
    }
    console.warn("gmickel.gno-recall: shell hide unavailable; overlay closed locally, bar/panel stay usable")
  }

  function toggle() {
    if (opened)
      dismiss()
    else
      open("{}")
  }

  function resolveFocusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    var screens = Quickshell.screens || []
    if (name !== "") {
      for (var i = 0; i < screens.length; i++) {
        if (String(screens[i].name || "") === name)
          return screens[i]
      }
    }
    return screens.length > 0 ? screens[0] : null
  }

  function cachedRecents() {
    var snap = displaySnapshot
    if (!snap || !snap.recent || !snap.recent.length)
      return []
    var rows = []
    for (var i = 0; i < snap.recent.length; i++) {
      if (snap.recent[i])
        rows.push(snap.recent[i])
    }
    return rows
  }

  function uriTail(uri) {
    var value = String(uri || "")
    if (value === "")
      return ""
    var q = value.indexOf("?")
    if (q >= 0)
      value = value.slice(0, q)
    var slash = value.lastIndexOf("/")
    var tail = slash >= 0 ? value.slice(slash + 1) : value
    try {
      tail = decodeURIComponent(tail)
    } catch (error) {
    }
    return tail
  }

  function collectionFromUri(uri) {
    var value = String(uri || "")
    if (value.indexOf("gno://") !== 0)
      return ""
    var rest = value.slice(6)
    var slash = rest.indexOf("/")
    return slash >= 0 ? rest.slice(0, slash) : rest
  }

  function rowTitle(row) {
    var title = row && row.title !== undefined && row.title !== null ? String(row.title).trim() : ""
    if (title !== "")
      return title
    var tail = uriTail(row ? row.uri : "")
    return tail !== "" ? tail : "(untitled)"
  }

  function rowCollection(row, kind) {
    if (kind === "recent" && row && row.collection)
      return String(row.collection)
    return collectionFromUri(row ? row.uri : "")
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
    return text !== "" ? text : ""
  }

  function rowMatchesFilter(row, needle) {
    if (needle === "")
      return true
    var title = rowTitle(row).toLowerCase()
    var tail = uriTail(row ? row.uri : "").toLowerCase()
    var uri = String(row && row.uri ? row.uri : "").toLowerCase()
    return title.indexOf(needle) !== -1 || tail.indexOf(needle) !== -1 || uri.indexOf(needle) !== -1
  }

  function normalizeRecent(row) {
    return {
      kind: "recent",
      docid: String(row && row.docid ? row.docid : ""),
      uri: String(row && row.uri ? row.uri : ""),
      title: rowTitle(row),
      collection: rowCollection(row, "recent"),
      snippet: "",
      modifiedAt: row && row.modifiedAt ? String(row.modifiedAt) : "",
      absPath: row && row.absPath ? String(row.absPath) : ""
    }
  }

  function normalizeSearch(row) {
    return {
      kind: "search",
      docid: String(row && row.docid ? row.docid : ""),
      uri: String(row && row.uri ? row.uri : ""),
      title: rowTitle(row),
      collection: row && row.collection ? String(row.collection) : collectionFromUri(row ? row.uri : ""),
      snippet: row && row.snippet ? String(row.snippet) : "",
      modifiedAt: row && row.modifiedAt ? String(row.modifiedAt) : "",
      absPath: row && row.absPath ? String(row.absPath) : ""
    }
  }

  function resolveEmptyKind() {
    if (showingSearch) {
      if (searchState === "timeout")
        return "search-timeout"
      if (searchState === "error")
        return "search-error"
      if (searchState === "empty")
        return "search-empty"
      if (searchState === "loading")
        return "search-loading"
      return ""
    }
    var snap = displaySnapshot
    if (snap && snap.initialized === false)
      return "uninitialized"
    if (snap && snap.initialized === true) {
      var docs = snap.counts && snap.counts.documents !== undefined ? parseInt(snap.counts.documents, 10) : 0
      if ((!isFinite(docs) || docs === 0) && cachedRecents().length === 0)
        return "empty-index"
    }
    if (filterText.trim() !== "" && displayModel.count === 0)
      return "filter-empty"
    if (!snap && (!service || String(service.state || "") === "loading"))
      return "loading"
    if (!snap)
      return "plugin-error"
    return ""
  }

  function resolveStatusLine() {
    if (actionStatus !== "")
      return actionStatus
    if (isStale)
      return "Showing last good snapshot"
    if (showingSearch && searchState === "loading")
      return "Searching…"
    if (showingSearch && searchState === "ready")
      return searchHitCount + " results"
    if (showingSearch && searchState === "empty")
      return "No results"
    if (showingSearch && (searchState === "error" || searchState === "timeout"))
      return searchMessage !== "" ? searchMessage : (searchState === "timeout" ? "Search timed out" : "Search failed")
    if (filterText.trim() !== "")
      return "Filtered recents — Enter to search"
    var recents = cachedRecents().length
    return recents > 0 ? recents + " recent · Enter file · Ctrl+Enter web" : ""
  }

  function emptyCopy() {
    if (emptyKind === "uninitialized")
      return "GNO is not initialized yet.\n\nRun gno init in a terminal, then summon Recall again."
    if (emptyKind === "empty-index")
      return "The index is empty.\n\nAdd documents to a GNO collection so Recall has something to search."
    if (emptyKind === "filter-empty")
      return "No matches for “" + filterText + "”\n\nEnter searches the full index."
    if (emptyKind === "search-empty")
      return "No results for “" + searchQuery + "”"
    if (emptyKind === "search-timeout")
      return "Search timed out.\n\nThe overlay is still open — edit the query and press Enter to try again."
    if (emptyKind === "search-error")
      return "Search failed"
        + (searchMessage !== "" ? "\n\n" + searchMessage : "")
        + "\n\nThe overlay is still open — edit the query and press Enter to try again."
    if (emptyKind === "search-loading")
      return "Searching…"
    if (emptyKind === "loading")
      return "Loading GNO index status…"
    if (emptyKind === "plugin-error") {
      var detail = service && service.message ? String(service.message) : ""
      return "Could not read the GNO index."
        + (detail !== "" ? "\n\n" + detail : "")
        + "\n\nSet Path to gno in the widget settings, or install gno >= 1.36.0 on PATH."
    }
    return ""
  }

  function rebuildDisplay() {
    displayModel.clear()
    var rows = []
    if (showingSearch && (searchState === "ready" || searchState === "empty")) {
      var hits = service && service.searchResults ? service.searchResults : []
      for (var i = 0; i < hits.length; i++) {
        if (hits[i])
          rows.push(normalizeSearch(hits[i]))
      }
    } else if (!showingSearch || searchState === "idle") {
      var needle = filterText.trim().toLowerCase()
      var recents = cachedRecents()
      for (var r = 0; r < recents.length; r++) {
        if (rowMatchesFilter(recents[r], needle))
          rows.push(normalizeRecent(recents[r]))
      }
    }

    for (var n = 0; n < rows.length; n++)
      displayModel.append(rows[n])

    if (displayModel.count === 0)
      selectedIndex = 0
    else if (selectedIndex >= displayModel.count)
      selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0)
      selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0 && resultList)
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function setFilter(nextFilter) {
    var next = String(nextFilter || "")
    if (next === root.filterText)
      return
    root.filterText = next
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    if (service && typeof service.cancelSearch === "function" && service.searchLoading === true)
      service.cancelSearch("query-changed")
    root.rebuildDisplay()
  }

  function commitSearch() {
    var q = root.filterText.trim()
    if (q === "")
      return
    if (!service || typeof service.runSearch !== "function")
      return
    root.cursorActive = true
    root.selectedIndex = 0
    service.runSearch(q)
    root.rebuildDisplay()
  }

  function select(delta) {
    if (displayModel.count === 0)
      return
    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (displayModel.count === 0)
      return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse))
      return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function rowAt(index) {
    if (index < 0 || index >= displayModel.count)
      return null
    return displayModel.get(index)
  }

  function activateIndex(index) {
    var row = rowAt(index)
    if (!row || !service || typeof service.openSourceFile !== "function")
      return
    service.openSourceFile(row.absPath)
  }

  function openWebAt(index) {
    var row = rowAt(index)
    if (!row || !service || typeof service.openWebUi !== "function")
      return
    service.openWebUi(row.uri)
  }

  function openSelectedFile(arg) {
    activateIndex(root.selectedIndex)
    return peekState(arg)
  }

  function openSelectedWeb(arg) {
    openWebAt(root.selectedIndex)
    return peekState(arg)
  }

  function refresh(arg) {
    if (service && typeof service.refresh === "function")
      service.refresh()
    return peekState(arg)
  }

  function setFileOpener(path) {
    if (service && typeof service.setFileOpener === "function")
      return service.setFileOpener(path)
    return "no-service"
  }

  function setBrowserOpener(path) {
    if (service && typeof service.setBrowserOpener === "function")
      return service.setBrowserOpener(path)
    return service ? "no-method" : "no-service"
  }

  function injectMissingAbsPathRow(arg) {
    displayModel.insert(0, {
      kind: "recent",
      docid: "qa-no-abspath",
      uri: "gno://qa/missing-abspath.md",
      title: "QA missing absPath",
      collection: "qa",
      snippet: "",
      modifiedAt: "",
      absPath: ""
    })
    root.selectedIndex = 0
    root.cursorActive = true
    return peekState(arg)
  }

  function peekState(arg) {
    var base = {}
    if (service && typeof service.debugSnapshot === "function") {
      try {
        base = JSON.parse(service.debugSnapshot())
      } catch (error) {
        base = { error: "debug-parse-failed" }
      }
    } else if (!service) {
      base = { error: "service-unavailable" }
    }
    var first = displayModel.count > 0 ? displayModel.get(0) : null
    var selected = rowAt(root.selectedIndex)
    base.overlayOpened = root.opened
    base.panelOpened = service ? service.panelOpened === true : false
    base.filterText = root.filterText
    base.showingSearch = root.showingSearch
    base.emptyKind = root.emptyKind
    base.selectedIndex = root.selectedIndex
    base.rowCount = displayModel.count
    base.firstUri = first ? String(first.uri || "") : ""
    base.firstTitle = first ? String(first.title || "") : ""
    base.firstAbsPath = first ? String(first.absPath || "") : ""
    base.selectedUri = selected ? String(selected.uri || "") : ""
    base.selectedAbsPath = selected ? String(selected.absPath || "") : ""
    base.selectedCanOpenFile = selected ? String(selected.absPath || "").trim() !== "" : false
    base.fileOpenDisabled = selected ? String(selected.absPath || "").trim() === "" : false
    base.webDocUrl = service && typeof service.webDocUrl === "function" && selected
      ? service.webDocUrl(selected.uri)
      : ""
    base.targetScreen = root.targetScreen ? String(root.targetScreen.name || "") : ""
    return JSON.stringify(base)
  }

  onDisplaySnapshotChanged: if (opened) rebuildDisplay()
  onSearchStateChanged: if (opened) rebuildDisplay()
  onSearchGenerationIdChanged: if (opened) rebuildDisplay()
  onSearchHitCountChanged: if (opened) rebuildDisplay()

  ListModel { id: displayModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.targetScreen
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    WlrLayershell.namespace: "gmickel-gno-recall"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText)
              root.setFilter("")
            else
              root.dismiss()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if ((event.key === Qt.Key_J || event.key === Qt.Key_K) && root.filterText === "") {
            root.select(event.key === Qt.Key_J ? 1 : -1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectAbsolute(0)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectAbsolute(displayModel.count - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (event.modifiers & Qt.ControlModifier) {
              if (displayModel.count > 0)
                root.openWebAt(root.selectedIndex)
            } else if (displayModel.count > 0 && (root.showingSearch || root.filterText.trim() === "")) {
              root.activateIndex(root.selectedIndex)
            } else if (root.filterText.trim() !== "") {
              root.commitSearch()
            } else if (displayModel.count > 0) {
              root.activateIndex(root.selectedIndex)
            }
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Column {
          width: parent.width
          spacing: Style.space(4)

          Rectangle {
            width: parent.width
            height: root.headerHeight
            radius: root.cornerRadius
            color: "transparent"

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.filterText || "Recall recent documents…"
              color: root.foreground
              opacity: root.filterText ? 1 : 0.58
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              elide: Text.ElideRight
            }
          }

          Text {
            visible: root.statusLine !== ""
            width: parent.width
            text: root.statusLine
            color: root.actionStatus !== "" || root.isStale || root.emptyKind === "search-error" || root.emptyKind === "search-timeout"
              ? Color.urgent
              : root.foreground
            opacity: 0.72
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing
            - (root.statusLine !== "" ? Style.font.caption + Style.space(4) : 0)

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: Style.space(4)
            boundsBehavior: Flickable.StopAtBounds
            visible: displayModel.count > 0

            delegate: Rectangle {
              id: row
              required property int index
              required property string title
              required property string collection
              required property string snippet
              required property string modifiedAt
              required property string uri
              required property string kind
              required property string absPath

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
              readonly property bool canOpenFile: String(absPath || "").trim() !== ""
              readonly property string metaText: {
                var bits = []
                if (collection !== "")
                  bits.push(collection)
                var stamp = root.formatStamp(modifiedAt)
                if (stamp !== "")
                  bits.push(stamp)
                if (!canOpenFile)
                  bits.push("no file path")
                return bits.join(" · ")
              }

              width: ListView.view.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"

              Column {
                anchors.fill: parent
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.topMargin: Style.space(8)
                anchors.bottomMargin: Style.space(8)
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: row.title
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: row.canOpenFile ? 1 : 0.55
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  visible: row.metaText !== ""
                  text: row.metaText
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  visible: row.snippet !== ""
                  text: row.snippet.replace(/\s+/g, " ").trim()
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: 0.78
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  wrapMode: Text.NoWrap
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: row.canOpenFile ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPositionChanged: function(mouse) {
                  root.selectFromPointer(row.index, row, mouse)
                }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index)
                }
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            width: parent.width - Style.space(32)
            visible: displayModel.count === 0

            Text {
              width: parent.width
              text: root.emptyCopy()
              color: root.emptyKind === "search-error" || root.emptyKind === "search-timeout" || root.emptyKind === "plugin-error"
                ? Color.urgent
                : root.foreground
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }
    }
  }
}
