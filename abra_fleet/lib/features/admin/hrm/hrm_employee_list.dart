// ============================================================================
// HRM EMPLOYEES LIST SCREEN
// ============================================================================
// Complete employee list with filters, table, actions, CSV import/export
// Matching Master Settings UI design
// ============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/hrm_employee_service.dart';
import 'hrm_employee_filters.dart';
import 'hrm_add_employee_screen.dart';
import 'hrm_edit_employee_screen.dart';

class HRMEmployeesListScreen extends StatefulWidget {
  const HRMEmployeesListScreen({Key? key}) : super(key: key);

  @override
  State<HRMEmployeesListScreen> createState() => _HRMEmployeesListScreenState();
}

class _HRMEmployeesListScreenState extends State<HRMEmployeesListScreen> {
  final HRMEmployeeService _service = HRMEmployeeService();
  
  // ── Data ──────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _employees = [];
  Map<String, dynamic> _pagination = {};
  
  // ── Loading ───────────────────────────────────────────────────────────
  bool _isLoading = false;
  
  // ── Filters ───────────────────────────────────────────────────────────
  Map<String, dynamic> _currentFilters = {};
  
  // ── Pagination ────────────────────────────────────────────────────────
  int _currentPage = 1;
  final int _pageSize = 50;
  
  // ── User permissions ──────────────────────────────────────────────────
  bool _isSuperManager = false;
  
  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _loadEmployees();
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // USER ROLE CHECK
  // ═══════════════════════════════════════════════════════════════════════
  
  Future<void> _checkUserRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('user_email')?.toLowerCase() ?? '';
      
      // Super Managers who can delete employees
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
  
  Future<void> _loadEmployees() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final result = await _service.getEmployees(
        search: _currentFilters['search'],
        status: _currentFilters['status'],
        department: _currentFilters['department'],
        position: _currentFilters['position'],
        employeeType: _currentFilters['employeeType'],
        workLocation: _currentFilters['workLocation'],
        companyName: _currentFilters['companyName'],
        country: _currentFilters['country'],
        state: _currentFilters['state'],
        page: _currentPage,
        limit: _pageSize,
      );
      
