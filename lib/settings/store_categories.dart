import 'package:flutter/material.dart';

import '../database/repositories.dart';
import '../models/store.dart';
import '../widgets/feedback.dart';

/// Menu categories — 主餐 / 小菜 / 飲料, or whatever this kitchen actually calls
/// its sections.
///
/// Registration no longer invents three for every new store, so this is where
/// they come from. They matter beyond tidiness: the category breakdown on the
/// analysis page ("drinks are 18% of revenue") is only as good as they are.
///
/// Stored inline on the store document rather than as a subcollection: there
/// are only ever a handful, and every screen that shows the menu needs all of
/// them at once.
class StoreCategories extends StatefulWidget {
  const StoreCategories(this.storeId, {super.key});

  final String storeId;

  @override
  State<StoreCategories> createState() => _StoreCategoriesState();
}

class _StoreCategoriesState extends State<StoreCategories> {
  List<StoreCategory> _categories = const [];

  /// How many dishes sit in each category, so one that is in use cannot be
  /// deleted out from under them.
  Map<String, int> _usage = const {};

  bool _loading = true;
  bool _saving = false;

  /// Owned here, not created inside [_openDialog]. Disposing a controller
  /// straight after `await showDialog` throws "A TextEditingController was used
  /// after being disposed" — the future completes as the exit transition
  /// starts, while the TextField is still mounted and still reading it.
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Reads the categories and counts what sits in each, so a category holding
  /// dishes can refuse to be deleted.
  ///
  /// `_loading` is cleared in both outcomes. Left only on the success path, a
  /// failed read held the screen on its spinner for good — and a spinner that
  /// never resolves is the one failure a person cannot even describe.
  Future<void> _load() async {
    try {
      final store = await storeRepository.fetch(widget.storeId);
      final items = await menuRepository.fetchAll(widget.storeId);

      final usage = <String, int>{};
      for (final item in items) {
        final id = item.categoryId;
        if (id != null) usage[id] = (usage[id] ?? 0) + 1;
      }

      if (!mounted) return;
      setState(() {
        _categories = [...?store?.categories]
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        _usage = usage;
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
        title: const Text('Menu Categories'),
        bottom: _saving
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : () => _openDialog(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _categories.isEmpty
              ? const _EmptyState()
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 0, 88),
                  itemCount: _categories.length,
                  itemBuilder: (context, index) => _tile(_categories[index]),
                  onReorderItem: (oldIndex, newIndex) {
                    final reordered = [..._categories];
                    reordered.insert(newIndex, reordered.removeAt(oldIndex));
                    _persist(reordered);
                  },
                ),
    );
  }

  Widget _tile(StoreCategory category) {
    final count = _usage[category.id] ?? 0;
    return ListTile(
      key: ValueKey(category.id),
      leading: Icon(Icons.drag_indicator,
          color: Theme.of(context).colorScheme.outlineVariant),
      title: Text(category.name),
      subtitle: Text(count == 0
          ? 'No dishes'
          : '$count ${count == 1 ? 'dish' : 'dishes'}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _openDialog(existing: category),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outlined),
            onPressed: () => _delete(category),
          ),
        ],
      ),
    );
  }

  Future<void> _openDialog({StoreCategory? existing}) async {
    _nameController.text = existing?.name ?? '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add Category' : 'Rename Category'),
        content: TextField(
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Category name'),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final updated = [..._categories];
    if (existing == null) {
      updated.add(StoreCategory(
        // Derived from the position, not the name: a category that gets
        // renamed must keep its id, or every dish in it comes loose.
        id: 'cat_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        sortOrder: updated.length,
      ));
    } else {
      final index = updated.indexWhere((c) => c.id == existing.id);
      if (index < 0) return;
      updated[index] = StoreCategory(
        id: existing.id,
        name: name,
        sortOrder: existing.sortOrder,
      );
    }
    await _persist(updated);
  }

  Future<void> _delete(StoreCategory category) async {
    final count = _usage[category.id] ?? 0;
    if (count > 0) {
      _snack(
        'Move the $count ${count == 1 ? 'dish' : 'dishes'} in '
        '${category.name} to another category first.',
        isError: true,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${category.name}?'),
        content: const Text('It has no dishes in it, so nothing else changes.'),
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

    await _persist(_categories.where((c) => c.id != category.id).toList());
  }

  /// Writes the whole list back, renumbering `sortOrder` from its position.
  /// The array is the unit of storage here, so there is nothing finer to
  /// update, and renumbering on every write keeps the values consecutive.
  Future<void> _persist(List<StoreCategory> categories) async {
    final numbered = [
      for (var i = 0; i < categories.length; i++)
        StoreCategory(
          id: categories[i].id,
          name: categories[i].name,
          sortOrder: i,
        ),
    ];

    setState(() {
      _categories = numbered;
      _saving = true;
    });

    try {
      await storeRepository.updateCategories(widget.storeId, numbered);
    } catch (e) {
      // Put back what the store actually holds rather than leaving the screen
      // showing an edit that never landed. `_load` reports its own failures,
      // so a reload that also fails does not swallow this one.
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.category_outlined,
                size: 40, color: Theme.of(context).disabledColor),
            const SizedBox(height: 12),
            const Text(
              'No categories yet',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Dishes work without them, but grouping the menu is what makes '
              '"drinks are 18% of revenue" a question the analysis page can '
              'answer.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}
