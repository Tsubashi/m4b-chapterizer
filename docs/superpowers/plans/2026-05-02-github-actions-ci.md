# GitHub Actions CI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a GitHub Actions workflow that runs `flutter analyze`, `flutter test`, and `flutter build <platform> --debug` on macOS, Ubuntu, and Windows runners.

**Architecture:** Single workflow with a 3-platform matrix. CI uses system-installed ffmpeg (via brew/apt/choco) instead of `fetch_ffmpeg.dart`'s pinned bundled binaries; a new `tool/stage_system_ffmpeg.dart` script copies the system binaries into `assets/bin/<platform>/` so `bundledTestResolver()` finds them.

**Reference design:** `docs/superpowers/specs/2026-05-02-github-actions-ci-design.md`

**Conventions:** `--no-gpg-sign` REQUIRED on every commit.

---

## Task 1: `tool/stage_system_ffmpeg.dart`

**Files:**
- Create: `tool/stage_system_ffmpeg.dart`

### Step 1: Implement the script

Create `tool/stage_system_ffmpeg.dart`:

```dart
// Copies system-installed `ffmpeg` and `ffprobe` (from PATH) into
// `assets/bin/<platform>/` so `bundledTestResolver()` finds them. Used by
// CI in place of `fetch_ffmpeg.dart`'s pinned bundled binaries — see the
// design at docs/superpowers/specs/2026-05-02-github-actions-ci-design.md
// for the rationale (we don't have SHAs pinned for windows/linux/macos-x64
// yet).
//
// Run from the repo root:
//   dart run tool/stage_system_ffmpeg.dart

import 'dart:io';

String _platformKey() {
  if (Platform.isMacOS) {
    return Platform.version.contains('arm64') ? 'macos-arm64' : 'macos-x64';
  }
  if (Platform.isWindows) return 'windows-x64';
  if (Platform.isLinux) return 'linux-x64';
  throw UnsupportedError('Unsupported: ${Platform.operatingSystem}');
}

Future<String> _which(String name) async {
  final cmd = Platform.isWindows ? 'where' : 'which';
  final result = await Process.run(cmd, [name]);
  if (result.exitCode != 0) {
    throw StateError(
      '$name not found on PATH. Install it (brew/apt/choco) and retry.',
    );
  }
  // `where` on Windows can return multiple lines; take the first.
  return (result.stdout as String).split('\n').first.trim();
}

Future<void> _stage(String name, String platformKey) async {
  final src = await _which(name);
  final exeSuffix = Platform.isWindows ? '.exe' : '';
  final destDir = Directory('assets/bin/$platformKey');
  if (!destDir.existsSync()) destDir.createSync(recursive: true);
  final destPath = '${destDir.path}/$name$exeSuffix';
  await File(src).copy(destPath);
  if (!Platform.isWindows) {
    await Process.run('chmod', ['+x', destPath]);
  }
  stdout.writeln('  $src -> $destPath');
}

Future<void> main() async {
  final key = _platformKey();
  stdout.writeln('Staging system ffmpeg/ffprobe for $key...');
  await _stage('ffmpeg', key);
  await _stage('ffprobe', key);
  stdout.writeln('Done.');
}
```

### Step 2: Sanity-check on the local machine

Run:

```bash
dart run tool/stage_system_ffmpeg.dart
ls -la assets/bin/macos-arm64/
```

Expected: prints two `... -> assets/bin/macos-arm64/...` lines, then "Done."; the `ls` shows updated mtimes on the staged files.

