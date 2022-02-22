import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class StoreEditMenu extends StatefulWidget {
  String storeID;
  StoreEditMenu(this.storeID, {Key? key}) : super(key: key);

  @override
  State<StoreEditMenu> createState() => _StoreEditMenuState();
}

class _StoreEditMenuState extends State<StoreEditMenu> {
  late Map<String, dynamic> stores;
  late TextEditingController dishNameController, dishPriceController;

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
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('store')
            .where(widget.storeID)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(),
            );
          }

          snapshot.data!.docs.forEach((DocumentSnapshot document) {
            stores = document.data() as Map<String, dynamic>;
          });

          print(stores['menu']);

          return SafeArea(
            child: ReorderableListView.builder(
              itemBuilder: (context, index) => ListTile(
                key: ValueKey(index),
                title: Text(stores['menu'][index]['name']),
                subtitle:
                    Text("NTD " + stores['menu'][index]['price'].toString()),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.delete_outlined),
                    ),
                  ],
                ),
              ),
              itemCount: stores['menu'].length,
              onReorder: (oldIndex, newIndex) => setState(
                () {},
              ),
            ),
          );
        },
      ),
      floatingActionButton: _floatAddButton(context),
    );
  }

  Widget _floatAddButton(BuildContext context) {
    return FloatingActionButton(
      onPressed: () {
        openDialog();
        final snackBar = SnackBar(
          content: Text('Update Successful!'),
          action: SnackBarAction(
            label: 'OK',
            onPressed: () {
              // Some code to undo the change.
            },
          ),
        );

        // Show SnackBar.
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      },
      child: const Icon(Icons.add),
    );
  }

  Future<Map<String, int>?> openDialog() => showDialog<Map<String, int>>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Menu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(hintText: 'Dishes name'),
                controller: dishNameController,
              ),
              TextField(
                decoration: InputDecoration(hintText: 'Dishes price'),
                controller: dishPriceController,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () {
                  Navigator.of(context).pop({
                    dishNameController.text,
                    int.parse(dishPriceController.text)
                  });
                },
                child: Text('Cancel')),
            TextButton(onPressed: () {}, child: Text('Save')),
          ],
        ),
      );
}
