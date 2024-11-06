import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import 'addorder.dart';

class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
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
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.email)
            .snapshots(),
        builder:
            (BuildContext context, AsyncSnapshot<DocumentSnapshot> snapshot) {
          if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(),
            );
          }
          String greet = "";
          print(currentUser.email);
          if (snapshot.hasData) {
            print(snapshot.data?.data());
          }
          print(snapshot.data);
          users = snapshot.data?.data() as Map<String, dynamic>;

          greet = "${greetingText()}, " + users['name'];

          return Scaffold(
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => AddOrder(users['storeID'])),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Order'),
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
