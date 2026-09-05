import 'package:flutter_test/flutter_test.dart';
import 'package:Revenue/models/order_slip.dart';

/// What comes back from photographing a paper slip.
///
/// The reading is the one thing in this app produced by a model rather than by
/// a person tapping, so what is pinned here is the shape of not trusting it:
/// unsure lines surface first, nothing is filtered away, and the count of
/// invented ids is carried rather than swallowed.
void main() {
  test('lines the reader hedged on come first', () {
    const reading = SlipReading(lines: [
      SlipLine(itemId: 'a', qty: 1),
      SlipLine(itemId: 'b', qty: 2, sure: false),
      SlipLine(itemId: 'c', qty: 1),
    ]);

    expect(reading.sorted.first.itemId, 'b');
  });

  test('ordering is the only thing that changes — nothing is hidden', () {
    // A line the reader was confident about can still be wrong, so `sure` is a
    // hint about what to check first and never a filter.
    const reading = SlipReading(lines: [
      SlipLine(itemId: 'a', qty: 1),
      SlipLine(itemId: 'b', qty: 2, sure: false),
    ]);

    expect(reading.sorted, hasLength(2));
  });

  test('a reading with no lines knows it is empty', () {
    expect(const SlipReading().isEmpty, isTrue);
    expect(
      const SlipReading(lines: [SlipLine(itemId: 'a', qty: 1)]).isEmpty,
      isFalse,
    );
  });

  test('an id that never reached the menu is counted, not swallowed', () {
    // Should always be zero: the reader is handed the shop's menu and picks
    // from it. A non-zero count means the closed-set match is not holding,
    // which is the one failure the whole design exists to prevent — so it is
    // carried to the screen rather than dropped on the server.
    const reading = SlipReading(unmatched: 2);
    expect(reading.unmatched, 2);
  });

  test('a malformed line from the wire does not crash the reading', () {
    final line = SlipLine.fromMap(const {});
    expect(line.itemId, isEmpty);
    expect(line.qty, 0);
    expect(line.sure, isTrue);
  });
}
