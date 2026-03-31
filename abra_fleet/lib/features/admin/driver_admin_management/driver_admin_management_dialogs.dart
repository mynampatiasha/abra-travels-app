// lib/features/admin/driver_admin_management/driver_management_dialogs.dart

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:abra_fleet/core/services/driver_service.dart';

import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;

import 'dart:convert';

import 'dart:io';

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:intl/intl.dart';

// Conditional import for web-only functionality
import 'stub_html.dart' if (dart.library.html) 'dart:html' as html;

// ==================== ADD DRIVER DIALOG ====================

class AddDriverDialog extends StatefulWidget {

  final DriverService driverService;

  const AddDriverDialog({Key? key, required this.driverService}) : super(key: key);

  @override

  State<AddDriverDialog> createState() => _AddDriverDialogState();

}

class _AddDriverDialogState extends State<AddDriverDialog> {

  final _formKey = GlobalKey<FormState>();

  int _currentStep = 0;

  bool _isSubmitting = false;

  // Personal Information Controllers

  final _firstNameController = TextEditingController();

  final _lastNameController = TextEditingController();

  final _emailController = TextEditingController();

  final _phoneController = TextEditingController();

  final _dateOfBirthController = TextEditingController();

  final _bloodGroupController = TextEditingController();

  String _selectedGender = 'Male';

  // Address Controllers

  final _streetController = TextEditingController();

  final _cityController = TextEditingController();

  final _stateController = TextEditingController();

  final _postalCodeController = TextEditingController();

  final _countryController = TextEditingController();

  // License Information Controllers

  final _licenseNumberController = TextEditingController();

  final _licenseTypeController = TextEditingController();

  final _licenseIssueDateController = TextEditingController();

  final _licenseExpiryDateController = TextEditingController();

  final _issuingAuthorityController = TextEditingController();

  // Emergency Contact Controllers

  final _emergencyNameController = TextEditingController();

  final _emergencyPhoneController = TextEditingController();

  final _emergencyRelationshipController = TextEditingController();

  // Employment Details Controllers

  final _employeeIdController = TextEditingController();

  final _joinDateController = TextEditingController();

  final _salaryController = TextEditingController();

  String _selectedEmploymentType = 'Full-time';

  String _selectedStatus = 'active';

  // Bank Details Controllers

  final _bankNameController = TextEditingController();

  final _accountNumberController = TextEditingController();

  final _ifscCodeController = TextEditingController();

  final _accountHolderNameController = TextEditingController();

  @override

  void dispose() {

    // Dispose all controllers

    _firstNameController.dispose();

    _lastNameController.dispose();

    _emailController.dispose();

    _phoneController.dispose();

    _dateOfBirthController.dispose();

    _bloodGroupController.dispose();

    _streetController.dispose();

    _cityController.dispose();

    _stateController.dispose();

    _postalCodeController.dispose();

    _countryController.dispose();

    _licenseNumberController.dispose();

    _licenseTypeController.dispose();

    _licenseIssueDateController.dispose();

    _licenseExpiryDateController.dispose();

    _issuingAuthorityController.dispose();

    _emergencyNameController.dispose();

    _emergencyPhoneController.dispose();

    _emergencyRelationshipController.dispose();

    _employeeIdController.dispose();

    _joinDateController.dispose();

    _salaryController.dispose();

    _bankNameController.dispose();

    _accountNumberController.dispose();

    _ifscCodeController.dispose();

    _accountHolderNameController.dispose();

    super.dispose();

  }

  Future<void> _selectDate(TextEditingController controller) async {

    final DateTime? picked = await showDatePicker(

      context: context,

      initialDate: DateTime.now(),

      firstDate: DateTime(1950),

      lastDate: DateTime(2100),

    );

    if (picked != null) {

      controller.text = DateFormat('yyyy-MM-dd').format(picked);

    }
  }
  List<Step> _buildSteps() {

    return [

      // Step 1: Personal Information

      Step(

        title: const Text('Personal Info'),

        isActive: _currentStep >= 0,

        state: _currentStep > 0 ? StepState.complete : StepState.indexed,

        content: Column(

          children: [

            Row(

              children: [

                Expanded(

                  child: TextFormField(

                    controller: _firstNameController,

                    decoration: const InputDecoration(

                      labelText: 'First Name *',

                      border: OutlineInputBorder(),

                    ),

                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

                  ),

                ),

                const SizedBox(width: 12),

                Expanded(

                  child: TextFormField(

                    controller: _lastNameController,

                    decoration: const InputDecoration(

                      labelText: 'Last Name *',

                      border: OutlineInputBorder(),

                    ),

                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

                  ),

                ),

              ],

            ),

            const SizedBox(height: 16),

            TextFormField(

              controller: _emailController,

              decoration: const InputDecoration(

                labelText: 'Email Address *',

                border: OutlineInputBorder(),

              ),

              keyboardType: TextInputType.emailAddress,

              validator: (v) {

                if (v?.isEmpty ?? true) return 'Required';

                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v!)) {

                  return 'Invalid email';

                }

                return null;

              },

            ),

            const SizedBox(height: 16),

            TextFormField(

              controller: _phoneController,

              decoration: const InputDecoration(

                labelText: 'Phone Number *',

                border: OutlineInputBorder(),

                prefixText: '+91 ',

              ),

              keyboardType: TextInputType.phone,

              inputFormatters: [FilteringTextInputFormatter.digitsOnly],

              validator: (v) {

                if (v?.isEmpty ?? true) return 'Required';

                if (v!.length != 10) return 'Must be 10 digits';

                return null;

              },

            ),

            const SizedBox(height: 16),

            Row(

              children: [

                Expanded(

                  child: TextFormField(

                    controller: _dateOfBirthController,

                    decoration: const InputDecoration(

                      labelText: 'Date of Birth *',

                      border: OutlineInputBorder(),

                      suffixIcon: Icon(Icons.calendar_today),

                    ),

                    readOnly: true,

                    onTap: () => _selectDate(_dateOfBirthController),

                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

                  ),

                ),

                const SizedBox(width: 12),

                Expanded(

                  child: DropdownButtonFormField<String>(

                    value: _selectedGender,

                    decoration: const InputDecoration(

                      labelText: 'Gender *',

                      border: OutlineInputBorder(),

                    ),

                    items: const [

                      DropdownMenuItem(value: 'Male', child: Text('Male')),

                      DropdownMenuItem(value: 'Female', child: Text('Female')),

                      DropdownMenuItem(value: 'Other', child: Text('Other')),

                    ],

                    onChanged: (v) => setState(() => _selectedGender = v!),

                  ),

                ),

              ],

            ),

            const SizedBox(height: 16),

            TextFormField(

              controller: _bloodGroupController,

              decoration: const InputDecoration(

                labelText: 'Blood Group',

                border: OutlineInputBorder(),

                hintText: 'e.g., O+, A-, B+',

              ),

            ),

          ],

        ),

      ),

      // Step 2: Address Information

