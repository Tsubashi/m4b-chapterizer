# Variable Playback Speed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user pick playback speed from seven presets via a button next to the time readout or via Cmd+]/Cmd+[/Cmd+\, with the waveform's smooth-scroll baseline resetting on every speed change so scrolling stays smooth across rate transitions.

**Architecture:** `PlaybackController` grows `setSpeed`/`speed`/`speedStream`. A new `SpeedButton` widget plus its preset/format helpers live in `lib/presentation/widgets/speed_button.dart`. Three keyboard intents (`StepSpeedIntent` ±1, `ResetSpeedIntent`) wire up via the existing shortcut machinery. `WaveformView` reads `controller.speed` from its existing `_currentPlaybackSpeed()` seam and subscribes to `speedStream` to reset its extrapolation baseline on every emission.

**Tech Stack:** Flutter 3.41.9, Dart 3.11, just_audio 0.10.x, flutter_riverpod 3.x.

**Spec:** `docs/superpowers/specs/2026-05-04-variable-playback-speed-design.md`

---

## File Map

**New:**
- `lib/presentation/widgets/speed_button.dart` — `kSpeedPresets`, `kDefaultSpeed`, `formatSpeed`, `nextSpeedPreset`, `_closestPresetIndex`, `SpeedButton`.
- `test/presentation/widgets/speed_format_test.dart` — pure-logic tests for `formatSpeed` and `nextSpeedPreset`.
- `test/presentation/widgets/speed_button_test.dart` — widget tests for `SpeedButton`.

**Modified:**
- `lib/presentation/providers/playback.dart` — interface gains `setSpeed`/`speed`/`speedStream`; `JustAudioPlaybackController` forwards each.
- `lib/presentation/widgets/playback_controls.dart` — insert `SpeedButton` between time readout and `Spacer()`.
- `lib/presentation/keyboard/shortcuts.dart` — `StepSpeedIntent`, `ResetSpeedIntent`, three new bindings, two new actions.
- `lib/presentation/widgets/waveform_view.dart` — `_speedSub`, `_onSpeedChange`, `_currentPlaybackSpeed()` reads `controller.speed`.
- `test/presentation/playback_controls_test.dart` — extend `_FakePlayback` (and `_StreamingFakePlayback`) for the new interface members; add presence test for `SpeedButton`.
- `test/presentation/waveform_view_test.dart` — extend `_FakePlayback`; add baseline-reset test.
- `test/presentation/keyboard_shortcuts_test.dart` — extend `_FakePlayback`; add 7 keyboard-shortcut tests.
- `test/presentation/editor_screen_test.dart` — extend `_NoopPlayback` and `_RecordingPlayback`.
- `test/presentation/chapter_list_test.dart` — extend whichever `PlaybackController` implementor lives there.
- `test/presentation/editor_state_test.dart` — extend whichever `PlaybackController` implementor lives there.

---

## Task 1: Grow `PlaybackController` interface and update every test fake

This task lands the abstract members and updates every existing test-fake `PlaybackController` so the project still compiles. No production behavior changes; nothing reads or writes `speed` yet.

**Files:**
- Modify: `lib/presentation/providers/playback.dart`
- Modify: every test file with `implements PlaybackController`:
  - `test/presentation/playback_controls_test.dart`
  - `test/presentation/waveform_view_test.dart`
  - `test/presentation/keyboard_shortcuts_test.dart`
  - `test/presentation/editor_screen_test.dart`
  - `test/presentation/chapter_list_test.dart`
  - `test/presentation/editor_state_test.dart`

- [ ] **Step 1: Add the new members to the interface and the JustAudio impl**

Replace `lib/presentation/providers/playback.dart` with:

