import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../database/repositories.dart';
import '../widgets/feedback.dart';
import 'theme_controller.dart';

class AppSettings extends StatefulWidget {
  final String storeID;
  const AppSettings(this.storeID, {super.key});

  @override
  State<AppSettings> createState() => _AppSettingsState();
}

class _AppSettingsState extends State<AppSettings> {
  late PackageInfo packageInfo = PackageInfo(
    appName: 'Unknown',
    packageName: 'Unknown',
    version: 'Unknown',
    buildNumber: 'Unknown',
    buildSignature: 'Unknown',
  );

  final TextEditingController feedbackController = TextEditingController();
  bool isSubmitting = false; // 用來控制提交狀態的變量

  @override
  void initState() {
    super.initState();
    getAppInfo();
  }

  @override
  void dispose() {
    feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('App Settings'),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            _buildAppearanceTile(),
            const Divider(height: 8),
            ListTile(
              title: const Text('App Name'),
              subtitle: Text(packageInfo.appName),
            ),
            ListTile(
              title: const Text('App Version'),
              subtitle: Text(packageInfo.version),
            ),
            ListTile(
              title: const Text('App Build Number'),
              subtitle: Text(packageInfo.buildNumber),
            ),
            ListTile(
              leading: const Icon(Icons.feedback_outlined),
              title: const Text('Feedback'),
              subtitle: const Text('Improvement ideas, or a bug you hit'),
              onTap: () => showFeedbackDialog(context),
            ),
            if (isSubmitting) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  /// Light / dark / follow the system.
  ///
  /// The dark palette has existed in theme.dart since the theme was generated
  /// and was unreachable until now.
  Widget _buildAppearanceTile() {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeController,
      builder: (context, mode, _) => ListTile(
        leading: Icon(mode.icon),
        title: const Text('Appearance'),
        subtitle: Text(mode.label),
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

  Future<void> getAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        packageInfo = info;
      });
    } catch (e) {
      // Left alone on purpose: a missing version string is cosmetic, and there
      // is nothing the person reading this screen could do about it.
      debugPrint('Failed to get app info: $e');
    }
  }

  void showFeedbackDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Feedback'),
        content: TextField(
          controller: feedbackController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Tell us some improvement ideas or bugs you found',
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Send'),
            onPressed: () {
              sendFeedbackToFirebase();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Future<void> sendFeedbackToFirebase() async {
    if (feedbackController.text.isEmpty) {
      // 如果反饋內容為空，則提示用戶
      showError(context, 'Feedback cannot be empty');
      return;
    }

    setState(() {
      isSubmitting = true;
    });

    try {
      await feedbackRepository.submit(
        storeId: widget.storeID,
        message: feedbackController.text.trim(),
        version: packageInfo.version,
        build: packageInfo.buildNumber,
        uid: authRepository.currentUid,
      );
      if (!mounted) return;
      feedbackController.clear();
      showInfo(context, 'Thanks — that went through.');
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
  }
}
