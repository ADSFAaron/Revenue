import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/menu_item.dart';
import '../models/order_slip.dart';
import '../models/store.dart';
import '../widgets/money.dart';

/// What the reader found, before any of it is in the basket.
///
/// **The whole point of this screen is that it is in the way.** A photograph
/// read into an order and rung up without a person looking at it is a takings
/// figure nobody checked — and unlike a mis-tapped dish, nobody would ever
/// know which order was wrong or by how much. So the reading lands here, next
/// to the prices, and only what somebody confirms goes any further.
///
/// It is deliberately a full screen rather than a sheet. The counter tablet is
/// held at arm's length, and a half-height sheet with a scroll in it is the
/// shape that gets confirmed without being read.
class OrderSlipReview extends StatefulWidget {
  const OrderSlipReview({
    required this.reading,
    required this.menu,
    required this.store,
    super.key,
  });

  final SlipReading reading;

  /// This store's dishes, for the names and the prices. The reading carries
  /// only ids — asking the reader for names back would invite it to correct
  /// their spelling, and then a dish that differs by one character is a
  /// mismatch nobody can see.
  final List<MenuItem> menu;

  final Store store;

  @override
  State<OrderSlipReview> createState() => _OrderSlipReviewState();
}

class _OrderSlipReviewState extends State<OrderSlipReview> {
  /// itemId -> quantity, as it will be added. Editable here and nowhere else.
  late final Map<String, int> _quantities = {
    for (final line in widget.reading.sorted) line.itemId: line.qty,
  };

  late final Map<String, MenuItem> _byId = {
    for (final item in widget.menu) item.id: item,
  };

  late final Set<String> _hedged = {
    for (final line in widget.reading.lines)
      if (!line.sure) line.itemId,
  };

  int get _total => _quantities.entries.fold<int>(
        0,
        (sum, entry) => sum + (_byId[entry.key]?.price ?? 0) * entry.value,
      );

  int get _dishes =>
      _quantities.values.fold<int>(0, (sum, qty) => sum + qty);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = moneyFormat(widget.store);
    final ordered = widget.reading.sorted
        .where((line) => _byId.containsKey(line.itemId))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('What the slip says')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  if (_hedged.isNotEmpty)
                    _banner(
                      context,
                      icon: Icons.help_outline_rounded,
                      text: '${_hedged.length} '
                          '${_hedged.length == 1 ? 'line is' : 'lines are'} '
                          'marked as unsure and put first. Check '
                          '${_hedged.length == 1 ? 'it' : 'them'} against the '
                          'slip before adding.',
                    ),
                  for (final line in ordered) _buildLine(context, line, money),
                  if (widget.reading.unreadable.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildUnreadable(context),
                  ],
                  if (widget.reading.unmatched > 0) ...[
                    const SizedBox(height: 16),
                    _banner(
                      context,
                      icon: Icons.report_outlined,
                      // Should never happen — the reader picks from a list it
                      // was given. It is surfaced rather than swallowed because
                      // if it ever does, it means the closed-set match is not
                      // holding, and that is worth somebody knowing.
                      text: '${widget.reading.unmatched} '
                          '${widget.reading.unmatched == 1 ? 'line' : 'lines'} '
                          'came back naming a dish that is not on this menu, '
                          'and were dropped.',
                      bad: true,
                    ),
                  ],
                ],
              ),
            ),
            _buildBar(context, theme, money),
          ],
        ),
      ),
    );
  }

  Widget _buildLine(BuildContext context, SlipLine line, NumberFormat money) {
    final item = _byId[line.itemId]!;
    final qty = _quantities[line.itemId] ?? 0;
    final theme = Theme.of(context);
    final unsure = _hedged.contains(line.itemId);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: unsure
          ? Icon(Icons.help_outline_rounded, color: theme.colorScheme.tertiary)
          : const Icon(Icons.check_rounded),
      title: Text(item.name),
      subtitle: Text(
        qty == 0
            ? 'Not being added'
            : '${money.format(item.price)} each · '
                '${money.format(item.price * qty)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'One fewer',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: qty == 0
                ? null
                : () => setState(() {
                      final next = qty - 1;
                      if (next <= 0) {
                        _quantities[line.itemId] = 0;
                      } else {
                        _quantities[line.itemId] = next;
                      }
                    }),
          ),
          SizedBox(
            width: 28,
            child: Text('$qty',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
          ),
          IconButton(
            tooltip: 'One more',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () =>
                setState(() => _quantities[line.itemId] = qty + 1),
          ),
        ],
      ),
    );
  }

  Widget _buildUnreadable(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Written on the slip, not on the menu',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'A handwritten special, a request, or a dish that has been '
              'retired. Add these on the order screen.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final text in widget.reading.unreadable)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('· $text', style: theme.textTheme.bodyMedium),
              ),
          ],
        ),
      ),
    );
  }

  Widget _banner(
    BuildContext context, {
    required IconData icon,
    required String text,
    bool bad = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bad ? scheme.errorContainer : scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 20,
                color: bad
                    ? scheme.onErrorContainer
                    : scheme.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: bad
                      ? scheme.onErrorContainer
                      : scheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBar(BuildContext context, ThemeData theme, NumberFormat money) {
    final adding = _dishes > 0;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      adding
                          ? '$_dishes ${_dishes == 1 ? 'dish' : 'dishes'}'
                          : 'Nothing to add',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(money.format(_total),
                        style: theme.textTheme.titleLarge),
                  ],
                ),
              ),
              // Says "add to the order", not "save". Nothing is rung up here —
              // this fills the basket and the order screen is still between it
              // and the takings.
              FilledButton.icon(
                onPressed: adding ? _confirm : null,
                icon: const Icon(Icons.add_shopping_cart_outlined),
                label: const Text('Add to the order'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirm() {
    Navigator.of(context).pop({
      for (final entry in _quantities.entries)
        if (entry.value > 0) entry.key: entry.value,
    });
  }
}
