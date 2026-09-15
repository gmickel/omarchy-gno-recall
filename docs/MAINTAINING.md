# Maintaining the verified runtime

Recall's runtime is a release dependency, not a user's global GNO installation.
Read this document before changing backend calls, interpreter/dependency versions,
installation, or verification. The reviewed plugin commit is the trust root.

## Files and boundary

- `runtime/package.json` pins the direct GNO and Bun versions.
- `runtime/package-lock.json` records npm's full resolved dependency graph.
- `runtime/trust-manifest.json` selects Linux x86_64 glibc artifacts from that graph,
  including native CPU, CUDA, Vulkan, SQLite and image/PDF dependencies. Every
  archive has its exact HTTPS URL, version, SHA-512 integrity value and compressed
  `sizeBytes`, measured from the archive only after verifying its digest.
- `runtime/patches.json` lists two reviewed backend source adjustments: disable
  node-llama-cpp CLI progress during model resolution so first-use deep search
  returns clean JSON, and disable the external Bun transpiler cache in native
  workers as well as the parent process. Exact before/after SHA-256 values guard
  each transformation.
- `scripts/build-runtime-manifest.py` downloads those archives, verifies integrity,
  extracts without lifecycle scripts, applies the hash-guarded patches, and
  computes the committed `treeSha256`. The manifest embeds the patch recipe.
- `scripts/runtime.py` uses only the system Python standard library to install
  and verify. Users do not need npm or a global Bun/GNO installation.
- `scripts/verified-gno.sh` is the only backend launcher used by `Service.qml`.
  Every invocation hashes the complete installed tree before executing Bun.

The tree hash covers every relative path, directory, regular-file content hash and
normalized permission mode. Missing, added, changed, linked, or special files
fail verification. Directory ownership and writable-by-others modes are rejected.
Ancestor `node_modules` directories are refused so dependency resolution cannot
fall back outside the verified installation. Environment loader/preload options
are removed; Bun runs from the verified directory with its explicit config,
`.env` loading and automatic installation disabled. Native builds/downloads are
disabled; only included native packages are candidates. GNO 2.2.1 search/query
run in the CLI and do not delegate to a user's separately running resident.

Installation downloads at most eight archives concurrently, verifies them before extraction,
then verifies the resulting complete tree before an atomic rename into place.
It never executes package lifecycle scripts. The manifest content determines the
installation directory, so a new plugin manifest cannot silently use an old
runtime. Install is idempotent. `--repair` stages a verified replacement first
and retains the old tree under `.quarantine-<pid>`; a failed download or check
leaves the old tree intact. A shared/exclusive file lock coordinates launch and
installation. Keep the current manifest and runtime together when rolling back.

Each download has a **300-second total deadline**, supervised by the parent using
an isolated Python subprocess. A timeout kills and reaps that process, then removes
the partial archive; DNS, connection, TLS, header waits and slow body delivery
cannot extend the deadline. The socket's 120-second idle timeout is secondary.
Streaming writes never exceed the committed `sizeBytes`; EOF must match exactly,
and the checksum must still match. `Content-Length` is optional and never grants
more bytes; a declared mismatch fails immediately. A failed batch starts no more
queued downloads; at most the other seven already-started transfers finish under
their own deadlines before staging is removed. No partial runtime is activated.

The maintainer generator uses the same subprocess deadline, with a **2 GiB
per-archive discovery ceiling** because a candidate size is not known yet. It
records `sizeBytes` only after complete checksum verification, never from HTTP
headers. This ceiling is for generation only; user installation always requires
the exact committed size. Raising either bound requires a reviewed source change.
For GNO 2.2.1/Bun 1.4.2, 542 dependency paths share 532 archives totaling
566,812,950 compressed bytes. The largest is the 174,373,281-byte CUDA extension;
its 300-second budget requires roughly 0.6 MB/s sustained transfer speed.

This is provenance/integrity verification, not a sandbox. The plugin checkout,
OS Python/bash/utilities, kernel, dynamic loader, system libraries and GPU drivers
remain trusted. It does not protect against a compromised account rewriting the
verifier/manifest or racing a file change after verification. GGUF models and
GNO config/index/document data stay in their usual locations and are not runtime
code artifacts; model accuracy/content is not vouched for by the runtime hash.
The shell's existing document/browser opener boundary remains unchanged.

## Upgrade procedure

1. Check current upstream GNO/Bun release notes, supported platforms, package
   provenance and native dependency compatibility. Review GNO CLI delegation,
   module/native loading, worker environment and migration behavior again.
   Do not copy checksums from a local global installation and call it trusted.
2. Edit the two exact versions in `runtime/package.json`. With a maintained npm,
   resolve a candidate lockfile **without scripts**, then inspect the entire
   dependency diff (including native packages and non-npm tarball URLs):

   ```bash
   npm install --prefix runtime --package-lock-only --ignore-scripts --no-audit --no-fund
   ```

