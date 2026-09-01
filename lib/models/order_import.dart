import 'dart:convert';
import 'dart:typed_data';

import '../database/data_exception.dart';

/// Reading a delivery platform's own statement back into the till.
///
/// **Why an interface with nothing behind it yet.**
///
/// A shop selling through UberEats or foodpanda has those orders in the
/// platform's back office and nowhere else, so the day's takings in this app
/// are wrong by exactly the amount the platform sold. The direct fix is the
/// platform's order API, and every one of those is partner-gated: an agreement
/// and a certification, not a signup. What every platform *does* give a
/// merchant without asking anybody is a downloadable statement.
///
/// So the statement is the way in — but nobody here has seen a real one yet,
/// and a parser written against a guess at the columns is worse than no parser
/// at all: it would import numbers that look right. [kOrderStatementParsers] is
/// therefore empty on purpose. What is settled is the shape of the seam, so
/// that adding a real format later is one class and one line of registration.
///
/// Two things are deliberately *not* decided here, because a real statement
/// decides them:
///
///  * How an imported order is de-duplicated. [ImportedOrder.externalId] is the
///    platform's own order number and is the obvious key, but `Order` has no
///    field for it yet — importing the same statement twice must not double the
///    month, and that is a schema decision, not a parser one.
///  * How a platform's line items map onto this store's menu. Names will not
///    match, and a statement may carry only an order total.
class StatementFile {
  const StatementFile({required this.name, required this.bytes});

  /// As it was named on disk. Parsers are allowed to use it — platforms name
  /// their exports predictably — but not to rely on it alone.
  final String name;

  final Uint8List bytes;

  /// The file as text, for the CSV-shaped formats.
  ///
  /// Malformed bytes are replaced rather than thrown on: a statement that is
  /// half-readable should reach a parser, which can then say what it found.
  /// An XLSX is a zip and will come out as rubbish here — that is what
  /// [OrderStatementParser.canParse] is for.
  String get text => utf8.decode(bytes, allowMalformed: true);

  /// Lower case, without the dot. Empty when the name carries no extension.
  String get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  factory StatementFile.fromText(String text, {String name = 'pasted.csv'}) =>
      StatementFile(
        name: name,
        bytes: Uint8List.fromList(utf8.encode(text)),
      );
}

/// One line of an imported order, where the statement itemises them at all.
class ImportedOrderLine {
  const ImportedOrderLine({
    required this.name,
    this.qty = 1,
    this.unitPrice = 0,
    this.externalItemId,
  });

  /// As the platform printed it. Mapping this onto a dish on this menu is a
  /// separate step and a separate decision.
  final String name;

  final int qty;

  /// Whole currency units, as charged to the customer.
  final int unitPrice;

  /// The platform's own id for the dish, where it gives one. Worth far more
  /// than the name for mapping, because it survives a rename.
  final String? externalItemId;
}

/// One order as read out of a statement, before anything is written.
///
/// Everything past [externalId], [placedAt] and [total] is optional because a
/// statement may not carry it: some are a full itemised export, some are a
/// payout summary with one row per order and no dishes at all. A parser fills
/// what its format actually has and leaves the rest alone rather than
/// inventing it.
class ImportedOrder {
  const ImportedOrder({
    required this.externalId,
    required this.placedAt,
    required this.total,
    this.commissionAmount,
    this.lines = const [],
    this.guestCount,
    this.note,
    this.raw = const {},
  });

  /// The platform's own order number — the de-duplication key.
  final String externalId;

  final DateTime placedAt;

  /// What the customer paid, in whole currency units.
  final int total;

  /// What the platform kept. Left null when the statement does not break it
  /// out — null and zero are different answers, and a delivery order booked at
  /// zero commission reads as far more profitable than it was.
  final int? commissionAmount;

  final List<ImportedOrderLine> lines;

  final int? guestCount;

  /// Anything a person needs to see that has no field of its own.
  final String? note;

  /// The source row, kept for the preview and for working out what a
  /// disagreement came from. Never written to Firestore.
  final Map<String, String> raw;
}

/// Turns one platform's export into orders.
///
/// Implementations are pure: bytes in, orders out, no network and no writes.
/// That is what makes a format testable against a real sample file without a
/// store, an account or an emulator.
abstract class OrderStatementParser {
  const OrderStatementParser();

  /// Stable identifier, e.g. `ubereats_csv`. Goes in the audit trail when an
  /// import is eventually written.
  String get id;

  /// What a shop calls it: "UberEats", "foodpanda".
  String get platformName;

  /// Whether this parser recognises the file — by its header row, not by its
  /// filename alone. Must not throw.
  bool canParse(StatementFile file);

  /// Reads the whole file. Throws [StatementFormatException] when the file is
  /// recognisably this format but malformed.
  List<ImportedOrder> parse(StatementFile file);
}

/// The formats that can be read today.
///
/// Empty, and not an oversight: see the note on [StatementFile]. Adding one is
/// a class implementing [OrderStatementParser] plus its entry here — every
/// screen goes through [parserFor], so nothing else has to change.
const List<OrderStatementParser> kOrderStatementParsers = [];

/// The parser for a file, or null when nothing recognises it.
///
/// Null rather than a best guess. The failure a shop can act on is "this app
/// does not know this format yet"; a parser applied to a file it does not
/// understand produces numbers instead, and numbers are believed.
OrderStatementParser? parserFor(
  StatementFile file, {
  List<OrderStatementParser> parsers = kOrderStatementParsers,
}) {
  for (final parser in parsers) {
    if (parser.canParse(file)) return parser;
  }
  return null;
}

/// A file that is the right format but the wrong shape.
class StatementFormatException implements AppException {
  const StatementFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'StatementFormatException: $message';
}
