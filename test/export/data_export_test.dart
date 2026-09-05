import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/export/data_export.dart';
import 'package:Revenue/models/app_user.dart';
import 'package:Revenue/models/menu_item.dart';
import 'package:Revenue/models/order.dart';
import 'package:Revenue/models/store.dart';

/// The formats a shop's records leave in.
///
/// These are pure functions on purpose: the format is the part that has to be
/// right, and it is exactly the part a screen with a fetch in it hides. What is
/// pinned here is mostly the ways a CSV silently corrupts a shop's data —
/// encoding, quoting, and a spreadsheet running a dish name as a formula.
const store = Store(
  id: 'store-1',
  name: '好味小吃',
  categories: [StoreCategory(id: 'cat-main', name: '主食')],
  deliveryPlatforms: [DeliveryPlatform(id: 'foodpanda', name: 'foodpanda')],
);

Order order({
  String id = 'o1',
  int orderNo = 1,
  List<OrderLine> items = const [],
  OrderStatus status = OrderStatus.completed,
  String? createdBy,
  int total = 0,
  int totalCost = 0,
}) =>
    Order(
      id: id,
      orderNo: orderNo,
      businessDate: '2026-09-01',
      placedAt: DateTime.utc(2026, 9, 1, 12, 30),
      hourOfDay: 12,
      weekday: 2,
      items: items,
      status: status,
      createdBy: createdBy,
      total: total,
      totalCost: totalCost,
    );

List<String> rowsOf(String csv) =>
    const LineSplitter().convert(csv).where((l) => l.isNotEmpty).toList();

void main() {
  group('CSV', () {
    test('opens with a byte-order mark', () {
      // Without it, Excel on Windows reads a UTF-8 file as the system code page
      // and every Chinese dish name on the export becomes mojibake. Three
      // bytes, and the difference between the file working and looking broken
      // to the person it was made for.
      final csv = DataExport.ordersCsv([order()], store: store);
      expect(csv.codeUnitAt(0), 0xFEFF);
    });

    test('a dish name that is also a formula is not run by the spreadsheet',
        () {
      // Menu items can come out of a photo import, so the text in them is not
      // something this app chose. A cell opening with `=` is executed on open.
      final csv = DataExport.orderLinesCsv([
        order(items: [
          const OrderLine(
              itemId: 'i1', name: '=1+1', unitPrice: 100, unitCost: 40, qty: 1),
        ]),
      ]);

      expect(csv, contains("'=1+1"));
      expect(csv, isNot(contains(',=1+1')));
    });

    test('commas, quotes and newlines survive a round trip', () {
      final csv = DataExport.orderLinesCsv([
        order(items: [
          const OrderLine(
            itemId: 'i1',
            name: 'Rice, "large"',
            unitPrice: 100,
            unitCost: 40,
            qty: 2,
            note: 'no\nchilli',
          ),
        ]),
      ]);

      expect(csv, contains('"Rice, ""large"""'));
      expect(csv, contains('"no\nchilli"'));
    });

    test('numbers are never quoted or apostrophised', () {
      // The formula guard applies to text only. A negative figure is produced
      // by this file, not typed by anybody, and turning it into text would
      // break every sum downstream.
      final csv = DataExport.ordersCsv(
        [order(total: 1000, totalCost: 1200)],
        store: store,
      );
      expect(csv, contains(',-200,'), reason: 'profit stays a number');
    });

    test('a voided order is included and marked, not dropped', () {
      // An export that silently omits them cannot be reconciled against the
      // till, and "why is my export short" is the worse problem.
      final csv = DataExport.ordersCsv(
        [order(status: OrderStatus.voided)],
        store: store,
      );
      expect(rowsOf(csv), hasLength(2));
      expect(csv, contains('voided'));
    });

    test('ids are resolved to the names a person recognises', () {
      final csv = DataExport.ordersCsv(
        [order(createdBy: 'uid-1')],
        store: store,
        nameFor: (uid) => uid == 'uid-1' ? 'Ah-Ming' : '',
      );
      expect(csv, contains('Ah-Ming'));
      expect(csv, isNot(contains('uid-1,')));
    });

    test('an order with no staff on it leaves the cell empty', () {
      final csv = DataExport.ordersCsv([order()], store: store);
      expect(csv, isNot(contains('Not recorded')));
    });

    test('one row per line, across orders', () {
      final csv = DataExport.orderLinesCsv([
        order(id: 'o1', items: [
          const OrderLine(
              itemId: 'i1', name: 'A', unitPrice: 100, unitCost: 40, qty: 2),
          const OrderLine(
              itemId: 'i2', name: 'B', unitPrice: 50, unitCost: 10, qty: 1),
        ]),
        order(id: 'o2', orderNo: 2, items: [
          const OrderLine(
              itemId: 'i1', name: 'A', unitPrice: 100, unitCost: 40, qty: 1),
        ]),
      ]);

      expect(rowsOf(csv), hasLength(4), reason: 'a header and three lines');
      expect(csv, contains(',200,80,120,'), reason: 'two at 100, cost 40');
    });

    test('a category id is shown as its name', () {
      final csv = DataExport.orderLinesCsv(
        [
          order(items: [
            const OrderLine(
              itemId: 'i1',
              name: 'Rice',
              categoryId: 'cat-main',
              unitPrice: 100,
              unitCost: 40,
              qty: 1,
            ),
          ])
        ],
        categoryNames: {'cat-main': '主食'},
      );
      expect(csv, contains('主食'));
    });
  });

  group('JSON backup', () {
    String backup({List<Order> orders = const []}) => DataExport.backupJson(
          store: store,
          orders: orders,
          menu: const [MenuItem(id: 'i1', name: 'Rice', price: 100, cost: 40)],
          staff: const [
            AppUser(
              uid: 'uid-1',
              email: 'ming@example.test',
              displayName: 'Ah-Ming',
              storeId: 'store-1',
            ),
          ],
          fromBusinessDate: '2026-08-01',
          toBusinessDate: '2026-09-01',
          appVersion: '3.1.0+42',
        );

    test('is valid JSON and holds the whole shop', () {
      final decoded = jsonDecode(backup()) as Map<String, dynamic>;

      expect(decoded['format'], 'revenue.backup');
      expect(decoded['formatVersion'], 1);
      expect((decoded['store'] as Map)['name'], '好味小吃');
      expect(decoded['menu'], hasLength(1));
      expect(decoded['staff'], hasLength(1));
    });

    test('an order keeps its lines nested', () {
      // Flattening is right for the CSV and wrong here. A backup that has
      // thrown away the shape of an order cannot put one back.
      final decoded = jsonDecode(backup(orders: [
        order(items: [
          const OrderLine(
              itemId: 'i1', name: 'Rice', unitPrice: 100, unitCost: 40, qty: 2),
        ]),
      ])) as Map<String, dynamic>;

      final orders = decoded['orders'] as List;
      expect(orders, hasLength(1));
      expect((orders.first as Map)['items'], hasLength(1));
    });

    test('carries nothing that could sign anybody in', () {
      final text = backup().toLowerCase();
      for (final secret in ['password', 'passkey', 'credential', 'token']) {
        expect(text, isNot(contains(secret)), reason: 'no $secret in a backup');
      }
    });

    test('a shop that has not traded still backs up its menu and settings', () {
      final decoded = jsonDecode(backup()) as Map<String, dynamic>;
      expect(decoded['orders'], isEmpty);
      expect(decoded['menu'], hasLength(1));
    });
  });
}
