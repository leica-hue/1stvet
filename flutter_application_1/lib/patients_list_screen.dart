import 'package:flutter/material.dart';
import 'package:flutter_application_1/profile_screen.dart';
import 'patients_screen.dart';
import 'dashboard_screen.dart';
import 'appointments_table_view.dart';
import 'settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class PatientsListScreen extends StatefulWidget {
  const PatientsListScreen({super.key});

  @override
  State<PatientsListScreen> createState() => _PatientsListScreenState();
}

class _PatientsListScreenState extends State<PatientsListScreen> {
  final Color sidebarColor = const Color(0xFF728D5A); // green sidebar
  final Color headerColor = const Color(0xFFBDD9A4); // light green header

  List<Map<String, String>> patients = [];

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    final prefs = await SharedPreferences.getInstance();
    final String? patientsJson = prefs.getString("patients");

    if (patientsJson != null) {
      final List<dynamic> decoded = jsonDecode(patientsJson);
      setState(() {
        patients = decoded.map((e) => Map<String, String>.from(e)).toList();
      });
    }
  }

  Future<void> _savePatients() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(patients);
    await prefs.setString("patients", encoded);
  }

  void _addPatient(Map<String, String> patient) {
    setState(() {
      patients.add(patient);
    });
    _savePatients();
  }

  Future<void> _openPatientForm() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PatientsScreen(),
      ),
    );

    if (result != null && result is Map<String, String>) {
      _addPatient(result);
    }
  }

  void _viewPatientDetails(Map<String, String> patient) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Patient: ${patient["Patient Name"] ?? ""}"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow("Species", patient["Species"]),
              _detailRow("Breed", patient["Breed"]),
              _detailRow("Height", patient["Height"]),
              _detailRow("Weight", patient["Weight"]),
              _detailRow("Appearance", patient["Appearance"]),
              _detailRow("Owner Info", patient["Owner Info"]),
              _detailRow("Last Consultation", patient["Last Consultation"]),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        "$label: ${value ?? "-"}",
        style: const TextStyle(fontSize: 15),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar (identical to dashboard)
          Container(
            width: 220,
            color: sidebarColor,
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Column(
              children: [
                Image.asset('assets/furever2.png', width: 140),
                const SizedBox(height: 40),

                _sidebarItem(
                  "Profile",
                  icon: Icons.person,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfileScreen(),
                      ),
                    );
                  },
                ),
                _sidebarItem(
                  "Dashboard",
                  icon: Icons.dashboard,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DashboardScreen(),
                      ),
                    );
                  },
                ),
                _sidebarItem(
                  "Patients",
                  icon: Icons.pets,
                  selected: true,
                  onTap: () {
                    // Stay on this page
                  },
                ),
                _sidebarItem(
                  "Appointments",
                  icon: Icons.calendar_today,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AppointmentsTableView(
                          appointments: [],
                        ),
                      ),
                    );
                  },
                ),
                _sidebarItem(
                  "Feedback",
                  icon: Icons.feedback,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Main content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  color: headerColor,
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Patients",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _openPatientForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 18),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text(
                          "Add Patient",
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                    ],
                  ),
                ),

                // Patients Table
                Expanded(
                  child: patients.isEmpty
                      ? const Center(
                          child: Text(
                            "No patients found.\nClick 'Add Patient' to add one.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black54,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columnSpacing: 30,
                              headingRowColor: MaterialStateColor.resolveWith(
                                  (states) => Colors.grey.shade200),
                              columns: const [
                                DataColumn(label: Text("Name")),
                                DataColumn(label: Text("Species")),
                                DataColumn(label: Text("Breed")),
                                DataColumn(label: Text("Owner")),
                                DataColumn(label: Text("Actions")),
                              ],
                              rows: patients.map((p) {
                                return DataRow(
                                  cells: [
                                    DataCell(Text(p["Patient Name"] ?? "")),
                                    DataCell(Text(p["Species"] ?? "")),
                                    DataCell(Text(p["Breed"] ?? "")),
                                    DataCell(Text(p["Owner Info"] ?? "")),
                                    DataCell(
                                      IconButton(
                                        icon: const Icon(
                                          Icons.visibility,
                                          color: Colors.blue,
                                        ),
                                        onPressed: () =>
                                            _viewPatientDetails(p),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _sidebarItem(String title,
      {required IconData icon,
      bool selected = false,
      VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        decoration: BoxDecoration(
          color: selected ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
