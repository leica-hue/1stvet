import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'vet_history_notes_screen.dart';
import 'dart:async'; // Import for StreamSubscription
import 'common_sidebar.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'payment_option_screen.dart';

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
  List<Map<String, dynamic>> _filteredPets = []; // Changed to show unique pets
  List<Map<String, dynamic>> _allAppointments = [];
  Map<String, List<Map<String, dynamic>>> _appointmentsByPet = {}; // Group appointments by pet ID
  StreamSubscription? _petSubscription;
  StreamSubscription? _appointmentSubscription;
  bool _isLoading = true;
  final Map<String, String?> _imageUrlCache = {};
  
  // Premium status
  bool _isPremium = false;
  static const int _basicPatientLimit = 50;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _checkPremiumStatus();
    _fetchAndListenForData();
  }
  
  Future<void> _checkPremiumStatus() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      setState(() {
        _isPremium = false;
      });
      return;
    }

    try {
      final vetDoc = await _firestore.collection('vets').doc(currentUser.uid).get();
      if (vetDoc.exists) {
        final data = vetDoc.data();
        final premiumUntil = data?['premiumUntil'] as Timestamp?;
        final isPremium = data?['isPremium'] as bool? ?? false;
        
        bool hasActivePremium = false;
        if (premiumUntil != null) {
          final premiumDate = premiumUntil.toDate();
          hasActivePremium = premiumDate.isAfter(DateTime.now());
        }
        
      setState(() {
        _isPremium = hasActivePremium || isPremium;
      });
    } else {
      setState(() {
        _isPremium = false;
      });
    }
  } catch (e) {
    debugPrint("Error checking premium status: $e");
    setState(() {
      _isPremium = false;
    });
  }
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
          'User ID': appData['userId'] ?? '',
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
    
    // 1. Group appointments by pet ID
    _appointmentsByPet.clear();
    for (var appointment in _allAppointments) {
      final petId = appointment['Pet ID'] as String? ?? '';
      if (petId.isNotEmpty) {
        if (!_appointmentsByPet.containsKey(petId)) {
          _appointmentsByPet[petId] = [];
        }
        _appointmentsByPet[petId]!.add(appointment);
      }
    }
    
    // 2. Sort appointments within each pet by date
    _appointmentsByPet.forEach((petId, appointments) {
      appointments.sort((a, b) {
        final dateA = (a['Appointment Date'] as Timestamp?)?.toDate().millisecondsSinceEpoch ?? 0;
        final dateB = (b['Appointment Date'] as Timestamp?)?.toDate().millisecondsSinceEpoch ?? 0;
        return sortDescending ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
      });
    });
    
    // 3. Create unique pet entries with their most recent appointment
    final uniquePets = <String, Map<String, dynamic>>{};
    for (var petId in _appointmentsByPet.keys) {
      final appointments = _appointmentsByPet[petId]!;
      if (appointments.isNotEmpty) {
        // Use the most recent appointment as the base data
        final mostRecentAppt = appointments.first;
        uniquePets[petId] = {
          ...mostRecentAppt,
          'Appointment Count': appointments.length,
          'All Appointments': appointments,
        };
      }
    }
    
    // 4. Filter by search query
    final filteredPets = uniquePets.values.where((petData) {
      final petName = (petData['Patient Name'] as String).toLowerCase();
      final date = petData['Appointment Date'];
      final dateStr = date is Timestamp ? _formatDate(date) : date.toString();
      return petName.contains(query) || dateStr.toLowerCase().contains(query);
    }).toList();
    
    // 5. Sort pets by most recent appointment date
    filteredPets.sort((a, b) {
      final dateA = (a['Appointment Date'] as Timestamp?)?.toDate().millisecondsSinceEpoch ?? 0;
      final dateB = (b['Appointment Date'] as Timestamp?)?.toDate().millisecondsSinceEpoch ?? 0;
      return sortDescending ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
    });

    // 6. Apply premium limit for basic users (limit to last 50 patients)
    List<Map<String, dynamic>> limitedPets = filteredPets;
    if (!_isPremium && filteredPets.length > _basicPatientLimit) {
      limitedPets = filteredPets.take(_basicPatientLimit).toList();
    }

    // 7. Update state
    setState(() {
      searchQuery = query;
      _filteredPets = limitedPets;
    });
  }
  
  Widget _buildPremiumLimitBanner() {
    // Count unique patients from all appointments
    final uniquePatientCount = _appointmentsByPet.keys.length;
    final isLimited = uniquePatientCount > _basicPatientLimit;
    
    if (!isLimited) return const SizedBox.shrink();
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.amber.shade200, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Showing last $_basicPatientLimit of $uniquePatientCount patients. Upgrade to Premium to view all patients.",
              style: TextStyle(
                fontSize: 13,
                color: Colors.amber.shade900,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PaymentOptionScreen()),
              );
            },
            icon: const Icon(Icons.workspace_premium, size: 16),
            label: const Text("Upgrade"),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  void _openPetDetail(Map<String, dynamic> petData) {
    final petId = petData['Pet ID'] as String? ?? '';
    final appointments = _appointmentsByPet[petId] ?? [];
    final petName = petData['Patient Name'] as String;
    final vetId = _auth.currentUser?.uid ?? '';
    // Get userId from petData or from first appointment as fallback
    var userId = petData['User ID'] as String? ?? '';
    if (userId.isEmpty && appointments.isNotEmpty) {
      userId = appointments.first['User ID'] as String? ?? '';
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PetDetailScreen(
          petData: petData,
          appointments: appointments,
          petName: petName,
          vetId: vetId,
          userId: userId,
          onViewNotes: _onViewNotes,
          formatDate: _formatDate,
          getStatusColor: _getStatusColor,
          resolveImageUrl: _resolveImageUrl,
          looksLikeAssetPath: _looksLikeAssetPath,
          primaryGreen: primaryGreen,
        ),
      ),
    );
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

          // Premium limit banner for basic users
          if (!_isPremium && !_isLoading && _appointmentsByPet.keys.length > _basicPatientLimit)
            _buildPremiumLimitBanner(),

          // Main content
          Expanded(
            // Use _isLoading to show initial loading state
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: primaryGreen))
                : _filteredPets.isEmpty
                    ? Center(
                        child: Text(
                          "No matching records found.",
                          style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredPets.length,
                        itemBuilder: (context, index) {
                          final petData = _filteredPets[index];
                          final date = petData['Appointment Date'];
                          final formattedDate = date is Timestamp ? _formatDate(date) : date.toString();
                          final petName = petData['Patient Name'] as String;
                          final status = petData['Status'] as String;
                          final imageUrl = petData['Image'] as String?;
                          final appointmentCount = petData['Appointment Count'] as int? ?? 1;

                          return InkWell(
                            onTap: () => _openPetDetail(petData),
                            borderRadius: BorderRadius.circular(14),
                            child: Card(
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
                                              "Species: ${petData['Species']} • Breed: ${petData['Breed']}",
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
                                              "Sex: ${petData['Sex']} • Weight: ${petData['Weight']}",
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
                                              "Owner: ${petData['Owner']}",
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
                                            _InfoChip(label: "Purpose: ${petData['Purpose']}"),
                                            if (appointmentCount > 1)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: primaryGreen.withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(999),
                                                  border: Border.all(color: primaryGreen.withOpacity(0.3)),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.history, size: 12, color: primaryGreen),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      "$appointmentCount appointments",
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w700,
                                                        color: primaryGreen,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        color: primaryGreen,
                                        size: 20,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "View History",
                                        style: TextStyle(
                                          color: primaryGreen,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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

// Pet Detail Screen to show all appointments for a pet
class PetDetailScreen extends StatefulWidget {
  final Map<String, dynamic> petData;
  final List<Map<String, dynamic>> appointments;
  final String petName;
  final String vetId;
  final String userId;
  final Function(String, String) onViewNotes;
  final String Function(Timestamp?) formatDate;
  final Color Function(String) getStatusColor;
  final Future<String?> Function(String?) resolveImageUrl;
  final bool Function(String) looksLikeAssetPath;
  final Color primaryGreen;

  const PetDetailScreen({
    super.key,
    required this.petData,
    required this.appointments,
    required this.petName,
    required this.vetId,
    required this.userId,
    required this.onViewNotes,
    required this.formatDate,
    required this.getStatusColor,
    required this.resolveImageUrl,
    required this.looksLikeAssetPath,
    required this.primaryGreen,
  });

  @override
  State<PetDetailScreen> createState() => _PetDetailScreenState();
}

class _PetDetailScreenState extends State<PetDetailScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  List<Map<String, dynamic>> _careAdviceList = [];
  List<Map<String, dynamic>> _medicalHistoryList = [];

  @override
  void initState() {
    super.initState();
    _loadCareAdvice();
    _loadMedicalHistory();
  }
  
  Future<void> _loadMedicalHistory() async {
    final petId = widget.petData['Pet ID'] as String? ?? '';
    if (petId.isEmpty) {
      debugPrint('Medical History: petId is empty');
      return;
    }

    debugPrint('Medical History: Loading for petId: $petId');

    try {
      // Load from petMedicalHistory collection
      final snapshot = await _firestore
          .collection('petMedicalHistory')
          .where('petId', isEqualTo: petId)
          .get();
      
      // Get pet species to filter immunizations
      String? petSpecies;
      try {
        final petDoc = await _firestore.collection('petInfos').doc(petId).get();
        if (petDoc.exists) {
          petSpecies = petDoc.data()?['speciesType']?.toString();
        }
      } catch (e) {
        debugPrint('Error loading pet species: $e');
      }
      
      // Also load from petImmunizations collection
      // Note: Firestore doesn't support multiple where clauses easily, so we filter in memory
      final immunizationSnapshot = await _firestore
          .collection('petImmunizations')
          .where('petId', isEqualTo: petId)
          .get();
      
      // Filter by species in memory if species is known
      final filteredImmunizations = petSpecies != null && petSpecies.isNotEmpty
          ? immunizationSnapshot.docs.where((doc) {
              final data = doc.data();
              final entrySpecies = data['species']?.toString().toLowerCase() ?? '';
              return entrySpecies.isEmpty || entrySpecies == petSpecies!.toLowerCase();
            }).toList()
          : immunizationSnapshot.docs;
      
      debugPrint('Medical History: Found ${snapshot.docs.length} documents from petMedicalHistory');
      debugPrint('Medical History: Found ${immunizationSnapshot.docs.length} documents from petImmunizations');
      
      if (mounted) {
        setState(() {
          // Load from petMedicalHistory
          _medicalHistoryList = snapshot.docs.map<Map<String, dynamic>>((doc) {
            final data = doc.data();
            debugPrint('Medical History: Processing doc ${doc.id} with data: $data');
            return {
              'id': doc.id,
              'date': data['date'],
              'title': data['name']?.toString() ?? '', // Map 'name' to 'title' for internal use
              'type': data['type']?.toString() ?? '',
              'description': data['notes']?.toString() ?? '', // Map 'notes' to 'description' for internal use
              'vetId': data['vetId']?.toString() ?? '',
              'vetName': data['vetName']?.toString() ?? data['userId']?.toString() ?? 'Unknown',
              'petName': data['petName']?.toString() ?? widget.petName,
              'userId': data['userId']?.toString() ?? '',
              'createdAt': data['createdAt'],
              'updatedAt': data['updatedAt'],
            };
          }).toList();
          
          // Load from petImmunizations and convert to same format
          final immunizationEntries = filteredImmunizations.map<Map<String, dynamic>>((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              'date': data['date'],
              'title': data['vaccineName']?.toString() ?? '', // Use vaccineName as title
              'type': 'Vaccination',
              'description': '',
              'vetId': data['vetId']?.toString() ?? '',
              'vetName': data['vetName']?.toString() ?? 'Unknown',
              'petName': data['petName']?.toString() ?? widget.petName,
              'userId': '',
              'createdAt': data['createdAt'],
              'updatedAt': data['updatedAt'],
            };
          }).toList();
          
          // Combine both lists
          _medicalHistoryList.addAll(immunizationEntries);
          
          // Sort by date descending after loading
          _medicalHistoryList.sort((a, b) {
            final dateA = a['date'] as Timestamp?;
            final dateB = b['date'] as Timestamp?;
            if (dateA == null && dateB == null) return 0;
            if (dateA == null) return 1;
            if (dateB == null) return -1;
            return dateB.compareTo(dateA);
          });
          
          debugPrint('Medical History: Loaded ${_medicalHistoryList.length} total entries');
        });
      }
    } catch (e) {
      debugPrint('Error loading medical history: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading medical history: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
  
  Future<void> _showMedicalHistoryDialog() async {
    final petId = widget.petData['Pet ID'] as String? ?? '';
    final currentVet = _auth.currentUser;
    if (currentVet == null) return;
    
    // Get vet name
    String vetName = 'Unknown Vet';
    try {
      final vetDoc = await _firestore.collection('vets').doc(currentVet.uid).get();
      if (vetDoc.exists) {
        final name = vetDoc.data()?['name']?.toString() ?? 'Unknown Vet';
        // Add "Dr." prefix if not already present
        if (name.isNotEmpty && name != 'Unknown Vet' && !name.trim().startsWith('Dr.')) {
          vetName = 'Dr. ${name.trim()}';
        } else {
          vetName = name;
        }
      }
    } catch (e) {
      debugPrint('Error fetching vet name: $e');
    }
    
    if (!mounted) return;
    
    // Reload medical history before showing dialog to ensure latest data
    await _loadMedicalHistory();
    
    if (!mounted) return;
    
    debugPrint('Medical History Dialog: Showing with ${_medicalHistoryList.length} entries');
    
    showDialog(
      context: context,
      builder: (context) => _MedicalHistoryDialog(
        petId: petId,
        petName: widget.petName,
        medicalHistory: _medicalHistoryList,
        vetId: currentVet.uid,
        vetName: vetName,
        primaryGreen: widget.primaryGreen,
        formatDate: widget.formatDate,
        onSave: () async {
          await _loadMedicalHistory();
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('✅ Medical history saved successfully!'),
                backgroundColor: widget.primaryGreen,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _loadCareAdvice() async {
    if (widget.vetId.isEmpty) return;

    try {
      final snapshot = await _firestore
          .collection('careAdvice')
          .where('vetId', isEqualTo: widget.vetId)
          .get();
      
      if (mounted) {
        setState(() {
          _careAdviceList = snapshot.docs.map<Map<String, dynamic>>((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              'title': data['title']?.toString() ?? '',
              'breed': data['breed']?.toString() ?? '',
              'advice': data['advice']?.toString() ?? '',
            };
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading care advice: $e');
    }
  }

  Future<void> _sendNotification(String userId, String petName, String action) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'title': 'Care Advice Updated',
        'message': 'Your vet has $action care advice for ${petName}. Check your notifications!',
        'type': 'care_advice',
        'petName': petName,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint('Notification sent to user: $userId');
    } catch (e) {
      debugPrint('Error sending notification: $e');
    }
  }

  Future<void> _showCareAdviceDialog(Map<String, dynamic> appt) async {
    // Get the pet ID from the pet data
    final petId = widget.petData['Pet ID'] as String? ?? '';
    
    // Fetch breed and species directly from Firebase petInfos collection
    String petBreed = '';
    String petSpecies = '';
    
    if (petId.isNotEmpty) {
      try {
        final petDoc = await _firestore.collection('petInfos').doc(petId).get();
        if (petDoc.exists) {
          final petData = petDoc.data() ?? {};
          petBreed = petData['breed']?.toString() ?? '';
          petSpecies = petData['speciesType']?.toString() ?? '';
        }
      } catch (e) {
        debugPrint('Error fetching pet data from Firebase: $e');
        // Fallback to widget data if Firebase fetch fails
        petBreed = widget.petData['Breed'] as String? ?? '';
        petSpecies = widget.petData['Species'] as String? ?? '';
      }
    } else {
      // Fallback if no pet ID
      petBreed = widget.petData['Breed'] as String? ?? '';
      petSpecies = widget.petData['Species'] as String? ?? '';
    }
    
    // Get userId from appointment, fallback to widget.userId
    final appointmentUserId = appt['User ID'] as String? ?? widget.userId;
    
    // Filter care advice by breed/species
    final relevantAdvice = _careAdviceList.where((advice) {
      final adviceBreed = (advice['breed'] ?? '').toLowerCase();
      final adviceText = advice['breed'] ?? '';
      final petBreedLower = petBreed.toLowerCase();
      final petSpeciesLower = petSpecies.toLowerCase();
      
      return adviceBreed.contains(petBreedLower) || 
             adviceBreed.contains(petSpeciesLower) ||
             adviceText.toLowerCase().contains(petBreedLower) ||
             adviceText.toLowerCase().contains(petSpeciesLower) ||
             adviceBreed.isEmpty; // Show general advice if breed is empty
    }).toList();

    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => _EditableCareAdviceDialog(
        petBreed: petBreed,
        petSpecies: petSpecies,
        relevantAdvice: relevantAdvice,
        allAdvice: _careAdviceList,
        primaryGreen: widget.primaryGreen,
        vetId: widget.vetId,
        userId: appointmentUserId,
        petName: widget.petName,
        onSave: (updatedAdvice) async {
          // Save to Firestore careAdvice collection
          try {
            // Get the original list to compare what was deleted
            final originalIds = _careAdviceList.map((a) => a['id'] as String?).whereType<String>().toSet();
            final updatedIds = updatedAdvice.map((a) => a['id'] as String?).whereType<String>().toSet();
            
            // Delete removed items
            final deletedIds = originalIds.difference(updatedIds);
            for (final id in deletedIds) {
              await _firestore.collection('careAdvice').doc(id).delete();
            }
            
            // Save/update each advice item
            for (final advice in updatedAdvice) {
              final id = advice['id'] as String?;
              final adviceData = {
                'vetId': widget.vetId,
                'title': advice['title']?.toString() ?? '',
                'breed': advice['breed']?.toString() ?? '',
                'advice': advice['advice']?.toString() ?? '',
                'updatedAt': FieldValue.serverTimestamp(),
              };
              
              if (id != null && id.isNotEmpty) {
                // Update existing document
                await _firestore.collection('careAdvice').doc(id).update(adviceData);
              } else {
                // Create new document
                adviceData['createdAt'] = FieldValue.serverTimestamp();
                await _firestore.collection('careAdvice').add(adviceData);
              }
            }
            
            // Reload care advice
            await _loadCareAdvice();
            
            // Send notification to user
            if (appointmentUserId.isNotEmpty) {
              await _sendNotification(appointmentUserId, widget.petName, 'updated');
            }
            
            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('✅ Care advice saved successfully!'),
                  backgroundColor: widget.primaryGreen,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          } catch (e) {
            debugPrint('Error saving care advice: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('❌ Error saving care advice: $e'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = widget.petData['Image'] as String?;
    final now = DateTime.now();
    
    // Separate past and future appointments
    final pastAppointments = widget.appointments.where((appt) {
      final date = appt['Appointment Date'] as Timestamp?;
      return date != null && date.toDate().isBefore(now);
    }).toList();
    
    final upcomingAppointments = widget.appointments.where((appt) {
      final date = appt['Appointment Date'] as Timestamp?;
      return date != null && !date.toDate().isBefore(now);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFFBDD9A4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.petName,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pet Info Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    FutureBuilder<String?>(
                      future: widget.resolveImageUrl(imageUrl),
                      builder: (context, snapshot) {
                        final resolved = snapshot.data;
                        Widget avatarChild;
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          avatarChild = const SizedBox(width: 80, height: 80);
                        } else if (resolved == null || resolved.isEmpty) {
                          avatarChild = const Icon(Icons.pets, color: Colors.white, size: 40);
                        } else if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
                          avatarChild = ClipOval(
                            child: Image.network(
                              resolved,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(Icons.pets, color: Colors.white, size: 40);
                              },
                            ),
                          );
                        } else if (widget.looksLikeAssetPath(resolved)) {
                          avatarChild = ClipOval(
                            child: Image.asset(
                              resolved,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(Icons.pets, color: Colors.white, size: 40);
                              },
                            ),
                          );
                        } else {
                          avatarChild = const Icon(Icons.pets, color: Colors.white, size: 40);
                        }

                        return Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0xFFBBD29C),
                            borderRadius: BorderRadius.circular(40),
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                          child: ClipOval(child: Center(child: avatarChild)),
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.petName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildInfoRow(Icons.pets, "Species: ${widget.petData['Species']} • Breed: ${widget.petData['Breed']}"),
                          const SizedBox(height: 4),
                          _buildInfoRow(Icons.monitor_weight, "Sex: ${widget.petData['Sex']} • Weight: ${widget.petData['Weight']}"),
                          const SizedBox(height: 4),
                          _buildInfoRow(Icons.person, "Owner: ${widget.petData['Owner']}"),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Buttons on the right side
                    Column(
                      children: [
                        SizedBox(
                          width: 200,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              // Use the first appointment or create a dummy one for the dialog
                              final firstAppt = widget.appointments.isNotEmpty 
                                  ? widget.appointments.first 
                                  : <String, dynamic>{};
                              await _showCareAdviceDialog(firstAppt);
                            },
                            icon: const Icon(Icons.lightbulb_outline, size: 20),
                            label: const Text("Care Advice"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber.shade700,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: 200,
                          child: ElevatedButton.icon(
                            onPressed: () => _showMedicalHistoryDialog(),
                            icon: const Icon(Icons.medical_services, size: 20),
                            label: const Text("View Medical History"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.primaryGreen,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Past Appointments Section
            if (pastAppointments.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.history, color: widget.primaryGreen, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    "Past Appointments (${pastAppointments.length})",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: widget.primaryGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...pastAppointments.map((appt) => _buildAppointmentCard(
                context,
                appt,
                theme,
                isPast: true,
              )),
              const SizedBox(height: 24),
            ],
            
            // Upcoming Appointments Section
            if (upcomingAppointments.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.event, color: Colors.blue.shade700, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    "Upcoming Appointments (${upcomingAppointments.length})",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...upcomingAppointments.map((appt) => _buildAppointmentCard(
                context,
                appt,
                theme,
                isPast: false,
              )),
            ],
            
            if (pastAppointments.isEmpty && upcomingAppointments.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        "No appointments found",
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }

  Widget _buildAppointmentCard(
    BuildContext context,
    Map<String, dynamic> appt,
    ThemeData theme, {
    required bool isPast,
  }) {
    final date = appt['Appointment Date'] as Timestamp?;
    final formattedDate = date != null ? widget.formatDate(date) : 'N/A';
    final status = appt['Status'] as String;
    final appointmentId = appt['Appointment ID'] as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isPast ? Colors.orange.shade200 : Colors.blue.shade200,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _StatusChip(
                            label: status,
                            color: widget.getStatusColor(status),
                          ),
                          if (isPast) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.history, size: 12, color: Colors.orange.shade700),
                                  const SizedBox(width: 4),
                                  Text(
                                    "Past",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(Icons.calendar_today, "Date: $formattedDate"),
                      const SizedBox(height: 4),
                      _buildInfoRow(Icons.description, "Purpose: ${appt['Purpose']}"),
                      if (appt['Vet Notes'] != null && appt['Vet Notes'] != 'N/A' && (appt['Vet Notes'] as String).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _buildInfoRow(Icons.note, "Notes: ${appt['Vet Notes']}"),
                        ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => widget.onViewNotes(appointmentId, widget.petName),
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text("View Notes"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.primaryGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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

class _EditableCareAdviceDialog extends StatefulWidget {
  final String petBreed;
  final String petSpecies;
  final List<Map<String, dynamic>> relevantAdvice;
  final List<Map<String, dynamic>> allAdvice;
  final Color primaryGreen;
  final String vetId;
  final String userId;
  final String petName;
  final Function(List<Map<String, dynamic>>) onSave;

  const _EditableCareAdviceDialog({
    required this.petBreed,
    required this.petSpecies,
    required this.relevantAdvice,
    required this.allAdvice,
    required this.primaryGreen,
    required this.vetId,
    required this.userId,
    required this.petName,
    required this.onSave,
  });

  @override
  State<_EditableCareAdviceDialog> createState() => _EditableCareAdviceDialogState();
}

class _EditableCareAdviceDialogState extends State<_EditableCareAdviceDialog> {
  late List<Map<String, dynamic>> _editableAdvice;
  int? _editingIndex;

  @override
  void initState() {
    super.initState();
    _editableAdvice = List.from(widget.allAdvice);
    _editingIndex = null;
  }

  void _addNewAdvice() {
    setState(() {
      _editableAdvice.add({
        'id': null, // New items have no ID
        'title': '',
        'breed': widget.petBreed,
        'advice': '',
      });
      _editingIndex = _editableAdvice.length - 1;
    });
  }

  void _editAdvice(int index) {
    setState(() {
      _editingIndex = index;
    });
  }

  void _deleteAdvice(int index) {
    setState(() {
      _editableAdvice.removeAt(index);
      if (_editingIndex == index) {
        _editingIndex = null;
      } else if (_editingIndex != null && _editingIndex! > index) {
        _editingIndex = _editingIndex! - 1;
      }
    });
  }

  void _saveAdvice(int index, String title, String breed, String advice) {
    setState(() {
      // Preserve the ID if it exists
      final existingId = _editableAdvice[index]['id'];
      _editableAdvice[index] = {
        'id': existingId,
        'title': title,
        'breed': breed,
        'advice': advice,
      };
      _editingIndex = null;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final relevantAdvice = _editableAdvice.where((advice) {
      final adviceBreed = (advice['breed'] ?? '').toLowerCase();
      final petBreedLower = widget.petBreed.toLowerCase();
      final petSpeciesLower = widget.petSpecies.toLowerCase();
      
      return adviceBreed.contains(petBreedLower) || 
             adviceBreed.contains(petSpeciesLower) ||
             adviceBreed.isEmpty;
    }).toList();

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.lightbulb_outline, color: widget.primaryGreen),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Care Advice & Recommendations',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: Icon(Icons.add_circle, color: widget.primaryGreen),
            onPressed: _addNewAdvice,
            tooltip: 'Add new advice',
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.petBreed.isNotEmpty || widget.petSpecies.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.primaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: widget.primaryGreen.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.pets, size: 20, color: widget.primaryGreen),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'For: ${widget.petSpecies} ${widget.petBreed.isNotEmpty ? '(${widget.petBreed})' : ''}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: widget.primaryGreen,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (relevantAdvice.isEmpty && _editingIndex == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    Icon(Icons.info_outline, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      'No specific care advice available',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Click the + button to add care advice',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ...relevantAdvice.asMap().entries.map((entry) {
                final index = entry.key;
                final advice = entry.value;
                final isEditing = _editingIndex == index;

                if (isEditing) {
                  return _EditAdviceCard(
                    advice: advice,
                    primaryGreen: widget.primaryGreen,
                    onSave: (title, breed, adviceText) => _saveAdvice(index, title, breed, adviceText),
                    onCancel: _cancelEdit,
                  );
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: Colors.amber.shade50,
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.amber.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.pets, size: 18, color: widget.primaryGreen),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                advice['title'] ?? 'Care Advice',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.edit, size: 18, color: widget.primaryGreen),
                              onPressed: () => _editAdvice(index),
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                              onPressed: () => _deleteAdvice(index),
                              tooltip: 'Delete',
                            ),
                          ],
                        ),
                        if ((advice['breed'] ?? '').isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: widget.primaryGreen.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Breed: ${advice['breed']}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: widget.primaryGreen,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          advice['advice'] ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade800,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onSave(_editableAdvice);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.primaryGreen,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save All'),
        ),
      ],
    );
  }
}

class _EditAdviceCard extends StatefulWidget {
  final Map<String, dynamic> advice;
  final Color primaryGreen;
  final Function(String, String, String) onSave;
  final VoidCallback onCancel;

  const _EditAdviceCard({
    required this.advice,
    required this.primaryGreen,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_EditAdviceCard> createState() => _EditAdviceCardState();
}

class _EditAdviceCardState extends State<_EditAdviceCard> {
  late TextEditingController _titleController;
  late TextEditingController _breedController;
  late TextEditingController _adviceController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.advice['title'] ?? '');
    _breedController = TextEditingController(text: widget.advice['breed'] ?? '');
    _adviceController = TextEditingController(text: widget.advice['advice'] ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _breedController.dispose();
    _adviceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.blue.shade50,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: widget.primaryGreen, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: widget.primaryGreen, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _breedController,
              decoration: InputDecoration(
                labelText: 'Breed/Species',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: widget.primaryGreen, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _adviceController,
              decoration: InputDecoration(
                labelText: 'Advice',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: widget.primaryGreen, width: 2),
                ),
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    widget.onSave(
                      _titleController.text.trim(),
                      _breedController.text.trim(),
                      _adviceController.text.trim(),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.primaryGreen,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MedicalHistoryDialog extends StatefulWidget {
  final String petId;
  final String petName;
  final List<Map<String, dynamic>> medicalHistory;
  final String vetId;
  final String vetName;
  final Color primaryGreen;
  final String Function(Timestamp?) formatDate;
  final VoidCallback onSave;

  const _MedicalHistoryDialog({
    required this.petId,
    required this.petName,
    required this.medicalHistory,
    required this.vetId,
    required this.vetName,
    required this.primaryGreen,
    required this.formatDate,
    required this.onSave,
  });

  @override
  State<_MedicalHistoryDialog> createState() => _MedicalHistoryDialogState();
}

class _MedicalHistoryDialogState extends State<_MedicalHistoryDialog> {
  final _firestore = FirebaseFirestore.instance;
  late List<Map<String, dynamic>> _editableHistory;
  int? _editingIndex;
  
  // Filter state
  String? _selectedVeterinarian; // null = all, or specific vet name
  String? _selectedVaccineType; // null = all, or specific vaccine name
  DateTime? _startDate;
  DateTime? _endDate;
  bool _showFilters = false;
  String? _petSpecies; // Cache pet species
  List<String> _availableVaccines = []; // Cache available vaccines

  // Helper function to format vet name with "Dr." prefix
  String _formatVetName(String name) {
    if (name.isEmpty || name == 'Unknown' || name == 'Unknown Vet') {
      return name;
    }
    // Check if "Dr." is already present
    if (name.trim().startsWith('Dr.') || name.trim().startsWith('Dr ')) {
      return name.trim();
    }
    return 'Dr. ${name.trim()}';
  }

  @override
  void initState() {
    super.initState();
    _editableHistory = List.from(widget.medicalHistory);
    _editingIndex = null;
    _loadPetSpeciesAndVaccines();
  }
  
  // Load pet species and vaccines for filter dropdown
  Future<void> _loadPetSpeciesAndVaccines() async {
    try {
      final petDoc = await _firestore.collection('petInfos').doc(widget.petId).get();
      if (petDoc.exists) {
        _petSpecies = petDoc.data()?['speciesType']?.toString();
      }
      _availableVaccines = await _getVaccinesForSpecies(_petSpecies);
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error loading pet species and vaccines: $e');
    }
  }
  
  // Get unique list of veterinarians from history
  List<String> _getUniqueVeterinarians() {
    final Set<String> vets = {};
    for (var entry in _editableHistory) {
      final vetName = entry['vetName']?.toString() ?? '';
      if (vetName.isNotEmpty && vetName != 'Unknown') {
        vets.add(_formatVetName(vetName));
      }
    }
    return vets.toList()..sort();
  }
  
  // Apply filters to vaccine entries
  bool _shouldShowEntry({
    required String vaccine,
    required Map<String, dynamic>? entryData,
    required String vetName,
  }) {
    // Veterinarian filter
    if (_selectedVeterinarian != null && _selectedVeterinarian!.isNotEmpty) {
      if (vetName != _selectedVeterinarian) {
        return false;
      }
    }
    
    // Vaccine type filter
    if (_selectedVaccineType != null && _selectedVaccineType!.isNotEmpty) {
      if (vaccine != _selectedVaccineType) {
        return false;
      }
    }
    
    // Date range filter
    if (entryData != null && entryData['date'] != null) {
      final date = entryData['date'] is Timestamp
          ? (entryData['date'] as Timestamp).toDate()
          : null;
      
      if (date != null) {
        if (_startDate != null && date.isBefore(_startDate!)) {
          return false;
        }
        if (_endDate != null && date.isAfter(_endDate!.add(const Duration(days: 1)))) {
          return false;
        }
      }
    } else {
      // If filtering by date range and entry has no date, exclude it
      if (_startDate != null || _endDate != null) {
        return false;
      }
    }
    
    return true;
  }
  
  void _clearFilters() {
    setState(() {
      _selectedVeterinarian = null;
      _selectedVaccineType = null;
      _startDate = null;
      _endDate = null;
    });
  }

  void _addNewEntry() {
    setState(() {
      _editableHistory.insert(0, {
        'id': null,
        'date': Timestamp.now(),
        'title': '', // Internal use, will be saved as 'name'
        'type': '',
        'description': '', // Internal use, will be saved as 'notes'
        'vetId': widget.vetId,
        'vetName': _formatVetName(widget.vetName),
        'petName': widget.petName,
      });
      _editingIndex = 0;
    });
  }

  void _editEntry(int index) {
    setState(() {
      _editingIndex = index;
    });
  }

  void _deleteEntry(int index) {
    setState(() {
      _editableHistory.removeAt(index);
      if (_editingIndex == index) {
        _editingIndex = null;
      } else if (_editingIndex != null && _editingIndex! > index) {
        _editingIndex = _editingIndex! - 1;
      }
    });
  }

  void _saveEntry(int index, DateTime date, String title, String type, String description) {
    setState(() {
      final existingId = _editableHistory[index]['id'];
      _editableHistory[index] = {
        'id': existingId,
        'date': Timestamp.fromDate(date),
        'title': title,
        'type': type,
        'description': description,
        'vetId': widget.vetId,
        'vetName': _formatVetName(widget.vetName),
      };
      _editingIndex = null;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingIndex = null;
    });
  }

  Future<void> _saveAll() async {
    try {
      // Get original IDs
      final originalIds = widget.medicalHistory.map((h) => h['id'] as String?).whereType<String>().toSet();
      final updatedIds = _editableHistory.map((h) => h['id'] as String?).whereType<String>().toSet();
      
      // Delete removed entries (only if current vet created them)
      final deletedIds = originalIds.difference(updatedIds);
      for (final id in deletedIds) {
        // Check if current vet created this entry before deleting
        final originalEntry = widget.medicalHistory.firstWhere(
          (h) => h['id'] == id,
          orElse: () => {},
        );
        final originalVetId = originalEntry['vetId']?.toString() ?? '';
        if (originalVetId == widget.vetId) {
          // Check if it's a vaccination entry
          final entryType = originalEntry['type']?.toString() ?? '';
          final entryTitle = originalEntry['title']?.toString() ?? '';
          final isVaccination = entryType.toLowerCase() == 'vaccination' ||
                               entryTitle.toLowerCase().contains('vaccine') ||
                               _isVaccineName(entryTitle);
          
          if (isVaccination) {
            await _firestore.collection('petImmunizations').doc(id).delete();
          } else {
            await _firestore.collection('petMedicalHistory').doc(id).delete();
          }
        }
      }
      
      // Save/update each entry
      for (final entry in _editableHistory) {
        final id = entry['id'] as String?;
        
        // If updating existing entry, check permissions
        if (id != null && id.isNotEmpty) {
          final originalEntry = widget.medicalHistory.firstWhere(
            (h) => h['id'] == id,
            orElse: () => {},
          );
          final originalVetId = originalEntry['vetId']?.toString() ?? '';
          
          // Only allow update if current vet created this entry
          if (originalVetId != widget.vetId) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('❌ You can only edit entries you created'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
            continue; // Skip this entry
          }
        }
        
        // Check if this is a vaccination entry (should go to petImmunizations)
        final entryType = entry['type']?.toString() ?? '';
        final entryTitle = entry['title']?.toString() ?? '';
        final isVaccination = entryType.toLowerCase() == 'vaccination' ||
                             entryTitle.toLowerCase().contains('vaccine') ||
                             _isVaccineName(entryTitle);
        
        if (isVaccination) {
          // Get pet species before saving
          String? petSpecies;
          try {
            final petDoc = await _firestore.collection('petInfos').doc(widget.petId).get();
            if (petDoc.exists) {
              petSpecies = petDoc.data()?['speciesType']?.toString();
            }
          } catch (e) {
            debugPrint('Error loading pet species for save: $e');
          }
          
          // Save to petImmunizations collection
          final immunizationData = {
            'petId': widget.petId,
            'petName': widget.petName,
            'vaccineName': entry['title']?.toString() ?? '',
            'species': petSpecies?.toLowerCase() ?? '',
            'date': entry['date'],
            'vetId': widget.vetId,
            'vetName': _formatVetName(widget.vetName),
            'updatedAt': FieldValue.serverTimestamp(),
          };
          
          if (id != null && id.isNotEmpty) {
            // Check if entry exists in petImmunizations and belongs to current vet
            final doc = await _firestore.collection('petImmunizations').doc(id).get();
            if (doc.exists) {
              final docData = doc.data();
              final docVetId = docData?['vetId']?.toString() ?? '';
              
              // Only update if this entry belongs to the current vet
              if (docVetId == widget.vetId) {
                await _firestore.collection('petImmunizations').doc(id).update(immunizationData);
              } else {
                // Entry belongs to another vet - create a new entry instead
                debugPrint('Entry belongs to another vet, creating new entry instead');
                immunizationData['createdAt'] = FieldValue.serverTimestamp();
                await _firestore.collection('petImmunizations').add(immunizationData);
              }
            } else {
              // If not in petImmunizations, create new entry
              immunizationData['createdAt'] = FieldValue.serverTimestamp();
              await _firestore.collection('petImmunizations').add(immunizationData);
            }
          } else {
            // Always create new entry when id is null (new entry)
            immunizationData['createdAt'] = FieldValue.serverTimestamp();
            await _firestore.collection('petImmunizations').add(immunizationData);
          }
        } else {
          // Save to petMedicalHistory collection for non-vaccination entries
          final entryData = {
            'petId': widget.petId,
            'petName': widget.petName,
            'date': entry['date'],
            'name': entry['title']?.toString() ?? '', // Save as 'name' in Firebase
            'type': entry['type']?.toString() ?? '',
            'notes': entry['description']?.toString() ?? '', // Save as 'notes' in Firebase
            'vetId': widget.vetId,
            'vetName': _formatVetName(widget.vetName),
            'updatedAt': FieldValue.serverTimestamp(),
          };
          
          if (id != null && id.isNotEmpty) {
            await _firestore.collection('petMedicalHistory').doc(id).update(entryData);
          } else {
            entryData['createdAt'] = FieldValue.serverTimestamp();
            await _firestore.collection('petMedicalHistory').add(entryData);
          }
        }
      }
      
      widget.onSave();
    } catch (e) {
      debugPrint('Error saving medical history: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error saving medical history: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Helper method to build table header cell
  Widget _buildTableHeaderCell(String text) {
    return TableCell(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        constraints: const BoxConstraints(
          minWidth: 70,
          minHeight: 35,
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ),
    );
  }

  // Helper method to build table data cell
  Widget _buildTableDataCell(String text, {bool isBold = false}) {
    return TableCell(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        constraints: const BoxConstraints(
          minWidth: 70,
          minHeight: 35,
        ),
        child: Center(
          child: Text(
            text.isEmpty ? '-' : text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ),
    );
  }

  // Get vaccines based on pet species
  Future<List<String>> _getVaccinesForSpecies(String? species) async {
    // Default vaccines that apply to both
    final commonVaccines = ['Rabies', 'Heartworm Prevention'];
    
    if (species == null) return commonVaccines;
    
    final speciesLower = species.toLowerCase();
    
    // Try to load from Firebase first
    try {
      final vaccinesSnapshot = await _firestore
          .collection('vaccines')
          .where('species', isEqualTo: speciesLower)
          .get();
      
      if (vaccinesSnapshot.docs.isNotEmpty) {
        // Convert to list with order
        final vaccinesList = vaccinesSnapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'name': data['name']?.toString() ?? '',
            'order': (data['order'] as num?)?.toInt() ?? 999,
          };
        }).toList();
        
        // Sort by order
        vaccinesList.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
        
        // Extract names
        final vaccines = vaccinesList
            .map((v) => v['name'] as String)
            .where((name) => name.isNotEmpty)
            .toList();
            
        if (vaccines.isNotEmpty) {
          return [...commonVaccines, ...vaccines];
        }
      }
    } catch (e) {
      debugPrint('Error loading vaccines from Firebase: $e');
    }
    
    // Fallback to hardcoded lists if Firebase doesn't have data
    if (speciesLower.contains('dog') || speciesLower.contains('canine')) {
      return [
        ...commonVaccines,
        'DHPP (Distemper, Hepatitis, Parvovirus, Parainfluenza)',
        'Bordetella',
        'Leptospirosis',
        'Lyme Disease',
        'Canine Influenza',
        'Coronavirus',
        'Adenovirus-2',
      ];
    } else if (speciesLower.contains('cat') || speciesLower.contains('feline')) {
      return [
        ...commonVaccines,
        'FVRCP (Feline Viral Rhinotracheitis, Calicivirus, Panleukopenia)',
        'Feline Leukemia (FeLV)',
        'Feline Immunodeficiency Virus (FIV)',
        'Chlamydophila',
        'Bordetella',
      ];
    }
    
    return commonVaccines;
  }

  // Build vaccine rows for the immunization table
  Future<List<TableRow>> _buildVaccineRowsAsync() async {
    // Get pet species from widget or load it
    String? petSpecies;
    try {
      final petDoc = await _firestore.collection('petInfos').doc(widget.petId).get();
      if (petDoc.exists) {
        petSpecies = petDoc.data()?['speciesType']?.toString();
      }
    } catch (e) {
      debugPrint('Error loading pet species: $e');
    }
    
    // Get vaccines for this species
    final vaccines = await _getVaccinesForSpecies(petSpecies);

    // Group history entries by vaccine type (title)
    final Map<String, List<Map<String, dynamic>>> vaccineHistory = {};
    for (var entry in _editableHistory) {
      final title = entry['title']?.toString().toLowerCase() ?? '';
      final vetId = entry['vetId']?.toString() ?? '';
      final vetNameRaw = entry['vetName']?.toString() ?? 'Unknown';
      final vetName = _formatVetName(vetNameRaw);
      final entryId = entry['id'];
      
      // Try to match vaccine name (case-insensitive partial match)
      String? matchedVaccine;
      for (var vaccine in vaccines) {
        final vaccineLower = vaccine.toLowerCase();
        if (title.contains(vaccineLower) || 
            vaccineLower.contains(title) ||
            _matchesVaccineName(title, vaccineLower)) {
          matchedVaccine = vaccine;
          break;
        }
      }
      
      // If no match, use the title as-is
      final vaccineKey = matchedVaccine ?? title;
      
      if (!vaccineHistory.containsKey(vaccineKey)) {
        vaccineHistory[vaccineKey] = [];
      }
      vaccineHistory[vaccineKey]!.add({
        'vetId': vetId,
        'vetName': vetName,
        'id': entryId,
        'entry': entry,
      });
    }

    // Build rows for each vaccine
    // If multiple entries exist for a vaccine, create a row for each entry
    final List<TableRow> allRows = [];
    
    for (final vaccineEntry in vaccines.asMap().entries) {
      final index = vaccineEntry.key;
      final vaccine = vaccineEntry.value;
      final entries = vaccineHistory[vaccine] ?? [];
      
      if (entries.isEmpty) {
        // No entries - show one row with Add button (only if filters allow)
        if (_shouldShowEntry(vaccine: vaccine, entryData: null, vetName: '')) {
          final isEvenRow = index % 2 == 0;
          allRows.add(_buildVaccineTableRow(
            vaccine: vaccine,
            index: index,
            isEvenRow: isEvenRow,
            entryData: null,
            entryVetId: '',
            vetName: '',
          ));
        }
      } else {
        // Show a row for each entry (one per vet) - apply filters
        for (final entryInfo in entries) {
          final entryData = entryInfo['entry'] as Map<String, dynamic>?;
          final entryVetId = entryInfo['vetId'] as String? ?? '';
          final vetNameRaw = entryInfo['vetName'] as String? ?? '';
          final vetName = _formatVetName(vetNameRaw);
          
          // Apply filters
          if (_shouldShowEntry(
            vaccine: vaccine,
            entryData: entryData,
            vetName: vetName,
          )) {
            allRows.add(_buildVaccineTableRow(
              vaccine: vaccine,
              index: index,
              isEvenRow: index % 2 == 0,
              entryData: entryData,
              entryVetId: entryVetId,
              vetName: vetName,
            ));
          }
        }
      }
    }
    
    return allRows;
  }

  // Helper method to build a single vaccine table row
  TableRow _buildVaccineTableRow({
    required String vaccine,
    required int index,
    required bool isEvenRow,
    required Map<String, dynamic>? entryData,
    required String entryVetId,
    required String vetName,
  }) {
    // Get formatted date
    String dateText = '';
    if (entryData != null && entryData['date'] != null) {
      if (entryData['date'] is Timestamp) {
        dateText = widget.formatDate(entryData['date'] as Timestamp);
        // Format to show only date part (remove time)
        if (dateText.contains(' ')) {
          dateText = dateText.split(' ')[0];
        }
      }
    }
    
    // Check if current vet can edit/delete (only if they created this entry)
    final canEdit = entryVetId == widget.vetId || entryData == null;

    return TableRow(
        decoration: BoxDecoration(
          color: isEvenRow 
              ? widget.primaryGreen.withOpacity(0.1)
              : widget.primaryGreen.withOpacity(0.05),
        ),
        children: [
          _buildTableDataCell(vaccine, isBold: true),
          _buildTableDataCell(dateText),
          _buildTableDataCell(vetName),
          TableCell(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: canEdit
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            // If entry exists and belongs to current vet, edit it
                            // Otherwise, always add a new entry (don't replace another vet's entry)
                            if (entryData != null && entryVetId == widget.vetId) {
                              _addOrEditVaccineEntry(vaccine, entryData);
                            } else {
                              // Always create new entry when adding (don't pass existing entry)
                              _addOrEditVaccineEntry(vaccine, null);
                            }
                          },
                          icon: Icon(
                            (entryData != null && entryVetId == widget.vetId) ? Icons.edit : Icons.add,
                            size: 12,
                          ),
                          label: Text(
                            (entryData != null && entryVetId == widget.vetId) ? 'Edit' : 'Add',
                            style: const TextStyle(fontSize: 9),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.primaryGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            minimumSize: const Size(50, 24),
                          ),
                        ),
                        if (entryData != null) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: () => _deleteVaccineEntry(vaccine, entryData),
                            icon: const Icon(Icons.delete, size: 16),
                            color: Colors.red,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            tooltip: 'Delete',
                          ),
                        ],
                      ],
                    )
                  : Text(
                      'Locked',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
            ),
          ),
        ],
      );
  }

  // Helper to match vaccine names with variations
  bool _matchesVaccineName(String entryTitle, String vaccineName) {
    // Handle common variations
    final variations = {
      'dhpp': ['distemper', 'hepatitis', 'parvovirus', 'parainfluenza'],
      'fvrcp': ['feline viral rhinotracheitis', 'calicivirus', 'panleukopenia'],
      'felv': ['feline leukemia'],
      'fiv': ['feline immunodeficiency'],
    };
    
    for (var entry in variations.entries) {
      if (vaccineName.contains(entry.key) || entry.key.contains(vaccineName)) {
        return entry.value.any((variant) => entryTitle.contains(variant));
      }
    }
    return false;
  }

  // Helper method to check if a name is a vaccine
  bool _isVaccineName(String name) {
    final vaccines = [
      'rabies', 'distemper', 'parvovirus', 'panleukopenia', 'bordetella',
      'leptospirosis', 'coronavirus', 'heartworm', 'fvrcp', 'dhpp',
      'feline leukemia', 'lyme disease', 'canine influenza', 'adenovirus',
      'hepatitis', 'parainfluenza'
    ];
    final nameLower = name.toLowerCase();
    return vaccines.any((vaccine) => nameLower.contains(vaccine) || vaccine.contains(nameLower));
  }

  // Delete vaccine entry
  Future<void> _deleteVaccineEntry(String vaccineName, Map<String, dynamic> entryData) async {
    // Check if current vet created this entry
    final entryVetId = entryData['vetId']?.toString() ?? '';
    if (entryVetId != widget.vetId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('❌ You can only delete entries you created'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Immunization'),
        content: Text('Are you sure you want to delete the $vaccineName immunization record?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final entryId = entryData['id'];
      if (entryId != null && entryId.toString().isNotEmpty) {
        // Delete from Firebase petImmunizations collection
        await _firestore.collection('petImmunizations').doc(entryId.toString()).delete();
        
        // Also remove from local editable history
        setState(() {
          _editableHistory.removeWhere((e) => e['id'] == entryId);
        });

        // Reload the data
        widget.onSave();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ $vaccineName immunization deleted successfully!'),
              backgroundColor: widget.primaryGreen,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error deleting immunization: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error deleting immunization: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Add or edit vaccine entry
  void _addOrEditVaccineEntry(String vaccineName, Map<String, dynamic>? existingEntry) async {
    if (existingEntry != null) {
      // Find the index of this entry in _editableHistory
      final entryId = existingEntry['id'];
      final index = _editableHistory.indexWhere((e) => e['id'] == entryId);
      if (index != -1) {
        setState(() {
          _editingIndex = index;
        });
      }
    } else {
      // Get pet species before saving
      String? petSpecies;
      try {
        final petDoc = await _firestore.collection('petInfos').doc(widget.petId).get();
        if (petDoc.exists) {
          petSpecies = petDoc.data()?['speciesType']?.toString();
        }
      } catch (e) {
        debugPrint('Error loading pet species: $e');
      }

      // Save directly to Firebase petImmunizations collection
      try {
        final immunizationData = {
          'petId': widget.petId,
          'petName': widget.petName,
          'vaccineName': vaccineName,
          'species': petSpecies?.toLowerCase() ?? '',
          'date': Timestamp.now(),
          'vetId': widget.vetId,
          'vetName': _formatVetName(widget.vetName),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        
        await _firestore.collection('petImmunizations').add(immunizationData);
        
        // Also add to editable history for display
        setState(() {
          _editableHistory.insert(0, {
            'id': null,
            'date': Timestamp.now(),
            'title': vaccineName,
            'type': 'Vaccination',
            'description': '',
            'vetId': widget.vetId,
            'vetName': _formatVetName(widget.vetName),
            'petName': widget.petName,
          });
        });
        
        // Reload the editable history by calling widget.onSave which will reload from parent
        widget.onSave();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ $vaccineName immunization added successfully!'),
              backgroundColor: widget.primaryGreen,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        debugPrint('Error saving immunization: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error saving immunization: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.medical_services, color: widget.primaryGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Medical History - ${widget.petName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: Icon(Icons.add_circle, color: widget.primaryGreen),
            onPressed: _addNewEntry,
            tooltip: 'Add new entry',
          ),
        ],
      ),
      content: SizedBox(
        width: 600, // Fixed width for the popup card
        height: 600, // Fixed height for the popup card
        child: SingleChildScrollView(
          child: _editableHistory.isEmpty && _editingIndex == null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Icon(Icons.medical_information, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        'No medical history available',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Click the + button to add medical history',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : Center(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    // Show edit card if editing
                    if (_editingIndex != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _EditMedicalHistoryCard(
                          history: _editableHistory[_editingIndex!],
                          primaryGreen: widget.primaryGreen,
                          onSave: (date, title, type, description) => _saveEntry(_editingIndex!, date, title, type, description),
                          onCancel: _cancelEdit,
                        ),
                      ),
                    // Filter Section - Match table width
                    // Table: columns (520px) + table borders (7.5px) + container border (4px) = 531.5px
                    // Filter: content (520px + 30px spacing) + padding (24px) = 574px, but we want to match table container
                    // So filter container width = table container width = 528px (set on table) + 4px border = 532px
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: widget.primaryGreen.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.filter_list, color: widget.primaryGreen, size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                'Filters',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: Icon(
                                  _showFilters ? Icons.expand_less : Icons.expand_more,
                                  color: widget.primaryGreen,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _showFilters = !_showFilters;
                                  });
                                },
                                tooltip: _showFilters ? 'Hide filters' : 'Show filters',
                              ),
                            ],
                          ),
                          if (_showFilters) ...[
                            const SizedBox(height: 12),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Veterinarian Filter - all filters same size
                                Expanded(
                                  child: SizedBox(
                                    height: 48,
                                    child: DropdownButtonFormField<String>(
                                      value: _selectedVeterinarian,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        labelText: 'Veterinarian',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        isDense: true,
                                      ),
                                      items: [
                                        const DropdownMenuItem(value: null, child: Text('All Vets', overflow: TextOverflow.ellipsis)),
                                        ..._getUniqueVeterinarians().map((vet) => DropdownMenuItem(
                                          value: vet,
                                          child: Text(vet, overflow: TextOverflow.ellipsis, maxLines: 1),
                                        )),
                                      ],
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedVeterinarian = value;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Vaccine Type Filter - all filters same size
                                Expanded(
                                  child: SizedBox(
                                    height: 48,
                                    child: _availableVaccines.isEmpty
                                        ? const SizedBox(
                                            height: 48,
                                            child: Center(child: CircularProgressIndicator()),
                                          )
                                        : DropdownButtonFormField<String>(
                                            value: _selectedVaccineType,
                                            isExpanded: true,
                                            decoration: InputDecoration(
                                              labelText: 'Vaccine Type',
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              isDense: true,
                                            ),
                                            items: [
                                              const DropdownMenuItem(value: null, child: Text('All Vaccines', overflow: TextOverflow.ellipsis)),
                                              ..._availableVaccines.map((vaccine) => DropdownMenuItem(
                                                value: vaccine,
                                                child: Text(vaccine, overflow: TextOverflow.ellipsis, maxLines: 1),
                                              )),
                                            ],
                                            onChanged: (value) {
                                              setState(() {
                                                _selectedVaccineType = value;
                                              });
                                            },
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Date Range Filter - fit to text
                                SizedBox(
                                  height: 48,
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final DateTimeRange? picked = await showDateRangePicker(
                                        context: context,
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime.now().add(const Duration(days: 365)),
                                        initialDateRange: _startDate != null && _endDate != null
                                            ? DateTimeRange(start: _startDate!, end: _endDate!)
                                            : null,
                                      );
                                      if (picked != null) {
                                        setState(() {
                                          _startDate = picked.start;
                                          _endDate = picked.end;
                                        });
                                      }
                                    },
                                    icon: const Icon(Icons.calendar_today, size: 12),
                                    label: Text(
                                      _startDate != null && _endDate != null
                                          ? '${DateFormat('MM/dd').format(_startDate!)} - ${DateFormat('MM/dd').format(_endDate!)}'
                                          : 'Date Range',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      fixedSize: const Size.fromHeight(48),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      minimumSize: const Size(0, 48),
                                      alignment: Alignment.centerLeft,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Clear Filters Button - fit to text
                                SizedBox(
                                  height: 48,
                                  child: OutlinedButton.icon(
                                    onPressed: _clearFilters,
                                    icon: const Icon(Icons.clear, size: 12),
                                    label: const Text('Clear', style: TextStyle(fontSize: 11)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      fixedSize: const Size.fromHeight(48),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      minimumSize: const Size(0, 48),
                                      alignment: Alignment.centerLeft,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Immunization Record Table (matching the form format)
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: widget.primaryGreen, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: FutureBuilder<List<TableRow>>(
                        future: _buildVaccineRowsAsync(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.all(20.0),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (snapshot.hasError) {
                            return Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Text('Error loading vaccines: ${snapshot.error}'),
                            );
                          }
                          
                          final vaccineRows = snapshot.data ?? [];
                          
                          return SizedBox(
                            height: 400,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Table(
                                  border: TableBorder.all(
                                    color: widget.primaryGreen,
                                    width: 1.5,
                                  ),
                                  columnWidths: const {
                                    0: FixedColumnWidth(160), // Vaccine column
                                    1: FixedColumnWidth(110), // Date column
                                    2: FixedColumnWidth(120), // Veterinarian column
                                    3: FixedColumnWidth(130),  // Actions column
                                  },
                                      children: [
                                        // Header row
                                        TableRow(
                                          decoration: BoxDecoration(
                                            color: widget.primaryGreen,
                                          ),
                                          children: [
                                            _buildTableHeaderCell('Vaccine'),
                                            _buildTableHeaderCell('Date'),
                                            _buildTableHeaderCell('Veterinarian'),
                                            _buildTableHeaderCell('Actions'),
                                          ],
                                        ),
                                        // Vaccine rows
                                        ...vaccineRows,
                                      ],
                                    ),
                                  ),
                                ),
                              );
                        },
                      ),
                    ),
                    ],
                  ),
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveAll,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.primaryGreen,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save All'),
        ),
      ],
    );
  }
}

class _EditMedicalHistoryCard extends StatefulWidget {
  final Map<String, dynamic> history;
  final Color primaryGreen;
  final Function(DateTime, String, String, String) onSave;
  final VoidCallback onCancel;

  const _EditMedicalHistoryCard({
    required this.history,
    required this.primaryGreen,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_EditMedicalHistoryCard> createState() => _EditMedicalHistoryCardState();
}

class _EditMedicalHistoryCardState extends State<_EditMedicalHistoryCard> {
  late TextEditingController _titleController;
  late TextEditingController _typeController;
  late TextEditingController _descriptionController;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.history['title'] ?? '');
    _typeController = TextEditingController(text: widget.history['type'] ?? '');
    _descriptionController = TextEditingController(text: widget.history['description'] ?? '');
    
    if (widget.history['date'] is Timestamp) {
      _selectedDate = (widget.history['date'] as Timestamp).toDate();
    } else {
      _selectedDate = DateTime.now();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _typeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.green.shade50,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: widget.primaryGreen, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: widget.primaryGreen, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _typeController,
              decoration: InputDecoration(
                labelText: 'Type (e.g., Vaccination, Surgery, Check-up)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: widget.primaryGreen, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _selectDate(context),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: widget.primaryGreen, width: 2),
                  ),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                child: Text(DateFormat('yyyy-MM-dd').format(_selectedDate)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Description/Notes',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: widget.primaryGreen, width: 2),
                ),
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    widget.onSave(
                      _selectedDate,
                      _titleController.text.trim(),
                      _typeController.text.trim(),
                      _descriptionController.text.trim(),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.primaryGreen,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}