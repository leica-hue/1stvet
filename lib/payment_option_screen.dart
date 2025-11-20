import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart'; // <<< MUST BE IMPORTED

// Defining colors based on the current design theme (Greens and Yellow)
class AppColors {
  static const Color primaryGreen = Color(0xFF6B8E23);
  static const Color secondaryGreen = Color(0xFF728D5A);
  static const Color actionYellow = Color(0xFFEAF086);
  static const Color backgroundLight = Color(0xFFF8F9F5);
  static const Color appBarGreen = Color(0xFFBDD9A4);
  static const Color gcashBlue = Color(0xFF32A0E4);
  static const Color secondaryRed = Color(0xFFB71C1C);
}

// --- Payment Proof Screen (For Manual Verification & Screenshot Upload) ---

class PaymentProofScreen extends StatefulWidget {
  const PaymentProofScreen({super.key});

  @override
  State<PaymentProofScreen> createState() => _PaymentProofScreenState();
}

class _PaymentProofScreenState extends State<PaymentProofScreen> {
  
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _transactionIdController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  Uint8List? _pickedImageBytes;
  String? _imageFileName;
  
  final double _amountDue = 499.00; // Automatically filled amount

  @override
  void initState() {
    super.initState();
    _checkVerificationStatus();
  }

  // Check verification status before allowing payment submission
  Future<void> _checkVerificationStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Please log in to submit payment.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      final verificationDoc = await FirebaseFirestore.instance
          .collection('vet_verifications')
          .doc(user.uid)
          .get();

