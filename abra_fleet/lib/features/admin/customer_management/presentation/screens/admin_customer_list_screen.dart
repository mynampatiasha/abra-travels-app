// File: lib/features/admin/customer_management/presentation/screens/admin_customer_list_screen.dart
// Screen for Admin to view and manage list of customers, with navigation to Add/Edit and Details screens.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // For date formatting

// Import the Customer entity
import 'package:abra_fleet/features/admin/customer_management/domain/entities/customer_entity.dart';
// Import the Provider
import 'package:abra_fleet/features/admin/customer_management/presentation/providers/customer_provider.dart';
// Import the Add/Edit screen
import 'package:abra_fleet/features/admin/customer_management/presentation/screens/admin_add_edit_customer_screen.dart';
// Import the Details screen
import 'package:abra_fleet/features/admin/customer_management/presentation/screens/admin_customer_details_screen.dart';

class AdminCustomerListScreen extends StatefulWidget {
  const AdminCustomerListScreen({super.key});

  @override
  State<AdminCustomerListScreen> createState() => _AdminCustomerListScreenState();
}

class _AdminCustomerListScreenState extends State<AdminCustomerListScreen> {
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CustomerProvider>(context, listen: false).fetchCustomers();
    });
  }

  List<CustomerEntity> _getFilteredCustomers(List<CustomerEntity> allCustomers) {
    if (_searchTerm.isEmpty) {
      return allCustomers;
    }
    return allCustomers
        .where((customer) =>
    customer.name.toLowerCase().contains(_searchTerm.toLowerCase()) ||
        customer.email.toLowerCase().contains(_searchTerm.toLowerCase()) ||
        (customer.companyName?.toLowerCase().contains(_searchTerm.toLowerCase()) ?? false))
        .toList();
  }

  void _onSearchChanged(String searchTerm) {
    setState(() {
      _searchTerm = searchTerm;
    });
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active': return Colors.green.shade700;
      case 'suspended': return Colors.orange.shade700;
      case 'inactive': return Colors.red.shade700;
      default: return Colors.grey.shade700;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'active': return Icons.check_circle_outline_rounded;
      case 'suspended': return Icons.pause_circle_outline_rounded;
      case 'inactive': return Icons.remove_circle_outline_rounded;
      default: return Icons.help_outline_rounded;
    }
  }

  void _navigateToAddCustomer(BuildContext context) async {
  final result = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => const AdminAddEditCustomerScreen(),
    ),
  );

  // Refresh the customer list when returning from the add screen
  if (result == true && mounted) {
    await Provider.of<CustomerProvider>(context, listen: false).fetchCustomers();
  }
}
  void _navigateToCustomerDetails(BuildContext context, CustomerEntity customer) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminCustomerDetailsScreen(customerId: customer.id),
      ),
    );
  }

  // Replace the _navigateToAddEditScreen method in admin_customer_list_screen.dart
// Lines 98-135

// Method 2: _navigateToAddEditScreen (lines ~98-135) - REPLACE ENTIRELY
void _navigateToAddEditScreen(BuildContext context, {CustomerEntity? customer}) async {
  final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
  final scaffoldMessenger = ScaffoldMessenger.of(context);

  final result = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => AdminAddEditCustomerScreen(customer: customer),
    ),
  );

  if (result != null && mounted) {
    bool success = false;
    String message = '';

    if (result is CustomerEntity) {
      // This is an update operation (customer was passed in)
      if (customer != null) {
        success = await customerProvider.updateCustomer(result);
        message = success ? 'Customer "${result.name}" updated.' : 'Failed to update customer.';
      } else {
        // This shouldn't happen - new customers go through _navigateToAddCustomer
        message = 'Error: Invalid customer creation flow.';
        success = false;
      }
    } else if (result is Map && result['deleted'] == true && result['id'] != null) {
      success = await customerProvider.deleteCustomer(result['id']);
      message = success ? 'Customer deleted.' : 'Failed to delete customer.';
    } else if (result == true) {
      // Just a success indicator, refresh the list
      await customerProvider.fetchCustomers();
      return; // Don't show a message
    }

    if (message.isNotEmpty) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            message + (customerProvider.errorMessage != null 
              ? " Error: ${customerProvider.errorMessage}" 
              : "")
          ),
          backgroundColor: success 
            ? (result is Map && result['deleted'] == true ? Colors.blueAccent : Colors.green) 
            : Colors.redAccent,
        ),
      );
    }
  }
}

  // Method 3: _navigateToDetailsScreen (lines ~137-165) - NO CHANGES NEEDED, but here's the corrected version
void _navigateToDetailsScreen(BuildContext context, CustomerEntity customer) async {
  final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
  final scaffoldMessenger = ScaffoldMessenger.of(context);

  final resultFromDetails = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => AdminCustomerDetailsScreen(customerId: customer.id),
    ),
  );

  if (resultFromDetails != null && mounted) {
    bool success = false;
    String message = '';
    
    if (resultFromDetails is Map && resultFromDetails['deleted'] == true && resultFromDetails['id'] != null) {
      success = await customerProvider.deleteCustomer(resultFromDetails['id']);
      message = success ? 'Customer deleted from details.' : 'Failed to delete customer.';
    } else if (resultFromDetails is CustomerEntity) {
      success = await customerProvider.updateCustomer(resultFromDetails);
      message = success ? 'Customer "${resultFromDetails.name}" updated from details.' : 'Failed to update customer.';
    } else if (resultFromDetails == true) {
      // Just refresh
      await customerProvider.fetchCustomers();
      return;
    }
    
    if (message.isNotEmpty) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            message + (customerProvider.errorMessage != null 
              ? " Error: ${customerProvider.errorMessage}" 
              : "")
          ),
          backgroundColor: success ? Colors.blueAccent : Colors.redAccent,
        ),
      );
    }
  }
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => Provider.of<CustomerProvider>(context, listen: false).fetchCustomers(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: "add_customer_fab",
        onPressed: () => _navigateToAddCustomer(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Customer'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search customers...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
                filled: true,
                fillColor: Theme.of(context).cardColor,
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: Consumer<CustomerProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading && provider.customers.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (provider.errorMessage != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(provider.errorMessage!),
                        TextButton(
                          onPressed: provider.fetchCustomers,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final filteredCustomers = _getFilteredCustomers(provider.customers);

                if (filteredCustomers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          _searchTerm.isEmpty
                              ? 'No customers found.\nTap + to add a new customer.'
                              : 'No customers match your search.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: filteredCustomers.length,
                  itemBuilder: (context, index) {
                    final customer = filteredCustomers[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: ListTile(
                        leading: Hero(
                          tag: 'customer_avatar_${customer.id}',
                          child: CircleAvatar(
                            backgroundColor: _getStatusColor(customer.status).withOpacity(0.15),
                            child: Icon(_getStatusIcon(customer.status), color: _getStatusColor(customer.status), size: 24),
                          ),
                        ),
                        title: Text(
                          customer.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer.email,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            if (customer.companyName != null && customer.companyName!.isNotEmpty)
                              Text(
                                'Company: ${customer.companyName}',
                                style: Theme.of(context).textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            Text(
                              'Registered: ${DateFormat('MMM dd, yyyy').format(customer.registrationDate)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              'Status: ${customer.status}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _getStatusColor(customer.status), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        isThreeLine: (customer.companyName != null && customer.companyName!.isNotEmpty) || (customer.address != null && customer.address!.isNotEmpty),
                        onTap: () {
                          _navigateToDetailsScreen(context, customer);
                        },
                        onLongPress: () {
                          _navigateToAddEditScreen(context, customer: customer);
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
