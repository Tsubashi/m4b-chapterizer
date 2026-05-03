import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/bundled_binary_resolver.dart';
import 'data/ffmpeg_bookbinder.dart';
import 'data/process_runner.dart';
import 'presentation/app.dart';
import 'presentation/drag_drop/drag_drop_channel.dart';
import 'presentation/providers/editor_state.dart';

void main() {
  final resolver = BundledBinaryResolver();
  runApp(
    ProviderScope(
      overrides: [
        binaryResolverProvider.overrideWithValue(resolver),
        bookbinderProvider.overrideWithValue(
          FfmpegBookbinder(
            runner: const SystemProcessRunner(),
            binaries: resolver,
          ),
        ),
        dragDropChannelProvider.overrideWithValue(
          MethodChannelDragDropChannel(),
        ),
      ],
      child: const M4bChapterizerApp(),
    ),
  );
}
