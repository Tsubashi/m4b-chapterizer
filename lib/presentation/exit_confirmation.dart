import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/editor_state.dart';

enum ExitDecision { cancel, discard, save }

/// Shows the unsaved-changes confirm dialog. Returns the user's pick,
/// or null if the dialog cannot be shown.
Future<ExitDecision?> showExitConfirmDialog(BuildContext context) {
  return showDialog<ExitDecision>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Unsaved changes'),
      content: const Text(
        'Do you want to save your changes before exiting?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(ExitDecision.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(ExitDecision.discard),
          child: const Text('Discard'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(ExitDecision.save),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// True if the application should proceed with closing.
///
/// Fast path: if the editor isn't dirty, returns true without showing a
/// dialog. Otherwise shows [showExitConfirmDialog] and:
/// - Cancel / dismissed → false
/// - Discard → true
/// - Save → awaits the editor's save, then true
Future<bool> handleExitRequest(BuildContext context, WidgetRef ref) async {
  final state = ref.read(editorProvider);
  if (!state.isDirty) return true;

  final decision = await showExitConfirmDialog(context);
  switch (decision) {
    case ExitDecision.discard:
      return true;
    case ExitDecision.save:
      await ref.read(editorProvider.notifier).save();
      return true;
    case ExitDecision.cancel:
    case null:
      return false;
  }
}

// coverage:ignore-start
// Window-manager glue. The OS-level close event is delivered through a
// platform method channel that isn't exercised by `flutter test`; this
// widget is exercised only by smoke tests on a real desktop build. The
// testable logic is in [handleExitRequest] above.

/// Wraps [child] and intercepts OS window-close attempts (red X, Cmd+W,
/// Cmd+Q). On close, calls [handleExitRequest] and either destroys the
/// window or stays.
class WindowCloseGuard extends ConsumerStatefulWidget {
  const WindowCloseGuard({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WindowCloseGuard> createState() => _WindowCloseGuardState();
}

class _WindowCloseGuardState extends ConsumerState<WindowCloseGuard>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    if (!mounted) return;
    final shouldExit = await handleExitRequest(context, ref);
    if (shouldExit) {
      await windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
// coverage:ignore-end