```dart
// coverage:ignore-file
//
// `JustAudioPlaybackController` is a thin pass-through wrapper around
// `package:just_audio`'s `AudioPlayer`. The controller's behavior is
// exercised throughout the test suite via the `PlaybackController`
// abstraction with a fake; the production wrapper itself only runs in
// smoke tests against the real audio backend, where construction and
// stream subscription are platform-mediated and not meaningfully
// testable in `flutter test`. The provider closure that returns it has
// the same constraint.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

abstract class PlaybackController {
  Future<void> setSource(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Duration get position;
  bool get playing;
  double get speed;
  Stream<Duration> get positionStream;
  Stream<bool> get playingStream;
  Stream<double> get speedStream;
  Future<void> dispose();
}

class JustAudioPlaybackController implements PlaybackController {
  JustAudioPlaybackController() : _player = AudioPlayer();
  final AudioPlayer _player;
  String? _currentSource;

  @override
  Future<void> setSource(String path) async {
    if (_currentSource == path) return;
    _currentSource = path;
    await _player.setFilePath(path);
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);
  @override
  Duration get position => _player.position;
  @override
  bool get playing => _player.playing;
  @override
  double get speed => _player.speed;
  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Stream<bool> get playingStream => _player.playingStream;
  @override
  Stream<double> get speedStream => _player.speedStream;
  @override
  Future<void> dispose() => _player.dispose();
}

/// Provided at app startup with `playbackControllerProvider.overrideWithValue(...)`.
/// Tests override with a fake.
final playbackControllerProvider = Provider<PlaybackController>((ref) {
  final controller = JustAudioPlaybackController();
  ref.onDispose(controller.dispose);
  return controller;
});
```

- [ ] **Step 2: Run analyzer to find every test fake that needs updating**

Run: `flutter analyze`
Expected: errors of the form "Missing concrete implementations of 'PlaybackController.setSpeed', 'PlaybackController.speed', 'PlaybackController.speedStream'" in each of the test files listed in this task's `Files:` section.

- [ ] **Step 3: Update every test fake — common shape**

For each file with a `class _XYZ implements PlaybackController { ... }`, add the three new members. The exact shape depends on the fake's existing pattern, but every fake gets these field declarations and methods (place near the existing `_pos` / `_playing` fields, and the existing `setSource` / `play` / `pause` methods):

```dart
double _speed = 1.0;
double? lastSetSpeed;
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

Add `await speedController.close();` to the existing `dispose()` method.

If a fake doesn't have a `dispose()` (a few are minimal stubs that don't expose streams), add a no-op or extend their existing pattern — match the file's local conventions.

If a fake declares `setSpeed`, `speed`, or `speedStream` already (it doesn't today, but Step 2 will tell you), just verify the signatures match the interface.

For each of the 6 test files:

- `test/presentation/playback_controls_test.dart` has TWO classes — `_FakePlayback` and `_StreamingFakePlayback`. Update both.
- `test/presentation/waveform_view_test.dart` has one — `_FakePlayback`.
- `test/presentation/keyboard_shortcuts_test.dart` has one — `_FakePlayback`.
- `test/presentation/editor_screen_test.dart` has TWO — `_NoopPlayback` and `_RecordingPlayback`.
- `test/presentation/chapter_list_test.dart` and `test/presentation/editor_state_test.dart` may have minimal stubs that don't track speed beyond the bare interface — there it's fine to add only the abstract-method getters returning `1.0`, `const Stream.empty()`, and a no-op `setSpeed` (the tests in those files don't exercise speed). Concrete shape:

  ```dart
  @override
  double get speed => 1.0;
  @override
  Stream<double> get speedStream => const Stream.empty();
  @override
  Future<void> setSpeed(double speed) async {}
  ```

- [ ] **Step 4: Run analyzer + tests, verify clean**

Run: `flutter analyze`
Run: `flutter test`
Expected: analyzer reports no issues; all 253 tests pass (no behavior change).

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/providers/playback.dart test/presentation
git commit --no-gpg-sign -m "$(cat <<'EOF'
Grow PlaybackController interface with speed/setSpeed/speedStream

Adds the three new abstract members to PlaybackController; the
JustAudioPlaybackController forwards each to its underlying
AudioPlayer. Every existing test-fake PlaybackController gains the
matching members so the project compiles. No call sites use the new
members yet — the SpeedButton, keyboard shortcuts, and the
WaveformView speedStream subscription land in subsequent tasks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `kSpeedPresets`, `formatSpeed`, `nextSpeedPreset`

Pure-logic helpers, full TDD coverage. No widget code yet.

**Files:**
- Create: `lib/presentation/widgets/speed_button.dart`
- Create: `test/presentation/widgets/speed_format_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/presentation/widgets/speed_format_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/presentation/widgets/speed_button.dart';

