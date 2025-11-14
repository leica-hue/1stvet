import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'settings_screen.dart';
import 'payment_option_screen.dart';
import 'PricingManagementScreen.dart';
import 'common_sidebar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Text controllers
  final TextEditingController nameController = TextEditingController();
  final TextEditingController licenseController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController clinicController = TextEditingController();

  // Firebase
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String get currentUserId => _auth.currentUser?.uid ?? '';

  static const String _specializationPlaceholder = 'Select Specialization';
  String specialization = _specializationPlaceholder;

  final List<String> specializations = [
    _specializationPlaceholder,
    'Pathology',
    'Behaviour',
    'Dermatology',
    'General',
  ];

  // Image state
  File? _localProfileImageFile;        // for mobile preview
  Uint8List? _webProfileImageBytes;    // for web preview
  String _profileImageUrl = '';        // persisted download URL

  bool _isSaving = false;
  bool _isLoading = true;

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

  // Load profile data from Firestore
  Future<void> _loadProfile() async {
    if (currentUserId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final doc = await _firestore.collection('vets').doc(currentUserId).get();

      if (doc.exists) {
        final data = doc.data() ?? {};

        nameController.text = data['name'] ?? '';
        licenseController.text = data['license'] ?? '';
        emailController.text =
            data['email'] ?? (_auth.currentUser?.email ?? '');
        locationController.text = data['location'] ?? '';
        clinicController.text = data['clinic'] ?? '';

        final loadedSpec = data['specialization'];
        specialization =
            (loadedSpec != null && specializations.contains(loadedSpec))
                ? loadedSpec
                : _specializationPlaceholder;

        final loadedImageUrl = data['profileImageUrl'] ?? '';

        if (mounted) {
          setState(() {
            _profileImageUrl = loadedImageUrl;
            _localProfileImageFile = null;
            _webProfileImageBytes = null;
          });
        } else {
          _profileImageUrl = loadedImageUrl;
          _localProfileImageFile = null;
          _webProfileImageBytes = null;
        }

        print('PROFILE LOADED: userId=$currentUserId, url=$_profileImageUrl');
      } else {
        // No Firestore doc, try SharedPreferences as fallback
        await _loadFromSharedPreferences();
        print('PROFILE: no document found for $currentUserId, loaded from SharedPreferences');
      }
    } catch (e) {
      print('PROFILE ERROR: $e, falling back to SharedPreferences');
      specialization = _specializationPlaceholder;
      // Try to load from SharedPreferences as fallback
      await _loadFromSharedPreferences();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Load from SharedPreferences as fallback
  Future<void> _loadFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedUrl = prefs.getString('profileImageUrl_$currentUserId') ?? '';

      if (mounted) {
        setState(() {
          _profileImageUrl = cachedUrl;
          _localProfileImageFile = null;
          _webProfileImageBytes = null;
        });
      } else {
        _profileImageUrl = cachedUrl;
        _localProfileImageFile = null;
        _webProfileImageBytes = null;
      }

      print('PROFILE: loaded image URL from SharedPreferences: $cachedUrl');
    } catch (e) {
      print('PROFILE: SharedPreferences error: $e');
      if (mounted) {
        setState(() {
          _profileImageUrl = '';
          _localProfileImageFile = null;
          _webProfileImageBytes = null;
        });
      } else {
        _profileImageUrl = '';
        _localProfileImageFile = null;
        _webProfileImageBytes = null;
      }
    }
  }

  // Save vet profile to Firestore
  Future<void> _saveProfile() async {
    if (currentUserId.isEmpty) return;
    if (_isSaving) return;

    if (specialization == _specializationPlaceholder) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Please select a specialization before saving.'),
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

      await _firestore
          .collection('vets')
          .doc(currentUserId)
          .set(dataToSave, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      for (final entry in dataToSave.entries) {
        if (entry.value is String) {
          await prefs.setString(entry.key, entry.value as String);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Profile saved successfully!'),
            backgroundColor: Color(0xFF6B8E23),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('PROFILE SAVE ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Failed to save profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Upload profile image to Firebase Storage
  Future<void> _pickImage() async {
    print('IMAGE: _pickImage called, userId=$currentUserId');

    if (currentUserId.isEmpty) {
      print('IMAGE: user not logged in, abort');
      return;
    }

    final picker = ImagePicker();
    final pickedFile =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);

    if (pickedFile == null) {
      print('IMAGE: no image selected');
      return;
    }

    String oldUrl = _profileImageUrl;
    Uint8List bytes;
    File? localFile;

    try {
      if (kIsWeb) {
        bytes = await pickedFile.readAsBytes();
      } else {
        localFile = File(pickedFile.path);
        bytes = await localFile.readAsBytes();
      }

      if (bytes.isEmpty) {
        print('IMAGE: picked bytes empty, abort');
        return;
      }

      // Immediate preview
      setState(() {
        if (!kIsWeb) {
          _localProfileImageFile = localFile;
          _webProfileImageBytes = null;
        } else {
          _webProfileImageBytes = bytes;
          _localProfileImageFile = null;
        }
        _profileImageUrl = '';
      });

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('vet_profile_images')
          .child(
            '$currentUserId/profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );

      print('IMAGE: starting upload to ${storageRef.fullPath}');
      final uploadTask = storageRef.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      print('IMAGE: upload complete, url=$downloadUrl');

      // Delete old image from Storage if exists
      if (oldUrl.isNotEmpty) {
        try {
          final oldRef = FirebaseStorage.instance.refFromURL(oldUrl);
          await oldRef.delete();
          print('IMAGE: deleted old image from Storage');
        } catch (e) {
          print('IMAGE: could not delete old image: $e');
        }
      }

      if (mounted) {
        setState(() {
          _profileImageUrl = downloadUrl;
          // Clear local previews so network image displays
          _localProfileImageFile = null;
          _webProfileImageBytes = null;
        });
      } else {
        _profileImageUrl = downloadUrl;
        _localProfileImageFile = null;
        _webProfileImageBytes = null;
      }

      // Save to Firestore
      await _firestore.collection('vets').doc(currentUserId).set(
        {
          'profileImageUrl': _profileImageUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // Save to SharedPreferences for offline access (user-specific key)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profileImageUrl_$currentUserId', _profileImageUrl);

      print('IMAGE: url saved to Firestore and SharedPreferences');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Profile picture uploaded and saved!'),
            backgroundColor: Color(0xFF6B8E23),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e, st) {
      print('IMAGE ERROR: $e');
      print('IMAGE STACK: $st');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Failed to upload image: $e')),
        );
        setState(() {
          _localProfileImageFile = null;
          _webProfileImageBytes = null;
          _profileImageUrl = oldUrl;
        });
      } else {
        _localProfileImageFile = null;
        _webProfileImageBytes = null;
        _profileImageUrl = oldUrl;
      }
    }
  }

  void _navigateTo(Widget screen) {
    if (screen is SettingsScreen ||
        screen is PricingManagementScreen ||
        screen is PaymentOptionScreen) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => screen),
      );
    }
  }

  Widget _editableField(
    String label,
    TextEditingController controller, {
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontWeight: FontWeight.w500),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF728D5A)),
        ),
      );
    }

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CommonSidebar(currentScreen: 'Profile'),
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
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

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFBDD9A4),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Profile',
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
              'Get Premium',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6B8E23),
              padding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
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
                child: const Text('Upload Picture'),
              ),
            ],
          ),
          const SizedBox(width: 50),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _editableField('Full Name', nameController),
                const SizedBox(height: 20),
                _editableField('License Number', licenseController),
                const SizedBox(height: 20),
                _editableField(
                  'Email (Read-Only)',
                  emailController,
                  readOnly: true,
                ),
                const SizedBox(height: 20),
                _editableField('Location', locationController),
                const SizedBox(height: 20),
                _editableField('Clinic Name (optional)', clinicController),
                const SizedBox(height: 30),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveProfile,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3.0,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF728D5A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 24,
                      ),
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
                      'Specialization',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    DropdownButton<String>(
                      value: specialization,
                      isExpanded: true,
                      underline: Container(),
                      items: specializations
                          .map(
                            (spec) => DropdownMenuItem(
                              value: spec,
                              child: Text(spec),
                            ),
                          )
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
              const SizedBox(height: 20),
              SizedBox(
                width: 200,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      _navigateTo(const PricingManagementScreen()),
                  icon: const Icon(Icons.currency_exchange, size: 20),
                  label: const Text(
                    'Manage Rates',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEAF086),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      vertical: 15,
                      horizontal: 10,
                    ),
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

    // Priority: local preview (mobile or web) then network URL then placeholder
    if (!kIsWeb && _localProfileImageFile != null) {
      imageWidget = Image.file(
        _localProfileImageFile!,
        width: 120,
        height: 120,
        fit: BoxFit.cover,
      );
    } else if (kIsWeb && _webProfileImageBytes != null) {
      imageWidget = Image.memory(
        _webProfileImageBytes!,
        width: 120,
        height: 120,
        fit: BoxFit.cover,
      );
    } else if (_profileImageUrl.isNotEmpty) {
      // Add cache-busting parameter to force fresh load after upload
      final imageUrl = _profileImageUrl.contains('?')
          ? _profileImageUrl
          : '$_profileImageUrl?alt=media';

      imageWidget = Image.network(
        imageUrl,
        width: 120,
        height: 120,
        fit: BoxFit.cover,
        cacheWidth: 240, // 2x resolution for better quality
        cacheHeight: 240,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: 120,
            height: 120,
            color: Colors.grey[200],
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
                color: const Color(0xFF728D5A),
                strokeWidth: 3.0,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          print('IMAGE DISPLAY ERROR: $error');
          print('IMAGE URL: $imageUrl');
          return Container(
            width: 120,
            height: 120,
            color: Colors.grey[300],
            child: const Icon(
              Icons.broken_image,
              size: 60,
              color: Colors.grey,
            ),
          );
        },
      );
    } else {
      imageWidget = Container(
        width: 120,
        height: 120,
        color: const Color(0xFFBBD29C),
        child: const Icon(
          Icons.person,
          size: 60,
          color: Colors.white,
        ),
      );
    }

    return CircleAvatar(
      radius: 60,
      backgroundColor: const Color(0xFFBBD29C),
      child: ClipOval(child: imageWidget),
    );
  }
}
