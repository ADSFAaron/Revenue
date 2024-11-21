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
    print(stores);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                _buildStoreCard(stores),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    _buildCard(
                      title: 'Revenue',
                      icon: Icons.savings_rounded,
                      value:
                          "$currency ${totalIncome.length >= 10 ? totalIncome.substring(4) : totalIncome}",
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
                _buildListTile(
                  title: 'Store Settings',
                  subtitle: 'Menu editing, History orders',
                  icon: Icons.storefront_outlined,
                  onTap: () => _navigateTo(context, StoreSettings(storeID)),
                ),
                _buildListTile(
                  title: 'User Settings',
                  subtitle: 'User name, Change password',
                  icon: Icons.manage_accounts_outlined,
                  onTap: () =>
                      _navigateTo(context, UserSettings(currentUser.email!)),
                ),
                _buildListTile(
                  title: 'App Settings',
                  subtitle: 'App version, Privacy policy, Feedback',
                  icon: Icons.info_outline,
                  onTap: () => _navigateTo(context, AppSettings(storeID)),
                ),
                _buildListTile(
                  title: 'Logout',
                  icon: Icons.logout_outlined,
                  onTap: () => FirebaseAuth.instance.signOut(),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStoreCard(Map<String, dynamic> stores) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
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
                  onPressed: () => _navigateTo(context, StoreSettings(storeID)),
                  child: const Text('Edit'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ListView.separated(
              shrinkWrap: true,
              itemCount: stores['users'].length,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).splashColor,
                    child: Text(
                      stores['users2'][index]['name']
                          .substring(0, 2)
                          .toUpperCase(),
                    ),
                  ),
                  title: Text(stores['users2'][index]['mail']),
                  subtitle: Text(stores['users2'][index]['role']),
                );
              },
              separatorBuilder: (context, index) => const Divider(),
            ),
          ],
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
          height: MediaQuery.of(context).size.height / 7,
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      value ?? '',
                      style: const TextStyle(fontSize: 24),
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

  Widget _buildListTile({
    required String title,
    String? subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      leading: Icon(icon),
      onTap: onTap,
    );
  }

  void _navigateTo(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }
}
