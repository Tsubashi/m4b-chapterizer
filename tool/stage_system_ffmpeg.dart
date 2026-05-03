// Copies system-installed `ffmpeg` and `ffprobe` (from PATH) into
// `assets/bin/<platform>/` so `bundledTestResolver()` finds them. Used by
// CI in place of `fetch_ffmpeg.dart`'s pinned bundled binaries — see the
// design at docs/superpowers/specs/2026-05-02-github-actions-ci-design.md
// for the rationale (we don't have SHAs pinned for windows/linux/macos-x64
// yet).
//
// Run from the repo root:
//   dart run tool/stage_system_ffmpeg.dart
//
// On a developer machine this OVERWRITES the pinned bundled binaries staged
// by `fetch_ffmpeg.dart`. To restore them, re-run:
//   dart run tool/fetch_ffmpeg.dart

import 'dart:io';

String _platformKey() {
  if (Platform.isMacOS) {
    return Platform.version.contains('arm64') ? 'macos-arm64' : 'macos-x64';
  }
  if (Platform.isWindows) return 'windows-x64';
  if (Platform.isLinux) return 'linux-x64';
  throw UnsupportedError('Unsupported: ${Platform.operatingSystem}');
}

Future<String> _which(String name) async {
  final cmd = Platform.isWindows ? 'where' : 'which';
  final result = await Process.run(cmd, [name]);
  if (result.exitCode != 0) {
    throw StateError(
      '$name not found on PATH. Install it (brew/apt/choco) and retry.',
    );
  }
  // `where` on Windows can return multiple lines; take the first.
  return (result.stdout as String).split('\n').first.trim();
}

Future<void> _stage(String name, String platformKey) async {
  final src = await _which(name);
  final exeSuffix = Platform.isWindows ? '.exe' : '';
  final destDir = Directory('assets/bin/$platformKey');
  if (!destDir.existsSync()) destDir.createSync(recursive: true);
  final destPath = '${destDir.path}/$name$exeSuffix';
  await File(src).copy(destPath);
  if (!Platform.isWindows) {
    await Process.run('chmod', ['+x', destPath]);
  }
  stdout.writeln('  $src -> $destPath');
}

Future<void> main() async {
  final key = _platformKey();
  stdout.writeln('Staging system ffmpeg/ffprobe for $key...');
  await _stage('ffmpeg', key);
  await _stage('ffprobe', key);
  stdout.writeln('Done.');
}
