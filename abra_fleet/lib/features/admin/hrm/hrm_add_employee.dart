// lib/screens/hrm/hrm_add_employee.dart
// ============================================================================
// ➕ ADD/EDIT EMPLOYEE SCREEN - Teal/Blue Theme
// ============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:country_state_city_picker/country_state_city_picker.dart';
import 'package:abra_fleet/core/services/hrm_employee_service.dart';
import 'package:abra_fleet/features/admin/services/hrm_master_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HRMAddEmployeeScreen extends StatefulWidget {
  final String? employeeId;

  const HRMAddEmployeeScreen({Key? key, this.employeeId}) : super(key: key);

  @override
  State<HRMAddEmployeeScreen> createState() => _HRMAddEmployeeScreenState();
}

class _HRMAddEmployeeScreenState extends State<HRMAddEmployeeScreen> with TickerProviderStateMixin {
  final _employeeService = HRMEmployeeService();
  final _masterService = HRMMasterSettingsService();
  final _formKey = GlobalKey<FormState>();
  
  // Controllers - Personal Info
  final _nameController = TextEditingController();
  final _dobController = TextEditingController();
  final _bloodGroupController = TextEditingController();
  final _personalEmailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _altPhoneController = TextEditingController();
  final _addressController = TextEditingController();
  
  // Controllers - Identity
  final _aadharController = TextEditingController();
  final _panController = TextEditingController();
  
  // Controllers - Emergency Contact
  final _contactNameController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _contactAltPhoneController = TextEditingController();
  
  // Controllers - Education
  final _degreeController = TextEditingController();
  final _yearController = TextEditingController();
  final _percentageController = TextEditingController();
  
  // Controllers - Bank
  final _bankAccountController = TextEditingController();
  final _ifscController = TextEditingController();
  final _bankBranchController = TextEditingController();
  
  // Controllers - Official
  final _emailController = TextEditingController();
  final _hireDateController = TextEditingController();
  final _salaryController = TextEditingController();

  // Dropdowns
  String? _selectedGender;
  String? _selectedDepartment;
  String? _selectedPosition;
  String? _selectedEmployeeType;
  String? _selectedWorkLocation;
  String? _selectedTiming;
  String? _selectedCompany;
  String? _selectedStatus;
  String? _selectedReportingManager1;
  String? _selectedReportingManager2;
  
  // CSC Picker
  String? _selectedCountry;
  String? _selectedState;
  String? _selectedCity;
  
  // Master Data
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _positions = [];
  List<Map<String, dynamic>> _allPositions = [];
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _timings = [];
  List<Map<String, dynamic>> _companies = [];
  List<Map<String, dynamic>> _employees = [];
  
  // Documents
  List<File> _documents = [];
  List<Map<String, String>> _documentMetadata = [];
  List<Map<String, dynamic>> _existingDocuments = [];
  
  // State
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditMode = false;
  int _currentStep = 0;
  DateTime? _selectedDob;
  DateTime? _selectedHireDate;
  String? _currentEmployeeId;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.employeeId != null;
    _setupAnimations();
    _loadMasterData();
    if (_isEditMode) {
      _loadEmployeeData();
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _fadeController.forward();
  }

  Future<void> _loadMasterData() async {
    try {
      print('🔄 Loading master data...');
      
      final results = await Future.wait<dynamic>([
        _masterService.getDepartments(),
        _masterService.getPositions(),
        _masterService.getLocations(),
        _masterService.getTimings(),
        _masterService.getCompanies(),
        _employeeService.getEmployeesList(),
      ]);
      
      print('✅ Master data results:');
      print('  📋 Departments: ${results[0].length} items');
      print('  📋 Positions: ${results[1].length} items');
      print('  📍 Locations: ${results[2].length} items');
      print('  ⏰ Timings: ${results[3].length} items');
      print('  🏢 Companies: ${results[4].length} items');
      print('  👥 Employees: ${results[5]['success']}');
      
      setState(() {
        _departments = results[0];
        _allPositions = results[1];
        _positions = _allPositions;
        _locations = results[2];
        _timings = results[3];
        _companies = results[4];
        _employees = results[5]['success'] == true 
          ? List<Map<String, dynamic>>.from(results[5]['data'] ?? [])
          : [];
      });
      
    } catch (e) {
      print('❌ Error loading master data: $e');
      _showErrorSnackbar('Failed to load master data: $e');
    }
  }

