import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/bundled_binary_resolver.dart';
import 'data/ffmpeg_bookbinder.dart';
import 'data/process_runner.dart';
import 'presentation/app.dart';
import 'presentation/providers/editor_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final resolver = BundledBinaryResolver();
  await resolver.resolveFfmpeg();
  await resolver.resolveFfprobe();
  runApp(
    ProviderScope(
      overrides: [
        bookbinderProvider.overrideWithValue(
          FfmpegBookbinder(
            runner: const SystemProcessRunner(),
            binaries: resolver,
          ),
        ),
      ],
      child: const M4bChapterizerApp(),
    ),
  );
}
