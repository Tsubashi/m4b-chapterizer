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
