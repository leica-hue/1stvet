import 'package:flutter/material.dart';
import 'patients_list_screen.dart';

class PatientsScreen extends StatefulWidget {
  const PatientsScreen({super.key});

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  final Color headerColor = const Color(0xFFBDD9A4);

  // Controllers
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController speciesCtrl = TextEditingController();
  final TextEditingController breedCtrl = TextEditingController();
  final TextEditingController heightCtrl = TextEditingController();
  final TextEditingController weightCtrl = TextEditingController();
  final TextEditingController appearanceCtrl = TextEditingController();
  final TextEditingController notesCtrl = TextEditingController();
  final TextEditingController lastConsultCtrl = TextEditingController();
  final TextEditingController ownerCtrl = TextEditingController();

  void _resetForm() {
    nameCtrl.clear();
    speciesCtrl.clear();
    breedCtrl.clear();
    heightCtrl.clear();
    weightCtrl.clear();
    appearanceCtrl.clear();
    notesCtrl.clear();
    lastConsultCtrl.clear();
    ownerCtrl.clear();
  }

  void _saveForm() {
    final patient = {
      "Patient Name": nameCtrl.text,
      "Species": speciesCtrl.text,
      "Breed": breedCtrl.text,
      "Height": heightCtrl.text,
      "Weight": weightCtrl.text,
      "Appearance": appearanceCtrl.text,
      "Notes": notesCtrl.text,
      "Last Consultation": lastConsultCtrl.text,
      "Owner Info": ownerCtrl.text,
    };

    Navigator.pop(context, patient); // returns data to PatientsListScreen
  }

  void _viewPatientsList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PatientsListScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            color: headerColor,
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            child: const Text(
              "Add Patient",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
            ),
          ),

          // Form
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ListView(
                children: [
                  _buildTextField("Patient Name", nameCtrl),
                  _buildTextField("Species", speciesCtrl),
                  _buildTextField("Breed", breedCtrl),
                  _buildTextField("Height", heightCtrl),
                  _buildTextField("Weight", weightCtrl),
                  _buildTextField("Appearance", appearanceCtrl),
                  _buildTextField("Notes", notesCtrl, maxLines: 3),
                  _buildTextField("Last Consultation", lastConsultCtrl),
                  _buildTextField("Owner Info", ownerCtrl),

                  const SizedBox(height: 30),

                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _actionButton("Reset", Colors.grey, _resetForm),
                      const SizedBox(width: 12),
                      _actionButton("Save", Colors.green, _saveForm),
                      const SizedBox(width: 12),
                      _actionButton("View Patients", Colors.blue, _viewPatientsList),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Reusable styled textfield
  Widget _buildTextField(String label, TextEditingController ctrl,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: "Enter $label",
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade400),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.green, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Reusable styled button
  Widget _actionButton(String text, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }
}