      Step(

        title: const Text('Address'),

        isActive: _currentStep >= 1,

        state: _currentStep > 1 ? StepState.complete : StepState.indexed,

        content: Column(

          children: [

            TextFormField(

              controller: _streetController,

              decoration: const InputDecoration(

                labelText: 'Street Address *',

                border: OutlineInputBorder(),

              ),

              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

            ),

            const SizedBox(height: 16),

            Row(

              children: [

                Expanded(

                  child: TextFormField(

                    controller: _cityController,

                    decoration: const InputDecoration(

                      labelText: 'City *',

                      border: OutlineInputBorder(),

                    ),

                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

                  ),

                ),

                const SizedBox(width: 12),

                Expanded(

                  child: TextFormField(

                    controller: _stateController,

                    decoration: const InputDecoration(

                      labelText: 'State *',

                      border: OutlineInputBorder(),

                    ),

                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

                  ),

                ),

              ],

            ),

            const SizedBox(height: 16),

            Row(

              children: [

                Expanded(

                  child: TextFormField(

                    controller: _postalCodeController,

                    decoration: const InputDecoration(

                      labelText: 'Postal Code *',

                      border: OutlineInputBorder(),

                    ),

                    keyboardType: TextInputType.number,

                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],

                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

                  ),

                ),

                const SizedBox(width: 12),

                Expanded(

                  child: TextFormField(

                    controller: _countryController,

                    decoration: const InputDecoration(

                      labelText: 'Country *',

                      border: OutlineInputBorder(),

                    ),

                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

                  ),

                ),

              ],

            ),

          ],

        ),

      ),

      // Step 3: License Information

      Step(

        title: const Text('License'),

        isActive: _currentStep >= 2,

        state: _currentStep > 2 ? StepState.complete : StepState.indexed,

        content: Column(

          children: [

            TextFormField(

              controller: _licenseNumberController,

              decoration: const InputDecoration(

                labelText: 'License Number *',

                border: OutlineInputBorder(),

              ),

              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

            ),

            const SizedBox(height: 16),

            TextFormField(

              controller: _licenseTypeController,

              decoration: const InputDecoration(

                labelText: 'License Type *',

                border: OutlineInputBorder(),

                hintText: 'e.g., Commercial, LMV',

              ),

              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

            ),

            const SizedBox(height: 16),

            Row(

              children: [

                Expanded(

                  child: TextFormField(

                    controller: _licenseIssueDateController,

                    decoration: const InputDecoration(

                      labelText: 'Issue Date *',

                      border: OutlineInputBorder(),

                      suffixIcon: Icon(Icons.calendar_today),

                    ),

                    readOnly: true,

                    onTap: () => _selectDate(_licenseIssueDateController),

                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

                  ),

                ),

                const SizedBox(width: 12),

                Expanded(

                  child: TextFormField(

                    controller: _licenseExpiryDateController,

                    decoration: const InputDecoration(

                      labelText: 'Expiry Date *',

                      border: OutlineInputBorder(),

                      suffixIcon: Icon(Icons.calendar_today),

                    ),

                    readOnly: true,

                    onTap: () => _selectDate(_licenseExpiryDateController),

                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

                  ),

                ),

              ],

            ),

            const SizedBox(height: 16),

            TextFormField(

              controller: _issuingAuthorityController,

              decoration: const InputDecoration(

                labelText: 'Issuing Authority *',

                border: OutlineInputBorder(),

                hintText: 'e.g., RTO Office Name',

              ),

              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

            ),

          ],

        ),

      ),

      // Step 4: Emergency Contact

      Step(

        title: const Text('Emergency Contact'),

        isActive: _currentStep >= 3,

        state: _currentStep > 3 ? StepState.complete : StepState.indexed,

        content: Column(

          children: [

            TextFormField(

              controller: _emergencyNameController,

              decoration: const InputDecoration(

                labelText: 'Contact Name *',

                border: OutlineInputBorder(),

              ),

              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

            ),

            const SizedBox(height: 16),

            TextFormField(

              controller: _emergencyPhoneController,

              decoration: const InputDecoration(

                labelText: 'Contact Phone *',

                border: OutlineInputBorder(),

                prefixText: '+91 ',

              ),

              keyboardType: TextInputType.phone,

              inputFormatters: [FilteringTextInputFormatter.digitsOnly],

              validator: (v) {

                if (v?.isEmpty ?? true) return 'Required';

                if (v!.length != 10) return 'Must be 10 digits';

                return null;

              },

            ),

            const SizedBox(height: 16),

            TextFormField(

              controller: _emergencyRelationshipController,

              decoration: const InputDecoration(

                labelText: 'Relationship *',

                border: OutlineInputBorder(),

                hintText: 'e.g., Spouse, Parent, Sibling',

              ),

              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

            ),

          ],

        ),

      ),

      // Step 5: Employment Details

      Step(

        title: const Text('Employment'),

        isActive: _currentStep >= 4,

        state: _currentStep > 4 ? StepState.complete : StepState.indexed,

        content: Column(

          children: [

            TextFormField(

              controller: _employeeIdController,

              decoration: const InputDecoration(

                labelText: 'Employee ID *',

                border: OutlineInputBorder(),

              ),

              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

            ),

            const SizedBox(height: 16),

            TextFormField(

              controller: _joinDateController,

              decoration: const InputDecoration(

                labelText: 'Join Date *',

                border: OutlineInputBorder(),

                suffixIcon: Icon(Icons.calendar_today),

              ),

              readOnly: true,

              onTap: () => _selectDate(_joinDateController),

              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

            ),

            const SizedBox(height: 16),

            DropdownButtonFormField<String>(

              value: _selectedEmploymentType,

              decoration: const InputDecoration(

                labelText: 'Employment Type *',

                border: OutlineInputBorder(),

              ),

              items: const [

                DropdownMenuItem(value: 'Full-time', child: Text('Full-time')),

                DropdownMenuItem(value: 'Part-time', child: Text('Part-time')),

                DropdownMenuItem(value: 'Contract', child: Text('Contract')),

              ],

              onChanged: (v) => setState(() => _selectedEmploymentType = v!),

            ),

            const SizedBox(height: 16),

            TextFormField(

              controller: _salaryController,

              decoration: const InputDecoration(

                labelText: 'Monthly Salary *',

                border: OutlineInputBorder(),

                prefixText: '? ',

              ),

              keyboardType: TextInputType.number,

              inputFormatters: [FilteringTextInputFormatter.digitsOnly],

              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

            ),

            const SizedBox(height: 16),

            DropdownButtonFormField<String>(

              value: _selectedStatus,

              decoration: const InputDecoration(

                labelText: 'Status *',

                border: OutlineInputBorder(),

              ),

              items: const [

                DropdownMenuItem(value: 'active', child: Text('Active')),

                DropdownMenuItem(value: 'inactive', child: Text('Inactive')),

                DropdownMenuItem(value: 'on_leave', child: Text('On Leave')),

              ],

              onChanged: (v) => setState(() => _selectedStatus = v!),

            ),

          ],

        ),

      ),

      // Step 6: Bank Details

      Step(

        title: const Text('Bank Details'),

        isActive: _currentStep >= 5,

        state: _currentStep > 5 ? StepState.complete : StepState.indexed,

        content: Column(

          children: [

            TextFormField(

              controller: _bankNameController,

              decoration: const InputDecoration(

                labelText: 'Bank Name *',

                border: OutlineInputBorder(),

              ),

              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

            ),

            const SizedBox(height: 16),

            TextFormField(

              controller: _accountHolderNameController,

              decoration: const InputDecoration(

                labelText: 'Account Holder Name *',

                border: OutlineInputBorder(),

              ),

              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

            ),

            const SizedBox(height: 16),

            TextFormField(

              controller: _accountNumberController,

              decoration: const InputDecoration(

                labelText: 'Account Number *',

                border: OutlineInputBorder(),

              ),

              keyboardType: TextInputType.number,

              inputFormatters: [FilteringTextInputFormatter.digitsOnly],

              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,

            ),

            const SizedBox(height: 16),

            TextFormField(

              controller: _ifscCodeController,

              decoration: const InputDecoration(

                labelText: 'IFSC Code *',

                border: OutlineInputBorder(),

              ),

              textCapitalization: TextCapitalization.characters,

              validator: (v) {

                if (v?.isEmpty ?? true) return 'Required';

                if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(v!)) {

                  return 'Invalid IFSC code';

                }

                return null;

              },

            ),

          ],

        ),

      ),

    ];

  }

  Future<void> _submitDriver() async {

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {

      final driverData = {

        'personalInfo': {

          'firstName': _firstNameController.text,

          'lastName': _lastNameController.text,

          'email': _emailController.text,

          'phone': _phoneController.text,

          'dateOfBirth': _dateOfBirthController.text,

          'gender': _selectedGender,

          'bloodGroup': _bloodGroupController.text,

        },

        'address': {

          'street': _streetController.text,

          'city': _cityController.text,

          'state': _stateController.text,

          'postalCode': _postalCodeController.text,

          'country': _countryController.text,

        },

        'license': {

          'licenseNumber': _licenseNumberController.text,

          'type': _licenseTypeController.text,

          'issueDate': _licenseIssueDateController.text,

          'expiryDate': _licenseExpiryDateController.text,

          'issuingAuthority': _issuingAuthorityController.text,

        },

        'emergencyContact': {

          'name': _emergencyNameController.text,

          'phone': _emergencyPhoneController.text,

          'relationship': _emergencyRelationshipController.text,

        },

        'employmentDetails': {

          'employeeId': _employeeIdController.text,

          'joinDate': _joinDateController.text,

          'employmentType': _selectedEmploymentType,

          'salary': _salaryController.text,

        },

        'bankDetails': {

          'bankName': _bankNameController.text,

          'accountHolderName': _accountHolderNameController.text,

          'accountNumber': _accountNumberController.text,

          'ifscCode': _ifscCodeController.text,

        },

        'status': _selectedStatus,

      };

      await widget.driverService.addDriver(driverData);

      if (mounted) {

        Navigator.of(context).pop(true);

        ScaffoldMessenger.of(context).showSnackBar(

          const SnackBar(

            content: Text('Driver added successfully!'),

            backgroundColor: Colors.green,

          ),

        );

      }

    } catch (e) {

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(

            content: Text('Failed to add driver: $e'),

            backgroundColor: Colors.red,

          ),

        );

      }

    } finally {

      if (mounted) setState(() => _isSubmitting = false);

    }

  }

  @override

  Widget build(BuildContext context) {

    return Dialog(

      child: Container(

        width: MediaQuery.of(context).size.width * 0.8,

        height: MediaQuery.of(context).size.height * 0.9,

        child: Column(

          children: [

            // Header

            Container(

              padding: const EdgeInsets.all(20),

              decoration: const BoxDecoration(

                color: Color(0xFF1565C0),

                borderRadius: BorderRadius.only(

                  topLeft: Radius.circular(4),

                  topRight: Radius.circular(4),

                ),

              ),

              child: Row(

                children: [

                  const Icon(Icons.person_add, color: Colors.white, size: 28),

                  const SizedBox(width: 12),

                  const Text(

                    'Add New Driver',

                    style: TextStyle(

                      color: Colors.white,

                      fontSize: 20,

                      fontWeight: FontWeight.bold,

                    ),

                  ),

                  const Spacer(),

                  IconButton(

                    icon: const Icon(Icons.close, color: Colors.white),

                    onPressed: () => Navigator.of(context).pop(),

                  ),

                ],

              ),

            ),

            // Stepper Content

            Expanded(

              child: Form(

                key: _formKey,

                child: Stepper(

                  currentStep: _currentStep,

                  onStepContinue: () {

                    if (_currentStep < 5) {

                      if (_formKey.currentState!.validate()) {

                        setState(() => _currentStep++);

                      }

                    } else {

                      _submitDriver();

                    }

                  },

                  onStepCancel: () {

                    if (_currentStep > 0) {

                      setState(() => _currentStep--);

                    }

                  },

                  onStepTapped: (step) => setState(() => _currentStep = step),

                  controlsBuilder: (context, details) {

                    return Padding(

                      padding: const EdgeInsets.only(top: 20),

                      child: Row(

                        children: [

                          ElevatedButton(

                            onPressed: _isSubmitting ? null : details.onStepContinue,

                            style: ElevatedButton.styleFrom(

                              backgroundColor: const Color(0xFF1565C0),

                            ),

                            child: Text(_currentStep == 5 ? 'Submit' : 'Continue'),

                          ),

                          const SizedBox(width: 12),

                          if (_currentStep > 0)

                            OutlinedButton(

                              onPressed: details.onStepCancel,

                              child: const Text('Back'),

                            ),

                        ],

                      ),

                    );

                  },

                  steps: _buildSteps(),

                ),

              ),

            ),

          ],

        ),

      ),

    );

  }

}

