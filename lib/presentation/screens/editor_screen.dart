import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../keyboard/shortcuts.dart';
import '../providers/editor_state.dart';
import '../providers/playback.dart';
import '../util/file_picker_errors.dart';
import '../widgets/chapter_list.dart';
import '../widgets/cover_panel.dart';
import '../widgets/metadata_form.dart';
import '../widgets/playback_controls.dart';

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  Future<bool> _confirmDiscard(BuildContext context) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text(
            'You have unsaved changes. Continue and lose them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
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
            onPressed: () async {
              if (state.isDirty && !await _confirmDiscard(context)) return;
              if (!context.mounted) return;
              final result = await guardFilePicker(
                context,
                () => FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: const ['m4b'],
                ),
              );
              final path = result?.files.single.path;
              if (path == null) return;
              await notifier.open(path);
            },
            child: const Text('Open…'),
          ),
          TextButton(
            onPressed:
                state.audiobook == null ? null : () => notifier.save(),
            child: const Text('Save'),
          ),
          TextButton(
            onPressed: state.audiobook == null
                ? null
                : () async {
                    final result = await guardFilePicker(
                      context,
                      () => FilePicker.saveFile(
                        type: FileType.custom,
                        allowedExtensions: const ['m4b'],
                        fileName: filename,
                      ),
                    );
                    if (result == null) return;
                    await notifier.saveAs(result);
                  },
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
