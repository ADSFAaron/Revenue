import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_iconpicker/Models/configuration.dart';
import 'package:flutter_iconpicker/flutter_iconpicker.dart';

import '../database/repositories.dart';
import '../models/menu_item.dart';
import '../models/store.dart';

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

  List<StoreCategory> _categories = const [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final store = await storeRepository.fetch(widget.storeID);
    if (mounted) setState(() => _categories = store?.categories ?? const []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Menu'),
        actions: [
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
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = snapshot.data!;
          final visible =
              _showRetired ? all : all.where((i) => i.isActive).toList();

          if (visible.isEmpty) {
            return const Center(
              child: Text('No dishes yet. Tap + to add one.'),
            );
          }

          return ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 0, 88),
            itemBuilder: (context, index) => _buildMenuTile(visible[index]),
            itemCount: visible.length,
            // onReorderItem hands back an index already adjusted for the
            // removal, unlike the deprecated onReorder.
            onReorderItem: (oldIndex, newIndex) {
              final reordered = [...visible];
              reordered.insert(newIndex, reordered.removeAt(oldIndex));
              menuRepository.reorder(widget.storeID, reordered);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildMenuTile(MenuItem item) {
    final subtitle = StringBuffer('NTD ${item.price}');
    if (item.cost > 0) {
      final margin = ((item.marginRate ?? 0) * 100).round();
      subtitle.write('  ·  cost ${item.cost}  ·  margin $margin%');
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
          const Icon(Icons.drag_indicator, color: Colors.black26),
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

    await menuRepository.deactivate(widget.storeID, item.id);
    _snack('${item.name} retired');
  }

  Future<void> _restoreItem(MenuItem item) async {
    await menuRepository.reactivate(widget.storeID, item.id);
    _snack('${item.name} is back on the menu');
  }

  Future<void> _openDialog({MenuItem? existing}) async {
    final isEdit = existing != null;
    final nameController = TextEditingController(text: existing?.name ?? '');
    final priceController =
        TextEditingController(text: isEdit ? existing.price.toString() : '');
    final costController = TextEditingController(
        text: isEdit && existing.cost > 0 ? existing.cost.toString() : '');
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
                if (_categories.isNotEmpty)
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

    if (saved == true) {
      final price = int.parse(priceController.text);
      final cost = int.tryParse(costController.text) ?? 0;

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
    }

    nameController.dispose();
    priceController.dispose();
    costController.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
