import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor_state.dart';
import '../util/file_picker_errors.dart';

/// Imperative editor actions shared between the AppBar buttons and
/// the keyboard shortcut bindings.
class EditorActions {
  EditorActions(this.context, this.ref);

  final BuildContext context;
  final WidgetRef ref;

  // coverage:ignore-start
  // The discard-confirmation dialog and the FilePicker open/saveAs flows
  // can't be simulated cleanly in a `flutter test` widget environment —
  // FilePicker is a platform plugin and the dialog flows are exercised
  // by interactive smoke tests. `save()` below stays measured because it
  // uses neither.
  Future<bool> _confirmDiscard() async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content:
            const Text('You have unsaved changes. Continue and lose them?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Discard')),
        ],
      ),
    );
    return answer ?? false;
  }

  Future<void> open() async {
    final state = ref.read(editorProvider);
    if (state.isDirty && !await _confirmDiscard()) return;
    if (!context.mounted) return;
    final result = await guardFilePicker(
      context,
      () => FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['m4b'],
      ),
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await ref.read(editorProvider.notifier).open(path);
  }
  // coverage:ignore-end

  Future<void> save() async {
    if (ref.read(editorProvider).audiobook == null) return;
    await ref.read(editorProvider.notifier).save();
  }

  // coverage:ignore-start
  // saveAs() bridges to FilePicker.saveFile, same constraint as open().
  Future<void> saveAs() async {
    if (ref.read(editorProvider).audiobook == null) return;
    final state = ref.read(editorProvider);
    final filename =
        state.path?.split(Platform.pathSeparator).last ?? 'book.m4b';
    final result = await guardFilePicker(
      context,
      () => FilePicker.saveFile(
        type: FileType.custom,
        allowedExtensions: const ['m4b'],
        fileName: filename,
      ),
    );
    if (result == null) return;
    await ref.read(editorProvider.notifier).saveAs(result);
  }
  // coverage:ignore-end
}
