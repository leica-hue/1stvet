import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PatientsScreen extends StatefulWidget {
  const PatientsScreen({super.key, Map<String, dynamic>? existingPatient, String? docId});

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  final _firestore = FirebaseFirestore.instance;

  void _openPatientForm({DocumentSnapshot? document}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditPatientScreen(
          docId: document?.id,
          existingPatient:
              document != null ? document.data() as Map<String, dynamic> : null,
        ),
      ),
    );
  }

  Future<void> _deletePatient(String docId) async {
    await _firestore.collection('patients').doc(docId).delete();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Patient deleted successfully!")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Patients List"),
        backgroundColor: const Color(0xFF728D5A),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF728D5A),
        onPressed: () => _openPatientForm(),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('patients')
            .orderBy('registeredDate', descending: true)
            .snapshots(), // 🔥 Real-time listener
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text("Error loading patients"));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final patients = snapshot.data!.docs;

          if (patients.isEmpty) {
            return const Center(child: Text("No patients found"));
          }

          return ListView.builder(
            itemCount: patients.length,
            itemBuilder: (context, index) {
              final patient = patients[index];
              final data = patient.data() as Map<String, dynamic>;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: ListTile(
                  title: Text(data["Patient Name"] ?? "Unknown"),
                  subtitle: Text("${data["Species"] ?? ''} • ${data["Owner Info"] ?? ''}"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _openPatientForm(document: patient),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deletePatient(patient.id),
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

// 🟩 ADD / EDIT SCREEN
class AddEditPatientScreen extends StatefulWidget {
  final Map<String, dynamic>? existingPatient;
  final String? docId;

  const AddEditPatientScreen({super.key, this.existingPatient, this.docId});

  @override
  State<AddEditPatientScreen> createState() => _AddEditPatientScreenState();
}

class _AddEditPatientScreenState extends State<AddEditPatientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;

  // Controllers
  final _nameController = TextEditingController();
  final _speciesController = TextEditingController();
  final _breedController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _appearanceController = TextEditingController();
  final _ownerController = TextEditingController();
  final _consultationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.existingPatient != null) {
      _nameController.text = widget.existingPatient!["Patient Name"] ?? "";
      _speciesController.text = widget.existingPatient!["Species"] ?? "";
      _breedController.text = widget.existingPatient!["Breed"] ?? "";
      _heightController.text = widget.existingPatient!["Height"] ?? "";
      _weightController.text = widget.existingPatient!["Weight"] ?? "";
      _appearanceController.text =
          widget.existingPatient!["Appearance"] ?? "";
      _ownerController.text = widget.existingPatient!["Owner Info"] ?? "";
      _consultationController.text =
          widget.existingPatient!["Last Consultation"] ?? "";
    }
  }

  Future<void> _savePatient() async {
    if (!_formKey.currentState!.validate()) return;

    final patientData = {
      "Patient Name": _nameController.text.trim(),
      "Species": _speciesController.text.trim(),
      "Breed": _breedController.text.trim(),
      "Height": _heightController.text.trim(),
      "Weight": _weightController.text.trim(),
      "Appearance": _appearanceController.text.trim(),
      "Owner Info": _ownerController.text.trim(),
      "Last Consultation": _consultationController.text.trim(),
      "registeredDate": FieldValue.serverTimestamp(),
    };

    try {
      if (widget.docId != null) {
        await _firestore
            .collection('patients')
            .doc(widget.docId)
            .update(patientData);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Patient updated successfully!")),
        );
      } else {
        await _firestore.collection('patients').add(patientData);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Patient added successfully!")),
        );
      }
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error saving patient: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.docId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? "Edit Patient" : "Add Patient"),
        backgroundColor: const Color(0xFF728D5A),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              _buildTextField(_nameController, "Patient Name"),
              _buildTextField(_speciesController, "Species"),
              _buildTextField(_breedController, "Breed"),
              _buildTextField(_heightController, "Height"),
              _buildTextField(_weightController, "Weight"),
              _buildTextField(_appearanceController, "Appearance"),
              _buildTextField(_ownerController, "Owner Info"),
              _buildTextField(_consultationController, "Last Consultation"),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text("Cancel"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _savePatient,
                    icon: const Icon(Icons.save),
                    label: Text(isEditing ? "Update" : "Save"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return "Please enter $label";
          }
          return null;
        },
      ),
    );
  }
}
