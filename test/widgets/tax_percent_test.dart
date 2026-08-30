import 'package:flutter_test/flutter_test.dart';

import 'package:Revenue/widgets/money.dart';

/// A shop on 1.5% could not save 1.5%. The input took digits only, the parse
/// was `int.tryParse`, and every display was `toStringAsFixed(0)` — so the
/// setting was unreachable in three separate ways, and the dialog re-opened
/// pre-filled with a rounded number that overwrote the real one on Save.
void main() {
  group('formatting', () {
    test('drops the decimals a whole percent does not need', () {
      expect(formatTaxPercent(0.05), '5');
      expect(formatTaxPercent(0), '0');
      expect(formatTaxPercent(0.1), '10');
    });

    test('keeps the ones that carry the setting', () {
      expect(formatTaxPercent(0.015), '1.5');
      expect(formatTaxPercent(0.005), '0.5');
      expect(formatTaxPercent(0.1025), '10.25');
    });

    test('survives the round trip a double makes of 1.5%', () {
      // 0.015 * 100 is 1.5000000000000002 in binary floating point.
      expect(formatTaxPercent(parseTaxPercent('1.5')!), '1.5');
      expect(formatTaxPercent(parseTaxPercent('8.25')!), '8.25');
      expect(formatTaxPercent(parseTaxPercent('5')!), '5');
    });
  });

  group('parsing', () {
    test('accepts a decimal rate', () {
      expect(parseTaxPercent('1.5'), closeTo(0.015, 1e-9));
      expect(parseTaxPercent('5'), closeTo(0.05, 1e-9));
      expect(parseTaxPercent(' 8.25 '), closeTo(0.0825, 1e-9));
    });

    test('refuses what is not a rate', () {
      expect(parseTaxPercent(''), isNull);
      expect(parseTaxPercent('abc'), isNull);
      expect(parseTaxPercent('-1'), isNull);
      expect(parseTaxPercent('101'), isNull);
      expect(parseTaxPercent('.'), isNull);
    });

    test('allows the ends of the range', () {
      expect(parseTaxPercent('0'), 0);
      expect(parseTaxPercent('100'), closeTo(1.0, 1e-9));
    });
  });
}
