import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/models/audiobook.dart';
import '../../domain/models/chapter.dart';
import '../providers/editor_state.dart'
    show EditorNotifier, SetChapterStartError, editorProvider;
import '../providers/playback.dart';
import '../util/duration_format.dart';

final selectedChapterProvider = StateProvider<int>((ref) => 0);

final chapterTitleFocusNodesProvider =
    Provider<Map<int, FocusNode>>((ref) => <int, FocusNode>{});

/// Increments each time `EditorNotifier.undo()` or `redo()` produces a chapter
/// change. The chapter list listens to this counter and scrolls the selected
/// chapter into view when it fires. Click and arrow-key selection do NOT
/// increment this — those are deliberate user actions that don't need a
/// scroll.
final chapterScrollRequestProvider = StateProvider<int>((ref) => 0);

class ChapterList extends ConsumerStatefulWidget {
  const ChapterList({super.key});

  @override
  ConsumerState<ChapterList> createState() => _ChapterListState();
}

class _ChapterListState extends ConsumerState<ChapterList> {
  static const double _kRowHeight = 64;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _ensureSelectedVisible() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final index = ref.read(selectedChapterProvider);
    final chapterTop = index * _kRowHeight;
    final chapterBottom = chapterTop + _kRowHeight;
    final viewportTop = position.pixels;
    final viewportBottom = viewportTop + position.viewportDimension;

    double? target;
    if (chapterTop < viewportTop) {
      target = chapterTop;
    } else if (chapterBottom > viewportBottom) {
      target = chapterBottom - position.viewportDimension;
    }
    if (target == null) return; // already on screen — don't move

    _scrollController.animateTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(chapterScrollRequestProvider, (_, _) {
      _ensureSelectedVisible();
    });