// ==================== EXPORT DRIVERS DIALOG ====================

class ExportDriversDialog extends StatefulWidget {

  final DriverService driverService;

  const ExportDriversDialog({Key? key, required this.driverService}) : super(key: key);

  @override

  State<ExportDriversDialog> createState() => _ExportDriversDialogState();

}

class _ExportDriversDialogState extends State<ExportDriversDialog> {

  bool _isExporting = false;

  String _selectedFormat = 'CSV';

  String _selectedStatus = 'All';

  bool _includePersonalInfo = true;

  bool _includeAddress = true;

  bool _includeLicense = true;

  bool _includeEmployment = true;

  bool _includeBankDetails = false;

  Future<void> _exportDrivers() async {

    setState(() => _isExporting = true);

    try {

      final drivers = await widget.driverService.getDrivers(
        status: _selectedStatus != 'All' ? _selectedStatus.toLowerCase() : null,
        limit: 10000,
      );

      final driversList = List<Map<String, dynamic>>.from(drivers['data'] ?? []);

      if (_selectedFormat == 'CSV') {

        await _exportToCSV(driversList);

      } else {

        await _exportToJSON(driversList);

      }

      if (mounted) {

        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(

            content: Text('Exported ${driversList.length} drivers successfully!'),

            backgroundColor: Colors.green,

          ),

        );

      }

    } catch (e) {

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(

            content: Text('Export failed: $e'),

            backgroundColor: Colors.red,

          ),

        );

      }

    } finally {

      if (mounted) setState(() => _isExporting = false);

    }

  }

  Future<void> _exportToCSV(List<Map<String, dynamic>> drivers) async {

    List<List<dynamic>> rows = [];

    

    List<String> headers = ['Driver ID', 'Status'];

    if (_includePersonalInfo) {

      headers.addAll(['First Name', 'Last Name', 'Email', 'Phone', 'DOB', 'Gender', 'Blood Group']);

    }

    if (_includeAddress) {

      headers.addAll(['Street', 'City', 'State', 'Postal Code', 'Country']);

    }

    if (_includeLicense) {

      headers.addAll(['License Number', 'License Type', 'Issue Date', 'Expiry Date', 'Issuing Authority']);

    }

    if (_includeEmployment) {

      headers.addAll(['Employee ID', 'Join Date', 'Employment Type', 'Salary']);

    }

    if (_includeBankDetails) {

      headers.addAll(['Bank Name', 'Account Holder', 'Account Number', 'IFSC Code']);

    }

    rows.add(headers);

    for (var driver in drivers) {

      List<dynamic> row = [

        driver['driverId'] ?? '',

        driver['status'] ?? '',

      ];

      if (_includePersonalInfo) {

        final personal = driver['personalInfo'] ?? {};

        row.addAll([

          personal['firstName'] ?? '',

          personal['lastName'] ?? '',

          personal['email'] ?? '',

          personal['phone'] ?? '',

          personal['dateOfBirth'] ?? '',

          personal['gender'] ?? '',

          personal['bloodGroup'] ?? '',

        ]);

      }

      if (_includeAddress) {

        final address = driver['address'] ?? {};

        row.addAll([

          address['street'] ?? '',

          address['city'] ?? '',

          address['state'] ?? '',

          address['postalCode'] ?? '',

          address['country'] ?? '',

        ]);

      }

      if (_includeLicense) {

        final license = driver['license'] ?? {};

        row.addAll([

          license['licenseNumber'] ?? '',

          license['type'] ?? '',

          license['issueDate'] ?? '',

          license['expiryDate'] ?? '',

          license['issuingAuthority'] ?? '',

        ]);

      }

      if (_includeEmployment) {

        final employment = driver['employment'] ?? {};

        row.addAll([

          employment['employeeId'] ?? driver['driverId'] ?? '',

          employment['joinDate'] ?? '',

          employment['employmentType'] ?? '',

          employment['salary'] ?? '',

        ]);

      }

      if (_includeBankDetails) {

        final bank = driver['bankDetails'] ?? {};

        row.addAll([

          bank['bankName'] ?? '',

          bank['accountHolderName'] ?? bank['accountHolder'] ?? '',

          bank['accountNumber'] ?? '',

          bank['ifscCode'] ?? '',

        ]);

      }

      rows.add(row);

    }

    String csv = const ListToCsvConverter().convert(rows);

    

    // Trigger download

    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

    final filename = 'drivers_export_$timestamp.csv';

    _downloadFile(csv, filename, 'text/csv');

  }

  Future<void> _exportToJSON(List<Map<String, dynamic>> drivers) async {

    final exportData = drivers.map((driver) {

      Map<String, dynamic> filteredDriver = {

        'driverId': driver['driverId'],

        'status': driver['status'],

      };

      if (_includePersonalInfo) filteredDriver['personalInfo'] = driver['personalInfo'];

      if (_includeAddress) filteredDriver['address'] = driver['address'];

      if (_includeLicense) filteredDriver['license'] = driver['license'];

      if (_includeEmployment) filteredDriver['employmentDetails'] = driver['employmentDetails'];

      if (_includeBankDetails) filteredDriver['bankDetails'] = driver['bankDetails'];

      return filteredDriver;

    }).toList();

    String jsonString = const JsonEncoder.withIndent('  ').convert(exportData);

    

    // Trigger download

    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

    final filename = 'drivers_export_$timestamp.json';

    _downloadFile(jsonString, filename, 'application/json');

  }

  void _downloadFile(String content, String filename, String mimeType) {

    if (kIsWeb) {

      // Web platform - use blob and anchor element

      final bytes = utf8.encode(content);

      final blob = html.Blob([bytes], mimeType);

      final url = html.Url.createObjectUrlFromBlob(blob);

      final anchor = html.AnchorElement(href: url)

        ..setAttribute('download', filename)

        ..click();

      html.Url.revokeObjectUrl(url);

    } else {

      // For non-web platforms, show dialog with content

      _showExportDownloadDialog(content, filename);

    }

  }

  void _showExportDownloadDialog(String content, String filename) {

    showDialog(

      context: context,

      builder: (context) => Dialog(

        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),

        child: Container(

          width: 700,

          constraints: BoxConstraints(

            maxHeight: MediaQuery.of(context).size.height * 0.8,

          ),

          padding: const EdgeInsets.all(20),

          child: Column(

            mainAxisSize: MainAxisSize.min,

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              Row(

                children: [

                  const Icon(Icons.download, color: Color(0xFF1565C0)),

                  const SizedBox(width: 12),

                  const Text(

                    'Export Ready',

                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),

                  ),

                  const Spacer(),

                  IconButton(

                    onPressed: () => Navigator.pop(context),

                    icon: const Icon(Icons.close),

                  ),

                ],

              ),

              const SizedBox(height: 16),

              Text(

                'Copy the content below and save it as "$filename":',

                style: const TextStyle(fontSize: 14, color: Colors.grey),

              ),

              const SizedBox(height: 16),

              Expanded(

                child: Container(

                  width: double.infinity,

                  padding: const EdgeInsets.all(12),

                  decoration: BoxDecoration(

                    color: Colors.grey.shade100,

                    borderRadius: BorderRadius.circular(8),

                    border: Border.all(color: Colors.grey.shade300),

                  ),

                  child: SingleChildScrollView(

                    child: SelectableText(

                      content,

                      style: const TextStyle(

                        fontFamily: 'monospace',

                        fontSize: 12,

                      ),

                    ),

                  ),

                ),

              ),

              const SizedBox(height: 16),

              Row(

                children: [

                  Expanded(

                    child: OutlinedButton.icon(

                      onPressed: () {

                        Clipboard.setData(ClipboardData(text: content));

                        ScaffoldMessenger.of(context).showSnackBar(

                          const SnackBar(

                            content: Text('Content copied to clipboard!'),

                            backgroundColor: Colors.green,

                            duration: Duration(seconds: 2),

                          ),

                        );

                      },

                      icon: const Icon(Icons.copy),

                      label: const Text('Copy to Clipboard'),

                      style: OutlinedButton.styleFrom(

                        padding: const EdgeInsets.symmetric(vertical: 12),

                      ),

                    ),

                  ),

                  const SizedBox(width: 12),

                  Expanded(

                    child: ElevatedButton(

                      onPressed: () => Navigator.pop(context),

                      style: ElevatedButton.styleFrom(

                        backgroundColor: const Color(0xFF1565C0),

                        foregroundColor: Colors.white,

                        padding: const EdgeInsets.symmetric(vertical: 12),

                      ),

                      child: const Text('Close'),

                    ),

                  ),

                ],

              ),

            ],

          ),

        ),

      ),

    );

  }

  @override

  Widget build(BuildContext context) {

    return Dialog(

      child: Container(

        width: 500,

        padding: const EdgeInsets.all(24),

        child: Column(

          mainAxisSize: MainAxisSize.min,

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            Row(

              children: [

                const Icon(Icons.file_download, color: Color(0xFF1565C0), size: 28),

                const SizedBox(width: 12),

                const Text(

                  'Export Drivers',

                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),

                ),

                const Spacer(),

                IconButton(

                  icon: const Icon(Icons.close),

                  onPressed: () => Navigator.of(context).pop(),

                ),

              ],

            ),

            const Divider(height: 32),

            

            const Text('Export Format', style: TextStyle(fontWeight: FontWeight.bold)),

            const SizedBox(height: 8),

            Row(

              children: [

                Expanded(

                  child: RadioListTile<String>(

                    title: const Text('CSV'),

                    value: 'CSV',

                    groupValue: _selectedFormat,

                    onChanged: (v) => setState(() => _selectedFormat = v!),

                    dense: true,

                  ),

                ),

                Expanded(

                  child: RadioListTile<String>(

                    title: const Text('JSON'),

                    value: 'JSON',

                    groupValue: _selectedFormat,

                    onChanged: (v) => setState(() => _selectedFormat = v!),

                    dense: true,

                  ),

                ),

              ],

            ),

            const SizedBox(height: 16),

            

            const Text('Status Filter', style: TextStyle(fontWeight: FontWeight.bold)),

            const SizedBox(height: 8),

            DropdownButtonFormField<String>(

              value: _selectedStatus,

              decoration: const InputDecoration(

                border: OutlineInputBorder(),

                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),

              ),

              items: const [

                DropdownMenuItem(value: 'All', child: Text('All Drivers')),

                DropdownMenuItem(value: 'Active', child: Text('Active Only')),

                DropdownMenuItem(value: 'Inactive', child: Text('Inactive Only')),

                DropdownMenuItem(value: 'On Leave', child: Text('On Leave')),

              ],

              onChanged: (v) => setState(() => _selectedStatus = v!),

            ),

            const SizedBox(height: 16),

            

            const Text('Include Fields', style: TextStyle(fontWeight: FontWeight.bold)),

            const SizedBox(height: 8),

            CheckboxListTile(

              title: const Text('Personal Information'),

              value: _includePersonalInfo,

              onChanged: (v) => setState(() => _includePersonalInfo = v!),

              dense: true,

            ),

            CheckboxListTile(

              title: const Text('Address'),

              value: _includeAddress,

              onChanged: (v) => setState(() => _includeAddress = v!),

              dense: true,

            ),

            CheckboxListTile(

              title: const Text('License Information'),

              value: _includeLicense,

              onChanged: (v) => setState(() => _includeLicense = v!),

              dense: true,

            ),

            CheckboxListTile(

              title: const Text('Employment Details'),

              value: _includeEmployment,

              onChanged: (v) => setState(() => _includeEmployment = v!),

              dense: true,

            ),

            CheckboxListTile(

              title: const Text('Bank Details'),

              value: _includeBankDetails,

              onChanged: (v) => setState(() => _includeBankDetails = v!),

              dense: true,

            ),

            const SizedBox(height: 24),

            

            Row(

              mainAxisAlignment: MainAxisAlignment.end,

              children: [

                OutlinedButton(

                  onPressed: () => Navigator.of(context).pop(),

                  child: const Text('Cancel'),

                ),

                const SizedBox(width: 12),

                ElevatedButton.icon(

                  onPressed: _isExporting ? null : _exportDrivers,

                  icon: _isExporting

                      ? const SizedBox(

                          width: 16,

                          height: 16,

                          child: CircularProgressIndicator(strokeWidth: 2),

                        )

                      : const Icon(Icons.download),

                  label: Text(_isExporting ? 'Exporting...' : 'Export'),

                  style: ElevatedButton.styleFrom(

                    backgroundColor: const Color(0xFF1565C0),

                  ),

                ),

              ],

            ),

          ],

        ),

      ),

    );

  }

}

