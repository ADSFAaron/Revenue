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
# Flutter embedding — deliberately no blanket keeps
# ---------------------------------------------------------------------------
#
# What used to be here:
#
#   -keep class io.flutter.app.**       { *; }
#   -keep class io.flutter.plugin.**    { *; }
#   -keep class io.flutter.embedding.** { *; }
#   -keep class io.flutter.plugins.**   { *; }
#
# `{ *; }` forbids both renaming and removal, and those four packages are very
# nearly the whole Java/Kotlin surface of a Flutter app — Firebase, CameraX and
# Credential Manager all sit behind `io.flutter.plugins`. Play Console reported
# the result: 56% obfuscated, and no shrinking figure at all.
#
# They are also not what Flutter asks for. The SDK's own
# flutter_tools/gradle/flutter_proguard_rules.pro, which the Flutter Gradle
# plugin applies on every release build, says:
#
#   -if class * implements io.flutter.embedding.engine.plugins.FlutterPlugin
#   -keep,allowshrinking,allowobfuscation class <1>
#
# `allowshrinking, allowobfuscation` is the point: upstream keeps plugin
# classes reachable while letting R8 rename and prune them. The blanket keeps
# overrode that with the strictest possible reading.
#
# The stated reason for them — reflection from the engine and the generated
# plugin registrant — does not hold either. GeneratedPluginRegistrant.java
# constructs each plugin directly (`new FlutterFirebaseCorePlugin()`), which
# R8 traces like any other call; MainActivity and the FlutterApplication are
# named in AndroidManifest.xml, and AGP generates keep rules from the manifest
# on its own. The genuinely reflective case is the `-if` rule above.
#
# Anything that does turn out to need a keep belongs here as a named rule for
# that one class, not as a package wildcard.

# ---------------------------------------------------------------------------
# Class repackaging
# ---------------------------------------------------------------------------
#
# Flattens the surviving classes into the root package, which is what Play
# Console's "repackage classes" line asks for. It reports this as needing AGP
# 9.0 because 9.0 turns it on by default; it is an R8 directive and works now.
#
# R8 full mode (default since AGP 8.0) implies -allowaccessmodification, which
# is what lets repackaging actually move anything.
#
# If a release build ever breaks in a way that smells like a class being found
# by name, this is the first line to remove — it is the only rule here that
# changes where classes live.
-repackageclasses ''

# ---------------------------------------------------------------------------
# Line numbers in a Play crash report
# ---------------------------------------------------------------------------
#
# Without these, an obfuscated stack trace has no line numbers at all and the
# mapping file cannot put them back. Costs a few kilobytes.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
