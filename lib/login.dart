import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'home.dart';

import 'animation/FadeAnimation.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  String errorString = "";
  bool errorVisible = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
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
      body: SingleChildScrollView(
        child: SizedBox(
          height: MediaQuery.of(context).size.height,
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  FadeAnimation(
                    0,
                    Text(
                      "Login",
                      style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Colors.black),
                    ),
                  ),
                  SizedBox(height: 10),
                  FadeAnimation(
                      100,
                      Text(
                        "Login to your account",
                        style: TextStyle(fontSize: 15, color: Colors.grey[700]),
                      )),
                  SizedBox(height: 10),
                  Visibility(
                    visible: errorVisible,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: SizedBox(
                          width: double.infinity,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: Colors.red),
                            child: Center(
                                child: Text(
                                  errorString,
                                  style: TextStyle(fontSize: 18, color: Colors.white),
                                )),
                          )),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 20, horizontal: 40),
                    child: Column(
                      children: <Widget>[
                        FadeAnimation(
                            250,
                            makeInput(
                                label: "Email", controller: emailController)),
                        FadeAnimation(
                            500,
                            makeInput(
                                label: "Password",
                                obscureText: true,
                                controller: passwordController)),
                      ],
                    ),
                  ),
                  FadeAnimation(
                      750,
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 40,
                        ),
                        child: Container(
                          padding: EdgeInsets.only(top: 3, left: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(color: Colors.black),
                          ),
                          child: MaterialButton(
                            height: 60,
                            minWidth: MediaQuery.of(context).size.width,
                            onPressed: () {
                              signIn(emailController.text.trim(),
                                  passwordController.text.trim());
                            },
                            color: Colors.greenAccent,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(50)),
                            child: Text(
                              'Login',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      )),
                ],
              ),
              FadeAnimation(
                  1000,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Don't have an account? "),
                      Text(
                        "Sign UP",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  )),
              FadeAnimation(
                1250,
                SizedBox(
                  height: MediaQuery.of(context).size.height / 4,
                  child: SvgPicture.asset(
                    'assets/login_bg.svg',
                    fit: BoxFit.fitHeight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future signIn(email, password) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return const Center(child: CircularProgressIndicator());
      },
    );

    try {
      UserCredential credential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      if (credential.user != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => LoginHomePage()),
        );
      }
    } on FirebaseAuthException catch (e) {
      Navigator.pop(context);
      showError(e.message ?? 'Unknown Error');
    }
  }

  void showError(String message) {
    final snackBar = SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  Widget makeInput({label, obscureText = false, controller}) {
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
          textInputAction: obscureText ? TextInputAction.done : TextInputAction.next,
          onSubmitted: (value) {
            if (obscureText) {
              signIn(emailController.text.trim(), passwordController.text.trim());
            }
          },
          decoration: InputDecoration(
            contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 10),
            border: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
          ),
        ),
        SizedBox(height: 20),
      ],
    );
  }

  void validateAndSignIn() {
    String email = emailController.text.trim();
    String password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      showError('Please fill all fields');
      return;
    }

    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
      showError('Invalid Email Format');
      return;
    }

    signIn(email, password);
  }

}
