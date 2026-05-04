# M4b Chapterizer

A GUI utility for editing M4B chapters and metadata.

## Bundled ffmpeg / ffprobe

The app is designed to ship with pinned `ffmpeg` and `ffprobe` static binaries (version 7.1) bundled as Flutter assets. The binaries are not committed to the repository, so you will need to populate `assets/bin/<platform>/` by running `dart run tool/fetch_ffmpeg.dart` before running `flutter build` or `flutter run` on a fresh checkout. The script downloads the platform-appropriate archive, verifies its SHA-256 against the value pinned in `tool/fetch_ffmpeg.dart`, and extracts the binaries. Per-platform URLs and hashes are tracked inside that script.