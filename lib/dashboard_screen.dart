import 'dart:async'; // Keep for StreamSubscription type
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'appointments_screen.dart';
import 'profile_screen.dart';
import 'user_prefs.dart'; // Assuming this file contains the UserPrefs.loadProfile logic
import 'common_sidebar.dart';
import 'notification_icon.dart';

// --- Appointment Class (No Changes Needed) ---
class Appointment {
  final String petName;
  final String timeSlot;
  final String userName;
  final String userId;
  final String status;
  final DateTime appointmentDateTime;
  final String id; // Document ID

  Appointment({
    required this.petName,
    required this.timeSlot,
    required this.userName,
    required this.status,
    required this.appointmentDateTime,
    required this.userId,
    required this.id,
  });

  factory Appointment.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Appointment(
      petName: data['petName'] ?? '',
      timeSlot: data['timeSlot'] ?? '',
      userName: data['userName'] ?? '',
      userId: data['userId'] ?? '',
      id: doc.id,
      status: data['status'] ?? 'Pending',
      appointmentDateTime: (data['appointmentDateTime'] is Timestamp)
          ? (data['appointmentDateTime'] as Timestamp).toDate()
          : DateTime.tryParse(data['appointmentDateTime'].toString()) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'petName': petName,
    'timeSlot': timeSlot,
    'userName': userName,
    'userId': userId,
    'status': status,
    'appointmentDateTime': appointmentDateTime,
  };
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final user = FirebaseAuth.instance.currentUser;

  // Theme colors (kept on-brand)
  final Color _headerColor = const Color(0xFFBDD9A4);
  final Color _primaryGreen = const Color(0xFF728D5A);
  final Color _chipGreen = const Color(0xFF9DBD81);

  StreamSubscription? _ratingSubscription;

  double _averagerating = 0.0;
  int _ratingCount = 0;

  List<Appointment> _appointments = [];
  bool _isLoading = true;

  int confirmedCount = 0;
  int pendingCount = 0;
  int declinedCount = 0;
  int completedCount = 0;
  int cancelledCount = 0;

  // Profile data
  String _name = '';
  String _location = ''; // Will be loaded from Firestore
  String _email = '';
  String _specialization = ''; // Will be loaded from Firestore
  String _vetStatus = 'Loading...';
  File? _profileImage;
  String _profileImageUrl = ''; // Firebase Storage URL

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _ratingSubscription?.cancel();
    super.dispose();
  }

// --- Loading Functions ---

// 🎯 PRIMARY LOADING FUNCTION: Ensures all data loads completely
  Future<void> _loadAllData() async {
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    
    // 1. Load basic profile (name, image) AND specialization/location from Firestore
    await _loadProfileAndDetails();

    // 2. Setup the real-time listener (relies on _name from step 1)
    _setupRatingListener();

    // 3. Load vet status (relies on user!.uid)
    await _loadVetStatus();

    // 4. Load appointments (relies on user!.uid)
    await _loadAppointments();

    // Final step: Turn off loading indicator
    if (mounted) setState(() => _isLoading = false);
  }

// Load vet status from Firestore
  Future<void> _loadVetStatus() async {
    if (user == null) return;

    try {
      final doc = await _firestore.collection('vets').doc(user!.uid).get();
      if (doc.exists) {
        final data = doc.data();
        final inactive = data?['inactive'] ?? false;
        final status = data?['status'] ?? 'Available';
        if (!mounted) return;
        setState(() {
          _vetStatus = inactive ? 'Unavailable (Deactivated)' : status;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _vetStatus = 'Status not found';
        });
      }
    } catch (e) {
      debugPrint('Error loading vet status: $e');
    }
  }

  // Load user profile from shared prefs AND specialization/location from Firestore (MODIFIED)
