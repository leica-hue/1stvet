import 'package:flutter/material.dart';
import 'signup_screen.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  final String registeredEmail;
  final String registeredPassword;

  const LoginScreen({
    super.key,
    required this.registeredEmail,
    required this.registeredPassword,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool rememberMe = false;

  InputDecoration _inputDecoration(String label, Icon icon) {
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      prefixIcon: icon,
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
    );
  }

  void _handleLogin() {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields.')),
      );
      return;
    }

    if (email == widget.registeredEmail && password == widget.registeredPassword) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid email or password.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF6E8C5E),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Image.asset(
                'assets/furever2.png',
                height: 100,
              ),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Welcome Back!',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color.fromARGB(221, 14, 51, 26),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: emailController,
                          decoration:
                              _inputDecoration('Email', const Icon(Icons.email)),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: passwordController,
                          obscureText: true,
                          decoration:
                              _inputDecoration('Password', const Icon(Icons.lock)),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: rememberMe,
                                  onChanged: (value) {
                                    setState(() {
                                      rememberMe = value!;
                                    });
                                  },
                                ),
                                const Text("Remember me"),
                              ],
                            ),
                            TextButton(
                              onPressed: () {
                                // TODO: Forgot password logic
                              },
                              child: const Text("Forgot Password?"),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0B3F18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _handleLogin,
                            child: const Text(
                              'Login',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text("Or sign in using"),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: () {
                                // TODO: Facebook login
                              },
                              icon: const Icon(Icons.facebook),
                              color: Colors.blue[800],
                              iconSize: 32,
                            ),
                            const SizedBox(width: 20),
                            IconButton(
                              onPressed: () {
                                // TODO: Google login
                              },
                              icon: Image.asset(
                                'assets/google_icon.png',
                                height: 28,
                                width: 28,
                              ),
                              iconSize: 32,
                              splashRadius: 24,
                            ),
                            const SizedBox(width: 20),
                            IconButton(
                              onPressed: () {
                                // TODO: Twitter/X login
                              },
                              icon: const Icon(Icons.alternate_email),
                              color: Colors.black87,
                              iconSize: 28,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text("Don't have an Account?"),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const SignUpScreen(),
                                  ),
                                );
                              },
                              child: const Text('Sign Up'),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
