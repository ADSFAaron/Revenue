import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'database/repositories.dart';

/// The alternatives to email and password, shared by the login screen and both
/// registration paths.
///
/// Neither button is ever shown speculatively. Google is hidden where the
/// platform has no implementation (Windows), and passkeys are hidden until the
/// device says it can actually do them — Android below API 28 cannot, and nor
/// can an old browser. A button whose only possible outcome is an error is
/// worse than no button at all.
///
/// Email and password stay available underneath in every case. Passkeys are
/// additive here and always will be: losing or replacing a phone must not lock
/// an owner out of their own books.
class SignInOptions extends StatefulWidget {
  const SignInOptions({
    super.key,
    required this.onGoogle,
    this.onPasskey,
    this.busy = false,
  });

  /// Runs the Google flow. The caller owns the outcome, including its errors.
  final Future<void> Function() onGoogle;

  /// Runs the passkey flow. Null on screens where signing in with one makes no
  /// sense — registration, where there is no account to hold a passkey yet.
  final Future<void> Function()? onPasskey;

  /// Set while the caller is busy with something else, so two flows cannot be
  /// started at once.
  final bool busy;

  @override
  State<SignInOptions> createState() => _SignInOptionsState();
}

class _SignInOptionsState extends State<SignInOptions> {
  /// Resolved once. The answer cannot change while the screen is open, and
  /// asking the platform on every rebuild would be wasteful.
  late final Future<bool> _passkeysSupported = widget.onPasskey == null
      ? Future.value(false)
      : passkeyRepository.isSupported();

  bool _running = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_running || widget.busy) return;
    setState(() => _running = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _running || widget.busy;

    return FutureBuilder<bool>(
      future: _passkeysSupported,
      builder: (context, snapshot) {
        final showPasskey = snapshot.data == true && widget.onPasskey != null;
        final showGoogle = authRepository.supportsGoogle;
        if (!showGoogle && !showPasskey) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _OrDivider(),
            const SizedBox(height: 16),
            if (showGoogle)
              _ProviderButton(
                icon: SvgPicture.asset(
                  'assets/google-icon.svg',
                  width: 20,
                  height: 20,
                ),
                label: 'Continue with Google',
                onPressed: disabled ? null : () => _run(widget.onGoogle),
              ),
            if (showGoogle && showPasskey) const SizedBox(height: 12),
            if (showPasskey)
              _ProviderButton(
                icon: const Icon(Icons.fingerprint, size: 22),
                label: 'Sign in with a passkey',
                onPressed: disabled ? null : () => _run(widget.onPasskey!),
              ),
            if (_running) ...[
              const SizedBox(height: 12),
              const Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final line = Expanded(child: Divider(color: Colors.grey[400]));
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('or', style: TextStyle(color: Colors.grey[600])),
        ),
        line,
      ],
    );
  }
}

/// Outlined rather than filled: these sit next to the one green primary button
/// on the screen, and there can only be one of those.
class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: Text(label, style: const TextStyle(fontSize: 16)),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.black87,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: Colors.black),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(50),
        ),
      ),
    );
  }
}
