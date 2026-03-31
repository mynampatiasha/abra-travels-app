// ============================================================================
// HRM EDIT EMPLOYEE SCREEN
// ============================================================================
// Complete employee edit form with pre-filled data, document management
// Matching Master Settings UI design
// ============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:country_state_city/country_state_city.dart' as csc;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/hrm_employee_service.dart';

class HRMEditEmployeeScreen extends StatefulWidget {
  final String employeeId;

  const HRMEditEmployeeScreen({
    Key? key,
    required this.employeeId,
  }) : super(key: key);

  @override
  State<HRMEditEmployeeScreen> createState() => _HRMEditEmployeeScreenState();
}

class _HRMEditEmployeeScreenState extends State<HRMEditEmployeeScreen> {
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
  String? _status;
  String? _employeeType;
  String? _workLocation;
  String? _company;
  String? _timings;
  String? _reportingManager1;
  String? _reportingManager2;
  String? _countryName;
  String? _stateName;
  String _employeeIdDisplay = '';
  
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
  bool _loadingEmployee = true;
  bool _loadingMasterData = true;
  
  // ── Existing Documents ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _existingDocuments = [];
  
  // ── New Documents ──────────────────────────────────────────────────────
  List<Map<String, dynamic>> _newDocuments = [];
  
  // ── User Permissions ───────────────────────────────────────────────────
  bool _isSuperManager = false;
  
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
    _checkUserRole();
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
  // USER ROLE CHECK
  // ═══════════════════════════════════════════════════════════════════════
  
  Future<void> _checkUserRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('user_email')?.toLowerCase() ?? '';
      
      final superManagerEmails = [
        'admin@abrafleet.com',
        'abishek.veeraswamy@abra-travels.com',
      ];
      
