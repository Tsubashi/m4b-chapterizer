import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor_state.dart';
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
              return ListTile(
                key: ValueKey('chapters.row.$i'),
                selected: i == selected,
                onTap: () =>
                    ref.read(selectedChapterProvider.notifier).state = i,
                leading: Text('${i + 1}'),
                title: TextField(
                  key: ValueKey('chapters.title.$i'),
                  controller: TextEditingController(text: chapter.title),
                  onTap: () =>
                      ref.read(selectedChapterProvider.notifier).state = i,
                  onSubmitted: (v) => notifier.renameChapter(i, v),
                  onChanged: (v) => notifier.renameChapter(i, v),
                  decoration: const InputDecoration(isDense: true),
                ),
                trailing: SizedBox(
                  width: 110,
                  child: TextField(
                    key: ValueKey('chapters.start.$i'),
                    controller:
                        TextEditingController(text: formatDuration(chapter.start)),
                    onTap: () =>
                        ref.read(selectedChapterProvider.notifier).state = i,
                    onSubmitted: (v) {
                      try {
                        notifier.setChapterStart(i, parseDuration(v));
                      } on FormatException {
                        // leave field as-is
                      }
                    },
                  ),
                ),
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
