# GitHub Actions CI — Design

**Date:** 2026-05-02
**Status:** Approved (brainstorming phase)

## Overview

Add a GitHub Actions workflow that runs on every push and pull request, builds and tests the project on macOS, Ubuntu, and Windows runners. Catches platform-specific compile errors (e.g. the Swift `windowShouldClose:` change we just landed) that the unit-test suite can't see.

## Goals

- Three OS matrix: `macos-latest`, `ubuntu-latest`, `windows-latest`.
- Each job runs `flutter pub get` → `flutter analyze` → `flutter test` → `flutter build <platform> --debug`.
- Each job has access to `ffmpeg`/`ffprobe` so the bookbinder integration test and the waveform extractor integration test can run against `bundledTestResolver()`.
- `fail-fast: false` so one platform's failure doesn't mask the others.
- Workflow runs on every push and every pull-request.
- Deferred items captured as a `TODO.md` so they don't get lost.

## Non-goals (deferred — see `TODO.md`)

The following are intentionally out of scope for the MVP CI; each is captured as a `TODO.md` entry:

- Per-platform SHA-pinning in `tool/fetch_ffmpeg.dart` for `windows-x64`, `linux-x64`, and `macos-x64`. CI uses system-installed ffmpeg instead.
- Equivalent of macOS's "Bundle ffmpeg binaries" build phase for Windows and Linux. Until then, Windows/Linux `flutter build` produces a binary that compiles cleanly but doesn't ship ffmpeg with it.
- Codecov / Coveralls / external coverage reporting. Filtered coverage continues to print in the log via `tool/coverage_summary.dart`.
- A coverage-floor gate (`--ci-fail-under <pct>`).
- Build artifact uploads (`.app`, `.exe`, executables).
- Test failure artifact uploads (golden mismatches, screenshots).
- A README status badge.

## Architecture

### Workflow file

A single workflow at `.github/workflows/ci.yml`. One job (`build-and-test`) with a 3-platform matrix.

```yaml
name: CI

on:
  push:
  pull_request:

jobs:
  build-and-test:
    strategy:
      fail-fast: false
      matrix:
        os: [macos-latest, ubuntu-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.9'
          channel: 'stable'
          cache: true
      - name: Install ffmpeg (Ubuntu)
        if: runner.os == 'Linux'
        run: sudo apt-get update && sudo apt-get install -y ffmpeg
      - name: Install ffmpeg (Windows)
        if: runner.os == 'Windows'
        run: choco install ffmpeg-essentials -y
      - name: Verify ffmpeg (macOS)
        if: runner.os == 'macOS'
        run: ffmpeg -version || brew install ffmpeg
      - name: Stage system ffmpeg into assets/bin
        run: dart run tool/stage_system_ffmpeg.dart
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test --coverage
      - run: dart run tool/coverage_summary.dart
      - name: Build (macOS)
        if: runner.os == 'macOS'
        run: flutter build macos --debug
      - name: Build (Ubuntu)
        if: runner.os == 'Linux'
        run: flutter build linux --debug
      - name: Build (Windows)
        if: runner.os == 'Windows'
        run: flutter build windows --debug
```

(Final whitespace and step phrasing get nailed down in the implementation plan.)

### `tool/stage_system_ffmpeg.dart` (new)

A small Dart script that:

1. Determines the platform key with the same `_platformKey()` logic used in `fetch_ffmpeg.dart`.
2. Resolves `ffmpeg`/`ffprobe` on `PATH` (`Process.run('which', [name])` on Unix, `Process.run('where', [name])` on Windows).
3. Creates `assets/bin/<key>/` if it doesn't exist.
4. Copies (not symlinks — Windows symlinks need elevated permissions and the runners don't grant them by default) `ffmpeg` and `ffprobe` into `assets/bin/<key>/{ffmpeg,ffprobe}{,.exe}`.
5. Sets the execute bit on Unix via `chmod +x`.
6. Refuses cleanly with a clear error if either binary isn't on `PATH`.

This script replaces `fetch_ffmpeg.dart` for CI purposes. Locally, developers who want the pinned bundled version still run `fetch_ffmpeg.dart`.

### `TODO.md` (new)

A simple markdown file at the repo root tracking deferred work. Initial entries match the Non-goals section above. Format:

```markdown
# Deferred work

Items intentionally out of scope for the current cycle but worth doing later.

## CI / build infrastructure

- [ ] **Pin per-platform ffmpeg SHAs in `tool/fetch_ffmpeg.dart`** for `windows-x64`, `linux-x64`, and `macos-x64`. Currently CI relies on system ffmpeg via `tool/stage_system_ffmpeg.dart`; production builds for those platforms don't yet bundle ffmpeg.
- [ ] **Add macOS-equivalent "Bundle ffmpeg binaries" build steps for Windows and Linux** so production builds on those platforms also ship the pinned ffmpeg.
- [ ] **Coverage reporting service** (Codecov or Coveralls) so coverage is visible on PRs without reading raw logs.
- [ ] **Coverage-floor gate**: extend `tool/coverage_summary.dart` with `--ci-fail-under <pct>` and wire into CI to fail builds if filtered coverage drops below ~95%.
- [ ] **Build-artifact upload** for the `.app`, `.exe`, and Linux bundle so PRs can ship test-able artifacts.
- [ ] **Test-failure artifact upload** (golden diffs, widget screenshots) for diagnosing CI-only failures.
- [ ] **README status badge** for the CI workflow.

## Other

- (Add new items here as they come up.)
```

### Why CI uses system ffmpeg instead of `fetch_ffmpeg.dart`

`fetch_ffmpeg.dart` requires SHA pins for each archive. We have them for `macos-arm64` and placeholders for the other three platforms. Until those are filled in (and the windows/linux extraction branches finished), `fetch_ffmpeg.dart` won't run on CI runners. System ffmpeg via package manager bypasses the entire pinning question — at the cost of CI testing against whatever ffmpeg version the runner happens to have. Acceptable for catching regressions; insufficient for production builds, which is why the bundling story is in `TODO.md`.

## Tests

This is infrastructure, not application code; there are no unit tests to add. Verification is empirical:

1. Push the workflow on a feature branch.
2. Observe each platform's job: setup → install ffmpeg → analyze → test → build all green.
3. Iterate on the workflow until clean.

The plan calls out the verification step explicitly.

## Files

- Create: `.github/workflows/ci.yml`
- Create: `tool/stage_system_ffmpeg.dart`
- Create: `TODO.md`
