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

class Appointment {
  final String petName;
  final String purpose;
  final String time;
  final String owner;
  final String status;
  final DateTime date;

  Appointment({
    required this.petName,
    required this.purpose,
    required this.time,
    required this.owner,
    required this.status,
    required this.date,
  });

  factory Appointment.fromJson(Map<String, dynamic> json) {
    return Appointment(
      petName: json['petName'] ?? '',
      purpose: json['purpose'] ?? '',
      time: json['time'] ?? '',
      owner: json['owner'] ?? '',
      status: json['status'] ?? 'Pending',
      date: (json['date'] is Timestamp)
          ? (json['date'] as Timestamp).toDate()
          : DateTime.tryParse(json['date'].toString()) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'petName': petName,
        'purpose': purpose,
        'time': time,
        'owner': owner,
        'status': status,
        'date': date.toIso8601String(),
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

  double _averageRating = 0.0;
  int _ratingCount = 0;
  int _selectedRating = 0;

  List<Appointment> _appointments = [];
  bool _isLoading = true;

  int confirmedCount = 0;
  int pendingCount = 0;
  int declinedCount = 0;
  int completedCount = 0;

  String _name = '';
  String _location = '';
  String _email = '';
  String _specialization = '';
  String _vetStatus = 'Loading...';
  File? _profileImage;
  bool _isVerified = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadVetStatus();
    _loadRatings();
    _loadAppointments();
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
    final verification = await UserPrefs.loadVerification();
    if (!mounted) return;
    setState(() {
      _name = profile.name;
      _location = profile.location;
      _email = profile.email;
      _specialization = profile.specialization;
      _profileImage = profile.profileImage;
      _isVerified = verification.isVerified;
    });
  }

  // Load Firestore ratings
Future<void> _loadRatings() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Read the vet’s own rating document
    final doc = await _firestore.collection('ratings').doc(user.uid).get();

    if (doc.exists) {
      final data = doc.data()!;
      if (!mounted) return;
      setState(() {
        _averageRating = (data['avg'] ?? 0).toDouble();
        _ratingCount = (data['count'] ?? 0).toInt();
      });
    } else {
      // No ratings yet
      if (!mounted) return;
      setState(() {
        _averageRating = 0;
        _ratingCount = 0;
      });
    }
  } catch (e) {
    debugPrint('Error loading ratings: $e');
  }
}


  // Load appointments
Future<void> _loadAppointments() async {
  try {
    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('No logged-in vet found.');
      setState(() => _isLoading = false);
      return;
    }

    // ✅ Query only this vet’s appointments
    final snapshot = await _firestore
        .collection('appointments')
        .where('vetId', isEqualTo: user.uid)
        .get();

    // ✅ Safely handle no results
    final List<Appointment> loadedAppointments = snapshot.docs.isNotEmpty
        ? snapshot.docs.map((doc) => Appointment.fromJson(doc.data())).toList()
        : [];

    if (!mounted) return;

    setState(() {
      _appointments = loadedAppointments;

      // ✅ Reset all counts to 0 before recounting
      confirmedCount = 0;
      pendingCount = 0;
      declinedCount = 0;
      completedCount = 0;

      if (_appointments.isNotEmpty) {
        confirmedCount = _appointments.where((a) => a.status == 'Confirmed').length;
        pendingCount = _appointments.where((a) => a.status == 'Pending').length;
        declinedCount = _appointments.where((a) => a.status == 'Declined').length;
        completedCount = _appointments.where((a) => a.status == 'Completed').length;
      }

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

  Future<void> _verifyLicense() async {
    setState(() => _isVerified = true);
    await UserPrefs.saveVerification(isVerified: true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('License verified successfully!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayAppointments = _appointments.where((appt) =>
        appt.date.year == today.year &&
        appt.date.month == today.month &&
        appt.date.day == today.day).toList();

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
              Row(
                children: [
                  if (_isVerified)
                    const Row(
                      children: [
                        Icon(Icons.verified, size: 16, color: Colors.green),
                        SizedBox(width: 4),
                        Text('License Verified'),
                      ],
                    )
                  else
                    ElevatedButton(
                      onPressed: _verifyLicense,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEAF086),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      ),
                      child: const Text('Verify License'),
                    ),
                  const SizedBox(width: 16),
                  Text('Status: $_vetStatus',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                ],
              ),
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
            if (_ratingCount == 0)
              const Text('No ratings yet', style: TextStyle(color: Colors.grey)),

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
      case "Canceled":
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
            Text(appt.purpose),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.access_time),
              const SizedBox(width: 6),
              Text(appt.time)
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.person),
              const SizedBox(width: 6),
              Text(appt.owner)
            ]),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(onPressed: () {}, child: const Text('View Details')),
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
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                _averageRating.toStringAsFixed(1),
                style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold),
              ),
              const Icon(Icons.star, color: Colors.green, size: 30),
              const Text('Overall Rating'),
              Text(
                '$_ratingCount Client Feedbacks',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Appointment Summary',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusCount('Pending', pendingCount, color: Colors.orange),
                  _statusCount('Confirmed', confirmedCount, color: Colors.green),
                  _statusCount('Declined', declinedCount, color: Colors.red),
                  _statusCount('Completed', completedCount, color: Colors.blue),
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