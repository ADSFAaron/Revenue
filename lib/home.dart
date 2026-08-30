import 'package:flutter/material.dart';

import 'database/repositories.dart';

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

  @override
  void initState() {
    super.initState();
    final uid = authRepository.currentUid;
    if (uid != null) connectionStatus.watch(uid);
  }

  @override
  void dispose() {
    connectionStatus.stop();
    super.dispose();
  }

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

  void _select(int index) => setState(() {
        pageIndex = index;
        _visited.add(index);
      });

  @override
  Widget build(BuildContext context) {
    // Material's medium window class starts at 600dp, and that is also where a
    // bottom bar stops making sense: on a browser window the destinations sit
    // at the very bottom of a tall viewport, miles from the content. Measured
    // from the layout rather than the device, so a resized window and a split
    // screen both do the right thing.
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >= 600 ? _buildWide() : _buildCompact(),
    );
  }

  Widget _body() => Column(
        children: [
          const _OfflineBanner(),
          Expanded(
            child: IndexedStack(
              index: pageIndex,
              children: [
                for (var i = 0; i < _screens.length; i++)
                  if (_visited.contains(i))
                    _screens[i]
                  else
                    const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      );

  Widget _buildWide() {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: pageIndex,
            onDestinationSelected: _select,
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final destination in _destinations)
                NavigationRailDestination(
                  icon: destination.icon,
                  selectedIcon: destination.selectedIcon,
                  label: Text(destination.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _buildCompact() {
    return Scaffold(
      // No NavigationBarTheme override any more. It used to paint the
      // indicator `onPrimaryContainer` and the selected icon `onPrimary` —
      // both of those are foreground tokens, so the pill came out as a dark
      // blot far heavier than anything else on screen, and the selected label
      // underneath kept its unselected colour. Material 3's own defaults
      // (secondaryContainer / onSecondaryContainer) are the correct pairing.
      bottomNavigationBar: NavigationBar(
        selectedIndex: pageIndex,
        onDestinationSelected: _select,
        destinations: _destinations,
      ),
      body: _body(),
    );
  }
}

/// Says when the figures on screen came out of the cache.
///
/// Firestore keeps serving from disk when the connection drops, which is what
/// makes the app usable in a shop with patchy wifi — and also what makes a
/// stale number indistinguishable from a live one. Anything a till shows about
/// money has to say which of the two it is.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: connectionStatus,
      builder: (context, offline, _) {
        final scheme = Theme.of(context).colorScheme;
        return AnimatedSize(
          duration: Durations.short4,
          curve: Easing.standard,
          alignment: Alignment.topCenter,
          child: offline
              ? Material(
                  color: scheme.tertiaryContainer,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.cloud_off_rounded,
                              size: 18, color: scheme.onTertiaryContainer),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Offline — showing the last figures this device '
                              'saw. New orders are saved and will sync.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onTertiaryContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        );
      },
    );
  }
}
