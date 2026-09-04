import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import '../widgets/dropdown_value.dart';
import '../database/repositories.dart';
import '../models/app_user.dart';
import '../models/store.dart';
import '../widgets/feedback.dart';
import '../widgets/money.dart';
import 'store_settings_edit_menu.dart';
import 'store_delivery_platforms.dart';
import 'store_payment_methods.dart';
import 'store_staff.dart';
import '../widgets/page_body.dart';
import '../widgets/setting_tile.dart';

class StoreSettings extends StatefulWidget {
  final String storeId;

  const StoreSettings(this.storeId, {super.key});

  @override
  State<StoreSettings> createState() => _StoreSettingsState();
}

class _StoreSettingsState extends State<StoreSettings> {
  // Every dialog's controller is owned by this State, not created inside the
  // method that shows the dialog.
  //
  // `showDialog`'s future completes the moment the route is popped, which is
  // the *start* of the exit transition — the TextField is still mounted and
  // still reading its controller for another frame or two. Disposing it there
  // throws "A TextEditingController was used after being disposed", which is
  // what made Cancel crash. Tying the lifetime to the screen instead means the
  // dispose happens when nothing can still be reading it.
  final TextEditingController storeNameController = TextEditingController();
  final TextEditingController rateController = TextEditingController();
  final TextEditingController ordersController = TextEditingController();
  final TextEditingController revenueController = TextEditingController();

