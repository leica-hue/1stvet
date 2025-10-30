import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CreateZoomMeetingScreen extends StatefulWidget {
  const CreateZoomMeetingScreen({super.key});

  @override
  State<CreateZoomMeetingScreen> createState() =>
      _CreateZoomMeetingScreenState();
}

class _CreateZoomMeetingScreenState extends State<CreateZoomMeetingScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _meetingIdController = TextEditingController();
  bool _isLoading = false;

  Future<bool> _verifyUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to continue.'),
          backgroundColor: Color(0xFF6E8C5E),
        ),
      );
      return false;
    }
    return true;
  }

  // ✅ Placeholder: Ready for Zoom API integration
  Future<void> _createZoomMeeting() async {
    if (!await _verifyUser()) return;
    setState(() => _isLoading = true);

    try {
      // 🔹 Replace this with your real API call later
      const zoomJWT = "YOUR_ZOOM_JWT_TOKEN_HERE";

      final response = await http.post(
        Uri.parse("https://api.zoom.us/v2/users/me/meetings"),
        headers: {
          'Authorization': 'Bearer $zoomJWT',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "topic": "EchoSpartan Meeting", // You can customize this later
          "type": 2,
          "password": _passwordController.text.trim(),
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Meeting created successfully!'),
            backgroundColor: Color(0xFF6E8C5E),
          ),
        );
        debugPrint('🔗 Join URL: ${data["join_url"]}');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Failed to create meeting (Code: ${response.statusCode})'),
            backgroundColor: const Color(0xFF6E8C5E),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: const Color(0xFF6E8C5E),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ✅ Placeholder for joining
  Future<void> _joinMeeting() async {
    final meetingId = _meetingIdController.text.trim();
    final password = _passwordController.text.trim();

    if (meetingId.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter Meeting ID and Password to join'),
          backgroundColor: Color(0xFF6E8C5E),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Joining meeting: $meetingId (API coming soon)'),
        backgroundColor: const Color(0xFF6E8C5E),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gradient = const LinearGradient(
      colors: [Color(0xFF6E8C5E), Color(0xFFA7C957)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FBF6),
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: gradient),
        ),
        title: const Text(
          'Zoom Meeting Setup',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            width: 370,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(Icons.video_call_rounded,
                    color: Color(0xFF6E8C5E), size: 48),
                const SizedBox(height: 10),
                const Text(
                  "Create or Join a Meeting",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4C7043),
                  ),
                ),
                const SizedBox(height: 25),

                // 🔐 Password
                _buildInputField(
                  _passwordController,
                  "Meeting Password",
                  Icons.lock,
                  obscure: true,
                ),
                const SizedBox(height: 16),

                // 🔢 Meeting ID for Join
                _buildInputField(
                  _meetingIdController,
                  "Meeting ID (for joining)",
                  Icons.numbers,
                ),
                const SizedBox(height: 28),

                // 🌿 Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _createZoomMeeting,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          elevation: 3,
                          backgroundColor: const Color(0xFF6E8C5E),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'Create Meeting',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _joinMeeting,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: Color(0xFF6E8C5E),
                            width: 2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Join Meeting',
                          style: TextStyle(
                            color: Color(0xFF6E8C5E),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType keyboard = TextInputType.text,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF6E8C5E)),
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF6E8C5E)),
        filled: true,
        fillColor: const Color(0xFFF9FCF7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF6E8C5E)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF6E8C5E), width: 2),
        ),
      ),
    );
  }
}
