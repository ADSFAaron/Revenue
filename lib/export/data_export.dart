import 'dart:convert';

import '../models/app_user.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../models/store.dart';

/// The shop's own records, in formats that outlive this app.
///
/// **Not the same job as the Excel report.** [StatisticsWorkbook] writes a
/// period's rollups for somebody to read — sheets, headings, totals. This
/// writes what actually happened, one row per thing, for a bookkeeper's
/// spreadsheet or for keeping. The two are different needs and a multi-sheet
/// report answers only the first: nobody pivots a workbook laid out for
/// reading, and nobody restores from one.
///
/// Everything here is a pure function over data already fetched, which is what
/// makes it testable — the formats are the part worth being sure about, and
/// they are exactly the part that a screen with a fetch in it hides.
class DataExport {
  const DataExport._();

  /// Byte-order mark.
  ///
  /// Excel on Windows reads a UTF-8 CSV as the system's legacy code page
  /// unless the file opens with this, which turns every Chinese dish name into
  /// mojibake. It is three bytes and it is the difference between the file
  /// working and looking corrupted to the person this export is for.
  static const String _bom = '﻿';

  /// One row per order. What a bookkeeper reconciles against.
  static String ordersCsv(
    List<Order> orders, {
    required Store store,
    Map<String, String> staffNames = const {},
  }) {
    final platforms = {
      for (final platform in store.deliveryPlatforms) platform.id: platform.name
    };
    final payments = {
      for (final method in store.paymentMethods) method.id: method.name
    };

    final rows = <List<Object?>>[
      const [
        'business_date',
        'order_no',
        'placed_at',
        'status',
        'channel',
        'guests',
        'payment_method',
        'delivery_platform',
        'subtotal',
        'discount',
        'discount_reason',
        'tax',
        'commission',
        'total',
        'cost',
        'profit',
        'rung_up_by',
        'voided_at',
        'void_reason',
        'order_id',
      ],
      for (final order in orders)
        [
          order.businessDate,
          order.orderNo,
          _timestamp(order.placedAt),
          order.status.id,
          order.channel.label,
          order.guestCount,
          payments[order.paymentMethodId] ?? order.paymentMethodId,
          platforms[order.deliveryPlatformId] ?? order.deliveryPlatformId,
          order.subtotal,
          order.discountAmount,
          order.discountReason,
          order.taxAmount,
          order.commissionAmount,
          order.total,
          order.totalCost,
          order.total - order.totalCost,
          _who(order.createdBy, staffNames),
          _timestamp(order.voidedAt),
          order.voidReason,
          order.id,
        ],
    ];
    return _csv(rows);
  }

  /// One row per dish sold. What anything per-item is pivoted from.
  ///
  /// Voided orders are included, marked, rather than filtered out. An export
  /// that silently drops them cannot be reconciled against the till's own
  /// numbers, and "why is my export short" is a worse problem than a column
  /// somebody has to filter on.
  static String orderLinesCsv(
    List<Order> orders, {
    Map<String, String> categoryNames = const {},
  }) {
    final rows = <List<Object?>>[
      const [
        'business_date',
        'order_no',
        'placed_at',
        'status',
        'channel',
        'item',
        'category',
        'qty',
        'unit_price',
        'unit_cost',
        'line_revenue',
        'line_cost',
        'line_profit',
        'note',
        'item_id',
        'order_id',
      ],
      for (final order in orders)
        for (final line in order.items)
          [
            order.businessDate,
            order.orderNo,
            _timestamp(order.placedAt),
            order.status.id,
            order.channel.label,
            line.name,
            categoryNames[line.categoryId] ?? line.categoryId,
            line.qty,
            line.unitPrice,
            line.unitCost,
            line.unitPrice * line.qty,
            line.unitCost * line.qty,
            (line.unitPrice - line.unitCost) * line.qty,
            line.note,
            line.itemId,
            order.id,
          ],
    ];
    return _csv(rows);
  }