// ==================== IMPORT DRIVERS DIALOG (FULL BULK IMPORT) ====================

class ImportDriversDialog extends StatefulWidget {

  final DriverService driverService;

  const ImportDriversDialog({Key? key, required this.driverService}) : super(key: key);

  @override

  State<ImportDriversDialog> createState() => _ImportDriversDialogState();

}

class _ImportDriversDialogState extends State<ImportDriversDialog> {

  static const Color primaryColor = Color(0xFF0D47A1);

  

  FilePickerResult? _selectedFileResult;

  String? _selectedFileName;

  int? _selectedFileSize;

  

  bool _isProcessing = false;

  List<Map<String, dynamic>> _previewData = [];

  List<String> _validationErrors = [];

  int _currentStep = 0;

  int _importedCount = 0;

  int _failedCount = 0;

  int _totalCount = 0;

  List<String> _importErrors = [];

  

  final List<String> _requiredFields = [

    'First Name',

    'Last Name',

    'Email',

    'Phone',

    'DOB',

    'Gender',

    'Blood Group',

    'Street',

    'City',

    'State',

    'Postal Code',

    'Country',

    'License Number',

    'License Type',

    'Issue Date',

    'Expiry Date',

    'Issuing Authority',

    'Emergency Contact Name',

    'Emergency Contact Phone',

    'Emergency Contact Relationship',

    'Employee ID',

    'Join Date',

    'Employment Type',

    'Salary',

    'Bank Name',

    'Account Holder',

    'Account Number',

    'IFSC Code',

    'Status'

  ];

  

