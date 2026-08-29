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
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 900, 60, 3600)

  readonly property string stateNotFound: "not-found"
  readonly property string stateNotExecutable: "not-executable"
  readonly property string stateSpawnFailure: "spawn-failure"
  readonly property string stateTimeout: "timeout"
  readonly property string stateMalformedJson: "malformed-json"
  readonly property string stateUnknownCommand: "unknown-command"
  readonly property string stateVersionSkew: "version-skew"
  readonly property string stateReady: "ready"
  readonly property string stateLoading: "loading"

  property string state: "loading"
  property string message: ""
  property string resolvedGnoPath: ""
  property var snapshot: null
  property var lastGoodSnapshot: null
  property int generationId: 0
  property bool loading: false
  property string lastPeekAt: ""

  property string _phase: ""
  property string _stdout: ""
  property string _stderr: ""
  property bool _started: false
  property bool _timedOut: false
  property bool _refreshQueued: false

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
      stale: snapshot === null && lastGoodSnapshot !== null
    })
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
      loading = false
      setState(stateTimeout, "Timed out resolving gno")
      finishIdle()
      return
    }
    if (!_started) {
      loading = false
      setState(stateSpawnFailure, "Failed to start gno discovery")
      finishIdle()
      return
    }

    if (_phase === "which") {
      if (exitCode !== 0 || stdout === "") {
        loading = false
        setState(stateNotFound, "gno was not found on PATH")
        finishIdle()
        return
      }
      if (stdout.charAt(0) !== "/") {
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
        loading = false
        setState(stateNotExecutable, "gno is not executable: " + resolvedGnoPath)
        finishIdle()
        return
      }
      startPeek(resolvedGnoPath)
      return
    }

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
      setState(stateTimeout, "Timed out running gno peek --json")
      finishIdle()
      return
    }
    if (!_started) {
      setState(stateSpawnFailure, "Failed to start gno peek --json")
      finishIdle()
      return
    }
    if (stdout.length > maxStdoutChars || stderr.length > maxStdoutChars) {
      setState(stateMalformedJson, "gno peek output exceeded the size bound")
      finishIdle()
      return
    }

    var errObj = parseJsonObject(stderr)
    if (isUnknownCommand(stderr, errObj)) {
      setState(stateUnknownCommand, "gno does not provide peek; install gno >= " + supportedGnoFloor)
      finishIdle()
      return
    }

    if (exitCode !== 0) {
      var fail = errObj && errObj.error ? errObj.error : null
      var detail = fail && fail.message ? String(fail.message) : (stderr.trim() || "gno peek failed")
      setState(stateSpawnFailure, detail)
      finishIdle()
      return
    }

    var data = parseJsonObject(stdout)
    if (!data || typeof data.schemaVersion !== "string" || typeof data.gnoVersion !== "string") {
      setState(stateMalformedJson, "gno peek returned unreadable or incomplete JSON")
      finishIdle()
      return
    }
    if (!versionAtLeast(data.gnoVersion, supportedGnoFloor)) {
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

  function killProcess(proc, forceTimer) {
    if (!proc.running)
      return
    _timedOut = true
    proc.signal(15)
    forceTimer.restart()
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
        root.loading = false
        root.setState(root.stateSpawnFailure, "Failed to start gno peek --json")
        root.finishIdle()
      }
    }
    onExited: function(exitCode) {
      root.handlePeekExit(exitCode)
    }
  }
}
