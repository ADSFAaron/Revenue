import 'package:flutter/material.dart';

/// The half-width figure tile used on Today, Reports and Store.
///
/// Was four near-identical private `_buildCard()` methods, one per page, each
/// with its own copy of the `width / 2 - 30` sizing and its own icon puck. They
/// drifted — one had `crossAxisAlignment.start`, one pinned a height, one left
/// the value unaligned — and every colour fix had to be made four times.
class StatCard extends StatelessWidget {
  const StatCard({
    required this.title,
    required this.value,
    this.icon,
    this.onTap,
    this.trailing,
    super.key,
  });

  final String title;
  final String value;
  final IconData? icon;
  final VoidCallback? onTap;

  /// Sits to the right of the figure — the change pill, where there is one.
  final Widget? trailing;

  /// Two to a row inside the pages' `Wrap(spacing: 10)` at 16pt page padding.
  static double widthIn(BuildContext context) =>
      MediaQuery.of(context).size.width / 2 - 30;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: widthIn(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    StatIcon(icon: icon),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: FittedBox(
                        alignment: Alignment.centerRight,
                        child: Text(
                          value,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing!,
                    ],
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

/// The round puck behind a tile's icon.
///
/// Was `Theme.of(context).splashColor` everywhere — the Material 2 ripple
/// colour, a translucent black with no meaning under Material 3. Laid over a
/// card it produced whatever the card happened to be, with no contrast
/// guarantee for the glyph on top.
class StatIcon extends StatelessWidget {
  const StatIcon({required this.icon, this.size = 48, super.key});

  final IconData? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(icon,
          color: scheme.onSecondaryContainer, size: size * 0.5),
    );
  }
}

/// The "+12%" pill next to a figure.
///
/// A null [change] renders as an em dash rather than as 0%: "no comparison
/// available" and "flat against last month" are different things, and a shop's
/// first week would otherwise read as though it had gone nowhere.
class ChangeBadge extends StatelessWidget {
  const ChangeBadge({this.change, super.key});

  final double? change;

  @override
  Widget build(BuildContext context) {
    final change = this.change;
    if (change == null) {
      return Text('—', style: Theme.of(context).textTheme.bodySmall);
    }

    final scheme = Theme.of(context).colorScheme;
    final rising = change >= 0;
    // Was Colors.green on Colors.green[100] — about 2.2:1, under half the 4.5:1
    // floor, on the one number the page exists to convey. Tertiary also keeps
    // "up" from colliding with the green primary the buttons already use.
    final background =
        rising ? scheme.tertiaryContainer : scheme.errorContainer;
    final foreground =
        rising ? scheme.onTertiaryContainer : scheme.onErrorContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The arrow carries the direction on its own, so the pill still reads
          // where colour does not.
          Icon(rising ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              size: 16, color: foreground),
          Text(
            ' ${(change * 100).toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}
