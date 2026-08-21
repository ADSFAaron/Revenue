import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/repositories.dart';
import '../models/daily_stats.dart';
import 'addorder.dart';

class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  late final Future<Session> _session = loadSession();
  Timer? _clock;
  late String _timeString;

  @override
  void initState() {
    super.initState();
    _timeString = _formatDateTime(DateTime.now());
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() => _timeString = _formatDateTime(DateTime.now()));
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String _formatDateTime(DateTime dateTime) =>
      DateFormat('yyyy/MM/dd\nH:mm').format(dateTime);

  String _getGreeting(DateTime now) {
    if (now.hour >= 6 && now.hour <= 12) return "☀️ Morning";
    if (now.hour >= 13 && now.hour <= 18) return "🌻 Afternoon";
    if (now.hour >= 19 && now.hour <= 23) return "Evening";
    return "🌝 Night";
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
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final session = snapshot.data!;
        final greeting =
            "${_getGreeting(DateTime.now())}, ${session.user.displayName}";

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AddOrder(session.storeId),
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Add Order'),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(greeting, _timeString),
                  const SizedBox(height: 20),
                  // Today's figures come from the day's rollup document.
                  StreamBuilder<DailyStats>(
                    stream: statsRepository.watchDay(
                        session.storeId, session.store.currentBusinessDate),
                    builder: (context, snapshot) {
                      final stats = snapshot.data ??
                          DailyStats(
                              businessDate:
                                  session.store.currentBusinessDate);
                      final money = NumberFormat.decimalPattern();
                      return Column(
                        children: [
                          _buildStatCard(
                            title: "Today's Revenue",
                            icon: Icons.savings_rounded,
                            prefix: 'NTD ',
                            value: money.format(stats.revenue),
                            storeId: session.storeId,
                          ),
                          _buildStatCard(
                            title: 'Number of Sales',
                            icon: Icons.shopping_bag_rounded,
                            value: money.format(stats.orderCount),
                            storeId: session.storeId,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required IconData icon,
    required String value,
    required String storeId,
    String prefix = '',
  }) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24),
        child: Column(
          children: [
            ListTile(
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Store ID: $storeId')),
              ),
              title: Text(title),
              leading: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).splashColor,
                  borderRadius: BorderRadius.circular(48),
                ),
                height: 48,
                width: 48,
                child: Icon(icon, color: Theme.of(context).iconTheme.color),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  if (prefix.isNotEmpty) Text(prefix),
                  Flexible(
                    child: FittedBox(
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 28,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String greeting, String time) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            greeting,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(time, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 18),
          const Text(
            'Explore information and activity \nabout your store',
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
