import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async'; // IMPORTED for Timer
import 'common_sidebar.dart';

class VetFeedbackScreen extends StatefulWidget {
  const VetFeedbackScreen({super.key});

  @override
  State<VetFeedbackScreen> createState() => _VetFeedbackScreenState();
}

class _UserAvatar extends StatelessWidget {
  final String? inlineUrl;
  final String? userId;
  final Future<String?> Function(String userId) resolver;

  const _UserAvatar({
    required this.inlineUrl,
    required this.userId,
    required this.resolver,
  });

  @override
  Widget build(BuildContext context) {
    final String? immediateUrl = inlineUrl?.trim().isEmpty == true ? null : inlineUrl?.trim();

    Widget buildAvatar(String? url) {
      if (url == null || url.isEmpty) {
        return const CircleAvatar(
          backgroundColor: Color(0xFFBBD29C),
          child: Icon(Icons.person, color: Colors.white),
        );
      }
      return CircleAvatar(
        backgroundColor: const Color(0xFFBBD29C),
        child: ClipOval(
          child: Image.network(
            url,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return const SizedBox(width: 48, height: 48);
            },
          ),
        ),
      );
    }

    if (immediateUrl != null) {
      return buildAvatar(immediateUrl);
    }

    final String uid = (userId ?? '').trim();
    if (uid.isEmpty) {
      return buildAvatar(null);
    }

    return FutureBuilder<String?>(
      future: resolver(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CircleAvatar(
            backgroundColor: Color(0xFFBBD29C),
            child: SizedBox(width: 24, height: 24),
          );
        }
        return buildAvatar(snapshot.data);
      },
    );
  }
}

class _RatingPill extends StatelessWidget {
  final num rating;
  final Color color;
  const _RatingPill({required this.rating, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            rating.toStringAsFixed(1),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: color,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.star, color: Colors.amber, size: 12),
        ],
      ),
    );
  }
}

class _VetFeedbackScreenState extends State<VetFeedbackScreen> {
  final Color headerColor = const Color(0xFFBDD9A4);
  final Color accentGreen = const Color(0xFF8DBF67);

  String _sortOption = "Newest First";
  String _searchQuery = "";

  // NEW: Controller for better control over the TextField
  final TextEditingController _searchController = TextEditingController();
  // NEW: Timer for debouncing
  Timer? _debounce;

  final CollectionReference feedbackCollection =
      FirebaseFirestore.instance.collection('feedback');
  final CollectionReference usersCollection =
      FirebaseFirestore.instance.collection('users');

  // COLLECTION 2: Reference for user appointments
  final CollectionReference appointmentsCollection =
      FirebaseFirestore.instance.collection('user_appointments');

// Placeholder for the fix, requires a separate Future/Stream for vet profile
String? _loggedInVetName; // Will be null while loading

@override
void initState() {
  super.initState();
  _fetchVetName();
}

@override
void dispose() {
  // CRUCIAL: Cancel the timer and dispose the controller when the widget is removed
  _debounce?.cancel();
  _searchController.dispose();
  super.dispose();
}

void _fetchVetName() async {
  final user = FirebaseAuth.instance.currentUser;
  // If user is null, we can't proceed, but we'll default to null/loading state
  if (user != null) {
    try {
      // Assuming you have a 'vets' collection
      final vetDoc = await FirebaseFirestore.instance.collection('vets').doc(user.uid).get();
      if (vetDoc.exists) {
        setState(() {
          // Update state with the fetched name
          _loggedInVetName = vetDoc.data()?['name'] ?? 'Unknown Vet';
        });
      } else {
        setState(() {
          _loggedInVetName = 'Unknown Vet (No Profile)';
        });
      }
    } catch (e) {
      print("Error fetching vet name: $e");
      setState(() {
        _loggedInVetName = 'Error Loading Name';
      });
    }
  } else {
    setState(() {
      _loggedInVetName = 'Not Logged In';
    });
  }
}

// NEW FUNCTION: The core debouncing logic
void _onSearchChanged(String query) {
  // If a timer is active, cancel it.
  if (_debounce?.isActive ?? false) _debounce!.cancel();

  // Start a new timer. The search update will execute after 500 milliseconds (0.5 seconds).
  _debounce = Timer(const Duration(milliseconds: 500), () {
    // Only update the state if the search query has actually changed since the last update
    if (_searchQuery != query) {
      setState(() {
        _searchQuery = query;
      });
    }
  });
}

