import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PricingManagementScreen extends StatefulWidget {
  const PricingManagementScreen({super.key});

  @override
  State<PricingManagementScreen> createState() => _PricingManagementScreenState();
}

class _PricingManagementScreenState extends State<PricingManagementScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? _currentVetId;
  String get _collectionName => 'app_settings';

  final Map<String, dynamic> _defaultRates = {
    'consultation_fee_php': 800.00,
    'urgent_surcharge_php': 500.00,
    'dog_vaccination_rates': {
      'puppy_vaccination': 1500.00,
      'adult_booster': 1200.00,
    },
    'cat_vaccination_rates': {
      'kitten_vaccination': 1000.00,
      'adult_booster': 800.00,
    },
    'deworming_rates': {
      'small_pet': 300.00,
      'large_pet': 550.00,
    },
    'custom_services': {},
  };

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _originalValues = {};
  final Set<String> _savingFields = {};

  @override
  void initState() {
    super.initState();
    _currentVetId = _auth.currentUser?.uid;
  }

  @override
  void dispose() {
    _controllers.forEach((key, controller) => controller.dispose());
    super.dispose();
  }

  String get _ratesDocId => 'vet_rates_${_currentVetId ?? "unknown"}';

  Stream<DocumentSnapshot> _getRatesStream() {
    return _firestore.collection(_collectionName).doc(_ratesDocId).snapshots();
  }

  Future<void> _updatePrice(String field, String value) async {
    if (_currentVetId == null) return;

    final double? price = double.tryParse(value);
    if (price == null || price < 0) return;

    setState(() => _savingFields.add(field));

    try {
      final Map<String, dynamic> updateData = field.contains('.')
          ? {field.split('.')[0]: {field.split('.')[1]: price}}
          : {field: price};

      await _firestore
          .collection(_collectionName)
          .doc(_ratesDocId)
          .set({
            'vetId': _currentVetId,
            'updatedAt': FieldValue.serverTimestamp(),
            ...updateData,
          }, SetOptions(merge: true));

      _originalValues[field] = price.toStringAsFixed(2);
    } finally {
      setState(() => _savingFields.remove(field));
    }
  }

  Future<void> _addService(String baseField, String name, double price) async {
    if (_currentVetId == null) return;
    final docRef = _firestore.collection(_collectionName).doc(_ratesDocId);
    
    // Get current document to merge with existing services
    final docSnapshot = await docRef.get();
    final currentData = _convertToMapStringDynamic(docSnapshot.data());
    final existingServices = _convertToMapStringDynamic(currentData[baseField]);
    
    // Add new service to existing services
    existingServices[name] = price;
    
    await docRef.set({
      baseField: existingServices,
      'updatedAt': FieldValue.serverTimestamp(),
      'vetId': _currentVetId,
    }, SetOptions(merge: true));
  }

  Future<void> _removeService(String baseField, String name) async {
    if (_currentVetId == null) return;
    final docRef = _firestore.collection(_collectionName).doc(_ratesDocId);
    await docRef.update({
      '$baseField.$name': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  void _showAddServiceDialog(Map<String, dynamic> rates) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController priceController = TextEditingController();
    String selectedCategory = 'custom_services';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add New Service', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Service Category:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'custom_services',
                      child: Text('Custom Services'),
                    ),
                    DropdownMenuItem(
                      value: 'dog_vaccination_rates',
                      child: Text('Dog Vaccination'),
                    ),
                    DropdownMenuItem(
                      value: 'cat_vaccination_rates',
                      child: Text('Cat Vaccination'),
                    ),
                    DropdownMenuItem(
                      value: 'deworming_rates',
                      child: Text('Deworming'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedCategory = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Service Name',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., X-Ray, Surgery, Grooming',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Price (₱)',
                    border: OutlineInputBorder(),
                    prefixText: '₱ ',
                    hintText: '0.00',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                nameController.dispose();
                priceController.dispose();
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a service name')),
                  );
                  return;
                }

                final price = double.tryParse(priceController.text.trim());
                if (price == null || price < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid price')),
                  );
                  return;
                }

                // Convert name to a valid key (replace spaces with underscores, lowercase)
                final serviceKey = name.toLowerCase().replaceAll(' ', '_').replaceAll(RegExp(r'[^a-z0-9_]'), '');
                
                _addService(selectedCategory, serviceKey, price).then((_) {
                  nameController.dispose();
                  priceController.dispose();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Service "$name" added successfully!'),
                      backgroundColor: const Color(0xFF6B8E23),
                    ),
                  );
                }).catchError((error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Error adding service: $error'),
                      backgroundColor: Colors.red,
                    ),
                  );
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 222, 245, 175),
                foregroundColor: Colors.black87,
              ),
              child: const Text('Add Service'),
            ),
          ],
        ),
      ),
    );
  }


  String _formatPrice(dynamic price) {
    if (price == null) return '0.00';
    if (price is num) return price.toStringAsFixed(2);
    final num? parsed = num.tryParse(price.toString());
    return parsed != null ? parsed.toStringAsFixed(2) : '0.00';
  }

  String _formatServiceName(String key) {
    // Replace underscores with spaces and capitalize each word
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty
            ? ''
            : word[0].toUpperCase() + (word.length > 1 ? word.substring(1).toLowerCase() : ''))
        .join(' ');
  }

  // Helper function to safely convert LinkedMap/dynamic maps to Map<String, dynamic>
  Map<String, dynamic> _convertToMapStringDynamic(dynamic data) {
    if (data == null) return <String, dynamic>{};
    if (data is Map<String, dynamic>) return data;
    
    // Handle LinkedMap or Map<dynamic, dynamic>
    final Map<String, dynamic> result = {};
    if (data is Map) {
      data.forEach((key, value) {
        final String stringKey = key.toString();
        if (value is Map) {
          result[stringKey] = _convertToMapStringDynamic(value);
        } else {
          result[stringKey] = value;
        }
      });
    }
    return result;
  }

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

    final controller = _controllers[firestoreField]!;
    final isSaving = _savingFields.contains(firestoreField);
    final isModified = controller.text != _originalValues[firestoreField];

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isModified ? const Color(0xFFEAF086) : Colors.transparent,
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
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: Colors.black87)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 15),
            SizedBox(
              width: 120,
              child: TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF6B8E23)),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  prefixText: '₱ ',
                  border: InputBorder.none,
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onChanged: (_) => setState(() {}),
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
                          icon: const Icon(Icons.check_circle, color: Color(0xFF6B8E23), size: 28),
                          onPressed: () => _updatePrice(firestoreField, controller.text),
                        )
                      : const SizedBox.shrink()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicServiceTile({
    required String title,
    required String baseFirestoreField,
    required Map<String, dynamic> rates,
    IconData icon = Icons.category_outlined,
  }) {
    final average = rates.isEmpty
        ? 0.0
        : rates.values.fold<double>(0.0, (sum, v) => sum + (v as num).toDouble()) / rates.length;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Icon(icon, color: const Color(0xFF728D5A), size: 32),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: Colors.black87)),
        subtitle: Text('Average Rate: ₱${average.toStringAsFixed(2)}',
            style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        childrenPadding: const EdgeInsets.only(left: 20, right: 20, top: 8, bottom: 12),
        children: rates.entries.map((entry) {
          final tierKey = entry.key;
          final fullField = '$baseFirestoreField.$tierKey';
          final tierPrice = _formatPrice(entry.value);

          if (!_controllers.containsKey(fullField)) {
            _controllers[fullField] = TextEditingController(text: tierPrice);
            _originalValues[fullField] = tierPrice;
          }

          final controller = _controllers[fullField]!;
          final isSaving = _savingFields.contains(fullField);
          final isModified = controller.text != _originalValues[fullField];

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
                    _formatServiceName(tierKey),
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF728D5A), fontSize: 14),
                  ),
                ),
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
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _removeService(baseFirestoreField, tierKey),
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

  @override
  Widget build(BuildContext context) {
    if (_currentVetId == null) {
      return const Scaffold(
        body: Center(child: Text('⚠️ Please log in as a vet to manage your pricing.')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFBDD9A4),
        title: const Text('Service & Pricing Management 💰',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: StreamBuilder<DocumentSnapshot>(
            stream: _getRatesStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF728D5A)));
              }

              if (snapshot.hasError) {
                return Center(child: Text('❌ Error loading rates: ${snapshot.error}'));
              }

              final Map<String, dynamic> snapshotData = _convertToMapStringDynamic(snapshot.data?.data());
              final ratesData = snapshotData.isNotEmpty ? snapshotData : _defaultRates;

              if (snapshotData.isEmpty && snapshot.data?.exists == false) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _firestore.collection(_collectionName).doc(_ratesDocId).set(_defaultRates);
                });
              }

              final consultFee = _formatPrice(ratesData['consultation_fee_php']);
              final urgentSurcharge = _formatPrice(ratesData['urgent_surcharge_php']);

              // Handle migration from old 'vaccination_rates' structure if it exists
              if (ratesData.containsKey('vaccination_rates') && 
                  !ratesData.containsKey('dog_vaccination_rates') && 
                  !ratesData.containsKey('cat_vaccination_rates')) {
                final oldVaccinationRates = _convertToMapStringDynamic(ratesData['vaccination_rates']);
                final Map<String, dynamic> migrationData = {
                  'updatedAt': FieldValue.serverTimestamp(),
                };
                
                // Migrate old data to new structure
                if (oldVaccinationRates.containsKey('dog')) {
                  migrationData['dog_vaccination_rates'] = {'default': oldVaccinationRates['dog']};
                  ratesData['dog_vaccination_rates'] = {'default': oldVaccinationRates['dog']};
                }
                if (oldVaccinationRates.containsKey('cat')) {
                  migrationData['cat_vaccination_rates'] = {'default': oldVaccinationRates['cat']};
                  ratesData['cat_vaccination_rates'] = {'default': oldVaccinationRates['cat']};
                }
                
                // Save migrated data to Firebase
                if (migrationData.length > 1) {
                  _firestore.collection(_collectionName).doc(_ratesDocId).set(migrationData, SetOptions(merge: true));
                }
              }

              final dogVaccinationRates =
                  _convertToMapStringDynamic(ratesData['dog_vaccination_rates'] ?? _defaultRates['dog_vaccination_rates']);
              final catVaccinationRates =
                  _convertToMapStringDynamic(ratesData['cat_vaccination_rates'] ?? _defaultRates['cat_vaccination_rates']);
              final dewormingRates =
                  _convertToMapStringDynamic(ratesData['deworming_rates'] ?? _defaultRates['deworming_rates']);
              final customServices =
                  _convertToMapStringDynamic(ratesData['custom_services'] ?? _defaultRates['custom_services']);

              return ListView(
                padding: const EdgeInsets.only(bottom: 80),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                    child: Text('Fixed Fees',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                  ),
                  _buildPriceInputTile(
                    title: 'Initial Consultation Fee',
                    subtitle: 'Base cost for general appointments.',
                    firestoreField: 'consultation_fee_php',
                    initialValue: consultFee,
                    icon: Icons.monitor_heart_outlined,
                  ),
                  _buildPriceInputTile(
                    title: 'Urgent Care Surcharge',
                    subtitle: 'Added for emergency or after-hours visits.',
                    firestoreField: 'urgent_surcharge_php',
                    initialValue: urgentSurcharge,
                    icon: Icons.warning_amber_rounded,
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 8.0),
                    child: Text('Tiered Services',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                  ),
                  _buildDynamicServiceTile(
                    title: 'Dog Vaccination 🐕',
                    baseFirestoreField: 'dog_vaccination_rates',
                    rates: dogVaccinationRates,
                    icon: Icons.vaccines_outlined,
                  ),
                  _buildDynamicServiceTile(
                    title: 'Cat Vaccination 🐱',
                    baseFirestoreField: 'cat_vaccination_rates',
                    rates: catVaccinationRates,
                    icon: Icons.vaccines_outlined,
                  ),
                  _buildDynamicServiceTile(
                    title: 'Deworming Service',
                    baseFirestoreField: 'deworming_rates',
                    rates: dewormingRates,
                    icon: Icons.bug_report_outlined,
                  ),
                  _buildDynamicServiceTile(
                    title: 'Custom Services',
                    baseFirestoreField: 'custom_services',
                    rates: customServices,
                    icon: Icons.medical_services_outlined,
                  ),
                ],
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Get current rates data from the stream builder context
          // We'll pass empty map as it's not critical for the dialog
          _showAddServiceDialog({});
        },
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('Add Service'),
        backgroundColor: const Color(0xFF6B8E23),
        foregroundColor: const Color.fromARGB(221, 255, 255, 255),
        tooltip: 'Add a new service to your pricing list',
      ),
    );
  }
}
 