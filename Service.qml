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
  readonly property string supportedGnoFloor: "1.39.2"
  readonly property string peekSchemaVersion: "peek@1.0"
  readonly property string supportedPeekSchemaMajor: "peek@1.x"
  readonly property int maxPeekStdoutChars: 524288
  readonly property int maxSearchStdoutChars: 2097152
  readonly property int maxStatusStdoutChars: 524288
  readonly property int maxLsStdoutChars: 524288
  readonly property int maxProbeStdoutChars: 4096
  readonly property int probeTimeoutMs: 3000
  readonly property int peekTimeoutMs: 8000
  readonly property int searchTimeoutMs: 15000
  readonly property int deepSearchTimeoutMs: 90000
  readonly property int statusTimeoutMs: 8000
  readonly property int lsTimeoutMs: 8000
  readonly property int openProbeTimeoutMs: 3000
  readonly property int searchLimit: 20
  readonly property int lsPageSize: 50
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
  property int peekGenerationId: 0
  property bool loading: false
  property bool panelOpened: false
  property string lastPeekAt: ""
  property string lastSuccessfulRefreshAt: ""
  readonly property bool stale: snapshot === null && lastGoodSnapshot !== null
  readonly property bool refreshQueued: _refreshQueued === true

  property string searchState: "idle"
  property string searchQuery: ""
  property string searchMode: ""
  property string searchMessage: ""
  property var searchResults: []
  property int searchGenerationId: 0
  property int searchHitCount: 0
  property bool searchLoading: false

  readonly property string browseStateIdle: "idle"
  readonly property string browseStateLoading: "loading"
  readonly property string browseStateReady: "ready"
  readonly property string browseStateEmpty: "empty"
  readonly property string browseStateError: "error"
  readonly property string browseStateTimeout: "timeout"

  property var collections: []
  property string collectionsState: "idle"
  property string collectionsMessage: ""
  property int collectionsGenerationId: 0
  property bool collectionsLoading: false
  property string lastStatusAt: ""
  property var lastGoodCollections: []

  property string lsCollection: ""
  property string lsCollectionPath: ""
  property int lsDocumentCount: 0
  property var lsDocuments: []
  property int lsOffset: 0
  property bool lsHasMore: false
  property string lsState: "idle"
  property string lsMessage: ""
  property int lsGenerationId: 0
  property bool lsLoading: false

  property string actionStatus: ""
  property string fileOpenerOverride: ""
  property string browserOpenerOverride: ""
  property string lastOpenKind: ""
  property var lastOpenArgv: []
  property bool lastOpenOk: false
  property string lastOpenMessage: ""

  readonly property string defaultFileOpener: "VISUAL/omawrite (fallback gio/xdg-open)"
  // Compile-time constant. Document path is argv $1 only (R7).
  readonly property string defaultFileOpenScript: 'ext="${1##*.}"; ext=$(printf "%s" "$ext" | tr "[:upper:]" "[:lower:]"); case "$ext" in md|markdown|txt|org|rst|adoc|text) if [ -n "${VISUAL:-}" ]; then case "${VISUAL##*/}" in nvim|vim|vi|nano|micro|hx|helix|fresh|kak) exec omarchy-launch-tui "$VISUAL" "$1" ;; *) exec setsid uwsm-app -- "$VISUAL" "$1" ;; esac; elif command -v omawrite >/dev/null 2>&1; then exec setsid uwsm-app -- omawrite "$1"; elif command -v omarchy-launch-editor >/dev/null 2>&1; then exec omarchy-launch-editor "$1"; elif command -v gio >/dev/null 2>&1; then exec gio open "$1"; else exec xdg-open "$1"; fi ;; *) if command -v gio >/dev/null 2>&1; then exec gio open "$1"; else exec xdg-open "$1"; fi ;; esac'
  readonly property string defaultBrowserOpener: "omarchy-launch-browser"
  readonly property int actionStatusMs: 3000

  property bool _openStarted: false
  property string _openKind: ""
  property var _pendingOpenArgv: []
  property string _pendingOpenKind: ""
  property string _pendingOpenNotice: ""

  property string _phase: ""
  property string _stdout: ""
  property string _stderr: ""
  property bool _started: false
  property bool _timedOut: false
  property bool _probeOversized: false
  property bool _peekOversized: false
  property bool _refreshQueued: false
  property int _runningPeekGen: 0

  property string _searchStdout: ""
  property string _searchStderr: ""
  property bool _searchStarted: false
  property bool _searchTimedOut: false
  property bool _searchOversized: false
  property int _runningSearchGen: 0
  property bool _runningSearchDeep: false
  property string _pendingSearchQuery: ""
  property string _pendingSearchStdin: ""
  property int _pendingSearchGen: 0
  property bool _pendingSearchDeep: false
  property bool _openTimedOut: false

  property string _statusStdout: ""
  property string _statusStderr: ""
  property bool _statusStarted: false
  property bool _statusTimedOut: false
  property bool _statusOversized: false
  property int _runningStatusGen: 0
  property int _pendingStatusGen: 0

  property string _lsStdout: ""
  property string _lsStderr: ""
  property bool _lsStarted: false
  property bool _lsTimedOut: false
  property bool _lsOversized: false
  property int _runningLsGen: 0
  property string _pendingLsCollection: ""
  property string _pendingLsPath: ""
  property int _pendingLsOffset: 0
  property int _pendingLsGen: 0
  property int _pendingLsDocCount: 0
  property bool _lsAppend: false

  function pluginScript(rel) {
    var url = Qt.resolvedUrl(rel).toString()
    if (url.indexOf("file://") === 0)
      url = decodeURIComponent(url.slice(7))
    return url
  }

  function isolateCommand(argv) {
    var list = [pluginScript("scripts/run-in-pgroup.sh")]
    var source = argv || []
    for (var i = 0; i < source.length; i++)
      list.push(String(source[i]))
    return list
  }

  function killProcessGroup(proc, sig) {
    var pid = proc && proc.processId ? proc.processId : 0
    if (pid > 1)
      Quickshell.execDetached(["kill", String(sig || "-TERM"), "--", "-" + pid])
    if (proc && proc.running)
      proc.signal(sig === "-KILL" ? 9 : 15)
  }

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

  function peekSchemaCompatible(schemaVersion) {
    var text = String(schemaVersion || "")
    if (text === peekSchemaVersion)
      return true
    return /^peek@1\.\d+$/.test(text)
  }

  function isFiniteNumber(value) {
    return typeof value === "number" && isFinite(value)
  }

  function peekPayloadComplete(data) {
    if (!data || typeof data.initialized !== "boolean")
      return false
    var serve = data.serve
    if (!serve || typeof serve !== "object" || typeof serve.running !== "boolean")
      return false
    if (data.initialized !== true) {
      return data.counts === null && data.backlog === null && Array.isArray(data.recent)
    }
    var counts = data.counts
    var backlog = data.backlog
    if (!counts || typeof counts !== "object")
      return false
    if (!isFiniteNumber(counts.documents) || !isFiniteNumber(counts.collections))
      return false
    if (!backlog || typeof backlog !== "object")
      return false
    if (!isFiniteNumber(backlog.pending) || !isFiniteNumber(backlog.failed))
      return false
    return Array.isArray(data.recent)
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

  function cacheAgeLabel() {
    var stamp = lastSuccessfulRefreshAt !== "" ? lastSuccessfulRefreshAt : lastPeekAt
    var then = new Date(String(stamp || "")).getTime()
    if (!isFinite(then))
      return stamp !== "" ? stamp : "last good snapshot"
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

  function debugSnapshot() {
    var peek = snapshot || lastGoodSnapshot
    var recents = peek && peek.recent ? peek.recent : []
    return JSON.stringify({
      state: state,
      message: message,
      resolvedGnoPath: resolvedGnoPath,
      generationId: generationId,
      peekGenerationId: peekGenerationId,
      lastPeekAt: lastPeekAt,
      lastSuccessfulRefreshAt: lastSuccessfulRefreshAt,
      cacheAge: cacheAgeLabel(),
      refreshQueued: refreshQueued,
      maxPeekStdoutChars: maxPeekStdoutChars,
      maxSearchStdoutChars: maxSearchStdoutChars,
      supportedGnoFloor: supportedGnoFloor,
      snapshot: peek,
      lastGoodSnapshot: lastGoodSnapshot,
      stale: stale,
      recentCount: recents && recents.length ? recents.length : 0,
      firstRecentTitle: recents && recents.length > 0 ? String(recents[0].title || recents[0].uri || "") : "",
      panelOpened: panelOpened === true,
      searchState: searchState,
      searchQuery: searchQuery,
      searchMode: searchMode,
      searchMessage: searchMessage,
      searchGenerationId: searchGenerationId,
      searchHitCount: searchHitCount,
      searchLoading: searchLoading === true,
      searchLimit: searchLimit,
      deepSearchTimeoutMs: deepSearchTimeoutMs,
      firstSearchUri: searchResults && searchResults.length > 0 ? String(searchResults[0].uri || "") : "",
      collectionsState: collectionsState,
      collectionsMessage: collectionsMessage,
      collectionsGenerationId: collectionsGenerationId,
      collectionsLoading: collectionsLoading === true,
      collectionsCount: collections && collections.length ? collections.length : 0,
      lastStatusAt: lastStatusAt,
      statusCacheAge: statusCacheAgeLabel(),
      lsState: lsState,
      lsMessage: lsMessage,
      lsCollection: lsCollection,
      lsCollectionPath: lsCollectionPath,
      lsDocumentCount: lsDocumentCount,
      lsOffset: lsOffset,
      lsHasMore: lsHasMore === true,
      lsGenerationId: lsGenerationId,
      lsLoading: lsLoading === true,
      lsRowCount: lsDocuments && lsDocuments.length ? lsDocuments.length : 0,
      lsPageSize: lsPageSize,
      firstLsUri: lsDocuments && lsDocuments.length > 0 ? String(lsDocuments[0].uri || "") : "",
      firstLsAbsPath: lsDocuments && lsDocuments.length > 0 ? String(lsDocuments[0].absPath || "") : "",
      actionStatus: actionStatus,
      lastOpenKind: lastOpenKind,
      lastOpenArgv: lastOpenArgv,
      lastOpenOk: lastOpenOk === true,
      lastOpenMessage: lastOpenMessage,
      serveRunning: serveIsRunning(),
      serveUrl: serveHomeUrl(),
      fileOpener: resolveFileOpener(),
      browserOpener: resolveBrowserOpener(),
      guidanceNotice: missingPathGuidance()
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

  function beginPeekGeneration() {
    peekGenerationId += 1
    _runningPeekGen = peekGenerationId
    console.info("gmickel.gno-recall: peek start gen=" + peekGenerationId)
  }

  function peekGenIsStale(finishedGen) {
    if (finishedGen === peekGenerationId)
      return false
    console.info("gmickel.gno-recall: peek late-drop gen=" + finishedGen
      + " current=" + peekGenerationId)
    return true
  }

  function stdoutWithinBound(raw, limit, label) {
    var text = String(raw || "")
    if (text.length > limit) {
      console.info("gmickel.gno-recall: " + label + " oversized stdout chars=" + text.length
        + " bound=" + limit)
      return false
    }
    return true
  }

  function accumulateBounded(current, chunk, limit) {
    var piece = String(chunk || "")
    if (current.length + piece.length > limit)
      return null
    return current + piece
  }

  function takeProbeOutput(chunk, isStderr) {
    if (_probeOversized)
      return
    var current = isStderr ? _stderr : _stdout
    var next = accumulateBounded(current, chunk, maxProbeStdoutChars)
    if (next === null) {
      killProbeForOversized()
      return
    }
    if (isStderr)
      _stderr = next
    else
      _stdout = next
  }

  function takePeekOutput(chunk, isStderr) {
    if (_peekOversized)
      return
    var current = isStderr ? _stderr : _stdout
    var next = accumulateBounded(current, chunk, maxPeekStdoutChars)
    if (next === null) {
      killPeekForOversized()
      return
    }
    if (isStderr)
      _stderr = next
    else
      _stdout = next
  }

  function takeSearchOutput(chunk, isStderr) {
    if (_searchOversized)
      return
    var current = isStderr ? _searchStderr : _searchStdout
    var next = accumulateBounded(current, chunk, maxSearchStdoutChars)
    if (next === null) {
      killSearchForOversized()
      return
    }
    if (isStderr)
      _searchStderr = next
    else
      _searchStdout = next
  }

  function takeStatusOutput(chunk, isStderr) {
    if (_statusOversized)
      return
    var current = isStderr ? _statusStderr : _statusStdout
    var next = accumulateBounded(current, chunk, maxStatusStdoutChars)
    if (next === null) {
      killStatusForOversized()
      return
    }
    if (isStderr)
      _statusStderr = next
    else
      _statusStdout = next
  }

  function takeLsOutput(chunk, isStderr) {
    if (_lsOversized)
      return
    var current = isStderr ? _lsStderr : _lsStdout
    var next = accumulateBounded(current, chunk, maxLsStdoutChars)
    if (next === null) {
      killLsForOversized()
      return
    }
    if (isStderr)
      _lsStderr = next
    else
      _lsStdout = next
  }

  function signalAndForceKill(proc, forceTimer) {
    if (!proc.running)
      return
    killProcessGroup(proc, "-TERM")
    forceTimer.restart()
  }

  function killProbeForOversized() {
    if (_probeOversized)
      return
    _probeOversized = true
    console.info("gmickel.gno-recall: probe oversized bound=" + maxProbeStdoutChars)
    probeKillTimer.stop()
    signalAndForceKill(probeProcess, probeForceKillTimer)
  }

  function killPeekForOversized() {
    if (_peekOversized)
      return
    _peekOversized = true
    console.info("gmickel.gno-recall: peek oversized bound=" + maxPeekStdoutChars)
    peekKillTimer.stop()
    signalAndForceKill(peekProcess, peekForceKillTimer)
  }

  function killSearchForOversized() {
    if (_searchOversized)
      return
    _searchOversized = true
    console.info("gmickel.gno-recall: search oversized bound=" + maxSearchStdoutChars)
    searchKillTimer.stop()
    signalAndForceKill(searchProcess, searchForceKillTimer)
  }

  function killStatusForOversized() {
    if (_statusOversized)
      return
    _statusOversized = true
    console.info("gmickel.gno-recall: status oversized bound=" + maxStatusStdoutChars)
    statusKillTimer.stop()
    signalAndForceKill(statusProcess, statusForceKillTimer)
  }

  function killLsForOversized() {
    if (_lsOversized)
      return
    _lsOversized = true
    console.info("gmickel.gno-recall: ls oversized bound=" + maxLsStdoutChars)
    lsKillTimer.stop()
    signalAndForceKill(lsProcess, lsForceKillTimer)
  }

  function refresh() {
    if (probeProcess.running || peekProcess.running) {
      _refreshQueued = true
      peekGenerationId += 1
      console.info("gmickel.gno-recall: peek coalesce queued gen=" + peekGenerationId
        + " dropped=" + _runningPeekGen)
      return
    }
    _refreshQueued = false
    beginPeekGeneration()
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
    _probeOversized = false
    _stdout = ""
    _stderr = ""
    probeProcess.command = isolateCommand(argv)
    probeProcess.running = true
    probeKillTimer.interval = probeTimeoutMs
    probeKillTimer.restart()
  }

  function startPeek(gnoPath) {
    _phase = "peek"
    _started = false
    _timedOut = false
    _peekOversized = false
    _stdout = ""
    _stderr = ""
    peekProcess.command = isolateCommand([gnoPath, "peek", "--json"])
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
    var finishedGen = _runningPeekGen
    if (peekGenIsStale(finishedGen)) {
      loading = false
      finishIdle()
      return
    }
    var stdout = String(_stdout || "").trim()
    if (_probeOversized) {
      dropLiveSnapshot()
      loading = false
      setState(stateSpawnFailure, "gno discovery output exceeded the size bound")
      finishIdle()
      return
    }
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
    var finishedGen = _runningPeekGen
    var stdout = String(_stdout || "")
    var stderr = String(_stderr || "")
    loading = false

    if (peekGenIsStale(finishedGen)) {
      finishIdle()
      return
    }

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
    if (_peekOversized
        || !stdoutWithinBound(stdout, maxPeekStdoutChars, "peek")
        || !stdoutWithinBound(stderr, maxPeekStdoutChars, "peek-stderr")) {
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
    if (!peekSchemaCompatible(data.schemaVersion)) {
      dropLiveSnapshot()
      setState(stateVersionSkew, "gno peek schema " + data.schemaVersion
        + " is unsupported; plugin supports " + supportedPeekSchemaMajor)
      finishIdle()
      return
    }
    if (!peekPayloadComplete(data)) {
      dropLiveSnapshot()
      setState(stateMalformedJson, "gno peek returned an incomplete peek@1.0 payload")
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
    lastSuccessfulRefreshAt = new Date().toISOString()
    lastPeekAt = lastSuccessfulRefreshAt
    setState(stateReady, "")
    console.info("gmickel.gno-recall: peek ok schema=" + data.schemaVersion
      + " gnoVersion=" + data.gnoVersion
      + " initialized=" + data.initialized
      + " documents=" + (data.counts && data.counts.documents !== undefined ? data.counts.documents : "?"))
    if (data.initialized === true)
      runStatus()
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

  function searchHitsArray(data) {
    if (!data)
      return null
    if (Array.isArray(data.results))
      return data.results
    if (Array.isArray(data.hits))
      return data.hits
    return null
  }

  function normalizeSearchHits(data) {
    var hits = searchHitsArray(data)
    var rows = []
    if (!hits)
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
      var collection = collectionFromUri(hit.uri)
      var cachedCollection = collectionByName(collection)
      rows.push({
        kind: "search",
        docid: String(hit.docid || ""),
        uri: String(hit.uri || ""),
        title: title,
        collection: collection,
        collectionPath: cachedCollection ? String(cachedCollection.path || "") : "",
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
    _pendingSearchDeep = false
    searchKillTimer.stop()
    if (searchProcess.running) {
      _searchTimedOut = false
      killProcessGroup(searchProcess, "-TERM")
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
      searchMode = ""
    }
    console.info("gmickel.gno-recall: search cancelled gen=" + searchGenerationId
      + " reason=" + String(reason || "cancel")
      + " dropped=" + _runningSearchGen)
  }

  function runDeepSearch(query) {
    runSearch(query, true)
  }

  function runSearch(query, deep) {
    var q = String(query || "").trim()
    if (q === "")
      return
    var isDeep = deep === true
    searchGenerationId += 1
    var gen = searchGenerationId
    searchQuery = q
    searchMode = isDeep ? "deep" : "bm25"
    searchMessage = ""
    searchResults = []
    searchHitCount = 0
    searchLoading = true
    searchState = searchStateLoading
    _searchTimedOut = false
    console.info("gmickel.gno-recall: search request gen=" + gen
      + " mode=" + searchMode
      + " query=" + q)

    if (searchProcess.running) {
      _pendingSearchQuery = q
      _pendingSearchGen = gen
      _pendingSearchDeep = isDeep
      killProcessGroup(searchProcess, "-TERM")
      searchForceKillTimer.restart()
      console.info("gmickel.gno-recall: search cancel-inflight running=" + _runningSearchGen
        + " pending=" + gen
        + " pendingMode=" + (isDeep ? "deep" : "bm25"))
      return
    }
    startSearchProcess(q, gen, isDeep)
  }

  function startSearchProcess(query, gen, deep) {
    var isDeep = deep === true
    _runningSearchGen = gen
    _runningSearchDeep = isDeep
    _pendingSearchQuery = ""
    _pendingSearchGen = 0
    _pendingSearchDeep = false
    _searchStarted = false
    _searchTimedOut = false
    _searchOversized = false
    _searchStdout = ""
    _searchStderr = ""
    searchKillTimer.stop()
    searchForceKillTimer.stop()

    if (resolvedGnoPath === "") {
      searchLoading = false
      searchState = searchStateError
      searchMessage = "gno path is not resolved"
      console.info("gmickel.gno-recall: search error gen=" + gen
        + " mode=" + (isDeep ? "deep" : "bm25")
        + " message=" + searchMessage)
      return
    }

    var verb = isDeep ? "query" : "search"
    _pendingSearchStdin = String(query || "").replace(/[\r\n]/g, " ")
    searchProcess.command = [
      pluginScript("scripts/search-via-query-file.sh"),
      resolvedGnoPath,
      verb,
      "--json",
      "--no-project-affinity",
      "-n",
      String(searchLimit)
    ]
    searchProcess.running = true
    searchKillTimer.interval = isDeep ? deepSearchTimeoutMs : searchTimeoutMs
    searchKillTimer.restart()
    console.info("gmickel.gno-recall: search start gen=" + gen
      + " mode=" + (isDeep ? "deep" : "bm25")
      + " argv=[" + resolvedGnoPath + ", " + verb + ", <query>, --json, --no-project-affinity, -n, "
      + searchLimit + "]")
  }

  function handleSearchExit(exitCode) {
    searchKillTimer.stop()
    searchForceKillTimer.stop()
    var finishedGen = _runningSearchGen
    var finishedDeep = _runningSearchDeep === true
    var pendingQuery = _pendingSearchQuery
    var pendingGen = _pendingSearchGen
    var pendingDeep = _pendingSearchDeep === true
    var stdout = String(_searchStdout || "")
    var stderr = String(_searchStderr || "")
    var timedOut = _searchTimedOut
    var started = _searchStarted
    var oversized = _searchOversized
    var finishedMode = finishedDeep ? "deep" : "bm25"
    _runningSearchGen = 0
    _runningSearchDeep = false
    _pendingSearchQuery = ""
    _pendingSearchGen = 0
    _pendingSearchDeep = false
    _searchTimedOut = false
    _searchOversized = false

    if (pendingQuery !== "" && pendingGen === searchGenerationId) {
      console.info("gmickel.gno-recall: search late-drop gen=" + finishedGen
        + " mode=" + finishedMode
        + " current=" + searchGenerationId
        + " starting pending gen=" + pendingGen
        + " pendingMode=" + (pendingDeep ? "deep" : "bm25"))
      startSearchProcess(pendingQuery, pendingGen, pendingDeep)
      return
    }

    if (finishedGen !== searchGenerationId) {
      console.info("gmickel.gno-recall: search late-drop gen=" + finishedGen
        + " mode=" + finishedMode
        + " current=" + searchGenerationId)
      return
    }

    searchLoading = false

    if (timedOut) {
      searchResults = []
      searchHitCount = 0
      searchState = searchStateTimeout
      searchMessage = finishedDeep ? "Deep search timed out" : "Search timed out"
      console.info("gmickel.gno-recall: search timeout gen=" + finishedGen
        + " mode=" + finishedMode)
      return
    }
    if (!started) {
      searchResults = []
      searchHitCount = 0
      searchState = searchStateError
      searchMessage = finishedDeep ? "Failed to start gno query" : "Failed to start gno search"
      console.info("gmickel.gno-recall: search spawn-failure gen=" + finishedGen
        + " mode=" + finishedMode)
      return
    }
    if (oversized
        || !stdoutWithinBound(stdout, maxSearchStdoutChars, "search")
        || !stdoutWithinBound(stderr, maxSearchStdoutChars, "search-stderr")) {
      searchResults = []
      searchHitCount = 0
      searchState = searchStateError
      searchMessage = finishedDeep
        ? "gno query output exceeded the size bound"
        : "gno search output exceeded the size bound"
      console.info("gmickel.gno-recall: search error gen=" + finishedGen
        + " mode=" + finishedMode
        + " message=" + searchMessage)
      return
    }

    if (exitCode !== 0) {
      var errObj = errorPayload(stderr, stdout)
      searchResults = []
      searchHitCount = 0
      searchState = searchStateError
      searchMessage = errorDetail(errObj, stderr, stdout,
        finishedDeep ? "gno query failed" : "gno search failed")
      console.info("gmickel.gno-recall: search error gen=" + finishedGen
        + " mode=" + finishedMode
        + " exit=" + exitCode + " message=" + searchMessage)
      return
    }

    var data = parseJsonObject(stdout)
    if (!data || searchHitsArray(data) === null) {
      searchResults = []
      searchHitCount = 0
      searchState = searchStateError
      searchMessage = finishedDeep
        ? "gno query returned unreadable or incomplete JSON"
        : "gno search returned unreadable or incomplete JSON"
      console.info("gmickel.gno-recall: search malformed-json gen=" + finishedGen
        + " mode=" + finishedMode)
      return
    }

    var rows = normalizeSearchHits(data)
    searchResults = rows
    searchHitCount = rows.length
    searchMessage = ""
    searchState = rows.length === 0 ? searchStateEmpty : searchStateReady
    console.info("gmickel.gno-recall: search ok gen=" + finishedGen
      + " mode=" + finishedMode
      + " hits=" + rows.length
      + " first=" + (rows.length > 0 ? rows[0].uri : ""))
  }

  function statusCacheAgeLabel() {
    var then = new Date(String(lastStatusAt || "")).getTime()
    if (!isFinite(then))
      return lastStatusAt !== "" ? lastStatusAt : ""
    var seconds = Math.max(0, Math.floor((Date.now() - then) / 1000))
    if (seconds < 60)
      return "just now"
    if (seconds < 3600)
      return Math.floor(seconds / 60) + "m ago"
    if (seconds < 86400)
      return Math.floor(seconds / 3600) + "h ago"
    return Math.floor(seconds / 86400) + "d ago"
  }

  function normalizeRelPath(relPath) {
    var rel = String(relPath || "")
    if (rel.indexOf("\0") !== -1)
      return ""
    try {
      if (/%[0-9A-Fa-f]{2}/.test(rel))
        rel = decodeURIComponent(rel)
    } catch (error) {
      return ""
    }
    if (rel === "" || rel.charAt(0) === "/")
      return ""
    var parts = rel.split("/")
    var out = []
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i]
      if (part === "" || part === ".")
        continue
      if (part === "..") {
        if (out.length === 0)
          return ""
        out.pop()
        continue
      }
      out.push(part)
    }
    return out.join("/")
  }

  function browsedAbsPath(collectionPath, relPath) {
    var root = String(collectionPath || "").replace(/\/+$/, "")
    var rel = normalizeRelPath(relPath)
    if (rel === "")
      return ""
    if (root === "")
      return ""
    return root + "/" + rel
  }

  function collectionByName(name) {
    var needle = String(name || "")
    var lists = [collections, lastGoodCollections]
    for (var l = 0; l < lists.length; l++) {
      var rows = lists[l] || []
      for (var i = 0; i < rows.length; i++) {
        if (rows[i] && String(rows[i].name || "") === needle)
          return rows[i]
      }
    }
    return null
  }

  function normalizeCollections(data) {
    var src = data && data.collections ? data.collections : []
    var rows = []
    if (!Array.isArray(src))
      return rows
    for (var i = 0; i < src.length; i++) {
      var item = src[i]
      if (!item)
        continue
      var name = String(item.name || "").trim()
      if (name === "")
        continue
      var count = parseInt(item.documentCount, 10)
      rows.push({
        name: name,
        path: String(item.path || ""),
        documentCount: isFinite(count) ? count : 0
      })
    }
    return rows
  }

  function normalizeLsDocuments(data, collectionName, collectionPath) {
    var docs = data && data.documents ? data.documents : []
    var rows = []
    if (!Array.isArray(docs))
      return rows
    for (var i = 0; i < docs.length; i++) {
      var doc = docs[i]
      if (!doc)
        continue
      var source = doc.source && typeof doc.source === "object" ? doc.source : {}
      var title = doc.title !== undefined && doc.title !== null ? String(doc.title) : ""
      var relPath = source.relPath !== undefined && source.relPath !== null ? String(source.relPath) : ""
      var uri = String(doc.uri || "")
      rows.push({
        kind: "browse",
        docid: String(doc.docid || ""),
        uri: uri,
        title: title,
        collection: String(collectionName || ""),
        collectionPath: String(collectionPath || ""),
        snippet: "",
        modifiedAt: "",
        absPath: browsedAbsPath(collectionPath, relPath),
        relPath: relPath
      })
    }
    return rows
  }

  function inferLsHasMore(data, pageRows, loadedCount) {
    var meta = data && data.meta && typeof data.meta === "object" ? data.meta : null
    if (meta) {
      if (typeof meta.hasMore === "boolean")
        return meta.hasMore
      if (typeof meta.has_more === "boolean")
        return meta.has_more
      var total = parseInt(meta.total, 10)
      if (isFinite(total))
        return loadedCount < total
    }
    return pageRows.length >= lsPageSize
  }

  function cancelStatus(reason) {
    collectionsGenerationId += 1
    _pendingStatusGen = 0
    statusKillTimer.stop()
    if (statusProcess.running) {
      _statusTimedOut = false
      killProcessGroup(statusProcess, "-TERM")
      statusForceKillTimer.restart()
    } else {
      statusForceKillTimer.stop()
    }
    collectionsLoading = false
    if (collectionsState === browseStateLoading) {
      if (lastGoodCollections && lastGoodCollections.length > 0) {
        collections = lastGoodCollections
        collectionsState = browseStateReady
        collectionsMessage = ""
      } else {
        collectionsState = browseStateIdle
        collectionsMessage = ""
      }
    }
    console.info("gmickel.gno-recall: status cancelled gen=" + collectionsGenerationId
      + " reason=" + String(reason || "cancel")
      + " dropped=" + _runningStatusGen)
  }

  function runStatus() {
    collectionsGenerationId += 1
    var gen = collectionsGenerationId
    collectionsMessage = ""
    collectionsLoading = true
    collectionsState = browseStateLoading
    _statusTimedOut = false
    console.info("gmickel.gno-recall: status request gen=" + gen)

    if (statusProcess.running) {
      _pendingStatusGen = gen
      killProcessGroup(statusProcess, "-TERM")
      statusForceKillTimer.restart()
      console.info("gmickel.gno-recall: status cancel-inflight running=" + _runningStatusGen
        + " pending=" + gen)
      return
    }
    startStatusProcess(gen)
  }

  function startStatusProcess(gen) {
    _runningStatusGen = gen
    _pendingStatusGen = 0
    _statusStarted = false
    _statusTimedOut = false
    _statusOversized = false
    _statusStdout = ""
    _statusStderr = ""
    statusKillTimer.stop()
    statusForceKillTimer.stop()

    if (resolvedGnoPath === "") {
      collectionsLoading = false
      collectionsState = browseStateError
      collectionsMessage = "gno path is not resolved"
      console.info("gmickel.gno-recall: status error gen=" + gen + " message=" + collectionsMessage)
      return
    }

    statusProcess.command = isolateCommand([resolvedGnoPath, "status", "--json"])
    statusProcess.running = true
    statusKillTimer.interval = statusTimeoutMs
    statusKillTimer.restart()
    console.info("gmickel.gno-recall: status start gen=" + gen
      + " argv=[" + resolvedGnoPath + ", status, --json]")
  }

  function handleStatusExit(exitCode) {
    statusKillTimer.stop()
    statusForceKillTimer.stop()
    var finishedGen = _runningStatusGen
    var pendingGen = _pendingStatusGen
    var stdout = String(_statusStdout || "")
    var stderr = String(_statusStderr || "")
    var timedOut = _statusTimedOut
    var started = _statusStarted
    var oversized = _statusOversized
    _runningStatusGen = 0
    _pendingStatusGen = 0
    _statusTimedOut = false
    _statusOversized = false

    if (pendingGen !== 0 && pendingGen === collectionsGenerationId) {
      console.info("gmickel.gno-recall: status late-drop gen=" + finishedGen
        + " current=" + collectionsGenerationId
        + " starting pending gen=" + pendingGen)
      startStatusProcess(pendingGen)
      return
    }

    if (finishedGen !== collectionsGenerationId) {
      console.info("gmickel.gno-recall: status late-drop gen=" + finishedGen
        + " current=" + collectionsGenerationId)
      return
    }

    collectionsLoading = false

    if (timedOut) {
      collectionsState = browseStateTimeout
      collectionsMessage = "Timed out listing collections"
      console.info("gmickel.gno-recall: status timeout gen=" + finishedGen)
      return
    }
    if (!started) {
      collectionsState = browseStateError
      collectionsMessage = "Failed to start gno status"
      console.info("gmickel.gno-recall: status spawn-failure gen=" + finishedGen)
      return
    }
    if (oversized
        || !stdoutWithinBound(stdout, maxStatusStdoutChars, "status")
        || !stdoutWithinBound(stderr, maxStatusStdoutChars, "status-stderr")) {
      collectionsState = browseStateError
      collectionsMessage = "gno status output exceeded the size bound"
      console.info("gmickel.gno-recall: status error gen=" + finishedGen + " message=" + collectionsMessage)
      return
    }

    if (exitCode !== 0) {
      var errObj = errorPayload(stderr, stdout)
      collectionsState = browseStateError
      collectionsMessage = errorDetail(errObj, stderr, stdout, "gno status failed")
      console.info("gmickel.gno-recall: status error gen=" + finishedGen
        + " exit=" + exitCode + " message=" + collectionsMessage)
      return
    }

    var data = parseJsonObject(stdout)
    if (!data || !Array.isArray(data.collections)) {
      collectionsState = browseStateError
      collectionsMessage = "gno status returned unreadable or incomplete JSON"
      console.info("gmickel.gno-recall: status malformed-json gen=" + finishedGen)
      return
    }

    var rows = normalizeCollections(data)
    collections = rows
    lastGoodCollections = rows
    lastStatusAt = new Date().toISOString()
    collectionsMessage = ""
    collectionsState = rows.length === 0 ? browseStateEmpty : browseStateReady
    console.info("gmickel.gno-recall: status ok gen=" + finishedGen
      + " collections=" + rows.length)
  }

  function cancelLs(reason) {
    lsGenerationId += 1
    _pendingLsCollection = ""
    _pendingLsPath = ""
    _pendingLsOffset = 0
    _pendingLsGen = 0
    _pendingLsDocCount = 0
    lsKillTimer.stop()
    if (lsProcess.running) {
      _lsTimedOut = false
      killProcessGroup(lsProcess, "-TERM")
      lsForceKillTimer.restart()
    } else {
      lsForceKillTimer.stop()
    }
    lsLoading = false
    if (lsState === browseStateLoading) {
      lsState = lsDocuments && lsDocuments.length > 0 ? browseStateReady : browseStateIdle
      lsMessage = ""
    }
    console.info("gmickel.gno-recall: ls cancelled gen=" + lsGenerationId
      + " reason=" + String(reason || "cancel")
      + " dropped=" + _runningLsGen)
  }

  function runLs(collection, offset) {
    var name = String(collection || "").trim()
    var off = parseInt(offset, 10)
    if (!isFinite(off) || off < 0)
      off = 0
    if (name === "")
      return

    var cached = collectionByName(name)
    var collectionPath = cached ? String(cached.path || "") : String(lsCollectionPath || "")
    var docCount = cached && isFiniteNumber(cached.documentCount)
      ? cached.documentCount
      : (name === lsCollection ? lsDocumentCount : 0)

    lsGenerationId += 1
    var gen = lsGenerationId
    var changing = name !== lsCollection || off === 0
    if (changing) {
      lsDocuments = []
      lsHasMore = false
      lsOffset = 0
    }
    lsCollection = name
    lsCollectionPath = collectionPath
    lsDocumentCount = docCount
    lsMessage = ""
    lsLoading = true
    lsState = browseStateLoading
    _lsTimedOut = false
    console.info("gmickel.gno-recall: ls request gen=" + gen
      + " collection=" + name + " offset=" + off)

    if (lsProcess.running) {
      _pendingLsCollection = name
      _pendingLsPath = collectionPath
      _pendingLsOffset = off
      _pendingLsGen = gen
      _pendingLsDocCount = docCount
      killProcessGroup(lsProcess, "-TERM")
      lsForceKillTimer.restart()
      console.info("gmickel.gno-recall: ls cancel-inflight running=" + _runningLsGen
        + " pending=" + gen)
      return
    }
    startLsProcess(name, collectionPath, off, gen, docCount)
  }

  function startLsProcess(collection, collectionPath, offset, gen, docCount) {
    _runningLsGen = gen
    _pendingLsCollection = ""
    _pendingLsPath = ""
    _pendingLsOffset = 0
    _pendingLsGen = 0
    _pendingLsDocCount = 0
    _lsStarted = false
    _lsTimedOut = false
    _lsOversized = false
    _lsStdout = ""
    _lsStderr = ""
    _lsAppend = offset > 0
    lsKillTimer.stop()
    lsForceKillTimer.stop()

    if (resolvedGnoPath === "") {
      lsLoading = false
      lsState = browseStateError
      lsMessage = "gno path is not resolved"
      console.info("gmickel.gno-recall: ls error gen=" + gen + " message=" + lsMessage)
      return
    }

    var argv = [
      resolvedGnoPath,
      "ls",
      collection,
      "--json",
      "-n",
      String(lsPageSize)
    ]
    // gno 1.36.0 rejects --offset 0 ("must be positive"); omit it on page 1.
    if (offset > 0)
      argv.push("--offset", String(offset))
    lsProcess.command = isolateCommand(argv)
    lsProcess.running = true
    lsKillTimer.interval = lsTimeoutMs
    lsKillTimer.restart()
    console.info("gmickel.gno-recall: ls start gen=" + gen
      + " argv=[" + argv.join(", ") + "]")
  }

  function handleLsExit(exitCode) {
    lsKillTimer.stop()
    lsForceKillTimer.stop()
    var finishedGen = _runningLsGen
    var pendingCollection = _pendingLsCollection
    var pendingPath = _pendingLsPath
    var pendingOffset = _pendingLsOffset
    var pendingGen = _pendingLsGen
    var pendingDocCount = _pendingLsDocCount
    var stdout = String(_lsStdout || "")
    var stderr = String(_lsStderr || "")
    var timedOut = _lsTimedOut
    var started = _lsStarted
    var oversized = _lsOversized
    var append = _lsAppend
    _runningLsGen = 0
    _pendingLsCollection = ""
    _pendingLsPath = ""
    _pendingLsOffset = 0
    _pendingLsGen = 0
    _pendingLsDocCount = 0
    _lsTimedOut = false
    _lsOversized = false
    _lsAppend = false

    if (pendingCollection !== "" && pendingGen === lsGenerationId) {
      lsCollection = pendingCollection
      lsCollectionPath = pendingPath
      lsDocumentCount = pendingDocCount
      console.info("gmickel.gno-recall: ls late-drop gen=" + finishedGen
        + " current=" + lsGenerationId
        + " starting pending gen=" + pendingGen)
      startLsProcess(pendingCollection, pendingPath, pendingOffset, pendingGen, pendingDocCount)
      return
    }

    if (finishedGen !== lsGenerationId) {
      console.info("gmickel.gno-recall: ls late-drop gen=" + finishedGen
        + " current=" + lsGenerationId)
      return
    }

    lsLoading = false

    if (timedOut) {
      if (!append)
        lsDocuments = []
      lsHasMore = false
      lsState = browseStateTimeout
      lsMessage = "Timed out listing documents"
      console.info("gmickel.gno-recall: ls timeout gen=" + finishedGen)
      return
    }
    if (!started) {
      if (!append)
        lsDocuments = []
      lsHasMore = false
      lsState = browseStateError
      lsMessage = "Failed to start gno ls"
      console.info("gmickel.gno-recall: ls spawn-failure gen=" + finishedGen)
      return
    }
    if (oversized
        || !stdoutWithinBound(stdout, maxLsStdoutChars, "ls")
        || !stdoutWithinBound(stderr, maxLsStdoutChars, "ls-stderr")) {
      if (!append)
        lsDocuments = []
      lsHasMore = false
      lsState = browseStateError
      lsMessage = "gno ls output exceeded the size bound"
      console.info("gmickel.gno-recall: ls error gen=" + finishedGen + " message=" + lsMessage)
      return
    }

    if (exitCode !== 0) {
      var errObj = errorPayload(stderr, stdout)
      if (!append)
        lsDocuments = []
      lsHasMore = false
      lsState = browseStateError
      lsMessage = errorDetail(errObj, stderr, stdout, "gno ls failed")
      console.info("gmickel.gno-recall: ls error gen=" + finishedGen
        + " exit=" + exitCode + " message=" + lsMessage)
      return
    }

    var data = parseJsonObject(stdout)
    if (!data || !Array.isArray(data.documents)) {
      if (!append)
        lsDocuments = []
      lsHasMore = false
      lsState = browseStateError
      lsMessage = "gno ls returned unreadable or incomplete JSON"
      console.info("gmickel.gno-recall: ls malformed-json gen=" + finishedGen)
      return
    }

    var page = normalizeLsDocuments(data, lsCollection, lsCollectionPath)
    var merged = []
    if (append) {
      var existing = lsDocuments || []
      for (var i = 0; i < existing.length; i++)
        merged.push(existing[i])
    }
    for (var p = 0; p < page.length; p++)
      merged.push(page[p])
    lsDocuments = merged
    lsOffset = merged.length
    var meta = data.meta && typeof data.meta === "object" ? data.meta : null
    var total = meta ? parseInt(meta.total, 10) : NaN
    if (isFinite(total))
      lsDocumentCount = total
    lsHasMore = inferLsHasMore(data, page, merged.length)
    lsMessage = ""
    lsState = merged.length === 0 ? browseStateEmpty : browseStateReady
    console.info("gmickel.gno-recall: ls ok gen=" + finishedGen
      + " collection=" + lsCollection
      + " rows=" + merged.length
      + " page=" + page.length
      + " hasMore=" + lsHasMore
      + " first=" + (merged.length > 0 ? merged[0].uri : ""))
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

  function rowCollectionPath(row) {
    if (!row)
      return ""
    var direct = String(row.collectionPath || "").trim()
    if (direct !== "")
      return direct
    var named = collectionByName(row.collection)
    return named ? String(named.path || "") : ""
  }

  function rowAbsPath(row) {
    if (!row)
      return ""
    var direct = String(row.absPath || "").trim()
    if (direct !== "")
      return direct
    var rel = String(row.relPath || "").trim()
    var colPath = String(row.collectionPath || "").trim()
    if (rel === "")
      return ""
    return browsedAbsPath(colPath, rel)
  }

  function rowUri(row) {
    if (!row)
      return ""
    return String(row.uri || "").trim()
  }

  function canOpenFile(rowOrPath) {
    if (rowOrPath && typeof rowOrPath === "object")
      return rowAbsPath(rowOrPath) !== ""
    return String(rowOrPath || "").trim() !== ""
  }

  function canOpenDocument(row) {
    if (canOpenFile(row))
      return true
    return serveIsRunning() && serveHomeUrl() !== "" && rowUri(row) !== ""
  }

  function missingPathGuidance() {
    return "No file path — start gno serve --detach to open in the web UI."
  }

  function showMissingPathGuidance(kind) {
    lastOpenKind = String(kind || "document")
    lastOpenArgv = []
    lastOpenOk = false
    setActionStatus(missingPathGuidance())
    console.info("gmickel.gno-recall: open-document guidance missing-abspath serve-down")
    return false
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

  function launchArgv(argv, kind, successNotice) {
    var list = []
    var source = argv || []
    for (var i = 0; i < source.length; i++)
      list.push(String(source[i]))
    lastOpenKind = String(kind || "")
    lastOpenArgv = list
    lastOpenOk = false
    lastOpenMessage = ""
    _pendingOpenNotice = String(successNotice || "")
    console.info("gmickel.gno-recall: exec argv=[" + formatArgv(list) + "] kind=" + lastOpenKind)

    if (list.length === 0) {
      finishOpenFailure("No opener command")
      return false
    }

    if (openProbeProcess.running) {
      // A second open while the probe is in flight still launches argv-safe.
      detachOpen(list)
      lastOpenOk = true
      setActionStatus(_pendingOpenNotice)
      return true
    }

    _openStarted = false
    _openTimedOut = false
    _openKind = lastOpenKind
    _pendingOpenArgv = list
    _pendingOpenKind = lastOpenKind
    var binary = list[0]
    if (binary.indexOf("/") === 0)
      openProbeProcess.command = ["/usr/bin/test", "-x", binary]
    else
      openProbeProcess.command = ["/usr/bin/which", binary]
    openProbeProcess.running = true
    openProbeKillTimer.interval = openProbeTimeoutMs
    openProbeKillTimer.restart()
    return true
  }

  function detachOpen(argv) {
    // Login shell + constant `exec "$@"` — same argv-safe pattern as Util.execArgv.
    // GUI handlers (omawrite / gio / xdg-open) need the session PATH/env.
    Quickshell.execDetached(["bash", "-lc", 'exec "$@"', "bash"].concat(argv))
  }

  function handleOpenProbe(exitCode) {
    openProbeKillTimer.stop()
    openProbeForceKillTimer.stop()
    var argv = _pendingOpenArgv
    var kind = _pendingOpenKind
    var timedOut = _openTimedOut
    _pendingOpenArgv = []
    _pendingOpenKind = ""
    _openTimedOut = false
    if (timedOut || !_openStarted || exitCode !== 0) {
      finishOpenFailure("Could not start " + (kind || "file") + " opener")
      return
    }
    detachOpen(argv)
    lastOpenOk = true
    lastOpenMessage = ""
    setActionStatus(_pendingOpenNotice)
    _pendingOpenNotice = ""
    console.info("gmickel.gno-recall: open-ok kind=" + kind
      + " argv=[" + formatArgv(argv) + "]")
  }

  function finishOpenFailure(detail) {
    lastOpenOk = false
    _pendingOpenNotice = ""
    setActionStatus(String(detail || "Could not start opener"))
    console.info("gmickel.gno-recall: open-fail kind=" + lastOpenKind
      + " message=" + lastOpenMessage
      + " argv=[" + formatArgv(lastOpenArgv) + "]")
  }

  function openSourceFile(absPath, collectionPath) {
    var path = String(absPath || "").trim()
    if (path === "")
      return showMissingPathGuidance("file")
    var root = String(collectionPath || "").trim()
    if (root === "")
      return showMissingPathGuidance("file")
    var contained = [
      pluginScript("scripts/open-contained.sh"),
      root,
      path,
      "--"
    ]
    if (fileOpenerOverride !== "")
      return launchArgv(contained.concat([fileOpenerOverride]), "file")
    return launchArgv(contained.concat(["bash", "-lc", defaultFileOpenScript, "bash"]), "file")
  }

  function openDocument(row) {
    var path = rowAbsPath(row)
    if (path !== "")
      return openSourceFile(path, rowCollectionPath(row))

    var uri = rowUri(row)
    if (serveIsRunning() && serveHomeUrl() !== "" && uri !== "") {
      console.info("gmickel.gno-recall: open-document fallback-web uri=" + uri)
      return openWebUi(uri, "Opened in web UI")
    }

    return showMissingPathGuidance("document")
  }

  function openWebUi(uri, successNotice) {
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
    return launchArgv([resolveBrowserOpener(), webDocUrl(value)], "web", successNotice)
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
    killProcessGroup(proc, "-TERM")
    forceTimer.restart()
  }

  function killSearchProcess() {
    if (!searchProcess.running)
      return
    _searchTimedOut = true
    killProcessGroup(searchProcess, "-TERM")
    searchForceKillTimer.restart()
  }

  function killStatusProcess() {
    if (!statusProcess.running)
      return
    _statusTimedOut = true
    killProcessGroup(statusProcess, "-TERM")
    statusForceKillTimer.restart()
  }

  function killLsProcess() {
    if (!lsProcess.running)
      return
    _lsTimedOut = true
    killProcessGroup(lsProcess, "-TERM")
    lsForceKillTimer.restart()
  }

  function killOpenProbeProcess() {
    if (!openProbeProcess.running)
      return
    _openTimedOut = true
    killProcessGroup(openProbeProcess, "-TERM")
    openProbeForceKillTimer.restart()
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
    onTriggered: if (probeProcess.running) root.killProcessGroup(probeProcess, "-KILL")
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
    onTriggered: if (peekProcess.running) root.killProcessGroup(peekProcess, "-KILL")
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
    onTriggered: if (searchProcess.running) root.killProcessGroup(searchProcess, "-KILL")
  }

  Timer {
    id: statusKillTimer
    interval: root.statusTimeoutMs
    repeat: false
    onTriggered: root.killStatusProcess()
  }

  Timer {
    id: statusForceKillTimer
    interval: 1000
    repeat: false
    onTriggered: if (statusProcess.running) root.killProcessGroup(statusProcess, "-KILL")
  }

  Timer {
    id: lsKillTimer
    interval: root.lsTimeoutMs
    repeat: false
    onTriggered: root.killLsProcess()
  }

  Timer {
    id: lsForceKillTimer
    interval: 1000
    repeat: false
    onTriggered: if (lsProcess.running) root.killProcessGroup(lsProcess, "-KILL")
  }

  Timer {
    id: openProbeKillTimer
    interval: root.openProbeTimeoutMs
    repeat: false
    onTriggered: root.killOpenProbeProcess()
  }

  Timer {
    id: openProbeForceKillTimer
    interval: 1000
    repeat: false
    onTriggered: if (openProbeProcess.running) root.killProcessGroup(openProbeProcess, "-KILL")
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
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.takeProbeOutput(data, false) }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.takeProbeOutput(data, true) }
    }
    onStarted: root._started = true
    onRunningChanged: {
      if (!running && root._phase !== "peek" && root._phase !== "" && !root._started && !root._timedOut) {
        probeKillTimer.stop()
        if (root.peekGenIsStale(root._runningPeekGen)) {
          root.loading = false
          root.finishIdle()
          return
        }
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
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.takePeekOutput(data, false) }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.takePeekOutput(data, true) }
    }
    onStarted: root._started = true
    onRunningChanged: {
      if (!running && root._phase === "peek" && !root._started && !root._timedOut) {
        peekKillTimer.stop()
        if (root.peekGenIsStale(root._runningPeekGen)) {
          root.loading = false
          root.finishIdle()
          return
        }
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
    stdinEnabled: true
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.takeSearchOutput(data, false) }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.takeSearchOutput(data, true) }
    }
    onStarted: {
      root._searchStarted = true
      if (root._pendingSearchStdin !== "") {
        write(root._pendingSearchStdin + "\n")
        root._pendingSearchStdin = ""
      }
    }
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
    id: statusProcess
    running: false
    command: []
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.takeStatusOutput(data, false) }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.takeStatusOutput(data, true) }
    }
    onStarted: root._statusStarted = true
    onRunningChanged: {
      if (!running && root._runningStatusGen !== 0 && !root._statusStarted && !root._statusTimedOut) {
        statusKillTimer.stop()
        root.handleStatusExit(1)
      }
    }
    onExited: function(exitCode) {
      root.handleStatusExit(exitCode)
    }
  }

  Process {
    id: lsProcess
    running: false
    command: []
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.takeLsOutput(data, false) }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.takeLsOutput(data, true) }
    }
    onStarted: root._lsStarted = true
    onRunningChanged: {
      if (!running && root._runningLsGen !== 0 && !root._lsStarted && !root._lsTimedOut) {
        lsKillTimer.stop()
        root.handleLsExit(1)
      }
    }
    onExited: function(exitCode) {
      root.handleLsExit(exitCode)
    }
  }

  Process {
    id: openProbeProcess
    running: false
    command: []
    onStarted: root._openStarted = true
    onRunningChanged: {
      if (!running && !root._openStarted && root._pendingOpenArgv && root._pendingOpenArgv.length > 0) {
        openProbeKillTimer.stop()
        openProbeForceKillTimer.stop()
        root.finishOpenFailure("Could not start " + (root._pendingOpenKind || "file") + " opener")
        root._pendingOpenArgv = []
        root._pendingOpenKind = ""
        root._openTimedOut = false
      }
    }
    onExited: function(exitCode) {
      root.handleOpenProbe(exitCode)
    }
  }
}
