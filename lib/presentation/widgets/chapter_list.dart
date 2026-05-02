import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/models/chapter.dart';
import '../providers/editor_state.dart' show SetChapterStartError, editorProvider;
import '../util/duration_format.dart';

final selectedChapterProvider = StateProvider<int>((ref) => 0);

class ChapterList extends ConsumerWidget {
  const ChapterList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(editorProvider).audiobook;
    final selected = ref.watch(selectedChapterProvider);
    final notifier = ref.read(editorProvider.notifier);
    if (book == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: book.chapters.length,
            itemBuilder: (context, i) {
              final chapter = book.chapters[i];
              return _ChapterRow(
                key: ValueKey('chapters.row.$i'),
                index: i,
                chapter: chapter,
                selected: i == selected,
                onTap: () =>
                    ref.read(selectedChapterProvider.notifier).state = i,
                onTitleChanged: (v) => notifier.renameChapter(i, v),
                onStartChanged: (d) => notifier.setChapterStart(i, d),
              );
            },
          ),
        ),
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

class _ChapterRow extends StatefulWidget {
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
  State<_ChapterRow> createState() => _ChapterRowState();
}

class _ChapterRowState extends State<_ChapterRow> {
  late final TextEditingController _titleController;
  late final TextEditingController _startController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.chapter.title);
    _startController =
        TextEditingController(text: formatDuration(widget.chapter.start));
  }

  @override
  void didUpdateWidget(covariant _ChapterRow oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    _titleController.dispose();
    _startController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: widget.selected,
      onTap: widget.onTap,
      leading: Text('${widget.index + 1}'),
      title: Row(
        children: [
          Expanded(
            child: TextField(
              key: ValueKey('chapters.title.${widget.index}'),
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
                controller: _startController,
                onTap: widget.onTap,
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
