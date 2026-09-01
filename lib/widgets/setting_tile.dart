import 'package:flutter/material.dart';

/// What tapping a settings row actually does.
enum SettingKind {
  /// Opens another screen.
  page,

  /// Edits in place — a dialog, a picker, a segmented button.
  inline,

  /// Shows a value and nothing else.
  readOnly,
}

/// One row on a settings screen, with the affordance matched to what tapping
/// it does.
///
/// Every row used to be a `ListTile` with a `keyboard_arrow_right` bolted on,
/// including the four that open a dialog and never leave the page. A chevron
/// that sometimes means "a new screen" and sometimes means "a dialog" is not
/// telling anybody anything, so the chevron now belongs to exactly one of the
/// three cases and the other two say what they are in their own way.
class SettingTile extends StatelessWidget {
  /// Pushes another screen. The only kind that gets a chevron.
  const SettingTile.page({
    required this.icon,
    required this.title,
    required VoidCallback this.onTap,
    this.subtitle,
    this.locked = false,
    super.key,
  })  : kind = SettingKind.page,
        trailing = null;

  /// Edits in place. The current value in the subtitle is the affordance; a
  /// row that carries its own control passes it as [trailing].
  const SettingTile.inline({
    required this.icon,
    required this.title,
    this.onTap,
    this.subtitle,
    this.trailing,
    this.locked = false,
    super.key,
  }) : kind = SettingKind.inline;

  /// A fact about the store or the account that nobody edits from here.
  const SettingTile.readOnly({
    required this.icon,
    required this.title,
    this.subtitle,
    super.key,
  })  : kind = SettingKind.readOnly,
        onTap = null,
        trailing = null,
        locked = false;

  final SettingKind kind;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Manager-only, and this account is not one.
  ///
  /// Read-only rather than hidden. Somebody working the till who cannot see
  /// the tax rate, the trading-day cutoff or which payment methods are set up
  /// has no way to reconcile a drawer at the end of a shift, and every "why is
  /// this figure like that" becomes a phone call to the owner. The value
  /// stays; only the way to change it goes.
  ///
  /// This is a courtesy, not a security boundary — `firestore.rules` is what
  /// actually refuses the write. The point of the lock is that a store
  /// assistant finds out before tapping rather than after.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tappable = !locked && onTap != null;

    return ListTile(
      leading: Icon(
        icon,
        color: locked ? scheme.onSurfaceVariant : null,
      ),
      title: Text(title),
      subtitle: _subtitle(theme),
      trailing: locked
          // Deliberately the same size and slot as the chevron it replaces, so
          // a locked list still scans as one column rather than as a ragged
          // one with holes in it.
          ? Icon(Icons.lock_outline_rounded,
              size: 20, color: scheme.onSurfaceVariant)
          : kind == SettingKind.page
              ? const Icon(Icons.keyboard_arrow_right_rounded)
              : trailing,
      // A row with no `onTap` is not greyed out the way `enabled: false` greys
      // it, which matters: the value on a locked row still has to be readable.
      onTap: tappable ? onTap : null,
    );
  }

  Widget? _subtitle(ThemeData theme) {
    if (subtitle == null && !locked) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (subtitle != null) Text(subtitle!),
        if (locked)
          Text(
            'Managers only',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: .3,
            ),
          ),
      ],
    );
  }
}

/// A labelled break between groups of rows.
///
/// A bare `Divider` says "these are two groups" and stops there; the person
/// reading still has to work out what the second group is for. One word above
/// the rule does the same job and answers that too.
class SettingSection extends StatelessWidget {
  const SettingSection(this.label, {this.first = false, super.key});

  final String label;

  /// The first section on a screen has nothing above it to be separated from.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, first ? 12 : 28, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
