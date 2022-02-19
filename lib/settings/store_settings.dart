import 'package:flutter/material.dart';

class StoreSettings extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Settings'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.title_outlined),
              title: Text('Store Name'),
              subtitle: Text('xxx'),
              trailing: Icon(Icons.mode_edit_outline),
            ),
            ListTile(
              leading: Icon(Icons.other_houses_outlined),
              title: Text('Store ID'),
              subtitle: Text('2 users'),
              trailing: Icon(Icons.copy_outlined),
            ),
            ListTile(
              leading: Icon(Icons.group_outlined),
              title: Text('Users in store'),
              subtitle: Text('2 users'),
            ),
            ListTile(
              leading: Icon(Icons.history_toggle_off_outlined),
              title: Text('Join Time'),
              subtitle: Text('2022'),
            ),
            ListTile(
              leading: Icon(Icons.menu_book_outlined),
              title: Text('Edit Menu'),
              trailing: Icon(Icons.keyboard_arrow_right_outlined),
              onTap: () {},
            ),
            ListTile(
              leading: Icon(Icons.history),
              trailing: Icon(Icons.keyboard_arrow_right_outlined),
              title: Text('History order'),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}
