import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/analytics_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import 'dashboard_screen.dart';
import 'appointments_table_view.dart';
import 'patients_list_screen.dart';
import 'profile_screen.dart';
import 'feedback_screen.dart';
import 'zoom_meeting_screen.dart'; // ✅ NEW IMPORT

void main() {
  runApp(const FureverHealthyApp());
}

class FureverHealthyApp extends StatelessWidget {
  const FureverHealthyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AppointmentsPage(),
    );
  }
}

/// Appointment Model
class Appointment {
  DateTime date;
  String petName;
  String purpose;
  String time;
  String owner;
  String status;

  Appointment({
    required this.date,
    required this.petName,
    required this.purpose,
    required this.time,
    required this.owner,
    this.status = "Pending",
  });

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'petName': petName,
        'purpose': purpose,
        'time': time,
        'owner': owner,
        'status': status,
      };

  static Appointment fromJson(Map<String, dynamic> json) => Appointment(
        date: DateTime.parse(json['date']),
        petName: json['petName'],
        purpose: json['purpose'],
        time: json['time'],
        owner: json['owner'],
        status: json['status'],
      );
}

class AppointmentsPage extends StatefulWidget {
  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  List<DateTime> _bookedDates = [];
  List<Appointment> _appointments = [];

  String _selectedFilter = "All";

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('appointments') ?? [];
    setState(() {
      _appointments =
          saved.map((e) => Appointment.fromJson(jsonDecode(e))).toList();
      _bookedDates = _appointments.map((e) => e.date).toList();
    });
  }

  Future<void> _saveAppointments() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _appointments.map((a) => jsonEncode(a.toJson())).toList();
    await prefs.setStringList('appointments', data);
  }

  Future<void> _clearAppointments() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('appointments');
    setState(() {
      _appointments.clear();
      _bookedDates.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredAppointments = _appointments.where((appt) {
      return _selectedFilter == "All" || appt.status == _selectedFilter;
    }).toList();

    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // HEADER
                Container(
                  width: double.infinity,
                  color: const Color(0xFFBDD9A4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        "Appointments",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),

                // MAIN CONTENT
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // FILTER TABS + TABLE VIEW + ZOOM BTN
                        Row(
                          children: [
                            _tabButton("All"),
                            _tabButton("Pending"),
                            _tabButton("Confirmed"),
                            _tabButton("Declined"),
                            _tabButton("Completed"),
                            const Spacer(),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF728D5A),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AppointmentsTableView(
                                        appointments: _appointments),
                                  ),
                                );
                              },
                              child: const Text("Table View"),
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
                        const SizedBox(height: 20),

                        // LIST + CALENDAR
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // LIST VIEW
                              Expanded(
                                child: filteredAppointments.isEmpty
                                    ? const Center(
                                        child: Text(
                                          "No appointments found.",
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: Color.fromARGB(
                                                255, 110, 110, 110),
                                          ),
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

                              // CALENDAR
                              _buildCalendarSection(),
                            ],
                          ),
                        ),
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

  /// Sidebar
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
            MaterialPageRoute(builder: (_) => const PatientsListScreen()),
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
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Calendar
  Widget _buildCalendarSection() {
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
            child: Text(
              "Booked Dates",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
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
                if (_bookedDates.any((d) => isSameDay(d, date))) {
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
                color: Colors.grey.shade400,
                shape: BoxShape.circle,
              ),
              selectedDecoration: const BoxDecoration(
                color: Color(0xFF9DBD81),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Appointment Card
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
                child: Text(
                  appt.petName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              DropdownButton<String>(
                value: appt.status,
                underline: const SizedBox(),
                items: ["Pending", "Confirmed", "Declined", "Completed"]
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      appt.status = val;
                      _saveAppointments();
                    });
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
              const Spacer(),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color.fromARGB(255, 169, 225, 150),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text("Notify Owner"),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _showBookingDialog(context, appt.date,
                    existing: appt),
                child: const Text("Edit"),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _appointments.remove(appt);
                    _bookedDates.removeWhere((d) =>
                        isSameDay(d, appt.date) &&
                        !_appointments.any((a) => isSameDay(a.date, d)));
                    _saveAppointments();
                  });
                },
                child: const Text("Delete",
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          )
        ],
      ),
    );
  }

  /// Filter Tabs
  Widget _tabButton(String label) {
    final isSelected = _selectedFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedFilter = label;
          });
        },
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// Edit Appointment Dialog
  void _showBookingDialog(BuildContext context, DateTime date,
      {Appointment? existing}) {
    final petController = TextEditingController(text: existing?.petName ?? "");
    final purposeController =
        TextEditingController(text: existing?.purpose ?? "");
    final timeController = TextEditingController(text: existing?.time ?? "");
    final ownerController = TextEditingController(text: existing?.owner ?? "");
    String status = existing?.status ?? "Pending";

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Edit Appointment"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: petController,
                    decoration: const InputDecoration(labelText: "Pet Name")),
                TextField(
                    controller: purposeController,
                    decoration: const InputDecoration(labelText: "Purpose")),
                TextField(
                    controller: timeController,
                    decoration: const InputDecoration(labelText: "Time")),
                TextField(
                    controller: ownerController,
                    decoration: const InputDecoration(labelText: "Owner Name")),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(labelText: "Status"),
                  items: ["Pending", "Confirmed", "Declined", "Completed"]
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) status = val;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  if (existing != null) {
                    existing.petName = petController.text;
                    existing.purpose = purposeController.text;
                    existing.time = timeController.text;
                    existing.owner = ownerController.text;
                    existing.status = status;
                    _saveAppointments();
                  }
                });
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color.fromARGB(255, 204, 224, 193)),
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }
}
