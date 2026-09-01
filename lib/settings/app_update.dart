import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where the source lives.
///
/// Quoted in the app rather than only in the README: the AGPL asks that people
/// using the software over a network can reach its source, and the people
/// using this one are looking at a phone, not at a repository.
const String kSourceUrl = 'https://github.com/ADSFAaron/Revenue';

/// The privacy policy, served from the same Firebase Hosting site as the web
/// build (web/privacy.html).
///
/// Google Play requires this as a link on the store listing. It is in the app
/// as well because the listing is not where somebody wonders what happens to
/// their shop's takings — this screen is.
const String kPrivacyPolicyUrl =
    'https://revenueapp-b8849.web.app/privacy.html';

/// Where this install is in relation to what Google Play is serving.
enum UpdateStage {
  /// Not a Play install: iOS, the web build, Windows, a debug run, or an APK
  /// somebody sideloaded. Play Core cannot answer for any of those, and the
  /// screen must not present that as "you are up to date".
  unavailable,

  /// Play says this is the current build.
  current,

  /// A newer build is published and this device may take it.
  available,

  /// Downloading in the background. The shop keeps trading while it does.
  downloading,

  /// On the device, waiting for the restart that swaps it in.
  readyToInstall,
}

/// What Play answered, and which build it was talking about.
class AppUpdateState {
  const AppUpdateState(this.stage, {this.availableVersionCode});

  final UpdateStage stage;

  /// The `versionCode` of the build on Play. Play returns no version *name*,
  /// so this is the only thing that can honestly be shown, and it is a build
  /// number rather than the "3.1.0" a person recognises — which is why the
  /// screen leads with the fact that there is one rather than with the digits.
  final int? availableVersionCode;
}

/// Asking Google Play whether this till is running the current build.
///
/// Play is the only authority on that question, and asking it directly is what
/// makes this worth having: the alternative — keeping the latest version
/// number in a Firestore document and comparing against it — needs somebody to
/// remember to edit that document on every release, and the failure mode of
/// forgetting is an app that swears it is current for months.
///
/// A shop is the reason the flexible flow is used rather than the immediate
/// one. An immediate update takes the screen over and restarts the app, which
/// is fine on a phone and unacceptable on the thing taking money at a counter
/// at seven in the evening. Flexible downloads in the background, keeps the
/// till working throughout, and asks for the restart when the shopkeeper is
/// ready for it.
class AppUpdates {
  const AppUpdates._();

  /// Play Core exists on Android alone. Everywhere else this is not a failure
  /// to report, just a question that cannot be asked.
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<AppUpdateState> check() async {
    if (!supported) return const AppUpdateState(UpdateStage.unavailable);
    try {
      final info = await InAppUpdate.checkForUpdate();

      // `developerTriggeredUpdateInProgress` is a download this app already
      // started on a previous run and never finished — it must resume, not be
      // reported as "up to date".
      if (info.installStatus == InstallStatus.downloaded) {
        return AppUpdateState(
          UpdateStage.readyToInstall,
          availableVersionCode: info.availableVersionCode,
        );
      }
      if (info.installStatus == InstallStatus.downloading) {
        return AppUpdateState(
          UpdateStage.downloading,
          availableVersionCode: info.availableVersionCode,
        );
      }
      if (info.updateAvailability == UpdateAvailability.updateAvailable &&
          info.flexibleUpdateAllowed) {
        return AppUpdateState(
          UpdateStage.available,
          availableVersionCode: info.availableVersionCode,
        );
      }
      if (info.updateAvailability == UpdateAvailability.updateNotAvailable) {
        return const AppUpdateState(UpdateStage.current);
      }
      // `unknown`, or an update Play will not let this device take flexibly.
      // Either way the honest answer is that the question went unanswered, and
      // the row falls back to a link to the listing.
      return const AppUpdateState(UpdateStage.unavailable);
    } catch (_) {
      // A debug run, a sideloaded APK, no Play Services, or no network. None
      // of those are worth an error in front of a shopkeeper who did not ask —
      // this check runs on its own, unprompted, every time the screen opens.
      return const AppUpdateState(UpdateStage.unavailable);
    }
  }

  /// Emits while a flexible download runs. Android only.
  static Stream<InstallStatus> get progress => InAppUpdate.installUpdateListener;

  /// Starts the background download. Returns false if the person declined or
  /// Play refused, so the caller can put the button back.
  static Future<bool> download() async {
    final result = await InAppUpdate.startFlexibleUpdate();
    return result == AppUpdateResult.success;
  }

  /// Swaps the downloaded build in. This restarts the app.
  static Future<void> install() => InAppUpdate.completeFlexibleUpdate();

  /// The Play listing, for when the in-app flow is not available.
  ///
  /// `market:` hands straight to the Play app and is what a phone with Play on
  /// it should get; the https form is the fallback for a device without it,
  /// and for anybody reading this on the web build.
  static Future<bool> openListing(String packageName) async {
    final market = Uri.parse('market://details?id=$packageName');
    if (await canLaunchUrl(market)) {
      return launchUrl(market, mode: LaunchMode.externalApplication);
    }
    return launchUrl(
      Uri.parse('https://play.google.com/store/apps/details?id=$packageName'),
      mode: LaunchMode.externalApplication,
    );
  }
}
