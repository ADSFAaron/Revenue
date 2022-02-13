// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_database/firebase_database.dart';
// import 'package:flutter/material.dart';

// class AddCart extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: FavoriteWidget(),
//     );
//   }
// }

// class FavoriteWidget extends StatefulWidget {
//   @override
//   _FavoriteWidgetState createState() => _FavoriteWidgetState();
// }

// class _FavoriteWidgetState extends State<FavoriteWidget> {
//   List<dynamic> menu = [];
//   var menuAmount = <int>[];
//   var FormKey = GlobalKey<FormState>();
//   DateTime pickDate = DateTime.now();
//   final fb = FirebaseDatabase.instance;
//   int totalCount = 0;

//   @override
//   void initState() {
//     super.initState();
//     pickDate = DateTime.now();
//   }

//   void calculateTotal() {
//     totalCount = 0;
//     for (int i = 0; i < menuAmount.length; i++) {
//       if (menuAmount[i] != 0) {
//         setState(() {
//           totalCount += (menu[i]['price'] * menuAmount[i]);
//         });
//       }
//     }
//   }

//   void addCount(int index) {
//     setState(() {
//       menuAmount[index]++;
//     });
//     calculateTotal();
//   }

//   void minusCount(int index) {
//     setState(() {
//       if (menuAmount[index] > 0) {
//         menuAmount[index]--;
//       }
//     });
//     calculateTotal();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return new Scaffold(
//       body: StreamBuilder(
//         stream: FirebaseFirestore.instance.collection('store').snapshots(),
//         builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
//           if (!snapshot.hasData) {
//             return Center(
//               child: CircularProgressIndicator(),
//             );
//           }

//           var docs = snapshot.data.docs.map((doc) => doc['Menu']);

//           if (menu == null) {
//             menu = docs.first;
//             menuAmount = new List(menu.length);

//             for (int i = 0; i < menu.length; i++) {
//               menuAmount[i] = 0;
//             }
//           }

//           return Column(
//             children: [
//               Container(
//                 height: MediaQuery.of(context).size.height / 12,
//                 child: ListTile(
//                   title: Text(
//                       "日期： ${pickDate.year} / ${pickDate.month} / ${pickDate.day}"),
//                   trailing: Icon(
//                     Icons.event,
//                     color: Colors.black,
//                   ),
//                   onTap: _pickDate,
//                 ),
//               ),
//               Container(
//                 height: MediaQuery.of(context).size.height / 13 * 9,
//                 child: Form(
//                   key: FormKey,
//                   child: ListView.separated(
//                     itemCount: menu.length,
//                     itemBuilder: (context, index) {
//                       // print(docsItem[index]['name'].toString());

