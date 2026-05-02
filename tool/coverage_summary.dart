// Reports filtered coverage from coverage/lcov.info, honoring
// `// coverage:ignore-file`, `// coverage:ignore-start` … `// coverage:ignore-end`,
// and `// coverage:ignore-line` markers in the source. Flutter's coverage
// pipeline respects these natively, but parsing them ourselves means the
// summary stays correct even if a future toolchain change drops the
// behavior, and lets us print a per-directory breakdown.
//
// Run with: `dart run tool/coverage_summary.dart`
//
// Exit codes:
//   0 — printed summary
//   1 — `coverage/lcov.info` missing (run `flutter test --coverage` first)

import 'dart:io';

const _lcovPath = 'coverage/lcov.info';

void main() {
  final lcov = File(_lcovPath);
  if (!lcov.existsSync()) {
    stderr.writeln('No $_lcovPath. Run `flutter test --coverage` first.');
    exit(1);
  }

  final files = _parseLcov(lcov.readAsLinesSync());
  final filtered = <String, _FileStats>{};
  for (final entry in files.entries) {
    final source = File(entry.key);
    final excluded = source.existsSync()
        ? _excludedLines(source.readAsLinesSync())
        : const _Excluded(wholeFile: false, lines: <int>{});
    if (excluded.wholeFile) continue;
    final stats = entry.value.exclude(excluded.lines);
    if (stats.total == 0) continue;
    filtered[entry.key] = stats;
  }

  final byGroup = <String, _FileStats>{};
  for (final entry in filtered.entries) {
    final group = _groupOf(entry.key);
    byGroup.update(
      group,
      (s) => s + entry.value,
      ifAbsent: () => entry.value,
    );
  }

  stdout.writeln('Coverage summary (filtered, ignoring marker-suppressed code)');
  stdout.writeln('-' * 60);
  stdout.writeln('  Group                                          Hit / Total   %');
  stdout.writeln('-' * 60);

  final groups = byGroup.keys.toList()..sort();
  for (final g in groups) {
    final s = byGroup[g]!;
    stdout.writeln(_row(g, s));
  }
  stdout.writeln('-' * 60);
  final overall = byGroup.values
      .fold<_FileStats>(const _FileStats(0, 0), (a, b) => a + b);
  stdout.writeln(_row('TOTAL', overall));
  stdout.writeln('');
  stdout.writeln('Files measured: ${filtered.length}');
}

String _row(String label, _FileStats s) {
  final pct = s.total == 0 ? 0.0 : (s.hit / s.total) * 100;
  return '  ${label.padRight(46)} ${s.hit.toString().padLeft(5)} /'
      ' ${s.total.toString().padLeft(5)}  ${pct.toStringAsFixed(2).padLeft(6)}%';
}

String _groupOf(String path) {
  final parts = path.split('/');
  // Group files under `lib/<top>/` together; report `lib/main.dart` as `lib`.
  if (parts.length >= 3 && parts[0] == 'lib') {
    return 'lib/${parts[1]}/';
  }
  return 'lib/';
}

class _FileStats {
  const _FileStats(this.hit, this.total);
  final int hit;
  final int total;

  _FileStats operator +(_FileStats other) =>
      _FileStats(hit + other.hit, total + other.total);
}

class _FileRecords {
  _FileRecords();
  // line number -> hit count
  final Map<int, int> da = <int, int>{};

  _FileStats exclude(Set<int> excluded) {
    var hit = 0;
    var total = 0;
    for (final entry in da.entries) {
      if (excluded.contains(entry.key)) continue;
      total += 1;
      if (entry.value > 0) hit += 1;
    }
    return _FileStats(hit, total);
  }
}

Map<String, _FileRecords> _parseLcov(List<String> lines) {
  final out = <String, _FileRecords>{};
  String? current;
  _FileRecords? records;
  for (final raw in lines) {
    final line = raw.trim();
    if (line.startsWith('SF:')) {
      current = line.substring(3);
      records = _FileRecords();
      out[current] = records;
    } else if (line.startsWith('DA:') && records != null) {
      // DA:<line>,<count>[,<digest>]
      final parts = line.substring(3).split(',');
      final ln = int.tryParse(parts[0]);
      final ct = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (ln != null && ct != null) records.da[ln] = ct;
    } else if (line == 'end_of_record') {
      current = null;
      records = null;
    }
  }
  return out;
}

class _Excluded {
  const _Excluded({required this.wholeFile, required this.lines});
  final bool wholeFile;
  final Set<int> lines;
}

_Excluded _excludedLines(List<String> sourceLines) {
  final excluded = <int>{};
  var inIgnoreBlock = false;
  for (var i = 0; i < sourceLines.length; i++) {
    final line = sourceLines[i];
    final ln = i + 1;
    if (line.contains('// coverage:ignore-file')) {
      return const _Excluded(wholeFile: true, lines: <int>{});
    }
    if (line.contains('// coverage:ignore-start')) {
      inIgnoreBlock = true;
      excluded.add(ln);
      continue;
    }
    if (line.contains('// coverage:ignore-end')) {
      inIgnoreBlock = false;
      excluded.add(ln);
      continue;
    }
    if (inIgnoreBlock || line.contains('// coverage:ignore-line')) {
      excluded.add(ln);
    }
  }
  return _Excluded(wholeFile: false, lines: excluded);
}
