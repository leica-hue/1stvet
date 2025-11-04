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
                  items: ["All", "pending", "confirmed", "declined", "completed", "cancelled"]
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
                        DataColumn(label: Text("Type")),
                        DataColumn(label: Text("Reason")),
                        DataColumn(label: Text("Time Slot")),
                        DataColumn(label: Text("Vet Name")),
                        DataColumn(label: Text("Specialty")),
                        DataColumn(label: Text("Cost")),
                        DataColumn(label: Text("User Name")),
                        DataColumn(label: Text("Status")),
                        DataColumn(label: Text("Actions")),
                      ],
                      rows: filteredAppointments.map((appt) {
                        return DataRow(
                          cells: [
                            DataCell(Text("${appt.appointmentDateTime.toLocal()}".split(' ')[0])),
                            DataCell(Text(appt.petName)),
                            DataCell(Text(appt.appointmentType)),
                            DataCell(Text(appt.reason)),
                            DataCell(Text(appt.timeSlot)),
                            DataCell(Text(appt.vetName)),
                            DataCell(Text(appt.vetSpecialty)),
                            DataCell(Text("\$${appt.cost}")),
                            DataCell(Text(appt.userName)),
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
    final reasonController = TextEditingController(text: appt.reason);
    final timeSlotController = TextEditingController(text: appt.timeSlot);
    final userNameController = TextEditingController(text: appt.userName);
    final vetNameController = TextEditingController(text: appt.vetName);
    final vetSpecialtyController = TextEditingController(text: appt.vetSpecialty);

    String status = appt.status;
    String appointmentType = appt.appointmentType;
    int cost = appt.cost;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Edit Appointment"),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: petController, decoration: const InputDecoration(labelText: "Pet Name")),
              TextField(controller: reasonController, decoration: const InputDecoration(labelText: "Reason")),
              TextField(controller: timeSlotController, decoration: const InputDecoration(labelText: "Time Slot")),
              TextField(controller: userNameController, decoration: const InputDecoration(labelText: "User Name")),
              TextField(controller: vetNameController, decoration: const InputDecoration(labelText: "Vet Name")),
              TextField(controller: vetSpecialtyController, decoration: const InputDecoration(labelText: "Vet Specialty")),
              TextFormField(
                initialValue: cost.toString(),
                decoration: const InputDecoration(labelText: "Cost"),
                keyboardType: TextInputType.number,
                onChanged: (val) {
                  cost = int.tryParse(val) ?? 0;
                },
              ),
              DropdownButtonFormField<String>(
                value: status,
                decoration: const InputDecoration(labelText: "Status"),
                items: ["pending", "confirmed", "declined", "completed", "cancelled"]
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) status = val;
                },
              ),
              DropdownButtonFormField<String>(
                value: appointmentType,
                decoration: const InputDecoration(labelText: "Appointment Type"),
                items: ["In-Person", "Virtual"]
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) appointmentType = val;
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
                appt.reason = reasonController.text;
                appt.timeSlot = timeSlotController.text;
                appt.userName = userNameController.text;
                appt.vetName = vetNameController.text;
                appt.vetSpecialty = vetSpecialtyController.text;
                appt.cost = cost;
                appt.appointmentType = appointmentType;
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
      case "confirmed":
        return Colors.green;
      case "declined":
        return Colors.red;
      case "pending":
        return Colors.orange;
      case "completed":
        return Colors.blue;
      case "cancelled":
        return const Color.fromARGB(255, 56, 3, 70);
      default:
        return Colors.black;
    }
  }
}
