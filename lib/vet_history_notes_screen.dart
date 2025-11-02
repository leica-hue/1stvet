import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/appointments_screen.dart';
// Note: Removed the unused 'appointments_screen.dart' import since you don't need the Appointment model here.

// 1. FIXED CONSTRUCTOR: Removed unnecessary parameters
class VetNotesScreen extends StatefulWidget {
  const VetNotesScreen({super.key, required Future<Null> Function() onSave, required List<Appointment> appointments});

  @override
  State<VetNotesScreen> createState() => _VetNotesScreenState();
}


class _VetNotesScreenState extends State<VetNotesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // 2. FIXED: Map to manage the state of each TextField's controller
  final Map<String, TextEditingController> _noteControllers = {};

  @override
  void dispose() {
    // Dispose all controllers when the widget is removed to prevent memory leaks
    _noteControllers.forEach((key, controller) => controller.dispose());
    super.dispose();
  }

  // Save vet notes to Firestore
  Future<void> _saveVetNotes(String docId, String newNotes) async {
    try {
      await _firestore.collection('appointments').doc(docId).set({
        'vetNotes': newNotes,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notes saved successfully!'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving notes: $e')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], // Slightly better background
      appBar: AppBar(
        title: const Text("Vet History & Notes"),
        backgroundColor: const Color(0xFF6E8C5E),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('appointments').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No appointments found."));
          }

          final appointments = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: appointments.length,
            itemBuilder: (context, index) {
              final doc = appointments[index];
              final docId = doc.id; // Important: Get the document ID
              final data = doc.data() as Map<String, dynamic>;

              final petName = data['petName'] ?? 'Unknown Pet';
              final owner = data['owner'] ?? 'Unknown Owner';
              final purpose = data['purpose'] ?? 'No Purpose';
              final initialVetNotes = data['vetNotes'] ?? '';
              
              // 3. FIXED: Controller management
              final controller = _noteControllers.putIfAbsent(
                docId, 
                () => TextEditingController(text: initialVetNotes),
              );

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        petName,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text("Owner: $owner"),
                      Text("Purpose: $purpose"),
                      const SizedBox(height: 8),

                      // 📝 Notes text field
                      TextField(
                        controller: controller, // Use the managed controller
                        decoration: const InputDecoration(
                          labelText: "Vet Notes",
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                        // Removed redundant onChanged
                      ),
                      const SizedBox(height: 10),

                      // 💾 Save button
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6E8C5E),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            // Pass the document ID and the controller's current text
                            await _saveVetNotes(docId, controller.text);
                          },
                          child: const Text("Save Notes"),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}