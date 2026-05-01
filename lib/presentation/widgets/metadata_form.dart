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
