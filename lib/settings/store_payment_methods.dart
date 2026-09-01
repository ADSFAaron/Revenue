import 'package:flutter/material.dart';

import '../database/repositories.dart';
import '../models/store.dart';
import '../widgets/feedback.dart';
import '../widgets/page_body.dart';
import '../widgets/payment_icons.dart';

/// The ways this shop takes money — 現金, 信用卡, LINE Pay, 街口, 悠遊卡, 掛帳.
///
/// These used to be an `enum` in the source: four options chosen by whoever
/// wrote the till screen, with everything else filed under "Other". A shop that
/// takes three mobile wallets could not tell them apart in the payment
/// breakdown, and a shop that takes none had a till offering two buttons it
/// would never press.
///
/// Renaming a method keeps its id, so its history stays with it. Deleting one
/// leaves past orders alone: they keep the id, and every screen resolves an
/// unknown id back to its own name rather than silently rewriting it to cash.
class StorePaymentMethods extends StatefulWidget {
  const StorePaymentMethods(this.storeId, {super.key});

  final String storeId;

  @override
  State<StorePaymentMethods> createState() => _StorePaymentMethodsState();
}

class _StorePaymentMethodsState extends State<StorePaymentMethods> {
  List<StorePaymentMethod> _methods = const [];
  bool _loading = true;
  bool _saving = false;

  /// Owned by this State, not created inside the dialog: disposing a controller
  /// straight after `await showDialog` throws "used after being disposed",
  /// because the future completes as the exit transition starts while the
  /// field is still mounted.
  final _nameController = TextEditingController();

  /// Whether this account may change any of this.
  ///
  /// The list is worth reading on a shift — which methods the till offers,
  /// and which one an order starts on — so a store assistant gets the page
  /// without the controls rather than a closed door. `firestore.rules`
  /// refuses the write either way; this is so nobody finds that out by
  /// tapping.
  bool _isManager = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadRole();
  }

  /// Resolved once on the way in. A failed lookup leaves this false, which is
  /// the safe way round: the page renders read-only rather than offering an
  /// edit the rules would refuse anyway.
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
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final store = await storeRepository.fetch(widget.storeId);
      if (!mounted) return;
      setState(() {
        _methods = store?.paymentMethods ?? kDefaultPaymentMethods;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Cleared on both paths: left only on success, a failed read holds the
      // screen on a spinner that never resolves.
      setState(() => _loading = false);
      showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Methods'),
        bottom: _saving
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      floatingActionButton: _isManager
          ? FloatingActionButton(
              onPressed: _loading ? null : () => _openDialog(),
              child: const Icon(Icons.add),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ReadingWidth(
              builder: (context, insets) => ReorderableListView.builder(
                // Without this the rows still answer a long press with a
                // drag that ends in a refused write.
                buildDefaultDragHandles: _isManager,
                padding: insets + const EdgeInsets.fromLTRB(16, 8, 0, 88),
                header: const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    'The till offers these in this order, and the first one is '
                    'what a new order starts on. Reports break the takings '
                    'down by them.',
                  ),
                ),
                itemCount: _methods.length,
                itemBuilder: (context, index) => _tile(_methods[index]),
                onReorderItem: (oldIndex, newIndex) {
                  final reordered = [..._methods];
                  reordered.insert(newIndex, reordered.removeAt(oldIndex));
                  _persist(reordered);
                },
              ),
            ),
    );
  }

  Widget _tile(StorePaymentMethod method) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      key: ValueKey(method.id),
      leading: _isManager
          ? Icon(Icons.drag_indicator, color: scheme.onSurfaceVariant)
          : Icon(paymentIconData(method.iconKey), size: 20),
      title: _isManager
          ? Row(
              children: [
                Icon(paymentIconData(method.iconKey), size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(method.name)),
              ],
            )
          // The icon has moved into the leading slot the drag handle vacated,
          // so it is not shown twice.
          : Text(method.name),
      subtitle: method.id == _methods.first.id
          ? const Text('Selected by default at the till')
          : null,
      trailing: _isManager
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _openDialog(existing: method),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outlined),
                  onPressed: () => _delete(method),
                ),
              ],
            )
          : null,
    );
  }

  Future<void> _openDialog({StorePaymentMethod? existing}) async {
    _nameController.text = existing?.name ?? '';
    var iconKey = existing?.iconKey ?? kDefaultPaymentIcon.key;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(existing == null ? 'Add a method' : 'Edit method'),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filledTonal(
                tooltip: 'Pick an icon',
                icon: Icon(paymentIconData(iconKey)),
                onPressed: () async {
                  final picked =
                      await pickPaymentIcon(context, selected: iconKey);
                  if (picked != null) {
                    setStateDialog(() => iconKey = picked.key);
                  }
                },
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _nameController,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'LINE Pay, 街口, on account…',
                  ),
                  onSubmitted: (_) => Navigator.pop(context, true),
                ),
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
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _snack('A payment method needs a name.', isError: true);
      return;
    }

    final updated = [..._methods];
    if (existing == null) {
      updated.add(StorePaymentMethod(
        // Generated, never derived from the name: the id is what past orders
        // and every `byPayment` bucket are keyed by, so a rename must not
        // move the money into a new column.
        id: 'pay_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        iconKey: iconKey,
        sortOrder: updated.length,
      ));
    } else {
      final index = updated.indexWhere((m) => m.id == existing.id);
      if (index < 0) return;
      updated[index] = existing.copyWith(name: name, iconKey: iconKey);
    }
    await _persist(updated);
  }

  Future<void> _delete(StorePaymentMethod method) async {
    if (_methods.length <= 1) {
      _snack('A till needs at least one way to take money.', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${method.name}?'),
        content: const Text(
          'Orders already taken this way keep it — they still read as this '
          'method in history and in the payment breakdown. It just stops '
          'being offered at the till.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          DestructiveButton(
            label: 'Delete',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _persist(_methods.where((m) => m.id != method.id).toList());
  }

  /// Writes the whole list back, renumbering `sortOrder` from position — the
  /// array is the unit of storage, so there is nothing finer to update.
  Future<void> _persist(List<StorePaymentMethod> methods) async {
    final numbered = [
      for (var i = 0; i < methods.length; i++)
        methods[i].copyWith(sortOrder: i),
    ];

    setState(() {
      _methods = numbered;
      _saving = true;
    });

    try {
      await storeRepository.updatePaymentMethods(widget.storeId, numbered);
    } catch (e) {
      // Put back what the store actually holds rather than leaving an edit on
      // screen that never landed.
      await _load();
      _snack(describeFailure(e).message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    showSnack(context, message, isError: isError);
  }
}
