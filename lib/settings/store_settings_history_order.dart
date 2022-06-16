import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:grouped_list/grouped_list.dart';
import 'package:intl/intl.dart';

import 'store_setting_history_order_detail.dart';

class StoreHistoryOrder extends StatelessWidget {
  String storeID;
  String currency = "NTD ";
  StoreHistoryOrder(this.storeID, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History Orders'),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('tmporder')
            .doc(storeID)
            .snapshots(),
        builder:
            (BuildContext context, AsyncSnapshot<DocumentSnapshot> snapshot) {
          if (snapshot.hasError) {
            return Text('Something went wrong');
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Text("Loading");
          }

          print("first");

          Map<String, dynamic> data =
              snapshot.data?.data() as Map<String, dynamic>;

          print(data);
          return GroupedListView<dynamic, String>(
            elements: data['orders'],
            groupBy: (element) =>
                DateFormat('yyyy-MM-dd').format(element['time'].toDate()),
            groupSeparatorBuilder: (String groupByValue) => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              child: Text(
                DateFormat('yyyy-MM-dd (EEEE)')
                    .format(DateTime.parse(groupByValue)),
                style: TextStyle(color: Colors.white),
              ),
              color: Colors.black,
            ),
            itemBuilder: (context, dynamic element) => Card(
              elevation: 3,
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                leading: const Icon(Icons.list_alt),
                title: Text(element['no'].toString()),
                subtitle: Text("contains " +
                    element['details'].length.toString() +
                    " dishes"),
                trailing: Text(currency + element['total'].toString()),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => StoreHistoryOrderDetail(
                          storeID, element['no'] as int, element),
                    ),
                  );
                },
              ),
            ),
            itemComparator: (item1, item2) =>
                item1['no'].compareTo(item2['no']),
            useStickyGroupSeparators: true,
          );
        },
      ),
    );
  }
}
