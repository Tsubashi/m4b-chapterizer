import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dialogs/unsaved_changes_dialog.dart';
import '../providers/editor_state.dart';

/// Returns true if the caller should proceed with replacing the
/// currently-open audiobook, false if the user cancelled.
///
/// - Clean state: returns true immediately, no dialog.
/// - Dirty + Cancel / dismiss: returns false.
/// - Dirty + Discard: returns true (no save).
/// - Dirty + Save: awaits `editor.save()`, returns true. If save throws,
///   the throw propagates and the caller treats that as "abort."
Future<bool> confirmReplaceCurrentBook(
  BuildContext context,
  WidgetRef ref,
) async {
  final state = ref.read(editorProvider);
  if (!state.isDirty) return true;

  final decision = await showUnsavedChangesDialog(context);
  switch (decision) {
    case UnsavedChangesDecision.discard:
      return true;
    case UnsavedChangesDecision.save:
      await ref.read(editorProvider.notifier).save();
      return true;
    case UnsavedChangesDecision.cancel:
    case null:
      return false;
  }
}
