import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/appointments_screen.dart';

class VetNotesScreen extends StatefulWidget {
  const VetNotesScreen({super.key, required List<Appointment> appointments, required Future<Null> Function() onSave});

  @override
  State<VetNotesScreen> createState() => _VetNotesScreenState();
}


class _VetNotesScreenState extends State<VetNotesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Save vet notes to Firestore
Future<void> _saveVetNotes(String docId, String newNotes) async {
  try {
    await _firestore.collection('appointments').doc(docId).set({
      'vetNotes': newNotes,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)); // ✅ ensures field is added if missing
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notes saved successfully!'),
        duration: Duration(seconds: 2),
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error saving notes: $e')),
    );
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
              final data = doc.data() as Map<String, dynamic>;

              final petName = data['petName'] ?? 'Unknown Pet';
              final owner = data['owner'] ?? 'Unknown Owner';
              final purpose = data['purpose'] ?? 'No Purpose';
              final vetNotes = data['vetNotes'] ?? '';

              final controller = TextEditingController(text: vetNotes);

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
                        controller: controller,
                        decoration: const InputDecoration(
                          labelText: "Vet Notes",
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                        onChanged: (val) {
                          // no need to update immediately
                        },
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
                            await _saveVetNotes(doc.id, controller.text);
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
