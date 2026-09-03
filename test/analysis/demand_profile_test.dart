import 'package:flutter_test/flutter_test.dart';

import 'package:Revenue/analysis/demand_profile.dart';
import 'package:Revenue/models/daily_stats.dart';
import 'package:Revenue/models/store.dart';

/// A trading day is not a calendar day. With the default 04:00 cutoff, an order
/// rung up at 01:00 belongs to the day that began the previous morning — it is
/// that day's *last* hour, not its first. Sorting the hours 0-23 put it first,
/// which drew the night's takings before the shop had opened and made the
/// overnight closure look like a quiet patch in the middle of service.
void main() {
  DailyStats dayWith(String businessDate, List<int> hours) => DailyStats(
        businessDate: businessDate,
        orderCount: hours.length,
        revenue: 100 * hours.length,
        byHour: {
          for (final hour in hours)
            '$hour': const StatBucket(orders: 1, revenue: 100, guests: 1),
        },
      );

  test('hours run from the cutoff, so after-midnight sales come last', () {
    // A Saturday that served lunch, dinner, and a last order at 01:00.
    final profile = DemandProfile.from(
      [
        dayWith('2026-08-29', [12, 19, 1])
      ],
      dayCutoffHour: 4,
    );

    expect(profile.activeHours, [12, 19, 1]);
  });

  test('a cutoff of zero leaves the hours on the clock', () {
    final profile = DemandProfile.from(
      [
        dayWith('2026-08-29', [12, 19, 1])
      ],
      dayCutoffHour: 0,
    );

    expect(profile.activeHours, [1, 12, 19]);
  });

  test('the cutoff only orders hours — it never moves a figure', () {
    final hours = [12, 19, 1];
    for (final cutoff in [0, 4, 6]) {
      final profile = DemandProfile.from([dayWith('2026-08-29', hours)],
          dayCutoffHour: cutoff);
      expect(profile.activeHours.toSet(), hours.toSet());
      expect(profile.cell(DateTime.saturday, 1)?.averageOrders, 1);
    }
  });

  group('how much evidence the profile has', () {
    // 2026-08-03 is a Monday.
    String dateAfter(int days) =>
        formatBusinessDate(DateTime(2026, 8, 3).add(Duration(days: days)));

    List<DailyStats> run(int days, {Set<int> skipWeekdays = const {}}) => [
          for (var i = 0; i < days; i++)
            if (!skipWeekdays.contains(
                DateTime(2026, 8, 3).add(Duration(days: i)).weekday))
              dayWith(dateAfter(i), const [12]),
        ];

    test('counts trading days and finds the thinnest weekday', () {
      // Fifteen days: Monday comes round three times, most weekdays twice.
      final profile = DemandProfile.from(run(15));

      expect(profile.tradingDays, 15);
      expect(profile.weakestObservations, 2);
      expect(profile.isReliable, isFalse);
    });

    test('three full weeks is the point it becomes a pattern', () {
      final profile = DemandProfile.from(run(21));

      expect(profile.weakestObservations, DemandProfile.minimumObservations);
      expect(profile.isReliable, isTrue);
    });

    test('a shop that never opens on Sunday is not held to Sundays', () {
      // Four weeks with Sundays skipped. Sunday is simply not an active
      // weekday, so it must not drag the profile below the bar.
      final profile =
          DemandProfile.from(run(28, skipWeekdays: {DateTime.sunday}));

      expect(profile.activeWeekdays, isNot(contains(DateTime.sunday)));
      expect(profile.isReliable, isTrue);
    });

    test('an empty profile is not quietly reliable', () {
      final profile = DemandProfile.from(const []);
      expect(profile.weakestObservations, 0);
      expect(profile.isReliable, isFalse);
    });
  });
}
