import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async'; // IMPORTED for Timer

class VetFeedbackScreen extends StatefulWidget {
  const VetFeedbackScreen({super.key});

  @override
  State<VetFeedbackScreen> createState() => _VetFeedbackScreenState();
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
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🟢 HEADER (Unchanged)
              Container(
                decoration: BoxDecoration(
                  color: headerColor,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.3),
                      spreadRadius: 2,
                      blurRadius: 5,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black87),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "Client Feedbacks",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 26,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),

              // ---

              // 🟢 SEARCH & SORT CONTROLS (Updated to use Debouncing)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        // ADDED: Use the controller
                        controller: _searchController,
                        // CHANGED: Call the debounced function
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: "Search by client name, pet name, or feedback...",
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _sortOption,
                          items: const [
                            DropdownMenuItem(
                                value: "Newest First", child: Text("Newest First")),
                            DropdownMenuItem(
                                value: "Oldest First", child: Text("Oldest First")),
                            DropdownMenuItem(
                                value: "Name (A–Z)", child: Text("Name (A–Z)")),
                            DropdownMenuItem(
                                value: "Name (Z–A)", child: Text("Name (Z–A)")),
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
                      final data = doc.data() as Map<String, dynamic>;
                      final docId = doc.id;

                      // Assuming a field 'appointmentId' exists in the feedback document to link it
                      final String? linkedApptId = data['appointmentId'];

                      final Map<String, dynamic>? linkedAppointment = linkedApptId != null
                          ? appointmentLookupMap[linkedApptId]
                          : null;

                      return {
                        "id": docId,
                        "name": data["Name"] ?? data["name"] ?? "Anonymous",
                        "feedback": data["Feedback"] ?? data["feedback"] ?? "",
                        "date": _getDateFromData(data["date"] ?? data["Date"]),
                        "rating": data["rating"] ?? 0,
                        // Attach the linked appointment data
                        "appointmentDetails": linkedAppointment,
                      };
                    }).toList();

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

                        // NEW: Extract and display linked appointment details
                        final linkedAppt = fb["appointmentDetails"] as Map<String, dynamic>?;
                        final petName = linkedAppt?['petName'] ?? 'N/A';

                        String subtitleText = fb["feedback"] ?? "";
                        // Updated appointmentInfo to only include Pet Name
                        String appointmentInfo = 'Pet: $petName';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12.withOpacity(0.08),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: accentGreen.withOpacity(0.8),
                              child: const Icon(Icons.person,
                                  color: Colors.white, size: 22),
                            ),
                            title: Text(
                              fb["name"] ?? "",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
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
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                                Text(
                                  appointmentInfo,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: accentGreen.withOpacity(0.9),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Original Rating/Date trailing content
                                Text(
                                  _formatDate(fb["date"] as DateTime?),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      fb["rating"].toString(),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: accentGreen,
                                      ),
                                    ),
                                    const Icon(
                                      Icons.star,
                                      color: Colors.amber,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}