import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB0BPUNYKl3JzJxT2SQBQkQ8b3ioWhHsoc',
    appId: '1:154419208249:web:dd77a0f06873a0a0e5ede8',
    messagingSenderId: '154419208249',
    projectId: 'fureverhealthy-admin',
    authDomain: 'fureverhealthy-admin.firebaseapp.com',
    storageBucket: 'fureverhealthy-admin.firebasestorage.app',
    measurementId: 'G-L4N3KBHRMZ',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB0BPUNYKl3JzJxT2SQBQkQ8b3ioWhHsoc',
    appId: '1:154419208249:web:dd77a0f06873a0a0e5ede8',
    messagingSenderId: '154419208249',
    projectId: 'fureverhealthy-admin',
    storageBucket: 'fureverhealthy-admin.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB0BPUNYKl3JzJxT2SQBQkQ8b3ioWhHsoc',
    appId: '1:154419208249:web:dd77a0f06873a0a0e5ede8',
    messagingSenderId: '154419208249',
    projectId: 'fureverhealthy-admin',
    storageBucket: 'fureverhealthy-admin.firebasestorage.app',
    iosBundleId: 'com.example.flutterApplication1',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyB0BPUNYKl3JzJxT2SQBQkQ8b3ioWhHsoc',
    appId: '1:154419208249:web:dd77a0f06873a0a0e5ede8',
    messagingSenderId: '154419208249',
    projectId: 'fureverhealthy-admin',
    storageBucket: 'fureverhealthy-admin.firebasestorage.app',
    iosBundleId: 'com.example.flutterApplication1',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyB0BPUNYKl3JzJxT2SQBQkQ8b3ioWhHsoc',
    appId: '1:154419208249:web:dd77a0f06873a0a0e5ede8',
    messagingSenderId: '154419208249',
    projectId: 'fureverhealthy-admin',
    storageBucket: 'fureverhealthy-admin.firebasestorage.app',
  );
}
