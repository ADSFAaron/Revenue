import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class StoreEditMenu extends StatefulWidget {
  final String storeID; // 加上 final，保持不可變
  const StoreEditMenu(this.storeID, {super.key});

  @override
  State<StoreEditMenu> createState() => _StoreEditMenuState();
}

class _StoreEditMenuState extends State<StoreEditMenu> {
  late TextEditingController dishNameController, dishPriceController;
  List<dynamic> menu = []; // 本地菜單列表

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
    final item = menu[index];
    return ListTile(
      key: ValueKey(index),
      leading: const Icon(Icons.restaurant),
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
    } else {
      dishNameController.clear();
      dishPriceController.clear();
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? 'Edit Dish' : 'Add Dish'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Dish Name'),
              controller: dishNameController,
            ),
            TextField(
              decoration: const InputDecoration(labelText: 'Dish Price'),
              controller: dishPriceController,
              keyboardType: TextInputType.number,
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
              };

              setState(() {
                if (isEdit && index != null) {
                  menu[index] = newDish;
                } else {
                  menu.add(newDish);
                }
                updateMenuToFirestore();
              });

              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(isEdit ? 'Dish Edited' : 'Dish Added'),
              ));
            },
            child: const Text('Save'),
          ),
        ],
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
    FirebaseFirestore.instance
        .collection('store')
        .doc(widget.storeID)
        .update({'menu': menu});
  }
}
