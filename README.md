# GNO Recall

An [Omarchy](https://omarchy.org/) shell plugin that surfaces [GNO](https://gno.sh) index activity from the bar.

This repository is the plugin source. The bar widget is quiet when the index is healthy (a history glyph only) and adds a distinct shape plus color when there is backlog, staleness, or a setup/degraded fault. Left-click opens an anchored index panel; `omarchy-shell shell toggle gmickel.gno-recall` (or Super+R later) summons the recall overlay.

## Requirements

- Omarchy with shell plugin support
- [gno](https://github.com/gmickel/gno) **>= 1.36.0** on `PATH`, or an absolute path in the widget's **Path to gno** setting
- A Nerd Font (Omarchy includes one by default)

`gno peek --json` is the snapshot path. Committed overlay search is a second argv-array call: `gno search <query> --json --no-project-affinity -n 20`. Peek shipped in gno 1.36.0 (`schemaVersion` `peek@1.0`). Older gno builds fail discovery with an `unknown-command` state instead of crashing the shell. The plugin never calls `gno get` or `gno serve`.

## Privilege boundary

Plugins run as **unsandboxed code inside `omarchy-shell`**. Adding a plugin clones files and toggles enabled state; it does not sandbox the QML. Only install repos you are willing to run in the long-lived shell process.

The installer **never runs hooks**. A Super+R keybind, if you want one later, is a documented script you add yourself — not an `omarchy plugin add` hook.

## Install

```bash
omarchy plugin add https://github.com/gmickel/omarchy-gno-recall --enable
```

The widget lands on the right side of the bar. Move it with:

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
| Path to gno (`gnoPath`) | empty | Absolute path to `gno`. Empty uses `PATH`. |
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
```

`OMARCHY_PATH` is typically `/usr/share/omarchy`. After add, the live copy is `~/.config/omarchy/plugins/gmickel.gno-recall`. The shell hot-reloads QML under that directory; `omarchy-shell shell rescanPlugins` forces a reload.

`qmllint` may report Quickshell-module false positives (`Quickshell.Io.Process`, `StdioCollector`, `PanelWindow`) because those types come from the Quickshell runtime, not the Omarchy import path. Treat those as noise unless they point at real syntax errors.

## How it works

`Service.qml` is the only `Process` owner. It resolves `gno` from the widget `gnoPath` (absolute) or `PATH`, then invokes `gno peek --json` as an argv array via `Quickshell.Io.Process` + `StdioCollector`. Bar and overlay surfaces look the service up with `bar.shell.serviceFor("gmickel.gno-recall")` — third-party plugins must not use `firstPartyServiceFor`.

The overlay is the summonable surface (`omarchy-shell shell toggle gmickel.gno-recall`). It opens on the focused monitor, grabs exclusive keyboard focus, and shows cached peek `recent[]` immediately. Typing filters titles and URI tails in memory — no `gno` subprocess per keystroke. Enter runs exactly one search through `Service.qml`; a new Enter or a query change cancels the in-flight Process and drops late JSON via a search generation id. Esc clears the filter, then dismisses via `shell.hide` so `openPanelIds` stays consistent.

Rows show title (URI-tail fallback), collection (peek field for recents, `gno://<collection>/…` for search hits), snippet, and modified time. Arrow keys (and `j`/`k` when the filter is empty) move the highlight. Enter on a row does not open files yet. Search failure/timeout stays inline and keeps the overlay interactive; zero hits and empty-but-initialized indexes have distinct copy from uninitialized guidance.

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

The panel never starts `gno serve`. **Open GNO web UI** is enabled only when peek reports `serve.running`; otherwise it stays disabled with `start: gno serve --detach`. **Recall search** toggles the overlay via `omarchy-shell shell toggle gmickel.gno-recall`.

When peek has nothing to list, the panel shows one of three copy blocks instead of going blank: run `gno init` (uninitialized), add documents (initialized but empty), or setup/degraded guidance with the service error message.

## License

MIT. Copyright Gordon Mickel.
