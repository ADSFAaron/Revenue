import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
        child: Column(
          children: [
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
              title: const Text('Check for Update'),
              onTap: () {
                // 可以在這裡加上檢查更新的邏輯
              },
            ),
            ListTile(
              title: const Text('Feedback'),
              onTap: () {
                showFeedbackDialog(context);
              },
            ),
            if (isSubmitting) // 如果正在提交，顯示加載進度提示
              const CircularProgressIndicator(),
          ],
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
      // 錯誤處理，可以選擇提示用戶或者日誌紀錄
      print('Failed to get app info: $e');
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feedback cannot be empty')),
      );
      return;
    }

    setState(() {
      isSubmitting = true;
    });

    CollectionReference feedbackCollection =
    FirebaseFirestore.instance.collection('feedback');
    DocumentReference feedbackDoc = feedbackCollection.doc(widget.storeID);

    try {
      await feedbackDoc.get().then((DocumentSnapshot docSnapshot) async {
        final feedbackData = {
          'version': packageInfo.version,
          'build': packageInfo.buildNumber,
          'feedback': feedbackController.text,
          'timestamp': FieldValue.serverTimestamp(),
        };

        if (docSnapshot.exists) {
          // 更新現有的反饋記錄
          await feedbackDoc.update({
            'item': FieldValue.arrayUnion([feedbackData]), // 使用 arrayUnion 來追加數據
          });
        } else {
          // 新增反饋記錄
          await feedbackDoc.set({
            'item': [feedbackData],
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feedback submitted successfully')),
        );
      });
    } catch (e) {
      // 捕捉異常並提示用戶
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send feedback: $e')),
      );
    } finally {
      setState(() {
        isSubmitting = false;
      });
    }
  }
}
