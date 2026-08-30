import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/repositories.dart';
import '../models/app_user.dart';
import '../settings/app_settings.dart';
import '../settings/store_settings.dart';
import '../settings/user_settings.dart';
import '../widgets/feedback.dart';
import '../widgets/money.dart';
import '../widgets/page_body.dart';
import '../widgets/stat_card.dart';

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
          // Retryable on purpose: the two calls behind this are a profile read
          // and a rollup read, and the usual reason either fails is a network
          // that has since come back.
          return ErrorView(
            snapshot.error!,
            onRetry: () => setState(() => _future = _load()),
          );
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
    final money = moneyFormat(session.store);
    final counts = NumberFormat.decimalPattern();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => setState(() => _future = _load()),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: PageBody(
              child: Column(
                children: <Widget>[
                  _buildStoreCard(session),
                  const SizedBox(height: 10),
                  StatCardGrid(
                    children: <Widget>[
                      StatCard(
                        title: 'Revenue',
                        icon: Icons.savings_rounded,
                        value: money.format(overview.totals.revenue),
                      ),
                      StatCard(
                        title: 'Orders',
                        icon: Icons.grading_rounded,
                        value: counts.format(overview.totals.orderCount),
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
                    onTap: () => _navigateTo(const UserSettings()),
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
                    // Was a bare call, sitting in a row of navigation tiles: one
                    // mis-tap and you are out and typing a password again.
                    onTap: _confirmLogout,
                  ),
                ],
              ),
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
                Expanded(
                  child: Text(
                    session.store.name,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () => _navigateTo(StoreSettings(session.storeId)),
                  child: const Text('Edit'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            StreamBuilder<List<AppUser>>(
              stream: userRepository.watchStaff(session.storeId),
              builder: (context, snapshot) {
                // An errored stream must not render as an empty roster: a
                // store whose staff could not be read looks exactly like a
                // store with no staff, and the second is a normal state.
                if (snapshot.hasError) {
                  return Text(
                    describeFailure(snapshot.error!).message,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  );
                }
                final staff = snapshot.data ?? const <AppUser>[];
                if (staff.isEmpty) return const SizedBox.shrink();
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: staff.length,
                  itemBuilder: (context, index) {
                    final user = staff[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor:
                            Theme.of(context).colorScheme.secondaryContainer,
                        foregroundColor:
                            Theme.of(context).colorScheme.onSecondaryContainer,
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

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
            'You will need your password, or a passkey, to get back in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          DestructiveButton(
            label: 'Log out',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Signing out rarely fails, but when it does the person is still signed in
    // and the screen has not changed — so without this they would tap Log out,
    // watch nothing happen, and have no idea why.
    try {
      await authRepository.signOut();
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
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
