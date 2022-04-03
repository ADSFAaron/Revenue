import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class StatisticsPage extends StatefulWidget {
  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  String dropdownValue = 'All orders';
  CollectionReference orderReference =
      FirebaseFirestore.instance.collection('tmporder');

  User currentUser = FirebaseAuth.instance.currentUser!;
  late Map<String, dynamic> users, stores;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where(currentUser.email!)
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
              users = document.data() as Map<String, dynamic>;
            });

            return FutureBuilder<DocumentSnapshot>(
                future: orderReference.doc(users['storeID']).get(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text("Something went wrong");
                  }

                  if (snapshot.hasData && !snapshot.data!.exists) {
                    return Text("Document does not exist");
                  }

                  if (snapshot.connectionState == ConnectionState.done) {
                    Map<String, dynamic> data =
                        snapshot.data!.data() as Map<String, dynamic>;
                    print(data);

                    return SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: <Widget>[
                            const Text(
                              'Trending dishes',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black),
                            ),
                            DropdownButton(
                              value: dropdownValue,
                              items: <String>[
                                'All orders',
                                'Last week',
                                'Last month',
                                'Custom'
                              ].map<DropdownMenuItem<String>>((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                setState(() {
                                  dropdownValue = newValue!;
                                });
                              },
                            ),
                            Column(children: <Widget>[
                              SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: getAllOrder(data['orders']))
                            ]),
                            const Text(
                              'Income',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return Center(
                    child: CircularProgressIndicator(),
                  );
                });
          }),
    );
  }

  DataTable getAllOrder(List<dynamic> data) {
    List<DataColumn> col = [];
    List<DataRow> row = [];
    Map<String, dynamic> allorders = Map();

    for (int i = 0; i < data.length; i++) {
      List<dynamic> perData = data[i]['details'];
      for (int j = 0; j < perData.length; j++) {
        if (allorders.containsKey(perData[j]['name'])) {
          allorders[perData[j]['name']]['amount'] += perData[j]['amount'];
        } else {
          allorders.putIfAbsent(perData[j]['name'], () => perData[j]);
        }
      }
    }

    // create table
    col.add(DataColumn(label: Text('Name')));
    col.add(DataColumn(label: Text('Price'), numeric: true));
    col.add(DataColumn(label: Text('Amount'), numeric: true));
    col.add(DataColumn(label: Text('Subtotal')));

    for (var i = 0; i < allorders.length; i++) {
      int subtotal =
          int.parse(allorders.values.elementAt(i)['amount'].toString()) *
              int.parse(allorders.values.elementAt(i)['price'].toString());
      print(subtotal);
      row.add(DataRow(cells: [
        DataCell(Text(allorders.keys.elementAt(i))),
        DataCell(Text(allorders.values.elementAt(i)['price'].toString())),
        DataCell(Text(allorders.values.elementAt(i)['amount'].toString())),
        DataCell(Text(subtotal.toString()))
      ]));
    }

    return DataTable(
        columns: col, rows: row, sortColumnIndex: 2, sortAscending: true);
  }
}
