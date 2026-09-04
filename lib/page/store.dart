import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/repositories.dart';
import '../models/app_user.dart';
import '../settings/account_settings.dart';
import '../settings/screen_lock.dart';
import '../settings/store_security.dart';
import '../settings/store_import_orders.dart';
import '../settings/store_settings.dart';
import '../settings/store_settings_audit_log.dart';
import '../settings/store_settings_history_order.dart';
import '../settings/user_manual.dart';
import '../widgets/feedback.dart';
import '../widgets/money.dart';
import '../widgets/page_body.dart';
import '../widgets/setting_tile.dart';

/// The shop, and everything about it that is not an order.
///
/// Three groups, each answering a question that can be asked in one sentence:
/// how is the shop set up, what has it done, and who am I on this device.
/// What used to be here instead was three settings entries plus a loose Log
/// out row, with a duplicate way into Store Settings above them and two
/// lifetime totals — a figure the Reports tab exists to show — taking up the
/// first screenful.
///
/// The three records are rows here rather than a "Records" screen holding
/// them. Wrapping them in one would have grouped them correctly and moved
/// nothing: an order history two pushes from the tab is two pushes either way,
/// and the whole complaint was that it sat too deep to be daily work. Flat,
/// the history is one push and an order's detail is two, which is what killed
/// the "View All" shortcut Today had grown to route around it.
class StorePage extends StatefulWidget {
  const StorePage({super.key});

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  late Future<_StoreOverview> _future = _load();

  /// The last load that worked.
  ///
  /// Pulling to refresh used to be able to destroy this screen. The gesture
  /// re-ran the load, and a load that failed — a moment offline is enough —
  /// replaced the entire page with an error, navigation rows and all. So one
  /// pull on a bad connection took away the way into Store settings, the order
  /// history and the account screen, none of which had anything to do with the
  /// figures being refreshed.
  ///
  /// Holding the last good result means a failed refresh leaves the page
  /// exactly as it was and says so in a snack bar, which is what a refresh
  /// gesture should do everywhere.
  _StoreOverview? _lastGood;

  /// The store id is the one thing on this screen that nothing can be drawn
  /// without, so [loadSession] is the only call allowed to fail the page. The
  /// lifetime totals are a caption; if the rollup read fails, the caption goes
  /// and the rest of the screen carries on.
  Future<_StoreOverview> _load() async {
    final session = await loadSession();
    StoreTotals? totals;
    try {
      totals = await statsRepository.fetchTotals(session.storeId);
    } catch (_) {
      totals = null;
    }
    return _StoreOverview(session: session, totals: totals);
  }

  /// Re-reads, and reports a failure without taking the screen down with it.
  ///
  /// Bounded, because `RefreshIndicator` keeps its spinner up and the list
  /// locked for exactly as long as this future takes, with no way for anybody
  /// to cancel it. A read that never answers therefore does not look like a
  /// slow refresh — it looks like the app has stopped, on a screen whose whole
  /// job is to be the way into settings, history and the account.
  static const Duration _refreshTimeout = Duration(seconds: 20);

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    try {
      // The timeout is on the wait, not on the load: `_future` is left running
      // so a late answer still reaches the screen through the FutureBuilder.
      await next.timeout(_refreshTimeout);
    } on TimeoutException {
      if (mounted) {
        showInfo(context, 'Still trying — showing what was last loaded');
      }
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StoreOverview>(
      future: _future,
      builder: (context, snapshot) {
        final overview = snapshot.data ?? _lastGood;
        if (overview == null) {
          // Nothing has ever loaded, so there is genuinely nothing to draw.
          if (snapshot.hasError) {
            return ErrorView(
              snapshot.error!,
              onRetry: () => setState(() => _future = _load()),
            );
          }
          return const Center(child: CircularProgressIndicator());
        }
        _lastGood = overview;
        return _buildStorePage(overview);
      },
    );
  }

