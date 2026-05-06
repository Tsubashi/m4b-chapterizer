import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'drag_drop_channel.dart';
import 'handle_files_dropped.dart';

/// True while the user is dragging a payload over the window.
final isDragOverProvider = StateProvider<bool>((ref) => false);

/// Wraps [child] and overlays a "Drop .m4b file here to open" panel
/// while the user is dragging files over the window. Routes drop
/// events to [handleFilesDropped].
class DragDropOverlay extends ConsumerStatefulWidget {
  const DragDropOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DragDropOverlay> createState() => _DragDropOverlayState();
}

class _DragDropOverlayState extends ConsumerState<DragDropOverlay> {
  StreamSubscription<DragEvent>? _sub;

  @override
  void initState() {
    super.initState();
    final channel = ref.read(dragDropChannelProvider);
    _sub = channel.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onEvent(DragEvent event) {
    if (!mounted) return;
    switch (event) {
      case DragEntered():
        ref.read(isDragOverProvider.notifier).state = true;
      case DragExited():
        ref.read(isDragOverProvider.notifier).state = false;
      case FilesDropped(:final paths):
        ref.read(isDragOverProvider.notifier).state = false;
        // Don't await — we want to return control to the stream
        // immediately. handleFilesDropped manages its own dialog state.
        handleFilesDropped(context, ref, paths);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDragOver = ref.watch(isDragOverProvider);
    return Stack(
      children: [
        widget.child,
        if (isDragOver)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                alignment: Alignment.center,
                child: const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.file_download, size: 48),
                        SizedBox(height: 12),
                        Text(
                          'Drop .m4b file here to open',
                          style: TextStyle(fontSize: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
