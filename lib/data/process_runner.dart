import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class ProcessOutput {
  const ProcessOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.stdoutBytes,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final Uint8List stdoutBytes;
}

abstract class ProcessRunner {
  Future<ProcessOutput> run({
    required String executable,
    required List<String> arguments,
  });
}

class SystemProcessRunner implements ProcessRunner {
  const SystemProcessRunner();

  @override
  Future<ProcessOutput> run({
    required String executable,
    required List<String> arguments,
  }) async {
    final result = await Process.run(
      executable,
      arguments,
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    final stdoutBytes = result.stdout as List<int>;
    final stderrBytes = result.stderr as List<int>;
    return ProcessOutput(
      exitCode: result.exitCode,
      stdout: utf8.decode(stdoutBytes, allowMalformed: true),
      stderr: utf8.decode(stderrBytes, allowMalformed: true),
      stdoutBytes: Uint8List.fromList(stdoutBytes),
    );
  }
}
