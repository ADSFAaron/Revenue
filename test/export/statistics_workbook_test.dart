import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/export/statistics_workbook.dart';
import 'package:Revenue/models/daily_stats.dart';
import 'package:Revenue/models/stats_period.dart';
import 'package:Revenue/models/store.dart';

const store =
    Store(id: 'noodle/shop', name: 'Ah Ming Noodles', currency: 'TWD');

final days = [
  DailyStats(
    businessDate: '2026-08-17',
    orderCount: 40,
    guestCount: 55,
    revenue: 12000,
    cost: 4000,
    byItem: const {
      'a': ItemStat(
          itemId: 'a',
          name: 'Beef Noodles',
          qty: 30,
          revenue: 9000,
          cost: 3600),
      'b': ItemStat(
          itemId: 'b', name: 'Tea Egg', qty: 25, revenue: 3000, cost: 0),
    },
    byPayment: const {'cash': StatBucket(orders: 30, revenue: 9000)},
    byChannel: const {'dine_in': StatBucket(orders: 40, revenue: 12000)},
  ),
  DailyStats(
    businessDate: '2026-08-18',
    orderCount: 20,
    guestCount: 24,
    revenue: 6000,
    cost: 2200,
  ),
];

final period =
    StatsPeriod.containing(DateTime(2026, 8, 17), StatsGranularity.week);

void main() {
  test('produces a workbook that decodes back to the figures put in', () {
    final workbook =
        StatisticsWorkbook(store: store, period: period, days: days);
    final bytes = workbook.build().encode();
    expect(bytes, isNotNull);

    // Re-read the actual file bytes rather than inspecting the object we just
    // built — that is the only way to know the export is really openable.
    final reopened = Excel.decodeBytes(bytes!);
    expect(reopened.sheets.keys,
        containsAll(['Summary', 'Daily', 'Items', 'Categories']));
    expect(reopened.sheets.keys, isNot(contains('Sheet1')));

    String? cellAt(String sheet, int row, int col) =>
        reopened[sheet].rows[row][col]?.value?.toString();

    // Summary carries the added-up revenue, as a number.
    final summary = reopened['Summary'].rows;
    final revenueRow =
        summary.firstWhere((r) => r.first?.value?.toString() == 'Revenue');
    expect(revenueRow[1]?.value, isA<IntCellValue>());
    expect((revenueRow[1]!.value as IntCellValue).value, 18000);

    // Daily lists both days with their weekday resolved.
    expect(cellAt('Daily', 1, 0), '2026-08-17');
    expect(cellAt('Daily', 1, 1), 'Mon');
    expect(cellAt('Daily', 2, 0), '2026-08-18');
  });

  test('a dish with no cost exports a blank margin, not 100%', () {
    final rows = Excel.decodeBytes(
      StatisticsWorkbook(store: store, period: period, days: days)
          .build()
          .encode()!,
    )['Items']
        .rows;

    final egg = rows.firstWhere((r) => r.first?.value?.toString() == 'Tea Egg');
    final beef =
        rows.firstWhere((r) => r.first?.value?.toString() == 'Beef Noodles');

    expect(egg.last?.value, isNull); // margin column left empty
    expect(beef.last?.value, isA<DoubleCellValue>());
    expect((beef.last!.value as DoubleCellValue).value, closeTo(0.6, 0.0001));
  });

  test('the filename survives a store name a file system would reject', () {
    final name =
        StatisticsWorkbook(store: store, period: period, days: days).fileName;
    expect(name, 'Ah_Ming_Noodles_2026-08-17_to_2026-08-23.xlsx');
    expect(name, isNot(contains('/')));
  });
}
