import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/repositories.dart';
import '../models/daily_stats.dart';
import '../models/order.dart';
import '../settings/store_setting_history_order_detail.dart';
import '../settings/store_settings_history_order.dart';
import '../widgets/feedback.dart';
import '../widgets/money.dart';
import '../widgets/setup_checklist.dart';
import '../widgets/stat_card.dart';
import 'addorder.dart';

/// The shop's day: today's figures, the last few tickets, and the way in to
/// ringing one up.
///
/// This is now the first tab. There used to be an Overview page ahead of it
/// showing today's revenue and order count — both of which are here, alongside
/// guests and average ticket, the recent orders, and the same Add Order
/// button. All it held that this does not was a greeting and a clock, and the
/// greeting has moved here.
class TransactionPage extends StatefulWidget {
  const TransactionPage({super.key});

  @override
  State<TransactionPage> createState() => _TransactionPageState();
}

class _TransactionPageState extends State<TransactionPage> {
  late final Future<Session> _session = loadSession();
  Timer? _clock;
  late DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Only the greeting line depends on the time, so only it is rebuilt. The
    // old Overview page put this timer around a `setState` on the whole page
    // and tore down the tree once a minute for one line of text.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Session>(
      future: _session,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorView(snapshot.error!);
        }
        return _buildTransactionPage(snapshot.data!);
      },
    );
  }

  Widget _buildTransactionPage(Session session) {
    final businessDate = session.store.currentBusinessDate;
    final money = moneyFormat(session.store);
    final counts = NumberFormat.decimalPattern();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => AddOrder(session.storeId)),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add Order'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildGreeting(session),
              const SizedBox(height: 20),
              // Disappears on its own once the store is set up.
              SetupChecklist(session: session),
              // Reads the day's rollup document, not the orders themselves.
              StreamBuilder<DailyStats>(
                stream:
                    statsRepository.watchDay(session.storeId, businessDate),
                builder: (context, snapshot) {
                  final stats =
                      snapshot.data ?? DailyStats(businessDate: businessDate);
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      StatCard(
                        title: 'Revenue',
                        icon: Icons.savings_rounded,
                        value: money.format(stats.revenue),
                      ),
                      StatCard(
                        title: 'Orders',
                        icon: Icons.grading_rounded,
                        value: counts.format(stats.orderCount),
                      ),
                      StatCard(
                        title: 'Guests',
                        icon: Icons.groups_rounded,
                        value: counts.format(stats.guestCount),
                      ),
                      StatCard(
                        title: 'Per order',
                        icon: Icons.receipt_long_rounded,
                        value:
                            money.format(stats.averageOrderValue.round()),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildLastTransactions(session),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGreeting(Session session) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_greeting(_now)}, ${session.user.displayName}',
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          DateFormat('EEEE, d MMMM · HH:mm').format(_now),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  static String _greeting(DateTime now) {
    if (now.hour >= 6 && now.hour <= 12) return '☀️ Morning';
    if (now.hour >= 13 && now.hour <= 18) return '🌻 Afternoon';
    if (now.hour >= 19 && now.hour <= 23) return '🌆 Evening';
    return '🌝 Night';
  }

  /// Real orders, newest first — this list used to be a single hard-coded row
  /// reading "Order No / Transaction Time".
  Widget _buildLastTransactions(Session session) {
    final money = moneyFormat(session.store);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Text('Last Transactions',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          StoreHistoryOrder(session.storeId),
                    ),
                  ),
                  child: const Text('View All'),
                ),
              ],
            ),
            StreamBuilder<List<Order>>(
              stream: orderRepository.watchRecent(session.storeId, limit: 5),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorView(snapshot.error!);
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  );
                }

                final orders = snapshot.data!;
                if (orders.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No orders yet.'),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    final strikethrough = order.isVoided
                        ? const TextStyle(
                            decoration: TextDecoration.lineThrough)
                        : null;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      // The rows looked exactly like the tappable ones behind
                      // View All, and were not.
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => StoreHistoryOrderDetail(
                              session.storeId, order),
                        ),
                      ),
                      leading: StatIcon(
                        icon: order.isVoided
                            ? Icons.block_rounded
                            : order.channel.icon,
                        size: 40,
                      ),
                      title: Text('Order #${order.orderNo}',
                          style: strikethrough),
                      subtitle: Text(
                        '${DateFormat.MMMd().add_Hm().format(order.placedAt)}'
                        '  ·  ${order.channel.label}',
                      ),
                      trailing: Text(
                        money.format(order.total),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.merge(strikethrough),
                      ),
                    );
                  },
                  separatorBuilder: (context, index) => const Divider(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