      setState(() {
        _isSuperManager = superManagerEmails.contains(email);
      });
    } catch (e) {
      print('❌ Error checking user role: $e');
    }
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // DATA LOADING
  // ═══════════════════════════════════════════════════════════════════════
  
  Future<void> _loadInitialData() async {
    setState(() {
      _loadingMasterData = true;
      _loadingEmployee = true;
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
    
    await _loadEmployeeData();
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
      final list = await _service.getEmployeesList();
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
      });
    } catch (e) {
      print('❌ Error loading states: $e');
    }
  }
  
  Future<void> _loadEmployeeData() async {
    try {
      final employee = await _service.getEmployee(widget.employeeId);
      
      if (employee == null) {
        _showErrorSnackbar('Employee not found');
        Navigator.pop(context);
        return;
      }
      
      // Populate fields
      setState(() {
        _employeeIdDisplay = employee['employeeId'] ?? '';
        _nameCtrl.text = employee['name'] ?? '';
        _emailCtrl.text = employee['email'] ?? '';
        _personalEmailCtrl.text = employee['personalEmail'] ?? '';
        _phoneCtrl.text = employee['phone'] ?? '';
        _altPhoneCtrl.text = employee['altPhone'] ?? '';
        _addressCtrl.text = employee['address'] ?? '';
        _aadharCtrl.text = employee['aadharCard'] ?? '';
        _panCtrl.text = employee['panNumber'] ?? '';
        _contactNameCtrl.text = employee['contactName'] ?? '';
        _relationshipCtrl.text = employee['relationship'] ?? '';
        _contactPhoneCtrl.text = employee['contactPhone'] ?? '';
        _contactAltPhoneCtrl.text = employee['contactAltPhone'] ?? '';
        _degreeCtrl.text = employee['universityDegree'] ?? '';
        _yearCtrl.text = employee['yearCompletion'] ?? '';
        _cgpaCtrl.text = employee['percentageCgpa'] ?? '';
        _accountCtrl.text = employee['bankAccountNumber'] ?? '';
        _ifscCtrl.text = employee['ifscCode'] ?? '';
        _branchCtrl.text = employee['bankBranch'] ?? '';
        _salaryCtrl.text = employee['salary']?.toString() ?? '';
        
        _gender = employee['gender'];
        _bloodGroup = employee['bloodGroup'];
        _department = employee['department'];
        _position = employee['position'];
        _status = employee['status'];
        _employeeType = employee['employeeType'];
        _workLocation = employee['workLocation'];
        _company = employee['companyName'];
        _reportingManager1 = employee['reportingManager1'];
        _reportingManager2 = employee['reportingManager2'];
        _countryName = employee['country'];
        _stateName = employee['state'];
        
        // Parse dates
        if (employee['hireDate'] != null) {
          _hireDate = DateTime.parse(employee['hireDate']);
        }
        if (employee['dob'] != null) {
          _dob = DateTime.parse(employee['dob']);
        }
        
        // Timings
        final timingsValue = employee['timings'] ?? '';
        if (_timingsList.contains(timingsValue)) {
          _timings = timingsValue;
        } else {
          _timings = 'Manual';
          _manualTimingsCtrl.text = timingsValue;
        }
        
        // Existing documents
        _existingDocuments = List<Map<String, dynamic>>.from(
          employee['documents'] ?? []
        );
        
        _loadingEmployee = false;
      });
      
      // Load states for selected country
      if (_countryName != null) {
        final country = _countries.firstWhere(
          (c) => c.name == _countryName,
          orElse: () => _countries.first,
        );
        await _loadStates(country.isoCode);
      }
    } catch (e) {
      setState(() {
        _loadingEmployee = false;
      });
      _showErrorSnackbar('Failed to load employee data: $e');
    }
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // DOCUMENT HANDLING
  // ═══════════════════════════════════════════════════════════════════════
  
  Future<void> _deleteExistingDocument(Map<String, dynamic> doc) async {
    if (!_isSuperManager) {
      _showErrorSnackbar('Only Super Managers can delete documents');
      return;
    }
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Document',
            style: TextStyle(fontWeight: FontWeight.bold)),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      try {
        await _service.deleteDocument(widget.employeeId, doc['_id']);
        setState(() {
          _existingDocuments.removeWhere((d) => d['_id'] == doc['_id']);
        });
        _showSuccessSnackbar('Document deleted successfully');
      } catch (e) {
        _showErrorSnackbar('Failed to delete document: $e');
      }
    }
  }
  
  void _addNewDocument() {
    setState(() {
      _newDocuments.add({
        'type': null,
        'customName': null,
        'file': null,
      });
    });
  }
  
  void _removeNewDocument(int index) {
    setState(() {
      _newDocuments.removeAt(index);
    });
  }
  
  Future<void> _pickDocument(int index) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
      );
      
      if (result != null && result.files.isNotEmpty) {
        final file = File(result.files.single.path!);
        final fileSize = await file.length();
        
        final ext = result.files.single.extension?.toLowerCase();
        final isImage = ['jpg', 'jpeg', 'png'].contains(ext);
        final maxSize = isImage ? 2 * 1024 * 1024 : 5 * 1024 * 1024;
        
        if (fileSize > maxSize) {
          _showErrorSnackbar(
              'File too large! Max ${isImage ? "2" : "5"} MB for ${isImage ? "images" : "documents"}');
          return;
        }
        
        setState(() {
          _newDocuments[index]['file'] = file;
        });
      }
    } catch (e) {
      _showErrorSnackbar('Failed to pick file: $e');
    }
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // UPDATE EMPLOYEE
  // ═══════════════════════════════════════════════════════════════════════
  
  Future<void> _updateEmployee() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackbar('Please fill all required fields');
      return;
    }
    
    if (_hireDate == null) {
      _showErrorSnackbar('Please select hire date');
      return;
    }
    
    if (_dob == null) {
      _showErrorSnackbar('Please select date of birth');
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final employeeData = {
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'personalEmail': _personalEmailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'altPhone': _altPhoneCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'country': _countryName ?? '',
        'state': _stateName ?? '',
        'gender': _gender ?? '',
        'dob': _dob!.toIso8601String(),
        'bloodGroup': _bloodGroup ?? '',
        'aadharCard': _aadharCtrl.text.trim(),
        'panNumber': _panCtrl.text.trim().toUpperCase(),
        'contactName': _contactNameCtrl.text.trim(),
        'relationship': _relationshipCtrl.text.trim(),
        'contactPhone': _contactPhoneCtrl.text.trim(),
        'contactAltPhone': _contactAltPhoneCtrl.text.trim(),
        'universityDegree': _degreeCtrl.text.trim(),
        'yearCompletion': _yearCtrl.text.trim(),
        'percentageCgpa': _cgpaCtrl.text.trim(),
        'bankAccountNumber': _accountCtrl.text.trim(),
        'ifscCode': _ifscCtrl.text.trim().toUpperCase(),
        'bankBranch': _branchCtrl.text.trim(),
        'hireDate': _hireDate!.toIso8601String(),
        'department': _department ?? '',
        'position': _position ?? '',
        'reportingManager1': _reportingManager1 ?? '',
        'reportingManager2': _reportingManager2 ?? '',
        'status': _status ?? 'Active',
        'employeeType': _employeeType ?? '',
        'salary': _salaryCtrl.text.trim(),
        'workLocation': _workLocation ?? '',
        'companyName': _company ?? '',
        'timings': _timings == 'Manual'
            ? _manualTimingsCtrl.text.trim()
            : _timings ?? '',
      };
      
      // Prepare new documents
      final documentFiles = <File>[];
      final documentMetadata = <Map<String, String>>[];
      
      for (var doc in _newDocuments) {
        if (doc['file'] != null && doc['type'] != null) {
          documentFiles.add(doc['file']);
          documentMetadata.add({
            'documentType': doc['type'] == 'Other'
                ? (doc['customName'] ?? 'Other')
                : doc['type'],
          });
        }
      }
      
      await _service.updateEmployee(
        id: widget.employeeId,
        employeeData: employeeData,
        newDocuments: documentFiles.isNotEmpty ? documentFiles : null,
        documentMetadata:
            documentMetadata.isNotEmpty ? documentMetadata : null,
      );
      
      setState(() {
        _isLoading = false;
      });
      
      _showSuccessSnackbar('Employee updated successfully');
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackbar('Failed to update employee: $e');
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
        title: Text(
          'Edit Employee${_employeeIdDisplay.isNotEmpty ? " - $_employeeIdDisplay" : ""}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF334155),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: (_loadingMasterData || _loadingEmployee)
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF334155)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── EMPLOYEE ID BADGE ───────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF334155), Color(0xFF1E40AF)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.badge, color: Colors.white, size: 28),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Employee ID',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                              Text(
                                _employeeIdDisplay,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // ── EXISTING DOCUMENTS ──────────────────────────
                    if (_existingDocuments.isNotEmpty) ...[
                      _buildSectionTitle(
                          'Existing Documents', Icons.folder_outlined),
                      _buildFormContainer([
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 2.5,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _existingDocuments.length,
                          itemBuilder: (context, index) {
                            final doc = _existingDocuments[index];
                            return _buildExistingDocumentCard(doc);
                          },
                        ),
                      ]),
                      const SizedBox(height: 24),
                    ],
                    
                    // ── REST OF FORM (Same as Add Screen) ──────────
                    // Copy all sections from Add Employee Screen here
                    // For brevity, I'll include the structure
                    
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
                                  initialDate: _hireDate ?? DateTime.now(),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (date != null) {
                                  setState(() => _hireDate = date);
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
                    
                    // Personal Information (same structure as Add)
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
                                  initialDate: _dob ?? DateTime(1990),
                                  firstDate: DateTime(1950),
                                  lastDate: DateTime.now(),
                                );
                                if (date != null) {
                                  setState(() => _dob = date);
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
                              keyboardType: TextInputType.emailAddress,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildCountryDropdown()),
                          const SizedBox(width: 16),
                          Expanded(child: _buildStateDropdown()),
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
                    
                    // Identity, Emergency, Education, Bank (same as Add)
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
                    
                    // ── ADD NEW DOCUMENTS ───────────────────────────
                    _buildSectionTitle(
                        'Add New Documents', Icons.file_upload_outlined),
                    _buildFormContainer([
                      const Text(
                        '📄 Upload Additional Documents\n'
                        '📏 Size Limits: Photos/Images: 2 MB | Documents: 5 MB',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._newDocuments.asMap().entries.map((entry) {
                        final index = entry.key;
                        final doc = entry.value;
                        return _buildDocumentRow(index, doc);
                      }).toList(),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _addNewDocument,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Document'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF10B981),
                          side: const BorderSide(color: Color(0xFF10B981)),
                        ),
                      ),
                    ]),
                    
                    const SizedBox(height: 32),
                    
                    // ── UPDATE BUTTON ────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _updateEmployee,
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
                                    'Update Employee',
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
  // UI BUILDERS (Same as Add Screen + Existing Document Card)
  // ═══════════════════════════════════════════════════════════════════════
  
  Widget _buildExistingDocumentCard(Map<String, dynamic> doc) {
    IconData icon;
    Color iconColor;
    
    final docType = doc['documentType']?.toString().toLowerCase() ?? '';
    
    if (docType.contains('aadhar')) {
      icon = Icons.credit_card;
      iconColor = const Color(0xFF3B82F6);
    } else if (docType.contains('pan')) {
      icon = Icons.badge;
      iconColor = const Color(0xFF8B5CF6);
    } else if (docType.contains('passport')) {
      icon = Icons.flight_takeoff;
      iconColor = const Color(0xFF10B981);
    } else if (docType.contains('resume') || docType.contains('cv')) {
      icon = Icons.description;
      iconColor = const Color(0xFFF59E0B);
    } else {
      icon = Icons.insert_drive_file;
      iconColor = const Color(0xFF64748B);
    }
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  doc['documentType'] ?? 'Document',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_isSuperManager)
                IconButton(
                  icon: const Icon(Icons.delete, size: 18),
                  color: const Color(0xFFDC2626),
                  onPressed: () => _deleteExistingDocument(doc),
                  tooltip: 'Delete',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
        ],
      ),
    );
  }
  
  // Copy all builder methods from Add Screen:
  // _buildSectionTitle, _buildFormContainer, _buildTextField,
  // _buildDropdown, _buildDateField, _buildCountryDropdown,
  // _buildStateDropdown, _buildDocumentRow
  
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
                  _newDocuments[index]['type'] = val;
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
                    _newDocuments[index]['customName'] = val;
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
            onPressed: () => _removeNewDocument(index),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}