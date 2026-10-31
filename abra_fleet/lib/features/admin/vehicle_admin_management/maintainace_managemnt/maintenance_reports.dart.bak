import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Add 'intl' package to your pubspec.yaml
import 'package:abra_fleet/core/services/maintenance_service.dart';
import 'package:abra_fleet/core/services/vehicle_service.dart';

// Constants can be moved to a shared file, but are here for completeness
const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kTextSecondaryColor = Color(0xFF757575);
const Color kSuccessColor = Color(0xFF4CAF50);
const Color kErrorColor = Color(0xFFF44336);

// 1. Data Model for Maintenance Reports
class MaintenanceReport {
  final String id;
  final DateTime date;
  final String vehicleId;
  final String maintenanceType;
  final double cost;
  final String technicianName;
  final String notes;

  MaintenanceReport({
    required this.id,
    required this.date,
    required this.vehicleId,
    required this.maintenanceType,
    required this.cost,
    required this.technicianName,
    required this.notes,
  });
}

// ============ MAINTENANCE REPORTS SCREEN (FULLY FEATURED) ============
class MaintenanceReportsScreen extends StatefulWidget {
  final VoidCallback onBack;
  const MaintenanceReportsScreen({required this.onBack, Key? key})
      : super(key: key);

  @override
  State<MaintenanceReportsScreen> createState() =>
      _MaintenanceReportsScreenState();
}

class _MaintenanceReportsScreenState extends State<MaintenanceReportsScreen> {
  // State variables
  bool _isLoading = true;
  bool _hasError = false;
  List<MaintenanceReport> _allReports = [];
  List<MaintenanceReport> _filteredReports = [];
  final TextEditingController _searchController = TextEditingController();
  final MaintenanceService _maintenanceService = MaintenanceService();

  // State for date filtering
  bool _isFilterCardVisible = false;
  DateTime? _startDate;
  DateTime? _endDate;
  String _activeQuickFilter = '';

  // Mock data - In a real app, this would come from an API call
  final List<MaintenanceReport> _mockReports = [
    MaintenanceReport(id: 'R001', date: DateTime.now().subtract(const Duration(days: 1)), vehicleId: 'KA01AB1234', maintenanceType: 'Oil Change', cost: 1200, technicianName: 'Ahmed Hassan', notes: 'Used synthetic oil. Customer reported smooth performance.'),
    MaintenanceReport(id: 'R002', date: DateTime.now().subtract(const Duration(days: 5)), vehicleId: 'KA02CD5678', maintenanceType: 'Tire Rotation', cost: 800, technicianName: 'Mohammed Ali', notes: 'Checked tire pressure and alignment. All tires in good condition.'),
    MaintenanceReport(id: 'R003', date: DateTime.now().subtract(const Duration(days: 10)), vehicleId: 'KA03EF9012', maintenanceType: 'Brake Service', cost: 2500, technicianName: 'Fatima Khan', notes: 'Replaced front brake pads and serviced calipers.'),
    MaintenanceReport(id: 'R004', date: DateTime.now().subtract(const Duration(days: 20)), vehicleId: 'KA01AB1234', maintenanceType: 'AC Service', cost: 1800, technicianName: 'Ahmed Hassan', notes: 'AC gas refilled and filter cleaned. Cooling performance is now optimal.'),
    MaintenanceReport(id: 'R005', date: DateTime.now(), vehicleId: 'KA02CD5678', maintenanceType: 'General Inspection', cost: 500, technicianName: 'Mohammed Ali', notes: 'Routine checkup. No issues found.'),
  ];

