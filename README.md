# Pinote

Pinote is a small [Omarchy](https://omarchy.org/) Shell plugin for keeping
plain-text notes close at hand. It adds a bar icon and a centered notes panel
with atomic local persistence.

## Install

Review the repository and `manifest.json`, then install with Omarchy:

```bash
omarchy plugin add https://github.com/diegoalveslv/omarchy-pinote.git --enable
```

The plugin ID is `dlv.pinote`.

```bash
omarchy plugin update dlv.pinote
omarchy plugin disable dlv.pinote
omarchy plugin enable dlv.pinote
omarchy plugin remove dlv.pinote
```

## Use

Click the Pinote bar icon, or control the panel through shell IPC:

```bash
omarchy-shell shell summon dlv.pinote '{}'
omarchy-shell shell hide dlv.pinote
omarchy-shell shell toggle dlv.pinote '{}'
```

Pinote does not install a keyboard shortcut. If desired, add the toggle command
to an unassigned personal Omarchy/Hyprland binding.

- `Up` / `Down`: select a note
- `Enter`: edit the selected note
- `N`: create a note
- `Delete` or `X`: request deletion
- `Ctrl+Enter` or `Ctrl+S`: save
- `Escape`: cancel, dismiss, or close

## Data

Notes are stored in `$XDG_STATE_HOME/pinote/notes.json` (or
`~/.local/state/pinote/notes.json`) with an atomic `notes.json.bak` backup.
Updates and removal leave this state untouched. If a file is invalid, Pinote
opens its recovery interface and preserves recovery archives.

To intentionally delete all Pinote data, disable or remove the plugin first,
confirm the directory contents, then run:

```bash
rm -rI -- "${XDG_STATE_HOME:-$HOME/.local/state}/pinote"
```

## Development

Run the complete local check suite with:

```bash
scripts/check
```

Pinote requires Omarchy 4.0.2+ and Quickshell 0.3.1+. Development checks also
require Node.js, Python 3, and Qt Declarative tools.

## Limitations

- Plain-text notes only: no rich text, attachments, search, sync, or encryption.
- Drafts survive hiding the panel, but not a shell restart, plugin reload,
  disable, or crash.
- Application bindings, launch detection, triggered note windows, and
  note-creation IPC are post-MVP.

## License

Pinote is available under the [Apache License 2.0](LICENSE).
