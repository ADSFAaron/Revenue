import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uuid/uuid.dart';

import 'home.dart';
import 'login.dart';
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  late TextEditingController emailController,
      passwordController,
      rePasswordController,
      storeIDController,
      nameController,
      storeNameController;

  bool showPassword = false;

  String passwordErrorMsg = "",
      mailErrorMsg = "",
      storeIDMsg = "",
      rePasswordErrorMsg = "",
      nameErrorMsg = "",
      storeNameErrorMsg = "";

  @override
  void initState() {
    super.initState();
    emailController = TextEditingController();
    passwordController = TextEditingController();
    rePasswordController = TextEditingController();
    storeIDController = TextEditingController();
    nameController = TextEditingController();
    storeNameController = TextEditingController();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    rePasswordController.dispose();
    storeIDController.dispose();
    nameController.dispose();
    storeNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle.light,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Colors.grey[700],
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Container(
          height: MediaQuery.of(context).size.height - 100,
          width: double.infinity,
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                Text(
                  "Register",
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.black),
                ),
                SizedBox(height: 10),
                Text(
                  "Register a new account",
                  style: TextStyle(fontSize: 15, color: Colors.grey[700]),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 20, horizontal: 40),
                  child: Column(
                    children: <Widget>[
                      makeInput(
                          label: "Email",
                          controller: emailController,
                          errorDescription: mailErrorMsg),
                      makeInput(
                          label: "Password",
                          controller: passwordController,
                          obscureText: !showPassword,
                          errorDescription: passwordErrorMsg,
                          suffixIcon: passwordSuffixIcon()),
                      makeInput(
                          label: "Confirm Password",
                          controller: rePasswordController,
                          obscureText: !showPassword,
                          errorDescription: rePasswordErrorMsg),
                      makeStoreIDInput(),
                      makeInput(
                          label: "Name",
                          controller: nameController,
                          errorDescription: nameErrorMsg),
                      makeInput(
                          label: "Store Name",
                          controller: storeNameController,
                          errorDescription: storeNameErrorMsg),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 40),
                  child: buildRegisterButton(),
                ),
                SizedBox(height: 20),
                buildLoginRedirect(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget makeStoreIDInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          "StoreID",
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
        ),
        SizedBox(height: 5),
        TextField(
          controller: storeIDController,
          decoration: InputDecoration(
            errorText: storeIDMsg == "" ? null : storeIDMsg,
            contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 10),
            border:
            OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            suffixIcon: TextButton(
              onPressed: () {
                var uuid = Uuid();
                storeIDController.text = uuid.v4();
              },
              child: Text("Generate"),
            ),
          ),
        ),
        SizedBox(height: 20),
      ],
    );
  }

  Widget makeInput(
      {required String label,
        required TextEditingController controller,
        bool obscureText = false,
        required String errorDescription,
        Widget? suffixIcon}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
        ),
        SizedBox(height: 5),
        TextField(
          controller: controller,
          obscureText: obscureText,
          decoration: InputDecoration(
            errorText: errorDescription == "" ? null : errorDescription,
            contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 10),
            border:
            OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            suffixIcon: suffixIcon,
          ),
        ),
        SizedBox(height: 20),
      ],
    );
  }

  Widget passwordSuffixIcon() {
    return IconButton(
      onPressed: () {
        setState(() {
          showPassword = !showPassword;
        });
      },
      icon: showPassword
          ? Icon(Icons.visibility)
          : Icon(Icons.visibility_off),
    );
  }

  Widget buildRegisterButton() {
    return Container(
      padding: EdgeInsets.only(top: 3, left: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: Colors.black),
      ),
      child: MaterialButton(
        height: 60,
        minWidth: MediaQuery.of(context).size.width,
        onPressed: registerUser,
        color: Colors.greenAccent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        child: Text(
          'Register',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget buildLoginRedirect() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text("Already have an account? "),
        TextButton(
          child: const Text(
            "Login",
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => LoginPage()),
            );
          },
        ),
      ],
    );
  }

  Future<void> registerUser() async {
    if (!validateInput()) return;

    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
          email: emailController.text,
          password: passwordController.text);

      await addUserToFirestore();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginHomePage()),
      );
    } on FirebaseAuthException catch (e) {
      handleFirebaseErrors(e);
    }
  }

  bool validateInput() {
    setState(() {
      mailErrorMsg = emailController.text.isEmpty ? 'Enter the email' : '';
      passwordErrorMsg =
      passwordController.text.isEmpty ? 'Enter the password' : '';
      rePasswordErrorMsg =
      passwordController.text != rePasswordController.text
          ? 'Passwords do not match'
          : '';
      storeIDMsg = storeIDController.text.isEmpty ? 'Enter the store ID' : '';
      nameErrorMsg = nameController.text.isEmpty ? 'Enter the name' : '';
      storeNameErrorMsg =
      storeNameController.text.isEmpty ? 'Enter the store name' : '';
    });
    return mailErrorMsg.isEmpty &&
        passwordErrorMsg.isEmpty &&
        rePasswordErrorMsg.isEmpty &&
        storeIDMsg.isEmpty &&
        nameErrorMsg.isEmpty &&
        storeNameErrorMsg.isEmpty;
  }

  void handleFirebaseErrors(FirebaseAuthException e) {
    if (e.code == 'weak-password') {
      setState(() {
        passwordErrorMsg = 'The password provided is too weak.';
      });
    } else if (e.code == 'email-already-in-use') {
      setState(() {
        mailErrorMsg = 'The account already exists for that email.';
      });
    }
  }

  Future<void> addUserToFirestore() async {
    CollectionReference users = FirebaseFirestore.instance.collection('users');
    await users.add({
      'email': emailController.text,
      'storeID': storeIDController.text,
      'name': nameController.text,
      'storeName': storeNameController.text,
    });
  }
}