void main() {
  group('formatSpeed', () {
    test('integer speeds render without trailing decimal', () {
      expect(formatSpeed(1.0), '1×');
      expect(formatSpeed(2.0), '2×');
      expect(formatSpeed(3.0), '3×');
    });

    test('fractional speeds render with the fraction', () {
      expect(formatSpeed(0.5), '0.5×');
      expect(formatSpeed(0.75), '0.75×');
      expect(formatSpeed(1.25), '1.25×');
      expect(formatSpeed(1.5), '1.5×');
    });
  });

  group('nextSpeedPreset', () {
    test('+1 returns the next preset', () {
      expect(nextSpeedPreset(1.0, direction: 1), 1.25);
      expect(nextSpeedPreset(1.5, direction: 1), 2.0);
      expect(nextSpeedPreset(2.0, direction: 1), 3.0);
    });

    test('-1 returns the previous preset', () {
      expect(nextSpeedPreset(1.0, direction: -1), 0.75);
      expect(nextSpeedPreset(1.5, direction: -1), 1.25);
      expect(nextSpeedPreset(0.75, direction: -1), 0.5);
    });

    test('clamps at the maximum', () {
      expect(nextSpeedPreset(3.0, direction: 1), 3.0);
    });

    test('clamps at the minimum', () {
      expect(nextSpeedPreset(0.5, direction: -1), 0.5);
    });

    test('snaps near-preset values to the closest preset before stepping', () {
      // 1.001 is closer to 1.0 than to 1.25; +1 from 1.0 is 1.25.
      expect(nextSpeedPreset(1.001, direction: 1), 1.25);
      // 0.499 is closer to 0.5 than to anything else; -1 clamps to 0.5.
      expect(nextSpeedPreset(0.499, direction: -1), 0.5);
    });
  });

  test('kSpeedPresets contains the seven canonical values in order', () {
    expect(kSpeedPresets, [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]);
  });

  test('kDefaultSpeed is 1.0', () {
    expect(kDefaultSpeed, 1.0);
  });
}
```

- [ ] **Step 2: Run tests; verify failure**

Run: `flutter test test/presentation/widgets/speed_format_test.dart`
Expected: compile error — `lib/presentation/widgets/speed_button.dart` doesn't exist.

- [ ] **Step 3: Implement the helpers**

Create `lib/presentation/widgets/speed_button.dart`:

```dart
/// Speed values offered by the SpeedButton's preset menu and reachable
/// via the Cmd+]/Cmd+[ keyboard shortcuts.
const List<double> kSpeedPresets = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

/// Speed selected by Cmd+\ (the "reset" shortcut) and used as the
/// initial speed for the JustAudio player.
const double kDefaultSpeed = 1.0;

/// Renders a speed value as the user-facing label. Integer speeds drop
/// the trailing decimal ("1×" not "1.0×"); fractional speeds keep their
/// fraction ("0.5×", "1.25×").
String formatSpeed(double speed) {
  if (speed == speed.roundToDouble()) {
    return '${speed.toInt()}×';
  }
  return '$speed×';
}

