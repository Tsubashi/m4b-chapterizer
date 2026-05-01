# m4b-chapterizer MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter desktop GUI that opens an `.m4b` audiobook file, displays its text metadata / cover art / chapters, lets the user edit them with audio-assisted chapter timing, and writes the result back to the file system.

**Architecture:** Three layers — `domain/` (pure-Dart models and the `Bookbinder` interface), `data/` (the `FfmpegBookbinder` that shells out to bundled `ffmpeg`/`ffprobe`), and `presentation/` (Flutter widgets + Riverpod state). Each layer is built test-first.

**Tech Stack:** Flutter 3.x desktop, Dart 3.x, `flutter_riverpod` 2.x for state, `just_audio` for playback, `file_picker` for dialogs, `mocktail` for test fakes, bundled `ffmpeg` 7.1 for m4b read/write.

**Reference design:** `docs/superpowers/specs/2026-04-30-m4b-chapterizer-mvp-design.md`

**Conventions throughout this plan:**
- Every `git commit` invocation must include `--no-gpg-sign` (the user's signing setup blocks Claude with a GUI prompt).
- All test commands use `flutter test`. Run a single test with `flutter test path/to/test.dart -p chrome` is **not** what we want; for unit/widget tests use `flutter test path/to/test.dart -r expanded` to get verbose output.
- After every task, run the full suite (`flutter test`) before committing to confirm no regressions.

---

## Phase 1 — Bootstrap

### Task 1: Initialize Flutter project and verify baseline

**Files:**
- Create: `pubspec.yaml`, `analysis_options.yaml`, `.gitignore`, `lib/main.dart`, `test/widget_test.dart`, plus the rest of the standard `flutter create` output
- Modify: `.gitignore` (add `assets/bin/` so downloaded ffmpeg binaries aren't committed)

- [ ] **Step 1: Run `flutter create`**

```bash
cd /Users/cscott/Projects/m4b-chapterizer
flutter create --project-name m4b_chapterizer --platforms=macos,windows,linux --org com.aquaveo .
```

Expected: a fresh Flutter desktop project scaffolded into the existing directory, leaving `docs/` untouched.

- [ ] **Step 2: Add dependencies**

Edit `pubspec.yaml` and add under `dependencies`:

```yaml
  flutter_riverpod: ^2.5.0
  just_audio: ^0.9.36
  file_picker: ^8.0.0
  path: ^1.9.0
  collection: ^1.18.0
```

Add under `dev_dependencies`:

```yaml
  mocktail: ^1.0.3
```

Then run:

```bash
flutter pub get
```

Expected: dependencies resolve cleanly.

- [ ] **Step 3: Tighten lint rules**

Replace the contents of `analysis_options.yaml` with:

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  errors:
    invalid_annotation_target: ignore

linter:
  rules:
    - prefer_const_constructors
    - prefer_final_locals
    - avoid_print
    - require_trailing_commas
```

- [ ] **Step 4: Append asset-bin ignore to .gitignore**

Append the following line to `.gitignore`:

```
/assets/bin/
```

- [ ] **Step 5: Replace the default smoke test with a sentinel that proves the harness is wired up**

Replace `test/widget_test.dart` contents with:

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test harness is wired up', () {
    expect(2 + 2, 4);
  });
}
```

- [ ] **Step 6: Verify `flutter test` passes**

Run: `flutter test`
Expected: `00:0X +1: All tests passed!`

- [ ] **Step 7: Commit**

```bash
git add -A
git commit --no-gpg-sign -m "Bootstrap Flutter desktop project with deps and lint config"
```

---

## Phase 2 — Domain models

### Task 2: `Chapter` value type

**Files:**
- Create: `lib/domain/models/chapter.dart`
- Test: `test/domain/chapter_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/domain/chapter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';

void main() {
  group('Chapter', () {
    test('exposes its title and start time', () {
      const chapter = Chapter(title: 'Prologue', start: Duration.zero);
      expect(chapter.title, 'Prologue');
      expect(chapter.start, Duration.zero);
    });

    test('is value-equal when fields match', () {
      const a = Chapter(title: 'C1', start: Duration(seconds: 5));
      const b = Chapter(title: 'C1', start: Duration(seconds: 5));
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith overrides only the supplied fields', () {
      const original = Chapter(title: 'A', start: Duration(seconds: 10));
      final renamed = original.copyWith(title: 'B');
      expect(renamed.title, 'B');
      expect(renamed.start, const Duration(seconds: 10));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/chapter_test.dart`
Expected: FAIL with "Target of URI doesn't exist".

- [ ] **Step 3: Implement `Chapter`**

Create `lib/domain/models/chapter.dart`:

```dart
import 'package:meta/meta.dart';

@immutable
class Chapter {
  const Chapter({required this.title, required this.start});

  final String title;
  final Duration start;

  Chapter copyWith({String? title, Duration? start}) =>
      Chapter(title: title ?? this.title, start: start ?? this.start);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Chapter && other.title == title && other.start == start;

  @override
  int get hashCode => Object.hash(title, start);

  @override
  String toString() => 'Chapter(title: $title, start: $start)';
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/domain/chapter_test.dart`
Expected: `+3: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/domain/models/chapter.dart test/domain/chapter_test.dart
git commit --no-gpg-sign -m "Add Chapter value type"
```

---

### Task 3: `Cover` value type

**Files:**
- Create: `lib/domain/models/cover.dart`
- Test: `test/domain/cover_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/domain/cover_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/models/cover.dart';

void main() {
  group('Cover', () {
    test('exposes bytes and mime type', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final cover = Cover(bytes: bytes, mimeType: 'image/png');
      expect(cover.bytes, bytes);
      expect(cover.mimeType, 'image/png');
    });

    test('is value-equal when bytes and mime type match', () {
      final a = Cover(bytes: Uint8List.fromList([1, 2]), mimeType: 'image/jpeg');
      final b = Cover(bytes: Uint8List.fromList([1, 2]), mimeType: 'image/jpeg');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('rejects unsupported mime types', () {
      expect(
        () => Cover(
          bytes: Uint8List.fromList([0]),
          mimeType: 'image/gif',
        ),
        throwsArgumentError,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/cover_test.dart`
Expected: FAIL — "Target of URI doesn't exist".

- [ ] **Step 3: Implement `Cover`**

Create `lib/domain/models/cover.dart`:

```dart
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

@immutable
class Cover {
  Cover({required this.bytes, required this.mimeType}) {
    if (mimeType != 'image/png' && mimeType != 'image/jpeg') {
      throw ArgumentError.value(
        mimeType,
        'mimeType',
        'must be image/png or image/jpeg',
      );
    }
  }

  final Uint8List bytes;
  final String mimeType;

  static const _eq = ListEquality<int>();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Cover &&
          other.mimeType == mimeType &&
          _eq.equals(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(mimeType, _eq.hash(bytes));
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/domain/cover_test.dart`
Expected: `+3: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/domain/models/cover.dart test/domain/cover_test.dart
git commit --no-gpg-sign -m "Add Cover value type"
```

---

### Task 4: `Audiobook` aggregate

**Files:**
- Create: `lib/domain/models/audiobook.dart`
- Test: `test/domain/audiobook_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/domain/audiobook_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';

void main() {
  group('Audiobook', () {
    const totalDuration = Duration(minutes: 30);
    const chapter1 = Chapter(title: 'One', start: Duration.zero);
    const chapter2 = Chapter(title: 'Two', start: Duration(minutes: 10));
    const chapter3 = Chapter(title: 'Three', start: Duration(minutes: 20));

    test('exposes its fields', () {
      const book = Audiobook(
        title: 'A Book',
        author: 'Some Author',
        narrator: 'A Narrator',
        chapters: [chapter1, chapter2],
        totalDuration: totalDuration,
      );
      expect(book.title, 'A Book');
      expect(book.author, 'Some Author');
      expect(book.narrator, 'A Narrator');
      expect(book.chapters, [chapter1, chapter2]);
      expect(book.totalDuration, totalDuration);
    });

    test('endOf returns the next chapter start time', () {
      const book = Audiobook(
        chapters: [chapter1, chapter2, chapter3],
        totalDuration: totalDuration,
      );
      expect(book.endOf(0), const Duration(minutes: 10));
      expect(book.endOf(1), const Duration(minutes: 20));
    });

    test('endOf for the last chapter returns the total duration', () {
      const book = Audiobook(
        chapters: [chapter1, chapter2, chapter3],
        totalDuration: totalDuration,
      );
      expect(book.endOf(2), totalDuration);
    });

    test('rejects empty chapter list', () {
      expect(
        () => const Audiobook(chapters: [], totalDuration: totalDuration),
        throwsArgumentError,
      );
    });

    test('rejects non-monotonic chapter starts', () {
      expect(
        () => Audiobook(
          chapters: const [
            Chapter(title: 'A', start: Duration(minutes: 5)),
            Chapter(title: 'B', start: Duration(minutes: 3)),
          ],
          totalDuration: totalDuration,
        ),
        throwsArgumentError,
      );
    });

    test('rejects chapter start past total duration', () {
      expect(
        () => Audiobook(
          chapters: const [Chapter(title: 'A', start: Duration(minutes: 31))],
          totalDuration: totalDuration,
        ),
        throwsArgumentError,
      );
    });

    test('copyWith updates only the supplied fields', () {
      const original = Audiobook(
        title: 'A',
        chapters: [chapter1],
        totalDuration: totalDuration,
      );
      final updated = original.copyWith(title: 'B');
      expect(updated.title, 'B');
      expect(updated.chapters, [chapter1]);
      expect(updated.totalDuration, totalDuration);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/audiobook_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `Audiobook`**

Create `lib/domain/models/audiobook.dart`:

```dart
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'chapter.dart';
import 'cover.dart';

@immutable
class Audiobook {
  const Audiobook({
    required this.chapters,
    required this.totalDuration,
    this.title,
    this.author,
    this.narrator,
    this.album,
    this.genre,
    this.description,
    this.year,
    this.cover,
  });

  final String? title;
  final String? author;
  final String? narrator;
  final String? album;
  final String? genre;
  final String? description;
  final int? year;
  final Cover? cover;
  final List<Chapter> chapters;
  final Duration totalDuration;

  factory Audiobook.validated({
    required List<Chapter> chapters,
    required Duration totalDuration,
    String? title,
    String? author,
    String? narrator,
    String? album,
    String? genre,
    String? description,
    int? year,
    Cover? cover,
  }) {
    _validate(chapters, totalDuration);
    return Audiobook(
      chapters: List.unmodifiable(chapters),
      totalDuration: totalDuration,
      title: title,
      author: author,
      narrator: narrator,
      album: album,
      genre: genre,
      description: description,
      year: year,
      cover: cover,
    );
  }

  /// End time of [index] — the start of the next chapter, or [totalDuration]
  /// for the final chapter.
  Duration endOf(int index) {
    if (index < 0 || index >= chapters.length) {
      throw RangeError.index(index, chapters);
    }
    if (index == chapters.length - 1) return totalDuration;
    return chapters[index + 1].start;
  }

  Audiobook copyWith({
    String? title,
    String? author,
    String? narrator,
    String? album,
    String? genre,
    String? description,
    int? year,
    Cover? cover,
    List<Chapter>? chapters,
    Duration? totalDuration,
    bool clearCover = false,
  }) {
    return Audiobook(
      title: title ?? this.title,
      author: author ?? this.author,
      narrator: narrator ?? this.narrator,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      description: description ?? this.description,
      year: year ?? this.year,
      cover: clearCover ? null : (cover ?? this.cover),
      chapters: chapters ?? this.chapters,
      totalDuration: totalDuration ?? this.totalDuration,
    );
  }

  static void _validate(List<Chapter> chapters, Duration totalDuration) {
    if (chapters.isEmpty) {
      throw ArgumentError.value(chapters, 'chapters', 'must not be empty');
    }
    if (chapters.first.start != Duration.zero) {
      throw ArgumentError.value(
        chapters,
        'chapters',
        'first chapter must start at Duration.zero',
      );
    }
    for (var i = 1; i < chapters.length; i++) {
      if (chapters[i].start <= chapters[i - 1].start) {
        throw ArgumentError.value(
          chapters,
          'chapters',
          'chapter starts must be strictly increasing',
        );
      }
    }
    if (chapters.last.start >= totalDuration) {
      throw ArgumentError.value(
        chapters,
        'chapters',
        'last chapter start must be before totalDuration',
      );
    }
  }

  static const _chapterEq = ListEquality<Chapter>();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Audiobook &&
          other.title == title &&
          other.author == author &&
          other.narrator == narrator &&
          other.album == album &&
          other.genre == genre &&
          other.description == description &&
          other.year == year &&
          other.cover == cover &&
          other.totalDuration == totalDuration &&
          _chapterEq.equals(other.chapters, chapters);

  @override
  int get hashCode => Object.hash(
        title,
        author,
        narrator,
        album,
        genre,
        description,
        year,
        cover,
        totalDuration,
        _chapterEq.hash(chapters),
      );
}
```

Note: the four "rejects" tests in Step 1 construct invalid books via `Audiobook.validated` rather than `const Audiobook(...)` to exercise validation. Update the test to call `Audiobook.validated(...)` for the three rejection cases.

- [ ] **Step 4: Update validation tests to call `Audiobook.validated`**

In `test/domain/audiobook_test.dart`, change the three rejection tests so they use `Audiobook.validated(...)` (with non-`const`) instead of `const Audiobook(...)`. The first three "exposes its fields" / "endOf" tests remain `const Audiobook(...)`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/domain/audiobook_test.dart`
Expected: `+7: All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/domain/models/audiobook.dart test/domain/audiobook_test.dart
git commit --no-gpg-sign -m "Add Audiobook aggregate with chapter validation"
```

---

### Task 5: `Bookbinder` abstract interface

**Files:**
- Create: `lib/domain/bookbinder.dart`

(No test — this is a pure interface definition. It will be exercised by the data-layer tests in Phase 5.)

- [ ] **Step 1: Implement the interface**

Create `lib/domain/bookbinder.dart`:

```dart
import 'models/audiobook.dart';

/// Reads and writes m4b audiobooks. The data layer provides an implementation
/// (`FfmpegBookbinder`); tests substitute a fake.
abstract class Bookbinder {
  /// Reads the m4b at [sourcePath] and returns a populated [Audiobook].
  Future<Audiobook> read(String sourcePath);

  /// Writes [audiobook] to [destinationPath], using [sourcePath] as the audio
  /// source. The audio stream is copied; only metadata and chapters change.
  /// Writes are atomic: if the operation fails, [destinationPath] is untouched.
  Future<void> write({
    required String sourcePath,
    required String destinationPath,
    required Audiobook audiobook,
  });
}
```

- [ ] **Step 2: Verify it analyzes cleanly**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/domain/bookbinder.dart
git commit --no-gpg-sign -m "Add Bookbinder abstract interface"
```

---

## Phase 3 — Data codecs

### Task 6: ffmetadata text codec — encode

**Files:**
- Create: `lib/data/ffmetadata_codec.dart`
- Test: `test/data/ffmetadata_codec_test.dart`
- Test fixture: `test/fixtures/ffmetadata_sample.txt`

- [ ] **Step 1: Add the golden fixture**

Create `test/fixtures/ffmetadata_sample.txt`:

```
;FFMETADATA1
title=A Test Book
artist=Test Author
composer=Test Narrator
album=Test Series
genre=Audiobook
date=2026
comment=A short test description
[CHAPTER]
TIMEBASE=1/1000
START=0
END=10000
title=One
[CHAPTER]
TIMEBASE=1/1000
START=10000
END=20000
title=Two
[CHAPTER]
TIMEBASE=1/1000
START=20000
END=30000
title=Three
```

- [ ] **Step 2: Write the failing encode test**

Create `test/data/ffmetadata_codec_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/ffmetadata_codec.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';

void main() {
  final goldenText = File('test/fixtures/ffmetadata_sample.txt')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  final book = Audiobook.validated(
    title: 'A Test Book',
    author: 'Test Author',
    narrator: 'Test Narrator',
    album: 'Test Series',
    genre: 'Audiobook',
    description: 'A short test description',
    year: 2026,
    chapters: const [
      Chapter(title: 'One', start: Duration.zero),
      Chapter(title: 'Two', start: Duration(seconds: 10)),
      Chapter(title: 'Three', start: Duration(seconds: 20)),
    ],
    totalDuration: const Duration(seconds: 30),
  );

  group('FfmetadataCodec.encode', () {
    test('encodes an Audiobook to ffmetadata text matching the golden file',
        () {
      const codec = FfmetadataCodec();
      expect(codec.encode(book), goldenText);
    });

    test('omits unset metadata fields', () {
      const codec = FfmetadataCodec();
      final stripped = Audiobook.validated(
        chapters: const [Chapter(title: 'Only', start: Duration.zero)],
        totalDuration: const Duration(seconds: 5),
      );
      final encoded = codec.encode(stripped);
      expect(encoded, contains(';FFMETADATA1'));
      expect(encoded, isNot(contains('title=')));
      expect(encoded, isNot(contains('artist=')));
      expect(encoded, contains('[CHAPTER]'));
    });

    test('escapes the four ffmetadata special characters', () {
      const codec = FfmetadataCodec();
      final book = Audiobook.validated(
        title: r'a=b;c#d\e\nf',
        chapters: const [Chapter(title: 'C1', start: Duration.zero)],
        totalDuration: const Duration(seconds: 1),
      );
      final encoded = codec.encode(book);
      expect(encoded, contains(r'title=a\=b\;c\#d\\e\\nf'));
    });
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/data/ffmetadata_codec_test.dart`
Expected: FAIL — "Target of URI doesn't exist".

- [ ] **Step 4: Implement encode (decode comes in Task 7)**

Create `lib/data/ffmetadata_codec.dart`:

```dart
import '../domain/models/audiobook.dart';

/// Encodes/decodes the ffmpeg `ffmetadata` text format.
///
/// Spec: https://ffmpeg.org/ffmpeg-formats.html#Metadata-2
class FfmetadataCodec {
  const FfmetadataCodec();

  static const _header = ';FFMETADATA1';

  /// ffmetadata reserves these four characters; they must be backslash-escaped
  /// in keys and values: `=`, `;`, `#`, `\`. Newlines are also escaped.
  static String _escape(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('=', r'\=')
      .replaceAll(';', r'\;')
      .replaceAll('#', r'\#')
      .replaceAll('\n', r'\n');

  String encode(Audiobook book) {
    final buffer = StringBuffer()..writeln(_header);
    void writeIfPresent(String key, String? value) {
      if (value == null || value.isEmpty) return;
      buffer.writeln('$key=${_escape(value)}');
    }

    writeIfPresent('title', book.title);
    writeIfPresent('artist', book.author);
    writeIfPresent('composer', book.narrator);
    writeIfPresent('album', book.album);
    writeIfPresent('genre', book.genre);
    if (book.year != null) buffer.writeln('date=${book.year}');
    writeIfPresent('comment', book.description);

    for (var i = 0; i < book.chapters.length; i++) {
      final chapter = book.chapters[i];
      final endMs = book.endOf(i).inMilliseconds;
      buffer
        ..writeln('[CHAPTER]')
        ..writeln('TIMEBASE=1/1000')
        ..writeln('START=${chapter.start.inMilliseconds}')
        ..writeln('END=$endMs')
        ..writeln('title=${_escape(chapter.title)}');
    }

    return buffer.toString();
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/data/ffmetadata_codec_test.dart`
Expected: `+3: All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/data/ffmetadata_codec.dart test/data/ffmetadata_codec_test.dart test/fixtures/ffmetadata_sample.txt
git commit --no-gpg-sign -m "Add ffmetadata codec encode path"
```

---

### Task 7: ffmetadata text codec — decode

**Files:**
- Modify: `lib/data/ffmetadata_codec.dart`
- Modify: `test/data/ffmetadata_codec_test.dart`

- [ ] **Step 1: Add failing decode test**

Append to `test/data/ffmetadata_codec_test.dart` inside the existing `main()` (after the encode group):

```dart
  group('FfmetadataCodec.decode', () {
    test('round-trips an Audiobook through encode and decode', () {
      const codec = FfmetadataCodec();
      final book = Audiobook.validated(
        title: 'A Test Book',
        author: 'Test Author',
        narrator: 'Test Narrator',
        album: 'Test Series',
        genre: 'Audiobook',
        description: 'A short test description',
        year: 2026,
        chapters: const [
          Chapter(title: 'One', start: Duration.zero),
          Chapter(title: 'Two', start: Duration(seconds: 10)),
          Chapter(title: 'Three', start: Duration(seconds: 20)),
        ],
        totalDuration: const Duration(seconds: 30),
      );

      final encoded = codec.encode(book);
      final decoded = codec.decode(encoded);

      expect(decoded.title, book.title);
      expect(decoded.author, book.author);
      expect(decoded.narrator, book.narrator);
      expect(decoded.album, book.album);
      expect(decoded.genre, book.genre);
      expect(decoded.description, book.description);
      expect(decoded.year, book.year);
      expect(decoded.chapters, book.chapters);
      expect(decoded.totalDuration, book.totalDuration);
    });

    test('decodes the golden file', () {
      const codec = FfmetadataCodec();
      final goldenText = File('test/fixtures/ffmetadata_sample.txt')
          .readAsStringSync();
      final decoded = codec.decode(goldenText);
      expect(decoded.title, 'A Test Book');
      expect(decoded.chapters.length, 3);
      expect(decoded.chapters[0].title, 'One');
      expect(decoded.totalDuration, const Duration(seconds: 30));
    });

    test('round-trips escape sequences', () {
      const codec = FfmetadataCodec();
      final book = Audiobook.validated(
        title: r'a=b;c#d\e',
        chapters: const [Chapter(title: 'C1', start: Duration.zero)],
        totalDuration: const Duration(seconds: 1),
      );
      final decoded = codec.decode(codec.encode(book));
      expect(decoded.title, r'a=b;c#d\e');
    });

    test('rejects input without the FFMETADATA1 header', () {
      const codec = FfmetadataCodec();
      expect(() => codec.decode('title=Foo'), throwsFormatException);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/ffmetadata_codec_test.dart`
Expected: FAIL — `decode` not defined.

- [ ] **Step 3: Implement decode**

Append to `lib/data/ffmetadata_codec.dart` inside the `FfmetadataCodec` class:

```dart
  /// Parses ffmetadata text and reconstructs an [Audiobook].
  ///
  /// The input must start with [_header]. The total duration is derived from
  /// the END timestamp of the last chapter.
  Audiobook decode(String text) {
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty || lines.first.trim() != _header) {
      throw const FormatException('Input is not ffmetadata: missing header');
    }

    final globalFields = <String, String>{};
    final chapterBlocks = <Map<String, String>>[];
    Map<String, String>? currentChapter;

    for (var i = 1; i < lines.length; i++) {
      final raw = lines[i];
      if (raw.isEmpty || raw.startsWith(';')) continue;
      if (raw.trim() == '[CHAPTER]') {
        currentChapter = <String, String>{};
        chapterBlocks.add(currentChapter);
        continue;
      }
      final pair = _parseKeyValue(raw);
      if (pair == null) continue;
      if (currentChapter != null) {
        currentChapter[pair.$1] = pair.$2;
      } else {
        globalFields[pair.$1] = pair.$2;
      }
    }

    if (chapterBlocks.isEmpty) {
      throw const FormatException('ffmetadata contains no chapters');
    }

    final chapters = <_ParsedChapter>[];
    for (final block in chapterBlocks) {
      final timebase = block['TIMEBASE'] ?? '1/1000';
      final divisor = _parseTimebaseDivisor(timebase);
      final startUnits = int.parse(block['START'] ?? '0');
      final endUnits = int.parse(block['END'] ?? '0');
      chapters.add(_ParsedChapter(
        title: block['title'] ?? '',
        start: Duration(milliseconds: startUnits * 1000 ~/ divisor),
        end: Duration(milliseconds: endUnits * 1000 ~/ divisor),
      ));
    }

    final totalDuration = chapters.last.end;

    return Audiobook.validated(
      title: globalFields['title'],
      author: globalFields['artist'],
      narrator: globalFields['composer'],
      album: globalFields['album'],
      genre: globalFields['genre'],
      description: globalFields['comment'],
      year: int.tryParse(globalFields['date'] ?? ''),
      chapters: [
        for (final c in chapters) Chapter(title: c.title, start: c.start),
      ],
      totalDuration: totalDuration,
    );
  }

  static (String, String)? _parseKeyValue(String line) {
    final buffer = StringBuffer();
    var i = 0;
    String? key;
    while (i < line.length) {
      final ch = line[i];
      if (ch == r'\' && i + 1 < line.length) {
        final next = line[i + 1];
        buffer.write(next == 'n' ? '\n' : next);
        i += 2;
        continue;
      }
      if (ch == '=' && key == null) {
        key = buffer.toString();
        buffer.clear();
        i++;
        continue;
      }
      buffer.write(ch);
      i++;
    }
    if (key == null) return null;
    return (key, buffer.toString());
  }

  static int _parseTimebaseDivisor(String timebase) {
    final parts = timebase.split('/');
    if (parts.length != 2) {
      throw FormatException('Invalid TIMEBASE: $timebase');
    }
    return int.parse(parts[1]);
  }
}

class _ParsedChapter {
  _ParsedChapter({required this.title, required this.start, required this.end});
  final String title;
  final Duration start;
  final Duration end;
```

Also add at the top of `lib/data/ffmetadata_codec.dart`:

```dart
import 'dart:convert';
```

And update the imports at the top of `test/data/ffmetadata_codec_test.dart` to include:

```dart
import 'dart:io';
```

(may already be present from Task 6).

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/ffmetadata_codec_test.dart`
Expected: All 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/data/ffmetadata_codec.dart test/data/ffmetadata_codec_test.dart
git commit --no-gpg-sign -m "Add ffmetadata codec decode path with round-trip"
```

---

### Task 8: ffprobe JSON codec

**Files:**
- Create: `lib/data/ffprobe_codec.dart`
- Test: `test/data/ffprobe_codec_test.dart`
- Fixture: `test/fixtures/ffprobe_sample.json`

- [ ] **Step 1: Add the golden ffprobe JSON fixture**

Create `test/fixtures/ffprobe_sample.json`:

```json
{
  "streams": [
    {
      "index": 0,
      "codec_type": "audio",
      "codec_name": "aac"
    },
    {
      "index": 1,
      "codec_type": "video",
      "codec_name": "mjpeg",
      "disposition": { "attached_pic": 1 }
    }
  ],
  "chapters": [
    {
      "id": 0,
      "time_base": "1/1000",
      "start": 0,
      "start_time": "0.000000",
      "end": 10000,
      "end_time": "10.000000",
      "tags": { "title": "One" }
    },
    {
      "id": 1,
      "time_base": "1/1000",
      "start": 10000,
      "start_time": "10.000000",
      "end": 20000,
      "end_time": "20.000000",
      "tags": { "title": "Two" }
    },
    {
      "id": 2,
      "time_base": "1/1000",
      "start": 20000,
      "start_time": "20.000000",
      "end": 30000,
      "end_time": "30.000000",
      "tags": { "title": "Three" }
    }
  ],
  "format": {
    "filename": "/tmp/sample.m4b",
    "duration": "30.000000",
    "tags": {
      "title": "A Test Book",
      "artist": "Test Author",
      "composer": "Test Narrator",
      "album": "Test Series",
      "genre": "Audiobook",
      "date": "2026",
      "comment": "A short test description"
    }
  }
}
```

- [ ] **Step 2: Write the failing test**

Create `test/data/ffprobe_codec_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/ffprobe_codec.dart';

void main() {
  group('FfprobeCodec.decode', () {
    final goldenJson =
        File('test/fixtures/ffprobe_sample.json').readAsStringSync();

    test('decodes the golden ffprobe output into a populated Audiobook', () {
      const codec = FfprobeCodec();
      final result = codec.decode(goldenJson);
      expect(result.audiobook.title, 'A Test Book');
      expect(result.audiobook.author, 'Test Author');
      expect(result.audiobook.narrator, 'Test Narrator');
      expect(result.audiobook.album, 'Test Series');
      expect(result.audiobook.genre, 'Audiobook');
      expect(result.audiobook.year, 2026);
      expect(result.audiobook.description, 'A short test description');
      expect(result.audiobook.chapters.length, 3);
      expect(result.audiobook.chapters[0].title, 'One');
      expect(result.audiobook.chapters[0].start, Duration.zero);
      expect(result.audiobook.chapters[1].start, const Duration(seconds: 10));
      expect(result.audiobook.totalDuration, const Duration(seconds: 30));
      expect(result.hasAttachedCover, isTrue);
    });

    test('reports no attached cover when no video stream is present', () {
      const codec = FfprobeCodec();
      final result = codec.decode('''
{
  "streams": [{"index": 0, "codec_type": "audio"}],
  "chapters": [
    {"time_base": "1/1000", "start": 0, "end": 1000, "tags": {"title": "C"}}
  ],
  "format": {"duration": "1.000000", "tags": {}}
}''');
      expect(result.hasAttachedCover, isFalse);
    });

    test('falls back to format.duration when chapters are missing', () {
      const codec = FfprobeCodec();
      expect(
        () => codec.decode('''
{
  "streams": [{"index": 0, "codec_type": "audio"}],
  "chapters": [],
  "format": {"duration": "10.000000", "tags": {}}
}'''),
        throwsFormatException,
      );
    });
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/data/ffprobe_codec_test.dart`
Expected: FAIL.

- [ ] **Step 4: Implement `FfprobeCodec`**

Create `lib/data/ffprobe_codec.dart`:

```dart
import 'dart:convert';

import '../domain/models/audiobook.dart';
import '../domain/models/chapter.dart';

class FfprobeResult {
  const FfprobeResult({required this.audiobook, required this.hasAttachedCover});

  final Audiobook audiobook;
  final bool hasAttachedCover;
}

class FfprobeCodec {
  const FfprobeCodec();

  FfprobeResult decode(String json) {
    final root = jsonDecode(json) as Map<String, dynamic>;
    final streams = (root['streams'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final chaptersJson =
        (root['chapters'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final format = (root['format'] as Map<String, dynamic>?) ?? const {};
    final formatTags =
        (format['tags'] as Map<String, dynamic>?)?.cast<String, dynamic>() ??
            const {};

    if (chaptersJson.isEmpty) {
      throw const FormatException(
        'ffprobe output contains no chapters; m4b without chapters is not '
        'supported in MVP',
      );
    }

    final chapters = <Chapter>[];
    Duration lastEnd = Duration.zero;
    for (final block in chaptersJson) {
      final timebase = block['time_base'] as String? ?? '1/1000';
      final divisor = _parseTimebaseDivisor(timebase);
      final startUnits = (block['start'] as num).toInt();
      final endUnits = (block['end'] as num).toInt();
      final tags = (block['tags'] as Map<String, dynamic>?) ?? const {};
      chapters.add(Chapter(
        title: tags['title'] as String? ?? '',
        start: Duration(milliseconds: startUnits * 1000 ~/ divisor),
      ));
      lastEnd = Duration(milliseconds: endUnits * 1000 ~/ divisor);
    }

    final hasAttachedCover = streams.any((s) {
      if (s['codec_type'] != 'video') return false;
      final disposition =
          (s['disposition'] as Map<String, dynamic>?) ?? const {};
      return (disposition['attached_pic'] as num?)?.toInt() == 1;
    });

    return FfprobeResult(
      audiobook: Audiobook.validated(
        title: formatTags['title'] as String?,
        author: formatTags['artist'] as String?,
        narrator: formatTags['composer'] as String?,
        album: formatTags['album'] as String?,
        genre: formatTags['genre'] as String?,
        description: formatTags['comment'] as String?,
        year: int.tryParse(formatTags['date'] as String? ?? ''),
        chapters: chapters,
        totalDuration: lastEnd,
      ),
      hasAttachedCover: hasAttachedCover,
    );
  }

  static int _parseTimebaseDivisor(String timebase) {
    final parts = timebase.split('/');
    if (parts.length != 2) {
      throw FormatException('Invalid time_base: $timebase');
    }
    return int.parse(parts[1]);
  }
}
```

- [ ] **Step 5: Run tests**

Run: `flutter test test/data/ffprobe_codec_test.dart`
Expected: `+3: All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/data/ffprobe_codec.dart test/data/ffprobe_codec_test.dart test/fixtures/ffprobe_sample.json
git commit --no-gpg-sign -m "Add ffprobe JSON codec"
```

---

## Phase 4 — Process plumbing

### Task 9: `ProcessRunner`

**Files:**
- Create: `lib/data/process_runner.dart`
- Test: `test/data/process_runner_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/data/process_runner_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/process_runner.dart';

void main() {
  group('SystemProcessRunner', () {
    test('runs an executable and captures stdout/stderr/exitCode', () async {
      const runner = SystemProcessRunner();
      final result = await runner.run(
        executable: Platform.isWindows ? 'cmd' : 'sh',
        arguments: Platform.isWindows
            ? const ['/c', 'echo hello']
            : const ['-c', 'echo hello'],
      );
      expect(result.exitCode, 0);
      expect(result.stdout.trim(), 'hello');
    });

    test('returns nonzero exit code for failing commands', () async {
      const runner = SystemProcessRunner();
      final result = await runner.run(
        executable: Platform.isWindows ? 'cmd' : 'sh',
        arguments: Platform.isWindows
            ? const ['/c', 'exit 7']
            : const ['-c', 'exit 7'],
      );
      expect(result.exitCode, 7);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/process_runner_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `ProcessRunner` and `SystemProcessRunner`**

Create `lib/data/process_runner.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class ProcessOutput {
  const ProcessOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.stdoutBytes,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final Uint8List stdoutBytes;
}

abstract class ProcessRunner {
  Future<ProcessOutput> run({
    required String executable,
    required List<String> arguments,
  });
}

class SystemProcessRunner implements ProcessRunner {
  const SystemProcessRunner();

  @override
  Future<ProcessOutput> run({
    required String executable,
    required List<String> arguments,
  }) async {
    final result = await Process.run(
      executable,
      arguments,
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    final stdoutBytes = result.stdout as List<int>;
    final stderrBytes = result.stderr as List<int>;
    return ProcessOutput(
      exitCode: result.exitCode,
      stdout: utf8.decode(stdoutBytes, allowMalformed: true),
      stderr: utf8.decode(stderrBytes, allowMalformed: true),
      stdoutBytes: Uint8List.fromList(stdoutBytes),
    );
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/data/process_runner_test.dart`
Expected: `+2: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/data/process_runner.dart test/data/process_runner_test.dart
git commit --no-gpg-sign -m "Add ProcessRunner abstraction with system implementation"
```

---

### Task 10: `BinaryResolver`

**Files:**
- Create: `lib/data/binary_resolver.dart`
- Test: `test/data/binary_resolver_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/data/binary_resolver_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/binary_resolver.dart';

void main() {
  group('SystemBinaryResolver', () {
    test('resolves to the named binary on PATH', () {
      const resolver = SystemBinaryResolver();
      expect(resolver.ffmpeg, 'ffmpeg');
      expect(resolver.ffprobe, 'ffprobe');
    });
  });

  group('FixedBinaryResolver', () {
    test('returns the explicit paths it was constructed with', () {
      const resolver = FixedBinaryResolver(
        ffmpeg: '/opt/ffmpeg/bin/ffmpeg',
        ffprobe: '/opt/ffmpeg/bin/ffprobe',
      );
      expect(resolver.ffmpeg, '/opt/ffmpeg/bin/ffmpeg');
      expect(resolver.ffprobe, '/opt/ffmpeg/bin/ffprobe');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/binary_resolver_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `lib/data/binary_resolver.dart`:

```dart
/// Locates the `ffmpeg` and `ffprobe` executables.
abstract class BinaryResolver {
  String get ffmpeg;
  String get ffprobe;
}

/// Relies on the OS to locate `ffmpeg` and `ffprobe` on `PATH`.
/// Used by tests, CI, and developer machines.
class SystemBinaryResolver implements BinaryResolver {
  const SystemBinaryResolver();

  @override
  String get ffmpeg => 'ffmpeg';

  @override
  String get ffprobe => 'ffprobe';
}

/// Returns explicit absolute paths. Used by `BundledBinaryResolver` (Phase 8)
/// and by tests that want full control.
class FixedBinaryResolver implements BinaryResolver {
  const FixedBinaryResolver({required this.ffmpeg, required this.ffprobe});

  @override
  final String ffmpeg;

  @override
  final String ffprobe;
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/data/binary_resolver_test.dart`
Expected: `+2: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/data/binary_resolver.dart test/data/binary_resolver_test.dart
git commit --no-gpg-sign -m "Add BinaryResolver with system and fixed implementations"
```

---

## Phase 5 — `FfmpegBookbinder`

### Task 11: Build the test fixture m4b

**Files:**
- Create: `tool/build_fixture.dart`
- Output (committed): `test/fixtures/sample.m4b`

The fixture is a ~10-second silent m4b with three chapters and a tiny PNG cover. The script uses `Process.run('ffmpeg', ...)` directly — it does not depend on any of the data-layer code we're testing. It is run **once by hand**; the resulting `sample.m4b` is checked in.

- [ ] **Step 1: Write `tool/build_fixture.dart`**

Create `tool/build_fixture.dart`:

```dart
// Generates test/fixtures/sample.m4b and test/fixtures/sample_cover.png.
// Run by hand once when the fixture needs to be (re)created:
//   dart run tool/build_fixture.dart
//
// Requires `ffmpeg` on PATH.

import 'dart:io';

const _metadata = '''
;FFMETADATA1
title=A Test Book
artist=Test Author
composer=Test Narrator
album=Test Series
genre=Audiobook
date=2026
comment=A short test description
[CHAPTER]
TIMEBASE=1/1000
START=0
END=10000
title=One
[CHAPTER]
TIMEBASE=1/1000
START=10000
END=20000
title=Two
[CHAPTER]
TIMEBASE=1/1000
START=20000
END=30000
title=Three
''';

Future<void> _runOrThrow(String exe, List<String> args) async {
  final result = await Process.run(exe, args);
  if (result.exitCode != 0) {
    throw StateError('$exe ${args.join(' ')} failed:\n${result.stderr}');
  }
}

Future<void> main() async {
  final tempDir = await Directory.systemTemp.createTemp('m4b-fixture-');
  try {
    final metadataPath = '${tempDir.path}/metadata.txt';
    final silentWavPath = '${tempDir.path}/silent.wav';
    final coverPath = 'test/fixtures/sample_cover.png';
    final outPath = 'test/fixtures/sample.m4b';

    await File(metadataPath).writeAsString(_metadata);

    // 30s of silence at 22050 Hz mono.
    await _runOrThrow('ffmpeg', [
      '-y',
      '-f', 'lavfi',
      '-i', 'anullsrc=channel_layout=mono:sample_rate=22050',
      '-t', '30',
      silentWavPath,
    ]);

    // 16x16 solid-colour PNG.
    await _runOrThrow('ffmpeg', [
      '-y',
      '-f', 'lavfi',
      '-i', 'color=c=red:s=16x16',
      '-frames:v', '1',
      coverPath,
    ]);

    // Encode to AAC + attach cover + apply chapter metadata.
    await _runOrThrow('ffmpeg', [
      '-y',
      '-i', silentWavPath,
      '-i', coverPath,
      '-i', metadataPath,
      '-map', '0:a',
      '-map', '1:v',
      '-map_metadata', '2',
      '-map_chapters', '2',
      '-c:a', 'aac',
      '-b:a', '32k',
      '-c:v', 'png',
      '-disposition:v:0', 'attached_pic',
      '-f', 'mp4',
      outPath,
    ]);

    stdout.writeln('Wrote $outPath');
  } finally {
    await tempDir.delete(recursive: true);
  }
}
```

- [ ] **Step 2: Run the script to produce the fixture**

```bash
dart run tool/build_fixture.dart
```

Expected: `Wrote test/fixtures/sample.m4b` and a non-zero-byte file at that path.

- [ ] **Step 3: Sanity-check the fixture with system ffprobe**

```bash
ffprobe -show_chapters -show_format -of json test/fixtures/sample.m4b | head -40
```

Expected: JSON containing 3 chapters with the titles "One", "Two", "Three".

- [ ] **Step 4: Commit the fixture and the script**

```bash
git add tool/build_fixture.dart test/fixtures/sample.m4b test/fixtures/sample_cover.png
git commit --no-gpg-sign -m "Add reproducible m4b test fixture"
```

---

### Task 12: `FfmpegBookbinder.read` — unit tests with mocked ProcessRunner

**Files:**
- Create: `lib/data/ffmpeg_bookbinder.dart`
- Test: `test/data/ffmpeg_bookbinder_test.dart`

- [ ] **Step 1: Write the failing read tests**

Create `test/data/ffmpeg_bookbinder_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:m4b_chapterizer/data/binary_resolver.dart';
import 'package:m4b_chapterizer/data/ffmpeg_bookbinder.dart';
import 'package:m4b_chapterizer/data/process_runner.dart';

class _MockProcessRunner extends Mock implements ProcessRunner {}

void main() {
  setUpAll(() {
    registerFallbackValue(const <String>[]);
  });

  late _MockProcessRunner runner;
  late FfmpegBookbinder bookbinder;

  setUp(() {
    runner = _MockProcessRunner();
    bookbinder = FfmpegBookbinder(
      runner: runner,
      binaries: const FixedBinaryResolver(
        ffmpeg: '/usr/bin/ffmpeg',
        ffprobe: '/usr/bin/ffprobe',
      ),
    );
  });

  group('FfmpegBookbinder.read', () {
    test('invokes ffprobe with the expected arguments', () async {
      final goldenJson =
          File('test/fixtures/ffprobe_sample.json').readAsStringSync();
      when(() => runner.run(
            executable: '/usr/bin/ffprobe',
            arguments: any(named: 'arguments'),
          )).thenAnswer((_) async => ProcessOutput(
            exitCode: 0,
            stdout: goldenJson,
            stderr: '',
            stdoutBytes: Uint8List.fromList(utf8.encode(goldenJson)),
          ));
      // No attached cover in this stub.
      when(() => runner.run(
            executable: '/usr/bin/ffmpeg',
            arguments: any(named: 'arguments'),
          )).thenAnswer((_) async => const ProcessOutput(
            exitCode: 1,
            stdout: '',
            stderr: 'no cover',
            stdoutBytes: Uint8List(0),
          ));

      final book = await bookbinder.read('/tmp/book.m4b');
      expect(book.title, 'A Test Book');
      expect(book.chapters.length, 3);

      verify(() => runner.run(
            executable: '/usr/bin/ffprobe',
            arguments: const [
              '-show_format',
              '-show_chapters',
              '-show_streams',
              '-of',
              'json',
              '-i',
              '/tmp/book.m4b',
            ],
          )).called(1);
    });

    test('extracts cover bytes when ffprobe reports an attached_pic stream',
        () async {
      final goldenJson =
          File('test/fixtures/ffprobe_sample.json').readAsStringSync();
      when(() => runner.run(
            executable: '/usr/bin/ffprobe',
            arguments: any(named: 'arguments'),
          )).thenAnswer((_) async => ProcessOutput(
            exitCode: 0,
            stdout: goldenJson,
            stderr: '',
            stdoutBytes: Uint8List.fromList(utf8.encode(goldenJson)),
          ));
      final fakeJpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      when(() => runner.run(
            executable: '/usr/bin/ffmpeg',
            arguments: any(named: 'arguments'),
          )).thenAnswer((_) async => ProcessOutput(
            exitCode: 0,
            stdout: '',
            stderr: '',
            stdoutBytes: fakeJpegBytes,
          ));

      final book = await bookbinder.read('/tmp/book.m4b');
      expect(book.cover, isNotNull);
      expect(book.cover!.bytes, fakeJpegBytes);
      expect(book.cover!.mimeType, 'image/jpeg');
    });

    test('throws BookbinderException when ffprobe returns a nonzero exit code',
        () async {
      when(() => runner.run(
            executable: any(named: 'executable'),
            arguments: any(named: 'arguments'),
          )).thenAnswer((_) async => const ProcessOutput(
            exitCode: 1,
            stdout: '',
            stderr: 'No such file',
            stdoutBytes: Uint8List(0),
          ));

      await expectLater(
        bookbinder.read('/tmp/missing.m4b'),
        throwsA(isA<BookbinderException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/ffmpeg_bookbinder_test.dart`
Expected: FAIL — `FfmpegBookbinder` not defined.

- [ ] **Step 3: Implement `FfmpegBookbinder` (read path only for now)**

Create `lib/data/ffmpeg_bookbinder.dart`:

```dart
import 'dart:typed_data';

import '../domain/bookbinder.dart';
import '../domain/models/audiobook.dart';
import '../domain/models/cover.dart';
import 'binary_resolver.dart';
import 'ffmpeg_invocation.dart' as inv;
import 'ffprobe_codec.dart';
import 'process_runner.dart';

class BookbinderException implements Exception {
  BookbinderException(this.message, {this.stderr});

  final String message;
  final String? stderr;

  @override
  String toString() =>
      'BookbinderException: $message${stderr == null ? '' : '\n$stderr'}';
}

class FfmpegBookbinder implements Bookbinder {
  FfmpegBookbinder({
    required ProcessRunner runner,
    required BinaryResolver binaries,
    FfprobeCodec ffprobeCodec = const FfprobeCodec(),
  })  : _runner = runner,
        _binaries = binaries,
        _ffprobe = ffprobeCodec;

  final ProcessRunner _runner;
  final BinaryResolver _binaries;
  final FfprobeCodec _ffprobe;

  @override
  Future<Audiobook> read(String sourcePath) async {
    final probeOutput = await _runner.run(
      executable: _binaries.ffprobe,
      arguments: inv.probeArguments(sourcePath),
    );
    if (probeOutput.exitCode != 0) {
      throw BookbinderException(
        'ffprobe failed for $sourcePath',
        stderr: probeOutput.stderr,
      );
    }
    final probe = _ffprobe.decode(probeOutput.stdout);
    if (!probe.hasAttachedCover) return probe.audiobook;
    final coverBytes = await _extractCover(sourcePath);
    if (coverBytes == null) return probe.audiobook;
    return probe.audiobook.copyWith(
      cover: Cover(bytes: coverBytes, mimeType: 'image/jpeg'),
    );
  }

  Future<Uint8List?> _extractCover(String sourcePath) async {
    final out = await _runner.run(
      executable: _binaries.ffmpeg,
      arguments: inv.extractCoverArguments(sourcePath),
    );
    if (out.exitCode != 0 || out.stdoutBytes.isEmpty) return null;
    return out.stdoutBytes;
  }

  @override
  Future<void> write({
    required String sourcePath,
    required String destinationPath,
    required Audiobook audiobook,
  }) {
    throw UnimplementedError('FfmpegBookbinder.write — Task 14');
  }
}
```

Also create `lib/data/ffmpeg_invocation.dart` (a small helper module so the argument lists can be unit-tested independently in Task 13/14):

```dart
List<String> probeArguments(String inputPath) => [
      '-show_format',
      '-show_chapters',
      '-show_streams',
      '-of',
      'json',
      '-i',
      inputPath,
    ];

List<String> extractCoverArguments(String inputPath) => [
      '-loglevel',
      'error',
      '-i',
      inputPath,
      '-map',
      '0:v',
      '-frames:v',
      '1',
      '-c',
      'copy',
      '-f',
      'image2',
      '-',
    ];

List<String> writeArguments({
  required String sourcePath,
  required String metadataPath,
  required String? coverPath,
  required String outputPath,
}) {
  final args = <String>[
    '-y',
    '-loglevel',
    'error',
    '-i',
    sourcePath,
    '-i',
    metadataPath,
    if (coverPath != null) ...['-i', coverPath],
    '-map',
    '0:a',
    if (coverPath != null) ...['-map', '2:v'],
    '-map_metadata',
    '1',
    '-map_chapters',
    '1',
    if (coverPath != null) ...['-disposition:v:0', 'attached_pic'],
    '-c',
    'copy',
    '-f',
    'mp4',
    outputPath,
  ];
  return args;
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/data/ffmpeg_bookbinder_test.dart`
Expected: `+3: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/data/ffmpeg_bookbinder.dart lib/data/ffmpeg_invocation.dart test/data/ffmpeg_bookbinder_test.dart
git commit --no-gpg-sign -m "Add FfmpegBookbinder.read with mocked process runner"
```

---

### Task 13: `FfmpegBookbinder.write` — unit tests with mocked ProcessRunner

**Files:**
- Modify: `lib/data/ffmpeg_bookbinder.dart`
- Modify: `test/data/ffmpeg_bookbinder_test.dart`

- [ ] **Step 1: Append failing write tests**

Append the following group inside `test/data/ffmpeg_bookbinder_test.dart`'s `main()` (after the read group):

```dart
  group('FfmpegBookbinder.write', () {
    final book = Audiobook.validated(
      title: 'New Title',
      author: 'New Author',
      chapters: const [
        Chapter(title: 'A', start: Duration.zero),
        Chapter(title: 'B', start: Duration(seconds: 5)),
      ],
      totalDuration: const Duration(seconds: 10),
    );

    test('invokes ffmpeg with -map_metadata, -map_chapters, and -c copy',
        () async {
      when(() => runner.run(
            executable: '/usr/bin/ffmpeg',
            arguments: any(named: 'arguments'),
          )).thenAnswer((_) async => const ProcessOutput(
            exitCode: 0,
            stdout: '',
            stderr: '',
            stdoutBytes: Uint8List(0),
          ));

      await bookbinder.write(
        sourcePath: '/tmp/in.m4b',
        destinationPath: '${Directory.systemTemp.path}/out.m4b',
        audiobook: book,
      );

      final captured = verify(() => runner.run(
            executable: '/usr/bin/ffmpeg',
            arguments: captureAny(named: 'arguments'),
          )).captured;
      final args = captured.single as List<String>;
      expect(args, contains('-map_metadata'));
      expect(args, contains('-map_chapters'));
      expect(args, contains('-c'));
      expect(args, contains('copy'));
    });

    test('atomic write: leaves destination untouched when ffmpeg fails',
        () async {
      final destPath = '${Directory.systemTemp.path}/out.m4b';
      // Pre-existing file we should NOT overwrite or clobber.
      File(destPath).writeAsStringSync('original-bytes');

      when(() => runner.run(
            executable: '/usr/bin/ffmpeg',
            arguments: any(named: 'arguments'),
          )).thenAnswer((_) async => const ProcessOutput(
            exitCode: 1,
            stdout: '',
            stderr: 'simulated failure',
            stdoutBytes: Uint8List(0),
          ));

      await expectLater(
        bookbinder.write(
          sourcePath: '/tmp/in.m4b',
          destinationPath: destPath,
          audiobook: book,
        ),
        throwsA(isA<BookbinderException>()),
      );
      expect(File(destPath).readAsStringSync(), 'original-bytes');
      File(destPath).deleteSync();
    });
  });
```

Also add the imports at the top of the test file (if not already present):

```dart
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
```

- [ ] **Step 2: Run tests and watch them fail**

Run: `flutter test test/data/ffmpeg_bookbinder_test.dart`
Expected: FAIL — `write` is unimplemented.

- [ ] **Step 3: Implement `FfmpegBookbinder.write`**

Replace the `write` stub in `lib/data/ffmpeg_bookbinder.dart` with:

```dart
  @override
  Future<void> write({
    required String sourcePath,
    required String destinationPath,
    required Audiobook audiobook,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('m4b-write-');
    final metadataPath = '${tempDir.path}/metadata.txt';
    final tempOutPath = '${tempDir.path}/out.m4b';
    String? coverPath;

    try {
      await File(metadataPath)
          .writeAsString(const FfmetadataCodec().encode(audiobook));

      if (audiobook.cover != null) {
        final ext = audiobook.cover!.mimeType == 'image/png' ? 'png' : 'jpg';
        coverPath = '${tempDir.path}/cover.$ext';
        await File(coverPath).writeAsBytes(audiobook.cover!.bytes);
      }

      final result = await _runner.run(
        executable: _binaries.ffmpeg,
        arguments: inv.writeArguments(
          sourcePath: sourcePath,
          metadataPath: metadataPath,
          coverPath: coverPath,
          outputPath: tempOutPath,
        ),
      );
      if (result.exitCode != 0) {
        throw BookbinderException(
          'ffmpeg failed writing $destinationPath',
          stderr: result.stderr,
        );
      }

      // Atomic move into place. dart:io's File.rename is atomic when both
      // paths share the same filesystem; for cross-FS we fall back to copy+delete.
      final tempOutFile = File(tempOutPath);
      try {
        await tempOutFile.rename(destinationPath);
      } on FileSystemException {
        await tempOutFile.copy(destinationPath);
        await tempOutFile.delete();
      }
    } finally {
      await tempDir.delete(recursive: true);
    }
  }
```

Update imports at top of file to include:

```dart
import 'dart:io';

import 'ffmetadata_codec.dart';
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/data/ffmpeg_bookbinder_test.dart`
Expected: `+5: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/data/ffmpeg_bookbinder.dart test/data/ffmpeg_bookbinder_test.dart
git commit --no-gpg-sign -m "Add FfmpegBookbinder.write with atomic temp+rename"
```

---

### Task 14: Integration test — round-trip against the real fixture

**Files:**
- Create: `test/data/ffmpeg_bookbinder_integration_test.dart`

This test runs the real `ffmpeg`/`ffprobe` (system PATH) against the checked-in fixture. It is the highest-value test we have. If `ffmpeg` is not on PATH, the test is skipped.

- [ ] **Step 1: Write the integration test**

Create `test/data/ffmpeg_bookbinder_integration_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/binary_resolver.dart';
import 'package:m4b_chapterizer/data/ffmpeg_bookbinder.dart';
import 'package:m4b_chapterizer/data/process_runner.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';

bool _ffmpegOnPath() {
  try {
    final result = Process.runSync('ffmpeg', ['-version']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  if (!_ffmpegOnPath()) {
    test('skipped: ffmpeg not on PATH', () {}, skip: true);
    return;
  }

  test('read → mutate → write → read round-trip preserves chapters and metadata',
      () async {
    final bookbinder = FfmpegBookbinder(
      runner: const SystemProcessRunner(),
      binaries: const SystemBinaryResolver(),
    );

    final tempDir = await Directory.systemTemp.createTemp('m4b-rt-');
    addTearDown(() => tempDir.delete(recursive: true));
    final workCopy = '${tempDir.path}/work.m4b';
    await File('test/fixtures/sample.m4b').copy(workCopy);

    final original = await bookbinder.read(workCopy);
    expect(original.title, 'A Test Book');
    expect(original.chapters.length, 3);
    expect(original.cover, isNotNull);

    final mutated = original.copyWith(
      title: 'Mutated Title',
      chapters: [
        const Chapter(title: 'Renamed', start: Duration.zero),
        original.chapters[1],
        original.chapters[2],
      ],
    );

    await bookbinder.write(
      sourcePath: workCopy,
      destinationPath: workCopy,
      audiobook: mutated,
    );

    final reread = await bookbinder.read(workCopy);
    expect(reread.title, 'Mutated Title');
    expect(reread.chapters[0].title, 'Renamed');
    expect(reread.chapters.length, 3);
    expect(reread.cover, isNotNull);
    expect(reread.totalDuration, original.totalDuration);
  });
}
```

- [ ] **Step 2: Run the test**

Run: `flutter test test/data/ffmpeg_bookbinder_integration_test.dart`
Expected on a machine with ffmpeg on PATH: `+1: All tests passed!`. On a machine without ffmpeg, the test is skipped without error.

- [ ] **Step 3: Run the entire suite once**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/data/ffmpeg_bookbinder_integration_test.dart
git commit --no-gpg-sign -m "Add FfmpegBookbinder round-trip integration test"
```

---

## Phase 6 — Editor state

### Task 15: `EditorState` and `EditorNotifier`

**Files:**
- Create: `lib/presentation/providers/editor_state.dart`
- Test: `test/presentation/editor_state_test.dart`

`EditorState` is an immutable snapshot: the loaded `Audiobook?`, the current file path, and a `dirty` flag. `EditorNotifier` (a Riverpod `Notifier`) drives transitions: `open`, `save`, `saveAs`, plus a family of mutators (`setTitle`, `addChapter`, `deleteChapter`, `renameChapter`, `setChapterStart`).

- [ ] **Step 1: Write the failing test**

Create `test/presentation/editor_state_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';

class _FakeBookbinder implements Bookbinder {
  _FakeBookbinder(this._book);
  final Audiobook _book;
  String? lastWritten;
  Audiobook? lastWrittenAudiobook;

  @override
  Future<Audiobook> read(String sourcePath) async => _book;

  @override
  Future<void> write({
    required String sourcePath,
    required String destinationPath,
    required Audiobook audiobook,
  }) async {
    lastWritten = destinationPath;
    lastWrittenAudiobook = audiobook;
  }
}

void main() {
  final book = Audiobook.validated(
    title: 'Original',
    chapters: const [
      Chapter(title: 'C1', start: Duration.zero),
      Chapter(title: 'C2', start: Duration(seconds: 5)),
    ],
    totalDuration: const Duration(seconds: 10),
  );

  ProviderContainer makeContainer(_FakeBookbinder fake) => ProviderContainer(
        overrides: [bookbinderProvider.overrideWithValue(fake)],
      );

  test('initial state has no audiobook and is not dirty', () {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    final state = container.read(editorProvider);
    expect(state.audiobook, isNull);
    expect(state.isDirty, isFalse);
    expect(state.path, isNull);
  });

  test('open loads an audiobook and resets dirty', () async {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/foo.m4b');
    final state = container.read(editorProvider);
    expect(state.audiobook?.title, 'Original');
    expect(state.path, '/tmp/foo.m4b');
    expect(state.isDirty, isFalse);
  });

  test('setTitle marks dirty and updates the title', () async {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/foo.m4b');
    container.read(editorProvider.notifier).setTitle('Edited');
    final state = container.read(editorProvider);
    expect(state.audiobook?.title, 'Edited');
    expect(state.isDirty, isTrue);
  });

  test('save writes back to the loaded path and clears dirty', () async {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/foo.m4b');
    container.read(editorProvider.notifier).setTitle('Edited');
    await container.read(editorProvider.notifier).save();
    expect(fake.lastWritten, '/tmp/foo.m4b');
    expect(fake.lastWrittenAudiobook?.title, 'Edited');
    expect(container.read(editorProvider).isDirty, isFalse);
  });

  test('saveAs writes to a new path and updates the loaded path', () async {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/foo.m4b');
    await container.read(editorProvider.notifier).saveAs('/tmp/bar.m4b');
    final state = container.read(editorProvider);
    expect(fake.lastWritten, '/tmp/bar.m4b');
    expect(state.path, '/tmp/bar.m4b');
    expect(state.isDirty, isFalse);
  });

  test('addChapter inserts at the end and marks dirty', () async {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/foo.m4b');
    container.read(editorProvider.notifier).addChapter();
    final state = container.read(editorProvider);
    expect(state.audiobook?.chapters.length, 3);
    expect(state.isDirty, isTrue);
  });

  test('deleteChapter removes the indexed chapter', () async {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/foo.m4b');
    container.read(editorProvider.notifier).deleteChapter(0);
    final state = container.read(editorProvider);
    expect(state.audiobook?.chapters.length, 1);
    expect(state.audiobook?.chapters.first.title, 'C2');
    // The first chapter was removed; the new first chapter must start at zero.
    expect(state.audiobook?.chapters.first.start, Duration.zero);
  });

  test('setChapterStart updates the chapter at index', () async {
    final fake = _FakeBookbinder(book);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(editorProvider.notifier).open('/tmp/foo.m4b');
    container
        .read(editorProvider.notifier)
        .setChapterStart(1, const Duration(seconds: 7));
    final state = container.read(editorProvider);
    expect(state.audiobook?.chapters[1].start, const Duration(seconds: 7));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/presentation/editor_state_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `EditorState` and `EditorNotifier`**

Create `lib/presentation/providers/editor_state.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../domain/bookbinder.dart';
import '../../domain/models/audiobook.dart';
import '../../domain/models/chapter.dart';

@immutable
class EditorState {
  const EditorState({this.audiobook, this.path, this.isDirty = false});

  final Audiobook? audiobook;
  final String? path;
  final bool isDirty;

  EditorState copyWith({
    Audiobook? audiobook,
    String? path,
    bool? isDirty,
  }) =>
      EditorState(
        audiobook: audiobook ?? this.audiobook,
        path: path ?? this.path,
        isDirty: isDirty ?? this.isDirty,
      );
}

/// Provided at app startup with `bookbinderProvider.overrideWithValue(...)`.
/// Tests override it with a fake.
final bookbinderProvider = Provider<Bookbinder>((ref) {
  throw StateError(
    'bookbinderProvider must be overridden at the app or test scope',
  );
});

final editorProvider =
    NotifierProvider<EditorNotifier, EditorState>(EditorNotifier.new);

class EditorNotifier extends Notifier<EditorState> {
  @override
  EditorState build() => const EditorState();

  Bookbinder get _bookbinder => ref.read(bookbinderProvider);

  Future<void> open(String path) async {
    final book = await _bookbinder.read(path);
    state = EditorState(audiobook: book, path: path);
  }

  Future<void> save() async {
    final book = state.audiobook;
    final path = state.path;
    if (book == null || path == null) return;
    await _bookbinder.write(
      sourcePath: path,
      destinationPath: path,
      audiobook: book,
    );
    state = state.copyWith(isDirty: false);
  }

  Future<void> saveAs(String newPath) async {
    final book = state.audiobook;
    final path = state.path;
    if (book == null || path == null) return;
    await _bookbinder.write(
      sourcePath: path,
      destinationPath: newPath,
      audiobook: book,
    );
    state = state.copyWith(path: newPath, isDirty: false);
  }

  void setTitle(String value) =>
      _updateBook((b) => b.copyWith(title: value));
  void setAuthor(String value) =>
      _updateBook((b) => b.copyWith(author: value));
  void setNarrator(String value) =>
      _updateBook((b) => b.copyWith(narrator: value));
  void setAlbum(String value) => _updateBook((b) => b.copyWith(album: value));
  void setGenre(String value) => _updateBook((b) => b.copyWith(genre: value));
  void setDescription(String value) =>
      _updateBook((b) => b.copyWith(description: value));
  void setYear(int? value) => _updateBook((b) => b.copyWith(year: value));

  void addChapter() {
    _updateBook((book) {
      final last = book.chapters.last;
      final lastEnd = book.totalDuration;
      final newStart = Duration(
        microseconds: (last.start.inMicroseconds + lastEnd.inMicroseconds) ~/ 2,
      );
      return book.copyWith(
        chapters: [
          ...book.chapters,
          Chapter(title: 'New chapter', start: newStart),
        ],
      );
    });
  }

  void deleteChapter(int index) {
    _updateBook((book) {
      if (book.chapters.length <= 1) return book; // never delete the last chapter
      final updated = [...book.chapters]..removeAt(index);
      // After deletion, ensure first chapter starts at zero (Audiobook invariant).
      if (index == 0) {
        updated[0] = updated[0].copyWith(start: Duration.zero);
      }
      return Audiobook.validated(
        title: book.title,
        author: book.author,
        narrator: book.narrator,
        album: book.album,
        genre: book.genre,
        description: book.description,
        year: book.year,
        cover: book.cover,
        chapters: updated,
        totalDuration: book.totalDuration,
      );
    });
  }

  void renameChapter(int index, String title) {
    _updateBook((book) {
      final updated = [...book.chapters];
      updated[index] = updated[index].copyWith(title: title);
      return book.copyWith(chapters: updated);
    });
  }

  void setChapterStart(int index, Duration start) {
    _updateBook((book) {
      final updated = [...book.chapters];
      updated[index] = updated[index].copyWith(start: start);
      return Audiobook.validated(
        title: book.title,
        author: book.author,
        narrator: book.narrator,
        album: book.album,
        genre: book.genre,
        description: book.description,
        year: book.year,
        cover: book.cover,
        chapters: updated,
        totalDuration: book.totalDuration,
      );
    });
  }

  void _updateBook(Audiobook Function(Audiobook book) f) {
    final book = state.audiobook;
    if (book == null) return;
    state = state.copyWith(audiobook: f(book), isDirty: true);
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/presentation/editor_state_test.dart`
Expected: All 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/providers/editor_state.dart test/presentation/editor_state_test.dart
git commit --no-gpg-sign -m "Add EditorState and EditorNotifier with bookbinder provider"
```

---

### Task 16: Time-string parsing helper

**Files:**
- Create: `lib/presentation/util/duration_format.dart`
- Test: `test/presentation/duration_format_test.dart`

Chapter start times are entered as `HH:MM:SS.mmm`. We need a permissive parser and a formatter so the widget tests in Phase 7 can rely on them.

- [ ] **Step 1: Failing tests**

Create `test/presentation/duration_format_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/presentation/util/duration_format.dart';

void main() {
  group('formatDuration', () {
    test('formats zero', () {
      expect(formatDuration(Duration.zero), '00:00:00.000');
    });
    test('formats one hour two minutes three seconds and 45 ms', () {
      expect(
        formatDuration(const Duration(
            hours: 1, minutes: 2, seconds: 3, milliseconds: 45)),
        '01:02:03.045',
      );
    });
  });

  group('parseDuration', () {
    test('parses HH:MM:SS.mmm', () {
      expect(parseDuration('01:02:03.045'),
          const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 45));
    });
    test('parses MM:SS.mmm (no hours)', () {
      expect(parseDuration('02:03.045'),
          const Duration(minutes: 2, seconds: 3, milliseconds: 45));
    });
    test('parses SS (seconds only)', () {
      expect(parseDuration('15'), const Duration(seconds: 15));
    });
    test('rejects garbage', () {
      expect(() => parseDuration('not a time'), throwsFormatException);
    });
    test('rejects negative components', () {
      expect(() => parseDuration('-01:00:00'), throwsFormatException);
    });
  });
}
```

- [ ] **Step 2: Run test, see it fail**

Run: `flutter test test/presentation/duration_format_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `lib/presentation/util/duration_format.dart`:

```dart
String formatDuration(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
  return '$h:$m:$s.$ms';
}

/// Parses `HH:MM:SS.mmm`, `MM:SS.mmm`, or plain seconds. Permissive about
/// missing leading zeroes and missing milliseconds. Throws [FormatException]
/// on invalid input.
Duration parseDuration(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty || trimmed.startsWith('-')) {
    throw FormatException('Invalid duration: $input');
  }
  final parts = trimmed.split(':');
  if (parts.length > 3) {
    throw FormatException('Too many : segments: $input');
  }
  int hours = 0;
  int minutes = 0;
  double seconds;
  if (parts.length == 3) {
    hours = int.parse(parts[0]);
    minutes = int.parse(parts[1]);
    seconds = double.parse(parts[2]);
  } else if (parts.length == 2) {
    minutes = int.parse(parts[0]);
    seconds = double.parse(parts[1]);
  } else {
    seconds = double.parse(parts[0]);
  }
  if (hours < 0 || minutes < 0 || seconds < 0) {
    throw FormatException('Negative components not allowed: $input');
  }
  final totalMs =
      (hours * 3600 + minutes * 60) * 1000 + (seconds * 1000).round();
  return Duration(milliseconds: totalMs);
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/presentation/duration_format_test.dart`
Expected: `+7: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/util/duration_format.dart test/presentation/duration_format_test.dart
git commit --no-gpg-sign -m "Add duration format/parse helpers"
```

---

## Phase 7 — Widgets

The four widgets are tested with widget tests that render them inside a minimal `ProviderScope` with `bookbinderProvider` overridden to a fake. We rely on `Finder` queries (by key, by widget type, by text) — keep widget keys stable.

### Task 17: `MetadataForm`

**Files:**
- Create: `lib/presentation/widgets/metadata_form.dart`
- Test: `test/presentation/metadata_form_test.dart`

- [ ] **Step 1: Failing widget test**

Create `test/presentation/metadata_form_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/widgets/metadata_form.dart';

class _StubBookbinder implements Bookbinder {
  _StubBookbinder(this._book);
  final Audiobook _book;
  @override
  Future<Audiobook> read(String sourcePath) async => _book;
  @override
  Future<void> write({required String sourcePath, required String destinationPath, required Audiobook audiobook}) async {}
}

Future<Widget> _harness(WidgetTester tester, _StubBookbinder fake) async {
  final container = ProviderContainer(
    overrides: [bookbinderProvider.overrideWithValue(fake)],
  );
  await container.read(editorProvider.notifier).open('/tmp/x.m4b');
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: MetadataForm())),
  );
}

void main() {
  testWidgets('renders the loaded audiobook fields', (tester) async {
    final fake = _StubBookbinder(Audiobook.validated(
      title: 'A Title',
      author: 'An Author',
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 5),
    ));
    await tester.pumpWidget(await _harness(tester, fake));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'A Title'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'An Author'), findsOneWidget);
  });

  testWidgets('typing in the title field updates editor state', (tester) async {
    final fake = _StubBookbinder(Audiobook.validated(
      title: 'Old',
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 5),
    ));
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: MetadataForm())),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('metadata.title')),
      'Brand New',
    );
    await tester.pump();

    expect(container.read(editorProvider).audiobook?.title, 'Brand New');
    expect(container.read(editorProvider).isDirty, isTrue);
  });
}
```

- [ ] **Step 2: Run, see failure**

Run: `flutter test test/presentation/metadata_form_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `MetadataForm`**

Create `lib/presentation/widgets/metadata_form.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor_state.dart';

class MetadataForm extends ConsumerStatefulWidget {
  const MetadataForm({super.key});

  @override
  ConsumerState<MetadataForm> createState() => _MetadataFormState();
}

class _MetadataFormState extends ConsumerState<MetadataForm> {
  late final _title = TextEditingController();
  late final _author = TextEditingController();
  late final _narrator = TextEditingController();
  late final _album = TextEditingController();
  late final _genre = TextEditingController();
  late final _year = TextEditingController();
  late final _description = TextEditingController();

  bool _hydrated = false;

  void _hydrateFromState(EditorState state) {
    final book = state.audiobook;
    if (book == null) return;
    _title.text = book.title ?? '';
    _author.text = book.author ?? '';
    _narrator.text = book.narrator ?? '';
    _album.text = book.album ?? '';
    _genre.text = book.genre ?? '';
    _year.text = book.year?.toString() ?? '';
    _description.text = book.description ?? '';
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _narrator.dispose();
    _album.dispose();
    _genre.dispose();
    _year.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider);
    if (!_hydrated && state.audiobook != null) {
      _hydrateFromState(state);
      _hydrated = true;
    }
    final notifier = ref.read(editorProvider.notifier);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field('Title', const ValueKey('metadata.title'), _title,
              notifier.setTitle),
          _field('Author', const ValueKey('metadata.author'), _author,
              notifier.setAuthor),
          _field('Narrator', const ValueKey('metadata.narrator'), _narrator,
              notifier.setNarrator),
          _field('Album', const ValueKey('metadata.album'), _album,
              notifier.setAlbum),
          _field('Genre', const ValueKey('metadata.genre'), _genre,
              notifier.setGenre),
          _field('Year', const ValueKey('metadata.year'), _year, (s) {
            notifier.setYear(int.tryParse(s));
          }),
          _field('Description', const ValueKey('metadata.description'),
              _description, notifier.setDescription,
              maxLines: 3),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    Key key,
    TextEditingController controller,
    void Function(String) onChanged, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        key: key,
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: onChanged,
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/presentation/metadata_form_test.dart`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/metadata_form.dart test/presentation/metadata_form_test.dart
git commit --no-gpg-sign -m "Add MetadataForm widget"
```

---

### Task 18: `CoverPanel`

**Files:**
- Create: `lib/presentation/widgets/cover_panel.dart`
- Test: `test/presentation/cover_panel_test.dart`

- [ ] **Step 1: Failing widget test**

Create `test/presentation/cover_panel_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/domain/models/cover.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/widgets/cover_panel.dart';

class _StubBookbinder implements Bookbinder {
  _StubBookbinder(this._book);
  final Audiobook _book;
  @override
  Future<Audiobook> read(String sourcePath) async => _book;
  @override
  Future<void> write({required String sourcePath, required String destinationPath, required Audiobook audiobook}) async {}
}

void main() {
  // 1x1 transparent PNG.
  final tinyPng = Uint8List.fromList(const [
    0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,
    0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
    0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
    0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,0x89,
    0x00,0x00,0x00,0x0D,0x49,0x44,0x41,0x54,
    0x78,0x9C,0x63,0x00,0x01,0x00,0x00,0x05,
    0x00,0x01,0x0D,0x0A,0x2D,0xB4,
    0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,
    0xAE,0x42,0x60,0x82,
  ]);

  testWidgets('shows placeholder when book has no cover', (tester) async {
    final fake = _StubBookbinder(Audiobook.validated(
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 1),
    ));
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: CoverPanel())),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cover.placeholder')), findsOneWidget);
  });

  testWidgets('shows the image when book has a cover', (tester) async {
    final fake = _StubBookbinder(Audiobook.validated(
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 1),
      cover: Cover(bytes: tinyPng, mimeType: 'image/png'),
    ));
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: CoverPanel())),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cover.image')), findsOneWidget);
  });

  testWidgets('Remove button clears the cover', (tester) async {
    final fake = _StubBookbinder(Audiobook.validated(
      chapters: const [Chapter(title: 'C', start: Duration.zero)],
      totalDuration: const Duration(seconds: 1),
      cover: Cover(bytes: tinyPng, mimeType: 'image/png'),
    ));
    final container = ProviderContainer(
      overrides: [bookbinderProvider.overrideWithValue(fake)],
    );
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: CoverPanel())),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cover.remove')));
    await tester.pump();

    expect(container.read(editorProvider).audiobook?.cover, isNull);
    expect(container.read(editorProvider).isDirty, isTrue);
  });
}
```

- [ ] **Step 2: Run test, see failure**

Run: `flutter test test/presentation/cover_panel_test.dart`
Expected: FAIL.

- [ ] **Step 3: Add `clearCover` action and `replaceCover` to `EditorNotifier`**

Append to the body of `EditorNotifier` in `lib/presentation/providers/editor_state.dart`:

```dart
  void clearCover() {
    final book = state.audiobook;
    if (book == null) return;
    state = state.copyWith(
      audiobook: book.copyWith(clearCover: true),
      isDirty: true,
    );
  }

  void replaceCover(Cover cover) =>
      _updateBook((b) => b.copyWith(cover: cover));
```

Add the import at the top of that file:

```dart
import '../../domain/models/cover.dart';
```

- [ ] **Step 4: Implement `CoverPanel`**

Create `lib/presentation/widgets/cover_panel.dart`:

```dart
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/cover.dart';
import '../providers/editor_state.dart';

class CoverPanel extends ConsumerWidget {
  const CoverPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = ref.watch(editorProvider).audiobook?.cover;
    final notifier = ref.read(editorProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 160,
          height: 160,
          child: cover == null
              ? Container(
                  key: const ValueKey('cover.placeholder'),
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.book, size: 64),
                )
              : Image.memory(cover.bytes, key: const ValueKey('cover.image')),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              key: const ValueKey('cover.replace'),
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: const ['png', 'jpg', 'jpeg'],
                );
                final picked = result?.files.single.path;
                if (picked == null) return;
                final bytes = await File(picked).readAsBytes();
                final mime = picked.toLowerCase().endsWith('.png')
                    ? 'image/png'
                    : 'image/jpeg';
                notifier.replaceCover(Cover(bytes: bytes, mimeType: mime));
              },
              child: const Text('Replace…'),
            ),
            TextButton(
              key: const ValueKey('cover.remove'),
              onPressed: cover == null ? null : notifier.clearCover,
              child: const Text('Remove'),
            ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Run tests**

Run: `flutter test test/presentation/cover_panel_test.dart`
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/providers/editor_state.dart lib/presentation/widgets/cover_panel.dart test/presentation/cover_panel_test.dart
git commit --no-gpg-sign -m "Add CoverPanel widget with replace and remove"
```

---

### Task 19: `ChapterList`

**Files:**
- Create: `lib/presentation/widgets/chapter_list.dart`
- Test: `test/presentation/chapter_list_test.dart`

- [ ] **Step 1: Failing widget test**

Create `test/presentation/chapter_list_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/widgets/chapter_list.dart';

class _StubBookbinder implements Bookbinder {
  _StubBookbinder(this._book);
  final Audiobook _book;
  @override
  Future<Audiobook> read(String sourcePath) async => _book;
  @override
  Future<void> write({required String sourcePath, required String destinationPath, required Audiobook audiobook}) async {}
}

Future<ProviderContainer> _setUp(WidgetTester tester) async {
  final fake = _StubBookbinder(Audiobook.validated(
    chapters: const [
      Chapter(title: 'Alpha', start: Duration.zero),
      Chapter(title: 'Beta', start: Duration(seconds: 10)),
    ],
    totalDuration: const Duration(seconds: 30),
  ));
  final container = ProviderContainer(
    overrides: [bookbinderProvider.overrideWithValue(fake)],
  );
  await container.read(editorProvider.notifier).open('/tmp/x.m4b');
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: ChapterList())),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('renders one row per chapter', (tester) async {
    await _setUp(tester);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('Add button appends a chapter', (tester) async {
    final container = await _setUp(tester);
    await tester.tap(find.byKey(const ValueKey('chapters.add')));
    await tester.pump();
    expect(container.read(editorProvider).audiobook?.chapters.length, 3);
  });

  testWidgets('Delete button removes the selected chapter', (tester) async {
    final container = await _setUp(tester);
    await tester.tap(find.byKey(const ValueKey('chapters.row.1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chapters.delete')));
    await tester.pump();
    expect(container.read(editorProvider).audiobook?.chapters.length, 1);
    expect(container.read(editorProvider).audiobook?.chapters.first.title,
        'Alpha');
  });

  testWidgets('editing a title updates state', (tester) async {
    final container = await _setUp(tester);
    await tester.enterText(
      find.byKey(const ValueKey('chapters.title.0')),
      'Renamed',
    );
    await tester.pump();
    expect(container.read(editorProvider).audiobook?.chapters.first.title,
        'Renamed');
  });
}
```

- [ ] **Step 2: Run, see failure**

Run: `flutter test test/presentation/chapter_list_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `ChapterList`**

Create `lib/presentation/widgets/chapter_list.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor_state.dart';
import '../util/duration_format.dart';

final selectedChapterProvider = StateProvider<int>((ref) => 0);

class ChapterList extends ConsumerWidget {
  const ChapterList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(editorProvider).audiobook;
    final selected = ref.watch(selectedChapterProvider);
    final notifier = ref.read(editorProvider.notifier);
    if (book == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: book.chapters.length,
            itemBuilder: (context, i) {
              final chapter = book.chapters[i];
              return ListTile(
                key: ValueKey('chapters.row.$i'),
                selected: i == selected,
                onTap: () =>
                    ref.read(selectedChapterProvider.notifier).state = i,
                leading: Text('${i + 1}'),
                title: TextField(
                  key: ValueKey('chapters.title.$i'),
                  controller: TextEditingController(text: chapter.title),
                  onSubmitted: (v) => notifier.renameChapter(i, v),
                  onChanged: (v) => notifier.renameChapter(i, v),
                  decoration: const InputDecoration(isDense: true),
                ),
                trailing: SizedBox(
                  width: 110,
                  child: TextField(
                    key: ValueKey('chapters.start.$i'),
                    controller:
                        TextEditingController(text: formatDuration(chapter.start)),
                    onSubmitted: (v) {
                      try {
                        notifier.setChapterStart(i, parseDuration(v));
                      } on FormatException {
                        // leave field as-is
                      }
                    },
                  ),
                ),
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(
              key: const ValueKey('chapters.add'),
              onPressed: notifier.addChapter,
              child: const Text('+ Add'),
            ),
            TextButton(
              key: const ValueKey('chapters.delete'),
              onPressed: () => notifier.deleteChapter(
                  ref.read(selectedChapterProvider)),
              child: const Text('− Delete'),
            ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/presentation/chapter_list_test.dart`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/chapter_list.dart test/presentation/chapter_list_test.dart
git commit --no-gpg-sign -m "Add ChapterList widget"
```

---

### Task 20: `PlaybackController` and `PlaybackControls`

**Files:**
- Create: `lib/presentation/providers/playback.dart`
- Create: `lib/presentation/widgets/playback_controls.dart`
- Test: `test/presentation/playback_controls_test.dart`

The `PlaybackController` interface lets us inject a fake in tests. The production implementation wraps `just_audio`.

- [ ] **Step 1: Failing widget test**

Create `test/presentation/playback_controls_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/providers/playback.dart';
import 'package:m4b_chapterizer/presentation/widgets/chapter_list.dart';
import 'package:m4b_chapterizer/presentation/widgets/playback_controls.dart';

class _StubBookbinder implements Bookbinder {
  @override
  Future<Audiobook> read(String sourcePath) async => Audiobook.validated(
        chapters: const [
          Chapter(title: 'A', start: Duration.zero),
          Chapter(title: 'B', start: Duration(seconds: 10)),
        ],
        totalDuration: const Duration(seconds: 30),
      );
  @override
  Future<void> write({required String sourcePath, required String destinationPath, required Audiobook audiobook}) async {}
}

class _FakePlayback implements PlaybackController {
  Duration _pos = const Duration(seconds: 7);
  bool _playing = false;
  @override
  Future<void> setSource(String path) async {}
  @override
  Future<void> play() async => _playing = true;
  @override
  Future<void> pause() async => _playing = false;
  @override
  Future<void> seek(Duration position) async => _pos = position;
  @override
  Duration get position => _pos;
  @override
  bool get playing => _playing;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('Set start to playhead snaps the selected chapter to position',
      (tester) async {
    final fake = _StubBookbinder();
    final fakePlayback = _FakePlayback();
    final container = ProviderContainer(
      overrides: [
        bookbinderProvider.overrideWithValue(fake),
        playbackControllerProvider.overrideWithValue(fakePlayback),
      ],
    );
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    container.read(selectedChapterProvider.notifier).state = 1;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: PlaybackControls())),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('playback.snap')));
    await tester.pump();

    expect(
      container.read(editorProvider).audiobook?.chapters[1].start,
      const Duration(seconds: 7),
    );
  });
}
```

- [ ] **Step 2: Run, see failure**

Run: `flutter test test/presentation/playback_controls_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `PlaybackController` and provider**

Create `lib/presentation/providers/playback.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

abstract class PlaybackController {
  Future<void> setSource(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Duration get position;
  bool get playing;
  Stream<Duration> get positionStream;
  Future<void> dispose();
}

class JustAudioPlaybackController implements PlaybackController {
  JustAudioPlaybackController() : _player = AudioPlayer();
  final AudioPlayer _player;
  String? _currentSource;

  @override
  Future<void> setSource(String path) async {
    if (_currentSource == path) return;
    _currentSource = path;
    await _player.setFilePath(path);
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Duration get position => _player.position;
  @override
  bool get playing => _player.playing;
  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Future<void> dispose() => _player.dispose();
}

/// Provided at app startup with `playbackControllerProvider.overrideWithValue(...)`.
/// Tests override with a fake.
final playbackControllerProvider = Provider<PlaybackController>((ref) {
  final controller = JustAudioPlaybackController();
  ref.onDispose(controller.dispose);
  return controller;
});
```

- [ ] **Step 4: Implement `PlaybackControls`**

Create `lib/presentation/widgets/playback_controls.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor_state.dart';
import '../providers/playback.dart';
import '../util/duration_format.dart';
import 'chapter_list.dart';

class PlaybackControls extends ConsumerWidget {
  const PlaybackControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackControllerProvider);
    final notifier = ref.read(editorProvider.notifier);
    final selectedIndex = ref.watch(selectedChapterProvider);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(controller.playing ? Icons.pause : Icons.play_arrow),
            onPressed: () =>
                controller.playing ? controller.pause() : controller.play(),
          ),
          const SizedBox(width: 12),
          StreamBuilder<Duration>(
            stream: controller.positionStream,
            builder: (context, snapshot) => Text(
              formatDuration(snapshot.data ?? controller.position),
            ),
          ),
          const Spacer(),
          ElevatedButton(
            key: const ValueKey('playback.snap'),
            onPressed: () =>
                notifier.setChapterStart(selectedIndex, controller.position),
            child: const Text('Set start to playhead'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run tests**

Run: `flutter test test/presentation/playback_controls_test.dart`
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/providers/playback.dart lib/presentation/widgets/playback_controls.dart test/presentation/playback_controls_test.dart
git commit --no-gpg-sign -m "Add PlaybackController and PlaybackControls widget"
```

---

### Task 21: `EditorScreen`, `StartupScreen`, app wiring, and dirty-discard dialog

**Files:**
- Create: `lib/presentation/screens/editor_screen.dart`
- Create: `lib/presentation/screens/startup_screen.dart`
- Create: `lib/presentation/app.dart`
- Modify: `lib/main.dart`
- Test: `test/presentation/editor_screen_test.dart`

- [ ] **Step 1: Failing widget test**

Create `test/presentation/editor_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/domain/bookbinder.dart';
import 'package:m4b_chapterizer/domain/models/audiobook.dart';
import 'package:m4b_chapterizer/domain/models/chapter.dart';
import 'package:m4b_chapterizer/presentation/providers/editor_state.dart';
import 'package:m4b_chapterizer/presentation/providers/playback.dart';
import 'package:m4b_chapterizer/presentation/screens/editor_screen.dart';

class _Stub implements Bookbinder {
  @override
  Future<Audiobook> read(String sourcePath) async => Audiobook.validated(
        title: 'Loaded',
        chapters: const [Chapter(title: 'C', start: Duration.zero)],
        totalDuration: const Duration(seconds: 5),
      );
  @override
  Future<void> write({required String sourcePath, required String destinationPath, required Audiobook audiobook}) async {}
}

class _NoopPlayback implements PlaybackController {
  @override
  Future<void> setSource(String path) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Duration get position => Duration.zero;
  @override
  bool get playing => false;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('shows the dirty marker after editing', (tester) async {
    final container = ProviderContainer(overrides: [
      bookbinderProvider.overrideWithValue(_Stub()),
      playbackControllerProvider.overrideWithValue(_NoopPlayback()),
    ]);
    await container.read(editorProvider.notifier).open('/tmp/x.m4b');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: EditorScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('•'), findsNothing);

    container.read(editorProvider.notifier).setTitle('Edited');
    await tester.pump();
    expect(find.text('•'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test, see it fail**

Run: `flutter test test/presentation/editor_screen_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `EditorScreen`**

Create `lib/presentation/screens/editor_screen.dart`:

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor_state.dart';
import '../providers/playback.dart';
import '../widgets/chapter_list.dart';
import '../widgets/cover_panel.dart';
import '../widgets/metadata_form.dart';
import '../widgets/playback_controls.dart';

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  Future<bool> _confirmDiscard(BuildContext context) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text(
            'You have unsaved changes. Continue and lose them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final notifier = ref.read(editorProvider.notifier);
    final playback = ref.read(playbackControllerProvider);
    final filename = state.path?.split(Platform.pathSeparator).last ?? '';

    // Wire playback source whenever the path changes.
    if (state.path != null) {
      playback.setSource(state.path!);
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(filename),
            const SizedBox(width: 8),
            if (state.isDirty) const Text('•'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (state.isDirty && !await _confirmDiscard(context)) return;
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: const ['m4b'],
              );
              final path = result?.files.single.path;
              if (path == null) return;
              await notifier.open(path);
            },
            child: const Text('Open…'),
          ),
          TextButton(
            onPressed:
                state.audiobook == null ? null : () => notifier.save(),
            child: const Text('Save'),
          ),
          TextButton(
            onPressed: state.audiobook == null
                ? null
                : () async {
                    final result = await FilePicker.platform.saveFile(
                      type: FileType.custom,
                      allowedExtensions: const ['m4b'],
                      fileName: filename,
                    );
                    if (result == null) return;
                    await notifier.saveAs(result);
                  },
            child: const Text('Save As…'),
          ),
        ],
      ),
      body: state.audiobook == null
          ? const Center(child: Text('Open an .m4b file to begin'))
          : Column(
              children: [
                Expanded(
                  child: Row(
                    children: const [
                      SizedBox(
                        width: 280,
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              CoverPanel(),
                              MetadataForm(),
                            ],
                          ),
                        ),
                      ),
                      VerticalDivider(width: 1),
                      Expanded(child: ChapterList()),
                    ],
                  ),
                ),
                const Divider(height: 1),
                const PlaybackControls(),
              ],
            ),
    );
  }
}
```

(Add the import `import 'dart:io';` at the top of `editor_screen.dart`.)

- [ ] **Step 4: Implement `app.dart` and `main.dart`**

Create `lib/presentation/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/editor_screen.dart';

class M4bChapterizerApp extends ConsumerWidget {
  const M4bChapterizerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'm4b chapterizer',
      theme: ThemeData(useMaterial3: true),
      home: const EditorScreen(),
    );
  }
}
```

Replace `lib/main.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/binary_resolver.dart';
import 'data/ffmpeg_bookbinder.dart';
import 'data/process_runner.dart';
import 'presentation/app.dart';
import 'presentation/providers/editor_state.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [
        bookbinderProvider.overrideWithValue(
          FfmpegBookbinder(
            runner: const SystemProcessRunner(),
            // Phase 8 swaps this to BundledBinaryResolver.
            binaries: const SystemBinaryResolver(),
          ),
        ),
      ],
      child: const M4bChapterizerApp(),
    ),
  );
}
```

- [ ] **Step 5: Run all tests**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 6: Smoke-test the app on macOS**

```bash
flutter run -d macos
```

Open the test fixture (`test/fixtures/sample.m4b`) and verify:
- Title, author, narrator, etc. populate correctly
- Cover thumbnail renders
- Three chapters appear with the expected names and starts
- Editing a field shows the `•` dirty marker
- Save writes back; reopening shows the change

- [ ] **Step 7: Commit**

```bash
git add lib/main.dart lib/presentation/app.dart lib/presentation/screens/editor_screen.dart test/presentation/editor_screen_test.dart
git commit --no-gpg-sign -m "Wire EditorScreen, app entrypoint, and dirty-discard dialog"
```

---

## Phase 8 — ffmpeg bundling

### Task 22: `tool/fetch_ffmpeg.dart` build-time downloader

> **Note for the implementer:** Cross-platform static-binary distribution is genuinely messy (URLs, archive layouts, and SHA-256s are owned by external maintainers and change). This task delivers the structural scaffold — platform detection, download, SHA verification, asset placement — and concrete URLs for macOS arm64. The implementer must (a) run the script on each target platform once, (b) compute SHA-256 of each downloaded archive (`shasum -a 256 <file>`) and paste it into the source map, and (c) extend the script with the matching extraction branch for Windows and Linux when those builds are added. This is acceptable scope for a build-time tool that runs once per machine; do not let it block the rest of the work.

**Files:**
- Create: `tool/fetch_ffmpeg.dart`
- Modify: `pubspec.yaml` (declare bundled binaries as assets — note that asset declarations apply per-platform via runtime path resolution)
- Modify: `README.md` (one-paragraph note on running `dart run tool/fetch_ffmpeg.dart` before `flutter build`)

The script:
1. Detects the current target platform.
2. Downloads a pinned ffmpeg+ffprobe archive for that platform.
3. Verifies SHA-256.
4. Extracts the binaries into `assets/bin/<platform>/`.

- [ ] **Step 1: Document the pinned versions**

Update the **Open items** section of the spec at `docs/superpowers/specs/2026-04-30-m4b-chapterizer-mvp-design.md` to record the chosen URLs and SHA-256s alongside ffmpeg version 7.1. Use:

- macOS arm64: `https://www.osxexperts.net/ffmpeg711arm.zip` and `https://www.osxexperts.net/ffprobe711arm.zip` (replace with current pinned hashes when running)
- macOS x86_64: `https://www.osxexperts.net/ffmpeg711intel.zip` and `https://www.osxexperts.net/ffprobe711intel.zip`
- Windows x86_64: from `https://github.com/GyanD/codexffmpeg/releases/tag/7.1` — `ffmpeg-7.1-essentials_build.zip`
- Linux x86_64: from `https://johnvansickle.com/ffmpeg/releases/ffmpeg-7.1-amd64-static.tar.xz`

