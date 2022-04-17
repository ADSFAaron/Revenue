import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppSettings extends StatefulWidget {
  String storeID;
  AppSettings(this.storeID, {Key? key}) : super(key: key);

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

  TextEditingController feedbackController = TextEditingController();

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
            title: const Text('App version'),
            subtitle: Text(packageInfo.version),
          ),
          ListTile(
            title: const Text('App buildNumber'),
            subtitle: Text(packageInfo.buildNumber),
          ),
          ListTile(
            title: const Text('Check for update'),
          ),
          ListTile(
            enabled: false,
            title: const Text('Feedback'),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Feedback'),
                  content: TextField(
                    controller: feedbackController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      labelText:
                          'Tell us some improvement ideas or bugs you found',
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
            },
          ),
        ],
      )),
    );
  }

  Future<void> getAppInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      packageInfo = info;
    });
  }

  void sendFeedbackToFirebase() {
    CollectionReference feedbackCollection =
        FirebaseFirestore.instance.collection('feedback');
    DocumentReference feedback = feedbackCollection.doc(widget.storeID);

    feedback.get().then((DocumentSnapshot value) {
      if (value.exists) {
        feedback.update({
          'item': [
            {
              'version': packageInfo.version,
              'build': packageInfo.buildNumber,
              'feedback': feedbackController.text,
              'timestamp': FieldValue.serverTimestamp(),
            }
          ]
        });
      } else {
        feedbackCollection.doc(widget.storeID).set({
          'item': [
            {
              'version': packageInfo.version,
              'build': packageInfo.buildNumber,
              'feedback': feedbackController.text,
              'timestamp': FieldValue.serverTimestamp(),
            }
          ]
        }).catchError((onError) {
          print(onError);
        }).then((value) => print("Successful feedback"));
        // feedback.set({
        //   'item': [
        //     {
        //       'version': packageInfo.version,
        //       'build': packageInfo.buildNumber,
        //       'feedback': feedbackController.text,
        //       'timestamp': FieldValue.serverTimestamp(),
        //     }
        //   ],
        // });
      }
    });
  }
}
