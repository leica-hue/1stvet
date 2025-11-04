import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PatientHistoryScreen extends StatefulWidget {
  const PatientHistoryScreen({super.key});

  @override
  State<PatientHistoryScreen> createState() => _PatientHistoryScreenState();
}

class _PatientHistoryScreenState extends State<PatientHistoryScreen> {
  final Color headerColor = const Color(0xFFBDD9A4);
  final Color primaryGreen = const Color(0xFF728D5A);
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String searchQuery = "";
  bool sortDescending = true;
  final TextEditingController _searchController = TextEditingController();

  // Helper function to format Firebase Timestamp
  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "-";
    final DateTime date = timestamp.toDate().toLocal(); 
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }

  // Helper function for status colors
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green.shade700;
      case 'pending':
        return Colors.amber.shade700;
      case 'cancelled':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade600;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      return Scaffold(
        body: Center(
          child: Text(
            "Please log in to view patient history.",
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[700]),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
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
                  "Patient History and Information",
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),

          // Search & Sort
          Container(
            color: Colors.white,
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
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
                        borderSide: BorderSide(color: primaryGreen, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        searchQuery = value.toLowerCase();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: () {
                    setState(() {
                      sortDescending = !sortDescending;
                    });
                  },
                  icon: Icon(
                    sortDescending ? Icons.arrow_downward : Icons.arrow_upward,
                    color: primaryGreen,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Colors.grey),

          // Table Section
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              // *** FIRST StreamBuilder: Fetch Pets by Vet ID ***
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    // 🚨 CORRECTION: Changed from 'petInfos' to 'patients'
                    .collection('patients') 
                    .where('vetId', isEqualTo: currentUser.uid)
                    .snapshots(),
                builder: (context, petSnapshot) {
                  if (petSnapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: primaryGreen));
                  }

                  if (!petSnapshot.hasData || petSnapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Text(
                        "No registered patients found for this vet.",
                        style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                      ),
                    );
                  }

                  // Extract pet data and IDs
                  final petDocs = petSnapshot.data!.docs;
                  final petMap = <String, Map<String, dynamic>>{};
                  final petIds = <String>[];
                  
                  for (var doc in petDocs) {
                    petMap[doc.id] = doc.data() as Map<String, dynamic>;
                    petIds.add(doc.id); // Collect pet IDs
                  }

                  // *** SECOND StreamBuilder: Fetch Appointments by Pet ID ***
                  return StreamBuilder<QuerySnapshot>(
                    stream: petIds.isNotEmpty
                        ? _firestore
                            .collection('appointments')
                            .where('vetId', isEqualTo: currentUser.uid)
                            .orderBy('date', descending: sortDescending)
                            .snapshots()
                        : const Stream.empty(),
                    builder: (context, appointmentSnapshot) {
                      if (appointmentSnapshot.connectionState == ConnectionState.waiting) {
                        return Center(child: CircularProgressIndicator(color: primaryGreen));
                      }
                      
                      final appointmentDocs = appointmentSnapshot.data?.docs ?? [];

                      // Combine pet and appointment data and apply search filter
                      final combinedDocs = appointmentDocs.map((appDoc) {
                        final appData = appDoc.data() as Map<String, dynamic>;
                        final vetId = appData['vetId'] as String? ?? '';
                        final petData = petMap[vetId] ?? {}; // Get pet data from the outer stream

                        return {
                          // Pet Information: Using the explicit field names from your Firebase documents
                          'Patient Name': petData['Patient Name'] ?? petData['name'] ?? '-', 
                          'Species': petData['Species'] ?? petData['species'] ?? '-',
                          'Breed': petData['Breed'] ?? petData['breed'] ?? '-',
                          'Sex': petData['Gender'] ?? petData['sex'] ?? '-', 
                          'Owner Info': petData['Owner Info'] ?? appData['owner'] ?? '-',
                          
                          // Appointment Information (from appointments)
                          'Appointment Date': appData['date'],
                          'Purpose': appData['purpose'] ?? '-',
                          'Status': appData['status'] ?? 'Pending',
                          'Vet Notes': appData['vetNotes'] ?? '-',
                        };
                      }).where((combined) {
                        final name = (combined['Patient Name'] as String).toLowerCase();
                        final dateString = _formatDate(combined['Appointment Date'] as Timestamp?);
                        return name.contains(searchQuery) ||
                            dateString.toLowerCase().contains(searchQuery);
                      }).toList();

                      if (combinedDocs.isEmpty) {
                        return Center(
                          child: Text(
                            "No matching history records found.",
                            style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                          ),
                        );
                      }

                      // Display DataTable
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 20,
                          headingRowColor: MaterialStateProperty.resolveWith(
                            (states) => headerColor.withOpacity(0.5),
                          ),
                          columns: const [
                            DataColumn(label: Text("Patient Name")),
                            DataColumn(label: Text("Species")),
                            DataColumn(label: Text("Breed")),
                            DataColumn(label: Text("Sex")),
                            DataColumn(label: Text("Owner")),
                            DataColumn(label: Text("Date & Time")),
                            DataColumn(label: Text("Purpose")),
                            DataColumn(label: Text("Status")),
                            DataColumn(label: Text("Vet Notes")),
                          ],
                          rows: combinedDocs.map((data) {
                            final formattedDate = _formatDate(data['Appointment Date'] as Timestamp?);
                            final status = data['Status'] as String;

                            return DataRow(cells: [
                              DataCell(Text(data['Patient Name'] as String)),
                              DataCell(Text(data['Species'] as String)),
                              DataCell(Text(data['Breed'] as String)),
                              DataCell(Text(data['Sex'] as String)),
                              DataCell(Text(data['Owner Info'] as String)),
                              DataCell(Text(formattedDate)),
                              DataCell(Text(data['Purpose'] as String)),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(status).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      color: _getStatusColor(status),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(Text(data['Vet Notes'] as String)),
                            ]);
                          }).toList(),
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