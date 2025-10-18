// user_prefs.dart
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class UserPrefsKeys {
  static const name = 'name';
  static const location = 'location';
  static const email = 'email';
  static const specialization = 'specialization';
  static const profileImage = 'profileImage';

  static const avgRating = 'avgRating';
  static const ratingCount = 'ratingCount';
  static const selectedRating = 'selectedRating';

  static const loggedInEmail = 'loggedInEmail';
  static const isLoggedIn = 'isLoggedIn';
}

class UserPrefs {
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
      name: prefs.getString(UserPrefsKeys.name) ?? 'Dr. Sarah Doe',
      location: prefs.getString(UserPrefsKeys.location) ?? 'Marawoy, Lipa City, Batangas',
      email: prefs.getString(UserPrefsKeys.email) ?? 'sarah@vetclinic.com',
      specialization: prefs.getString(UserPrefsKeys.specialization) ?? 'Pathology',
      profileImage: (imagePath != null && File(imagePath).existsSync()) ? File(imagePath) : null,
    );
  }

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

  static Future<({double avg, int count, int selected})> loadRatings() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      avg: prefs.getDouble(UserPrefsKeys.avgRating) ?? 4.9,
      count: prefs.getInt(UserPrefsKeys.ratingCount) ?? 121,
      selected: prefs.getInt(UserPrefsKeys.selectedRating) ?? 0,
    );
  }

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
}
