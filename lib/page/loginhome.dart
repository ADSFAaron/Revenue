import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import 'addorder.dart';

class HomeContentPage extends StatefulWidget {
  @override
  State<HomeContentPage> createState() => _HomeContentPageState();
}

class _HomeContentPageState extends State<HomeContentPage> {
  DateTime now = DateTime.now();
  String _timeString = "";
  User currentUser = FirebaseAuth.instance.currentUser!;
  late Map<String, dynamic> users, stores;
  final Stream<QuerySnapshot> _storesStream =
      FirebaseFirestore.instance.collection('store').snapshots();

  String greetingText() {
    String greeting = "";

    if (now.hour >= 6 && now.hour <= 12) {
      greeting = "Good Morning";
    } else if (now.hour >= 13 && now.hour <= 18) {
      greeting = "Good Afternoon";
    } else if (now.hour >= 19 && now.hour <= 23) {
      greeting = "Good Evening";
    } else {
      greeting = "Good Night";
    }

    return greeting;
  }

  // Future<void> getUserData(DocumentReference userRef) async {
  //   Map<String, dynamic> result;

  //   userRef.get().then((value) {
  //     result = value.data() as Map<String, dynamic>;

  //     setState(() {
  //       user = result;
  //     });
  //   });
  // }

  // Future<void> getStoreData(String storeId) async {
  //   Map<String, dynamic> result;

  //   FirebaseFirestore.instance
  //       .collection("store")
  //       .doc(storeId)
  //       .get()
  //       .then((value) {
  //     result = value.data() as Map<String, dynamic>;

  //     setState(() {
  //       store = result;
  //     });
  //   });
  // }

  void _getTime() {
    final DateTime now = DateTime.now();
    final String formattedDateTime = _formatDateTime(now);
    setState(() {
      _timeString = formattedDateTime;
    });
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('yyyy/MM/dd\nH:mm').format(dateTime);
  }

  @override
  void initState() {
    _timeString = _formatDateTime(DateTime.now());
    Timer.periodic(Duration(minutes: 1), (Timer t) => _getTime());

    super.initState();

    // Get User Data
    // FirebaseFirestore firestore = FirebaseFirestore.instance;
    // CollectionReference usersDB = firestore.collection('users');
    // DocumentReference userRef = usersDB.doc(currentUser.email);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where(currentUser.email!)
            .snapshots(),
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(),
            );
          }
          String greet = "";
          snapshot.data!.docs.forEach((DocumentSnapshot document) {
            users = document.data() as Map<String, dynamic>;

            greet = greetingText() + ", " + users['name'];
          });

          return Scaffold(
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => AddOrder(users['storeID'])),
                );
              },
              icon: Icon(Icons.add),
              label: Text('Add Order'),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8.0, vertical: 16.0),
                          child: Text(
                            greet,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          _timeString,
                          textAlign: TextAlign.end,
                        ),
                      ],
                    ),
                  ),
                  Center(
                    child: Text(
                      'HOme',
                    ),
                  ),
                ],
              ),
            ),
          );
        });
  }
}