The implementer must fetch each URL once, compute its SHA-256 with `shasum -a 256 <file>`, and paste the value into the URL→hash table inside the script (Step 2 below). Do not commit binaries; the script is committed and runs on each build host.

- [ ] **Step 2: Write the script**

Create `tool/fetch_ffmpeg.dart`:

```dart
// Downloads pinned ffmpeg/ffprobe binaries into assets/bin/<platform>/.
// Run once per development machine and once per CI build:
//   dart run tool/fetch_ffmpeg.dart
//
// Pinned to ffmpeg 7.1.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class _Source {
  const _Source({required this.url, required this.sha256, required this.member});
  final String url;
  final String sha256;

  /// Path within the archive to extract. For raw zips of a single binary,
  /// pass the binary's filename inside the zip.
  final String member;
}

const _sources = {
  'macos-arm64': [
    _Source(
      url: 'https://www.osxexperts.net/ffmpeg711arm.zip',
      sha256: 'PASTE_SHA256_HERE',
      member: 'ffmpeg',
    ),
    _Source(
      url: 'https://www.osxexperts.net/ffprobe711arm.zip',
      sha256: 'PASTE_SHA256_HERE',
      member: 'ffprobe',
    ),
  ],
  // Add macos-x64, windows-x64, linux-x64 entries with the same shape.
};

String _platformKey() {
  if (Platform.isMacOS) {
    return Platform.version.contains('arm64') ? 'macos-arm64' : 'macos-x64';
  }
  if (Platform.isWindows) return 'windows-x64';
  if (Platform.isLinux) return 'linux-x64';
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

Future<List<int>> _download(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) {
      throw StateError('Download failed: $url -> ${res.statusCode}');
    }
    final bytes = <int>[];
    await for (final chunk in res) {
      bytes.addAll(chunk);
    }
    return bytes;
  } finally {
    client.close();
  }
}

Future<void> _extractBinary({
  required List<int> archiveBytes,
  required String archiveExtension,
  required String memberName,
  required String destPath,
}) async {
  // Use the system `unzip` / `tar` to avoid dragging in archive packages.
  final tempArchive = await File(
    '${Directory.systemTemp.path}/m4b-fetch-${DateTime.now().millisecondsSinceEpoch}.$archiveExtension',
  ).create();
  await tempArchive.writeAsBytes(archiveBytes);
  final destDir = Directory(destPath).parent;
  await destDir.create(recursive: true);

  if (archiveExtension == 'zip') {
    final result = await Process.run(
        'unzip', ['-jo', tempArchive.path, memberName, '-d', destDir.path]);
    if (result.exitCode != 0) {
      throw StateError('unzip failed: ${result.stderr}');
    }
    final extracted = File('${destDir.path}/$memberName');
    await extracted.rename(destPath);
  } else if (archiveExtension == 'tar.xz') {
    final result = await Process.run(
        'tar', ['-xJf', tempArchive.path, '-C', destDir.path]);
    if (result.exitCode != 0) {
      throw StateError('tar failed: ${result.stderr}');
    }
    // Caller should know the in-archive path; for static builds this is
    // typically a directory named after the build, with ffmpeg at the root.
    // Adjust per-source as needed.
  }

  await tempArchive.delete();

  if (!Platform.isWindows) {
    await Process.run('chmod', ['+x', destPath]);
  }
}

Future<void> _verifySha256(List<int> bytes, String expected) async {
  final actual = sha256.convert(bytes).toString();
  if (actual != expected) {
    throw StateError(
      'SHA-256 mismatch:\n  expected $expected\n  actual   $actual',
    );
  }
}

Future<void> main() async {
  final key = _platformKey();
  final sources = _sources[key];
  if (sources == null) {
    throw UnsupportedError('No sources configured for $key');
  }
  for (final src in sources) {
    stdout.writeln('Downloading ${src.url} ...');
    final bytes = await _download(src.url);
    await _verifySha256(bytes, src.sha256);

    final ext = src.url.endsWith('.tar.xz') ? 'tar.xz' : 'zip';
    final destPath = 'assets/bin/$key/${src.member}'
        '${Platform.isWindows ? '.exe' : ''}';
    await _extractBinary(
      archiveBytes: bytes,
      archiveExtension: ext,
      memberName: src.member +
          (Platform.isWindows && ext == 'zip' ? '.exe' : ''),
      destPath: destPath,
    );
    stdout.writeln('  -> $destPath');
  }
  stdout.writeln(
      'Done. Make sure assets/bin/$key/ is included in the Flutter asset bundle.');
}
```

