import 'package:Revenue/settings/store_settings_edit_menu.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'store_settings_history_order.dart';

class StoreSettings extends StatefulWidget {
  String storeID;
  StoreSettings(this.storeID, {Key? key}) : super(key: key);

  @override
  State<StoreSettings> createState() => _StoreSettingsState();
}

class _StoreSettingsState extends State<StoreSettings> {
  late Map<String, dynamic> stores;

  late TextEditingController storeNameController;

  @override
  void initState() {
    super.initState();
    storeNameController = TextEditingController();
  }

  @override
  void dispose() {
    storeNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Store Settings'),
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

            print(stores);

            return SafeArea(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.title_outlined),
                    title: Text('Store Name'),
                    subtitle: Text(stores['name']),
                    trailing: Icon(Icons.mode_edit_outline),
                    onTap: editStoreName(context),
                  ),
                  ListTile(
                    leading: Icon(Icons.other_houses_outlined),
                    title: Text('Store ID'),
                    subtitle: Text(widget.storeID),
                    trailing: Icon(Icons.copy_outlined),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: widget.storeID));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text("Store ID copied to clipboard"),
                      ));
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.group_outlined),
                    title: Text('Users in store'),
                    subtitle: Text('${stores['users'].length} users'),
                  ),
                  ListTile(
                    leading: Icon(Icons.history_toggle_off_outlined),
                    title: Text('Join Time'),
                    subtitle: Text(DateFormat('yyyy-MM-dd  kk:mm')
                        .format(stores['joinDate'].toDate())),
                  ),
                  ListTile(
                    leading: Icon(Icons.menu_book_outlined),
                    title: Text('Edit Menu'),
                    trailing: Icon(Icons.keyboard_arrow_right_outlined),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                StoreEditMenu(this.widget.storeID)),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.history),
                    trailing: Icon(Icons.keyboard_arrow_right_outlined),
                    title: Text('History order'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                StoreHistoryOrder(this.widget.storeID)),
                      );
                    },
                  ),
                ],
              ),
            );
          }),
    );
  }

  editStoreName(BuildContext context) {
    storeNameController = TextEditingController(text: stores['name']);

    return () {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('Edit Store Name'),
            content: TextField(
              controller: storeNameController,
              decoration: InputDecoration(
                labelText: 'Store Name',
                hintText: 'Store Name',
              ),
            ),
            actions: [
              TextButton(
                child: Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: Text('Save'),
                onPressed: () {
                  String newName = storeNameController.text;
                  print('rename store');
                  print(newName);

                  if (newName.isNotEmpty) {
                    FirebaseFirestore.instance
                        .collection('store')
                        .doc(widget.storeID)
                        .update({'name': newName});
                    Navigator.of(context).pop();
                  }
                },
              ),
            ],
          );
        },
      );
    };
  }
}
