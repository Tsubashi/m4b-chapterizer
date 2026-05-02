import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/audiobook.dart';
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

  late final _titleFocus = FocusNode()..addListener(_onFocusChanged);
  late final _authorFocus = FocusNode()..addListener(_onFocusChanged);
  late final _narratorFocus = FocusNode()..addListener(_onFocusChanged);
  late final _albumFocus = FocusNode()..addListener(_onFocusChanged);
  late final _genreFocus = FocusNode()..addListener(_onFocusChanged);
  late final _yearFocus = FocusNode()..addListener(_onFocusChanged);
  late final _descriptionFocus = FocusNode()..addListener(_onFocusChanged);

  void _onFocusChanged() {
    final anyFocused = [
      _titleFocus,
      _authorFocus,
      _narratorFocus,
      _albumFocus,
      _genreFocus,
      _yearFocus,
      _descriptionFocus,
    ].any((n) => n.hasFocus);
    final notifier = ref.read(editorProvider.notifier);
    if (anyFocused) {
      notifier.beginFieldEdit();
    } else {
      notifier.endFieldEdit();
    }
  }

  /// Updates each controller in place if it disagrees with the audiobook's
  /// value. Loop-safe: when the user types, `onChanged` fires `setX` which
  /// updates the audiobook, so by the time we re-enter `build`, the controller
  /// and audiobook agree and we no-op. After undo/redo (or opening a new
  /// file), the audiobook changes without a corresponding controller write,
  /// so the comparison fires and we update.
  void _syncControllersFromAudiobook(Audiobook book) {
    void sync(TextEditingController c, String value) {
      if (c.text != value) c.text = value;
    }

    sync(_title, book.title ?? '');
    sync(_author, book.author ?? '');
    sync(_narrator, book.narrator ?? '');
    sync(_album, book.album ?? '');
    sync(_genre, book.genre ?? '');
    sync(_description, book.description ?? '');
    sync(_year, book.year?.toString() ?? '');
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
    _titleFocus.dispose();
    _authorFocus.dispose();
    _narratorFocus.dispose();
    _albumFocus.dispose();
    _genreFocus.dispose();
    _yearFocus.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorProvider);
    final book = state.audiobook;
    if (book != null) _syncControllersFromAudiobook(book);
    final notifier = ref.read(editorProvider.notifier);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field('Title', const ValueKey('metadata.title'), _title,
              _titleFocus, notifier.setTitle),
          _field('Author', const ValueKey('metadata.author'), _author,
              _authorFocus, notifier.setAuthor),
          _field('Narrator', const ValueKey('metadata.narrator'), _narrator,
              _narratorFocus, notifier.setNarrator),
          _field('Album', const ValueKey('metadata.album'), _album,
              _albumFocus, notifier.setAlbum),
          _field('Genre', const ValueKey('metadata.genre'), _genre,
              _genreFocus, notifier.setGenre),
          _field('Year', const ValueKey('metadata.year'), _year, _yearFocus,
              (s) => notifier.setYear(int.tryParse(s))),
          _field('Description', const ValueKey('metadata.description'),
              _description, _descriptionFocus, notifier.setDescription,
              maxLines: 3),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    Key key,
    TextEditingController controller,
    FocusNode focusNode,
    void Function(String) onChanged, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        key: key,
        focusNode: focusNode,
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: onChanged,
      ),
    );
  }
}
