import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:grouped_list/grouped_list.dart';
import 'package:intl/intl.dart';

import 'store_setting_history_order_detail.dart';

class StoreHistoryOrder extends StatelessWidget {
  final String storeId;
  final String currency = "NTD ";

  StoreHistoryOrder(this.storeId, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History Orders'),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('tmporder')
            .doc(storeId)
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
            groupSeparatorBuilder: (String groupByValue) => _buildGroupSeparator(groupByValue),
            itemBuilder: (context, dynamic element) => _buildOrderCard(context, element),
            itemComparator: (item1, item2) =>
                item1['no'].compareTo(item2['no']),
            useStickyGroupSeparators: true,
          );
        },
      ),
    );
  }

  Widget _buildGroupSeparator(String groupByValue) {
    final DateTime date = DateTime.parse(groupByValue);
    final String formattedDate =
    DateFormat('yyyy-MM-dd (EEEE)').format(date);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.black,
      child: Text(
        formattedDate,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, dynamic element) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: ListTile(
        contentPadding:
        const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        leading: const Icon(Icons.list_alt),
        title: Text('Order #${element['no']}'),
        subtitle: Text('Contains ${element['details'].length} dishes'),
        trailing: Text('$currency${element['total']}'),
        onTap: () => _navigateToOrderDetail(context, element),
      ),
    );
  }

  void _navigateToOrderDetail(BuildContext context, dynamic element) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoreHistoryOrderDetail(
          storeId,
          element['no'] as int,
          element,
        ),
      ),
    );
  }
}
