import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/repositories.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../models/order_draft.dart';
import '../models/store.dart';

/// A row on the order screen: an active menu item, or a retired one that an
/// order being edited still contains.
class _MenuRow {
  const _MenuRow({
    required this.itemId,
    required this.name,
    required this.price,
    required this.cost,
    required this.icon,
    this.categoryId,
    this.retired = false,
  });

  final String itemId;
  final String name;
  final int price;
  final int cost;
  final IconData icon;
  final String? categoryId;
  final bool retired;

  factory _MenuRow.fromMenuItem(MenuItem item) => _MenuRow(
        itemId: item.id,
        name: item.name,
        price: item.price,
        cost: item.cost,
        icon: item.iconData,
        categoryId: item.categoryId,
      );

  /// Built from the frozen copy on the order, so a retired dish still shows the
  /// price it was actually sold at.
  factory _MenuRow.fromOrderLine(OrderLine line) => _MenuRow(
        itemId: line.itemId,
        name: line.name,
        price: line.unitPrice,
        cost: line.unitCost,
        icon: Icons.history_toggle_off,
        categoryId: line.categoryId,
        retired: true,
      );
}

class AddOrder extends StatefulWidget {
  const AddOrder(this.storeId, {super.key, this.existing});

  final String storeId;

  /// Non-null when editing an order that has already been rung up.
  final Order? existing;

  @override
  State<AddOrder> createState() => _AddOrderState();
}

class _AddOrderState extends State<AddOrder> {
  Store? _store;
  List<MenuItem> _menu = const [];
  String? _loadError;

  /// itemId -> quantity.
  final Map<String, int> _quantities = {};

