import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/repositories.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../models/order_draft.dart';
import '../models/store.dart';
import '../settings/store_payment_methods.dart';
import '../settings/store_settings_edit_menu.dart';
import '../widgets/feedback.dart';
import '../widgets/money.dart';
import '../widgets/payment_icons.dart';
import '../widgets/pending_orders.dart';
import '../widgets/text_scale.dart';

/// A row on the order screen: an active menu item, or a retired one that an
/// order being edited still contains.
class _MenuRow {
  const _MenuRow({
    required this.itemId,
    required this.name,
    required this.price,
    required this.cost,
    required this.icon,
    this.categoryId,
    this.aliases = const [],
    this.retired = false,
  });

  final String itemId;
  final String name;
  final int price;
  final int cost;
  final IconData icon;
  final String? categoryId;

  /// What the kitchen calls it. The search box matches these as well as the
  /// printed name — a shop whose slips say 牛麵 should be able to type 牛麵.
  final List<String> aliases;

  final bool retired;

  factory _MenuRow.fromMenuItem(MenuItem item) => _MenuRow(
        itemId: item.id,
        name: item.name,
        price: item.price,
        cost: item.cost,
        icon: item.iconData,
        categoryId: item.categoryId,
        aliases: item.aliases,
      );

  /// Built from the frozen copy on the order, so a retired dish still shows the
  /// price it was actually sold at.
  factory _MenuRow.fromOrderLine(OrderLine line) => _MenuRow(
        itemId: line.itemId,
        name: line.name,
        price: line.unitPrice,
        cost: line.unitCost,
        icon: Icons.history_toggle_off,
        categoryId: line.categoryId,
        retired: true,
      );
}

class AddOrder extends StatefulWidget {
  const AddOrder(this.storeId, {super.key, this.existing});

  final String storeId;

  /// Non-null when editing an order that has already been rung up.
  final Order? existing;

  @override
  State<AddOrder> createState() => _AddOrderState();
}

class _AddOrderState extends State<AddOrder> {
  Store? _store;
  List<MenuItem> _menu = const [];
  Object? _loadError;

  /// itemId -> quantity.
  final Map<String, int> _quantities = {};

  /// Held here rather than left to the tile, which is inside the scrolling
  /// menu list: a tile that keeps its own expansion state is disposed when it
  /// scrolls off the top and comes back collapsed, folding away the channel
  /// and payment somebody had just opened.
  final ExpansibleController _optionsController = ExpansibleController();

  /// Set only when somebody picks a time by hand. Null means "whenever this
  /// order is actually rung up".
  ///
  /// This used to be a plain `DateTime` filled in from `DateTime.now()` in
  /// `initState` and again after each submit — so the till, which stays open
  /// on this screen between customers, stamped every order with the time the
  /// *previous* one was saved. An hour's gap meant an hour-wrong timestamp: the
  /// wrong bucket in Revenue by hour, and across 04:00 the wrong trading day
  /// altogether.
  DateTime? _placedAtOverride;

  OrderChannel _channel = OrderChannel.dineIn;
  String? _deliveryPlatformId;
  int _guestCount = 1;

  /// A [StorePaymentMethod.id]. Starts on the store's first method once the
  /// store has loaded, unless an order being edited says otherwise.
  String _paymentMethodId = kDefaultPaymentMethodId;
  bool _paymentMethodChosen = false;
  bool _submitting = false;

  /// Free-text filter over dish names. A shop with sixty dishes across six
  /// categories still means scrolling to reach one of them by eye.
  String _query = '';
  final _searchController = TextEditingController();

  /// Tiles or rows.
  ///
  /// The list is the better view for reading — it has room for the price, the
  /// category and a stepper on one line. But a till is operated by someone
  /// standing up, often in a hurry, sometimes with wet hands, and a 56pt row
  /// with a 24pt `-`/`+` pair at the far right is the wrong target for that.
  /// The grid gives each dish a single large button. Neither is right for
  /// everyone, so both are here and the choice is remembered.
  bool _posMode = false;

  bool get _isEdit => widget.existing != null;

