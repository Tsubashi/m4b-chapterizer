# Variable Playback Speed — Design

**Date:** 2026-05-04
**Status:** Approved (brainstorming phase)

## Overview

Let the user change playback speed across a fixed set of presets (0.5×, 0.75×, 1×, 1.25×, 1.5×, 2×, 3×) via either a small button in the playback bar or three keyboard shortcuts. Wire the chosen speed through `PlaybackController` so `just_audio` actually plays at that rate, and have the existing waveform-smoothing baseline reset on every speed change so the scroll stays smooth across rate transitions.

## Goals

- A button in the playback bar showing the current speed (e.g. `1×`, `1.25×`, `2×`); tapping it opens a menu of all 7 presets and the user's selection takes effect immediately.
- `Cmd+]` steps to the next-higher preset; `Cmd+[` steps to the next-lower preset; `Cmd+\` resets to `1×`. At the bounds, the step keys stay put.
- The chosen speed survives file open within the same app session; resetting on file open would be surprising for users dialled in on a particular pace.
- Speed does **not** persist across app restarts. (Out of scope for v1; can be added with a small SharedPreferences-style storage later.)
- Waveform scroll stays visually smooth across speed changes — the existing extrapolation baseline resets on every `speedStream` emission.

## Non-goals

- Persisting the chosen speed across app restarts.
- Per-file speed memory.
- Continuous speed slider, or arbitrary speeds outside the preset list.
- Pitch correction toggles (`just_audio` defaults to time-stretching that preserves pitch; we keep that and don't expose a control).

## Architecture

### `PlaybackController` interface

`lib/presentation/providers/playback.dart` gains three members:

```dart
abstract class PlaybackController {
  // ... existing members ...
  double get speed;
  Stream<double> get speedStream;
  Future<void> setSpeed(double speed);
}
```

`JustAudioPlaybackController` forwards each:

```dart
@override
double get speed => _player.speed;
@override
Stream<double> get speedStream => _player.speedStream;
@override
Future<void> setSpeed(double speed) => _player.setSpeed(speed);
```

The whole `JustAudioPlaybackController` class is already `coverage:ignore`-marked; the new methods inherit that.

### Speed presets

A new top-level list in `lib/presentation/widgets/speed_button.dart`:

```dart
const List<double> kSpeedPresets = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
const double kDefaultSpeed = 1.0;
```

A formatting helper (also in `speed_button.dart`):

```dart
String formatSpeed(double speed) {
  if (speed == speed.roundToDouble()) {
    return '${speed.toInt()}×';
  }
  return '$speed×';
}
```

So `0.5 → "0.5×"`, `1.0 → "1×"`, `1.25 → "1.25×"`, `2.0 → "2×"`, `3.0 → "3×"`.

A small helper for the keyboard shortcuts (also in `speed_button.dart`):

```dart
double nextSpeedPreset(double current, {required int direction}) {
  // Find the nearest preset to `current` (handles floating-point drift),
  // then step by `direction` (+1 next, -1 previous), clamped to ends.
  // direction == 0 returns the current preset (no-op caller).
  final closestIdx = _closestPresetIndex(current);
  final newIdx =
      (closestIdx + direction).clamp(0, kSpeedPresets.length - 1);
  return kSpeedPresets[newIdx];
}

int _closestPresetIndex(double speed) {
  var bestIdx = 0;
  var bestDelta = (kSpeedPresets[0] - speed).abs();
  for (var i = 1; i < kSpeedPresets.length; i++) {
    final d = (kSpeedPresets[i] - speed).abs();
    if (d < bestDelta) {
      bestDelta = d;
      bestIdx = i;
    }
  }
  return bestIdx;
}
```

### `SpeedButton` widget

A `ConsumerStatefulWidget` in `lib/presentation/widgets/speed_button.dart`. Uses a `StreamBuilder<double>` on `controller.speedStream` (with `initialData: controller.speed`) so the label tracks live changes from anywhere — keyboard shortcuts, the menu, or even just_audio's own emissions on `setSpeed`. Wraps a `MenuAnchor` (same pattern as the existing Save-As dropdown in `playback_controls.dart`):

```dart
class SpeedButton extends ConsumerWidget {
  const SpeedButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackControllerProvider);
    return StreamBuilder<double>(
      stream: controller.speedStream,
      initialData: controller.speed,
      builder: (context, snapshot) {
        final speed = snapshot.data ?? controller.speed;
        return MenuAnchor(
          builder: (context, menuController, _) => TextButton(
            key: const ValueKey('playback.speed'),
            onPressed: () => menuController.isOpen
                ? menuController.close()
                : menuController.open(),
            child: Text(formatSpeed(speed)),
          ),
          menuChildren: [
            for (final preset in kSpeedPresets)
              MenuItemButton(
                key: ValueKey('playback.speed.$preset'),
                onPressed: () => controller.setSpeed(preset),
                child: Text(formatSpeed(preset)),
              ),
          ],
        );
      },
    );
  }
}
```

### `PlaybackControls` integration

`lib/presentation/widgets/playback_controls.dart` inserts the `SpeedButton` between the time readout's `Spacer()` and its preceding section. Concretely, after the existing time-readout `StreamBuilder<Duration>(...)` and before the `Spacer()`, add:

```dart
const SizedBox(width: 12),
const SpeedButton(),
```

No other changes to that file.

### Keyboard shortcuts

`lib/presentation/keyboard/shortcuts.dart` gains three intents and three bindings:

```dart
class StepSpeedIntent extends Intent {
  const StepSpeedIntent(this.direction);
  final int direction; // +1 step up, -1 step down
}

