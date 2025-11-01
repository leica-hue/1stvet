import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_zoom_sdk/zoom_options.dart';
import 'package:flutter_zoom_sdk/zoom_view.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  bool _isZoomInitialized = false;

  // ⚠️ Replace with your real credentials
  static const String _zoomSdkKey = "Dn_zLL0BS4MRVVoTER9gA";
  static const String _zoomSdkSecret = "SOos3ZEU75jPlZ36CeOxVnzT8e9vRawE";
  static const String _zoomJwtToken = "pGBae5XHR_CZ8TuLU4SUVw";

  late ZoomOptions _zoomOptions;
  late ZoomView _zoom;

  @override
  void initState() {
    super.initState();
    _initZoom();
  }

  Future<void> _initZoom() async {
    try {
      _zoomOptions = ZoomOptions(
        domain: "zoom.us",
        appKey: _zoomSdkKey,
        appSecret: _zoomSdkSecret,
      );

      _zoom = ZoomView();
      var initResultRaw = await _zoom.initZoom(_zoomOptions);

      // Normalize the init result: it may be a Map or a JSON/string
      Map<String, dynamic> initResult;
      if (initResultRaw is String) {
        try {
          initResult = jsonDecode(initResultRaw as String) as Map<String, dynamic>;
        } catch (_) {
          // Fallback: wrap the raw result so we can still inspect it
          initResult = {'result': initResultRaw, 'success': false};
        }
      } else if (initResultRaw is Map) {
        initResult = Map<String, dynamic>.from(initResultRaw as Map);
      } else {
        initResult = {'result': initResultRaw, 'success': false};
      }

      // ✅ Handle all possible return formats (support bool/int/string)
      final resultVal = initResult['result'];
      final success = initResult['success'] == true ||
          initResult['success'] == 0 ||
          initResult['success'] == '0' ||
          resultVal == 0 ||
          resultVal == '0';

      if (success) {
        setState(() => _isZoomInitialized = true);
        debugPrint("✅ Zoom SDK initialized successfully: $initResult");
      } else {
        debugPrint("❌ Zoom SDK initialization failed: $initResult");
        _showSnack("Zoom SDK initialization failed.", Colors.red);
      }
    } catch (e) {
      debugPrint("Exception initializing Zoom SDK: $e");
      _showSnack("Zoom SDK initialization failed.", Colors.red);
    }
  }


  Future<void> _createZoomMeeting() async {
    if (FirebaseAuth.instance.currentUser == null) {
      _showSnack("Please login first.", Colors.orange);
      return;
    }

    if (_zoomJwtToken == "YOUR_VALID_ZOOM_JWT_TOKEN_HERE") {
      _showSnack("Please add your real Zoom JWT token.", Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse("https://api.zoom.us/v2/users/me/meetings"),
        headers: {
          'Authorization': 'Bearer $_zoomJwtToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "topic":
              "Vet Appointment: ${FirebaseAuth.instance.currentUser?.email ?? 'Guest'}",
          "type": 2,
          "password": _passwordController.text.trim(),
          "settings": {
            "join_before_host": false,
            "mute_upon_entry": true,
          }
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final meetingId = data["id"].toString();
        _meetingIdController.text = meetingId;

        _showSnack("✅ Meeting created! ID: $meetingId", Colors.green);
      } else {
        debugPrint("Zoom API Error: ${response.body}");
        _showSnack("Failed to create meeting. Check JWT token or Zoom App setup.", Colors.red);
      }
    } catch (e) {
      _showSnack("Network error while creating meeting.", Colors.red);
      debugPrint("Error creating meeting: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _joinMeeting() async {
    if (!_isZoomInitialized) {
      _showSnack("Zoom SDK not ready yet.", Colors.orange);
      return;
    }

    final meetingId = _meetingIdController.text.trim();
    final password = _passwordController.text.trim();

    if (meetingId.isEmpty || password.isEmpty) {
      _showSnack("Enter Meeting ID and Password.", Colors.orange);
      return;
    }

    try {
      var options = ZoomMeetingOptions(
        userId: FirebaseAuth.instance.currentUser?.displayName ?? 'Client',
        meetingId: meetingId,
        meetingPassword: password,
        disableDialIn: "true",
        disableDrive: "true",
        disableInvite: "true",
        disableShare: "true",
      );

      _zoom.joinMeeting(options);
      debugPrint("✅ Joined meeting: $meetingId");
    } catch (e) {
      _showSnack("Failed to join meeting: $e", Colors.red);
      debugPrint("Error joining meeting: $e");
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
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
        flexibleSpace: Container(decoration: BoxDecoration(gradient: gradient)),
        title: Text(
          _isZoomInitialized ? 'Zoom Ready' : 'Initializing Zoom...',
          style: const TextStyle(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            _inputField(_meetingIdController, "Meeting ID", Icons.numbers),
            const SizedBox(height: 16),
            _inputField(_passwordController, "Meeting Password", Icons.lock,
                obscure: true),
            const SizedBox(height: 30),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createZoomMeeting,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6E8C5E)),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Create Meeting"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _joinMeeting,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF6E8C5E)),
                    ),
                    child: const Text("Join Meeting"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputField(TextEditingController controller, String label, IconData icon,
      {bool obscure = false}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF6E8C5E)),
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
