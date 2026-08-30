import 'package:flutter/material.dart';

/// Nothing to show, and why.
///
/// There were five of these: `_EmptyNotice` on Insights, `_CenteredMessage` on
/// invites, `_Message` on passkeys, `_EmptyState` on categories, and two
/// screens that just printed a sentence — "No orders available." — with no
/// icon, no explanation and nowhere to go. An empty screen is the moment a
/// person most needs telling what happened and what to do, so it is worth one
/// shape used everywhere rather than five that drifted.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  /// The way out, where there is one. Omit it when there genuinely is nothing
  /// to do from here.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
