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
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('store')
            .doc(widget.storeID)
            .snapshots(),
        builder:
            (BuildContext context, AsyncSnapshot<DocumentSnapshot> snapshot) {
          if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(),
            );
          }

          stores = snapshot.data?.data() as Map<String, dynamic>;

          print(stores['menu']);

          return SafeArea(
            child: ReorderableListView.builder(
              itemBuilder: (context, index) => ListTile(
                leading: Icon(Icons.restaurant),
                key: ValueKey(index),
                title: Text(stores['menu'][index]['name']),
                subtitle:
                    Text("NTD " + stores['menu'][index]['price'].toString()),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {
                        edit(index);
                      },
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      onPressed: () {
                        remove(index);
                      },
                      icon: const Icon(Icons.delete_outlined),
                    ),
                  ],
                ),
              ),
              itemCount: stores['menu'].length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex >= stores['menu'].length) {
                  newIndex = stores['menu'].length - 1;
                }

                print(newIndex.toString() + "  " + oldIndex.toString());

                setState(
                  () {
                    var tmp = stores['menu'][oldIndex];
                    stores['menu'][oldIndex] = stores['menu'][newIndex];
                    stores['menu'][newIndex] = tmp;

                    updateMenuToFirestore();
                  },
                );
              },
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
        Map<String, dynamic> result = {};

        openDialog(result);
        // print(result);
        result = {};
      },
      child: const Icon(Icons.add),
    );
  }

  Future<Map<String, dynamic>?> openDialog(Map<String, dynamic> result) =>
      showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Add Menu'),
          content: popupContent(),
          actions: popupNewAction(context),
        ),
      );

  List<Widget> popupNewAction(BuildContext context) {
    Map<String, dynamic> result = {};
    return [
      TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text('Cancel')),
      TextButton(
          onPressed: () {
            result['name'] = dishNameController.text;
            result['price'] = int.parse(dishPriceController.text);

            List<dynamic> originMenu = stores['menu'];

            setState(() {
              stores['menu'].add(result);
              updateMenuToFirestore();
              print(stores['menu']);
            });

            Navigator.of(context).pop();

            dishNameController.clear();
            dishPriceController.clear();

            final snackBar = SnackBar(
              content: Text('Add Dishes Successful!'),
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
          child: Text('Save')),
    ];
  }

  List<Widget> popupEditAction(BuildContext context, int index) {
    Map<String, dynamic> result = {};
    return [
      TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text('Cancel')),
      TextButton(
          onPressed: () {
            result['name'] = dishNameController.text;
            result['price'] = int.parse(dishPriceController.text);

            List<dynamic> originMenu = stores['menu'];

            setState(() {
              stores['menu'][index] = (result);
              updateMenuToFirestore();
              print(stores['menu']);
            });

            Navigator.of(context).pop();

            dishNameController.clear();
            dishPriceController.clear();

            final snackBar = SnackBar(
              content: Text('Edit Dishes Successful!'),
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
          child: Text('Save')),
    ];
  }

  Column popupContent([Map<String, dynamic>? originItem]) {
    if (originItem == null) {
      dishNameController = TextEditingController();
      dishPriceController = TextEditingController();

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            decoration: InputDecoration(hintText: 'Dishes name'),
            controller: dishNameController,
          ),
          TextField(
            decoration: InputDecoration(hintText: 'Dishes price'),
            controller: dishPriceController,
            keyboardType: TextInputType.number,
          ),
        ],
      );
    } else {
      dishNameController = TextEditingController(text: originItem['name']);
      dishPriceController =
          TextEditingController(text: originItem['price'].toString());

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            decoration: InputDecoration(hintText: 'Dishes name'),
            controller: dishNameController,
          ),
          TextFormField(
            decoration: InputDecoration(hintText: 'Dishes price'),
            controller: dishPriceController,
            keyboardType: TextInputType.number,
          ),
        ],
      );
    }
  }

  void remove(int index) {
    setState(() {
      stores['menu'].removeAt(index);
      updateMenuToFirestore();
    });
  }

  void edit(int index) {
    showDialog(
        context: context,
        builder: (context) {
          Map<String, dynamic> item = stores['menu'][index];
          print(item);

          return AlertDialog(
              title: const Text("Edit Menu"),
              content: popupContent(item),
              actions: popupEditAction(context, index));
        });
  }

  void updateMenuToFirestore() {
    DocumentReference documentReference =
        FirebaseFirestore.instance.collection('store').doc(widget.storeID);

    documentReference.update({'menu': stores['menu']});
  }
}
