import 'package:excel/excel.dart';

import 'save_outcome.dart';

Future<SaveOutcome> saveWorkbook({
  required Excel excel,
  required String fileName,
}) =>
    throw UnsupportedError('Exporting is not supported on this platform.');
