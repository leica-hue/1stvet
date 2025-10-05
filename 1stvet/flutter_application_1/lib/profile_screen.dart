import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard_screen.dart';
import 'appointments_screen.dart';
import 'patients_list_screen.dart';

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
  List<String> specializations = ['Pathology', 'Behaviour', 'Dermatology'];
  File? profileImage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      nameController.text = prefs.getString('name') ?? 'Dr. Sarah Doe';
      licenseController.text = prefs.getString('license') ?? 'PHVET-2023-014587';
      emailController.text = prefs.getString('email') ?? 'sarah@vetclinic.com';
      locationController.text =
          prefs.getString('location') ?? 'Marawoy, Lipa City, Batangas';
      clinicController.text = prefs.getString('clinic') ?? '';
      specialization = prefs.getString('specialization') ?? 'Pathology';
      String? imagePath = prefs.getString('profileImage');
      if (imagePath != null && File(imagePath).existsSync()) {
        profileImage = File(imagePath);
      }
    });
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('name', nameController.text);
    await prefs.setString('license', licenseController.text);
    await prefs.setString('email', emailController.text);
    await prefs.setString('location', locationController.text);
    await prefs.setString('clinic', clinicController.text);
    await prefs.setString('specialization', specialization);
    if (profileImage != null) {
      await prefs.setString('profileImage', profileImage!.path);
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        profileImage = File(pickedFile.path);
      });
      _saveProfile();
    }
  }

  void _navigateTo(Widget screen) async {
    await _saveProfile();
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
          // ✅ Sidebar (exact same as Dashboard)
          Container(
            width: 240,
            color: const Color(0xFF728D5A),
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
            child: Column(
              children: [
                // Logo
                Center(
                  child: Image.asset('assets/furever2.png', width: 150),
                ),
                const SizedBox(height: 40),

                // Menu Items with icons
                                const SizedBox(height: 12),
                _sidebarItem(
                  icon: Icons.person,
                  title: "Profile",
                  selected: true,
                ),
                _sidebarItem(
                  icon: Icons.dashboard,
                  title: "Dashboard",
                  selected: false,
                  onTap: () => _navigateTo(const DashboardScreen()),
                ),
                const SizedBox(height: 12),
                _sidebarItem(
                  icon: Icons.calendar_today,
                  title: "Appointments",
                  selected: false,
                  onTap: () => _navigateTo(AppointmentsPage()),
                ),
                const SizedBox(height: 12),
                _sidebarItem(
                  icon: Icons.pets,
                  title: "Patients",
                  selected: false,
                  onTap: () => _navigateTo(const PatientsListScreen()),
                ),
                const SizedBox(height: 12),
                _sidebarItem(
                  icon: Icons.feedback,
                  title: "Feedback",
                  selected: false,
                ),
              ],
            ),
          ),

          // ✅ Main Content
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
                    children: const [
                      Text(
                        "Profile",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      Icon(Icons.settings, size: 28, color: Colors.black),
                    ],
                  ),
                ),

                // Content
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
                              // Left column: Avatar
                              Column(
                                children: [
                                  CircleAvatar(
                                    radius: 60,
                                    backgroundColor: const Color(0xFFBBD29C),
                                    backgroundImage: profileImage != null
                                        ? FileImage(profileImage!)
                                        : null,
                                    child: profileImage == null
                                        ? const Icon(Icons.person,
                                            size: 60, color: Colors.white)
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

                              // Middle column: Editable fields
                              Expanded(
                                child: Column(
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
                                  ],
                                ),
                              ),
                              const SizedBox(width: 40),

                              // Right column: License & Specialization
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 180,
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey.shade300),
                                      color: Colors.white,
                                    ),
                                    child: Column(
                                      children: const [
                                        Icon(Icons.verified,
                                            size: 50, color: Colors.green),
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
                                            _saveProfile();
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
      onChanged: (_) => _saveProfile(),
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
