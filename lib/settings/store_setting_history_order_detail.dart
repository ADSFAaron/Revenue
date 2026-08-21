import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/repositories.dart';
import '../models/order.dart';
import '../models/store.dart';
import '../page/addorder.dart';

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
  static const String currency = 'NTD';

  late Order _order = widget.order;
  Store? _store;
  bool _busy = false;

  /// True when anything was changed, so the list behind can refresh.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _loadStore();
  }

  Future<void> _loadStore() async {
    final store = await storeRepository.fetch(widget.storeID);
    if (mounted) setState(() => _store = store);
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
                        '$currency ${order.commissionAmount}'),
                  if (order.totalCost > 0)
                    _buildFact('Gross profit', '$currency ${order.grossProfit}'),
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
          style: TextStyle(
            fontSize: 48,
            fontFamily: 'NotoSans',
            color: order.isVoided ? Colors.grey : null,
            decoration: order.isVoided ? TextDecoration.lineThrough : null,
          ),
        ),
        const SizedBox(width: 12),
        if (order.isVoided)
          const Chip(
            label: Text('VOIDED'),
            backgroundColor: Color(0xFFFFCDD2),
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
      taxLine = 'Included tax $currency ${order.taxAmount}';
    } else {
      taxLine = 'Plus tax $currency ${order.taxAmount}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Total $currency ',
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w200)),
            Text('${order.total}',
                style: const TextStyle(
                    fontSize: 32, fontWeight: FontWeight.w400)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            taxLine,
            style: const TextStyle(
                fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w300),
          ),
        ),
      ],
    );
  }

  Widget _buildFact(String label, String value, {IconData? icon}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 18, color: Colors.grey)),
        Row(
          spacing: 8,
          children: [
            if (icon != null) Icon(icon, color: Colors.grey),
            Text(value,
                style: const TextStyle(fontSize: 18, color: Colors.grey)),
          ],
        ),
      ],
    );
  }

  Widget _buildLine(OrderLine line) {
    return Card(
      elevation: 0,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(vertical: 3, horizontal: 24),
        title: Text(line.name, style: const TextStyle(fontSize: 16)),
        subtitle: Text('$currency ${line.unitPrice} × ${line.qty}'),
        trailing: Text(
          textAlign: TextAlign.center,
          '$currency \n${line.lineRevenue}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
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
                  style: const TextStyle(color: Colors.grey)),
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

    final refreshed = await orderRepository.fetch(widget.storeID, _order.id);
    if (!mounted) return;
    setState(() {
      if (refreshed != null) _order = refreshed;
      _changed = true;
    });
  }

  Future<void> _confirmVoid() async {
    final reasonController = TextEditingController();
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
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Void'),
          ),
        ],
      ),
    );

    final reason = reasonController.text.trim();
    reasonController.dispose();
    if (confirmed != true) return;

    final store = _store;
    if (store == null) return;

    setState(() => _busy = true);
    try {
      await orderRepository.voidOrder(
        store: store,
        orderId: _order.id,
        byUid: userRepository.currentUid,
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to void the order: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
