import 'package:intl/intl.dart';

import '../models/store.dart';

/// The currency a store falls back to before its document has loaded.
const String kDefaultCurrency = 'TWD';

/// Formats an amount in the store's own currency.
///
/// Was `NumberFormat.currency(...)` duplicated in statistics.dart and
/// analysis.dart, while transaction.dart, overview.dart, store.dart,
/// addorder.dart and both order-history screens hard-coded the string `'NTD'`
/// in front of a plain number — so a shop set to anything but TWD had six
/// screens lying about which currency it was counting in.
NumberFormat moneyFormat(Store? store) =>
    moneyFormatFor(store?.currency ?? kDefaultCurrency);

/// For the screens that hold a currency code but not the whole store.
NumberFormat moneyFormatFor(String currency) => NumberFormat.currency(
      // Firestore holds money as whole units — see the schema notes in
      // docs/refactor-plan.md — so a decimal place would only ever show '.00'.
      name: currency,
      symbol: currency == 'TWD' ? 'NT\$' : null,
      decimalDigits: 0,
    );

/// A tax rate as a percentage, without trailing zeros.
///
/// 0.05 reads "5", 0.015 reads "1.5", 0.1025 reads "10.25". The trimming is
/// the point: `toStringAsFixed(0)` was in three places and it did not round a
/// display, it *erased a setting* — a shop on 1.5% saw "2%" on the settings
/// row, "2%" on the order summary, and a dialog that opened pre-filled with 2
/// and overwrote the real rate the moment somebody pressed Save.
///
/// Two decimal places, because the multiplication back out of a stored double
/// is not exact — 0.015 × 100 is 1.5000000000000002 — and no tax authority
/// bills in thousandths of a percent.
String formatTaxPercent(double rate) {
  final percent = rate * 100;
  final rounded = double.parse(percent.toStringAsFixed(2));
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toString();
}

/// Turns what somebody typed into a rate, or null if it is not a usable one.
///
/// Rejects the empty string, anything unparseable, and anything outside 0–100
/// — all three of which used to arrive at Firestore as either a crash or a
/// silent zero.
double? parseTaxPercent(String input) {
  final percent = double.tryParse(input.trim());
  if (percent == null || percent.isNaN || percent < 0 || percent > 100) {
    return null;
  }
  return double.parse((percent / 100).toStringAsFixed(6));
}
