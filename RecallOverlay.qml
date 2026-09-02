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
  property string browseLevel: "recents"
  readonly property string levelRecents: "recents"
  readonly property string levelCollections: "collections"
  readonly property string levelDocs: "docs"

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
  property int headerHeight: Math.max(Style.space(26), Style.font.heading + Style.space(4))
  property int contentSpacing: Style.spacing.sm
  property int cardWidth: Math.min(Style.space(720), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)
  property int rowPadY: Style.space(5)
  property int rowInnerSpacing: 1
  property int rowListSpacing: Style.space(2)
  readonly property int rowMinHeight: Style.font.title + Style.font.caption + rowInnerSpacing + rowPadY * 2

  readonly property string pluginId: (manifest && manifest.id) ? String(manifest.id) : "gmickel.gno-recall"
  readonly property var liveSnapshot: service ? service.snapshot : null
  readonly property var lastGood: service ? service.lastGoodSnapshot : null
  readonly property var displaySnapshot: liveSnapshot ? liveSnapshot : lastGood
  readonly property bool isStale: service ? service.stale === true : false
  readonly property string searchState: service ? String(service.searchState || "idle") : "idle"
  readonly property bool searchLoading: service ? service.searchLoading === true : false
  readonly property string searchQuery: service ? String(service.searchQuery || "") : ""
  readonly property string searchMode: service ? String(service.searchMode || "") : ""
  readonly property string searchMessage: service ? String(service.searchMessage || "") : ""
  readonly property int searchGenerationId: service ? (service.searchGenerationId || 0) : 0
  readonly property int searchHitCount: service ? (service.searchHitCount || 0) : 0
  readonly property bool inBrowse: browseLevel === levelCollections || browseLevel === levelDocs
  readonly property string collectionsState: service ? String(service.collectionsState || "idle") : "idle"
  readonly property bool collectionsLoading: service ? service.collectionsLoading === true : false
  readonly property string collectionsMessage: service ? String(service.collectionsMessage || "") : ""
  readonly property int collectionsGenerationId: service ? (service.collectionsGenerationId || 0) : 0
  readonly property string lsState: service ? String(service.lsState || "idle") : "idle"
  readonly property bool lsLoading: service ? service.lsLoading === true : false
  readonly property string lsMessage: service ? String(service.lsMessage || "") : ""
  readonly property int lsGenerationId: service ? (service.lsGenerationId || 0) : 0
  readonly property string lsCollection: service ? String(service.lsCollection || "") : ""
  readonly property int lsDocumentCount: service ? (service.lsDocumentCount || 0) : 0
  readonly property bool lsHasMore: service ? service.lsHasMore === true : false
  readonly property int lsRowCount: service && service.lsDocuments ? service.lsDocuments.length : 0
  readonly property int lsPageSize: service ? (service.lsPageSize || 50) : 50
  readonly property bool showingSearch: browseLevel === levelRecents
    && filterText.trim() !== ""
    && filterText.trim() === searchQuery
    && (searchState === "ready" || searchState === "empty" || searchState === "error" || searchState === "timeout" || searchState === "loading")
  readonly property string emptyKind: resolveEmptyKind()
  readonly property string statusLine: resolveStatusLine()
  readonly property string actionStatus: service ? String(service.actionStatus || "") : ""

  function parsePayload(payloadJson) {
    var text = String(payloadJson || "").trim()
    if (text === "" || text === "{}")
      return ({})
    try {
      var value = JSON.parse(text)
      return value && typeof value === "object" ? value : ({})
    } catch (error) {
      return ({})
    }
  }

  function open(payloadJson) {
    root.targetScreen = root.resolveFocusedScreen()
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    if (service && typeof service.cancelSearch === "function")
      service.cancelSearch("open")
    var payload = root.parsePayload(payloadJson)
    if (String(payload.mode || "") === "collections")
      root.enterCollections("open-payload")
    else
      root.resetToRecents("open")
    root.rebuildDisplay()
    Qt.callLater(function() {
      if (keyCatcher)
        keyCatcher.forceActiveFocus()
    })
    console.info("gmickel.gno-recall: overlay opened screen="
      + (root.targetScreen ? String(root.targetScreen.name || "") : "(default)")
      + " stale=" + root.isStale
      + " recents=" + root.cachedRecents().length
      + " browseLevel=" + root.browseLevel
      + " payloadMode=" + String(payload.mode || ""))
  }

  function close() {
    root.opened = false
    if (service && typeof service.cancelSearch === "function")
      service.cancelSearch("close")
    if (service && typeof service.cancelLs === "function")
      service.cancelLs("close")
  }

  function dismiss() {
    root.opened = false
    if (service && typeof service.cancelSearch === "function")
      service.cancelSearch("dismiss")
    if (service && typeof service.cancelLs === "function")
      service.cancelLs("dismiss")
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

  function colorToHex(value) {
    var c = Qt.color(value)
    var r = Math.round(c.r * 255)
    var g = Math.round(c.g * 255)
    var b = Math.round(c.b * 255)
    function hex(n) {
      var s = n.toString(16)
      return s.length === 1 ? "0" + s : s
    }
    return "#" + hex(r) + hex(g) + hex(b)
  }

  function styleSnippet(raw, highlightColor) {
    var collapsed = String(raw || "").replace(/\s+/g, " ").trim()
    var budget = 240
    if (collapsed.length > budget) {
      // Drop any tag cut in half by the budget, then re-balance an
      // unterminated <mark> so the styled conversion below stays paired.
      collapsed = collapsed.slice(0, budget).replace(/<[^>]*$/, "")
      var opens = (collapsed.match(/<mark>/g) || []).length
      var closes = (collapsed.match(/<\/mark>/g) || []).length
      if (opens > closes)
        collapsed += "</mark>"
    }
    var escaped = collapsed
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
    var color = colorToHex(highlightColor || Color.accent)
    return escaped
      .replace(/&lt;mark&gt;/g, "<b><font color=\"" + color + "\">")
      .replace(/&lt;\/mark&gt;/g, "</font></b>")
  }

  function cacheAgeLabel() {
    if (service && typeof service.cacheAgeLabel === "function")
      return service.cacheAgeLabel()
    var stamp = ""
    if (service && service.lastSuccessfulRefreshAt)
      stamp = String(service.lastSuccessfulRefreshAt)
    else if (service && service.lastPeekAt)
      stamp = String(service.lastPeekAt)
    var rel = relativeTime(stamp)
    return rel !== "" ? rel : "last good snapshot"
  }

  function rowMatchesFilter(row, needle) {
    if (needle === "")
      return true
    var title = rowTitle(row).toLowerCase()
    var tail = uriTail(row ? row.uri : "").toLowerCase()
    var uri = String(row && row.uri ? row.uri : "").toLowerCase()
    var rel = String(row && row.relPath ? row.relPath : "").toLowerCase()
    var name = String(row && row.collection ? row.collection : "").toLowerCase()
    return title.indexOf(needle) !== -1
      || tail.indexOf(needle) !== -1
      || uri.indexOf(needle) !== -1
      || rel.indexOf(needle) !== -1
      || name.indexOf(needle) !== -1
  }

  function cachedCollections() {
    var rows = service && service.collections ? service.collections : []
    if ((!rows || rows.length === 0) && service && service.lastGoodCollections)
      rows = service.lastGoodCollections
    if (!rows || !rows.length)
      return []
    var out = []
    for (var i = 0; i < rows.length; i++) {
      if (rows[i])
        out.push(rows[i])
    }
    return out
  }

  function cachedBrowseDocs() {
    var rows = service && service.lsDocuments ? service.lsDocuments : []
    if (!rows || !rows.length)
      return []
    var out = []
    for (var i = 0; i < rows.length; i++) {
      if (rows[i])
        out.push(rows[i])
    }
    return out
  }

  function resetToRecents(reason) {
    root.browseLevel = root.levelRecents
    if (service && typeof service.cancelLs === "function")
      service.cancelLs(reason || "recents")
    console.info("gmickel.gno-recall: browse level=recents reason=" + String(reason || ""))
  }

  function enterCollections(reason) {
    root.browseLevel = root.levelCollections
    root.selectedIndex = 0
    root.cursorActive = true
    if (service && typeof service.cancelSearch === "function")
      service.cancelSearch("browse-collections")
    if (service && typeof service.cancelLs === "function")
      service.cancelLs("browse-collections")
    if (service && typeof service.runStatus === "function")
      service.runStatus()
    console.info("gmickel.gno-recall: browse level=collections reason=" + String(reason || "key"))
    root.rebuildDisplay()
  }

  function enterDocs(collectionName, reason) {
    var name = String(collectionName || "").trim()
    if (name === "")
      return
    root.browseLevel = root.levelDocs
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    if (service && typeof service.runLs === "function")
      service.runLs(name, 0)
    console.info("gmickel.gno-recall: browse level=docs collection=" + name
      + " reason=" + String(reason || "enter"))
    root.rebuildDisplay()
  }

  function loadMoreDocs() {
    if (!service || typeof service.runLs !== "function")
      return
    if (!root.lsHasMore || root.lsLoading)
      return
    var name = root.lsCollection
    if (name === "")
      return
    service.runLs(name, root.lsRowCount)
    console.info("gmickel.gno-recall: browse load-more collection=" + name
      + " offset=" + root.lsRowCount)
  }

  function goBackLevel() {
    if (root.browseLevel === root.levelDocs) {
      root.filterText = ""
      root.enterCollections("back")
      return true
    }
    if (root.browseLevel === root.levelCollections) {
      root.filterText = ""
      root.resetToRecents("back")
      root.rebuildDisplay()
      return true
    }
    return false
  }

  function handleEscape() {
    if (root.filterText) {
      root.setFilter("")
      return
    }
    if (root.goBackLevel())
      return
    root.dismiss()
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
      absPath: row && row.absPath ? String(row.absPath) : "",
      relPath: "",
      documentCount: 0,
      collectionPath: ""
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
      absPath: row && row.absPath ? String(row.absPath) : "",
      relPath: "",
      documentCount: 0,
      collectionPath: ""
    }
  }

  function normalizeCollection(row) {
    var count = row && row.documentCount !== undefined ? parseInt(row.documentCount, 10) : 0
    return {
      kind: "collection",
      docid: "",
      uri: "",
      title: String(row && row.name ? row.name : ""),
      collection: String(row && row.name ? row.name : ""),
      snippet: "",
      modifiedAt: "",
      absPath: "",
      relPath: "",
      documentCount: isFinite(count) ? count : 0,
      collectionPath: String(row && row.path ? row.path : "")
    }
  }

  function normalizeBrowse(row) {
    var title = rowTitle(row)
    var relPath = String(row && row.relPath ? row.relPath : "")
    return {
      kind: "browse",
      docid: String(row && row.docid ? row.docid : ""),
      uri: String(row && row.uri ? row.uri : ""),
      title: title,
      collection: String(row && row.collection ? row.collection : root.lsCollection),
      snippet: "",
      modifiedAt: "",
      absPath: String(row && row.absPath ? row.absPath : ""),
      relPath: relPath,
      documentCount: 0,
      collectionPath: String(row && row.collectionPath ? row.collectionPath : "")
    }
  }

  function loadMoreRow() {
    return {
      kind: "more",
      docid: "",
      uri: "",
      title: "Load more…",
      collection: root.lsCollection,
      snippet: "",
      modifiedAt: "",
      absPath: "",
      relPath: "",
      documentCount: 0,
      collectionPath: ""
    }
  }

  function resolveEmptyKind() {
    if (browseLevel === levelCollections) {
      if (collectionsState === "timeout")
        return "status-timeout"
      if (collectionsState === "error")
        return "status-error"
      if (collectionsState === "empty")
        return "collections-empty"
      if (collectionsState === "loading" && cachedCollections().length === 0)
        return "collections-loading"
      if (filterText.trim() !== "" && displayModel.count === 0)
        return "filter-empty"
      return ""
    }
    if (browseLevel === levelDocs) {
      if (lsState === "timeout")
        return "ls-timeout"
      if (lsState === "error")
        return "ls-error"
      if (lsState === "empty")
        return "collection-empty"
      if (lsState === "loading" && cachedBrowseDocs().length === 0)
        return "docs-loading"
      if (filterText.trim() !== "" && displayModel.count === 0)
        return "filter-empty"
      return ""
    }
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
    if (browseLevel === levelCollections) {
      if (collectionsState === "loading" && cachedCollections().length === 0)
        return "Loading collections…"
      if (collectionsState === "error" || collectionsState === "timeout")
        return collectionsMessage !== "" ? collectionsMessage : "Could not list collections"
      var n = cachedCollections().length
      if (filterText.trim() !== "")
        return "Collections — filtered"
      return n > 0
        ? "Collections — " + n + " · Enter opens · Esc back"
        : "Collections"
    }
    if (browseLevel === levelDocs) {
      var name = lsCollection !== "" ? lsCollection : "collection"
      var total = lsDocumentCount
      var page = Math.max(1, Math.ceil(lsRowCount / Math.max(1, lsPageSize)))
      if (lsState === "loading" && lsRowCount === 0)
        return name + " — loading documents…"
      if (lsState === "error" || lsState === "timeout")
        return lsMessage !== "" ? lsMessage : "Could not list documents"
      if (lsState === "empty")
        return name + " — empty"
      var suffix = total > 0 ? total + " docs" : lsRowCount + " loaded"
      if (lsLoading)
        return name + " — " + suffix + " — loading page " + (page + (lsHasMore ? 1 : 0))
      return name + " — " + suffix + " — page " + page
    }
    if (isStale)
      return "Showing last good · " + cacheAgeLabel()
    if (showingSearch && searchState === "loading")
      return searchMode === "deep"
        ? "Deep searching… (embeddings + rerank)"
        : "Searching…"
    if (showingSearch && searchState === "ready")
      return searchMode === "deep"
        ? searchHitCount + " deep hits"
        : searchHitCount + " results"
    if (showingSearch && searchState === "empty")
      return searchMode === "deep" ? "No deep hits" : "No results"
    if (showingSearch && (searchState === "error" || searchState === "timeout"))
      return searchMessage !== "" ? searchMessage : (searchState === "timeout" ? "Search timed out" : "Search failed")
    if (filterText.trim() !== "")
      return "Filtered recents — Enter to search · Shift+Enter deep · Tab collections"
    var recents = cachedRecents().length
    return recents > 0
      ? recents + " recent · Tab collections · Enter opens · Shift+Enter deep · Ctrl+Enter web"
      : "Tab to browse collections"
  }

  function emptyCopy() {
    if (emptyKind === "uninitialized")
      return "GNO is not initialized yet.\n\nRun gno init in a terminal, then summon Recall again."
    if (emptyKind === "empty-index")
      return "The index is empty.\n\nAdd documents to a GNO collection so Recall has something to search."
    if (emptyKind === "filter-empty") {
      if (inBrowse)
        return "No matches for “" + filterText + "”"
      return "No matches for “" + filterText + "”\n\nEnter searches the full index."
    }
    if (emptyKind === "search-empty")
      return "No results for “" + searchQuery + "”"
    if (emptyKind === "search-timeout")
      return "Search timed out.\n\nThe overlay is still open — edit the query and press Enter to try again."
    if (emptyKind === "search-error")
      return "Search failed"
        + (searchMessage !== "" ? "\n\n" + searchMessage : "")
        + "\n\nThe overlay is still open — edit the query and press Enter to try again."
    if (emptyKind === "search-loading")
      return searchMode === "deep"
        ? "Deep searching… (embeddings + rerank)"
        : "Searching…"
    if (emptyKind === "collections-loading")
      return "Loading collections…"
    if (emptyKind === "collections-empty")
      return "No collections in this index."
    if (emptyKind === "status-timeout")
      return "Could not list collections (timed out).\n\nThe overlay is still open — press Tab or Esc and try again."
    if (emptyKind === "status-error")
      return "Could not list collections."
        + (collectionsMessage !== "" ? "\n\n" + collectionsMessage : "")
        + "\n\nThe overlay is still open — press Tab or Esc and try again."
    if (emptyKind === "docs-loading")
      return "Loading documents…"
    if (emptyKind === "collection-empty")
      return "This collection is empty.\n\nEsc returns to the collections list."
    if (emptyKind === "ls-timeout")
      return "Could not list documents (timed out).\n\nThe overlay is still open — Esc goes back, Enter retries."
    if (emptyKind === "ls-error")
      return "Could not list documents."
        + (lsMessage !== "" ? "\n\n" + lsMessage : "")
        + "\n\nThe overlay is still open — Esc goes back, Enter retries."
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
    var needle = filterText.trim().toLowerCase()
    if (browseLevel === levelCollections) {
      var cols = cachedCollections()
      for (var c = 0; c < cols.length; c++) {
        var col = normalizeCollection(cols[c])
        if (rowMatchesFilter(col, needle))
          rows.push(col)
      }
    } else if (browseLevel === levelDocs) {
      var docs = cachedBrowseDocs()
      for (var d = 0; d < docs.length; d++) {
        var doc = normalizeBrowse(docs[d])
        if (rowMatchesFilter(doc, needle))
          rows.push(doc)
      }
      if (lsHasMore && needle === "")
        rows.push(loadMoreRow())
    } else if (showingSearch && (searchState === "ready" || searchState === "empty")) {
      var hits = service && service.searchResults ? service.searchResults : []
      for (var i = 0; i < hits.length; i++) {
        if (hits[i])
          rows.push(normalizeSearch(hits[i]))
      }
    } else if (!showingSearch || searchState === "idle") {
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
    if (root.inBrowse)
      return
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

  function commitDeepSearch() {
    if (root.inBrowse)
      return
    var q = root.filterText.trim()
    if (q === "")
      return
    if (!service || typeof service.runDeepSearch !== "function")
      return
    root.cursorActive = true
    root.selectedIndex = 0
    service.runDeepSearch(q)
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
    if (!row)
      return
    if (String(row.kind || "") === "collection") {
      root.enterDocs(row.collection || row.title, "enter")
      return
    }
    if (String(row.kind || "") === "more") {
      root.loadMoreDocs()
      return
    }
    if (browseLevel === levelDocs && (lsState === "error" || lsState === "timeout") && lsRowCount === 0) {
      if (service && typeof service.runLs === "function" && lsCollection !== "")
        service.runLs(lsCollection, 0)
      return
    }
    if (service && typeof service.openDocument === "function") {
      service.openDocument(row)
      return
    }
    if (service && typeof service.setActionStatus === "function")
      service.setActionStatus("No file path — start gno serve --detach to open in the web UI.")
  }

  function openWebAt(index) {
    var row = rowAt(index)
    if (!row || String(row.kind || "") === "collection" || String(row.kind || "") === "more")
      return
    if (!service || typeof service.openWebUi !== "function")
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
      absPath: "",
      relPath: "",
      documentCount: 0,
      collectionPath: ""
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
    base.statusLine = root.statusLine
    base.cacheAge = root.cacheAgeLabel()
    base.filterText = root.filterText
    base.showingSearch = root.showingSearch
    base.searchMode = root.searchMode
    base.emptyKind = root.emptyKind
    base.selectedIndex = root.selectedIndex
    base.rowCount = displayModel.count
    base.firstUri = first ? String(first.uri || "") : ""
    base.firstTitle = first ? String(first.title || "") : ""
    base.firstAbsPath = first ? String(first.absPath || "") : ""
    base.selectedUri = selected ? String(selected.uri || "") : ""
    base.selectedAbsPath = selected ? String(selected.absPath || "") : ""
    base.selectedCanOpenFile = service && typeof service.canOpenFile === "function"
      ? service.canOpenFile(selected)
      : !!(selected && String(selected.absPath || "").trim() !== "")
    base.selectedCanOpenDocument = service && typeof service.canOpenDocument === "function"
      ? service.canOpenDocument(selected)
      : base.selectedCanOpenFile
    base.fileOpenDisabled = !base.selectedCanOpenFile
    base.webDocUrl = service && typeof service.webDocUrl === "function" && selected
      ? service.webDocUrl(selected.uri)
      : ""
    base.targetScreen = root.targetScreen ? String(root.targetScreen.name || "") : ""
    base.browseLevel = root.browseLevel
    base.collectionsState = root.collectionsState
    base.collectionsMessage = root.collectionsMessage
    base.collectionsLoading = root.collectionsLoading
    base.collectionsCount = root.cachedCollections().length
    base.lsState = root.lsState
    base.lsMessage = root.lsMessage
    base.lsLoading = root.lsLoading
    base.lsCollection = root.lsCollection
    base.lsDocumentCount = root.lsDocumentCount
    base.lsRowCount = root.lsRowCount
    base.lsHasMore = root.lsHasMore
    base.lsOffset = service ? (service.lsOffset || 0) : 0
    base.selectedKind = selected ? String(selected.kind || "") : ""
    base.selectedRelPath = selected ? String(selected.relPath || "") : ""
    base.selectedCollection = selected ? String(selected.collection || "") : ""
    return JSON.stringify(base)
  }

  onDisplaySnapshotChanged: if (opened) rebuildDisplay()
  onSearchStateChanged: if (opened) rebuildDisplay()
  onSearchGenerationIdChanged: if (opened) rebuildDisplay()
  onSearchHitCountChanged: if (opened) rebuildDisplay()
  onCollectionsGenerationIdChanged: if (opened && browseLevel === levelCollections) rebuildDisplay()
  onCollectionsStateChanged: if (opened && browseLevel === levelCollections) rebuildDisplay()
  onLsGenerationIdChanged: if (opened && browseLevel === levelDocs) rebuildDisplay()
  onLsStateChanged: if (opened && browseLevel === levelDocs) rebuildDisplay()
  onLsRowCountChanged: if (opened && browseLevel === levelDocs) rebuildDisplay()
  onLsHasMoreChanged: if (opened && browseLevel === levelDocs) rebuildDisplay()

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
            root.handleEscape()
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace && root.filterText === "" && root.inBrowse) {
            root.goBackLevel()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if ((event.key === Qt.Key_Tab || ((event.key === Qt.Key_B) && (event.modifiers & Qt.ControlModifier)))
                     && root.browseLevel === root.levelRecents) {
            root.enterCollections(event.key === Qt.Key_Tab ? "tab" : "ctrl-b")
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            if (root.browseLevel === root.levelDocs && root.lsHasMore) {
              var last = displayModel.count - 1
              var atMore = last >= 0 && root.rowAt(last) && String(root.rowAt(last).kind) === "more"
                && root.selectedIndex >= Math.max(0, last - 1)
              if (atMore) {
                root.loadMoreDocs()
                event.accepted = true
                return
              }
            }
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Right && root.browseLevel === root.levelDocs && root.lsHasMore) {
            root.loadMoreDocs()
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
            } else if (event.modifiers & Qt.ShiftModifier) {
              root.commitDeepSearch()
            } else if (root.inBrowse) {
              if (displayModel.count > 0)
                root.activateIndex(root.selectedIndex)
              else if (root.browseLevel === root.levelDocs && (root.lsState === "error" || root.lsState === "timeout")
                       && root.lsCollection !== "" && root.service && typeof root.service.runLs === "function")
                root.service.runLs(root.lsCollection, 0)
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
          spacing: Style.space(2)

          Rectangle {
            width: parent.width
            height: root.headerHeight
            radius: root.cornerRadius
            color: "transparent"

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.filterText || (root.browseLevel === root.levelCollections
                ? "Filter collections…"
                : (root.browseLevel === root.levelDocs
                  ? ("Filter " + (root.lsCollection || "documents") + "…")
                  : "Recall recent documents…"))
              textFormat: Text.PlainText
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
            textFormat: Text.PlainText
            color: root.actionStatus !== "" || root.isStale
              || root.emptyKind === "search-error" || root.emptyKind === "search-timeout"
              || root.emptyKind === "status-error" || root.emptyKind === "status-timeout"
              || root.emptyKind === "ls-error" || root.emptyKind === "ls-timeout"
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
            - (root.statusLine !== "" ? Style.font.caption + Style.space(2) : 0)

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: root.rowListSpacing
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
              required property string relPath
              required property int documentCount

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
              readonly property bool isCollection: kind === "collection"
              readonly property bool isMore: kind === "more"
              readonly property bool canOpenFile: !isCollection && !isMore && String(absPath || "").trim() !== ""
              readonly property bool canOpenDocument: {
                if (isCollection || isMore)
                  return false
                if (root.service && typeof root.service.canOpenDocument === "function")
                  return root.service.canOpenDocument({ absPath: absPath, uri: uri, relPath: relPath })
                return canOpenFile
              }
              readonly property string metaText: {
                if (isMore)
                  return "Next " + root.lsPageSize + " documents"
                if (isCollection)
                  return documentCount + (documentCount === 1 ? " document" : " documents")
                var bits = []
                if (kind === "browse" && relPath !== "")
                  bits.push(relPath)
                else if (collection !== "")
                  bits.push(collection)
                var stamp = root.formatStamp(modifiedAt)
                if (stamp !== "")
                  bits.push(stamp)
                if (!canOpenFile)
                  bits.push("no file path")
                return bits.join(" · ")
              }

              width: ListView.view.width
              implicitHeight: Math.max(root.rowMinHeight, rowColumn.implicitHeight + root.rowPadY * 2)
              height: implicitHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"

              Column {
                id: rowColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                spacing: root.rowInnerSpacing

                Text {
                  width: parent.width
                  text: row.title
                  textFormat: Text.PlainText
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: row.canOpenDocument ? 1 : 0.55
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  visible: row.metaText !== ""
                  text: row.metaText
                  textFormat: Text.PlainText
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  visible: row.snippet !== ""
                  text: root.styleSnippet(row.snippet, Color.accent)
                  textFormat: Text.StyledText
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
                cursorShape: row.canOpenDocument ? Qt.PointingHandCursor : Qt.ArrowCursor
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
              textFormat: Text.PlainText
              color: root.emptyKind === "search-error" || root.emptyKind === "search-timeout"
                || root.emptyKind === "status-error" || root.emptyKind === "status-timeout"
                || root.emptyKind === "ls-error" || root.emptyKind === "ls-timeout"
                || root.emptyKind === "plugin-error"
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
