import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/export/workbook_saver.dart';

// Importing this at all is half the point: it forces the dart:io branch of the
// conditional export to compile. The web branch is covered by `flutter build
// web`, which cannot see dart:io.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('revenue_export_test');
    // path_provider talks to the host over a method channel that no unit test
    // has; standing in for it is what lets the real write be exercised.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('writes a workbook that reopens from disk', () async {
    final excel = Excel.createExcel();
    excel['Sheet1'].appendRow([TextCellValue('hello')]);

    final outcome = await saveWorkbook(excel: excel, fileName: 'saver_test.xlsx');

    expect(outcome.downloaded, isFalse);
    expect(outcome.path, endsWith('saver_test.xlsx'));
    expect(outcome.description, startsWith('Saved to '));

    final written = File(outcome.path!);
    expect(written.existsSync(), isTrue);
    // Reopened from the bytes actually on disk, not from the object in memory.
    final reopened = Excel.decodeBytes(written.readAsBytesSync());
    expect(reopened['Sheet1'].rows.first.first?.value?.toString(), 'hello');
  });
}
