import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

function handlers(file, names) {
  const source = readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');
  return names.map(name => {
    const match = source.match(new RegExp(`  function ${name}\\([^]*?\\n  }`));
    assert.ok(match, `Missing ${name}`);
    return match[0];
  }).join('\n');
}

const data = mkdtempSync(join(tmpdir(), 'recall-runtime-ui-'));
try {
  const result = spawnSync(fileURLToPath(new URL('./verified-gno.sh', import.meta.url)), ['peek', '--json'], {
    env: { ...process.env, XDG_DATA_HOME: data }, encoding: 'utf8',
  });
  assert.equal(result.status, 78);
  let state;
  let liveSnapshot = { initialized: true };
  const context = vm.createContext({
    stderr: result.stderr, stateRuntimeError: 'runtime-error',
    dropLiveSnapshot() { liveSnapshot = null; },
    setState(next, message) { state = { next, message }; },
  });
  vm.runInContext(handlers('Service.qml', ['parseJsonObject', 'errorPayload', 'noteRuntimeFailure']), context);
  vm.runInContext('noteRuntimeFailure(errorPayload(stderr, ""))', context);
  assert.equal(state.next, 'runtime-error');
  assert.match(state.message, /runtime missing/);
  assert.equal(liveSnapshot, null);

  // Cached rows must not hide the new failure or replace the warning glyph.
  const overlay = vm.createContext({ runtimeBlocked: true, isStale: true });
  vm.runInContext(handlers('RecallOverlay.qml', ['resolveStatusLine']), overlay);
  assert.match(vm.runInContext('resolveStatusLine()', overlay), /Runtime blocked.*--repair.*cached rows/);
  const bar = vm.createContext({ serviceState: 'runtime-error', recallService: { runtimeBlocked: true } });
  vm.runInContext(handlers('BarWidget.qml', ['resolveVisualKind']), bar);
  assert.equal(vm.runInContext('resolveVisualKind()', bar), 'degraded');
} finally {
  rmSync(data, { recursive: true, force: true });
}
console.log('Runtime failure protocol and cached UI regression checks passed');
