import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Events emitted by the platform drag-drop channel as the user drags
/// files over the window.
sealed class DragEvent {
  const DragEvent();
}

/// A drag has entered the window. The overlay should appear.
class DragEntered extends DragEvent {
  const DragEntered();
}

/// The drag exited the window without dropping. The overlay should
/// disappear.
class DragExited extends DragEvent {
  const DragExited();
}

/// The user dropped one or more files. [paths] is the absolute
/// filesystem paths in drop order.
class FilesDropped extends DragEvent {
  const FilesDropped(this.paths);
  final List<String> paths;
}

/// Source of [DragEvent]s. Production binds [MethodChannelDragDropChannel];
/// tests bind a fake.
abstract class DragDropChannel {
  Stream<DragEvent> get events;
}

/// Provider for the drag-drop channel. Tests override; `main.dart`
/// overrides at production startup.
final dragDropChannelProvider = Provider<DragDropChannel>((ref) {
  // coverage:ignore-start
  // Defensive fallback: production wires the override in main(); tests
  // always override before reading.
  throw StateError(
    'dragDropChannelProvider must be overridden at the app or test scope',
  );
  // coverage:ignore-end
});
