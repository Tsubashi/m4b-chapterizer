# m4b-chapterizer MVP — Design

**Date:** 2026-04-30
**Status:** Approved (brainstorming phase)

## Overview

A cross-platform desktop GUI utility for editing m4b audiobook metadata, with a primary focus on chapter information. The user opens an existing `.m4b` file, edits its metadata and chapters (including audio-assisted chapter timing), and saves the result back to disk.

The implementation uses Flutter for the UI and bundles ffmpeg/ffprobe for all m4b read and write operations. The project is built test-first.

This MVP is the first deliverable in what is expected to grow into a broader m4b toolkit. The architecture is therefore deliberately layered so that future features (binding, splitting, batch operations) can plug in without restructuring.

## Goals

- Read an existing m4b file: text metadata, cover art, chapters
- Edit all of the above in a Flutter desktop GUI
- Add or delete chapters; rename and re-time them; replace cover art
- Use audio playback to find chapter boundaries by ear
- Save changes back to the original file (atomic write) or to a new path (Save As)
- Run on macOS, Windows, and Linux
- Be built test-first with a clear separation between domain logic, the ffmpeg adapter, and the UI

## Non-goals (deferred)

- Undo/redo
- Drag-and-drop file open
- Recent files menu
- Multi-file or batch editing
- Audio waveform visualization
- "Bind" workflow (combining loose audio files into an m4b)
- "Split" workflow
- Chapter import/export from external formats (Audacity labels, etc.)
- macOS code signing & notarization for distribution
- Localization
- Settings/preferences UI (ffmpeg path override, save defaults, etc.)
- Mobile (iOS/Android) support

## Architecture

Three layers, depended on in this direction only: `presentation/` → `domain/` ← `data/`.

### `domain/` — pure Dart

No Flutter, no `dart:io`, no ffmpeg references. Models and abstract interfaces only. Fully unit-testable.

- Models: `Audiobook`, `Chapter`, `Cover`
- Interface: `Bookbinder` (the abstract m4b reader/writer contract)
- Pure logic: chapter contiguity invariant, ffmetadata text serialization, ffprobe JSON deserialization

### `data/` — adapter to external tools

- `FfmpegBookbinder` implements `Bookbinder` by shelling out to bundled `ffmpeg` and `ffprobe`
- `BinaryResolver` interface abstracts where the binaries live; `BundledBinaryResolver` (production) finds them inside the app bundle, `SystemBinaryResolver` (tests/CI) finds them on `$PATH`
- `ProcessRunner` interface wraps `Process.run` so unit tests can inject canned outputs

### `presentation/` — Flutter UI

- Screens, widgets, and Riverpod state notifiers
- Depends only on `domain/` interfaces; the concrete `FfmpegBookbinder` is provided through a Riverpod override at app startup
- Widget tests substitute a `FakeBookbinder` via the same override mechanism

### Naming

`Bookbinder` / `FfmpegBookbinder` are working names that read as audiobook-themed but evoke the technical pattern. Locked in for the implementation plan unless the user proposes alternatives.

## Data model

```dart
class Audiobook {
  String? title;
  String? author;       // ffmpeg "artist" / m4a ©ART
  String? narrator;     // ffmpeg "composer" / m4a ©wrt — Audible convention
  String? album;        // ffmpeg "album" / m4a ©alb — series or audiobook title
  String? genre;
  String? description;  // ffmpeg "comment" / m4a ©cmt
  int? year;
  Cover? cover;
  List<Chapter> chapters;
  Duration totalDuration;  // read-only, sourced from ffprobe
}

class Chapter {
  String title;
  Duration start;
  Duration end;  // contiguous: chapters[i].end == chapters[i+1].start
}

class Cover {
  Uint8List bytes;
  String mimeType;  // "image/jpeg" or "image/png"
}
```

`Duration` (microsecond resolution in Dart) is used internally. Times cross the ffmpeg boundary as integer milliseconds, matching the convention in the user's prior `m4b-util` project.

