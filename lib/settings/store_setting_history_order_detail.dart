import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/repositories.dart';
import '../models/order.dart';
import '../models/store.dart';
import '../page/addorder.dart';
import '../widgets/feedback.dart';
import '../widgets/money.dart';

/// One order, with the option to edit it or void it.
///
/// There is no delete. Voiding keeps the document and backs the money out of
/// the day's totals, which is what makes a disputed till reconcilable.
class StoreHistoryOrderDetail extends StatefulWidget {
  const StoreHistoryOrderDetail(this.storeID, this.order, {super.key});

  final String storeID;
  final Order order;

  @override
  State<StoreHistoryOrderDetail> createState() =>
      _StoreHistoryOrderDetailState();
}

class _StoreHistoryOrderDetailState extends State<StoreHistoryOrderDetail> {
  /// Formats in the store's currency once it has loaded. Before that there is
  /// nothing on screen that shows money anyway.
  NumberFormat get _money => moneyFormat(_store);

  late Order _order = widget.order;
  Store? _store;
  bool _busy = false;

  /// True when anything was changed, so the list behind can refresh.
  bool _changed = false;

  /// Owned by this State, not by the void dialog. Disposing it straight after
  /// `await showDialog` throws "A TextEditingController was used after being
  /// disposed" — the future completes as the exit transition starts, while the
  /// TextField is still mounted and still reading it.
  final reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStore();
  }

  @override
  void dispose() {
    reasonController.dispose();
    super.dispose();
  }

  /// The store is what `voidOrder` needs to work out which trading day to back
  /// the order out of, so Void stays disabled until this lands.
  ///
  /// Unguarded, a failed read left `_store` null and Void did nothing at all —
  /// no spinner, no error, no void. Reporting it here is what makes the
  /// disabled button explicable.
  Future<void> _loadStore() async {
    try {
      final store = await storeRepository.fetch(widget.storeID);
      if (mounted) setState(() => _store = store);
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Detail')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                spacing: 20,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(order),
                  _buildTotals(order),
                  const SizedBox(height: 4),
                  _buildFact('Order time',
                      DateFormat.yMd().add_jms().format(order.placedAt)),
                  _buildFact('Trading day', order.businessDate),
                  _buildFact('Channel', _channelLabel(order)),
                  _buildFact('Guests', '${order.guestCount}'),
                  _buildFact('Payment method', order.paymentMethod.label,
                      icon: order.paymentMethod.icon),
                  if (order.commissionAmount > 0)
                    _buildFact('Platform commission',
                        _money.format(order.commissionAmount)),
                  if (order.totalCost > 0)
                    _buildFact(
                        'Gross profit', _money.format(order.grossProfit)),
                  ...order.items.map(_buildLine),
                  const SizedBox(height: 10),
                  _buildActionButtons(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _channelLabel(Order order) {
    final platform = _store?.platformById(order.deliveryPlatformId);
    return platform == null
        ? order.channel.label
        : '${order.channel.label} · ${platform.name}';
  }

  Widget _buildHeader(Order order) {
    return Row(
      children: [
        Text(
          'Order #${order.orderNo.toString().padLeft(2, '0')}',
          // The 'NotoSans' family this used to name was never declared in
          // pubspec.yaml, so it has always silently fallen back anyway.
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: order.isVoided
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : null,
                decoration:
                    order.isVoided ? TextDecoration.lineThrough : null,
              ),
        ),
        const SizedBox(width: 12),
        if (order.isVoided)
          Chip(
            label: const Text('VOIDED'),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            labelStyle: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer),
          ),
      ],
    );
  }

  Widget _buildTotals(Order order) {
    final store = _store;
    final String taxLine;
    if (order.taxAmount <= 0) {
      taxLine = 'No tax applied';
    } else if (store?.taxIncluded ?? true) {
      taxLine = 'Included tax ${_money.format(order.taxAmount)}';
    } else {
      taxLine = 'Plus tax ${_money.format(order.taxAmount)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Total ', style: Theme.of(context).textTheme.titleLarge),
            Text(_money.format(order.total),
                style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            taxLine,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildFact(String label, String value, {IconData? icon}) {
    final muted = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: muted),
          Row(
            spacing: 8,
            children: [
              if (icon != null)
                Icon(icon,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              Text(value, style: muted),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLine(OrderLine line) {
    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(vertical: 3, horizontal: 24),
        title: Text(line.name),
        subtitle: Text('${_money.format(line.unitPrice)} × ${line.qty}'),
        trailing: Text(
          _money.format(line.lineRevenue),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_order.isVoided) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This order was voided and no longer counts towards any '
              'total.'),
          if (_order.voidReason != null && _order.voidReason!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Reason: ${_order.voidReason}',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
        ],
      );
    }

    return Row(
      spacing: 10,
      children: [
        ElevatedButton.icon(
          onPressed: _busy ? null : _editOrder,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _confirmVoid,
          icon: const Icon(Icons.block_outlined),
          label: const Text('Void'),
        ),
      ],
    );
  }

  Future<void> _editOrder() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AddOrder(widget.storeID, existing: _order),
      ),
    );
    if (saved != true) return;

    // The edit itself already committed — this only re-reads it to show. A
    // failure here leaves the screen on the old figures, so it says so rather
    // than letting them be mistaken for the saved ones.
    try {
      final refreshed = await orderRepository.fetch(widget.storeID, _order.id);
      if (!mounted) return;
      setState(() {
        if (refreshed != null) _order = refreshed;
        _changed = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _changed = true);
      showFailure(context, e);
    }
  }

  Future<void> _confirmVoid() async {
    reasonController.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Void this order?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Order #${_order.orderNo} will be backed out of the day\'s '
                'takings. The record is kept.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g. wrong dish, customer cancelled',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          DestructiveButton(
            label: 'Void',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    final reason = reasonController.text.trim();
    if (confirmed != true) return;

    final store = _store;
    if (store == null) {
      if (mounted) {
        showError(context, 'The store settings have not loaded yet. Try again '
            'in a moment.');
      }
      return;
    }

    setState(() => _busy = true);
    try {
      await orderRepository.voidOrder(
        store: store,
        orderId: _order.id,
        by: currentActor(),
        reason: reason.isEmpty ? null : reason,
      );
      final refreshed = await orderRepository.fetch(widget.storeID, _order.id);
      if (!mounted) return;
      setState(() {
        if (refreshed != null) _order = refreshed;
        _changed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order voided')),
      );
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
