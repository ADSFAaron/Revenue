import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/repositories.dart';
import '../models/store.dart';
import '../widgets/empty_state.dart';
import '../widgets/feedback.dart';
import '../widgets/money.dart';
import '../widgets/page_body.dart';

/// The delivery platforms this shop sells through, and what each one keeps.
///
/// The model, the till's platform picker and the commission arithmetic have all
/// been here since orders had channels — with no way to enter a platform, so
/// the picker was permanently empty and every delivery order was booked at zero
/// commission. Delivery revenue then read as the most profitable channel in the
/// shop, which is the exact opposite of the truth: a third of it never arrives.
///
/// The rate is stored as a fraction (0.3), entered as a percentage (30), the
/// same way tax is.
class StoreDeliveryPlatforms extends StatefulWidget {
  const StoreDeliveryPlatforms(this.storeId, {super.key});

  final String storeId;

  @override
  State<StoreDeliveryPlatforms> createState() => _StoreDeliveryPlatformsState();
}

class _StoreDeliveryPlatformsState extends State<StoreDeliveryPlatforms> {
  List<DeliveryPlatform> _platforms = const [];
  bool _loading = true;
  bool _saving = false;

  /// Owned by this State, not by the dialog: disposing a controller straight
  /// after `await showDialog` throws "used after being disposed", because the
  /// future completes as the exit transition starts.
  final _nameController = TextEditingController();
  final _rateController = TextEditingController();

  /// Whether this account may change any of this.
  ///
  /// What each platform keeps is worth knowing on a shift — it is the
  /// difference between a delivery order's takings and what the shop
  /// actually earns — so the page opens for everyone and only its controls
  /// are a manager's.
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
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final store = await storeRepository.fetch(widget.storeId);
      if (!mounted) return;
      setState(() {
        _platforms = [...?store?.deliveryPlatforms];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Platforms'),
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
          : _platforms.isEmpty
              ? const EmptyState(
                  icon: Icons.delivery_dining_outlined,
                  title: 'No delivery platforms yet',
                  body: 'Add the ones this shop sells through, with the cut '
                      'each takes. Without the commission, a delivery order '
                      'reads as pure revenue and the gross profit on the '
                      'reports is wrong by whatever the platform kept.',
                )
              : ReadingWidth(
                  builder: (context, insets) => ListView(
                    padding: insets + const EdgeInsets.fromLTRB(16, 8, 16, 88),
                    children: _platforms.map(_tile).toList(),
                  ),
                ),
    );
  }

  Widget _tile(DeliveryPlatform platform) {
    return ListTile(
      key: ValueKey(platform.id),
      leading: const Icon(Icons.storefront_outlined),
      title: Text(platform.name),
      subtitle: Text(platform.commissionRate <= 0
          // Zero is a real answer — an own-fleet platform takes nothing — but
          // it is also what an unfilled field looks like, so it says so.
          ? 'No commission'
          : 'Keeps ${formatTaxPercent(platform.commissionRate)}% of the order'),
      trailing: _isManager
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _openDialog(existing: platform),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outlined),
                  onPressed: () => _delete(platform),
                ),
              ],
            )
          : null,
    );
  }

  Future<void> _openDialog({DeliveryPlatform? existing}) async {
    _nameController.text = existing?.name ?? '';
    _rateController.text =
        existing == null ? '' : formatTaxPercent(existing.commissionRate);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add a platform' : 'Edit platform'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'UberEats, foodpanda, own delivery…',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _rateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              // Digits and one point: a 32.5% commission has to be typeable.
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Commission (%)',
                hintText: '30',
                helperText: 'What the platform keeps. 0 if it keeps nothing.',
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => Navigator.pop(context, true),
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
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _snack('A platform needs a name.', isError: true);
      return;
    }
    final text = _rateController.text.trim();
    final rate = text.isEmpty ? 0.0 : parseTaxPercent(text);
    if (rate == null) {
      _snack('Commission has to be a number between 0 and 100.', isError: true);
      return;
    }

    final updated = [..._platforms];
    if (existing == null) {
      updated.add(DeliveryPlatform(
        // Generated, never derived from the name: past orders point at this id
        // and a rename must not orphan them.
        id: 'plat_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        commissionRate: rate,
      ));
    } else {
      final index = updated.indexWhere((p) => p.id == existing.id);
      if (index < 0) return;
      updated[index] = DeliveryPlatform(
        id: existing.id,
        name: name,
        commissionRate: rate,
      );
    }
    await _persist(updated);
  }

  Future<void> _delete(DeliveryPlatform platform) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${platform.name}?'),
        content: const Text(
          'Orders already taken through it keep their platform and the '
          'commission that was charged at the time. It just stops being '
          'offered at the till.',
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

    await _persist(_platforms.where((p) => p.id != platform.id).toList());
  }

  Future<void> _persist(List<DeliveryPlatform> platforms) async {
    setState(() {
      _platforms = platforms;
      _saving = true;
    });

    try {
      await storeRepository.updateDeliveryPlatforms(widget.storeId, platforms);
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
