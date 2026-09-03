import 'package:excel_plus/excel_plus.dart';

import 'save_outcome.dart';

Future<SaveOutcome> saveWorkbook({
  required Excel excel,
  required String fileName,
}) =>
    throw UnsupportedError('Exporting is not supported on this platform.');
