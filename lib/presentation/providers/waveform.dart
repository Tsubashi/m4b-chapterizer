import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/waveform_extractor.dart';
import 'editor_state.dart';

/// Computes amplitude peaks for the audio at [path] in the background.
/// Errors and "still loading" both render as an empty peak list at the UI.
final waveformPeaksProvider =
    FutureProvider.family<List<double>, String>((ref, path) async {
  final book = ref.watch(editorProvider).audiobook;
  if (book == null) return <double>[];

  final extractor = WaveformExtractor(
    binaries: ref.read(binaryResolverProvider),
    processStarter: Process.start,
  );
  ref.onDispose(extractor.cancel);

  return extractor.extract(path: path, totalDuration: book.totalDuration);
});
