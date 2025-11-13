import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// The screen name used in PatientHistoryScreen was VetHistoryNotesScreen.
class VetHistoryNotesScreen extends StatefulWidget {
  // 1. Corrected Constructor: It now requires the specific appointment ID and patient name.
  final String appointmentId;
  final String patientName;

  const VetHistoryNotesScreen({
    super.key,
    required this.appointmentId,
    required this.patientName,
  });

  @override
  State<VetHistoryNotesScreen> createState() => _VetHistoryNotesScreenState();
}

class _VetHistoryNotesScreenState extends State<VetHistoryNotesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Color primaryGreen = const Color(0xFF728D5A); // Color consistent with PatientHistoryScreen
  
  // Controller for the single notes field
  late TextEditingController _notesController;
  
  // State variables for displaying patient/appointment info
  Map<String, dynamic>? _appointmentData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
    _fetchAppointmentData();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }
  
  // Helper to format Timestamp
  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "N/A";
    final date = timestamp.toDate().toLocal();
    return DateFormat('MMM dd, yyyy @ hh:mm a').format(date);
  }

  // 2. Data Fetching Logic: Fetch only the single required document
  Future<void> _fetchAppointmentData() async {
    try {
      final docSnapshot = await _firestore
          .collection('user_appointments') // Assuming this is the correct collection
          .doc(widget.appointmentId)
          .get();

      if (docSnapshot.exists) {
        _appointmentData = docSnapshot.data();
        // Initialize controller with existing notes
        final initialNotes = _appointmentData?['vetNotes'] ?? '';
        _notesController.text = initialNotes;
      }
    } catch (e) {
      debugPrint("Error fetching appointment data: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 3. Save vet notes to Firestore for the specific document
  Future<void> _saveVetNotes() async {
    if (_appointmentData == null) return;
    
    // Check if notes have actually changed before saving
    final currentNotes = _notesController.text;
    if (currentNotes == (_appointmentData!['vetNotes'] ?? '')) {
       if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No changes to save.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      await _firestore.collection('user_appointments').doc(widget.appointmentId).set({
        'vetNotes': currentNotes,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      // Update local state and show success message
      setState(() {
        _appointmentData!['vetNotes'] = currentNotes;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Notes saved successfully!'),
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
      backgroundColor: Colors.grey[50], 
      appBar: AppBar(
        title: Text("Notes for ${widget.patientName}"),
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryGreen))
          : _appointmentData == null
              ? Center(child: Text("Error: Appointment ID ${widget.appointmentId} not found."))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Patient/Appointment Summary Card
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Appointment Details",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: primaryGreen,
                                ),
                              ),
                              const Divider(),
                              _buildDetailRow(
                                  Icons.calendar_today,
                                  "Date & Time",
                                  _formatDate(_appointmentData!['appointmentDateTime'] as Timestamp?),
                                  
                              ),
                              _buildDetailRow(
                                  Icons.person_outline,
                                  "Owner",
                                  _appointmentData!['userName'] ?? 'N/A'),
                              _buildDetailRow(
                                  Icons.info_outline,
                                  "Purpose",
                                  _appointmentData!['reason'] ?? 'N/A'),
                              _buildDetailRow(
                                  Icons.verified_user_outlined,
                                  "Status",
                                  _appointmentData!['status'] ?? 'N/A',
                                  color: _getStatusColor(_appointmentData!['status'] ?? 'N/A')),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Vet Notes Section
                      Text(
                        "Clinical/History Notes",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 10),

                      TextField(
                        controller: _notesController,
                        decoration: InputDecoration(
                          labelText: "Enter detailed clinical notes here...",
                          alignLabelWithHint: true,
                          border: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(10)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: primaryGreen, width: 2),
                            borderRadius: const BorderRadius.all(Radius.circular(10)),
                          ),
                        ),
                        maxLines: 10,
                        minLines: 5,
                      ),
                      const SizedBox(height: 20),

                      // Save button
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: _saveVetNotes,
                          icon: const Icon(Icons.save, size: 18),
                          label: const Text("Save"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),

                    ],
                  ),
                ),
    );
  }
  
  // Helper widget to display a row of detail
  Widget _buildDetailRow(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: primaryGreen),
          const SizedBox(width: 8),
          Text("$label: ", style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: color ?? Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  // Helper to get color for status (reused from PatientHistoryScreen)
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return Colors.green.shade700;
      case 'pending':
        return Colors.amber.shade700;
      case 'declined':
      case 'cancelled':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade600;
    }
  }
}