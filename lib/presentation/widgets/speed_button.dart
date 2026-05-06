import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/playback.dart';

/// Speed values offered by the SpeedButton's preset menu and reachable
/// via the Cmd+]/Cmd+[ keyboard shortcuts.
const List<double> kSpeedPresets = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

/// Speed selected by Cmd+\ (the "reset" shortcut) and used as the
/// initial speed for the JustAudio player.
const double kDefaultSpeed = 1.0;

/// Renders a speed value as the user-facing label. Integer speeds drop
/// the trailing decimal ("1×" not "1.0×"); fractional speeds keep their
/// fraction ("0.5×", "1.25×").
String formatSpeed(double speed) {
  if (speed == speed.roundToDouble()) {
    return '${speed.toInt()}×';
  }
  return '$speed×';
}

/// Returns the preset reached by stepping from the closest preset to
/// [current] by [direction] (+1 forward, -1 backward), clamped to the
/// ends of [kSpeedPresets].
double nextSpeedPreset(double current, {required int direction}) {
  final closestIdx = _closestPresetIndex(current);
  final newIdx =
      (closestIdx + direction).clamp(0, kSpeedPresets.length - 1);
  return kSpeedPresets[newIdx];
}

int _closestPresetIndex(double speed) {
  var bestIdx = 0;
  var bestDelta = (kSpeedPresets[0] - speed).abs();
  for (var i = 1; i < kSpeedPresets.length; i++) {
    final d = (kSpeedPresets[i] - speed).abs();
    if (d < bestDelta) {
      bestDelta = d;
      bestIdx = i;
    }
  }
  return bestIdx;
}

class SpeedButton extends ConsumerWidget {
  const SpeedButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackControllerProvider);
    return StreamBuilder<double>(
      stream: controller.speedStream,
      initialData: controller.speed,
      builder: (context, snapshot) {
        final speed = snapshot.data ?? controller.speed;
        return MenuAnchor(
          builder: (context, menuController, _) => TextButton(
            key: const ValueKey('playback.speed'),
            onPressed: () => menuController.isOpen
                ? menuController.close()
                : menuController.open(),
            child: Text(formatSpeed(speed)),
          ),
          menuChildren: [
            for (final preset in kSpeedPresets)
              MenuItemButton(
                key: ValueKey('playback.speed.$preset'),
                onPressed: () => controller.setSpeed(preset),
                child: Text(formatSpeed(preset)),
              ),
          ],
        );
      },
    );
  }
}