End times are not exposed in the UI. Each chapter's end is derived from the next chapter's start, with the final chapter ending at `Audiobook.totalDuration`. This eliminates the contiguous/non-overlapping invariant as a category of user error.

## Read flow

1. User picks `.m4b` via `file_picker`
2. `FfmpegBookbinder.read(path)` runs:
   ```
   ffprobe -show_format -show_chapters -show_streams -of json -i <file>
   ```
3. JSON is deserialized into an `Audiobook` (text metadata + chapters + total duration)
4. If a video stream with `disposition.attached_pic == 1` is present, cover bytes are read with:
   ```
   ffmpeg -i <file> -map 0:v -frames:v 1 -f image2 pipe:1
   ```
   into memory
5. `Audiobook` is returned to the UI layer

## Write flow

1. User clicks Save (overwrite original) or Save As (new path)
2. `FfmpegBookbinder.write(audiobook, destPath)` materializes an ffmetadata text file in a temp directory:
   ```
   ;FFMETADATA1
   title=Foo
   artist=Bar
   composer=Narrator Name
   ...
   [CHAPTER]
   TIMEBASE=1/1000
   START=0
   END=183000
   title=Chapter 1
   ...
   ```
3. If cover changed, cover bytes are written to a temp file
4. ffmpeg is invoked:
   ```
   ffmpeg -i <input> -i <metadata.txt> [-i <cover>] \
     -map 0:a -map_metadata 1 -map_chapters 1 \
     [-map 2 -disposition:v:0 attached_pic] \
     -c copy <tempOut>
   ```
   The audio stream is copied (not re-encoded), so the operation is fast even on long books.
5. **Atomic replace:** the temp output is renamed over the destination path. If any step fails, the destination is untouched and the temp file is removed in a `finally` block.

## ffmpeg bundling

A specific ffmpeg version is pinned (initial target: 7.1) and per-platform static binaries are bundled inside the app:

- **macOS:** universal builds from `evermeet.cx/ffmpeg`
- **Windows:** static builds from `gyan.dev/ffmpeg`
- **Linux:** static builds from `johnvansickle.com`

A build-time tool, `tool/fetch_ffmpeg.dart`, downloads the binaries for the current build target with SHA-256 verification and places them under `assets/bin/<platform>/`. They are packaged into the Flutter app bundle and resolved at runtime via `Platform.resolvedExecutable` plus a relative path computed by `BundledBinaryResolver`.

The previous Python project (`m4b-util`) hit CI breakage from unpinned ffmpeg version drift. Bundling is explicitly chosen to avoid that class of problem.

## UI layout

Single-window editor. Approximate layout:

```
┌────────────────────────────────────────────────────────────────┐
│ [Open…] [Save] [Save As…]    book.m4b              [unsaved •] │
├──────────────────────────┬─────────────────────────────────────┤
│   Cover thumbnail        │  Chapters                           │
│   [Replace…] [Remove]    │  ┌──────────────────────────────┐   │
│                          │  │ # | Title       | Start      │   │
│   Title:    [_________]  │  │ 1 | Prologue    | 00:00.000  │   │
│   Author:   [_________]  │  │ 2 | Chapter 1   | 02:14.500  │   │
│   Narrator: [_________]  │  │ ...                          │   │
│   Album:    [_________]  │  │ [+ Add] [− Delete]           │   │
│   Year:     [____]       │  │ [Set start to playhead]      │   │
│   Genre:    [_________]  │  └──────────────────────────────┘   │
│   Description: [______]  │                                     │
├──────────────────────────┴─────────────────────────────────────┤
│ ⏮ ⏯ ⏭   00:14:32.110 / 08:42:01.000   ━━━━●────────────  1.0x  │
└────────────────────────────────────────────────────────────────┘
```

Key behaviors:

