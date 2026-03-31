// ============================================================================
// DELIVERY CHALLANS LIST PAGE - PART 1 OF 2
// ============================================================================
// File: lib/screens/billing/delivery_challans_list_page.dart
// PART 1: Imports, State Variables, Init/Dispose, Data Loading Methods
// ============================================================================
// INSTRUCTIONS: Combine this with PART 2 to create the complete file
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_html/html.dart' as html;
import '../../../../core/utils/export_helper.dart';
import '../../../../core/services/delivery_challan_service.dart';
import '../app_top_bar.dart';
import 'new_delivery_challan.dart'; // ✅ ADD THIS LINE

class DeliveryChallansListPage extends StatefulWidget {
  const DeliveryChallansListPage({Key? key}) : super(key: key);

  @override
  State<DeliveryChallansListPage> createState() => _DeliveryChallansListPageState();
}

class _DeliveryChallansListPageState extends State<DeliveryChallansListPage> {
  // Data
  List<DeliveryChallan> _challans = [];
  ChallanStats? _stats;
  bool _isLoading = true;
  String? _errorMessage;
  
  // Filters
  String _selectedStatus = 'All';
  final List<String> _statusFilters = [
    'All',
    'DRAFT',
    'OPEN',
    'DELIVERED',
    'INVOICED',
    'PARTIALLY_INVOICED',
    'RETURNED',
    'PARTIALLY_RETURNED',
    'CANCELLED',
  ];
  
  // Date Range Filter
  DateTime? _fromDate;
  DateTime? _toDate;
  
  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalChallans = 0;
  final int _itemsPerPage = 20;
  
  // Selection
  final Set<String> _selectedChallans = {};
  bool _selectAll = false;
  
  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadChallans();
    _loadStats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================================
  // DATA LOADING METHODS
  // ============================================================================

  // Load challans from backend
  Future<void> _loadChallans() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await DeliveryChallanService.getDeliveryChallans(
        status: _selectedStatus == 'All' ? null : _selectedStatus,
        fromDate: _fromDate,
        toDate: _toDate,
        page: _currentPage,
        limit: _itemsPerPage,
      );

      setState(() {
        _challans = response.challans;
        _totalPages = response.pagination.pages;
        _totalChallans = response.pagination.total;
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
      final stats = await DeliveryChallanService.getStats();
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
      _loadChallans(),
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
    _loadChallans();
  }

  // Toggle selection
  void _toggleSelection(String challanId) {
    setState(() {
      if (_selectedChallans.contains(challanId)) {
        _selectedChallans.remove(challanId);
      } else {
        _selectedChallans.add(challanId);
      }
      _selectAll = _selectedChallans.length == _challans.length;
    });
  }

  // Toggle select all
  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        _selectedChallans.addAll(_challans.map((ch) => ch.id));
      } else {
        _selectedChallans.clear();
      }
    });
  }

  // ============================================================================
  // NAVIGATION & ACTION METHODS
  // ============================================================================

