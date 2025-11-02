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

  // Show password dialog
  Future<String?> _showPasswordDialog() async {
    final TextEditingController _passwordController = TextEditingController();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Password'),
          content: TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Enter your password'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, _passwordController.text),
                child: const Text('Confirm')),
          ],
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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect password. Action cancelled.')),
      );
      return false;
    }
  }

  Future<void> _deleteAccount() async {
    if (user == null) return;

    // Ask for password
    final password = await _showPasswordDialog();
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
      Navigator.of(context).popUntil((route) => route.isFirst); // back to login screen
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete account: $e'), backgroundColor: Colors.red),
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
            onTap: () {}, // keep your existing password change dialog
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
            leading: Icon(_isInactive ? Icons.toggle_off : Icons.toggle_on),
            title: Text(_isInactive ? 'Reactivate Account' : 'Deactivate Account'),
            onTap: () => _confirmAction(
              _isInactive ? 'Reactivate Account' : 'Deactivate Account',
              _isInactive
                  ? 'Do you want to reactivate your account?'
                  : 'Do you want to deactivate your account?',
              () => _setInactive(!_isInactive),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever),
            title: const Text('Delete Account'),
            onTap: () => _confirmAction(
              'Delete Account',
              'This action is permanent. Do you really want to delete your account?',
              _deleteAccount,
            ),
          ),
        ],
      ),
    );
  }
}
