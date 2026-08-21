import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/repositories.dart';
import '../models/daily_stats.dart';
import '../models/order.dart';
import '../settings/store_settings_history_order.dart';
import 'addorder.dart';

class TransactionPage extends StatefulWidget {
  const TransactionPage({super.key});

  @override
  State<TransactionPage> createState() => _TransactionPageState();
}

class _TransactionPageState extends State<TransactionPage> {
  late final Future<Session> _session = loadSession();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Session>(
      future: _session,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        return _buildTransactionPage(snapshot.data!);
      },
    );
  }

  Widget _buildTransactionPage(Session session) {
    final businessDate = session.store.currentBusinessDate;
    final money = NumberFormat.decimalPattern();

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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 32.0),
                  child: Row(
                    children: [
                      Text(
                        "Today's Summary",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
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
                        _buildCard(
                          title: 'Revenue',
                          icon: Icons.savings_rounded,
                          value: money.format(stats.revenue),
                        ),
                        _buildCard(
                          title: 'Orders',
                          icon: Icons.grading_rounded,
                          value: money.format(stats.orderCount),
                        ),
                        _buildCard(
                          title: 'Guests',
                          icon: Icons.groups_rounded,
                          value: money.format(stats.guestCount),
                        ),
                        _buildCard(
                          title: 'Per order',
                          icon: Icons.receipt_long_rounded,
                          value: money
                              .format(stats.averageOrderValue.round()),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                _buildLastTransactions(session),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Real orders, newest first — this list used to be a single hard-coded row
  /// reading "Order No / Transaction Time".
  Widget _buildLastTransactions(Session session) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 10),
                const Text('Last Transactions',
                    style: TextStyle(fontSize: 20)),
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
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error: ${snapshot.error}'),
                  );
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
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).splashColor,
                        child: Text('#${order.orderNo}'),
                      ),
                      title: Text(
                        'Order #${order.orderNo}',
                        style: order.isVoided
                            ? const TextStyle(
                                decoration: TextDecoration.lineThrough)
                            : null,
                      ),
                      subtitle: Text(
                        '${DateFormat.MMMd().add_Hm().format(order.placedAt)}'
                        '  ·  ${order.channel.label}',
                      ),
                      trailing: Text('NTD ${order.total}',
                          style: const TextStyle(fontSize: 16)),
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

  Widget _buildCard({
    required String title,
    String? value,
    IconData? icon,
  }) {
    return Card(
      elevation: 0,
      child: SizedBox(
        width: MediaQuery.of(context).size.width / 2 - 30,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).splashColor,
                      borderRadius: BorderRadius.circular(48),
                    ),
                    height: 48,
                    width: 48,
                    child: Icon(icon, color: Theme.of(context).iconTheme.color),
                  ),
                  const SizedBox(width: 10),
                  Flexible(child: Text(title)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: FittedBox(
                      child: Text(value ?? '',
                          style: const TextStyle(fontSize: 24)),
                    ),
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
