import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../keyboard/editor_actions.dart';
import '../providers/editor_state.dart';
import '../providers/playback.dart';
import '../providers/waveform.dart';
import '../util/duration_format.dart';
import 'chapter_scrubber.dart';

class PlaybackControls extends ConsumerWidget {
  const PlaybackControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackControllerProvider);
    final state = ref.watch(editorProvider);
    final book = state.audiobook;

    final peaksAsync = state.path == null
        ? const AsyncValue<List<double>>.data(<double>[])
        : ref.watch(waveformPeaksProvider(state.path!));
    final peaks = peaksAsync.maybeWhen(
      data: (p) => p,
      orElse: () => const <double>[],
    );

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
                  peaks: peaks,
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    key: const ValueKey('playback.save'),
                    onPressed: book == null
                        ? null
                        : () => EditorActions(context, ref).save(),
                    child: const Text('Save'),
                  ),
                  MenuAnchor(
                    builder: (context, menuController, _) => IconButton(
                      key: const ValueKey('playback.save.menu'),
                      icon: const Icon(Icons.arrow_drop_down),
                      onPressed: book == null
                          ? null
                          : () => menuController.isOpen
                              ? menuController.close()
                              : menuController.open(),
                    ),
                    menuChildren: [
                      MenuItemButton(
                        key: const ValueKey('playback.saveAs'),
                        onPressed: () =>
                            EditorActions(context, ref).saveAs(),
                        child: const Text('Save As…'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
