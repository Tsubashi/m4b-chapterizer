import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/binary_resolver.dart';
import 'package:m4b_chapterizer/data/waveform_extractor.dart';

class _MockProcess implements Process {
  _MockProcess({
    required this.stdout,
    required Future<int> exitCode,
    this.onKill,
  }) : _exitCode = exitCode;

  @override
  final Stream<List<int>> stdout;

  final Future<int> _exitCode;
  @override
  Future<int> get exitCode => _exitCode;

  final void Function()? onKill;

  bool killed = false;

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  int get pid => 0;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    onKill?.call();
    return true;
  }
}

/// Builds a single PCM sample as little-endian int16 bytes.
List<int> _le16(int sample) {
  final clamped = sample & 0xFFFF;
  return [clamped & 0xFF, (clamped >> 8) & 0xFF];
}

List<int> _samples(List<int> values) =>
    [for (final v in values) ..._le16(v)];

void main() {
  const binaries = FixedBinaryResolver(ffmpeg: '/x/ffmpeg', ffprobe: '/x/ffprobe');

  group('WaveformExtractor.extract', () {
    test('bins synthetic PCM into the requested number of peaks', () async {
      // 32_000 samples at constant amplitude 16384. With 4 s totalDuration and
      // targetPeaks=10: samplesPerBin = 4 * 8000 / 10 = 3200. We supply exactly
      // 10 bins worth.
      final samples = List.filled(32000, 16384);
      final bytes = _samples(samples);

      final extractor = WaveformExtractor(
        binaries: binaries,
        processStarter: (exe, args) async => _MockProcess(
          stdout: Stream.value(bytes),
          exitCode: Future.value(0),
        ),
      );

      final peaks = await extractor.extract(
        path: '/x.m4b',
        totalDuration: const Duration(seconds: 4),
        targetPeaks: 10,
      );

      expect(peaks.length, 10);
      for (final p in peaks) {
        expect(p, closeTo(0.5, 1e-6));
      }
    });

    test('reports max-abs per bin', () async {
      // One bin's worth of samples (16, given samplesPerBin=16): 14 zeros, one
      // +16383 and one -16383. The peak should be ~0.5.
      final samples = <int>[
        ...List.filled(7, 0),
        16383,
        -16383,
        ...List.filled(7, 0),
      ];
      final bytes = _samples(samples);

      final extractor = WaveformExtractor(
        binaries: binaries,
        processStarter: (exe, args) async => _MockProcess(
          stdout: Stream.value(bytes),
          exitCode: Future.value(0),
        ),
      );

      final peaks = await extractor.extract(
        path: '/x.m4b',
        totalDuration: const Duration(milliseconds: 2),
        targetPeaks: 1,
      );

      expect(peaks.length, 1);
      expect(peaks.first, closeTo(16383 / 32768, 1e-6));
    });

    test('handles odd-byte chunk boundaries (carry buffer)', () async {
      // Two int16 samples = 4 bytes. Emit them as [byte1], [byte2,byte3,byte4].
      final fullBytes = _samples([16384, 16384]);
      final controller = StreamController<List<int>>();
      controller.add([fullBytes[0]]);
      controller.add([fullBytes[1], fullBytes[2], fullBytes[3]]);
      unawaited(controller.close());

      final extractor = WaveformExtractor(
        binaries: binaries,
        processStarter: (exe, args) async => _MockProcess(
          stdout: controller.stream,
          exitCode: Future.value(0),
        ),
      );

      final peaks = await extractor.extract(
        path: '/x.m4b',
        totalDuration: const Duration(microseconds: 250),
        targetPeaks: 1,
      );

      expect(peaks.length, 1);
      expect(peaks.first, closeTo(0.5, 1e-6));
    });

    test('cancellation kills the process and throws WaveformCancelled',
        () async {
      final controller = StreamController<List<int>>();
      final exitCompleter = Completer<int>();
      late _MockProcess mock;
      mock = _MockProcess(
        stdout: controller.stream,
        exitCode: exitCompleter.future,
        onKill: () {
          controller.close();
          if (!exitCompleter.isCompleted) exitCompleter.complete(143);
        },
      );

      final extractor = WaveformExtractor(
        binaries: binaries,
        processStarter: (exe, args) async => mock,
      );

      // Start extracting; emit a few bytes; then cancel.
      final future = extractor.extract(
        path: '/x.m4b',
        totalDuration: const Duration(seconds: 1),
        targetPeaks: 100,
      );
      // Let extract get to its await for loop.
      await Future<void>.delayed(Duration.zero);
      controller.add(_samples([0, 0, 0, 0]));
      await Future<void>.delayed(Duration.zero);
      extractor.cancel();

      expect(future, throwsA(isA<WaveformCancelled>()));
      // Sanity: kill was invoked.
      await Future<void>.delayed(Duration.zero);
      expect(mock.killed, isTrue);
    });

    test('throws StateError if ffmpeg exits with a non-zero code', () async {
      final extractor = WaveformExtractor(
        binaries: binaries,
        processStarter: (exe, args) async => _MockProcess(
          stdout: const Stream.empty(),
          exitCode: Future.value(1),
        ),
      );

      expect(
        extractor.extract(
          path: '/x.m4b',
          totalDuration: const Duration(seconds: 1),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('WaveformExtractor.extractRange', () {
    test('invokes ffmpeg with -ss before -i and -t after', () async {
      List<String>? capturedArgs;
      final extractor = WaveformExtractor(
        binaries: binaries,
        processStarter: (exe, args) async {
          capturedArgs = args;
          return _MockProcess(
            stdout: const Stream.empty(),
            exitCode: Future.value(0),
          );
        },
      );

      await extractor.extractRange(
        path: '/x.m4b',
        start: const Duration(seconds: 10),
        duration: const Duration(seconds: 30),
        targetPeaks: 100,
      );

      expect(capturedArgs, isNotNull);
      final args = capturedArgs!;
      // -ss must precede -i (input seek for fast container indexing).
      final ssIdx = args.indexOf('-ss');
      final iIdx = args.indexOf('-i');
      final tIdx = args.indexOf('-t');
      expect(ssIdx, greaterThanOrEqualTo(0));
      expect(iIdx, greaterThan(ssIdx));
      expect(tIdx, greaterThan(iIdx));
      // -ss value is the start in seconds.
      expect(double.parse(args[ssIdx + 1]), closeTo(10.0, 1e-9));
      // -t value is the duration in seconds.
      expect(double.parse(args[tIdx + 1]), closeTo(30.0, 1e-9));
      expect(args[iIdx + 1], '/x.m4b');
    });

    test('bins windowed PCM into the requested number of peaks', () async {
      // 240,000 samples at constant amplitude 16384. With 30 s duration and
      // targetPeaks=10: samplesPerBin = 30 * 8000 / 10 = 24000.
      final samples = List.filled(240000, 16384);
      final bytes = _samples(samples);

      final extractor = WaveformExtractor(
        binaries: binaries,
        processStarter: (exe, args) async => _MockProcess(
          stdout: Stream.value(bytes),
          exitCode: Future.value(0),
        ),
      );

      final peaks = await extractor.extractRange(
        path: '/x.m4b',
        start: const Duration(seconds: 5),
        duration: const Duration(seconds: 30),
        targetPeaks: 10,
      );

      expect(peaks.length, 10);
      for (final p in peaks) {
        expect(p, closeTo(0.5, 1e-6));
      }
    });

    test('cancellation kills the process and throws WaveformCancelled',
        () async {
      final stdoutController = StreamController<List<int>>();
      addTearDown(stdoutController.close);
      final exitCompleter = Completer<int>();
      final extractor = WaveformExtractor(
        binaries: binaries,
        processStarter: (exe, args) async => _MockProcess(
          stdout: stdoutController.stream,
          exitCode: exitCompleter.future,
          onKill: () {
            if (!exitCompleter.isCompleted) exitCompleter.complete(137);
          },
        ),
      );

      final future = extractor.extractRange(
        path: '/x.m4b',
        start: Duration.zero,
        duration: const Duration(seconds: 5),
        targetPeaks: 10,
      );
      final expectation =
          expectLater(future, throwsA(isA<WaveformCancelled>()));
      // Pump a small amount of data, then cancel.
      stdoutController.add(_samples(List.filled(100, 16384)));
      await Future<void>.delayed(Duration.zero);
      extractor.cancel();
      await stdoutController.close();
      await expectation;
    });
  });
}