  /// The time this order will carry: the one that was chosen, or now.
  DateTime get _placedAt => _placedAtOverride ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    // An order being edited keeps the time it was rung up at.
    _placedAtOverride = widget.existing?.placedAt;
    if (existing != null) {
      _channel = existing.channel;
      _deliveryPlatformId = existing.deliveryPlatformId;
      _guestCount = existing.guestCount;
      _paymentMethodId = existing.paymentMethodId;
      _paymentMethodChosen = true;
      for (final line in existing.items) {
        _quantities[line.itemId] = line.qty;
      }
    }
    _load();
    _loadLayout();
  }

  Future<void> _loadLayout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() => _posMode = prefs.getBool(_posModeKey) ?? false);
      }
    } catch (_) {
      // The list view is the safe default.
    }
  }

  Future<void> _setPosMode(bool on) async {
    setState(() => _posMode = on);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_posModeKey, on);
    } catch (_) {
      // Changed for this visit; just not remembered.
    }
  }

  static const _posModeKey = 'addOrder.posMode';

  Future<void> _load() async {
    try {
      final store = await storeRepository.fetch(widget.storeId);
      final menu = await menuRepository.fetchActive(widget.storeId);
      if (!mounted) return;
      if (store == null) {
        setState(() => _loadError = DataException(
              DataFailure.notFound,
              'Store ${widget.storeId} was not found.',
            ));
        return;
      }
      setState(() {
        _store = store;
        _menu = menu;
        // Whatever this shop put first, rather than a hard-coded 'cash' — a
        // card-only cafe should not have to change the payment on every order.
        if (!_paymentMethodChosen) {
          _paymentMethodId = store.defaultPaymentMethodId;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  /// Active dishes, plus any retired dish the edited order still contains so
  /// its quantity remains adjustable.
  List<_MenuRow> get _rows {
    final rows = _menu.map(_MenuRow.fromMenuItem).toList();
    final known = rows.map((r) => r.itemId).toSet();
    for (final line in widget.existing?.items ?? const <OrderLine>[]) {
      if (!known.contains(line.itemId)) rows.add(_MenuRow.fromOrderLine(line));
    }
    return rows;
  }

  OrderDraft _buildDraft() {
    final byId = {for (final row in _rows) row.itemId: row};
    final items = <OrderLine>[];
    _quantities.forEach((itemId, qty) {
      final row = byId[itemId];
      if (row == null || qty <= 0) return;
      items.add(OrderLine(
        itemId: row.itemId,
        name: row.name,
        categoryId: row.categoryId,
        unitPrice: row.price,
        unitCost: row.cost,
        qty: qty,
      ));
    });

    return OrderDraft(
      placedAt: _placedAt,
      items: items,
      channel: _channel,
      guestCount: _guestCount,
      deliveryPlatformId: _deliveryPlatformId,
      paymentMethodId: _paymentMethodId,
    );
  }

  Future<void> _selectDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _placedAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_placedAt),
    );
    // The same guard the date picker above already has. Both pickers can be
    // torn down with the page under them — an Android back gesture, or the
    // process being trimmed — and only one of the two was checking.
    if (time == null || !mounted) return;

    setState(() {
      _placedAtOverride =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    final store = _store;
    if (store == null || _submitting) return;

    final draft = _buildDraft();
    if (draft.isEmpty) {
      _snack('No items in order!', isError: true);
      return;
    }
    if (_channel == OrderChannel.delivery &&
        store.deliveryPlatforms.isNotEmpty &&
        _deliveryPlatformId == null) {
      _snack('Choose a delivery platform', isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      if (_isEdit) {
        await orderRepository.replace(
          store: store,
          orderId: widget.existing!.id,
          draft: draft,
          by: currentActor(),
        );
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

      final orderNo = await orderRepository.submit(
        store: store,
        draft: draft,
        createdBy: authRepository.currentUid,
      );
      if (!mounted) return;
      _snack('Order #$orderNo added');
      setState(() {
        _quantities.clear();
        // Back to "now" rather than to this instant: the next order is stamped
        // when it is rung up, not when this one was.
        _placedAtOverride = null;
        _guestCount = 1;
      });
    } catch (e) {
      // The draft is left exactly as it was, quantities included: an order
      // that failed to save is an order somebody still has to ring up, and
      // making them tap it in again is the worst possible response to a
      // dropped connection.
      final failure = describeFailure(e);
      // A new order with no connection is not a failure the person at the till
      // can do anything about, and "try again later" is not an answer with a
      // customer standing there. It goes on the device instead, keeping the
      // time it was rung up at, and is sent when there is a connection.
      //
      // Only new orders. An edit has to be applied against the order as it
      // stands on the server — which is exactly what cannot be read offline —
      // so it stays a failure and says so.
      if (!_isEdit && failure.failure == DataFailure.offline) {
        await _queueOffline(store, draft);
        return;
      }
      _snack(
        failure.failure == DataFailure.offline
            // The generic wording ("check your network and try again") reads
            // like the edit may have gone through. It has not.
            ? 'No connection, so this change could not be saved. Nothing has '
                'been altered — try again once you are back online.'
            : failure.message,
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Puts an order that could not be sent on the device's queue, and clears
  /// the till for the next customer.
  Future<void> _queueOffline(Store store, OrderDraft draft) async {
    await pendingOrders.add(store.id, draft);
    if (!mounted) return;
    setState(() {
      _quantities.clear();
      _placedAtOverride = null;
      _guestCount = 1;
    });
    final waiting = pendingOrders.length;
    _snack('Saved on this device — $waiting '
        '${waiting == 1 ? 'order is' : 'orders are'} waiting to be sent. '
        'It keeps the time it was rung up at.');
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    showSnack(context, message, isError: isError);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _optionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // A tap on the phone's back gesture used to discard a full basket
      // without a word.
      canPop: _quantities.isEmpty || _submitting,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? 'Edit Order' : 'Add Order'),
          actions: [
            IconButton(
              tooltip: _posMode ? 'Show as a list' : 'Show as big buttons',
              icon: Icon(_posMode
                  ? Icons.view_list_outlined
                  : Icons.grid_view_rounded),
              onPressed: () => _setPosMode(!_posMode),
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    final lines = _quantities.length;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard this order?'),
            content: Text(
              '$lines ${lines == 1 ? 'dish is' : 'dishes are'} on it. '
              'Nothing has been rung up yet.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return ErrorView(_loadError!, onRetry: _load);
    }
    final store = _store;
    if (store == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final rows = _rows;
    final draft = _buildDraft();
    final totals = draft.price(store);

    // A tablet or a desktop window has room to keep dine-in / takeout /
    // delivery, the guest count and the payment permanently on screen. Folding
    // them into a collapsed tile — the right answer on a phone, where the menu
    // needs the whole screen — turns a one-tap setting into three on the one
    // layout that has space to spare, and leaves a third of a 1200pt window as
    // margin while it does it.
    final wide = MediaQuery.sizeOf(context).width >= _twoPaneWidth;

    return Column(
      children: [
        Expanded(
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildMenuList(store, rows)),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      // The panel is a column of labelled controls, so it
                      // takes its width from the text in it rather than from
                      // a number that was measured at one font size.
                      width: scaledForText(context, 360, cap: 1.5),
                      child: _buildOptionsPanel(store),
                    ),
                  ],
                )
              : _buildMenuList(store, rows, options: true),
        ),
        _buildSummary(store, totals),
      ],
    );
  }

  /// Past this the order settings get a column of their own.
  static const double _twoPaneWidth = 840;

  /// The dishes, with the collapsed settings tile above them on a phone.
  Widget _buildMenuList(
    Store store,
    List<_MenuRow> rows, {
    bool options = false,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        // Collapsed by default. Date, channel, guests and payment used
        // to fill the whole first screen, so ringing up an order — the
        // thing this page is for — started with a scroll past four
        // settings that are right nearly every time. The header carries
        // their current values, so nothing is hidden, only folded.
        if (options) _buildOptionsTile(store),
        if (rows.isNotEmpty) _buildSearchField(),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                const Text(
                  'No dishes on the menu yet.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // Naming the screen and leaving someone to find it is
                // most of the way to helping.
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StoreEditMenu(widget.storeId),
                    ),
                  ),
                  icon: const Icon(Icons.restaurant_menu),
                  label: const Text('Edit the menu'),
                ),
              ],
            ),
          )
        else
          ..._buildMenuSections(store, rows),
      ],
    );
  }

  /// The same four settings as [_buildOptionsTile], open and staying open.
  Widget _buildOptionsPanel(Store store) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            'Order details',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        _buildDateTile(store),
        _buildChannelTile(store),
        if (_channel == OrderChannel.delivery &&
            store.deliveryPlatforms.isNotEmpty)
          _buildPlatformTile(store),
        _buildGuestCountTile(),
        _buildPaymentTile(store),
      ],
    );
  }

  Widget _buildSearchField() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value.trim()),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search the menu',
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
      );

  /// A one-line summary of the four order settings: "Dine in · 2 guests ·
  /// Cash · today 14:30".
  String _optionsSummary(Store store) {
    final parts = <String>[_channel.label];
    if (_channel == OrderChannel.delivery) {
      final platform = store.platformById(_deliveryPlatformId);
      if (platform != null) parts.add(platform.name);
    }
    parts.add('$_guestCount ${_guestCount == 1 ? 'guest' : 'guests'}');
    parts.add(store.paymentMethodById(_paymentMethodId).name);
    parts.add(DateFormat('MMM d, HH:mm').format(_placedAt));
    return parts.join('  ·  ');
  }

  Widget _buildOptionsTile(Store store) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        controller: _optionsController,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.tune_rounded),
        title: const Text('Order details'),
        subtitle: Text(
          _optionsSummary(store),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          _buildDateTile(store),
          _buildChannelTile(store),
          if (_channel == OrderChannel.delivery &&
              store.deliveryPlatforms.isNotEmpty)
            _buildPlatformTile(store),
          _buildGuestCountTile(),
          _buildPaymentTile(store),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// The menu, under its category headings.
  ///
  /// The categories were already on every dish and already editable under
  /// Store Settings; this screen ignored them and laid the whole menu out as
  /// one flat list, which on a real menu means scrolling past the drinks to
  /// reach the mains. Dishes in no category, and retired ones carried in by an
  /// edited order, go last under their own headings.
  List<Widget> _buildMenuSections(Store store, List<_MenuRow> rows) {
    if (_query.isNotEmpty) {
      final needle = _query.toLowerCase();
      rows = rows
          .where((r) =>
              r.name.toLowerCase().contains(needle) ||
              r.aliases.any((a) => a.toLowerCase().contains(needle)))
          .toList();
      if (rows.isEmpty) {
        return [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text('No dish matches “$_query”.')),
          ),
        ];
      }
      // A search result is already a shortlist; splitting it back into
      // categories would put one dish under each of four headings.
      return [_buildGroup(rows)];
    }

    final sections = <Widget>[];

    void section(String title, List<_MenuRow> items) {
      if (items.isEmpty) return;
      sections
        ..add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ))
        ..add(_buildGroup(items));
    }

    final live = rows.where((r) => !r.retired).toList();
    final retired = rows.where((r) => r.retired).toList();

    for (final category in store.categories) {
      section(category.name,
          live.where((r) => r.categoryId == category.id).toList());
    }

    final categorised = store.categories.map((c) => c.id).toSet();
    final loose = live
        .where(
            (r) => r.categoryId == null || !categorised.contains(r.categoryId))
        .toList();
    // No heading when there is nothing to distinguish it from: a store with no
    // categories at all should just see its menu.
    if (sections.isEmpty) {
      sections.add(_buildGroup(loose));
    } else {
      section('Uncategorised', loose);
    }
    section('No longer on the menu', retired);

    return sections;
  }

  /// One category's dishes, in whichever layout is selected.
  Widget _buildGroup(List<_MenuRow> items) {
    if (!_posMode) {
      return Column(children: items.map(_buildMenuRow).toList());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Roughly 150pt tiles, so a phone gets two per row and a tablet more,
        // rather than a fixed count that is cramped on one and silly on the
        // other.
        final columns = (constraints.maxWidth / 150).floor().clamp(2, 5);
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.05,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: items.map(_buildMenuTile).toList(),
        );
      },
    );
  }

  Widget _buildDateTile(Store store) {
    final placedAt = _placedAt;
    final businessDate = store.businessDateOf(placedAt);
    final calendarDate = DateFormat('yyyy-MM-dd').format(placedAt);
    final notes = <String>[
      // An order rung up after midnight belongs to the previous trading day.
      // Say so rather than let the owner wonder why it is on yesterday's sheet.
      if (businessDate != calendarDate)
        'Counts towards trading day $businessDate',
      if (_placedAtOverride == null) 'Stamped when the order is added',
    ];
    return ListTile(
      leading: const Icon(Icons.calendar_today),
      title: Text(DateFormat('yyyy/MM/dd  HH:mm').format(placedAt)),
      subtitle: notes.isEmpty ? null : Text(notes.join(' · ')),
      trailing: _placedAtOverride == null
          ? const Icon(Icons.edit_outlined)
          : IconButton(
              tooltip: 'Back to the time it is added',
              icon: const Icon(Icons.restore_rounded),
              onPressed: () => setState(() => _placedAtOverride = null),
            ),
      onTap: _selectDateTime,
    );
  }

  Widget _buildChannelTile(Store store) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SegmentedButton<OrderChannel>(
        // The channel's own icon says which segment is which; the tick Material
        // adds on top only costs width, and width is what the side column has
        // least of.
        showSelectedIcon: false,
        segments: OrderChannel.values
            .map((c) => ButtonSegment(
                  value: c,
                  icon: Icon(c.icon),
                  label: Text(c.label),
                ))
            .toList(),
        selected: {_channel},
        onSelectionChanged: (selection) => setState(() {
          _channel = selection.first;
          if (_channel != OrderChannel.delivery) {
            _deliveryPlatformId = null;
          } else {
            _deliveryPlatformId ??= store.deliveryPlatforms.isNotEmpty
                ? store.deliveryPlatforms.first.id
                : null;
          }
        }),
      ),
    );
  }

  Widget _buildPlatformTile(Store store) {
    final platform = store.platformById(_deliveryPlatformId);
    return ListTile(
      leading: const Icon(Icons.storefront_outlined),
      title: DropdownButtonFormField<String>(
        initialValue: _deliveryPlatformId,
        decoration: const InputDecoration(labelText: 'Delivery platform'),
        items: store.deliveryPlatforms
            .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
            .toList(),
        onChanged: (value) => setState(() => _deliveryPlatformId = value),
      ),
      subtitle: platform == null || platform.commissionRate <= 0
          ? null
          : Text(
              'Commission ${(platform.commissionRate * 100).toStringAsFixed(0)}%'),
    );
  }

  Widget _buildGuestCountTile() {
    return ListTile(
      leading: const Icon(Icons.groups_outlined),
      title: const Text('Guests'),
      // Without this, a family of four sharing one bill counts as one customer
      // and the per-head spend comes out four times too high.
      subtitle: const Text('People on this bill'),
      trailing: _buildStepper(
        value: _guestCount,
        min: 1,
        label: 'Guests',
        onChanged: (delta) =>
            setState(() => _guestCount = (_guestCount + delta).clamp(1, 99)),
      ),
    );
  }

  /// The methods come from the store, not from a fixed enum, so a shop that
  /// takes 街口支付 or runs monthly accounts can say so — and the payment
  /// breakdown in Reports then means something.
  Widget _buildPaymentTile(Store store) {
    final current = store.paymentMethodById(_paymentMethodId);
    return ListTile(
      leading: Icon(paymentIconData(current.iconKey)),
      title: Text('Payment: ${current.name}'),
      trailing: const Icon(Icons.arrow_forward_rounded),
      onTap: () => showModalBottomSheet<void>(
        showDragHandle: true,
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final method in store.paymentMethods)
                ListTile(
                  leading: Icon(paymentIconData(method.iconKey)),
                  title: Text(method.name),
                  selected: method.id == current.id,
                  onTap: () {
                    setState(() {
                      _paymentMethodId = method.id;
                      _paymentMethodChosen = true;
                    });
                    Navigator.pop(sheetContext);
                  },
                ),
              const Divider(height: 1),
              // The list is a shop setting, and the moment somebody notices it
              // is missing something is while they are ringing an order up.
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Edit payment methods'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _editPaymentMethods();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editPaymentMethods() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StorePaymentMethods(widget.storeId),
      ),
    );
    // The store is held as a snapshot here, so a method added on that screen
    // would otherwise not appear until this page was left and re-entered.
    await _load();
  }

  String _priceLabel(int price) => moneyFormat(_store).format(price);

  Widget _buildMenuRow(_MenuRow row) {
    final qty = _quantities[row.itemId] ?? 0;
    return ListTile(
      leading: Icon(row.icon),
      title: Text(row.retired ? '${row.name}  (retired)' : row.name),
      subtitle: Text(_priceLabel(row.price)),
      trailing: _buildStepper(
        value: qty,
        onChanged: (delta) => setState(() {
          final next = qty + delta;
          if (next <= 0) {
            _quantities.remove(row.itemId);
          } else {
            _quantities[row.itemId] = next;
          }
        }),
      ),
    );
  }

  /// One dish as a single large button.
  ///
  /// The whole tile is the target — around 150×140 rather than the 24pt icon
  /// button a list row offers — because the person using this is standing at a
  /// counter, not reading. Tap adds one; the small minus in the corner appears
  /// only once there is something to take away, so an untouched tile has
  /// exactly one thing you can do to it.
  Widget _buildMenuTile(_MenuRow row) {
    final qty = _quantities[row.itemId] ?? 0;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = qty > 0;

    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outline,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // `Positioned.fill`, not a bare child: a `Stack` hands its
          // non-positioned children *loose* constraints, so the InkWell shrank
          // to the width of the widest thing in the Column. On a dish named
          // 白飯 that was about a third of the tile, and the other two thirds —
          // still card, still looking exactly like a button — did nothing when
          // tapped. Filling the stack makes the whole tile the target the
          // comment below has always claimed it is.
          Positioned.fill(
            child: InkWell(
              onTap: () => _addOne(row),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      row.icon,
                      size: 28,
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Text(
                        row.retired ? '${row.name} (retired)' : row.name,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      _priceLabel(row.price),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (selected)
            Positioned(
              top: 4,
              right: 4,
              child: Semantics(
                label: '${row.name} $qty on this order',
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$qty',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: scheme.onPrimary)),
                ),
              ),
            ),
          if (selected)
            Positioned(
              bottom: 0,
              right: 0,
              // No `visualDensity: compact` here, tempting as it is for the
              // corner of a tile: compact takes 8pt off each axis and puts the
              // target at 40x40, under the 48x48 floor. On a till operated at
              // speed the undo button is the one that most needs to be hit
              // first time.
              child: IconButton(
                tooltip: 'One fewer ${row.name}',
                icon: Icon(Icons.remove_circle_outline,
                    color: scheme.onPrimaryContainer),
                onPressed: () => _removeOne(row),
              ),
            ),
        ],
      ),
    );
  }

  /// The lines currently on the order, adjustable without leaving the grid.
  void _showBasket() {
    final byId = {for (final row in _rows) row.itemId: row};
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final entries = _quantities.entries
              .where((e) => byId.containsKey(e.key))
              .toList();
          if (entries.isEmpty) {
            Navigator.pop(sheetContext);
            return const SizedBox.shrink();
          }
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.6,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text('On this order',
                        style: Theme.of(sheetContext).textTheme.titleMedium),
                  ),
                  for (final entry in entries)
                    ListTile(
                      title: Text(byId[entry.key]!.name),
                      subtitle: Text(_priceLabel(byId[entry.key]!.price)),
                      trailing: _buildStepper(
                        value: entry.value,
                        label: byId[entry.key]!.name,
                        onChanged: (delta) {
                          // Both states: the sheet redraws itself, the page
                          // behind it redraws its total.
                          setSheetState(() {});
                          delta > 0
                              ? _addOne(byId[entry.key]!)
                              : _removeOne(byId[entry.key]!);
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _addOne(_MenuRow row) => setState(
      () => _quantities[row.itemId] = (_quantities[row.itemId] ?? 0) + 1);

  void _removeOne(_MenuRow row) => setState(() {
        final next = (_quantities[row.itemId] ?? 0) - 1;
        if (next <= 0) {
          _quantities.remove(row.itemId);
        } else {
          _quantities[row.itemId] = next;
        }
      });

  Widget _buildStepper({
    required int value,
    required void Function(int delta) onChanged,
    int min = 0,
    String label = 'quantity',
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'One fewer',
          icon: const Icon(Icons.remove),
          // Was always enabled, so at zero it looked live and did nothing.
          onPressed: value <= min ? null : () => onChanged(-1),
        ),
        // Was a fixed 24pt box, which clipped three digits and clipped two as
        // soon as the phone's text size went up.
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 32),
          child: Semantics(
            label: '$label $value',
            child: Text('$value',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        IconButton(
          tooltip: 'One more',
          icon: const Icon(Icons.add),
          onPressed: () => onChanged(1),
        ),
      ],
    );
  }

  Widget _buildSummary(Store store, OrderTotals totals) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = moneyFormat(store);
    final rate = formatTaxPercent(store.taxRate);

    final taxLabel = store.taxRate <= 0
        ? 'No tax configured'
        : store.taxIncluded
            ? 'Includes tax ${money.format(totals.taxAmount)} ($rate%)'
            : 'Plus tax ${money.format(totals.taxAmount)} ($rate%)';

    final fine =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return Material(
      elevation: 3,
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The shell's offline banner sits behind this route, and this is
            // the one screen where the answer differs by what you are doing:
            // a new order is queued on the device, an edit cannot be. Saying
            // which before the button is pressed beats saying it afterwards.
            _OfflineStrip(isEdit: _isEdit),
            PendingOrdersBar(currency: store.currency),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(taxLabel, style: fine),
                  if (totals.commissionAmount > 0)
                    Text(
                        'Platform commission '
                        '${money.format(totals.commissionAmount)}',
                        style: fine),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // In grid mode the chosen dishes are scattered across
                      // the tiles, so the bill itself needs somewhere to live.
                      if (_quantities.isNotEmpty)
                        TextButton.icon(
                          onPressed: _showBasket,
                          icon:
                              const Icon(Icons.receipt_long_outlined, size: 18),
                          label: Text(
                            '${_quantities.length} '
                            '${_quantities.length == 1 ? 'dish' : 'dishes'}',
                          ),
                        )
                      else
                        Text('Total', style: theme.textTheme.titleMedium),
                      const SizedBox(width: 8),
                      // One flexible child, not two.
                      //
                      // This was `Flexible(FittedBox(…))` followed by `Spacer()`,
                      // and both of those are flex-1: the leftover width was split
                      // down the middle between the price and a gap, so the price
                      // and the button moved as the total got longer or shorter
                      // rather than staying put. At NT$0 — the shortest string
                      // there is — everything sat at its most lopsided.
                      //
                      // `scaleDown` rather than the default `contain`, so a long
                      // total is allowed to shrink but a short one is never blown
                      // up to fill the space it happens to have been given.
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(money.format(totals.total),
                                style: theme.textTheme.headlineSmall),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(_isEdit ? 'Save changes' : 'Add order'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one line the till needs when the connection goes: what still works.
///
/// The menu, the prices and the basket are all local, and since the offline
/// queue arrived so is the saving: `_queueOffline` puts a new order on the
/// device with the time it was rung up at, and `PendingOrderQueue` sends it
/// when the connection returns.
///
/// This text used to say the opposite — "keep taking the order, but it cannot
/// be saved" — which was true before the queue and was never updated when it
/// shipped. It was the one screen where the app told somebody a feature it has
/// does not exist, and it contradicted the store listing, which describes
/// offline ordering as a headline feature.
///
/// An **edit** still cannot be saved offline, and that part was and remains
/// true: an edit has to be applied against the order as it stands on the
/// server, which is exactly what cannot be read with no connection. Hence
/// [isEdit] — the two cases need opposite answers, and one line for both was
/// wrong for whichever it was not written for.
class _OfflineStrip extends StatelessWidget {
  const _OfflineStrip({required this.isEdit});

  final bool isEdit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: connectionStatus,
      builder: (context, offline, _) {
        if (!offline) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Material(
          color: scheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.cloud_off_rounded,
                    size: 18, color: scheme.onTertiaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isEdit
                        ? 'Offline — this order cannot be changed until the '
                            'connection is back. An edit has to be applied to '
                            'the order as it stands on the server.'
                        : 'Offline — carry on. The order is kept on this '
                            'device and sent when the connection is back, '
                            'keeping the time it was rung up at. Prices are '
                            'the last ones this device saw.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onTertiaryContainer),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