  /// Whether this account may change any of this.
  ///
  /// `firestore.rules` has always refused a store assistant's write here, but
  /// the screen never asked. So every manager-only row was tappable, opened a
  /// dialog, took a new value, and only then failed on save with a permission
  /// error — the worst possible order to find out in, because the person has
  /// already decided what they wanted and typed it.
  ///
  /// Resolved once on the way in, the way the order-detail screen does it,
  /// rather than watched: somebody's role changing while they have this screen
  /// open is not a case worth a second listener.
  bool _isManager = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  /// A failed lookup leaves [_isManager] false, which is the safe way round —
  /// the rows render read-only rather than offering an edit the rules would
  /// refuse anyway.
  Future<void> _loadRole() async {
    try {
      final session = await loadSession();
      if (mounted) setState(() => _isManager = session.user.role.canManage);
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  @override
  void dispose() {
    storeNameController.dispose();
    rateController.dispose();
    ordersController.dispose();
    revenueController.dispose();
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
            return ErrorView(snapshot.error!);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final store = snapshot.data;
          if (store == null) {
            return const Center(child: Text('Store not found.'));
          }

          return SafeArea(
            child: ReadingWidth(
              builder: (context, insets) => ListView(
                padding: insets +
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                children: [
                  const SettingSection('Store', first: true),
                  SettingTile.inline(
                    icon: Symbols.id_card,
                    title: 'Store name',
                    subtitle: store.name,
                    locked: !_isManager,
                    onTap: () => _editStoreNameDialog(store),
                  ),
                  // No "Store ID" row. The id is an internal identifier now —
                  // generated at registration, never displayed and never typed.
                  // Colleagues are added with an invite code instead, from the
                  // Staff screen.
                  _buildStaffTile(store),
                  if (store.createdAt != null)
                    SettingTile.readOnly(
                      icon: Symbols.timer_arrow_up,
                      title: 'Opened',
                      subtitle: DateFormat('yyyy-MM-dd  kk:mm')
                          .format(store.createdAt!),
                    ),
                  const SettingSection('Trading rules'),
                  SettingTile.inline(
                    icon: Icons.bedtime_outlined,
                    title: 'Trading day starts at',
                    subtitle:
                        '${store.dayCutoffHour.toString().padLeft(2, '0')}:00 — '
                        'orders before this count towards the previous day',
                    locked: !_isManager,
                    onTap: () => _editDayCutoffDialog(store),
                  ),
                  SettingTile.inline(
                    icon: Icons.percent_outlined,
                    title: 'Tax',
                    subtitle: store.taxRate <= 0
                        ? 'Not applied'
                        : '${formatTaxPercent(store.taxRate)}% · '
                            '${store.taxIncluded ? 'included in prices' : 'added on top'}',
                    locked: !_isManager,
                    onTap: () => _editTaxDialog(store),
                  ),
                  SettingTile.inline(
                    icon: Icons.flag_outlined,
                    title: 'Daily targets',
                    subtitle: '${store.targets.dailyOrders} orders · '
                        '${moneyFormat(store).format(store.targets.dailyRevenue)}',
                    locked: !_isManager,
                    onTap: () => _editTargetsDialog(store),
                  ),
                  // The two below stay open to everyone, because the page
                  // behind each is worth reading on a shift even when nothing
                  // on it can be changed: which methods the till offers and in
                  // what order, and what each platform keeps. The screens
                  // themselves drop their editing controls for a store
                  // assistant rather than the row refusing entry.
                  SettingTile.page(
                    icon: Icons.payments_outlined,
                    title: 'Payment methods',
                    subtitle: _paymentSummary(store),
                    onTap: () => _push(StorePaymentMethods(widget.storeId)),
                  ),
                  SettingTile.page(
                    icon: Icons.delivery_dining_outlined,
                    title: 'Delivery platforms',
                    subtitle: _platformSummary(store),
                    onTap: () => _push(StoreDeliveryPlatforms(widget.storeId)),
                  ),
                  const SettingSection('Menu'),
                  SettingTile.page(
                    icon: Icons.menu_book_outlined,
                    // Calling it "Edit Menu" to somebody who cannot edit it is
                    // a promise the next screen does not keep.
                    title: _isManager ? 'Edit menu' : 'Menu',
                    subtitle: _isManager
                        ? 'Add, edit, or retire menu items'
                        : 'Dishes, prices and categories',
                    onTap: () => _push(StoreEditMenu(widget.storeId)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// The first few methods by name, so the row says what this shop takes
  /// without being opened.
  String _paymentSummary(Store store) {
    final names = store.paymentMethods.map((m) => m.name).toList();
    final shown = names.take(3).join(' · ');
    return names.length <= 3 ? shown : '$shown · +${names.length - 3} more';
  }

  /// Names and rates, so the row says whether delivery is costed at all.
  String _platformSummary(Store store) {
    if (store.deliveryPlatforms.isEmpty) {
      return 'None yet — delivery orders are booked at zero commission';
    }
    return store.deliveryPlatforms
        .map((p) => p.commissionRate <= 0
            ? p.name
            : '${p.name} ${formatTaxPercent(p.commissionRate)}%')
        .join(' · ');
  }

  /// Staff are found by reverse lookup on `users.storeId` rather than from a
  /// list kept on the store document, which used to drift out of sync.
  Widget _buildStaffTile(Store store) {
    return StreamBuilder<List<AppUser>>(
      stream: userRepository.watchStaff(widget.storeId),
      builder: (context, snapshot) {
        final count = snapshot.data?.length;
        return SettingTile.page(
          icon: Icons.group_outlined,
          title: 'Staff',
          // `count == null` covers two different situations and used to say
          // "Loading…" for both, so a refused or offline staff query left a
          // row that loads forever — the one wording that promises something
          // is still on its way when nothing is. The row stays tappable
          // either way: the page behind it reports the failure properly, and
          // a store assistant may read the roster even though only a manager
          // can change it.
          subtitle: snapshot.hasError
              ? 'Could not read the staff list'
              : count == null
                  ? 'Loading…'
                  : '$count ${count == 1 ? 'person' : 'people'}'
                      '${_isManager ? ' · invite a colleague' : ''}',
          onTap: () => _push(StoreStaff(widget.storeId, storeName: store.name)),
        );
      },
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

    if (newName == null) return; // Cancel
    if (newName.isEmpty) {
      // Was a silent return: the dialog closed, nothing saved, nothing said.
      if (mounted) showError(context, 'A store needs a name.');
      return;
    }
    try {
      await storeRepository.updateName(widget.storeId, newName);
      _showSnackBar('Store name updated successfully');
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
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
                // Belt and braces next to the clamp in Store.fromDoc: this is
                // the screen that would be unopenable if an hour outside 0-23
                // ever reached it.
                initialValue:
                    dropdownValue(hour, List.generate(24, (h) => h)),
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
    try {
      await storeRepository.updateDayCutoffHour(widget.storeId, hour);
      // Existing orders keep the trading day they were written with; only new
      // ones use the new cutoff.
      _showSnackBar('Trading day now starts at '
          '${hour.toString().padLeft(2, '0')}:00 for new orders');
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  Future<void> _editTaxDialog(Store store) async {
    rateController.text = formatTaxPercent(store.taxRate);
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                // Digits and one point. `digitsOnly` was here, which made a
                // 1.5% rate physically untypeable — the keyboard offered the
                // decimal point and the field swallowed it.
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  _SingleDecimalPoint(),
                ],
                decoration: const InputDecoration(
                  labelText: 'Rate (%)',
                  hintText: '5',
                  helperText: 'Decimals are fine — 1.5, 8.25',
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

    if (saved != true) return;
    final rate = parseTaxPercent(rateController.text);
    if (rate == null) {
      if (mounted) showError(context, 'Enter a tax rate between 0 and 100.');
      return;
    }

    try {
      await storeRepository.updateTax(
        widget.storeId,
        taxRate: rate,
        taxIncluded: included,
      );
      _showSnackBar('Tax settings updated');
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  /// Feeds the statistics gauge, which used to be hard-coded to 60 / 200.
  Future<void> _editTargetsDialog(Store store) async {
    ordersController.text = store.targets.dailyOrders.toString();
    revenueController.text = store.targets.dailyRevenue.toString();

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
              decoration: InputDecoration(
                  labelText: 'Revenue per day '
                      '(${store.currency})'),
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

    if (saved != true) return;
    final orders = int.tryParse(ordersController.text);
    final revenue = int.tryParse(revenueController.text);
    if (orders == null || revenue == null || orders <= 0 || revenue <= 0) {
      if (mounted) {
        showError(context, 'Both targets need to be a number above zero.');
      }
      return;
    }

    try {
      await storeRepository.updateTargets(
        widget.storeId,
        StoreTargets(dailyOrders: orders, dailyRevenue: revenue),
      );
      _showSnackBar('Targets updated');
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Keeps a decimal field to one decimal point.
///
/// `FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))` lets "1.5.5" through
/// because it filters characters, not strings; this rejects the edit that
/// would produce a second point rather than trying to repair it, which leaves
/// the caret where the person left it.
class _SingleDecimalPoint extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      '.'.allMatches(newValue.text).length > 1 ? oldValue : newValue;
}
