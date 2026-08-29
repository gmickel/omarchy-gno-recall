# GNO Recall

An [Omarchy](https://omarchy.org/) shell plugin that surfaces [GNO](https://gno.sh) index activity from the bar.

This repository is the plugin source. The bar widget is quiet when the index is healthy (a history glyph only) and adds a distinct shape plus color when there is backlog, staleness, or a setup/degraded fault. Left-click opens an anchored index panel; Super+R (after the optional keybind script) or `omarchy-shell shell toggle gmickel.gno-recall` summons the recall overlay.

## Requirements

- Omarchy with shell plugin support
- [gno](https://github.com/gmickel/gno) **>= 1.36.0** on `PATH`, or an absolute path in the widget's **Path to gno** setting
- A Nerd Font (Omarchy includes one by default)

`gno peek --json` is the snapshot path. Committed overlay search is a second argv-array call: `gno search <query> --json --no-project-affinity -n 20`. Collection browse uses `gno status --json` (collections list) and `gno ls <collection> --json -n 50 --offset <n>` (paginated documents). Released gno 1.36.0 ships `gno peek` (`schemaVersion` `peek@1.0`) and the GNO web UI `/doc?uri=` deep link (plus `source.absPath` on search hits). Older gno builds fail discovery with an `unknown-command` state instead of crashing the shell. The plugin never calls `gno get` or `gno serve`.

## Privilege boundary

Plugins run as **unsandboxed code inside `omarchy-shell`**. Adding a plugin clones files and toggles enabled state; it does not sandbox the QML. Only install repos you are willing to run in the long-lived shell process.

The installer **never runs hooks**. `omarchy plugin add` only clones files and toggles enabled state; it never runs plugin code. Super+R is a documented post-add script you run yourself (`scripts/install-keybind.sh`).

## Install

```bash
omarchy plugin add https://github.com/gmickel/omarchy-gno-recall --enable
```

The widget lands on the right side of the bar. The overlay is summonable immediately over IPC; Super+R is optional and is **not** installed by `plugin add`.

```bash
# From a checkout, after the plugin is added:
./scripts/install-keybind.sh
```

Move the widget with:

```bash
omarchy bar move gmickel.gno-recall --section right
```

### Update

```bash
omarchy plugin update gmickel.gno-recall
```

Or update every git-managed plugin:

```bash
omarchy plugin update
```

### Remove

```bash
omarchy plugin remove gmickel.gno-recall
```

## Settings

| Setting | Default | Meaning |
| --- | --- | --- |
| Path to gno (`gnoPath`) | empty | Absolute path to `gno` (>= 1.36.0). Empty uses `PATH`. |
| Refresh interval (`refreshIntervalSec`) | 900 | Coarse poll interval in seconds (60–3600). |

```bash
omarchy bar set gmickel.gno-recall gnoPath ""
omarchy bar set gmickel.gno-recall refreshIntervalSec 900
```

## Local development

From a checkout of this repo:

```bash
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" Service.qml BarWidget.qml Panel.qml RecallOverlay.qml
omarchy plugin add "$PWD" --enable
./scripts/install-keybind.sh   # optional; skipped automatically if SUPER+R is taken
```

`OMARCHY_PATH` is typically `/usr/share/omarchy`. After add, the live copy is `~/.config/omarchy/plugins/gmickel.gno-recall`. The shell hot-reloads QML under that directory; `omarchy-shell shell rescanPlugins` forces a reload.

`qmllint` may report Quickshell-module false positives (`Quickshell.Io.Process`, `SplitParser`, `PanelWindow`) because those types come from the Quickshell runtime, not the Omarchy import path. Treat those as noise unless they point at real syntax errors.

## Cache and privacy

The last-good peek snapshot (titles, paths, snippets, and the last successful search list) lives **only in memory** on the `Service.qml` object, as do the collections list from `gno status` and any paginated `gno ls` page. Nothing is written to XDG state, `Qt.labs.settings`, or a FileView. A Quickshell restart (`omarchy restart shell`) drops the cache; the bar shows a loading/empty state until the next `gno peek` succeeds. When a refresh fails, surfaces keep the last-good rows and show a visible cache age from `lastSuccessfulRefreshAt` (for example `Showing last good · 2m ago`).

## How it works

`Service.qml` is the only `Process` owner. It resolves `gno` from the widget `gnoPath` (absolute) or `PATH`, then invokes `gno peek --json` as an argv array via `Quickshell.Io.Process` + `SplitParser` (empty `splitMarker`, raw-chunk accumulation with a 512KiB kill bound). Bar and overlay surfaces look the service up with `bar.shell.serviceFor("gmickel.gno-recall")` — third-party plugins must not use `firstPartyServiceFor`.

The overlay is the summonable surface (`omarchy-shell shell toggle gmickel.gno-recall`). It opens on the focused monitor, grabs exclusive keyboard focus, and shows cached peek `recent[]` immediately. Typing filters titles and URI tails in memory — no `gno` subprocess per keystroke. Enter on a query (before results land) runs exactly one search through `Service.qml`; a new Enter or a query change cancels the in-flight Process and drops late JSON via a search generation id.

**Browse collections** is a second overlay mode. From recents, **Tab** (or **Ctrl+B**) lists every collection from `gno status --json` (name + document count). Enter drills into a paginated `gno ls` document list (50 per page). A **Load more…** row (Enter, Right, or Page Down at the end) appends the next offset. Typing still filters in memory only — collection names on the list, already-loaded document titles/paths inside a collection. Esc walks back one step at a time: clear filter → documents back to collections → collections back to recents → dismiss via `shell.hide`. Backspace with an empty filter also steps back a browse level without dismissing.

`omarchy-shell shell summon gmickel.gno-recall '{"mode":"collections"}'` opens the overlay directly on the collections list. The panel **Browse collections** action uses that payload.

Rows show title (URI-tail fallback), collection (peek field for recents, `gno://<collection>/…` for search hits, `source.relPath` for browsed documents), snippet, and modified time. Browsed documents derive `absPath` by joining the collection's absolute `path` with `source.relPath` — the plugin never calls `gno get`. Arrow keys (and `j`/`k` when the filter is empty) move the highlight. Search, status, and ls failure/timeout stay inline and keep the overlay interactive; empty collections and empty-but-initialized indexes have distinct copy from uninitialized guidance.

### Summon: Super+R, IPC, and alternatives

The overlay toggle is already on the shell IPC contract — no second `IpcHandler` in this plugin:

```bash
omarchy-shell shell toggle gmickel.gno-recall
omarchy-shell shell summon gmickel.gno-recall
omarchy-shell shell summon gmickel.gno-recall '{"mode":"collections"}'
omarchy-shell shell hide gmickel.gno-recall
```

Default chord is **Super+R** ("Recall"). It is free against Omarchy Quattro defaults, but the install script still checks the live session (`omarchy menu keybindings --print` and `hyprctl binds` plain text — `hyprctl -j binds` is unreliable).

| Result | Script behavior |
| --- | --- |
| Super+R free | Appends `o.bind("SUPER + R", "GNO Recall", "omarchy-shell shell toggle gmickel.gno-recall")` to `~/.config/hypr/bindings.lua` |
| Super+R already this bind | Prints that it is installed and writes nothing (idempotent) |
| Super+R taken by something else | Prints the conflicting bind, writes nothing, exits 1. Summon stays unbound. Never `hl.unbind`. |

If the script exits 1, keep using the IPC one-liner or bind a free chord yourself.

**Alternatives:** Super+G is taken by Omarchy's window-grouping default. Super+N is often free on Quattro, but collided with the editor bind on pre-Quattro Omarchy — treat it as a last-resort chord and re-check your own `bindings.lua` first.

### Open actions

Both the overlay rows and the panel recents list share `Service.qml`'s `openDocument(row)`. Enter on a document row always tries to open something: the source file when `absPath` is present or derivable, otherwise the web UI deep link when `serve.running`, otherwise a non-blocking guidance notice. The plugin never calls `gno get` and never starts `gno serve`.

**Enter / click** (primary open via `openDocument`):

| Condition | Outcome |
| --- | --- |
| `absPath` present or joined from `collection.path` + `source.relPath` | Open the source file (text: `$VISUAL` / omawrite; else `gio open` / `xdg-open`) |
| No `absPath`, `serve.running` | Open `{serve.url}/doc?uri=<encodeURIComponent(uri)>` (success; brief “Opened in web UI”) |
| No `absPath`, serve down | Notice: `No file path — start gno serve --detach to open in the web UI.` Nothing is spawned. |

**Open matrix** (row type × key × outcome):

| Row | Enter / click | Ctrl+Enter | w |
| --- | --- | --- | --- |
| Overlay recents | file, else fallback-to-web, else guidance | web (guidance if serve down) | — |
| Overlay search hits | file, else fallback-to-web, else guidance | web (guidance if serve down) | — |
| Overlay browsed docs | file (joined absPath), else fallback-to-web, else guidance | web (guidance if serve down) | — |
| Overlay collection | drill-in | — | — |
| Overlay Load more… | load next page | — | — |
| Panel recents | file, else fallback-to-web, else guidance | — | web (guidance if serve down) |
| Panel “Open GNO web UI” | home URL when serve is up; disabled when down | — | — |

### Overlay keys

| Key | Recents | Collections | Documents |
| --- | --- | --- | --- |
| Type / Backspace | Filter recents in memory | Filter collection names | Filter loaded rows |
| Enter | Search if a filter is typed; otherwise open the document | Open the highlighted collection | Open the document (or load the next page on **Load more…**) |
| Ctrl+Enter | Open web UI | — | Open web UI |
| Tab / Ctrl+B | Switch to collections | — | — |
| Esc | Clear filter, then dismiss | Clear filter, then back to recents | Clear filter, then back to collections |
| Backspace (empty filter) | — | Back to recents | Back to collections |
| Page Down / Right | Jump highlight | Jump highlight | Load more when the page is full |

File-open uses the row's `absPath` (peek recents use `absPath`; search hits use `source.absPath`; browsed docs join `collection.path` + `source.relPath`). With no `fileOpener` override, a login-shell trampoline (`bash -lc`, so **not** `.zshrc`) picks the handler: text-like files (`md`, `markdown`, `txt`, `org`, `rst`, `adoc`, `text`) honor `$VISUAL` when it is set in that environment (TUI editors such as nvim via `omarchy-launch-tui` so a terminal is visible; GUI editors via `uwsm-app`), otherwise **omawrite** on a stock Omarchy install, then `omarchy-launch-editor`, then `gio open` / `xdg-open`. Non-text files go straight to `gio open` (proper mime) or `xdg-open`. Raw `xdg-open` alone is what used to open markdown as headless nvim. Set `VISUAL` in a login-visible place (`~/.profile`, `.zprofile`, or uwsm env) if you want your editor to win for text docs. The `fileOpener` override still skips the chain. Explicit web-open (Ctrl+Enter / **w**) launches `omarchy-launch-browser` at `{serve.url}/doc?uri=<encodeURIComponent(uri)>`. If serve is down, that key shows a short non-blocking notice (`Web UI is down. Start it with: gno serve --detach`) and spawns nothing. A spawn failure of the opener is the same kind of notice; the overlay and panel stay interactive.

Left-clicking the bar widget toggles the nested `Panel.qml` loader — it does not call that overlay IPC path. The anchored popup is not a manifest `panel` kind, so it cannot steal the overlay toggle.

### Bar health states

Every state pairs a different glyph or badge **shape** with a theme color (`Color.foreground` / `Color.muted` / `Color.urgent`). Color is never the only signal.

| Visual | When | Glyph / marker |
| --- | --- | --- |
| Healthy | `ready`, initialized, no backlog | History glyph only |
| Backlog pending | `backlog.pending` > 0 | History + `●N` (circle) |
| Backlog failed | `backlog.failed` > 0 | History + `◆N` (diamond) |
| Stale | Latest refresh failed, last-good snapshot kept | History + `~` |
| Setup guidance | `not-found` / `not-executable` / `version-skew` / `unknown-command` | Question-circle |
| Init guidance | Peek succeeded with `initialized: false` | Plus |
| Degraded | `runtime-error` (peek `RUNTIME` envelope) / `timeout` / `malformed-json` / `spawn-failure` | Warning triangle |

Hover the widget for a short accessible status line. Middle-click refreshes the peek snapshot. Left-click opens the anchored panel: health line, document/collection counts, backlog, last-indexed time, and recent titles (URI-tail fallback when title is null). Escape closes it. Arrow keys move the highlight across recents and the footer actions.

The panel never starts `gno serve`. **Open GNO web UI** is enabled only when peek reports `serve.running`; otherwise it stays disabled with `start: gno serve --detach`. **Recall search** toggles the overlay via `omarchy-shell shell toggle gmickel.gno-recall`. **Browse collections** summons the overlay directly into collections mode (`{"mode":"collections"}`). Recent rows use the same `openDocument` matrix as the overlay: Enter/click opens the file (or falls back to web / guidance), and `w` is the explicit web-open.

When peek has nothing to list, the panel shows one of three copy blocks instead of going blank: run `gno init` (uninitialized), add documents (initialized but empty), or setup/degraded guidance with the service error message.

## License

MIT. Copyright Gordon Mickel.
