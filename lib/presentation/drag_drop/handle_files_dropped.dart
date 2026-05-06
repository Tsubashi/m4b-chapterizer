import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor_state.dart';
import 'dirty_check.dart';

/// Validates a dropped payload and, if it's a single .m4b file,
/// runs the dirty-check and opens the file.
///
/// Validation order (first match wins):
///   1. paths.length != 1  → SnackBar "Drop only one .m4b file at a time"
///   2. extension != .m4b   → SnackBar "Only .m4b files can be opened"
///   3. otherwise           → confirmReplaceCurrentBook → editor.open
Future<void> handleFilesDropped(
  BuildContext context,
  WidgetRef ref,
  List<String> paths,
) async {
  if (paths.length != 1) {
    _snack(context, 'Drop only one .m4b file at a time');
    return;
  }
  final path = paths.single;
  if (!path.toLowerCase().endsWith('.m4b')) {
    _snack(context, 'Only .m4b files can be opened');
    return;
  }
  if (!await confirmReplaceCurrentBook(context, ref)) return;
  if (!context.mounted) return;
  await ref.read(editorProvider.notifier).open(path);
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