  @override
  void initState() {
    super.initState();
    _fetchReports();
    _searchController.addListener(() {
      _filterReports();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // *** FIX: Moved the helper function to the class level ***
  DateTime _startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);

  Future<void> _fetchReports() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // Fetch reports from backend
      final result = await _maintenanceService.getMaintenanceReports(
        page: 1,
        limit: 100, // Get all reports for now
      );

      if (result['success']) {
        final List<dynamic> reportsData = result['data'] ?? [];
        final List<MaintenanceReport> backendReports = reportsData.map((data) {
          return MaintenanceReport(
            id: data['_id'] ?? data['id'] ?? '',
            date: DateTime.parse(data['completedDate'] ?? data['date'] ?? DateTime.now().toIso8601String()),
            vehicleId: data['vehicleNumber'] ?? data['vehicleId'] ?? '',
            maintenanceType: data['maintenanceType'] ?? '',
            cost: (data['actualCost'] ?? data['cost'] ?? 0).toDouble(),
            technicianName: data['vendorName'] ?? data['technicianName'] ?? '',
            notes: data['description'] ?? data['notes'] ?? '',
          );
        }).toList();

        setState(() {
          // Combine backend reports with mock data for demo
          _allReports = [...backendReports, ..._mockReports];
          _filteredReports = _allReports;
          _isLoading = false;
        });
      } else {
        // Fallback to mock data if backend fails
        setState(() {
          _allReports = _mockReports;
          _filteredReports = _allReports;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching reports: $e');
      // Fallback to mock data
      setState(() {
        _allReports = _mockReports;
        _filteredReports = _allReports;
        _isLoading = false;
      });
    }
  }

  void _filterReports() {
    List<MaintenanceReport> tempReports = _allReports;
    final String query = _searchController.text;

    // 1. Filter by Date
    if (_startDate != null || _endDate != null) {
      tempReports = tempReports.where((report) {
        final reportDate = _startOfDay(report.date); // Use class-level function
        if (_startDate != null && reportDate.isBefore(_startOfDay(_startDate!))) { // Use class-level function
          return false;
        }
        if (_endDate != null && reportDate.isAfter(_startOfDay(_endDate!))) { // Use class-level function
          return false;
        }
        return true;
      }).toList();
    }

    // 2. Filter by Search Query
    if (query.isNotEmpty) {
      tempReports = tempReports.where((report) {
        final queryLower = query.toLowerCase();
        return report.vehicleId.toLowerCase().contains(queryLower) ||
            report.maintenanceType.toLowerCase().contains(queryLower) ||
            report.technicianName.toLowerCase().contains(queryLower);
      }).toList();
    }
    
    setState(() {
      _filteredReports = tempReports;
    });
  }


  void _sortReports(String sortBy) {
    setState(() {
      if (sortBy == 'date_desc') {
        _filteredReports.sort((a, b) => b.date.compareTo(a.date));
      } else if (sortBy == 'date_asc') {
        _filteredReports.sort((a, b) => a.date.compareTo(b.date));
      } else if (sortBy == 'cost_desc') {
        _filteredReports.sort((a, b) => b.cost.compareTo(a.cost));
      } else if (sortBy == 'cost_asc') {
        _filteredReports.sort((a, b) => a.cost.compareTo(b.cost));
      }
    });
  }

  void _applyQuickFilter(String filterType) {
    setState(() {
      _activeQuickFilter = filterType;
      final now = DateTime.now();
      if (filterType == 'today') {
        _startDate = now;
        _endDate = now;
      } else if (filterType == 'yesterday') {
        final yesterday = now.subtract(const Duration(days: 1));
        _startDate = yesterday;
        _endDate = yesterday;
      } else if (filterType == 'last7days') {
        _startDate = now.subtract(const Duration(days: 6));
        _endDate = now;
      }
      _filterReports();
    });
  }

  void _clearDateFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _activeQuickFilter = '';
      _filterReports();
    });
  }

  // Add new maintenance report
  void _showAddReportDialog() {
    showDialog(
      context: context,
      builder: (context) => AddEditMaintenanceReportDialog(
        onSave: _addReport,
      ),
    );
  }

  // Edit maintenance report
  void _showEditReportDialog(MaintenanceReport report) {
    showDialog(
      context: context,
      builder: (context) => AddEditMaintenanceReportDialog(
        report: report,
        onSave: (updatedReport) => _updateReport(report.id, updatedReport),
      ),
    );
  }

