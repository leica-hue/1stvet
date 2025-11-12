import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class PricingManagementScreen extends StatefulWidget {
  const PricingManagementScreen({super.key});

  @override
  State<PricingManagementScreen> createState() => _PricingManagementScreenState();
}

class _PricingManagementScreenState extends State<PricingManagementScreen> {
  final _firestore = FirebaseFirestore.instance;
  final String _ratesDocId = 'vet_rates';
  final String _collectionName = 'app_settings';

  // 🎯 DEFAULT RATES STRUCTURE - Used for initialization if Firestore is empty
  final Map<String, dynamic> _defaultRates = {
    'consultation_fee_php': 800.00,
    'urgent_surcharge_php': 500.00,
    'vaccination_rates': {
      'dog': 1500.00,
      'cat': 1000.00,
    },
    'deworming_rates': {
      'small_pet': 300.00,
      'large_pet': 550.00,
    },
  };

  // --- State Management for Text Fields ---
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _originalValues = {};
  final Set<String> _savingFields = {};

  @override
  void dispose() {
    _controllers.forEach((key, controller) => controller.dispose());
    super.dispose();
  }

  // --- Firestore Interaction Methods ---

  Stream<DocumentSnapshot> _getRatesStream() {
    return _firestore.collection(_collectionName).doc(_ratesDocId).snapshots();
  }