- Editing any field marks the document dirty; window title shows `•`
- Closing the window or opening another file with unsaved changes prompts to confirm
- Chapter rows are inline-editable for title and start time
- Start times are entered as `HH:MM:SS.mmm` strings; parsing is permissive about omitted leading zeros and missing milliseconds
- "Set start to playhead" snaps the selected chapter's start to the current playback position
- The cover thumbnail is replaceable from a file picker; "Remove" clears the cover

## Testing strategy

Test-first across three layers, all run by `flutter test`.

### 1. Domain unit tests (`test/domain/`)

- `Chapter` and `Audiobook` value semantics and validation
- Contiguity invariant: helpers that derive end times, insert/delete/move chapters while preserving the invariant
- ffmetadata text **codec round-trips** (parse → serialize → parse, byte-equal where defined)
- ffprobe JSON deserialization against checked-in golden fixtures

These tests have no external dependencies; they run on any machine in milliseconds.

### 2. Data-layer integration tests (`test/data/`)

- `FfmpegBookbinder` exercised against a real ffmpeg (system or bundled, via `BinaryResolver`)
- A small fixture `.m4b` (≈10 seconds of silence with 2–3 chapters, kilobytes in size) is checked into `test/fixtures/` and produced by a one-shot `tool/build_fixture.dart` script (run by hand, output committed). Building the fixture is therefore not on the test path; if it's ever lost or regenerated, the script reproduces it deterministically.
- The headline test is **read → mutate → write → read → assert** — the highest-confidence regression catch we have.

### 3. Widget tests (`test/presentation/`)

- Each screen/widget tested with a `FakeBookbinder` injected via Riverpod provider override
- Cover topics: dirty-state tracking, save/save-as flow, chapter editing, time string parsing, "set to playhead" wiring, confirm-discard dialogs

### CI

`dart test` (or `flutter test`) is wired up early — likely the first or second implementation chunk — so subsequent work has a green baseline. CI uses `SystemBinaryResolver` against a CI-provided ffmpeg of the pinned version.

## Project structure

```
m4b-chapterizer/
├── lib/
│   ├── domain/
│   │   ├── models/           # audiobook.dart, chapter.dart, cover.dart
│   │   └── bookbinder.dart   # abstract interface
│   ├── data/
│   │   ├── ffmpeg_bookbinder.dart
│   │   ├── ffmetadata_codec.dart
│   │   ├── ffprobe_codec.dart
│   │   ├── binary_resolver.dart
│   │   └── process_runner.dart
│   ├── presentation/
│   │   ├── app.dart
│   │   ├── screens/          # editor_screen.dart, startup_screen.dart
│   │   ├── widgets/          # chapter_list.dart, metadata_form.dart, cover_panel.dart, playback_controls.dart
│   │   └── providers/        # editor_state.dart, playback.dart
│   └── main.dart
├── test/
│   ├── domain/
│   ├── data/
│   ├── presentation/
│   └── fixtures/             # golden ffprobe JSON, sample.m4b
├── tool/
│   └── fetch_ffmpeg.dart     # build-time binary downloader
├── assets/
│   └── bin/                  # populated by fetch_ffmpeg.dart at build time
└── pubspec.yaml
```

## Key packages

| Concern | Package | Reason |
|---|---|---|
| State management | `flutter_riverpod` 2.x | Override-based DI gives trivial test seams without codegen |
| Audio playback | `just_audio` | Mature, supports macOS/Windows/Linux desktop |
| File picker | `file_picker` | Cross-desktop file open/save dialogs |
| Subprocess | `dart:io` `Process.run` | Built-in, sufficient |
| Mocking | `mocktail` | Null-safe, no codegen, simpler than mockito |

## Open items for the implementation plan

- Final naming for `Bookbinder` / `FfmpegBookbinder` (the user has noted these may be revised)
- The exact ffmpeg version to pin and the SHA-256 of each platform binary
- Concrete fixture m4b generation steps (commands and inputs)
