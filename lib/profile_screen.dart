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

  // ID Verification state
  File? _localIdImageFile;             // for mobile preview
  Uint8List? _webIdImageBytes;         // for web preview
  bool _isUploadingId = false;
  String _verificationStatus = '';     // pending, approved, rejected

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

      // Load verification status
      await _loadVerificationStatus();
    } catch (e) {
      print('PROFILE ERROR: $e, falling back to SharedPreferences');
      specialization = _specializationPlaceholder;
      // Try to load from SharedPreferences as fallback
      await _loadFromSharedPreferences();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Load verification status from Firestore
  Future<void> _loadVerificationStatus() async {
    if (currentUserId.isEmpty) return;

    try {
      final verificationDoc = await _firestore
          .collection('vet_verifications')
          .doc(currentUserId)
          .get();

      if (verificationDoc.exists) {
        final data = verificationDoc.data() ?? {};
        final status = data['status'] ?? '';
        if (mounted) {
          setState(() => _verificationStatus = status);
        } else {
          _verificationStatus = status;
        }
        print('VERIFICATION STATUS: $status');
      }
    } catch (e) {
      print('VERIFICATION STATUS ERROR: $e');
    }
  }

  // Check verification status before allowing premium access
  Future<void> _checkVerificationBeforePremium() async {
    // Reload verification status first
    await _loadVerificationStatus();
    
    if (_verificationStatus.isEmpty || _verificationStatus == 'pending') {
      // Show pending message
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.hourglass_empty, color: Colors.orange),
                SizedBox(width: 10),
                Text('Verification Pending'),
              ],
            ),
            content: const Text(
              'Your ID verification is still under review. Please wait for admin approval before applying for premium.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }
    
    if (_verificationStatus == 'rejected') {
      // Show rejection message with admin notes
      await _showRejectionDialog();
      return;
    }
    
    if (_verificationStatus == 'approved') {
      // Allow access to premium
      _navigateTo(const PaymentOptionScreen());
    }
  }

  // Show rejection dialog with admin notes
  Future<void> _showRejectionDialog() async {
    // Fetch admin notes if available
    String adminNotes = '';
    try {
      final verificationDoc = await _firestore
          .collection('vet_verifications')
          .doc(currentUserId)
          .get();
      if (verificationDoc.exists) {
        final data = verificationDoc.data() ?? {};
        adminNotes = data['adminNotes'] ?? '';
      }
    } catch (e) {
      print('Error loading admin notes: $e');
    }
    
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.cancel, color: Colors.red),
              SizedBox(width: 10),
              Text('Verification Rejected'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your ID verification has been rejected. You cannot apply for premium until your verification is approved.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              if (adminNotes.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Admin Notes:',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(adminNotes),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'You can resubmit your ID for verification.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _pickIdImage(); // Allow resubmission
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF728D5A),
              ),
              child: const Text('Resubmit ID'),
            ),
          ],
        ),
      );
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

  // Pick ID image for verification
  Future<void> _pickIdImage() async {
    if (currentUserId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Please log in to submit ID verification'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    try {
      Uint8List bytes;
      File? localFile;

      if (kIsWeb) {
        bytes = await pickedFile.readAsBytes();
      } else {
        localFile = File(pickedFile.path);
        bytes = await localFile.readAsBytes();
      }

      if (bytes.isEmpty) return;

      // Show preview
      if (mounted) {
        setState(() {
          if (!kIsWeb) {
            _localIdImageFile = localFile;
            _webIdImageBytes = null;
          } else {
            _webIdImageBytes = bytes;
            _localIdImageFile = null;
          }
        });
      }

      // Upload ID image
      await _uploadIdForVerification(bytes);
    } catch (e) {
      print('ID PICK ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Failed to pick image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Upload ID image to Firebase Storage and create verification request
  Future<void> _uploadIdForVerification(Uint8List bytes) async {
    if (currentUserId.isEmpty) return;

    setState(() => _isUploadingId = true);

    try {
      // Upload to Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('vet_id_verifications')
          .child('$currentUserId/id_${DateTime.now().millisecondsSinceEpoch}.jpg');

      print('ID UPLOAD: Starting upload to ${storageRef.fullPath}');
      final uploadTask = storageRef.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      print('ID UPLOAD: Upload complete, url=$downloadUrl');

      // Get vet information
      final vetDoc = await _firestore.collection('vets').doc(currentUserId).get();
      final vetData = vetDoc.data() ?? {};

      // Create verification request in Firestore
      final verificationData = {
        'vetId': currentUserId,
        'vetName': vetData['name'] ?? nameController.text,
        'vetEmail': vetData['email'] ?? emailController.text,
        'licenseNumber': vetData['license'] ?? licenseController.text,
        'idImageUrl': downloadUrl,
        'status': 'pending', // pending, approved, rejected
        'submittedAt': FieldValue.serverTimestamp(),
        'reviewedBy': '',
        'reviewedAt': null,
        'adminNotes': '',
      };

      await _firestore
          .collection('vet_verifications')
          .doc(currentUserId)
          .set(verificationData, SetOptions(merge: true));

      print('ID VERIFICATION: Request saved to Firestore');

      // Clear preview and update status
      if (mounted) {
        setState(() {
          _localIdImageFile = null;
          _webIdImageBytes = null;
          _isUploadingId = false;
          _verificationStatus = 'pending';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ ID submitted successfully! Admin will review it shortly.'),
            backgroundColor: Color(0xFF6B8E23),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e, st) {
      print('ID UPLOAD ERROR: $e');
      print('ID UPLOAD STACK: $st');

      if (mounted) {
        setState(() => _isUploadingId = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Failed to upload ID: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
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
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF728D5A), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
      decoration: BoxDecoration(
        color: const Color(0xFFBDD9A4),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(10),
                child: const Icon(Icons.person, color: Color(0xFF728D5A), size: 26),
              ),
              const SizedBox(width: 12),
              const Text(
                'Profile',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          ElevatedButton.icon(
            onPressed: () => _checkVerificationBeforePremium(),
            icon: const Icon(Icons.star, color: Colors.white, size: 18),
            label: const Text(
              'Get Premium',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF728D5A),
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
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
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
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
                    borderRadius: BorderRadius.circular(12),
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
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 24,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Specialization',
                      style: TextStyle(fontWeight: FontWeight.w800),
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
                              child: Text(
                                spec,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
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
                      fontWeight: FontWeight.w700,
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 200,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF728D5A),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF728D5A).withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isUploadingId ? null : _pickIdImage,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF086),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: _isUploadingId
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Color(0xFF728D5A),
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.verified_user,
                                        size: 24,
                                        color: Color(0xFF728D5A),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isUploadingId ? 'Uploading...' : 'Submit ID',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                        color: Color(0xFF728D5A),
                                      ),
                                    ),
                                    if (!_isUploadingId)
                                      const Text(
                                        'for Verification',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
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
              // Show verification status if exists
              if (_verificationStatus.isNotEmpty) ...[
                const SizedBox(height: 15),
                Container(
                  width: 200,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _verificationStatus == 'approved'
                          ? Colors.green
                          : _verificationStatus == 'rejected'
                              ? Colors.red
                              : Colors.orange,
                      width: 2,
                    ),
                    color: _verificationStatus == 'approved'
                        ? Colors.green.shade50
                        : _verificationStatus == 'rejected'
                            ? Colors.red.shade50
                            : Colors.orange.shade50,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _verificationStatus == 'approved'
                                ? Icons.check_circle
                                : _verificationStatus == 'rejected'
                                    ? Icons.cancel
                                    : Icons.pending,
                            color: _verificationStatus == 'approved'
                                ? Colors.green
                                : _verificationStatus == 'rejected'
                                    ? Colors.red
                                    : Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Status: ${_verificationStatus.toUpperCase()}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: _verificationStatus == 'approved'
                                    ? Colors.green.shade700
                                    : _verificationStatus == 'rejected'
                                        ? Colors.red.shade700
                                        : Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_verificationStatus == 'rejected') ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => _showRejectionDialog(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'View Details',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              // Show ID preview if selected
              if (_localIdImageFile != null || _webIdImageBytes != null) ...[
                const SizedBox(height: 15),
                Container(
                  width: 200,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF728D5A), width: 2),
                    color: Colors.grey.shade50,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ID Preview:',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: kIsWeb && _webIdImageBytes != null
                            ? Image.memory(
                                _webIdImageBytes!,
                                width: double.infinity,
                                height: 120,
                                fit: BoxFit.cover,
                              )
                            : _localIdImageFile != null
                                ? Image.file(
                                    _localIdImageFile!,
                                    width: double.infinity,
                                    height: 120,
                                    fit: BoxFit.cover,
                                  )
                                : const SizedBox(),
                      ),
                    ],
                  ),
                ),
              ],
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

    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0xFFBBD29C),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(child: imageWidget),
    );
  }
}
