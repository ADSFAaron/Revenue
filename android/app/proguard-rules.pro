# R8 keeps for the release build.
#
# Only the Java/Kotlin half of the app goes through R8 at all — the Dart code
# is AOT-compiled into libapp.so long before this runs, so nothing in lib/ is
# affected by anything in this file. What R8 is shrinking is Firebase, Play
# Core, CameraX and Credential Manager, and each of those ships its own
# consumer rules inside its AAR. This file is only for what those do not
# cover.

# ---------------------------------------------------------------------------
# Play Core
# ---------------------------------------------------------------------------
#
# Flutter's Android embedding references Play Core's deferred-components and
# split-install classes (FlutterPlayStoreSplitApplication, PlayStoreDeferred-
# ComponentManager) whether or not the app uses deferred components. This one
# does not, so those classes are genuinely absent and R8 stops on the dangling
# references.
#
# `in_app_update` pulls in `com.google.android.play:app-update`, which is a
# different artifact from the `com.google.android.play:core` the embedding is
# reaching for — having one does not satisfy the other.
#
# Warning suppressed rather than the classes kept: they do not exist to keep,
# and the code paths that would reach them are unreachable in an app with no
# deferred components.
-dontwarn com.google.android.play.core.**

# ---------------------------------------------------------------------------
# Flutter embedding
# ---------------------------------------------------------------------------
#
# Reached reflectively by the engine and by the generated plugin registrant
# rather than by any call R8 can trace.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# ---------------------------------------------------------------------------
# Line numbers in a Play crash report
# ---------------------------------------------------------------------------
#
# Without these, an obfuscated stack trace has no line numbers at all and the
# mapping file cannot put them back. Costs a few kilobytes.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
