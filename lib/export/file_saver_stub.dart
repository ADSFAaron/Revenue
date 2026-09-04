import 'dart:typed_data';

import 'save_outcome.dart';

Future<SaveOutcome> saveBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) =>
    throw UnsupportedError('Exporting is not supported on this platform.');
