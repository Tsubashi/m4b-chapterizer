import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/binary_resolver.dart';
import 'data/ffmpeg_bookbinder.dart';
import 'data/process_runner.dart';
import 'presentation/app.dart';
import 'presentation/providers/editor_state.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [
        bookbinderProvider.overrideWithValue(
          FfmpegBookbinder(
            runner: const SystemProcessRunner(),
            // Phase 8 swaps this to BundledBinaryResolver.
            binaries: const SystemBinaryResolver(),
          ),
        ),
      ],
      child: const M4bChapterizerApp(),
    ),
  );
}
