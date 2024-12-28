import 'package:Revenue/page/addorder.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class StoreHistoryOrderDetail extends StatelessWidget {
  final String storeID;
  final String currency = "NTD";
  final int index;
  final Map<String, dynamic> order;

  const StoreHistoryOrderDetail(this.storeID, this.index, this.order,
      {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Column(
              spacing: 20,
              children: [
                Row(
                  children: [
                    Text(
                      'Order #${order['no'].toString().padLeft(2, '0')}',
                      style:
                          const TextStyle(fontSize: 48, fontFamily: 'NotoSans'),
                    ),
                  ],
                ),
                Column(
                  children: [
                    Row(
                      // total price
                      children: [
                        Text(
                          'Total $currency ',
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w200),
                        ),
                        Text(
                          '${order['total']}',
                          style: const TextStyle(
                              fontSize: 32, fontWeight: FontWeight.w400),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: Text(
                            'Included tax (0%)',
                            style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                                fontWeight: FontWeight.w300),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Order time',
                      style: const TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    Text(
                      DateFormat.yMd().add_jms().format(order['time'].toDate()),
                      style: const TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Payment method',
                      style: const TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    Row(
                      spacing: 8,
                      children: [
                        Icon(
                          Icons.payments_outlined,
                          color: Colors.grey,
                        ),
                        Text(
                          "Cash",
                          style:
                              const TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
                Column(
                  children: order['details'].map<Widget>(
                    (dynamic element) {
                      return Card(
                        elevation: 0,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 3, horizontal: 24),
                          title: Text(element['name'].toString(),
                              style: const TextStyle(fontSize: 16)),
                          trailing: Row(
                            spacing: 8,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                textAlign: TextAlign.center,
                                '$currency \n${element['price'] * element['amount']}',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w400),
                              ),
                            ],
                          ),
                          subtitle: Text('$currency ${element['price']} * ${element['amount']}'),
                        ),
                      );
                    },
                  ).toList(),
                ),
                SizedBox(
                  height: 10,
                ),
                _buildActionButtons(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Function to navigate to the edit order page
  void _navigateToEditOrder(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AddOrder(storeID, origin: order),
      ),
    );
  }

  // Function to confirm and delete the order
  void _confirmDeleteOrder(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content:
              Text('Are you sure you want to delete order no: ${order['no']}?'),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text('Delete'),
              onPressed: () => _deleteOrder(context),
            ),
          ],
        );
      },
    );
  }

  // Widget to build the order header
  Widget _buildOrderHeader() {
    return Text(
      'Order no: ${order['no'].toString().padLeft(3, '0')}',
      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
    );
  }

  // Widget to build the order details (time and total)
  Widget _buildOrderDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Order time: ${DateFormat('yyyy-MM-dd (EEEE)').format(order['time'].toDate())}',
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 16),
        Text(
          'Total: $currency ${order['total']}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // Widget to build the list of order items
  Widget _buildOrderItems() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Items:',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                  title: Text(element['name'].toString(),
                      style: const TextStyle(fontSize: 16)),
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

  // Widget to build the action buttons (Edit and Delete)
  Widget _buildActionButtons(BuildContext context) {
    return Row(
      spacing: 10,
      children: [
        ElevatedButton.icon(
          onPressed: () => _navigateToEditOrder(context),
          icon: const Icon(Icons.edit_outlined),
          label: const Text("Edit"),
        ),
        OutlinedButton.icon(
          onPressed: () => _confirmDeleteOrder(context),
          icon: const Icon(Icons.delete_outline),
          label: const Text("Delete"),
        ),
      ],
    );
  }

  // Function to perform the order deletion
  Future<void> _deleteOrder(BuildContext context) async {
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
  }
}
