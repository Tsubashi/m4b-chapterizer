import 'dart:async';

import 'package:flutter/services.dart';
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

// coverage:ignore-start
// Production implementation. The platform side (Swift on macOS, future
// C++ on Windows, GTK on Linux) sends three method calls over this
// channel: 'dragEntered' (no args), 'dragExited' (no args), and
// 'filesDropped' with `paths: List<String>`. Exercised only by smoke
// tests on a real desktop build.

/// Platform-channel-backed drag-drop event stream.
class MethodChannelDragDropChannel implements DragDropChannel {
  MethodChannelDragDropChannel({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('m4b_chapterizer/drag_drop') {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final StreamController<DragEvent> _controller =
      StreamController<DragEvent>.broadcast();

  @override
  Stream<DragEvent> get events => _controller.stream;

  Future<void> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'dragEntered':
        _controller.add(const DragEntered());
      case 'dragExited':
        _controller.add(const DragExited());
      case 'filesDropped':
        final raw = (call.arguments as Map?)?['paths'] as List? ?? const [];
        _controller.add(FilesDropped(raw.cast<String>()));
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _controller.close();
  }
}
// coverage:ignore-end
