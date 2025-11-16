import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'vet_history_notes_screen.dart';
import 'dart:async'; // Import for StreamSubscription
import 'common_sidebar.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;

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
  final firebase_storage.FirebaseStorage _storage = firebase_storage.FirebaseStorage.instance;

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
  final Map<String, String?> _imageUrlCache = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _fetchAndListenForData();
  }

  // --- Helper Methods ---

  bool _looksLikeAssetPath(String path) {
    if (path.isEmpty) return false;
    return path.startsWith('assets/') || path.endsWith('.png') || path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.webp');
  }

  Future<String?> _resolveImageUrl(String? rawUrl) async {
    final String key = (rawUrl ?? '').trim();
    if (key.isEmpty) return null;

    // Cache hit
    if (_imageUrlCache.containsKey(key)) {
      return _imageUrlCache[key];
    }

    // Direct web URL
    if (key.startsWith('http://') || key.startsWith('https://')) {
      _imageUrlCache[key] = key;
      return key;
    }

    // Firebase Storage URL
    if (key.startsWith('gs://') || key.startsWith('firebase://')) {
      try {
        final ref = _storage.refFromURL(key);
        final downloadUrl = await ref.getDownloadURL();
        _imageUrlCache[key] = downloadUrl;
        return downloadUrl;
      } catch (e) {
        debugPrint('Failed to resolve storage URL: $key, error: $e');
        _imageUrlCache[key] = null;
        return null;
      }
    }

    // Treat other non-empty strings that look like file names as assets
    if (_looksLikeAssetPath(key)) {
      _imageUrlCache[key] = key; // keep as asset path (handled separately)
      return key;
    }

    _imageUrlCache[key] = null;
    return null;
  }

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
          doc.id: doc.data(),
      };
      // When pet data updates, refresh appointments with latest pet fields (including imageUrl)
      if (_allAppointments.isNotEmpty) {
        _allAppointments = _allAppointments.map((app) {
          final petId = app['Pet ID'] ?? '';
          final petData = _petMap[petId] ?? {};
          return {
            ...app,
            'Patient Name': petData['name'] ?? app['Patient Name'],
            'Species': petData['speciesType'] ?? app['Species'],
            'Breed': petData['breed'] ?? app['Breed'],
            'Sex': petData['gender'] ?? app['Sex'],
            'Spayed/Neutered': petData['spayedNeutered'] ?? app['Spayed/Neutered'],
            'Weight': petData['weight'] ?? app['Weight'],
            'Medical Concerns': _formatMedicalConcerns(petData['medicalConcerns']),
            'Record Created': petData['createdAt'] ?? app['Record Created'],
            'Record Updated': petData['updatedAt'] ?? app['Record Updated'],
            // Pull strictly from petInfos.imageUrl as requested
            'Image': petData['imageUrl'] ?? '',
          };
        }).toList();
      }
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
        final appData = appDoc.data();
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
          'Pet ID': petId,
          'Patient Name': petData['name'] ?? 'N/A',
          'Species': petData['speciesType'] ?? 'N/A',
          'Breed': petData['breed'] ?? 'N/A',
          'Sex': petData['gender'] ?? 'N/A',
          'Spayed/Neutered': petData['spayedNeutered'] ?? 'N/A',
          'Weight': petData['weight'] ?? 'N/A',
          'Medical Concerns': _formatMedicalConcerns(petData['medicalConcerns']),
          'Record Created': petData['createdAt'],
          'Record Updated': petData['updatedAt'],
          // Pull strictly from petInfos.imageUrl as requested
          'Image': petData['imageUrl'] ?? '',
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
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sidebar
          const CommonSidebar(currentScreen: 'Patients'),
          
          // Main content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 20, 20, 14),
                  decoration: BoxDecoration(
                    color: headerColor,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: Icon(Icons.pets, color: primaryGreen, size: 26),
                      ),
                      const SizedBox(width: 12),
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

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            elevation: 0.5,
                            child: Padding(
                              padding: const EdgeInsets.all(14.0),
                              child: Row(
                                children: [
                                  FutureBuilder<String?>(
                                    future: _resolveImageUrl(imageUrl),
                                    builder: (context, snapshot) {
                                      final resolved = snapshot.data;

                                      Widget avatarChild;
                                      if (snapshot.connectionState == ConnectionState.waiting) {
                                        avatarChild = const SizedBox(width: 50, height: 50);
                                      } else if (resolved == null || resolved.isEmpty) {
                                        avatarChild = const Icon(Icons.pets, color: Colors.white);
                                      } else if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
                                        avatarChild = ClipOval(
                                          child: Image.network(
                                            resolved,
                                            width: 50,
                                            height: 50,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              debugPrint('PET IMAGE ERROR for $petName: $error');
                                              return const SizedBox(width: 50, height: 50);
                                            },
                                          ),
                                        );
                                      } else if (_looksLikeAssetPath(resolved)) {
                                        avatarChild = ClipOval(
                                          child: Image.asset(
                                            resolved,
                                            width: 50,
                                            height: 50,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              return const SizedBox(width: 50, height: 50);
                                            },
                                          ),
                                        );
                                      } else {
                                        avatarChild = const Icon(Icons.pets, color: Colors.white);
                                      }

                                      return Container(
                                        width: 56,
                                        height: 56,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFBBD29C),
                                          borderRadius: BorderRadius.circular(28),
                                          border: Border.all(color: Colors.white, width: 2),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.06),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: ClipOval(child: Center(child: avatarChild)),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          petName,
                                          style: const TextStyle(
                                              fontSize: 16, fontWeight: FontWeight.w800),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Icon(Icons.pets, size: 14, color: Colors.grey.shade600),
                                            const SizedBox(width: 4),
                                            Text(
                                              "Species: ${data['Species']} • Breed: ${data['Breed']}",
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Icon(Icons.monitor_weight, size: 14, color: Colors.grey.shade600),
                                            const SizedBox(width: 4),
                                            Text(
                                              "Sex: ${data['Sex']} • Weight: ${data['Weight']}",
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Icon(Icons.person, size: 14, color: Colors.grey.shade600),
                                            const SizedBox(width: 4),
                                            Text(
                                              "Owner: ${data['Owner']}",
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: -6,
                                          children: [
                                            _StatusChip(label: status, color: _getStatusColor(status)),
                                            _InfoChip(label: "Date: $formattedDate"),
                                            _InfoChip(label: "Purpose: ${data['Purpose']}"),
                                          ],
                                        ),
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
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
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
            ),
          ],
        ),
      );
    }
  }

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: color,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade700,
          fontSize: 12,
        ),
      ),
    );
  }
}