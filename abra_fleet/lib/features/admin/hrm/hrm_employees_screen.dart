import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:abra_fleet/core/services/backend_connection_manager.dart';
import 'package:intl/intl.dart';

class HrmEmployeesScreen extends StatefulWidget {
  const HrmEmployeesScreen({super.key});

  @override
  State<HrmEmployeesScreen> createState() => _HrmEmployeesScreenState();
}

class _HrmEmployeesScreenState extends State<HrmEmployeesScreen> {
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filteredEmployees = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String _selectedDepartment = 'All';
  String _selectedStatus = 'All';
  
  final List<String> _departments = [
    'All',
    'IT',
    'HR',
    'Finance',
    'Operations',
    'Sales',
    'Marketing',
    'Administration'
  ];
  
  final List<String> _statusOptions = ['All', 'active', 'inactive'];

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
  }

  Future<void> _fetchEmployees() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final connectionManager = Provider.of<BackendConnectionManager>(
        context,
        listen: false,
      );

      final response = await connectionManager.apiService.get('/api/hrm/employees');

      if (response != null && response['success'] == true) {
        setState(() {
          _employees = List<Map<String, dynamic>>.from(response['data'] ?? []);
          _filterEmployees();
        });
      }
    } catch (e) {
      print('❌ Error fetching employees: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load employees: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterEmployees() {
    setState(() {
      _filteredEmployees = _employees.where((employee) {
        final matchesSearch = _searchQuery.isEmpty ||
            employee['name']?.toLowerCase().contains(_searchQuery.toLowerCase()) == true ||
            employee['email']?.toLowerCase().contains(_searchQuery.toLowerCase()) == true ||
            employee['phone']?.toLowerCase().contains(_searchQuery.toLowerCase()) == true;

        final matchesDepartment = _selectedDepartment == 'All' ||
            employee['department'] == _selectedDepartment;

        final matchesStatus = _selectedStatus == 'All' ||
            employee['status'] == _selectedStatus;

        return matchesSearch && matchesDepartment && matchesStatus;
      }).toList();
    });
  }

  Future<void> _showAddEmployeeDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final departmentController = TextEditingController();
    final designationController = TextEditingController();
    final salaryController = TextEditingController();
    final addressController = TextEditingController();
    final emergencyContactController = TextEditingController();
    final bloodGroupController = TextEditingController();
    
    String selectedStatus = 'active';
    String selectedGender = 'Male';
    String selectedDepartment = 'IT';
    DateTime? hireDate;
    DateTime? dateOfBirth;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.person_add, color: Colors.blue[700]),
              const SizedBox(width: 12),
              const Text('Add New Employee'),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Personal Information Section
                    const Text(
                      'Personal Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email *',
                              prefixIcon: Icon(Icons.email),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter email';
                              }
                              if (!value.contains('@')) {
                                return 'Invalid email';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: phoneController,
                            decoration: const InputDecoration(
                              labelText: 'Phone *',
                              prefixIcon: Icon(Icons.phone),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter phone';
                              }
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
                          child: DropdownButtonFormField<String>(
                            value: selectedGender,
                            decoration: const InputDecoration(
                              labelText: 'Gender',
                              prefixIcon: Icon(Icons.wc),
                              border: OutlineInputBorder(),
                            ),
                            items: ['Male', 'Female', 'Other'].map((gender) {
                              return DropdownMenuItem(
                                value: gender,
                                child: Text(gender),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setDialogState(() {
                                selectedGender = value!;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now().subtract(const Duration(days: 365 * 25)),
                                firstDate: DateTime(1950),
                                lastDate: DateTime.now(),
                              );
                              if (date != null) {
                                setDialogState(() {
                                  dateOfBirth = date;
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Date of Birth',
                                prefixIcon: Icon(Icons.cake),
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                dateOfBirth != null
                                    ? DateFormat('dd/MM/yyyy').format(dateOfBirth!)
                                    : 'Select date',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: bloodGroupController,
                            decoration: const InputDecoration(
                              labelText: 'Blood Group',
                              prefixIcon: Icon(Icons.bloodtype),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: emergencyContactController,
                            decoration: const InputDecoration(
                              labelText: 'Emergency Contact',
                              prefixIcon: Icon(Icons.emergency),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Employment Information Section
                    const Text(
                      'Employment Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedDepartment,
                            decoration: const InputDecoration(
                              labelText: 'Department *',
                              prefixIcon: Icon(Icons.business),
                              border: OutlineInputBorder(),
                            ),
                            items: _departments
                                .where((dept) => dept != 'All')
                                .map((dept) {
                              return DropdownMenuItem(
                                value: dept,
                                child: Text(dept),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setDialogState(() {
                                selectedDepartment = value!;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: designationController,
                            decoration: const InputDecoration(
                              labelText: 'Designation',
                              prefixIcon: Icon(Icons.work),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (date != null) {
                                setDialogState(() {
                                  hireDate = date;
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Hire Date *',
                                prefixIcon: Icon(Icons.calendar_today),
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                hireDate != null
                                    ? DateFormat('dd/MM/yyyy').format(hireDate!)
                                    : 'Select hire date',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: salaryController,
                            decoration: const InputDecoration(
                              labelText: 'Salary',
                              prefixIcon: Icon(Icons.attach_money),
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    DropdownButtonFormField<String>(
                      value: selectedStatus,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        prefixIcon: Icon(Icons.info),
                        border: OutlineInputBorder(),
                      ),
                      items: ['active', 'inactive'].map((status) {
                        return DropdownMenuItem(
                          value: status,
                          child: Text(status.toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedStatus = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: addressController,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        prefixIcon: Icon(Icons.home),
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  if (hireDate == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please select hire date'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  
                  Navigator.pop(context);
                  await _addEmployee(
                    name: nameController.text,
                    email: emailController.text,
                    phone: phoneController.text,
                    department: selectedDepartment,
                    designation: designationController.text,
                    hireDate: hireDate!,
                    salary: salaryController.text.isEmpty ? 0 : double.parse(salaryController.text),
                    status: selectedStatus,
                    address: addressController.text,
                    emergencyContact: emergencyContactController.text,
                    bloodGroup: bloodGroupController.text,
                    dateOfBirth: dateOfBirth,
                    gender: selectedGender,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save Employee'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addEmployee({
    required String name,
    required String email,
    required String phone,
    required String department,
    required String designation,
    required DateTime hireDate,
    required double salary,
    required String status,
    required String address,
    required String emergencyContact,
    required String bloodGroup,
    DateTime? dateOfBirth,
    required String gender,
  }) async {
    try {
      final connectionManager = Provider.of<BackendConnectionManager>(
        context,
        listen: false,
      );

      // ✅ FIXED: Remove 'body:' wrapper - pass map directly
      final response = await connectionManager.apiService.post(
        '/api/hrm/employees',
        body: {
          'name': name,
          'email': email,
          'phone': phone,
          'department': department,
          'designation': designation,
          'hireDate': hireDate.toIso8601String(),
          'salary': salary,
          'status': status,
          'address': address,
          'emergencyContact': emergencyContact,
          'bloodGroup': bloodGroup,
          if (dateOfBirth != null) 'dateOfBirth': dateOfBirth.toIso8601String(),
          'gender': gender,
        },
      );

      if (response != null && response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Employee added successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchEmployees();
        }
      }
    } catch (e) {
      print('❌ Error adding employee: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add employee: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showEditEmployeeDialog(Map<String, dynamic> employee) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: employee['name']);
    final emailController = TextEditingController(text: employee['email']);
    final phoneController = TextEditingController(text: employee['phone']);
    final designationController = TextEditingController(text: employee['designation'] ?? '');
    final salaryController = TextEditingController(
      text: employee['salary']?.toString() ?? '0',
    );
    final addressController = TextEditingController(text: employee['address'] ?? '');
    final emergencyContactController = TextEditingController(
      text: employee['emergencyContact'] ?? '',
    );
    final bloodGroupController = TextEditingController(text: employee['bloodGroup'] ?? '');
    
    String selectedStatus = employee['status'] ?? 'active';
    String selectedGender = employee['gender'] ?? 'Male';
    String selectedDepartment = employee['department'] ?? 'IT';
    DateTime? hireDate = employee['hireDate'] != null 
        ? DateTime.parse(employee['hireDate'])
        : null;
    DateTime? dateOfBirth = employee['dateOfBirth'] != null
        ? DateTime.parse(employee['dateOfBirth'])
        : null;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.edit, color: Colors.blue[700]),
              const SizedBox(width: 12),
              const Text('Edit Employee'),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Personal Information Section
                    const Text(
                      'Personal Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email *',
                              prefixIcon: Icon(Icons.email),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter email';
                              }
                              if (!value.contains('@')) {
                                return 'Invalid email';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: phoneController,
                            decoration: const InputDecoration(
                              labelText: 'Phone *',
                              prefixIcon: Icon(Icons.phone),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter phone';
                              }
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
                          child: DropdownButtonFormField<String>(
                            value: selectedGender,
                            decoration: const InputDecoration(
                              labelText: 'Gender',
                              prefixIcon: Icon(Icons.wc),
                              border: OutlineInputBorder(),
                            ),
                            items: ['Male', 'Female', 'Other'].map((gender) {
                              return DropdownMenuItem(
                                value: gender,
                                child: Text(gender),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setDialogState(() {
                                selectedGender = value!;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: dateOfBirth ?? DateTime.now().subtract(const Duration(days: 365 * 25)),
                                firstDate: DateTime(1950),
                                lastDate: DateTime.now(),
                              );
                              if (date != null) {
                                setDialogState(() {
                                  dateOfBirth = date;
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Date of Birth',
                                prefixIcon: Icon(Icons.cake),
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                dateOfBirth != null
                                    ? DateFormat('dd/MM/yyyy').format(dateOfBirth!)
                                    : 'Select date',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: bloodGroupController,
                            decoration: const InputDecoration(
                              labelText: 'Blood Group',
                              prefixIcon: Icon(Icons.bloodtype),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: emergencyContactController,
                            decoration: const InputDecoration(
                              labelText: 'Emergency Contact',
                              prefixIcon: Icon(Icons.emergency),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Employment Information Section
                    const Text(
                      'Employment Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedDepartment,
                            decoration: const InputDecoration(
                              labelText: 'Department *',
                              prefixIcon: Icon(Icons.business),
                              border: OutlineInputBorder(),
                            ),
                            items: _departments
                                .where((dept) => dept != 'All')
                                .map((dept) {
                              return DropdownMenuItem(
                                value: dept,
                                child: Text(dept),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setDialogState(() {
                                selectedDepartment = value!;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: designationController,
                            decoration: const InputDecoration(
                              labelText: 'Designation',
                              prefixIcon: Icon(Icons.work),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: hireDate ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (date != null) {
                                setDialogState(() {
                                  hireDate = date;
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Hire Date *',
                                prefixIcon: Icon(Icons.calendar_today),
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                hireDate != null
                                    ? DateFormat('dd/MM/yyyy').format(hireDate!)
                                    : 'Select hire date',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: salaryController,
                            decoration: const InputDecoration(
                              labelText: 'Salary',
                              prefixIcon: Icon(Icons.attach_money),
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    DropdownButtonFormField<String>(
                      value: selectedStatus,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        prefixIcon: Icon(Icons.info),
                        border: OutlineInputBorder(),
                      ),
                      items: ['active', 'inactive'].map((status) {
                        return DropdownMenuItem(
                          value: status,
                          child: Text(status.toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedStatus = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: addressController,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        prefixIcon: Icon(Icons.home),
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context);
                  await _updateEmployee(
                    id: employee['_id'],
                    name: nameController.text,
                    email: emailController.text,
                    phone: phoneController.text,
                    department: selectedDepartment,
                    designation: designationController.text,
                    hireDate: hireDate,
                    salary: salaryController.text.isEmpty ? 0 : double.parse(salaryController.text),
                    status: selectedStatus,
                    address: addressController.text,
                    emergencyContact: emergencyContactController.text,
                    bloodGroup: bloodGroupController.text,
                    dateOfBirth: dateOfBirth,
                    gender: selectedGender,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Update Employee'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateEmployee({
    required String id,
    required String name,
    required String email,
    required String phone,
    required String department,
    required String designation,
    DateTime? hireDate,
    required double salary,
    required String status,
    required String address,
    required String emergencyContact,
    required String bloodGroup,
    DateTime? dateOfBirth,
    required String gender,
  }) async {
    try {
      final connectionManager = Provider.of<BackendConnectionManager>(
        context,
        listen: false,
      );

      // ✅ FIXED: Remove 'body:' wrapper - pass map directly
      final response = await connectionManager.apiService.put(
        '/api/hrm/employees/$id',
        body: {
          'name': name,
          'email': email,
          'phone': phone,
          'department': department,
          'designation': designation,
          if (hireDate != null) 'hireDate': hireDate.toIso8601String(),
          'salary': salary,
          'status': status,
          'address': address,
          'emergencyContact': emergencyContact,
          'bloodGroup': bloodGroup,
          if (dateOfBirth != null) 'dateOfBirth': dateOfBirth.toIso8601String(),
          'gender': gender,
        },
      );

      if (response != null && response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Employee updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchEmployees();
        }
      }
    } catch (e) {
      print('❌ Error updating employee: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update employee: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteEmployee(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete $name?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final connectionManager = Provider.of<BackendConnectionManager>(
        context,
        listen: false,
      );

      final response = await connectionManager.apiService.delete(
        '/api/hrm/employees/$id',
      );

      if (response != null && response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Employee deleted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchEmployees();
        }
      }
    } catch (e) {
      print('❌ Error deleting employee: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete employee: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          // Header Section
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.people, size: 32, color: Colors.blue[700]),
                    const SizedBox(width: 12),
                    const Text(
                      'Employees List',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _showAddEmployeeDialog,
                      icon: const Icon(Icons.person_add),
                      label: const Text('Add New Employee'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Filters Row
                Row(
                  children: [
                    // Search
                    Expanded(
                      flex: 2,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search by name, email, or phone...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                            _filterEmployees();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    
                    // Department Filter
                    SizedBox(
                      width: 200,
                      child: DropdownButtonFormField<String>(
                        value: _selectedDepartment,
                        decoration: InputDecoration(
                          labelText: 'Department',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        items: _departments.map((dept) {
                          return DropdownMenuItem(
                            value: dept,
                            child: Text(dept),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedDepartment = value!;
                            _filterEmployees();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    
                    // Status Filter
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<String>(
                        value: _selectedStatus,
                        decoration: InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        items: _statusOptions.map((status) {
                          return DropdownMenuItem(
                            value: status,
                            child: Text(status.toUpperCase()),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedStatus = value!;
                            _filterEmployees();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Employees Table
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredEmployees.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 80, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No employees found',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        margin: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: MaterialStateProperty.all(
                              Colors.grey[100],
                            ),
                            columns: const [
                              DataColumn(label: Text('ID', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Email', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Department', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Edit', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Delete', style: TextStyle(fontWeight: FontWeight.bold))),
                            ],
                            rows: _filteredEmployees.map((employee) {
                              return DataRow(
                                cells: [
                                  DataCell(Text(employee['_id'].toString().substring(0, 8))),
                                  DataCell(Text(employee['name'] ?? '')),
                                  DataCell(Text(employee['email'] ?? '')),
                                  DataCell(Text(employee['phone'] ?? '')),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue[50],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        employee['department'] ?? '',
                                        style: TextStyle(
                                          color: Colors.blue[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: employee['status'] == 'active'
                                            ? Colors.green[50]
                                            : Colors.red[50],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        (employee['status'] ?? 'inactive').toUpperCase(),
                                        style: TextStyle(
                                          color: employee['status'] == 'active'
                                              ? Colors.green[700]
                                              : Colors.red[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () => _showEditEmployeeDialog(employee),
                                    ),
                                  ),
                                  DataCell(
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteEmployee(
                                        employee['_id'],
                                        employee['name'] ?? '',
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}