import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'appointments_screen.dart'; // Assuming this is where AppointmentsPage is defined

class PatientHistoryScreen extends StatefulWidget {
  const PatientHistoryScreen({super.key});

  @override
  State<PatientHistoryScreen> createState() => _PatientHistoryScreenState();
}

class _PatientHistoryScreenState extends State<PatientHistoryScreen> {
  final Color headerColor = const Color(0xFFBDD9A4);
  final Color primaryGreen = const Color(0xFF728D5A); // Assuming a primary color
  final _firestore = FirebaseFirestore.instance;

  String searchQuery = "";
  bool sortDescending = true;
  final TextEditingController _searchController = TextEditingController();

  // Helper function for consistent date/time formatting
  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) {
      return "-";
    }
    final DateTime date = timestamp.toDate().toLocal();
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Green Heading Bar (Patient History)
          Container(
            color: headerColor,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 40, 20, 10),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: Colors.grey[800]),
                  onPressed: () => Navigator.pop(context),
                  splashRadius: 20,
                ),
                Text(
                  "Patient History",
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),

          // 2. Search Bar and Sort Row (White Background)
          Container(
            color: Colors.white,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(
              children: [
                // Search Bar
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Search by patient name or date",
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: primaryGreen, width: 1.5),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    ),
                    onChanged: (value) {
                      setState(() {
                        searchQuery = value.toLowerCase();
                      });
                    },
                  ),
                ),

                const SizedBox(width: 10),

                // Sort Button (Beside Search Bar)
                Tooltip(
                  message: sortDescending ? "Sort Oldest to Newest" : "Sort Newest to Oldest",
                  child: IconButton(
                    onPressed: () {
                      setState(() {
                        sortDescending = !sortDescending;
                      });
                    },
                    icon: Icon(
                      sortDescending
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                      color: primaryGreen,
                      size: 24,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey[100],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Colors.grey),

          // 3. Patient History Table Area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('appointments')
                    .orderBy('date', descending: sortDescending)
                    .snapshots(),
                builder: (context, appointmentSnapshot) {
                  if (!appointmentSnapshot.hasData) {
                    return Center(
                        child: CircularProgressIndicator(color: primaryGreen));
                  }

                  final appointmentDocs = appointmentSnapshot.data!.docs;

                  if (appointmentDocs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_open,
                              size: 60, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            "No patient history found.",
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    );
                  }

                  return StreamBuilder<QuerySnapshot>(
                    stream: _firestore.collection('petInfos').snapshots(),
                    builder: (context, petSnapshot) {
                      if (!petSnapshot.hasData) {
                        return Center(
                            child:
                                CircularProgressIndicator(color: primaryGreen));
                      }

                      final petMap = <String, Map<String, dynamic>>{};
                      for (var doc in petSnapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        petMap[doc.id] = data;
                      }

                      final combinedDocs = appointmentDocs.map((appDoc) {
                        final appData = appDoc.data() as Map<String, dynamic>;
                        final petId = appData['petId'] ?? '';
                        final petData = petMap[petId] ?? {};

                        return {
                          'appointmentDoc': appDoc,
                          'Patient Name':
                              petData['name'] ?? appData['petName'] ?? '-',
                          'Species': petData['species'] ?? '-',
                          'Breed': petData['breed'] ?? '-',
                          'Sex': petData['sex'] ?? '-', // ADDED
                          'Owner Info': appData['owner'] ?? '-',
                          'Appointment Date': appData['date'],
                          'Purpose': appData['purpose'] ?? '-', // ADDED
                          'Status': appData['status'] ?? 'Pending', // ADDED
                          'Vet Notes': appData['vetNotes'] ?? '-',
                        };
                      }).where((combined) {
                        final name =
                            (combined['Patient Name'] ?? '').toLowerCase();
                        // For search by date, we convert the timestamp to a string
                        final dateString = _formatDate(combined['Appointment Date'] as Timestamp?);
                        return name.contains(searchQuery) ||
                            dateString.toLowerCase().contains(searchQuery);
                      }).toList();

                      if (combinedDocs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off,
                                  size: 60, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                "No matching history found for \"$searchQuery\".",
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        );
                      }

                      // Table Centering
                      return Align(
                        alignment: Alignment.topCenter, // Align to top-center
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              showCheckboxColumn: false,
                              columnSpacing: 25, // Adjusted spacing
                              dataRowMinHeight: 50,
                              dataRowMaxHeight: 60,
                              headingRowHeight: 56,
                              horizontalMargin: 10,

                              // "Card" Effect for the Table
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.1),
                                    spreadRadius: 1,
                                    blurRadius: 5,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),

                              // Header Styling
                              headingRowColor: MaterialStateProperty.resolveWith(
                                  (states) => headerColor.withOpacity(0.5)),
                              columns: [
                                DataColumn(
                                    label: Text("Patient Name",
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87))),
                                DataColumn(
                                    label: Text("Species",
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87))),
                                DataColumn(
                                    label: Text("Breed",
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87))),
                                DataColumn(
                                    label: Text("Sex", // ADDED COLUMN
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87))),
                                DataColumn(
                                    label: Text("Owner",
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87))),
                                DataColumn(
                                    label: Text("Date & Time",
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87))),
                                DataColumn(
                                    label: Text("Purpose", // ADDED COLUMN
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87))),
                                DataColumn(
                                    label: Text("Status", // ADDED COLUMN
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87))),
                                DataColumn(
                                    label: Text("Vet Notes",
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87))),
                              ],
                              rows: combinedDocs.asMap().entries.map((entry) {
                                int index = entry.key;
                                var data = entry.value;
                                final formattedDate =
                                    _formatDate(data['Appointment Date'] as Timestamp?);

                                return DataRow(
                                  // Zebra Stripping for readability
                                  color: MaterialStateProperty.resolveWith<Color?>(
                                    (Set<MaterialState> states) {
                                      if (states.contains(MaterialState.hovered)) {
                                        return primaryGreen.withOpacity(0.05);
                                      }
                                      return index % 2 == 0
                                          ? Colors.white
                                          : Colors.grey[100];
                                    },
                                  ),
                                  cells: [
                                    DataCell(Text(data['Patient Name'] ?? '-',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: primaryGreen))),
                                    DataCell(Text(data['Species'] ?? '-',
                                        style: theme.textTheme.bodyMedium)),
                                    DataCell(Text(data['Breed'] ?? '-',
                                        style: theme.textTheme.bodyMedium)),
                                    DataCell(Text(data['Sex'] ?? '-', // ADDED CELL
                                        style: theme.textTheme.bodyMedium)),
                                    DataCell(Text(data['Owner Info'] ?? '-',
                                        style: theme.textTheme.bodyMedium)),
                                    DataCell(Text(formattedDate,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                            fontStyle: FontStyle.italic))),
                                    DataCell(Text(data['Purpose'] ?? '-', // ADDED CELL
                                        style: theme.textTheme.bodyMedium)),
                                    DataCell(Text(data['Status'] ?? '-', // ADDED CELL
                                        style: theme.textTheme.bodyMedium)),
                                    DataCell(
                                      Text(
                                        data['Vet Notes'] ?? '-',
                                        style: theme.textTheme.bodyMedium,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2, // Allow vet notes to wrap slightly
                                      ),
                                    ),
                                  ],
                                  onSelectChanged: (_) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => AppointmentsPage(
                                          appointmentDoc: data['appointmentDoc'],
                                        ),
                                      ),
                                    );
                                  },
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}