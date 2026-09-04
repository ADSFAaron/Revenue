import 'package:flutter/material.dart';

/// The full-width action on the screens before sign-in.
///
/// These were three copies of the same thing: a `MaterialButton` filled with
/// `Colors.greenAccent`, inside a `Container` carrying a 1px black border
/// offset three pixels to make a drawn-on-paper shadow. It is a look, and it
/// only works on paper — the outline is black because the background is white,
/// and there is no dark-mode value for "black outline on white" that keeps the
/// same idea. That single detail is most of why lib/widgets/pre_auth_theme.dart
/// had to pin these screens to the light palette.
///
/// What carries the character now is the shape: full width, sixty tall, fully
/// rounded. The colour and every state — pressed, disabled, focused — come from
/// the scheme, so these buttons are the same objects the rest of the app uses
/// and follow the theme without being told to.
class EntryButton extends StatelessWidget {
  const EntryButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.filled = true,
    this.icon,
    super.key,
  });

  const EntryButton.outlined({
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    super.key,
  }) : filled = false;

  final String label;
  final VoidCallback? onPressed;

  /// Swaps the label for a spinner and refuses taps. The button keeps its size
  /// so the page does not resettle under the reader's thumb mid-tap.
  final bool busy;

  final bool filled;
  final Widget? icon;

  static const double _height = 60;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(double.infinity, _height)),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      textStyle: WidgetStatePropertyAll(
        Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );

    final child = busy
        ? SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: filled
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.primary,
            ),
          )
        : Text(label);

    final onTap = busy ? null : onPressed;

    if (!filled) {
      return icon == null
          ? OutlinedButton(style: style, onPressed: onTap, child: child)
          : OutlinedButton.icon(
              style: style, onPressed: onTap, icon: icon, label: child);
    }
    return icon == null
        ? FilledButton(style: style, onPressed: onTap, child: child)
        : FilledButton.icon(
            style: style, onPressed: onTap, icon: icon, label: child);
  }
}
