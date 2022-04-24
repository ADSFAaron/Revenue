import 'package:Revenue/page/addorder.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class StoreHistoryOrderDetail extends StatelessWidget {
  String storeID;
  String currency = "NTD ";
  int index;
  Map<String, dynamic> order;
  StoreHistoryOrderDetail(this.storeID, this.index, this.order, {Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white70,
      appBar: AppBar(
        title: const Text('Transaction details'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Card(
            elevation: 5,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    'Order no : ' + order['no'].toString().padLeft(10, '0'),
                    style: TextStyle(color: Colors.black, fontSize: 24),
                  ),
                  Divider(
                    color: Colors.black,
                    height: 20,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Order time : ' +
                            DateFormat('yyyy-MM-dd (EEEE)').format(
                                DateTime.parse(
                                    order['time'].toDate().toString())),
                        style: TextStyle(color: Colors.black, fontSize: 18),
                      ),
                    ),
                  ),
                  Divider(
                    color: Colors.black,
                    height: 20,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Total : ' + currency + order['total'].toString(),
                        style: TextStyle(color: Colors.black, fontSize: 18),
                      ),
                    ),
                  ),
                  const Divider(
                    color: Colors.black,
                    height: 20,
                  ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Items : ',
                      style: TextStyle(color: Colors.black, fontSize: 18),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: order['details']
                          .map<Widget>(
                            (dynamic element) => Card(
                              elevation: 0,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 3, horizontal: 24),
                                title: Text(element['name'].toString()),
                                subtitle: Text("contains " +
                                    element['amount'].toString() +
                                    " pieces"),
                                trailing: Text(
                                    currency + element['price'].toString()),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size.fromHeight(
                            40), // fromHeight use double.infinity as width and 40 is the height
                      ),
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (context) => AddOrder(
                                    storeID,
                                    origin: order,
                                  )),
                        );
                      },
                      icon: Icon(Icons.edit_outlined),
                      label: Text("Edit")),
                  OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          minimumSize: Size.fromHeight(40)),
                      onPressed: () {
                        reconfirm(context);
                      },
                      icon: Icon(Icons.delete_outline),
                      label: Text("Delete")),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void reconfirm(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: const Text('Are you sure you want to delete this order?'),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            TextButton(
              child: Text('Delete'),
              onPressed: () {
                FirebaseFirestore.instance
                    .collection('tmporder')
                    .doc(storeID)
                    .update({
                  'orders': FieldValue.arrayRemove([order])
                });
                Navigator.pop(context);
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }
}