      setState(() {
        _employees = result['employees'] ?? [];
        _pagination = result['pagination'] ?? {};
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackbar('Failed to load employees: $e');
    }
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // FILTER HANDLING
  // ═══════════════════════════════════════════════════════════════════════
  
  void _onFilterApplied(Map<String, dynamic> filters) {
    setState(() {
      _currentFilters = filters;
      _currentPage = 1; // Reset to first page
    });
    _loadEmployees();
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // PAGINATION
  // ═══════════════════════════════════════════════════════════════════════
  
  void _goToPage(int page) {
    setState(() {
      _currentPage = page;
    });
    _loadEmployees();
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // DELETE EMPLOYEE
  // ═══════════════════════════════════════════════════════════════════════
  
  Future<void> _deleteEmployee(Map<String, dynamic> employee) async {
    if (!_isSuperManager) {
      _showErrorSnackbar('Only Super Managers can delete employees');
      return;
    }
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Employee',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
            'Are you sure you want to delete "${employee['name']}" (${employee['employeeId']})?'),
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
        await _service.deleteEmployee(employee['_id']);
        _showSuccessSnackbar('Employee deleted successfully');
        _loadEmployees();
      } catch (e) {
        _showErrorSnackbar('Failed to delete employee: $e');
      }
    }
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // CSV EXPORT
  // ═══════════════════════════════════════════════════════════════════════
  
  Future<void> _exportCSV() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      final csvData = await _service.exportCSV();
      
      final directory = await getApplicationDocumentsDirectory();
      final file = File(
          '${directory.path}/employees_export_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(csvData);
      
      setState(() {
        _isLoading = false;
      });
      
      _showSuccessSnackbar('Exported to: ${file.path}');
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackbar('Export failed: $e');
    }
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // CSV IMPORT
  // ═══════════════════════════════════════════════════════════════════════
  
  Future<void> _importCSV() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final file = File(result.files.single.path!);
      
      setState(() {
        _isLoading = true;
      });
      
      final importResult = await _service.importCSV(file);
      
      setState(() {
        _isLoading = false;
      });
      
      _showSuccessSnackbar(
          'Import complete: ${importResult['success']} imported, ${importResult['failed']} failed');
      
      _loadEmployees();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackbar('Import failed: $e');
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
  // STATUS BADGE
  // ═══════════════════════════════════════════════════════════════════════
  
  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    
    switch (status.toLowerCase()) {
      case 'active':
        bgColor = const Color(0xFFD1FAE5);
        textColor = const Color(0xFF065F46);
        break;
      case 'inactive':
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFF92400E);
        break;
      case 'terminated':
        bgColor = const Color(0xFFFEE2E2);
        textColor = const Color(0xFF991B1B);
        break;
      default:
        bgColor = const Color(0xFFF1F5F9);
        textColor = const Color(0xFF64748B);
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
  
  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════
  
  @override
  Widget build(BuildContext context) {
    final totalRecords = _pagination['total'] ?? 0;
    final totalPages = _pagination['pages'] ?? 0;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Employee Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF334155),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _exportCSV,
            tooltip: 'Export CSV',
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _importCSV,
            tooltip: 'Import CSV',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEmployees,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // ── HEADER STATS ───────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF334155),
                  const Color(0xFF334155).withOpacity(0.9),
                ],
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatBox(
                  'Total Employees',
                  totalRecords.toString(),
                  Icons.people,
                ),
                _buildStatBox(
                  'Active',
                  _employees
                      .where((e) => e['status'] == 'Active')
                      .length
                      .toString(),
                  Icons.check_circle,
                ),
                _buildStatBox(
                  'Page',
                  '$_currentPage of $totalPages',
                  Icons.pages,
                ),
              ],
            ),
          ),
          
          // ── FILTERS ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: HRMEmployeeFilters(
              onFilterApplied: _onFilterApplied,
            ),
          ),
          
          // ── ACTION BAR ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${_employees.length} employee(s)',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HRMAddEmployeeScreen(),
                      ),
                    );
                    if (result == true) {
                      _loadEmployees();
                    }
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Employee'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // ── TABLE ──────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF334155),
                    ),
                  )
                : _employees.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline,
                                size: 80,
                                color: Colors.grey.withOpacity(0.3)),
                            const SizedBox(height: 16),
                            const Text(
                              'No employees found',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Add your first employee to get started',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: DataTable(
                              headingRowHeight: 56,
                              dataRowHeight: 64,
                              columnSpacing: 24,
                              headingRowColor: MaterialStateProperty.all(
                                const Color(0xFF334155),
                              ),
                              columns: const [
                                DataColumn(
                                  label: Text('Employee ID',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                ),
                                DataColumn(
                                  label: Text('Name',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                ),
                                DataColumn(
                                  label: Text('Department',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                ),
                                DataColumn(
                                  label: Text('Position',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                ),
                                DataColumn(
                                  label: Text('Email',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                ),
                                DataColumn(
                                  label: Text('Phone',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                ),
                                DataColumn(
                                  label: Text('Status',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                ),
                                DataColumn(
                                  label: Text('Actions',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                              rows: _employees.map((employee) {
                                return DataRow(
                                  cells: [
                                    DataCell(
                                      Text(
                                        employee['employeeId'] ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1E3A8A),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        employee['name'] ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(employee['department'] ?? 'N/A'),
                                    ),
                                    DataCell(
                                      Text(employee['position'] ?? 'N/A'),
                                    ),
                                    DataCell(
                                      Text(employee['email'] ?? 'N/A'),
                                    ),
                                    DataCell(
                                      Text(employee['phone'] ?? 'N/A'),
                                    ),
                                    DataCell(
                                      _buildStatusBadge(
                                          employee['status'] ?? 'N/A'),
                                    ),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit,
                                                color: Color(0xFF1E40AF)),
                                            onPressed: () async {
                                              final result =
                                                  await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      HRMEditEmployeeScreen(
                                                    employeeId:
                                                        employee['_id'],
                                                  ),
                                                ),
                                              );
                                              if (result == true) {
                                                _loadEmployees();
                                              }
                                            },
                                            tooltip: 'Edit',
                                          ),
                                          if (_isSuperManager)
                                            IconButton(
                                              icon: const Icon(Icons.delete,
                                                  color: Color(0xFFDC2626)),
                                              onPressed: () =>
                                                  _deleteEmployee(employee),
                                              tooltip: 'Delete',
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
          ),
          
          // ── PAGINATION ─────────────────────────────────────────────────
          if (totalPages > 1)
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _currentPage > 1
                        ? () => _goToPage(_currentPage - 1)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Page $_currentPage of $totalPages',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _currentPage < totalPages
                        ? () => _goToPage(_currentPage + 1)
                        : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildStatBox(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }
}