      if (verificationDoc.exists) {
        final data = verificationDoc.data() ?? {};
        final status = data['status'] ?? '';

        if (status == 'rejected') {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('❌ Your verification was rejected. Please resubmit your ID in Profile.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
          }
          return;
        }

        if (status == 'pending') {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⏳ Your verification is pending. Please wait for admin approval.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 5),
              ),
            );
          }
          return;
        }

        // If approved, allow access
        if (status != 'approved') {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ Please submit your ID for verification first.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 5),
              ),
            );
          }
          return;
        }
      } else {
        // No verification document found
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Please submit your ID for verification first in Profile.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }
    } catch (e) {
      print('Error checking verification: $e');
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Error checking verification: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  // *** NEW: Function to safely get the current Vet ID ***
  String? _getCurrentvetId() {
    // Returns the unique ID of the currently logged-in user (Vet)
    return FirebaseAuth.instance.currentUser?.uid;
  }

  // Validation function for GCash Transaction ID
  String? _validateGCashTransactionId(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'GCash Transaction ID is required';
    }
    
    final trimmedValue = value.trim();
    
    // Only numbers and dashes are allowed
    if (!RegExp(r'^[0-9\-]+$').hasMatch(trimmedValue)) {
      return 'Only numbers and dashes are allowed';
    }
    
    // Remove dashes to check minimum length
    final numbersOnly = trimmedValue.replaceAll('-', '');
    if (numbersOnly.isEmpty) {
      return 'Transaction ID must contain at least one number';
    }
    
    return null; // Valid
  }

  Future<void> _pickScreenshot() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedImageBytes = bytes;
        _imageFileName = pickedFile.name;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("📎 Screenshot attached!"),
          backgroundColor: AppColors.secondaryGreen,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // NOTE: This function now relies on the ID being retrieved inside _submitProof
  Future<String?> _uploadScreenshot(String vetId) async {
    if (_pickedImageBytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ No screenshot selected'),
            backgroundColor: AppColors.secondaryRed,
          ),
        );
      }
      return null;
    }

    final fileExtension = _imageFileName?.split('.').last.toLowerCase() ?? 'jpg';
    final contentType = fileExtension == 'png' ? 'image/png' : 'image/jpeg';

    // Match the Storage rules path: payment_proofs/{vetId}/{fileName}
    final fileName = 'proof_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
    final storageRef = FirebaseStorage.instance
      .ref()
      .child('payment_proofs/$vetId/$fileName');

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⬆️ Uploading to Firebase Storage...')),
        );
      }
      
      final uploadTask = await storageRef.putData(
        _pickedImageBytes!,
        SettableMetadata(contentType: contentType),
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Upload complete: ${uploadTask.state}'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      final imageUrl = await storageRef.getDownloadURL();
      
      // Log successful upload
      print('✅ Screenshot uploaded successfully!');
      print('   Storage path: payment_proofs/$vetId/$fileName');
      print('   Download URL: $imageUrl');
      
      return imageUrl;
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Storage Error: ${e.code} - ${e.message}'),
            backgroundColor: AppColors.secondaryRed,
            duration: const Duration(seconds: 8),
          ),
        );
      }
      print('Firebase Storage Error Code: ${e.code}');
      print('Firebase Storage Error Message: ${e.message}');
      print('Full error: $e');
      return null;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Unexpected error: $e'),
            backgroundColor: AppColors.secondaryRed,
            duration: const Duration(seconds: 6),
          ),
        );
      }
      print('Unexpected upload error: $e');
      return null;
    }
  }

  // *** NEW: Function accepts the dynamically retrieved vetId ***
  Future<DateTime> _calculateNewPremiumUntil(String vetId) async {
    try {
      // Correctly reference the 'vets' collection using the dynamic ID
      final docSnapshot = await FirebaseFirestore.instance
          .collection('vets') 
          .doc(vetId)
          .get();

      if (docSnapshot.exists) {
        final vetData = docSnapshot.data();
        final currentUntilTimestamp = vetData?['premiumUntil'] as Timestamp?;

        DateTime currentUntilDate = currentUntilTimestamp?.toDate() ?? DateTime.now();

        // If premium is still active, extend from expiration date.
        DateTime startOfNewPeriod = currentUntilDate.isAfter(DateTime.now())
            ? currentUntilDate
            : DateTime.now();

        // Add 30 days (1 month)
        return startOfNewPeriod.add(const Duration(days: 30)); 

      } else {
        // Fallback: If document doesn't exist, start 30 days from now.
        return DateTime.now().add(const Duration(days: 30));
      }
    } catch (e) {
      print('Error accessing or calculating premium end date: $e');
      return DateTime.now().add(const Duration(days: 30));
    }
  }

  Future<void> _submitProof() async {
    // Validate form first
    if (!_formKey.currentState!.validate()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please enter a valid GCash Transaction ID."),
            backgroundColor: AppColors.secondaryRed,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // 1. Get Vet ID and perform initial validation
    final String? currentvetId = _getCurrentvetId();
  
    if (currentvetId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Error: Vet ID not found. Please log in again."),
            backgroundColor: AppColors.secondaryRed,
          ),
        );
      }
      return;
    }

    final hasImage = _pickedImageBytes != null;
    if (!hasImage) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please upload a screenshot of your payment."),
            backgroundColor: AppColors.secondaryRed,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Uploading proof...')),
    );
    
    // 2. Upload Screenshot using the fetched ID
    final screenshotUrl = await _uploadScreenshot(currentvetId);

    if (screenshotUrl == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload failed. Check console for details.'),
          backgroundColor: AppColors.secondaryRed,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Screenshot uploaded: ${screenshotUrl.substring(0, 50)}...')),
    );

    try {
      // 3. Calculate New Premium End Date using the fetched ID
      final newPremiumUntil = await _calculateNewPremiumUntil(currentvetId);

      // --- A. Write data to 'payment' collection (Verification record) ---
      final paymentData = {
        'vetId': currentvetId,
        'transactionId': _transactionIdController.text.trim(),
        'notes': _notesController.text.trim(),
        'screenshotUrl': screenshotUrl,
        'amount': _amountDue,
        'status': 'Pending',
        'submissionTime': FieldValue.serverTimestamp(),
        'adminVerifiedBy': '',
        'premiumUntilCalculated': Timestamp.fromDate(newPremiumUntil),
      };
      
      print('📝 Preparing to save payment data to Firestore:');
      print('   vetId: $currentvetId');
      print('   transactionId: ${_transactionIdController.text.trim()}');
      print('   screenshotUrl: $screenshotUrl');
      print('   amount: $_amountDue');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saving to collection: payment (vetId: $currentvetId)'),
          duration: const Duration(seconds: 3),
        ),
      );
      
      final docRef = await FirebaseFirestore.instance.collection('payment').add(paymentData);
      
      print('✅ Payment document created successfully!');
      print('   Document ID: ${docRef.id}');
      print('   Collection: payment');
      print('   Screenshot URL stored: $screenshotUrl');
      
      // Verify the data was saved by reading it back
      final savedDoc = await docRef.get();
      final savedData = savedDoc.data();
      print('📖 Verified saved data:');
      print('   screenshotUrl from Firestore: ${savedData?['screenshotUrl']}');
      print('   vetId from Firestore: ${savedData?['vetId']}');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Payment doc created! ID: ${docRef.id}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );

      // --- B. Update the 'vets' collection (Immediate Activation) ---
      await FirebaseFirestore.instance.collection('vets').doc(currentvetId).set({
        'isPremium': true,
        'premiumSince': FieldValue.serverTimestamp(),
        'premiumUntil': Timestamp.fromDate(newPremiumUntil), 
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));


      // 4. Success Feedback and Navigation
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Payment submitted & Premium activated until ${newPremiumUntil.month}/${newPremiumUntil.day}/${newPremiumUntil.year}!"),
          backgroundColor: AppColors.primaryGreen,
          duration: const Duration(seconds: 4),
        ),
      );
      Navigator.pop(context);

    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Firebase error: ${e.code} - ${e.message}'),
          backgroundColor: AppColors.secondaryRed,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.secondaryRed,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
  // (The rest of the class remains the same...)

  @override
  void dispose() {
    _transactionIdController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text(
          'Submit Payment Details',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        backgroundColor: AppColors.appBarGreen,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 550),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'Please fill in the required details and upload a screenshot of your GCash payment for quick verification.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.black87),
                    ),
                    const SizedBox(height: 30),

                    // 1. Input for GCash Transaction ID
                    TextFormField(
                      controller: _transactionIdController,
                      validator: _validateGCashTransactionId,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: InputDecoration(
                        labelText: 'GCash Transaction ID (Required)',
                        hintText: 'e.g., 20240921-2345-6789 or 2024092123456789',
                        prefixIcon: const Icon(Icons.receipt_long, color: AppColors.gcashBlue),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.secondaryRed, width: 2),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.secondaryRed, width: 2),
                        ),
                        helperText: 'Only numbers and dashes are allowed',
                        helperMaxLines: 2,
                      ),
                    ),
                  const SizedBox(height: 20),

                  // 2. Upload Screenshot Button/Display
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.secondaryGreen.withOpacity(0.5)),
                    ),
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      children: [
                        Text(
                          _pickedImageBytes == null
                              ? 'No Screenshot Attached'
                              : 'Attached File: $_imageFileName',
                          style: TextStyle(
                            fontSize: 14,
                            color: _pickedImageBytes == null
                                ? Colors.redAccent
                                : AppColors.primaryGreen,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _pickScreenshot,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Upload Payment Screenshot'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.secondaryGreen,
                            side: const BorderSide(color: AppColors.secondaryGreen),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // 3. Optional Note
                  TextFormField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Optional: Notes or Reference',
                      hintText: 'Enter name used for payment or other details.',
                      prefixIcon: const Icon(Icons.edit_note, color: AppColors.secondaryGreen),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Submit Button
                  ElevatedButton.icon(
                    onPressed: _submitProof,
                    icon: const Icon(Icons.send, color: Colors.white),
                    label: const Text(
                      'Submit for Verification',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 10,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Your Premium status has been **temporarily activated** until the Admin confirms your payment (which will make it permanent).',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.black54, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
  }
}
// (PaymentOptionScreen remains the same)
// --- Payment Option Screen (Remains unchanged for context) ---

class PaymentOptionScreen extends StatefulWidget {
  const PaymentOptionScreen({super.key});

  @override
  State<PaymentOptionScreen> createState() => _PaymentOptionScreenState();
}

class _PaymentOptionScreenState extends State<PaymentOptionScreen> {
  bool _isCheckingVerification = true;
  bool _isVerified = false;

  static const String adminGCashName = "H. F. P. C.";
  static const String adminGCashNumber = "09995188336";
  static const String amountDue = '₱499.00';
  static const String qrCodeImage = 'assets/GCash-MyQR-13112025232733.PNG.jpg';

  @override
  void initState() {
    super.initState();
    _checkVerificationStatus();
  }

  Future<void> _checkVerificationStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.pop(context);
      }
      return;
    }

    try {
      final verificationDoc = await FirebaseFirestore.instance
          .collection('vet_verifications')
          .doc(user.uid)
          .get();

      if (verificationDoc.exists) {
        final data = verificationDoc.data() ?? {};
        final status = data['status'] ?? '';

        if (status == 'rejected') {
          if (mounted) {
            setState(() {
              _isCheckingVerification = false;
              _isVerified = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('❌ Your verification was rejected. Please resubmit your ID in Profile.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
          }
          return;
        }

        if (status == 'pending') {
          if (mounted) {
            setState(() {
              _isCheckingVerification = false;
              _isVerified = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⏳ Your verification is pending. Please wait for admin approval.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 5),
              ),
            );
          }
          return;
        }

        if (status == 'approved') {
          if (mounted) {
            setState(() {
              _isCheckingVerification = false;
              _isVerified = true;
            });
          }
          return;
        }
      }

      // No verification document found
      if (mounted) {
        setState(() {
          _isCheckingVerification = false;
          _isVerified = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Please submit your ID for verification first in Profile.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      print('Error checking verification: $e');
      if (mounted) {
        setState(() {
          _isCheckingVerification = false;
          _isVerified = false;
        });
      }
    }
  } 

  Widget _buildPremiumBanner() { 
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [AppColors.primaryGreen, AppColors.secondaryGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Column(
        children: [
          Icon(Icons.workspace_premium, color: Colors.white, size: 60),
          SizedBox(height: 15),
          Text(
            'Go Premium: ₱499.00/month',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 10), 
          Text(
            'Unlock all features and get priority vet visibility on every user\'s screen!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: AppColors.actionYellow,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGCashInstructionCard(BuildContext context) { 
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'GCash Payment Details',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondaryGreen,
                  ),
                ),
                const Icon(Icons.payment, size: 45, color: AppColors.gcashBlue),
              ],
            ),
            const Divider(height: 30, thickness: 1.5),

            _buildQrCodeSection(context),
            const Divider(height: 30, thickness: 1.5),

            _buildDetailRow(
              'Amount Due:',
              amountDue,
              Icons.attach_money,
              AppColors.secondaryRed,
              true, 
            ),
            const SizedBox(height: 15),

            _buildDetailRow(
              'OR Pay via:',
              adminGCashNumber,
              Icons.phone_android,
              AppColors.gcashBlue,
              true, 
              onTap: () {
                Clipboard.setData(const ClipboardData(text: adminGCashNumber));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('GCash Number copied to clipboard!'),
                    backgroundColor: AppColors.gcashBlue,
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            ),

            _buildDetailRow(
              'Account Name:',
              adminGCashName,
              Icons.person_pin_circle,
              AppColors.primaryGreen,
              false, 
            ),
            const Divider(height: 30, thickness: 1.5),

            const Text(
              'Action Required: Scan the QR or send the payment, then tap "I Have Paid" below to submit your transaction proof.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.black54, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrCodeSection(BuildContext context) { 
    return Column(
      children: [
        const Text(
          'Option 1: Scan to Pay',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryGreen,
          ),
        ),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.gcashBlue, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppColors.gcashBlue.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          width: 200,
          height: 200,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              qrCodeImage,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Placeholder(
                  fallbackHeight: 200,
                  fallbackWidth: 200,
                  color: AppColors.gcashBlue,
                  strokeWidth: 5.0,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Total: $amountDue',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.secondaryRed,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon, Color color, bool highlightValue, {VoidCallback? onTap}) { 
    Widget content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: highlightValue
                ? BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withOpacity(0.5)),
                  )
                : null,
            child: Text(
              value,
              style: TextStyle(
                fontWeight: highlightValue ? FontWeight.bold : FontWeight.normal,
                color: highlightValue ? color : Colors.black87,
                fontSize: 15,
              ),
            ),
          ),
          if (onTap != null)
            const Padding(
              padding: EdgeInsets.only(left: 8.0),
              child: Icon(Icons.copy, size: 20, color: Colors.black45),
            ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: content,
      );
    }
    return content;
  }

  Widget _buildIHavePaidButton(BuildContext context) { 
    return ElevatedButton.icon(
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const PaymentProofScreen()),
        );
      },
      icon: const Icon(Icons.check_circle_outline, color: Colors.white),
      label: const Text(
        'I Have Paid, Submit Proof',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryGreen,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.actionYellow, 
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 12,
        shadowColor: AppColors.actionYellow.withOpacity(0.8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) { 
    if (_isCheckingVerification) {
      return Scaffold(
        backgroundColor: AppColors.backgroundLight,
        appBar: AppBar(
          title: const Text(
            'Upgrade to Premium',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
          ),
          backgroundColor: AppColors.appBarGreen,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        body: const Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryGreen,
          ),
        ),
      );
    }

    if (!_isVerified) {
      return Scaffold(
        backgroundColor: AppColors.backgroundLight,
        appBar: AppBar(
          title: const Text(
            'Upgrade to Premium',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
          ),
          backgroundColor: AppColors.appBarGreen,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        body: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 550),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.red, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.cancel, color: Colors.red, size: 60),
                          const SizedBox(height: 20),
                          const Text(
                            'Verification Required',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: 15),
                          const Text(
                            'You must be verified before applying for premium. Please submit your ID for verification in your Profile.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 30),
                          ElevatedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Go to Profile'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: 15,
                                horizontal: 24,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text(
          'Upgrade to Premium',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        backgroundColor: AppColors.appBarGreen,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 550),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPremiumBanner(),
                  const SizedBox(height: 30),
                  _buildGCashInstructionCard(context),
                  const SizedBox(height: 40),
                  _buildIHavePaidButton(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
} 
