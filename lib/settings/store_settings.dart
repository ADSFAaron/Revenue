import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'store_settings_edit_menu.dart';
import 'store_settings_history_order.dart';

class StoreSettings extends StatefulWidget {
  final String storeId;

  const StoreSettings(this.storeId, {super.key});

  @override
  State<StoreSettings> createState() => _StoreSettingsState();
}

class _StoreSettingsState extends State<StoreSettings> {
  late Map<String, dynamic> storeData;
  final TextEditingController storeNameController = TextEditingController();

  @override
  void dispose() {
    storeNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Settings'),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('store')
            .doc(widget.storeId)
            .snapshots(),
        builder:
            (BuildContext context, AsyncSnapshot<DocumentSnapshot> snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          storeData = snapshot.data?.data() as Map<String, dynamic>;

          return SafeArea(
            child: ListView(
              children: [
                _buildListTile(
                  context,
                  icon: Icons.title_outlined,
                  title: 'Store Name',
                  subtitle: storeData['name'],
                  trailing: const Icon(Icons.mode_edit_outline),
                  onTap: () => _editStoreNameDialog(context),
                ),
                _buildListTile(
                  context,
                  icon: Icons.other_houses_outlined,
                  title: 'Store ID',
                  subtitle: widget.storeId,
                  trailing: const Icon(Icons.copy_outlined),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: widget.storeId));
                    _showSnackBar(context, 'Store ID copied to clipboard');
                  },
                ),
                _buildListTile(
                  context,
                  icon: Icons.group_outlined,
                  title: 'Users in store',
                  subtitle: '${storeData['users'].length} users',
                ),
                _buildListTile(
                  context,
                  icon: Icons.history_toggle_off_outlined,
                  title: 'Join Time',
                  subtitle: DateFormat('yyyy-MM-dd  kk:mm')
                      .format(storeData['joinDate'].toDate()),
                ),
                _buildListTile(
                  context,
                  icon: Icons.menu_book_outlined,
                  title: 'Edit Menu',
                  trailing: const Icon(Icons.keyboard_arrow_right_outlined),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => StoreEditMenu(widget.storeId),
                      ),
                    );
                  },
                ),
                _buildListTile(
                  context,
                  icon: Icons.history,
                  title: 'History Order',
                  trailing: const Icon(Icons.keyboard_arrow_right_outlined),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            StoreHistoryOrder(widget.storeId),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildListTile(
      BuildContext context, {
        required IconData icon,
        required String title,
        String? subtitle,
        Widget? trailing,
        void Function()? onTap,
      }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: trailing,
      onTap: onTap,
    );
  }

  void _editStoreNameDialog(BuildContext context) {
    storeNameController.text = storeData['name'];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Store Name'),
          content: TextField(
            controller: storeNameController,
            decoration: const InputDecoration(
              labelText: 'Store Name',
              hintText: 'Enter new store name',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final newName = storeNameController.text.trim();
                if (newName.isNotEmpty) {
                  FirebaseFirestore.instance
                      .collection('store')
                      .doc(widget.storeId)
                      .update({'name': newName});
                  Navigator.of(context).pop();
                  _showSnackBar(context, 'Store name updated successfully');
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
