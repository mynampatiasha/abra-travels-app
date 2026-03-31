// File: lib/features/admin/customer_management/presentation/screens/admin_add_edit_customer_screen.dart
// Screen for Admin to add or edit a customer, now using CustomerProvider.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import 'package:abra_fleet/features/admin/customer_management/domain/entities/customer_entity.dart';
import 'package:abra_fleet/features/admin/customer_management/presentation/providers/customer_provider.dart';

class AdminAddEditCustomerScreen extends StatefulWidget {
  final CustomerEntity? customer;

  const AdminAddEditCustomerScreen({
    Key? key,
    this.customer,
  }) : super(key: key);

  @override
  State<AdminAddEditCustomerScreen> createState() => _AdminAddEditCustomerScreenState();
}

class _AdminAddEditCustomerScreenState extends State<AdminAddEditCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _companyController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  // For password update in edit mode
  final _newPasswordController = TextEditingController();
  final _confirmNewPasswordController = TextEditingController();
  bool _showPasswordUpdate = false;

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmNewPassword = true;

  @override
  void initState() {
    super.initState();
    if (widget.customer != null) {
      _nameController.text = widget.customer!.name;
      _emailController.text = widget.customer!.email;
      _phoneController.text = widget.customer!.phoneNumber ?? '';
      _companyController.text = widget.customer!.companyName ?? '';
      _addressController.text = widget.customer!.address ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _companyController.dispose();
    _addressController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmNewPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);

    try {
  if (widget.customer == null) {
    // Create new customer
    final result = await customerProvider.createCustomer(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      company: _companyController.text.trim(),
      address: _addressController.text.trim(),
      password: _passwordController.text.trim(),
    );

    if (result['success'] == true && mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer created successfully')),
      );
    }
      } else {
        // Update existing customer
        final updatedCustomer = widget.customer!.copyWith(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          companyName: _companyController.text.trim(),
          address: _addressController.text.trim(),
        );

        final success = await customerProvider.updateCustomer(updatedCustomer);
        
        // Update password if provided
        if (success && _newPasswordController.text.trim().isNotEmpty) {
          final passwordUpdateSuccess = await customerProvider.updateCustomerPassword(
            widget.customer!.id,
            _newPasswordController.text.trim(),
          );
          
          if (!passwordUpdateSuccess && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  customerProvider.errorMessage ?? 'Failed to update password'
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
        
        if (success && mounted) {
          Navigator.pop(context, true); // Return success
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Customer updated successfully')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.customer != null;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Customer' : 'Add New Customer'),
        actions: [
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _isLoading ? null : () => _deleteCustomer(),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTextField(
                      controller: _nameController,
                      label: 'Full Name',
                      icon: Icons.person_outline,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _emailController,
                      label: 'Email',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !isEdit, // Disable email editing for existing customers
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter an email';
                        }
                        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    IntlPhoneField(
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        prefixIcon: const Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      initialCountryCode: 'US',
                      initialValue: _phoneController.text,
                      onChanged: (phone) {
                        // Update controller with complete phone number
                        _phoneController.text = phone.completeNumber;
                      },
                      validator: (phone) {
                        if (phone == null || phone.number.isEmpty) {
                          return 'Please enter a phone number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _companyController,
                      label: 'Company (Optional)',
                      icon: Icons.business_outlined,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _addressController,
                      label: 'Address (Optional)',
                      icon: Icons.location_on_outlined,
                      maxLines: 2,
                    ),
                    if (!isEdit) ...[  // Only show password fields for new customers
                      const SizedBox(height: 16),
                      _buildPasswordField(
                        controller: _passwordController,
                        label: 'Password',
                        obscureText: _obscurePassword,
                        onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a password';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildPasswordField(
                        controller: _confirmPasswordController,
                        label: 'Confirm Password',
                        obscureText: _obscureConfirmPassword,
                        onToggle: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                        validator: (value) {
                          if (value != _passwordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _saveCustomer,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(isEdit ? 'Update Customer' : 'Create Customer'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    int maxLines = 1,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        enabled: enabled,
      ),
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      maxLines: maxLines,
      enabled: enabled,
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool obscureText,
    required VoidCallback onToggle,
    required String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(obscureText ? Icons.visibility : Icons.visibility_off),
          onPressed: onToggle,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      validator: validator,
    );
  }

  Future<void> _deleteCustomer() async {
    if (widget.customer == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Customer'),
        content: const Text('Are you sure you want to delete this customer? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final success = await Provider.of<CustomerProvider>(
        context,
        listen: false,
      ).deleteCustomer(widget.customer!.id);

      if (success && mounted) {
        Navigator.pop(context, true); // Return success
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Customer deleted successfully')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting customer: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
