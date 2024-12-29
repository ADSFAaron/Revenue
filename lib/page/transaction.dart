import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'addorder.dart';

class TransactionPage extends StatefulWidget {
  const TransactionPage({super.key});

  @override
  State<TransactionPage> createState() => _TransactionPageState();
}

class _TransactionPageState extends State<TransactionPage> {
  final User currentUser = FirebaseAuth.instance.currentUser!;
  late Future<Map<String, dynamic>> _storeDataFuture;
  late String storeID;

  @override
  void initState() {
    super.initState();
    _storeDataFuture = _loadStoreData();
  }

  Future<Map<String, dynamic>> _loadStoreData() async {
    try {
      // 取得使用者數據
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.email)
          .get();

      final userData = userDoc.data();

      if (userData == null || !userData.containsKey('storeID')) {
        throw Exception('User data or storeID is missing');
      }

      storeID = userData['storeID'];

      // 取得商店數據
      final storeDoc = await FirebaseFirestore.instance
          .collection('store')
          .doc(userData['storeID'])
          .get();

      final storeData = storeDoc.data();

      if (storeData == null) {
        throw Exception('Store data is missing');
      }

      return storeData;
    } catch (e) {
      if (kDebugMode) {
        print('Error loading store data: $e');
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _storeDataFuture,
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
            child: Text('No data available'),
          );
        }

        final stores = snapshot.data!;
        return _buildTransactionPage(stores);
      },
    );
  }

  Widget _buildTransactionPage(Map<String, dynamic> stores) {
    String currency = "NTD";
    String totalIncome = "${stores['totalIncome']}";

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddOrder(storeID),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Order'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 32.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Text(
                        "Today's Summary",
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    _buildCard(
                      title: 'Revenue',
                      icon: Icons.savings_rounded,
                      value:
                          "${totalIncome.length >= 10 ? totalIncome.substring(4) : totalIncome}",
                      onTap: () => debugPrint('Revenue Card tapped'),
                    ),
                    _buildCard(
                      title: 'Orders',
                      icon: Icons.grading_rounded,
                      value: stores['orderIndex'].toString(),
                      onTap: () => debugPrint('Orders Card tapped'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Column(
                  children: [
                    Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const SizedBox(width: 10),
                                Text(
                                  "Last Transactions",
                                  style: const TextStyle(fontSize: 20),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: () =>
                                      debugPrint('View All tapped'),
                                  child: const Text('View All'),
                                ),
                              ],
                            ),
                            ListView.separated(
                              shrinkWrap: true,
                              itemCount: 1,
                              itemBuilder: (context, index) {
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        Theme.of(context).splashColor,
                                    child: Text(
                                      "Aa".toUpperCase(),
                                    ),
                                  ),
                                  title: Text("Order No"),
                                  subtitle: Text("Transaction Time"),
                                );
                              },
                              separatorBuilder: (context, index) =>
                                  const Divider(),
                            ),
                          ],
                        ),
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
