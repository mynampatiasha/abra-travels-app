// lib/screens/tms/all_tickets_screen.dart
// ============================================================================
// 🎫 ALL TICKETS SCREEN - Admin Dashboard (Shows ALL Tickets)
// ============================================================================
// Features:
// - Shows ALL tickets from all employees (no email filtering)
// - Compact statistics in single row
// - Click to navigate to ticket details
// - Reassign & Delete functionality
// - Beautiful modern card design
// - Table view with horizontal & vertical scrolling
// - Export to Excel functionality
// - Enhanced filters
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:abra_fleet/core/services/tms_service.dart';
import 'package:abra_fleet/features/TMS/ticket_detail_screen.dart';
import 'package:abra_fleet/core/utils/export_helper.dart';

class AllTicketsScreen extends StatefulWidget {
  const AllTicketsScreen({Key? key}) : super(key: key);

  @override
  State<AllTicketsScreen> createState() => _AllTicketsScreenState();
}

class _AllTicketsScreenState extends State<AllTicketsScreen>
    with SingleTickerProviderStateMixin {
  final _tmsService = TMSService();
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _tickets = [];
  List<Map<String, dynamic>> _filteredTickets = [];
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = true;
  bool _loadingEmployees = true;
  bool _isExporting = false;

  // Filters
  String _statusFilter = 'all';
  String _priorityFilter = '';
  String _assignedToFilter = '';
  String _searchQuery = '';
  
  // Date Range Filter
  DateTime? _fromDate;
  DateTime? _toDate;

  // Statistics
  int _totalCount = 0;
  int _openCount = 0;
  int _inProgressCount = 0;
  int _closedCount = 0;
  int _highPriorityCount = 0;
  int _unassignedCount = 0;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimation();
    _fetchEmployees();
    _fetchTickets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _setupAnimation() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  // ========================================================================
  // 📦 FETCH EMPLOYEES
  // ========================================================================
  Future<void> _fetchEmployees() async {
    setState(() => _loadingEmployees = true);

    final response = await _tmsService.fetchEmployees();

    print('📋 Employees Response: $response'); // Debug

    if (response['success'] == true && response['data'] != null) {
      setState(() {
        _employees = List<Map<String, dynamic>>.from(response['data']);
        _loadingEmployees = false;
      });
      print('✅ Loaded ${_employees.length} employees'); // Debug
    } else {
      setState(() => _loadingEmployees = false);
      print('❌ Failed to load employees'); // Debug
    }
  }

  // ========================================================================
  // 📦 FETCH ALL TICKETS (NO EMAIL FILTERING)
  // ========================================================================
  Future<void> _fetchTickets() async {
    setState(() => _isLoading = true);

    // 🔥 Use fetchAllTicketsAdmin instead of fetchMyTickets
    final response = await _tmsService.fetchAllTicketsAdmin(
      status: _statusFilter == 'all' ? null : _statusFilter,
      priority: _priorityFilter.isEmpty ? null : _priorityFilter,
      assignedTo: _assignedToFilter.isEmpty ? null : _assignedToFilter,
    );

    print('🎫 All Tickets Response: $response'); // Debug

    if (response['success'] == true && response['data'] != null) {
      setState(() {
        _tickets = List<Map<String, dynamic>>.from(response['data']);
        _applyFilters();
        _calculateStatistics();
        _isLoading = false;
      });
      print('✅ Loaded ${_tickets.length} tickets'); // Debug
    } else {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Failed to load tickets');
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredTickets = _tickets.where((ticket) {
        if (_searchQuery.isNotEmpty) {
          final subject = ticket['subject']?.toString().toLowerCase() ?? '';
          final ticketNumber =
              ticket['ticket_number']?.toString().toLowerCase() ?? '';
          final query = _searchQuery.toLowerCase();

          if (!subject.contains(query) && !ticketNumber.contains(query)) {
            return false;
          }
        }
        return true;
      }).toList();
    });
  }

  void _calculateStatistics() {
    _totalCount = _tickets.length;
    _openCount = 0;
    _inProgressCount = 0;
    _closedCount = 0;
    _highPriorityCount = 0;
    _unassignedCount = 0;

    for (final ticket in _tickets) {
      final status = ticket['status']?.toString() ?? '';
      final priority = ticket['priority']?.toString().toLowerCase() ?? '';
      final assignedTo = ticket['assigned_to'];

      if (status == 'Open') _openCount++;
      if (status == 'In Progress') _inProgressCount++;
      if (status == 'closed') _closedCount++;
      if (priority == 'high') _highPriorityCount++;
      if (assignedTo == null) _unassignedCount++;
    }
  }

  // ========================================================================
  // 🔄 REASSIGN TICKET
  // ========================================================================
  Future<void> _reassignTicket(String ticketId, String newEmployeeId) async {
    final response = await _tmsService.reassignTicket(ticketId, newEmployeeId);

    if (response['success'] == true) {
      _showSuccessSnackbar('Ticket reassigned successfully!');
      _fetchTickets();
    } else {
      _showErrorSnackbar('Failed to reassign ticket');
    }
  }

  void _showReassignDialog(
      String ticketId, String ticketNumber, String? currentAssignedId) {
    String selectedEmployeeId = currentAssignedId ?? '0';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Reassign Ticket $ticketNumber',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select an employee to assign this ticket to:'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedEmployeeId,
              decoration: InputDecoration(
                labelText: 'Assign To',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: [
                const DropdownMenuItem(
                  value: '0',
                  child: Text('Unassigned'),
                ),
                ..._employees.map((emp) {
                  return DropdownMenuItem<String>(
                    value: emp['_id'].toString(),
                    child: Text(emp['name_parson'] ?? 'Unknown'),
                  );
                }).toList(),
              ],
              onChanged: (value) {
                selectedEmployeeId = value ?? '0';
              },
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
              Navigator.pop(context);
              _reassignTicket(ticketId, selectedEmployeeId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Save Assignment'),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // 🗑️ DELETE TICKET
  // ========================================================================
  Future<void> _deleteTicket(String ticketId) async {
    final response = await _tmsService.deleteTicket(ticketId);

    if (response['success'] == true) {
      _showSuccessSnackbar('Ticket deleted successfully!');
      setState(() {
        _tickets.removeWhere((t) => t['_id'].toString() == ticketId);
        _applyFilters();
        _calculateStatistics();
      });
    } else {
      _showErrorSnackbar('Failed to delete ticket');
    }
  }

  void _showDeleteConfirmation(String ticketId, String ticketNumber) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Ticket?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete ticket $ticketNumber? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteTicket(ticketId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            Text(message),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ========================================================================
  // 📤 EXPORT TO EXCEL
  // ========================================================================
  Future<void> _exportToExcel() async {
    if (_filteredTickets.isEmpty) {
      _showErrorSnackbar('No tickets to export');
      return;
    }

    setState(() => _isExporting = true);

    try {
      _showSuccessSnackbar('Preparing Excel export...');

      // Prepare data for export
      List<List<dynamic>> csvData = [
        // Headers
        [
          'Ticket Number',
          'Subject',
          'Status',
          'Priority',
          'Assigned To',
          'Timeline (min)',
          'Deadline',
          'Created At',
          'Message',
        ],
      ];

      print('📊 Exporting ${_filteredTickets.length} tickets...');

      // Add data rows
      for (var ticket in _filteredTickets) {
        csvData.add([
          ticket['ticket_number'] ?? 'N/A',
          ticket['subject'] ?? 'No Subject',
          ticket['status'] ?? 'Open',
          ticket['priority'] ?? 'Medium',
          ticket['assigned_to_name'] ?? 'Unassigned',
          ticket['timeline']?.toString() ?? '0',
          ticket['deadline'] ?? 'No deadline',
          _formatDate(ticket['created_at']),
          ticket['message'] ?? '',
        ]);
      }

      // Use ExportHelper to export
      await ExportHelper.exportToExcel(
        data: csvData,
        filename: 'all_tickets_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
      );

      setState(() => _isExporting = false);
      _showSuccessSnackbar('✅ Excel file downloaded with ${_filteredTickets.length} tickets!');
    } catch (e) {
      setState(() => _isExporting = false);
      print('❌ Export Error: $e');
      _showErrorSnackbar('Failed to export: $e');
    }
  }

  // ========================================================================
  // 📅 DATE PICKER METHODS
  // ========================================================================
  Future<void> _selectFromDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF3B82F6),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _fromDate = picked;
        _applyFilters();
      });
    }
  }

  Future<void> _selectToDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF3B82F6),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _toDate = picked;
        _applyFilters();
      });
    }
  }

  void _clearDateFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _applyFilters();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Custom color scheme matching raise_ticket.dart
    const Color darkBlue = Color(0xFF042E45);
    const Color lightBlue = Color(0xFFEBF2F5);

    return Scaffold(
      backgroundColor: lightBlue,
      appBar: AppBar(
        backgroundColor: darkBlue,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'All Tickets',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        actions: [
          // Export Button
          IconButton(
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.file_download, color: Colors.white, size: 20),
                  ),
            onPressed: _isExporting ? null : _exportToExcel,
            tooltip: 'Export to Excel',
          ),
          // Refresh Button
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
            ),
            onPressed: _fetchTickets,
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchTickets,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Statistics Cards (Single Row)
                    _buildStatistics(),

                    // Filters (Single Row)
                    _buildFilters(),

                    // Tickets Table - Now scrollable within the main scroll
                    _buildTicketsTable(),
                  ],
                ),
              ),
            ),
    );
  }

  // ========================================================================
  // 📊 STATISTICS (SINGLE ROW, COMPACT)
  // ========================================================================
  Widget _buildStatistics() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildStatCard('Total', _totalCount, Icons.list_alt_rounded,
                const Color(0xFF3B82F6)),
            const SizedBox(width: 12),
            _buildStatCard('Open', _openCount, Icons.circle_outlined,
                const Color(0xFFEF4444)),
            const SizedBox(width: 12),
            _buildStatCard('In Progress', _inProgressCount,
                Icons.autorenew_rounded, const Color(0xFFF59E0B)),
            const SizedBox(width: 12),
            _buildStatCard('Closed', _closedCount, Icons.check_circle_rounded,
                const Color(0xFF10B981)),
            const SizedBox(width: 12),
            _buildStatCard('High Priority', _highPriorityCount,
                Icons.priority_high_rounded, const Color(0xFF8B5CF6)),
            const SizedBox(width: 12),
            _buildStatCard('Unassigned', _unassignedCount,
                Icons.person_off_rounded, const Color(0xFFEC4899)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, int count, IconData icon, Color color) {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // 🔍 FILTERS (SINGLE ROW)
  // ========================================================================
  Widget _buildFilters() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          // Search Bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search tickets...',
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B)),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _applyFilters();
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
                _applyFilters();
              });
            },
          ),
          const SizedBox(height: 12),

          // All Filters in Single Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Status Filter
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<String>(
                    value: _statusFilter,
                    decoration: InputDecoration(
                      labelText: 'Status',
                      labelStyle: const TextStyle(fontSize: 11),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
                    items: const [
                      DropdownMenuItem(
                          value: 'all',
                          child: Text('All', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: 'active',
                          child: Text('Active', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: 'Open',
                          child: Text('Open', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: 'In Progress',
                          child: Text('In Progress', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: 'closed',
                          child: Text('Closed', style: TextStyle(fontSize: 12))),
                    ],
                    onChanged: (value) {
                      setState(() => _statusFilter = value ?? 'all');
                      _fetchTickets();
                    },
                  ),
                ),
                const SizedBox(width: 8),

                // Priority Filter
                SizedBox(
                  width: 130,
                  child: DropdownButtonFormField<String>(
                    value: _priorityFilter,
                    decoration: InputDecoration(
                      labelText: 'Priority',
                      labelStyle: const TextStyle(fontSize: 11),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
                    items: const [
                      DropdownMenuItem(
                          value: '',
                          child: Text('All', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: 'High',
                          child: Text('High', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: 'Medium',
                          child: Text('Medium', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: 'Low',
                          child: Text('Low', style: TextStyle(fontSize: 12))),
                    ],
                    onChanged: (value) {
                      setState(() => _priorityFilter = value ?? '');
                      _fetchTickets();
                    },
                  ),
                ),
                const SizedBox(width: 8),

                // From Date
                InkWell(
                  onTap: _selectFromDate,
                  child: Container(
                    width: 140,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      color: _fromDate != null
                          ? const Color(0xFF3B82F6).withOpacity(0.1)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _fromDate != null
                            ? const Color(0xFF3B82F6)
                            : Colors.grey[300]!,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: _fromDate != null
                              ? const Color(0xFF3B82F6)
                              : Colors.grey[600],
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _fromDate != null
                                ? DateFormat('dd/MM/yy').format(_fromDate!)
                                : 'From Date',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: _fromDate != null
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: _fromDate != null
                                  ? const Color(0xFF3B82F6)
                                  : Colors.grey[700],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // To Date
                InkWell(
                  onTap: _selectToDate,
                  child: Container(
                    width: 140,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      color: _toDate != null
                          ? const Color(0xFF3B82F6).withOpacity(0.1)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _toDate != null
                            ? const Color(0xFF3B82F6)
                            : Colors.grey[300]!,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: _toDate != null
                              ? const Color(0xFF3B82F6)
                              : Colors.grey[600],
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _toDate != null
                                ? DateFormat('dd/MM/yy').format(_toDate!)
                                : 'To Date',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: _toDate != null
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: _toDate != null
                                  ? const Color(0xFF3B82F6)
                                  : Colors.grey[700],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Clear Date Filters Button
                if (_fromDate != null || _toDate != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.clear, color: Colors.red, size: 18),
                    onPressed: _clearDateFilters,
                    tooltip: 'Clear Date Filters',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red[50],
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // 📋 TICKETS TABLE WITH HORIZONTAL & VERTICAL SCROLLING (FULL SCREEN)
  // ========================================================================
  Widget _buildTicketsTable() {
    if (_filteredTickets.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.inbox_rounded,
                size: 80,
                color: Colors.grey.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'No tickets found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'Tickets List',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const Spacer(),
                Text(
                  '${_filteredTickets.length} tickets',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Table with Both Horizontal & Vertical Scrolling
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    columnSpacing: 24,
                    horizontalMargin: 16,
                    headingRowHeight: 56,
                    dataRowHeight: 72,
                    headingRowColor: MaterialStateProperty.all(
                      const Color(0xFFF8FAFC),
                    ),
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: Colors.grey[200]!,
                        width: 1,
                      ),
                    ),
                    columns: const [
                        DataColumn(
                          label: Text(
                            'Ticket #',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Subject',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Status',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Priority',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Assigned To',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Timeline',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Deadline',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Created',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Actions',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ],
                      rows: _filteredTickets.map((ticket) {
                        final ticketId = ticket['_id']?.toString() ?? '';
                        final ticketNumber = ticket['ticket_number'] ?? 'N/A';
                        final subject = ticket['subject'] ?? 'No Subject';
                        final priority = ticket['priority'] ?? 'Medium';
                        final status = ticket['status'] ?? 'Open';
                        final timeline = ticket['timeline'];
                        final deadline = ticket['deadline'];
                        final assignedToName = ticket['assigned_to_name'];
                        final assignedToId = ticket['assigned_to']?.toString();
                        final createdAt = ticket['created_at'];

                        return DataRow(
                          cells: [
                            // Ticket Number
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  ticketNumber,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        TicketDetailScreen(ticket: ticket),
                                  ),
                                ).then((_) => _fetchTickets());
                              },
                            ),

                            // Subject
                            DataCell(
                              Container(
                                constraints: const BoxConstraints(maxWidth: 250),
                                child: Text(
                                  subject,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        TicketDetailScreen(ticket: ticket),
                                  ),
                                ).then((_) => _fetchTickets());
                              },
                            ),

                            // Status
                            DataCell(_buildStatusBadge(status)),

                            // Priority
                            DataCell(_buildPriorityBadge(priority)),

                            // Assigned To
                            DataCell(_buildAssignedToBadge(assignedToName)),

                            // Timeline
                            DataCell(_buildTimelineBadge(timeline)),

                            // Deadline
                            DataCell(_buildDeadlineStatus(deadline)),

                            // Created
                            DataCell(
                              Row(
                                children: [
                                  const Icon(Icons.access_time_rounded,
                                      size: 14, color: Color(0xFF94A3B8)),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatDate(createdAt),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Actions
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Reassign Button
                                  IconButton(
                                    icon: const Icon(Icons.person_add_rounded,
                                        size: 18, color: Color(0xFF3B82F6)),
                                    onPressed: () => _showReassignDialog(
                                        ticketId, ticketNumber, assignedToId),
                                    tooltip: 'Reassign',
                                    style: IconButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF3B82F6).withOpacity(0.1),
                                      padding: const EdgeInsets.all(8),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  // Delete Button
                                  IconButton(
                                    icon: const Icon(Icons.delete_rounded,
                                        size: 18, color: Color(0xFFEF4444)),
                                    onPressed: () => _showDeleteConfirmation(
                                        ticketId, ticketNumber),
                                    tooltip: 'Delete',
                                    style: IconButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFFEF4444).withOpacity(0.1),
                                      padding: const EdgeInsets.all(8),
                                    ),
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
        ],
      ),
    );
  }

  // ========================================================================
  // 🎨 HELPER WIDGETS
  // ========================================================================
  Widget _buildPriorityBadge(String priority) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _getPriorityColor(priority).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getPriorityColor(priority), width: 1.5),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: _getPriorityColor(priority),
        ),
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return const Color(0xFFEF4444);
      case 'medium':
        return const Color(0xFFF59E0B);
      case 'low':
        return const Color(0xFF10B981);
      default:
        return Colors.grey;
    }
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    IconData icon;

    switch (status) {
      case 'Open':
        color = const Color(0xFFEF4444);
        icon = Icons.circle_outlined;
        break;
      case 'In Progress':
        color = const Color(0xFFF59E0B);
        icon = Icons.autorenew_rounded;
        break;
      case 'closed':
        color = const Color(0xFF10B981);
        icon = Icons.check_circle_rounded;
        break;
      default:
        color = Colors.grey;
        icon = Icons.help_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineBadge(int? minutes) {
    if (minutes == null || minutes <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 14, color: Color(0xFF94A3B8)),
            SizedBox(width: 4),
            Text(
              'Not Set',
              style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_rounded, size: 14, color: Color(0xFF10B981)),
          const SizedBox(width: 4),
          Text(
            _formatTimeline(minutes),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF10B981),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeline(int minutes) {
    if (minutes < 60) return '$minutes min';
    if (minutes < 1440) return '${(minutes / 60).floor()}h';
    if (minutes < 10080) return '${(minutes / 1440).floor()}d';
    if (minutes < 43200) return '${(minutes / 10080).floor()}w';
    return '${(minutes / 43200).floor()}mo';
  }

  Widget _buildDeadlineStatus(String? deadline) {
    if (deadline == null || deadline.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'No deadline',
          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
        ),
      );
    }

    final deadlineDate = DateTime.tryParse(deadline);
    if (deadlineDate == null) {
      return const Text('Invalid');
    }

    final now = DateTime.now();
    final difference = deadlineDate.difference(now);
    final isOverdue = difference.isNegative;

    Color bgColor, textColor;
    IconData icon;
    String statusText;

    if (isOverdue) {
      bgColor = const Color(0xFFFEE2E2);
      textColor = const Color(0xFFEF4444);
      icon = Icons.warning_rounded;
      statusText = 'Overdue';
    } else if (difference.inHours < 1) {
      bgColor = const Color(0xFFFEF3C7);
      textColor = const Color(0xFFF59E0B);
      icon = Icons.hourglass_bottom_rounded;
      statusText = '${difference.inMinutes}min left';
    } else if (difference.inHours < 4) {
      bgColor = const Color(0xFFFEF3C7);
      textColor = const Color(0xFFF59E0B);
      icon = Icons.hourglass_empty_rounded;
      statusText = '${difference.inHours}h left';
    } else {
      bgColor = const Color(0xFFDCFCE7);
      textColor = const Color(0xFF10B981);
      icon = Icons.check_circle_rounded;
      statusText = difference.inDays > 0
          ? '${difference.inDays}d left'
          : '${difference.inHours}h left';
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignedToBadge(String? name) {
    if (name == null || name.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_rounded,
                size: 14, color: Color(0xFFF59E0B)),
            SizedBox(width: 4),
            Text(
              'Unassigned',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF59E0B),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFDBEAFE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_rounded, size: 14, color: Color(0xFF3B82F6)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3B82F6),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'N/A';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return 'Invalid';
    return DateFormat('MMM dd').format(date);
  }
}