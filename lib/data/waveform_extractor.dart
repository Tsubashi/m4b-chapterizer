import 'dart:async';
import 'dart:io';

import 'binary_resolver.dart';

class WaveformCancelled implements Exception {
  const WaveformCancelled();

  @override
  String toString() => 'WaveformCancelled';
}

class WaveformExtractor {
  WaveformExtractor({required this.binaries, required this.processStarter});

  final BinaryResolver binaries;
  final Future<Process> Function(String exe, List<String> args) processStarter;

  Process? _activeProcess;
  bool _cancelled = false;

  Future<List<double>> extract({
    required String path,
    required Duration totalDuration,
    int targetPeaks = 4096,
  }) async {
    final totalSamples =
        (totalDuration.inMicroseconds * 8000) ~/ Duration.microsecondsPerSecond;
    var samplesPerBin = totalSamples ~/ targetPeaks;
    if (samplesPerBin < 1) samplesPerBin = 1;

    final process = await processStarter(binaries.ffmpeg, [
      '-loglevel', 'error',
      '-i', path,
      '-map', '0:a',
      '-f', 's16le',
      '-ac', '1',
      '-ar', '8000',
      '-',
    ]);
    _activeProcess = process;

    final peaks = <double>[];
    int currentBinSampleCount = 0;
    int currentBinMax = 0;
    int? carryByte;

    try {
      await for (final chunk in process.stdout) {
        if (_cancelled) throw const WaveformCancelled();
        final List<int> bytes;
        if (carryByte != null) {
          bytes = [carryByte, ...chunk];
          carryByte = null;
        } else {
          bytes = chunk;
        }
        final usableLength = bytes.length & ~1;
        if (bytes.length > usableLength) {
          carryByte = bytes[usableLength];
        }
        for (var i = 0; i < usableLength; i += 2) {
          var sample = bytes[i] | (bytes[i + 1] << 8);
          if (sample >= 0x8000) sample -= 0x10000;
          final absSample = sample < 0 ? -sample : sample;
          if (absSample > currentBinMax) currentBinMax = absSample;
          currentBinSampleCount++;
          if (currentBinSampleCount >= samplesPerBin) {
            peaks.add(currentBinMax / 32768);
            currentBinSampleCount = 0;
            currentBinMax = 0;
          }
        }
      }

      if (_cancelled) throw const WaveformCancelled();

      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        throw StateError('ffmpeg exited with code $exitCode');
      }

      if (currentBinSampleCount > 0) {
        peaks.add(currentBinMax / 32768);
      }
      return peaks;
    } catch (e) {
      if (_cancelled) throw const WaveformCancelled();
      rethrow;
    } finally {
      _activeProcess = null;
    }
  }

  void cancel() {
    _cancelled = true;
    _activeProcess?.kill();
  }
}