// Navigate to new challan
  void _openNewChallan() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NewDeliveryChallanScreen(),
      ),
    );
    
    if (result == true) {
      _refreshData();
    }
  }

  // Navigate to edit challan
  void _openEditChallan(String challanId) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewDeliveryChallanScreen(challanId: challanId),
      ),
    );
    
    if (result == true) {
      _refreshData();
    }
  }

  // View challan details
  Future<void> _viewChallanDetails(DeliveryChallan challan) async {
    setState(() => _isLoading = true);
    
    try {
      final fullChallan = await DeliveryChallanService.getDeliveryChallan(challan.id);
      setState(() => _isLoading = false);
      
      showDialog(
        context: context,
        builder: (context) => _buildDetailsDialog(fullChallan),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Failed to load challan details: ${e.toString()}');
    }
  }

  // Delete challan
  Future<void> _deleteChallan(DeliveryChallan challan) async {
    if (challan.status != 'DRAFT') {
      _showErrorSnackbar('Only draft challans can be deleted');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Delivery Challan'),
        content: Text('Are you sure you want to delete challan ${challan.challanNumber}?'),
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
        await DeliveryChallanService.deleteDeliveryChallan(challan.id);
        _showSuccessSnackbar('Challan deleted successfully');
        _refreshData();
      } catch (e) {
        _showErrorSnackbar('Failed to delete challan: $e');
      }
    }
  }

  // Dispatch challan
  Future<void> _dispatchChallan(DeliveryChallan challan) async {
    if (challan.status != 'DRAFT') {
      _showErrorSnackbar('Only draft challans can be dispatched');
      return;
    }

    try {
      await DeliveryChallanService.dispatchChallan(challan.id);
      _showSuccessSnackbar('Challan marked as dispatched');
      _refreshData();
    } catch (e) {
      _showErrorSnackbar('Failed to dispatch challan: $e');
    }
  }

  // Mark as delivered
  Future<void> _markAsDelivered(DeliveryChallan challan) async {
    if (challan.status != 'OPEN') {
      _showErrorSnackbar('Only dispatched challans can be marked as delivered');
      return;
    }

    try {
      await DeliveryChallanService.markAsDelivered(challan.id);
      _showSuccessSnackbar('Challan marked as delivered');
      _refreshData();
    } catch (e) {
      _showErrorSnackbar('Failed to mark as delivered: $e');
    }
  }

  // Convert to invoice
  Future<void> _convertToInvoice(DeliveryChallan challan) async {
    if (challan.status != 'DELIVERED' && challan.status != 'PARTIALLY_INVOICED') {
      _showErrorSnackbar('Only delivered challans can be converted to invoice');
      return;
    }

    try {
      final result = await DeliveryChallanService.convertToInvoice(challan.id);
      
      _showSuccessSnackbar('Challan converted to invoice successfully');
      _refreshData();
      
      // TODO: Navigate to invoice page with pre-filled data
      // Navigator.push(context, MaterialPageRoute(
      //   builder: (context) => NewInvoiceScreen(
      //     prefilledData: result['invoiceData'],
      //   ),
      // ));
      
    } catch (e) {
      _showErrorSnackbar('Failed to convert to invoice: $e');
    }
  }

  // Mark as returned
  Future<void> _markAsReturned(DeliveryChallan challan) async {
    try {
      await DeliveryChallanService.markAsReturned(challan.id);
      _showSuccessSnackbar('Challan marked as returned');
      _refreshData();
    } catch (e) {
      _showErrorSnackbar('Failed to mark as returned: $e');
    }
  }

  // Send challan
  Future<void> _sendChallan(DeliveryChallan challan) async {
    if (challan.customerEmail == null || challan.customerEmail!.isEmpty) {
      _showErrorSnackbar('Customer email is required to send challan');
      return;
    }

    try {
      await DeliveryChallanService.sendChallan(challan.id);
      _showSuccessSnackbar('Challan sent to ${challan.customerEmail}');
      _refreshData();
    } catch (e) {
      _showErrorSnackbar('Failed to send challan: $e');
    }
  }

  // Download PDF
  Future<void> _downloadChallanPDF(DeliveryChallan challan) async {
    try {
      _showSuccessSnackbar('Preparing PDF download...');
      
      final pdfUrl = await DeliveryChallanService.downloadPDF(challan.id);
      
      if (kIsWeb) {
        html.AnchorElement(href: pdfUrl)
          ..setAttribute('download', '${challan.challanNumber}.pdf')
          ..setAttribute('target', '_blank')
          ..click();
        
        _showSuccessSnackbar('✅ PDF download started for ${challan.challanNumber}');
      } else {
        final uri = Uri.parse(pdfUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          _showSuccessSnackbar('✅ PDF opened for ${challan.challanNumber}');
        } else {
          throw 'Could not launch PDF viewer';
        }
      }
    } catch (e) {
      print('PDF Download Error: $e');
      _showErrorSnackbar('Failed to download PDF: $e');
    }
  }

  // Export to Excel
  Future<void> _exportToExcel() async {
    try {
      if (_challans.isEmpty) {
        _showErrorSnackbar('No challans to export');
        return;
      }

      _showSuccessSnackbar('Preparing Excel export...');

      List<List<dynamic>> csvData = [
        [
          'Date',
          'Challan Number',
          'Reference Number',
          'Customer Name',
          'Customer Email',
          'Status',
          'Expected Delivery',
          'Purpose',
          'Transport Mode',
          'Vehicle Number',
          'Total Items',
          'Total Quantity',
        ],
      ];

      print('📊 Exporting ${_challans.length} challans...');

      for (var challan in _challans) {
        csvData.add([
          DateFormat('dd/MM/yyyy').format(challan.challanDate),
          challan.challanNumber,
          challan.referenceNumber ?? '',
          challan.customerName,
          challan.customerEmail ?? '',
          challan.status,
          challan.expectedDeliveryDate != null 
              ? DateFormat('dd/MM/yyyy').format(challan.expectedDeliveryDate!)
              : '',
          challan.purpose,
          challan.transportMode,
          challan.vehicleNumber ?? '',
          challan.items.length.toString(),
          challan.items.fold(0.0, (sum, item) => sum + item.quantity).toString(),
        ]);
      }

      final filePath = await ExportHelper.exportToExcel(
        data: csvData,
        filename: 'delivery_challans',
      );

      _showSuccessSnackbar('✅ Excel file downloaded with ${_challans.length} challans!');
    } catch (e) {
      print('❌ Export Error: $e');
      _showErrorSnackbar('Failed to export: $e');
    }
  }

  // ============================================================================
  // DATE PICKER METHODS
  // ============================================================================
  
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
              primary: Color(0xFF3498DB),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        _fromDate = picked;
      });
      _loadChallans();
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
              primary: Color(0xFF3498DB),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        _toDate = picked;
      });
      _loadChallans();
    }
  }
  
  void _clearDateFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    _loadChallans();
  }

  // ============================================================================
  // SNACKBAR HELPERS
  // ============================================================================

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