class ResetSpeedIntent extends Intent {
  const ResetSpeedIntent();
}
```

In `editorShortcuts()`:

```dart
cmd(LogicalKeyboardKey.bracketRight): const StepSpeedIntent(1),
cmd(LogicalKeyboardKey.bracketLeft): const StepSpeedIntent(-1),
cmd(LogicalKeyboardKey.backslash): const ResetSpeedIntent(),
```

These use modifier keys (Cmd on macOS, Ctrl elsewhere via the existing `cmd(...)` helper) so they work even while a TextField is focused — same precedent as Cmd+S, Cmd+N, Cmd+Z.

In `_EditorShortcutsState.build`'s `actions:` map:

```dart
StepSpeedIntent: CallbackAction<StepSpeedIntent>(onInvoke: (intent) {
  final controller = ref.read(playbackControllerProvider);
  final next = nextSpeedPreset(controller.speed, direction: intent.direction);
  if (next != controller.speed) controller.setSpeed(next);
  return null;
}),
ResetSpeedIntent: CallbackAction<ResetSpeedIntent>(onInvoke: (_) {
  final controller = ref.read(playbackControllerProvider);
  if (controller.speed != kDefaultSpeed) controller.setSpeed(kDefaultSpeed);
  return null;
}),
```

These import `nextSpeedPreset` and `kDefaultSpeed` from the new `speed_button.dart` (same library/file is fine — the keyboard helpers are tiny).

### Waveform smoothing — speed-aware

`lib/presentation/widgets/waveform_view.dart` changes:

1. The existing `_currentPlaybackSpeed()` getter starts reading from the controller:

   ```dart
   double _currentPlaybackSpeed() =>
       ref.read(playbackControllerProvider).speed;
   ```

2. A new `StreamSubscription<double>? _speedSub` is set up in `initState` next to the existing `_positionSub` and `_playingSub`:

   ```dart
   _speedSub = controller.speedStream.listen(_onSpeedChange);
   ```

   Cancelled in `dispose`.

3. `_onSpeedChange` resets the extrapolation baseline so the new speed only applies to wall-clock time *after* the change:

   ```dart
   void _onSpeedChange(double newSpeed) {
     if (!mounted) return;
     final controller = ref.read(playbackControllerProvider);
     _basePosition = controller.position;
     _baseWallClock = clock.now();
   }
   ```

   No `setState` is needed — the next Ticker tick (or position emission) will pick up the new baseline. While paused, `_smoothedPlayhead` doesn't advance anyway.

This eliminates the forward-jump-then-backward-correction visual glitch described in the brainstorm: the new speed multiplier only applies to wall-clock time strictly after the speed change.

## Test plan

### `lib/presentation/providers/playback.dart`

The `JustAudioPlaybackController`'s new `speed`, `speedStream`, `setSpeed` are inside the existing `coverage:ignore-file` block — no new tests on the production wrapper.

### `test/presentation/widgets/speed_button_test.dart` (new)

Direct widget tests using a fake controller that exposes `speed` and `setSpeed`:

1. **Renders the controller's current speed.** Stub controller with `speed = 1.5`, pump `SpeedButton`, find text `1.5×`.
2. **Updates label when `speedStream` emits.** Stub with controller that pushes `2.0` on its stream after pump; verify label flips from `1×` to `2×`.
3. **Tapping the button opens the menu with all presets.** Find each `playback.speed.<preset>` key.
4. **Selecting a preset calls `setSpeed` with that value.** Tap `playback.speed.2.0`, verify `controller.lastSetSpeed == 2.0`.

### `test/presentation/widgets/speed_format_test.dart` (new)

Pure logic — no widget tree:

5. **`formatSpeed`** maps integer speeds to integer strings and fractional speeds to fractional. Cases: 0.5 → `0.5×`, 0.75 → `0.75×`, 1.0 → `1×`, 1.25 → `1.25×`, 2.0 → `2×`, 3.0 → `3×`.
6. **`nextSpeedPreset`** with `direction: +1` returns the next preset; with `-1` returns the previous; clamps at both ends. Cases: 1.0 +1 → 1.25; 0.5 -1 → 0.5 (clamped); 3.0 +1 → 3.0 (clamped); 1.5 +1 → 2.0; 1.5 -1 → 1.25.
7. **`nextSpeedPreset`** snaps a near-preset value to the closest preset before stepping (handles float drift). Case: 1.001 +1 → 1.25 (treats input as 1.0).

### `test/presentation/playback_controls_test.dart` (extend)

8. **`SpeedButton` is present in the playback bar when an audiobook is loaded.** Pump `PlaybackControls`, find `SpeedButton`.

### `test/presentation/keyboard_shortcuts_test.dart` (extend)

9. **`Cmd+]` steps speed up.** With `controller.speed == 1.0`, send `Cmd+]`, expect `setSpeed(1.25)` was called.
10. **`Cmd+[` steps speed down.** With `controller.speed == 1.0`, send `Cmd+[`, expect `setSpeed(0.75)`.
11. **`Cmd+]` at maximum is a no-op.** With `controller.speed == 3.0`, send `Cmd+]`, expect no `setSpeed` call.
12. **`Cmd+[` at minimum is a no-op.** With `controller.speed == 0.5`, send `Cmd+[`, expect no `setSpeed` call.
13. **`Cmd+\` resets to 1×.** With `controller.speed == 2.0`, send `Cmd+\`, expect `setSpeed(1.0)`.
14. **`Cmd+\` at 1× is a no-op.** With `controller.speed == 1.0`, send `Cmd+\`, expect no `setSpeed` call.
15. **Speed shortcuts work while a TextField is focused.** With chapter title focused and `controller.speed == 1.0`, send `Cmd+]`, expect `setSpeed(1.25)` (Cmd modifier means it bypasses the BareKey gate).

### `test/presentation/waveform_view_test.dart` (extend)

16. **Speed change mid-playback resets the extrapolation baseline.** Setup: emit position 0, start playing, pump 100 ms (`windowStart` advances at 1×). Then `playback.emitSpeed(2.0)` followed by `pump(50 ms)`. Verify `windowStart` is approximately `controller.position + 50 ms × 2.0 − 25% × windowDuration` — i.e., extrapolation uses 2.0× from the speed-change moment forward, not from the original baseline.

### Test fakes — `_FakePlayback` updates across all test files

Each test file with a `_FakePlayback` (currently `keyboard_shortcuts_test.dart`, `waveform_view_test.dart`, `playback_controls_test.dart`, and the helpers in `editor_screen_test.dart` / `editor_actions_test.dart`) gains:

```dart
double _speed = 1.0;
double? lastSetSpeed; // for assertion in tests
final speedController = StreamController<double>.broadcast();

@override
double get speed => _speed;
@override
Stream<double> get speedStream => speedController.stream;
@override
Future<void> setSpeed(double speed) async {
  _speed = speed;
  lastSetSpeed = speed;
  speedController.add(speed);
}
void emitSpeed(double s) {
  _speed = s;
  speedController.add(s);
}
```

`speedController` is closed in the existing `dispose()`. The mechanical edit is the same in all test files; not every test file needs every member, but adding the full set everywhere keeps the fake consistent and avoids per-file divergence.

## Smoke-test plan

1. Open an `.m4b`. Play. Speed button shows `1×`.
2. Click the speed button — menu opens with the 7 presets.
3. Click `2×`. Audio plays faster, button label updates to `2×`, waveform continues scrolling smoothly (no visual jolt).
4. While playing, press `Cmd+]` — speed steps to `3×`, waveform stays smooth.
5. `Cmd+]` again — no change (already at maximum).
6. `Cmd+\` — speed resets to `1×`, audio returns to normal pace, waveform smooth.
7. `Cmd+[` repeatedly — speed steps down through `0.75×`, `0.5×`, then stays at `0.5×`.
8. Open a different `.m4b` — speed stays at `0.5×` (does not reset on file open).
9. While a chapter title is focused, press `Cmd+]` — speed changes; the modifier keeps the shortcut active even with text focus.

## Files

- Modify: `lib/presentation/providers/playback.dart` — interface + JustAudio passthroughs.
- Create: `lib/presentation/widgets/speed_button.dart` — `kSpeedPresets`, `kDefaultSpeed`, `formatSpeed`, `nextSpeedPreset`, `SpeedButton` widget.
- Modify: `lib/presentation/widgets/playback_controls.dart` — insert `const SpeedButton()` in the bottom row.
- Modify: `lib/presentation/keyboard/shortcuts.dart` — `StepSpeedIntent`, `ResetSpeedIntent`, three new bindings, two new actions.
- Modify: `lib/presentation/widgets/waveform_view.dart` — `_speedSub`, `_onSpeedChange`, `_currentPlaybackSpeed()` reads `controller.speed`.
- Create: `test/presentation/widgets/speed_button_test.dart` — widget tests (4).
- Create: `test/presentation/widgets/speed_format_test.dart` — pure logic tests (3).
- Modify: `test/presentation/playback_controls_test.dart` — add presence test for `SpeedButton`; extend `_FakePlayback`.
- Modify: `test/presentation/keyboard_shortcuts_test.dart` — 7 keyboard tests; extend `_FakePlayback`.
- Modify: `test/presentation/waveform_view_test.dart` — speed-change baseline-reset test; extend `_FakePlayback`.
- Modify: `test/presentation/editor_screen_test.dart` and `test/presentation/editor_actions_test.dart` — extend their respective `_FakePlayback`s for compile-only conformance to the new interface members.
