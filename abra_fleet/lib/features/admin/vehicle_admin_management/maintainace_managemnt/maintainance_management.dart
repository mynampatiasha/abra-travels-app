import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'maintenance_reports.dart';
import 'schedule_maintenance.dart';
import 'vendor_management.dart';
import '../../../../core/services/maintenance_service.dart';
import '../../../../core/utils/export_helper.dart';

const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kTextPrimaryColor = Color(0xFF212121);
const Color kTextSecondaryColor = Color(0xFF757575);
const Color kWarningColor = Color(0xFFF57C00);
const Color kWarningBackgroundColor = Color(0xFFFFF8E1);
const Color kSuccessColor = Color(0xFF4CAF50);
const Color kErrorColor = Color(0xFFF44336);
const Color kInfoColor = Color(0xFF0288D1);

class MaintenanceManagementScreen extends StatefulWidget {
  const MaintenanceManagementScreen({super.key});

  @override
  State<MaintenanceManagementScreen> createState() =>
      _MaintenanceManagementScreenState();
}

class _MaintenanceManagementScreenState
    extends State<MaintenanceManagementScreen> {
  List<Widget> _overlayStack = [];
  final MaintenanceService _maintenanceService = MaintenanceService();
  List<Map<String, dynamic>> _scheduledMaintenances = [];
  List<Map<String, dynamic>> _filteredMaintenances = [];
  bool _isLoading = false;

  // Filter variables
  String _selectedStatus = 'All';
  DateTime? _fromDate;
  DateTime? _toDate;
  final TextEditingController _searchController = TextEditingController();

  // Pagination
  int _currentPage = 1;
  final int _itemsPerPage = 20;
  int _totalPages = 1;
  int _totalItems = 0;

  // Single scroll controller for the entire page
  final ScrollController _scrollController = ScrollController();

  final List<String> _statusFilters = [
    'All',
    'Scheduled',
    'In Progress',
    'Completed',
    'Cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _loadScheduledMaintenances();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadScheduledMaintenances() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _maintenanceService.getMaintenanceSchedules(
        page: _currentPage,
        limit: _itemsPerPage,
      );

      if (result['success'] == true) {
        setState(() {
          _scheduledMaintenances = List<Map<String, dynamic>>.from(result['data'] ?? []);
          _applyFilters();
          _isLoading = false;
        });
      } else {
        _showSnackBar('Failed to load scheduled maintenances: ${result['message']}');
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading scheduled maintenances: $e');
      _showSnackBar('Error loading scheduled maintenances');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> filtered = List.from(_scheduledMaintenances);

    // Status filter
    if (_selectedStatus != 'All') {
      filtered = filtered.where((m) {
        return m['status']?.toString().toLowerCase() == _selectedStatus.toLowerCase();
      }).toList();
    }

    // Date range filter
    if (_fromDate != null || _toDate != null) {
      filtered = filtered.where((m) {
        final scheduledDate = DateTime.tryParse(m['scheduledDate']?.toString() ?? '');
        if (scheduledDate == null) return false;

        if (_fromDate != null && scheduledDate.isBefore(_fromDate!)) {
          return false;
        }
        if (_toDate != null && scheduledDate.isAfter(_toDate!.add(const Duration(days: 1)))) {
          return false;
        }
        return true;
      }).toList();
    }

    // Search filter
    final searchQuery = _searchController.text.toLowerCase();
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((m) {
        return m['vehicleNumber']?.toString().toLowerCase().contains(searchQuery) == true ||
               m['maintenanceType']?.toString().toLowerCase().contains(searchQuery) == true ||
               m['vendorName']?.toString().toLowerCase().contains(searchQuery) == true;
      }).toList();
    }

    setState(() {
      _filteredMaintenances = filtered;
      _totalItems = filtered.length;
      _totalPages = (_totalItems / _itemsPerPage).ceil();
      if (_totalPages == 0) _totalPages = 1;
    });
  }

  Future<void> _refreshMaintenances() async {
    await _loadScheduledMaintenances();
    _showSnackBar('Maintenance data refreshed');
  }

  Future<void> _selectFromDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: kPrimaryColor),
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
            colorScheme: const ColorScheme.light(primary: kPrimaryColor),
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

  Future<void> _exportToExcel() async {
    try {
      if (_filteredMaintenances.isEmpty) {
        _showSnackBar('No maintenance records to export');
        return;
      }

      _showSnackBar('Preparing Excel export...');

      List<List<dynamic>> csvData = [
        // Headers
        [
          'Vehicle Number',
          'Make/Model',
          'Maintenance Type',
          'Scheduled Date',
          'Status',
          'Priority',
          'Vendor Name',
          'Estimated Cost',
          'Description',
          'Created By',
          'Created At',
        ],
      ];

      for (var maintenance in _filteredMaintenances) {
        final scheduledDate = DateTime.tryParse(maintenance['scheduledDate']?.toString() ?? '');
        final createdAt = DateTime.tryParse(maintenance['createdAt']?.toString() ?? '');

        csvData.add([
          maintenance['vehicleNumber'] ?? '',
          '${maintenance['vehicleMake'] ?? ''} ${maintenance['vehicleModel'] ?? ''}'.trim(),
          maintenance['maintenanceType'] ?? '',
          scheduledDate != null ? DateFormat('dd/MM/yyyy').format(scheduledDate) : '',
          maintenance['status'] ?? '',
          maintenance['priority'] ?? '',
          maintenance['vendorName'] ?? '',
          maintenance['estimatedCost']?.toString() ?? '0',
          maintenance['description'] ?? '',
          maintenance['createdBy'] ?? 'System',
          createdAt != null ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt) : '',
        ]);
      }

      await ExportHelper.exportToExcel(
        data: csvData,
        filename: 'maintenance_schedules',
      );

      _showSnackBar('✅ Excel file downloaded with ${_filteredMaintenances.length} records!');
    } catch (e) {
      print('❌ Export Error: $e');
      _showSnackBar('Failed to export: $e');
    }
  }

  void _pushOverlay(Widget overlay) {
    setState(() {
      _overlayStack.add(overlay);
    });
  }

  void _popOverlay() {
    if (_overlayStack.isNotEmpty) {
      setState(() {
        _overlayStack.removeLast();
      });
    }
  }

  void _clearAllOverlays() {
    setState(() {
      _overlayStack.clear();
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: kPrimaryColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showScheduleMaintenanceScreen() {
    _pushOverlay(
      _buildOverlayWrapper(
        title: 'Schedule Maintenance',
        child: ScheduleMaintenanceScreen(
          onBack: () {
            _popOverlay();
            _refreshMaintenances();
          },
        ),
      ),
    );
  }

  void _showMaintenanceReportsScreen() {
    _pushOverlay(
      _buildOverlayWrapper(
        title: 'Maintenance Reports',
        child: MaintenanceReportsScreen(onBack: _popOverlay),
      ),
    );
  }

  void _showVendorManagementScreen() {
    _pushOverlay(
      _buildOverlayWrapper(
        title: 'Vendor Management',
        child: const VendorManagementScreen(),
      ),
    );
  }

  void _showMaintenanceDetailsOverlay(Map<String, dynamic> maintenance) {
    _pushOverlay(
      Material(
        color: Colors.black54,
        child: Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.7,
            height: MediaQuery.of(context).size.height * 0.85,
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.description, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              maintenance['vehicleNumber'] ?? 'Unknown Vehicle',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Maintenance Details',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildStatusBadgeForOverlay(maintenance['status']?.toString() ?? 'Unknown'),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: _popOverlay,
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailSection(
                          'Vehicle Information',
                          [
                            _buildDetailRow('Vehicle Number', maintenance['vehicleNumber']),
                            _buildDetailRow('Make/Model', '${maintenance['vehicleMake'] ?? ''} ${maintenance['vehicleModel'] ?? ''}'.trim()),
                            _buildDetailRow('Vehicle Type', maintenance['vehicleType']),
                          ],
                        ),
                        const SizedBox(height: 24),

                        _buildDetailSection(
                          'Maintenance Information',
                          [
                            _buildDetailRow('Maintenance Type', maintenance['maintenanceType']),
                            _buildDetailRow('Scheduled Date', _formatDate(maintenance['scheduledDate'])),
                            _buildDetailRow('Status', maintenance['status']),
                            _buildDetailRow('Priority', maintenance['priority']),
                            if (maintenance['estimatedCost'] != null)
                              _buildDetailRow('Estimated Cost', '₹${maintenance['estimatedCost']}'),
                          ],
                        ),
                        const SizedBox(height: 24),

                        _buildDetailSection(
                          'Vendor Information',
                          [
                            _buildDetailRow('Vendor Name', maintenance['vendorName'] ?? 'Not assigned'),
                            if (maintenance['vendorEmail'] != null)
                              _buildDetailRow('Vendor Email', maintenance['vendorEmail']),
                            if (maintenance['vendorPhone'] != null)
                              _buildDetailRow('Vendor Phone', maintenance['vendorPhone']),
                          ],
                        ),
                        const SizedBox(height: 24),

                        if (maintenance['description'] != null && maintenance['description'].toString().isNotEmpty)
                          _buildDetailSection(
                            'Description / Notes',
                            [
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  maintenance['description'].toString(),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[800],
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),

                        const SizedBox(height: 24),
                        _buildDetailSection(
                          'Audit Information',
                          [
                            _buildDetailRow('Created By', maintenance['createdBy'] ?? 'System'),
                            _buildDetailRow('Created At', _formatDateTime(maintenance['createdAt'])),
                            _buildDetailRow('Last Updated', _formatDateTime(maintenance['updatedAt'])),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadgeForOverlay(String status) {
    Color backgroundColor;
    Color textColor;

    switch (status.toLowerCase()) {
      case 'scheduled':
        backgroundColor = kInfoColor.withOpacity(0.2);
        textColor = kInfoColor;
        break;
      case 'in progress':
        backgroundColor = kWarningColor.withOpacity(0.2);
        textColor = kWarningColor;
        break;
      case 'completed':
        backgroundColor = kSuccessColor.withOpacity(0.2);
        textColor = kSuccessColor;
        break;
      case 'cancelled':
        backgroundColor = kErrorColor.withOpacity(0.2);
        textColor = kErrorColor;
        break;
      default:
        backgroundColor = Colors.grey.withOpacity(0.2);
        textColor = Colors.grey[700]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: kPrimaryColor,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, dynamic value) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: kTextPrimaryColor,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.toString(),
              style: TextStyle(
                color: Colors.grey[800],
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'Not set';
    try {
      final DateTime dateTime = date is DateTime ? date : DateTime.parse(date.toString());
      return DateFormat('dd MMM yyyy').format(dateTime);
    } catch (e) {
      return date.toString();
    }
  }

  String _formatDateTime(dynamic date) {
    if (date == null) return 'Not available';
    try {
      final DateTime dateTime = date is DateTime ? date : DateTime.parse(date.toString());
      return DateFormat('dd MMM yyyy, HH:mm').format(dateTime);
    } catch (e) {
      return date.toString();
    }
  }

  Widget _buildOverlayWrapper({
    required String title,
    required Widget child,
  }) {
    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.95,
          height: MediaQuery.of(context).size.height * 0.90,
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _popOverlay,
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      title == 'Schedule Maintenance'
                          ? Icons.calendar_today_rounded
                          : title == 'Maintenance Reports'
                              ? Icons.analytics_rounded
                              : Icons.store_mall_directory_rounded,
                      color: kPrimaryColor,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _clearAllOverlays,
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: kPrimaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            debugPrint('🔙 ========================================');
            debugPrint('🔙 BACK BUTTON PRESSED in Maintenance Management');
            debugPrint('🔙 Calling Navigator.pop()...');
            debugPrint('🔙 ========================================');
            Navigator.of(context).pop();
            debugPrint('🔙 ✅ Navigator.pop() called successfully');
          },
          tooltip: 'Back to Admin Dashboard',
        ),
        title: const Text(
          'Maintenance Management',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    children: [
                      _buildTopBar(),
                      _buildQuickActionCards(),
                      _buildMaintenanceTable(),
                      if (_filteredMaintenances.isNotEmpty) _buildPagination(),
                    ],
                  ),
                ),
          ..._overlayStack,
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
              const Icon(Icons.build_circle, color: kPrimaryColor, size: 32),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Scheduled Maintenance',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: kPrimaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Filters Row
          Row(
            children: [
              // Status Filter
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
                        status,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedStatus = value;
                        _applyFilters();
                      });
                    }
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
                    hintText: 'Search by vehicle, type, vendor...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (value) => _applyFilters(),
                ),
              ),

              const SizedBox(width: 12),

              // From Date
              InkWell(
                onTap: _selectFromDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _fromDate != null ? kPrimaryColor.withOpacity(0.1) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _fromDate != null ? kPrimaryColor : Colors.grey[300]!,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 18,
                        color: _fromDate != null ? kPrimaryColor : Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _fromDate != null
                            ? 'From: ${DateFormat('dd/MM/yyyy').format(_fromDate!)}'
                            : 'From Date',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: _fromDate != null ? FontWeight.w600 : FontWeight.normal,
                          color: _fromDate != null ? kPrimaryColor : Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // To Date
              InkWell(
                onTap: _selectToDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _toDate != null ? kPrimaryColor.withOpacity(0.1) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _toDate != null ? kPrimaryColor : Colors.grey[300]!,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 18,
                        color: _toDate != null ? kPrimaryColor : Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _toDate != null
                            ? 'To: ${DateFormat('dd/MM/yyyy').format(_toDate!)}'
                            : 'To Date',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: _toDate != null ? FontWeight.w600 : FontWeight.normal,
                          color: _toDate != null ? kPrimaryColor : Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_fromDate != null || _toDate != null) ...[
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.red),
                  onPressed: _clearDateFilters,
                  tooltip: 'Clear Date Filters',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red[50],
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ],

              const SizedBox(width: 12),

              // Refresh Button
              IconButton(
                icon: const Icon(Icons.refresh, size: 24),
                onPressed: _isLoading ? null : _refreshMaintenances,
                tooltip: 'Refresh',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey[200],
                  padding: const EdgeInsets.all(12),
                ),
              ),

              const SizedBox(width: 12),

              // Export to Excel
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
        ],
      ),
    );
  }

  Widget _buildQuickActionCards() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: _buildActionCard(
              icon: Icons.calendar_today_rounded,
              title: 'Schedule Maintenance',
              description: 'Create new maintenance schedule',
              color: kPrimaryColor,
              onTap: _showScheduleMaintenanceScreen,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildActionCard(
              icon: Icons.analytics_rounded,
              title: 'Maintenance Reports',
              description: 'View reports and analytics',
              color: Colors.blue.shade700,
              onTap: _showMaintenanceReportsScreen,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildActionCard(
              icon: Icons.store_mall_directory_rounded,
              title: 'Vendor Management',
              description: 'Manage service vendors',
              color: Colors.grey.shade700,
              onTap: _showVendorManagementScreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
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
    );
  }

  Widget _buildMaintenanceTable() {
    if (_filteredMaintenances.isEmpty) {
      return _buildEmptyState();
    }

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
          // Table Title
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'Scheduled Maintenances',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: kPrimaryColor,
                  ),
                ),
                const Spacer(),
                Text(
                  'Showing ${_filteredMaintenances.length} of $_totalItems records',
                  style: TextStyle(
                    fontSize: 14,
                    color: kTextSecondaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Table with horizontal scrolling only
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 56,
              dataRowHeight: 72,
              headingRowColor: MaterialStateProperty.all(
                kPrimaryColor,
              ),
              columnSpacing: 24,
              horizontalMargin: 20,
              columns: const [
                DataColumn(
                  label: Text(
                    'VEHICLE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'MAKE/MODEL',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'MAINTENANCE TYPE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'SCHEDULED DATE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'STATUS',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'PRIORITY',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'VENDOR',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'COST',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'CREATED BY',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              rows: _filteredMaintenances.map((maintenance) {
                return DataRow(
                  onSelectChanged: (_) => _showMaintenanceDetailsOverlay(maintenance),
                  cells: [
                    DataCell(
                      Text(
                        maintenance['vehicleNumber']?.toString() ?? 'N/A',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        '${maintenance['vehicleMake'] ?? ''} ${maintenance['vehicleModel'] ?? ''}'.trim(),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    DataCell(
                      Text(
                        maintenance['maintenanceType']?.toString() ?? 'N/A',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    DataCell(
                      Text(
                        _formatDate(maintenance['scheduledDate']),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    DataCell(_buildStatusBadge(maintenance['status']?.toString() ?? 'Unknown')),
                    DataCell(_buildPriorityBadge(maintenance['priority']?.toString() ?? 'medium')),
                    DataCell(
                      Text(
                        maintenance['vendorName']?.toString() ?? 'Not assigned',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    DataCell(
                      Text(
                        maintenance['estimatedCost'] != null
                            ? '₹${maintenance['estimatedCost']}'
                            : '-',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        maintenance['createdBy']?.toString() ?? 'System',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color backgroundColor;
    Color textColor;

    switch (status.toLowerCase()) {
      case 'scheduled':
        backgroundColor = kInfoColor.withOpacity(0.1);
        textColor = kInfoColor;
        break;
      case 'in progress':
        backgroundColor = kWarningColor.withOpacity(0.1);
        textColor = kWarningColor;
        break;
      case 'completed':
        backgroundColor = kSuccessColor.withOpacity(0.1);
        textColor = kSuccessColor;
        break;
      case 'cancelled':
        backgroundColor = kErrorColor.withOpacity(0.1);
        textColor = kErrorColor;
        break;
      default:
        backgroundColor = Colors.grey[200]!;
        textColor = Colors.grey[800]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(String priority) {
    Color backgroundColor;
    Color textColor;

    switch (priority.toLowerCase()) {
      case 'urgent':
        backgroundColor = Colors.red[100]!;
        textColor = Colors.red[900]!;
        break;
      case 'high':
        backgroundColor = kWarningColor.withOpacity(0.1);
        textColor = kWarningColor;
        break;
      case 'medium':
        backgroundColor = Colors.blue[100]!;
        textColor = Colors.blue[900]!;
        break;
      case 'low':
        backgroundColor = Colors.grey[200]!;
        textColor = Colors.grey[800]!;
        break;
      default:
        backgroundColor = Colors.grey[200]!;
        textColor = Colors.grey[800]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No Scheduled Maintenances',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Click "Schedule Maintenance" to add new maintenance schedules',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showScheduleMaintenanceScreen,
            icon: const Icon(Icons.add),
            label: const Text('Schedule Maintenance'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${(_currentPage - 1) * _itemsPerPage + 1} - ${(_currentPage * _itemsPerPage).clamp(0, _totalItems)} of $_totalItems',
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
                          _applyFilters();
                        });
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
                          _applyFilters();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _currentPage == pageNum ? kPrimaryColor : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          pageNum.toString(),
                          style: TextStyle(
                            color: _currentPage == pageNum ? Colors.white : Colors.grey[700],
                            fontWeight: _currentPage == pageNum ? FontWeight.bold : FontWeight.normal,
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
                          _applyFilters();
                        });
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}