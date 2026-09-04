// Split out of lib/register.dart, which had grown to 1326 lines — the largest
// UI file in the project — by carrying the chooser, both registration flows and
// every piece of furniture they share in one place.

// The furniture the screens before sign-in share: the app bar, the error
// snackbar, and the small presentational pieces every step is built from.
//
// There are no drawings here any more. The four unDraw illustrations these
// screens used to open with were black-line artwork with a palette baked into
// the file, which is why they needed a generator script, two copies each, and
// — for a while — a whole theme pinning the entry flow to the light palette.
// What is left is type, the mark, and the shop's own colours, which follow the
// theme because they are the theme.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/invite.dart';
import '../database/repositories.dart';
import '../widgets/logo_mark.dart';
import '../widgets/page_body.dart';

/// The app bar every registration screen shares: transparent, so it always
/// matches the scaffold background instead of drifting from it.
PreferredSizeWidget buildEntryAppBar(
  BuildContext context, {
  VoidCallback? onBack,
}) {
  return AppBar(
    // Follows the theme rather than assuming a light bar. `SystemUiOverlayStyle
    // .dark` means *dark icons*, which is right on cream and invisible on
    // #12140E — one of the details that only worked while these screens were
    // pinned to the light palette.
    systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    elevation: 0,
    leading: IconButton(
      tooltip: 'Back',
      icon: Icon(
        Icons.arrow_back,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        size: 20,
      ),
      onPressed: onBack ?? () => Navigator.pop(context),
    ),
  );
}

void showEntryError(BuildContext context, String message) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: scheme.errorContainer,
      duration: const Duration(seconds: 6),
      content: Text(message),
    ),
  );
}

class StepBody extends StatelessWidget {
  const StepBody({
    required this.title,
    required this.subtitle,
    required this.children,

    super.key,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Every step of both wizards renders through here, so one cap covers all
    // of them.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
      child: PageBody(
        maxWidth: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepTitle(title),
            const SizedBox(height: 8),
            StepSubtitle(subtitle),
            const SizedBox(height: 28),
            ...children,
          ],
        ),
      ),
    );
  }
}

class StepTitle extends StatelessWidget {
  const StepTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );
}

class StepSubtitle extends StatelessWidget {
  const StepSubtitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      height: 1.4,
    ),
  );
}

class StepNote extends StatelessWidget {
  const StepNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      height: 1.4,
    ),
  );
}

/// Which step of how many, without pretending to be a Material Stepper.
class StepDots extends StatelessWidget {
  const StepDots({required this.count, required this.current, super.key});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final done = i <= current;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 6,
            width: i == current ? 28 : 12,
            decoration: BoxDecoration(
              color: done
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }
}

class PathCard extends StatelessWidget {
  const PathCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,

    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// "You are joining: `<store name>`" — shown before an account exists, which is
/// the only moment a mistyped code is still cheap to fix.
class JoiningBanner extends StatelessWidget {
  const JoiningBanner({required this.invite, super.key});

  final Invite invite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You are joining',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                Text(
                  invite.storeName.isEmpty ? 'this store' : invite.storeName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'as ${invite.role.label.toLowerCase()}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Signed in as …", once Google has answered and there is nothing left to
/// type on this step.
class SignedInBanner extends StatelessWidget {
  const SignedInBanner({required this.result, super.key});

  final SignInResult result;

  @override
  Widget build(BuildContext context) {
    final name = result.displayName.isNotEmpty
        ? result.displayName
        : result.email;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (result.email.isNotEmpty && result.email != name)
                  Text(
                    result.email,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LabelledField extends StatelessWidget {
  const LabelledField({
    required this.label,
    required this.controller,
    required this.errorText,
    this.obscureText = false,
    this.helperText,
    this.suffixIcon,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.autofillHints,
    this.onSubmitted,
    this.style,
    this.textAlign = TextAlign.start,

    super.key,
  });

  final String label;
  final TextEditingController controller;
  final String errorText;
  final bool obscureText;
  final String? helperText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final List<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          autofillHints: autofillHints,
          onSubmitted: onSubmitted,
          style: style,
          textAlign: textAlign,
          decoration: InputDecoration(
            errorText: errorText.isEmpty ? null : errorText,
            errorMaxLines: 3,
            helperText: helperText,
            helperMaxLines: 2,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 12,
            ),
            border: OutlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            suffixIcon: suffixIcon,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// Upper-cases as you type and silently drops anything outside the code
/// alphabet, so a code copied off a scrap of paper with a hyphen in it still
/// works.
class InviteCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = Invite.normalise(newValue.text);
    if (cleaned == newValue.text) return newValue;
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
    );
  }
}


/// The mark and the app's name, at the top of every screen before sign-in.
///
/// The mark is drawn from geometry rather than loaded, so it is correct in
/// both themes with nothing to generate and nothing to ship, and it is the
/// same shape the launch animation hands over from.
class EntryHeader extends StatelessWidget {
  const EntryHeader({this.tagline, super.key});

  /// One line under the name. Present on the first screen somebody sees and
  /// absent on the rest — a wordmark that explains itself on every step is a
  /// wordmark nobody reads by the third.
  final String? tagline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const SizedBox(
          height: 56,
          child: LogoMark(semanticLabel: 'Revenue'),
        ),
        const SizedBox(height: 12),
        Text(
          'Revenue',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        if (tagline != null) ...[
          const SizedBox(height: 6),
          Text(
            tagline!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// The layout every entry screen sits in: centred, capped at a form's width,
/// and scrollable, because a keyboard on a short phone takes half the screen.
class EntryBody extends StatelessWidget {
  const EntryBody({required this.children, this.padding, super.key});

  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: padding ?? const EdgeInsets.fromLTRB(28, 8, 28, 32),
        child: PageBody(
          maxWidth: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );
}
