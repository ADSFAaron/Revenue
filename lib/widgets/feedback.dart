import 'package:flutter/material.dart';

import '../database/data_exception.dart';

/// Reports a failure.
///
/// Every caller used to build its own `SnackBar(backgroundColor: Colors.red)`,
/// two of them with white text and a white glyph on top. That is a fixed red
/// regardless of theme, and under Material 3 a full-bleed saturated red reads
/// as an alarm rather than as a message. `errorContainer` is the token for
/// exactly this, and it moves with the scheme.
void showError(BuildContext context, String message, {Duration? duration}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: scheme.errorContainer,
      duration: duration ?? const Duration(seconds: 6),
      content: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child:
                Text(message, style: TextStyle(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    ));
}

/// Confirms something went through.
void showInfo(BuildContext context, String message, {Duration? duration}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: duration ?? const Duration(seconds: 3),
    ));
}

/// For the several screens that carry one `_snack(message, isError: …)` used
/// for both outcomes.
void showSnack(BuildContext context, String message, {bool isError = false}) =>
    isError ? showError(context, message) : showInfo(context, message);

/// Reports a failed read or write.
///
/// [error] is whatever `catch (e)` caught, untouched — the translation into
/// words happens here rather than at each call site, so no screen has to
/// remember not to interpolate a `FirebaseException` into a sentence and put
/// `[cloud_firestore/permission-denied]` in front of a shop owner. Guard the
/// call with `if (mounted)`: an await that fails after the person has left the
/// screen has nothing left to show a snack bar on.
void showFailure(BuildContext context, Object error) =>
    showError(context, describeFailure(error).message);

/// A failure that owns the whole body, rather than a snack bar over it.
///
/// For the case where there is nothing else to show: a stream that errored, a
/// first load that never arrived. A snack bar is wrong there because it leaves
/// an empty screen behind once it fades, and an empty screen is
/// indistinguishable from a store that has no data in it yet.
class ErrorView extends StatelessWidget {
  const ErrorView(this.error, {this.onRetry, super.key});

  /// Whatever was caught, or a `snapshot.error`.
  final Object error;

  /// Shown as a Retry button when there is something worth retrying. Omit it
  /// for failures a retry cannot fix, such as a refused permission.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: scheme.error),
            const SizedBox(height: 16),
            Text(
              describeFailure(error).message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A one-line failure note that sits under whatever it belongs to.
///
/// For the places where a failure has to be *said* but must not take the
/// page: a figure tile with no figure in it, a count that never arrived, a
/// control that is missing because the thing it depends on could not be read.
/// An [ErrorView] is wrong there because the rest of the screen is working; a
/// snack bar is wrong because it fades and leaves the gap behind with nothing
/// to explain it.
class InlineError extends StatelessWidget {
  const InlineError(this.error, {this.onRetry, super.key});

  /// Whatever was caught, or a `snapshot.error`.
  final Object error;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              describeFailure(error).message,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// The confirm button on a dialog that destroys something.
///
/// Delete, Remove and Void all used a plain `TextButton`, which under Material
/// 3 renders identically to the Cancel sitting next to it — the two most
/// different outcomes on the screen looked the same. Colour is not the only
/// signal (the words differ, and each dialog says what will happen), but it is
/// the one that works at a glance.
class DestructiveButton extends StatelessWidget {
  const DestructiveButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
        onPressed: onPressed,
        child: Text(label),
      );
}
