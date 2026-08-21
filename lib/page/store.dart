import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../database/repositories.dart';
import '../models/app_user.dart';
import '../settings/app_settings.dart';
import '../settings/store_settings.dart';
import '../settings/user_settings.dart';

class StorePage extends StatefulWidget {
  const StorePage({super.key});

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  late Future<_StoreOverview> _future = _load();

  Future<_StoreOverview> _load() async {
    final session = await loadSession();
    final totals = await statsRepository.fetchTotals(session.storeId);
    return _StoreOverview(session: session, totals: totals);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StoreOverview>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        return _buildStorePage(snapshot.data!);
      },
    );
  }

  Widget _buildStorePage(_StoreOverview overview) {
    final session = overview.session;
    // Lifetime revenue is summed from the daily rollups rather than kept as a
    // running counter on the store document, and formatted with separators
    // instead of being truncated once it got long.
    final money = NumberFormat.decimalPattern();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => setState(() => _future = _load()),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: <Widget>[
                _buildStoreCard(session),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    _buildCard(
                      title: 'Revenue',
                      icon: Icons.savings_rounded,
                      value: '${session.store.currency == 'TWD' ? 'NTD' : session.store.currency} '
                          '${money.format(overview.totals.revenue)}',
                    ),
                    _buildCard(
                      title: 'Orders',
                      icon: Icons.grading_rounded,
                      value: money.format(overview.totals.orderCount),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildListTile(
                  title: 'Store Settings',
                  subtitle: 'Menu editing, History orders',
                  icon: Icons.storefront_outlined,
                  onTap: () => _navigateTo(StoreSettings(session.storeId)),
                ),
                _buildListTile(
                  title: 'User Settings',
                  subtitle: 'User name, Change password',
                  icon: Icons.manage_accounts_outlined,
                  onTap: () => _navigateTo(UserSettings(session.user.email)),
                ),
                _buildListTile(
                  title: 'App Settings',
                  subtitle: 'App version, Privacy policy, Feedback',
                  icon: Icons.info_outline,
                  onTap: () => _navigateTo(AppSettings(session.storeId)),
                ),
                _buildListTile(
                  title: 'Logout',
                  icon: Icons.logout_outlined,
                  onTap: () => FirebaseAuth.instance.signOut(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStoreCard(Session session) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    session.store.name,
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      _navigateTo(StoreSettings(session.storeId)),
                  child: const Text('Edit'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            StreamBuilder<List<AppUser>>(
              stream: userRepository.watchStaff(session.storeId),
              builder: (context, snapshot) {
                final staff = snapshot.data ?? const <AppUser>[];
                if (staff.isEmpty) return const SizedBox.shrink();
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: staff.length,
                  itemBuilder: (context, index) {
                    final user = staff[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).splashColor,
                        child: Text(user.initials),
                      ),
                      title: Text(user.email),
                      subtitle: Text(user.role.label),
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
        height: MediaQuery.of(context).size.height / 7,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  Text(title),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: FittedBox(
                      child: Text(
                        value ?? '',
                        style: const TextStyle(fontSize: 24),
                      ),
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

  Widget _buildListTile({
    required String title,
    String? subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      leading: Icon(icon),
      onTap: onTap,
    );
  }

  void _navigateTo(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }
}

class _StoreOverview {
  const _StoreOverview({required this.session, required this.totals});

  final Session session;
  final StoreTotals totals;
}