//                       return Card(
//                         child: Padding(
//                           padding: const EdgeInsets.all(8.0),
//                           child: Row(
//                             children: <Widget>[
//                               Container(
//                                 width: MediaQuery.of(context).size.width / 2,
//                                 child: Text(
//                                   menu[index]['name'],
//                                   style: TextStyle(
//                                     fontSize: 16,
//                                   ),
//                                 ),
//                               ),
//                               IconButton(
//                                 icon: Icon(Icons.remove),
//                                 onPressed: () {
//                                   minusCount(index);
//                                 },
//                               ),
//                               new Text(
//                                 '${menuAmount[index]}',
//                               ),
//                               IconButton(
//                                 icon: Icon(Icons.add),
//                                 onPressed: () {
//                                   addCount(index);
//                                   print("IconButton: " + menuAmount.toString());
//                                 },
//                               ),
//                             ],
//                             mainAxisAlignment: MainAxisAlignment.center,
//                           ),
//                         ),
//                         margin: EdgeInsets.symmetric(horizontal: 10.0),
//                         shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(15.0),
//                         ),
//                       );
//                     },
//                     separatorBuilder: (context, index) {
//                       return SizedBox(
//                         height: 10,
//                       );
//                     },
//                   ),
//                 ),
//               ),
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceAround,
//                 crossAxisAlignment: CrossAxisAlignment.center,
//                 children: [
//                   SizedBox(
//                     width: MediaQuery.of(context).size.width / 2,
//                     height: MediaQuery.of(context).size.height / 12,
//                     child: Container(
//                       child: Center(
//                         child: RichText(
//                           text: TextSpan(
//                             text: "小計 ： ",
//                             style: TextStyle(color: Colors.black, fontSize: 16),
//                             children: <TextSpan>[
//                               TextSpan(
//                                   text: ' NTD ${totalCount.toString()}',
//                                   style: TextStyle(color: Colors.red)),
//                             ],
//                           ),
//                         ),
//                       ),
//                       decoration: new BoxDecoration(
//                         // 背景
//                         color: Colors.white,
//                         // 設定圓角
//                         borderRadius: BorderRadius.all(Radius.circular(36.0)),
//                         // 設定邊框
//                         // border: new Border.all(width: 1, color: Colors.black38),
//                         boxShadow: [
//                           BoxShadow(
//                             color: Colors.grey.withOpacity(0.16),
//                             spreadRadius: 5,
//                             blurRadius: 7,
//                             offset: Offset(0, 3), // changes position of shadow
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                   SizedBox(
//                       width: MediaQuery.of(context).size.width / 3,
//                       height: MediaQuery.of(context).size.height / 12,
//                       child: ElevatedButton(
//                           child: Text("增加訂單", style: TextStyle(fontSize: 16)),
//                           style: ButtonStyle(
//                             shape: MaterialStateProperty.all<
//                                 RoundedRectangleBorder>(
//                               RoundedRectangleBorder(
//                                 borderRadius: BorderRadius.circular(36.0),
//                               ),
//                             ),
//                           ),
//                           onPressed: () {
//                             updateCart2Firebase();
//                           })
//                       // child: ElevatedButton.icon(
//                       //   onPressed: () {
//                       //
//                       //   },
//                       //   icon: const Icon(Icons.note_add),
//                       //   label: Text('增加訂單'),
//                       // ),
//                       ),
//                 ],
//               )
//             ],
//           );
//         },
//       ),
//       backgroundColor: Colors.white60,
//       // floatingActionButton: _floatCheckButton(context),
//     );
//   }

//   _pickDate() async {
//     DateTime date = await showDatePicker(
//         context: context,
//         initialDate: pickDate,
//         firstDate: DateTime(DateTime.now().year - 5),
//         lastDate: DateTime(DateTime.now().year + 5));

//     if (date != null) {
//       setState(() {
//         pickDate = date;
//       });
//     }
//   }

//   Widget _floatCheckButton(BuildContext context) {
//     return FloatingActionButton.extended(
//       onPressed: () {
//         updateCart2Firebase();
//       },
//       label: Text('Total:'),
//       icon: const Icon(Icons.note_add),
//     );
//   }

//   updateCart2Firebase() {
//     print("Updating Cart");

//     // final isValid = FormKey.currentState.validate();
//     // FormKey.currentState.save();
//     // updateMenu2Firebase();
//     final ref = fb.reference();
//     var dateStr = pickDate.year.toString() +
//         "-" +
//         pickDate.month.toString() +
//         "-" +
//         pickDate.day.toString();

//     var originData;

//     DatabaseReference databaseReference = ref.child("yuyuan");

//     databaseReference.once().then((DataSnapshot data) {
//       // 判斷這日期是否有出現過
//       if (data.value[dateStr] == null) {
//         databaseReference.child(dateStr).set(dateStr).asStream();
//       } else {
//         // 有出現過就取得之前的資料
//         originData = data.value[dateStr];
//       }

//       // 確認有哪幾筆資料要新增
//       int totalNeedAdd = 0;
//       int currentAdd = 0;
//       for (int i = 0; i < menuAmount.length; i++) {
//         if (menuAmount[i] != 0) {
//           totalNeedAdd++;
//         }
//       }

//       // 所有的菜單
//       for (int i = 0; i < menuAmount.length; i++) {
//         // 有需要新增資料
//         if (menuAmount[i] != 0) {
//           currentAdd++;
//           // Original Amount
//           var originAmount;
//           if (originData != null && originData.containsKey(menu[i]['name'])) {
//             originAmount = originData[menu[i]['name']];
//           }

//           // print("originalAmount : " + originAmount.toString());

//           var amount = 0;
//           if (originAmount is int) {
//             amount = originAmount;
//           }

//           // print(menu[i]['name'] + ' Original: ' + originAmount.toString());
//           DatabaseReference addItemDR = ref.child('yuyuan').child(dateStr);
//           if (addItemDR == null) {
//             ref.child('yuyuan').set(dateStr);
//             addItemDR = ref.child('yuyuan').child(dateStr);
//           }

//           addItemDR
//               .child(menu[i]['name'].toString())
//               .set(amount + menuAmount[i])
//               .then((value) {
//             if (currentAdd == totalNeedAdd) {
//               final snackBar = SnackBar(
//                 content: Text('新增成功!'),
//               );
//               // Show SnackBar.
//               ScaffoldMessenger.of(context).showSnackBar(snackBar);
//               currentAdd++;

//               // 清除欄位中的資料
//               for (int i = 0; i < menuAmount.length; i++) {
//                 setState(() {
//                   menuAmount[i] = 0;
//                 });
//               }

//               // 清除增加訂單金額
//               setState(() {
//                 totalCount = 0;
//               });
//             }
//           }).onError((error, stackTrace) {
//             final snackBar = SnackBar(
//               content: Text('新增失敗, 原因:' + error),
//             );

//             // Show SnackBar.
//             ScaffoldMessenger.of(context).showSnackBar(snackBar);
//           }).asStream();

//           print(menu[i]['name'].toString() +
//               " After: " +
//               (amount + menuAmount[i]).toString());
//         }
//       }
//     });
//   }
// }