(On the dev machine, `assets/bin/macos-arm64/` already contains pinned-version binaries from prior `fetch_ffmpeg.dart` runs. The stage script overwrites them with whatever's on `PATH`. Run `dart run tool/fetch_ffmpeg.dart` afterward to restore the pinned versions for local development.)

### Step 3: Run tests + analyzer

Run: `flutter test`
Expected: all 183 tests pass (the stage script doesn't affect tests directly, but verifying nothing broke).

Run: `flutter analyze`
Expected: clean.

### Step 4: Commit

```bash
git add tool/stage_system_ffmpeg.dart
git commit --no-gpg-sign -m "Add tool/stage_system_ffmpeg.dart for CI use"
```

---

## Task 2: `TODO.md`

**Files:**
- Create: `TODO.md`

### Step 1: Write the file

Create `TODO.md` at the repo root:

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

### Step 2: Commit

```bash
git add TODO.md
git commit --no-gpg-sign -m "Track deferred CI/build work in TODO.md"
```

---

## Task 3: `.github/workflows/ci.yml`

**Files:**
- Create: `.github/workflows/ci.yml`

### Step 1: Create the workflow

Create `.github/workflows/ci.yml`:

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
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
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

      - name: Ensure ffmpeg present (macOS)
        if: runner.os == 'macOS'
        run: |
          if ! command -v ffmpeg >/dev/null 2>&1; then
            brew install ffmpeg
          fi
          ffmpeg -version

      - name: Stage system ffmpeg into assets/bin
        run: dart run tool/stage_system_ffmpeg.dart

      - name: Get packages
        run: flutter pub get

      - name: Analyze
        run: flutter analyze --fatal-infos

      - name: Test (with coverage)
        run: flutter test --coverage

      - name: Coverage summary
        run: dart run tool/coverage_summary.dart

      - name: Build (macOS)
        if: runner.os == 'macOS'
        run: flutter build macos --debug

      - name: Build (Linux)
        if: runner.os == 'Linux'
        run: |
          sudo apt-get install -y ninja-build libgtk-3-dev
          flutter build linux --debug

      - name: Build (Windows)
        if: runner.os == 'Windows'
        run: flutter build windows --debug
```

Notes on the steps:

- `flutter analyze --fatal-infos` upgrades any analyzer info-level warnings into errors. We currently keep the project clean of these; this guards against regressions.
- The Linux build step installs `ninja-build` and `libgtk-3-dev` because Flutter Linux requires them and they aren't always preinstalled on `ubuntu-latest`.
- `subosito/flutter-action@v2` caches the Flutter SDK and `~/.pub-cache` automatically when `cache: true`.

### Step 2: Lint the YAML locally (optional but cheap)

If `yamllint` is available, run it. Otherwise skip — the workflow's syntax will be checked by GitHub when it runs.

### Step 3: Commit

```bash
git add .github/workflows/ci.yml
git commit --no-gpg-sign -m "Add GitHub Actions CI for macOS, Ubuntu, Windows"
```

### Step 4: Verification (post-push)

After pushing to a remote and running the workflow, expect:

- macOS job green: ffmpeg present (preinstalled or `brew install`), tests pass, `flutter build macos --debug` succeeds (the existing Run Script phase copies our staged binaries into the .app).
- Ubuntu job green: ffmpeg installed via apt, tests pass, `flutter build linux --debug` succeeds (ninja + GTK installed by the build step).
- Windows job green: ffmpeg installed via choco, tests pass, `flutter build windows --debug` succeeds.

If any platform reveals an issue, fix forward and iterate. Common possible failures and their likely fixes:

- **Windows path separator issues** in `bundled_test_resolver.dart` or `stage_system_ffmpeg.dart`: use `path.join` consistently or check for `Platform.isWindows`. The current code uses `/` which Windows tolerates for most APIs but not all.
- **Linux audio backend missing for `just_audio`**: the package may need `libmpv` or another runtime dep on Ubuntu. If the Linux build complains about audio, add the relevant package to the install step.
- **macOS x64 vs arm64 ffmpeg architecture mismatch**: GitHub's `macos-latest` is arm64 since 2024; our existing `assets/bin/macos-arm64/` already matches. If a runner is x64, the platform key resolves to `macos-x64` and `_stage` puts files there — should work transparently.

---

## Final verification

- [ ] All three CI jobs green on the first push of the workflow.
- [ ] If any are red, iterate per the verification notes above.
