import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:grouped_list/grouped_list.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'store_setting_history_order_detail.dart';

class StoreHistoryOrder extends StatelessWidget {
  final String storeID;
  final String currency = "NTD";

  const StoreHistoryOrder(this.storeID, {super.key});

  // TODO: Make firebase query lazy loading (Paginate a query)
  // https://firebase.google.com/docs/firestore/query-data/query-cursors#dart_3

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
            return const Center(child: Text('Something went wrong.'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final Map<String, dynamic>? orderData =
              snapshot.data?.data() as Map<String, dynamic>?;

          if (orderData == null || orderData['orders'] == null) {
            return const Center(child: Text('No orders available.'));
          }

          final List<dynamic> orders = orderData['orders'];

          return GroupedListView<dynamic, String>(
            elements: orders,
            groupBy: (element) =>
                DateFormat('yyyy-MM-dd').format(element['time'].toDate()),
            groupSeparatorBuilder: (String groupByValue) =>
                _buildGroupSeparator(groupByValue),
            itemBuilder: (context, dynamic element) =>
                _buildOrderCard(context, element),
            itemComparator: (item1, item2) =>
                item1['no'].compareTo(item2['no']),
            useStickyGroupSeparators: true,
            floatingHeader: true,
          );
        },
      ),
    );
  }

  Widget _buildGroupSeparator(String groupByValue) {
    final DateTime date = DateTime.parse(groupByValue);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);

    String formattedDate;
    if (date == today) {
      formattedDate = "Today";
    } else if (date == yesterday) {
      formattedDate = "Yesterday";
    } else {
      formattedDate = DateFormat.yMd().add_j().format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      child: Chip(
        labelPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        label: Text(
          formattedDate,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, dynamic element) {
    final listAltCheckIcon = Icon(Symbols.list_alt_check);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        leading: listAltCheckIcon,
        title: Text('Order #${element['no']}'),
        subtitle: Text('${element['time'].toDate()}'),
        trailing: Text(
          textAlign: TextAlign.center,
          '$currency\n${element['total']}',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
        ),
        onTap: () => _navigateToOrderDetail(context, element),
      ),
    );
  }

  void _navigateToOrderDetail(BuildContext context, dynamic element) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoreHistoryOrderDetail(
          storeID,
          element['no'] as int,
          element,
        ),
      ),
    );
  }
}
