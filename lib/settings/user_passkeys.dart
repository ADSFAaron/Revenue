import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/repositories.dart';
import '../widgets/feedback.dart';
import '../widgets/page_body.dart';
import '../widgets/empty_state.dart';

/// The signed-in person's passkeys — one per device they want to sign in from.
///
/// A passkey is added here, never at registration, because it is always
/// *additive*. Email and password keep working; a passkey is a faster way into
/// an account somebody can already reach. That ordering is not a simplifica-
/// tion — losing or replacing a phone must not lock an owner out of their own
/// books, and for this audience that is not a recoverable failure.
class UserPasskeys extends StatefulWidget {
  const UserPasskeys({super.key});

  @override
  State<UserPasskeys> createState() => _UserPasskeysState();
}

class _UserPasskeysState extends State<UserPasskeys> {
  late Future<List<PasskeyInfo>> _passkeys = passkeyRepository.list();

  /// Null until the platform has answered. Distinguishes "still asking" from
  /// "this device cannot", which are different screens.
  bool? _supported;

  bool _busy = false;

  /// Owned here, not created inside [_add]. Disposing a controller straight
  /// after `await showDialog` throws "A TextEditingController was used after
  /// being disposed" — the future completes as the exit transition starts,
  /// while the TextField is still mounted and still reading it.
  final _deviceNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    passkeyRepository.isSupported().then((value) {
      if (mounted) setState(() => _supported = value);
    });
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _passkeys = passkeyRepository.list());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Passkeys'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      floatingActionButton: _supported == true
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.add),
              label: const Text('Add passkey'),
            )
          : null,
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_supported == false) {
      return const EmptyState(
        icon: Icons.no_encryption_gmailerrorred_outlined,
        title: 'This device cannot use passkeys',
        body: 'Passkeys need Android 13 or later, or a current browser. You '
            'can still add one from a device that supports them — a passkey '
            'signs in the account, not the device it was made on.',
      );
    }

    return FutureBuilder<List<PasskeyInfo>>(
      future: _passkeys,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          // Was interpolating the raw error into the body.
          return ErrorView(snapshot.error!, onRetry: _reload);
        }

        final passkeys = snapshot.data ?? const <PasskeyInfo>[];
        return ReadingWidth(
          builder: (context, insets) => ListView(
            padding: insets + const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              const _Explainer(),
              const SizedBox(height: 8),
              if (passkeys.isEmpty)
                const EmptyState(
                  icon: Icons.fingerprint,
                  title: 'No passkeys yet',
                  body: 'Add one and this device can sign you in with a '
                      'fingerprint, face or screen lock instead of a password.',
                )
              else
                ...passkeys.map(_tile),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(PasskeyInfo passkey) {
    final detail = StringBuffer();
    if (passkey.createdAt != null) {
      detail.write('Added ${_date(passkey.createdAt!)}');
    }
    if (passkey.lastUsedAt != null) {
      if (detail.isNotEmpty) detail.write('  ·  ');
      detail.write('last used ${_date(passkey.lastUsedAt!)}');
    } else if (detail.isNotEmpty) {
      detail.write('  ·  never used');
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.key_outlined),
      title: Text(passkey.deviceName),
      subtitle: detail.isEmpty ? null : Text(detail.toString()),
      trailing: IconButton(
        tooltip: 'Remove',
        icon: const Icon(Icons.delete_outline),
        onPressed: _busy ? null : () => _remove(passkey),
      ),
    );
  }

  static String _date(DateTime at) => DateFormat('yyyy-MM-dd').format(at);

  Future<void> _add() async {
    _deviceNameController.text = passkeyRepository.defaultDeviceName;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a passkey'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your device will ask you to confirm with a fingerprint, face '
              'or screen lock.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _deviceNameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name this device',
                helperText: 'So you can tell your devices apart later',
                helperMaxLines: 2,
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (value) => Navigator.pop(context, value.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _deviceNameController.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final added = await passkeyRepository.add(
        deviceName: name.isEmpty ? null : name,
      );
      _snack('$added can now sign you in');
      _reload();
    } on PasskeyException catch (e) {
      // Backing out of the platform sheet is a decision, not a failure.
      if (e.failure != PasskeyFailure.cancelled) {
        _snack(e.message, isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(PasskeyInfo passkey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${passkey.deviceName}?'),
        content: const Text(
          'That device will no longer sign you in with a passkey. Your email '
          'and password still work, and you can add it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          DestructiveButton(
            label: 'Remove',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await passkeyRepository.remove(passkey.credentialId);
      _snack('${passkey.deviceName} removed');
      _reload();
    } on PasskeyException catch (e) {
      _snack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    showSnack(context, message, isError: isError);
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'A passkey stays on the device that made it and never travels '
                'to us — we only keep the public half, which cannot sign in on '
                'its own. Your email and password keep working either way, so '
                'a lost phone is never a locked-out account.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
