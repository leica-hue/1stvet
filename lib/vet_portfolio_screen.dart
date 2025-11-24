import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'common_sidebar.dart';

class VetPortfolioScreen extends StatefulWidget {
  const VetPortfolioScreen({super.key});

  @override
  State<VetPortfolioScreen> createState() => _VetPortfolioScreenState();
}

class _VetPortfolioScreenState extends State<VetPortfolioScreen> {
  final Color headerColor = const Color(0xFFBDD9A4);
  final Color primaryGreen = const Color(0xFF728D5A);
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Controllers
  final TextEditingController _bioController = TextEditingController();
  
  // Lists for portfolio items
  List<Map<String, String>> _educationList = [];
  List<Map<String, String>> _experienceList = [];
  List<Map<String, String>> _certificationsList = [];
  List<Map<String, String>> _awardsList = [];
  List<Map<String, String>> _publicationsList = [];
  List<Map<String, String>> _membershipsList = [];

  bool _isLoading = true;
  bool _isSaving = false;

  String get _currentUserId => _auth.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _loadPortfolio();
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadPortfolio() async {
    if (_currentUserId.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final doc = await _firestore.collection('vets').doc(_currentUserId).get();
      
      if (doc.exists) {
        final data = doc.data() ?? {};
        final portfolio = data['portfolio'] as Map<String, dynamic>? ?? {};

        setState(() {
          _bioController.text = portfolio['bio'] ?? '';
          
          // Load lists from portfolio
          _educationList = _parseList(portfolio['education'], 'degree', 'institution', 'year');
          _experienceList = _parseList(portfolio['experience'], 'position', 'organization', 'years');
          _certificationsList = _parseList(portfolio['certifications'], 'name', 'issuer', 'year');
          _awardsList = _parseList(portfolio['awards'], 'title', 'organization', 'year');
          _publicationsList = _parseList(portfolio['publications'], 'title', 'journal', 'year');
          _membershipsList = _parseList(portfolio['memberships'], 'organization', 'role', 'year');
        });
      }
    } catch (e) {
      debugPrint('Error loading portfolio: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, String>> _parseList(dynamic data, String field1, String field2, String field3) {
    if (data == null) return [];
    if (data is! List) return [];
    
    return data.map<Map<String, String>>((item) {
      if (item is Map) {
        return {
          field1: item[field1]?.toString() ?? '',
          field2: item[field2]?.toString() ?? '',
          field3: item[field3]?.toString() ?? '',
        };
      }
      return {field1: '', field2: '', field3: ''};
    }).toList();
  }

  Future<void> _savePortfolio() async {
    if (_currentUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to save portfolio')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final portfolioData = {
        'bio': _bioController.text.trim(),
        'education': _educationList.map((e) => {
          'degree': e['degree'] ?? '',
          'institution': e['institution'] ?? '',
          'year': e['year'] ?? '',
        }).toList(),
        'experience': _experienceList.map((e) => {
          'position': e['position'] ?? '',
          'organization': e['organization'] ?? '',
          'years': e['years'] ?? '',
        }).toList(),
        'certifications': _certificationsList.map((e) => {
          'name': e['name'] ?? '',
          'issuer': e['issuer'] ?? '',
          'year': e['year'] ?? '',
        }).toList(),
        'awards': _awardsList.map((e) => {
          'title': e['title'] ?? '',
          'organization': e['organization'] ?? '',
          'year': e['year'] ?? '',
        }).toList(),
        'publications': _publicationsList.map((e) => {
          'title': e['title'] ?? '',
          'journal': e['journal'] ?? '',
          'year': e['year'] ?? '',
        }).toList(),
        'memberships': _membershipsList.map((e) => {
          'organization': e['organization'] ?? '',
          'role': e['role'] ?? '',
          'year': e['year'] ?? '',
        }).toList(),
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('vets').doc(_currentUserId).update({
        'portfolio': portfolioData,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Portfolio saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('Error saving portfolio: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving portfolio: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _addEducation() {
    _showAddDialog(
      title: 'Add Veterinary Education',
      fields: ['Veterinary Degree/Certification', 'Veterinary School/University', 'Year'],
      onSave: (values) {
        setState(() {
          _educationList.add({
            'degree': values[0],
            'institution': values[1],
            'year': values[2],
          });
        });
      },
    );
  }

  void _addExperience() {
    _showAddDialog(
      title: 'Add Veterinary Experience',
      fields: ['Veterinary Position', 'Clinic/Hospital Name', 'Years of Experience'],
      onSave: (values) {
        setState(() {
          _experienceList.add({
            'position': values[0],
            'organization': values[1],
            'years': values[2],
          });
        });
      },
    );
  }

  void _addCertification() {
    _showAddDialog(
      title: 'Add Veterinary Certification',
      fields: ['Veterinary Certification Name', 'Issuing Organization', 'Year'],
      onSave: (values) {
        setState(() {
          _certificationsList.add({
            'name': values[0],
            'issuer': values[1],
            'year': values[2],
          });
        });
      },
    );
  }

  void _addAward() {
    _showAddDialog(
      title: 'Add Veterinary Award',
      fields: ['Veterinary Award Title', 'Awarding Organization', 'Year'],
      onSave: (values) {
        setState(() {
          _awardsList.add({
            'title': values[0],
            'organization': values[1],
            'year': values[2],
          });
        });
      },
    );
  }

  void _addPublication() {
    _showAddDialog(
      title: 'Add Veterinary Publication',
      fields: ['Publication Title', 'Veterinary Journal/Publisher', 'Year'],
      onSave: (values) {
        setState(() {
          _publicationsList.add({
            'title': values[0],
            'journal': values[1],
            'year': values[2],
          });
        });
      },
    );
  }

  void _addMembership() {
    _showAddDialog(
      title: 'Add Veterinary Professional Membership',
      fields: ['Veterinary Organization', 'Role/Position', 'Year Joined'],
      onSave: (values) {
        setState(() {
          _membershipsList.add({
            'organization': values[0],
            'role': values[1],
            'year': values[2],
          });
        });
      },
    );
  }

  void _showAddDialog({
    required String title,
    required List<String> fields,
    required Function(List<String>) onSave,
  }) {
    final controllers = fields.map((_) => TextEditingController()).toList();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < fields.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: controllers[i],
                    decoration: InputDecoration(
                      labelText: fields[i],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              for (var controller in controllers) {
                controller.dispose();
              }
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final values = controllers.map((c) => c.text.trim()).toList();
              for (var controller in controllers) {
                controller.dispose();
              }
              Navigator.pop(context);
              onSave(values);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _editItem(List<Map<String, String>> list, int index, List<String> fieldLabels, List<String> keys) {
    final item = list[index];
    final controllers = keys.map((key) {
      return TextEditingController(text: item[key] ?? '');
    }).toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < fieldLabels.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: controllers[i],
                    decoration: InputDecoration(
                      labelText: fieldLabels[i],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              for (var controller in controllers) {
                controller.dispose();
              }
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                for (int i = 0; i < keys.length; i++) {
                  list[index][keys[i]] = controllers[i].text.trim();
                }
              });
              for (var controller in controllers) {
                controller.dispose();
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _removeItem(List list, int index) {
    setState(() {
      list.removeAt(index);
    });
  }

  Widget _buildListSection({
    required String title,
    required IconData icon,
    required List<Map<String, String>> items,
    required List<String> fieldLabels,
    required VoidCallback onAdd,
    required Function(int) onEdit,
    required Function(int) onRemove,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: primaryGreen, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onAdd,
                  icon: Icon(Icons.add_circle, color: primaryGreen),
                  tooltip: 'Add $title',
                ),
              ],
            ),
            const Divider(),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No $title added yet',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            else
              ...items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: Colors.grey.shade50,
                  child: ListTile(
                    title: Text(
                      item.values.first,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      item.values.skip(1).join(' • '),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () => onEdit(index),
                          color: primaryGreen,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 20),
                          onPressed: () => onRemove(index),
                          color: Colors.red,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (_auth.currentUser == null) {
      return Scaffold(
        body: Center(
          child: Text(
            "Please log in to view portfolio",
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[700]),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CommonSidebar(currentScreen: 'Portfolio'),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 20, 20, 14),
                  decoration: BoxDecoration(
                    color: headerColor,
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
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: Icon(Icons.work_outline, color: primaryGreen, size: 26),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        "Vet Portfolio",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _isSaving ? null : _savePortfolio,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save),
                        label: Text(_isSaving ? 'Saving...' : 'Save Portfolio'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Bio Section
                              Card(
                                margin: const EdgeInsets.only(bottom: 16),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.description, color: primaryGreen, size: 24),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Veterinary Professional Bio',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(),
                                      TextField(
                                        controller: _bioController,
                                        maxLines: 6,
                                        decoration: InputDecoration(
                                          hintText: 'Share your veterinary background, areas of expertise (e.g., small animals, exotics, surgery), years of practice, and what drives your passion for animal care...',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          filled: true,
                                          fillColor: Colors.grey.shade50,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Education
                              _buildListSection(
                                title: 'Veterinary Education',
                                icon: Icons.school,
                                items: _educationList,
                                fieldLabels: ['Veterinary Degree/Certification', 'Veterinary School/University', 'Year'],
                                onAdd: _addEducation,
                                onEdit: (index) => _editItem(_educationList, index, ['Veterinary Degree/Certification', 'Veterinary School/University', 'Year'], ['degree', 'institution', 'year']),
                                onRemove: (index) => _removeItem(_educationList, index),
                              ),

                              // Experience
                              _buildListSection(
                                title: 'Veterinary Experience',
                                icon: Icons.work,
                                items: _experienceList,
                                fieldLabels: ['Veterinary Position', 'Clinic/Hospital Name', 'Years of Experience'],
                                onAdd: _addExperience,
                                onEdit: (index) => _editItem(_experienceList, index, ['Veterinary Position', 'Clinic/Hospital Name', 'Years of Experience'], ['position', 'organization', 'years']),
                                onRemove: (index) => _removeItem(_experienceList, index),
                              ),

                              // Certifications
                              _buildListSection(
                                title: 'Veterinary Certifications',
                                icon: Icons.verified,
                                items: _certificationsList,
                                fieldLabels: ['Veterinary Certification Name', 'Issuing Organization', 'Year'],
                                onAdd: _addCertification,
                                onEdit: (index) => _editItem(_certificationsList, index, ['Veterinary Certification Name', 'Issuing Organization', 'Year'], ['name', 'issuer', 'year']),
                                onRemove: (index) => _removeItem(_certificationsList, index),
                              ),

                              // Awards
                              _buildListSection(
                                title: 'Veterinary Awards & Recognition',
                                icon: Icons.emoji_events,
                                items: _awardsList,
                                fieldLabels: ['Veterinary Award Title', 'Awarding Organization', 'Year'],
                                onAdd: _addAward,
                                onEdit: (index) => _editItem(_awardsList, index, ['Veterinary Award Title', 'Awarding Organization', 'Year'], ['title', 'organization', 'year']),
                                onRemove: (index) => _removeItem(_awardsList, index),
                              ),

                              // Publications
                              _buildListSection(
                                title: 'Veterinary Publications',
                                icon: Icons.article,
                                items: _publicationsList,
                                fieldLabels: ['Publication Title', 'Veterinary Journal/Publisher', 'Year'],
                                onAdd: _addPublication,
                                onEdit: (index) => _editItem(_publicationsList, index, ['Publication Title', 'Veterinary Journal/Publisher', 'Year'], ['title', 'journal', 'year']),
                                onRemove: (index) => _removeItem(_publicationsList, index),
                              ),

                              // Memberships
                              _buildListSection(
                                title: 'Veterinary Professional Memberships',
                                icon: Icons.groups,
                                items: _membershipsList,
                                fieldLabels: ['Veterinary Organization', 'Role/Position', 'Year Joined'],
                                onAdd: _addMembership,
                                onEdit: (index) => _editItem(_membershipsList, index, ['Veterinary Organization', 'Role/Position', 'Year Joined'], ['organization', 'role', 'year']),
                                onRemove: (index) => _removeItem(_membershipsList, index),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

