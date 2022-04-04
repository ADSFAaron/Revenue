import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

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
  late List<_ChartData> chartData;
  late TooltipBehavior _tooltip;
  Map<String, dynamic> allorderSave = {};

  @override
  void initState() {
    super.initState();

    // data = [
    //   _ChartData('CHN', 12),
    //   _ChartData('GER', 15),
    //   _ChartData('RUS', 30),
    //   _ChartData('BRZ', 6.4),
    //   _ChartData('IND', 14)
    // ];
    chartData = [];
    _tooltip = TooltipBehavior(enable: true);
  }

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
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
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
                              Column(
                                children: <Widget>[
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: getAllOrder(data['orders']),
                                  ),
                                  createChart(data['orders']),
                                  const Text(
                                    'Income',
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black),
                                  ),
                                ],
                              ),
                            ],
                          ),
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
    Map<String, dynamic> allorders = getOrderCount(data);

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

  Map<String, dynamic> getOrderCount(List<dynamic> data) {
    if (allorderSave.isEmpty) {
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
      allorderSave = allorders;
      return allorders;
    } else {
      return allorderSave;
    }
  }

  SfCartesianChart createChart(List<dynamic> data) {
    chartData = [];
    Map<String, dynamic> allorders = getOrderCount(data);
    int findMax = 0;
    for (int i = allorders.length - 1; i >= 0; i--) {
      if (int.parse(allorders.values.elementAt(i)['amount'].toString()) >
          findMax) {
        findMax = int.parse(allorders.values.elementAt(i)['amount'].toString());
      }
      chartData.add(_ChartData(allorders.keys.elementAt(i),
          double.parse(allorders.values.elementAt(i)['amount'].toString())));
    }

    return SfCartesianChart(
      title: ChartTitle(text: 'Amount of all Dishes'),
      primaryXAxis: CategoryAxis(),
      primaryYAxis: NumericAxis(
          minimum: 0, maximum: (findMax + 5).toDouble(), interval: 10),
      tooltipBehavior: _tooltip,
      series: <ChartSeries<_ChartData, String>>[
        BarSeries<_ChartData, String>(
          dataSource: chartData,
          xValueMapper: (_ChartData data, _) => data.x,
          yValueMapper: (_ChartData data, _) => data.y,
          name: 'Dish',
          dataLabelSettings: DataLabelSettings(isVisible: true),
          color: Color.fromRGBO(8, 142, 255, 1),
        ),
      ],
    );
  }
}

class _ChartData {
  _ChartData(this.x, this.y);

  final String x;
  final double y;
}
