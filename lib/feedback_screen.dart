import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class VetFeedbackScreen extends StatefulWidget {
  const VetFeedbackScreen({super.key});

  @override
  State<VetFeedbackScreen> createState() => _VetFeedbackScreenState();
}

class _VetFeedbackScreenState extends State<VetFeedbackScreen> {
  final Color headerColor = const Color(0xFFBDD9A4);
  final Color accentGreen = const Color(0xFF8DBF67);
  List<Map<String, String>> feedbackList = [];
  List<Map<String, String>> filteredList = [];

  String _sortOption = "Newest First";
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFeedback();
  }

  Future<void> _loadFeedback() async {
    final prefs = await SharedPreferences.getInstance();
    final storedData = prefs.getString('feedback_list');
    if (storedData != null) {
      setState(() {
        feedbackList = List<Map<String, String>>.from(jsonDecode(storedData));
        filteredList = List.from(feedbackList);
        _applySort();
      });
    }
  }

  void _applySort() {
    setState(() {
      if (_sortOption == "Newest First") {
        filteredList.sort((a, b) => (b["Date"] ?? "").compareTo(a["Date"] ?? ""));
      } else if (_sortOption == "Oldest First") {
        filteredList.sort((a, b) => (a["Date"] ?? "").compareTo(b["Date"] ?? ""));
      } else if (_sortOption == "Name (A–Z)") {
        filteredList.sort((a, b) => (a["Name"] ?? "").compareTo(b["Name"] ?? ""));
      } else if (_sortOption == "Name (Z–A)") {
        filteredList.sort((a, b) => (b["Name"] ?? "").compareTo(a["Name"] ?? ""));
      }
    });
  }

  void _filterSearch(String query) {
    setState(() {
      filteredList = feedbackList
          .where((fb) =>
              fb["Name"]!.toLowerCase().contains(query.toLowerCase()) ||
              fb["Feedback"]!.toLowerCase().contains(query.toLowerCase()))
          .toList();
      _applySort();
    });
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
                )
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black87),
                  onPressed: () {
                    Navigator.pop(context);
                  },
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

          // Search + Sort Controls
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              children: [
                // Search Bar
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _filterSearch,
                    decoration: InputDecoration(
                      hintText: "Search by client name or feedback...",
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Sort Dropdown
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
                        if (value != null) {
                          setState(() {
                            _sortOption = value;
                            _applySort();
                          });
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Feedback List
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: filteredList.isEmpty
                  ? const Center(
                      child: Text(
                        "No client feedback yet.",
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredList.length,
                      itemBuilder: (context, index) {
                        final fb = filteredList[index];
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
                              fb["Date"] ?? "",
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
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