  @override

  Widget build(BuildContext context) {

    return Dialog(

      child: Container(

        width: MediaQuery.of(context).size.width * 0.9,

        height: MediaQuery.of(context).size.height * 0.9,

        child: Column(

          children: [

            Container(

              padding: const EdgeInsets.all(20),

              decoration: const BoxDecoration(

                color: Color(0xFF1565C0),

                borderRadius: BorderRadius.only(

                  topLeft: Radius.circular(4),

                  topRight: Radius.circular(4),

                ),

              ),

              child: Row(

                children: [

                  const Icon(Icons.file_upload, color: Colors.white, size: 28),

                  const SizedBox(width: 12),

                  const Text(

                    'Import Drivers',

                    style: TextStyle(

                      color: Colors.white,

                      fontSize: 20,

                      fontWeight: FontWeight.bold),

                  ),

                  const Spacer(),

                  IconButton(

                    icon: const Icon(Icons.close, color: Colors.white),

                    onPressed: () => Navigator.of(context).pop(),

                  ),

                ],

              ),

            ),

            Expanded(

              child: _buildStepContent(),

            ),

          ],

        ),

      ),

    );

  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildUploadStep();
      case 1:
        return _buildValidationStep();
      case 2:
        return _buildImportStep();
      case 3:
        return _buildResultsStep();
      default:
        return _buildUploadStep();
    }
  }

  Widget _buildUploadStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 1: Upload CSV File',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _downloadTemplate,
            icon: const Icon(Icons.download),
            label: const Text('Download Template'),
          ),
          const SizedBox(height: 24),
          Center(
            child: InkWell(
              onTap: _pickFile,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey, width: 2, style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Icon(Icons.cloud_upload, size: 64, color: primaryColor),
                    const SizedBox(height: 16),
                    Text(
                      _selectedFileName ?? 'Click to select CSV file',
                      style: const TextStyle(fontSize: 16),
                    ),
                    if (_selectedFileSize != null)
                      Text(
                        '${(_selectedFileSize! / 1024).toStringAsFixed(2)} KB',
                        style: const TextStyle(color: Colors.grey),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _selectedFileResult != null ? _validateFile : null,
                style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                child: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildValidationStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 2: Validation Results',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          if (_validationErrors.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Validation Errors:',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  const SizedBox(height: 8),
                  ..._validationErrors.map((error) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $error', style: const TextStyle(color: Colors.red)),
                      )),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade700),
                  const SizedBox(width: 12),
                  Text(
                    'File validated successfully! ${_previewData.length} drivers found.',
                    style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          if (_previewData.isNotEmpty) ...[
            const Text('Preview:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Email')),
                    DataColumn(label: Text('Phone')),
                    DataColumn(label: Text('Status')),
                  ],
                  rows: _previewData.take(10).map((driver) {
                    return DataRow(cells: [
                      DataCell(Text('${driver['First Name']} ${driver['Last Name']}')),
                      DataCell(Text(driver['Email'] ?? '')),
                      DataCell(Text(driver['Phone'] ?? '')),
                      DataCell(Text(driver['Status'] ?? '')),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => setState(() => _currentStep = 0),
                child: const Text('Back'),
              ),
              ElevatedButton(
                onPressed: _validationErrors.isEmpty ? _startImport : null,
                style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                child: const Text('Import'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImportStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            'Importing drivers... $_importedCount of $_totalCount',
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Import Complete',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total: $_totalCount', style: const TextStyle(fontSize: 16)),
                Text('Successful: $_importedCount', style: TextStyle(color: Colors.green.shade700, fontSize: 16)),
                Text('Failed: $_failedCount', style: TextStyle(color: Colors.red.shade700, fontSize: 16)),
              ],
            ),
          ),
          if (_importErrors.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Errors:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _importErrors.map((error) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $error', style: const TextStyle(color: Colors.red)),
                      )).toList(),
                ),
              ),
            ),
          ],
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null) {
        setState(() {
          _selectedFileResult = result;
          _selectedFileName = result.files.first.name;
          _selectedFileSize = result.files.first.size;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking file: $e')),
      );
    }
  }

  Future<void> _validateFile() async {
    if (_selectedFileResult == null) return;

    setState(() => _isProcessing = true);

    try {
      final bytes = _selectedFileResult!.files.first.bytes;
      if (bytes == null) throw Exception('Could not read file');

      final csvString = utf8.decode(bytes);
      final List<List<dynamic>> csvData = const CsvToListConverter().convert(csvString);

      if (csvData.isEmpty) {
        throw Exception('CSV file is empty');
      }

      final headers = csvData[0].map((e) => e.toString()).toList();
      final List<Map<String, dynamic>> parsedData = [];
      final List<String> errors = [];

      for (int i = 1; i < csvData.length; i++) {
        if (csvData[i].length != headers.length) {
          errors.add('Row ${i + 1}: Column count mismatch');
          continue;
        }

        Map<String, dynamic> row = {};
        for (int j = 0; j < headers.length; j++) {
          row[headers[j]] = csvData[i][j].toString();
        }
        parsedData.add(row);
      }

      setState(() {
        _previewData = parsedData;
        _validationErrors = errors;
        _currentStep = 1;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _validationErrors = ['Error reading file: $e'];
        _isProcessing = false;
      });
    }
  }

  Future<void> _startImport() async {
    setState(() {
      _currentStep = 2;
      _totalCount = _previewData.length;
      _importedCount = 0;
      _failedCount = 0;
      _importErrors = [];
    });

    for (var driverData in _previewData) {
      try {
        // Transform CSV flat structure to nested backend structure
        final transformedData = _transformDriverData(driverData);
        await widget.driverService.addDriver(transformedData);
        setState(() => _importedCount++);
      } catch (e) {
        setState(() {
          _failedCount++;
          _importErrors.add('${driverData['First Name']} ${driverData['Last Name']}: $e');
        });
      }
    }

    setState(() => _currentStep = 3);
  }

  // Transform CSV flat structure to nested backend structure
  Map<String, dynamic> _transformDriverData(Map<String, dynamic> csvData) {
    return {
      'driverId': csvData['Employee ID'],
      'personalInfo': {
        'firstName': csvData['First Name'],
        'lastName': csvData['Last Name'],
        'email': csvData['Email'],
        'phone': csvData['Phone'],
        'dateOfBirth': csvData['DOB'],
        'gender': csvData['Gender'],
        'bloodGroup': csvData['Blood Group'],
      },
      'license': {
        'licenseNumber': csvData['License Number'],
        'type': csvData['License Type'],
        'issueDate': csvData['Issue Date'],
        'expiryDate': csvData['Expiry Date'],
        'issuingAuthority': csvData['Issuing Authority'],
      },
      'emergencyContact': {
        'name': csvData['Emergency Contact Name'],
        'phone': csvData['Emergency Contact Phone'],
        'relationship': csvData['Emergency Contact Relationship'],
      },
      'address': {
        'street': csvData['Street'],
        'city': csvData['City'],
        'state': csvData['State'],
        'postalCode': csvData['Postal Code'],
        'country': csvData['Country'],
      },
      'employment': {
        'joinDate': csvData['Join Date'],
        'employmentType': csvData['Employment Type'],
        'salary': csvData['Salary'],
      },
      'bankDetails': {
        'bankName': csvData['Bank Name'],
        'accountHolder': csvData['Account Holder'],
        'accountNumber': csvData['Account Number'],
        'ifscCode': csvData['IFSC Code'],
      },
      'status': csvData['Status']?.toLowerCase() ?? 'active',
    };
  }

  void _downloadTemplate() {

    List<List<String>> csvData = [

      _requiredFields,

      [

        'John', 'Doe', 'john.doe@example.com', '9876543210', '1990-05-15', 'Male', 'O+',

        '123 Main St', 'Bangalore', 'Karnataka', '560001', 'India',

        'KA0120230001234', 'Commercial', '2020-01-15', '2030-01-14', 'RTO Bangalore',

        'Jane Doe', '9876543211', 'Spouse',

        'EMP001', '2023-01-01', 'Full-time', '30000',

        'HDFC Bank', 'John Doe', '12345678901234', 'HDFC0001234',

        'active'

      ],

      [

        'Jane', 'Smith', 'jane.smith@example.com', '9876543220', '1992-08-20', 'Female', 'A+',

        '456 Park Ave', 'Mumbai', 'Maharashtra', '400001', 'India',

        'MH0120230002345', 'LMV', '2021-03-10', '2031-03-09', 'RTO Mumbai',

        'John Smith', '9876543221', 'Spouse',

        'EMP002', '2023-02-15', 'Full-time', '35000',

        'ICICI Bank', 'Jane Smith', '23456789012345', 'ICIC0002345',

        'active'

      ],

    ];

    String csvContent = csvData.map((row) => row.join(',')).join('\n');

    _showDownloadDialog(csvContent);

  }

  void _showDownloadDialog(String csvContent) {

    showDialog(

      context: context,

      builder: (context) => Dialog(

        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),

        child: Container(

          width: 600,

          constraints: BoxConstraints(

            maxHeight: MediaQuery.of(context).size.height * 0.8,

          ),

          padding: const EdgeInsets.all(20),

          child: Column(

            mainAxisSize: MainAxisSize.min,

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              Row(

                children: [

                  Icon(Icons.download, color: primaryColor),

                  const SizedBox(width: 12),

                  const Text(

                    'CSV Template',

                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),

                  ),

                  const Spacer(),

                  IconButton(

                    onPressed: () => Navigator.pop(context),

                    icon: const Icon(Icons.close),

                  ),

                ],

              ),

              const SizedBox(height: 16),

              const Text(

                'Copy the content below and save it as a .csv file:',

                style: TextStyle(fontSize: 14, color: Colors.grey),

              ),

              const SizedBox(height: 16),

              Expanded(

                child: Container(

                  width: double.infinity,

                  padding: const EdgeInsets.all(12),

                  decoration: BoxDecoration(

                    color: Colors.grey.shade100,

                    borderRadius: BorderRadius.circular(8),

                    border: Border.all(color: Colors.grey.shade300),

                  ),

                  child: SingleChildScrollView(

                    child: SelectableText(

                      csvContent,

                      style: const TextStyle(

                        fontFamily: 'monospace',

                        fontSize: 12,

                      ),

                    ),

                  ),

                ),

              ),

              const SizedBox(height: 16),

              SizedBox(

                width: double.infinity,

                child: ElevatedButton(

                  onPressed: () => Navigator.pop(context),

                  style: ElevatedButton.styleFrom(

                    backgroundColor: primaryColor,

                    foregroundColor: Colors.white,

                    padding: const EdgeInsets.symmetric(vertical: 12),

                  ),

                  child: const Text('Close'),

                ),

              ),

            ],

          ),

        ),

      ),

    );

  }

}


