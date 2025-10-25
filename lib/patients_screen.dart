import 'package:flutter/material.dart';

class PatientsScreen extends StatefulWidget {
  final Map<String, String>? existingPatient;

  const PatientsScreen({super.key, this.existingPatient});

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _speciesController = TextEditingController();
  final TextEditingController _breedController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _appearanceController = TextEditingController();
  final TextEditingController _ownerController = TextEditingController();
  final TextEditingController _consultationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // If editing existing patient, pre-fill fields
    if (widget.existingPatient != null) {
      _nameController.text = widget.existingPatient!["Patient Name"] ?? "";
      _speciesController.text = widget.existingPatient!["Species"] ?? "";
      _breedController.text = widget.existingPatient!["Breed"] ?? "";
      _heightController.text = widget.existingPatient!["Height"] ?? "";
      _weightController.text = widget.existingPatient!["Weight"] ?? "";
      _appearanceController.text = widget.existingPatient!["Appearance"] ?? "";
      _ownerController.text = widget.existingPatient!["Owner Info"] ?? "";
      _consultationController.text =
          widget.existingPatient!["Last Consultation"] ?? "";
    }
  }

  void _savePatient() {
    if (_formKey.currentState!.validate()) {
      final patientData = {
        "Patient Name": _nameController.text.trim(),
        "Species": _speciesController.text.trim(),
        "Breed": _breedController.text.trim(),
        "Height": _heightController.text.trim(),
        "Weight": _weightController.text.trim(),
        "Appearance": _appearanceController.text.trim(),
        "Owner Info": _ownerController.text.trim(),
        "Last Consultation": _consultationController.text.trim(),
      };

      Navigator.pop(context, patientData);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingPatient != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? "Edit Patient" : "Add Patient"),
        backgroundColor: const Color(0xFF728D5A),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Container(
            width: 600,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  spreadRadius: 3,
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  const SizedBox(height: 10),
                  _buildTextField(_nameController, "Patient Name"),
                  _buildTextField(_speciesController, "Species"),
                  _buildTextField(_breedController, "Breed"),
                  _buildTextField(_heightController, "Height"),
                  _buildTextField(_weightController, "Weight"),
                  _buildTextField(_appearanceController, "Appearance"),
                  _buildTextField(_ownerController, "Owner Info"),
                  _buildTextField(_consultationController, "Last Consultation"),

                  const SizedBox(height: 25),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                        label: const Text("Cancel"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 18),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _savePatient,
                        icon: const Icon(Icons.save),
                        label: Text(isEditing ? "Update" : "Save"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 18),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
          filled: true,
          fillColor: Colors.white,
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
