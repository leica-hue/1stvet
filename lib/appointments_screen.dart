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
  DateTime date;
  String petName;
  String purpose;
  String time;
  String owner;
  String status;
  String vetNotes;
  String vetId;

  Appointment({
    required this.id,
    required this.date,
    required this.petName,
    required this.purpose,
    required this.time,
    required this.owner,
    this.status = "Pending",
    this.vetNotes = "",
    required this.vetId,
  });

  Map<String, dynamic> toJson() => {
    'date': date,
    'petName': petName,
    'purpose': purpose,
    'time': time,
    'owner': owner,
    'status': status,
    'vetNotes': vetNotes,
    'vetId': vetId,
  };

  /**
   * Corrected fromDoc method to safely handle potential null 'date' fields.
   */
  static Appointment fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Safely cast to Timestamp? and use null-coalescing for a fallback date.
    final Timestamp? dateTimestamp = data['date'] as Timestamp?;
    final DateTime appointmentDate = dateTimestamp?.toDate() ?? DateTime(2000); 

    return Appointment(
      id: doc.id,
      date: appointmentDate,
      petName: data['petName'] ?? '',
      purpose: data['purpose'] ?? '',
      time: data['time'] ?? '',
      owner: data['owner'] ?? '',
      status: data['status'] ?? 'Pending',
      vetNotes: data['vetNotes'] ?? '',
      vetId: data['vetId'] ?? '',
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
  String _selectedFilter = "All";
  //bool _showOnlyMine = false; // toggle for filtering dynamically

  final user = FirebaseAuth.instance.currentUser;

  Stream<QuerySnapshot> _getAppointmentStream() {
    if ( user != null) {
      return FirebaseFirestore.instance
          .collection('appointments')
          .where('vetId', isEqualTo: user!.uid)
          .snapshots();
    } else {
      return FirebaseFirestore.instance.collection('appointments')
      .where('vetId', isEqualTo: 'none')
      .snapshots();
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

                // Main content
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
                          return _selectedFilter == "All" ||
                              appt.status == _selectedFilter;
                        }).toList();

                        final bookedDates =
                            appointments.map((e) => e.date).toList();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ✅ Toggle for All vs Mine
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    _tabButton("All"),
                                    _tabButton("Pending"),
                                    _tabButton("Confirmed"),
                                    _tabButton("Declined"),
                                    _tabButton("Completed"),
                                    const SizedBox(width: 10),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF728D5A),
                                          foregroundColor: Colors.white),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => AppointmentsTableView(
                                                appointments: appointments),
                                          ),
                                        );
                                      },
                                      child: const Text("Table View"),
                                    ),
                                    const SizedBox(width: 10),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF9DBD81),
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => VetNotesScreen(
                                              appointments: appointments,
                                              onSave: () async {},
                                            ),
                                          ),
                                        );
                                      },
                                      child: const Text("History & Notes"),
                                    ),
                                    const SizedBox(width: 10),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blueGrey,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  const CreateZoomMeetingScreen()),
                                        );
                                      },
                                      child: const Text("Join Zoom"),
                                    ),
                                  ],
                                ),
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
      case "Confirmed":
        statusColor = Colors.green;
        break;
      case "Declined":
        statusColor = Colors.red;
        break;
      case "Completed":
        statusColor = Colors.blue;
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
                child: Text(appt.petName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              DropdownButton<String>(
                value: appt.status,
                underline: const SizedBox(),
                items: ["Pending", "Confirmed", "Declined", "Completed"]
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (newStatus) async {
                  if (newStatus != null) {
                    await FirebaseFirestore.instance
                        .collection('appointments')
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
          const SizedBox(height: 4),
          Text(appt.purpose),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.access_time, size: 18),
              const SizedBox(width: 6),
              Text(appt.time),
              const SizedBox(width: 20),
              const Icon(Icons.person, size: 18),
              const SizedBox(width: 6),
              Text(appt.owner),
            ],
          ),
          const SizedBox(height: 8),
          if (appt.vetNotes.isNotEmpty)
            Text("Notes: ${appt.vetNotes}",
                style: const TextStyle(
                    fontStyle: FontStyle.italic, fontSize: 14)),
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
          // 
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