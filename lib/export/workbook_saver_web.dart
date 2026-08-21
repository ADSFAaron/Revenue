import 'package:excel/excel.dart';

import 'save_outcome.dart';

/// On the web the package hands the bytes to the browser itself, which starts
/// an ordinary download — there is no file system to choose a folder in.
Future<SaveOutcome> saveWorkbook({
  required Excel excel,
  required String fileName,
}) async {
  final bytes = excel.save(fileName: fileName);
  if (bytes == null) {
    throw StateError('The workbook could not be encoded.');
  }
  return const SaveOutcome.downloaded();
}
