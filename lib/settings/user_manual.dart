import 'package:flutter/material.dart';

import '../analysis/menu_engineering.dart';
import '../models/order.dart';
import '../widgets/page_body.dart';
import '../widgets/text_scale.dart';

/// The chapters of the manual, in the order somebody meets them.
enum ManualTopic {
  setup('Setting the shop up', Icons.rocket_launch_outlined),
  till('A day on the till', Icons.point_of_sale_outlined),
  money('How the figures are worked out', Icons.calculate_outlined),
  insights('Reading Insights', Icons.lightbulb_outline_rounded),
  roles('Who can do what', Icons.badge_outlined),
  trouble('When something looks wrong', Icons.help_outline_rounded);

  const ManualTopic(this.title, this.icon);

  final String title;
  final IconData icon;
}

/// What the app does, and where its numbers come from.
///
/// Every screen in here explains itself locally — an empty state says why it
/// is empty, a field says what it is for. What none of them can say is how the
/// pieces fit: that a dish left without a cost is invisible to every profit
/// figure in the app, that "Plowhorse" is a verdict about this menu rather
/// than an absolute one, or that the day's takings roll over at an hour
/// somebody chose in settings. Those are the questions that make a person
/// distrust a till, and they are answered in one place rather than sprinkled
/// as hints across six screens.
///
/// Written as prose with the actual arithmetic shown, not as a feature tour.
/// The constants quoted here are read from the code that uses them, so a
/// changed threshold cannot leave the manual quietly lying about it.
class UserManual extends StatefulWidget {
  const UserManual({this.initialTopic, super.key});

  /// Opens with one chapter already expanded. The Insights screen passes
  /// [ManualTopic.insights], so its help button lands on the four classes
  /// rather than at the top of a manual.
  final ManualTopic? initialTopic;

  @override
  State<UserManual> createState() => _UserManualState();
}

