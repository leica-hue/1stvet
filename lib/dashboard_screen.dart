import 'dart:async'; // Keep for StreamSubscription type
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'analytics_screen.dart';
import 'feedback_screen.dart';
import 'appointments_screen.dart';
import 'profile_screen.dart';
import 'login_screen.dart';
import 'settings_screen.dart' hide LoginScreen;
import 'patients_list_screen.dart';
import 'user_prefs.dart';

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

  String _name = '';
  String _location = '';
  String _email = '';
  String _specialization = '';
  String _vetStatus = 'Loading...';
  File? _profileImage;
  // Removed: bool _isVerified = false; 
  
@override
void initState() {
  super.initState();
  _loadAllData();
}

// Ensure profile loads first so _name is available for the listener
Future<void> _loadAllData() async {
    // 1. Wait until _name is loaded (via setState inside _loadProfile)
    await _loadProfile();
    
    // 2. Setup the real-time listener using the loaded _name
    _setupRatingListener();
    
    // 3. Load other data concurrently
    _loadVetStatus();
    _loadAppointments();
}
  
  @override
  void dispose() {
    _ratingSubscription?.cancel();
    super.dispose();
  }

  // Load vet status from Firestore
  Future<void> _loadVetStatus() async {
    if (user == null) return;

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
  }

  // Load user profile from shared prefs
  Future<void> _loadProfile() async {
    final profile = await UserPrefs.loadProfile();
    await UserPrefs.loadVerification(); // Keep loading it to avoid removing the UserPrefs function, but don't use the result
    if (!mounted) return;
    setState(() {
      _name = profile.name;
      _location = profile.location;
      _email = profile.email;
      _specialization = profile.specialization;
      _profileImage = profile.profileImage;
      // Removed: _isVerified = verification.isVerified;
    });
  }

  // Setup Firestore ratings listener (Handles real-time updates)
void _setupRatingListener() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || _name.isEmpty) return; // Must wait for _name

  if (mounted) {
      _ratingSubscription?.cancel();
  }

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
      if (data['rating'] != null) {
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

// 🔹 Load appointments and calculate STATUS SUMMARY (NO RATING CALCULATION HERE)
Future<void> _loadAppointments() async {
  try {
    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('No logged-in vet found.');
      setState(() => _isLoading = false);
      return;
    }

    // ✅ Fetch all appointments for this vet
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
      
      _isLoading = false;
    });
  } catch (e) {
    debugPrint('Error loading appointments: $e');
    if (!mounted) return;
    setState(() => _isLoading = false);
  }
}

  Future<void> _handleSidebarTap(String label) async {
    switch (label) {
      case 'Profile':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
        await _loadProfile();
        break;
      case 'Appointments':
        // Ensure AppointmentsPage can handle null if used from dashboard
        await Navigator.push(context, MaterialPageRoute(builder: (_) => AppointmentsPage(appointmentDoc: null)));
        await _loadAppointments();
        break;
      case 'Analytics':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalyticsScreen()));
        await _loadAppointments();
        break;
      case 'Feedback':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const VetFeedbackScreen()));
        break;
      case 'Settings':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
        break;
      case 'Patients':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const PatientHistoryScreen()));
        break;
      case 'Log out':
        await UserPrefs.clearLoggedIn();
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen(registeredEmail: '', registeredPassword: '')),
          (route) => false,
        );
        break;
    }
  }
  
  // Removed: Future<void> _verifyLicense() async { ... }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayAppointments = _appointments.where((appt) =>
        appt.appointmentDateTime.year == today.year &&
        appt.appointmentDateTime.month == today.month &&
        appt.appointmentDateTime.day == today.day).toList();

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sidebar
          Container(
            width: 220,
            color: const Color(0xFF728D5A),
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Column(
              children: [
                Image.asset('assets/furever2.png', width: 140),
                const SizedBox(height: 40),
                _buildSidebarItem('Profile', icon: Icons.person),
                _buildSidebarItem('Dashboard', icon: Icons.dashboard, selected: true),
                _buildSidebarItem('Appointments', icon: Icons.event),
                _buildSidebarItem('Analytics', icon: Icons.analytics),
                _buildSidebarItem('Patients', icon: Icons.pets),
                _buildSidebarItem('Feedback', icon: Icons.feedback_outlined),
                const Spacer(),
                _buildSidebarItem('Settings', icon: Icons.settings),
                _buildSidebarItem('Log out', icon: Icons.logout),
              ],
            ),
          ),

          // Main content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          color: const Color(0xFFBDD9A4),
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Dashboard',
                                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
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
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Deactivation Banner
        if (_vetStatus.contains('Deactivated'))
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.red.shade300,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Your account is deactivated. You are marked as unavailable.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),

        Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: Colors.grey.shade300,
              backgroundImage: _profileImage != null ? FileImage(_profileImage!) : null,
              child: _profileImage == null
                  ? const Icon(Icons.person, size: 40, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text(_location),
                Text(_specialization, style: const TextStyle(color: Colors.black87)),
                const SizedBox(height: 6),
                // Removed the License Verification Row content
                Text('Status: $_vetStatus',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
              ],
            ),
            const Spacer(),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEAF086),
                foregroundColor: Colors.black,
              ),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                await _loadProfile();
              },
              child: const Text('Edit Profile'),
            ),
          ],
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
                  ? const Center(
                      child: Text("No appointments today.",
                          style: TextStyle(fontSize: 16, color: Colors.grey)),
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

  Widget _appointmentCard(Appointment appt) {
    Color statusColor;
    switch (appt.status) {
      case "Confirmed":
        statusColor = Colors.green;
        break;
      case "Declined":
        statusColor = Colors.red;
        break;
      case "Completed":
        statusColor = Colors.blue;
        break;
      case "Cancelled":
        statusColor = Colors.orange;
        break;
      default:
        statusColor = Colors.yellow.shade700;
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appt.petName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.access_time),
              const SizedBox(width: 6),
              Text(appt.timeSlot)
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.person),
              const SizedBox(width: 6),
              Text(appt.userName)
            ]),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AppointmentsPage(appointmentDoc: appt),
                    ),
                  );
                  await _loadAppointments();
                }, child: const Text('View Details')),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(appt.status, style: TextStyle(color: statusColor)),
                )
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
        width: 300, // Fixed width
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              _averagerating.toStringAsFixed(1),
              style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.star, color: Colors.green, size: 30),
                const SizedBox(width: 4),
                Text(
                  'Overall Rating', // Display count for verification
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      // Appointment Summary Box
      Container(
        width: 430, // Fixed width
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Appointment Summary (Total: ${confirmedCount + pendingCount + declinedCount + completedCount + cancelledCount})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _statusCount('pending', pendingCount, color: Colors.orange),
                _statusCount('confirmed', confirmedCount, color: Colors.green),
                _statusCount('declined', declinedCount, color: Colors.red),
                _statusCount('completed', completedCount, color: Colors.blue),
                _statusCount('cancelled', cancelledCount,
                    color: const Color.fromARGB(255, 247, 0, 255)),
              ],
            ),
          ],
        ),
      ),
    ],
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

  Widget _buildSidebarItem(String label, {IconData? icon, bool selected = false}) {
    return InkWell(
      onTap: () => _handleSidebarTap(label),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (icon != null) Icon(icon, color: Colors.white, size: 20),
            if (icon != null) const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
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
}