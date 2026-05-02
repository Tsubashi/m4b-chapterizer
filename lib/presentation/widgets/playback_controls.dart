import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor_state.dart';
import '../providers/playback.dart';
import '../util/duration_format.dart';
import 'chapter_list.dart';
import 'chapter_scrubber.dart';

class PlaybackControls extends ConsumerWidget {
  const PlaybackControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackControllerProvider);
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final selectedIndex = ref.watch(selectedChapterProvider);
    final book = state.audiobook;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (book != null)
            StreamBuilder<Duration>(
              stream: controller.positionStream,
              initialData: controller.position,
              builder: (context, snapshot) {
                return ChapterScrubber(
                  position: snapshot.data ?? controller.position,
                  totalDuration: book.totalDuration,
                  chapterStarts: [for (final c in book.chapters) c.start],
                  onSeek: controller.seek,
                );
              },
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              StreamBuilder<bool>(
                stream: controller.playingStream,
                initialData: controller.playing,
                builder: (context, snapshot) {
                  final playing = snapshot.data ?? controller.playing;
                  return IconButton(
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    onPressed: () =>
                        playing ? controller.pause() : controller.play(),
                  );
                },
              ),
              const SizedBox(width: 12),
              StreamBuilder<Duration>(
                stream: controller.positionStream,
                builder: (context, snapshot) => Text(
                  formatDuration(snapshot.data ?? controller.position),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                key: const ValueKey('playback.snap'),
                onPressed: () => notifier.setChapterStart(
                    selectedIndex, controller.position),
                child: const Text('Set start to playhead'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
