import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Calls [body] and, if it throws a [PlatformException] with the
/// `ENTITLEMENT_NOT_FOUND` code (or any other PlatformException),
/// shows an explanatory dialog and returns null.
///
/// Use this at every call site that invokes file_picker on macOS, where the
/// app sandbox can refuse the picker if its entitlements file is missing
/// `com.apple.security.files.user-selected.read-write`.
Future<T?> guardFilePicker<T>(
  BuildContext context,
  Future<T?> Function() body,
) async {
  try {
    return await body();
  } on PlatformException catch (error) {
    if (!context.mounted) return null;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final isEntitlement = error.code == 'ENTITLEMENT_NOT_FOUND';
        return AlertDialog(
          title: Text(isEntitlement
              ? 'File access not permitted'
              : 'Couldn\'t open the file picker'),
          content: SingleChildScrollView(
            child: Text(
              isEntitlement
                  ? 'This build of m4b chapterizer is missing the macOS '
                      'sandbox entitlement that lets it read or write files '
                      'the user picks.\n\n'
                      'Fix: add this to '
                      'macos/Runner/{DebugProfile,Release}.entitlements:\n\n'
                      '<key>com.apple.security.files.user-selected.read-write</key>\n'
                      '<true/>\n\n'
                      'Then rebuild with `flutter build macos`.\n\n'
                      'Underlying error: ${error.message ?? error.code}'
                  : 'The file picker reported an error. You can try again, '
                      'or restart the app.\n\n'
                      'Underlying error: ${error.message ?? error.code}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    return null;
  }
}