3. Generate the candidate manifest from those immutable artifacts:

   ```bash
   python3 scripts/build-runtime-manifest.py runtime/package-lock.json --output runtime/trust-manifest.json
   ```

   This downloads hundreds of archives and extracts approximately 1.3 GiB for
   the initial release. It does not execute any downloaded code. Review the
   selected artifact list, measured byte sizes, version/integrity changes, resulting tree hash and
   package licenses. Reassess every `runtime/patches.json` entry on an upgrade;
   remove a patch once upstream includes the fix. A changed upstream source
   hash must fail generation until the patch has been explicitly reviewed. Archive extraction normalizes regular files to 0644/0755
   and directories to 0755, rejects links/traversal/special files, and follows
   last-entry semantics for duplicate regular entries in pinned npm tarballs.
   Do not manually adjust the tree hash to bless a failing installed tree.
   A metadata-only manifest change (including adding or correcting `sizeBytes`)
   changes the runtime directory identity even when `treeSha256` stays identical.
   Tell users to rerun `scripts/install-runtime.sh` and refresh Recall after the
   update. Preserve the previous plugin/manifest/runtime together for rollback.
4. Install under an isolated absolute `XDG_DATA_HOME` and use isolated
   `GNO_CONFIG_DIR`, `GNO_DATA_DIR`, `GNO_CACHE_DIR` and synthetic documents.
   Run `python3 scripts/test-runtime.py`, `python3 scripts/test-downloads.py`,
   `node scripts/test-service-runtime.mjs`,
   `node scripts/test-panel-focus.mjs`, `python3 scripts/test-marketplace-layout.py`,
   shell syntax checks, and `python3 scripts/smoke-runtime.py`. Run
   `python3 scripts/smoke-runtime.py --models-dir /absolute/path/to/gno/cache/models`
   to exercise fresh model metadata using existing GGUF files without copying
   the existing cache manifest. This catches first-use JSON contamination. Test actual
   model-backed deep search with the supported native backends available on
   the QA machine. CI's synthetic unit tests do not prove GPU compatibility.
5. Verify native Omarchy panel open/close/focus, fast/deep search, cancellation,
   collection pagination, document containment, and visible integrity failure.
   Tamper with a **test** runtime, confirm execution is refused, repair it,
   and confirm recovery. Preserve production config, data and session state.
6. Check index schema compatibility using copies/synthetic fixtures before
   adopting a runtime against an existing index. GNO may migrate older indexes
   when opening them; reverting executable files does not undo a database
   migration. Never test migrations against the user's only copy of an index.
   Document any supported migration or export/reindex step in release notes.
7. Update `manifest.json`'s plugin version, README requirements and release
   notes. Keep user install/update/recovery instructions accurate. Commit the
   lockfile, trust manifest, launcher changes, tests and docs together. Keep
   `.flow/` local and gitignored; do not add project automation scaffolding.
8. Publish through the repository PR/CI workflow. On marketplace issue **#3590**,
   provide the exact resulting commit SHA, pinning/verification entry points,
   artifact provenance and actual QA evidence; request fresh validation/security
   review on that same issue. A green CI or `validated` label is not security
   approval. Do not claim approval until the maintainer gives it.

## Marketplace repository layout

Reserve `manifest.json` for the plugin at the repository root. The marketplace
[discovery rule](https://github.com/omacom/omarchy-plugin-marketplace/blob/aca841ea0d7ecc72553b1c7939549c813dad3997/scripts/build-catalog.mjs#L1648-L1658)
counts that filename case-insensitively at the root and one directory below it,
before inspecting its contents. A runtime file with that name makes this
single-plugin submission fail validation. Keep the runtime lock at
`runtime/trust-manifest.json`; changing its path alone preserves its bytes,
runtime identity and existing installations.

`python3 scripts/test-marketplace-layout.py` checks Git's tracked paths against
that rule and reserves the filename at every depth. CI also checks a clean
`git archive` export with `--export <directory>` and verifies plugin entry points.
Run this check after staging any manifest rename or addition.

## Rollback and support

Revert the complete plugin release to its prior reviewed commit, then run that
checkout's installer. Its manifest selects its own previous runtime directory.
Keep old runtimes until rollback is no longer needed; removal is a separate,
explicit user action. Do not point `gnoPath` at another executable or add a
verification bypass for troubleshooting. Existing `gnoPath` settings are ignored.

Users sharing an index with a newer global GNO must stop before downgrading its
reader/writer. Check schema compatibility and back up data using GNO's supported
procedure; if incompatible, wait for a reviewed Recall runtime upgrade or use a
separate compatible index. Global `bun update`/`gno` upgrades do not update Recall.
