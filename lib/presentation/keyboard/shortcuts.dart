import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor_state.dart';
import '../providers/playback.dart';
import '../widgets/chapter_list.dart'
    show selectedChapterProvider, chapterTitleFocusNodesProvider;
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

/// True when an [EditableText] is currently the primary focus. Bare-key
/// shortcuts (Space, arrows, Backspace, Enter) defer to the focused field;
/// modifier shortcuts (Cmd/Ctrl-prefixed) and Esc do not.
bool _isEditableTextFocused() {
  final focused = FocusManager.instance.primaryFocus;
  return focused?.context?.findAncestorWidgetOfExactType<EditableText>() !=
      null;
}

/// A [CallbackAction] that disables itself (returning [KeyEventResult.ignored]
/// from the surrounding [Shortcuts] widget) whenever an [EditableText] has
/// focus, so the key event propagates to the focused field for text input.
class _BareKeyAction<T extends Intent> extends Action<T> {
  _BareKeyAction(this._onInvoke);

  final Object? Function(T intent) _onInvoke;

  @override
  bool isEnabled(T intent, [BuildContext? context]) =>
      !_isEditableTextFocused();

  @override
  bool consumesKey(T intent) => !_isEditableTextFocused();

  @override
  Object? invoke(T intent) => _onInvoke(intent);
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
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  /// Re-claim focus when primary focus drifts above our `Shortcuts` widget
  /// (e.g. after `FocusManager.instance.primaryFocus?.unfocus()`), so that
  /// keyboard shortcuts continue to route through us.
  void _onFocusChanged() {
    if (!mounted) return;
    final current = FocusManager.instance.primaryFocus;
    if (current == null) {
      _focusNode.requestFocus();
      return;
    }
    // If the current focus is a descendant of our node (or is our node),
    // there's nothing to do.
    final ancestorContext =
        current.context?.findAncestorWidgetOfExactType<EditableText>();
    if (ancestorContext != null) return; // a TextField owns the focus
    if (current == _focusNode) return;
    if (_hasAncestor(current, _focusNode)) return;
    _focusNode.requestFocus();
  }

  /// Returns true if [node] has [candidate] anywhere on its parent chain.
  bool _hasAncestor(FocusNode node, FocusNode candidate) {
    FocusNode? n = node.parent;
    while (n != null) {
      if (n == candidate) return true;
      n = n.parent;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    return Shortcuts(
      shortcuts: editorShortcuts(),
      child: Actions(
        actions: <Type, Action<Intent>>{
          PlayPauseIntent: _BareKeyAction<PlayPauseIntent>((_) {
            final c = ref.read(playbackControllerProvider);
            c.playing ? c.pause() : c.play();
            return null;
          }),
          ScrubIntent: _BareKeyAction<ScrubIntent>((intent) {
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
              _BareKeyAction<MoveChapterSelectionIntent>((intent) {
            final book = ref.read(editorProvider).audiobook;
            if (book == null) return null;
            final cur = ref.read(selectedChapterProvider);
            final next = (cur + intent.delta)
                .clamp(0, book.chapters.length - 1);
            ref.read(selectedChapterProvider.notifier).state = next;
            return null;
          }),
          DeleteSelectedChapterIntent:
              _BareKeyAction<DeleteSelectedChapterIntent>((_) {
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
          FocusSelectedChapterTitleIntent:
              _BareKeyAction<FocusSelectedChapterTitleIntent>((_) {
            final idx = ref.read(selectedChapterProvider);
            final nodes = ref.read(chapterTitleFocusNodesProvider);
            nodes[idx]?.requestFocus();
            return null;
          }),
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
