import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dashboard_screen.dart';
import 'appointments_table_view.dart';
import 'patients_list_screen.dart';
import 'profile_screen.dart';
import 'feedback_screen.dart';
import 'zoom_meeting_screen.dart';
import 'vet_history_notes_screen.dart';
import 'analytics_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const FureverHealthyApp());
}

class FureverHealthyApp extends StatelessWidget {
  const FureverHealthyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AppointmentsPage(appointmentDoc: null),
    );
  }
}

class Appointment {
  String id;
  DateTime appointmentDateTime;
  String petName;
  String reason;
  String timeSlot;
  String userName;
  String status;
  String vetNotes;
  String userId;
  String vetId;
  DateTime? createdAt;
  String vetName;
  String vetSpecialty;
  int vetRating;
  int cost;
  String appointmentType;
  String userEmail;

  Appointment({
    required this.id,
    required this.appointmentDateTime,
    required this.petName,
    required this.reason,
    required this.timeSlot,
    required this.userName,
    this.status = "Pending",
    this.vetNotes = "",
    required this.userId,
    required this.vetId,
    this.createdAt,
    this.vetName = '',
    this.vetSpecialty = '',
    this.vetRating = 0,
    this.cost = 0,
    this.appointmentType = '',
    this.userEmail = '',
  });

  static Appointment fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final Timestamp? apptTs = data['appointmentDateTime'] as Timestamp?;
    final Timestamp? createdAtTs = data['createdAt'] as Timestamp?;

    return Appointment(
      id: doc.id,
      appointmentDateTime: apptTs?.toDate() ?? DateTime.now(),
      petName: data['petName'] ?? '',
      reason: data['reason'] ?? '',
      timeSlot: data['timeSlot'] ?? '',
      userName: data['userName'] ?? '',
      status: data['status'] ?? 'Pending',
      vetNotes: data['vetNotes'] ?? '',
      userId: data['userId'] ?? '',
      vetId: data['vetId'] ?? '',
      createdAt: createdAtTs?.toDate(),
      vetName: data['vetName'] ?? 'N/A',
      vetSpecialty: data['vetSpecialty'] ?? 'N/A',
      vetRating: (data['vetRating'] as num?)?.toInt() ?? 0,
      cost: (data['cost'] as num?)?.toInt() ?? 0,
      appointmentType: data['appointmentType'] ?? 'N/A',
      userEmail: data['userEmail'] ?? '',
    );
  }
}

