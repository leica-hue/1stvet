import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Import necessary screens (assuming these paths are correct)
import 'login_screen.dart';
import 'settings_screen.dart';
import 'user_prefs.dart';
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
  // --- Controllers ---
  final TextEditingController nameController = TextEditingController();
  final TextEditingController licenseController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController clinicController = TextEditingController();

  // --- Firebase/State Management ---
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  String get currentUserId => _auth.currentUser?.uid ?? '';

  // FIX 1: Introduce a constant for the unselected placeholder.
  static const String _specializationPlaceholder = 'Select Specialization';

  // FIX 2: Initialize specialization with the placeholder.
  String specialization = _specializationPlaceholder;
  
  // FIX 3: Add the placeholder to the list of available specializations.
  List<String> specializations = [
    _specializationPlaceholder, 
    'Pathology',
    'Behaviour',
    'Dermatology',
    'General'
  ];

  // This is used ONLY for immediate file preview on non-web platforms
  File? _localProfileImageFile; 
  String _profileImageUrl = '';
  bool _isSaving = false;
  bool _isLoading = true; // Use a dedicated loading state

  // --- Initial Profile Loading Logic ---
  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // NOTE: This function also retrieves the current _profileImageUrl for error recovery.
Future<void> _loadProfile() async {
  if (currentUserId.isEmpty) {
    if (mounted) setState(() => _isLoading = false);
    return;
  }

  try {
    final userDoc = await _firestore.collection('vets').doc(currentUserId).get();

    if (userDoc.exists) {
      final data = userDoc.data()!;
      nameController.text = data['name'] ?? 'Dr. Sarah Doe';
      licenseController.text = data['license'] ?? '';
      emailController.text = data['email'] ?? (_auth.currentUser?.email ?? 'sarah@vetclinic.com');
      locationController.text = data['location'] ?? '';
      clinicController.text = data['clinic'] ?? '';
      
      // FIX 4: Handle specialization loading
      final loadedSpec = data['specialization'];
      specialization = (loadedSpec != null && specializations.contains(loadedSpec))
          ? loadedSpec
          : _specializationPlaceholder;

      _profileImageUrl = data['profileImageUrl'] ?? '';
    } else {
      // If the user doc does not exist, explicitly set specialization to placeholder
      specialization = _specializationPlaceholder;
    }
  } catch (e) {
    print("Error loading profile: $e");
    specialization = _specializationPlaceholder; // Set placeholder on error
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}


  // --- Save Profile Logic ---
  Future<void> _saveProfile() async {
    if (currentUserId.isEmpty) return;
    if (_isSaving) return;

    // Optional: Add a check to prevent saving if the specialization is still the placeholder
    if (specialization == _specializationPlaceholder) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⚠️ Please select a specialization before saving."),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() => _isSaving = true);

    try {
      final dataToSave = {
        'name': nameController.text,
        'license': licenseController.text,
        'email': emailController.text,
        'location': locationController.text,
        'clinic': clinicController.text,
        'specialization': specialization,
        'profileImageUrl': _profileImageUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('vets').doc(currentUserId).set(dataToSave, SetOptions(merge: true));

      // Save to SharedPreferences as backup/local cache
      final prefs = await SharedPreferences.getInstance();
      dataToSave.forEach((key, value) async {
        if (value is String) await prefs.setString(key, value);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Profile saved successfully!"),
            backgroundColor: Color(0xFF6B8E23),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("⚠️ Failed to save profile: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- Image Picking/Upload Logic (FIXED CATCH BLOCK) ---
  Future<void> _pickImage() async {
    if (currentUserId.isEmpty) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (pickedFile == null) return;

    // Save the current URL before clearing, in case the upload fails.
    final String oldImageUrl = _profileImageUrl;

    try {
      // Temporary UI update for preview/loading
      setState(() {
        if (!kIsWeb) {
          _localProfileImageFile = File(pickedFile.path); // Set local file for immediate non-web preview
        }
        _profileImageUrl = ''; // Clear URL temporarily to show the local image/loader/new file preview
      });
      
      // 1. Prepare Storage Reference
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('vet_profile_images')
          .child('$currentUserId/profile_${DateTime.now().millisecondsSinceEpoch}.jpg');

      // 2. Upload Task based on Platform
      UploadTask uploadTask;
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        uploadTask = storageRef.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        _localProfileImageFile = null; // Ensure local File is not used on web
      } else {
        final file = File(pickedFile.path);
        uploadTask = storageRef.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      }

      // 3. Wait for upload and get URL
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      // Append timestamp to URL to force reload/cache bust
      final finalUrl = "$downloadUrl?${DateTime.now().millisecondsSinceEpoch}"; 

      // 4. Update UI state and Firestore
      setState(() {
        _profileImageUrl = finalUrl;
        _localProfileImageFile = null; // Clear local file after successful network update
      });

      await _firestore.collection('vets').doc(currentUserId).set({
        'profileImageUrl': _profileImageUrl,
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Profile picture uploaded!"),
            backgroundColor: Color(0xFF6B8E23),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print("🚨 Error uploading image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("⚠️ Failed to upload image: $e")),
        );
      }
      
      // FIX: Revert state to the previous working image if upload fails
      if (mounted) setState(() {
        _localProfileImageFile = null; // Clear temporary file
        _profileImageUrl = oldImageUrl; // Restore the URL of the last successfully uploaded image
      });
    }
  }

  // --- Navigation & Helper Widgets (Unchanged) ---

  void _navigateTo(Widget screen) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Widget _editableField(String label, TextEditingController controller, {bool readOnly = false}) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
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
            if (icon != null) Icon(icon, color: Colors.white, size: 20),
            if (icon != null) const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Build Method (Unchanged) ---

  @override
  Widget build(BuildContext context) {
    // If data is still loading, show a centered spinner
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF728D5A))),
      );
    }
    
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sidebar
          _buildSidebar(),

          // Main content
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                
                // Profile body
                Expanded(
                  child: Container(
                    color: const Color(0xFFF8F9F5),
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: _buildProfileCard(),
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

  // --- Extracted Widgets (Unchanged) ---

  Widget _buildSidebar() {
    return Container(
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
                MaterialPageRoute(
                  builder: (_) =>
                      const LoginScreen(registeredEmail: '', registeredPassword: ''),
                ),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
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
            onPressed: () => _navigateTo(const PaymentOptionScreen()),
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
    );
  }

  Widget _buildProfileCard() {
    return Container(
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
          // Profile Image Upload Section
          Column(
            children: [
              _buildProfileAvatar(),
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

          // Editable Fields
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _editableField("Full Name", nameController),
                const SizedBox(height: 20),
                _editableField("License Number", licenseController),
                const SizedBox(height: 20),
                // Email field is often read-only for security
                _editableField("Email (Read-Only)", emailController, readOnly: true), 
                const SizedBox(height: 20),
                _editableField("Location", locationController),
                const SizedBox(height: 20),
                _editableField("Clinic Name (optional)", clinicController),
                const SizedBox(height: 30),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveProfile,
                    icon: _isSaving ? const SizedBox(
                      width: 20, 
                      height: 20, 
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3.0),
                    ) : const Icon(Icons.save),
                    label: Text(_isSaving ? "Saving..." : "Save Changes"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF728D5A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 24),
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

          // Specialization Dropdown
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
                      // Hide the underline to make the dropdown cleaner
                      underline: Container(), 
                      // FIX 5: Filter out the placeholder from the items list 
                      // if you don't want it to be selectable after choosing a real value
                      items: specializations
                          .map((spec) => DropdownMenuItem(
                                value: spec,
                                child: Text(spec),
                              ))
                          .toList(),
                      onChanged: (value) {
                        // Only allow setting a value if it's a valid specialization
                        if (value != null && value != _specializationPlaceholder) {
                          setState(() => specialization = value);
                        } else if (value == _specializationPlaceholder) {
                           setState(() => specialization = _specializationPlaceholder);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileAvatar() {
    Widget imageWidget;

    if (_localProfileImageFile != null && !kIsWeb) {
      // 1. Local file preview (Non-web platforms only)
      imageWidget = Image.file(
        _localProfileImageFile!,
        width: 120,
        height: 120,
        fit: BoxFit.cover,
      );
    } else if (_profileImageUrl.isNotEmpty) {
      // 2. Network image from Firebase
      imageWidget = CachedNetworkImage(
        imageUrl: _profileImageUrl,
        width: 120,
        height: 120,
        fit: BoxFit.cover,
        // The placeholder shows while loading
        placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
        // The error widget shows on network retrieval failure (this is what you were seeing)
        errorWidget: (_, __, ___) => Container(
          color: Colors.white, // Use white background for error
          child: const Icon(
            Icons.error_outline,
            size: 60,
            color: Colors.redAccent, 
          ), 
        ), 
      );
    } else {
      // 3. Default/Placeholder Icon (When no picture has ever been uploaded)
      imageWidget = const Icon(
        Icons.person,
        size: 60,
        color: Colors.white,
      );
    }

    return CircleAvatar(
      radius: 60,
      backgroundColor: const Color(0xFFBBD29C),
      child: ClipOval(child: imageWidget),
    );
  }
}