  // Delete maintenance report
  void _showDeleteConfirmation(MaintenanceReport report) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Report'),
        content: Text('Are you sure you want to delete this maintenance report for ${report.vehicleId}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteReport(report.id);
            },
            style: TextButton.styleFrom(foregroundColor: kErrorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Add report to backend and update UI
  Future<void> _addReport(MaintenanceReport report) async {
    try {
      final result = await _maintenanceService.createMaintenanceReport(
        vehicleId: report.vehicleId,
        maintenanceType: report.maintenanceType,
        completedDate: report.date,
        vendorName: report.technicianName,
        actualCost: report.cost,
        description: report.notes,
        status: 'completed',
      );

      if (result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maintenance report added successfully'),
            backgroundColor: kSuccessColor,
          ),
        );
        _fetchReports(); // Refresh the list
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Failed to add report'),
            backgroundColor: kErrorColor,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: kErrorColor,
        ),
      );
    }
  }

  // Update report in backend and UI
  Future<void> _updateReport(String reportId, MaintenanceReport report) async {
    try {
      final result = await _maintenanceService.updateMaintenanceReport(
        reportId: reportId,
        vehicleId: report.vehicleId,
        maintenanceType: report.maintenanceType,
        completedDate: report.date,
        vendorName: report.technicianName,
        actualCost: report.cost,
        description: report.notes,
        status: 'completed',
      );

      if (result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maintenance report updated successfully'),
            backgroundColor: kSuccessColor,
          ),
        );
        _fetchReports(); // Refresh the list
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Failed to update report'),
            backgroundColor: kErrorColor,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: kErrorColor,
        ),
      );
    }
  }

  // Delete report from backend and UI
  Future<void> _deleteReport(String reportId) async {
    try {
      final result = await _maintenanceService.deleteMaintenanceReport(reportId);

      if (result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maintenance report deleted successfully'),
            backgroundColor: kSuccessColor,
          ),
        );
        _fetchReports(); // Refresh the list
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Failed to delete report'),
            backgroundColor: kErrorColor,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: kErrorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 1,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: _buildSearchField(),
        actions: [
          IconButton(
            icon: Icon(Icons.filter_list, color: _startDate != null || _endDate != null ? kPrimaryColor : kTextSecondaryColor),
            onPressed: () {
              setState(() {
                _isFilterCardVisible = !_isFilterCardVisible;
              });
            },
            tooltip: 'Filter by Date',
          ),
          IconButton(
            icon: const Icon(Icons.sort, color: kTextSecondaryColor),
            onPressed: _showSortOptions,
            tooltip: 'Sort Reports',
          ),
        ],
      ),
      body: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: _isFilterCardVisible ? null : 0,
            child: _buildFilterCard(),
          ),
          _buildActiveFiltersDisplay(),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddReportDialog,
        backgroundColor: kPrimaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Report', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search by Vehicle, Service, etc...',
        border: InputBorder.none,
        prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => _searchController.clear(),
              )
            : null,
      ),
    );
  }

  Widget _buildFilterCard() {
    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Quick Filters', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(label: const Text('Today'), backgroundColor: _activeQuickFilter == 'today' ? kPrimaryColor.withOpacity(0.2) : null, onPressed: () => _applyQuickFilter('today')),
                ActionChip(label: const Text('Yesterday'), backgroundColor: _activeQuickFilter == 'yesterday' ? kPrimaryColor.withOpacity(0.2) : null, onPressed: () => _applyQuickFilter('yesterday')),
                ActionChip(label: const Text('Last 7 Days'), backgroundColor: _activeQuickFilter == 'last7days' ? kPrimaryColor.withOpacity(0.2) : null, onPressed: () => _applyQuickFilter('last7days')),
              ],
            ),
            const Divider(height: 24),
            const Text('Custom Date', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildDatePickerField(label: 'Start Date', date: _startDate, onDateSelected: (d) => setState(() { _startDate = d; _activeQuickFilter = ''; }))),
                const SizedBox(width: 12),
                Expanded(child: _buildDatePickerField(label: 'End Date', date: _endDate, onDateSelected: (d) => setState(() { _endDate = d; _activeQuickFilter = ''; }))),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: _clearDateFilter, child: const Text('Clear All')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: () {
                   _filterReports();
                   setState(() => _isFilterCardVisible = false);
                }, child: const Text('Apply')),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDatePickerField({required String label, required DateTime? date, required ValueChanged<DateTime> onDateSelected}) {
    final formatter = DateFormat('dd MMM yyyy');
    return InkWell(
      onTap: () async {
        final pickedDate = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (pickedDate != null) {
          onDateSelected(pickedDate);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(date != null ? formatter.format(date) : 'Select...'),
            const Icon(Icons.calendar_today, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveFiltersDisplay() {
    if (_startDate == null && _endDate == null) {
      return const SizedBox.shrink();
    }

    final formatter = DateFormat('dd MMM yyyy');
    String filterText;
    if (_startDate != null && _endDate != null) {
      // Use the class-level helper function here
      if (_startOfDay(_startDate!) == _startOfDay(_endDate!)) {
        filterText = 'Filtering for: ${formatter.format(_startDate!)}';
      } else {
        filterText = 'Filtering: ${formatter.format(_startDate!)} - ${formatter.format(_endDate!)}';
      }
    } else if (_startDate != null) {
      filterText = 'Filtering from: ${formatter.format(_startDate!)}';
    } else {
      filterText = 'Filtering up to: ${formatter.format(_endDate!)}';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.blue.shade50,
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 20, color: kPrimaryColor),
          const SizedBox(width: 8),
          Expanded(child: Text(filterText, style: const TextStyle(color: kPrimaryColor, fontWeight: FontWeight.w500))),
          InkWell(onTap: _clearDateFilter, child: const Row(children: [Text('Clear', style: TextStyle(color: kPrimaryColor)), SizedBox(width: 4), Icon(Icons.close, size: 18, color: kPrimaryColor)])),
        ],
      ),
    );
  }
  
  
  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Wrap(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.arrow_downward),
            title: const Text('Sort by Date (Newest First)'),
            onTap: () {
              _sortReports('date_desc');
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.arrow_upward),
            title: const Text('Sort by Date (Oldest First)'),
            onTap: () {
              _sortReports('date_asc');
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.attach_money),
            title: const Text('Sort by Cost (High to Low)'),
            onTap: () {
              _sortReports('cost_desc');
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.money_off),
            title: const Text('Sort by Cost (Low to High)'),
            onTap: () {
              _sortReports('cost_asc');
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Failed to load reports.', style: TextStyle(color: kErrorColor)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _fetchReports,
              child: const Text('Try Again'),
            )
          ],
        ),
      );
    }
    if (_filteredReports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('No maintenance reports found.', style: TextStyle(fontSize: 16, color: kTextSecondaryColor)),
            if (_searchController.text.isNotEmpty || _startDate != null || _endDate != null)
              const Text('Try adjusting your search or filters.', style: TextStyle(color: kTextSecondaryColor)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchReports,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _filteredReports.length,
        itemBuilder: (context, index) {
          final report = _filteredReports[index];
          return ReportListItem(
            report: report,
            onEdit: () => _showEditReportDialog(report),
            onDelete: () => _showDeleteConfirmation(report),
          );
        },
      ),
    );
  }
}

