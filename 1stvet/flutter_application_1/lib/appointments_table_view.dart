import 'package:flutter/material.dart';
import 'appointments_screen.dart'; // For Appointment model

class AppointmentsTableView extends StatefulWidget {
  final List<Appointment> appointments;

  const AppointmentsTableView({super.key, required this.appointments});

  @override
  State<AppointmentsTableView> createState() => _AppointmentsTableViewState();
}

class _AppointmentsTableViewState extends State<AppointmentsTableView> {
  String _selectedFilter = "All";

  @override
  Widget build(BuildContext context) {
    final filteredAppointments = widget.appointments.where((appt) {
      return _selectedFilter == "All" || appt.status == _selectedFilter;
    }).toList();

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 246, 247, 246), // Matches dashboard
      appBar: AppBar(
        title: const Text(
          "Appointments Table View",
          style: TextStyle(color: Colors.white), // White header text
        ),
        backgroundColor: const Color(0xFF728D5A),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Top Row: Dropdown Filter only (Back button removed)
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFF728D5A), width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: _selectedFilter,
                  underline: const SizedBox(),
                  iconEnabledColor: const Color(0xFF728D5A),
                  style: const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.w500),
                  items: ["All", "Pending", "Confirmed", "Declined", "Completed"]
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(s),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedFilter = val;
                      });
                    }
                  },
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Table Container
            Expanded(
              child: Card(
                elevation: 4,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor:
                          MaterialStateProperty.all(const Color(0xFF728D5A)),
                      headingTextStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      columns: const [
                        DataColumn(label: Text("Date")),
                        DataColumn(label: Text("Pet Name")),
                        DataColumn(label: Text("Purpose")),
                        DataColumn(label: Text("Time")),
                        DataColumn(label: Text("Owner")),
                        DataColumn(label: Text("Status")),
                        DataColumn(label: Text("Actions")),
                      ],
                      rows: filteredAppointments.map((appt) {
                        return DataRow(
                          cells: [
                            DataCell(Text("${appt.date.toLocal()}".split(' ')[0])),
                            DataCell(Text(appt.petName)),
                            DataCell(Text(appt.purpose)),
                            DataCell(Text(appt.time)),
                            DataCell(Text(appt.owner)),
                            DataCell(Text(
                              appt.status,
                              style: TextStyle(
                                color: _getStatusColor(appt.status),
                                fontWeight: FontWeight.bold,
                              ),
                            )),
                            DataCell(Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () {
                                    _showEditDialog(context, appt);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () {
                                    setState(() {
                                      widget.appointments.remove(appt);
                                    });
                                  },
                                ),
                              ],
                            )),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Edit Dialog
  void _showEditDialog(BuildContext context, Appointment appt) {
    final petController = TextEditingController(text: appt.petName);
    final purposeController = TextEditingController(text: appt.purpose);
    final timeController = TextEditingController(text: appt.time);
    final ownerController = TextEditingController(text: appt.owner);
    String status = appt.status;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Edit Appointment"),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: petController, decoration: const InputDecoration(labelText: "Pet Name")),
              TextField(controller: purposeController, decoration: const InputDecoration(labelText: "Purpose")),
              TextField(controller: timeController, decoration: const InputDecoration(labelText: "Time")),
              TextField(controller: ownerController, decoration: const InputDecoration(labelText: "Owner")),
              DropdownButtonFormField<String>(
                value: status,
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              setState(() {
                appt.petName = petController.text;
                appt.purpose = purposeController.text;
                appt.time = timeController.text;
                appt.owner = ownerController.text;
                appt.status = status;
              });
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF728D5A)),
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  /// Status color logic
  Color _getStatusColor(String status) {
    switch (status) {
      case "Confirmed":
        return Colors.green;
      case "Declined":
        return Colors.red;
      case "Pending":
        return Colors.orange;
      case "Completed":
        return Colors.blue;
      default:
        return Colors.black;
    }
  }
}
