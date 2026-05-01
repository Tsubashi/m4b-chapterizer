# m4b_chapterizer

A new Flutter project.

## Bundled ffmpeg / ffprobe

The app ships with pinned `ffmpeg` and `ffprobe` static binaries (version 7.1) bundled as Flutter assets. The binaries are not committed to the repository; before running `flutter build` or `flutter run` on a fresh checkout the build host must populate `assets/bin/<platform>/` by running `dart run tool/fetch_ffmpeg.dart`. The script downloads the platform-appropriate archive, verifies its SHA-256 against the value pinned in `tool/fetch_ffmpeg.dart`, and extracts the binaries. Per-platform URLs and hashes are tracked inside that script; SHA values for platforms other than `macos-arm64` are placeholders that must be filled in by running the script once on each target platform.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