class _UserManualState extends State<UserManual> {
  // The chapters are driven from here rather than left to manage themselves.
  // An expansion tile only reads `initiallyExpanded` when its state is
  // created, and a chapter scrolled off the end of the list is disposed and
  // created again on the way back — so a tile left to remember its own state
  // reopens from page storage and reports that as a change, in the middle of
  // the build that created it. Holding the controllers here means the tile is
  // rebuilt already agreeing with us, and nothing is announced.
  late final Map<ManualTopic, ExpansibleController> _controllers = {
    for (final topic in ManualTopic.values) topic: ExpansibleController(),
  };

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTopic;
    if (initial != null) {
      _controllers[initial]!.expand();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// One chapter open at a time: six of them expanded is a wall of text with
  /// no way to see what else is on offer.
  void _opened(ManualTopic topic) {
    for (final MapEntry(key: other, value: controller)
        in _controllers.entries) {
      if (other != topic) {
        controller.collapse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('How this works')),
      body: SafeArea(
        child: ReadingWidth(
          builder: (context, insets) => ListView(
            padding: insets + const EdgeInsets.fromLTRB(0, 8, 0, 40),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Text(
                  'Six questions, answered in the order they usually come up. '
                  'The arithmetic behind every figure the app shows is in '
                  '“How the figures are worked out”.',
                  style: _prose(context)
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              for (final topic in ManualTopic.values)
                _Chapter(
                  topic: topic,
                  controller: _controllers[topic]!,
                  onOpened: () => _opened(topic),
                  children: _body(topic),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(ManualTopic topic) => switch (topic) {
        ManualTopic.setup => const [
            _Para(
              'Four of these can wait. The first cannot: until dishes have '
              'costs on them, the app can tell you what you sold but not '
              'whether it was worth selling, and half the Insights tab stays '
              'blank.',
            ),
            _Step(
              1,
              'Put the menu in — with costs',
              'Store · Store settings · Menu. A dish needs a price and what '
                  'the ingredients cost you. The cost is the one people skip, '
                  'and it is the one everything else is built on: a dish with '
                  'no cost is left out of gross profit, out of the food-cost '
                  'rate, and off the Insights matrix entirely. It is not '
                  'guessed at or averaged — an unknown margin shows as '
                  'unknown.',
            ),
            _Step(
              2,
              'Say how you take money',
              'Store · Store settings · Payment methods. The till offers them '
                  'in the order you put them in, and a new order starts on the '
                  'first. Reports break the takings down by method, which is '
                  'what makes the end-of-day drawer count check out.',
            ),
            _Step(
              3,
              'Add delivery platforms, with their cut',
              'Store · Store settings · Delivery platforms. Enter the '
                  'commission each one keeps. Skip it and a delivery order '
                  'books as pure revenue — the takings look right and the '
                  'gross profit is wrong by whatever the platform kept.',
            ),
            _Step(
              4,
              'Set when your day rolls over',
              'Store · Store settings · Trading day starts at. A kitchen that '
                  'shuts at 02:00 should count those orders as the previous '
                  'day. Set the hour you open; leave it at 00:00 to use the '
                  'calendar day.',
            ),
            _Step(
              5,
              'Set a daily target',
              'Store · Store settings · Daily targets. Orders and takings per '
                  'day. This is what the gauge on Reports measures against — '
                  'without it there is a dial with no dial face.',
            ),
            _Callout(
              icon: Icons.group_add_outlined,
              text: 'Colleagues join with an invite code, not by being looked '
                  'up: Store settings · Staff · invite. You choose whether the '
                  'code makes them a manager or an assistant when you create '
                  'it.',
            ),
          ],
        ManualTopic.till => [
            const _Para(
              'Today is the working screen. It shows what has been taken so '
              'far against the target, the last few orders, and the button '
              'that rings up a new one.',
            ),
            const _Terms([
              (
                'Channel',
                'Dine-in, takeout or delivery. Not cosmetic — the cost '
                    'structures differ (packaging on takeout, commission on '
                    'delivery), so every report can be read per channel.'
              ),
              (
                'Guests',
                'How many people the order fed. This is the divisor behind '
                    '“per head”, so a table of four entered as one guest '
                    'makes that figure four times too high.'
              ),
              (
                'Payment method',
                'Which of your configured methods took the money. Starts on '
                    'the first in your list.'
              ),
            ]),
            _Para(
              'Made a mistake? Open the order from Today, or from Store · '
                  'Order history, and edit or void it. Anyone may correct their '
                  'own order for the first '
                  '$_correctionMinutes minutes; after that it takes a '
                  'manager. Both leave an entry in the change history, and a '
                  'voided order is struck through rather than deleted.',
            ),
            const _Callout(
              icon: Icons.cloud_off_rounded,
              text: 'Lost the wifi? A banner says the figures on screen are '
                  'the last ones this device saw. Orders you ring up are held '
                  'on the device and sent the moment the connection returns — '
                  'the bar under the banner counts what is still waiting.',
            ),
          ],
        ManualTopic.money => const [
            _Para(
              'Nothing here is estimated. Every figure below is arithmetic on '
              'what you entered, and where a number cannot be worked out '
              'honestly the app leaves it blank instead of filling it in.',
            ),
            _Formula(
              'Revenue',
              'sum of every completed order in the period',
              'Voided orders are excluded. Imported platform orders are '
                  'included from the day they cover, not the day you imported '
                  'them.',
            ),
            _Formula(
              'Gross profit',
              'revenue − ingredient cost − platform commission',
              'Ingredient cost is the cost you put on each dish, frozen at '
                  'the moment of sale — a supplier price rise next month does '
                  'not quietly rewrite last month’s profit. Dishes with no '
                  'cost on file contribute revenue but no cost, so a '
                  'half-costed menu overstates profit; fill the costs in.',
            ),
            _Formula(
              'Per head',
              'revenue ÷ guests',
              'Only orders that recorded a guest count are in the divisor.',
            ),
            _Formula(
              'Tax',
              'included in prices  ·  or  ·  added on top',
              'Set both the rate and which of the two it is, in Store '
                  'settings · Tax. “Included” means the menu price already '
                  'contains it and revenue is reported net of it; “added on '
                  'top” means it is charged over the menu price. Getting this '
                  'backwards moves every revenue figure in the app by the tax '
                  'rate.',
            ),
            _Formula(
              'Which day an order counts as',
              'before the cutoff hour → the previous trading day',
              'Set in Store settings · Trading day starts at. Orders keep the '
                  'trading day they were written with, so changing the cutoff '
                  'affects new orders only — yesterday’s totals do not move '
                  'under you.',
            ),
            _Formula(
              'Delivery commission',
              'order total × the platform’s rate',
              'Taken off gross profit, not off revenue: the customer really '
                  'did pay that, you simply did not keep it.',
            ),
          ],
        ManualTopic.insights => [
            const _Para(
              'Reports says what happened. Insights is the only part of the '
              'app that says what to do about it, and it needs dish costs to '
              'say anything at all.',
            ),
            const _Heading('The menu matrix'),
            const _Para(
              'Every costed dish is placed on two axes: how often it sells, '
              'and how much it earns per plate. Both thresholds are relative '
              'to your own menu, never to an industry figure — a dish is '
              '“profitable” when its margin per unit beats the average margin '
              'per unit across everything you sold, and “popular” when its '
              'share of units sold clears 70% of an even split. On a menu of '
              '20 costed dishes an even split is 5% each, so the bar is 3.5%.',
            ),
            const _Terms([
              (
                'Star',
                'Sells well, earns well. Protect it — do not reprice, resize '
                    'or move it down the menu.'
              ),
              (
                'Plowhorse',
                'Sells well, earns little. The dangerous one, and the reason '
                    'a best-seller chart is not enough: it tops that chart '
                    'while thinning the margin on every plate. Reprice, '
                    'resize, or cut its cost.'
              ),
              (
                'Puzzle',
                'Earns well, nobody orders it. Usually a menu-layout or '
                    'upselling problem rather than a food problem — move it '
                    'up the menu or push it.'
              ),
              (
                'Dog',
                'Neither sells nor earns. A candidate for removal.'
              ),
            ]),
            const _Callout(
              icon: Icons.info_outline,
              text: 'Because the thresholds are relative, every menu has '
                  'Plowhorses and Dogs — the classes are a ranking of your '
                  'dishes against each other, not a pass mark. Removing the '
                  'Dogs re-sorts the rest.',
            ),
            const _Heading('Food cost'),
            _Para(
              'Ingredient cost as a share of revenue, over the costed dishes '
              'only. Above $_foodCostWarning% the app flags it. That line is '
              'an American restaurant benchmark and Taiwanese cost structures '
              'differ, so treat the flag as a reason to go and look, not as a '
              'verdict.',
            ),
            const _Heading('Busiest times'),
            const _Para(
              'Orders averaged by weekday and hour, each square over every '
              'occurrence of that weekday in the range. Weekday and hour '
              'together, not a flat 24-hour chart: a Tuesday evening and a '
              'Saturday evening are two different businesses, and averaging '
              'them hides both. The per-dish forecast carries how many of '
              'that weekday it is drawn from — one Saturday is an anecdote — '
              'and the busiest single day seen, because preparing to the '
              'average sells out half the time.',
            ),
            const _Heading('Ordered together'),
            const _Para(
              'Pairings found by reading the orders themselves rather than '
              'the daily totals, which is why it loads on request. Three '
              'numbers travel with every pairing, and the third is the one '
              'that matters.',
            ),
            const _Terms([
              (
                'Support',
                'How often the pair shows up across all orders. Guards '
                    'against acting on something real that happens twice a '
                    'month.'
              ),
              (
                'Confidence',
                'Of the orders containing the first dish, the share that also '
                    'contained the second. The number to say out loud: “62% '
                    'of beef noodle orders add a tea egg.”'
              ),
              (
                'Lift',
                'Confidence divided by how often the second dish is ordered '
                    'anyway. A drink in 80% of all orders shows 80% '
                    'confidence behind every dish on the menu; only lift '
                    'shows it has nothing to do with any of them. Above 1 '
                    'means the two really do travel together.'
              ),
            ]),
          ],
        ManualTopic.roles => [
            const _Para(
              'Three roles. The limits are enforced by the database, not by '
              'the screens, so a setting an assistant cannot change is shown '
              'read-only rather than hidden — the value is still worth '
              'knowing on a shift.',
            ),
            _Terms([
              (
                'Owner',
                'One per store, set when the store is registered and never '
                    'transferable. Everything a manager can do, plus closing '
                    'the store by deleting their own account.'
              ),
              (
                'Manager',
                'Changes the shop’s settings, edits the menu and prices, '
                    'invites colleagues and sets their role, edits or voids '
                    'any order at any time, and reads the change history.'
              ),
              (
                'Assistant',
                'Takes orders, reads the menu, the staff list, the payment '
                    'methods, the delivery platforms and the order history. '
                    'May correct their own order for '
                    '$_correctionMinutes minutes after ringing it up. Cannot '
                    'change settings or prices, and cannot read the change '
                    'history.'
              ),
            ]),
            const _Callout(
              icon: Icons.lock_outline_rounded,
              text: 'A row with a padlock is a manager’s to change. Ask an '
                  'owner or manager, or have them change your role in Store '
                  'settings · Staff.',
            ),
          ],
        ManualTopic.trouble => const [
            _Terms([
              (
                'A banner says you are offline',
                'The figures on screen are the last ones this device saw, so '
                    'treat them as of that moment. Orders can still be rung '
                    'up; they queue on the device.'
              ),
              (
                'Orders are waiting to send',
                'The bar under the banner counts them. They go up on their '
                    'own when the connection returns — do not re-enter them, '
                    'or the day will be counted twice.'
              ),
              (
                'A figure looks wrong',
                'Store · Change history lists every void, order edit and '
                    'price change, with who did it and when. Managers only.'
              ),
              (
                'Insights is blank',
                'It needs dish costs. The empty state has a button straight '
                    'to the menu.'
              ),
              (
                'The day’s takings look short',
                'Two usual causes: the trading-day cutoff is putting late '
                    'orders on the previous day, or delivery orders have not '
                    'been imported yet — they live in the platform’s back '
                    'office until you read a statement in from Store · '
                    'Import orders.'
              ),
              (
                'Profit looks too good',
                'Dishes with no cost on file contribute revenue and no cost. '
                    'The Insights matrix lists them under “Not costed”.'
              ),
            ]),
          ],
      };
}

/// Quoted from the constants the app actually enforces, so the manual cannot
/// drift away from the behaviour it describes.
final String _correctionMinutes = kStaffCorrectionWindow.inMinutes.toString();
final String _foodCostWarning =
    (MenuEngineering.foodCostWarningRate * 100).round().toString();

/// The manual is the one screen in this app that is *read* rather than
/// scanned, and it was set in `bodyMedium` — Material's 14sp supporting size,
/// meant for the second line of a list tile, at a line height of 1.43. Six
/// chapters of paragraphs at that size is what makes a page tiring before it
/// makes it unreadable.
///
/// `bodyLarge` (16sp) is Material's actual reading size, and the extra leading
/// is what separates a wall from a page. Both come from the text theme rather
/// than a number here, so the system font size still moves them.
TextStyle? _prose(BuildContext context) =>
    Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5);

class _Chapter extends StatelessWidget {
  const _Chapter({
    required this.topic,
    required this.controller,
    required this.onOpened,
    required this.children,
  });

  final ManualTopic topic;
  final ExpansibleController controller;
  final VoidCallback onOpened;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      // The default expansion tile paints a divider above and below every
      // panel, which on six stacked panels reads as a table rather than as a
      // list of questions.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey(topic),
        controller: controller,
        onExpansionChanged: (open) {
          if (open) {
            onOpened();
          }
        },
        leading: Icon(topic.icon, color: theme.colorScheme.primary),
        title: Text(topic.title, style: theme.textTheme.titleMedium),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleMedium
            ?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

class _Para extends StatelessWidget {
  const _Para(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(text, style: _prose(context)),
      );
}

/// A numbered thing to go and do, with where to do it.
class _Step extends StatelessWidget {
  const _Step(this.number, this.title, this.body);

  final int number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: scaledForText(context, 24),
            height: scaledForText(context, 24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(body, style: _prose(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A figure, the arithmetic behind it, and the caveat that comes with it.
class _Formula extends StatelessWidget {
  const _Formula(this.name, this.expression, this.note);

  final String name;
  final String expression;
  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            expression,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Menlo', 'Courier New'],
              color: scheme.primary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            note,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// A short definition list — the shape most of this manual wants.
class _Terms extends StatelessWidget {
  const _Terms(this.entries);

  final List<(String, String)> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (term, definition) in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(term, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(definition, style: _prose(context)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: scheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: _prose(context)
                  ?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
