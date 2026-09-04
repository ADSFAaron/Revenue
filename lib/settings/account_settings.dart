import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../database/repositories.dart';
import '../models/app_user.dart';
import '../widgets/empty_state.dart';
import '../widgets/confirm_by_typing.dart';
import '../widgets/feedback.dart';
import '../widgets/page_body.dart';
import '../widgets/setting_tile.dart';
import 'app_update.dart';
import 'change_password.dart';
import 'theme_controller.dart';
import 'user_passkeys.dart';

/// You, this device, and the way out — everything on the Store tab that is not
/// about the shop.
///
/// This was two screens, User Settings and App Settings, plus a Log out row
/// sitting loose in the Store tab's navigation list. The split never held up:
/// App Settings took a `storeId` it only needed so that feedback could name a
/// shop, and the two account-ending actions were a level apart, with Log out
/// mixed in among navigation rows and Delete account at the bottom of a
/// different screen. Nobody thinks of "my name", "my password" and "dark mode"
/// as three different neighbourhoods.
///
/// The store id now comes off the signed-in user's own profile, so this screen
/// needs nothing passed in.
class AccountSettings extends StatefulWidget {
  const AccountSettings({super.key});

  @override
  State<AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends State<AccountSettings> {
  /// Opens an external link, and says so when it cannot.
  ///
  /// `launchUrl` was previously called bare, and both of the reasons that was
  /// wrong are worth naming.
  ///
  /// The first was a missing `<queries>` element in AndroidManifest.xml.
  /// Since Android 11 an app cannot see what else is installed unless it
  /// declares what it is looking for, and url_launcher resolves a link by
  /// asking the package manager who handles it — so on every Android 11 and
  /// later device the call found no browser, returned false, and this row did
  /// nothing at all. Silently. The manifest now declares it.
  ///
  /// The second is what remains once it can: a device really may have no
  /// browser, and url_launcher throws in that case. An uncaught exception out
  /// of a tap handler on a settings screen is a crash, and the thing being
  /// linked to here is the source code an AGPL licence obliges this app to
  /// make reachable — so failing quietly is not an option either.
  Future<void> _openLink(String url) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('Could not open $url: $e');
    }
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('No app on this device can open that link.'),
        action: SnackBarAction(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: url)),
        ),
      ),
    );
  }

  /// Stateful purely so these have an owner.
  ///
  /// A controller created inside the method that shows a dialog and disposed
  /// after the await throws "A TextEditingController was used after being
  /// disposed": `showDialog`'s future completes when the route is popped,
  /// which is the *start* of the exit transition, and the TextField is still
  /// mounted and still reading the controller. Cancel crashed every time.
  final _nameController = TextEditingController();
  final _feedbackController = TextEditingController();

  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account & App')),
      body: SafeArea(
        child: StreamBuilder<AppUser?>(
          stream: userRepository.watchCurrent(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorView(snapshot.error!);
            }
            if (!snapshot.hasData &&
                snapshot.connectionState != ConnectionState.active) {
              return const Center(child: CircularProgressIndicator());
            }

            final user = snapshot.data;
            if (user == null) {
              // Signed in, but the profile document is not there. Almost
              // always mid-registration; occasionally an account whose
              // provisioning failed.
              return const EmptyState(
                icon: Icons.person_off_outlined,
                title: 'No profile for this account',
                body:
                    'Sign out and back in. If it keeps happening, the '
                    'account was not finished being set up.',
              );
            }
            return _buildList(user);
          },
        ),
      ),
    );
  }

  Widget _buildList(AppUser user) {
    final scheme = Theme.of(context).colorScheme;
    final info = _packageInfo;

    return ReadingWidth(
      builder: (context, insets) => ListView(
        padding: insets + const EdgeInsets.only(bottom: 24),
        children: [
          const SettingSection('You', first: true),
          SettingTile.inline(
            icon: Icons.person_outline,
            title: 'Name',
            subtitle: user.displayName.isEmpty ? 'Not set' : user.displayName,
            onTap: () => _editDisplayName(user),
          ),
          SettingTile.readOnly(
            icon: Icons.mail_outline,
            title: 'Email',
            subtitle: user.email.isEmpty ? 'No email' : user.email,
          ),
          SettingTile.readOnly(
            icon: Icons.badge_outlined,
            title: 'Role',
            // The role decides what the rest of the app lets this account do,
            // so it says which of the two sides of that line it falls on
            // rather than leaving the word to be interpreted.
            subtitle:
                '${user.role.label} · ${user.role.canManage ? 'may change the shop’s settings' : 'takes orders; settings are read-only'}',
          ),
          const SettingSection('Signing in'),
          SettingTile.page(
            icon: Icons.password_outlined,
            title: 'Change password',
            onTap: () => _push(const ChangePassword()),
          ),
          SettingTile.page(
            icon: Icons.fingerprint,
            title: 'Passkeys',
            subtitle: 'Sign in with a fingerprint, face or screen lock',
            onTap: () => _push(const UserPasskeys()),
          ),
          const SettingSection('App'),
          _buildAppearanceTile(),
          // Three rows for app name, version and build number was three rows
          // saying one thing. It is one line on a support email — and the same
          // line is where "there is a newer one" belongs, because that is the
          // only moment anybody looks at a version number on purpose.
          _VersionTile(info),
          SettingTile.inline(
            icon: Icons.code_rounded,
            title: 'Source code',
            subtitle: 'AGPL-3.0 on GitHub',
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            // The AGPL asks that people using the software over a network can
            // get at its source. A till talking to Firestore and to the
            // functions in this same repository is exactly that, so the link
            // belongs in the app rather than only in a README nobody reading
            // this screen has seen.
            onTap: () => _openLink(kSourceUrl),
          ),
          SettingTile.inline(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy policy',
            subtitle: 'What is stored, where, and how to delete it',
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            onTap: () => _openLink(kPrivacyPolicyUrl),
          ),
          SettingTile.inline(
            icon: Icons.gavel_outlined,
            title: 'Terms of use',
            subtitle: 'What the app does, and who is responsible for what',
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            onTap: () => _openLink(kTermsUrl),
          ),
          SettingTile.inline(
            icon: Icons.feedback_outlined,
            title: 'Send feedback',
            subtitle: 'Improvement ideas, or a bug you hit',
            onTap: () => _sendFeedback(user.storeId),
          ),
          const SettingSection('Account'),
          SettingTile.inline(
            icon: Icons.logout_outlined,
            title: 'Log out',
            subtitle: 'Ends this session on this device',
            onTap: _confirmLogout,
          ),
          // App Store guideline 5.1.1(v): an app that lets somebody create an
          // account has to let them delete it, from inside the app, along with
          // their data, and it has to be easy to find. It sits beside Log out
          // because that is where somebody goes looking for it.
          ListTile(
            leading: Icon(Icons.person_remove_outlined, color: scheme.error),
            title: Text(
              'Delete account',
              style: TextStyle(color: scheme.error),
            ),
            subtitle: Text(
              user.role == UserRole.owner
                  ? 'Closes the store and erases everything in it'
                  : 'Removes you from this store and deletes your login',
            ),
            onTap: () => _deleteAccount(user),
          ),
        ],
      ),
    );
  }

  /// Light / dark / follow the system.
  Widget _buildAppearanceTile() {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeController,
      builder: (context, mode, _) => SettingTile.inline(
        icon: mode.icon,
        title: 'Appearance',
        subtitle: mode.label,
        trailing: SegmentedButton<ThemeMode>(
          showSelectedIcon: false,
          segments: [
            for (final option in ThemeMode.values)
              ButtonSegment(
                value: option,
                icon: Icon(option.icon),
                tooltip: option.label,
              ),
          ],
          selected: {mode},
          onSelectionChanged: (selection) =>
              themeController.set(selection.first),
        ),
      ),
    );
  }

  void _push(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      // The platform channel can answer after this page is gone, and a
      // `setState` on a disposed State throws — into the `catch` below, which
      // would file a lifecycle mistake away as "could not read the version".
      if (!mounted) return;
      setState(() => _packageInfo = info);
    } catch (e) {
      // Left alone on purpose: a missing version string is cosmetic, and there
      // is nothing the person reading this screen could do about it.
      debugPrint('Failed to get app info: $e');
    }
  }

  Future<void> _editDisplayName(AppUser user) async {
    _nameController.text = user.displayName;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    // The name is stamped onto every audit entry this person writes from here
    // on, so a rename that quietly failed would leave the log naming somebody
    // who no longer goes by that.
    try {
      await userRepository.updateDisplayName(user.uid, name);
      if (mounted) showInfo(context, 'Name updated');
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  /// The dialog validates before it closes.
  ///
  /// It used to carry a single "Send" button — no way out but the back gesture
  /// — and `pop()` was called without waiting for the send, so an empty
  /// message closed the dialog and *then* raised "Feedback cannot be empty" as
  /// a snack bar, pointing at a field that was no longer on screen.
  Future<void> _sendFeedback(String storeId) async {
    _feedbackController.clear();
    String? error;

    final message = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Send feedback'),
          content: TextField(
            controller: _feedbackController,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'What would you change, or what went wrong?',
              errorText: error,
            ),
            onChanged: (_) {
              if (error != null) setDialogState(() => error = null);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final text = _feedbackController.text.trim();
                if (text.isEmpty) {
                  setDialogState(
                    () =>
                        error = 'Say what happened, or what you would change.',
                  );
                  return;
                }
                Navigator.pop(context, text);
              },
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );

    if (message == null || !mounted) return;

    final info = _packageInfo;
    try {
      await feedbackRepository.submit(
        storeId: storeId,
        message: message,
        version: info?.version ?? 'unknown',
        build: info?.buildNumber ?? 'unknown',
        uid: authRepository.currentUid,
      );
      if (mounted) showInfo(context, 'Thanks — that went through.');
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need your password, or a passkey, to get back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          DestructiveButton(
            label: 'Log out',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Signing out rarely fails, but when it does the person is still signed in
    // and the screen has not changed — so without this they would tap Log out,
    // watch nothing happen, and have no idea why.
    try {
      await authRepository.signOut();
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  /// Two steps, because the owner's version is not reversible and is not only
  /// about them: it takes the shop's entire history and every colleague's
  /// login with it.
  Future<void> _deleteAccount(AppUser user) async {
    final owner = user.role == UserRole.owner;
    final store = owner ? await storeRepository.fetch(user.storeId) : null;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Text(
          owner
              ? 'You own ${store?.name ?? 'this store'}. Deleting your account '
                    'closes it: every order, every day\'s takings, the menu, and '
                    'your colleagues\' logins all go with it. There is no undo '
                    'and no export afterwards.'
              : 'Your login and your place on this store are deleted. The '
                    'orders you rang up stay on the store\'s books.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep my account'),
          ),
          DestructiveButton(
            label: 'Continue',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    String? typedName;
    if (owner) {
      // Typing the shop's name is the only thing between a mis-tap and a
      // business's records.
      typedName = await _askForStoreName(store?.name ?? '');
      if (typedName == null || !mounted) return;
    }

    try {
      await authRepository.deleteAccount(storeName: typedName);
      // Signed out here rather than left to the auth listener, which is what
      // this used to assume. Deleting the account happens on the server, and
      // FirebaseAuth on this device does not find out until its token is next
      // refreshed — up to an hour later. Until then the app sits on a signed-in
      // session belonging to an account that no longer exists, every read
      // failing, which is exactly the screen this whole flow was reported for.
      //
      // Signing out locally makes the auth stream fire now, and the listener at
      // the root takes the routes above it with it.
      try {
        await authRepository.signOut();
      } catch (_) {
        // The deletion succeeded, which is the part that cannot be undone.
        // Failing to tidy up the local session afterwards is not worth an
        // error message about; the next launch signs out anyway.
      }
    } on AuthException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  Future<String?> _askForStoreName(String storeName) => confirmByTyping(
    context,
    title: 'Type the store name to confirm',
    phrase: storeName,
    fieldLabel: 'Store name',
    confirmLabel: 'Delete everything',
  );
}

/// The version, and whether Google Play is serving a newer one.
///
/// Its own widget because it owns a subscription: a flexible update reports
/// its progress on a stream, and that has to be cancelled with the row rather
/// than with the screen's other state.
class _VersionTile extends StatefulWidget {
  const _VersionTile(this.info);

  /// Null until `PackageInfo` answers. The row still renders — a version that
  /// has not arrived is a caption, not a reason to hold the list back.
  final PackageInfo? info;

  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  AppUpdateState _state = const AppUpdateState(UpdateStage.unavailable);
  StreamSubscription<InstallStatus>? _progress;

  /// Set while the Play dialog is up, so a second tap cannot start a second
  /// download.
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _check();
    if (AppUpdates.supported) {
      _progress = AppUpdates.progress.listen(
        _onInstallStatus,
        // A broken progress stream must not take the screen with it. The
        // download is Play's to finish either way; the worst case is a row
        // that stops narrating it.
        onError: (Object _) {},
      );
    }
  }

  @override
  void dispose() {
    _progress?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final state = await AppUpdates.check();
    if (mounted) setState(() => _state = state);
  }

  void _onInstallStatus(InstallStatus status) {
    if (!mounted) return;
    final code = _state.availableVersionCode;
    setState(() {
      _state = switch (status) {
        InstallStatus.downloaded => AppUpdateState(
          UpdateStage.readyToInstall,
          availableVersionCode: code,
        ),
        InstallStatus.pending || InstallStatus.downloading => AppUpdateState(
          UpdateStage.downloading,
          availableVersionCode: code,
        ),
        // Cancelled or failed puts the button back rather than leaving a
        // progress bar that has stopped moving.
        InstallStatus.failed || InstallStatus.canceled => AppUpdateState(
          UpdateStage.available,
          availableVersionCode: code,
        ),
        _ => _state,
      };
    });
  }

  Future<void> _download() async {
    setState(() => _starting = true);
    try {
      final started = await AppUpdates.download();
      if (!mounted) return;
      // Declining is a normal answer in the middle of a shift, not an error.
      if (!started) setState(() => _starting = false);
    } catch (e) {
      if (mounted) {
        setState(() => _starting = false);
        showFailure(context, e);
      }
    }
  }

  Future<void> _install() async {
    try {
      await AppUpdates.install();
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  Future<void> _openListing() async {
    final package = widget.info?.packageName;
    if (package == null) return;
    try {
      await AppUpdates.openListing(package);
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  /// `Revenue 3.0.0 (3)` — the line somebody pastes into a support message.
  String get _installed {
    final info = widget.info;
    if (info == null) return 'Reading…';
    return '${info.appName} ${info.version} (${info.buildNumber})';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return switch (_state.stage) {
      UpdateStage.available => SettingTile.inline(
        icon: Icons.system_update_rounded,
        title: 'Update available',
        subtitle:
            'A newer build is on Google Play. It downloads in the '
            'background — the till keeps working. You are on $_installed.',
        trailing: _starting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FilledButton(onPressed: _download, child: const Text('Update')),
      ),
      UpdateStage.downloading => SettingTile.inline(
        icon: Icons.downloading_rounded,
        title: 'Downloading update',
        subtitle:
            'Carry on serving — you will be asked to restart when it '
            'is ready.',
        trailing: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      UpdateStage.readyToInstall => SettingTile.inline(
        icon: Icons.restart_alt_rounded,
        title: 'Update ready',
        subtitle:
            'Restarting takes a few seconds. Anything rung up is '
            'already saved.',
        trailing: FilledButton(
          onPressed: _install,
          child: const Text('Restart'),
        ),
      ),
      UpdateStage.current => SettingTile.readOnly(
        icon: Icons.verified_outlined,
        title: 'Version',
        subtitle: '$_installed · up to date',
      ),
      // Play could not be asked: not an Android build, no Play Services, a
      // sideloaded APK, or simply offline. Saying "up to date" here would be a
      // guess, so the row offers the listing instead of an answer.
      UpdateStage.unavailable =>
        AppUpdates.supported
            ? SettingTile.inline(
                icon: Icons.info_outline,
                title: 'Version',
                subtitle: '$_installed · check Google Play for a newer one',
                trailing: Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                onTap: _openListing,
              )
            : SettingTile.readOnly(
                icon: Icons.info_outline,
                title: 'Version',
                subtitle: _installed,
              ),
    };
  }
}
