import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/presentation/widgets/speed_button.dart';

void main() {
  group('formatSpeed', () {
    test('integer speeds render without trailing decimal', () {
      expect(formatSpeed(1.0), '1×');
      expect(formatSpeed(2.0), '2×');
      expect(formatSpeed(3.0), '3×');
    });

    test('fractional speeds render with the fraction', () {
      expect(formatSpeed(0.5), '0.5×');
      expect(formatSpeed(0.75), '0.75×');
      expect(formatSpeed(1.25), '1.25×');
      expect(formatSpeed(1.5), '1.5×');
    });
  });

  group('nextSpeedPreset', () {
    test('+1 returns the next preset', () {
      expect(nextSpeedPreset(1.0, direction: 1), 1.25);
      expect(nextSpeedPreset(1.5, direction: 1), 2.0);
      expect(nextSpeedPreset(2.0, direction: 1), 3.0);
    });

    test('-1 returns the previous preset', () {
      expect(nextSpeedPreset(1.0, direction: -1), 0.75);
      expect(nextSpeedPreset(1.5, direction: -1), 1.25);
      expect(nextSpeedPreset(0.75, direction: -1), 0.5);
    });

    test('clamps at the maximum', () {
      expect(nextSpeedPreset(3.0, direction: 1), 3.0);
    });

    test('clamps at the minimum', () {
      expect(nextSpeedPreset(0.5, direction: -1), 0.5);
    });

    test('snaps near-preset values to the closest preset before stepping', () {
      // 1.001 is closer to 1.0 than to 1.25; +1 from 1.0 is 1.25.
      expect(nextSpeedPreset(1.001, direction: 1), 1.25);
      // 0.499 is closer to 0.5 than to anything else; -1 clamps to 0.5.
      expect(nextSpeedPreset(0.499, direction: -1), 0.5);
    });
  });

  test('kSpeedPresets contains the seven canonical values in order', () {
    expect(kSpeedPresets, [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]);
  });

  test('kDefaultSpeed is 1.0', () {
    expect(kDefaultSpeed, 1.0);
  });
}
