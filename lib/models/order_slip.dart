/// One dish the reader found ticked on a paper slip.
class SlipLine {
  const SlipLine({
    required this.itemId,
    required this.qty,
    this.sure = true,
  });

  /// A [MenuItem.id] on *this* store's menu.
  ///
  /// Guaranteed by the server, not hoped for: the reader is given the shop's
  /// menu and returns ids from it, and every id that comes back is looked up
  /// against that list before it is sent. An id that is not on the menu never
  /// reaches here. See functions/src/order_slip.ts.
  final String itemId;

  final int qty;

  /// False when the reader could not be certain — an ambiguous mark, unclear
  /// writing, or two dishes it could equally have been.
  ///
  /// A hint for what to look at first, never a filter. A line the reader was
  /// confident about can still be wrong, so the review screen shows every line
  /// and merely puts these at the top.
  final bool sure;

  factory SlipLine.fromMap(Map<String, dynamic> map) => SlipLine(
        itemId: map['itemId'] as String? ?? '',
        qty: (map['qty'] as num?)?.toInt() ?? 0,
        sure: map['sure'] as bool? ?? true,
      );
}

/// What came back from photographing a slip.
class SlipReading {
  const SlipReading({
    this.lines = const [],
    this.unreadable = const [],
    this.unmatched = 0,
  });

  final List<SlipLine> lines;

  /// Things written on the slip that were marked and are not on the menu — a
  /// handwritten special, a request, a dish that has been retired.
  ///
  /// Shown rather than dropped. Somebody holding the slip can see there is
  /// writing on it that did not make it into the basket, and a reader that
  /// quietly ignored it would be teaching them not to check.
  final List<String> unreadable;

  /// How many lines the server threw away because the id was not on the menu.
  ///
  /// Should be zero. It is carried because a non-zero count means the model
  /// invented an id despite being given a closed set to pick from, which is
  /// the one failure this whole design exists to prevent — so it is visible
  /// rather than silent.
  final int unmatched;

  bool get isEmpty => lines.isEmpty;

  /// Lines the reader hedged on, first. Nothing is hidden; the order is the
  /// only thing that changes.
  List<SlipLine> get sorted =>
      [...lines]..sort((a, b) => (a.sure ? 1 : 0).compareTo(b.sure ? 1 : 0));
}
