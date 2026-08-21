import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'database/repositories.dart';
import 'login.dart';
import 'models/app_user.dart';
import 'models/store.dart';
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
  bool isSubmitting = false;

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
        // Dark status-bar icons, because the bar behind them is light.
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        // Transparent so the bar always matches the scaffold background
        // instead of drifting from it. Matches login.dart.
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
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
                          errorDescription: storeNameErrorMsg,
                          helperText:
                              "Ignored if the store ID already exists — "
                              "you will join that store instead"),
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
        String? helperText,
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
            helperText: helperText,
            helperMaxLines: 2,
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
        onPressed: isSubmitting ? null : registerUser,
        color: Colors.greenAccent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        child: isSubmitting
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
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
    if (isSubmitting || !validateInput()) return;
    setState(() => isSubmitting = true);

    final email = emailController.text.trim();

    try {
      final uid = await authRepository.register(
        email: email,
        password: passwordController.text,
      );

      await _provisionAccount(uid, email);

      if (!mounted) return;
      // Pop back to the root, which is already watching auth state and will
      // show the shell through the session gate. Pushing a second shell here
      // used to leave two of them mounted, each with its own timers.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      if (mounted) showAuthError(e);
    } catch (e) {
      // The auth account exists but its store data does not, which would leave
      // an account that can sign in and then find nothing. Undo it.
      await authRepository.deleteCurrentAccount();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Could not finish setting up the account: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  /// Creates the Firestore side of a new account.
  ///
  /// The user document is keyed by the Auth uid, not by email — every screen
  /// looks the user up by uid, and an email is something a person can change.
  ///
  /// Entering a store ID that already exists joins that store as staff;
  /// otherwise the store is created here, along with a starter menu, so a new
  /// owner does not land on an empty app.
  Future<void> _provisionAccount(String uid, String email) async {
    final storeId = storeIDController.text.trim();

    await userRepository.create(AppUser(
      uid: uid,
      email: email,
      displayName: nameController.text.trim(),
      storeId: storeId,
      role: UserRole.staff,
    ));

    if (await storeRepository.exists(storeId)) return;

    // Creating the store makes this person its owner. The role has to be
    // raised before the menu is seeded, because menu writes are manager-only.
    await userRepository.updateRole(uid, UserRole.owner);
    await storeRepository.create(Store(
      id: storeId,
      name: storeNameController.text.trim(),
      categories: MenuRepository.defaultCategories,
    ));
    await menuRepository.seedDefaults(storeId);
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

  /// Puts the failure where the person can act on it: under the field that
  /// caused it when there is one, in a snackbar when there is not.
  void showAuthError(AuthException e) {
    switch (e.failure) {
      case AuthFailure.weakPassword:
        setState(() => passwordErrorMsg = e.message);
      case AuthFailure.emailInUse:
      case AuthFailure.invalidEmail:
        setState(() => mailErrorMsg = e.message);
      default:
        _showError(e.message);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 6),
      content: Text(message),
    ));
  }

}
