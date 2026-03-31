// File: lib/features/admin/customer_management/presentation/screens/admin_customer_details_screen.dart
// Screen to display detailed information about a specific customer, using CustomerProvider.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // For date formatting
// Import the Customer entity
import 'package:abra_fleet/features/admin/customer_management/domain/entities/customer_entity.dart';
// Import the Provider
import 'package:abra_fleet/features/admin/customer_management/presentation/providers/customer_provider.dart';
// Import the Add/Edit screen to navigate to it
import 'package:abra_fleet/features/admin/customer_management/presentation/screens/admin_add_edit_customer_screen.dart';

class AdminCustomerDetailsScreen extends StatelessWidget {
  final String customerId; // Now takes customerId to fetch the latest from provider

  const AdminCustomerDetailsScreen({super.key, required this.customerId});

  Widget _buildDetailRow(BuildContext context, String label, String? value, {IconData? icon, Color? valueColor}) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
          ] else ...[
            const SizedBox(width: 32), // Placeholder for alignment
          ],
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value ?? 'N/A',
              style: textTheme.bodyLarge?.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active': return Colors.green.shade700;
      case 'suspended': return Colors.orange.shade700;
      case 'inactive': return Colors.red.shade700;
      default: return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final DateFormat dateFormat = DateFormat('MMM dd, yyyy');

    // Use Consumer to get the latest customer details from the provider
    return Consumer<CustomerProvider>(
      builder: (context, customerProvider, child) {
        final CustomerEntity? customer = customerProvider.getCustomerFromListById(customerId);

        if (customerProvider.isLoading && customer == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Loading Customer...')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (customer == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Customer Not Found')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  const Text('Customer details could not be loaded.'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      customerProvider.fetchCustomers().then((_) {
                        if (customerProvider.getCustomerFromListById(customerId) == null && context.mounted) {
                          Navigator.of(context).pop();
                        }
                      });
                    },
                    child: const Text('Retry Load'),
                  )
                ],
              ),
            ),
          );
        }

        // If customer is found, build the details UI
        return Scaffold(
          appBar: AppBar(
            title: Text(customer.name, overflow: TextOverflow.ellipsis),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_note_rounded),
                tooltip: 'Edit Customer',
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AdminAddEditCustomerScreen(customer: customer),
                    ),
                  );
                  if (result != null && context.mounted) {
                    if (result is Map && result['deleted'] == true) {
                      Navigator.pop(context); // Pop details screen if customer was deleted
                    }
                    // If updated, Consumer will rebuild with new data from provider
                  }
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Column(
                    children: [
                      Hero(
                        tag: 'customer_avatar_${customer.id}',
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                          child: Icon(
                            Icons.account_circle_rounded,
                            size: 60,
                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        customer.name,
                        style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Chip(
                        label: Text(
                          customer.status,
                          style: textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        backgroundColor: _getStatusColor(customer.status),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24.0),
                const Divider(),
                _buildDetailRow(context, 'Customer ID:', customer.id, icon: Icons.badge_outlined),
                _buildDetailRow(context, 'Email:', customer.email, icon: Icons.email_outlined),
                _buildDetailRow(context, 'Phone:', customer.phoneNumber, icon: Icons.phone_outlined),
                if (customer.companyName != null && customer.companyName!.isNotEmpty)
                  _buildDetailRow(context, 'Company:', customer.companyName, icon: Icons.business_rounded),
                if (customer.address != null && customer.address!.isNotEmpty)
                  _buildDetailRow(context, 'Address:', customer.address, icon: Icons.location_on_outlined),
                _buildDetailRow(
                    context,
                    'Registered On:',
                    dateFormat.format(customer.registrationDate),
                    icon: Icons.calendar_today_outlined
                ),

                const SizedBox(height: 24.0),
                Text(
                  'Booking History (Placeholder)',
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text('Service Request - ${DateFormat('MMM dd').format(DateTime.now().subtract(const Duration(days: 5)))}'),
                    subtitle: const Text('Vehicle: Sedan Alpha, Status: Completed'),
                    onTap: () {},
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
