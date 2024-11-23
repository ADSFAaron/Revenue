import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
      return "☀️ Morning";
    } else if (now.hour >= 13 && now.hour <= 18) {
      return "🌻 Afternoon";
    } else if (now.hour >= 19 && now.hour <= 23) {
      return "Evening";
    } else {
      return "🌝 Night";
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _userDataFuture,
      builder:
          (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
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
        final String greeting =
            "${_getGreeting(DateTime.now())}, ${userData['name']}";

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
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(greeting, _timeString),
                  const SizedBox(height: 20),
                  Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 32),
                      child: Column(
                        children: [
                          ListTile(
                            onTap: () {
                              SnackBar snackBar = SnackBar(
                                content:
                                    Text('Store ID: ${userData['storeID']}'),
                              );
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(snackBar);
                            },
                            title: const Text('Total Property'),
                            leading: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).splashColor,
                                borderRadius: BorderRadius.circular(48),
                              ),
                              height: 48,
                              width: 48,
                              child: Icon(Icons.shopping_bag_rounded,
                                  color: Theme.of(context).iconTheme.color),
                            ),
                            trailing: IconButton.outlined(
                              icon: const Icon(Icons.arrow_forward_ios_rounded,
                                  size: 16),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Theme.of(context).primaryColor,
                                side: const BorderSide(color: Colors.grey),
                              ),
                              onPressed: () {
                                SnackBar snackBar = SnackBar(
                                  content: Text(
                                      'Navigate to Transaction Page with store ID: ${userData['storeID']}'),
                                );
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(snackBar);
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Row(
                              children: [
                                const Text('NTD '),
                                Text(
                                  '12345',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 28,
                                  ),
                                ),
                                SizedBox(width: 16),
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
                                SizedBox(width: 8),
                                Text(
                                  'Last month 1234',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 32),
                      child: Column(
                        children: [
                          ListTile(
                            onTap: () {
                              SnackBar snackBar = SnackBar(
                                content:
                                    Text('Store ID: ${userData['storeID']}'),
                              );
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(snackBar);
                            },
                            title: const Text('Number of Sales'),
                            leading: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).splashColor,
                                borderRadius: BorderRadius.circular(48),
                              ),
                              height: 48,
                              width: 48,
                              child: Icon(Icons.shopping_bag_rounded,
                                  color: Theme.of(context).iconTheme.color),
                            ),
                            trailing: IconButton.outlined(
                              icon: const Icon(Icons.arrow_forward_ios_rounded,
                                  size: 16),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Theme.of(context).primaryColor,
                                side: const BorderSide(color: Colors.grey),
                              ),
                              onPressed: () {
                                SnackBar snackBar = SnackBar(
                                  content: Text(
                                      'Navigate to Transaction Page with store ID: ${userData['storeID']}'),
                                );
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(snackBar);
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Row(
                              children: [
                                Text(
                                  '12345',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 28,
                                  ),
                                ),
                                SizedBox(width: 16),
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
                                SizedBox(width: 8),
                                Text(
                                  'Last month 1234',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(String greeting, String time) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                greeting,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Explore information and activity \nabout your store',
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
