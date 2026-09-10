# Pinote

Pinote is an Omarchy Shell plugin for keeping plain-text notes close at hand.
The current implementation is the initial shell skeleton: it provides a bar
widget and a centered panel with the standard shell lifecycle.

## Requirements

- Omarchy 4.0.2 or newer
- Quickshell 0.3.1 or newer, as provided by Omarchy
- Qt 6 QML tools for local checks
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

The suggested keyboard shortcut is `SUPER ALT + N`. Shortcut configuration
will be documented with the completed notes workflow.

## Checks

Run all repository checks through one command:

```bash
scripts/check
```

The script validates `manifest.json`, runs the pure JavaScript model tests with
Node's built-in test runner, and runs `qmllint`. It finds `qmllint` through
`PATH` first and uses `/usr/lib/qt6/bin/qmllint` as the Arch Linux fallback.
Set `OMARCHY_SHELL_ROOT` only when the Omarchy Shell QML modules are installed
somewhere other than `/usr/share/omarchy/shell`.

## License

Pinote is available under the [MIT License](LICENSE).
