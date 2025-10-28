import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkMode = false;
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _darkMode = prefs.getBool('darkMode') ?? false;
      _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', _darkMode);
    await prefs.setBool('notificationsEnabled', _notificationsEnabled);
  }

  void _changePasswordDialog() {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

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
            onPressed: () {
              if (newPasswordController.text != confirmPasswordController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Passwords do not match!")),
                );
                return;
              }
              // TODO: Connect to real password change API here
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Password changed successfully!")),
              );
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

  void _notificationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Notification Preferences"),
        content: SwitchListTile(
          title: const Text("Enable Notifications"),
          value: _notificationsEnabled,
          activeColor: const Color(0xFF728D5A),
          onChanged: (val) {
            setState(() {
              _notificationsEnabled = val;
            });
            _savePreferences();
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(val
                    ? "Notifications enabled"
                    : "Notifications disabled"),
              ),
            );
          },
        ),
      ),
    );
  }

  void _themeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Theme Settings"),
        content: SwitchListTile(
          title: const Text("Dark Mode"),
          value: _darkMode,
          activeColor: const Color(0xFF728D5A),
          onChanged: (val) {
            setState(() {
              _darkMode = val;
            });
            _savePreferences();
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text(val ? "Dark mode enabled" : "Light mode enabled"),
              ),
            );
          },
        ),
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
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('Notification Preferences'),
            onTap: _notificationDialog,
          ),
          ListTile(
            leading: const Icon(Icons.color_lens),
            title: const Text('Theme'),
            onTap: _themeDialog,
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
