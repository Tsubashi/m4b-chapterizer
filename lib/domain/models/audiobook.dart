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

extension AudiobookDiff on Audiobook {
  /// Returns the index of the first chapter that differs between this and
  /// [other], using `Chapter`'s value equality. If lengths differ, the
  /// index is the shorter list's length (the first divergent slot).
  /// Returns null when every shared chapter is equal AND lengths match.
  int? firstDifferingChapterIndex(Audiobook other) {
    final n =
        chapters.length < other.chapters.length ? chapters.length : other.chapters.length;
    for (var i = 0; i < n; i++) {
      if (chapters[i] != other.chapters[i]) return i;
    }
    if (chapters.length != other.chapters.length) return n;
    return null;
  }
}