  Widget _buildStorePage(_StoreOverview overview) {
    final session = overview.session;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          // Worth keeping despite this being mostly a navigation screen: the
          // lifetime figures on the card are a one-shot read, and the shell
          // keeps this page alive once built, so without a pull there is no
          // way to see them move.
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: PageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildStoreCard(overview),
                  const SettingSection('Setup'),
                  SettingTile.page(
                    icon: Icons.storefront_outlined,
                    title: 'Store settings',
                    subtitle: 'Menu, prices, tax, targets, staff',
                    onTap: () => _navigateTo(StoreSettings(session.storeId)),
                  ),
                  const SettingSection('Records'),
                  SettingTile.page(
                    icon: Icons.history,
                    title: 'Order history',
                    subtitle: 'Every order, with what was in it',
                    onTap: () =>
                        _navigateTo(StoreHistoryOrder(session.storeId)),
                  ),
                  SettingTile.page(
                    icon: Icons.upload_file_outlined,
                    title: 'Import orders',
                    subtitle: 'Read a delivery platform’s statement into '
                        'the till',
                    onTap: () => _navigateTo(StoreImportOrders(session.storeId)),
                  ),
                  SettingTile.page(
                    icon: Icons.fact_check_outlined,
                    title: 'Change history',
                    subtitle: 'Voids, order edits and price changes',
                    // `auditLogs` grants read to managers alone, so for anybody
                    // else this row would open and then show a permission
                    // error — which reads as a broken screen, not a closed
                    // door. The other two rows stay open: orders are readable
                    // and creatable by any member.
                    locked: !session.user.role.canManage,
                    onTap: () => _openLocked(
                      StoreAuditLog(session.storeId),
                      'Unlock to open the change history',
                    ),
                  ),
                  SettingTile.page(
                    icon: Icons.shield_outlined,
                    title: 'Security',
                    subtitle: 'What protects this shop, and the screen lock',
                    onTap: () => _navigateTo(StoreSecurity(
                      storeId: session.storeId,
                      role: session.user.role,
                    )),
                  ),
                  const SettingSection('You'),
                  SettingTile.page(
                    icon: Icons.manage_accounts_outlined,
                    title: 'Account & app',
                    subtitle: 'Your profile, sign-in, appearance, log out',
                    onTap: () => _openLocked(
                      const AccountSettings(),
                      'Unlock to open your account',
                    ),
                  ),
                  SettingTile.page(
                    icon: Icons.help_outline_rounded,
                    title: 'How this works',
                    subtitle: 'What the figures mean and where they come from',
                    onTap: () => _navigateTo(const UserManual()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStoreCard(_StoreOverview overview) {
    final theme = Theme.of(context);
    final session = overview.session;
    // Lifetime revenue is summed from the daily rollups rather than kept as a
    // running counter on the store document. It was two large stat cards, the
    // same shape and weight the Reports tab uses for the figures it is *for*;
    // one line of caption is the right size for a number nobody comes to this
    // screen to read.
    final money = moneyFormat(session.store);
    final counts = NumberFormat.decimalPattern();
    final totals = overview.totals;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.store.name,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            // Omitted rather than zeroed when the rollup could not be read:
            // "0 across 0 orders" is a shop that has never sold anything, and
            // that is not what happened.
            if (totals != null) ...[
              const SizedBox(height: 2),
              Text(
                '${money.format(totals.revenue)} across '
                '${counts.format(totals.orderCount)} orders, all time',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 8),
            StreamBuilder<List<AppUser>>(
              stream: userRepository.watchStaff(session.storeId),
              builder: (context, snapshot) {
                // An errored stream must not render as an empty roster: a
                // store whose staff could not be read looks exactly like a
                // store with no staff, and the second is a normal state.
                if (snapshot.hasError) {
                  return Text(
                    describeFailure(snapshot.error!).message,
                    style: TextStyle(color: theme.colorScheme.error),
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
                        backgroundColor: theme.colorScheme.secondaryContainer,
                        foregroundColor:
                            theme.colorScheme.onSecondaryContainer,
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

  void _navigateTo(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  /// Opens a screen that a stranger behind an unattended counter should not
  /// reach. No-ops when the lock is off, which is the default.
  Future<void> _openLocked(Widget page, String reason) async {
    if (!await screenLock.confirm(reason)) return;
    if (!mounted) return;
    _navigateTo(page);
  }
}

class _StoreOverview {
  const _StoreOverview({required this.session, required this.totals});

  final Session session;

  /// Null when the rollup read failed. The screen drops the line rather than
  /// showing a figure it does not have.
  final StoreTotals? totals;
}
