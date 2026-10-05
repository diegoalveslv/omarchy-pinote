# Pinote

Pinote is an Omarchy Shell plugin for keeping plain-text notes close at hand.
It provides a bar widget, a centered notes panel, and an atomic persistent
store.

## Requirements

- Omarchy 4.0.2 or newer
- Quickshell 0.3.1 or newer, as provided by Omarchy
- Python 3 and the standard Linux `/proc` filesystem for the descriptor-safe
  recovery filesystem helper
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

## Installation And Lifecycle

Review the repository and its `manifest.json` before enabling any third-party
plugin. Once the public repository is available, install Pinote with Omarchy's
supported plugin command:

```bash
omarchy plugin add https://github.com/diegoalveslv/omarchy-pinote.git --enable
```

The manifest ID is `diegoalveslv.pinote`. Manage an installed copy with:

```bash
omarchy plugin disable diegoalveslv.pinote
omarchy plugin enable diegoalveslv.pinote
omarchy plugin update diegoalveslv.pinote
omarchy plugin remove diegoalveslv.pinote
```

Removing the plugin does not remove notes, backups, or recovery archives. To
delete all Pinote data intentionally, first disable or remove the plugin, then
remove its state directory only after confirming its contents:

```bash
rm -rI -- "${XDG_STATE_HOME:-$HOME/.local/state}/pinote"
```

Installation and shortcut configuration do not edit Hyprland configuration.

### Isolated Live Testing

Do not run destructive acceptance tests against an installed production copy
of Pinote. Start with the read-only preflight:

```bash
scripts/live-check
```

Then create an ephemeral `Pinote (Live Test)` installation with the distinct
ID `diegoalveslv.pinote.live-test` and state directory `pinote-live-test`:

```bash
scripts/live-test
```

The script stages the generated variant in a hidden directory on the plugin
filesystem, validates it, and atomically renames it into place. It waits while
the manual acceptance flow runs and removes its plugin and state on exit. For
agent-driven testing, `scripts/live-test --yes-production-idle --keep` leaves
the variant available temporarily; always finish with:

```bash
scripts/live-test --remove
```

Installing or removing any plugin reloads the entire Omarchy plugin registry.
Confirm production Pinote is hidden, durable, and has no draft before starting.
Prefer one manual click on the live-test bar icon to verify pointer routing.

## Usage

Click the Pinote icon in the bar, or use shell IPC:

```bash
omarchy-shell shell summon diegoalveslv.pinote '{}'
omarchy-shell shell hide diegoalveslv.pinote
omarchy-shell shell toggle diegoalveslv.pinote '{}'
```

No keyboard shortcut is installed or recommended by default. Use shell IPC:

```bash
omarchy-shell shell toggle diegoalveslv.pinote '{}'
```

To add an optional shortcut, first check your effective bindings for a
collision. Add the following line to `~/.config/hypr/bindings.lua` only after
replacing `YOUR KEY COMBINATION` with an unassigned shortcut, then reload
Hyprland through your usual Omarchy workflow:

```lua
o.bind("YOUR KEY COMBINATION", "Pinote", "omarchy-shell shell toggle diegoalveslv.pinote '{}'")
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

Pinote keeps its state directory at mode `0700`. Recovery-created note files,
staging files, transaction markers, and archives use mode `0600`. If recovery
moves an existing primary aside, that original file retains its existing mode.

### Recovery

If `notes.json` is malformed or contains invalid records, Pinote blocks normal
writes and shows any individually valid records as a read-only preview. Use
**Retry** after repairing the file externally. If `notes.json.bak` is complete
and valid, **Restore backup** can restore it. **Start fresh** creates an empty
version-1 collection. Both replacement actions require confirmation and first
copy the damaged primary into an independent timestamped
`notes.json.recovery-*` file. Pinote
then stages the replacement, moves the current primary into a private
timestamped `notes.json.recovery-current-*/notes.json` archive, and installs
the stage through atomic hard-link creation. Unsupported hard links or an
existing primary fail safely instead of falling back to check-then-rename.
Recovery verifies that note and transaction descriptors still match their
expected state-directory names, rejects additional hard-link aliases, and
preserves their final content and mode when aliases are raced against a
permission update. An
external primary appearing during that handoff is preserved rather than
overwritten. A private transaction marker lets Pinote safely finish or abandon
an interrupted handoff on its next start.

After a replacement is installed and transaction cleanup succeeds, Pinote stays
read-only and asks you to select **Check again**. Editing is enabled only after
a fresh read of the canonical file, so recovery verification cannot expose a
stale in-memory snapshot as writable.

Starting fresh does not replace `notes.json.bak`; the previous backup remains
available for manual recovery until a later successful note mutation updates
it. A future schema version remains read-only and cannot be restored or reset
from Pinote. Replace it externally with a compatible file and select
**Check again**.

For manual recovery, close or disable Pinote before changing files, preserve
all `notes.json.recovery-*` files, inspect `notes.json` and `notes.json.bak`,
then put one complete version-1 document at `notes.json`. Plugin updates and
removal leave the entire state directory, including backups and recovery
archives, untouched.

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

## MVP Limitations

- Pinote stores plain-text notes only; it does not support rich text,
  attachments, search, sync, or encryption.
- Uncommitted drafts survive hiding the panel but not a shell restart, plugin
  reload, disable, or crash.
- Application bindings, launch detection, and triggered note windows are
  post-MVP features.
- Pinote does not currently provide an IPC method to create notes directly.

## License

Pinote is available under the [Apache License 2.0](LICENSE).
