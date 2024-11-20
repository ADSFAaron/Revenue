import 'package:Revenue/page/addorder.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class StoreHistoryOrderDetail extends StatelessWidget {
  final String storeID;
  final String currency = "NTD ";
  final int index;
  final Map<String, dynamic> order;

  const StoreHistoryOrderDetail(this.storeID, this.index, this.order, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white70,
      appBar: AppBar(
        title: const Text('Transaction Details'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Card(
            elevation: 5,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildOrderHeader(),
                  const Divider(color: Colors.black, height: 20),
                  _buildOrderDetails(),
                  const Divider(color: Colors.black, height: 20),
                  _buildOrderItems(),
                  const SizedBox(height: 20),
                  _buildActionButtons(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrderHeader() {
    return Text(
      'Order no: ${order['no'].toString().padLeft(10, '0')}',
      style: const TextStyle(color: Colors.black, fontSize: 24),
    );
  }

  Widget _buildOrderDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Order time: ${DateFormat('yyyy-MM-dd (EEEE)').format(order['time'].toDate())}',
          style: const TextStyle(color: Colors.black, fontSize: 18),
        ),
        const SizedBox(height: 16),
        Text(
          'Total: $currency${order['total']}',
          style: const TextStyle(color: Colors.black, fontSize: 18),
        ),
      ],
    );
  }

  Widget _buildOrderItems() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Items:',
          style: TextStyle(color: Colors.black, fontSize: 18),
        ),
        const SizedBox(height: 8),
        Column(
          children: order['details'].map<Widget>(
                (dynamic element) {
              return Card(
                elevation: 0,
                child: ListTile(
                  contentPadding:
                  const EdgeInsets.symmetric(vertical: 3, horizontal: 24),
                  title: Text(element['name'].toString()),
                  subtitle: Text("Quantity: ${element['amount']}"),
                  trailing: Text('$currency${element['price']}'),
                ),
              );
            },
          ).toList(),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(40),
          ),
          onPressed: () => _navigateToEditOrder(context),
          icon: const Icon(Icons.edit_outlined),
          label: const Text("Edit"),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(40),
          ),
          onPressed: () => _confirmDeleteOrder(context),
          icon: const Icon(Icons.delete_outline),
          label: const Text("Delete"),
        ),
      ],
    );
  }

  void _navigateToEditOrder(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AddOrder(storeID, origin: order),
      ),
    );
  }

  void _confirmDeleteOrder(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: Text(
              'Are you sure you want to delete order no: ${order['no']}?'),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text('Delete'),
              onPressed: () async {
                try {
                  await FirebaseFirestore.instance
                      .collection('tmporder')
                      .doc(storeID)
                      .update({
                    'orders': FieldValue.arrayRemove([order]),
                  });
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Return to previous screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Order deleted successfully')),
                  );
                } catch (error) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete order: $error')),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }
}
