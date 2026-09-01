import 'package:flutter/material.dart';
import 'package:grouped_list/grouped_list.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../database/repositories.dart';
import '../models/order.dart';
import '../models/store.dart';
import 'store_setting_history_order_detail.dart';
import '../widgets/feedback.dart';
import '../widgets/money.dart';
import '../widgets/page_body.dart';
import '../widgets/payment_icons.dart';
import '../widgets/empty_state.dart';

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
  NumberFormat get _money => moneyFormat(_store);

  final _scrollController = ScrollController();
  final List<Order> _orders = [];

  Store? _store;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  /// The error itself, not its message: ErrorView needs the object to tell a
  /// refused permission (no retry) from a dropped connection (retry).
  Object? _error;

  /// Client-side filters over what has been paged in so far.
  ///
  /// Deliberately not Firestore `where` clauses. Each combination would need
  /// its own composite index, and this list already pages a fixed window of
  /// recent orders — filtering what is on screen is what someone reconciling a
  /// till actually wants, and voided orders in particular are the ones they
  /// come here to find.
  OrderChannel? _channel;

  /// A [StorePaymentMethod.id], filtered client-side like the rest.
  String? _paymentId;
  bool _onlyVoided = false;

  bool get _filtering => _channel != null || _paymentId != null || _onlyVoided;

  List<Order> get _visible => _orders.where((order) {
        if (_onlyVoided && !order.isVoided) return false;
        if (_channel != null && order.channel != _channel) return false;
        if (_paymentId != null && order.paymentMethodId != _paymentId) {
          return false;
        }
        return true;
      }).toList();

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
          _error = e;
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
    } catch (e) {
      // Stop asking for more. Without this the scroll listener re-fires at the
      // same offset on the next frame and a failing query is retried a few
      // times a second, quietly, for as long as the screen is open.
      if (!mounted) return;
      setState(() => _hasMore = false);
      showFailure(context, e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History Orders'),
        actions: [
          if (_filtering)
            TextButton(
              onPressed: () => setState(() {
                _channel = null;
                _paymentId = null;
                _onlyVoided = false;
              }),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) return ErrorView(_error!, onRetry: _initialLoad);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_orders.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No orders yet',
        body: 'Every order rung up on this store appears here, newest first.',
      );
    }

    final visible = _visible;

    return Column(
      children: [
        _buildFilterBar(),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No order in the ${_orders.length} loaded so far '
                      'matches these filters.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _buildList(visible),
        ),
      ],
    );
  }

  /// One scrolling row of filter chips.
  ///
  /// Sized by its chips rather than pinned to `height: 56`. A chip grows with
  /// the system font, and a fixed-height row around it clipped the labels off
  /// at the large end of the accessibility slider — a horizontal `ListView`
  /// needs a bounded height, but a scroll view around a `Row` does not.
  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          FilterChip(
            label: const Text('Voided'),
            avatar: _onlyVoided ? null : const Icon(Icons.block, size: 18),
            selected: _onlyVoided,
            onSelected: (on) => setState(() => _onlyVoided = on),
          ),
          const SizedBox(width: 8),
          for (final channel in OrderChannel.values) ...[
            FilterChip(
              label: Text(channel.label),
              avatar: _channel == channel ? null : Icon(channel.icon, size: 18),
              selected: _channel == channel,
              onSelected: (on) =>
                  setState(() => _channel = on ? channel : null),
            ),
            const SizedBox(width: 8),
          ],
          // The shop's own methods, not a fixed enum — and the defaults until
          // the store lands, so the bar does not jump about as it loads.
          for (final method
              in _store?.paymentMethods ?? kDefaultPaymentMethods) ...[
            FilterChip(
              label: Text(method.name),
              avatar: _paymentId == method.id
                  ? null
                  : Icon(paymentIconData(method.iconKey), size: 18),
              selected: _paymentId == method.id,
              onSelected: (on) =>
                  setState(() => _paymentId = on ? method.id : null),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildList(List<Order> visible) {
    return RefreshIndicator(
      onRefresh: _initialLoad,
      child: ReadingWidth(
        builder: (context, insets) => GroupedListView<Order, String>(
          padding: insets,
          controller: _scrollController,
          elements: visible,
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
      ),
    );
  }

  Widget _buildGroupSeparator(String businessDate) {
    final store = _store;
    final today = store?.currentBusinessDate;
    final yesterday =
        today == null ? null : StatsRepository.shiftBusinessDate(today, -1);

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
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  /// Resolved against the shop's own list, falling back to the built-in names
  /// while the store loads and for a method that has since been deleted.
  String _paymentName(Order order) => resolvePaymentMethod(
        _store?.paymentMethods ?? kDefaultPaymentMethods,
        order.paymentMethodId,
      ).name;

  Widget _buildOrderCard(Order order) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        leading: Icon(
          order.isVoided ? Symbols.cancel : Symbols.list_alt_check,
          color: order.isVoided ? scheme.error : null,
        ),
        title: Text(
          'Order #${order.orderNo}',
          style: order.isVoided
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(
          '${DateFormat.Hm().format(order.placedAt)}  ·  '
          '${order.channel.label}  ·  ${_paymentName(order)}',
        ),
        trailing: Text(
          _money.format(order.total),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: order.isVoided ? scheme.onSurfaceVariant : null,
                decoration: order.isVoided ? TextDecoration.lineThrough : null,
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
