# Repository Agent Guidance

## Validation

- Run the complete automated gate with `scripts/check`.
- `qmltestrunner` is provided by Arch's `qt6-declarative` package. Resolve it
  from `PATH` first, then `/usr/lib/qt6/bin/qmltestrunner`.
- Standalone `qmltestrunner` cannot instantiate `Panel.qml` because
  Quickshell's QML plugin is statically linked into `qs`. Keep state and input
  routing in Qt-only components where practical, test those offscreen, and use
  the running Omarchy Shell for final panel integration tests.
- Never use real note content in tests or logs. Remove live-test notes after
  the acceptance flow and verify both `notes.json` and `notes.json.bak` contain
  the expected final snapshot.

## Live Plugin Testing

- Install or sync development code only under
  `~/.config/omarchy/plugins/diegoalveslv.pinote/`. Never modify
  `/usr/share/omarchy/`.
- Back up an existing installed plugin before overwriting it, and do not
  replace unrelated user changes without explicit approval.
- Prefer `wtype` for keyboard interaction and `grim -o <output>` for visual
  verification.
- Exercise both shell IPC and the actual bar icon. IPC alone does not verify
  `BarWidget.qml` pointer routing.
- Inspect the active shell log with `qs log --pid <pid> -t <lines> --no-color`.
  Check for Pinote QML errors, binding loops, exceptions, and leaked note text.

## Pointer Automation

Do not install `ydotool` just for live tests when `/dev/uinput` is writable and
Python's `evdev` module is available.

1. Find output position and scale with `hyprctl monitors -j`.
2. Screenshot coordinates are physical pixels. Convert them to Hyprland global
   logical coordinates by dividing output-local coordinates by its scale and
   adding the output's logical `x` and `y` offsets.
3. Move the cursor with Hyprland's Lua dispatcher:

   ```bash
   hyprctl eval 'return hl.dispatch(hl.dsp.cursor.move({ x = 100, y = 100 }))'
   ```

4. Confirm the position with `hyprctl cursorpos`, then emit exactly one click:

   ```bash
   python -c 'import time; from evdev import UInput, ecodes as e; ui=UInput({e.EV_KEY:[e.BTN_LEFT], e.EV_REL:[e.REL_X,e.REL_Y]}, name="pinote-live-test-pointer"); time.sleep(0.5); ui.write(e.EV_KEY,e.BTN_LEFT,1); ui.syn(); time.sleep(0.1); ui.write(e.EV_KEY,e.BTN_LEFT,0); ui.syn(); time.sleep(0.5); ui.close()'
   ```

5. Capture another screenshot to verify the intended control received the
   click. The `UInput` context is temporary; always close it immediately.

Only synthesize input after confirming the target coordinates. Avoid repeated
or exploratory clicks that could activate neighboring tray controls.
