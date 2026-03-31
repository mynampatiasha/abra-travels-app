// File: lib/features/customer/profile/presentation/screens/customer_profile_screen.dart
// Enhanced screen for Customer to view and manage their profile, with navigation to edit.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/auth/domain/entities/user_entity.dart';
// Import the Customer entity and Provider
import 'package:abra_fleet/features/admin/customer_management/domain/entities/customer_entity.dart';
import 'package:abra_fleet/features/admin/customer_management/presentation/providers/customer_provider.dart';
// Import the Edit Profile Screen
import 'package:abra_fleet/features/customer/profile/presentation/screens/edit_customer_profile_screen.dart';

// Assuming DataState enum is defined in CustomerProvider or a shared location

class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({super.key});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authUser = Provider.of<AuthRepository>(context, listen: false).currentUser;
      if (authUser.isAuthenticated && authUser.role == 'Customer') {
        Provider.of<CustomerProvider>(context, listen: false).fetchCustomers();
      }
    });
  }

  // Method to refresh profile data
  Future<void> _refreshProfile() async {
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
    await customerProvider.fetchCustomers();
  }

  Widget _buildProfileOption(
      BuildContext context, {
        required IconData icon,
        required String title,
        String? subtitle,
        required VoidCallback onTap,
      }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
        onTap: onTap,
      ),
    );
  }

  Widget _buildInfoTile(BuildContext context, {required IconData icon, required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 12),
          Text('$label: ', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyLarge, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final authRepository = Provider.of<AuthRepository>(context, listen: false);
    final UserEntity currentUser = authRepository.currentUser;
    final textTheme = Theme.of(context).textTheme;
    final DateFormat dateFormat = DateFormat('MMM dd, yyyy');

    return Scaffold(
      // AppBar is provided by MainAppShell
      body: Consumer<CustomerProvider>(
        builder: (context, customerProvider, child) {
          final CustomerEntity? customerDetails = customerProvider.getCustomerFromListById(currentUser.id);

          if (customerProvider.isLoading && customerDetails == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (customerDetails == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_search_outlined, size: 60, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text('Could not load your profile details.', style: textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('Please try again later or contact support.', style: textTheme.bodyMedium, textAlign: TextAlign.center,),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => customerProvider.fetchCustomers(),
                    child: const Text('Retry Load'),
                  )
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshProfile,
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: <Widget>[
                Center(
                  child: Column(
                    children: [
                      Hero(
                        tag: 'customer_profile_avatar_${customerDetails.id}',
                        child: CircleAvatar(
                          radius: 55,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Icon(
                            Icons.account_circle,
                            size: 70,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        customerDetails.name,
                        style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        customerDetails.email,
                        style: textTheme.titleMedium?.copyWith(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 8),
                      Chip(
                        avatar: Icon(Icons.verified_user_outlined, size: 16, color: Theme.of(context).colorScheme.secondary),
                        label: Text('Customer Account (${customerDetails.status})', style: textTheme.labelMedium),
                        backgroundColor: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24.0),
                const Divider(),
                const SizedBox(height: 10.0),

                Text('Account Details', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8.0),
                _buildInfoTile(context, icon: Icons.phone_iphone_rounded, label: 'Phone', value: customerDetails.phoneNumber ?? 'Not provided'),
                if (customerDetails.companyName != null && customerDetails.companyName!.isNotEmpty)
                  _buildInfoTile(context, icon: Icons.business_center_rounded, label: 'Company', value: customerDetails.companyName!),
                if (customerDetails.address != null && customerDetails.address!.isNotEmpty)
                  _buildInfoTile(context, icon: Icons.home_work_outlined, label: 'Address', value: customerDetails.address!),
                _buildInfoTile(context, icon: Icons.event_note_rounded, label: 'Member Since', value: dateFormat.format(customerDetails.registrationDate)),

                const SizedBox(height: 24.0),
                const Divider(),
                const SizedBox(height: 10.0),

                _buildProfileOption(
                  context,
                  icon: Icons.edit_attributes_outlined,
                  title: 'Edit Profile',
                  subtitle: 'Update your name, phone, or address',
                  onTap: () async {
                    if (customerDetails != null) {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditCustomerProfileScreen(customer: customerDetails),
                        ),
                      );
                      if (result != null && result is CustomerEntity && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Profile updated!'), backgroundColor: Colors.green),
                        );
                      }
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Could not load profile to edit.'), backgroundColor: Colors.orange)
                        );
                      }
                    }
                  },
                ),
                _buildProfileOption(
                  context,
                  icon: Icons.payment_rounded,
                  title: 'Payment Methods',
                  subtitle: 'Manage your saved payment options',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Navigate to Payment Methods (Placeholder)')),
                    );
                  },
                ),
                _buildProfileOption(
                  context,
                  icon: Icons.notifications_active_outlined,
                  title: 'Notification Preferences',
                  subtitle: 'Control how you receive updates',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Navigate to Notification Settings (Placeholder)')),
                    );
                  },
                ),
                _buildProfileOption(
                  context,
                  icon: Icons.lock_person_outlined,
                  title: 'Change Password',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Navigate to Change Password (Placeholder)')),
                    );
                  },
                ),
                _buildProfileOption(
                  context,
                  icon: Icons.support_agent_rounded,
                  title: 'Help & Support',
                  subtitle: 'FAQ and contact information',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Navigate to Help & Support (Placeholder)')),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
