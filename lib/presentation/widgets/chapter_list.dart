import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/models/chapter.dart';
import '../providers/editor_state.dart' show SetChapterStartError, editorProvider;
import '../providers/playback.dart';
import '../util/duration_format.dart';

final selectedChapterProvider = StateProvider<int>((ref) => 0);

final chapterTitleFocusNodesProvider =
    Provider<Map<int, FocusNode>>((ref) => <int, FocusNode>{});

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

  void _onSelectionChanged(int? prev, int next) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (next * _kRowHeight)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(selectedChapterProvider, _onSelectionChanged);

    final book = ref.watch(editorProvider).audiobook;
    final selected = ref.watch(selectedChapterProvider);
    final notifier = ref.read(editorProvider.notifier);
    if (book == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
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
      title: Row(
        children: [
          Expanded(
            child: TextField(
              key: ValueKey('chapters.title.${widget.index}'),
              focusNode: _titleFocusNode,
              controller: _titleController,
              onTap: widget.onTap,
              onChanged: widget.onTitleChanged,
              decoration: const InputDecoration(isDense: true),
            ),
          ),
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
                    _startController.text = formatDuration(widget.chapter.start);
                    return;
                  }
                  final error = widget.onStartChanged(parsed);
                  if (error != null) {
                    _startController.text = formatDuration(widget.chapter.start);
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
      ),
    );
  }
}
