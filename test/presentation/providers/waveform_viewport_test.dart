import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/presentation/providers/waveform_viewport.dart';

const _total60s = Duration(seconds: 60);
const _viewportWidth = 800.0;

WaveformViewportNotifier _makeNotifier() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  // Read once to instantiate the notifier; we drive it directly from
  // here for the rest of each test.
  container.read(waveformViewportProvider);
  return container.read(waveformViewportProvider.notifier);
}

void main() {
  test('reset returns to default state', () {
    final n = _makeNotifier();
    n.zoomTo(400, const Duration(seconds: 5), _total60s, _viewportWidth);
    n.reset(_total60s, _viewportWidth);
    expect(n.state.pixelsPerSecond, 100);
    expect(n.state.windowStart, Duration.zero);
  });

  test('reset clamps to whole-file fit for short files', () {
    final n = _makeNotifier();
    // totalDuration=4s, viewport=800 → minPxPerSec = 200. Default 100 is
    // below the min, so reset picks the min.
    n.reset(const Duration(seconds: 4), _viewportWidth);
    expect(n.state.pixelsPerSecond, 200);
    expect(n.state.windowStart, Duration.zero);
  });

  test('zoomIn doubles pxPerSec and re-centers on centerTime', () {
    final n = _makeNotifier();
    // Default state: 100 px/s, windowStart 0 ⇒ windowDuration = 8s.
    // Center on time 12s. Old fraction of 12s in window is (12-0)/8 = 1.5
    // — but center time only matters when it's actually inside the
    // window, otherwise it's clamped after. Pick a center inside.
    n.zoomTo(100, Duration.zero, _total60s, _viewportWidth);
    // Now zoomIn centered on 4s (which IS in the [0, 8] window).
    n.zoomIn(const Duration(seconds: 4), _total60s, _viewportWidth);
    expect(n.state.pixelsPerSecond, 200);
    // Window is now 800/200 = 4s wide. 4s should be at the same fraction
    // (0.5) it was before, so windowStart = 4 - 0.5*4 = 2s.
    expect(n.state.windowStart, const Duration(seconds: 2));
  });

  test('zoomOut halves and clamps at min', () {
    final n = _makeNotifier();
    n.reset(_total60s, _viewportWidth); // 100 px/s
    n.zoomOut(const Duration(seconds: 4), _total60s, _viewportWidth);
    expect(n.state.pixelsPerSecond, 50);
    n.zoomOut(const Duration(seconds: 4), _total60s, _viewportWidth);
    expect(n.state.pixelsPerSecond, 25);
    n.zoomOut(const Duration(seconds: 4), _total60s, _viewportWidth);
    // minPxPerSec = 800/60 ≈ 13.333. Halving 25 → 12.5, but clamped to
    // 13.333… (we accept ±0.01 tolerance for float math).
    expect(n.state.pixelsPerSecond, closeTo(800 / 60, 0.01));
  });

  test('zoomIn clamps at max (2000)', () {
    final n = _makeNotifier();
    n.zoomTo(1500, Duration.zero, _total60s, _viewportWidth);
    n.zoomIn(Duration.zero, _total60s, _viewportWidth);
    expect(n.state.pixelsPerSecond, 2000); // 3000 clamped to 2000
  });

  test('panBy shifts windowStart and clamps left', () {
    final n = _makeNotifier();
    n.reset(_total60s, _viewportWidth);
    n.zoomTo(100, const Duration(seconds: 10), _total60s, _viewportWidth);
    expect(n.state.windowStart, const Duration(seconds: 10));
    n.panBy(-2000, _total60s, _viewportWidth); // -20s in time
    expect(n.state.windowStart, Duration.zero);
  });

  test('panBy shifts windowStart and clamps right', () {
    final n = _makeNotifier();
    n.reset(_total60s, _viewportWidth);
    n.panBy(10000, _total60s, _viewportWidth); // +100s in time
    // windowDuration = 8s, so max windowStart = 60 - 8 = 52s.
    expect(n.state.windowStart, const Duration(seconds: 52));
  });

  test('followPlayhead places playhead at 25% from left', () {
    final n = _makeNotifier();
    n.reset(_total60s, _viewportWidth);
    // windowDuration = 8s; 25% of 8 = 2s. So windowStart = 30 - 2 = 28s.
    n.followPlayhead(const Duration(seconds: 30), _total60s, _viewportWidth);
    expect(n.state.windowStart, const Duration(seconds: 28));
  });

  test('followPlayhead clamps near file start', () {
    final n = _makeNotifier();
    n.reset(_total60s, _viewportWidth);
    n.followPlayhead(const Duration(seconds: 1), _total60s, _viewportWidth);
    expect(n.state.windowStart, Duration.zero);
  });

  test('followPlayhead clamps near file end', () {
    final n = _makeNotifier();
    n.reset(_total60s, _viewportWidth);
    n.followPlayhead(const Duration(seconds: 59), _total60s, _viewportWidth);
    // windowDuration = 8s, max start = 52s.
    expect(n.state.windowStart, const Duration(seconds: 52));
  });

  test('zoomTo direct call clamps and re-centers', () {
    final n = _makeNotifier();
    n.reset(_total60s, _viewportWidth);
    n.zoomTo(400, const Duration(seconds: 5), _total60s, _viewportWidth);
    expect(n.state.pixelsPerSecond, 400);
    // windowDuration = 800/400 = 2s. 5s was at fraction 5/8 = 0.625 in
    // the old window. New windowStart = 5 - 0.625*2 = 3.75s.
    expect(
      n.state.windowStart.inMilliseconds,
      closeTo(3750, 1),
    );
  });
}
