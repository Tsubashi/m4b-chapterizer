import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/presentation/keyboard/shortcuts.dart';

void main() {
  group('editorShortcuts keymap', () {
    test('maps Space to PlayPauseIntent', () {
      final map = editorShortcuts();
      final entry = map.entries.firstWhere(
        (e) => e.value is PlayPauseIntent,
        orElse: () => throw StateError('no PlayPauseIntent'),
      );
      expect(entry.key,
          const SingleActivator(LogicalKeyboardKey.space));
    });

    test('maps ArrowLeft to ScrubIntent(-5s) and ArrowRight to +5s', () {
      final map = editorShortcuts();
      final left = map[const SingleActivator(LogicalKeyboardKey.arrowLeft)];
      final right = map[const SingleActivator(LogicalKeyboardKey.arrowRight)];
      expect(left, isA<ScrubIntent>());
      expect((left as ScrubIntent).delta, const Duration(seconds: -5));
      expect(right, isA<ScrubIntent>());
      expect((right as ScrubIntent).delta, const Duration(seconds: 5));
    });

    test('maps Shift+ArrowLeft and Shift+ArrowRight to ±30s', () {
      final map = editorShortcuts();
      final shiftLeft =
          map[const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true)];
      final shiftRight = map[
          const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true)];
      expect((shiftLeft as ScrubIntent).delta, const Duration(seconds: -30));
      expect((shiftRight as ScrubIntent).delta, const Duration(seconds: 30));
    });

    test('maps ArrowUp/ArrowDown to MoveChapterSelectionIntent ±1', () {
      final map = editorShortcuts();
      final up = map[const SingleActivator(LogicalKeyboardKey.arrowUp)];
      final down = map[const SingleActivator(LogicalKeyboardKey.arrowDown)];
      expect((up as MoveChapterSelectionIntent).delta, -1);
      expect((down as MoveChapterSelectionIntent).delta, 1);
    });

    test('uses meta modifier on macOS, control elsewhere for Save', () {
      final map = editorShortcuts();
      final saveEntry = map.entries.firstWhere((e) => e.value is SaveIntent);
      final activator = saveEntry.key as SingleActivator;
      expect(activator.trigger, LogicalKeyboardKey.keyS);
      if (Platform.isMacOS) {
        expect(activator.meta, isTrue);
        expect(activator.control, isFalse);
      } else {
        expect(activator.meta, isFalse);
        expect(activator.control, isTrue);
      }
    });

    test('contains entries for the documented intents', () {
      final map = editorShortcuts();
      final intentTypes = map.values.map((v) => v.runtimeType).toSet();
      expect(intentTypes, containsAll(<Type>[
        PlayPauseIntent,
        ScrubIntent,
        MoveChapterSelectionIntent,
        FocusSelectedChapterTitleIntent,
        DeleteSelectedChapterIntent,
        AddChapterIntent,
        SaveIntent,
        SaveAsIntent,
        OpenFileIntent,
        SetChapterToPlayheadIntent,
        DefocusIntent,
      ]));
    });
  });
}
