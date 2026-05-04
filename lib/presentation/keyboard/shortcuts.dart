import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor_state.dart';
import '../providers/playback.dart';
import '../widgets/chapter_list.dart'
    show
        chapterScrollRequestProvider,
        chapterStartCommitProvider,
        chapterStartFocusNodesProvider,
        chapterTitleFocusNodesProvider,
        selectedChapterProvider;
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

class UndoIntent extends Intent {
  const UndoIntent();
}

class RedoIntent extends Intent {
  const RedoIntent();
}

class ChapterFieldTabIntent extends Intent {
  const ChapterFieldTabIntent(this.delta);
  final int delta; // +1 for Tab, -1 for Shift+Tab
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
    cmd(LogicalKeyboardKey.keyZ): const UndoIntent(),
    cmd(LogicalKeyboardKey.keyZ, shift: true): const RedoIntent(),
    const SingleActivator(LogicalKeyboardKey.tab):
        const ChapterFieldTabIntent(1),
    const SingleActivator(LogicalKeyboardKey.tab, shift: true):
        const ChapterFieldTabIntent(-1),
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

enum _ChapterFieldType { title, start }

class _FocusedChapterField {
  const _FocusedChapterField(this.index, this.type);
  final int index;
  final _ChapterFieldType type;
}

_FocusedChapterField? _focusedChapterField(WidgetRef ref) {
  final focused = FocusManager.instance.primaryFocus;
  if (focused == null) return null;
  final titles = ref.read(chapterTitleFocusNodesProvider);
  for (final entry in titles.entries) {
    if (entry.value == focused) {
      return _FocusedChapterField(entry.key, _ChapterFieldType.title);
    }
  }
  final starts = ref.read(chapterStartFocusNodesProvider);
  for (final entry in starts.entries) {
    if (entry.value == focused) {
      return _FocusedChapterField(entry.key, _ChapterFieldType.start);
    }
  }
  return null;
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

/// An action that runs only when focus is on a chapter title or start
/// field. When the action is disabled, Flutter's default focus
/// traversal handles the key press normally.
class _ChapterFieldAction<T extends Intent> extends Action<T> {
  _ChapterFieldAction(this._ref, this._onInvoke);

  final WidgetRef _ref;
  final Object? Function(T intent, _FocusedChapterField field) _onInvoke;

  @override
  bool isEnabled(T intent, [BuildContext? context]) =>
      _focusedChapterField(_ref) != null;

  @override
  bool consumesKey(T intent) => _focusedChapterField(_ref) != null;

  @override
  Object? invoke(T intent) {
    final field = _focusedChapterField(_ref);
    if (field == null) return null;
    return _onInvoke(intent, field);
  }
}

/// Up/Down handler. Three branches:
/// - Focus on a chapter title or start field: commit any pending edit and
///   jump to the corresponding field of the chapter above/below.
/// - Focus on a non-chapter EditableText (metadata): action is disabled so
///   the field's own arrow handling runs.
/// - No field focused: move chapter selection, clamp at bounds, seek.
class _MoveChapterSelectionAction
    extends Action<MoveChapterSelectionIntent> {
  _MoveChapterSelectionAction(this._ref);

  final WidgetRef _ref;

  bool _isInOtherEditableText() {
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null) return false;
    final inEditable =
        focused.context?.findAncestorWidgetOfExactType<EditableText>() !=
            null;
    if (!inEditable) return false;
    return _focusedChapterField(_ref) == null;
  }

  @override
  bool isEnabled(MoveChapterSelectionIntent intent, [BuildContext? c]) =>
      !_isInOtherEditableText();

  @override
  bool consumesKey(MoveChapterSelectionIntent intent) =>
      !_isInOtherEditableText();

  @override
  Object? invoke(MoveChapterSelectionIntent intent) {
    final field = _focusedChapterField(_ref);
    if (field != null) {
      return _invokeChapterFieldBranch(intent, field);
    }
    return _invokeNoFocusBranch(intent);
  }

  Object? _invokeChapterFieldBranch(
    MoveChapterSelectionIntent intent,
    _FocusedChapterField field,
  ) {
    final book = _ref.read(editorProvider).audiobook;
    if (book == null) return null;
    final n = book.chapters.length;
    final targetIdx = field.index + intent.delta;
    if (targetIdx < 0 || targetIdx >= n) return null;

    final targetChapter = book.chapters[targetIdx];

    if (field.type == _ChapterFieldType.start) {
      _ref.read(chapterStartCommitProvider)[field.index]?.call();
    }

    final newBook = _ref.read(editorProvider).audiobook;
    if (newBook == null) return null;
    final newIdx =
        newBook.chapters.indexWhere((c) => identical(c, targetChapter));
    // Fallback for the case where setChapterStart rebuilt the target's
    // own object via copyWith (only happens when delta == 0, which we
    // already filtered, but matched for parity with Tab action).
    final resolvedIdx = (newIdx < 0 &&
            targetIdx >= 0 &&
            targetIdx < newBook.chapters.length)
        ? targetIdx
        : newIdx;
    if (resolvedIdx < 0) return null;

    _ref.read(selectedChapterProvider.notifier).state = resolvedIdx;
    _ref
        .read(playbackControllerProvider)
        .seek(newBook.chapters[resolvedIdx].start);
    _ref.read(chapterScrollRequestProvider.notifier).state++;

    final node = field.type == _ChapterFieldType.title
        ? _ref.read(chapterTitleFocusNodesProvider)[resolvedIdx]
        : _ref.read(chapterStartFocusNodesProvider)[resolvedIdx];
    node?.requestFocus();
    return null;
  }

  Object? _invokeNoFocusBranch(MoveChapterSelectionIntent intent) {
    final book = _ref.read(editorProvider).audiobook;
    if (book == null) return null;
    final cur = _ref.read(selectedChapterProvider);
    final next =
        (cur + intent.delta).clamp(0, book.chapters.length - 1);
    if (next == cur) return null;
    _ref.read(selectedChapterProvider.notifier).state = next;
    _ref
        .read(playbackControllerProvider)
        .seek(book.chapters[next].start);
    _ref.read(chapterScrollRequestProvider.notifier).state++;
    return null;
  }
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
          MoveChapterSelectionIntent: _MoveChapterSelectionAction(ref),
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
          // coverage:ignore-start
          // Cmd+O / Cmd+Shift+S bridge to EditorActions.open / saveAs,
          // which surface the FilePicker. The EditorActions methods
          // themselves are coverage-ignored above for the same reason.
          OpenFileIntent: CallbackAction<OpenFileIntent>(onInvoke: (_) {
            EditorActions(context, ref).open();
            return null;
          }),
          SaveAsIntent: CallbackAction<SaveAsIntent>(onInvoke: (_) {
            EditorActions(context, ref).saveAs();
            return null;
          }),
          // coverage:ignore-end
          FocusSelectedChapterTitleIntent:
              _BareKeyAction<FocusSelectedChapterTitleIntent>((_) {
            final idx = ref.read(selectedChapterProvider);
            final nodes = ref.read(chapterTitleFocusNodesProvider);
            nodes[idx]?.requestFocus();
            return null;
          }),
          UndoIntent: CallbackAction<UndoIntent>(onInvoke: (_) {
            final notifier = ref.read(editorProvider.notifier);
            if (_isEditableTextFocused()) {
              notifier.cancelFieldEdit();
              FocusManager.instance.primaryFocus?.unfocus();
            } else {
              notifier.undo();
            }
            return null;
          }),
          RedoIntent: CallbackAction<RedoIntent>(onInvoke: (_) {
            if (_isEditableTextFocused()) return null;
            ref.read(editorProvider.notifier).redo();
            return null;
          }),
          ChapterFieldTabIntent: _ChapterFieldAction<ChapterFieldTabIntent>(
              ref, (intent, field) {
            final book = ref.read(editorProvider).audiobook;
            if (book == null) return null;
            final n = book.chapters.length;
            if (n == 0) return null;

            // Compute next (chapterIdx, fieldType).
            late int nextIdx;
            late _ChapterFieldType nextType;
            if (intent.delta > 0) {
              if (field.type == _ChapterFieldType.title) {
                nextIdx = field.index;
                nextType = _ChapterFieldType.start;
              } else {
                nextIdx = (field.index + 1) % n;
                nextType = _ChapterFieldType.title;
              }
            } else {
              if (field.type == _ChapterFieldType.start) {
                nextIdx = field.index;
                nextType = _ChapterFieldType.title;
              } else {
                nextIdx = (field.index - 1 + n) % n;
                nextType = _ChapterFieldType.start;
              }
            }

            // Capture the target chapter reference from the pre-commit list.
            final targetChapter = book.chapters[nextIdx];

            // Commit any pending start-field edit.
            if (field.type == _ChapterFieldType.start) {
              ref.read(chapterStartCommitProvider)[field.index]?.call();
            }

            // Look up target's new index in the (possibly-reordered) list.
            // If the commit replaced the target chapter (e.g. we just edited
            // its own start time), identity will not match — fall back to
            // the pre-commit index, which is still valid since a same-row
            // navigation cannot have been reordered relative to itself.
            final newBook = ref.read(editorProvider).audiobook;
            if (newBook == null) return null;
            var newIdx = newBook.chapters.indexWhere(
              (c) => identical(c, targetChapter),
            );
            if (newIdx < 0) {
              if (nextIdx >= 0 && nextIdx < newBook.chapters.length) {
                newIdx = nextIdx;
              } else {
                return null;
              }
            }

            ref.read(selectedChapterProvider.notifier).state = newIdx;

            final node = nextType == _ChapterFieldType.title
                ? ref.read(chapterTitleFocusNodesProvider)[newIdx]
                : ref.read(chapterStartFocusNodesProvider)[newIdx];
            node?.requestFocus();
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