  late DateTime _placedAt;
  OrderChannel _channel = OrderChannel.dineIn;
  String? _deliveryPlatformId;
  int _guestCount = 1;
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  bool _submitting = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _placedAt = existing?.placedAt ?? DateTime.now();
    if (existing != null) {
      _channel = existing.channel;
      _deliveryPlatformId = existing.deliveryPlatformId;
      _guestCount = existing.guestCount;
      _paymentMethod = existing.paymentMethod;
      for (final line in existing.items) {
        _quantities[line.itemId] = line.qty;
      }
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final store = await storeRepository.fetch(widget.storeId);
      final menu = await menuRepository.fetchActive(widget.storeId);
      if (!mounted) return;
      if (store == null) {
        setState(() => _loadError = 'Store ${widget.storeId} was not found.');
        return;
      }
      setState(() {
        _store = store;
        _menu = menu;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    }
  }

  /// Active dishes, plus any retired dish the edited order still contains so
  /// its quantity remains adjustable.
  List<_MenuRow> get _rows {
    final rows = _menu.map(_MenuRow.fromMenuItem).toList();
    final known = rows.map((r) => r.itemId).toSet();
    for (final line in widget.existing?.items ?? const <OrderLine>[]) {
      if (!known.contains(line.itemId)) rows.add(_MenuRow.fromOrderLine(line));
    }
    return rows;
  }

  OrderDraft _buildDraft() {
    final byId = {for (final row in _rows) row.itemId: row};
    final items = <OrderLine>[];
    _quantities.forEach((itemId, qty) {
      final row = byId[itemId];
      if (row == null || qty <= 0) return;
      items.add(OrderLine(
        itemId: row.itemId,
        name: row.name,
        categoryId: row.categoryId,
        unitPrice: row.price,
        unitCost: row.cost,
        qty: qty,
      ));
    });

    return OrderDraft(
      placedAt: _placedAt,
      items: items,
      channel: _channel,
      guestCount: _guestCount,
      deliveryPlatformId: _deliveryPlatformId,
      paymentMethod: _paymentMethod,
    );
  }

  Future<void> _selectDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _placedAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_placedAt),
    );
    if (time == null) return;

    setState(() {
      _placedAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    final store = _store;
    if (store == null || _submitting) return;

    final draft = _buildDraft();
    if (draft.isEmpty) {
      _snack('No items in order!', isError: true);
      return;
    }
    if (_channel == OrderChannel.delivery &&
        store.deliveryPlatforms.isNotEmpty &&
        _deliveryPlatformId == null) {
      _snack('Choose a delivery platform', isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      if (_isEdit) {
        await orderRepository.replace(
          store: store,
          orderId: widget.existing!.id,
          draft: draft,
        );
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

      final orderNo = await orderRepository.submit(
        store: store,
        draft: draft,
        createdBy: authRepository.currentUid,
      );
      if (!mounted) return;
      _snack('Order #$orderNo added');
      setState(() {
        _quantities.clear();
        _placedAt = DateTime.now();
        _guestCount = 1;
      });
    } catch (e) {
      _snack('Could not save the order: $e', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      backgroundColor: isError ? Colors.red : null,
      content: Row(
        children: [
          Icon(isError ? Icons.warning_outlined : Icons.check,
              color: Colors.white),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Order' : 'Add Order')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return Center(child: Text('Error: $_loadError'));
    }
    final store = _store;
    if (store == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final rows = _rows;
    final draft = _buildDraft();
    final totals = draft.price(store);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            children: [
              _buildDateTile(store),
              _buildChannelTile(store),
              if (_channel == OrderChannel.delivery &&
                  store.deliveryPlatforms.isNotEmpty)
                _buildPlatformTile(store),
              _buildGuestCountTile(),
              _buildPaymentTile(),
              const Divider(height: 32),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text('No dishes on the menu yet.\n'
                        'Add some in Store Settings → Edit Menu.'),
                  ),
                )
              else
                ...rows.map(_buildMenuRow),
            ],
          ),
        ),
        _buildSummary(store, totals),
      ],
    );
  }

  Widget _buildDateTile(Store store) {
    final businessDate = store.businessDateOf(_placedAt);
    final calendarDate = DateFormat('yyyy-MM-dd').format(_placedAt);
    return ListTile(
      leading: const Icon(Icons.calendar_today),
      title: Text(DateFormat('yyyy/MM/dd  HH:mm').format(_placedAt)),
      // An order rung up after midnight belongs to the previous trading day.
      // Say so rather than let the owner wonder why it is on yesterday's sheet.
      subtitle: businessDate == calendarDate
          ? null
          : Text('Counts towards trading day $businessDate'),
      trailing: const Icon(Icons.edit_outlined),
      onTap: _selectDateTime,
    );
  }

  Widget _buildChannelTile(Store store) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SegmentedButton<OrderChannel>(
        segments: OrderChannel.values
            .map((c) => ButtonSegment(
                  value: c,
                  icon: Icon(c.icon),
                  label: Text(c.label),
                ))
            .toList(),
        selected: {_channel},
        onSelectionChanged: (selection) => setState(() {
          _channel = selection.first;
          if (_channel != OrderChannel.delivery) {
            _deliveryPlatformId = null;
          } else {
            _deliveryPlatformId ??= store.deliveryPlatforms.isNotEmpty
                ? store.deliveryPlatforms.first.id
                : null;
          }
        }),
      ),
    );
  }

  Widget _buildPlatformTile(Store store) {
    final platform = store.platformById(_deliveryPlatformId);
    return ListTile(
      leading: const Icon(Icons.storefront_outlined),
      title: DropdownButtonFormField<String>(
        initialValue: _deliveryPlatformId,
        decoration: const InputDecoration(labelText: 'Delivery platform'),
        items: store.deliveryPlatforms
            .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
            .toList(),
        onChanged: (value) => setState(() => _deliveryPlatformId = value),
      ),
      subtitle: platform == null || platform.commissionRate <= 0
          ? null
          : Text(
              'Commission ${(platform.commissionRate * 100).toStringAsFixed(0)}%'),
    );
  }

  Widget _buildGuestCountTile() {
    return ListTile(
      leading: const Icon(Icons.groups_outlined),
      title: const Text('Guests'),
      // Without this, a family of four sharing one bill counts as one customer
      // and the per-head spend comes out four times too high.
      subtitle: const Text('People on this bill'),
      trailing: _buildStepper(
        value: _guestCount,
        onChanged: (delta) => setState(
            () => _guestCount = (_guestCount + delta).clamp(1, 99)),
      ),
    );
  }

  Widget _buildPaymentTile() {
    return ListTile(
      leading: Icon(_paymentMethod.icon),
      title: Text('Payment: ${_paymentMethod.label}'),
      trailing: const Icon(Icons.arrow_forward_rounded),
      onTap: () => showModalBottomSheet<void>(
        showDragHandle: true,
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: PaymentMethod.values
                .map((method) => ListTile(
                      leading: Icon(method.icon),
                      title: Text(method.label),
                      selected: method == _paymentMethod,
                      onTap: () {
                        setState(() => _paymentMethod = method);
                        Navigator.pop(context);
                      },
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuRow(_MenuRow row) {
    final qty = _quantities[row.itemId] ?? 0;
    return ListTile(
      leading: Icon(row.icon),
      title: Text(row.retired ? '${row.name}  (retired)' : row.name),
      subtitle: Text('NTD ${row.price}'),
      trailing: _buildStepper(
        value: qty,
        onChanged: (delta) => setState(() {
          final next = qty + delta;
          if (next <= 0) {
            _quantities.remove(row.itemId);
          } else {
            _quantities[row.itemId] = next;
          }
        }),
      ),
    );
  }

  Widget _buildStepper({
    required int value,
    required void Function(int delta) onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: () => onChanged(-1),
        ),
        SizedBox(
          width: 24,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16)),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () => onChanged(1),
        ),
      ],
    );
  }

  Widget _buildSummary(Store store, OrderTotals totals) {
    final taxLabel = store.taxRate <= 0
        ? 'No tax configured'
        : store.taxIncluded
            ? 'Includes tax NTD ${totals.taxAmount} '
                '(${(store.taxRate * 100).toStringAsFixed(0)}%)'
            : 'Plus tax NTD ${totals.taxAmount} '
                '(${(store.taxRate * 100).toStringAsFixed(0)}%)';

    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(taxLabel,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if (totals.commissionAmount > 0)
                Text('Platform commission NTD ${totals.commissionAmount}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.attach_money),
                  const SizedBox(width: 8),
                  Text('Total: NTD ${totals.total}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_isEdit ? '修改訂單' : '增加訂單'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
