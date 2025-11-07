import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_application_1/login_screen.dart';
import 'package:flutter_application_1/settings_screen.dart';
import 'package:flutter_application_1/user_prefs.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import 'payment_option_screen.dart';
import 'dashboard_screen.dart';
import 'appointments_screen.dart';
import 'patients_list_screen.dart';
import 'analytics_screen.dart';
import 'feedback_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController licenseController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController clinicController = TextEditingController();

  String specialization = 'Pathology';
  List<String> specializations = ['Pathology', 'Behaviour', 'Dermatology', 'General'];

  File? profileImage;
  File? idImage;
  bool isVerified = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // ✅ Load profile data
  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      nameController.text = prefs.getString('name') ?? 'Dr. Sarah Doe';
      licenseController.text = prefs.getString('license') ?? '';
      emailController.text = prefs.getString('email') ?? 'sarah@vetclinic.com';
      locationController.text = prefs.getString('location') ?? '';
      clinicController.text = prefs.getString('clinic') ?? '';
      specialization = prefs.getString('specialization') ?? 'Pathology';
      isVerified = prefs.getBool('isVerified') ?? false;

      final profilePath = prefs.getString('profileImage');
      if (!kIsWeb && profilePath != null) {
        try {
          final file = File(profilePath);
          if (file.existsSync()) profileImage = file;
        } catch (_) {}
      }

      final idPath = prefs.getString('idImage');
      if (!kIsWeb && idPath != null) {
        try {
          final file = File(idPath);
          if (file.existsSync()) idImage = file;
        } catch (_) {}
      }
    });
  }

  // ✅ Save profile info
  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('name', nameController.text);
    await prefs.setString('license', licenseController.text);
    await prefs.setString('email', emailController.text);
    await prefs.setString('location', locationController.text);
    await prefs.setString('clinic', clinicController.text);
    await prefs.setString('specialization', specialization);
    await prefs.setBool('isVerified', isVerified);
    if (profileImage != null && !kIsWeb) {
      await prefs.setString('profileImage', profileImage!.path);
    }
    if (idImage != null && !kIsWeb) {
      await prefs.setString('idImage', idImage!.path);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Profile saved successfully!"),
          backgroundColor: Color(0xFF6B8E23),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ✅ Pick and persist profile picture (works on web + mobile)
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      try {
        final prefs = await SharedPreferences.getInstance();

        if (kIsWeb) {
          // Web: just save the temporary path reference
          await prefs.setString('profileImage', pickedFile.path);
          setState(() {});
        } else {
          // Mobile/Desktop: move to permanent directory
          final directory = await getApplicationDocumentsDirectory();
          final newPath = '${directory.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
          final newImage = await File(pickedFile.path).copy(newPath);

          await prefs.setString('profileImage', newImage.path);
          setState(() {
            profileImage = newImage;
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("⚠️ Failed to save image: $e")),
          );
        }
      }
    }
  }

  // ✅ Upload ID (verification)
  Future<void> _uploadId() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      try {
        if (kIsWeb) {
          setState(() => isVerified = true);
        } else {
          idImage = File(pickedFile.path);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('isVerified', true);
          await prefs.setString('idImage', pickedFile.path);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ ID uploaded successfully! Awaiting verification..."),
              backgroundColor: Color(0xFF728D5A),
              duration: Duration(seconds: 2),
            ),
          );
        }

        setState(() => isVerified = true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("⚠️ Failed to upload ID: $e")),
          );
        }
      }
    }
  }

  // ✅ Navigation helper
  void _navigateTo(Widget screen) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sidebar
          Container(
            width: 240,
            color: const Color(0xFF728D5A),
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
            child: Column(
              children: [
                Center(child: Image.asset('assets/furever2.png', width: 150)),
                const SizedBox(height: 40),
                _sidebarItem(icon: Icons.person, title: "Profile", selected: true),
                const SizedBox(height: 12),
                _sidebarItem(
                  icon: Icons.dashboard,
                  title: "Dashboard",
                  onTap: () => _navigateTo(const DashboardScreen()),
                ),
                const SizedBox(height: 12),
                _sidebarItem(
                  icon: Icons.calendar_today,
                  title: "Appointments",
                  onTap: () => _navigateTo(AppointmentsPage(appointmentDoc: null)),
                ),
                const SizedBox(height: 12),
                _sidebarItem(
                  icon: Icons.analytics,
                  title: "Analytics",
                  onTap: () => _navigateTo(const AnalyticsScreen()),
                ),
                const SizedBox(height: 12),
                _sidebarItem(
                  icon: Icons.pets,
                  title: "Patients",
                  onTap: () => _navigateTo(const PatientHistoryScreen()),
                ),
                const SizedBox(height: 12),
                _sidebarItem(
                  icon: Icons.feedback,
                  title: "Feedback",
                  onTap: () => _navigateTo(const VetFeedbackScreen()),
                ),
                const Spacer(),
                
                const SizedBox(height: 12),
                _sidebarItem(
                  icon: Icons.settings,
                  title: "Settings",
                  onTap: () => _navigateTo(const SettingsScreen()),
                ),
                const SizedBox(height: 12),
                _sidebarItem(
                  icon: Icons.logout,
                  title: "Logout",
                  onTap: () async {
                    await UserPrefs.clearLoggedIn();
                    if (!mounted) return;
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen(registeredEmail: '', registeredPassword: '')),
                      (route) => false,
                    );
                  },
                ),
              ],
            ),
          ),

          // Main content
          Expanded(
            child: Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  color: const Color(0xFFBDD9A4),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Profile",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PaymentOptionScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.star, color: Colors.white),
                        label: const Text(
                          "Get Premium",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6B8E23),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Profile body
                Expanded(
                  child: Container(
                    color: const Color(0xFFF8F9F5),
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: Container(
                          padding: const EdgeInsets.all(30),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Profile image
                              Column(
                                children: [
                                  CircleAvatar(
                                    radius: 60,
                                    backgroundColor: const Color(0xFFBBD29C),
                                    backgroundImage: !kIsWeb && profileImage != null
                                        ? FileImage(profileImage!)
                                        : null,
                                    child: profileImage == null
                                        ? const Icon(Icons.person, size: 60, color: Colors.white)
                                        : null,
                                  ),
                                  const SizedBox(height: 15),
                                  ElevatedButton(
                                    onPressed: _pickImage,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFEAF086),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text("Upload Picture"),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 50),

                              // Editable fields
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _editableField("Full Name", nameController),
                                    const SizedBox(height: 20),
                                    _editableField("License Number", licenseController),
                                    const SizedBox(height: 20),
                                    _editableField("Email", emailController),
                                    const SizedBox(height: 20),
                                    _editableField("Location", locationController),
                                    const SizedBox(height: 20),
                                    _editableField("Clinic Name (optional)", clinicController),
                                    const SizedBox(height: 30),
                                    Center(
                                      child: ElevatedButton.icon(
                                        onPressed: _saveProfile,
                                        icon: const Icon(Icons.save),
                                        label: const Text("Save Changes"),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF728D5A),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 40),

                              // Verification + Specialization
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 200,
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey.shade300),
                                      color: Colors.white,
                                    ),
                                    child: Column(
                                      children: [
                                        if (isVerified)
                                          const Column(
                                            children: [
                                              Icon(Icons.verified, size: 50, color: Colors.green),
                                              SizedBox(height: 10),
                                              Text(
                                                "License Verified",
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          )
                                        else
                                          Column(
                                            children: [
                                              ElevatedButton.icon(
                                                onPressed: _uploadId,
                                                icon: const Icon(Icons.upload_file),
                                                label: const Text("Get Verified"),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFFEAF086),
                                                  foregroundColor: Colors.black,
                                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              const Text(
                                                "Upload valid ID to verify your license.",
                                                textAlign: TextAlign.center,
                                                style: TextStyle(fontSize: 12, color: Colors.black54),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 30),
                                  Container(
                                    width: 200,
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey.shade300),
                                      color: Colors.white,
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          "Specialization",
                                          style: TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 12),
                                        DropdownButton<String>(
                                          value: specialization,
                                          isExpanded: true,
                                          underline: Container(),
                                          items: specializations
                                              .map((spec) => DropdownMenuItem(
                                                    value: spec,
                                                    child: Text(spec),
                                                  ))
                                              .toList(),
                                          onChanged: (value) {
                                            setState(() => specialization = value!);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _editableField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontWeight: FontWeight.w500),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Widget _sidebarItem({
    required IconData icon,
    required String title,
    bool selected = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
