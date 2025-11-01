import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {


  @override
  void initState() {
    super.initState();
  }


void _changePasswordDialog() {
  final oldPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final user = FirebaseAuth.instance.currentUser;

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Change Password"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: oldPasswordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: "Old Password"),
          ),
          TextField(
            controller: newPasswordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: "New Password"),
          ),
          TextField(
            controller: confirmPasswordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: "Confirm Password"),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () async {
            if (newPasswordController.text != confirmPasswordController.text) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Passwords do not match!")),
              );
              return;
            }

            if (user == null || user.email == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("No user logged in!")),
              );
              return;
            }

            try {
              // 🔹 Reauthenticate the user before changing password
              final cred = EmailAuthProvider.credential(
                email: user.email!,
                password: oldPasswordController.text,
              );

              await user.reauthenticateWithCredential(cred);

              // 🔹 Update password in Firebase Auth
              await user.updatePassword(newPasswordController.text);

              

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Password changed successfully!"),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } on FirebaseAuthException catch (e) {
              String errorMessage = "Error: ${e.message}";
              if (e.code == 'wrong-password') {
                errorMessage = "Old password is incorrect.";
              } else if (e.code == 'weak-password') {
                errorMessage = "New password is too weak.";
              } else if (e.code == 'requires-recent-login') {
                errorMessage = "Please log in again before changing password.";
              }

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(errorMessage),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF728D5A),
            foregroundColor: Colors.white,
          ),
          child: const Text("Save"),
        ),
      ],
    ),
  );
}


  void _aboutApp() {
    showAboutDialog(
      context: context,
      applicationName: 'Furever Vet Clinic',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.pets, size: 40),
      applicationLegalese: '© 2025 Furever Vet Clinic. All rights reserved.',
      children: [
        const SizedBox(height: 10),
        const Text(
          'Furever Vet Clinic is your trusted partner in managing pet health records, appointments, and veterinary services with ease.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF728D5A),
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Account',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.lock),
            title: const Text('Change Password'),
            onTap: _changePasswordDialog,
          ),
          const Divider(height: 30),
          const Text(
            'App',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('About App'),
            onTap: _aboutApp,
          ),
        ],
      ),
    );
  }
}
