import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import '../database/repositories.dart';
import '../models/app_user.dart';
import '../models/store.dart';
import 'store_settings_audit_log.dart';
import 'store_settings_edit_menu.dart';
import 'store_settings_history_order.dart';
import 'store_staff.dart';

class StoreSettings extends StatefulWidget {
  final String storeId;

  const StoreSettings(this.storeId, {super.key});

  @override
  State<StoreSettings> createState() => _StoreSettingsState();
}

class _StoreSettingsState extends State<StoreSettings> {
  final TextEditingController storeNameController = TextEditingController();

  @override
  void dispose() {
    storeNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Store Settings')),
      body: StreamBuilder<Store?>(
        stream: storeRepository.watch(widget.storeId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final store = snapshot.data;
          if (store == null) {
            return const Center(child: Text('Store not found.'));
          }

          return SafeArea(
            child: ListView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              children: [
                _buildListTile(
                  icon: Symbols.id_card,
                  title: 'Store Name',
                  subtitle: store.name,
                  trailing: const Icon(Icons.keyboard_arrow_right_outlined),
                  onTap: () => _editStoreNameDialog(store),
                ),
                _buildListTile(
                  icon: Icons.fingerprint,
                  title: 'Store ID',
                  subtitle: widget.storeId,
                  trailing: const Icon(Icons.keyboard_arrow_right_outlined),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: widget.storeId));
                    _showSnackBar('Store ID copied to clipboard');
                  },
                ),
                _buildStaffTile(),
                if (store.createdAt != null)
                  _buildListTile(
                    icon: Symbols.timer_arrow_up,
                    title: 'Join Time',
                    subtitle: DateFormat('yyyy-MM-dd  kk:mm')
                        .format(store.createdAt!),
                  ),
                const Divider(height: 24),
                _buildListTile(
                  icon: Icons.bedtime_outlined,
                  title: 'Trading day starts at',
                  subtitle:
                      '${store.dayCutoffHour.toString().padLeft(2, '0')}:00 — '
                      'orders before this count towards the previous day',
                  trailing: const Icon(Icons.keyboard_arrow_right_outlined),
                  onTap: () => _editDayCutoffDialog(store),
                ),
                _buildListTile(
                  icon: Icons.percent_outlined,
                  title: 'Tax',
                  subtitle: store.taxRate <= 0
                      ? 'Not applied'
                      : '${(store.taxRate * 100).toStringAsFixed(0)}% · '
                          '${store.taxIncluded ? 'included in prices' : 'added on top'}',
                  trailing: const Icon(Icons.keyboard_arrow_right_outlined),
                  onTap: () => _editTaxDialog(store),
                ),
                _buildListTile(
                  icon: Icons.flag_outlined,
                  title: 'Daily targets',
                  subtitle: '${store.targets.dailyOrders} orders · '
                      'NTD ${store.targets.dailyRevenue}',
                  trailing: const Icon(Icons.keyboard_arrow_right_outlined),
                  onTap: () => _editTargetsDialog(store),
                ),
                const Divider(height: 24),
                _buildListTile(
                  icon: Icons.menu_book_outlined,
                  title: 'Edit Menu',
                  trailing: const Icon(Icons.keyboard_arrow_right_outlined),
                  subtitle: 'Add, edit, or retire menu items',
                  onTap: () => _push(StoreEditMenu(widget.storeId)),
                ),
                _buildListTile(
                  icon: Icons.history,
                  title: 'History Order',
                  trailing: const Icon(Icons.keyboard_arrow_right_outlined),
                  subtitle: 'View order history',
                  onTap: () => _push(StoreHistoryOrder(widget.storeId)),
                ),
                _buildListTile(
                  icon: Icons.fact_check_outlined,
                  title: 'Change history',
                  trailing: const Icon(Icons.keyboard_arrow_right_outlined),
                  subtitle: 'Voids, order edits and price changes',
                  onTap: () => _push(StoreAuditLog(widget.storeId)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Staff are found by reverse lookup on `users.storeId` rather than from a
  /// list kept on the store document, which used to drift out of sync.
  Widget _buildStaffTile() {
    return StreamBuilder<List<AppUser>>(
      stream: userRepository.watchStaff(widget.storeId),
      builder: (context, snapshot) {
        final count = snapshot.data?.length;
        return _buildListTile(
          icon: Icons.group_outlined,
          trailing: const Icon(Icons.keyboard_arrow_right_outlined),
          title: 'Staff',
          subtitle: count == null ? 'Loading…' : '$count users',
          onTap: () => _push(StoreStaff(widget.storeId)),
        );
      },
    );
  }

  Widget _buildListTile({
    required IconData? icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    void Function()? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }

  void _push(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  Future<void> _editStoreNameDialog(Store store) async {
    storeNameController.text = store.name;

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Store Name'),
        content: TextField(
          autofocus: true,
          controller: storeNameController,
          decoration: const InputDecoration(
            labelText: 'Store Name',
            hintText: 'Enter new store name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, storeNameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;
    await storeRepository.updateName(widget.storeId, newName);
    _showSnackBar('Store name updated successfully');
  }

  /// The hour a trading day rolls over. A late-night kitchen counts 02:00 as
  /// still being the previous day; a store that shuts at nine does not.
  Future<void> _editDayCutoffDialog(Store store) async {
    var hour = store.dayCutoffHour;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Trading day starts at'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Orders taken before this hour are counted towards the '
                'previous trading day. Set 0 to use the calendar day.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: hour,
                decoration: const InputDecoration(labelText: 'Hour'),
                items: List.generate(
                  24,
                  (h) => DropdownMenuItem(
                    value: h,
                    child: Text('${h.toString().padLeft(2, '0')}:00'),
                  ),
                ),
                onChanged: (value) =>
                    setStateDialog(() => hour = value ?? hour),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    await storeRepository.updateDayCutoffHour(widget.storeId, hour);
    // Existing orders keep the trading day they were written with; only new
    // ones use the new cutoff.
    _showSnackBar('Trading day now starts at '
        '${hour.toString().padLeft(2, '0')}:00 for new orders');
  }

  Future<void> _editTaxDialog(Store store) async {
    final rateController = TextEditingController(
        text: (store.taxRate * 100).toStringAsFixed(0));
    var included = store.taxIncluded;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Tax'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: rateController,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Rate (%)',
                  hintText: '5',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Included in menu prices'),
                value: included,
                onChanged: (value) => setStateDialog(() => included = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    final percent = int.tryParse(rateController.text) ?? 0;
    rateController.dispose();
    if (saved != true) return;

    await storeRepository.updateTax(
      widget.storeId,
      taxRate: percent / 100,
      taxIncluded: included,
    );
    _showSnackBar('Tax settings updated');
  }

  /// Feeds the statistics gauge, which used to be hard-coded to 60 / 200.
  Future<void> _editTargetsDialog(Store store) async {
    final ordersController =
        TextEditingController(text: store.targets.dailyOrders.toString());
    final revenueController =
        TextEditingController(text: store.targets.dailyRevenue.toString());

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Daily targets'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ordersController,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Orders per day'),
            ),
            TextField(
              controller: revenueController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration:
                  const InputDecoration(labelText: 'Revenue per day (NTD)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    final orders = int.tryParse(ordersController.text);
    final revenue = int.tryParse(revenueController.text);
    ordersController.dispose();
    revenueController.dispose();
    if (saved != true || orders == null || revenue == null) return;

    await storeRepository.updateTargets(
      widget.storeId,
      StoreTargets(dailyOrders: orders, dailyRevenue: revenue),
    );
    _showSnackBar('Targets updated');
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
