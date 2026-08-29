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
