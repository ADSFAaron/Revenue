import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'save_outcome.dart';

/// Hands the bytes to the browser as an ordinary download.
///
/// There is no file system to choose a folder in, so the object URL is created,
/// clicked and revoked in the same breath. Revoking matters: without it the
/// blob is held for the life of the tab, and a shop exporting a year of orders
/// several times over would be holding every copy in memory.
Future<SaveOutcome> saveBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName;
  anchor.click();
  web.URL.revokeObjectURL(url);
  return const SaveOutcome.downloaded();
}
