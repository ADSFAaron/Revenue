import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_iconpicker/Models/configuration.dart';
import 'package:flutter_iconpicker/flutter_iconpicker.dart';

class StoreEditMenu extends StatefulWidget {
  final String storeID; // 加上 final，保持不可變
  const StoreEditMenu(this.storeID, {super.key});

  @override
  State<StoreEditMenu> createState() => _StoreEditMenuState();
}

class _StoreEditMenuState extends State<StoreEditMenu> {
  late TextEditingController dishNameController, dishPriceController;
  List<dynamic> menu = []; // 本地菜單列表
  Icon? _selectedIcon;

  @override
  void initState() {
    super.initState();
    dishNameController = TextEditingController();
    dishPriceController = TextEditingController();
  }

  @override
  void dispose() {
    dishNameController.dispose();
    dishPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Menu'),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('store')
            .doc(widget.storeID)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // 更新本地菜單
          final data = snapshot.data?.data() as Map<String, dynamic>?;
          if (data != null && data.containsKey('menu')) {
            menu = List.from(data['menu']);
          }

          return ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 0, 8),
            itemBuilder: (context, index) => buildMenuTile(index),
            itemCount: menu.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = menu.removeAt(oldIndex);
                menu.insert(newIndex, item);
                updateMenuToFirestore();
              });
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => openDialog(isEdit: false),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget buildMenuTile(int index) {
    print('menu: $menu');
    // Get the icon data from the menu list
    IconData? dishIcon = IconData(int.parse(menu[index]['icon'] ?? '0xe043'), fontFamily: 'MaterialIcons');
    final item = menu[index];
    return ListTile(
      key: ValueKey(index),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [const Icon(Icons.drag_indicator, color: Colors.black26,), Icon(dishIcon)],
      ),
      // Connect to Firebase
      title: Text(item['name']),
      subtitle: Text("NTD ${item['price']}"),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => openDialog(isEdit: true, index: index),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            onPressed: () => removeMenuItem(index),
            icon: const Icon(Icons.delete_outlined),
          ),
        ],
      ),
    );
  }

  Future<void> openDialog({required bool isEdit, int? index}) async {
    if (isEdit && index != null) {
      final item = menu[index];
      dishNameController.text = item['name'];
      dishPriceController.text = item['price'].toString();
      _selectedIcon = Icon(IconData(int.parse(item['icon'] ?? '0xe043'), fontFamily: 'MaterialIcons'));
    } else {
      dishNameController.clear();
      dishPriceController.clear();
      _selectedIcon = const Icon(Icons.restaurant); // Default icon for new dishes
    }

    Future<void> pickIcon(StateSetter setStateDialog) async {
      IconPickerIcon? icon = await showIconPicker(
        context,
        configuration: SinglePickerConfiguration(
          iconPackModes: [IconPack.material],
          searchComparator: (String search, IconPickerIcon icon) =>
              search
                  .toLowerCase()
                  .contains(icon.name.replaceAll('_', ' ').toLowerCase()) ||
              icon.name.toLowerCase().contains(search.toLowerCase()),
        ),
      );

      setStateDialog(() {
        _selectedIcon = Icon(icon?.data);
      });

      debugPrint('Picked Icon:  $icon');
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(isEdit ? 'Edit Dish' : 'Add Dish'),
          content: Column(
            spacing: 8,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Dish Icon'),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _selectedIcon, // Use _selectedIcon here
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
                controller: dishNameController,
                textInputAction: TextInputAction.next,
              ),
              TextField(
                decoration: const InputDecoration(labelText: 'Dish Price'),
                controller: dishPriceController,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly
                ],
                // Only numbers can be entered
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (dishNameController.text.isEmpty ||
                    dishPriceController.text.isEmpty ||
                    int.tryParse(dishPriceController.text) == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Invalid input!'),
                  ));
                  return;
                }

                final newDish = {
                  'name': dishNameController.text,
                  'price': int.parse(dishPriceController.text),
                  'icon': _selectedIcon?.icon?.codePoint.toString(), // Save the selected icon
                };

                setState(() {
                  if (isEdit && index != null) {
                    menu[index] = newDish;
                  } else {
                    menu.add(newDish);
                  }

                  debugPrint('Menu: $menu');
                  updateMenuToFirestore();
                });

                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isEdit ? 'Dish Edited' : 'Dish Added'),
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void removeMenuItem(int index) {
    setState(() {
      menu.removeAt(index);
      updateMenuToFirestore();
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Dish Removed'),
    ));
  }

  void updateMenuToFirestore() {
    print('Updating menu to Firestore');
    print('Menu: $menu');

    FirebaseFirestore.instance
        .collection('store')
        .doc(widget.storeID)
        .update({'menu': menu})
        .then((value) => print('Menu updated successfully'))
        .catchError((error) => print('Failed to update menu: $error'));
  }
}
