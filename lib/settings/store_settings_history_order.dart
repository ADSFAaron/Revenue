import 'package:flutter/material.dart';
import 'package:grouped_list/grouped_list.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../database/repositories.dart';
import '../models/order.dart';
import '../models/store.dart';
import 'store_setting_history_order_detail.dart';

/// Order history, newest first, grouped by trading day.
///
/// Loads a page at a time. The whole history used to arrive in one document,
/// which is exactly what one order per document was meant to end.
class StoreHistoryOrder extends StatefulWidget {
  const StoreHistoryOrder(this.storeID, {super.key});

  final String storeID;

  @override
  State<StoreHistoryOrder> createState() => _StoreHistoryOrderState();
}

class _StoreHistoryOrderState extends State<StoreHistoryOrder> {
  static const _pageSize = 30;
  static const String currency = 'NTD';

  final _scrollController = ScrollController();
  final List<Order> _orders = [];

  Store? _store;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initialLoad();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) _loadMore();
  }

  Future<void> _initialLoad() async {
    try {
      final store = await storeRepository.fetch(widget.storeID);
      final page =
          await orderRepository.fetchPage(widget.storeID, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _store = store;
        _orders
          ..clear()
          ..addAll(page);
        _hasMore = page.length == _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _orders.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await orderRepository.fetchPage(
        widget.storeID,
        limit: _pageSize,
        startAfter: _orders.last,
      );
      if (!mounted) return;
      setState(() {
        _orders.addAll(page);
        _hasMore = page.length == _pageSize;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History Orders')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) return Center(child: Text('Error: $_error'));
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_orders.isEmpty) {
      return const Center(child: Text('No orders available.'));
    }

    return RefreshIndicator(
      onRefresh: _initialLoad,
      child: GroupedListView<Order, String>(
        controller: _scrollController,
        elements: _orders,
        groupBy: (order) => order.businessDate,
        groupComparator: (a, b) => b.compareTo(a),
        itemComparator: (a, b) => b.placedAt.compareTo(a.placedAt),
        groupSeparatorBuilder: _buildGroupSeparator,
        itemBuilder: (context, order) => _buildOrderCard(order),
        useStickyGroupSeparators: true,
        floatingHeader: true,
        footer: _loadingMore
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            : const SizedBox(height: 24),
      ),
    );
  }

  Widget _buildGroupSeparator(String businessDate) {
    final store = _store;
    final today = store?.currentBusinessDate;
    final yesterday = today == null
        ? null
        : StatsRepository.shiftBusinessDate(today, -1);

    final String label;
    if (businessDate == today) {
      label = 'Today';
    } else if (businessDate == yesterday) {
      label = 'Yesterday';
    } else {
      label = DateFormat.yMMMEd().format(parseBusinessDate(businessDate));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      child: Chip(
        labelPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildOrderCard(Order order) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        leading: Icon(
          order.isVoided ? Symbols.cancel : Symbols.list_alt_check,
          color: order.isVoided ? Colors.red : null,
        ),
        title: Text(
          'Order #${order.orderNo}',
          style: order.isVoided
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(
          '${DateFormat.Hm().format(order.placedAt)}  ·  '
          '${order.channel.label}  ·  ${order.paymentMethod.label}',
        ),
        trailing: Text(
          textAlign: TextAlign.center,
          '$currency\n${order.total}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: order.isVoided ? Colors.grey : null,
          ),
        ),
        onTap: () => _openDetail(order),
      ),
    );
  }

  Future<void> _openDetail(Order order) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => StoreHistoryOrderDetail(widget.storeID, order),
      ),
    );
    if (changed == true) _initialLoad();
  }
}