// Load user profile from shared prefs AND specialization/location from Firestore (MODIFIED)
  Future<void> _loadProfileAndDetails() async {
    // 1. Load local data (Name, Email, Profile Image)
    final profile = await UserPrefs.loadProfile();
    await UserPrefs.loadVerification();

    // Start with local/default values
    String newName = profile.name;
    String newEmail = profile.email;
    File? newProfileImage = profile.profileImage;
    String newProfileImageUrl = '';
    // Initialize these with generic defaults if UserPrefs happens to contain placeholders
    String newSpecialization = 'Specialization not set';
    String newLocation = 'Location not set';

    // 2. Load Specialization, Location, and Profile Image URL from Firestore using vetId
    if (user != null) {
      try {
        final doc = await _firestore.collection('vets').doc(user!.uid).get();
        if (doc.exists) {
          final data = doc.data();

          // Get the values from Firestore (or empty string if not present/null)
          final firestoreSpecialization = data?['specialization']?.toString().trim() ?? '';
          final firestoreLocation = data?['location']?.toString().trim() ?? '';
          final firestoreImageUrl = data?['profileImageUrl']?.toString().trim() ?? '';

          // ✅ Set specialization and location from Firestore.
          // If the Firestore value is an empty string, it will be handled by the logic below.
          if (firestoreSpecialization.isNotEmpty) {
            newSpecialization = firestoreSpecialization; // Use valid Firestore value
          }
          if (firestoreLocation.isNotEmpty) {
            newLocation = firestoreLocation; // Use valid Firestore value
          }
          if (firestoreImageUrl.isNotEmpty) {
            newProfileImageUrl = firestoreImageUrl; // Use Firestore image URL
          }
        }
      } catch (e) {
        debugPrint('Error loading data from Firestore: $e');
        // Fallback to SharedPreferences if Firestore fails
        await _loadProfileImageFromSharedPreferences();
      }
    }

    // 3. If no URL from Firestore, try SharedPreferences as fallback
    if (newProfileImageUrl.isEmpty && user != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        newProfileImageUrl = prefs.getString('profileImageUrl_${user!.uid}') ?? '';
        if (newProfileImageUrl.isNotEmpty) {
          debugPrint('DASHBOARD: Loaded profile image URL from SharedPreferences');
        }
      } catch (e) {
        debugPrint('Error loading profile image from SharedPreferences: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _name = newName;
      _email = newEmail;
      _profileImage = newProfileImage;
      _profileImageUrl = newProfileImageUrl;

      // Apply the prioritized values
      _specialization = newSpecialization;
      _location = newLocation;

      // Ensure the displayed location and specialization are placeholders if empty.
      // NOTE: The previous logic in the build method for display used ternary operators
      // but explicitly setting the state variable here makes the intent clearer and
      // more robust for display throughout the widget.
      if (_location.isEmpty || _location == 'Location not set') {
          _location = 'Location not set';
      }
       if (_specialization.isEmpty || _specialization == 'Specialization not set') {
          _specialization = 'Specialization not set';
      }
    });

    debugPrint('DASHBOARD: Profile loaded - name=$_name, imageUrl=$_profileImageUrl');
  }

  // Load profile image URL from SharedPreferences as fallback
  Future<void> _loadProfileImageFromSharedPreferences() async {
    if (user == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedUrl = prefs.getString('profileImageUrl_${user!.uid}') ?? '';
      if (mounted) {
        setState(() {
          _profileImageUrl = cachedUrl;
        });
      }
      debugPrint('DASHBOARD: Loaded profile image URL from SharedPreferences fallback');
    } catch (e) {
      debugPrint('Error in SharedPreferences fallback: $e');
    }
  }

  // Setup Firestore ratings listener (Handles real-time updates)
  void _setupRatingListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _name.isEmpty) return; // Must wait for _name

    if (mounted) {
      _ratingSubscription?.cancel();
    }

    // Since the rating data seems to use 'vetName', we stick to that filter here
    _ratingSubscription = _firestore
        .collection('feedback')
        .where('vetName', isEqualTo: _name) // Filter is based on _name
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      double total = 0;
      int count = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        // Ensure rating is treated as a number
        if (data.containsKey('rating') && data['rating'] is num) {
          total += (data['rating'] as num).toDouble();
          count++;
        }
      }

      setState(() {
        _ratingCount = count;
        _averagerating = count > 0 ? total / count : 0.0;
      });
    }, onError: (e) {
      debugPrint('Error listening to ratings: $e');
    });
  }

