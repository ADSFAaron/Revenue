import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/repositories.dart';
import '../models/app_user.dart';
import '../models/menu_item.dart';
import '../settings/store_invites.dart';
import '../settings/store_settings.dart';
import '../settings/store_settings_edit_menu.dart';

/// One thing a new store has to do before the rest of the app says anything.
class _Step {
  const _Step({
    required this.title,
    required this.detail,
    required this.done,
    required this.open,
  });

  final String title;
  final String detail;
  final bool done;
  final VoidCallback open;
}

/// What is left to set up, shown at the top of Today until it is all done.
///
/// A brand-new store opens on four empty tabs. Each one explains itself, but
/// none of them knows about the others, so there is no order to work through
/// and no sense of how far along you are — Insights in particular is blank
/// until dishes have costs, which is two screens away and not obvious from
/// there. This is the one place that says what to do next.
///
/// Reads once on build rather than watching: it is a first-run aid, and once
/// the four rows are ticked it never renders again.
class SetupChecklist extends StatefulWidget {
  const SetupChecklist({required this.session, super.key});

  final Session session;

  @override
  State<SetupChecklist> createState() => _SetupChecklistState();
}

class _SetupChecklistState extends State<SetupChecklist> {
  late Future<(List<MenuItem>, List<AppUser>)> _future = _load();

  /// Remembered between launches, like the theme choice is.
  ///
  /// Session-only state would be worse than none: this card sits above the
  /// day's takings on the screen a shop opens every morning, and a shop that
  /// has decided it does not want four rows of homework there has decided that
  /// once, not once per launch.
  static const String _collapsedKey = 'setup_checklist_collapsed';

  /// Starts expanded and folds itself away if the stored answer says so — the
  /// wrong way round would flash a collapsed card open on every launch.
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(_collapsedKey) ?? false;
      if (mounted && stored != _collapsed) setState(() => _collapsed = stored);
    } catch (_) {
      // A preference that cannot be read is not a reason to hide the card.
    }
  }

  Future<void> _toggle() async {
    final next = !_collapsed;
    setState(() => _collapsed = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_collapsedKey, next);
    } catch (_) {
      // It stays folded for this session either way.
    }
  }

  Future<(List<MenuItem>, List<AppUser>)> _load() async {
    final menu = await menuRepository.fetchActive(widget.session.storeId);
    final staff = await userRepository.watchStaff(widget.session.storeId).first;
    return (menu, staff);
  }

  /// Re-reads after a trip to one of the screens, so a row ticks itself off on
  /// the way back instead of on the next launch.
  void _openThen(Widget page) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page))
        .then((_) {
      if (mounted) setState(() => _future = _load());
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;

    return FutureBuilder<(List<MenuItem>, List<AppUser>)>(
      future: _future,
      builder: (context, snapshot) {
        // Silent while loading and silent on failure: this is an aid, and a
        // broken aid should not be the first thing on the page.
        if (!snapshot.hasData) return const SizedBox.shrink();

        final (menu, staff) = snapshot.data!;
        final costed = menu.where((item) => item.cost > 0).length;

        final steps = <_Step>[
          _Step(
            title: 'Put your dishes on the menu',
            detail: menu.isEmpty
                ? 'Nothing can be rung up until there is something to sell.'
                : '${menu.length} on the menu.',
            done: menu.isNotEmpty,
            open: () => _openThen(StoreEditMenu(session.storeId)),
          ),
          _Step(
            title: 'Fill in what each dish costs',
            detail: menu.isEmpty
                ? 'Add the dishes first.'
                : costed == menu.length
                    ? 'All ${menu.length} costed.'
                    : '$costed of ${menu.length} done — Insights can only '
                        'judge the ones with a cost on file.',
            done: menu.isNotEmpty && costed == menu.length,
            open: () => _openThen(StoreEditMenu(session.storeId)),
          ),
          _Step(
            title: 'Set a daily target',
            detail: 'The gauge on Reports measures against it. '
                '${session.store.targets.dailyOrders} orders a day right now.',
            // Every store starts on the same 100/20000 default, so leaving it
            // untouched is indistinguishable from not having looked. Treated
            // as done once it differs.
            done: session.store.targets.dailyOrders != 100 ||
                session.store.targets.dailyRevenue != 20000,
            open: () => _openThen(StoreSettings(session.storeId)),
          ),
          if (session.user.role.canManage)
            _Step(
              title: 'Invite your colleagues',
              detail: staff.length <= 1
                  ? 'Right now it is just you.'
                  : '${staff.length} people on the team.',
              done: staff.length > 1,
              open: () => _openThen(StoreInvites(
                storeId: session.storeId,
                storeName: session.store.name,
              )),
            ),
        ];

        final remaining = steps.where((s) => !s.done).length;
        if (remaining == 0) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final scheme = theme.colorScheme;

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Card(
            color: scheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The header is the control. Collapsed, it keeps the count
                  // and the bar — which is the part worth glancing at — and
                  // names the next thing to do, so folding it away costs the
                  // progress, not the plan.
                  InkWell(
                    onTap: _toggle,
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Finish setting up',
                                style: theme.textTheme.titleMedium?.copyWith(
                                    color: scheme.onSecondaryContainer),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _collapsed
                                    ? '${steps.length - remaining} of '
                                        '${steps.length} done · next: '
                                        '${steps.firstWhere((s) => !s.done).title}'
                                    : '${steps.length - remaining} of '
                                        '${steps.length} done',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSecondaryContainer),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          _collapsed ? Icons.expand_more : Icons.expand_less,
                          color: scheme.onSecondaryContainer,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (steps.length - remaining) / steps.length,
                      backgroundColor:
                          scheme.onSecondaryContainer.withValues(alpha: 0.15),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (!_collapsed)
                    for (final step in steps)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(
                          step.done
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: scheme.onSecondaryContainer,
                        ),
                        title: Text(
                          step.title,
                          style: TextStyle(
                            color: scheme.onSecondaryContainer,
                            decoration:
                                step.done ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        subtitle: Text(
                          step.detail,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSecondaryContainer
                                .withValues(alpha: 0.8),
                          ),
                        ),
                        trailing: step.done
                            ? null
                            : Icon(Icons.chevron_right_rounded,
                                color: scheme.onSecondaryContainer),
                        onTap: step.open,
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
