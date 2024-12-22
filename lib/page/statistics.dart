import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

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
  late Map<String, dynamic> orderForOutput = {};
  Map<String, dynamic> allorderSave = {};
  late Directory rootPath;
  String? dirPath;
  bool isDark = false;

  List<ChartSampleData>? _internetUsersDataIn2016;
  TooltipBehavior? _tooltipBehavior;

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
    return Scaffold(
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
    print(data);
    orderForOutput = data;

    if (data['orders'].isEmpty) {
      return SafeArea(
        child: Center(
          child: Text('No Order'),
        ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: <Widget>[
              buildSearchAnchor(),
              SizedBox(height: 20),
              SingleChoice(),
              SizedBox(height: 20),
              _buildHeaderRow(),
              SizedBox(height: 20),
              _buildRangePointerExampleGauge(),
              _buildCartesianChart(),
              SizedBox(height: 20),
              Wrap(
                children: [
                  _buildCard(
                    title: 'money',
                    icon: Icons.grading_rounded,
                    value: '2000',
                    onTap: () => debugPrint('money Card tapped'),
                  ),
                  _buildCard(
                    title: 'excel',
                    icon: Icons.download_outlined,
                    value: '2000',
                    onTap: () => {print('excel tapped')},
                  ),
                  _buildAddMoreCard(context),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ElevatedButton(
          onPressed: () {},
          style: ElevatedButton.styleFrom(elevation: 0),
          child: Icon(Icons.arrow_back),
        ),
        Text(
          'Today',
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
    return _buildCard(
      title: 'add more',
      icon: Icons.grading_rounded,
      value: '+',
      onTap: () {
        showModalBottomSheet<void>(
          context: context,
          builder: (BuildContext context) {
            return _buildAddMoreSheet(context);
          },
        );
      },
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
                'Add more feature',
                style: TextStyle(fontSize: 20),
              ),
              _buildListTile('money', 'Select Date', Icons.check_rounded),
              _buildListTile(
                  'peak time', 'most people come here', Icons.check_rounded),
              _buildListTile(
                  'export excel', 'export data to excel', Icons.check_rounded),
              _buildListTile(
                  'export sheet', 'export data to sheet', Icons.check_rounded),
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

  SearchAnchor buildSearchAnchor() {
    return SearchAnchor(
        builder: (BuildContext context, SearchController controller) {
      return SearchBar(
        controller: controller,
        elevation: WidgetStateProperty.all(0),
        padding: const WidgetStatePropertyAll<EdgeInsets>(
            EdgeInsets.symmetric(horizontal: 16.0)),
        onTap: () {
          controller.openView();
        },
        onChanged: (_) {
          controller.openView();
        },
        leading: const Icon(
          Icons.psychology_alt_outlined,
          color: Colors.grey,
        ),
        hintText: 'Ask Gemini',
        trailing: <Widget>[
          Tooltip(
            message: 'Search for a statistic suggestion',
            child: IconButton(
              isSelected: isDark,
              onPressed: () {
                setState(() {
                  isDark = !isDark;
                });
              },
              icon: const Icon(Icons.search_outlined),
              selectedIcon: const Icon(Icons.brightness_2_outlined),
            ),
          )
        ],
      );
    }, suggestionsBuilder: (BuildContext context, SearchController controller) {
      return List<ListTile>.generate(5, (int index) {
        final String item = 'item $index';
        return ListTile(
          title: Text(item),
          onTap: () {
            setState(() {
              controller.closeView(item);
            });
          },
        );
      });
    });
  }

  Map<String, dynamic> getOrderCount(List<dynamic> data) {
    if (allorderSave.isEmpty) {
      Map<String, dynamic> allorders = {};

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

  /// Return the Cartesian Chart with Column series.
  SfCartesianChart _buildCartesianChart() {
    bool isCardView = false;
    return SfCartesianChart(
      plotAreaBorderWidth: 0,
      title: ChartTitle(
        text: isCardView ? '' : 'Internet Users - 2016',
      ),
      primaryXAxis: const CategoryAxis(
        majorGridLines: MajorGridLines(width: 0),
      ),
      primaryYAxis: const NumericAxis(
        minimum: 0,
        maximum: 80,
        isVisible: false,
        labelFormat: '{value}M',
      ),
      series: _buildColumnSeries(),
      tooltipBehavior: _tooltipBehavior,
    );
  }

  /// Returns the list of Cartesian Column series.
  List<ColumnSeries<ChartSampleData, String>> _buildColumnSeries() {
    return <ColumnSeries<ChartSampleData, String>>[
      ColumnSeries<ChartSampleData, String>(
        dataSource: _internetUsersDataIn2016,
        xValueMapper: (ChartSampleData data, int index) => data.x,
        yValueMapper: (ChartSampleData data, int index) => data.yValue,
        pointColorMapper: (ChartSampleData data, int index) => data.pointColor,
        dataLabelSettings: const DataLabelSettings(
          isVisible: true,
        ),
      ),
    ];
  }

  Widget _buildCard({
    required String title,
    String? value,
    IconData? icon,
    required VoidCallback onTap,
  }) {
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
                    Spacer(),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.trending_up_rounded,
                            size: 16,
                            color: Colors.green,
                          ),
                          const Text(
                            (' 5%'),
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
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

enum Calendar { day, week, month, year }

class SingleChoice extends StatefulWidget {
  const SingleChoice({super.key});

  @override
  State<SingleChoice> createState() => _SingleChoiceState();
}

class _SingleChoiceState extends State<SingleChoice> {
  Calendar calendarView = Calendar.day;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<Calendar>(
      segments: const <ButtonSegment<Calendar>>[
        ButtonSegment<Calendar>(
            value: Calendar.day,
            label: Text('Day'),
            icon: Icon(Icons.calendar_view_day)),
        ButtonSegment<Calendar>(
            value: Calendar.week,
            label: Text('Week'),
            icon: Icon(Icons.calendar_view_week)),
        ButtonSegment<Calendar>(
            value: Calendar.month,
            label: Text('Month'),
            icon: Icon(Icons.calendar_view_month)),
        ButtonSegment<Calendar>(
            value: Calendar.year,
            label: Text('Year'),
            icon: Icon(Icons.calendar_today)),
      ],
      selected: <Calendar>{calendarView},
      onSelectionChanged: (Set<Calendar> newSelection) {
        setState(() {
          // By default there is only a single segment that can be
          // selected at one time, so its value is always the first
          // item in the selected set.
          calendarView = newSelection.first;
        });
      },
    );
  }
}

SfRadialGauge _buildRangePointerExampleGauge() {
  bool isCardView = false;
  return SfRadialGauge(
    axes: <RadialAxis>[
      RadialAxis(
        showLabels: true,
        showTicks: false,
        startAngle: 270,
        endAngle: 270,
        radiusFactor: 0.8,
        axisLineStyle: const AxisLineStyle(
          thicknessUnit: GaugeSizeUnit.factor,
          thickness: 0.15,
        ),
        annotations: <GaugeAnnotation>[
          GaugeAnnotation(
            angle: 180,
            widget: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'today orders',
                  style: TextStyle(
                    fontFamily: 'Times',
                    fontSize: isCardView ? 18 : 22,
                    fontWeight: FontWeight.w400,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                Text(
                  ' / expect orders',
                  style: TextStyle(
                    fontFamily: 'Times',
                    fontSize: isCardView ? 18 : 22,
                    fontWeight: FontWeight.w400,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
        pointers: <GaugePointer>[
          RangePointer(
            value: 50,
            // cornerStyle: CornerStyle.bothCurve,
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
