import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor_state.dart';
import '../providers/playback.dart';
import '../widgets/chapter_list.dart' show selectedChapterProvider;
import 'editor_actions.dart';

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

class EditorShortcuts extends ConsumerStatefulWidget {
  const EditorShortcuts({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<EditorShortcuts> createState() => _EditorShortcutsState();
}

class _EditorShortcutsState extends ConsumerState<EditorShortcuts> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'EditorShortcuts');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    return Shortcuts(
      shortcuts: editorShortcuts(),
      child: Actions(
        actions: <Type, Action<Intent>>{
          PlayPauseIntent: CallbackAction<PlayPauseIntent>(onInvoke: (_) {
            final c = ref.read(playbackControllerProvider);
            c.playing ? c.pause() : c.play();
            return null;
          }),
          ScrubIntent: CallbackAction<ScrubIntent>(onInvoke: (intent) {
            final c = ref.read(playbackControllerProvider);
            final book = ref.read(editorProvider).audiobook;
            if (book == null) return null;
            final raw = c.position + intent.delta;
            final clamped = raw < Duration.zero
                ? Duration.zero
                : (raw > book.totalDuration ? book.totalDuration : raw);
            c.seek(clamped);
            return null;
          }),
          MoveChapterSelectionIntent:
              CallbackAction<MoveChapterSelectionIntent>(onInvoke: (intent) {
            final book = ref.read(editorProvider).audiobook;
            if (book == null) return null;
            final cur = ref.read(selectedChapterProvider);
            final next = (cur + intent.delta)
                .clamp(0, book.chapters.length - 1);
            ref.read(selectedChapterProvider.notifier).state = next;
            return null;
          }),
          DeleteSelectedChapterIntent:
              CallbackAction<DeleteSelectedChapterIntent>(onInvoke: (_) {
            final book = ref.read(editorProvider).audiobook;
            if (book == null) return null;
            final idx = ref.read(selectedChapterProvider);
            ref.read(editorProvider.notifier).deleteChapter(idx);
            return null;
          }),
          AddChapterIntent: CallbackAction<AddChapterIntent>(onInvoke: (_) {
            ref.read(editorProvider.notifier).addChapter();
            return null;
          }),
          SaveIntent: CallbackAction<SaveIntent>(onInvoke: (_) {
            ref.read(editorProvider.notifier).save();
            return null;
          }),
          SetChapterToPlayheadIntent:
              CallbackAction<SetChapterToPlayheadIntent>(onInvoke: (_) {
            final book = ref.read(editorProvider).audiobook;
            if (book == null) return null;
            final idx = ref.read(selectedChapterProvider);
            final pos = ref.read(playbackControllerProvider).position;
            ref.read(editorProvider.notifier).setChapterStart(idx, pos);
            return null;
          }),
          DefocusIntent: CallbackAction<DefocusIntent>(onInvoke: (_) {
            FocusManager.instance.primaryFocus?.unfocus();
            // Re-claim focus on this widget so subsequent shortcuts still
            // route through `Shortcuts`.
            _focusNode.requestFocus();
            return null;
          }),
          OpenFileIntent: CallbackAction<OpenFileIntent>(onInvoke: (_) {
            EditorActions(context, ref).open();
            return null;
          }),
          SaveAsIntent: CallbackAction<SaveAsIntent>(onInvoke: (_) {
            EditorActions(context, ref).saveAs();
            return null;
          }),
          // FocusSelectedChapterTitleIntent is wired in the next task.
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          child: widget.child,
        ),
      ),
    );
  }
}
