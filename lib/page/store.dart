import 'package:Revenue/settings/app_settings.dart';
import 'package:Revenue/settings/store_settings.dart';
import 'package:Revenue/settings/user_settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class StorePage extends StatefulWidget {
  const StorePage({super.key});

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
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
        return _buildStorePage(stores);
      },
    );
  }

  Widget _buildStorePage(Map<String, dynamic> stores) {
    String currency = "NTD";
    String totalIncome = "${stores['totalIncome']}";
    List<String> users = ["user1", "user2", "user3"];
    // String storeName = stores['name'];
    // String storeID = stores['id'];
    print(stores);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Page'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: <Widget>[
              Card(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 10),
                          Text(
                            stores['name'],
                            style: const TextStyle(
                                fontSize: 28, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => StoreSettings(stores['id']),
                                  ),
                                );
                              }, child: const Text('Edit'))
                        ],
                      ),
                      SizedBox(height: 10),
                      ListView.separated(
                        shrinkWrap: true,
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue,
                              child: const Text('AH'),
                            ),
                            title: Text(users[index]),
                            subtitle: const Text('Manager'),
                          );
                        },
                        separatorBuilder: (BuildContext context, int index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 0.0, horizontal: 16),
                            child: const Divider(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _buildCard(
                    color: const Color(0xff95eeb3),
                    title: 'Assets',
                    value: totalIncome.length >= 10
                        ? totalIncome.substring(4)
                        : totalIncome,
                    onTap: () => debugPrint('Assets Card tapped'),
                  ),
                  _buildCard(
                    color: const Color(0xffFDBE90),
                    title: 'Store',
                    icon: Icons.storefront_outlined,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => StoreSettings(storeID),
                        ),
                      );
                    },
                  ),
                  _buildCard(
                    color: const Color.fromARGB(255, 97, 213, 224),
                    title: 'User Settings',
                    icon: Icons.manage_accounts_outlined,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              UserSettings(currentUser.email!),
                        ),
                      );
                    },
                  ),
                  _buildCard(
                    color: const Color.fromARGB(255, 90, 209, 227),
                    title: 'App Settings',
                    icon: Icons.info_outline,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AppSettings(storeID),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard({
    required Color color,
    required String title,
    String? value,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return Card(
      color: color,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: MediaQuery.of(context).size.width / 2 - 30,
          height: MediaQuery.of(context).size.height/7,
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(48),
                      ),
                      height: 48,
                      width: 48,
                      child: Icon(
                          icon
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(title),

                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      value ?? '',
                      style: const TextStyle(fontSize: 24),
                    ),
                  ],
                ),
                // if (icon != null)
                //   Icon(
                //     icon,
                //     size: 40,
                //   )
                // else if (value != null)
                //   Text(
                //     value,
                //     style: const TextStyle(fontSize: 20),
                //   ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
