import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'main.dart';
import 'page/loginhome.dart';
import 'page/statistics.dart';
import 'page/store.dart';

class LoginHomePage extends StatefulWidget {
  @override
  State<LoginHomePage> createState() => _LoginHomePageState();
}

class _LoginHomePageState extends State<LoginHomePage> {
  // final user = FirebaseAuth.instance.currentUser!;
  int pageIndex = 0;

  final screen = [
    HomeContentPage(),
    StatisticsPage(),
    StorePage(),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        bottomNavigationBar: NavigationBarTheme(
          data: NavigationBarThemeData(
            indicatorColor: Colors.blue.shade100,
            labelTextStyle: MaterialStateProperty.all(
              TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          child: NavigationBar(
            selectedIndex: pageIndex,
            onDestinationSelected: (index) => setState(() => pageIndex = index),
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            animationDuration: Duration(seconds: 1),
            destinations: [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.assessment_outlined),
                selectedIcon: Icon(Icons.assessment),
                label: 'Statistics',
              ),
              NavigationDestination(
                icon: Icon(Icons.store_outlined),
                selectedIcon: Icon(Icons.store),
                label: 'Store',
              ),
            ],
          ),
        ),
        body: screen[pageIndex],
      );
}
