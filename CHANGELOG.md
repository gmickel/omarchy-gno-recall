# Changelog

## 1.1.1

- Bound every runtime archive download to its committed compressed byte size and
  a hard 300-second deadline covering connection, headers and body. Reject
  oversized, truncated, stalled and slow-drip responses; clean up partial files
  before reporting failure. Thanks to [@HANCORE-linux](https://github.com/HANCORE-linux)
  for the [download-bound review](https://github.com/omacom/omarchy-plugin-marketplace/issues/3590#issuecomment-5672167746).
- Record hash-verified archive sizes without changing GNO/Bun/dependency pins or
  installed runtime contents. Run `./scripts/install-runtime.sh` after updating:
  the changed trust manifest selects a new runtime directory. Existing runtimes
  and GNO config/index/models remain intact.

## 1.1.0

- Replace global/PATH-configured GNO execution with a dedicated, hash-locked GNO
  2.2.1 and Bun 1.4.2 runtime, including its Linux x86_64 native dependencies.
  Installation is explicit; every invocation verifies the entire installed tree.
  Thanks to [@HANCORE-linux](https://github.com/HANCORE-linux) for the
  [marketplace security review](https://github.com/omacom/omarchy-plugin-marketplace/issues/3590#issuecomment-5642540040).
- Remove the `gnoPath` setting. Existing values are ignored; install the verified
  runtime and refresh the plugin after upgrading.
- Fix first-use deep search JSON contamination from upstream model-resolution
  progress. Two documented source patches have exact before/after hashes:
  quiet model resolution and disabling the native worker's external Bun cache.
- Stop including query text in search diagnostics. Preserve query-file privacy,
  cancellation, file containment and panel focus behavior.
- Document installation, explicit runtime upgrades, integrity recovery, rollback,
  supported platforms and shared-index schema compatibility.

This release addresses the requested verification design; marketplace approval
remains subject to the maintainer's review of the resulting commit.
