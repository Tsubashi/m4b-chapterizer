import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class PlayPauseIntent extends Intent {
  const PlayPauseIntent();
}

class ScrubIntent extends Intent {
  const ScrubIntent(this.delta);
  final Duration delta;
}

class MoveChapterSelectionIntent extends Intent {
  const MoveChapterSelectionIntent(this.delta);
  final int delta;
}

class FocusSelectedChapterTitleIntent extends Intent {
  const FocusSelectedChapterTitleIntent();
}

class DeleteSelectedChapterIntent extends Intent {
  const DeleteSelectedChapterIntent();
}

class AddChapterIntent extends Intent {
  const AddChapterIntent();
}

class SaveIntent extends Intent {
  const SaveIntent();
}

class SaveAsIntent extends Intent {
  const SaveAsIntent();
}

class OpenFileIntent extends Intent {
  const OpenFileIntent();
}

class SetChapterToPlayheadIntent extends Intent {
  const SetChapterToPlayheadIntent();
}

class DefocusIntent extends Intent {
  const DefocusIntent();
}

/// Returns the editor's full keyboard shortcut map, with platform-correct
/// modifiers (`⌘` on macOS, `Ctrl` elsewhere).
Map<ShortcutActivator, Intent> editorShortcuts() {
  final isMac = Platform.isMacOS;
  SingleActivator cmd(LogicalKeyboardKey trigger, {bool shift = false}) =>
      SingleActivator(
        trigger,
        meta: isMac,
        control: !isMac,
        shift: shift,
      );

  return <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.space): const PlayPauseIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowLeft):
        const ScrubIntent(Duration(seconds: -5)),
    const SingleActivator(LogicalKeyboardKey.arrowRight):
        const ScrubIntent(Duration(seconds: 5)),
    const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
        const ScrubIntent(Duration(seconds: -30)),
    const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
        const ScrubIntent(Duration(seconds: 30)),
    const SingleActivator(LogicalKeyboardKey.arrowUp):
        const MoveChapterSelectionIntent(-1),
    const SingleActivator(LogicalKeyboardKey.arrowDown):
        const MoveChapterSelectionIntent(1),
    const SingleActivator(LogicalKeyboardKey.enter):
        const FocusSelectedChapterTitleIntent(),
    const SingleActivator(LogicalKeyboardKey.backspace):
        const DeleteSelectedChapterIntent(),
    const SingleActivator(LogicalKeyboardKey.escape): const DefocusIntent(),
    cmd(LogicalKeyboardKey.keyN): const AddChapterIntent(),
    cmd(LogicalKeyboardKey.keyS): const SaveIntent(),
    cmd(LogicalKeyboardKey.keyS, shift: true): const SaveAsIntent(),
    cmd(LogicalKeyboardKey.keyO): const OpenFileIntent(),
    cmd(LogicalKeyboardKey.keyB): const SetChapterToPlayheadIntent(),
  };
}