// ============================================================================
// END OF PART 1
// Continue with PART 2 for the build methods and UI widgets
// ============================================================================
// ============================================================================
// DELIVERY CHALLANS LIST PAGE - PART 2 OF 2
// ============================================================================
// PART 2: Build Methods and UI Widgets
// ============================================================================
// INSTRUCTIONS: 
// 1. Remove the lines below from PART 1 (they're duplicated here for context):
//    - The closing braces and class ending
// 2. Append this entire file content to PART 1
// 3. This creates the complete delivery_challans_list_page.dart file
// ============================================================================

  // ============================================================================
  // BUILD METHOD - MAIN SCAFFOLD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Delivery Challans'),
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
                    : _challans.isEmpty
                        ? _buildEmptyState()
                        : _buildChallansTable(),
          ),
          if (!_isLoading && _challans.isNotEmpty) _buildPagination(),
        ],
      ),
    );
  }

  // ============================================================================
  // TOP BAR - RESPONSIVE
  // ============================================================================

  Widget _buildTopBar() {
    final isMobile = MediaQuery.of(context).size.width < 900;
    
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: isMobile
          ? Column(
              children: [
                // Row 1: Status dropdown + Search bar
                Row(
                  children: [
                    // Status Filter Dropdown
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButton<String>(
                          value: _selectedStatus,
                          underline: const SizedBox(),
                          icon: const Icon(Icons.arrow_drop_down),
                          isExpanded: true,
                          items: _statusFilters.map((status) {
                            return DropdownMenuItem(
                              value: status,
                              child: Text(
                                status == 'All' ? 'All Challans' : status.replaceAll('_', ' '),
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
                    ),
                    const SizedBox(width: 12),
                    // Search
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search challans...',
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
                  ],
                ),
                const SizedBox(height: 12),
                // Row 2: All buttons in horizontal scroll
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // From Date
                      InkWell(
                        onTap: _selectFromDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: _fromDate != null ? const Color(0xFF3498DB).withOpacity(0.1) : Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _fromDate != null ? const Color(0xFF3498DB) : Colors.grey[300]!,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: _fromDate != null ? const Color(0xFF3498DB) : Colors.grey[600],
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _fromDate != null
                                    ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}'
                                    : 'From Date',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: _fromDate != null ? FontWeight.w600 : FontWeight.normal,
                                  color: _fromDate != null ? const Color(0xFF3498DB) : Colors.grey[700],
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: _toDate != null ? const Color(0xFF3498DB).withOpacity(0.1) : Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _toDate != null ? const Color(0xFF3498DB) : Colors.grey[300]!,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: _toDate != null ? const Color(0xFF3498DB) : Colors.grey[600],
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _toDate != null
                                    ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}'
                                    : 'To Date',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: _toDate != null ? FontWeight.w600 : FontWeight.normal,
                                  color: _toDate != null ? const Color(0xFF3498DB) : Colors.grey[700],
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
                          icon: const Icon(Icons.clear, color: Colors.red, size: 20),
                          onPressed: _clearDateFilters,
                          tooltip: 'Clear Date Filters',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.red[50],
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      // Refresh Button
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: _isLoading ? null : _refreshData,
                        tooltip: 'Refresh',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // New Challan Button
                      ElevatedButton.icon(
                        onPressed: _openNewChallan,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('New Challan', style: TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3498DB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Export to Excel Button
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _exportToExcel,
                        icon: const Icon(Icons.file_download, size: 18),
                        label: const Text('Export Excel', style: TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF27AE60),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Row(
              children: [
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
                          status == 'All' ? 'All Challans' : status.replaceAll('_', ' '),
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
                      hintText: 'Search challans...',
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
                
                // From Date
                InkWell(
                  onTap: _selectFromDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _fromDate != null ? const Color(0xFF3498DB).withOpacity(0.1) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _fromDate != null ? const Color(0xFF3498DB) : Colors.grey[300]!,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 18,
                          color: _fromDate != null ? const Color(0xFF3498DB) : Colors.grey[600],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _fromDate != null
                              ? 'From: ${DateFormat('dd/MM/yyyy').format(_fromDate!)}'
                              : 'From Date',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: _fromDate != null ? FontWeight.w600 : FontWeight.normal,
                            color: _fromDate != null ? const Color(0xFF3498DB) : Colors.grey[700],
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
                      color: _toDate != null ? const Color(0xFF3498DB).withOpacity(0.1) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _toDate != null ? const Color(0xFF3498DB) : Colors.grey[300]!,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 18,
                          color: _toDate != null ? const Color(0xFF3498DB) : Colors.grey[600],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _toDate != null
                              ? 'To: ${DateFormat('dd/MM/yyyy').format(_toDate!)}'
                              : 'To Date',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: _toDate != null ? FontWeight.w600 : FontWeight.normal,
                            color: _toDate != null ? const Color(0xFF3498DB) : Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Clear Date Filters
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
                  onPressed: _isLoading ? null : _refreshData,
                  tooltip: 'Refresh',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey[200],
                    padding: const EdgeInsets.all(12),
                  ),
                ),

                const SizedBox(width: 16),

                // New Challan Button
                ElevatedButton.icon(
                  onPressed: _openNewChallan,
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('New Challan'),
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

  // ============================================================================
  // STATS CARDS
  // ============================================================================

  Widget _buildStatsCards() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        children: [
          _buildStatCard(
            'Total Challans',
            _stats!.totalChallans.toString(),
            Icons.description,
            Colors.blue,
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            'Draft',
            (_stats!.byStatus['DRAFT'] ?? 0).toString(),
            Icons.drafts,
            Colors.grey,
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            'Open',
            (_stats!.byStatus['OPEN'] ?? 0).toString(),
            Icons.local_shipping,
            Colors.orange,
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            'Delivered',
            (_stats!.byStatus['DELIVERED'] ?? 0).toString(),
            Icons.check_circle,
            Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
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
            Column(
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
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // CHALLANS TABLE
  // ============================================================================

  Widget _buildChallansTable() {
    // Filter by search
    List<DeliveryChallan> filteredChallans = _searchQuery.isEmpty
        ? _challans
        : _challans.where((challan) {
            return challan.challanNumber.toLowerCase().contains(_searchQuery) ||
                   challan.customerName.toLowerCase().contains(_searchQuery) ||
                   (challan.referenceNumber?.toLowerCase().contains(_searchQuery) ?? false);
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
            decoration: const BoxDecoration(
              color: Color(0xFF34495E),
              borderRadius: BorderRadius.only(
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
                _buildHeaderCell('DATE', flex: 2),
                _buildHeaderCell('CHALLAN#', flex: 2),
                _buildHeaderCell('REFERENCE', flex: 2),
                _buildHeaderCell('CUSTOMER', flex: 3),
                _buildHeaderCell('STATUS', flex: 2),
                _buildHeaderCell('ITEMS', flex: 1),
                _buildHeaderCell('QUANTITY', flex: 1),
                const SizedBox(width: 60),
              ],
            ),
          ),

          // Table Rows
          Expanded(
            child: ListView.separated(
              itemCount: filteredChallans.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: Colors.grey[200],
              ),
              itemBuilder: (context, index) {
                return _buildChallanRow(filteredChallans[index]);
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

  Widget _buildChallanRow(DeliveryChallan challan) {
    final isSelected = _selectedChallans.contains(challan.id);
    final totalQty = challan.items.fold(0.0, (sum, item) => sum + item.quantity);

    return InkWell(
      onTap: () => _openEditChallan(challan.id),
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
                onChanged: (value) => _toggleSelection(challan.id),
              ),
            ),

            // Date
            Expanded(
              flex: 2,
              child: Text(
                DateFormat('dd/MM/yyyy').format(challan.challanDate),
                style: const TextStyle(fontSize: 14),
              ),
            ),

            // Challan Number
            Expanded(
              flex: 2,
              child: InkWell(
                onTap: () => _openEditChallan(challan.id),
                child: Text(
                  challan.challanNumber,
                  style: const TextStyle(
                    color: Color(0xFF3498DB),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),

            // Reference Number
            Expanded(
              flex: 2,
              child: Text(
                challan.referenceNumber ?? '-',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ),

            // Customer Name
            Expanded(
              flex: 3,
              child: Text(
                challan.customerName,
                style: const TextStyle(fontSize: 14),
              ),
            ),

            // Status Badge
            Expanded(
              flex: 2,
              child: _buildStatusBadge(challan.status),
            ),

            // Items Count
            Expanded(
              flex: 1,
              child: Text(
                challan.items.length.toString(),
                style: const TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),

            // Total Quantity
            Expanded(
              flex: 1,
              child: Text(
                totalQty.toStringAsFixed(0),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            // Actions
            SizedBox(
              width: 60,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'view',
                    child: ListTile(
                      leading: Icon(Icons.visibility, size: 18, color: Color(0xFF3498DB)),
                      title: Text('View Details'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit, size: 18),
                      title: Text('Edit'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (challan.status == 'DRAFT')
                    const PopupMenuItem(
                      value: 'dispatch',
                      child: ListTile(
                        leading: Icon(Icons.local_shipping, size: 18),
                        title: Text('Dispatch'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (challan.status == 'OPEN')
                    const PopupMenuItem(
                      value: 'delivered',
                      child: ListTile(
                        leading: Icon(Icons.check_circle, size: 18, color: Colors.green),
                        title: Text('Mark as Delivered'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (challan.status == 'DELIVERED' || challan.status == 'PARTIALLY_INVOICED')
                    const PopupMenuItem(
                      value: 'convert',
                      child: ListTile(
                        leading: Icon(Icons.receipt_long, size: 18, color: Color(0xFF3498DB)),
                        title: Text('Convert to Invoice'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'send',
                    child: ListTile(
                      leading: Icon(Icons.send, size: 18),
                      title: Text('Send'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'download',
                    child: ListTile(
                      leading: Icon(Icons.download, size: 18),
                      title: Text('Download PDF'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (challan.status != 'DRAFT')
                    const PopupMenuItem(
                      value: 'return',
                      child: ListTile(
                        leading: Icon(Icons.keyboard_return, size: 18, color: Colors.orange),
                        title: Text('Mark as Returned'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (challan.status == 'DRAFT')
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete, size: 18, color: Colors.red),
                        title: Text('Delete', style: TextStyle(color: Colors.red)),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                ],
                onSelected: (value) async {
                  switch (value) {
                    case 'view':
                      _viewChallanDetails(challan);
                      break;
                    case 'edit':
                      _openEditChallan(challan.id);
                      break;
                    case 'dispatch':
                      _dispatchChallan(challan);
                      break;
                    case 'delivered':
                      _markAsDelivered(challan);
                      break;
                    case 'convert':
                      _convertToInvoice(challan);
                      break;
                    case 'send':
                      _sendChallan(challan);
                      break;
                    case 'download':
                      await _downloadChallanPDF(challan);
                      break;
                    case 'return':
                      _markAsReturned(challan);
                      break;
                    case 'delete':
                      _deleteChallan(challan);
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
      case 'DELIVERED':
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        break;
      case 'DRAFT':
        backgroundColor = Colors.grey[200]!;
        textColor = Colors.grey[800]!;
        break;
      case 'OPEN':
        backgroundColor = Colors.orange[100]!;
        textColor = Colors.orange[800]!;
        break;
      case 'INVOICED':
        backgroundColor = Colors.blue[100]!;
        textColor = Colors.blue[800]!;
        break;
      case 'PARTIALLY_INVOICED':
        backgroundColor = Colors.purple[100]!;
        textColor = Colors.purple[800]!;
        break;
      case 'RETURNED':
      case 'PARTIALLY_RETURNED':
        backgroundColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        break;
      case 'CANCELLED':
        backgroundColor = Colors.grey[300]!;
        textColor = Colors.grey[700]!;
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
        status.replaceAll('_', ' '),
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ============================================================================
  // PAGINATION
  // ============================================================================

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${(_currentPage - 1) * _itemsPerPage + 1} - ${(_currentPage * _itemsPerPage).clamp(0, _totalChallans)} of $_totalChallans',
            style: TextStyle(color: Colors.grey[700]),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 1
                    ? () {
                        setState(() => _currentPage--);
                        _loadChallans();
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
                        setState(() => _currentPage = pageNum);
                        _loadChallans();
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
                        setState(() => _currentPage++);
                        _loadChallans();
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // EMPTY STATE
  // ============================================================================

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_shipping_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No delivery challans found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first delivery challan to get started',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _openNewChallan,
            icon: const Icon(Icons.add),
            label: const Text('Create Challan'),
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

  // ============================================================================
  // ERROR STATE
  // ============================================================================

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text(
            'Error Loading Challans',
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

  // ============================================================================
  // DETAILS DIALOG
  // ============================================================================

  Widget _buildDetailsDialog(DeliveryChallan challan) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.local_shipping, color: Color(0xFF3498DB), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        challan.challanNumber,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                      Text(
                        'Delivery Challan Details',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(challan.status),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 32),
            
            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailSection('Customer Information', [
                      _buildDetailRow('Customer Name', challan.customerName),
                      _buildDetailRow('Email', challan.customerEmail),
                      _buildDetailRow('Phone', challan.customerPhone),
                      if (challan.deliveryAddress != null)
                        _buildDetailRow('Address',
                            '${challan.deliveryAddress!.street ?? ''}, ${challan.deliveryAddress!.city ?? ''}, ${challan.deliveryAddress!.state ?? ''} ${challan.deliveryAddress!.pincode ?? ''}'),
                    ]),
                    const SizedBox(height: 24),
                    
                    _buildDetailSection('Challan Information', [
                      _buildDetailRow('Challan Number', challan.challanNumber),
                      _buildDetailRow('Date', DateFormat('dd MMM yyyy').format(challan.challanDate)),
                      _buildDetailRow('Reference', challan.referenceNumber),
                      _buildDetailRow('Purpose', challan.purpose),
                    ]),
                    const SizedBox(height: 24),
                    
                    if (challan.transportMode.isNotEmpty)
                      _buildDetailSection('Transport Details', [
                        _buildDetailRow('Mode', challan.transportMode),
                        _buildDetailRow('Vehicle Number', challan.vehicleNumber),
                        _buildDetailRow('Driver', challan.driverName),
                        _buildDetailRow('Transporter', challan.transporterName),
                      ]),
                    
                    const SizedBox(height: 24),
                    
                    _buildItemsSection(challan.items),
                    
                    if (challan.customerNotes != null && challan.customerNotes!.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildDetailSection('Notes', [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            challan.customerNotes!,
                            style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                          ),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          ],
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
            color: Color(0xFF2C3E50),
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

  Widget _buildDetailRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF2C3E50),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
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

  Widget _buildItemsSection(List<ChallanItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Items',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C3E50),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Table(
            border: TableBorder.all(color: Colors.grey[300]!, width: 1),
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.grey[200]),
                children: const [
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Item', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Unit', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              ...items.map((item) {
                return TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(item.itemDetails),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(item.quantity.toString()),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(item.unit),
                    ),
                  ],
                );
              }).toList(),
            ],
          ),
        ),
      ],
    );
  }
}