  // FUNCTION 1: Fetch all relevant appointments once (Future)
  Future<QuerySnapshot> _fetchVetAppointments() async {
    // Return empty result immediately if the vet name hasn't loaded yet
    if (_loggedInVetName == null) {
      return Future.error("Vet Name is Loading");
    }

    return appointmentsCollection
        .where('vetName', isEqualTo: _loggedInVetName)
        .get();
  }

  // Cache for user profile images to avoid repeated fetches
  final Map<String, String?> _userImageCache = {};

  Future<String?> _getUserProfileImage(String userId) async {
    if (userId.isEmpty) return null;
    if (_userImageCache.containsKey(userId)) {
      return _userImageCache[userId];
    }
    try {
      final doc = await usersCollection.doc(userId).get();
      final url = (doc.data() as Map<String, dynamic>?)?['profileImageUrl'] as String?;
      _userImageCache[userId] = url;
      return url;
    } catch (e) {
      _userImageCache[userId] = null;
      return null;
    }
  }

  /// Safely convert Timestamp or String date to DateTime
  DateTime? _getDateFromData(dynamic dateValue) {
    if (dateValue is Timestamp) {
      return dateValue.toDate();
    } else if (dateValue is String) {
      try {
        return DateTime.parse(dateValue);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Format date for display
  String _formatDate(DateTime? date) {
    if (date == null) return "N/A";
    return '${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.year}';
  }
  double _safeRating(dynamic rating) {
    double v = 0.0;
    if (rating == null) return 0.0;
    if (rating is num) v = rating.toDouble();
    else if (rating is String) v = double.tryParse(rating) ?? 0.0;
    if (v.isNaN || v.isInfinite) return 0.0;
    return v;
  }

  @override
  Widget build(BuildContext context) {
    // Handle initial loading state for the vet's name
    if (_loggedInVetName == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(value: null, semanticsLabel: 'Loading Vet Profile')),
      );
    }

    // WRAPPER: FutureBuilder waits for appointment data to be ready
    return FutureBuilder<QuerySnapshot>(
      future: _fetchVetAppointments(),
      builder: (context, appointmentSnapshot) {

        // Handle loading state for appointments (only if the vet name loaded successfully)
        if (appointmentSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Handle error state for appointments
        if (appointmentSnapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('Error loading appointments: ${appointmentSnapshot.error}')),
          );
        }

        // DATA PREP: Create an efficient lookup map for appointments
        final Map<String, Map<String, dynamic>> appointmentLookupMap = {};
        if (appointmentSnapshot.hasData) {
          for (var doc in appointmentSnapshot.data!.docs) {
            appointmentLookupMap[doc.id] = doc.data() as Map<String, dynamic>;
          }
        }

        // Now build the main UI with the Scaffold
        return Scaffold(
          backgroundColor: Colors.grey.shade100,
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sidebar
              const CommonSidebar(currentScreen: 'Feedback'),
              
              // Main content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🟢 HEADER (Refreshed styling)
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
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
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.all(10),
                            child: Icon(Icons.reviews, color: accentGreen, size: 28),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Client Feedback",
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 24,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _loggedInVetName ?? '',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: Colors.black.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

              // ---

              // 🟢 SEARCH & SORT CONTROLS (Updated to use Debouncing)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: "Search client, pet, or feedback...",
                          prefixIcon: const Icon(Icons.search, color: Colors.grey),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: accentGreen, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _sortOption,
                          items: const [
                            DropdownMenuItem(value: "Newest First", child: Text("Newest First")),
                            DropdownMenuItem(value: "Oldest First", child: Text("Oldest First")),
                            DropdownMenuItem(value: "Name (A–Z)", child: Text("Name (A–Z)")),
                            DropdownMenuItem(value: "Name (Z–A)", child: Text("Name (Z–A)")),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _sortOption = value);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ---

              // 🟢 FEEDBACK LIST (StreamBuilder)
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: feedbackCollection
                          // The vet name is guaranteed to be non-null here due to the check above
                      .where('vetName', isEqualTo: _loggedInVetName!)
                      .snapshots(),
                  builder: (context, feedbackSnapshot) {
                    if (feedbackSnapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading feedback: ${feedbackSnapshot.error}',
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      );
                    }
                    if (feedbackSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!feedbackSnapshot.hasData || feedbackSnapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Text(
                          "No client feedback found for $_loggedInVetName.",
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      );
                    }

                    // DATA JOIN: Combine feedback data with appointment data
                    List<Map<String, dynamic>> feedbackList = feedbackSnapshot.data!.docs.map((doc) {
                      try {
                        final raw = doc.data();
                        if (raw == null) return <String, dynamic>{};
                        final data = Map<String, dynamic>.from(raw as Map);
                        final docId = doc.id;

                      // Assuming a field 'appointmentId' exists in the feedback document to link it
                        final String? linkedApptId = data['appointmentId'];

                        final Map<String, dynamic>? linkedAppointment = linkedApptId != null
                            ? appointmentLookupMap[linkedApptId]
                            : null;

                      // Try to resolve userId from feedback first, then from linked appointment
                        final String? userId =
                            (data['userId'] ?? data['userDocId'] ?? linkedAppointment?['userId'] ?? linkedAppointment?['userDocId'])
                                ?.toString();
                        final String? inlineProfile =
                            (data['profileImageUrl'] ?? data['userProfileImageUrl'])?.toString();

                        return {
                          "id": docId,
                          "name": data["Name"] ?? data["name"] ?? "Anonymous",
                          "feedback": data["Feedback"] ?? data["feedback"] ?? "",
                          "date": _getDateFromData(data["date"] ?? data["Date"]),
                          "rating": _safeRating(data["rating"]),
                          // Attach the linked appointment data
                          "appointmentDetails": linkedAppointment,
                          // For profile rendering
                          "userId": userId,
                          "inlineProfileImageUrl": inlineProfile,
                        };
                      } catch (_) {
                        // Skip malformed document
                        return <String, dynamic>{};
                      }
                    }).toList();

                    // Remove any skipped/empty entries
                    feedbackList = feedbackList.where((e) => e.isNotEmpty).toList();

                    // 🔍 Filter and 📅 Sort logic
                    feedbackList = feedbackList
                        .where((fb) {
                          final name = fb["name"].toString().toLowerCase();
                          final feedback = fb["feedback"].toString().toLowerCase();
                          final query = _searchQuery.toLowerCase().trim();

                          // Also check against appointment details like pet name
                          final linkedAppt = fb["appointmentDetails"];
                          final petName = linkedAppt?['petName']?.toString().toLowerCase() ?? '';

                          return name.contains(query) || feedback.contains(query) || petName.contains(query);
                        })
                        .toList();

                    feedbackList.sort((a, b) {
                      switch (_sortOption) {
                        case "Newest First":
                          final dateA = a["date"] as DateTime?;
                          final dateB = b["date"] as DateTime?;
                          if (dateA == null && dateB == null) return 0;
                          if (dateA == null) return 1;
                          if (dateB == null) return -1;
                          return dateB.compareTo(dateA);
                        case "Oldest First":
                          final dateA = a["date"] as DateTime?;
                          final dateB = b["date"] as DateTime?;
                          if (dateA == null && dateB == null) return 0;
                          if (dateA == null) return 1;
                          if (dateB == null) return -1;
                          return dateA.compareTo(dateB);
                        case "Name (A–Z)":
                          return (a["name"] ?? "").compareTo(b["name"] ?? "");
                        case "Name (Z–A)":
                          return (b["name"] ?? "").compareTo(a["name"] ?? "");
                        default:
                          return 0;
                      }
                    });

                    // 🧩 DISPLAY FEEDBACK CARDS
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: feedbackList.length,
                      itemBuilder: (context, index) {
                        final fb = feedbackList[index];
                        try {

                        // NEW: Extract and display linked appointment details
                        final linkedAppt = fb["appointmentDetails"] as Map<String, dynamic>?;
                        final petName = (linkedAppt?['petName'] ?? 'N/A').toString();

                        String subtitleText = (fb["feedback"] ?? "").toString();
                        // Updated appointmentInfo to only include Pet Name
                        String appointmentInfo = 'Pet: $petName';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12.withOpacity(0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ListTile(
                            isThreeLine: true,
                            contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                            leading: SizedBox(
                              width: 48,
                              height: 48,
                              child: _UserAvatar(
                                inlineUrl: fb["inlineProfileImageUrl"] as String?,
                                userId: fb["userId"] as String?,
                                resolver: _getUserProfileImage,
                              ),
                            ),
                            title: Text(
                              fb["name"] ?? "",
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            // Updated subtitle to include both feedback and appointment info
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                                  child: Text(
                                    subtitleText,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.5,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: accentGreen.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        appointmentInfo,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: accentGreen.withOpacity(0.9),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _formatDate(fb["date"] as DateTime?),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: SizedBox(
                              height: 24,
                              child: _RatingPill(rating: _safeRating(fb["rating"]), color: accentGreen),
                            ),
                          ),
                        );
                        } catch (e, _) {
                          // If any unexpected issue occurs for this row, skip rendering it.
                          return const SizedBox.shrink();
                        }
                      },
                    );
                  },
                ),
              ),
                    ],
                  ),
                ),
              ],
            ),
          )
        ;
      },
    );
  }
}

