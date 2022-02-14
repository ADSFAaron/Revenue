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

          // per Row content
          return Column(
            children: <Widget>[
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Container(
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
              ),
              Form(
                key: formKey,
                child: ListView.separated(
                    itemBuilder: (context, index) => ListTile(
                          leading: Icon(Icons.event_seat_rounded),
                          title: Text("test"),
                          subtitle: Text("subtitle"),
                        ),
                    separatorBuilder: (context, index) => Divider(),
                    itemCount: 10),
              ),
            ],
          );
        },
      ),
    );
  }
}
