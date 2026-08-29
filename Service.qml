import QtQuick
import Quickshell
import Quickshell.Io

// Headless GNO peek owner. Later surfaces look this up with
// bar.shell.serviceFor("gmickel.gno-recall") and must not spawn their own Process.
Item {
  id: root

  visible: false

  property var shell: null
  property var manifest: null
  property var settings: ({})

  readonly property string pluginId: "gmickel.gno-recall"
  readonly property string supportedGnoFloor: "1.36.0"
  readonly property string peekSchemaVersion: "peek@1.0"
  readonly property int maxStdoutChars: 262144
  readonly property int probeTimeoutMs: 3000
  readonly property int peekTimeoutMs: 8000
  readonly property int searchTimeoutMs: 15000
  readonly property int searchLimit: 20
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 900, 60, 3600)

  readonly property string stateNotFound: "not-found"
  readonly property string stateNotExecutable: "not-executable"
  readonly property string stateSpawnFailure: "spawn-failure"
  readonly property string stateTimeout: "timeout"
  readonly property string stateMalformedJson: "malformed-json"
  readonly property string stateUnknownCommand: "unknown-command"
  readonly property string stateVersionSkew: "version-skew"
  readonly property string stateRuntimeError: "runtime-error"
  readonly property string stateReady: "ready"
  readonly property string stateLoading: "loading"
  readonly property string searchStateIdle: "idle"
  readonly property string searchStateLoading: "loading"
  readonly property string searchStateReady: "ready"
  readonly property string searchStateEmpty: "empty"
  readonly property string searchStateError: "error"
  readonly property string searchStateTimeout: "timeout"

  property string state: "loading"
  property string message: ""
  property string resolvedGnoPath: ""
  property var snapshot: null
  property var lastGoodSnapshot: null
  property int generationId: 0
  property bool loading: false
  property bool panelOpened: false
  property string lastPeekAt: ""
  readonly property bool stale: snapshot === null && lastGoodSnapshot !== null

  property string searchState: "idle"
  property string searchQuery: ""
  property string searchMessage: ""
  property var searchResults: []
  property int searchGenerationId: 0
  property int searchHitCount: 0
  property bool searchLoading: false

  property string actionStatus: ""
  property string fileOpenerOverride: ""
  property string browserOpenerOverride: ""
  property string lastOpenKind: ""
  property var lastOpenArgv: []
  property bool lastOpenOk: false
  property string lastOpenMessage: ""

  readonly property string defaultFileOpener: "xdg-open"
  readonly property string defaultBrowserOpener: "omarchy-launch-browser"
  readonly property int actionStatusMs: 3000

  property bool _openStarted: false
  property string _openKind: ""
  property var _pendingOpenArgv: []
  property string _pendingOpenKind: ""

  property string _phase: ""
  property string _stdout: ""
  property string _stderr: ""
  property bool _started: false
  property bool _timedOut: false
  property bool _refreshQueued: false

  property string _searchStdout: ""
  property string _searchStderr: ""
  property bool _searchStarted: false
  property bool _searchTimedOut: false
  property int _runningSearchGen: 0
  property string _pendingSearchQuery: ""
  property int _pendingSearchGen: 0

  function setting(name, fallback) {
    var fromProp = settings ? settings[name] : undefined
    if (fromProp !== undefined && fromProp !== null)
      return fromProp
    var layout = layoutSettings()
    var fromLayout = layout ? layout[name] : undefined
    if (fromLayout !== undefined && fromLayout !== null)
      return fromLayout
    return fallback
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value))
      value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function layoutSettings() {
    if (!shell || !shell.shellConfig || !shell.shellConfig.bar || !shell.shellConfig.bar.layout)
      return ({})
    var layout = shell.shellConfig.bar.layout
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var entries = layout[sections[s]]
      if (!Array.isArray(entries))
        continue
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        if (entry && String(entry.id || "") === pluginId)
          return entry
      }
    }
    return ({})
  }

  function configuredGnoPath() {
    return String(setting("gnoPath", "")).trim()
  }

  function parseVersionParts(value) {
    var text = String(value || "").replace(/^[vV]/, "")
    var parts = text.split(/[^0-9]+/)
    return [parseInt(parts[0], 10) || 0, parseInt(parts[1], 10) || 0, parseInt(parts[2], 10) || 0]
  }

  function versionAtLeast(actual, floor) {
    var a = parseVersionParts(actual)
    var b = parseVersionParts(floor)
    for (var i = 0; i < 3; i++) {
      if (a[i] > b[i])
        return true
      if (a[i] < b[i])
        return false
    }
    return true
  }

  function parseJsonObject(raw) {
    var text = String(raw || "").trim()
    if (text === "")
      return null
    try {
      var value = JSON.parse(text)
      return value && typeof value === "object" ? value : null
    } catch (error) {
      return null
    }
  }

  function isUnknownCommand(stderrText, parsedError) {
    var err = parsedError && parsedError.error ? parsedError.error : parsedError
    if (err && String(err.code || "") === "VALIDATION") {
      var details = err.details || {}
      if (String(details.commanderCode || "") === "commander.unknownCommand")
        return true
      if (/unknown command/i.test(String(err.message || "")))
        return true
    }
    return /unknown command ['"]peek['"]/i.test(String(stderrText || ""))
  }

  function bumpGeneration() {
    generationId += 1
  }

  function setState(next, detail) {
    state = next
    message = String(detail || "")
    bumpGeneration()
    console.info("gmickel.gno-recall: state=" + state
      + " gno=" + (resolvedGnoPath || "(unresolved)")
      + " generation=" + generationId
      + (message !== "" ? " message=" + message : ""))
  }

  function debugSnapshot() {
    var peek = snapshot || lastGoodSnapshot
    return JSON.stringify({
      state: state,
      message: message,
      resolvedGnoPath: resolvedGnoPath,
      generationId: generationId,
      lastPeekAt: lastPeekAt,
      supportedGnoFloor: supportedGnoFloor,
      snapshot: peek,
      lastGoodSnapshot: lastGoodSnapshot,
      stale: stale,
      panelOpened: panelOpened === true,
      searchState: searchState,
      searchQuery: searchQuery,
      searchMessage: searchMessage,
      searchGenerationId: searchGenerationId,
      searchHitCount: searchHitCount,
      searchLoading: searchLoading === true,
      searchLimit: searchLimit,
      firstSearchUri: searchResults && searchResults.length > 0 ? String(searchResults[0].uri || "") : "",
      actionStatus: actionStatus,
      lastOpenKind: lastOpenKind,
      lastOpenArgv: lastOpenArgv,
      lastOpenOk: lastOpenOk === true,
      lastOpenMessage: lastOpenMessage,
      serveRunning: serveIsRunning(),
      serveUrl: serveHomeUrl(),
      fileOpener: resolveFileOpener(),
      browserOpener: resolveBrowserOpener()
    })
  }

  function dropLiveSnapshot() {
    snapshot = null
  }

  function errorPayload(stderrText, stdoutText) {
    return parseJsonObject(stderrText) || parseJsonObject(stdoutText)
  }

  function isRuntimeEnvelope(parsedError) {
    var err = parsedError && parsedError.error ? parsedError.error : parsedError
    return !!(err && String(err.code || "") === "RUNTIME")
  }

  function errorDetail(parsedError, stderrText, stdoutText, fallback) {
    var err = parsedError && parsedError.error ? parsedError.error : parsedError
    if (err && err.message)
      return String(err.message)
    var stderr = String(stderrText || "").trim()
    if (stderr !== "")
      return stderr
    var stdout = String(stdoutText || "").trim()
    if (stdout !== "")
      return stdout
    return fallback
  }

  function refresh() {
    if (probeProcess.running || peekProcess.running) {
      _refreshQueued = true
      return
    }
    _refreshQueued = false
    loading = true
    _stdout = ""
    _stderr = ""
    _started = false
    _timedOut = false
    resolvedGnoPath = ""

    var configured = configuredGnoPath()
    if (configured !== "") {
      if (configured.charAt(0) !== "/") {
        dropLiveSnapshot()
        loading = false
        setState(stateNotFound, "gnoPath must be an absolute path")
        return
      }
      resolvedGnoPath = configured
      startProbe("exists", ["/usr/bin/test", "-e", configured])
      return
    }

    startProbe("which", ["/usr/bin/which", "gno"])
  }

  function startProbe(phase, argv) {
    _phase = phase
    _started = false
    _timedOut = false
    _stdout = ""
    _stderr = ""
    probeProcess.command = argv
    probeProcess.running = true
    probeKillTimer.interval = probeTimeoutMs
    probeKillTimer.restart()
  }

  function startPeek(gnoPath) {
    _phase = "peek"
    _started = false
    _timedOut = false
    _stdout = ""
    _stderr = ""
    peekProcess.command = [gnoPath, "peek", "--json"]
    peekProcess.running = true
    peekKillTimer.interval = peekTimeoutMs
    peekKillTimer.restart()
  }

  function finishIdle() {
    loading = false
    if (_refreshQueued) {
      _refreshQueued = false
      Qt.callLater(root.refresh)
    }
  }

  function handleProbeExit(exitCode) {
    probeKillTimer.stop()
    probeForceKillTimer.stop()
    var stdout = String(probeStdout.text || _stdout || "").trim()
    if (_timedOut) {
      dropLiveSnapshot()
      loading = false
      setState(stateTimeout, "Timed out resolving gno")
      finishIdle()
      return
    }
    if (!_started) {
      dropLiveSnapshot()
      loading = false
      setState(stateSpawnFailure, "Failed to start gno discovery")
      finishIdle()
      return
    }

    if (_phase === "which") {
      if (exitCode !== 0 || stdout === "") {
        dropLiveSnapshot()
        loading = false
        setState(stateNotFound, "gno was not found on PATH")
        finishIdle()
        return
      }
      if (stdout.charAt(0) !== "/") {
        dropLiveSnapshot()
        loading = false
        setState(stateNotFound, "PATH lookup did not return an absolute path")
        finishIdle()
        return
      }
      resolvedGnoPath = stdout
      startProbe("exec", ["/usr/bin/test", "-x", resolvedGnoPath])
      return
    }

    if (_phase === "exists") {
      if (exitCode !== 0) {
        dropLiveSnapshot()
        loading = false
        setState(stateNotFound, "gno was not found at " + resolvedGnoPath)
        finishIdle()
        return
      }
      startProbe("exec", ["/usr/bin/test", "-x", resolvedGnoPath])
      return
    }

    if (_phase === "exec") {
      if (exitCode !== 0) {
        dropLiveSnapshot()
        loading = false
        setState(stateNotExecutable, "gno is not executable: " + resolvedGnoPath)
        finishIdle()
        return
      }
      startPeek(resolvedGnoPath)
      return
    }

    dropLiveSnapshot()
    loading = false
    setState(stateSpawnFailure, "Unexpected discovery phase")
    finishIdle()
  }

  function handlePeekExit(exitCode) {
    peekKillTimer.stop()
    peekForceKillTimer.stop()
    var stdout = String(peekStdout.text || _stdout || "")
    var stderr = String(peekStderr.text || _stderr || "")
    loading = false

    if (_timedOut) {
      dropLiveSnapshot()
      setState(stateTimeout, "Timed out running gno peek --json")
      finishIdle()
      return
    }
    if (!_started) {
      dropLiveSnapshot()
      setState(stateSpawnFailure, "Failed to start gno peek --json")
      finishIdle()
      return
    }
    if (stdout.length > maxStdoutChars || stderr.length > maxStdoutChars) {
      dropLiveSnapshot()
      setState(stateMalformedJson, "gno peek output exceeded the size bound")
      finishIdle()
      return
    }

    var errObj = errorPayload(stderr, stdout)
    if (isUnknownCommand(stderr, errObj)) {
      dropLiveSnapshot()
      setState(stateUnknownCommand, "gno does not provide peek; install gno >= " + supportedGnoFloor)
      finishIdle()
      return
    }

    if (exitCode !== 0) {
      dropLiveSnapshot()
      var detail = errorDetail(errObj, stderr, stdout, "gno peek failed")
      setState(isRuntimeEnvelope(errObj) ? stateRuntimeError : stateSpawnFailure, detail)
      finishIdle()
      return
    }

    var data = parseJsonObject(stdout)
    if (!data || typeof data.schemaVersion !== "string" || typeof data.gnoVersion !== "string") {
      dropLiveSnapshot()
      setState(stateMalformedJson, "gno peek returned unreadable or incomplete JSON")
      finishIdle()
      return
    }
    if (!versionAtLeast(data.gnoVersion, supportedGnoFloor)) {
      dropLiveSnapshot()
      setState(stateVersionSkew, "gno " + data.gnoVersion + " is below the " + supportedGnoFloor + " floor")
      finishIdle()
      return
    }

    snapshot = data
    lastGoodSnapshot = data
    lastPeekAt = String(data.generatedAt || "")
    setState(stateReady, "")
    console.info("gmickel.gno-recall: peek ok schema=" + data.schemaVersion
      + " gnoVersion=" + data.gnoVersion
      + " initialized=" + data.initialized
      + " documents=" + (data.counts && data.counts.documents !== undefined ? data.counts.documents : "?"))
    finishIdle()
  }

  function collectionFromUri(uri) {
    var value = String(uri || "")
    if (value.indexOf("gno://") !== 0)
      return ""
    var rest = value.slice(6)
    var slash = rest.indexOf("/")
    return slash >= 0 ? rest.slice(0, slash) : rest
  }

  function normalizeSearchHits(data) {
    var hits = data && data.results ? data.results : []
    var rows = []
    if (!Array.isArray(hits))
      return rows
    for (var i = 0; i < hits.length; i++) {
      var hit = hits[i]
      if (!hit)
        continue
      var source = hit.source && typeof hit.source === "object" ? hit.source : {}
      var title = hit.title !== undefined && hit.title !== null ? String(hit.title) : ""
      var snippet = hit.snippet !== undefined && hit.snippet !== null
        ? String(hit.snippet)
        : (hit.content !== undefined && hit.content !== null ? String(hit.content) : "")
      rows.push({
        kind: "search",
        docid: String(hit.docid || ""),
        uri: String(hit.uri || ""),
        title: title,
        collection: collectionFromUri(hit.uri),
        snippet: snippet,
        modifiedAt: source.modifiedAt ? String(source.modifiedAt) : "",
        absPath: source.absPath ? String(source.absPath) : ""
      })
    }
    return rows
  }

  function cancelSearch(reason) {
    searchGenerationId += 1
    _pendingSearchQuery = ""
    _pendingSearchGen = 0
    searchKillTimer.stop()
    if (searchProcess.running) {
      _searchTimedOut = false
      searchProcess.signal(15)
      searchForceKillTimer.restart()
    } else {
      searchForceKillTimer.stop()
    }
    searchLoading = false
    if (searchState === searchStateLoading) {
      searchState = searchStateIdle
      searchMessage = ""
      searchResults = []
      searchHitCount = 0
    }
    console.info("gmickel.gno-recall: search cancelled gen=" + searchGenerationId
      + " reason=" + String(reason || "cancel")
      + " dropped=" + _runningSearchGen)
  }

  function runSearch(query) {
    var q = String(query || "").trim()
    if (q === "")
      return
    searchGenerationId += 1
    var gen = searchGenerationId
    searchQuery = q
    searchMessage = ""
    searchResults = []
    searchHitCount = 0
    searchLoading = true
    searchState = searchStateLoading
    _searchTimedOut = false
    console.info("gmickel.gno-recall: search request gen=" + gen + " query=" + q)

    if (searchProcess.running) {
      _pendingSearchQuery = q
      _pendingSearchGen = gen
      searchProcess.signal(15)
      searchForceKillTimer.restart()
      console.info("gmickel.gno-recall: search cancel-inflight running=" + _runningSearchGen
        + " pending=" + gen)
      return
    }
    startSearchProcess(q, gen)
  }

  function startSearchProcess(query, gen) {
    _runningSearchGen = gen
    _pendingSearchQuery = ""
    _pendingSearchGen = 0
    _searchStarted = false
    _searchTimedOut = false
    _searchStdout = ""
    _searchStderr = ""
    searchKillTimer.stop()
    searchForceKillTimer.stop()

    if (resolvedGnoPath === "") {
      searchLoading = false
      searchState = searchStateError
      searchMessage = "gno path is not resolved"
      console.info("gmickel.gno-recall: search error gen=" + gen + " message=" + searchMessage)
      return
    }

    searchProcess.command = [
      resolvedGnoPath,
      "search",
      query,
      "--json",
      "--no-project-affinity",
      "-n",
      String(searchLimit)
    ]
    searchProcess.running = true
    searchKillTimer.interval = searchTimeoutMs
    searchKillTimer.restart()
    console.info("gmickel.gno-recall: search start gen=" + gen
      + " argv=[" + resolvedGnoPath + ", search, <query>, --json, --no-project-affinity, -n, "
      + searchLimit + "]")
  }

  function handleSearchExit(exitCode) {
    searchKillTimer.stop()
    searchForceKillTimer.stop()
    var finishedGen = _runningSearchGen
    var pendingQuery = _pendingSearchQuery
    var pendingGen = _pendingSearchGen
    var stdout = String(searchStdout.text || _searchStdout || "")
    var stderr = String(searchStderr.text || _searchStderr || "")
    var timedOut = _searchTimedOut
    var started = _searchStarted
    _runningSearchGen = 0
    _pendingSearchQuery = ""
    _pendingSearchGen = 0
    _searchTimedOut = false

    if (pendingQuery !== "" && pendingGen === searchGenerationId) {
      console.info("gmickel.gno-recall: search late-drop gen=" + finishedGen
        + " current=" + searchGenerationId
        + " starting pending gen=" + pendingGen)
      startSearchProcess(pendingQuery, pendingGen)
      return
    }

    if (finishedGen !== searchGenerationId) {
      console.info("gmickel.gno-recall: search late-drop gen=" + finishedGen
        + " current=" + searchGenerationId)
      return
    }

    searchLoading = false

    if (timedOut) {
      searchResults = []
      searchHitCount = 0
      searchState = searchStateTimeout
      searchMessage = "Search timed out"
      console.info("gmickel.gno-recall: search timeout gen=" + finishedGen)
      return
    }
    if (!started) {
      searchResults = []
      searchHitCount = 0
      searchState = searchStateError
      searchMessage = "Failed to start gno search"
      console.info("gmickel.gno-recall: search spawn-failure gen=" + finishedGen)
      return
    }
    if (stdout.length > maxStdoutChars || stderr.length > maxStdoutChars) {
      searchResults = []
      searchHitCount = 0
      searchState = searchStateError
      searchMessage = "gno search output exceeded the size bound"
      console.info("gmickel.gno-recall: search error gen=" + finishedGen + " message=" + searchMessage)
      return
    }

    if (exitCode !== 0) {
      var errObj = errorPayload(stderr, stdout)
      searchResults = []
      searchHitCount = 0
      searchState = searchStateError
      searchMessage = errorDetail(errObj, stderr, stdout, "gno search failed")
      console.info("gmickel.gno-recall: search error gen=" + finishedGen
        + " exit=" + exitCode + " message=" + searchMessage)
      return
    }

    var data = parseJsonObject(stdout)
    if (!data || !Array.isArray(data.results)) {
      searchResults = []
      searchHitCount = 0
      searchState = searchStateError
      searchMessage = "gno search returned unreadable or incomplete JSON"
      console.info("gmickel.gno-recall: search malformed-json gen=" + finishedGen)
      return
    }

    var rows = normalizeSearchHits(data)
    searchResults = rows
    searchHitCount = rows.length
    searchMessage = ""
    searchState = rows.length === 0 ? searchStateEmpty : searchStateReady
    console.info("gmickel.gno-recall: search ok gen=" + finishedGen
      + " hits=" + rows.length
      + " first=" + (rows.length > 0 ? rows[0].uri : ""))
  }

  function setActionStatus(text) {
    actionStatus = String(text || "")
    lastOpenMessage = actionStatus
    if (actionStatus !== "")
      actionStatusTimer.restart()
    else
      actionStatusTimer.stop()
  }

  function setFileOpener(path) {
    fileOpenerOverride = String(path || "").trim()
    console.info("gmickel.gno-recall: file-opener override=" + (fileOpenerOverride || "(default)"))
    return fileOpenerOverride || defaultFileOpener
  }

  function setBrowserOpener(path) {
    browserOpenerOverride = String(path || "").trim()
    console.info("gmickel.gno-recall: browser-opener override=" + (browserOpenerOverride || "(default)"))
    return browserOpenerOverride || defaultBrowserOpener
  }

  function resolveFileOpener() {
    return fileOpenerOverride !== "" ? fileOpenerOverride : defaultFileOpener
  }

  function resolveBrowserOpener() {
    return browserOpenerOverride !== "" ? browserOpenerOverride : defaultBrowserOpener
  }

  function rowAbsPath(row) {
    if (!row)
      return ""
    return String(row.absPath || "").trim()
  }

  function canOpenFile(rowOrPath) {
    if (rowOrPath && typeof rowOrPath === "object")
      return rowAbsPath(rowOrPath) !== ""
    return String(rowOrPath || "").trim() !== ""
  }

  function serveIsRunning() {
    var snap = snapshot || lastGoodSnapshot
    return !!(snap && snap.serve && snap.serve.running === true)
  }

  function serveHomeUrl() {
    if (!serveIsRunning())
      return ""
    var snap = snapshot || lastGoodSnapshot
    var url = snap && snap.serve ? String(snap.serve.url || "").trim() : ""
    return url.replace(/\/+$/, "")
  }

  function webDocUrl(uri) {
    var home = serveHomeUrl()
    if (home === "")
      return ""
    return home + "/doc?uri=" + encodeURIComponent(String(uri || ""))
  }

  function formatArgv(argv) {
    var parts = []
    var list = argv || []
    for (var i = 0; i < list.length; i++)
      parts.push(String(list[i]))
    return parts.join(", ")
  }

  function launchArgv(argv, kind) {
    var list = []
    var source = argv || []
    for (var i = 0; i < source.length; i++)
      list.push(String(source[i]))
    lastOpenKind = String(kind || "")
    lastOpenArgv = list
    lastOpenOk = false
    lastOpenMessage = ""
    console.info("gmickel.gno-recall: exec argv=[" + formatArgv(list) + "] kind=" + lastOpenKind)

    if (list.length === 0) {
      finishOpenFailure("No opener command")
      return false
    }

    if (openProbeProcess.running) {
      // A second open while the probe is in flight still launches argv-safe.
      detachOpen(list)
      lastOpenOk = true
      setActionStatus("")
      return true
    }

    _openStarted = false
    _openKind = lastOpenKind
    _pendingOpenArgv = list
    _pendingOpenKind = lastOpenKind
    var binary = list[0]
    if (binary.indexOf("/") === 0)
      openProbeProcess.command = ["/usr/bin/test", "-x", binary]
    else
      openProbeProcess.command = ["/usr/bin/which", binary]
    openProbeProcess.running = true
    return true
  }

  function detachOpen(argv) {
    // Login shell + constant `exec "$@"` — same argv-safe pattern as Util.execArgv.
    // GUI handlers (xdg-open → typora) need the session PATH/env.
    Quickshell.execDetached(["bash", "-lc", 'exec "$@"', "bash"].concat(argv))
  }

  function handleOpenProbe(exitCode) {
    var argv = _pendingOpenArgv
    var kind = _pendingOpenKind
    _pendingOpenArgv = []
    _pendingOpenKind = ""
    if (!_openStarted || exitCode !== 0) {
      finishOpenFailure("Could not start " + (kind || "file") + " opener")
      return
    }
    detachOpen(argv)
    lastOpenOk = true
    lastOpenMessage = ""
    setActionStatus("")
    console.info("gmickel.gno-recall: open-ok kind=" + kind
      + " argv=[" + formatArgv(argv) + "]")
  }

  function finishOpenFailure(detail) {
    lastOpenOk = false
    setActionStatus(String(detail || "Could not start opener"))
    console.info("gmickel.gno-recall: open-fail kind=" + lastOpenKind
      + " message=" + lastOpenMessage
      + " argv=[" + formatArgv(lastOpenArgv) + "]")
  }

  function openSourceFile(absPath) {
    var path = String(absPath || "").trim()
    if (path === "") {
      lastOpenKind = "file"
      lastOpenArgv = []
      lastOpenOk = false
      setActionStatus("No file path — open source is disabled for this row")
      console.info("gmickel.gno-recall: open-file disabled missing-abspath")
      return false
    }
    return launchArgv([resolveFileOpener(), path], "file")
  }

  function openWebUi(uri) {
    var value = String(uri || "").trim()
    if (!serveIsRunning() || serveHomeUrl() === "") {
      lastOpenKind = "web"
      lastOpenArgv = []
      lastOpenOk = false
      setActionStatus("Web UI is down. Start it with: gno serve --detach")
      console.info("gmickel.gno-recall: open-web blocked serve-down")
      return false
    }
    if (value === "") {
      lastOpenKind = "web"
      lastOpenArgv = []
      lastOpenOk = false
      setActionStatus("Missing document URI — cannot open web UI")
      return false
    }
    return launchArgv([resolveBrowserOpener(), webDocUrl(value)], "web")
  }

  function openServeHome() {
    var url = serveHomeUrl()
    if (url === "") {
      lastOpenKind = "web-home"
      lastOpenArgv = []
      lastOpenOk = false
      setActionStatus("Web UI is down. Start it with: gno serve --detach")
      console.info("gmickel.gno-recall: open-web-home blocked serve-down")
      return false
    }
    return launchArgv([resolveBrowserOpener(), url], "web-home")
  }

  function killProcess(proc, forceTimer) {
    if (!proc.running)
      return
    _timedOut = true
    proc.signal(15)
    forceTimer.restart()
  }

  function killSearchProcess() {
    if (!searchProcess.running)
      return
    _searchTimedOut = true
    searchProcess.signal(15)
    searchForceKillTimer.restart()
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: probeKillTimer
    interval: root.probeTimeoutMs
    repeat: false
    onTriggered: root.killProcess(probeProcess, probeForceKillTimer)
  }

  Timer {
    id: probeForceKillTimer
    interval: 1000
    repeat: false
    onTriggered: if (probeProcess.running) probeProcess.signal(9)
  }

  Timer {
    id: peekKillTimer
    interval: root.peekTimeoutMs
    repeat: false
    onTriggered: root.killProcess(peekProcess, peekForceKillTimer)
  }

  Timer {
    id: peekForceKillTimer
    interval: 1000
    repeat: false
    onTriggered: if (peekProcess.running) peekProcess.signal(9)
  }

  Timer {
    id: searchKillTimer
    interval: root.searchTimeoutMs
    repeat: false
    onTriggered: root.killSearchProcess()
  }

  Timer {
    id: searchForceKillTimer
    interval: 1000
    repeat: false
    onTriggered: if (searchProcess.running) searchProcess.signal(9)
  }

  Timer {
    id: actionStatusTimer
    interval: root.actionStatusMs
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: probeProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: probeStdout
      waitForEnd: true
      onStreamFinished: root._stdout = text
    }
    stderr: StdioCollector {
      id: probeStderr
      waitForEnd: true
      onStreamFinished: root._stderr = text
    }
    onStarted: root._started = true
    onRunningChanged: {
      if (!running && root._phase !== "peek" && root._phase !== "" && !root._started && !root._timedOut) {
        probeKillTimer.stop()
        root.dropLiveSnapshot()
        root.loading = false
        root.setState(root.stateSpawnFailure, "Failed to start gno discovery")
        root.finishIdle()
      }
    }
    onExited: function(exitCode) {
      root.handleProbeExit(exitCode)
    }
  }

  Process {
    id: peekProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: peekStdout
      waitForEnd: true
      onStreamFinished: root._stdout = text
    }
    stderr: StdioCollector {
      id: peekStderr
      waitForEnd: true
      onStreamFinished: root._stderr = text
    }
    onStarted: root._started = true
    onRunningChanged: {
      if (!running && root._phase === "peek" && !root._started && !root._timedOut) {
        peekKillTimer.stop()
        root.dropLiveSnapshot()
        root.loading = false
        root.setState(root.stateSpawnFailure, "Failed to start gno peek --json")
        root.finishIdle()
      }
    }
    onExited: function(exitCode) {
      root.handlePeekExit(exitCode)
    }
  }

  Process {
    id: searchProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: searchStdout
      waitForEnd: true
      onStreamFinished: root._searchStdout = text
    }
    stderr: StdioCollector {
      id: searchStderr
      waitForEnd: true
      onStreamFinished: root._searchStderr = text
    }
    onStarted: root._searchStarted = true
    onRunningChanged: {
      if (!running && root._runningSearchGen !== 0 && !root._searchStarted && !root._searchTimedOut) {
        searchKillTimer.stop()
        root.handleSearchExit(1)
      }
    }
    onExited: function(exitCode) {
      root.handleSearchExit(exitCode)
    }
  }

  Process {
    id: openProbeProcess
    running: false
    command: []
    onStarted: root._openStarted = true
    onRunningChanged: {
      if (!running && !root._openStarted && root._pendingOpenArgv && root._pendingOpenArgv.length > 0) {
        root.finishOpenFailure("Could not start " + (root._pendingOpenKind || "file") + " opener")
        root._pendingOpenArgv = []
        root._pendingOpenKind = ""
      }
    }
    onExited: function(exitCode) {
      root.handleOpenProbe(exitCode)
    }
  }
}
