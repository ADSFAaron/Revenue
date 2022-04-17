import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({Key? key}) : super(key: key);

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
  late Map<String, dynamic> orderForOutput = {};
  Map<String, dynamic> allorderSave = {};
  late DateTimeRange _date;

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

    _date = DateTimeRange(
      start: DateTime(
          DateTime.now().year, DateTime.now().month - 1, DateTime.now().day),
      end: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          openDialog();

          // print("create excel");
          // createExcelFile();
        },
        icon: const Icon(Icons.save_alt_outlined),
        label: const Text('Output to Excel'),
      ),
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
                    orderForOutput = data;

                    return SafeArea(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            children: <Widget>[
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
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
                                    ].map<DropdownMenuItem<String>>(
                                        (String value) {
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
                                ],
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

  Future<void> createExcelFile() async {
    if (orderForOutput.isEmpty) {
      print("empty doc");
      return;
    } else {
      print("not empty");
      print(orderForOutput['orders']);

      Map<String, dynamic> count = getOrderCount(orderForOutput['orders']);
      // find one day
      // show output option

      Excel excel = Excel.createExcel();
      var defaultSheet = await excel.getDefaultSheet();
      String firstTitle = "日期 \\ 品項";

      List<String> menuName = [firstTitle];

      // for (int i = 0; i < menu.length; i++) {
      //   menuName.add(menu[i]['name']);
      // }

    }
  }

  Future openDialog() {
    return showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Excel option'),
            content: Column(children: <Widget>[
              ElevatedButton(
                onPressed: () {
                  _selectDate(context);
                },
                child: const Text('Choose Date'),
              ),
              Center(
                child: Text(
                  '選擇區間: \n${_getYMD(_date.start)} ~ ${_getYMD(_date.end)}',
                  textAlign: TextAlign.center,
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  createExcelFile();
                },
                child: const Text('Output'),
              ),
            ]),
          );
        });
  }

  void _selectDate(BuildContext context) async {
    DateTimeRange? newDate = await showDateRangePicker(
      context: context,
      initialDateRange: _date,
      firstDate: DateTime(2021, 1),
      lastDate: DateTime(2022, 7),
      helpText: 'Select a date range',
    );
    if (newDate != null) {
      setState(() {
        _date = newDate;
      });
    }
  }

  // 只取得日期 並轉換為 string
  String _getYMD(DateTime date) {
    return date.year.toString() +
        "-" +
        date.month.toString() +
        "-" +
        date.day.toString();
  }
}

class _ChartData {
  _ChartData(this.x, this.y);

  final String x;
  final double y;
}
