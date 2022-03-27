import 'package:Revenue/settings/store_settings_edit_menu.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'store_settings_history_order.dart';

class StoreSettings extends StatelessWidget {
  String storeID;
  StoreSettings(this.storeID, {Key? key}) : super(key: key);
  late Map<String, dynamic> stores;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Settings'),
      ),
      body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('store')
              .where(storeID)
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

            print(stores);

            return SafeArea(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.title_outlined),
                    title: Text('Store Name'),
                    subtitle: Text(stores['name']),
                    trailing: Icon(Icons.mode_edit_outline),
                  ),
                  ListTile(
                    leading: Icon(Icons.other_houses_outlined),
                    title: Text('Store ID'),
                    subtitle: Text(storeID),
                    trailing: Icon(Icons.copy_outlined),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: storeID));
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
                            builder: (context) => StoreEditMenu(this.storeID)),
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
                                StoreHistoryOrder(this.storeID)),
                      );
                    },
                  ),
                ],
              ),
            );
          }),
    );
  }
}