// 🔹 Load appointments and calculate STATUS SUMMARY
  Future<void> _loadAppointments() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('No logged-in vet found.');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // ✅ Fetch all appointments for this vet using UID
      final snapshot = await _firestore
          .collection('user_appointments')
          .where('vetId', isEqualTo: user.uid) // match by vet ID
          .get();

      final docs = snapshot.docs;

      // ✅ Map the appointments into objects
      final List<Appointment> loadedAppointments = docs.isNotEmpty
          ? docs.map((doc) => Appointment.fromFirestore(doc)).toList()
          : [];

      // ✅ Calculate counts for statuses
      int confirmed = 0;
      int pending = 0;
      int declined = 0;
      int completed = 0;
      int cancelled = 0;

      for (var doc in docs) {
        final data = doc.data();
        final status = data['status']?.toString().toLowerCase() ?? '';

        switch (status) {
          case 'confirmed':
            confirmed++;
            break;
          case 'pending':
            pending++;
            break;
          case 'declined':
            declined++;
            break;
          case 'completed':
            completed++;
            break;
          case 'cancelled':
            cancelled++;
            break;
        }
      }

      if (!mounted) return;

      setState(() {
        _appointments = loadedAppointments;

        confirmedCount = confirmed;
        pendingCount = pending;
        declinedCount = declined;
        completedCount = completed;
        cancelledCount = cancelled;
        
        // Note: _isLoading is set to false in _loadAllData
      });
    } catch (e) {
      debugPrint('Error loading appointments: $e');
      // If error occurs, let _loadAllData handle setting _isLoading to false
    }
  }


  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayAppointments = _appointments.where((appt) =>
        appt.status.toLowerCase() != 'completed' &&
        appt.status.toLowerCase() != 'declined' &&
        appt.status.toLowerCase() != 'cancelled' &&
        appt.appointmentDateTime.year == today.year &&
        appt.appointmentDateTime.month == today.month &&
        appt.appointmentDateTime.day == today.day).toList();

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sidebar
          const CommonSidebar(currentScreen: 'Dashboard'),

          // Main content
          Expanded(
            child: Container(
              color: const Color(0xFFF8F9F5), // Light background color for the main area
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: _primaryGreen))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 22),
                          decoration: BoxDecoration(
                            color: _headerColor,
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
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.all(10),
                                child: Icon(Icons.dashboard_rounded, color: _primaryGreen, size: 26),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Dashboard',
                                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                                ),
                              ),
                              const NotificationIcon(),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildProfileHeader(),
                                const SizedBox(height: 40),
                                _buildAppointmentsSection(todayAppointments),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // Build profile image widget with Firebase Storage support
  Widget _buildProfileImage() {
    // Priority: Firebase Storage URL -> local file -> placeholder
    if (_profileImageUrl.isNotEmpty) {
      final imageUrl = _profileImageUrl.contains('?')
          ? _profileImageUrl
          : '$_profileImageUrl?alt=media';

      return Image.network(
        imageUrl,
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: 64,
            height: 64,
            color: Colors.grey[200],
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
                color: const Color(0xFF728D5A),
                strokeWidth: 2.0,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          debugPrint('DASHBOARD IMAGE ERROR: $error');
          // Fallback to local file if network fails
          if (_profileImage != null) {
            return Image.file(
              _profileImage!,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            );
          }
          return Container(
            width: 64,
            height: 64,
            color: Colors.grey[300],
            child: const Icon(
              Icons.person,
              size: 40,
              color: Colors.white,
            ),
          );
        },
      );
    } else if (_profileImage != null) {
      // Fallback to local file
      return Image.file(
        _profileImage!,
        width: 64,
        height: 64,
        fit: BoxFit.cover,
      );
    } else {
      // Default placeholder
      return Container(
        width: 64,
        height: 64,
        color: const Color(0xFFBBD29C),
        child: const Icon(
          Icons.person,
          size: 40,
          color: Colors.white,
        ),
      );
    }
  }

  Widget _buildProfileHeader() {
    final bool isDeactivated = _vetStatus.contains('Deactivated');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isDeactivated)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.red.shade400,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Your account is deactivated. You are marked as unavailable.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: Colors.grey.shade300,
                child: ClipOval(child: _buildProfileImage()),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name.isNotEmpty ? 'Dr. $_name' : 'Vet Name',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _infoChip(_location.isNotEmpty ? _location : 'Location not set'),
                        _infoChip(_specialization.isNotEmpty ? _specialization : 'Specialization not set'),
                        _statusChip(
                          _vetStatus,
                          isAvailable: _vetStatus.toLowerCase().contains('available') &&
                              !_vetStatus.toLowerCase().contains('unavailable'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                  await _loadAllData();
                },
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Edit Profile'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAppointmentsSection(List<Appointment> todayAppointments) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Today's Appointments",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            GestureDetector(
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => AppointmentsPage(appointmentDoc: null)));
                await _loadAppointments();
              },
              child: const Text('View All', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: todayAppointments.isEmpty
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      alignment: Alignment.center,
                      child: Text(
                        "No appointments today.",
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                    )
                  : Column(
                      children: todayAppointments.map((appt) => _appointmentCard(appt)).toList(),
                    ),
            ),
            const SizedBox(width: 24),
            Expanded(flex: 2, child: _buildRatingAndSummaryBox()),
          ],
        )
      ],
    );
  }


  // Helper function to format time slot for display
  // Handles multiple formats: legacy ("11:00"), old ("11:00 - 12:00 PM"), and new ("11:00 - 12:00 NN")
  String _formatTimeSlot(String timeSlot) {
    if (timeSlot.isEmpty) return timeSlot;
    
    // Migrate old format to new format for display
    if (timeSlot == '11:00 - 12:00 PM') {
      return '11:00 - 12:00 NN';
    }
    
    // Handle legacy format where it's just the start time (e.g., "11:00")
    // Convert to full range format "11:00 - 12:00 NN"
    if (timeSlot == '11:00' || timeSlot == '11:00 AM' || timeSlot == '11:00 PM') {
      return '11:00 - 12:00 NN';
    }
    
    // Map other legacy single time formats to their full ranges
    final timeSlotMap = {
      '08:00': '8:00 - 9:00 AM',
      '8:00': '8:00 - 9:00 AM',
      '8:00 AM': '8:00 - 9:00 AM',
      '09:00': '9:00 - 10:00 AM',
      '9:00': '9:00 - 10:00 AM',
      '9:00 AM': '9:00 - 10:00 AM',
      '10:00': '10:00 - 11:00 AM',
      '10:00 AM': '10:00 - 11:00 AM',
      '12:00': '11:00 - 12:00 NN',
      '12:00 PM': '11:00 - 12:00 NN',
      '13:00': '1:00 - 2:00 PM',
      '1:00': '1:00 - 2:00 PM',
      '1:00 PM': '1:00 - 2:00 PM',
      '14:00': '2:00 - 3:00 PM',
      '2:00': '2:00 - 3:00 PM',
      '2:00 PM': '2:00 - 3:00 PM',
      '15:00': '3:00 - 4:00 PM',
      '3:00': '3:00 - 4:00 PM',
      '3:00 PM': '3:00 - 4:00 PM',
      '16:00': '4:00 - 5:00 PM',
      '4:00': '4:00 - 5:00 PM',
      '4:00 PM': '4:00 - 5:00 PM',
    };
    
    // Check if it's a legacy single time format
    if (timeSlotMap.containsKey(timeSlot)) {
      return timeSlotMap[timeSlot]!;
    }
    
    // If it already contains the full range with NN, return as-is
    if (timeSlot.contains(' - ') && timeSlot.contains('NN')) {
      return timeSlot;
    }
    
    // If it contains the full range with PM/AM, return as-is
    // (other time slots like "1:00 - 2:00 PM" should display normally)
    if (timeSlot.contains(' - ') && (timeSlot.contains('PM') || timeSlot.contains('AM'))) {
      return timeSlot;
    }
    
    // For any other format, return as-is
    return timeSlot;
  }

  Widget _appointmentCard(Appointment appt) {
    Color statusColor;
    switch (appt.status.toLowerCase()) {
      case "confirmed":
        statusColor = Colors.green.shade700;
        break;
      case "declined":
        statusColor = Colors.red.shade700;
        break;
      case "completed":
        statusColor = Colors.blue.shade700;
        break;
      case "cancelled":
        statusColor = const Color.fromARGB(255, 243, 34, 198);
        break;
      default:
        statusColor = Colors.amber.shade700;
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appt.petName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.access_time, color: Colors.grey.shade700, size: 18),
              const SizedBox(width: 6),
              Text(_formatTimeSlot(appt.timeSlot))
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.person, color: Colors.grey.shade700, size: 18),
              const SizedBox(width: 6),
              Text(appt.userName)
            ]),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AppointmentsPage(appointmentDoc: appt),
                      ),
                    );
                    await _loadAppointments();
                  },
                  icon: Icon(Icons.open_in_new, color: _primaryGreen, size: 18),
                  label: Text('View Details', style: TextStyle(color: _primaryGreen, fontWeight: FontWeight.w700)),
                ),
                _statusPill(appt.status, statusColor),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingAndSummaryBox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Overall Rating Box
        Container(
          width: double.infinity, 
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                _averagerating.toStringAsFixed(1),
                style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star, color: _primaryGreen, size: 28),
                  const SizedBox(width: 4),
                  Text(
                    'Overall Rating',
                    style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (_ratingCount > 0)
                Text(
                  'Based on $_ratingCount reviews',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Appointment Summary Box
        Container(
          width: double.infinity, // Use double.infinity for responsive width
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Appointment Summary (Total: ${confirmedCount + pendingCount + declinedCount + completedCount + cancelledCount})',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  _statusCount('Pending', pendingCount, color: Colors.amber.shade700),
                  _statusCount('Confirmed', confirmedCount, color: Colors.green.shade700),
                  _statusCount('Declined', declinedCount, color: Colors.red.shade700),
                  _statusCount('Completed', completedCount, color: Colors.blue.shade700),
                  _statusCount('Cancelled', cancelledCount,
                      color: const Color.fromARGB(255, 247, 0, 255)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Small UI helpers ---
  Widget _infoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _statusChip(String label, {required bool isAvailable}) {
    // Red if unavailable, green if available.
    final Color color = isAvailable ? _chipGreen : Colors.red.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: color,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 12),
      ),
    );
  }

  Widget _statusCount(String label, int count, {required Color color}) {
    return Column(
      children: [
        Text(count.toString(),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label),
      ],
    );
  }

}