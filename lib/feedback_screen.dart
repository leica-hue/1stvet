import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  final CollectionReference feedbackCollection =
      FirebaseFirestore.instance.collection('feedback');

  // Helper function to safely get a DateTime from Firestore data
  DateTime? _getDateFromData(dynamic dateValue) {
    if (dateValue is Timestamp) {
      return dateValue.toDate();
    }
    // If it's not a Timestamp, return null or handle appropriately
    return null;
  }

  // Helper function to format the date for display
  String _formatDate(DateTime? date) {
    if (date == null) return "N/A";
    // Example: Format as 'MM/dd/yyyy'
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
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

          // Search + Sort
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      hintText: "Search by client name or feedback...",
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

          // Real-time Firestore feedbacks
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: feedbackCollection.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      "No client feedback yet.",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  );
                }

                // 🛠️ FIX 1: Convert Timestamp to DateTime during mapping
                List<Map<String, dynamic>> feedbackList = snapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return {
                    "id": doc.id,
                    "Name": data["Name"] ?? "",
                    "Feedback": data["Feedback"] ?? "",
                    // Convert Timestamp to DateTime (or null if missing/wrong type)
                    "Date": _getDateFromData(data["date"]), 
                  };
                }).toList();

                // Search filter
                feedbackList = feedbackList
                    .where((fb) {
                      final name =
                          fb["Name"]?.toString().toLowerCase().trim() ?? "";
                      final feedback =
                          fb["Feedback"]?.toString().toLowerCase().trim() ?? "";
                      final query = _searchQuery.toLowerCase().trim();
                      return name.contains(query) || feedback.contains(query);
                    })
                    .toList();

                // 🛠️ FIX 2: Use DateTime.compareTo() for date sorting
                feedbackList.sort((a, b) {
                  switch (_sortOption) {
                    case "Newest First":
                      // Use DateTime.compareTo() for correct date ordering
                      final dateA = a["Date"] as DateTime?;
                      final dateB = b["Date"] as DateTime?;
                      if (dateA == null && dateB == null) return 0;
                      if (dateA == null) return 1; // Put null dates last
                      if (dateB == null) return -1; // Put null dates last
                      return dateB.compareTo(dateA); // Descending (Newest first)
                      
                    case "Oldest First":
                      // Use DateTime.compareTo()
                      final dateA = a["Date"] as DateTime?;
                      final dateB = b["Date"] as DateTime?;
                      if (dateA == null && dateB == null) return 0;
                      if (dateA == null) return 1;
                      if (dateB == null) return -1;
                      return dateA.compareTo(dateB); // Ascending (Oldest first)

                    case "Name (A–Z)":
                      return (a["Name"] ?? "").compareTo(b["Name"] ?? "");
                    case "Name (Z–A)":
                      return (b["Name"] ?? "").compareTo(a["Name"] ?? "");
                    default:
                      return 0;
                  }
                });

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: feedbackList.length,
                  itemBuilder: (context, index) {
                    final fb = feedbackList[index];
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
                          fb["Name"] ?? "",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            fb["Feedback"] ?? "",
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ),
                        trailing: Text(
                          // 🛠️ FIX 3: Use the formatter for display
                          _formatDate(fb["Date"] as DateTime?),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
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
  }
}