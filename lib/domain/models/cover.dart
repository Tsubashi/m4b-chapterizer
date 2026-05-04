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
