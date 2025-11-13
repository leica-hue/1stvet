import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
// Screens referenced by the sidebar
import 'dashboard_screen.dart';
import 'appointments_screen.dart';
import 'profile_screen.dart';
import 'patients_list_screen.dart';
import 'analytics_screen.dart';
import 'feedback_screen.dart';
import 'settings_screen.dart';
import 'PricingManagementScreen.dart';
import 'login_screen.dart';
import 'user_prefs.dart';

/// Common sidebar widget used across all screens
/// Provides consistent navigation and styling
class CommonSidebar extends StatelessWidget {
  final String currentScreen;

  const CommonSidebar({
    super.key,
    required this.currentScreen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: const Color(0xFF728D5A),
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          Image.asset('assets/furever2.png', width: 140),
          const SizedBox(height: 40),
          
          // Main menu items
          _buildSidebarItem(
            context: context,
            icon: Icons.person,
            label: 'Profile',
            selected: currentScreen == 'Profile',
            onTap: () => _navigateToScreen(context, 'Profile'),
          ),
          _buildSidebarItem(
            context: context,
            icon: Icons.dashboard,
            label: 'Dashboard',
            selected: currentScreen == 'Dashboard',
            onTap: () => _navigateToScreen(context, 'Dashboard'),
          ),
          _buildSidebarItem(
            context: context,
            icon: Icons.event,
            label: 'Appointments',
            selected: currentScreen == 'Appointments',
            onTap: () => _navigateToScreen(context, 'Appointments'),
          ),
          _buildSidebarItem(
            context: context,
            icon: Icons.analytics,
            label: 'Analytics',
            selected: currentScreen == 'Analytics',
            onTap: () => _navigateToScreen(context, 'Analytics'),
          ),
          _buildSidebarItem(
            context: context,
            icon: Icons.pets,
            label: 'Patients',
            selected: currentScreen == 'Patients',
            onTap: () => _navigateToScreen(context, 'Patients'),
          ),
          _buildSidebarItem(
            context: context,
            icon: Icons.feedback_outlined,
            label: 'Feedback',
            selected: currentScreen == 'Feedback',
            onTap: () => _navigateToScreen(context, 'Feedback'),
          ),
          
          const Spacer(),
          
          // Bottom menu items
          _buildSidebarItem(
            context: context,
            icon: Icons.price_change_outlined,
            label: 'Pricing',
            selected: currentScreen == 'Pricing',
            onTap: () => _navigateToScreen(context, 'Pricing', replace: false),
          ),
          _buildSidebarItem(
            context: context,
            icon: Icons.settings,
            label: 'Settings',
            selected: currentScreen == 'Settings',
            onTap: () => _navigateToScreen(context, 'Settings', replace: false),
          ),
          _buildSidebarItem(
            context: context,
            icon: Icons.logout,
            label: 'Log out',
            selected: false,
            onTap: () => _handleLogout(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToScreen(BuildContext context, String screenName, {bool replace = true}) {
    // Don't navigate if already on the current screen
    if (currentScreen == screenName) return;

    Widget? screen;
    switch (screenName) {
      case 'Profile':
        screen = const ProfileScreen();
        break;
      case 'Dashboard':
        screen = const DashboardScreen();
        break;
      case 'Appointments':
        screen = AppointmentsPage(appointmentDoc: null);
        break;
      case 'Analytics':
        screen = const AnalyticsScreen();
        break;
      case 'Patients':
        screen = const PatientHistoryScreen();
        break;
      case 'Feedback':
        screen = const VetFeedbackScreen();
        break;
      case 'Settings':
        screen = const SettingsScreen();
        break;
      case 'Pricing':
        screen = const PricingManagementScreen();
        break;
    }

    if (screen != null) {
      if (replace) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => screen!),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => screen!),
        );
      }
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    await UserPrefs.clearLoggedIn();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(registeredEmail: '', registeredPassword: ''),
      ),
      (route) => false,
    );
  }
}


