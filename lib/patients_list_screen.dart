import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'vet_history_notes_screen.dart';
import 'dart:async'; // Import for StreamSubscription

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

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String searchQuery = "";
  bool sortDescending = true;

  // --- New State Variables for Data Caching and Stream Subscription ---
  Map<String, dynamic> _petMap = {};
  List<Map<String, dynamic>> _filteredAppointments = [];
  List<Map<String, dynamic>> _allAppointments = [];
  StreamSubscription? _petSubscription;
  StreamSubscription? _appointmentSubscription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _fetchAndListenForData();
  }

  // --- Helper Methods ---

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "-";
    final date = timestamp.toDate().toLocal();
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }

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

  String _formatMedicalConcerns(dynamic concerns) {
    if (concerns is List && concerns.isNotEmpty) {
      return concerns.join(', ');
    }
    if (concerns is Map && concerns.isNotEmpty) {
      return concerns.values.map((v) => v['name'] ?? v).join(', ');
    }
    return 'None';
  }

  void _onViewNotes(String appointmentId, String petName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VetHistoryNotesScreen(
          appointmentId: appointmentId,
          patientName: petName,
        ),
      ),
    );
  }

  void _onSearchChanged() {
    // Debounce is optional but recommended for performance on fast typing
    // For simplicity, we call _applyFilterAndSort directly.
    _applyFilterAndSort();
  }

  void _toggleSort() {
    setState(() {
      sortDescending = !sortDescending;
      _applyFilterAndSort(); // Re-apply filter and sort
    });
  }
  
  // --- Data Fetching and Processing ---

  void _fetchAndListenForData() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      setState(() => _isLoading = false);
      return;
    }
    final vetId = currentUser.uid;

    // 1. Fetch and listen for all petInfos once
    _petSubscription = _firestore.collection('petInfos').snapshots().listen((petSnapshot) {
      _petMap = {
        for (var doc in petSnapshot.docs)
          doc.id: doc.data() as Map<String, dynamic>,
      };
      // Once pet data is loaded, check if we can process appointments
      if (_allAppointments.isNotEmpty || _isLoading) {
        _processAppointments();
      }
    }, onError: (error) {
      // Handle error
      if (mounted) setState(() => _isLoading = false);
    });

    // 2. Fetch and listen for appointments
    _appointmentSubscription = _firestore
        .collection('user_appointments')
        .where('vetId', isEqualTo: vetId)
        // Note: The ordering here is for the initial data fetch, but we will
        // re-sort locally based on user preference.
        .orderBy('appointmentDateTime', descending: true) 
        .snapshots()
        .listen((appointmentSnapshot) {
      _allAppointments = appointmentSnapshot.docs.map((appDoc) {
        final appData = appDoc.data() as Map<String, dynamic>;
        final petId = appData['petDocId'] ?? appData['petId'] ?? '';
        final petData = _petMap[petId] ?? {}; // Use the cached pet map
        
        // Combine data for processing
        return {
          'Appointment ID': appDoc.id,
          'Appointment Date': appData['appointmentDateTime'],
          'Owner': appData['userName'] ?? 'N/A',
          'Purpose': appData['reason'] ?? appData['appointmentType'] ?? 'N/A',
          'Status': appData['status'] ?? 'Pending',
          'Vet Notes': appData['vetNotes'] ?? 'N/A',
          'Patient Name': petData['name'] ?? 'N/A',
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
      }).toList();

      _processAppointments();
    }, onError: (error) {
      // Handle error
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _processAppointments() {
    if (!mounted) return;
    
    // Set isLoading to false only after data has potentially arrived
    if (_isLoading) {
      setState(() {
        _isLoading = false;
      });
    }

    // Now call the filtering and sorting logic
    _applyFilterAndSort();
  }

  void _applyFilterAndSort() {
    if (!mounted) return;

    final query = _searchController.text.toLowerCase();
    
    // 1. Filter
    final filtered = _allAppointments.where((data) {
      final petName = (data['Patient Name'] as String).toLowerCase();
      final date = data['Appointment Date'];
      final dateStr = date is Timestamp ? _formatDate(date) : date.toString();
      return petName.contains(query) || dateStr.toLowerCase().contains(query);
    }).toList();

    // 2. Sort
    filtered.sort((a, b) {
      final dateA = (a['Appointment Date'] as Timestamp?)?.toDate().millisecondsSinceEpoch ?? 0;
      final dateB = (b['Appointment Date'] as Timestamp?)?.toDate().millisecondsSinceEpoch ?? 0;
      return sortDescending ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
    });

    // 3. Update state only with the final results
    setState(() {
      searchQuery = query; // Update state variable for accurate display
      _filteredAppointments = filtered;
    });
  }


  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _petSubscription?.cancel();
    _appointmentSubscription?.cancel();
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
    
    // ... UI elements (Header and Search/Sort) remain the same ...
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

          // Search + Sort
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
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    ),
                    // Removed onChanged: it's now handled by the listener in initState
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: _toggleSort, // Call the new toggle method
                  icon: Icon(
                    sortDescending ? Icons.arrow_downward : Icons.arrow_upward,
                    color: primaryGreen,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Colors.grey),

          // Main content
          Expanded(
            // Use _isLoading to show initial loading state
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: primaryGreen))
                : _filteredAppointments.isEmpty
                    ? Center(
                        child: Text(
                          "No matching records found.",
                          style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredAppointments.length,
                        itemBuilder: (context, index) {
                          final data = _filteredAppointments[index];
                          final date = data['Appointment Date'];
                          final formattedDate = date is Timestamp ? _formatDate(date) : date.toString();
                          final petName = data['Patient Name'] as String;
                          final status = data['Status'] as String;
                          final imageUrl = data['Image'] as String?;
                          String asset = 'assets/default_pet.png';
                          final species = (data['Species'] as String).toLowerCase();
                          if (species.contains('dog')) asset = 'assets/dog.png';
                          if (species.contains('cat')) asset = 'assets/cat.png';

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 25,
                                    backgroundImage: (imageUrl != null && imageUrl.startsWith('http'))
                                        ? NetworkImage(imageUrl)
                                        : AssetImage(asset) as ImageProvider,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          petName,
                                          style: const TextStyle(
                                              fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                        Text("Species: ${data['Species']} | Breed: ${data['Breed']}"),
                                        Text("Sex: ${data['Sex']} | Weight: ${data['Weight']}"),
                                        Text("Owner: ${data['Owner']} | Date: $formattedDate"),
                                        Text("Purpose: ${data['Purpose']} | Status: $status",
                                            style: TextStyle(
                                                color: _getStatusColor(status),
                                                fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => _onViewNotes(
                                      data['Appointment ID'] as String,
                                      petName,
                                    ),
                                    icon: const Icon(Icons.edit_note, size: 18),
                                    label: const Text("Notes"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryGreen,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}