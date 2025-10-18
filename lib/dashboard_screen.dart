import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/analytics_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'appointments_screen.dart';
import 'profile_screen.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'patients_list_screen.dart';
import 'user_prefs.dart';

// If you already have this model elsewhere, remove this and import your model instead.
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
      petName: json['petName'] as String,
      purpose: json['purpose'] as String,
      time: json['time'] as String,
      owner: json['owner'] as String,
      status: json['status'] as String,
      date: DateTime.parse(json['date'] as String),
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
  double _averageRating = 4.9;
  int _ratingCount = 121;
  int _selectedRating = 0;

  List<Appointment> _appointments = [];
  int confirmedCount = 0;
  int pendingCount = 0;
  int declinedCount = 0;
  int completedCount = 0;

  String _name = 'Dr. Sarah Doe';
  String _location = 'Marawoy, Lipa City, Batangas';
  String _email = 'sarah@vetclinic.com';
  String _specialization = 'Pathology';
  File? _profileImage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadAppointments();
    _loadRatings();
  }

  Future<void> _loadProfile() async {
    final profile = await UserPrefs.loadProfile();
    if (!mounted) return;
    setState(() {
      _name = profile.name;
      _location = profile.location;
      _email = profile.email;
      _specialization = profile.specialization;
      _profileImage = profile.profileImage;
    });
  }

  Future<void> _loadRatings() async {
    final r = await UserPrefs.loadRatings();
    if (!mounted) return;
    setState(() {
      _averageRating = r.avg;
      _ratingCount = r.count;
      _selectedRating = r.selected;
    });
  }

  Future<void> _loadAppointments() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('appointments') ?? [];

    if (!mounted) return;
    setState(() {
      _appointments =
          saved.map((e) => Appointment.fromJson(jsonDecode(e))).toList();
      confirmedCount =
          _appointments.where((a) => a.status == 'Confirmed').length;
      pendingCount = _appointments.where((a) => a.status == 'Pending').length;
      declinedCount =
          _appointments.where((a) => a.status == 'Declined').length;
      completedCount =
          _appointments.where((a) => a.status == 'Completed').length;
    });
  }

  Future<void> _saveAppointments() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'appointments',
      _appointments.map((a) => jsonEncode(a.toJson())).toList(),
    );
  }

  void _submitRating(int newRating) async {
    setState(() {
      _averageRating =
          ((_averageRating * _ratingCount) + newRating) / (_ratingCount + 1);
      _ratingCount++;
      _selectedRating = newRating;
    });
    await UserPrefs.saveRatings(
      avg: _averageRating,
      count: _ratingCount,
      selected: _selectedRating,
    );
  }

  Future<void> _handleSidebarTap(String label) async {
    if (label == 'Profile') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
      await _loadProfile();
    } else if (label == 'Appointments') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AppointmentsPage()),
      );
    } else if (label == 'Analytics') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
      );
      await _loadAppointments();
    } else if (label == 'Settings') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
    } else if (label == 'Log out') {
      await UserPrefs.clearLoggedIn();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const LoginScreen(
            registeredEmail: '',
            registeredPassword: '',
          ),
        ),
        (Route<dynamic> route) => false,
      );
    } else if (label == 'Patients') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PatientsListScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayAppointments = _appointments.where((appt) {
      return appt.date.year == today.year &&
          appt.date.month == today.month &&
          appt.date.day == today.day;
    }).toList();

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
                _buildSidebarItem('Dashboard',
                    icon: Icons.dashboard, selected: true),
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

          // Main
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  color: const Color(0xFFBDD9A4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        'Dashboard',
                        style:
                            TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                // Body
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Profile section
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 32,
                              backgroundColor: Colors.grey.shade300,
                              backgroundImage: _profileImage != null
                                  ? FileImage(_profileImage!)
                                  : null,
                              child: _profileImage == null
                                  ? const Icon(Icons.person,
                                      size: 40, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 20),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_name,
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold)),
                                Text(_location),
                                const Row(
                                  children: [
                                    Icon(Icons.verified,
                                        size: 16, color: Colors.green),
                                    SizedBox(width: 4),
                                    Text('License Verified'),
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
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const ProfileScreen()),
                                );
                                await _loadProfile();
                              },
                              child: const Text('Edit Profile'),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE5F5E9),
                              ),
                              onPressed: () {},
                              child: const Text('View Public Profile'),
                            )
                          ],
                        ),
                        const SizedBox(height: 40),

                        // Appointments header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Today's Appointments",
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            GestureDetector(
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => AppointmentsPage()),
                                );
                                await _loadAppointments();
                              },
                              child: const Text('View All',
                                  style: TextStyle(
                                      color: Color.fromARGB(255, 15, 15, 15))),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Appointments + rating summary
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: todayAppointments.isEmpty
                                  ? const Center(
                                      child: Text(
                                        "No appointments today.",
                                        style: TextStyle(
                                            fontSize: 16, color: Colors.grey),
                                      ),
                                    )
                                  : Column(
                                      children: todayAppointments
                                          .map((appt) => _appointmentCard(appt))
                                          .toList(),
                                    ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              flex: 2,
                              child: _buildRatingAndSummaryBox(),
                            ),
                          ],
                        )
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

  Widget _appointmentCard(Appointment appt) {
    Color statusColor;
    switch (appt.status) {
      case "Confirmed":
        statusColor = Colors.green;
        break;
      case "Declined":
        statusColor = Colors.red;
        break;
      case "Canceled":
        statusColor = Colors.orange;
        break;
      case "Completed":
        statusColor = Colors.blue;
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
            Text(appt.petName,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
              Text(_averageRating.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 42, fontWeight: FontWeight.bold)),
              const Icon(Icons.star, color: Colors.green, size: 30),
              const Text('Rating'),
              Text('$_ratingCount Client Feedback',
                  style: const TextStyle(color: Colors.grey)),
              const Divider(),
              const Text('Submit your rating:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final starIndex = index + 1;
                  return IconButton(
                    icon: Icon(
                      Icons.star,
                      color: starIndex <= _selectedRating
                          ? Colors.amber
                          : Colors.grey.shade400,
                    ),
                    onPressed: () => _submitRating(starIndex),
                  );
                }),
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
              const Text('Appointment Summary',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _statusCount('Pending', pendingCount, color: Colors.orange),
                  _statusCount('Confirmed', confirmedCount, color: Colors.green),
                  _statusCount('Declined', declinedCount, color: Colors.red),
                  _statusCount('Completed', completedCount, color: Colors.blue),
                ],
              ),
              const Divider(height: 30),
              const Text('Specialization',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: _specialization,
                isExpanded: true,
                onChanged: (String? newValue) async {
                  if (newValue == null) return;
                  final prefs = await SharedPreferences.getInstance();
                  setState(() => _specialization = newValue);
                  await prefs.setString(UserPrefsKeys.specialization, newValue);
                },
                items: const ['Pathology', 'Dermatology', 'Behaviour']
                    .map<DropdownMenuItem<String>>(
                      (v) => DropdownMenuItem<String>(
                        value: v,
                        child: Text(v),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget _statusCount(String label, int count, {required Color color}) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label),
      ],
    );
  }

  Widget _buildSidebarItem(String label,
      {IconData? icon, bool selected = false}) {
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
