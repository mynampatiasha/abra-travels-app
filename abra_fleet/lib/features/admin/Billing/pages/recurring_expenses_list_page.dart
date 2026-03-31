// ============================================================================
// RECURRING EXPENSES LIST PAGE - Complete Implementation with Lifecycle Dialog
// ============================================================================
// File: lib/screens/expenses/recurring_expenses_list_page.dart
// Features:
// - Display all recurring expense profiles
// - Advanced Filter Dialog (From/To Date, Status)
// - Excel Export (downloads ALL data)
// - Pause/Resume/Stop actions
// - Generate manual expense
// - View child expenses
// - **NEW: View Process/Lifecycle Dialog**
// - Similar UI to recurring_invoices_list.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import '../../../../core/utils/export_helper.dart';
import '../../../../core/services/recurring_expense_service.dart';
import '../app_top_bar.dart';
import 'new_recurring_expense.dart';

class RecurringExpensesListPage extends StatefulWidget {
  const RecurringExpensesListPage({Key? key}) : super(key: key);

  @override
  State<RecurringExpensesListPage> createState() =>
      _RecurringExpensesListPageState();
}

class _RecurringExpensesListPageState
    extends State<RecurringExpensesListPage> {
  // Data
  List<RecurringExpense> _recurringProfiles = [];
  RecurringExpenseStats? _stats;
  bool _isLoading = true;
  String? _errorMessage;

  // Filters
  String _selectedStatus = 'All';
  final List<String> _statusFilters = [
    'All',
    'ACTIVE',
    'PAUSED',
    'STOPPED',
  ];

  // Advanced Filters - Date Based Only
  DateTime? _fromDate;
  DateTime? _toDate;
  String _dateFilterType =
      'All'; // 'All', 'Within Date Range', 'Particular Date', 'Today', 'This Week', 'This Month'
  DateTime? _particularDate;

  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalProfiles = 0;
  final int _itemsPerPage = 20;

  // Selection
  final Set<String> _selectedProfiles = {};
  bool _selectAll = false;

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadRecurringProfiles();
    _loadStats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Load recurring profiles from backend
  Future<void> _loadRecurringProfiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await RecurringExpenseService.getRecurringExpenses(
        status: _selectedStatus == 'All' ? null : _selectedStatus,
        fromDate: _fromDate?.toIso8601String(),
        toDate: _toDate?.toIso8601String(),
        page: _currentPage,
        limit: _itemsPerPage,
      );

      setState(() {
        // The service already returns parsed RecurringExpense objects
        final recurringExpensesData = response['data'];
        if (recurringExpensesData != null && recurringExpensesData is List) {
          // Data is already parsed as RecurringExpense objects
          _recurringProfiles = recurringExpensesData.cast<RecurringExpense>();
        } else {
          _recurringProfiles = [];
        }
        
        // Handle pagination safely
        final pagination = response['pagination'];
        if (pagination != null && pagination is Map) {
          _totalPages = pagination['pages'] ?? 1;
          _totalProfiles = pagination['total'] ?? 0;
        } else {
          _totalPages = 1;
          _totalProfiles = 0;
        }
        
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  // Load statistics
  Future<void> _loadStats() async {
    try {
      final stats = await RecurringExpenseService.getStats();
      setState(() {
        _stats = stats;
      });
    } catch (e) {
      print('Error loading stats: $e');
    }
  }

  // Refresh data
  Future<void> _refreshData() async {
    await Future.wait([
      _loadRecurringProfiles(),
      _loadStats(),
    ]);
    _showSuccessSnackbar('Data refreshed successfully');
  }

  // Filter by status
  void _filterByStatus(String status) {
    setState(() {
      _selectedStatus = status;
      _currentPage = 1;
    });
    _loadRecurringProfiles();
  }

  // Show Lifecycle Dialog
  void _showLifecycleDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          width: 800,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Life cycle of a Recurring Expense',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              
              const SizedBox(height: 32),
              
              // Lifecycle Diagram
              _buildLifecycleDiagram(),
              
              const SizedBox(height: 32),
              
              // Explanation
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          'How it Works:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildExplanationPoint(
                      '1. Create Recurring Expense',
                      'Set up a recurring profile with vendor, amount, and frequency',
                    ),
                    _buildExplanationPoint(
                      '2. Billable or Non-Billable',
                      'Choose if this expense can be invoiced to customers',
                    ),
                    _buildExplanationPoint(
                      '3. Automatic Generation',
                      'System automatically creates expenses based on schedule',
                    ),
                    _buildExplanationPoint(
                      '4. Invoice & Reimbursement',
                      'Billable expenses can be converted to invoices and reimbursed',
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Close Button
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3498DB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 16,
                  ),
                ),
                child: const Text('Got it!'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Build Lifecycle Diagram
  Widget _buildLifecycleDiagram() {
    return SizedBox(
      height: 200,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Step 1: Create
          _buildLifecycleStep(
            icon: Icons.add_circle_outline,
            label: 'CREATE RECURRING\nEXPENSE',
            color: const Color(0xFF3498DB),
          ),
          
          _buildArrow(),
          
          // Branch Container
          SizedBox(
            width: 350,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Top Branch: Billable
                Row(
                  children: [
                    _buildLifecycleStep(
                      icon: Icons.receipt_long,
                      label: 'BILLABLE',
                      color: const Color(0xFF27AE60),
                      compact: true,
                    ),
                    _buildSmallArrow(),
                    _buildLifecycleStep(
                      icon: Icons.description,
                      label: 'CONVERT TO\nINVOICE',
                      color: const Color(0xFF3498DB),
                      compact: true,
                    ),
                    _buildSmallArrow(),
                    _buildLifecycleStep(
                      icon: Icons.attach_money,
                      label: 'GET\nREIMBURSED',
                      color: const Color(0xFF27AE60),
                      compact: true,
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Bottom Branch: Non-Billable
                _buildLifecycleStep(
                  icon: Icons.cancel_outlined,
                  label: 'NON-BILLABLE',
                  color: const Color(0xFFE74C3C),
                  compact: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLifecycleStep({
    required IconData icon,
    required String label,
    required Color color,
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: compact ? 24 : 32),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.bold,
              color: color,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArrow() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 2,
            color: Colors.grey[400],
          ),
          Icon(Icons.arrow_forward, color: Colors.grey[600], size: 24),
        ],
      ),
    );
  }

  Widget _buildSmallArrow() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 2,
            color: Colors.grey[400],
          ),
          Icon(Icons.arrow_forward, color: Colors.grey[600], size: 16),
        ],
      ),
    );
  }

  Widget _buildExplanationPoint(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.blue[700],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Show Filter Dialog - Date Based Only
  void _showFilterDialog() {
    DateTime? tempFromDate = _fromDate;
    DateTime? tempToDate = _toDate;
    DateTime? tempParticularDate = _particularDate;
    String tempDateFilterType = _dateFilterType;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Filter by Date'),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date Filter Type
                  const Text(
                    'Filter Type',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<String>(
                      value: tempDateFilterType,
                      isExpanded: true,
                      underline: const SizedBox(),
                      icon: const Icon(Icons.arrow_drop_down),
                      items: const [
                        DropdownMenuItem(
                            value: 'All', child: Text('All Dates')),
                        DropdownMenuItem(
                            value: 'Within Date Range',
                            child: Text('Within Date Range')),
                        DropdownMenuItem(
                            value: 'Particular Date',
                            child: Text('Particular Date')),
                        DropdownMenuItem(value: 'Today', child: Text('Today')),
                        DropdownMenuItem(
                            value: 'This Week', child: Text('This Week')),
                        DropdownMenuItem(
                            value: 'This Month', child: Text('This Month')),
                        DropdownMenuItem(
                            value: 'Last Month', child: Text('Last Month')),
                        DropdownMenuItem(
                            value: 'This Year', child: Text('This Year')),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          tempDateFilterType = value ?? 'All';
                          // Auto-set dates for quick filters
                          if (value == 'Today') {
                            tempFromDate = DateTime.now();
                            tempToDate = DateTime.now();
                          } else if (value == 'This Week') {
                            final now = DateTime.now();
                            tempFromDate =
                                now.subtract(Duration(days: now.weekday - 1));
                            tempToDate =
                                now.add(Duration(days: 7 - now.weekday));
                          } else if (value == 'This Month') {
                            final now = DateTime.now();
                            tempFromDate = DateTime(now.year, now.month, 1);
                            tempToDate = DateTime(now.year, now.month + 1, 0);
                          } else if (value == 'Last Month') {
                            final now = DateTime.now();
                            tempFromDate = DateTime(now.year, now.month - 1, 1);
                            tempToDate = DateTime(now.year, now.month, 0);
                          } else if (value == 'This Year') {
                            final now = DateTime.now();
                            tempFromDate = DateTime(now.year, 1, 1);
                            tempToDate = DateTime(now.year, 12, 31);
                          } else if (value == 'All') {
                            tempFromDate = null;
                            tempToDate = null;
                            tempParticularDate = null;
                          }
                        });
                      },
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Show date pickers based on filter type
                  if (tempDateFilterType == 'Within Date Range') ...[
                    // From Date
                    const Text(
                      'From Date',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: tempFromDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            tempFromDate = picked;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 20),
                            const SizedBox(width: 12),
                            Text(
                              tempFromDate != null
                                  ? DateFormat('dd/MM/yyyy')
                                      .format(tempFromDate!)
                                  : 'Select from date',
                              style: TextStyle(
                                color: tempFromDate != null
                                    ? Colors.black
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // To Date
                    const Text(
                      'To Date',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: tempToDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            tempToDate = picked;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 20),
                            const SizedBox(width: 12),
                            Text(
                              tempToDate != null
                                  ? DateFormat('dd/MM/yyyy').format(tempToDate!)
                                  : 'Select to date',
                              style: TextStyle(
                                color: tempToDate != null
                                    ? Colors.black
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  if (tempDateFilterType == 'Particular Date') ...[
                    // Particular Date
                    const Text(
                      'Select Date',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: tempParticularDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            tempParticularDate = picked;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 20),
                            const SizedBox(width: 12),
                            Text(
                              tempParticularDate != null
                                  ? DateFormat('dd/MM/yyyy')
                                      .format(tempParticularDate!)
                                  : 'Select date',
                              style: TextStyle(
                                color: tempParticularDate != null
                                    ? Colors.black
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  if (tempDateFilterType != 'All' &&
                      tempDateFilterType != 'Within Date Range' &&
                      tempDateFilterType != 'Particular Date') ...[
                    // Show selected date range for quick filters
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 18, color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              tempFromDate != null && tempToDate != null
                                  ? 'From ${DateFormat('dd/MM/yyyy').format(tempFromDate!)} to ${DateFormat('dd/MM/yyyy').format(tempToDate!)}'
                                  : 'Date range will be applied automatically',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            // Clear Button
            TextButton(
              onPressed: () {
                setDialogState(() {
                  tempFromDate = null;
                  tempToDate = null;
                  tempParticularDate = null;
                  tempDateFilterType = 'All';
                });
              },
              child: const Text(
                'Clear',
                style: TextStyle(color: Colors.red),
              ),
            ),

            // Apply Button
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _dateFilterType = tempDateFilterType;
                  _fromDate = tempFromDate;
                  _toDate = tempToDate;
                  _particularDate = tempParticularDate;
                  _currentPage = 1;
                });
                Navigator.pop(context);
                _loadRecurringProfiles();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3498DB),
                foregroundColor: Colors.white,
              ),
              child: const Text('Apply Filter'),
            ),
          ],
        ),
      ),
    );
  }

  // Clear all filters
  void _clearAllFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _particularDate = null;
      _dateFilterType = 'All';
      _selectedStatus = 'All';
      _currentPage = 1;
    });
    _loadRecurringProfiles();
  }

  // Check if any filters are active
  bool get _hasActiveFilters {
    return _dateFilterType != 'All' || _selectedStatus != 'All';
  }

  // Toggle selection
  void _toggleSelection(String profileId) {
    setState(() {
      if (_selectedProfiles.contains(profileId)) {
        _selectedProfiles.remove(profileId);
      } else {
        _selectedProfiles.add(profileId);
      }
      _selectAll = _selectedProfiles.length == _recurringProfiles.length;
    });
  }

  // Toggle select all
  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        _selectedProfiles.addAll(_recurringProfiles.map((p) => p.id));
      } else {
        _selectedProfiles.clear();
      }
    });
  }

  // Navigate to new recurring expense
  void _openNewRecurringExpense() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NewRecurringExpenseScreen(),
      ),
    );

    if (result == true) {
      _refreshData();
    }
  }

  // Navigate to edit recurring expense
  void _openEditRecurringExpense(String profileId) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            NewRecurringExpenseScreen(recurringExpenseId: profileId),
      ),
    );

    if (result == true) {
      _refreshData();
    }
  }

  // Pause profile
  Future<void> _pauseProfile(RecurringExpense profile) async {
    if (profile.status != 'ACTIVE') {
      _showErrorSnackbar('Only active profiles can be paused');
      return;
    }

    try {
      await RecurringExpenseService.pauseRecurringExpense(profile.id);
      _showSuccessSnackbar('Profile "${profile.profileName}" paused');
      _refreshData();
    } catch (e) {
      _showErrorSnackbar('Failed to pause profile: $e');
    }
  }

  // Resume profile
  Future<void> _resumeProfile(RecurringExpense profile) async {
    if (profile.status != 'PAUSED') {
      _showErrorSnackbar('Only paused profiles can be resumed');
      return;
    }

    try {
      await RecurringExpenseService.resumeRecurringExpense(profile.id);
      _showSuccessSnackbar('Profile "${profile.profileName}" resumed');
      _refreshData();
    } catch (e) {
      _showErrorSnackbar('Failed to resume profile: $e');
    }
  }

  // Stop profile
  Future<void> _stopProfile(RecurringExpense profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Recurring Profile'),
        content: Text(
            'Are you sure you want to permanently stop "${profile.profileName}"?\n\n'
            'This will prevent any future expenses from being generated.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Stop'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await RecurringExpenseService.stopRecurringExpense(profile.id);
        _showSuccessSnackbar('Profile "${profile.profileName}" stopped');
        _refreshData();
      } catch (e) {
        _showErrorSnackbar('Failed to stop profile: $e');
      }
    }
  }

  // Generate manual expense
  Future<void> _generateManualExpense(RecurringExpense profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate Expense'),
        content: Text(
            'Generate a new expense from profile "${profile.profileName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
            ),
            child: const Text('Generate'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final result =
            await RecurringExpenseService.generateManualExpense(profile.id);
        _showSuccessSnackbar(
            result ? 'Expense generated successfully' : 'Failed to generate expense');
        _refreshData();
      } catch (e) {
        _showErrorSnackbar('Failed to generate expense: $e');
      }
    }
  }

  // Delete profile
  Future<void> _deleteProfile(RecurringExpense profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recurring Profile'),
        content: Text(
            'Are you sure you want to delete "${profile.profileName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await RecurringExpenseService.deleteRecurringExpense(profile.id);
        _showSuccessSnackbar('Profile deleted successfully');
        _refreshData();
      } catch (e) {
        _showErrorSnackbar('Failed to delete profile: $e');
      }
    }
  }

  // View child expenses
  Future<void> _viewChildExpenses(RecurringExpense profile) async {
    try {
      final response =
          await RecurringExpenseService.getChildExpenses(profile.id);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Child Expenses - ${profile.profileName}'),
          content: SizedBox(
            width: 600,
            height: 400,
            child: response.isEmpty
                ? const Center(
                    child: Text('No expenses generated yet'),
                  )
                : ListView.builder(
                    itemCount: response.length,
                    itemBuilder: (context, index) {
                      final expense = response[index];
                      return ListTile(
                        leading: Icon(
                          Icons.receipt,
                          color: _getStatusColor(expense['status'] ?? 'DRAFT'),
                        ),
                        title: Text(expense['expenseNumber'] ?? 'N/A'),
                        subtitle: Text(
                            'Date: ${expense['expenseDate'] != null ? DateFormat('dd/MM/yyyy').format(DateTime.parse(expense['expenseDate'])) : 'N/A'} | '
                            'Amount: ₹${(expense['totalAmount'] ?? 0).toStringAsFixed(2)}'),
                        trailing: _buildStatusBadge(expense['status'] ?? 'DRAFT'),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showErrorSnackbar('Failed to load child expenses: $e');
    }
  }

  // Export to Excel - Downloads ALL recurring profiles
  Future<void> _exportToExcel() async {
    try {
      // Show loading
      _showSuccessSnackbar('Preparing Excel export...');

      // Fetch ALL recurring profiles (not just current page)
      final allProfiles = await RecurringExpenseService.getRecurringExpenses(
        limit: 10000, // Get all
      );

      // The service already returns parsed RecurringExpense objects
      final recurringExpenses = (allProfiles['data'] as List<RecurringExpense>?) ?? [];

      if (recurringExpenses.isEmpty) {
        _showErrorSnackbar('No recurring profiles to export');
        return;
      }

      // Prepare data for export
      List<List<dynamic>> csvData = [
        // Headers
        [
          'Profile Name',
          'Vendor Name',
          'Expense Account',
          'Paid Through',
          'Status',
          'Repeat Every',
          'Repeat Unit',
          'Start Date',
          'End Date',
          'Next Expense Date',
          'Total Generated',
          'Creation Mode',
          'Amount',
          'Tax',
          'Total Amount',
          'Last Generated',
        ],
      ];

      print(
          '📊 Exporting ${recurringExpenses.length} recurring profiles...');

      // Add data rows
      for (var profile in recurringExpenses) {
        final totalAmount = profile.amount + profile.tax;
        csvData.add([
          profile.profileName,
          profile.vendorName,
          profile.expenseAccount,
          profile.paidThrough,
          profile.status,
          profile.repeatEvery.toString(),
          profile.repeatUnit,
          DateFormat('dd/MM/yyyy').format(profile.startDate),
          profile.endDate != null
              ? DateFormat('dd/MM/yyyy').format(profile.endDate!)
              : 'Never',
          DateFormat('dd/MM/yyyy').format(profile.nextExpenseDate),
          profile.totalExpensesGenerated.toString(),
          profile.expenseCreationMode,
          profile.amount.toStringAsFixed(2),
          profile.tax.toStringAsFixed(2),
          totalAmount.toStringAsFixed(2),
          profile.lastGeneratedDate != null
              ? DateFormat('dd/MM/yyyy').format(profile.lastGeneratedDate!)
              : 'Not yet',
        ]);
      }

      // Use ExportHelper to export
      final filePath = await ExportHelper.exportToExcel(
        data: csvData,
        filename: 'recurring_expenses',
      );

      _showSuccessSnackbar(
          '✅ Excel file downloaded with ${recurringExpenses.length} profiles!');
    } catch (e) {
      print('❌ Export Error: $e');
      _showErrorSnackbar('Failed to export: $e');
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'RECORDED':
        return Colors.green;
      case 'DRAFT':
        return Colors.grey;
      case 'PENDING':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Recurring Expenses'),
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          _buildTopBar(),
          if (_stats != null) _buildStatsCards(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? _buildErrorState()
                    : _recurringProfiles.isEmpty
                        ? _buildEmptyState()
                        : _buildRecurringProfilesTable(),
          ),
          if (!_isLoading && _recurringProfiles.isNotEmpty) _buildPagination(),
        ],
      ),
    );
  }

  // Top Bar
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        children: [
          const SizedBox(width: 8),

          // Status Filter Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              value: _selectedStatus,
              underline: const SizedBox(),
              icon: const Icon(Icons.arrow_drop_down),
              items: _statusFilters.map((status) {
                return DropdownMenuItem(
                  value: status,
                  child: Text(
                    status == 'All' ? 'All Recurring Expenses' : status,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) _filterByStatus(value);
              },
            ),
          ),

          const Spacer(),

          // Search
          SizedBox(
            width: 300,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search recurring expenses...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),

          const SizedBox(width: 12),

          // Filter Button
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list, size: 24),
                onPressed: _showFilterDialog,
                tooltip: 'Filter',
                style: IconButton.styleFrom(
                  backgroundColor: _hasActiveFilters
                      ? const Color(0xFF3498DB).withOpacity(0.2)
                      : Colors.grey[200],
                  padding: const EdgeInsets.all(12),
                ),
              ),
              if (_hasActiveFilters)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3498DB),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(width: 8),

          // Clear Filters Button (only show if filters active)
          if (_hasActiveFilters)
            TextButton.icon(
              onPressed: _clearAllFilters,
              icon: const Icon(Icons.clear, size: 18),
              label: const Text('Clear'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
            ),

          const SizedBox(width: 8),

          // Refresh Button
          IconButton(
            icon: const Icon(Icons.refresh, size: 24),
            onPressed: _isLoading ? null : _refreshData,
            tooltip: 'Refresh',
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey[200],
              padding: const EdgeInsets.all(12),
            ),
          ),

          const SizedBox(width: 16),

          // View Process Button
          OutlinedButton.icon(
            onPressed: _showLifecycleDialog,
            icon: const Icon(Icons.info_outline, size: 20),
            label: const Text('View Process'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF3498DB),
              side: const BorderSide(color: Color(0xFF3498DB)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // New Recurring Expense Button
          ElevatedButton.icon(
            onPressed: _openNewRecurringExpense,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('New Recurring Expense'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Export to Excel Button
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _exportToExcel,
            icon: const Icon(Icons.file_download, size: 20),
            label: const Text('Export Excel'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27AE60),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Stats Cards
  Widget _buildStatsCards() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        children: [
          _buildStatCard(
            'Total Profiles',
            _stats!.totalProfiles.toString(),
            Icons.repeat,
            Colors.blue,
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            'Active',
            _stats!.activeProfiles.toString(),
            Icons.check_circle,
            Colors.green,
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            'Paused',
            _stats!.pausedProfiles.toString(),
            Icons.pause_circle,
            Colors.orange,
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            'Stopped',
            _stats!.stoppedProfiles.toString(),
            Icons.stop_circle,
            Colors.red,
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            'Total Generated',
            _stats!.totalExpensesGenerated.toString(),
            Icons.receipt,
            Colors.purple,
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            'Total Amount',
            '₹${_stats!.totalAmountGenerated.toStringAsFixed(2)}',
            Icons.currency_rupee,
            Colors.teal,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Recurring Profiles Table
  Widget _buildRecurringProfilesTable() {
    // Filter by search
    final filteredProfiles = _searchQuery.isEmpty
        ? _recurringProfiles
        : _recurringProfiles.where((profile) {
            return profile.profileName.toLowerCase().contains(_searchQuery) ||
                profile.vendorName.toLowerCase().contains(_searchQuery);
          }).toList();

    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF34495E),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Checkbox(
                    value: _selectAll,
                    onChanged: _toggleSelectAll,
                    fillColor: MaterialStateProperty.all(Colors.white),
                    checkColor: const Color(0xFF34495E),
                  ),
                ),
                _buildHeaderCell('PROFILE NAME', flex: 3),
                _buildHeaderCell('VENDOR', flex: 2),
                _buildHeaderCell('FREQUENCY', flex: 2),
                _buildHeaderCell('NEXT EXPENSE', flex: 2),
                _buildHeaderCell('STATUS', flex: 1),
                _buildHeaderCell('GENERATED', flex: 1),
                _buildHeaderCell('AMOUNT', flex: 2),
                const SizedBox(width: 60), // Actions column
              ],
            ),
          ),

          // Table Rows
          Expanded(
            child: ListView.separated(
              itemCount: filteredProfiles.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: Colors.grey[200],
              ),
              itemBuilder: (context, index) {
                return _buildProfileRow(filteredProfiles[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildProfileRow(RecurringExpense profile) {
    final isSelected = _selectedProfiles.contains(profile.id);
    final frequency = '${profile.repeatEvery} ${profile.repeatUnit}(s)';
    final totalAmount = profile.amount + profile.tax;

    return InkWell(
      onTap: () => _openEditRecurringExpense(profile.id),
      child: Container(
        padding: const EdgeInsets.all(16),
        color: isSelected ? Colors.blue[50] : null,
        child: Row(
          children: [
            // Checkbox
            SizedBox(
              width: 40,
              child: Checkbox(
                value: isSelected,
                onChanged: (value) => _toggleSelection(profile.id),
              ),
            ),

            // Profile Name
            Expanded(
              flex: 3,
              child: InkWell(
                onTap: () => _openEditRecurringExpense(profile.id),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.profileName,
                      style: const TextStyle(
                        color: Color(0xFF3498DB),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.expenseCreationMode == 'auto_create'
                          ? '🚀 Auto-Create'
                          : '📝 Save as Draft',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Vendor Name
            Expanded(
              flex: 2,
              child: Text(
                profile.vendorName,
                style: const TextStyle(fontSize: 14),
              ),
            ),

            // Frequency
            Expanded(
              flex: 2,
              child: Text(
                frequency,
                style: const TextStyle(fontSize: 14),
              ),
            ),

            // Next Expense Date
            Expanded(
              flex: 2,
              child: Text(
                DateFormat('dd MMM yyyy').format(profile.nextExpenseDate),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            // Status Badge
            Expanded(
              flex: 1,
              child: _buildStatusBadge(profile.status),
            ),

            // Total Generated
            Expanded(
              flex: 1,
              child: InkWell(
                onTap: () => _viewChildExpenses(profile),
                child: Text(
                  profile.totalExpensesGenerated.toString(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3498DB),
                    decoration: TextDecoration.underline,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

            // Amount
            Expanded(
              flex: 2,
              child: Text(
                '₹${totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.right,
              ),
            ),

            // Actions
            SizedBox(
              width: 60,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit, size: 18),
                      title: Text('Edit'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'generate',
                    child: ListTile(
                      leading: Icon(Icons.add_circle, size: 18),
                      title: Text('Generate Expense'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'view_expenses',
                    child: ListTile(
                      leading: Icon(Icons.list, size: 18),
                      title: Text('View Child Expenses'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (profile.status == 'ACTIVE')
                    const PopupMenuItem(
                      value: 'pause',
                      child: ListTile(
                        leading: Icon(Icons.pause, size: 18),
                        title: Text('Pause'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (profile.status == 'PAUSED')
                    const PopupMenuItem(
                      value: 'resume',
                      child: ListTile(
                        leading: Icon(Icons.play_arrow, size: 18),
                        title: Text('Resume'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'stop',
                    child: ListTile(
                      leading:
                          Icon(Icons.stop, size: 18, color: Colors.orange),
                      title: Text('Stop',
                          style: TextStyle(color: Colors.orange)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete, size: 18, color: Colors.red),
                      title: Text('Delete',
                          style: TextStyle(color: Colors.red)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _openEditRecurringExpense(profile.id);
                      break;
                    case 'generate':
                      _generateManualExpense(profile);
                      break;
                    case 'view_expenses':
                      _viewChildExpenses(profile);
                      break;
                    case 'pause':
                      _pauseProfile(profile);
                      break;
                    case 'resume':
                      _resumeProfile(profile);
                      break;
                    case 'stop':
                      _stopProfile(profile);
                      break;
                    case 'delete':
                      _deleteProfile(profile);
                      break;
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color backgroundColor;
    Color textColor;

    switch (status) {
      case 'ACTIVE':
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        break;
      case 'PAUSED':
        backgroundColor = Colors.orange[100]!;
        textColor = Colors.orange[800]!;
        break;
      case 'STOPPED':
        backgroundColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        break;
      case 'RECORDED':
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        break;
      case 'DRAFT':
        backgroundColor = Colors.grey[100]!;
        textColor = Colors.grey[800]!;
        break;
      default:
        backgroundColor = Colors.blue[100]!;
        textColor = Colors.blue[800]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // Pagination
  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${(_currentPage - 1) * _itemsPerPage + 1} - ${(_currentPage * _itemsPerPage).clamp(0, _totalProfiles)} of $_totalProfiles',
            style: TextStyle(color: Colors.grey[700]),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 1
                    ? () {
                        setState(() {
                          _currentPage--;
                        });
                        _loadRecurringProfiles();
                      }
                    : null,
              ),
              ...List.generate(
                _totalPages.clamp(0, 5),
                (index) {
                  final pageNum = index + 1;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _currentPage = pageNum;
                        });
                        _loadRecurringProfiles();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _currentPage == pageNum
                              ? const Color(0xFF3498DB)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          pageNum.toString(),
                          style: TextStyle(
                            color: _currentPage == pageNum
                                ? Colors.white
                                : Colors.grey[700],
                            fontWeight: _currentPage == pageNum
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < _totalPages
                    ? () {
                        setState(() {
                          _currentPage++;
                        });
                        _loadRecurringProfiles();
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Empty State
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.repeat, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No recurring expense profiles found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first recurring profile to automate expense recording',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _openNewRecurringExpense,
            icon: const Icon(Icons.add),
            label: const Text('Create Recurring Expense'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  // Error State
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text(
            'Error Loading Recurring Profiles',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Unknown error',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _refreshData,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}