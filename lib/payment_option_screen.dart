import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Defining colors based on the current design theme (Greens and Yellow)
class AppColors {
  static const Color primaryGreen = Color(0xFF6B8E23); // Darker Green (Banner base)
  static const Color secondaryGreen = Color(0xFF728D5A); // Header/Accent Green
  static const Color actionYellow = Color(0xFFEAF086); // Light Yellow (Action button)
  static const Color backgroundLight = Color(0xFFF8F9F5); // Very light background
  static const Color appBarGreen = Color(0xFFBDD9A4); // App bar background
  static const Color gcashBlue = Color(0xFF32A0E4); // GCash Icon/Pay Now Button Color
}

// Converted back to StatelessWidget as the verification modal and its state are removed.
class PaymentOptionScreen extends StatelessWidget {
  const PaymentOptionScreen({super.key});

  // --- Widget Builders ---

  Widget _buildPremiumBanner() {
    // Enhanced banner with gradient and heavier shadow
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
            // UPDATED: Highlighting vet visibility on every user's screen
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
                // Using a stylized GCash color icon
                const Icon(Icons.payment, size: 45, color: AppColors.gcashBlue),
              ],
            ),
            const Divider(height: 30, thickness: 1.5),

            // Only showing Amount Due
            _buildDetailRow(
              'Amount Due:',
              '₱499.00',
              Icons.attach_money,
              Colors.redAccent,
            ),
            const SizedBox(height: 25),

            const Text(
              // UPDATED: Simple instruction, as verification step is removed
              'Action Required: Tap "Pay Now" to securely open the GCash app and complete your transaction. Your Premium features will be activated immediately upon successful payment.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.black54, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon, Color color) {
    return Padding(
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
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Button to simulate deep link redirection for immediate payment
  Widget _buildPayNowButton(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () {
        // Simulate successful redirection to GCash app/API
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🚀 Redirecting to GCash app to complete payment of ₱499.00..."),
            backgroundColor: AppColors.primaryGreen,
            duration: Duration(seconds: 3),
          ),
        );
        // In a real app, this would use a URL launcher or deep linking library
        // launchUrl(Uri.parse('gcash://pay?amount=499.00&...'));
      },
      icon: const Icon(Icons.send_to_mobile, color: Colors.white),
      label: const Text(
        'Pay Now',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.gcashBlue, // Use GCash Blue for high contrast/trust
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 12,
        shadowColor: AppColors.gcashBlue.withOpacity(0.8),
      ),
    );
  }

  // --- Main Build Method ---

  @override
  Widget build(BuildContext context) {
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
                  const SizedBox(height: 40), // Increased spacing for the single final button
                  _buildPayNowButton(context), // The only action button remaining
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}