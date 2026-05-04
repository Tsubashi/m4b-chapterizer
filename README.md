# m4b_chapterizer

A new Flutter project.

## Bundled ffmpeg / ffprobe

The app ships with pinned `ffmpeg` and `ffprobe` static binaries (version 7.1) bundled as Flutter assets. The binaries are not committed to the repository; before running `flutter build` or `flutter run` on a fresh checkout the build host must populate `assets/bin/<platform>/` by running `dart run tool/fetch_ffmpeg.dart`. The script downloads the platform-appropriate archive, verifies its SHA-256 against the value pinned in `tool/fetch_ffmpeg.dart`, and extracts the binaries. Per-platform URLs and hashes are tracked inside that script; SHA values for platforms other than `macos-arm64` are placeholders that must be filled in by running the script once on each target platform.