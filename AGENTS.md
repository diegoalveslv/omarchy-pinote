# Repository Agent Guidance

## Validation

- Run the complete automated gate with `scripts/check`.
- `qmltestrunner` is provided by Arch's `qt6-declarative` package. Resolve it
  from `PATH` first, then `/usr/lib/qt6/bin/qmltestrunner`.
- Standalone `qmltestrunner` cannot instantiate `Panel.qml` because
  Quickshell's QML plugin is statically linked into `qs`. Keep state and input
  routing in Qt-only components where practical, test those offscreen, and use
  the running Omarchy Shell for final panel integration tests.
- Never use real note content in tests, screenshots, or logs.

## Isolated Live Testing

- Run `scripts/live-check` before changing the active shell. It is read-only
  and reports plugin paths, state presence, shell PID, output transforms, and
  available input tools.
- Run destructive acceptance tests only against the generated
  `dlv.pinote.live-test` plugin and its `pinote-live-test` state
  directory. Never run CRUD acceptance tests against production Pinote state.
- `scripts/live-test` stages a complete runtime tree in a hidden sibling under
  the plugin root, validates it, and renames it atomically into
  `~/.config/omarchy/plugins/dlv.pinote.live-test/`.
- The script must stop if the test installation or state already exists. Never
  overwrite an existing plugin directory. Generated installations carry an
  ownership marker that cleanup must verify before removal.
- Omarchy reloads all plugins when its plugin tree changes. Before installing
  or removing the test variant, confirm production Pinote is hidden, durable,
  and has no draft. Filesystem isolation cannot preserve an in-memory draft
  across this global reload.
- Use the ephemeral default workflow. `scripts/live-test --keep` is only for
  agent-driven debugging and must be followed by `scripts/live-test --remove`.
- Keep staging directories hidden and directly under
  `~/.config/omarchy/plugins/`. Omarchy excludes hidden top-level entries from
  discovery, and sharing the target filesystem keeps the final rename atomic.
- If isolated testing is unavailable, use a disposable user/session. Testing
  against an existing production state requires explicit approval, disabling
  the plugin, archiving the complete state directory, and byte-verifying an
  exact restoration afterward.
- Exercise both test IPC and the actual test bar icon. IPC alone does not
  verify `BarWidget.qml` pointer routing.
- Inspect the active shell log with `qs log --pid <pid> -t <lines> --no-color`.
  Check for test-plugin QML errors, binding loops, exceptions, and leaked note
  text.

## Keyboard And Screenshots

- Prefer `wtype` for keyboard interaction.
- Always give `grim` a private destination file; omitting it writes binary PNG
  data to stdout. Create the file under a private temporary directory, inspect
  it, then explicitly remove that directory. Do not use an `EXIT` trap in the
  capture command when inspection happens in a later tool call because the
  trap would remove the image first.

```bash
shot_dir=$(mktemp -d "${TMPDIR:-/tmp}/pinote-shot.XXXXXX")
grim -o "$output" "$shot_dir/panel.png"
# Inspect "$shot_dir/panel.png" before running:
rm -rf -- "$shot_dir"
```

## Pointer Automation

Prefer asking the user to click the `Pinote (Live Test)` bar icon once. Use
synthetic pointer input only when a manual click is impractical and all safety
conditions below are satisfied.

1. Read output position, scale, and transform with `hyprctl monitors -j`.
2. Stop unless the target output has `transform: 0`. Do not attempt coordinate
   conversion for rotated or reflected outputs.
3. Identify the target bounds from a screenshot. Screenshot coordinates are
   physical pixels; convert output-local coordinates to Hyprland global logical
   coordinates by dividing by scale and adding the output's logical `x` and
   `y` offsets.
4. Move the cursor, then confirm its exact position:

   ```bash
   hyprctl eval 'return hl.dispatch(hl.dsp.cursor.move({ x = 100, y = 100 }))'
   hyprctl cursorpos
   ```

5. If `/dev/uinput` is writable and Python's `evdev` module is available, emit
   exactly one click with a context-managed temporary device:

   ```bash
   python - <<'PY'
   import time
   from evdev import UInput, ecodes as e

   capabilities = {
       e.EV_KEY: [e.BTN_LEFT],
       e.EV_REL: [e.REL_X, e.REL_Y],
   }
   with UInput(capabilities, name="pinote-live-test-pointer") as ui:
       time.sleep(0.5)
       ui.write(e.EV_KEY, e.BTN_LEFT, 1)
       ui.syn()
       time.sleep(0.1)
       ui.write(e.EV_KEY, e.BTN_LEFT, 0)
       ui.syn()
       time.sleep(0.5)
   PY
   ```

6. Capture another private screenshot and verify the intended control received
   the click.

Never install `ydotool` solely for these tests when the temporary `evdev`
method is available. Never issue repeated or exploratory clicks near unrelated
tray controls.
