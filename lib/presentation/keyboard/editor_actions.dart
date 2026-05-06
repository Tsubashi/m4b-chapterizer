import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../drag_drop/dirty_check.dart';
import '../providers/editor_state.dart';
import '../util/file_picker_errors.dart';

/// Imperative editor actions shared between the AppBar buttons and
/// the keyboard shortcut bindings.
class EditorActions {
  EditorActions(this.context, this.ref);

  final BuildContext context;
  final WidgetRef ref;

  // coverage:ignore-start
  // FilePicker is a platform plugin and can't be simulated cleanly in a
  // `flutter test` widget environment. The dirty-check is in
  // confirmReplaceCurrentBook (covered by dirty_check_test.dart);
  // open() itself is exercised only by interactive smoke tests.
  Future<void> open() async {
    if (!await confirmReplaceCurrentBook(context, ref)) return;
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
