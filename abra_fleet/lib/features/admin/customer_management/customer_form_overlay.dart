import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:abra_fleet/features/admin/customer_management/domain/entities/customer_entity.dart';
import 'package:abra_fleet/features/admin/customer_management/presentation/providers/customer_provider.dart';

class CustomerFormOverlay extends StatefulWidget {
  final CustomerEntity? customer;
  final VoidCallback onClose;
  final VoidCallback onSaved;

  const CustomerFormOverlay({
    Key? key,
    this.customer,
    required this.onClose,
    required this.onSaved,
  }) : super(key: key);

  @override
  State<CustomerFormOverlay> createState() => _CustomerFormOverlayState();
}

class _CustomerFormOverlayState extends State<CustomerFormOverlay> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  
  // Basic Information
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _alternativePhoneController = TextEditingController();
  
  // Organization Details
  final _companyNameController = TextEditingController();
  final _departmentSearchController = TextEditingController();
  String? _selectedDepartment;
  final _employeeIdController = TextEditingController();
  final _designationController = TextEditingController();
  
  // Branch Information
  final _branchSearchController = TextEditingController();
  String? _selectedBranch;
  bool _isBranchDropdownOpen = false;
  List<String> _filteredBranches = [];
  
  // Status
  String _selectedStatus = 'Active';
  
  // Emergency Contact
  final _emergencyContactNameController = TextEditingController();
  final _emergencyContactPhoneController = TextEditingController();
  
  // Password Update (for edit mode only)
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _showPasswordFields = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  
  bool _isLoading = false;
  bool _isDepartmentDropdownOpen = false;
  List<String> _filteredDepartments = [];

  final List<String> _departments = [
    'Engineering',
    'Human Resources',
    'Finance',
    'Sales',
    'Marketing',
    'Operations',
    'IT Support',
    'Customer Service',
    'Product Management',
    'Legal',
    'Administration',
    'Research & Development',
  ];

  // Common branch locations in India for companies
  final List<String> _branches = [
    'Bangalore',
    'Chennai',
    'Hyderabad',
    'Mumbai',
    'Delhi',
    'Pune',
    'Kolkata',
    'Ahmedabad',
    'Gurgaon',
    'Noida',
    'Kochi',
    'Coimbatore',
    'Indore',
    'Bhubaneswar',
    'Jaipur',
    'Chandigarh',
    'Lucknow',
    'Nagpur',
    'Vadodara',
    'Thiruvananthapuram',
  ];

  final List<String> _statusOptions = ['Active', 'Inactive', 'Pending'];

  @override
  void initState() {
    super.initState();
    _filteredDepartments = _departments;
    _filteredBranches = _branches;
    if (widget.customer != null) {
      _populateFields();
    }
  }

  void _populateFields() {
    final customer = widget.customer!;
    _nameController.text = customer.name;
    _emailController.text = customer.email;
    _phoneController.text = customer.phoneNumber ?? '';
    _companyNameController.text = customer.companyName ?? '';
    _employeeIdController.text = customer.employeeId ?? '';
    _selectedDepartment = customer.department;
    _selectedBranch = customer.branch; // Add branch field
    _selectedStatus = customer.status;
  }

  void _filterDepartments(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredDepartments = _departments;
      } else {
        _filteredDepartments = _departments
            .where((dept) => dept.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _filterBranches(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredBranches = _branches;
      } else {
        _filteredBranches = _branches
            .where((branch) => branch.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.5),
      child: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.4,
          height: MediaQuery.of(context).size.height * 0.85,
          constraints: const BoxConstraints(
            maxWidth: 600,
            minWidth: 450,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  color: Color(0xFF2563EB),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_add, color: Colors.white, size: 24),
                    const SizedBox(width: 10),
                    Text(
                      widget.customer == null ? 'Add New Customer' : 'Edit Customer',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close, color: Colors.white, size: 20),
                      tooltip: 'Close',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              // Form Content
              Expanded(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Basic Information Section
                        _buildSectionHeader('Basic Information', Icons.info_outline),
                        const SizedBox(height: 20),
                        _buildTextField(
                          controller: _nameController,
                          label: 'Full Name',
                          icon: Icons.person,
                          required: true,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter customer name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        _buildTextField(
                          controller: _emailController,
                          label: 'Email Address',
                          icon: Icons.email,
                          required: true,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter email';
                            }
                            if (!value.contains('@')) {
                              return 'Please enter a valid email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        _buildTextField(
                          controller: _phoneController,
                          label: 'Phone Number',
                          icon: Icons.phone,
                          required: true,
                          keyboardType: TextInputType.phone,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter phone number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        _buildTextField(
                          controller: _alternativePhoneController,
                          label: 'Alternative Phone (Optional)',
                          icon: Icons.phone_android,
                          keyboardType: TextInputType.phone,
                        ),

                        const SizedBox(height: 40),
                        const Divider(thickness: 2),
                        const SizedBox(height: 40),

                        // Organization Details Section
                        _buildSectionHeader('Organization Details', Icons.business),
                        const SizedBox(height: 20),
                        _buildTextField(
                          controller: _companyNameController,
                          label: 'Company Name',
                          icon: Icons.business_center,
                          hintText: 'Enter company name',
                          required: true,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter company name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        _buildTextField(
                          controller: _employeeIdController,
                          label: 'Employee ID',
                          icon: Icons.badge,
                          hintText: 'Auto-generated if left empty',
                          required: false,
                        ),
                        const SizedBox(height: 20),
                        _buildSearchableDepartmentDropdown(),
                        const SizedBox(height: 20),
                        _buildSearchableBranchDropdown(),
                        const SizedBox(height: 20),
                        _buildTextField(
                          controller: _designationController,
                          label: 'Designation/Position',
                          icon: Icons.work,
                          hintText: 'Job title or position',
                        ),
                        const SizedBox(height: 20),
                        _buildStatusDropdown(),

                        const SizedBox(height: 40),
                        const Divider(thickness: 2),
                        const SizedBox(height: 40),

                        // Password Update Section (only for edit mode)
                        if (widget.customer != null) ...[
                          _buildSectionHeader('Update Password', Icons.lock_reset),
                          const SizedBox(height: 20),
                          _buildPasswordUpdateSection(),
                          const SizedBox(height: 40),
                          const Divider(thickness: 2),
                          const SizedBox(height: 40),
                        ],

                        // Emergency Contact Section
                        _buildSectionHeader('Emergency Contact', Icons.emergency),
                        const SizedBox(height: 20),
                        _buildTextField(
                          controller: _emergencyContactNameController,
                          label: 'Emergency Contact Name',
                          icon: Icons.contact_emergency,
                          hintText: 'Full name of emergency contact',
                        ),
                        const SizedBox(height: 20),
                        _buildTextField(
                          controller: _emergencyContactPhoneController,
                          label: 'Emergency Contact Phone',
                          icon: Icons.phone_in_talk,
                          hintText: 'Emergency contact number',
                          keyboardType: TextInputType.phone,
                        ),
                        
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),

              // Footer with Actions
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300),
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _isLoading ? null : widget.onClose,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _saveCustomer,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: Text(_isLoading ? 'Saving...' : 'Save Customer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF2563EB), size: 24),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hintText,
    bool required = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
            children: [
              if (required)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(color: Colors.red),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(icon, size: 20),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: const TextSpan(
            text: 'Status',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
            children: [
              TextSpan(
                text: ' *',
                style: TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedStatus,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.info_outline, size: 20),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          items: _statusOptions.map((String status) {
            Color statusColor;
            switch (status.toLowerCase()) {
              case 'active':
                statusColor = const Color(0xFF10B981);
                break;
              case 'inactive':
                statusColor = const Color(0xFFEF4444);
                break;
              case 'pending':
                statusColor = const Color(0xFFF59E0B);
                break;
              default:
                statusColor = const Color(0xFF64748B);
            }
            
            return DropdownMenuItem<String>(
              value: status,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(status),
                ],
              ),
            );
          }).toList(),
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() {
                _selectedStatus = newValue;
              });
            }
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please select a status';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildSearchableDepartmentDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: const TextSpan(
            text: 'Department',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
            children: [
              TextSpan(
                text: ' *',
                style: TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FormField<String>(
          validator: (value) {
            if (_selectedDepartment == null || _selectedDepartment!.isEmpty) {
              return 'Please select a department';
            }
            return null;
          },
          builder: (formFieldState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isDepartmentDropdownOpen = !_isDepartmentDropdownOpen;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: Border.all(
                        color: formFieldState.hasError 
                            ? Colors.red 
                            : const Color(0xFFE2E8F0),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.category, size: 20, color: Colors.grey),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selectedDepartment ?? 'Select department',
                            style: TextStyle(
                              color: _selectedDepartment == null 
                                  ? Colors.grey 
                                  : Colors.black,
                            ),
                          ),
                        ),
                        Icon(
                          _isDepartmentDropdownOpen 
                              ? Icons.arrow_drop_up 
                              : Icons.arrow_drop_down,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isDepartmentDropdownOpen)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: TextField(
                            controller: _departmentSearchController,
                            decoration: InputDecoration(
                              hintText: 'Search departments...',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            onChanged: _filterDepartments,
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _filteredDepartments.length,
                            itemBuilder: (context, index) {
                              final dept = _filteredDepartments[index];
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedDepartment = dept;
                                    _isDepartmentDropdownOpen = false;
                                    _departmentSearchController.clear();
                                    _filteredDepartments = _departments;
                                  });
                                  formFieldState.didChange(dept);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _selectedDepartment == dept
                                        ? const Color(0xFF2563EB).withOpacity(0.1)
                                        : Colors.transparent,
                                  ),
                                  child: Text(
                                    dept,
                                    style: TextStyle(
                                      color: _selectedDepartment == dept
                                          ? const Color(0xFF2563EB)
                                          : Colors.black,
                                      fontWeight: _selectedDepartment == dept
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                if (formFieldState.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 12),
                    child: Text(
                      formFieldState.errorText!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSearchableBranchDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: const TextSpan(
            text: 'Branch/Location',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
            children: [
              TextSpan(
                text: ' *',
                style: TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FormField<String>(
          validator: (value) {
            if (_selectedBranch == null || _selectedBranch!.isEmpty) {
              return 'Please select a branch/location';
            }
            return null;
          },
          builder: (formFieldState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isBranchDropdownOpen = !_isBranchDropdownOpen;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: Border.all(
                        color: formFieldState.hasError 
                            ? Colors.red 
                            : const Color(0xFFE2E8F0),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_city, size: 20, color: Colors.grey),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selectedBranch ?? 'Select branch/location',
                            style: TextStyle(
                              color: _selectedBranch == null 
                                  ? Colors.grey 
                                  : Colors.black,
                            ),
                          ),
                        ),
                        Icon(
                          _isBranchDropdownOpen 
                              ? Icons.arrow_drop_up 
                              : Icons.arrow_drop_down,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isBranchDropdownOpen)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: TextField(
                            controller: _branchSearchController,
                            decoration: InputDecoration(
                              hintText: 'Search branches...',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            onChanged: _filterBranches,
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _filteredBranches.length,
                            itemBuilder: (context, index) {
                              final branch = _filteredBranches[index];
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedBranch = branch;
                                    _isBranchDropdownOpen = false;
                                    _branchSearchController.clear();
                                    _filteredBranches = _branches;
                                  });
                                  formFieldState.didChange(branch);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _selectedBranch == branch
                                        ? const Color(0xFF2563EB).withOpacity(0.1)
                                        : Colors.transparent,
                                  ),
                                  child: Text(
                                    branch,
                                    style: TextStyle(
                                      color: _selectedBranch == branch
                                          ? const Color(0xFF2563EB)
                                          : Colors.black,
                                      fontWeight: _selectedBranch == branch
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                if (formFieldState.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 12),
                    child: Text(
                      formFieldState.errorText!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all required fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final provider = Provider.of<CustomerProvider>(context, listen: false);
      
      bool success;
      if (widget.customer == null) {
        // Create new customer - without status parameter
        final result = await provider.createCustomer(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          phone: _phoneController.text.trim(),
          company: _companyNameController.text.trim(),
          address: null,
          department: _selectedDepartment,
          branch: _selectedBranch, // Add branch field
          employeeId: _employeeIdController.text.trim().isEmpty 
              ? null 
              : _employeeIdController.text.trim(),
          password: 'Customer@123',
        );
        success = result['success'] == true;
        
        // If created successfully and status is not Active, update the status
        if (success && _selectedStatus != 'Active' && result['customer'] != null) {
          final customerId = result['customer']['id'];
          final newCustomer = CustomerEntity(
            id: customerId,
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            phoneNumber: _phoneController.text.trim(),
            companyName: _companyNameController.text.trim(),
            department: _selectedDepartment,
            branch: _selectedBranch, // Add branch field
            employeeId: _employeeIdController.text.trim().isEmpty 
                ? null 
                : _employeeIdController.text.trim(),
            status: _selectedStatus,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          await provider.updateCustomer(newCustomer);
        }
      } else {
        // Update existing customer
        final updatedCustomer = widget.customer!.copyWith(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          companyName: _companyNameController.text.trim(),
          department: _selectedDepartment,
          branch: _selectedBranch, // Add branch field
          employeeId: _employeeIdController.text.trim().isEmpty 
              ? null 
              : _employeeIdController.text.trim(),
          status: _selectedStatus,
          updatedAt: DateTime.now(),
        );
        
        success = await provider.updateCustomer(updatedCustomer);
        
        // Update password if provided
        if (success && _newPasswordController.text.trim().isNotEmpty) {
          final passwordUpdateSuccess = await provider.updateCustomerPassword(
            widget.customer!.id,
            _newPasswordController.text.trim(),
          );
          
          if (!passwordUpdateSuccess && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  provider.errorMessage ?? 'Failed to update password'
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.customer == null 
                ? 'Customer added successfully' 
                : 'Customer updated successfully'
            ),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSaved();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              provider.errorMessage ?? 
              (widget.customer == null 
                ? 'Failed to add customer' 
                : 'Failed to update customer')
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildPasswordUpdateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle button to show/hide password fields
        if (!_showPasswordFields)
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _showPasswordFields = true;
              });
            },
            icon: const Icon(Icons.lock_open),
            label: const Text('Update Password'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        
        // Password fields (shown when toggle is active)
        if (_showPasswordFields) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFA726)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFFF57C00), size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Leave blank to keep current password unchanged',
                    style: TextStyle(
                      color: Color(0xFFF57C00),
                      fontSize: 13,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    setState(() {
                      _showPasswordFields = false;
                      _newPasswordController.clear();
                      _confirmPasswordController.clear();
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildPasswordField(
            controller: _newPasswordController,
            label: 'New Password',
            icon: Icons.lock_outline,
            obscureText: _obscureNewPassword,
            onToggleVisibility: () {
              setState(() {
                _obscureNewPassword = !_obscureNewPassword;
              });
            },
          ),
          const SizedBox(height: 20),
          _buildPasswordField(
            controller: _confirmPasswordController,
            label: 'Confirm New Password',
            icon: Icons.lock_outline,
            obscureText: _obscureConfirmPassword,
            onToggleVisibility: () {
              setState(() {
                _obscureConfirmPassword = !_obscureConfirmPassword;
              });
            },
            validator: (value) {
              if (_newPasswordController.text.isNotEmpty && value != _newPasswordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
        ],
      ],
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          validator: validator,
          decoration: InputDecoration(
            hintText: 'Enter $label',
            prefixIcon: Icon(icon, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                obscureText ? Icons.visibility_off : Icons.visibility,
                size: 20,
              ),
              onPressed: onToggleVisibility,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _alternativePhoneController.dispose();
    _companyNameController.dispose();
    _employeeIdController.dispose();
    _designationController.dispose();
    _departmentSearchController.dispose();
    _emergencyContactNameController.dispose();
    _emergencyContactPhoneController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}