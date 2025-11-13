import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Import necessary screens
import 'settings_screen.dart';
import 'payment_option_screen.dart';
// 🎯 REQUIRED: Import the new pricing screen
import 'PricingManagementScreen.dart';
import 'common_sidebar.dart'; 

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

  static const String _specializationPlaceholder = 'Select Specialization';
  String specialization = _specializationPlaceholder;
  
  List<String> specializations = [
    _specializationPlaceholder, 
    'Pathology',
    'Behaviour',
    'Dermatology',
    'General'
  ];

  File? _localProfileImageFile; 
  String _profileImageUrl = '';
  bool _isSaving = false;
  bool _isLoading = true; 

  // --- Initial Profile Loading Logic ---
  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    nameController.dispose();
    licenseController.dispose();
    emailController.dispose();
    locationController.dispose();
    clinicController.dispose();
    super.dispose();
  }

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
        
        final loadedSpec = data['specialization'];
        specialization = (loadedSpec != null && specializations.contains(loadedSpec))
            ? loadedSpec
            : _specializationPlaceholder;

        _profileImageUrl = data['profileImageUrl'] ?? '';
      } else {
        specialization = _specializationPlaceholder;
      }
    } catch (e) {
      print("Error loading profile: $e");
      specialization = _specializationPlaceholder; 
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  // --- Save Profile Logic ---
  Future<void> _saveProfile() async {
    if (currentUserId.isEmpty) return;
    if (_isSaving) return;

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

  // --- Image Picking/Upload Logic ---
  Future<void> _pickImage() async {
    if (currentUserId.isEmpty) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (pickedFile == null) return;

    final String oldImageUrl = _profileImageUrl;

    try {
      setState(() {
        if (!kIsWeb) {
          _localProfileImageFile = File(pickedFile.path); 
        }
        _profileImageUrl = ''; 
      });
      
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('vet_profile_images')
          .child('$currentUserId/profile_${DateTime.now().millisecondsSinceEpoch}.jpg');

      UploadTask uploadTask;
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        uploadTask = storageRef.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        _localProfileImageFile = null;
      } else {
        final file = File(pickedFile.path);
        uploadTask = storageRef.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      }

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      final finalUrl = "$downloadUrl?${DateTime.now().millisecondsSinceEpoch}"; 

      setState(() {
        _profileImageUrl = finalUrl;
        _localProfileImageFile = null; 
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
      
      if (mounted) {
        setState(() {
        _localProfileImageFile = null;
        _profileImageUrl = oldImageUrl;
      });
      }
    }
  }

  // --- Navigation & Helper Widgets ---

  void _navigateTo(Widget screen) {
    // This uses pushReplacement for sidebar items, which clears the history.
    // Use regular Navigator.push for screens that should allow going back
    if (screen is SettingsScreen || screen is PricingManagementScreen || screen is PaymentOptionScreen) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => screen));
    }
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

  
  // --- Main Build Method ---

  @override
  Widget build(BuildContext context) {
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
          const CommonSidebar(currentScreen: 'Profile'),

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

  // --- Extracted Widgets ---

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
                // Email field is read-only
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

          // Specialization Dropdown and New Button
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Specialization Dropdown
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
                        if (value != null) {
                          setState(() => specialization = value);
                        }
                      },
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20), // Spacing between specialization and button

              // 2. 🎯 NEW: Manage Rates Button (Below Specialization)
              SizedBox(
                width: 200,
                child: ElevatedButton.icon(
                  onPressed: () => _navigateTo(const PricingManagementScreen()),
                  icon: const Icon(Icons.currency_exchange, size: 20),
                  label: const Text(
                    "Manage Rates",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEAF086),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
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
        placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
        errorWidget: (_, __, ___) => Container(
          color: Colors.white,
          child: const Icon(
            Icons.broken_image, // Changed to a less alarming icon for a profile
            size: 60,
            color: Colors.grey, 
          ), 
        ), 
      );
    } else {
      // 3. Default/Placeholder Icon
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