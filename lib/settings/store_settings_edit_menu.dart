import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_iconpicker/Models/configuration.dart';
import 'package:flutter_iconpicker/flutter_iconpicker.dart';

import '../database/repositories.dart';
import '../models/menu_item.dart';
import '../models/store.dart';
import '../widgets/feedback.dart';
import '../widgets/money.dart';
import 'store_categories.dart';
import 'store_settings_import_menu.dart';

class StoreEditMenu extends StatefulWidget {
  final String storeID;

  const StoreEditMenu(this.storeID, {super.key});

  @override
  State<StoreEditMenu> createState() => _StoreEditMenuState();
}

class _StoreEditMenuState extends State<StoreEditMenu> {
  /// Retired dishes are hidden by default but never deleted, so they can be
  /// brought back without breaking the orders that reference them.
  bool _showRetired = false;

  /// Narrows the list to the dishes with no cost on file.
  ///
  /// Every report under Insights is built on `cost`: with it blank a dish
  /// cannot be placed on the menu matrix, and the food-cost rate silently
  /// omits it. Insights can now say so, but it could only send someone here to
  /// a full menu with no indication of which rows were the problem.
  bool _onlyUncosted = false;

  /// Free-text filter over dish names.
  ///
  /// A menu is a long reorderable list, and finding one dish to reprice meant
  /// reading it. Kept in the State rather than in the controller alone so the
  /// list rebuilds as it is typed.
  String _query = '';
  final _searchController = TextEditingController();

  Store? _store;

  List<StoreCategory> get _categories => _store?.categories ?? const [];

