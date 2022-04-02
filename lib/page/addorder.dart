// import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class AddOrder extends StatefulWidget {
  final String storeId;
  const AddOrder(this.storeId);

  @override
  State<AddOrder> createState() => _AddOrderState();
}

class _AddOrderState extends State<AddOrder> {
  DateTime pickDate = DateTime.now(); // 讓使用者可以選取時間
  GlobalKey<FormState> formKey = GlobalKey<FormState>(); // 取得表單選取內容
  late Map<String, dynamic> users, stores;
  int totalCount = 0;
  List<dynamic> menuList = [];

  void _pickDate() async {
    DateTime? date = await showDatePicker(
        context: context,
        initialDate: pickDate,
        firstDate: DateTime(DateTime.now().year - 5),
        lastDate: DateTime(DateTime.now().year + 5));

    if (date != null) {
      setState(() {
        pickDate = date;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add Order'),
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection('store')
            .where(widget.storeId)
            .snapshots(),
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (!snapshot.hasData) {
            return Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }

          // Get Data from Firestore
          snapshot.data!.docs.forEach((DocumentSnapshot document) {
            stores = document.data() as Map<String, dynamic>;
          });

          if (menuList.isEmpty) {
            menuList = stores['menu'];
            for (int i = 0; i < menuList.length; i++) {
              menuList[i] = menuList[i] as Map<String, dynamic>;
              menuList[i]['amount'] = 0;
            }

            print(menuList);
          }

          // per Row content
          return SizedBox(
            height: MediaQuery.of(context).size.height,
            child: SafeArea(
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: ListTile(
                      title: Text(
                          "日期 :  ${pickDate.year}  / ${pickDate.month}  / ${pickDate.day}"),
                      trailing: Icon(
                        Icons.calendar_today,
                        color: Colors.grey[700],
                      ),
                      onTap: _pickDate,
                    ),
                  ),
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.65,
                    child: ListView.separated(
                      itemBuilder: (BuildContext context, int index) {
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 30, vertical: 10),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  flex: 1,
                                  child: Icon(Icons.account_circle_outlined),
                                ),
                                Spacer(
                                  flex: 1,
                                ),
                                Expanded(
                                  flex: 5,
                                  child: Text(
                                    menuList[index]['name'].toString(),
                                    style: TextStyle(fontSize: 16),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Center(
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.remove,
                                      ),
                                      onPressed: () {
                                        if (menuList[index]['amount'] > 0) {
                                          setState(() {
                                            menuList[index]['amount']--;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: Text(
                                        menuList[index]['amount'].toString()),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: IconButton(
                                      onPressed: () {
                                        setState(() {
                                          menuList[index]['amount']++;
                                        });
                                      },
                                      icon: const Icon(Icons.add),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      itemCount: menuList.length,
                      separatorBuilder: (BuildContext context, int index) {
                        return const Divider(
                          height: 0.5,
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.1,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 6,
                            child: Container(
                              child: Center(
                                child: RichText(
                                  text: TextSpan(
                                    text: "小計 : ",
                                    style: TextStyle(
                                        color: Colors.black, fontSize: 16),
                                    children: <TextSpan>[
                                      TextSpan(
                                        text: ' NTD ${totalCount.toString()}',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              decoration: BoxDecoration(
                                // 背景
                                color: Colors.white,
                                // 設定圓角
                                borderRadius:
                                    BorderRadius.all(Radius.circular(36.0)),
                                // 設定邊框
                                // border: new Border.all(width: 1, color: Colors.black38),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.16),
                                    spreadRadius: 5,
                                    blurRadius: 7,
                                    offset: Offset(
                                        0, 3), // changes position of shadow
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Spacer(
                            flex: 1,
                          ),
                          Expanded(
                            flex: 4,
                            child: ConstrainedBox(
                              constraints: BoxConstraints.tightFor(
                                  width: 200, height: 200),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  shape: const StadiumBorder(),
                                ),
                                child: Text("增加訂單",
                                    style: TextStyle(fontSize: 16)),
                                onPressed: () {
                                  updateOrderToFirebase();
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void updateOrderToFirebase() {}
}
