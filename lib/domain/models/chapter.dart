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
