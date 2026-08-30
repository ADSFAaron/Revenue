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
import '../widgets/page_body.dart';
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
          child: PageBody(
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
                    // A shop that has sold nothing today is a real zero, and
                    // the repository already sends it as one: `watchDay` maps
                    // a missing rollup document to an empty [DailyStats].
                    //
                    // A day that could not be *read* is not a zero, and
                    // `?? DailyStats(...)` said it was — a refused query, an
                    // expired session or a cold start with no cache all put
                    // "Revenue $0" on the first screen of the app, indis-
                    // tinguishable from a genuinely quiet morning. That is the
                    // one failure here that is worse than an error message,
                    // because nothing about it looks like a failure.
                    //
                    // An em dash is what [ChangeBadge] already uses for a
                    // figure it does not have, and the note underneath says
                    // why there isn't one.
                    final stats = snapshot.data;
                    String figure(String Function(DailyStats) of) =>
                        stats == null ? '—' : of(stats);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatCardGrid(
                          children: <Widget>[
                            StatCard(
                              title: 'Revenue',
                              icon: Icons.savings_rounded,
                              value: figure((s) => money.format(s.revenue)),
                            ),
                            StatCard(
                              title: 'Orders',
                              icon: Icons.grading_rounded,
                              value: figure((s) => counts.format(s.orderCount)),
                            ),
                            StatCard(
                              title: 'Guests',
                              icon: Icons.groups_rounded,
                              value: figure((s) => counts.format(s.guestCount)),
                            ),
                            StatCard(
                              title: 'Per order',
                              icon: Icons.receipt_long_rounded,
                              value: figure((s) =>
                                  money.format(s.averageOrderValue.round())),
                            ),
                          ],
                        ),
                        if (snapshot.hasError) InlineError(snapshot.error!),
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
                      builder: (context) => StoreHistoryOrder(session.storeId),
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
                          builder: (_) =>
                              StoreHistoryOrderDetail(session.storeId, order),
                        ),
                      ),
                      leading: StatIcon(
                        icon: order.isVoided
                            ? Icons.block_rounded
                            : order.channel.icon,
                        size: 40,
                      ),
                      title:
                          Text('Order #${order.orderNo}', style: strikethrough),
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
