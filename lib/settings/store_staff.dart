import 'package:flutter/material.dart';

class StoreStaff extends StatefulWidget {
  const StoreStaff(String storeId, {super.key});

  @override
  State<StoreStaff> createState() => _StoreStaffState();
}

class _StoreStaffState extends State<StoreStaff> {
  @override
  Widget build(BuildContext context) {
    List<String> staffList = [
      'Staff 1',
      'Staff 2',
      'Staff 3',
      'Staff 4',
      'Staff 5'
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Staff'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: ListView.builder(
          itemCount: staffList.length,
          itemBuilder: (BuildContext context, int index) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: ListTile(
                title: Text(staffList[index]),
                subtitle: const Text('Email\nRole'),
                trailing: const Icon(Icons.edit_outlined),
                isThreeLine: true,
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).splashColor,
                  child: Text(
                    'ST'.substring(0, 2).toUpperCase(),
                  ),
                ),
                onTap: () {},
              ),
            );
          },
        ),
      ),
    );
  }
}
