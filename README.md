# Pinote

Pinote is an Omarchy Shell plugin for keeping plain-text notes close at hand.
It provides a bar widget, a centered notes panel, and an atomic persistent
store.

## Requirements

- Omarchy 4.0.2 or newer
- Quickshell 0.3.1 or newer, as provided by Omarchy
- Qt 6 declarative tools for local checks (`qmllint` and `qmltestrunner`)
- Node.js for development checks (tested with 26.7.0)

## Local Development

Omarchy discovers user plugins under `~/.config/omarchy/plugins/`. Clone the
repository into the directory named for the manifest ID, then enable it:

```bash
mkdir -p ~/.config/omarchy/plugins
git clone /path/to/pinote ~/.config/omarchy/plugins/diegoalveslv.pinote
omarchy-shell shell rescanPlugins
omarchy plugin enable diegoalveslv.pinote
```

For active development, edit the checkout under
`~/.config/omarchy/plugins/diegoalveslv.pinote/`. Omarchy Shell reloads plugin
code when a file in that directory changes. If a change is not detected, run:

```bash
omarchy-shell shell rescanPlugins
```

The development workflow never requires modifying `/usr/share/omarchy/`.

## Usage

Click the Pinote icon in the bar, or use shell IPC:

```bash
omarchy-shell shell summon diegoalveslv.pinote '{}'
omarchy-shell shell hide diegoalveslv.pinote
omarchy-shell shell toggle diegoalveslv.pinote '{}'
```

The suggested keyboard shortcut is `SUPER ALT + N`, bound to:

```bash
omarchy-shell shell toggle diegoalveslv.pinote '{}'
```

### Controls

- `Up` / `Down`: select a note
- `Enter`: edit the selected note
- `N`: create a note
- `Delete` or `X`: request deletion of the selected note
- `Ctrl+Enter` or `Ctrl+S`: save while editing
- `Escape`: cancel editing, dismiss confirmation, or close the panel

Notes are committed only when Save succeeds. Cancel leaves the committed note
unchanged. Hiding the panel preserves an uncommitted draft in memory, but the
draft does not survive an Omarchy Shell restart, plugin reload, disable, or
crash.

## Storage

Pinote stores committed notes in `$XDG_STATE_HOME/pinote/notes.json`, falling
back to `~/.local/state/pinote/notes.json`. Confirmed snapshots are also copied
atomically to `notes.json.bak`. Hiding the panel, restarting Omarchy Shell, or
updating the plugin does not remove these files. A saving indicator means the
latest committed in-memory snapshot is not durable yet; if saving fails,
Pinote keeps that snapshot available and offers a retry. If the canonical file
changes externally while a save is unresolved, Pinote refuses to overwrite it.
Keep the panel open to retain the in-memory snapshot, restore `notes.json` to
the version Pinote last loaded, and use **Check again**.

## Checks

Run all repository checks through one command:

```bash
scripts/check
```

The script validates `manifest.json`, runs the pure JavaScript tests with
Node's built-in test runner, runs `qmllint`, executes focused QML interaction
tests with `qmltestrunner`, and exercises the persistent store with disposable
state through Quickshell. It finds both Qt tools through `PATH` first and uses
their `/usr/lib/qt6/bin/` locations as Arch Linux fallbacks. On Arch, both are
provided by `qt6-declarative`. Set `OMARCHY_SHELL_ROOT` only when the Omarchy
Shell QML modules are installed somewhere other than
`/usr/share/omarchy/shell`.

## License

Pinote is available under the [MIT License](LICENSE).
