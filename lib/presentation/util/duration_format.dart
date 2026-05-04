String formatDuration(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
  return '$h:$m:$s.$ms';
}

/// Parses `HH:MM:SS.mmm`, `MM:SS.mmm`, or plain seconds. Permissive about
/// missing leading zeroes and missing milliseconds. Throws [FormatException]
/// on invalid input.
Duration parseDuration(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty || trimmed.startsWith('-')) {
    throw FormatException('Invalid duration: $input');
  }
  final parts = trimmed.split(':');
  if (parts.length > 3) {
    throw FormatException('Too many : segments: $input');
  }
  int hours = 0;
  int minutes = 0;
  double seconds;
  if (parts.length == 3) {
    hours = int.parse(parts[0]);
    minutes = int.parse(parts[1]);
    seconds = double.parse(parts[2]);
  } else if (parts.length == 2) {
    minutes = int.parse(parts[0]);
    seconds = double.parse(parts[1]);
  } else {
    seconds = double.parse(parts[0]);
  }
  if (hours < 0 || minutes < 0 || seconds < 0) {
    throw FormatException('Negative components not allowed: $input');
  }
  final totalMs =
      (hours * 3600 + minutes * 60) * 1000 + (seconds * 1000).round();
  return Duration(milliseconds: totalMs);
}