  Future<void> _updatePrice(String field, String value) async {
    final double? price = double.tryParse(value);

    if (price == null || price < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Invalid price format. Please enter a valid number.'),
              backgroundColor: Colors.red),
        );
      }
      return;
    }

    setState(() {
      _savingFields.add(field);
    });

    try {
      final Map<String, dynamic> updateData;
      if (field.contains('.')) {
        final parts = field.split('.');
        updateData = {
          parts[0]: {parts[1]: price}
        };
      } else {
        updateData = {field: price};
      }

      await _firestore
          .collection(_collectionName)
          .doc(_ratesDocId)
          .set(updateData, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${field.split('.').last.replaceAll('_', ' ')} updated to ₱${price.toStringAsFixed(2)}'),
              backgroundColor: const Color(0xFF6B8E23)),
        );
      }
      // Update the original value after successful save
      _originalValues[field] = price.toStringAsFixed(2);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update price: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingFields.remove(field);
        });
      }
    }
  }

  String _formatPrice(dynamic price) {
    if (price == null) return '0.00';
    if (price is num) {
      return price.toStringAsFixed(2);
    }
    final num? parsed = num.tryParse(price.toString());
    return parsed != null ? parsed.toStringAsFixed(2) : '0.00';
  }

  // --- Widget Builders ---

  // Refactored for better visual separation and hover effect (if on Web/Desktop)
  Widget _buildPriceInputTile({
    required String title,
    required String subtitle,
    required String firestoreField,
    required String initialValue,
    IconData icon = Icons.info_outline,
  }) {
    if (!_controllers.containsKey(firestoreField)) {
      _controllers[firestoreField] = TextEditingController(text: initialValue);
      _originalValues[firestoreField] = initialValue;
    }

    final TextEditingController controller = _controllers[firestoreField]!;
    final bool isSaving = _savingFields.contains(firestoreField);
    final bool isModified = controller.text.isNotEmpty && controller.text != _originalValues[firestoreField];

    return Card(
      elevation: 4, // Increased elevation for a floating effect
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16), // Rounded corners
        side: BorderSide(
          color: isModified ? const Color(0xFFEAF086) : Colors.transparent, // Highlight modified fields
          width: 2,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF728D5A), size: 32),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: Colors.black87)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 15),
            SizedBox(
              width: 120, // Increased width for better input visibility
              child: TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF6B8E23)), // Prominent text style
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  prefixText: '₱ ',
                  border: InputBorder.none,
                  filled: true,
                  fillColor: Colors.grey[50], // Slight background for input
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onChanged: (_) {
                  setState(() {}); 
                },
              ),
            ),
            SizedBox(
              width: 40,
              child: isSaving
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF728D5A)),
                      ),
                    )
                  : (isModified
                      ? IconButton(
                          icon: const Icon(Icons.check_circle, color: Color(0xFF6B8E23), size: 28), // Check icon for saving
                          onPressed: () => _updatePrice(firestoreField, controller.text),
                          tooltip: 'Save Rate',
                        )
                      : const SizedBox.shrink()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTieredServiceTile({
    required String title,
    required String subtitle,
    required Map<String, dynamic> rates,
    required String baseFirestoreField,
    IconData icon = Icons.category_outlined,
  }) {
    final average = rates.values.fold<double>(0.0, (sum, item) => sum + (item as num).toDouble()) / rates.length;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Icon(icon, color: const Color(0xFF728D5A), size: 32),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: Colors.black87)),
        subtitle: Text('Average Rate: ₱${average.toStringAsFixed(2)}. $subtitle', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        childrenPadding: const EdgeInsets.only(left: 20, right: 20, top: 8, bottom: 12),
        
        children: rates.entries.map((entry) {
          final tierKey = entry.key;
          final fullField = '$baseFirestoreField.$tierKey';
          final tierPrice = _formatPrice(entry.value);

          if (!_controllers.containsKey(fullField)) {
            _controllers[fullField] = TextEditingController(text: tierPrice);
            _originalValues[fullField] = tierPrice;
          }

          final TextEditingController controller = _controllers[fullField]!;
          final bool isSaving = _savingFields.contains(fullField);
          final bool isModified = controller.text.isNotEmpty && controller.text != _originalValues[fullField];

          return Container(
            margin: const EdgeInsets.only(bottom: 8.0),
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 10.0),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${tierKey.replaceAll('_', ' ')} Rate'.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF728D5A), fontSize: 14),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                    ],
                    decoration: const InputDecoration(
                      prefixText: '₱ ',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (_) {
                      setState(() {});
                    },
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: isSaving
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF728D5A)),
                          ),
                        )
                      : (isModified
                          ? IconButton(
                              icon: const Icon(Icons.check_circle_outline, color: Color(0xFF6B8E23)),
                              onPressed: () => _updatePrice(fullField, controller.text),
                              tooltip: 'Save Rate',
                            )
                          : const SizedBox.shrink()),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // --- Main Build Method ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9F5), // Light off-white background
      appBar: AppBar(
        backgroundColor: const Color(0xFFBDD9A4),
        title: const Text('Service & Pricing Management 💰',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Center( // 🎯 CRITICAL: Centered the entire body content
        child: ConstrainedBox( // 🎯 CRITICAL: Constrained width for professional desktop look
          constraints: const BoxConstraints(maxWidth: 900),
          child: StreamBuilder<DocumentSnapshot>(
            stream: _getRatesStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF728D5A)),
                    SizedBox(height: 10),
                    Text("Loading latest rates from cloud..."),
                  ],
                );
              }
              if (snapshot.hasError) {
                return Center(child: Text('❌ Error loading rates: ${snapshot.error}'));
              }

              // 1. Get data from snapshot or use defaults
              final Map<String, dynamic> snapshotData = snapshot.data?.data() as Map<String, dynamic>? ?? {};
              final Map<String, dynamic> ratesData = snapshotData.isNotEmpty ? snapshotData : _defaultRates;

              // 2. Initialize Firebase with defaults if the document was missing
              if (snapshotData.isEmpty && snapshot.data?.exists == false) {
                 WidgetsBinding.instance.addPostFrameCallback((_) {
                   _firestore.collection(_collectionName).doc(_ratesDocId).set(_defaultRates, SetOptions(merge: true));
                 });
              }

              // 3. Extract Fixed Rates
              final consultFee = _formatPrice(ratesData['consultation_fee_php']);
              final urgentSurcharge = _formatPrice(ratesData['urgent_surcharge_php']);

              // 4. Extract Tiered Rates and ensure they are numbers
              final Map<String, dynamic> vaccinationRates = ratesData['vaccination_rates'] ?? _defaultRates['vaccination_rates'];
              vaccinationRates.updateAll((key, value) => value is num ? value : num.tryParse(value.toString()) ?? 0.0);
              
              final Map<String, dynamic> dewormingRates = ratesData['deworming_rates'] ?? _defaultRates['deworming_rates'];
              dewormingRates.updateAll((key, value) => value is num ? value : num.tryParse(value.toString()) ?? 0.0);


              return ListView(
                children: [
                  
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                    child: Text('Fixed Fees',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                  ),

                  // 1. Initial Consultation Fee
                  _buildPriceInputTile(
                    title: 'Initial Consultation Fee',
                    subtitle: 'The base cost for any new general appointment.',
                    firestoreField: 'consultation_fee_php',
                    initialValue: consultFee,
                    icon: Icons.monitor_heart_outlined,
                  ),

                  // 2. Urgent Care Surcharge
                  _buildPriceInputTile(
                    title: 'Urgent Care Surcharge',
                    subtitle: 'Applied automatically for emergency or after-hours requests.',
                    firestoreField: 'urgent_surcharge_php',
                    initialValue: urgentSurcharge,
                    icon: Icons.warning_amber_rounded,
                  ),

                  const Padding(
                    padding: EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 8.0),
                    child: Text('Tiered Services',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                  ),

                  // 3. Routine Vaccination (Tiered)
                  _buildTieredServiceTile(
                    title: 'Routine Vaccination',
                    subtitle: 'Prices are set based on the species (Dog vs Cat) and vaccine type.',
                    rates: vaccinationRates,
                    baseFirestoreField: 'vaccination_rates',
                    icon: Icons.vaccines_outlined,
                  ),
                  
                  // 4. Deworming (New Tiered Service)
                  _buildTieredServiceTile(
                    title: 'Deworming Service',
                    subtitle: 'Prices are set based on the weight or size of the animal.',
                    rates: dewormingRates,
                    baseFirestoreField: 'deworming_rates',
                    icon: Icons.bug_report_outlined,
                  ),

                  const SizedBox(height: 50),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}