import 'package:flutter/material.dart';

enum UnsavedChangesDecision { cancel, discard, save }

/// Shows the unsaved-changes confirm dialog. Returns the user's pick,
/// or null if the dialog cannot be shown / was dismissed.
Future<UnsavedChangesDecision?> showUnsavedChangesDialog(BuildContext context) {
  return showDialog<UnsavedChangesDecision>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Unsaved changes'),
      content: const Text(
        'Do you want to save your changes before continuing?',
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(UnsavedChangesDecision.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(UnsavedChangesDecision.discard),
          child: const Text('Discard'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(ctx).pop(UnsavedChangesDecision.save),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