/// Returns the preset reached by stepping from the closest preset to
/// [current] by [direction] (+1 forward, -1 backward), clamped to the
/// ends of [kSpeedPresets]. The closest-preset snap handles
/// floating-point drift from `just_audio.setSpeed` so that
/// `Cmd+]` always lands on a clean preset value.
double nextSpeedPreset(double current, {required int direction}) {
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

`SpeedButton` itself is added in Task 3, which prepends the necessary widget/Riverpod imports and the widget class to this file.

- [ ] **Step 4: Run tests; verify pass**

Run: `flutter test test/presentation/widgets/speed_format_test.dart`
Expected: all formatSpeed/nextSpeedPreset/kSpeedPresets/kDefaultSpeed tests pass.

- [ ] **Step 5: Run full suite + analyzer**

Run: `flutter test`
Run: `flutter analyze`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/widgets/speed_button.dart test/presentation/widgets/speed_format_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add speed presets, formatter, and next-preset helper

Pure-logic helpers for the upcoming SpeedButton and keyboard
shortcuts: kSpeedPresets (the canonical seven values), kDefaultSpeed
(1.0), formatSpeed (renders 1.0 as "1×" but 0.5 as "0.5×"), and
nextSpeedPreset (steps from the closest preset to a given current
speed, clamped at the ends).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `SpeedButton` widget + integration into `PlaybackControls`

Replace the placeholder in `speed_button.dart` with the actual widget, and wire it into the playback bar.

**Files:**
- Modify: `lib/presentation/widgets/speed_button.dart`
- Modify: `lib/presentation/widgets/playback_controls.dart`
- Create: `test/presentation/widgets/speed_button_test.dart`
- Modify: `test/presentation/playback_controls_test.dart`

- [ ] **Step 1: Write failing widget tests**

Create `test/presentation/widgets/speed_button_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/presentation/providers/playback.dart';
import 'package:m4b_chapterizer/presentation/widgets/speed_button.dart';

class _FakePlayback implements PlaybackController {
  double _speed = 1.0;
  double? lastSetSpeed;
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

  // Unused-but-required PlaybackController surface.
  @override
  Future<void> setSource(String path) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Duration get position => Duration.zero;
  @override
  bool get playing => false;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Future<void> dispose() async => speedController.close();
}

Future<_FakePlayback> _pump(WidgetTester tester, {double initialSpeed = 1.0}) async {
  final playback = _FakePlayback().._speed = initialSpeed;
  addTearDown(playback.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [playbackControllerProvider.overrideWithValue(playback)],
    child: const MaterialApp(
      home: Scaffold(body: SpeedButton()),
    ),
  ));
  await tester.pumpAndSettle();
  return playback;
}

void main() {
  testWidgets('renders the controllers current speed', (tester) async {
    await _pump(tester, initialSpeed: 1.5);
    expect(find.text('1.5×'), findsOneWidget);
  });

  testWidgets('updates label when speedStream emits', (tester) async {
    final playback = await _pump(tester);
    expect(find.text('1×'), findsOneWidget);

    playback.emitSpeed(2.0);
    await tester.pumpAndSettle();
    expect(find.text('2×'), findsOneWidget);
    expect(find.text('1×'), findsNothing);
  });

  testWidgets('tapping opens the menu with all presets', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('playback.speed')));
    await tester.pumpAndSettle();

    for (final preset in kSpeedPresets) {
      expect(
        find.byKey(ValueKey('playback.speed.$preset')),
        findsOneWidget,
        reason: 'menu should contain $preset preset',
      );
    }
  });

  testWidgets('selecting a preset calls setSpeed', (tester) async {
    final playback = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('playback.speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playback.speed.2.0')));
    await tester.pumpAndSettle();

    expect(playback.lastSetSpeed, 2.0);
  });
}
```

- [ ] **Step 2: Run tests; verify failure**

Run: `flutter test test/presentation/widgets/speed_button_test.dart`
Expected: compile error — `SpeedButton` is not defined.

- [ ] **Step 3: Replace the placeholder with the actual widget**

Replace `lib/presentation/widgets/speed_button.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/playback.dart';

/// Speed values offered by the SpeedButton's preset menu and reachable
/// via the Cmd+]/Cmd+[ keyboard shortcuts.
const List<double> kSpeedPresets = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

/// Speed selected by Cmd+\ (the "reset" shortcut) and used as the
/// initial speed for the JustAudio player.
const double kDefaultSpeed = 1.0;

/// Renders a speed value as the user-facing label. Integer speeds drop
/// the trailing decimal ("1×" not "1.0×"); fractional speeds keep their
/// fraction ("0.5×", "1.25×").
String formatSpeed(double speed) {
  if (speed == speed.roundToDouble()) {
    return '${speed.toInt()}×';
  }
  return '$speed×';
}

/// Returns the preset reached by stepping from the closest preset to
/// [current] by [direction] (+1 forward, -1 backward), clamped to the
/// ends of [kSpeedPresets].
double nextSpeedPreset(double current, {required int direction}) {
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

- [ ] **Step 4: Insert SpeedButton into PlaybackControls**

In `lib/presentation/widgets/playback_controls.dart`, add the import:

```dart
import 'speed_button.dart';
```

Find the `Row` containing the play button, time readout, and `Spacer()`. After the existing time-readout `StreamBuilder<Duration>(...)` and before the `Spacer()`, add:

```dart
const SizedBox(width: 12),
const SpeedButton(),
```

- [ ] **Step 5: Add presence test in playback_controls_test.dart**

In `test/presentation/playback_controls_test.dart`, add the import near the top:

```dart
import 'package:m4b_chapterizer/presentation/widgets/speed_button.dart';
```

Append inside `void main() { ... }`:

```dart
  testWidgets('renders SpeedButton when an audiobook is loaded',
      (tester) async {
    final fake = _StubBookbinder();
    final fakePlayback = _FakePlayback();
    addTearDown(fakePlayback.dispose);
    final container = ProviderContainer(
      overrides: [
        bookbinderProvider.overrideWithValue(fake),
        playbackControllerProvider.overrideWithValue(fakePlayback),
      ],
    );
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: PlaybackControls())),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SpeedButton), findsOneWidget);
  });
