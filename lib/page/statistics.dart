import 'dart:io';
import 'package:path/path.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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
  late Directory rootPath;
  String? dirPath;

  @override
  void initState() {
    _prepareStorage();
    super.initState();

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
                              ElevatedButton.icon(
                                onPressed: () {
                                  openExcelDialog(context);
                                },
                                icon: const Icon(Icons.output_outlined),
                                label: const Text('Output Excel'),
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

  Future<void> createExcelFile(DateTimeRange dateRange) async {
    // Check data exist
    if (orderForOutput.isNotEmpty) {
      // Get all date
      final daysToGenerate = dateRange.end.difference(dateRange.start).inDays;
      List<DateTime> days = List.generate(
          daysToGenerate,
          (i) => DateTime(dateRange.start.year, dateRange.start.month,
              dateRange.start.day + (i)));

      List<dynamic> rangeData = [];
      Map<DateTime, dynamic> daysHM = {};
      for (int i = 0; i < days.length; i++) {
        daysHM.putIfAbsent(days[i], () => {});
      }

      for (int i = 0; i < orderForOutput['orders'].length; i++) {
        DateTime orderDate = orderForOutput['orders'][i]['time'].toDate();
        orderDate = DateTime(orderDate.year, orderDate.month, orderDate.day);
        if (daysHM.containsKey(orderDate)) {
          rangeData.add(orderForOutput['orders'][i]);
        }
      }

      // Create excel file
      Excel excel = Excel.createExcel();

      // Output First Row
      String? defaultSheet = excel.getDefaultSheet();
      List<String> menuName = ["日期 \\ 品項"];

      // Get the shop's menu
      getOrderCount(orderForOutput['orders']).forEach((key, value) {
        menuName.add(key);
      });

      excel.appendRow(defaultSheet.toString(), menuName);

      for (int i = 0; i < rangeData.length; i++) {
        Map<String, dynamic> tmp = rangeData[i];
        List<String> row = [tmp['time'].toDate().toString()];

        for (int j = 1; j < menuName.length; j++) {
          String name = menuName[j];
          bool hasData = false;

          for (int k = 0; k < tmp['details'].length; k++) {
            if (tmp['details'][k]['name'] == name) {
              row.add(tmp['details'][k]['amount'].toString());
              hasData = true;
              break;
            }
          }

          if (hasData == false) {
            row.add("0");
          }
        }
        excel.appendRow(defaultSheet.toString(), row);
      }

      var fileBytes = excel.save();

      File(join(
          dirPath!,
          "Revenue"
              " - ",
          _getYMD(dateRange.start),
          " - ",
          _getYMD(dateRange.end),
          ".xlsx"))
        ..createSync(recursive: true)
        ..writeAsBytesSync(excel.encode()!);

      print("output finish");
    }
  }

  Future openExcelDialog(context) {
    DateTimeRange _date = DateTimeRange(
      start: DateTime(
          DateTime.now().year, DateTime.now().month - 1, DateTime.now().day),
      end: DateTime.now(),
    );
    return showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, StateSetter setState) {
              return AlertDialog(
                title: const Text('Excel option'),
                content:
                    Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Row(
                    children: [
                      Text(
                        'Date Range: \n\n${_getYMD(_date.start)} ~ ${_getYMD(_date.end)} \n',
                        textAlign: TextAlign.start,
                      ),
                      Spacer(),
                      IconButton(
                        onPressed: () {
                          _selectDate(context, _date).then((value) => {
                                setState(() {
                                  print(value);
                                  _date = value!;
                                })
                              });
                        },
                        icon: const Icon(Icons.date_range_outlined),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Output Path: \n\n$dirPath',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Spacer(),
                      IconButton(
                        onPressed: () async {
                          if (await _requestPermission(Permission.storage)) {
                            String? path = await FilesystemPicker.open(
                              title: 'Save to folder',
                              context: context,
                              rootDirectory: rootPath,
                              fsType: FilesystemType.folder,
                              pickText: 'Save file to this folder',
                              folderIconColor: Colors.teal,
                              requestPermission: () async =>
                                  await Permission.storage.request().isGranted,
                            );

                            print('path: ${path}');

                            setState(() {
                              dirPath = path;
                            });
                          } else {
                            const snackBar = SnackBar(
                              content: Text('Sorry! No permission'),
                            );
                            ScaffoldMessenger.of(context)
                                .showSnackBar(snackBar);
                          }
                        },
                        icon: const Icon(Icons.folder_open_outlined),
                      ),
                    ],
                  ),
                ]),
                actions: [
                  TextButton(
                    child: const Text('Cancel'),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                  ElevatedButton(
                    onPressed: () {
                      createExcelFile(_date);
                      Navigator.of(context).pop();
                    },
                    child: const Text('Output'),
                  ),
                ],
              );
            },
          );
        });
  }

  Future<DateTimeRange?> _selectDate(
      BuildContext context, DateTimeRange _date) async {
    DateTimeRange? newDate = await showDateRangePicker(
      context: context,
      initialDateRange: _date,
      firstDate: DateTime(2022, 1),
      lastDate: DateTime(2100, 12),
      helpText: 'Select a date range',
    );

    return newDate;
  }

  // 只取得日期 並轉換為 string
  String _getYMD(DateTime date) {
    return date.year.toString() +
        "-" +
        date.month.toString() +
        "-" +
        date.day.toString();
  }

  Future<void> _prepareStorage() async {
    rootPath = await getApplicationDocumentsDirectory();

    print(rootPath);
    String newPath = rootPath.path.substring(0, 5);
    print(newPath);

    // Create sample directory if not exists
    Directory sampleFolder = Directory('${newPath}');
    if (!sampleFolder.existsSync()) {
      sampleFolder.createSync();
    }

    setState(() {});
  }

  Future<bool> _requestPermission(Permission permission) async {
    if (await permission.isGranted) {
      return true;
    } else {
      var result = await permission.request();
      if (result == PermissionStatus.granted) {
        return true;
      } else {
        return false;
      }
    }
  }
}

class _ChartData {
  _ChartData(this.x, this.y);

  final String x;
  final double y;
}
