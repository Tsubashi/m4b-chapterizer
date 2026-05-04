import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/process_runner.dart';

void main() {
  group('SystemProcessRunner', () {
    test('runs an executable and captures stdout/stderr/exitCode', () async {
      const runner = SystemProcessRunner();
      final result = await runner.run(
        executable: Platform.isWindows ? 'cmd' : 'sh',
        arguments: Platform.isWindows
            ? const ['/c', 'echo hello']
            : const ['-c', 'echo hello'],
      );
      expect(result.exitCode, 0);
      expect(result.stdout.trim(), 'hello');
    });

    test('returns nonzero exit code for failing commands', () async {
      const runner = SystemProcessRunner();
      final result = await runner.run(
        executable: Platform.isWindows ? 'cmd' : 'sh',
        arguments: Platform.isWindows
            ? const ['/c', 'exit 7']
            : const ['-c', 'exit 7'],
      );
      expect(result.exitCode, 7);
    });
  });
}