  Future<void> _loadEmployeeData() async {
    setState(() => _isLoading = true);
    
    try {
      final response = await _employeeService.getEmployee(widget.employeeId!);
      
      if (response['success'] == true) {
        final emp = response['data'];
        
        setState(() {
          _currentEmployeeId = emp['employeeId'];
          
          // Personal Info
          _nameController.text = emp['name'] ?? '';
          _selectedGender = emp['gender'];
          _selectedDob = emp['dob'] != null ? DateTime.parse(emp['dob']) : null;
          _dobController.text = _selectedDob != null 
            ? DateFormat('dd/MM/yyyy').format(_selectedDob!)
            : '';
          _bloodGroupController.text = emp['bloodGroup'] ?? '';
          _personalEmailController.text = emp['personalEmail'] ?? '';
          _phoneController.text = emp['phone'] ?? '';
          _altPhoneController.text = emp['altPhone'] ?? '';
          _addressController.text = emp['address'] ?? '';
          _selectedCountry = emp['country'];
          _selectedState = emp['state'];
          
          // Identity
          _aadharController.text = emp['aadharCard'] ?? '';
          _panController.text = emp['panNumber'] ?? '';
          
          // Emergency
          _contactNameController.text = emp['contactName'] ?? '';
          _relationshipController.text = emp['relationship'] ?? '';
          _contactPhoneController.text = emp['contactPhone'] ?? '';
          _contactAltPhoneController.text = emp['contactAltPhone'] ?? '';
          
          // Education
          _degreeController.text = emp['universityDegree'] ?? '';
          _yearController.text = emp['yearCompletion'] ?? '';
          _percentageController.text = emp['percentageCgpa'] ?? '';
          
          // Bank
          _bankAccountController.text = emp['bankAccountNumber'] ?? '';
          _ifscController.text = emp['ifscCode'] ?? '';
          _bankBranchController.text = emp['bankBranch'] ?? '';
          
          // Official
          _emailController.text = emp['email'] ?? '';
          _selectedHireDate = emp['hireDate'] != null ? DateTime.parse(emp['hireDate']) : null;
          _hireDateController.text = _selectedHireDate != null
            ? DateFormat('dd/MM/yyyy').format(_selectedHireDate!)
            : '';
          _selectedDepartment = emp['department'];
          _selectedPosition = emp['position'];
          _selectedEmployeeType = emp['employeeType'];
          _salaryController.text = emp['salary']?.toString() ?? '';
          _selectedWorkLocation = emp['workLocation'];
          _selectedTiming = emp['timings'];
          _selectedCompany = emp['companyName'];
          _selectedStatus = emp['status'];
          _selectedReportingManager1 = emp['reportingManager1'];
          _selectedReportingManager2 = emp['reportingManager2'];
          
          // Documents
          _existingDocuments = List<Map<String, dynamic>>.from(emp['documents'] ?? []);
          
          // Filter positions by department
          if (_selectedDepartment != null) {
            _filterPositionsByDepartment(_selectedDepartment!);
          }
        });
      }
    } catch (e) {
      _showErrorSnackbar('Failed to load employee: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _filterPositionsByDepartment(String departmentName) {
    final dept = _departments.firstWhere(
      (d) => d['name'] == departmentName,
      orElse: () => {},
    );
    
    if (dept.isNotEmpty) {
      setState(() {
        _positions = _allPositions.where((p) {
          final deptId = p['departmentId'];
          if (deptId is Map) {
            return deptId['_id'] == dept['_id'];
          }
          return deptId == dept['_id'];
        }).toList();
        
        // Clear position if not in filtered list
        if (_selectedPosition != null && 
            !_positions.any((p) => p['title'] == _selectedPosition)) {
          _selectedPosition = null;
        }
      });
    }
  }

  Future<void> _pickDate(BuildContext context, bool isHireDate) async {
    final initialDate = isHireDate 
      ? (_selectedHireDate ?? DateTime.now())
      : (_selectedDob ?? DateTime(2000));
      
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1B7FA8),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (pickedDate != null) {
      setState(() {
        if (isHireDate) {
          _selectedHireDate = pickedDate;
          _hireDateController.text = DateFormat('dd/MM/yyyy').format(pickedDate);
        } else {
          _selectedDob = pickedDate;
          _dobController.text = DateFormat('dd/MM/yyyy').format(pickedDate);
        }
      });
    }
  }

  Future<void> _pickDocuments() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx'],
        allowMultiple: true,
      );
      
