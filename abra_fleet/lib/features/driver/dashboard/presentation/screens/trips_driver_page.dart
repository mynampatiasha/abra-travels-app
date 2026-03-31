// lib/features/driver/dashboard/presentation/screens/trips_driver_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/auth/presentation/screens/welcome_screen.dart';
import 'package:abra_fleet/features/driver/dashboard/presentation/screens/driver_individual_trips.dart';
// ✅ IMPORT DRIVER NOTIFICATIONS SCREEN
import 'package:abra_fleet/features/notifications/presentation/screens/driver_notifications_screen.dart';

// --- UI Constants - Matching the Dashboard ---
const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kScaffoldBackgroundColor = Color(0xFFF1F5F9);
const Color kCardBackgroundColor = Colors.white;
const Color kPrimaryTextColor = Color(0xFF1E293B);
const Color kSecondaryTextColor = Color(0xFF64748B);

class TripsDriverPage extends StatelessWidget {
  const TripsDriverPage({Key? key}) : super(key: key);

  Future<void> _handleLogout(BuildContext context) async {
    final authRepository = Provider.of<AuthRepository>(context, listen: false);
    final confirmLogout = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Confirm Logout'),
              content: const Text('Are you sure you want to log out?'),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Logout')),
              ],
            ));
    if (confirmLogout == true && context.mounted) {
      await authRepository.signOut();
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const WelcomeScreen()), (Route<dynamic> route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kScaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('My Trips', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: kPrimaryColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications, color: Colors.white),
            tooltip: 'Notifications',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DriverNotificationsScreen(),
                ),
              );
            },
          ),
          IconButton(icon: const Icon(Icons.logout, color: Colors.white), tooltip: 'Logout', onPressed: () => _handleLogout(context)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAdminCreatedTripsCard(context),
          ],
        ),
      ),
    );
  }

  // --- Reusable Widgets ---
  Widget _buildCard({required String title, required Widget child, IconData? icon}) {
    return Card(
      elevation: 2.0,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      color: kCardBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (icon != null) Icon(icon, color: kPrimaryTextColor, size: 22),
              if (icon != null) const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: kPrimaryTextColor)),
            ],),
            const SizedBox(height: 15.0),
            child,
          ],
        ),
      ),
    );
  }
  
  Widget _buildStyledButton({required VoidCallback onPressed, required String text, required Color backgroundColor, IconData? icon}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 18),
        label: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
          elevation: 2,
        ),
      ),
    );
  }
  
  // --- Page Sections ---
  Widget _buildAdminCreatedTripsCard(BuildContext context) {
    return _buildCard(
      title: 'Admin Created Trips',
      icon: Icons.admin_panel_settings,
      child: Column(
        children: [
          const Text(
            'View and manage trips created by admin. Accept or decline trip requests.',
            style: TextStyle(color: kSecondaryTextColor, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _buildStyledButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DriverIndividualTripsScreen(),
                ),
              );
            },
            text: 'View Admin Created Trips',
            icon: Icons.arrow_forward,
            backgroundColor: kPrimaryColor,
          ),
        ],
      ),
    );
  }
}