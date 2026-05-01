import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/cover.dart';
import '../providers/editor_state.dart';

class CoverPanel extends ConsumerWidget {
  const CoverPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = ref.watch(editorProvider).audiobook?.cover;
    final notifier = ref.read(editorProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 160,
          height: 160,
          child: cover == null
              ? Container(
                  key: const ValueKey('cover.placeholder'),
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.book, size: 64),
                )
              : Image.memory(cover.bytes, key: const ValueKey('cover.image')),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              key: const ValueKey('cover.replace'),
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: const ['png', 'jpg', 'jpeg'],
                );
                final picked = result?.files.single.path;
                if (picked == null) return;
                final bytes = await File(picked).readAsBytes();
                final mime = picked.toLowerCase().endsWith('.png')
                    ? 'image/png'
                    : 'image/jpeg';
                notifier.replaceCover(Cover(bytes: bytes, mimeType: mime));
              },
              child: const Text('Replace…'),
            ),
            TextButton(
              key: const ValueKey('cover.remove'),
              onPressed: cover == null ? null : notifier.clearCover,
              child: const Text('Remove'),
            ),
          ],
        ),
      ],
    );
  }
}
