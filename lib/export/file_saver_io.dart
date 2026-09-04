import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'save_outcome.dart';

/// Writes a file into the app's own storage.
///
/// Deliberately not into a shared folder: on Android that needs a runtime
/// storage permission, and asking for access to a person's whole photo and
/// document library so that a shop can save a spreadsheet is out of proportion
/// to what is being done. The path is reported back so the file can be found,
/// and sharing it onward is the platform's own business.
Future<SaveOutcome> saveBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  // On Android the external app directory is reachable over USB and from a
  // file manager, which the internal documents directory is not; elsewhere
  // there is no such distinction.
  Directory? directory;
  if (Platform.isAndroid) {
    directory = await getExternalStorageDirectory();
  }
  directory ??= await getApplicationDocumentsDirectory();

  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  await file.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  return SaveOutcome.written(file.path);
}