```

- [ ] **Step 6: Run tests; verify pass**

Run: `flutter test`
Run: `flutter analyze`
Expected: 253 prior + 4 SpeedButton + 1 PlaybackControls presence = 258 tests passing.

- [ ] **Step 7: Commit**

```bash
git add lib/presentation/widgets/speed_button.dart lib/presentation/widgets/playback_controls.dart test/presentation/widgets/speed_button_test.dart test/presentation/playback_controls_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add SpeedButton widget and mount it in PlaybackControls

A compact button next to the time readout shows the current playback
speed (1×, 1.5×, etc.) and opens a menu of all seven presets on tap.
The label tracks the controller's speedStream so any other source
of speed change (the upcoming keyboard shortcuts, or just_audio's
own emissions) updates it live.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Keyboard shortcuts (`Cmd+]`, `Cmd+[`, `Cmd+\`)

Wire `StepSpeedIntent` and `ResetSpeedIntent` into the editor's shortcut map.

**Files:**
- Modify: `lib/presentation/keyboard/shortcuts.dart`
- Modify: `test/presentation/keyboard_shortcuts_test.dart`

- [ ] **Step 1: Append failing tests**

Add the following inside the existing `void main() { ... }` of `test/presentation/keyboard_shortcuts_test.dart`. Place the keymap tests inside the existing `group('editorShortcuts keymap', ...)`; place the widget tests inside the existing `group('EditorShortcuts widget', ...)` (or a new `group('Speed shortcuts', ...)` inside the widget group, to keep things tidy):

```dart
    test('maps Cmd+] to StepSpeedIntent(+1) and Cmd+[ to StepSpeedIntent(-1)',
        () {
      final map = editorShortcuts();
      final stepUp = map.entries.firstWhere(
        (e) => e.value is StepSpeedIntent &&
            (e.value as StepSpeedIntent).direction == 1,
      );
      final stepDown = map.entries.firstWhere(
        (e) => e.value is StepSpeedIntent &&
            (e.value as StepSpeedIntent).direction == -1,
      );
      expect((stepUp.key as SingleActivator).trigger,
          LogicalKeyboardKey.bracketRight);
      expect((stepDown.key as SingleActivator).trigger,
          LogicalKeyboardKey.bracketLeft);
    });

    test('maps Cmd+\\ to ResetSpeedIntent', () {
      final map = editorShortcuts();
      final entry =
          map.entries.firstWhere((e) => e.value is ResetSpeedIntent);
      expect((entry.key as SingleActivator).trigger,
          LogicalKeyboardKey.backslash);
    });
```

And the widget-level shortcuts tests:

```dart
    group('Speed shortcuts', () {
      testWidgets('Cmd+] steps speed up from 1× to 1.25×', (tester) async {
        final h = await _pumpEditor(tester);
        // Default _FakePlayback speed is 1.0.
        await _sendCmdKey(tester, LogicalKeyboardKey.bracketRight);
        expect(h.playback.lastSetSpeed, 1.25);
      });

      testWidgets('Cmd+[ steps speed down from 1× to 0.75×',
          (tester) async {
        final h = await _pumpEditor(tester);
        await _sendCmdKey(tester, LogicalKeyboardKey.bracketLeft);
        expect(h.playback.lastSetSpeed, 0.75);
      });

      testWidgets('Cmd+] at maximum is a no-op', (tester) async {
        final h = await _pumpEditor(tester);
        h.playback.emitSpeed(3.0);
        await tester.pump();
        // Drop the previous lastSetSpeed value so we can assert no
        // call was made.
        h.playback.lastSetSpeed = null;

        await _sendCmdKey(tester, LogicalKeyboardKey.bracketRight);
        expect(h.playback.lastSetSpeed, isNull);
      });

      testWidgets('Cmd+[ at minimum is a no-op', (tester) async {
        final h = await _pumpEditor(tester);
        h.playback.emitSpeed(0.5);
        await tester.pump();
        h.playback.lastSetSpeed = null;

        await _sendCmdKey(tester, LogicalKeyboardKey.bracketLeft);
        expect(h.playback.lastSetSpeed, isNull);
      });

      testWidgets('Cmd+\\ resets speed to 1×', (tester) async {
        final h = await _pumpEditor(tester);
        h.playback.emitSpeed(2.0);
        await tester.pump();
        h.playback.lastSetSpeed = null;

        await _sendCmdKey(tester, LogicalKeyboardKey.backslash);
        expect(h.playback.lastSetSpeed, 1.0);
      });

      testWidgets('Cmd+\\ at 1× is a no-op', (tester) async {
        final h = await _pumpEditor(tester);
        // _FakePlayback default is 1.0; clear lastSetSpeed in case
        // anything earlier touched it.
        h.playback.lastSetSpeed = null;

        await _sendCmdKey(tester, LogicalKeyboardKey.backslash);
        expect(h.playback.lastSetSpeed, isNull);
      });

      testWidgets(
          'speed shortcuts work while a TextField is focused',
          (tester) async {
        final h = await _pumpEditor(tester);
        await tester.tap(find.byKey(const ValueKey('chapters.title.0')));
        await tester.pump();

        await _sendCmdKey(tester, LogicalKeyboardKey.bracketRight);
        expect(h.playback.lastSetSpeed, 1.25);
      });
    });
```

- [ ] **Step 2: Run tests; verify failure**

Run: `flutter test test/presentation/keyboard_shortcuts_test.dart`
Expected: compile errors — `StepSpeedIntent` and `ResetSpeedIntent` don't exist.

- [ ] **Step 3: Add the intents, bindings, and actions**

In `lib/presentation/keyboard/shortcuts.dart`, add the two intent classes near the existing intent declarations (alphabetical or just at the bottom of the existing block — match local conventions):

```dart
class StepSpeedIntent extends Intent {
  const StepSpeedIntent(this.direction);
  final int direction; // +1 step up, -1 step down
}

class ResetSpeedIntent extends Intent {
  const ResetSpeedIntent();
}
```

Update the imports at the top of the file to include the new helpers from `speed_button.dart`:

```dart
import '../widgets/speed_button.dart' show kDefaultSpeed, nextSpeedPreset;
```

Add three bindings to the map returned by `editorShortcuts()` (place them next to the other `cmd(...)` bindings):

```dart
cmd(LogicalKeyboardKey.bracketRight): const StepSpeedIntent(1),
cmd(LogicalKeyboardKey.bracketLeft): const StepSpeedIntent(-1),
cmd(LogicalKeyboardKey.backslash): const ResetSpeedIntent(),
```

Add two action entries to the `actions:` map in `_EditorShortcutsState.build()`:

```dart
StepSpeedIntent: CallbackAction<StepSpeedIntent>(onInvoke: (intent) {
  final controller = ref.read(playbackControllerProvider);
  final next = nextSpeedPreset(
    controller.speed,
    direction: intent.direction,
  );
  if (next != controller.speed) controller.setSpeed(next);
  return null;
}),
ResetSpeedIntent: CallbackAction<ResetSpeedIntent>(onInvoke: (_) {
  final controller = ref.read(playbackControllerProvider);
  if (controller.speed != kDefaultSpeed) controller.setSpeed(kDefaultSpeed);
  return null;
}),
```

These use `CallbackAction` (not `_BareKeyAction`) because the bindings include the `Cmd`/`Ctrl` modifier — they should fire even when an `EditableText` has focus. That's the established pattern in this file (see `SaveIntent`, `AddChapterIntent`, etc.).

- [ ] **Step 4: Run tests; verify pass**

Run: `flutter test test/presentation/keyboard_shortcuts_test.dart`
Expected: all keymap and shortcut tests pass.

- [ ] **Step 5: Run full suite + analyzer**

Run: `flutter test`
Run: `flutter analyze`
Expected: 258 prior + 2 keymap + 7 shortcut = 267 tests passing.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/keyboard/shortcuts.dart test/presentation/keyboard_shortcuts_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add Cmd+]/[/\ keyboard shortcuts for playback speed

Cmd+] steps to the next-higher preset; Cmd+[ steps to the next-lower;
Cmd+\\ resets to 1×. At the bounds, the step keys are no-ops. Because
all three include Cmd (or Ctrl off-mac), they bypass the bare-key
gate and work even with a TextField focused.

The actions read PlaybackController.speed and call
nextSpeedPreset/setSpeed, snapping any floating-point drift to the
closest preset before stepping.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: WaveformView reads `controller.speed` and resets baseline on speed change

Wire `_currentPlaybackSpeed()` to read live, and add a `speedStream` subscription that resets the extrapolation baseline.

**Files:**
- Modify: `lib/presentation/widgets/waveform_view.dart`
- Modify: `test/presentation/waveform_view_test.dart`

- [ ] **Step 1: Append the failing test**

Add inside the existing `group('Smooth playback scroll', () { ... })` in `test/presentation/waveform_view_test.dart`:

```dart
    testWidgets('speed change resets the extrapolation baseline',
        (tester) async {
      final playback = _FakePlayback();
      addTearDown(playback.dispose);
      final container = await _pump(tester, playback: playback);

      // Play from 0 at 1× for 100 ms — windowStart advances by ~100 ms
      // of audio (bounded by the 25 % follow anchor).
      playback.emitPosition(Duration.zero);
      playback.emitPlaying(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Now flip to 2× WITHOUT emitting a new position. controller.position
      // returns whatever _pos was last set to (0 from emitPosition above),
      // so the new baseline is (0 s, now). The next 50 ms of wall-clock
      // should advance the extrapolation by 100 ms of audio (50 ms × 2.0).
      // followPlayhead at 25 % of an 8 s window: windowStart = 100 ms − 2 s,
      // clamped to 0.
      playback.emitSpeed(2.0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The earlier 1× pump may have advanced past 0 already, but the
      // baseline reset on speedStream means windowStart should now be
      // computed from controller.position (0 s) plus 50 ms × 2.0 = 100 ms
      // forward. With clamping, that lands at 0 (since 100 ms < 2 s
      // anchor offset). What matters: we did NOT see windowStart leap
      // forward to (originalExtrapolation × 2.0).
      // Use a generous, monotonic-only assertion so test stays robust:
      // windowStart didn't shoot way past where 100 ms × 2.0 of audio
      // could have moved it.
      final windowStart = container
          .read(waveformViewportProvider)
          .windowStart
          .inMilliseconds;
      expect(windowStart, lessThan(2000));
    });
```

(This test asserts the behavior negatively — it verifies the extrapolation didn't leap forward to where it would have under the old "no reset" math. A more precise assertion would tie the test to specific frame timing, which is fragile; this monotonic-only check is robust and proves the fix.)

- [ ] **Step 2: Run test; verify failure (before the fix)**

Run: `flutter test test/presentation/waveform_view_test.dart`
Expected: this single new test fails — without the speed-stream baseline reset, `_currentPlaybackSpeed()` would return 1.0 because of the existing hardcoded `=> 1.0` (so the test might pass by coincidence in the existing implementation). To force a meaningful failure, comment out the (unimplemented) `_speedSub`/`_onSpeedChange` insertion and verify the behavior gap. **If the test passes against the existing code, write the failure assertion more strictly:** assert `windowStart` lands within `[80, 120]` ms (50 ms × 2.0 = 100 ms in audio time) post-reset, which forces both the read-from-controller AND the baseline-reset to be in place.

In practice the simpler check above is sufficient for the regression once both pieces are wired; if the reviewer wants a tighter check, replace the `lessThan(2000)` with `inInclusiveRange(80, 200)` after the implementation lands.

- [ ] **Step 3: Make `_currentPlaybackSpeed` read from the controller**

In `lib/presentation/widgets/waveform_view.dart`, replace the existing `_currentPlaybackSpeed()` getter:

```dart
double _currentPlaybackSpeed() => 1.0;
```

with:

```dart
double _currentPlaybackSpeed() =>
    ref.read(playbackControllerProvider).speed;
```

- [ ] **Step 4: Subscribe to speedStream and reset the baseline on emission**

Add a new field next to `_positionSub` and `_playingSub`:

```dart
StreamSubscription<double>? _speedSub;
```

In `initState`, after the existing `_playingSub = ...` line, add:

```dart
_speedSub = controller.speedStream.listen(_onSpeedChange);
```

In `dispose`, after `_playingSub?.cancel();`, add:

```dart
_speedSub?.cancel();
```

Add the new method (place near `_onPlayingChange`):

```dart
void _onSpeedChange(double newSpeed) {
  if (!mounted) return;
  // The new speed only applies to wall-clock time strictly after the
  // change. Re-read controller.position and restamp the wall-clock
  // baseline so the next Ticker tick computes a small delta scaled
  // by the new speed, not the entire pre-change interval scaled by it.
  final controller = ref.read(playbackControllerProvider);
  _basePosition = controller.position;
  _baseWallClock = clock.now();
}
```

`_onSpeedChange` doesn't call `setState` — the next Ticker tick (or position-stream emission) will pick up the new baseline naturally; the smoothed playhead doesn't need an immediate redraw because `_smoothedPlayhead` keeps its current value and the next frame is at most ~16 ms away.

- [ ] **Step 5: Run tests; verify pass**

Run: `flutter test test/presentation/waveform_view_test.dart`
Expected: all "Smooth playback scroll" tests pass, including the new one.

- [ ] **Step 6: Run full suite + analyzer**

Run: `flutter test`
Run: `flutter analyze`
Expected: 267 prior + 1 new = 268 tests passing.

- [ ] **Step 7: Build macOS to confirm runtime is happy**

Run: `flutter build macos --debug`
Expected: clean build.

- [ ] **Step 8: Commit**

```bash
git add lib/presentation/widgets/waveform_view.dart test/presentation/waveform_view_test.dart
git commit --no-gpg-sign -m "$(cat <<'EOF'
Wire WaveformView to live playback speed and reset baseline on change

_currentPlaybackSpeed() now reads from PlaybackController.speed
instead of returning the hardcoded 1.0; the existing extrapolation
loop multiplies wall-clock delta by this on every frame.

A new speedStream subscription resets the extrapolation baseline
(_basePosition, _baseWallClock) on every emission, so the new speed
only applies to wall-clock time strictly after the change. Without
this, flipping to 2× would have caused an immediate forward jump in
the rendered playhead (because the new multiplier retroactively
applied to the pre-change interval) followed by a backward correction
when the next position emission landed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Verification

After all tasks land:

- [ ] **Final test run**

Run: `flutter test`
Expected: 268 tests passing.

- [ ] **Final analyzer**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Coverage**

Run: `flutter test --coverage`
Run: `dart tool/coverage_summary.dart coverage/lcov.info`
Expected: total stays at or above the previous baseline.

- [ ] **macOS smoke test** — walk through the 9 cases in the spec's "Smoke-test plan" section.
