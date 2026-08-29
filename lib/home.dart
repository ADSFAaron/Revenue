import 'package:flutter/material.dart';

import 'page/analysis.dart';
import 'page/statistics.dart';
import 'page/store.dart';
import 'page/transaction.dart';

/// The signed-in shell.
///
/// Four destinations, in the order the questions get asked: what happened
/// today, what should I do about it, what do the numbers say over time, and
/// the shop's own settings.
///
/// Insights used to be an unlabelled icon in the statistics app bar, next to a
/// larger and more prominent button that did nothing. It is the only part of
/// the app that answers "what should I change" rather than "what was sold", so
/// it now sits a level up, where Overview — two figures that Today already
/// showed — used to be.
class LoginHomePage extends StatefulWidget {
  const LoginHomePage({super.key});

  @override
  State<LoginHomePage> createState() => _LoginHomePageState();
}

class _LoginHomePageState extends State<LoginHomePage> {
  int pageIndex = 0;

  /// Destinations the user has actually opened.
  ///
  /// The shell keeps pages alive once built, so switching tabs no longer tears
  /// a page down and re-reads its session and figures on the way back. But
  /// building all four up front would mean Insights' ninety-day fetch runs for
  /// someone who never opens it, so a page is not built until it is first
  /// visited.
  final _visited = <int>{0};

  static const _screens = [
    TransactionPage(),
    AnalysisPage(),
    StatisticsPage(),
    StorePage(),
  ];

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.today_outlined),
      selectedIcon: Icon(Icons.today_rounded),
      label: 'Today',
    ),
    NavigationDestination(
      icon: Icon(Icons.lightbulb_outline_rounded),
      selectedIcon: Icon(Icons.lightbulb_rounded),
      label: 'Insights',
    ),
    NavigationDestination(
      icon: Icon(Icons.bar_chart_outlined),
      selectedIcon: Icon(Icons.bar_chart_rounded),
      label: 'Reports',
    ),
    NavigationDestination(
      icon: Icon(Icons.storefront_outlined),
      selectedIcon: Icon(Icons.storefront_rounded),
      label: 'Store',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No NavigationBarTheme override any more. It used to paint the
      // indicator `onPrimaryContainer` and the selected icon `onPrimary` —
      // both of those are foreground tokens, so the pill came out as a dark
      // blot far heavier than anything else on screen, and the selected label
      // underneath kept its unselected colour. Material 3's own defaults
      // (secondaryContainer / onSecondaryContainer) are the correct pairing.
      bottomNavigationBar: NavigationBar(
        selectedIndex: pageIndex,
        onDestinationSelected: (index) => setState(() {
          pageIndex = index;
          _visited.add(index);
        }),
        destinations: _destinations,
      ),
      body: IndexedStack(
        index: pageIndex,
        children: [
          for (var i = 0; i < _screens.length; i++)
            if (_visited.contains(i)) _screens[i] else const SizedBox.shrink(),
        ],
      ),
    );
  }
}