(Add `crypto: ^3.0.3` to `pubspec.yaml` `dependencies`.)

The script intentionally calls out to `unzip`/`tar` rather than depending on a Dart archive package — both are present on all three target platforms (Windows ships `tar` and `expand-archive`/`unzip` is widely available; we can swap to `Expand-Archive` via PowerShell if `unzip` isn't always present in CI).

- [ ] **Step 3: Run the script on the dev machine**

```bash
flutter pub get
dart run tool/fetch_ffmpeg.dart
```

Expected: `assets/bin/<platform>/ffmpeg` and `assets/bin/<platform>/ffprobe` exist and run (`assets/bin/macos-arm64/ffmpeg -version`).

- [ ] **Step 4: Declare the directory in `pubspec.yaml`**

Under the `flutter:` key, add (or merge with existing assets):

```yaml
flutter:
  assets:
    - assets/bin/
```

Note: Flutter's bundled assets are read-only and not directly executable. We will instead resolve the binary by copying it out of the asset bundle into the user's application support directory at first launch — that is `BundledBinaryResolver`'s job in Task 23.

- [ ] **Step 5: Commit**

```bash
git add tool/fetch_ffmpeg.dart pubspec.yaml pubspec.lock README.md
git commit --no-gpg-sign -m "Add fetch_ffmpeg build-time binary downloader"
```

---

### Task 23: `BundledBinaryResolver` and main wiring

**Files:**
- Create: `lib/data/bundled_binary_resolver.dart`
- Modify: `lib/main.dart`
- Test: `test/data/bundled_binary_resolver_test.dart`

The resolver, on first call, copies the relevant `ffmpeg` and `ffprobe` binaries from the asset bundle into the platform-specific application support directory, marks them executable, and returns those paths. Subsequent calls return the cached paths without copying.

- [ ] **Step 1: Failing test**

Create `test/data/bundled_binary_resolver_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/data/bundled_binary_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('extracts ffmpeg and ffprobe from assets into the support directory',
      () async {
    final tempSupport =
        await Directory.systemTemp.createTemp('m4b-bundled-');
    addTearDown(() => tempSupport.delete(recursive: true));

    // Pretend asset loader: returns canned bytes for the two known assets.
    final loader = (String key) async {
      if (key.endsWith('/ffmpeg') || key.endsWith('/ffmpeg.exe')) {
        return ByteData.view(Uint8List.fromList([0x7F, 0x45, 0x4C, 0x46]).buffer);
      }
      if (key.endsWith('/ffprobe') || key.endsWith('/ffprobe.exe')) {
        return ByteData.view(Uint8List.fromList([0x7F, 0x45, 0x4C, 0x46]).buffer);
      }
      throw FlutterError('asset not found: $key');
    };

    final resolver = BundledBinaryResolver(
      assetLoader: loader,
      supportDirOverride: tempSupport.path,
    );

    final ffmpeg = await resolver.resolveFfmpeg();
    final ffprobe = await resolver.resolveFfprobe();

    expect(File(ffmpeg).existsSync(), isTrue);
    expect(File(ffprobe).existsSync(), isTrue);
    if (!Platform.isWindows) {
      // Should be marked executable.
      final stat = File(ffmpeg).statSync();
      expect(stat.modeString().contains('x'), isTrue);
    }
  });
}
```

- [ ] **Step 2: Run, see failure**

Run: `flutter test test/data/bundled_binary_resolver_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `BundledBinaryResolver`**

Create `lib/data/bundled_binary_resolver.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:path/path.dart' as p;

import 'binary_resolver.dart';

typedef AssetLoader = Future<ByteData> Function(String key);

/// Copies bundled ffmpeg/ffprobe binaries out of the asset bundle into the
/// app's support directory on first use, then returns those paths.
class BundledBinaryResolver implements BinaryResolver {
  BundledBinaryResolver({
    AssetLoader? assetLoader,
    String? supportDirOverride,
  })  : _assetLoader = assetLoader ?? rootBundle.load,
        _supportDirOverride = supportDirOverride;

  final AssetLoader _assetLoader;
  final String? _supportDirOverride;
  String? _cachedFfmpeg;
  String? _cachedFfprobe;

  static String _platformKey() {
    if (Platform.isMacOS) {
      return Platform.version.contains('arm64') ? 'macos-arm64' : 'macos-x64';
    }
    if (Platform.isWindows) return 'windows-x64';
    if (Platform.isLinux) return 'linux-x64';
    throw UnsupportedError('Unsupported: ${Platform.operatingSystem}');
  }

  Future<String> _supportDir() async {
    if (_supportDirOverride != null) return _supportDirOverride!;
    // Default: ~/Library/Application Support/m4b_chapterizer or platform equivalent.
    // Dev convenience — production code would use path_provider, but to keep
    // this MVP free of an extra package we synthesize a reasonable default.
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    final base = Platform.isMacOS
        ? p.join(home, 'Library', 'Application Support', 'm4b_chapterizer')
        : Platform.isWindows
            ? p.join(home, 'AppData', 'Roaming', 'm4b_chapterizer')
            : p.join(home, '.local', 'share', 'm4b_chapterizer');
    final dir = Directory(base);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  Future<String> _extract(String name) async {
    final platformKey = _platformKey();
    final exeSuffix = Platform.isWindows ? '.exe' : '';
    final assetPath = 'assets/bin/$platformKey/$name$exeSuffix';
    final destPath = p.join(await _supportDir(), '$name$exeSuffix');
    final destFile = File(destPath);
    if (!destFile.existsSync()) {
      final data = await _assetLoader(assetPath);
      await destFile.writeAsBytes(data.buffer.asUint8List());
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', destPath]);
      }
    }
    return destPath;
  }

  Future<String> resolveFfmpeg() async => _cachedFfmpeg ??= await _extract('ffmpeg');
  Future<String> resolveFfprobe() async => _cachedFfprobe ??= await _extract('ffprobe');

  @override
  String get ffmpeg {
    if (_cachedFfmpeg == null) {
      throw StateError('Call resolveFfmpeg() before reading .ffmpeg');
    }
    return _cachedFfmpeg!;
  }

  @override
  String get ffprobe {
    if (_cachedFfprobe == null) {
      throw StateError('Call resolveFfprobe() before reading .ffprobe');
    }
    return _cachedFfprobe!;
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/data/bundled_binary_resolver_test.dart`
Expected: pass.

- [ ] **Step 5: Wire `BundledBinaryResolver` into `main.dart`**

Replace the body of `main()` in `lib/main.dart` with:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final resolver = BundledBinaryResolver();
  await resolver.resolveFfmpeg();
  await resolver.resolveFfprobe();
  runApp(
    ProviderScope(
      overrides: [
        bookbinderProvider.overrideWithValue(
          FfmpegBookbinder(
            runner: const SystemProcessRunner(),
            binaries: resolver,
          ),
        ),
      ],
      child: const M4bChapterizerApp(),
    ),
  );
}
```

Add the import for `BundledBinaryResolver`.

- [ ] **Step 6: Run the full test suite**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 7: Smoke-test the app**

Run:
```bash
dart run tool/fetch_ffmpeg.dart
flutter run -d macos
```

Open `test/fixtures/sample.m4b` and verify the same behaviors as Phase 7's smoke test, but now with the bundled ffmpeg.

- [ ] **Step 8: Commit**

```bash
git add lib/main.dart lib/data/bundled_binary_resolver.dart test/data/bundled_binary_resolver_test.dart
git commit --no-gpg-sign -m "Add BundledBinaryResolver and wire bundled ffmpeg into app"
```

---

## Final verification

- [ ] **Run the entire test suite**

Run: `flutter test`
Expected: all tests pass with no skipped tests on a machine that has ffmpeg on PATH.

- [ ] **Run the full app on macOS, Windows, and Linux** and exercise the golden path:
  1. Open the fixture m4b.
  2. Edit the title.
  3. Add a chapter.
  4. Set its start using "Set start to playhead" while playing.
  5. Save (overwrite).
  6. Close and reopen — verify changes persisted.
  7. Save As to a new file — verify the new file plays in a third-party audiobook player.
