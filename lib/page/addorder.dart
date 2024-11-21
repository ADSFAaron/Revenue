import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AddOrder extends StatefulWidget {
  final String storeId;
  final Map<String, dynamic>? origin;

  const AddOrder(this.storeId, {super.key, this.origin});

  @override
  _AddOrderState createState() => _AddOrderState();
}

class _AddOrderState extends State<AddOrder> {
  DateTime _pickDate = DateTime.now();
  final _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _menuList = [];
  int _totalCount = 0;
  String _paymentMethod = 'Cash'; // Default payment method
  int _taxRate = 0;

  @override
  void initState() {
    super.initState();
    _pickDate = widget.origin?['time']?.toDate() ?? DateTime.now();
  }

  Future<void> _selectDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _pickDate,
      firstDate: DateTime.now().subtract(Duration(days: 365 * 5)),
      lastDate: DateTime.now().add(Duration(days: 365 * 5)),
    );

    if (date != null) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_pickDate),
      );

      if (time != null) {
        setState(() {
          _pickDate =
              DateTime(date.year, date.month, date.day, time.hour, time.minute);
        });
      }
    }
  }

  void _updateItemCount(int index, bool isIncreasing) {
    setState(() {
      final price = int.parse(_menuList[index]['price'].toString());
      _menuList[index]['amount'] += isIncreasing ? 1 : -1;
      _totalCount += isIncreasing ? price : -price;
    });
  }

  void _submitOrder(Map<String, dynamic> storeInfo) {
    final validOrderList =
        _menuList.where((item) => item['amount'] > 0).toList();
    final total = validOrderList.fold(
        0,
        (sum, item) =>
            sum +
            (int.parse(item['price'].toString()) *
                int.parse(item['amount'].toString())));

    if (validOrderList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Row(
            children: const [
              Icon(Icons.warning_outlined, color: Colors.white),
              Text('   No items in order!'),
            ],
          ),
        ),
      );
      return;
    }

    _processFirebaseOrder(storeInfo, validOrderList, total);
  }

  void _processFirebaseOrder(
      Map<String, dynamic> storeInfo, List<dynamic> orderList, int total) {
    final orderRef = _firestore.collection('tmporder').doc(widget.storeId);

    orderRef.get().then((snapshot) {
      if (snapshot.exists) {
        _updateExistingOrder(snapshot.data()!, orderList, total);
      } else {
        _createNewOrder(orderList, total);
      }
      _showSuccessSnackBar();
      _resetOrderState(storeInfo, total);
    }).catchError((error) => print('Order submission error: $error'));
  }

  void _updateExistingOrder(
      Map<String, dynamic> data, List<dynamic> orderList, int total) {
    if (widget.origin != null) {
      final orders = data['orders'] as List<dynamic>;
      final index =
          orders.indexWhere((order) => order['no'] == widget.origin!['no']);
      if (index != -1) {
        orders[index] = {
          "details": orderList,
          "time": _pickDate,
          "no": widget.origin!['no'],
          "total": total
        };
      }
      _firestore
          .collection('tmporder')
          .doc(widget.storeId)
          .update({'orders': orders});
    } else {
      _firestore.collection('tmporder').doc(widget.storeId).update({
        'orders': FieldValue.arrayUnion([
          {
            "details": orderList,
            "time": _pickDate,
            "no": data['orderIndex'],
            "total": total
          }
        ])
      });
    }
  }

  void _createNewOrder(List<dynamic> orderList, int total) {
    _firestore.collection('tmporder').doc(widget.storeId).set({
      'orders': [
        {
          "details": orderList,
          "time": _pickDate,
          "no": widget.origin?['no'] ?? 0,
          "total": total
        }
      ]
    });
  }

  void _showSuccessSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 1),
        content: Row(
          children: const [
            Icon(Icons.check, color: Colors.white),
            Text('   Order added!'),
          ],
        ),
      ),
    );
  }

  void _resetOrderState(Map<String, dynamic> storeInfo, int total) {
    setState(() {
      _totalCount = 0;
      _menuList.clear();
    });

    if (widget.origin == null) {
      _firestore.collection('store').doc(widget.storeId).update({
        "orderIndex": storeInfo['orderIndex'] + 1,
        "totalIncome": storeInfo['totalIncome'] + total
      });
    }

    if (widget.origin != null) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.origin == null ? 'Add Order' : 'Edit Order')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _firestore.collection('store').doc(widget.storeId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final stores = snapshot.data!.data() as Map<String, dynamic>;

          if (_menuList.isEmpty) {
            _menuList = _initializeMenuList(stores, widget.origin);
          }

          return _buildOrderContent(stores);
        },
      ),
    );
  }

  List<Map<String, dynamic>> _initializeMenuList(
      Map<String, dynamic> stores, Map<String, dynamic>? origin) {
    var menuList = (stores['menu'] as List)
        .map((item) => Map<String, dynamic>.from(item)..['amount'] = 0)
        .toList();

    if (origin != null) {
      final originDetails = origin['details'] as List<dynamic>;
      final detailMap = {for (var d in originDetails) d['name']: d};

      for (var m in menuList) {
        if (detailMap.containsKey(m['name'])) {
          m['amount'] = detailMap[m['name']]['amount'];
        }
      }
      _totalCount = origin['total'];
    }

    return menuList;
  }

  Widget _buildOrderContent(Map<String, dynamic> stores) {
    final addOrderButtonName = widget.origin == null ? "增加訂單" : "修改訂單";

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildDatePicker(),
          SizedBox(height: 20),
          _buildMenuList(),
          Spacer(),
          _buildTotalAndSubmitSection(addOrderButtonName, stores),
        ],
      ),
    );
  }

  Widget _buildDatePicker() {
    return ListTile(
      title: Text("${_pickDate.year} / ${_pickDate.month} / ${_pickDate.day}\n"
          "${_pickDate.hour.toString().padLeft(2, '0')}:${_pickDate.minute.toString().padLeft(2, '0')}"),
      leading: const Icon(Icons.calendar_today),
      onTap: _selectDateTime,
    );
  }

  Widget _buildMenuList() {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.5,
      child: ListView.separated(
        itemBuilder: (context, index) => _buildMenuItemCard(index),
        itemCount: _menuList.length,
        separatorBuilder: (context, index) => const Divider(),
      ),
    );
  }

  Widget _buildMenuItemCard(int index) {
    return ListTile(
      title: Text(
        _menuList[index]['name'].toString(),
        style: const TextStyle(fontSize: 16),
      ),
      subtitle: Text(
        'NTD ${_menuList[index]['price']}',
        style: const TextStyle(fontSize: 14),
      ),
      leading: Icon(_menuList[index]['icon'] ?? Icons.restaurant_rounded),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: () => _updateItemCount(index, false),
          ),
          SizedBox(width: 4),
          Text(_menuList[index]['amount'].toString(),
              style: const TextStyle(fontSize: 16)),
          SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _updateItemCount(index, true),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalAndSubmitSection(
      String addOrderButtonName, Map<String, dynamic> stores) {

    List<Map<String, dynamic>> paymentMethods = [
      {'label': 'Cash', 'icon': Icons.money_rounded},
      {'label': 'Credit Card', 'icon': Icons.credit_card_rounded},
      {'label': 'Line Pay', 'icon': Icons.contactless_rounded},
    ];

    List<Widget> buttonList = List.generate(
      paymentMethods.length,
          (index) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            IconButton(
              onPressed: () {
                setState(() {
                  _paymentMethod = paymentMethods[index]['label'];
                });
                Navigator.pop(context);
              },
              icon: Icon(paymentMethods[index]['icon']),
            ),
            Text(paymentMethods[index]['label']),
          ],
        ),
      ),
    );


    return Column(
      children: [
        ListTile(
          title: Text(
            'Payment Method: $_paymentMethod',
            style: const TextStyle(fontSize: 16),
          ),
          leading: const Icon(Icons.payments_rounded),
          trailing: const Icon(Icons.arrow_forward_rounded),
          onTap: () {
            // Payment choosing use bottom sheet
            showModalBottomSheet<void>(
              showDragHandle: true,
              context: context,
              builder: (context) {
                return SizedBox(
                  height: 150,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: ListView(
                      shrinkWrap: true,
                      scrollDirection: Axis.horizontal,
                      children: buttonList,
                    ),
                  ),
                );
              },
            );
          },
        ),
        ListTile(
          title: Text("Included tax: $_taxRate%"),
          leading: const Icon(Icons.euro_rounded),
        ),
        ListTile(
          title: Text(
            'Total: NTD $_totalCount',
            style: const TextStyle(fontSize: 16),
          ),
          leading: const Icon(Icons.attach_money),
          trailing: FilledButton.tonalIcon(
            onPressed: () => _submitOrder(stores),
            label: Text(addOrderButtonName),
            icon: const Icon(Icons.check_rounded),
          ),
        ),
      ],
    );
  }
}
