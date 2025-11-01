import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'firebase_options.dart';
import 'login_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FacebookAuth.instance.webAndDesktopInitialize(
  appId: "1574236717087823", // Replace with your Facebook App ID
  cookie: true,
  xfbml: true,
  version: "v19.0",
);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Furever Healthy',
      theme: ThemeData(
        fontFamily: 'Inter',
        primarySwatch: Colors.green,
      ),
      home: const LoginScreen(
        registeredEmail: '',
        registeredPassword: '',
      ),
    );
  }
}
