import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

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

  File? _localProfileImageFile;
  String _profileImageUrl = '';
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
      final doc =
          await _firestore.collection('vets').doc(currentUserId).get();

      if (doc.exists) {
        final data = doc.data()!;
        nameController.text = data['name'] ?? 'Dr. Sarah Doe';
        licenseController.text = data['license'] ?? '';
        emailController.text =
            data['email'] ?? (_auth.currentUser?.email ?? 'sarah@vetclinic.com');
        locationController.text = data['location'] ?? '';
        clinicController.text = data['clinic'] ?? '';

        final loadedSpec = data['specialization'];
        specialization =
            (loadedSpec != null && specializations.contains(loadedSpec))
                ? loadedSpec
                : _specializationPlaceholder;

        _profileImageUrl = data['profileImageUrl'] ?? '';
        
        print('📖 PROFILE LOADED FROM FIRESTORE:');
        print('   User ID: $currentUserId');
        print('   Name: ${nameController.text}');
        print('   Profile Image URL: $_profileImageUrl');
        print('   Image URL is ${_profileImageUrl.isEmpty ? "EMPTY" : "SET"}');
      } else {
        specialization = _specializationPlaceholder;
        print('⚠️ No profile document found for user: $currentUserId');
      }
    } catch (e) {
      print('PROFILE DEBUG: Error loading profile: $e');
      specialization = _specializationPlaceholder;
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      print('PROFILE DEBUG: Error saving profile: $e');
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
    print('IMAGE DEBUG: _pickImage called');
    print('IMAGE DEBUG: currentUserId = $currentUserId');

    if (currentUserId.isEmpty) {
      print('IMAGE DEBUG: User not logged in, aborting');
      return;
    }

    final picker = ImagePicker();
    final pickedFile =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);

    if (pickedFile == null) {
      print('IMAGE DEBUG: No image selected');
      return;
    }

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
          .child(
            '$currentUserId/profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );

      UploadTask uploadTask;
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        uploadTask = storageRef.putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        _localProfileImageFile = null;
      } else {
        final file = File(pickedFile.path);
        uploadTask = storageRef.putFile(
          file,
          SettableMetadata(contentType: 'image/jpeg'),
        );
      }

      print('IMAGE DEBUG: Starting upload');
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      print('IMAGE DEBUG: Upload complete, downloadUrl = $downloadUrl');

      // Don't add timestamp parameter - it can cause CORS issues on web
      final finalUrl = downloadUrl;
      
      print('IMAGE DEBUG: finalUrl = $finalUrl');

      setState(() {
        _profileImageUrl = finalUrl;
        _localProfileImageFile = null;
        print('IMAGE DEBUG: setState called - _profileImageUrl set to: $_profileImageUrl');
      });

      print('IMAGE DEBUG: Updating vets/$currentUserId with profileImageUrl');
      await _firestore.collection('vets').doc(currentUserId).set(
        {
          'profileImageUrl': _profileImageUrl,
        },
        SetOptions(merge: true),
      );

      print('✅ PROFILE IMAGE SAVED TO FIRESTORE:');
      print('   Collection: vets');
      print('   Document: $currentUserId');
      print('   Field: profileImageUrl');
      print('   URL: $_profileImageUrl');
      
      // Verify by reading back
      final verifyDoc = await _firestore.collection('vets').doc(currentUserId).get();
      final verifiedUrl = verifyDoc.data()?['profileImageUrl'];
      print('📖 VERIFIED: profileImageUrl from Firestore: $verifiedUrl');
      
      // Force UI refresh to display the new image
      if (mounted) {
        setState(() {
          // _profileImageUrl is already set above, just trigger rebuild
          print('🔄 UI: Triggering rebuild to display new image');
        });
      }

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
      print('IMAGE DEBUG: Error in _pickImage: $e');
      print('IMAGE DEBUG STACK: $st');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Failed to upload image: $e')),
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
                _editableField('Email (Read-Only)', emailController,
                    readOnly: true),
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
    print('🖼️ AVATAR BUILD: _profileImageUrl = "$_profileImageUrl"');
    print('🖼️ AVATAR BUILD: _profileImageUrl.isNotEmpty = ${_profileImageUrl.isNotEmpty}');
    print('🖼️ AVATAR BUILD: _localProfileImageFile = $_localProfileImageFile');
    print('🖼️ AVATAR BUILD: kIsWeb = $kIsWeb');
    
    Widget imageWidget;

    if (_localProfileImageFile != null && !kIsWeb) {
      print('🖼️ AVATAR: Displaying local file image');
      imageWidget = Image.file(
        _localProfileImageFile!,
        width: 120,
        height: 120,
        fit: BoxFit.cover,
      );
    } else if (_profileImageUrl.isNotEmpty) {
      print('🖼️ AVATAR: Will display CachedNetworkImage from: $_profileImageUrl');
      
      // For web, use Image.network instead of CachedNetworkImage
      if (kIsWeb) {
        print('🌐 AVATAR: Using Image.network for web');
        print('🌐 AVATAR: Image URL = $_profileImageUrl');
        imageWidget = Image.network(
          _profileImageUrl,
          key: ValueKey(_profileImageUrl), // Force rebuild when URL changes
          width: 120,
          height: 120,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              print('✅ AVATAR: Image loaded successfully!');
              return child;
            }
            final progress = loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                : null;
            print('🔄 AVATAR: Loading... ${(progress! * 100).toStringAsFixed(0)}%');
            return const Center(child: CircularProgressIndicator(strokeWidth: 2.0));
          },
          errorBuilder: (context, error, stackTrace) {
            print('❌ AVATAR: Failed to load image on web!');
            print('❌ AVATAR ERROR: $error');
            print('❌ AVATAR URL: $_profileImageUrl');
            print('❌ AVATAR STACK: $stackTrace');
            return Container(
              width: 120,
              height: 120,
              color: Colors.grey[300],
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.broken_image,
                    size: 40,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Failed to load',
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          },
        );
      } else {
        print('📱 AVATAR: Using CachedNetworkImage for mobile');
        imageWidget = CachedNetworkImage(
          imageUrl: _profileImageUrl,
          width: 120,
          height: 120,
          fit: BoxFit.cover,
          placeholder: (_, __) {
            print('🔄 AVATAR: Loading image...');
            return const Center(child: CircularProgressIndicator(strokeWidth: 2.0));
          },
          errorWidget: (_, __, error) {
            print('❌ AVATAR: Failed to load image: $error');
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
      }
    } else {
      print('🖼️ AVATAR: No image URL, showing placeholder icon');
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
