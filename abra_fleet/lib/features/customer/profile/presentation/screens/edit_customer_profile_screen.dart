// File: lib/features/customer/profile/presentation/screens/edit_customer_profile_screen.dart
// Enhanced screen for Customer to edit their profile details with Firebase integration.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// Import the Customer entity (assuming it's the one from admin/customer_management for now)
import 'package:abra_fleet/features/admin/customer_management/domain/entities/customer_entity.dart';
// Import the CustomerProvider to potentially save changes
import 'package:abra_fleet/features/admin/customer_management/presentation/providers/customer_provider.dart';
// Import JWT auth repository for direct profile updates
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/auth/data/repositories/jwt_auth_repository_impl.dart';


class EditCustomerProfileScreen extends StatefulWidget {
  final CustomerEntity customer;

  const EditCustomerProfileScreen({super.key, required this.customer});

  @override
  State<EditCustomerProfileScreen> createState() => _EditCustomerProfileScreenState();
}

class _EditCustomerProfileScreenState extends State<EditCustomerProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _companyNameController;
  late TextEditingController _addressController;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.customer.name);
    _phoneController = TextEditingController(text: widget.customer.phoneNumber);
    _companyNameController = TextEditingController(text: widget.customer.companyName ?? '');
    _addressController = TextEditingController(text: widget.customer.address ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _companyNameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final authRepository = Provider.of<AuthRepository>(context, listen: false);
      final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);

      try {
        // Update profile in Firebase first (name and phone number)
        bool firebaseSuccess = false;
        if (authRepository is FirebaseAuthRepositoryImpl) {
          firebaseSuccess = await authRepository.updateUserProfile(
            userId: widget.customer.id,
            name: _nameController.text.trim(),
            phoneNumber: _phoneController.text.trim(),
          );
        }

        if (!firebaseSuccess) {
          throw Exception('Failed to update profile in Firebase');
        }

        // Create an updated CustomerEntity object for local state management
        final updatedCustomer = widget.customer.copyWith(
          name: _nameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          companyName: _companyNameController.text.trim().isNotEmpty ? _companyNameController.text.trim() : null,
          address: _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
        );

        // Update in local provider for immediate UI updates
        bool providerSuccess = await customerProvider.updateCustomer(updatedCustomer);

        if (mounted) {
          String message = (firebaseSuccess && providerSuccess)
              ? 'Profile updated successfully!'
              : 'Profile updated in Firebase, but local sync may be delayed.';

          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: firebaseSuccess ? Colors.green : Colors.orange,
            ),
          );
          
          setState(() => _isLoading = false);
          
          if (firebaseSuccess) {
            navigator.pop(updatedCustomer); // Return updated customer to refresh previous screen
          }
        }
      } catch (e) {
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('Failed to update profile: ${e.toString()}'),
              backgroundColor: Colors.redAccent,
            ),
          );
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        Icons.account_circle,
                        size: 60,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: IconButton(
                          icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                          onPressed: () {
                            // TODO: Implement profile picture update
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Update profile picture (Placeholder)')),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24.0),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Full Name*', prefixIcon: Icon(Icons.person_outline_rounded)),
                validator: (value) => value == null || value.isEmpty ? 'Please enter your name' : null,
                textInputAction: TextInputAction.next,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16.0),

              // Email is typically not editable by the user directly after registration
              TextFormField(
                initialValue: widget.customer.email, // Display email
                decoration: const InputDecoration(labelText: 'Email (Cannot be changed)', prefixIcon: Icon(Icons.email_outlined)),
                readOnly: true, // Make it read-only
                enabled: false,
              ),
              const SizedBox(height: 16.0),

              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone Number*', prefixIcon: Icon(Icons.phone_outlined)),
                keyboardType: TextInputType.phone,
                validator: (value) => value == null || value.isEmpty ? 'Please enter your phone number' : null,
                textInputAction: TextInputAction.next,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16.0),

              TextFormField(
                controller: _companyNameController,
                decoration: const InputDecoration(labelText: 'Company Name (Optional)', prefixIcon: Icon(Icons.business_rounded)),
                textInputAction: TextInputAction.next,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16.0),

              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Address (Optional)', prefixIcon: Icon(Icons.location_city_rounded)),
                textInputAction: TextInputAction.done,
                maxLines: 2,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 32.0),

              ElevatedButton.icon(
                icon: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_alt_rounded),
                label: Text(_isLoading ? 'Saving...' : 'Save Changes'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: _isLoading ? null : _saveProfile,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