      if (result != null) {
        for (var file in result.files) {
          final fileObj = File(file.path!);
          final sizeInBytes = await fileObj.length();
          final sizeInMB = sizeInBytes / (1024 * 1024);
          
          if (sizeInMB > 5) {
            _showErrorSnackbar('${file.name} exceeds 5MB limit');
            continue;
          }
          
          // Show dialog to get document type
          final docType = await _showDocumentTypeDialog(file.name);
          
          if (docType != null) {
            setState(() {
              _documents.add(fileObj);
              _documentMetadata.add({
                'documentType': docType,
                'filename': file.name,
              });
            });
          }
        }
      }
    } catch (e) {
      _showErrorSnackbar('Failed to pick files: $e');
    }
  }

  Future<String?> _showDocumentTypeDialog(String filename) async {
    final controller = TextEditingController();
    
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Document Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'File: $filename',
              style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select or enter document type:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                'Aadhar Card',
                'PAN Card',
                'Resume',
                'Offer Letter',
                'Experience Letter',
                'Education Certificate',
                'Other',
              ].map((type) => FilterChip(
                label: Text(type),
                selected: controller.text == type,
                onSelected: (selected) {
                  setState(() {
                    controller.text = selected ? type : '';
                  });
                },
                selectedColor: const Color(0xFF1B7FA8).withOpacity(0.2),
                checkmarkColor: const Color(0xFF1B7FA8),
              )).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Custom Type',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                Navigator.pop(context, controller.text);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B7FA8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _removeDocument(int index) {
    setState(() {
      _documents.removeAt(index);
      _documentMetadata.removeAt(index);
    });
  }

  Future<void> _deleteExistingDocument(Map<String, dynamic> doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Document?'),
        content: Text('Are you sure you want to delete "${doc['filename']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final response = await _employeeService.deleteDocument(
        widget.employeeId!,
        doc['_id'],
      );
      
      if (response['success'] == true) {
        setState(() {
          _existingDocuments.remove(doc);
        });
        _showSuccessSnackbar('Document deleted');
      } else {
        _showErrorSnackbar(response['message'] ?? 'Failed to delete document');
      }
    }
  }

  Future<void> _saveEmployee() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackbar('Please fill all required fields');
      return;
    }
    
    if (_selectedCountry == null) {
      _showErrorSnackbar('Please select country');
      return;
    }
    
    if (_selectedState == null) {
      _showErrorSnackbar('Please select state');
      return;
    }
    
    setState(() => _isSaving = true);
    
    try {
      final employeeData = {
        'name': _nameController.text.trim(),
        'gender': _selectedGender,
        'dob': _selectedDob?.toIso8601String(),
        'bloodGroup': _bloodGroupController.text.trim(),
        'personalEmail': _personalEmailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'altPhone': _altPhoneController.text.trim(),
        'address': _addressController.text.trim(),
        'country': _selectedCountry,
        'state': _selectedState,
        'aadharCard': _aadharController.text.trim(),
        'panNumber': _panController.text.trim().toUpperCase(),
        'contactName': _contactNameController.text.trim(),
        'relationship': _relationshipController.text.trim(),
        'contactPhone': _contactPhoneController.text.trim(),
        'contactAltPhone': _contactAltPhoneController.text.trim(),
        'universityDegree': _degreeController.text.trim(),
        'yearCompletion': _yearController.text.trim(),
        'percentageCgpa': _percentageController.text.trim(),
        'bankAccountNumber': _bankAccountController.text.trim(),
        'ifscCode': _ifscController.text.trim().toUpperCase(),
        'bankBranch': _bankBranchController.text.trim(),
        'email': _emailController.text.trim(),
        'hireDate': _selectedHireDate?.toIso8601String(),
        'department': _selectedDepartment,
        'position': _selectedPosition,
        'reportingManager1': _selectedReportingManager1,
        'reportingManager2': _selectedReportingManager2,
        'employeeType': _selectedEmployeeType,
        'salary': _salaryController.text.trim(),
        'workLocation': _selectedWorkLocation,
        'timings': _selectedTiming,
        'companyName': _selectedCompany,
        'status': _selectedStatus ?? 'Active',
      };
      
      Map<String, dynamic> response;
      
      if (_isEditMode) {
        response = await _employeeService.updateEmployee(
          id: widget.employeeId!,
          employeeData: employeeData,
          newDocuments: _documents.isEmpty ? null : _documents,
          documentMetadata: _documents.isEmpty ? null : _documentMetadata,
        );
      } else {
        response = await _employeeService.createEmployee(
          employeeData: employeeData,
          documents: _documents.isEmpty ? null : _documents,
          documentMetadata: _documents.isEmpty ? null : _documentMetadata,
        );
      }
      
      if (response['success'] == true) {
        _showSuccessSnackbar(
          _isEditMode 
            ? 'Employee updated successfully' 
            : 'Employee created successfully'
        );
        Navigator.pop(context, true);
      } else {
        _showErrorSnackbar(response['message'] ?? 'Failed to save employee');
      }
    } catch (e) {
      _showErrorSnackbar('Error: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dobController.dispose();
    _bloodGroupController.dispose();
    _personalEmailController.dispose();
    _phoneController.dispose();
    _altPhoneController.dispose();
    _addressController.dispose();
    _aadharController.dispose();
    _panController.dispose();
    _contactNameController.dispose();
    _relationshipController.dispose();
    _contactPhoneController.dispose();
    _contactAltPhoneController.dispose();
    _degreeController.dispose();
    _yearController.dispose();
    _percentageController.dispose();
    _bankAccountController.dispose();
    _ifscController.dispose();
    _bankBranchController.dispose();
    _emailController.dispose();
    _hireDateController.dispose();
    _salaryController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FA),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(Color(0xFF1B7FA8)),
              ),
            )
          : FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _buildPersonalInfoSection(),
                            const SizedBox(height: 24),
                            _buildContactSection(),
                            const SizedBox(height: 24),
                            _buildEducationBankSection(),
                            const SizedBox(height: 24),
                            _buildOfficialSection(),
                            const SizedBox(height: 24),
                            _buildDocumentsSection(),
                            const SizedBox(height: 32),
                            _buildSaveButton(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1B7FA8), Color(0xFF2D3E50)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_add, color: Colors.white, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _isEditMode 
                ? 'Edit Employee${_currentEmployeeId != null ? " ($_currentEmployeeId)" : ""}' 
                : 'Add New Employee',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              // Scan document functionality
            },
            icon: const Icon(Icons.document_scanner, size: 18),
            label: const Text('Scan Document'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEC4899),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back to List'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B7FA8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoSection() {
    return _buildSection(
      title: 'Personal Information',
      icon: Icons.person,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _nameController,
                label: 'Full Name',
                icon: Icons.badge,
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDropdown(
                label: 'Gender',
                value: _selectedGender,
                items: ['Male', 'Female', 'Other'],
                onChanged: (value) => setState(() => _selectedGender = value),
                icon: Icons.wc,
                validator: (value) => value == null ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDateField(
                controller: _dobController,
                label: 'Date of Birth',
                icon: Icons.cake,
                onTap: () => _pickDate(context, false),
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _bloodGroupController,
                label: 'Blood Group',
                icon: Icons.bloodtype,
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _personalEmailController,
                label: 'Personal Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (!value!.contains('@')) return 'Invalid email';
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _phoneController,
                label: 'Phone Number',
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (value!.length != 10) return 'Must be 10 digits';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _altPhoneController,
                label: 'Alternate Phone',
                icon: Icons.phone_android,
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (value!.length != 10) return 'Must be 10 digits';
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _addressController,
          label: 'Address',
          icon: Icons.home,
          maxLines: 3,
          validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          padding: const EdgeInsets.all(16),
          child: SelectState(
            onCountryChanged: (country) {
              setState(() {
                _selectedCountry = country;
                _selectedState = null;
                _selectedCity = null;
              });
            },
            onStateChanged: (state) {
              setState(() {
                _selectedState = state;
                _selectedCity = null;
              });
            },
            onCityChanged: (city) {
              setState(() {
                _selectedCity = city;
              });
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _aadharController,
                label: 'Aadhar Card Number',
                icon: Icons.credit_card,
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (value!.length != 12) return 'Must be 12 digits';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _panController,
                label: 'PAN Number',
                icon: Icons.credit_card,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  LengthLimitingTextInputFormatter(10),
                ],
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (value!.length != 10) return 'Must be 10 characters';
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContactSection() {
    return _buildSection(
      title: 'Emergency Contact',
      icon: Icons.emergency,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _contactNameController,
                label: 'Contact Person Name',
                icon: Icons.person_outline,
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _relationshipController,
                label: 'Relationship',
                icon: Icons.family_restroom,
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _contactPhoneController,
                label: 'Contact Phone',
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (value!.length != 10) return 'Must be 10 digits';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _contactAltPhoneController,
                label: 'Contact Alternate Phone',
                icon: Icons.phone_android,
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (value!.length != 10) return 'Must be 10 digits';
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEducationBankSection() {
    return _buildSection(
      title: 'Education & Bank Details',
      icon: Icons.school,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _degreeController,
                label: 'University Degree',
                icon: Icons.school,
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _yearController,
                label: 'Year of Completion',
                icon: Icons.calendar_today,
                keyboardType: TextInputType.number,
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _percentageController,
                label: 'Percentage / CGPA',
                icon: Icons.grade,
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _bankAccountController,
                label: 'Bank Account Number',
                icon: Icons.account_balance_wallet,
                keyboardType: TextInputType.number,
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _ifscController,
                label: 'IFSC Code',
                icon: Icons.code,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  LengthLimitingTextInputFormatter(11),
                ],
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (value!.length != 11) return 'Must be 11 characters';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _bankBranchController,
                label: 'Bank Branch',
                icon: Icons.location_city,
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOfficialSection() {
    return _buildSection(
      title: 'Official Information',
      icon: Icons.work,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _emailController,
                label: 'Official Email ID',
                icon: Icons.email,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (!value!.contains('@')) return 'Invalid email';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDateField(
                controller: _hireDateController,
                label: 'Date of Joining',
                icon: Icons.calendar_today,
                onTap: () => _pickDate(context, true),
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDropdown(
                label: 'Department',
                value: _selectedDepartment,
                items: _departments.map((d) => d['name'].toString()).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedDepartment = value;
                    _selectedPosition = null;
                  });
                  if (value != null) {
                    _filterPositionsByDepartment(value);
                  }
                },
                icon: Icons.business,
                validator: (value) => value == null ? 'Required' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildDropdown(
                label: 'Designation/Position',
                value: _selectedPosition,
                items: _positions.map((p) => p['title'].toString()).toList(),
                onChanged: (value) => setState(() => _selectedPosition = value),
                icon: Icons.work_outline,
                validator: (value) => value == null ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSearchableDropdown(
                label: 'Reporting Manager 1',
                value: _selectedReportingManager1,
                items: _employees,
                onChanged: (value) => setState(() => _selectedReportingManager1 = value),
                icon: Icons.person,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSearchableDropdown(
                label: 'Reporting Manager 2',
                value: _selectedReportingManager2,
                items: _employees,
                onChanged: (value) => setState(() => _selectedReportingManager2 = value),
                icon: Icons.person_outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildDropdown(
                label: 'Status',
                value: _selectedStatus,
                items: ['Active', 'Inactive', 'Terminated'],
                onChanged: (value) => setState(() => _selectedStatus = value),
                icon: Icons.toggle_on,
                validator: (value) => value == null ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDropdown(
                label: 'Employee Type',
                value: _selectedEmployeeType,
                items: ['Probation period', 'Permanent Employee'],
                onChanged: (value) => setState(() => _selectedEmployeeType = value),
                icon: Icons.badge,
                validator: (value) => value == null ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _salaryController,
                label: 'Total Salary (₹)',
                icon: Icons.attach_money,
                keyboardType: TextInputType.number,
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildDropdown(
                label: 'Work Location',
                value: _selectedWorkLocation,
                items: _locations.map((l) => l['locationName'].toString()).toList(),
                onChanged: (value) => setState(() => _selectedWorkLocation = value),
                icon: Icons.location_on,
                validator: (value) => value == null ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDropdown(
                label: 'Company Name',
                value: _selectedCompany,
                items: _companies.map((c) => c['companyName'].toString()).toList(),
                onChanged: (value) => setState(() => _selectedCompany = value),
                icon: Icons.business_center,
                validator: (value) => value == null ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDropdown(
                label: 'Timings',
                value: _selectedTiming,
                items: _timings.map((t) => '${t['startTime']} - ${t['endTime']}').toList(),
                onChanged: (value) => setState(() => _selectedTiming = value),
                icon: Icons.access_time,
                validator: (value) => value == null ? 'Required' : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDocumentsSection() {
    return _buildSection(
      title: 'Documents Upload',
      icon: Icons.upload_file,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1B7FA8).withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1B7FA8).withOpacity(0.2)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Color(0xFF1B7FA8)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Allowed: JPG, PNG, PDF, DOC, DOCX (Max 5MB per file)',
                  style: TextStyle(fontSize: 13, color: Color(0xFF1B7FA8)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _pickDocuments,
          icon: const Icon(Icons.add_photo_alternate),
          label: const Text('Add Documents'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1B7FA8),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        if (_documents.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            'New Documents:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 12),
          ..._documents.asMap().entries.map((entry) {
            final index = entry.key;
            final file = entry.value;
            final metadata = _documentMetadata[index];
            
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getFileIcon(file.path),
                      color: const Color(0xFF10B981),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metadata['documentType']!,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          metadata['filename']!,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _removeDocument(index),
                    icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
        if (_existingDocuments.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text(
            'Existing Documents:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 12),
          ..._existingDocuments.map((doc) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B7FA8).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getFileIcon(doc['filename']),
                      color: const Color(0xFF1B7FA8),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc['documentType'] ?? 'Document',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          doc['filename'] ?? 'Unknown',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _deleteExistingDocument(doc),
                    icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ],
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveEmployee,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: _isSaving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Text(
                _isEditMode ? 'Update Employee' : 'Save Employee',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B7FA8).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF1B7FA8), size: 24),
              ),
              const SizedBox(width: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3E50),
                ),
              ),
            ],
          ),
          const Divider(height: 32, color: Color(0xFFE2E8F0)),
          ...children,
        ],
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
    Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF1B7FA8)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1B7FA8), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildDateField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      validator: validator,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF1B7FA8)),
        suffixIcon: const Icon(Icons.calendar_today, color: Color(0xFF64748B)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1B7FA8), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
    required IconData icon,
    String? Function(String?)? validator,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF1B7FA8)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1B7FA8), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildSearchableDropdown({
    required String label,
    required String? value,
    required List<Map<String, dynamic>> items,
    required Function(String?) onChanged,
    required IconData icon,
  }) {
    final selectedEmployee = items.firstWhere(
      (e) => e['employeeId'] == value,
      orElse: () => {},
    );
    
    return InkWell(
      onTap: () => _showEmployeeSearchDialog(label, items, onChanged),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF1B7FA8)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selectedEmployee.isNotEmpty
                        ? '${selectedEmployee['name']} (${selectedEmployee['employeeId']})'
                        : 'Select Manager',
                    style: TextStyle(
                      fontSize: 15,
                      color: selectedEmployee.isNotEmpty
                          ? const Color(0xFF1E293B)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  void _showEmployeeSearchDialog(
    String label,
    List<Map<String, dynamic>> items,
    Function(String?) onChanged,
  ) {
    final searchController = TextEditingController();
    List<Map<String, dynamic>> filtered = items;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(label),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by name or ID...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        filtered = items.where((e) {
                          final name = e['name'].toString().toLowerCase();
                          final id = e['employeeId'].toString().toLowerCase();
                          final query = value.toLowerCase();
                          return name.contains(query) || id.contains(query);
                        }).toList();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 300,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final emp = filtered[index];
                        return ListTile(
                          title: Text(emp['name']),
                          subtitle: Text('${emp['employeeId']} • ${emp['position']}'),
                          onTap: () {
                            onChanged(emp['employeeId']);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  onChanged(null);
                  Navigator.pop(context);
                },
                child: const Text('Clear'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _getFileIcon(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }
}