// ==================== BULK IMPORT DRIVERS DIALOG (6 SAMPLE DRIVERS) ====================

class BulkImportDriversDialog extends StatefulWidget {
  final DriverService driverService;

  const BulkImportDriversDialog({Key? key, required this.driverService}) : super(key: key);

  @override
  State<BulkImportDriversDialog> createState() => _BulkImportDriversDialogState();
}

class _BulkImportDriversDialogState extends State<BulkImportDriversDialog> {
  bool _isImporting = false;
  bool _importCompleted = false;
  int _importedCount = 0;
  int _failedCount = 0;
  List<String> _importErrors = [];

  // 6 Sample drivers data
  final List<Map<String, dynamic>> _sampleDrivers = [
    {
      'firstName': 'Arjun',
      'lastName': 'Reddy',
      'email': 'arjun.reddy@abrafleet.com',
      'phone': '9876543210',
      'dob': '1990-05-15',
      'gender': 'Male',
      'bloodGroup': 'O+',
      'street': '123 Brigade Road',
      'city': 'Bangalore',
      'state': 'Karnataka',
      'postalCode': '560001',
      'country': 'India',
      'licenseNumber': 'KA0520230001234',
      'licenseType': 'LMV',
      'issueDate': '2020-03-15',
      'expiryDate': '2030-03-14',
      'issuingAuthority': 'RTO Bangalore',
      'emergencyContactName': 'Lakshmi Reddy',
      'emergencyContactPhone': '9876543211',
      'emergencyContactRelationship': 'Spouse',
      'employeeId': 'DRV001',
      'joinDate': '2024-01-15',
      'employmentType': 'Full-time',
      'salary': '45000',
      'bankName': 'HDFC Bank',
      'accountHolder': 'Arjun Reddy',
      'accountNumber': '12345678901234',
      'ifscCode': 'HDFC0001234',
      'status': 'active'
    },
    {
      'firstName': 'Priya',
      'lastName': 'Sharma',
      'email': 'priya.sharma@abrafleet.com',
      'phone': '9876543212',
      'dob': '1988-08-22',
      'gender': 'Female',
      'bloodGroup': 'A+',
      'street': '456 MG Road',
      'city': 'Chennai',
      'state': 'Tamil Nadu',
      'postalCode': '600001',
      'country': 'India',
      'licenseNumber': 'TN0520230005678',
      'licenseType': 'Commercial',
      'issueDate': '2019-07-10',
      'expiryDate': '2029-07-09',
      'issuingAuthority': 'RTO Chennai',
      'emergencyContactName': 'Raj Sharma',
      'emergencyContactPhone': '9876543213',
      'emergencyContactRelationship': 'Father',
      'employeeId': 'DRV002',
      'joinDate': '2024-01-20',
      'employmentType': 'Full-time',
      'salary': '42000',
      'bankName': 'SBI Bank',
      'accountHolder': 'Priya Sharma',
      'accountNumber': '23456789012345',
      'ifscCode': 'SBIN0002345',
      'status': 'active'
    },
    {
      'firstName': 'Vikram',
      'lastName': 'Singh',
      'email': 'vikram.singh@abrafleet.com',
      'phone': '9876543214',
      'dob': '1992-12-03',
      'gender': 'Male',
      'bloodGroup': 'B+',
      'street': '789 Connaught Place',
      'city': 'Delhi',
      'state': 'Delhi',
      'postalCode': '110001',
      'country': 'India',
      'licenseNumber': 'DL0520230009012',
      'licenseType': 'LMV',
      'issueDate': '2021-01-20',
      'expiryDate': '2031-01-19',
      'issuingAuthority': 'RTO Delhi',
      'emergencyContactName': 'Sunita Singh',
      'emergencyContactPhone': '9876543215',
      'emergencyContactRelationship': 'Mother',
      'employeeId': 'DRV003',
      'joinDate': '2024-02-01',
      'employmentType': 'Full-time',
      'salary': '48000',
      'bankName': 'Axis Bank',
      'accountHolder': 'Vikram Singh',
      'accountNumber': '34567890123456',
      'ifscCode': 'UTIB0003456',
      'status': 'active'
    },
    {
      'firstName': 'Anita',
      'lastName': 'Patel',
      'email': 'anita.patel@abrafleet.com',
      'phone': '9876543216',
      'dob': '1985-04-18',
      'gender': 'Female',
      'bloodGroup': 'AB+',
      'street': '321 CG Road',
      'city': 'Ahmedabad',
      'state': 'Gujarat',
      'postalCode': '380001',
      'country': 'India',
      'licenseNumber': 'GJ0520230003456',
      'licenseType': 'Commercial',
      'issueDate': '2018-09-05',
      'expiryDate': '2028-09-04',
      'issuingAuthority': 'RTO Ahmedabad',
      'emergencyContactName': 'Kiran Patel',
      'emergencyContactPhone': '9876543217',
      'emergencyContactRelationship': 'Husband',
      'employeeId': 'DRV004',
      'joinDate': '2024-02-10',
      'employmentType': 'Full-time',
      'salary': '44000',
      'bankName': 'ICICI Bank',
      'accountHolder': 'Anita Patel',
      'accountNumber': '45678901234567',
      'ifscCode': 'ICIC0004567',
      'status': 'active'
    },
    {
      'firstName': 'Rajesh',
      'lastName': 'Kumar',
      'email': 'rajesh.kumar@abrafleet.com',
      'phone': '9876543218',
      'dob': '1987-11-25',
      'gender': 'Male',
      'bloodGroup': 'O-',
      'street': '654 Park Street',
      'city': 'Kolkata',
      'state': 'West Bengal',
      'postalCode': '700001',
      'country': 'India',
      'licenseNumber': 'WB0520230007890',
      'licenseType': 'LMV',
      'issueDate': '2020-06-12',
      'expiryDate': '2030-06-11',
      'issuingAuthority': 'RTO Kolkata',
      'emergencyContactName': 'Meera Kumar',
      'emergencyContactPhone': '9876543219',
      'emergencyContactRelationship': 'Spouse',
      'employeeId': 'DRV005',
      'joinDate': '2024-02-15',
      'employmentType': 'Full-time',
      'salary': '46000',
      'bankName': 'PNB Bank',
      'accountHolder': 'Rajesh Kumar',
      'accountNumber': '56789012345678',
      'ifscCode': 'PUNB0005678',
      'status': 'active'
    },
    {
      'firstName': 'Deepika',
      'lastName': 'Nair',
      'email': 'deepika.nair@abrafleet.com',
      'phone': '9876543220',
      'dob': '1991-09-14',
      'gender': 'Female',
      'bloodGroup': 'A-',
      'street': '987 Marine Drive',
      'city': 'Mumbai',
      'state': 'Maharashtra',
      'postalCode': '400001',
      'country': 'India',
      'licenseNumber': 'MH0520230001122',
      'licenseType': 'Commercial',
      'issueDate': '2021-11-08',
      'expiryDate': '2031-11-07',
      'issuingAuthority': 'RTO Mumbai',
      'emergencyContactName': 'Suresh Nair',
      'emergencyContactPhone': '9876543221',
      'emergencyContactRelationship': 'Father',
      'employeeId': 'DRV006',
      'joinDate': '2024-03-01',
      'employmentType': 'Full-time',
      'salary': '50000',
      'bankName': 'Kotak Bank',
      'accountHolder': 'Deepika Nair',
      'accountNumber': '67890123456789',
      'ifscCode': 'KKBK0006789',
      'status': 'active'
    },
  ];

