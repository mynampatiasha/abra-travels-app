// File: lib/features/driver/profile/presentation/screens/edit_driver_profile_screen.dart
// Enhanced screen for Driver to edit their profile details with Firebase integration.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // For date formatting if needed
// Import the Driver entity (from admin features, as it's the source of truth for Driver data)
import 'package:abra_fleet/features/admin/driver_management/domain/entities/driver_entity.dart';
// Import the DriverProvider (from admin features)
import 'package:abra_fleet/features/admin/driver_management/presentation/providers/driver_provider.dart';

class EditDriverProfileScreen extends StatefulWidget {
  final Driver driver; // The current driver's details to edit

  const EditDriverProfileScreen({super.key, required this.driver});

  @override
  State<EditDriverProfileScreen> createState() => _EditDriverProfileScreenState();
}

class _EditDriverProfileScreenState extends State<EditDriverProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  // Email, License Number, Status, Assigned Vehicle are typically not editable by the driver themselves.
  // License Expiry might be viewable but updated by admin.

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.driver.name);
    _phoneController = TextEditingController(text: widget.driver.phoneNumber);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);

      try {
        // Create an updated Driver object
        final updatedDriver = widget.driver.copyWith(
          name: _nameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
        );

        // Update via provider (which calls backend API)
        bool success = await driverProvider.updateDriver(updatedDriver);

        if (mounted) {
          if (success) {
            scaffoldMessenger.showSnackBar(
              const SnackBar(
                content: Text('Profile updated successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            
            setState(() => _isLoading = false);
            navigator.pop(updatedDriver); // Return updated driver
          } else {
            throw Exception('Failed to update profile');
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
        title: const Text('Edit My Details'),
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
                        Icons.account_circle_outlined, // Different icon
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
                            // TODO: Implement profile picture update for driver
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

              // Display Email (read-only)
              TextFormField(
                initialValue: widget.driver.email,
                decoration: const InputDecoration(labelText: 'Email (Cannot be changed)', prefixIcon: Icon(Icons.email_outlined)),
                readOnly: true,
                enabled: false,
              ),
              const SizedBox(height: 16.0),

              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone Number*', prefixIcon: Icon(Icons.phone_outlined)),
                keyboardType: TextInputType.phone,
                validator: (value) => value == null || value.isEmpty ? 'Please enter your phone number' : null,
                textInputAction: TextInputAction.done,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16.0),

              // Display License Number (read-only)
              TextFormField(
                initialValue: widget.driver.licenseNumber,
                decoration: const InputDecoration(labelText: 'License Number', prefixIcon: Icon(Icons.card_membership_outlined)),
                readOnly: true,
                enabled: false,
              ),
              const SizedBox(height: 16.0),

              // Display License Expiry (read-only)
              if(widget.driver.licenseExpiryDate != null)
                TextFormField(
                  initialValue: DateFormat('MMM dd, yyyy').format(widget.driver.licenseExpiryDate!),
                  decoration: const InputDecoration(labelText: 'License Expiry', prefixIcon: Icon(Icons.calendar_today_outlined)),
                  readOnly: true,
                  enabled: false,
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
