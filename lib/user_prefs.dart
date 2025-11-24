// user_prefs.dart
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class UserPrefsKeys {
  // Profile data
  static const name = 'name';
  static const location = 'location';
  static const email = 'email';
  static const specialization = 'specialization';
  static const profileImage = 'profileImage';

  // Ratings
  static const avgRating = 'avgRating';
  static const ratingCount = 'ratingCount';
  static const selectedRating = 'selectedRating';

  // Login state
  static const loggedInEmail = 'loggedInEmail';
  static const isLoggedIn = 'isLoggedIn';

  // Verification
  static const isVerified = 'isVerified';
  static const verificationIDPath = 'verificationIDPath';
}

class UserPrefs {
  // ✅ Save basic profile data
  static Future<void> saveProfile({
    required String name,
    required String location,
    required String email,
    required String specialization,
    String? profileImagePath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(UserPrefsKeys.name, name);
    await prefs.setString(UserPrefsKeys.location, location);
    await prefs.setString(UserPrefsKeys.email, email);
    await prefs.setString(UserPrefsKeys.specialization, specialization);

    if (profileImagePath != null && File(profileImagePath).existsSync()) {
      await prefs.setString(UserPrefsKeys.profileImage, profileImagePath);
    }
  }

  // ✅ Load profile data
  static Future<({
    String name,
    String location,
    String email,
    String specialization,
    File? profileImage
  })> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final imagePath = prefs.getString(UserPrefsKeys.profileImage);

    return (
      name: prefs.getString(UserPrefsKeys.name) ?? '',
      location: prefs.getString(UserPrefsKeys.location) ?? '',
      email: prefs.getString(UserPrefsKeys.email) ?? '',
      specialization: prefs.getString(UserPrefsKeys.specialization) ?? '',
      profileImage:
          (imagePath != null && File(imagePath).existsSync()) ? File(imagePath) : null,
    );
  }

  // ✅ Save rating information
  static Future<void> saveRatings({
    required double avg,
    required int count,
    required int selected,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(UserPrefsKeys.avgRating, avg);
    await prefs.setInt(UserPrefsKeys.ratingCount, count);
    await prefs.setInt(UserPrefsKeys.selectedRating, selected);
  }

  // ✅ Load ratings
  static Future<({double avg, int count, int selected})> loadRatings() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      avg: prefs.getDouble(UserPrefsKeys.avgRating) ?? 4.9,
      count: prefs.getInt(UserPrefsKeys.ratingCount) ?? 121,
      selected: prefs.getInt(UserPrefsKeys.selectedRating) ?? 0,
    );
  }

  // ✅ Manage login state
  static Future<void> setLoggedIn({required String email}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserPrefsKeys.isLoggedIn, true);
    await prefs.setString(UserPrefsKeys.loggedInEmail, email);
  }

  static Future<void> clearLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserPrefsKeys.isLoggedIn, false);
    await prefs.remove(UserPrefsKeys.loggedInEmail);
  }

  // ✅ Save verification data
  static Future<void> saveVerification({
    required bool isVerified,
    String? verificationIDPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserPrefsKeys.isVerified, isVerified);
    if (verificationIDPath != null && File(verificationIDPath).existsSync()) {
      await prefs.setString(UserPrefsKeys.verificationIDPath, verificationIDPath);
    }
  }

  // ✅ Load verification status and ID
  static Future<({bool isVerified, File? verificationID})> loadVerification() async {
    final prefs = await SharedPreferences.getInstance();
    final idPath = prefs.getString(UserPrefsKeys.verificationIDPath);

    return (
      isVerified: prefs.getBool(UserPrefsKeys.isVerified) ?? false,
      verificationID:
          (idPath != null && File(idPath).existsSync()) ? File(idPath) : null,
    );
  }

  // ✅ Clear all saved data (optional utility)
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
