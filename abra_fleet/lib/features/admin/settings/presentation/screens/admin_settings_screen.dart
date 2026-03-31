// File: lib/features/admin/settings/presentation/screens/admin_settings_screen.dart
// Enhanced placeholder screen for Admin settings.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/auth/presentation/screens/welcome_screen.dart'; // For logout navigation

class AdminSettingsScreen extends StatelessWidget {
  const AdminSettingsScreen({super.key});

  Widget _buildSettingsCategoryHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0, left: 8.0, right: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildSettingsOptionTile(
      BuildContext context, {
        required IconData icon,
        required String title,
        String? subtitle,
        VoidCallback? onTap,
        Widget? trailing,
      }) {
    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.symmetric(vertical: 5.0, horizontal: 4.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.secondary, size: 26),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: trailing ?? (onTap != null ? const Icon(Icons.arrow_forward_ios_rounded, size: 16) : null),
        onTap: onTap ?? () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$title tapped (Placeholder)')),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authRepository = Provider.of<AuthRepository>(context, listen: false);
    final currentUser = authRepository.currentUser; // For displaying user info

    return Scaffold(
      // AppBar is provided by MainAppShell
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: <Widget>[
          // User Profile Section (Simplified)
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 45,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(
                    Icons.admin_panel_settings_rounded,
                    size: 50,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  currentUser.name ?? 'Admin User',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  currentUser.email ?? 'admin@example.com',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),

          _buildSettingsCategoryHeader(context, 'Account'),
          _buildSettingsOptionTile(
              context,
              icon: Icons.manage_accounts_rounded,
              title: 'Edit Profile',
              subtitle: 'Update your personal information',
              onTap: () { /* TODO: Navigate to Admin Edit Profile Screen */ }
          ),
          _buildSettingsOptionTile(
              context,
              icon: Icons.lock_reset_rounded,
              title: 'Change Password',
              onTap: () { /* TODO: Navigate to Change Password Screen */ }
          ),

          _buildSettingsCategoryHeader(context, 'Application'),
          _buildSettingsOptionTile(
              context,
              icon: Icons.notifications_active_outlined,
              title: 'Notification Preferences',
              subtitle: 'Manage how you receive alerts',
              onTap: () { /* TODO: Navigate to Notification Settings */ }
          ),
          _buildSettingsOptionTile(
            context,
            icon: Icons.color_lens_outlined,
            title: 'Appearance',
            subtitle: 'Customize theme (e.g., Dark Mode)',
            trailing: Switch( // Example of a different trailing widget
              value: Theme.of(context).brightness == Brightness.dark, // Placeholder
              onChanged: (bool value) {
                // TODO: Implement theme switching logic
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Dark Mode toggle (Placeholder - ${value ? "ON" : "OFF"})')),
                );
              },
            ),
            onTap: null, // onTap is handled by the Switch in this case
          ),
          _buildSettingsOptionTile(
              context,
              icon: Icons.language_rounded,
              title: 'Language',
              subtitle: 'English (US)', // Placeholder
              onTap: () { /* TODO: Navigate to Language Selection */ }
          ),

          _buildSettingsCategoryHeader(context, 'System & Legal'),
          _buildSettingsOptionTile(
              context,
              icon: Icons.business_center_outlined,
              title: 'Organization Settings',
              subtitle: 'Manage fleet-wide configurations',
              onTap: () { /* TODO: Navigate to Organization Settings */ }
          ),
          _buildSettingsOptionTile(
              context,
              icon: Icons.info_outline_rounded,
              title: 'About Abra Travels',
              subtitle: 'Version, licenses, and terms',
              onTap: () { /* TODO: Navigate to About Screen */ }
          ),
          _buildSettingsOptionTile(
              context,
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              onTap: () { /* TODO: Open Privacy Policy URL */ }
          ),

          const SizedBox(height: 24.0),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              label: const Text('Logout', style: TextStyle(color: Colors.redAccent)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                await authRepository.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                        (Route<dynamic> route) => false,
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 20.0),
        ],
      ),
    );
  }
}