  Future<void> _importSampleDrivers() async {
    setState(() {
      _isImporting = true;
      _importedCount = 0;
      _failedCount = 0;
      _importErrors = [];
    });

    try {
      final response = await widget.driverService.bulkImportDrivers(_sampleDrivers);
      
      if (response['success'] == true) {
        final results = response['results'];
        setState(() {
          _importedCount = (results['successful'] as List).length;
          _failedCount = (results['failed'] as List).length;
          _importErrors = (results['failed'] as List)
              .map((failed) => '${failed['data']['firstName']} ${failed['data']['lastName']}: ${failed['error']}')
              .toList();
        });
      } else {
        throw Exception(response['message'] ?? 'Import failed');
      }
    } catch (e) {
      setState(() {
        _failedCount = _sampleDrivers.length;
        _importErrors = ['Import failed: $e'];
      });
    } finally {
      setState(() {
        _isImporting = false;
        _importCompleted = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.upload_file, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bulk Import Sample Drivers',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Import 6 pre-configured sample drivers',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 32),

            if (!_importCompleted) ...[
              // Sample drivers preview
              const Text(
                'Sample Drivers to Import:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              
              Container(
                height: 300,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: DataTable(
                    columnSpacing: 20,
                    columns: const [
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Email')),
                      DataColumn(label: Text('Phone')),
                      DataColumn(label: Text('City')),
                    ],
                    rows: _sampleDrivers.map((driver) {
                      return DataRow(cells: [
                        DataCell(Text('${driver['firstName']} ${driver['lastName']}')),
                        DataCell(Text(driver['email'])),
                        DataCell(Text(driver['phone'])),
                        DataCell(Text(driver['city'])),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Import info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Import Details',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('• 6 sample drivers with complete profiles'),
                    const Text('• Firebase authentication accounts will be created'),
                    const Text('• Welcome emails will be sent to each driver'),
                    const Text('• Drivers can reset passwords using email links'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isImporting ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isImporting ? null : _importSampleDrivers,
                    icon: _isImporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload),
                    label: Text(_isImporting ? 'Importing...' : 'Import 6 Drivers'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Import results
              const Text(
                'Import Results',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _importedCount > 0 ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _importedCount > 0 ? Colors.green.shade200 : Colors.red.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _importedCount > 0 ? Icons.check_circle : Icons.error,
                          color: _importedCount > 0 ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Import Summary',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _importedCount > 0 ? Colors.green.shade700 : Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Total: ${_sampleDrivers.length}', style: const TextStyle(fontSize: 16)),
                    Text(
                      'Successful: $_importedCount',
                      style: TextStyle(color: Colors.green.shade700, fontSize: 16),
                    ),
                    Text(
                      'Failed: $_failedCount',
                      style: TextStyle(color: Colors.red.shade700, fontSize: 16),
                    ),
                  ],
                ),
              ),

              if (_importErrors.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Errors:',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 150,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _importErrors.map((error) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $error', style: const TextStyle(color: Colors.red)),
                      )).toList(),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}