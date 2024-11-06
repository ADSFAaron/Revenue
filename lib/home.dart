import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'main.dart';
import 'page/overview.dart';
import 'page/statistics.dart';
import 'page/store.dart';
import 'page/transaction.dart';

class LoginHomePage extends StatefulWidget {
  const LoginHomePage({super.key});

  @override
  State<LoginHomePage> createState() => _LoginHomePageState();
}

class _LoginHomePageState extends State<LoginHomePage> {
  int pageIndex = 0;

  final screens = [
    OverviewPage(),
    TransactionPage(),
    StatisticsPage(),
    StorePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(),
        child: NavigationBar(
          selectedIndex: pageIndex,
          onDestinationSelected: (index) => setState(() => pageIndex = index),
          animationDuration: Duration(milliseconds: 800),
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.grid_view_rounded),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: 'Overview',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_rounded),
              selectedIcon: Icon(Icons.bar_chart_rounded),
              label: 'Trans',
            ),
            NavigationDestination(
              icon: Icon(Icons.analytics_rounded),
              selectedIcon: Icon(Icons.analytics_rounded),
              label: 'Stats',
            ),
            NavigationDestination(
              icon: Icon(Icons.storefront_rounded),
              selectedIcon: Icon(Icons.storefront_rounded),
              label: 'Store',
            ),
          ],
        ),
      ),
      body: screens[pageIndex],
    );
  }
}