  // Owned by this State rather than created inside _openDialog. Disposing a
  // controller straight after `await showDialog` throws "A
  // TextEditingController was used after being disposed": the future completes
  // when the route is popped, which is the start of the exit transition, and
  // the TextField is still mounted and still reading it. That is what made
  // Cancel crash.
  final nameController = TextEditingController();
  final priceController = TextEditingController();
  final costController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    nameController.dispose();
    priceController.dispose();
    costController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Reloads on the way back: the dish dialog's category dropdown is built
  /// from this list, and an edit made next door has to show up here.
  Future<void> _openCategories() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StoreCategories(widget.storeID)),
    );
    await _loadCategories();
  }

  /// Imported dishes land in the same subcollection this screen already
  /// watches, so the list updates itself. Only the categories need reloading —
  /// an import may have created some, and the dish dialog's dropdown is built
  /// from that list.
  Future<void> _importFromPhoto() async {
    final added = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => StoreImportMenu(widget.storeID)),
    );
    await _loadCategories();
    if (added != null && added > 0) {
      _snack(added == 1 ? '1 dish added' : '$added dishes added');
    }
  }

  /// Failure here is not fatal to the screen — the dish list comes from its own
  /// stream and still works — but it must be said, because the only visible
  /// symptom is a category dropdown that is silently empty, which reads as
  /// "this store has no categories" rather than as "they could not be read".
  Future<void> _loadCategories() async {
    try {
      final store = await storeRepository.fetch(widget.storeID);
      if (mounted) setState(() => _store = store);
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Menu'),
        actions: [
          IconButton(
            tooltip: 'Import from a photo',
            icon: const Icon(Icons.document_scanner_outlined),
            onPressed: _importFromPhoto,
          ),
          IconButton(
            tooltip: 'Menu categories',
            icon: const Icon(Icons.category_outlined),
            onPressed: _openCategories,
          ),
          IconButton(
            tooltip: _showRetired ? 'Hide retired dishes' : 'Show retired dishes',
            icon: Icon(_showRetired
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
            onPressed: () => setState(() => _showRetired = !_showRetired),
          ),
        ],
      ),
      body: StreamBuilder<List<MenuItem>>(
        stream: menuRepository.watchAll(widget.storeID),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorView(snapshot.error!);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = snapshot.data!;
          var visible =
              _showRetired ? all : all.where((i) => i.isActive).toList();

          if (_query.isNotEmpty) {
            final needle = _query.toLowerCase();
            visible = visible
                .where((i) => i.name.toLowerCase().contains(needle))
                .toList();
          }

          // Counted over the active menu whatever the filters are showing:
          // this is a statement about the shop, not about the current view.
          final uncosted =
              all.where((i) => i.isActive && i.cost <= 0).toList();
          if (_onlyUncosted) {
            visible = visible.where((i) => i.cost <= 0).toList();
          }

          if (visible.isEmpty && _query.isNotEmpty) {
            return Column(
              children: [
                _buildSearchField(),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('No dish matches “$_query”.'),
                    ),
                  ),
                ),
              ],
            );
          }

          if (visible.isEmpty && !_onlyUncosted) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No dishes yet. Tap + to add one.\n\n'
                  'A new store starts with an empty menu on purpose — a '
                  'starter menu that looks real is a sale waiting to be rung '
                  'up against a dish this kitchen has never sold.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // Dragging inside a filtered view would write an order derived
          // from a subset back over the whole menu, so while a filter is on
          // the list is a plain one.
          final filtered = _query.isNotEmpty || _onlyUncosted;
          final list = filtered
              ? ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 0, 88),
                  itemBuilder: (context, index) =>
                      _buildMenuTile(visible[index]),
                  itemCount: visible.length,
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 0, 88),
                  itemBuilder: (context, index) =>
                      _buildMenuTile(visible[index]),
                  itemCount: visible.length,
                  // onReorderItem hands back an index already adjusted for the
                  // removal, unlike the deprecated onReorder.
                  onReorderItem: (oldIndex, newIndex) {
                    final reordered = [...visible];
                    reordered.insert(newIndex, reordered.removeAt(oldIndex));
                    menuRepository.reorder(widget.storeID, reordered);
                  },
                );

          return Column(
            children: [
              _buildSearchField(),
              if (uncosted.isNotEmpty) _buildUncostedBanner(uncosted.length),
              Expanded(
                child: visible.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('Every dish shown has a cost on it.'),
                        ),
                      )
                    : list,
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSearchField() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value.trim()),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search dishes',
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

  /// Says how many dishes are missing a cost, and filters down to them.
  Widget _buildUncostedBanner(int count) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: _onlyUncosted ? scheme.secondaryContainer : scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => setState(() => _onlyUncosted = !_onlyUncosted),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(Icons.savings_outlined, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count ${count == 1 ? 'dish has' : 'dishes have'} no '
                      'cost recorded',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      _onlyUncosted
                          ? 'Showing only those. Tap to show everything.'
                          : 'Insights cannot tell you what they earn. Tap to '
                              'show just them.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(_onlyUncosted ? Icons.filter_alt : Icons.filter_alt_outlined,
                  color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuTile(MenuItem item) {
    final money = moneyFormat(_store);
    final subtitle = StringBuffer(money.format(item.price));
    if (item.cost > 0) {
      final margin = ((item.marginRate ?? 0) * 100).round();
      subtitle.write('  ·  cost ${money.format(item.cost)}  ·  '
          'margin $margin%');
    } else {
      subtitle.write('  ·  cost not set');
    }
    final categoryName = _categoryName(item.categoryId);
    if (categoryName != null) subtitle.write('  ·  $categoryName');

    return ListTile(
      key: ValueKey(item.id),
      enabled: item.isActive,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          Icon(Icons.drag_indicator,
              color: Theme.of(context).colorScheme.outlineVariant),
          Icon(item.iconData),
        ],
      ),
      title: Text(
        item.isActive ? item.name : '${item.name}  (retired)',
        style: item.isActive
            ? null
            : const TextStyle(decoration: TextDecoration.lineThrough),
      ),
      subtitle: Text(subtitle.toString()),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => _openDialog(existing: item),
            icon: const Icon(Icons.edit_outlined),
          ),
          if (item.isActive)
            IconButton(
              tooltip: 'Retire dish',
              onPressed: () => _retireItem(item),
              icon: const Icon(Icons.delete_outlined),
            )
          else
            IconButton(
              tooltip: 'Put back on the menu',
              onPressed: () => _restoreItem(item),
              icon: const Icon(Icons.restore_from_trash_outlined),
            ),
        ],
      ),
    );
  }

  String? _categoryName(String? categoryId) {
    if (categoryId == null) return null;
    for (final c in _categories) {
      if (c.id == categoryId) return c.name;
    }
    return null;
  }

  Future<void> _retireItem(MenuItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Retire ${item.name}?'),
        content: const Text(
          'It comes off the order screen but stays in your sales history, so '
          'past reports keep working. You can put it back any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retire'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await menuRepository.deactivate(widget.storeID, item.id);
      _snack('${item.name} retired');
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  Future<void> _restoreItem(MenuItem item) async {
    try {
      await menuRepository.reactivate(widget.storeID, item.id);
      _snack('${item.name} is back on the menu');
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  Future<void> _openDialog({MenuItem? existing}) async {
    final isEdit = existing != null;
    // Reset rather than recreate — the same three controllers serve every
    // dish, so each opening has to clear what the last one left behind.
    nameController.text = existing?.name ?? '';
    priceController.text = isEdit ? existing.price.toString() : '';
    costController.text =
        isEdit && existing.cost > 0 ? existing.cost.toString() : '';
    var iconCodePoint = existing?.icon ?? MenuItem.defaultIconCodePoint;
    var categoryId = existing?.categoryId ??
        (_categories.isNotEmpty ? _categories.first.id : null);

    Future<void> pickIcon(StateSetter setStateDialog) async {
      final icon = await showIconPicker(
        context,
        configuration: SinglePickerConfiguration(
          iconPackModes: const [IconPack.material],
          searchComparator: (String search, IconPickerIcon icon) =>
              search
                  .toLowerCase()
                  .contains(icon.name.replaceAll('_', ' ').toLowerCase()) ||
              icon.name.toLowerCase().contains(search.toLowerCase()),
        ),
      );
      if (icon != null) {
        setStateDialog(() => iconCodePoint = icon.data.codePoint.toString());
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(isEdit ? 'Edit Dish' : 'Add Dish'),
          content: SingleChildScrollView(
            child: Column(
              spacing: 8,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Dish Icon'),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        IconData(int.tryParse(iconCodePoint) ?? 0xe56c,
                            fontFamily: 'MaterialIcons'),
                        key: ValueKey(iconCodePoint),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => pickIcon(setStateDialog),
                      child: const Icon(Icons.edit),
                    ),
                  ],
                ),
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Dish Name'),
                  controller: nameController,
                  textInputAction: TextInputAction.next,
                ),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Price (NTD)',
                  ),
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  textInputAction: TextInputAction.next,
                ),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Ingredient cost (NTD)',
                    helperText: 'Optional — unlocks margin and menu analysis',
                    helperMaxLines: 2,
                  ),
                  controller: costController,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  textInputAction: TextInputAction.done,
                ),
                if (_categories.isEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context, false);
                        _openCategories();
                      },
                      icon: const Icon(Icons.category_outlined, size: 18),
                      label: const Text('Set up categories'),
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: categoryId,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: _categories
                        .map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setStateDialog(() => categoryId = value),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final price = int.tryParse(priceController.text);
                if (nameController.text.trim().isEmpty || price == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Enter a name and a numeric price'),
                  ));
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;

    final price = int.parse(priceController.text);
    final cost = int.tryParse(costController.text) ?? 0;

    // The confirmation must depend on the write having happened. Unguarded,
    // a rejected write threw past this method and the screen said nothing at
    // all — no error, no "Dish added" — and the dish list, which is a live
    // query, simply never showed the dish. That reads as the app ignoring the
    // Save button rather than as a failure worth retrying.
    try {
      if (isEdit) {
        await menuRepository.update(
          widget.storeID,
          existing.copyWith(
            name: nameController.text.trim(),
            price: price,
            cost: cost,
            icon: iconCodePoint,
            categoryId: categoryId,
          ),
          previous: existing,
          by: currentActor(),
        );
      } else {
        await menuRepository.add(
          widget.storeID,
          MenuItem(
            id: '',
            name: nameController.text.trim(),
            price: price,
            cost: cost,
            icon: iconCodePoint,
            categoryId: categoryId,
            sortOrder: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ),
        );
      }
      _snack(isEdit ? 'Dish updated' : 'Dish added');
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