    final book = ref.watch(editorProvider).audiobook;
    final selected = ref.watch(selectedChapterProvider);
    final notifier = ref.read(editorProvider.notifier);
    if (book == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        // The fixed-width cover/metadata panel can starve the chapter list
        // of all horizontal room when the window is small. Below this
        // threshold the inner ListTile/Row layouts can't fit even their
        // minimum chrome — collapse to nothing rather than throw.
        if (constraints.maxWidth < 80) {
          return const SizedBox.shrink();
        }
        return _buildList(book, selected, notifier);
      },
    );
  }

  Widget _buildList(
    Audiobook book,
    int selected,
    EditorNotifier notifier,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            // Pin every row to exactly _kRowHeight so the scroll math in
            // _ensureSelectedVisible matches reality. Without this, ListTile
            // measures itself and rows can be shorter than our estimate,
            // causing the computed offset to overshoot.
            itemExtent: _kRowHeight,
            itemCount: book.chapters.length,
            itemBuilder: (context, i) {
              final chapter = book.chapters[i];
              return _ChapterRow(
                key: ValueKey('chapters.row.$i'),
                index: i,
                chapter: chapter,
                selected: i == selected,
                onTap: () {
                  ref.read(selectedChapterProvider.notifier).state = i;
                  ref.read(playbackControllerProvider).seek(chapter.start);
                },
                onTitleChanged: (v) => notifier.renameChapter(i, v),
                onStartChanged: (d) => notifier.setChapterStart(i, d),
              );
            },
          ),
        ),
        const Divider(height: 1),
        OverflowBar(
          alignment: MainAxisAlignment.spaceEvenly,
          overflowAlignment: OverflowBarAlignment.center,
          spacing: 8,
          children: [
            TextButton(
              key: const ValueKey('chapters.add'),
              onPressed: notifier.addChapter,
              child: const Text('+ Add'),
            ),
            TextButton(
              key: const ValueKey('chapters.delete'),
              onPressed: () => notifier.deleteChapter(
                  ref.read(selectedChapterProvider)),
              child: const Text('− Delete'),
            ),
            TextButton(
              key: const ValueKey('chapters.snap'),
              onPressed: () {
                final book = ref.read(editorProvider).audiobook;
                if (book == null) return;
                final idx = ref.read(selectedChapterProvider);
                final pos =
                    ref.read(playbackControllerProvider).position;
                ref.read(editorProvider.notifier).setChapterStart(idx, pos);
              },
              child: const Text('Match Playhead'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChapterRow extends ConsumerStatefulWidget {
  const _ChapterRow({
    super.key,
    required this.index,
    required this.chapter,
    required this.selected,
    required this.onTap,
    required this.onTitleChanged,
    required this.onStartChanged,
  });

  final int index;
  final Chapter chapter;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<String> onTitleChanged;
  final SetChapterStartError? Function(Duration) onStartChanged;

  @override
  ConsumerState<_ChapterRow> createState() => _ChapterRowState();
}

class _ChapterRowState extends ConsumerState<_ChapterRow> {
  late final FocusNode _titleFocusNode;
  late final FocusNode _startFocusNode;
  late final TextEditingController _titleController;
  late final TextEditingController _startController;
  // Cached so it remains accessible in dispose() after the widget unmounts.
  late final Map<int, FocusNode> _focusNodesMap;

  @override
  void initState() {
    super.initState();
    _titleFocusNode = FocusNode()..addListener(_onTitleFocusChanged);
    _startFocusNode = FocusNode()..addListener(_onStartFocusChanged);
    _titleController = TextEditingController(text: widget.chapter.title);
    _startController =
        TextEditingController(text: formatDuration(widget.chapter.start));
    _focusNodesMap = ref.read(chapterTitleFocusNodesProvider);
    _focusNodesMap[widget.index] = _titleFocusNode;
  }

  void _onTitleFocusChanged() {
    final notifier = ref.read(editorProvider.notifier);
    if (_titleFocusNode.hasFocus) {
      notifier.beginFieldEdit();
    } else {
      notifier.endFieldEdit();
    }
  }

  void _onStartFocusChanged() {
    final notifier = ref.read(editorProvider.notifier);
    if (_startFocusNode.hasFocus) {
      notifier.beginFieldEdit();
    } else {
      notifier.endFieldEdit();
    }
  }

  @override
  void didUpdateWidget(covariant _ChapterRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _focusNodesMap.remove(oldWidget.index);
      _focusNodesMap[widget.index] = _titleFocusNode;
    }
    if (widget.chapter.title != _titleController.text) {
      _titleController.text = widget.chapter.title;
    }
    final formatted = formatDuration(widget.chapter.start);
    if (formatted != _startController.text) {
      _startController.text = formatted;
    }
  }

  @override
  void dispose() {
    _focusNodesMap.remove(widget.index);
    _titleFocusNode.dispose();
    _startFocusNode.dispose();
    _titleController.dispose();
    _startController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      selected: widget.selected,
      onTap: widget.onTap,
      leading: Container(
        key: ValueKey('chapters.number.${widget.index}'),
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.selected ? scheme.primary : Colors.transparent,
        ),
        child: Text(
          '${widget.index + 1}',
          style: TextStyle(
            color: widget.selected ? scheme.onPrimary : null,
            fontWeight: widget.selected ? FontWeight.bold : null,
          ),
        ),
      ),
      title: LayoutBuilder(
        builder: (context, constraints) {
          final titleField = TextField(
            key: ValueKey('chapters.title.${widget.index}'),
            focusNode: _titleFocusNode,
            controller: _titleController,
            onTap: widget.onTap,
            onChanged: widget.onTitleChanged,
            decoration: const InputDecoration(isDense: true),
          );

          // 110px (start field max) + 8px (gap) + 24px (title minimum to be
          // useful). Below this, drop the start field rather than overflow
          // the row by the fixed SizedBox width.
          const minWidthForStartField = 142.0;
          if (constraints.maxWidth < minWidthForStartField) {
            return titleField;
          }

          return Row(
            children: [
              Expanded(child: titleField),
              const SizedBox(width: 8),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: TextField(
                    key: ValueKey('chapters.start.${widget.index}'),
                    focusNode: _startFocusNode,
                    controller: _startController,
                    onTap: widget.onTap,
                    decoration: const InputDecoration(isDense: true),
                    onSubmitted: (v) {
                      Duration parsed;
                      try {
                        parsed = parseDuration(v);
                      } on FormatException {
                        _startController.text =
                            formatDuration(widget.chapter.start);
                        return;
                      }
                      final error = widget.onStartChanged(parsed);
                      if (error != null) {
                        _startController.text =
                            formatDuration(widget.chapter.start);
                        final messenger = ScaffoldMessenger.of(context);
                        messenger.showSnackBar(SnackBar(
                          content: Text(switch (error) {
                            SetChapterStartError.duplicate =>
                                'Chapter start times must be unique',
                            SetChapterStartError.firstNotZero =>
                                'First chapter must start at 00:00:00.000',
                          }),
                        ));
                      }
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
