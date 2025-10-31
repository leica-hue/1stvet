import 'package:flutter/material.dart';
import 'appointments_screen.dart';

class VetNotesScreen extends StatefulWidget {
  final List<Appointment> appointments;
  final Future<void> Function() onSave;

  const VetNotesScreen({
    super.key,
    required this.appointments,
    required this.onSave,
  });

  @override
  State<VetNotesScreen> createState() => _VetNotesScreenState();
}

class _VetNotesScreenState extends State<VetNotesScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Vet History & Notes"),
        backgroundColor: const Color(0xFF6E8C5E),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView.builder(
          itemCount: widget.appointments.length,
          itemBuilder: (context, index) {
            final appt = widget.appointments[index];

            // ✅ Controller initialized with the vetNotes text
            final controller = TextEditingController(text: appt.vetNotes);

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
                    Text(appt.petName,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text("Owner: ${appt.owner}"),
                    Text("Purpose: ${appt.purpose}"),
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
                        // ✅ update appointment data immediately
                        appt.vetNotes = val;
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
                          await widget.onSave(); // parent callback
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Notes saved successfully!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: const Text("Save Notes"),
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