class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({super.key, required appointmentDoc});

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  String _selectedFilter = "all";
  final user = FirebaseAuth.instance.currentUser;

  Stream<QuerySnapshot> _getAppointmentStream() {
    if (user != null) {
      // ✅ Vet will only see appointments assigned to them
      return FirebaseFirestore.instance
          .collection('user_appointments')
          .where('vetId', isEqualTo: user!.uid)
          .snapshots();
    } else {
      return const Stream.empty();
    }
  }

  Widget _tabButton(String label) {
    final isSelected = _selectedFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ElevatedButton(
        onPressed: () {
          setState(() => _selectedFilter = label);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isSelected ? const Color(0xFF728D5A) : Colors.grey.shade300,
          foregroundColor: isSelected ? Colors.white : Colors.black,
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  color: const Color(0xFFBDD9A4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: const Text(
                    "Appointments",
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black),
                  ),
                ),

                // Main Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _getAppointmentStream(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(
                              child: Text("No appointments found."));
                        }

                        final appointments = snapshot.data!.docs
                            .map((doc) => Appointment.fromDoc(doc))
                            .toList();

                        final filteredAppointments = appointments.where((appt) {
                          return _selectedFilter == "all" ||
                              appt.status == _selectedFilter;
                        }).toList();

                        final bookedDates =
                            appointments.map((e) => e.appointmentDateTime).toList();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _tabButton("all"),
                                _tabButton("pending"),
                                _tabButton("confirmed"),
                                _tabButton("declined"),
                                _tabButton("completed"),
                                _tabButton("cancelled"),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: filteredAppointments.isEmpty
                                        ? const Center(
                                            child: Text(
                                              "No appointments found.",
                                              style: TextStyle(
                                                  fontSize: 16,
                                                  color: Colors.grey),
                                            ),
                                          )
                                        : ListView(
                                            children: filteredAppointments
                                                .map((appt) =>
                                                    _appointmentCard(appt))
                                                .toList(),
                                          ),
                                  ),
                                  const SizedBox(width: 20),
                                  _buildCalendarSection(bookedDates),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
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
      case "confirmed":
        statusColor = Colors.green;
        break;
      case "declined":
        statusColor = Colors.red;
        break;
      case "completed":
        statusColor = Colors.blue;
        break;
      case "cancelled":
        statusColor = Colors.purple;
        break;
      default:
        statusColor = Colors.orange;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  appt.petName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              Text(
                "₱${appt.cost}",
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xFF728D5A)),
              ),
              const SizedBox(width: 10),

              // ✅ Vet can update status
              DropdownButton<String>(
                value: appt.status,
                underline: const SizedBox(),
                items: [
                  "pending",
                  "confirmed",
                  "declined",
                  "completed",
                  "cancelled"
                ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (newStatus) async {
                  if (newStatus != null) {
                    await FirebaseFirestore.instance
                        .collection('user_appointments')
                        .doc(appt.id)
                        .update({'status': newStatus});
                  }
                },
              ),

              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(left: 6),
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text("${appt.reason} (${appt.appointmentType})"),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.access_time, size: 18),
              const SizedBox(width: 6),
              Text(appt.timeSlot),
              const SizedBox(width: 20),
              const Icon(Icons.person, size: 18),
              const SizedBox(width: 6),
              Text(appt.userName),
              const SizedBox(width: 20),
              const Icon(Icons.email_outlined, size: 18),
              const SizedBox(width: 6),
              Text(appt.userEmail),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.medical_services_outlined, size: 18),
              const SizedBox(width: 6),
              Text("${appt.vetName} (${appt.vetSpecialty})",
                  style: const TextStyle(fontStyle: FontStyle.italic)),
              const Spacer(),
              const Icon(Icons.star, size: 16, color: Colors.amber),
              Text(appt.vetRating.toString()),
            ],
          ),
          if (appt.vetNotes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text("Notes: ${appt.vetNotes}",
                  style: const TextStyle(fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 240,
      color: const Color(0xFF728D5A),
      child: Column(
        children: [
          const SizedBox(height: 30),
          Image.asset('assets/furever2.png', width: 140),
          const SizedBox(height: 40),
          _sidebarItem(Icons.person_outline, "Profile"),
          _sidebarItem(Icons.dashboard, "Dashboard"),
          _sidebarItem(Icons.event_note, "Appointments", selected: true),
          _sidebarItem(Icons.analytics, "Analytics"),
          _sidebarItem(Icons.pets, "Patients"),
          _sidebarItem(Icons.feedback_outlined, "Feedback"),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String title, {bool selected = false}) {
    return InkWell(
      onTap: () {
        if (title == "Dashboard") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const DashboardScreen()),
          );
        } else if (title == "Patients") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const PatientHistoryScreen()),
          );
        } else if (title == "Analytics") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
          );
        } else if (title == "Profile") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          );
        } else if (title == "Feedback") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const VetFeedbackScreen()),
          );
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        color: selected ? const Color(0xFF5C7449) : Colors.transparent,
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 14),
            Text(title,
                style: TextStyle(
                    color: Colors.white,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarSection(List<DateTime> bookedDates) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text("Booked Dates",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(height: 10),
          TableCalendar(
            firstDay: DateTime.utc(2025, 1, 1),
            lastDay: DateTime.utc(2025, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, date, events) {
                if (bookedDates.any((d) => isSameDay(d, date))) {
                  return Positioned(
                    bottom: 1,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }
                return null;
              },
            ),
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
            ),
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                  color: Colors.grey.shade400, shape: BoxShape.circle),
              selectedDecoration: const BoxDecoration(
                  color: Color(0xFF9DBD81), shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}