  /// Everything, as one JSON document.
  ///
  /// The twin of account deletion: the same shop, written out instead of
  /// removed. Orders carry their lines nested rather than flattened, because
  /// this one is for keeping rather than for reading — a backup that has
  /// thrown away the shape of an order cannot put one back.
  static String backupJson({
    required Store store,
    required List<Order> orders,
    required List<MenuItem> menu,
    required List<AppUser> staff,
    required String fromBusinessDate,
    required String toBusinessDate,
    required String appVersion,
  }) {
    final document = {
      'format': 'revenue.backup',
      // Bumped when the shape changes in a way something reading this would
      // care about. Nothing reads it yet, and that is exactly when it is cheap
      // to start writing.
      'formatVersion': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'appVersion': appVersion,
      'range': {'from': fromBusinessDate, 'to': toBusinessDate},
      'store': {
        'id': store.id,
        'name': store.name,
        'currency': store.currency,
        'timezone': store.timezone,
        'taxRate': store.taxRate,
        'taxIncluded': store.taxIncluded,
        'dayCutoffHour': store.dayCutoffHour,
        'idleTimeoutMinutes': store.idleTimeoutMinutes,
        'businessHours': store.businessHours,
        'targets': store.targets.toMap(),
        'categories': [for (final c in store.categories) c.toMap()],
        'paymentMethods': [for (final m in store.paymentMethods) m.toMap()],
        'deliveryPlatforms': [for (final p in store.deliveryPlatforms) p.toMap()],
      },
      'menu': [
        for (final item in menu) {'id': item.id, ...item.toMap()},
      ],
      // Names and roles, not credentials. There is nothing here that could
      // sign anybody in, and an export that carried one would be the worst
      // file this app knows how to write.
      'staff': [
        for (final person in staff)
          {
            'uid': person.uid,
            'email': person.email,
            'displayName': person.displayName,
            'role': person.role.id,
            'active': person.active,
          },
      ],
      'orders': [for (final order in orders) _orderJson(order)],
    };

    // Indented. A backup nobody can read is a backup nobody checks, and the
    // size difference is nothing next to being able to open it and see the
    // shop in there.
    return const JsonEncoder.withIndent('  ').convert(document);
  }

  static Map<String, Object?> _orderJson(Order order) => {
        'id': order.id,
        'orderNo': order.orderNo,
        'businessDate': order.businessDate,
        'placedAt': _timestamp(order.placedAt),
        'hourOfDay': order.hourOfDay,
        'weekday': order.weekday,
        'channel': order.channel.id,
        'guestCount': order.guestCount,
        'deliveryPlatformId': order.deliveryPlatformId,
        'commissionRate': order.commissionRate,
        'commissionAmount': order.commissionAmount,
        'paymentMethodId': order.paymentMethodId,
        'subtotal': order.subtotal,
        'discountAmount': order.discountAmount,
        'discountReason': order.discountReason,
        'taxAmount': order.taxAmount,
        'total': order.total,
        'totalCost': order.totalCost,
        'status': order.status.id,
        'voidedAt': _timestamp(order.voidedAt),
        'voidedBy': order.voidedBy,
        'voidReason': order.voidReason,
        'createdBy': order.createdBy,
        'createdAt': _timestamp(order.createdAt),
        'updatedAt': _timestamp(order.updatedAt),
        'items': [
          for (final line in order.items)
            {
              'itemId': line.itemId,
              'name': line.name,
              'categoryId': line.categoryId,
              'unitPrice': line.unitPrice,
              'unitCost': line.unitCost,
              'qty': line.qty,
              'note': line.note,
            },
        ],
      };

  static String _who(String? uid, Map<String, String> names) {
    if (uid == null || uid.isEmpty) return '';
    return names[uid] ?? uid;
  }

  static String? _timestamp(DateTime? at) => at?.toIso8601String();

  static String _csv(List<List<Object?>> rows) {
    final buffer = StringBuffer(_bom);
    for (final row in rows) {
      buffer.writeln(row.map(_field).join(','));
    }
    return buffer.toString();
  }

  /// RFC 4180, plus one thing RFC 4180 does not cover.
  ///
  /// A spreadsheet treats a cell opening with `=`, `+`, `-` or `@` as a
  /// formula, so a dish named `=1+1` — or anything a menu photo import read
  /// off a paper menu — is executed when the file is opened. The standard
  /// mitigation is a leading apostrophe, and it is applied only to text: the
  /// numeric columns here are produced by this file, never typed by anybody,
  /// so a negative total stays a negative total.
  static String _field(Object? value) {
    if (value == null) return '';
    if (value is num) return '$value';

    var text = '$value';
    if (text.isNotEmpty && '=+-@\t\r'.contains(text[0])) {
      text = "'$text";
    }
    if (text.contains(RegExp(r'[",\n\r]'))) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }
}
