import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../keyboard/editor_actions.dart';
import '../keyboard/shortcuts.dart';
import '../providers/editor_state.dart';
import '../providers/playback.dart';
import '../widgets/chapter_list.dart';
import '../widgets/cover_panel.dart';
import '../widgets/metadata_form.dart';
import '../widgets/playback_controls.dart';

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final playback = ref.read(playbackControllerProvider);
    final filename = state.path?.split(Platform.pathSeparator).last ?? '';

    // Wire playback source whenever the path changes.
    ref.listen<String?>(editorProvider.select((s) => s.path), (previous, next) {
      if (next != null && next != previous) {
        playback.setSource(next);
      }
    });

    return EditorShortcuts(
      child: Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(filename),
            const SizedBox(width: 8),
            if (state.isDirty) const Text('•'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => EditorActions(context, ref).open(),
            child: const Text('Open…'),
          ),
          TextButton(
            onPressed: state.audiobook == null
                ? null
                : () => EditorActions(context, ref).save(),
            child: const Text('Save'),
          ),
          TextButton(
            onPressed: state.audiobook == null
                ? null
                : () => EditorActions(context, ref).saveAs(),
            child: const Text('Save As…'),
          ),
        ],
      ),
      body: state.audiobook == null
          ? const Center(child: Text('Open an .m4b file to begin'))
          : const Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 280,
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              CoverPanel(),
                              MetadataForm(),
                            ],
                          ),
                        ),
                      ),
                      VerticalDivider(width: 1),
                      Expanded(child: ChapterList()),
                    ],
                  ),
                ),
                Divider(height: 1),
                PlaybackControls(),
              ],
            ),
    ),
    );
  }
}
