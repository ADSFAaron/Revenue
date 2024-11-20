import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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
  final User currentUser = FirebaseAuth.instance.currentUser!;
  late Future<Map<String, dynamic>> _userDataFuture;
  late String _timeString;

  @override
  void initState() {
    super.initState();
    _userDataFuture = _fetchUserData();
    _timeString = _formatDateTime(DateTime.now());
    Timer.periodic(const Duration(minutes: 1), (timer) {
      setState(() {
        _timeString = _formatDateTime(DateTime.now());
      });
    });
  }

  Future<Map<String, dynamic>> _fetchUserData() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.email)
          .get();

      final userData = userDoc.data();
      if (userData == null) {
        throw Exception("User data not found");
      }
      return userData;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching user data: $e');
      }
      rethrow;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('yyyy/MM/dd\nH:mm').format(dateTime);
  }

  String _getGreeting(DateTime now) {
    if (now.hour >= 6 && now.hour <= 12) {
      return "Good Morning";
    } else if (now.hour >= 13 && now.hour <= 18) {
      return "Good Afternoon";
    } else if (now.hour >= 19 && now.hour <= 23) {
      return "Good Evening";
    } else {
      return "Good Night";
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _userDataFuture,
      builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        } else if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}'),
          );
        } else if (!snapshot.hasData) {
          return const Center(
            child: Text('No user data available'),
          );
        }

        final userData = snapshot.data!;
        final String greeting = "${_getGreeting(DateTime.now())}, ${userData['name']}";

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddOrder(userData['storeID']),
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Order'),
          ),
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(greeting, _timeString),
                const SizedBox(height: 20),
                Expanded(
                  child: Center(
                    child: const Text(
                      'Home',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(String greeting, String time) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            greeting,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            time,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }
}
