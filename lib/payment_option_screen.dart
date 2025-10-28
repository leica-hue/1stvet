import 'package:flutter/material.dart';

class PaymentOptionScreen extends StatefulWidget {
  const PaymentOptionScreen({super.key});

  @override
  State<PaymentOptionScreen> createState() => _PaymentOptionScreenState();
}

class _PaymentOptionScreenState extends State<PaymentOptionScreen> {
  String? selectedPayment; // Track selected payment method

  // Controllers for credit card inputs
  final TextEditingController cardNumberController = TextEditingController();
  final TextEditingController expiryController = TextEditingController();
  final TextEditingController cvvController = TextEditingController();
  final TextEditingController nameController = TextEditingController();

  final double inputHeight = 55; // uniform height for all inputs

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9F5),
      appBar: AppBar(
        title: const Text("Choose Payment Method"),
        backgroundColor: const Color(0xFF728D5A),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Select Your Payment Option",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Please choose your preferred payment method below.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                ),
                const SizedBox(height: 30),

                // GCash Option
                _paymentOption(
                  icon: Icons.phone_iphone,
                  title: "GCash",
                  subtitle: "Pay easily using your GCash wallet",
                  value: "gcash",
                ),
                const SizedBox(height: 15),

                // PayMaya Option
                _paymentOption(
                  icon: Icons.account_balance_wallet,
                  title: "PayMaya",
                  subtitle: "Secure transactions via PayMaya",
                  value: "paymaya",
                ),
                const SizedBox(height: 15),

                // Credit Card Option
                _paymentOption(
                  icon: Icons.credit_card,
                  title: "Credit / Debit Card",
                  subtitle: "Use your Visa or Mastercard securely",
                  value: "card",
                ),

                // Show credit card form when selected
                if (selectedPayment == "card") ...[
                  const SizedBox(height: 20),
                  _buildCreditCardForm(),
                ],

                const SizedBox(height: 40),

                // Proceed Button
                ElevatedButton(
                  onPressed: selectedPayment == null
                      ? null
                      : () {
                          if (selectedPayment == "card") {
                            _validateCardForm(context);
                          } else {
                            _showPaymentDetails(context, selectedPayment!);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEAF086),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 50, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    "Proceed to Payment",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _paymentOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
  }) {
    final bool isSelected = selectedPayment == value;
    return InkWell(
      onTap: () {
        setState(() {
          selectedPayment = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color:
              isSelected ? const Color(0xFFBDD9A4).withOpacity(0.3) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isSelected ? const Color(0xFF728D5A) : const Color(0xFFBDD9A4),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 40, color: const Color(0xFF728D5A)),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style:
                          const TextStyle(fontSize: 14, color: Colors.black54)),
                ],
              ),
            ),
            Radio<String>(
              value: value,
              groupValue: selectedPayment,
              activeColor: const Color(0xFF728D5A),
              onChanged: (newValue) {
                setState(() {
                  selectedPayment = newValue;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreditCardForm() {
    final inputDecoration = InputDecoration(
      labelStyle: const TextStyle(fontSize: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      counterText: "",
    );

    return Column(
      children: [
        SizedBox(
          height: inputHeight,
          child: TextField(
            controller: nameController,
            decoration: inputDecoration.copyWith(labelText: "Cardholder Name"),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: inputHeight,
          child: TextField(
            controller: cardNumberController,
            decoration: inputDecoration.copyWith(labelText: "Card Number"),
            keyboardType: TextInputType.number,
            maxLength: 16,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: inputHeight,
                child: TextField(
                  controller: expiryController,
                  decoration: inputDecoration.copyWith(labelText: "MM/YY"),
                  keyboardType: TextInputType.datetime,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: inputHeight,
                child: TextField(
                  controller: cvvController,
                  decoration: inputDecoration.copyWith(labelText: "CVV"),
                  keyboardType: TextInputType.number,
                  maxLength: 3,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _validateCardForm(BuildContext context) {
    if (cardNumberController.text.isEmpty ||
        expiryController.text.isEmpty ||
        cvvController.text.isEmpty ||
        nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all credit card details.")),
      );
      return;
    }

    _showPaymentDetails(context, "card");
  }

  void _showPaymentDetails(BuildContext context, String paymentType) {
    String paymentTitle;
    String instructions;

    if (paymentType == "gcash") {
      paymentTitle = "GCash Payment";
      instructions =
          "To complete your payment, open your GCash app and send payment to 09XX-XXX-XXXX.";
    } else if (paymentType == "paymaya") {
      paymentTitle = "PayMaya Payment";
      instructions =
          "To complete your payment, open your PayMaya app and send payment to paymaya@sample.com.";
    } else {
      paymentTitle = "Credit / Debit Card";
      instructions =
          "Your card payment will be processed securely. (Simulation only — no real API connected)";
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title:
            Text(paymentTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_2, size: 100, color: Color(0xFF728D5A)),
            const SizedBox(height: 10),
            Text(
              instructions,
              style: const TextStyle(fontSize: 15, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("$paymentTitle initiated successfully.")),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF728D5A),
              foregroundColor: Colors.white,
            ),
            child: const Text("Continue"),
          ),
        ],
      ),
    );
  }
}
