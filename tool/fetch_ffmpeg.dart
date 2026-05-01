// Downloads pinned ffmpeg/ffprobe binaries into assets/bin/<platform>/.
// Run once per development machine and once per CI build:
//   dart run tool/fetch_ffmpeg.dart
//
// Pinned to ffmpeg 7.1.

import 'dart:io';

import 'package:crypto/crypto.dart';

class _Source {
  const _Source({required this.url, required this.sha256, required this.member});
  final String url;
  final String sha256;

  /// Path within the archive to extract. For raw zips of a single binary,
  /// pass the binary's filename inside the zip.
  final String member;
}

const _sources = {
  'macos-arm64': [
    _Source(
      url: 'https://www.osxexperts.net/ffmpeg711arm.zip',
      sha256:
          '59e39a5cec2e5d2307ed079c53227a9181e64b87454ed4de998349e044bfdc70',
      member: 'ffmpeg',
    ),
    _Source(
      url: 'https://www.osxexperts.net/ffprobe711arm.zip',
      sha256:
          'e695da37c08c8fbc218ebc161ee20d5606b50f3c7e8d696cbcf01bd40fe20d7e',
      member: 'ffprobe',
    ),
  ],
  // TODO: run on this platform to compute SHA.
  'macos-x64': [
    _Source(
      url: 'https://www.osxexperts.net/ffmpeg711intel.zip',
      sha256: 'PASTE_SHA256_HERE',
      member: 'ffmpeg',
    ),
    _Source(
      url: 'https://www.osxexperts.net/ffprobe711intel.zip',
      sha256: 'PASTE_SHA256_HERE',
      member: 'ffprobe',
    ),
  ],
  // TODO: run on this platform to compute SHA. Note: the GyanD windows build
  // ships a single zip with both ffmpeg.exe and ffprobe.exe under bin/. The
  // current extraction logic below assumes a flat zip with the binary at the
  // root; the windows source needs an extension-aware extraction branch when
  // it is wired up. See _extractBinary's `if (archiveExtension == 'zip')`.
  'windows-x64': [
    _Source(
      url:
          'https://github.com/GyanD/codexffmpeg/releases/download/7.1/ffmpeg-7.1-essentials_build.zip',
      sha256: 'PASTE_SHA256_HERE',
      member: 'ffmpeg.exe',
    ),
    _Source(
      url:
          'https://github.com/GyanD/codexffmpeg/releases/download/7.1/ffmpeg-7.1-essentials_build.zip',
      sha256: 'PASTE_SHA256_HERE',
      member: 'ffprobe.exe',
    ),
  ],
  // TODO: run on this platform to compute SHA. Note: the johnvansickle build
  // ships ffmpeg and ffprobe inside a directory named `ffmpeg-7.1-amd64-static/`.
  // The tar.xz extraction branch below extracts the whole archive; the linux
  // hookup will need to move the two binaries out of that subdirectory.
  'linux-x64': [
    _Source(
      url:
          'https://johnvansickle.com/ffmpeg/releases/ffmpeg-7.1-amd64-static.tar.xz',
      sha256: 'PASTE_SHA256_HERE',
      member: 'ffmpeg',
    ),
    _Source(
      url:
          'https://johnvansickle.com/ffmpeg/releases/ffmpeg-7.1-amd64-static.tar.xz',
      sha256: 'PASTE_SHA256_HERE',
      member: 'ffprobe',
    ),
  ],
};

String _platformKey() {
  if (Platform.isMacOS) {
    return Platform.version.contains('arm64') ? 'macos-arm64' : 'macos-x64';
  }
  if (Platform.isWindows) return 'windows-x64';
  if (Platform.isLinux) return 'linux-x64';
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

Future<List<int>> _download(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode == 301 || res.statusCode == 302) {
      final next = res.headers.value(HttpHeaders.locationHeader);
      if (next == null) {
        throw StateError('Redirect without Location header for $url');
      }
      // Drain & follow.
      await res.drain<void>();
      return _download(next);
    }
    if (res.statusCode != 200) {
      throw StateError('Download failed: $url -> ${res.statusCode}');
    }
    final bytes = <int>[];
    await for (final chunk in res) {
      bytes.addAll(chunk);
    }
    return bytes;
  } finally {
    client.close();
  }
}

Future<void> _extractBinary({
  required List<int> archiveBytes,
  required String archiveExtension,
  required String memberName,
  required String destPath,
}) async {
  // Use the system `unzip` / `tar` to avoid dragging in archive packages.
  final tempArchive = await File(
    '${Directory.systemTemp.path}/m4b-fetch-${DateTime.now().millisecondsSinceEpoch}.$archiveExtension',
  ).create();
  await tempArchive.writeAsBytes(archiveBytes);
  final destDir = Directory(destPath).parent;
  await destDir.create(recursive: true);

  if (archiveExtension == 'zip') {
    final result = await Process.run(
        'unzip', ['-jo', tempArchive.path, memberName, '-d', destDir.path]);
    if (result.exitCode != 0) {
      throw StateError('unzip failed: ${result.stderr}');
    }
    final extracted = File('${destDir.path}/$memberName');
    if (extracted.path != destPath) {
      await extracted.rename(destPath);
    }
  } else if (archiveExtension == 'tar.xz') {
    final result = await Process.run(
        'tar', ['-xJf', tempArchive.path, '-C', destDir.path]);
    if (result.exitCode != 0) {
      throw StateError('tar failed: ${result.stderr}');
    }
    // Caller should know the in-archive path; for static builds this is
    // typically a directory named after the build, with ffmpeg at the root.
    // Adjust per-source as needed.
  }

  await tempArchive.delete();

  if (!Platform.isWindows) {
    await Process.run('chmod', ['+x', destPath]);
  }
}

Future<void> _verifySha256(List<int> bytes, String expected) async {
  final actual = sha256.convert(bytes).toString();
  if (actual != expected) {
    throw StateError(
      'SHA-256 mismatch:\n  expected $expected\n  actual   $actual',
    );
  }
}

Future<void> main() async {
  final key = _platformKey();
  final sources = _sources[key];
  if (sources == null) {
    throw UnsupportedError('No sources configured for $key');
  }
  for (final src in sources) {
    if (src.sha256 == 'PASTE_SHA256_HERE') {
      throw StateError(
        'No SHA-256 pinned for ${src.url} on $key. Run this script on '
        '$key once, compute `shasum -a 256 <archive>`, and paste the value '
        'into tool/fetch_ffmpeg.dart.',
      );
    }
    stdout.writeln('Downloading ${src.url} ...');
    final bytes = await _download(src.url);
    await _verifySha256(bytes, src.sha256);

    final ext = src.url.endsWith('.tar.xz') ? 'tar.xz' : 'zip';
    final destPath = 'assets/bin/$key/${src.member}'
        '${Platform.isWindows ? '.exe' : ''}';
    await _extractBinary(
      archiveBytes: bytes,
      archiveExtension: ext,
      memberName: src.member +
          (Platform.isWindows && ext == 'zip' ? '.exe' : ''),
      destPath: destPath,
    );
    stdout.writeln('  -> $destPath');
  }
  stdout.writeln(
      'Done. Make sure assets/bin/$key/ is included in the Flutter asset bundle.');
}
