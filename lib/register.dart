import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uuid/uuid.dart';

import 'login.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({Key? key}) : super(key: key);

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  late TextEditingController emailController,
      passwordController,
      rePasswordController,
      storeIDController;
  bool _validate = false, showPassword = false;
  String passwordErrorMsg = "",
      mailErrorMsg = "",
      storeIDMsg = "",
      rePasswordErrorMsg = "";

  @override
  void initState() {
    super.initState();
    emailController = TextEditingController();
    passwordController = TextEditingController();
    rePasswordController = TextEditingController();
    storeIDController = TextEditingController();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    rePasswordController.dispose();
    storeIDController.dispose();
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
            scrollDirection: Axis.vertical,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                Column(
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
                      padding:
                          EdgeInsets.symmetric(vertical: 20, horizontal: 40),
                      child: Column(
                        children: <Widget>[
                          makeInput(
                              label: "Email",
                              Controller: emailController,
                              errorDescription: mailErrorMsg),
                          makeInput(
                              label: "Password",
                              Controller: passwordController,
                              obscureText: showPassword,
                              errorDescription: passwordErrorMsg),
                          makeInput(
                              label: "Confirm Password",
                              Controller: rePasswordController,
                              errorDescription: rePasswordErrorMsg,
                              obscureText: false),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                "StoreID",
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87),
                              ),
                              SizedBox(height: 5),
                              TextField(
                                controller: storeIDController,
                                decoration: InputDecoration(
                                  errorText:
                                      storeIDMsg == "" ? null : storeIDMsg,
                                  contentPadding: EdgeInsets.symmetric(
                                      vertical: 0, horizontal: 10),
                                  border: OutlineInputBorder(
                                      borderSide:
                                          BorderSide(color: Colors.grey)),
                                  enabledBorder: OutlineInputBorder(
                                      borderSide:
                                          BorderSide(color: Colors.grey)),
                                  suffixIcon: TextButton(
                                      onPressed: () {
                                        var uuid = Uuid();
                                        String u = uuid.v4();
                                        storeIDController.text = u;
                                      },
                                      child: Text("Generate")),
                                ),
                              ),
                              SizedBox(height: 20),
                            ],
                          ),
                        ],
                      ),
                    ),
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
                          onPressed: () async {
                            print('Email: $emailController.text');

                            if (emailController.text.isEmpty) {
                              setState(() {
                                mailErrorMsg = 'Enter the email';
                              });
                              return;
                            } else {
                              setState(() {
                                mailErrorMsg = '';
                              });
                            }
                            if (passwordController.text.isEmpty) {
                              setState(() {
                                passwordErrorMsg = 'Enter the password';
                              });
                              return;
                            } else {
                              setState(() {
                                passwordErrorMsg = '';
                              });
                            }

                            if (storeIDController.text.isEmpty) {
                              setState(() {
                                storeIDMsg = 'Enter the store ID';
                              });
                              return;
                            } else {
                              setState(() {
                                storeIDMsg = '';
                              });
                            }

                            if (passwordController.text ==
                                rePasswordController.text) {
                              try {
                                UserCredential userCredential =
                                    await FirebaseAuth.instance
                                        .createUserWithEmailAndPassword(
                                            email: emailController.text,
                                            password: passwordController.text);
                              } on FirebaseAuthException catch (e) {
                                if (e.code == 'weak-password') {
                                  print('The password provided is too weak.');
                                  setState(() {
                                    passwordErrorMsg =
                                        'The password provided is too weak.';
                                  });
                                } else if (e.code == 'email-already-in-use') {
                                  print(
                                      'The account already exists for that email.');
                                  mailErrorMsg =
                                      'The account already exists for that email.';
                                }
                              } catch (e) {
                                print(e);
                              }
                            } else {
                              setState(() {
                                rePasswordErrorMsg =
                                    'Confirm Password no match';
                              });
                            }
                          },
                          color: Colors.greenAccent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50)),
                          child: Text(
                            'Register',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Already have an account? "),
                        TextButton(
                          child: const Text(
                            "Login",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 20,
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => LoginPage()),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget makeInput({label, Controller, obscureText = true, errorDescription}) {
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
          controller: Controller,
          obscureText: !obscureText,
          decoration: InputDecoration(
            errorText: errorDescription == "" ? null : errorDescription,
            contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 10),
            border:
                OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            enabledBorder:
                OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            suffixIcon: label == "Password"
                ? IconButton(
                    onPressed: () {
                      setState(() {
                        showPassword = !showPassword;
                      });
                    },
                    icon: showPassword
                        ? Icon(Icons.visibility)
                        : Icon(Icons.visibility_off),
                  )
                : null,
          ),
        ),
        SizedBox(height: 20),
      ],
    );
  }
}
