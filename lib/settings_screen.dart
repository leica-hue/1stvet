import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final user = FirebaseAuth.instance.currentUser;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _vetStatus = 'Loading...';
  final List<String> _statusOptions = ['Available', 'Unavailable'];
  bool _isInactive = false;

  @override
  void initState() {
    super.initState();
    _loadVetStatus();
  }

  Future<void> _loadVetStatus() async {
    if (user == null) return;

    final doc = await _firestore.collection('vets').doc(user!.uid).get();
    if (doc.exists) {
      final data = doc.data();
      final inactive = data?['inactive'] ?? false;
      final status = data?['status'] ?? 'Available';
      if (!mounted) return;
      setState(() {
        _isInactive = inactive;
        _vetStatus = inactive ? 'Unavailable (Deactivated)' : status;
      });
    } else {
      if (!mounted) return;
      setState(() {
        _vetStatus = 'Status not found';
      });
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    if (user == null) return;
    try {
      await _firestore.collection('vets').doc(user!.uid).update({'status': newStatus});
      if (!mounted) return;
      setState(() {
        _vetStatus = newStatus;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Status updated to "$newStatus"'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to update status: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _setInactive(bool value) async {
    if (user == null) return;
    try {
      await _firestore.collection('vets').doc(user!.uid).update({'inactive': value});
      if (!mounted) return;
      setState(() {
        _isInactive = value;
        _vetStatus = value ? 'Unavailable (Deactivated)' : 'Available';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? 'Account deactivated' : 'Account reactivated'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to update account status: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  // --- PASSWORD CHANGE IMPLEMENTATION ---

  // Dialog for current password (re-authentication) with working visibility toggle
// MODIFIED Dialog to ask for the current password (re-authentication)
Future<String?> _showCurrentPasswordDialog() async {
  final TextEditingController passwordController = TextEditingController();
  // State variable defined OUTSIDE the StatefulBuilder's builder function
  bool obscureText = true; 

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setStateSB) {
          return AlertDialog(
            title: const Text('Confirm Current Password'),
            content: TextField(
              controller: passwordController,
              obscureText: obscureText, // Uses the state variable
              decoration: InputDecoration(
                labelText: 'Enter your current password',
                suffixIcon: IconButton(
                  icon: Icon(
                    obscureText ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    // This setStateSB updates the variable declared outside
                    setStateSB(() { 
                      obscureText = !obscureText;
                    });
                  },
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context, passwordController.text),
                  child: const Text('Confirm')),
            ],
          );
        },
      );
    },
  );
}

  // Dialog for new password with working visibility toggle and validation
// MODIFIED Dialog to ask for the new password
Future<String?> _showNewPasswordDialog() async {
  final TextEditingController newPasswordController = TextEditingController();
  // State variable defined OUTSIDE the StatefulBuilder's builder function
  bool obscureText = true; 

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setStateSB) {
          return AlertDialog(
            title: const Text('Set New Password'),
            content: TextField(
              controller: newPasswordController,
              obscureText: obscureText, // Uses the state variable
              decoration: InputDecoration(
                labelText: 'Enter new password (min 6 characters)',
                suffixIcon: IconButton(
                  icon: Icon(
                    obscureText ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    // This setStateSB updates the variable declared outside
                    setStateSB(() {
                      obscureText = !obscureText;
                    });
                  },
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: () {
                    final newPass = newPasswordController.text;
                    if (newPass.length < 6) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Password must be at least 6 characters.')),
                      );
                    } else {
                      Navigator.pop(context, newPass);
                    }
                  },
                  child: const Text('Set Password')),
            ],
          );
        },
      );
    },
  );
}
  // Re-authenticate user
  Future<bool> _reauthenticate(String password) async {
    if (user == null || user?.email == null) return false;

    try {
      final credential =
          EmailAuthProvider.credential(email: user!.email!, password: password);
      await user!.reauthenticateWithCredential(credential);
      return true;
    } on FirebaseAuthException catch (e) {
      if (!mounted) return false;
      String message;
      if (e.code == 'wrong-password') {
        message = 'Incorrect current password.';
      } else {
        message = 'Re-authentication failed. Try logging in again.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return false;
    }
  }

  // Main function to handle password change
  Future<void> _changePassword() async {
    if (user == null) return;

    // 1. Get the new desired password
    final newPassword = await _showNewPasswordDialog();
    if (newPassword == null || newPassword.isEmpty) return;

    // 2. Get the current password for re-authentication
    final currentPassword = await _showCurrentPasswordDialog();
    if (currentPassword == null || currentPassword.isEmpty) return;

    // 3. Re-authenticate
    final authenticated = await _reauthenticate(currentPassword);
    if (!authenticated) return;

    // 4. Update password
    try {
      await user!.updatePassword(newPassword);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password changed successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to change password: ${e.message}'),
            backgroundColor: Colors.red),
      );
    }
  }
  
  // --- END PASSWORD CHANGE IMPLEMENTATION ---

  Future<void> _deleteAccount() async {
    if (user == null) return;

    // Ask for password
    final password = await _showCurrentPasswordDialog(); // Reusing the password dialog for security
    if (password == null || password.isEmpty) return;

    final authenticated = await _reauthenticate(password);
    if (!authenticated) return;

    try {
      await _firestore.collection('vets').doc(user!.uid).delete();
      await user!.delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
      // Navigate to login screen
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
       if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete account: ${e.message}'), backgroundColor: Colors.red),
      );
    }
  }

  void _confirmAction(String title, String message, Function action) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              action();
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF728D5A),
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.lock),
            title: const Text('Change Password'),
            onTap: _changePassword, 
          ),
          const Divider(height: 30),
          const Text('Vet Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.circle),
            title: const Text('Availability'),
            trailing: DropdownButton<String>(
              value: _statusOptions.contains(_vetStatus) ? _vetStatus : 'Available',
              items: _statusOptions
                  .map((status) => DropdownMenuItem(value: status, child: Text(status)))
                  .toList(),
              onChanged: (value) {
                if (value != null) _updateStatus(value);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever),
            title: const Text('Delete Account'),
            onTap: () => _confirmAction(
              'Delete Account',
              'This action is permanent and irreversible. Your data will be deleted. Do you really want to proceed?',
              _deleteAccount,
            ),
          ),
        ],
      ),
    );
  }
}