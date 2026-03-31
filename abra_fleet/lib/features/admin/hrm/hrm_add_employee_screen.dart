// ============================================================================
// HRM ADD EMPLOYEE SCREEN
// ============================================================================
// Complete employee add form with all fields, dropdowns, document upload
// Matching Master Settings UI design
// ============================================================================

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:country_state_city/country_state_city.dart' as csc;
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../../../core/services/hrm_employee_service.dart';
import '../../../app/config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HRMAddEmployeeScreen extends StatefulWidget {
  const HRMAddEmployeeScreen({Key? key}) : super(key: key);

  @override
  State<HRMAddEmployeeScreen> createState() => _HRMAddEmployeeScreenState();
}

class _HRMAddEmployeeScreenState extends State<HRMAddEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();
  final HRMEmployeeService _service = HRMEmployeeService();
  
  // ── Controllers ────────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _personalEmailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _altPhoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _aadharCtrl = TextEditingController();
  final _panCtrl = TextEditingController();
  final _contactNameCtrl = TextEditingController();
  final _relationshipCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();
  final _contactAltPhoneCtrl = TextEditingController();
  final _degreeCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _cgpaCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();
  final _salaryCtrl = TextEditingController();
  final _manualTimingsCtrl = TextEditingController();
  
  // ── Selected Values ────────────────────────────────────────────────────
  DateTime? _hireDate;
  DateTime? _dob;
  String? _gender;
  String? _bloodGroup;
  String? _department;
  String? _position;
  String? _status = 'Active';
  String? _employeeType;
  String? _workLocation;
  String? _company;
  String? _timings;
  String? _reportingManager1;
  String? _reportingManager2;
  String? _countryName;
  String? _stateName;
  
  // ── Data Lists ─────────────────────────────────────────────────────────
  List<String> _departments = [];
  List<String> _positions = [];
  List<String> _workLocations = [];
  List<String> _companies = [];
  List<String> _timingsList = [];
  List<Map<String, dynamic>> _employees = [];
  List<csc.Country> _countries = [];
  List<csc.State> _states = [];
  
  // ── Loading States ─────────────────────────────────────────────────────
  bool _isLoading = false;
  bool _loadingMasterData = true;
  
  // ── Documents ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _documents = [];
  
  // ── Document Files (Web-compatible) ────────────────────────────────────
  List<PlatformFile> _documentFiles = [];
  
  // ── Static Options ─────────────────────────────────────────────────────
  final List<String> _genderOptions = ['Male', 'Female', 'Other'];
  final List<String> _bloodGroupOptions = [
    'A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'
  ];
  final List<String> _statusOptions = ['Active', 'Inactive', 'Terminated'];
  final List<String> _employeeTypeOptions = [
    'Probation period',
    'Permanent Employee'
  ];
  final List<String> _documentTypes = [
    'Aadhar Card', 'PAN Card', 'Passport', 'Driving License',
    '10th Marksheet', '12th Marksheet', 'Degree Certificate',
    'Resume/CV', 'Experience Letter', 'Bank Passbook',
    'Cancelled Cheque', 'Photo', 'Medical Certificate',
    'Police Verification', 'Other'
  ];
  
  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }
  
  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _personalEmailCtrl.dispose();
    _phoneCtrl.dispose();
    _altPhoneCtrl.dispose();
    _addressCtrl.dispose();
    _aadharCtrl.dispose();
    _panCtrl.dispose();
    _contactNameCtrl.dispose();
    _relationshipCtrl.dispose();
    _contactPhoneCtrl.dispose();
    _contactAltPhoneCtrl.dispose();
    _degreeCtrl.dispose();
    _yearCtrl.dispose();
    _cgpaCtrl.dispose();
    _accountCtrl.dispose();
    _ifscCtrl.dispose();
    _branchCtrl.dispose();
    _salaryCtrl.dispose();
    _manualTimingsCtrl.dispose();
    super.dispose();
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // DATA LOADING
  // ═══════════════════════════════════════════════════════════════════════
  
  Future<void> _loadInitialData() async {
    setState(() {
      _loadingMasterData = true;
    });
    
    await Future.wait([
      _loadDepartments(),
      _loadPositions(),
      _loadWorkLocations(),
      _loadCompanies(),
      _loadTimings(),
      _loadEmployees(),
      _loadCountries(),
    ]);
    
    setState(() {
      _loadingMasterData = false;
    });
  }
  
  Future<void> _loadDepartments() async {
    try {
      final list = await _service.getDepartments();
      setState(() {
        _departments = list;
      });
    } catch (e) {
      print('❌ Error loading departments: $e');
    }
  }
  
  Future<void> _loadPositions() async {
    try {
      final list = await _service.getPositions();
      setState(() {
        _positions = list;
      });
    } catch (e) {
      print('❌ Error loading positions: $e');
    }
  }
  
  Future<void> _loadWorkLocations() async {
    try {
      final list = await _service.getWorkLocations();
      setState(() {
        _workLocations = list;
      });
    } catch (e) {
      print('❌ Error loading work locations: $e');
    }
  }
  
  Future<void> _loadCompanies() async {
    try {
      final list = await _service.getCompanies();
      setState(() {
        _companies = list;
      });
    } catch (e) {
      print('❌ Error loading companies: $e');
    }
  }
  
  Future<void> _loadTimings() async {
    try {
      final list = await _service.getTimings();
      setState(() {
        _timingsList = list;
      });
    } catch (e) {
      print('❌ Error loading timings: $e');
    }
  }
  
  Future<void> _loadEmployees() async {
    try {
      print('👥 Loading employees for reporting manager dropdown...');
      final list = await _service.getEmployeesList();
      print('✅ Loaded ${list.length} employees');
      if (list.isNotEmpty) {
        print('📋 First employee: ${list.first}');
      }
      setState(() {
        _employees = list;
      });
    } catch (e) {
      print('❌ Error loading employees: $e');
    }
  }
  
  Future<void> _loadCountries() async {
    try {
      final list = await csc.getAllCountries();
      setState(() {
        _countries = list..sort((a, b) => a.name.compareTo(b.name));
      });
    } catch (e) {
      print('❌ Error loading countries: $e');
    }
  }
  
  Future<void> _loadStates(String countryIso) async {
    try {
      final list = await csc.getStatesOfCountry(countryIso);
      setState(() {
        _states = list..sort((a, b) => a.name.compareTo(b.name));
        _stateName = null;
      });
    } catch (e) {
      print('❌ Error loading states: $e');
    }
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // DOCUMENT HANDLING (WEB-COMPATIBLE)
  // ═══════════════════════════════════════════════════════════════════════
  
  void _addDocument() {
    setState(() {
      _documents.add({
        'type': null,
        'customName': null,
        'file': null,
      });
      _documentFiles.add(PlatformFile(name: '', size: 0));
    });
  }
  
  void _removeDocument(int index) {
    setState(() {
      _documents.removeAt(index);
      _documentFiles.removeAt(index);
    });
  }
  
  Future<void> _pickDocument(int index) async {
    try {
      print('📎 Picking document for index $index...');
      
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
        withData: kIsWeb, // ✅ Load bytes for web
      );
      
      if (result != null && result.files.isNotEmpty) {
        final platformFile = result.files.single;
        
        print('📄 File picked: ${platformFile.name}');
        print('📏 File size: ${platformFile.size} bytes');
        print('🌐 Platform: ${kIsWeb ? "Web" : "Mobile"}');
        
        // File size validation (2MB for images, 5MB for documents)
        final ext = platformFile.extension?.toLowerCase();
        final isImage = ['jpg', 'jpeg', 'png'].contains(ext);
        final maxSize = isImage ? 2 * 1024 * 1024 : 5 * 1024 * 1024;
        
        if (platformFile.size > maxSize) {
          _showErrorSnackbar(
              'File too large! Max ${isImage ? "2" : "5"} MB for ${isImage ? "images" : "documents"}');
          return;
        }
        
        // ✅ Store PlatformFile (works for both web and mobile)
        setState(() {
          _documentFiles[index] = platformFile;
          _documents[index]['file'] = platformFile.name; // Store name for display
        });
        
        print('✅ Document stored successfully');
      }
    } catch (e) {
      print('❌ Error picking file: $e');
      _showErrorSnackbar('Failed to pick file: $e');
    }
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // SAVE EMPLOYEE (WEB-COMPATIBLE FILE UPLOAD)
  // ═══════════════════════════════════════════════════════════════════════
  
  Future<void> _saveEmployee() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackbar('Please fill all required fields');
      return;
    }
    
    // Additional validation
    if (_hireDate == null) {
      _showErrorSnackbar('Please select hire date');
      return;
    }
    
    if (_dob == null) {
      _showErrorSnackbar('Please select date of birth');
      return;
    }
    
    // ✅ Validate Personal Email is not empty
    if (_personalEmailCtrl.text.trim().isEmpty) {
      _showErrorSnackbar('Personal Email is required');
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      print('➕ Creating employee...');
      
      // Get JWT token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      
      if (token == null || token.isEmpty) {
        throw Exception('Not authenticated. Please login again.');
      }
      
      // ✅ Use multipart request for web-compatible file upload
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/employees'),
      );
      
      request.headers['Authorization'] = 'Bearer $token';
      
      // Add all employee data as fields
      request.fields['name'] = _nameCtrl.text.trim();
      request.fields['email'] = _emailCtrl.text.trim();
      request.fields['personalEmail'] = _personalEmailCtrl.text.trim();
      request.fields['phone'] = _phoneCtrl.text.trim();
      request.fields['altPhone'] = _altPhoneCtrl.text.trim();
      request.fields['address'] = _addressCtrl.text.trim();
      request.fields['country'] = _countryName ?? '';
      request.fields['state'] = _stateName ?? '';
      request.fields['gender'] = _gender ?? '';
      request.fields['dob'] = _dob!.toIso8601String();
      request.fields['bloodGroup'] = _bloodGroup ?? '';
      request.fields['aadharCard'] = _aadharCtrl.text.trim();
      request.fields['panNumber'] = _panCtrl.text.trim().toUpperCase();
      request.fields['contactName'] = _contactNameCtrl.text.trim();
      request.fields['relationship'] = _relationshipCtrl.text.trim();
      request.fields['contactPhone'] = _contactPhoneCtrl.text.trim();
      request.fields['contactAltPhone'] = _contactAltPhoneCtrl.text.trim();
      request.fields['universityDegree'] = _degreeCtrl.text.trim();
      request.fields['yearCompletion'] = _yearCtrl.text.trim();
      request.fields['percentageCgpa'] = _cgpaCtrl.text.trim();
      request.fields['bankAccountNumber'] = _accountCtrl.text.trim();
      request.fields['ifscCode'] = _ifscCtrl.text.trim().toUpperCase();
      request.fields['bankBranch'] = _branchCtrl.text.trim();
      request.fields['hireDate'] = _hireDate!.toIso8601String();
      request.fields['department'] = _department ?? '';
      request.fields['position'] = _position ?? '';
      request.fields['reportingManager1'] = _reportingManager1 ?? '';
      request.fields['reportingManager2'] = _reportingManager2 ?? '';
      request.fields['status'] = _status ?? 'Active';
      request.fields['employeeType'] = _employeeType ?? '';
      request.fields['salary'] = _salaryCtrl.text.trim();
      request.fields['workLocation'] = _workLocation ?? '';
      request.fields['companyName'] = _company ?? '';
      request.fields['timings'] = _timings == 'Manual'
          ? _manualTimingsCtrl.text.trim()
          : _timings ?? '';
      
      // ✅ Add documents with metadata (web-compatible)
      final documentMetadata = <Map<String, String>>[];
      
      for (int i = 0; i < _documents.length; i++) {
        final doc = _documents[i];
        final platformFile = _documentFiles[i];
        
        if (doc['type'] != null && platformFile.name.isNotEmpty) {
          // Add document metadata
          documentMetadata.add({
            'documentType': doc['type'] == 'Other'
                ? (doc['customName'] ?? 'Other')
                : doc['type'],
          });
          
          // ✅ Add file (works for both web and mobile)
          if (kIsWeb) {
            // Web: Use bytes
            if (platformFile.bytes != null) {
              request.files.add(
                http.MultipartFile.fromBytes(
                  'documents',
                  platformFile.bytes!,
                  filename: platformFile.name,
                ),
              );
            }
          } else {
            // Mobile: Use path
            if (platformFile.path != null) {
              request.files.add(
                await http.MultipartFile.fromPath(
                  'documents',
                  platformFile.path!,
                  filename: platformFile.name,
                ),
              );
            }
          }
        }
      }
      
      // Add document metadata as JSON string
      if (documentMetadata.isNotEmpty) {
        request.fields['documentMetadata'] = jsonEncode(documentMetadata);
      }
      
      print('📤 Sending request with ${request.files.length} files...');
      
      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      print('📡 Response Status: ${response.statusCode}');
      print('📡 Response Body: ${response.body}');
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          setState(() {
            _isLoading = false;
          });
          
          _showSuccessSnackbar('Employee created successfully');
          Navigator.pop(context, true);
        } else {
          throw Exception(data['message'] ?? 'Failed to create employee');
        }
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? data['error'] ?? 'Request failed');
      }
    } catch (e) {
      print('❌ Error creating employee: $e');
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackbar('Failed to create employee: $e');
    }
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // SNACKBAR HELPERS
  // ═══════════════════════════════════════════════════════════════════════
  
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
  
  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Add New Employee',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF334155),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loadingMasterData
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF334155)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── OFFICIAL INFORMATION ─────────────────────────
                    _buildSectionTitle(
                        'Official Information', Icons.business_center),
                    _buildFormContainer([
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _emailCtrl,
                              label: 'Official Email',
                              required: true,
                              keyboardType: TextInputType.emailAddress,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildDateField(
                              label: 'Date of Joining',
                              value: _hireDate,
                              onTap: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (date != null) {
                                  setState(() {
                                    _hireDate = date;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDropdown(
                              label: 'Department',
                              value: _department,
                              items: _departments,
                              onChanged: (val) =>
                                  setState(() => _department = val),
                              required: true,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildDropdown(
                              label: 'Position',
                              value: _position,
                              items: _positions,
                              onChanged: (val) =>
                                  setState(() => _position = val),
                              required: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _employees.isEmpty
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Reporting Manager 1',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF334155),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF3C7),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: const Color(0xFFF59E0B),
                                          ),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(
                                              Icons.info_outline,
                                              color: Color(0xFFF59E0B),
                                              size: 20,
                                            ),
                                            SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'No employees available',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Color(0xFF92400E),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                : _buildDropdown(
                                    label: 'Reporting Manager 1',
                                    value: _reportingManager1,
                                    items: _employees
                                        .map((e) =>
                                            '${e['name']} (${e['employeeId']})')
                                        .toList(),
                                    onChanged: (val) {
                                      final emp = _employees.firstWhere(
                                        (e) =>
                                            '${e['name']} (${e['employeeId']})' ==
                                            val,
                                      );
                                      setState(() =>
                                          _reportingManager1 = emp['employeeId']);
                                    },
                                  ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _employees.isEmpty
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Reporting Manager 2',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF334155),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF3C7),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: const Color(0xFFF59E0B),
                                          ),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(
                                              Icons.info_outline,
                                              color: Color(0xFFF59E0B),
                                              size: 20,
                                            ),
                                            SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'No employees available',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Color(0xFF92400E),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                : _buildDropdown(
                                    label: 'Reporting Manager 2',
                                    value: _reportingManager2,
                                    items: _employees
                                        .map((e) =>
                                            '${e['name']} (${e['employeeId']})')
                                        .toList(),
                                    onChanged: (val) {
                                      final emp = _employees.firstWhere(
                                        (e) =>
                                            '${e['name']} (${e['employeeId']})' ==
                                            val,
                                      );
                                      setState(() =>
                                          _reportingManager2 = emp['employeeId']);
                                    },
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
                              value: _status,
                              items: _statusOptions,
                              onChanged: (val) =>
                                  setState(() => _status = val),
                              required: true,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildDropdown(
                              label: 'Employee Type',
                              value: _employeeType,
                              items: _employeeTypeOptions,
                              onChanged: (val) =>
                                  setState(() => _employeeType = val),
                              required: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _salaryCtrl,
                              label: 'Total Salary (₹)',
                              required: true,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildDropdown(
                              label: 'Work Location',
                              value: _workLocation,
                              items: _workLocations,
                              onChanged: (val) =>
                                  setState(() => _workLocation = val),
                              required: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDropdown(
                              label: 'Company',
                              value: _company,
                              items: _companies,
                              onChanged: (val) =>
                                  setState(() => _company = val),
                              required: true,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildDropdown(
                              label: 'Timings',
                              value: _timings,
                              items: [..._timingsList, 'Manual'],
                              onChanged: (val) =>
                                  setState(() => _timings = val),
                              required: true,
                            ),
                          ),
                        ],
                      ),
                      if (_timings == 'Manual') ...[
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _manualTimingsCtrl,
                          label: 'Manual Timings',
                          hint: 'e.g. 09:00 AM - 06:00 PM',
                          required: true,
                        ),
                      ],
                    ]),
                    
                    const SizedBox(height: 24),
                    
                    // ── PERSONAL INFORMATION ──────────────────────────
                    _buildSectionTitle('Personal Information', Icons.person),
                    _buildFormContainer([
                      _buildTextField(
                        controller: _nameCtrl,
                        label: 'Full Name',
                        required: true,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDropdown(
                              label: 'Gender',
                              value: _gender,
                              items: _genderOptions,
                              onChanged: (val) =>
                                  setState(() => _gender = val),
                              required: true,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildDateField(
                              label: 'Date of Birth',
                              value: _dob,
                              onTap: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime(1990),
                                  firstDate: DateTime(1950),
                                  lastDate: DateTime.now(),
                                );
                                if (date != null) {
                                  setState(() {
                                    _dob = date;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDropdown(
                              label: 'Blood Group',
                              value: _bloodGroup,
                              items: _bloodGroupOptions,
                              onChanged: (val) =>
                                  setState(() => _bloodGroup = val),
                              required: true,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTextField(
                              controller: _phoneCtrl,
                              label: 'Mobile Number',
                              required: true,
                              keyboardType: TextInputType.phone,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _altPhoneCtrl,
                              label: 'Alternate Phone',
                              required: true,
                              keyboardType: TextInputType.phone,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTextField(
                              controller: _personalEmailCtrl,
                              label: 'Personal Email',
                              required: true,
                              keyboardType: TextInputType.emailAddress,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildCountryDropdown(),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildStateDropdown(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _addressCtrl,
                        label: 'Residential Address',
                        required: true,
                        maxLines: 3,
                      ),
                    ]),
                    
                    const SizedBox(height: 24),
                    
                    // ── IDENTITY DOCUMENTS ─────────────────────────────
                    _buildSectionTitle(
                        'Identity Documents', Icons.badge_outlined),
                    _buildFormContainer([
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _aadharCtrl,
                              label: 'Aadhar Card Number',
                              required: true,
                              keyboardType: TextInputType.number,
                              maxLength: 12,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTextField(
                              controller: _panCtrl,
                              label: 'PAN Number',
                              required: true,
                              textCapitalization: TextCapitalization.characters,
                              maxLength: 10,
                            ),
                          ),
                        ],
                      ),
                    ]),
                    
                    const SizedBox(height: 24),
                    
                    // ── EMERGENCY CONTACT ───────────────────────────────
                    _buildSectionTitle(
                        'Emergency Contact', Icons.phone_in_talk),
                    _buildFormContainer([
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _contactNameCtrl,
                              label: 'Contact Name',
                              required: true,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTextField(
                              controller: _relationshipCtrl,
                              label: 'Relationship',
                              required: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _contactPhoneCtrl,
                              label: 'Phone Number',
                              required: true,
                              keyboardType: TextInputType.phone,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTextField(
                              controller: _contactAltPhoneCtrl,
                              label: 'Alternate Phone',
                              required: true,
                              keyboardType: TextInputType.phone,
                            ),
                          ),
                        ],
                      ),
                    ]),
                    
                    const SizedBox(height: 24),
                    
                    // ── EDUCATION ───────────────────────────────────────
                    _buildSectionTitle('Education', Icons.school),
                    _buildFormContainer([
                      _buildTextField(
                        controller: _degreeCtrl,
                        label: 'Degree/University',
                        required: true,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _yearCtrl,
                              label: 'Year of Completion',
                              required: true,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTextField(
                              controller: _cgpaCtrl,
                              label: 'Percentage/CGPA',
                              required: true,
                            ),
                          ),
                        ],
                      ),
                    ]),
                    
                    const SizedBox(height: 24),
                    
                    // ── BANK DETAILS ────────────────────────────────────
                    _buildSectionTitle('Bank Details', Icons.account_balance),
                    _buildFormContainer([
                      _buildTextField(
                        controller: _accountCtrl,
                        label: 'Bank Account Number',
                        required: true,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _ifscCtrl,
                              label: 'IFSC Code',
                              required: true,
                              textCapitalization: TextCapitalization.characters,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTextField(
                              controller: _branchCtrl,
                              label: 'Bank Branch',
                              required: true,
                            ),
                          ),
                        ],
                      ),
                    ]),
                    
                    const SizedBox(height: 24),
                    
                    // ── UPLOAD DOCUMENTS ────────────────────────────────
                    _buildSectionTitle(
                        'Upload Documents', Icons.file_upload_outlined),
                    _buildFormContainer([
                      const Text(
                        '📄 Upload Documents: Aadhar, PAN, Resume, etc.\n'
                        '📏 Size Limits: Photos/Images: 2 MB | Documents: 5 MB',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._documents.asMap().entries.map((entry) {
                        final index = entry.key;
                        final doc = entry.value;
                        return _buildDocumentRow(index, doc);
                      }).toList(),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _addDocument,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Document'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF10B981),
                          side: const BorderSide(color: Color(0xFF10B981)),
                        ),
                      ),
                    ]),
                    
                    const SizedBox(height: 32),
                    
                    // ── SUBMIT BUTTON ────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveEmployee,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF334155),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.save),
                                  SizedBox(width: 8),
                                  Text(
                                    'Save Employee',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // UI BUILDERS
  // ═══════════════════════════════════════════════════════════════════════
  
  Widget _buildSectionTitle(String title, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF334155), Color(0xFF1E40AF)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E3A8A),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFormContainer(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
  
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    bool required = false,
    TextInputType? keyboardType,
    int? maxLines,
    int? maxLength,
    String? hint,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            if (required)
              const Text(
                ' *',
                style: TextStyle(
                  color: Color(0xFFDC2626),
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines ?? 1,
          maxLength: maxLength,
          textCapitalization: textCapitalization,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.normal,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF1E40AF), width: 2),
            ),
          ),
          validator: required
              ? (val) => val?.trim().isEmpty ?? true
                  ? '$label is required'
                  : null
              : null,
        ),
      ],
    );
  }
  
  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
    bool required = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            if (required)
              const Text(
                ' *',
                style: TextStyle(
                  color: Color(0xFFDC2626),
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          items: items.map((item) {
            return DropdownMenuItem(
              value: item,
              child: Text(item),
            );
          }).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF1E40AF), width: 2),
            ),
          ),
          validator: required
              ? (val) => val == null ? '$label is required' : null
              : null,
        ),
      ],
    );
  }
  
  Widget _buildDateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            const Text(
              ' *',
              style: TextStyle(
                color: Color(0xFFDC2626),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 18,
                  color: value != null
                      ? const Color(0xFF334155)
                      : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 12),
                Text(
                  value != null
                      ? DateFormat('dd/MM/yyyy').format(value)
                      : 'Select Date',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: value != null
                        ? const Color(0xFF334155)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildCountryDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Text(
              'Country',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            Text(
              ' *',
              style: TextStyle(
                color: Color(0xFFDC2626),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _countryName,
          items: _countries.map((country) {
            return DropdownMenuItem(
              value: country.name,
              child: Text(country.name),
            );
          }).toList(),
          onChanged: (val) {
            final country = _countries.firstWhere((c) => c.name == val);
            setState(() {
              _countryName = val;
              _stateName = null;
            });
            _loadStates(country.isoCode);
          },
          decoration: InputDecoration(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF1E40AF), width: 2),
            ),
          ),
          validator: (val) => val == null ? 'Country is required' : null,
        ),
      ],
    );
  }
  
  Widget _buildStateDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Text(
              'State',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            Text(
              ' *',
              style: TextStyle(
                color: Color(0xFFDC2626),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _stateName,
          items: _states.map((state) {
            return DropdownMenuItem(
              value: state.name,
              child: Text(state.name),
            );
          }).toList(),
          onChanged: _countryName == null
              ? null
              : (val) {
                  setState(() {
                    _stateName = val;
                  });
                },
          decoration: InputDecoration(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF1E40AF), width: 2),
            ),
          ),
          validator: (val) => val == null ? 'State is required' : null,
        ),
      ],
    );
  }
  
  Widget _buildDocumentRow(int index, Map<String, dynamic> doc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: doc['type'],
              decoration: const InputDecoration(
                labelText: 'Document Type',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _documentTypes.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _documents[index]['type'] = val;
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          if (doc['type'] == 'Other')
            Expanded(
              flex: 2,
              child: TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Custom Name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (val) {
                  setState(() {
                    _documents[index]['customName'] = val;
                  });
                },
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: OutlinedButton.icon(
              onPressed: () => _pickDocument(index),
              icon: Icon(
                doc['file'] != null ? Icons.check_circle : Icons.upload_file,
                size: 18,
              ),
              label: Text(
                doc['file'] != null
                    ? 'File Selected'
                    : 'Choose File',
                style: const TextStyle(fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: doc['file'] != null
                    ? const Color(0xFF10B981)
                    : const Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete, color: Color(0xFFDC2626)),
            onPressed: () => _removeDocument(index),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}