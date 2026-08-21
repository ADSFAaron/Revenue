import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/models/stats_period.dart';

void main() {
  test('week runs Monday to Sunday', () {
    // 2026-08-21 is a Friday.
    final p = StatsPeriod.containing(DateTime(2026, 8, 21), StatsGranularity.week);
    expect(p.fromBusinessDate, '2026-08-17'); // Mon
    expect(p.toBusinessDate, '2026-08-23');   // Sun
    expect(p.dayCount, 7);
    expect(p.previous.fromBusinessDate, '2026-08-10');
    expect(p.next.fromBusinessDate, '2026-08-24');
  });

  test('month handles February and year boundaries', () {
    final feb = StatsPeriod.containing(DateTime(2024, 2, 15), StatsGranularity.month);
    expect(feb.toBusinessDate, '2024-02-29'); // leap year
    expect(feb.dayCount, 29);
    final jan = StatsPeriod.containing(DateTime(2026, 1, 5), StatsGranularity.month);
    expect(jan.previous.fromBusinessDate, '2025-12-01');
    expect(jan.previous.toBusinessDate, '2025-12-31');
    final dec = StatsPeriod.containing(DateTime(2025, 12, 5), StatsGranularity.month);
    expect(dec.next.fromBusinessDate, '2026-01-01');
  });

  test('partial month compares against the same days of the previous one', () {
    final today = DateTime(2026, 8, 3);
    final aug = StatsPeriod.containing(today, StatsGranularity.month);
    expect(aug.elapsedDays(today), 3);
    expect(aug.isComplete(today), isFalse);
    final cmp = aug.comparableTo(today);
    expect(cmp.fromBusinessDate, '2026-07-01');
    expect(cmp.toBusinessDate, '2026-07-03'); // not all of July
    expect(aug.comparisonLabel(today), 'vs same days last month');
  });

  test('finished month compares against the whole previous month', () {
    final today = DateTime(2026, 8, 21);
    final july = StatsPeriod.containing(DateTime(2026, 7, 10), StatsGranularity.month);
    expect(july.isComplete(today), isTrue);
    final cmp = july.comparableTo(today);
    expect(cmp.fromBusinessDate, '2026-06-01');
    expect(cmp.toBusinessDate, '2026-06-30');
    expect(july.comparisonLabel(today), 'vs previous month');
  });

  test('day paging crosses month boundaries', () {
    final d = StatsPeriod.containing(DateTime(2026, 9, 1), StatsGranularity.day);
    expect(d.previous.fromBusinessDate, '2026-08-31');
    expect(d.dayCount, 1);
  });

  test('switching granularity keeps you in the same part of the calendar', () {
    final june = StatsPeriod.containing(DateTime(2026, 6, 15), StatsGranularity.month);
    final asDay = june.withGranularity(StatsGranularity.day);
    expect(asDay.fromBusinessDate, '2026-06-01'); // not today
  });

  test('labels', () {
    final today = DateTime(2026, 8, 21);
    expect(StatsPeriod.containing(today, StatsGranularity.day).label(today), 'Today');
    expect(StatsPeriod.containing(DateTime(2026, 8, 20), StatsGranularity.day).label(today), 'Yesterday');
    expect(StatsPeriod.containing(today, StatsGranularity.month).label(today), 'This month');
    expect(StatsPeriod.containing(DateTime(2026, 5, 4), StatsGranularity.month).label(today), 'May 2026');
  });
}
