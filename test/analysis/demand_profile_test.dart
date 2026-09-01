import 'package:flutter_test/flutter_test.dart';

import 'package:Revenue/analysis/demand_profile.dart';
import 'package:Revenue/models/daily_stats.dart';

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
}
