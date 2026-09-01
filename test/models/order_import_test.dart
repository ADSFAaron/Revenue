import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:Revenue/models/order_import.dart';

/// The seam a platform statement comes in through. There is no parser behind
/// it yet — see `models/order_import.dart` — so what is worth pinning down is
/// the one behaviour that decides whether a wrong import is possible at all:
/// a file nobody recognises is refused, never handed to the nearest parser.
class _FakeCsvParser extends OrderStatementParser {
  const _FakeCsvParser();

  @override
  String get id => 'fake_csv';

  @override
  String get platformName => 'Fake';

  @override
  bool canParse(StatementFile file) =>
      file.extension == 'csv' && file.text.startsWith('order_id,');

  @override
  List<ImportedOrder> parse(StatementFile file) => [
        ImportedOrder(
          externalId: file.text.trim().split('\n').last.split(',').first,
          placedAt: DateTime(2026, 8, 30, 12, 30),
          total: 350,
        ),
      ];
}

void main() {
  const parsers = [_FakeCsvParser()];

  test('nothing ships that would read a format it has not seen', () {
    // Deliberately empty: a parser written against a guess at the columns
    // imports numbers that look right, which is worse than importing nothing.
    expect(kOrderStatementParsers, isEmpty);
  });

  test('an unrecognised file gets no parser rather than the nearest one', () {
    final file = StatementFile.fromText('date;amount\n2026-08-30;350',
        name: 'payouts.csv');
    expect(parserFor(file, parsers: parsers), isNull);
  });

  test('a recognised file finds its parser', () {
    final file =
        StatementFile.fromText('order_id,total\nA-771,350', name: 'ue.csv');
    final parser = parserFor(file, parsers: parsers);
    expect(parser?.id, 'fake_csv');
    expect(parser!.parse(file).single.externalId, 'A-771');
  });

  test('the extension comes off the name, however it is written', () {
    final empty = Uint8List(0);
    expect(StatementFile(name: 'Statement.CSV', bytes: empty).extension, 'csv');
    expect(StatementFile(name: 'statement', bytes: empty).extension, '');
  });

  test('bytes that are not text do not throw on the way to canParse', () {
    // An XLSX is a zip. `canParse` must be able to look and say no.
    final xlsx = StatementFile(
        name: 'x.xlsx', bytes: Uint8List.fromList([0x50, 0x4b, 0x03, 0xff]));
    expect(() => xlsx.text, returnsNormally);
    expect(parserFor(xlsx, parsers: parsers), isNull);
  });
}
