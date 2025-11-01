import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/analytics_screen.dart';
import 'package:flutter_application_1/feedback_screen.dart';
import 'package:flutter_application_1/profile_screen.dart';
import 'patients_screen.dart';
import 'dashboard_screen.dart';
import 'appointments_screen.dart';

class PatientsListScreen extends StatefulWidget {
  const PatientsListScreen({super.key});

  @override
  State<PatientsListScreen> createState() => _PatientsListScreenState();
}

class _PatientsListScreenState extends State<PatientsListScreen> {
  final Color sidebarColor = const Color(0xFF728D5A);
  final Color headerColor = const Color(0xFFBDD9A4);
  final _firestore = FirebaseFirestore.instance;

  Set<String> selectedDocIds = {};

  Future<void> _deleteSelected() async {
    if (selectedDocIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Selected Patients"),
        content: const Text(
            "Are you sure you want to delete the selected patients?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      for (final id in selectedDocIds) {
        await _firestore.collection('patients').doc(id).delete();
      }
      setState(() => selectedDocIds.clear());
    }
  }

  void _viewPatientDetails(Map<String, dynamic> patient) {
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
              child: const Text("Close")),
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

  void _openPatientForm({Map<String, dynamic>? existingPatient, String? docId}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            PatientsScreen(existingPatient: existingPatient, docId: docId),
      ),
    );
  }

  void _toggleSelectAll(List<DocumentSnapshot> docs) {
    setState(() {
      if (selectedDocIds.length == docs.length) {
        selectedDocIds.clear();
      } else {
        selectedDocIds = docs.map((e) => e.id).toSet();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // 🟩 Sidebar
          Container(
            width: 220,
            color: sidebarColor,
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Column(
              children: [
                Image.asset('assets/furever2.png', width: 140),
                const SizedBox(height: 40),
                _sidebarItem("Profile", icon: Icons.person, onTap: () {
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (context) => const ProfileScreen()));
                }),
                _sidebarItem("Dashboard", icon: Icons.dashboard, onTap: () {
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (context) => const DashboardScreen()));
                }),
                _sidebarItem("Appointments", icon: Icons.calendar_today, onTap: () {
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (context) => AppointmentsPage()));
                }),
                _sidebarItem("Analytics", icon: Icons.analytics, onTap: () {
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (context) => const AnalyticsScreen()));
                }),
                _sidebarItem("Patients", icon: Icons.pets, selected: true),
                _sidebarItem("Feedback", icon: Icons.feedback, onTap: () {
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (context) => const VetFeedbackScreen()));
                }),
              ],
            ),
          ),

          // 🟦 Main Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🟨 Header
                Container(
                  color: headerColor,
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Patients",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 24)),
                      StreamBuilder<QuerySnapshot>(
                        stream: _firestore.collection('patients').snapshots(),
                        builder: (context, snapshot) {
                          final docs = snapshot.data?.docs ?? [];
                          return Row(
                            children: [
                              if (selectedDocIds.isNotEmpty)
                                ElevatedButton.icon(
                                  onPressed: _deleteSelected,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12, horizontal: 16),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.delete),
                                  label: Text(
                                      "Delete (${selectedDocIds.length})"),
                                ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: () => _toggleSelectAll(docs),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.select_all),
                                label: Text(selectedDocIds.length == docs.length
                                    ? "Deselect All"
                                    : "Select All"),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: () => _openPatientForm(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.add),
                                label: const Text("Add Patient"),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // 🟩 Realtime Table
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('patients')
                        .orderBy('registeredDate', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snapshot.data?.docs ?? [];

                      if (docs.isEmpty) {
                        return const Center(
                          child: Text(
                            "No patients found.\nClick 'Add Patient' to add one.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 16, color: Colors.black54),
                          ),
                        );
                      }

                      return SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columnSpacing: 30,
                            headingRowColor: MaterialStateColor.resolveWith(
                                (states) => Colors.grey.shade200),
                            columns: const [
                              DataColumn(label: Text("Select")),
                              DataColumn(label: Text("Name")),
                              DataColumn(label: Text("Species")),
                              DataColumn(label: Text("Breed")),
                              DataColumn(label: Text("Owner")),
                              DataColumn(label: Text("Actions")),
                            ],
                            rows: docs.map((doc) {
                              final data =
                                  doc.data() as Map<String, dynamic>;
                              final isSelected = selectedDocIds.contains(doc.id);

                              return DataRow(
                                cells: [
                                  DataCell(
                                    Checkbox(
                                      value: isSelected,
                                      onChanged: (bool? selected) {
                                        setState(() {
                                          if (selected == true) {
                                            selectedDocIds.add(doc.id);
                                          } else {
                                            selectedDocIds.remove(doc.id);
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                  DataCell(Text(data["Patient Name"] ?? "")),
                                  DataCell(Text(data["Species"] ?? "")),
                                  DataCell(Text(data["Breed"] ?? "")),
                                  DataCell(Text(data["Owner Info"] ?? "")),
                                  DataCell(
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.visibility,
                                              color: Colors.blue),
                                          onPressed: () =>
                                              _viewPatientDetails(data),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit,
                                              color: Colors.orange),
                                          onPressed: () => _openPatientForm(
                                              existingPatient: data,
                                              docId: doc.id),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarItem(String title,
      {required IconData icon, bool selected = false, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        decoration: BoxDecoration(
          color: selected ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
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
