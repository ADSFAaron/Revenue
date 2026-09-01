import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/repositories.dart';
import '../models/pending_order.dart';
import 'feedback.dart';
import 'money.dart';

/// The bar that says an order is rung up but not yet sent.
///
/// Orders taken with no connection live on the device until there is one (see
/// [PendingOrderQueue]). That is only safe if it is *visible*: a sale that the
/// phone is quietly holding, with nobody aware of it, is the same as a lost
/// one at cashing-up time. So this sits above the page, says how many and how
/// old, sends them on demand, and opens the list.
class PendingOrdersBar extends StatelessWidget {
  const PendingOrdersBar({this.currency, super.key});

  /// The store's, where the caller has one. Falls back to the default rather
  /// than fetching a store just to format a number.
  final String? currency;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<PendingOrder>>(
      valueListenable: pendingOrders,
      builder: (context, waiting, _) {
        if (waiting.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final oldest = waiting
            .map((p) => p.draft.placedAt)
            .reduce((a, b) => a.isBefore(b) ? a : b);

        return Material(
          color: scheme.secondaryContainer,
          child: InkWell(
            onTap: () => _showList(context, currency),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.schedule_send_rounded,
                      size: 18, color: scheme.onSecondaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${waiting.length} '
                      '${waiting.length == 1 ? 'order is' : 'orders are'} '
                      'waiting to be sent — oldest from '
                      '${DateFormat.Hm().format(oldest)}. Tap to see them.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSecondaryContainer),
                    ),
                  ),
                  const SizedBox(width: 8),
                  pendingOrders.isSending
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed: () => pendingOrders.flush(),
                          child: const Text('Send now'),
                        ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static void _showList(BuildContext context, String? currency) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: _PendingList(currency: currency),
        ),
      ),
    );
  }
}

class _PendingList extends StatelessWidget {
  const _PendingList({this.currency});

  final String? currency;

  @override
  Widget build(BuildContext context) {
    final money = moneyFormatFor(currency ?? kDefaultCurrency);

    return ValueListenableBuilder<List<PendingOrder>>(
      valueListenable: pendingOrders,
      builder: (context, waiting, _) {
        if (waiting.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Everything has been sent.')),
          );
        }

        return ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('Waiting to be sent',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'These were rung up on this device and keep the time they were '
                'rung up at. They go as soon as there is a connection, and they '
                'do not appear in the reports until they do.',
              ),
            ),
            for (final pending in waiting)
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(
                  '${DateFormat.Hm().format(pending.draft.placedAt)}  ·  '
                  '${pending.draft.items.length} '
                  '${pending.draft.items.length == 1 ? 'dish' : 'dishes'}',
                ),
                // The subtotal, not the total: tax and platform commission are
                // worked out against the store when it is sent, and quoting a
                // total here that the sent order might not match would be
                // worse than quoting nothing.
                subtitle: Text('${money.format(pending.draft.items.fold<int>(
                  0,
                  (sum, line) => sum + line.lineRevenue,
                ))} before tax'),
                trailing: IconButton(
                  tooltip: 'Discard',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDiscard(context, pending),
                ),
              ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Future<void> _confirmDiscard(
      BuildContext context, PendingOrder pending) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this order?'),
        content: const Text(
          'It was never sent, so nothing is backed out and nothing is logged. '
          'It simply stops existing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          DestructiveButton(
            label: 'Discard',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed == true) await pendingOrders.discard(pending.id);
  }
}
