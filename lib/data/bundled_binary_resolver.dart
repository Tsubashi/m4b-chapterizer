import 'dart:io';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:path/path.dart' as p;

import 'binary_resolver.dart';

typedef AssetLoader = Future<ByteData> Function(String key);

/// Copies bundled ffmpeg/ffprobe binaries out of the asset bundle into the
/// app's support directory on first use, then returns those paths.
class BundledBinaryResolver implements BinaryResolver {
  BundledBinaryResolver({
    AssetLoader? assetLoader,
    String? supportDirOverride,
  })  : _assetLoader = assetLoader ?? rootBundle.load,
        _supportDirOverride = supportDirOverride;

  final AssetLoader _assetLoader;
  final String? _supportDirOverride;
  String? _cachedFfmpeg;
  String? _cachedFfprobe;

  static String _platformKey() {
    if (Platform.isMacOS) {
      return Platform.version.contains('arm64') ? 'macos-arm64' : 'macos-x64';
    }
    if (Platform.isWindows) return 'windows-x64';
    if (Platform.isLinux) return 'linux-x64';
    throw UnsupportedError('Unsupported: ${Platform.operatingSystem}');
  }

  Future<String> _supportDir() async {
    final override = _supportDirOverride;
    if (override != null) return override;
    // Default: ~/Library/Application Support/m4b_chapterizer or platform equivalent.
    // Dev convenience — production code would use path_provider, but to keep
    // this MVP free of an extra package we synthesize a reasonable default.
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    final base = Platform.isMacOS
        ? p.join(home, 'Library', 'Application Support', 'm4b_chapterizer')
        : Platform.isWindows
            ? p.join(home, 'AppData', 'Roaming', 'm4b_chapterizer')
            : p.join(home, '.local', 'share', 'm4b_chapterizer');
    final dir = Directory(base);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  Future<String> _extract(String name) async {
    final platformKey = _platformKey();
    final exeSuffix = Platform.isWindows ? '.exe' : '';
    final assetPath = 'assets/bin/$platformKey/$name$exeSuffix';
    final destPath = p.join(await _supportDir(), '$name$exeSuffix');
    final destFile = File(destPath);
    if (!destFile.existsSync()) {
      final data = await _assetLoader(assetPath);
      await destFile.writeAsBytes(data.buffer.asUint8List());
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', destPath]);
      }
    }
    return destPath;
  }

  Future<String> resolveFfmpeg() async =>
      _cachedFfmpeg ??= await _extract('ffmpeg');
  Future<String> resolveFfprobe() async =>
      _cachedFfprobe ??= await _extract('ffprobe');

  @override
  String get ffmpeg {
    if (_cachedFfmpeg == null) {
      throw StateError('Call resolveFfmpeg() before reading .ffmpeg');
    }
    return _cachedFfmpeg!;
  }

  @override
  String get ffprobe {
    if (_cachedFfprobe == null) {
      throw StateError('Call resolveFfprobe() before reading .ffprobe');
    }
    return _cachedFfprobe!;
  }
}
