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

  // Helper to format Timestamp
  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "-";
    final date = timestamp.toDate().toLocal();
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }

  // Helper to get color for status
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

  // Helper to format list of concerns
  String _formatMedicalConcerns(dynamic concerns) {
    if (concerns is List && concerns.isNotEmpty) {
      return concerns.join(', ');
    }
    // If medicalConcerns is an object like in the screenshot's array field structure
    if (concerns is Map && concerns.isNotEmpty) {
      return concerns.values.map((v) => v['name'] ?? v).join(', ');
    }
    return 'None';
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

          // Search and Sort (Kept for functionality)
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
                      hintText: "Search by pet name or date",
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

          // Data Table
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('petInfos').snapshots(),
                builder: (context, petSnapshot) {
                  if (petSnapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: primaryGreen));
                  }

                  final petDocs = petSnapshot.data?.docs ?? [];
                  
                  // Map 1: Keyed by the Pet Document ID (e.g., BB9ZQ...) - BEST for linking
                  final petMapByDocId = <String, Map<String, dynamic>>{};
                  // Map 2: Keyed by the User ID - Used for fallback/if petId is missing from appointment
                  final petMapByUserId = <String, Map<String, dynamic>>{};

                  for (var doc in petDocs) {
                    final petData = doc.data() as Map<String, dynamic>;
                    
                    // Populate map by Pet Document ID
                    petMapByDocId[doc.id] = petData;
                    
                    // Populate map by User ID (note: this will overwrite if user has multiple pets)
                    final userId = petData['userId'] ?? '';
                    if (userId.isNotEmpty) {
                      petMapByUserId[userId] = petData;
                    }
                  }

                  return StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('user_appointments')
                        // ✅ Changed sort field to a more common appointment field, assuming it exists
                        .orderBy('appointmentDateTime', descending: sortDescending) 
                        .snapshots(),
                    builder: (context, appointmentSnapshot) {
                      if (appointmentSnapshot.connectionState == ConnectionState.waiting) {
                        return Center(child: CircularProgressIndicator(color: primaryGreen));
                      }

                      final appointmentDocs = appointmentSnapshot.data?.docs ?? [];
                      if (appointmentDocs.isEmpty) {
                        return Center(
                          child: Text(
                            "No appointments found.",
                            style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                          ),
                        );
                      }

                      final combinedDocs = appointmentDocs.map((appDoc) {
                        final appData = appDoc.data() as Map<String, dynamic>;

                        // 🎯 CRITICAL FIX: Determine which ID to use to fetch Pet Data
                        // 1. Check if the appointment document stores the Pet's Document ID directly (best practice)
                        final petDocIdInAppointment = appData['petDocId'] ?? appData['petId'] ?? ''; 
                        
                        // 2. Fallback to User ID if a pet ID isn't found
                        final userId = appData['userId'] ?? '';
                        
                        // 3. Prioritize pet data lookup by doc ID, then by user ID
                        final petData = petMapByDocId[petDocIdInAppointment] ?? petMapByUserId[userId] ?? {};

                        return {
                          // Appointment Fields
                          'Appointment ID': appDoc.id, // For true deduplication if needed
                          'Appointment Date': appData['appointmentDateTime'],
                          'Owner Info': appData['userName'] ?? 'N/A',
                          'Purpose': appData['reason'] ?? appData['appointmentType'] ?? 'N/A',
                          'Status': appData['status'] ?? 'Pending',
                          'Vet Notes': appData['vetNotes'] ?? 'N/A',
                          
                          // PetInfo Fields (Now guaranteed to be the correct pet IF the link exists)
                          'Patient Name': petData['name'] ?? 'N/A', // Using name from petData as primary
                          'Species': petData['speciesType'] ?? 'N/A',
                          'Breed': petData['breed'] ?? 'N/A',
                          'Sex': petData['gender'] ?? 'N/A',
                          'Spayed/Neutered': petData['spayedNeutered'] ?? 'N/A',
                          'Weight': petData['weight'] ?? 'N/A',
                          'Medical Concerns': _formatMedicalConcerns(petData['medicalConcerns']),
                          'Record Created': petData['createdAt'],
                          'Record Updated': petData['updatedAt'],
                          'Image': petData['imageAsset'] ?? petData['imageUrl'] ?? '',
                        };
                      }).where((data) {
                        final name = (data['Patient Name'] as String).toLowerCase();
                        final date = data['Appointment Date'];
                        final dateString =
                            date is Timestamp ? _formatDate(date) : date.toString();
                        return name.contains(searchQuery) ||
                            dateString.toLowerCase().contains(searchQuery);
                      }).toList();

                      if (combinedDocs.isEmpty) {
                        return Center(
                          child: Text(
                            "No matching records found.",
                            style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                          ),
                        );
                      }

                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 20,
                          headingRowColor:
                              MaterialStateProperty.resolveWith((states) => headerColor.withOpacity(0.5)),
                          // 🎯 Added all PetInfo columns here
                          columns: const [
                            DataColumn(label: Text("Patient")),
                            DataColumn(label: Text("Species")),
                            DataColumn(label: Text("Breed")),
                            DataColumn(label: Text("Sex")),
                            DataColumn(label: Text("Spayed/Neutered")), // NEW
                            DataColumn(label: Text("Weight (kg)")),      // NEW
                            DataColumn(label: Text("Medical Concerns")), // NEW
                            DataColumn(label: Text("Owner")),
                            DataColumn(label: Text("Date & Time")),
                            DataColumn(label: Text("Purpose")),
                            DataColumn(label: Text("Status")),
                            DataColumn(label: Text("Vet Notes")),
                            DataColumn(label: Text("Pet Record Created")), // NEW
                            DataColumn(label: Text("Pet Record Updated")), // NEW
                          ],
                          rows: combinedDocs.map((data) {
                            final formattedAppointmentDate = data['Appointment Date'] is Timestamp
                                ? _formatDate(data['Appointment Date'] as Timestamp)
                                : data['Appointment Date'].toString();
                            
                            // Formatting new pet date fields
                            final formattedCreatedDate = data['Record Created'] is Timestamp
                                ? _formatDate(data['Record Created'] as Timestamp)
                                : 'N/A';
                            final formattedUpdatedDate = data['Record Updated'] is Timestamp
                                ? _formatDate(data['Record Updated'] as Timestamp)
                                : 'N/A';
                            
                            final status = data['Status'] as String;
                            final imageUrl = data['Image'] as String?;

                            return DataRow(cells: [
                              DataCell(Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundImage: imageUrl != null && imageUrl.isNotEmpty && !imageUrl.startsWith('assets/') 
                                        ? NetworkImage(imageUrl)
                                        : const AssetImage('assets/default_pet.png') as ImageProvider,
                                    backgroundColor: Colors.grey[200],
                                  ),
                                  const SizedBox(width: 8),
                                  Text(data['Patient Name'] as String),
                                ],
                              )),
                              DataCell(Text(data['Species'] as String)),
                              DataCell(Text(data['Breed'] as String)),
                              DataCell(Text(data['Sex'] as String)),
                              DataCell(Text(data['Spayed/Neutered'] as String)), // NEW Cell
                              DataCell(Text(data['Weight'].toString())),       // NEW Cell
                              DataCell(Text(data['Medical Concerns'] as String)), // NEW Cell
                              DataCell(Text(data['Owner Info'] as String)),
                              DataCell(Text(formattedAppointmentDate)),
                              DataCell(Text(data['Purpose'] as String)),
                              DataCell(Container(
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
                              )),
                              DataCell(Text(data['Vet Notes'] as String)),
                              DataCell(Text(formattedCreatedDate)), // NEW Cell
                              DataCell(Text(formattedUpdatedDate)), // NEW Cell
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