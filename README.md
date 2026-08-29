# GNO Recall

An [Omarchy](https://omarchy.org/) shell plugin that surfaces [GNO](https://gno.sh) index activity from the bar.

This repository is the plugin source. The widget is a small glyph today; later work adds the anchored popup and overlay.

## Requirements

- Omarchy with shell plugin support
- [gno](https://github.com/gmickel/gno) **>= 1.36.0** on `PATH`, or an absolute path in the widget's **Path to gno** setting
- A Nerd Font (Omarchy includes one by default)

`gno peek --json` is the only data path. That command shipped in gno 1.36.0 (`schemaVersion` `peek@1.0`). Older gno builds fail discovery with an `unknown-command` state instead of crashing the shell.

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

The overlay is the summonable surface (`omarchy-shell shell toggle gmickel.gno-recall`). The anchored popup will be an internal `Panel.qml` loaded by `BarWidget.qml`; it is not a manifest `panel` kind, so it cannot steal that toggle.

## License

MIT. Copyright Gordon Mickel.
