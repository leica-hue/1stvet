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

  // Services must be added by the vet - no defaults
  final Map<String, dynamic> _defaultRates = {
    'dog_vaccination_rates': {},   // Empty - vet adds their own services
    'cat_vaccination_rates': {},   // Empty - vet adds their own services
    'deworming_rates': {},         // Empty - vet adds their own services
    'custom_services': {},         // Empty - vet adds their own services
  };

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _originalValues = {};
  final Set<String> _savingFields = {};
  bool _hasRemovedDefaults = false; // Flag to ensure we only remove defaults once

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

  // Detect and remove old default services and fixed fees
  Future<void> _removeDefaultServices() async {
    if (_currentVetId == null) return;
    
    final docRef = _firestore.collection(_collectionName).doc(_ratesDocId);
    final docSnapshot = await docRef.get();
    if (!docSnapshot.exists) return;
    
    final data = _convertToMapStringDynamic(docSnapshot.data());
    final Map<String, dynamic> updates = {};
    bool hasChanges = false;
    
    // Remove fixed fees fields
    if (data.containsKey('consultation_fee_php')) {
      updates['consultation_fee_php'] = FieldValue.delete();
      hasChanges = true;
    }
    if (data.containsKey('urgent_surcharge_php')) {
      updates['urgent_surcharge_php'] = FieldValue.delete();
      hasChanges = true;
    }
    
    // Old default service keys to remove
    final defaultServiceKeys = {
      'dog_vaccination_rates': ['puppy_vaccination', 'adult_booster'],
      'cat_vaccination_rates': ['kitten_vaccination', 'adult_booster'],
      'deworming_rates': ['small_pet', 'large_pet'],
    };
    
    // Check and mark default services for removal
    defaultServiceKeys.forEach((category, keys) {
      final categoryData = _convertToMapStringDynamic(data[category]);
      keys.forEach((key) {
        if (categoryData.containsKey(key)) {
          updates['$category.$key'] = FieldValue.delete();
          hasChanges = true;
        }
      });
    });
    
    if (hasChanges) {
      updates['updatedAt'] = FieldValue.serverTimestamp();
      await docRef.update(updates);
    }
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
      elevation: 0.5,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Icon(icon, color: const Color(0xFF728D5A), size: 32),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Colors.black87)),
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
            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _formatServiceName(tierKey),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF728D5A), fontSize: 14),
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
                    decoration: InputDecoration(
                      prefixText: '₱ ',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: Color(0xFF728D5A), width: 1.5),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
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
                              icon: const Icon(Icons.check_circle_outline, color: Color(0xFF728D5A)),
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
      // Polished header (consistent with other screens)
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
            decoration: BoxDecoration(
              color: const Color(0xFFBDD9A4),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: Colors.black87),
                  tooltip: 'Back',
                ),
                const SizedBox(width: 4),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: const Icon(Icons.currency_exchange, color: Color(0xFF728D5A), size: 26),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Service & Pricing Management',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.black),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showAddServiceDialog({}),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Service'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF728D5A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
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
                    
                    // Remove fixed fees from data immediately (don't display them)
                    final cleanedData = Map<String, dynamic>.from(snapshotData);
                    cleanedData.remove('consultation_fee_php');
                    cleanedData.remove('urgent_surcharge_php');
                    final ratesData = cleanedData.isNotEmpty ? cleanedData : _defaultRates;

                    if (snapshotData.isEmpty && snapshot.data?.exists == false) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _firestore.collection(_collectionName).doc(_ratesDocId).set({
                          'vetId': _currentVetId,
                          'dog_vaccination_rates': {},
                          'cat_vaccination_rates': {},
                          'deworming_rates': {},
                          'custom_services': {},
                          'createdAt': FieldValue.serverTimestamp(),
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                      });
                    }

                    // Automatically remove old default services and fixed fees on first load (only once)
                    if (!_hasRemovedDefaults) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _removeDefaultServices().then((_) {
                          _hasRemovedDefaults = true;
                        });
                      });
                    }

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

                    // Check if vet has added any services yet
                    final hasAnyServices = dogVaccinationRates.isNotEmpty ||
                        catVaccinationRates.isNotEmpty ||
                        dewormingRates.isNotEmpty ||
                        customServices.isNotEmpty;

                    return ListView(
                      padding: const EdgeInsets.only(bottom: 80),
                      children: [
                        // Helpful banner for new vets
                        if (!hasAnyServices)
                          Container(
                            margin: const EdgeInsets.all(16.0),
                            padding: const EdgeInsets.all(16.0),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF086),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF728D5A), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, color: Color(0xFF6B8E23), size: 28),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Get Started',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Add your services using the "Add Service" button below.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[800],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                          child: Text('Services',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
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
          ),
        ],
      ),
    );
  }
}
 