// Widget for a single item in the report list
class ReportListItem extends StatelessWidget {
  final MaintenanceReport report;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  
  const ReportListItem({
    required this.report,
    this.onEdit,
    this.onDelete,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: () {
          // Navigate to a new detail screen
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => MaintenanceReportDetailScreen(report: report),
          ));
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      report.maintenanceType,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kPrimaryColor),
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        '₹${NumberFormat('#,##0').format(report.cost)}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: kSuccessColor),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit' && onEdit != null) {
                            onEdit!();
                          } else if (value == 'delete' && onDelete != null) {
                            onDelete!();
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 18),
                                SizedBox(width: 8),
                                Text('Edit'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 18, color: kErrorColor),
                                SizedBox(width: 8),
                                Text('Delete', style: TextStyle(color: kErrorColor)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildInfoRow(Icons.directions_car, report.vehicleId),
              const SizedBox(height: 6),
              _buildInfoRow(Icons.person_outline, report.technicianName),
              const SizedBox(height: 6),
              _buildInfoRow(Icons.calendar_today_outlined, DateFormat('dd MMM yyyy').format(report.date)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: kTextSecondaryColor),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 13, color: kTextSecondaryColor)),
      ],
    );
  }
}

// ============ DETAIL SCREEN FOR A SINGLE REPORT ============
class MaintenanceReportDetailScreen extends StatelessWidget {
  final MaintenanceReport report;

