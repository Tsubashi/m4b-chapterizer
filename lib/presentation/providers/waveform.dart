import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/waveform_extractor.dart';
import 'editor_state.dart';

/// Provided here so tests can override with a spy. Production wires the
/// real ffmpeg-driven extractor.
final waveformExtractorProvider = Provider<WaveformExtractor>((ref) {
  // coverage:ignore-start
  // Production wiring for the real ffmpeg-driven extractor. Tests
  // override this provider with a spy; the real wiring is exercised by
  // the platform integration tests under `test/data/`.
  return WaveformExtractor(
    binaries: ref.read(binaryResolverProvider),
    processStarter: Process.start,
  );
  // coverage:ignore-end
});

/// Computes amplitude peaks for the audio at [path] in the background.
/// Errors and "still loading" both render as an empty peak list at the UI.
final waveformPeaksProvider =
    FutureProvider.family<List<double>, String>((ref, path) async {
  final book = ref.read(editorProvider).audiobook;
  if (book == null) return <double>[];

  final extractor = ref.read(waveformExtractorProvider);
  ref.onDispose(extractor.cancel);

  return extractor.extract(path: path, totalDuration: book.totalDuration);
});
