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
    final icons = [
      Icons.grid_view_rounded,
      Icons.bar_chart_rounded,
      Icons.analytics_rounded,
      Icons.storefront_rounded,
    ];

    final labels = ['Overview', 'Trans', 'Stats', 'Store'];

    return Scaffold(
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(indicatorColor: Theme.of(context).colorScheme.onPrimaryContainer),
        child: NavigationBar(
          selectedIndex: pageIndex,
          onDestinationSelected: (index) => setState(() => pageIndex = index),
          animationDuration: Duration(milliseconds: 800),
          destinations: List.generate(icons.length, (index) {
            return NavigationDestination(
              icon: Icon(icons[index]),
              selectedIcon: Icon(icons[index], color: Theme.of(context).colorScheme.onPrimary),
              label: labels[index],
            );
          }),
        ),
      ),
      body: screens[pageIndex],
    );
  }
}