  const MaintenanceReportDetailScreen({required this.report, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Report: ${report.id}'),
        backgroundColor: kPrimaryColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailCard('Summary', [
              _buildDetailRow('Vehicle ID:', report.vehicleId),
              _buildDetailRow('Service:', report.maintenanceType),
              _buildDetailRow('Date:', DateFormat('dd MMMM yyyy').format(report.date)),
            ]),
            const SizedBox(height: 16),
            _buildDetailCard('Cost & Technician', [
              _buildDetailRow('Total Cost:', '₹${NumberFormat('#,##0.00').format(report.cost)}'),
              _buildDetailRow('Technician:', report.technicianName),
            ]),
            const SizedBox(height: 16),
             _buildDetailCard('Technician Notes', [
              Text(report.notes, style: const TextStyle(fontSize: 15, height: 1.5, color: kTextSecondaryColor)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(String title, List<Widget> children) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kPrimaryColor)),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 15, color: kTextSecondaryColor, fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ============ ADD/EDIT MAINTENANCE REPORT DIALOG ============
class AddEditMaintenanceReportDialog extends StatefulWidget {
  final MaintenanceReport? report;
  final Function(MaintenanceReport) onSave;

  const AddEditMaintenanceReportDialog({
    this.report,
    required this.onSave,
    Key? key,
  }) : super(key: key);

  @override
  State<AddEditMaintenanceReportDialog> createState() => _AddEditMaintenanceReportDialogState();
}

class _AddEditMaintenanceReportDialogState extends State<AddEditMaintenanceReportDialog> {
  final _formKey = GlobalKey<FormState>();
  final _vehicleIdController = TextEditingController();
  final _technicianController = TextEditingController();
  final _costController = TextEditingController();
  final _notesController = TextEditingController();
  
  String _selectedMaintenanceType = 'Oil Change';
  DateTime _selectedDate = DateTime.now();
  bool _isSubmitting = false;
  
  // Vehicle selection
  final VehicleService _vehicleService = VehicleService();
  List<Map<String, dynamic>> _vehicles = [];
  bool _isLoadingVehicles = false;
  String? _selectedVehicleId;
  String? _selectedVehicleDisplay;

  final List<String> _maintenanceTypes = [
    'Oil Change',
    'Filter Replacement',
    'Tire Rotation',
    'Brake Service',
    'General Inspection',
    'AC Service',
    'Engine Diagnostics',
    'Battery Service',
    'Transmission Service',
    'Cooling System',
  ];

  @override
  void initState() {
    super.initState();
    _loadVehicles();
    if (widget.report != null) {
      _selectedVehicleId = widget.report!.vehicleId;
      _vehicleIdController.text = widget.report!.vehicleId;
      _technicianController.text = widget.report!.technicianName;
      _costController.text = widget.report!.cost.toString();
      _notesController.text = widget.report!.notes;
      _selectedMaintenanceType = widget.report!.maintenanceType;
      _selectedDate = widget.report!.date;
    }
  }

  Future<void> _loadVehicles() async {
    setState(() {
      _isLoadingVehicles = true;
    });

    try {
      final result = await _vehicleService.getVehicles(page: 1, limit: 100);
      if (result['success'] == true) {
        setState(() {
          _vehicles = List<Map<String, dynamic>>.from(result['data'] ?? []);
          
          // If editing and we have a vehicle ID, find the matching vehicle
          if (widget.report != null && _selectedVehicleId != null) {
            final matchingVehicle = _vehicles.firstWhere(
              (vehicle) => 
                vehicle['_id'] == _selectedVehicleId ||
                vehicle['registrationNumber'] == _selectedVehicleId ||
                vehicle['vehicleNumber'] == _selectedVehicleId,
              orElse: () => {},
            );
            
            if (matchingVehicle.isNotEmpty) {
              _selectedVehicleDisplay = '${matchingVehicle['registrationNumber'] ?? matchingVehicle['vehicleNumber']} - ${matchingVehicle['make']} ${matchingVehicle['model']}';
            }
          }
        });
      }
    } catch (e) {
      print('Error loading vehicles: $e');
    } finally {
      setState(() {
        _isLoadingVehicles = false;
      });
    }
  }

  @override
  void dispose() {
    _vehicleIdController.dispose();
    _technicianController.dispose();
    _costController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.report == null ? 'Add Maintenance Report' : 'Edit Maintenance Report'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Vehicle Selection Dropdown
                _isLoadingVehicles
                    ? const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Text('Loading vehicles...'),
                          ],
                        ),
                      )
                    : DropdownButtonFormField<String>(
                        value: _selectedVehicleId,
                        decoration: const InputDecoration(
                          labelText: 'Select Vehicle',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.directions_car),
                        ),
                        hint: const Text('Choose a vehicle'),
                        items: _vehicles.map((vehicle) {
                          final vehicleId = vehicle['_id'] ?? '';
                          final registrationNumber = vehicle['registrationNumber'] ?? vehicle['vehicleNumber'] ?? 'Unknown';
                          final make = vehicle['make'] ?? '';
                          final model = vehicle['model'] ?? '';
                          final displayText = '$registrationNumber - $make $model';
                          
                          return DropdownMenuItem<String>(
                            value: registrationNumber, // Use registration number as the value
                            child: Text(
                              displayText,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedVehicleId = value;
                            _vehicleIdController.text = value ?? '';
                          });
                        },
                        validator: (value) => value?.isEmpty == true ? 'Please select a vehicle' : null,
                      ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedMaintenanceType,
                  decoration: const InputDecoration(
                    labelText: 'Maintenance Type',
                    border: OutlineInputBorder(),
                  ),
                  items: _maintenanceTypes.map((type) => DropdownMenuItem(
                    value: type,
                    child: Text(type),
                  )).toList(),
                  onChanged: (value) => setState(() => _selectedMaintenanceType = value!),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => _selectedDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Completion Date',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(DateFormat('dd MMM yyyy').format(_selectedDate)),
                        const Icon(Icons.calendar_today),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _technicianController,
                  decoration: const InputDecoration(
                    labelText: 'Technician/Vendor Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty == true ? 'Technician name is required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _costController,
                  decoration: const InputDecoration(
                    labelText: 'Cost (₹)',
                    border: OutlineInputBorder(),
                    prefixText: '₹ ',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value?.isEmpty == true) return 'Cost is required';
                    if (double.tryParse(value!) == null) return 'Enter a valid cost';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes/Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  validator: (value) => value?.isEmpty == true ? 'Notes are required' : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _saveReport,
          child: _isSubmitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.report == null ? 'Add' : 'Update'),
        ),
      ],
    );
  }

  void _saveReport() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final cost = double.parse(_costController.text);
      
      final report = MaintenanceReport(
        id: widget.report?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        date: _selectedDate,
        vehicleId: _selectedVehicleId ?? _vehicleIdController.text,
        maintenanceType: _selectedMaintenanceType,
        cost: cost,
        technicianName: _technicianController.text,
        notes: _notesController.text,
      );

      await widget.onSave(report);
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: kErrorColor,
        ),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }
}