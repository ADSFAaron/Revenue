import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';


// TODO: "More Feature" function work
// TODO: "Export" function work
// TODO: currentOrders and expectOrders data from Firestore

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage>
    with TickerProviderStateMixin {
  CollectionReference orderReference =
      FirebaseFirestore.instance.collection('tmporder');
  User currentUser = FirebaseAuth.instance.currentUser!;
  late Map<String, dynamic> users, stores;
  late List<_ChartData> chartData;
  late Map<String, dynamic> orderForOutput = {};
  Map<String, dynamic> allorderSave = {};
  late Directory rootPath;
  String? dirPath;
  bool isDark = false;
  late final TabController _tabController;

  TooltipBehavior? _tooltipBehavior;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    _internetUsersDataIn2016 = _initializeChartData();
    _tooltipBehavior = TooltipBehavior(
      enable: true,
      header: '',
      canShowMarker: false,
    );

    chartData = [];
    _tabController = TabController(length: 3, vsync: this);
  }

  List<ChartSampleData> _initializeChartData() {
    return <ChartSampleData>[
      ChartSampleData(
        x: 'South\nKorea',
        yValue: 39,
        pointColor: Colors.teal[300],
      ),
      ChartSampleData(
        x: 'India',
        yValue: 20,
        pointColor: const Color.fromRGBO(53, 124, 210, 1),
      ),
      ChartSampleData(
        x: 'South\nAfrica',
        yValue: 61,
        pointColor: Colors.pink,
      ),
      ChartSampleData(
        x: 'China',
        yValue: 65,
        pointColor: Colors.orange,
      ),
      ChartSampleData(
        x: 'France',
        yValue: 45,
        pointColor: Colors.green,
      ),
      ChartSampleData(
        x: 'Saudi\nArabia',
        yValue: 10,
        pointColor: Colors.pink[300],
      ),
      ChartSampleData(
        x: 'Japan',
        yValue: 16,
        pointColor: Colors.purple[300],
      ),
      ChartSampleData(
        x: 'Mexico',
        yValue: 31,
        pointColor: const Color.fromRGBO(127, 132, 232, 1),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    const String assetName = 'assets/google-gemini-icon.svg';
    final Widget svg = SvgPicture.asset(
      assetName,
      semanticsLabel: 'Gemini Logo',
      height: 24,
      width: 24,
      colorFilter: isDark
          ? ColorFilter.mode(Colors.white, BlendMode.srcIn)
          : ColorFilter.mode(Colors.black, BlendMode.srcIn),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Statistics'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Day'),
            Tab(text: 'Week'),
            Tab(text: 'Month'),
          ],
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.email)
            .snapshots(),
        builder:
            (BuildContext context, AsyncSnapshot<DocumentSnapshot> snapshot) {
          if (snapshot.hasError) {
            return _buildErrorWidget(snapshot.error.toString());
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingWidget();
          }

          users = snapshot.data?.data() as Map<String, dynamic>;

          return FutureBuilder<DocumentSnapshot>(
            future: orderReference.doc(users['storeID']).get(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _buildErrorWidget("Something went wrong");
              }

              if (snapshot.hasData && !snapshot.data!.exists) {
                return _buildErrorWidget("Document does not exist");
              }

              if (snapshot.connectionState == ConnectionState.done) {
                return _buildContent(snapshot.data!);
              }
              return _buildLoadingWidget();
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          debugPrint('FloatingActionButton tapped');
        },
        child: GestureDetector(
          child: svg,
        ),
      ),
    );
  }

  Widget _buildErrorWidget(String errorMessage) {
    return Center(child: Text('Error: $errorMessage'));
  }

  Widget _buildLoadingWidget() {
    return Center(child: CircularProgressIndicator());
  }

  Widget _buildContent(DocumentSnapshot snapshot) {
    Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
    orderForOutput = data;
    debugPrint('DB orders: $data');

    DateTime now = DateTime.now();
    num currentOrders = 60;
    num expectOrders = 200;
    String chartTitle = 'Today\'s Dishes';
    Icon moneyBagIcon = Icon(Symbols.money_bag);
    double totalIncome = 0;

    if (data['orders'].isEmpty) {
      return SafeArea(
        child: Center(
          child: Text('No Order'),
        ),
      );
    }

    // Recursive all orders
    List<ChartSampleData> ordersData = [];
    Map<String, dynamic> ordersCount = getOrderCount(data['orders']);
    ordersCount.forEach((key, value) {
      ordersData.add(ChartSampleData(x: key, yValue: value['amount']));
    });

    ordersCount.forEach((key, value) {
      totalIncome += (value['price'] * value['amount']);
    });

    debugPrint('ordersData: $ordersData');

    return SafeArea(
      child: TabBarView(
        controller: _tabController,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                spacing: 20,
                children: <Widget>[
                  _buildHeaderRow(now),
                  _buildRangePointerGauge(currentOrders, expectOrders),
                  _buildCartesianChart(chartTitle, ordersData),
                  Wrap(
                    children: [
                      _buildCard(
                        title: 'Income',
                        icon: moneyBagIcon.icon,
                        value: totalIncome.toStringAsFixed(0),
                        onTap: () => debugPrint('money Card tapped'),
                      ),
                      _buildCard(
                        title: 'Export',
                        icon: Icons.download_outlined,
                        value: 'Excel',
                        onTap: () => {debugPrint('excel tapped')},
                      ),
                      _buildAddMoreCard(context),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Icon(Icons.directions_transit),
          Icon(Icons.directions_bike),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(DateTime infoDate) {
    DateTime now = DateTime.now();
    String displayDate;

    // Determine is today or yesterday
    if (infoDate.day == now.day) {
      displayDate = 'Today';
    } else if (infoDate.day == now.day - 1) {
      displayDate = 'Yesterday';
    } else {
      displayDate = infoDate.toString();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ElevatedButton(
          onPressed: () {},
          style: ElevatedButton.styleFrom(elevation: 0),
          child: Icon(Icons.arrow_back),
        ),
        Text(
          displayDate,
          style: TextStyle(fontSize: 20),
        ),
        ElevatedButton(
          onPressed: () {},
          style: ElevatedButton.styleFrom(elevation: 0),
          child: Icon(Icons.arrow_forward),
        ),
      ],
    );
  }

  Widget _buildAddMoreCard(BuildContext context) {
    return Card(
      elevation: 0,
      child: InkWell(
        onTap: () {
          showModalBottomSheet(
            context: context,
            builder: (context) => _buildAddMoreSheet(context),
          );
        },
        child: SizedBox(
          width: MediaQuery.of(context).size.width / 2 - 30,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).splashColor,
                    borderRadius: BorderRadius.circular(48),
                  ),
                  height: 48,
                  width: 48,
                  child:
                      Icon(Icons.add, color: Theme.of(context).iconTheme.color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddMoreSheet(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.5,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'More Feature',
                style: TextStyle(fontSize: 20),
              ),
              _buildListTile('Income', 'Selected Date Income', Icons.check_rounded),
              _buildListTile(
                  'Export', 'Export data to Excel', Icons.check_rounded),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    child: const Text('Close'),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListTile(String title, String subtitle, IconData icon) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () => {},
    );
  }

  Map<String, dynamic> getOrderCount(List<dynamic> data) {
    if (allorderSave.isEmpty) {
      Map<String, dynamic> allOrders = {};

      for (int i = 0; i < data.length; i++) {
        List<dynamic> perData = data[i]['details'];
        for (int j = 0; j < perData.length; j++) {
          if (allOrders.containsKey(perData[j]['name'])) {
            allOrders[perData[j]['name']]['amount'] += perData[j]['amount'];
          } else {
            allOrders.putIfAbsent(perData[j]['name'], () => perData[j]);
          }
        }
      }
      allorderSave = allOrders;

      debugPrint('allOrders: $allOrders');
      return allOrders;
    } else {
      return allorderSave;
    }
  }

  /// Return the Cartesian Chart with Column series.
  SfCartesianChart _buildCartesianChart(
      String chartTitle, List<ChartSampleData> data) {
    // Calculate max from data
    num? max = 0;
    for (int i = 0; i < data.length; i++) {
      if (data[i].yValue! > max!) {
        max = data[i].yValue!;
      }
    }

    double maxVal = double.parse(max.toString());

    return SfCartesianChart(
      plotAreaBorderWidth: 0,
      title: ChartTitle(
        text: chartTitle,
      ),
      primaryXAxis: const CategoryAxis(
        majorGridLines: MajorGridLines(width: 0),
      ),
      primaryYAxis: NumericAxis(
        minimum: 0,
        maximum: maxVal,
        isVisible: true,
        labelFormat: '{value}',
      ),
      series: _buildColumnSeries(data),
      tooltipBehavior: _tooltipBehavior,
    );
  }

  /// Returns the list of Cartesian Column series.
  List<ColumnSeries<ChartSampleData, String>> _buildColumnSeries(
      List<ChartSampleData> source) {
    return <ColumnSeries<ChartSampleData, String>>[
      ColumnSeries<ChartSampleData, String>(
        dataSource: source,
        xValueMapper: (ChartSampleData data, int index) => data.x,
        yValueMapper: (ChartSampleData data, int index) => data.yValue,
        pointColorMapper: (ChartSampleData data, int index) => data.pointColor,
        dataLabelSettings: const DataLabelSettings(
          isVisible: true,
        ),
      ),
    ];
  }

  Widget _buildCard(
      {required String title,
      String? value,
      IconData? icon,
      required VoidCallback onTap,
      double? growth}) {
    Container growthContainer;

    if (growth == null) {
      growthContainer = Container();
    } else {
      Icon icon = growth >= 0
          ? const Icon(Icons.trending_up_rounded, size: 16, color: Colors.green)
          : const Icon(Icons.trending_down_rounded,
              size: 16, color: Colors.red);
      String growthText = growth >= 0 ? ' $growth%' : ' $growth%';

      growthContainer = Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: growth >= 0 ? Colors.green[100] : Colors.red[100],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            icon,
            Text(
              growthText,
              style: TextStyle(
                color: growth >= 0 ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: MediaQuery.of(context).size.width / 2 - 30,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).splashColor,
                        borderRadius: BorderRadius.circular(48),
                      ),
                      height: 48,
                      width: 48,
                      child:
                          Icon(icon, color: Theme.of(context).iconTheme.color),
                    ),
                    const SizedBox(width: 10),
                    Text(title),
                  ],
                ),
                SizedBox(
                  height: 16,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      value ?? '',
                      style: const TextStyle(fontSize: 24),
                    ),
                    growth != null
                        ? Spacer()
                        : SizedBox(
                            width: 8,
                          ),
                    growthContainer,
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

///Chart sample data
class ChartSampleData {
  /// Holds the datapoint values like x, y, etc.,
  ChartSampleData(
      {this.x,
      this.y,
      this.xValue,
      this.yValue,
      this.secondSeriesYValue,
      this.thirdSeriesYValue,
      this.pointColor,
      this.size,
      this.text,
      this.open,
      this.close,
      this.low,
      this.high,
      this.volume});

  /// Holds x value of the datapoint
  final dynamic x;

  /// Holds y value of the datapoint
  final num? y;

  /// Holds x value of the datapoint
  final dynamic xValue;

  /// Holds y value of the datapoint
  final num? yValue;

  /// Holds y value of the datapoint(for 2nd series)
  final num? secondSeriesYValue;

  /// Holds y value of the datapoint(for 3nd series)
  final num? thirdSeriesYValue;

  /// Holds point color of the datapoint
  final Color? pointColor;

  /// Holds size of the datapoint
  final num? size;

  /// Holds datalabel/text value mapper of the datapoint
  final String? text;

  /// Holds open value of the datapoint
  final num? open;

  /// Holds close value of the datapoint
  final num? close;

  /// Holds low value of the datapoint
  final num? low;

  /// Holds high value of the datapoint
  final num? high;

  /// Holds open value of the datapoint
  final num? volume;
}

class _ChartData {
  _ChartData(this.x, this.y, {this.color = Colors.blue});

  final String x;
  final double y;
  final Color color;
}

SfRadialGauge _buildRangePointerGauge(currentOrders, expectOrders) {
  double ordersPercent = (currentOrders / expectOrders) * 100;

  return SfRadialGauge(
    axes: <RadialAxis>[
      RadialAxis(
        showLabels: true,
        showTicks: false,
        maximum: expectOrders.toDouble(),
        radiusFactor: 0.8,
        axisLineStyle: const AxisLineStyle(
          thicknessUnit: GaugeSizeUnit.factor,
          thickness: 0.15,
        ),
        annotations: <GaugeAnnotation>[
          GaugeAnnotation(
            angle: 200,
            widget: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      currentOrders.toString(),
                      style: TextStyle(
                        fontFamily: 'Times',
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    Text(
                      ' / $expectOrders',
                      style: TextStyle(
                        fontFamily: 'Times',
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
                Text(
                  '$ordersPercent%',
                ),
              ],
            ),
          ),
        ],
        pointers: <GaugePointer>[
          RangePointer(
            value: currentOrders.toDouble(),
            enableAnimation: true,
            animationDuration: 1000,
            sizeUnit: GaugeSizeUnit.factor,
            gradient: const SweepGradient(
              colors: <Color>[Color(0xFF6A6EF6), Color(0xFFDB82F5)],
              stops: <double>[0.25, 0.75],
            ),
            color: const Color(0xFF00A8B5),
            width: 0.15,
          ),
        ],
      ),
    ],
  );
}
