// ============================================================================
// PURCHASE ORDERS LIST PAGE - Complete Implementation
// ============================================================================
// File: lib/screens/billing/purchase_orders_list_page.dart
// Features: Filter, Search, Date Range, Bulk Import, Excel Export,
//           PDF Download, Convert to Bill, Record Receive, Lifecycle View
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'dart:typed_data';
import 'dart:convert';
import 'package:universal_html/html.dart' as html;
import '../../../../core/utils/export_helper.dart';
import '../../../../core/services/purchase_order_service.dart';
import '../app_top_bar.dart';
import 'new_purchase_order.dart';

class PurchaseOrdersListPage extends StatefulWidget {
  const PurchaseOrdersListPage({Key? key}) : super(key: key);

  @override
  State<PurchaseOrdersListPage> createState() =>
      _PurchaseOrdersListPageState();
}

class _PurchaseOrdersListPageState extends State<PurchaseOrdersListPage> {
  // Data
  List<PurchaseOrder> _purchaseOrders = [];
  PurchaseOrderStats? _stats;
  bool _isLoading = true;
  String? _errorMessage;

  // Filters
  String _selectedStatus = 'All';
  final List<String> _statusFilters = [
    'All',
    'DRAFT',
    'ISSUED',
    'PARTIALLY_RECEIVED',
    'RECEIVED',
    'PARTIALLY_BILLED',
    'BILLED',
    'CLOSED',
    'CANCELLED',
  ];

  // Date Range Filter
  DateTime? _fromDate;
  DateTime? _toDate;

  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalPurchaseOrders = 0;
  final int _itemsPerPage = 20;

  // Selection
  final Set<String> _selectedPOs = {};
  bool _selectAll = false;

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadPurchaseOrders();
    _loadStats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPurchaseOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await PurchaseOrderService.getPurchaseOrders(
        status: _selectedStatus == 'All' ? null : _selectedStatus,
        page: _currentPage,
        limit: _itemsPerPage,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        fromDate: _fromDate,
        toDate: _toDate,
      );

      setState(() {
        _purchaseOrders = response.purchaseOrders;
        _totalPages = response.pagination.pages;
        _totalPurchaseOrders = response.pagination.total;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadStats() async {
    try {
      final stats = await PurchaseOrderService.getStats();
      setState(() => _stats = stats);
    } catch (e) {
      print('Error loading stats: $e');
    }
  }

  Future<void> _refreshData() async {
    await Future.wait([_loadPurchaseOrders(), _loadStats()]);
    _showSuccessSnackbar('Data refreshed successfully');
  }

  void _filterByStatus(String status) {
    setState(() {
      _selectedStatus = status;
      _currentPage = 1;
    });
    _loadPurchaseOrders();
  }

  void _toggleSelection(String poId) {
    setState(() {
      if (_selectedPOs.contains(poId)) {
        _selectedPOs.remove(poId);
      } else {
        _selectedPOs.add(poId);
      }
      _selectAll = _selectedPOs.length == _purchaseOrders.length;
    });
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        _selectedPOs.addAll(_purchaseOrders.map((po) => po.id));
      } else {
        _selectedPOs.clear();
      }
    });
  }

  void _openNewPurchaseOrder() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => const NewPurchaseOrderScreen()),
    );
    if (result == true) _refreshData();
  }

  void _openEditPurchaseOrder(String poId) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) =>
              NewPurchaseOrderScreen(purchaseOrderId: poId)),
    );
    if (result == true) _refreshData();
  }

  Future<void> _viewPurchaseOrderDetails(PurchaseOrder po) async {
    setState(() => _isLoading = true);
    try {
      final fullPO = await PurchaseOrderService.getPurchaseOrder(po.id);
      setState(() => _isLoading = false);
      showDialog(
        context: context,
        builder: (context) =>
            PurchaseOrderDetailsDialog(purchaseOrder: fullPO),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Failed to load details: ${e.toString()}');
    }
  }

  Future<void> _deletePurchaseOrder(PurchaseOrder po) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Purchase Order'),
        content: Text(
            'Are you sure you want to delete ${po.purchaseOrderNumber}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await PurchaseOrderService.deletePurchaseOrder(po.id);
        _showSuccessSnackbar('Purchase order deleted successfully');
        _refreshData();
      } catch (e) {
        _showErrorSnackbar('Failed to delete: $e');
      }
    }
  }

  Future<void> _sendPurchaseOrder(PurchaseOrder po) async {
    try {
      await PurchaseOrderService.sendPurchaseOrder(po.id);
      _showSuccessSnackbar(
          'Purchase order sent to ${po.vendorEmail ?? po.vendorName}');
      _refreshData();
    } catch (e) {
      _showErrorSnackbar('Failed to send: $e');
    }
  }

  Future<void> _downloadPDF(PurchaseOrder po) async {
    try {
      _showSuccessSnackbar('Preparing PDF download...');
      final pdfUrl = await PurchaseOrderService.downloadPDF(po.id);
      if (kIsWeb) {
        html.AnchorElement(href: pdfUrl)
          ..setAttribute('download', '${po.purchaseOrderNumber}.pdf')
          ..setAttribute('target', '_blank')
          ..click();
        _showSuccessSnackbar('✅ PDF download started for ${po.purchaseOrderNumber}');
      } else {
        final uri = Uri.parse(pdfUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not launch PDF viewer';
        }
      }
    } catch (e) {
      _showErrorSnackbar('Failed to download PDF: $e');
    }
  }

  Future<void> _issuePurchaseOrder(PurchaseOrder po) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Issue Purchase Order'),
        content: Text(
            'Mark ${po.purchaseOrderNumber} as ISSUED and send to vendor?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF27AE60)),
              child: const Text('Issue')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await PurchaseOrderService.issuePurchaseOrder(po.id);
        _showSuccessSnackbar('Purchase order issued successfully');
        _refreshData();
      } catch (e) {
        _showErrorSnackbar('Failed to issue: $e');
      }
    }
  }

  Future<void> _recordReceive(PurchaseOrder po) async {
    final items = po.items
        .map((item) => {'item': item, 'received': item.quantity})
        .toList();

    showDialog(
      context: context,
      builder: (context) =>
          RecordReceiveDialog(purchaseOrder: po, onReceived: () {
        _refreshData();
      }),
    );
  }

  Future<void> _convertToBill(PurchaseOrder po) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Convert to Bill'),
        content: Text(
            'Convert ${po.purchaseOrderNumber} to a Bill?\n\nThis will create a bill for all received items.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF27AE60)),
              child: const Text('Convert to Bill')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await PurchaseOrderService.convertToBill(po.id);
        _showSuccessSnackbar(
            '${po.purchaseOrderNumber} converted to bill successfully');
        _refreshData();
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/admin/billing/bills');
        }
      } catch (e) {
        _showErrorSnackbar('Failed to convert to bill: $e');
      }
    }
  }

  Future<void> _cancelPurchaseOrder(PurchaseOrder po) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Purchase Order'),
        content: Text(
            'Are you sure you want to cancel ${po.purchaseOrderNumber}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Cancel PO')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await PurchaseOrderService.cancelPurchaseOrder(po.id);
        _showSuccessSnackbar('Purchase order cancelled');
        _refreshData();
      } catch (e) {
        _showErrorSnackbar('Failed to cancel: $e');
      }
    }
  }

  Future<void> _exportToExcel() async {
    try {
      if (_purchaseOrders.isEmpty) {
        _showErrorSnackbar('No purchase orders to export');
        return;
      }
      _showSuccessSnackbar('Preparing Excel export...');

      List<List<dynamic>> csvData = [
        [
          'Date',
          'PO Number',
          'Reference Number',
          'Vendor Name',
          'Vendor Email',
          'Status',
          'Expected Delivery',
          'Payment Terms',
          'Sub Total',
          'CGST',
          'SGST',
          'IGST',
          'Total Amount',
          'Receive Status',
          'Billing Status',
        ],
      ];

      for (var po in _purchaseOrders) {
        csvData.add([
          DateFormat('dd/MM/yyyy').format(po.purchaseOrderDate),
          po.purchaseOrderNumber,
          po.referenceNumber ?? '',
          po.vendorName,
          po.vendorEmail ?? '',
          po.status,
          po.expectedDeliveryDate != null
              ? DateFormat('dd/MM/yyyy').format(po.expectedDeliveryDate!)
              : '',
          po.paymentTerms,
          po.subTotal.toStringAsFixed(2),
          po.cgst.toStringAsFixed(2),
          po.sgst.toStringAsFixed(2),
          po.igst.toStringAsFixed(2),
          po.totalAmount.toStringAsFixed(2),
          po.receiveStatus ?? '',
          po.billingStatus ?? '',
        ]);
      }

      await ExportHelper.exportToExcel(
        data: csvData,
        filename: 'purchase_orders',
      );

      _showSuccessSnackbar(
          '✅ Excel downloaded with ${_purchaseOrders.length} purchase orders!');
    } catch (e) {
      _showErrorSnackbar('Failed to export: $e');
    }
  }

  void _handleBulkImport() {
    showDialog(
      context: context,
      builder: (context) => BulkImportPurchaseOrdersDialog(
          onImportComplete: () => _refreshData()),
    );
  }

  Future<void> _selectFromDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _fromDate = picked);
      _loadPurchaseOrders();
    }
  }

  Future<void> _selectToDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _toDate = picked);
      _loadPurchaseOrders();
    }
  }

  void _clearDateFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    _loadPurchaseOrders();
  }

  // ============================================================================
  // PURCHASE ORDER LIFECYCLE DIALOG (shows assets/purchase_order.png)
  // ============================================================================

  void _showPurchaseOrderLifecycleDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.85,
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          color: Color(0xFF3498DB),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Purchase Order Lifecycle Process',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // Image with InteractiveViewer (pinch to zoom)
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          child: InteractiveViewer(
                            panEnabled: true,
                            minScale: 0.5,
                            maxScale: 4.0,
                            child: Center(
                              child: Image.asset(
                                'assets/purchase_order.png',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.account_tree_outlined,
                                          size: 80,
                                          color: Colors.grey[400]),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Purchase Order Flow',
                                        style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey[700]),
                                      ),
                                      const SizedBox(height: 24),
                                      _buildLifecycleStep(
                                          '1', 'Business Need',
                                          Colors.blue, Icons.lightbulb),
                                      _buildLifecycleArrow(),
                                      _buildLifecycleStep(
                                          '2',
                                          'Create Purchase Order (Draft)',
                                          Colors.orange,
                                          Icons.edit_document),
                                      _buildLifecycleArrow(),
                                      _buildLifecycleStep(
                                          '3',
                                          'Approval (if applicable)',
                                          Colors.purple,
                                          Icons.approval),
                                      _buildLifecycleArrow(),
                                      _buildLifecycleStep(
                                          '4',
                                          'Issue & Send to Vendor (via Email)',
                                          Colors.teal,
                                          Icons.send),
                                      _buildLifecycleArrow(),
                                      _buildLifecycleStep(
                                          '5',
                                          'Vendor Delivers Goods/Services',
                                          Colors.indigo,
                                          Icons.local_shipping),
                                      _buildLifecycleArrow(),
                                      _buildLifecycleStep(
                                          '6', 'Record Purchase Receive',
                                          Colors.cyan,
                                          Icons.inventory_2),
                                      _buildLifecycleArrow(),
                                      _buildLifecycleStep(
                                          '7', 'Convert PO → Bill',
                                          Colors.green,
                                          Icons.receipt_long),
                                      _buildLifecycleArrow(),
                                      _buildLifecycleStep(
                                          '8', 'Record Payment',
                                          Colors.amber,
                                          Icons.payment),
                                      _buildLifecycleArrow(),
                                      _buildLifecycleStep(
                                          '✅', 'PO Closed',
                                          Colors.green,
                                          Icons.check_circle),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Footer
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Tip: Pinch to zoom, drag to pan',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Close button
            Positioned(
              top: 40,
              right: 40,
              child: IconButton(
                icon: const Icon(Icons.close,
                    color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.6),
                  padding: const EdgeInsets.all(14),
                ),
                tooltip: 'Close',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLifecycleStep(
      String step, String label, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color,
            child: Text(step,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildLifecycleArrow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Icon(Icons.arrow_downward, color: Colors.grey[400], size: 20),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ============================================================================
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    
    return Scaffold(
      appBar: AppTopBar(title: 'Purchase Orders'),
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          _buildTopBar(isMobile),
          if (_stats != null) _buildStatsCards(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? _buildErrorState()
                    : _purchaseOrders.isEmpty
                        ? _buildEmptyState()
                        : _buildPOTable(),
          ),
          if (!_isLoading && _purchaseOrders.isNotEmpty) _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isMobile) {
    if (isMobile) {
      return _buildMobileTopBar();
    } else {
      return _buildDesktopTopBar();
    }
  }
  
  Widget _buildMobileTopBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          // Row 1: Status Filter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              value: _selectedStatus,
              isExpanded: true,
              underline: const SizedBox(),
              icon: const Icon(Icons.arrow_drop_down),
              items: _statusFilters.map((status) {
                return DropdownMenuItem(
                  value: status,
                  child: Text(
                    status == 'All' ? 'All Purchase Orders' : status.replaceAll('_', ' '),
                    style: const TextStyle(fontSize: 14),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) _filterByStatus(value);
              },
            ),
          ),
          const SizedBox(height: 12),
          
          // Row 2: Search
          SizedBox(
            width: double.infinity,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search purchase orders...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value.toLowerCase());
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (_searchQuery == value.toLowerCase()) {
                    _loadPurchaseOrders();
                  }
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          
          // Row 3: Date Filters
          Row(
            children: [
              Expanded(child: _buildDateFilterButton(_fromDate, 'From Date', _selectFromDate)),
              const SizedBox(width: 8),
              Expanded(child: _buildDateFilterButton(_toDate, 'To Date', _selectToDate)),
            ],
          ),
          if (_fromDate != null || _toDate != null) ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.clear, color: Colors.red, size: 18),
              onPressed: _clearDateFilters,
              label: const Text('Clear Dates'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[50],
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 12),
                minimumSize: const Size(double.infinity, 0),
              ),
            ),
          ],
          const SizedBox(height: 12),
          
          // Row 4: Action Buttons
          Row(
            children: [
              Expanded(
                child: IconButton(
                  icon: const Icon(Icons.refresh, size: 24),
                  onPressed: _isLoading ? null : _refreshData,
                  tooltip: 'Refresh',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey[200],
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: IconButton(
                  icon: const Icon(Icons.account_tree, size: 24, color: Color(0xFF3498DB)),
                  onPressed: _showPurchaseOrderLifecycleDialog,
                  tooltip: 'View Process',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF3498DB).withOpacity(0.1),
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _openNewPurchaseOrder,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('New Purchase Order'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              minimumSize: const Size(double.infinity, 0),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _handleBulkImport,
                  icon: const Icon(Icons.upload_file, size: 20),
                  label: const Text('Import'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9B59B6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _exportToExcel,
                  icon: const Icon(Icons.file_download, size: 20),
                  label: const Text('Export'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF27AE60),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildDesktopTopBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        children: [
          const SizedBox(width: 8),

          // Status filter dropdown
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    status == 'All'
                        ? 'All Purchase Orders'
                        : status.replaceAll('_', ' '),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
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
            width: 280,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search purchase orders...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value.toLowerCase());
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (_searchQuery == value.toLowerCase()) {
                    _loadPurchaseOrders();
                  }
                });
              },
            ),
          ),

          const SizedBox(width: 12),

          // From date
          _buildDateFilterButton(
              _fromDate, 'From Date', _selectFromDate),

          const SizedBox(width: 12),

          // To date
          _buildDateFilterButton(_toDate, 'To Date', _selectToDate),

          if (_fromDate != null || _toDate != null) ...[
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.red),
              onPressed: _clearDateFilters,
              tooltip: 'Clear Date Filters',
              style: IconButton.styleFrom(
                  backgroundColor: Colors.red[50],
                  padding: const EdgeInsets.all(12)),
            ),
          ],

          const SizedBox(width: 12),

          IconButton(
            icon: const Icon(Icons.refresh, size: 24),
            onPressed: _isLoading ? null : _refreshData,
            tooltip: 'Refresh',
            style: IconButton.styleFrom(
                backgroundColor: Colors.grey[200],
                padding: const EdgeInsets.all(12)),
          ),

          const SizedBox(width: 12),

          // View Process button
          IconButton(
            icon: const Icon(Icons.account_tree,
                size: 24, color: Color(0xFF3498DB)),
            onPressed: _showPurchaseOrderLifecycleDialog,
            tooltip: 'View Purchase Order Process',
            style: IconButton.styleFrom(
              backgroundColor:
                  const Color(0xFF3498DB).withOpacity(0.1),
              padding: const EdgeInsets.all(12),
            ),
          ),

          const SizedBox(width: 16),

          ElevatedButton.icon(
            onPressed: _openNewPurchaseOrder,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('New Purchase Order'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
            ),
          ),

          const SizedBox(width: 12),

          ElevatedButton.icon(
            onPressed: _isLoading ? null : _handleBulkImport,
            icon: const Icon(Icons.upload_file, size: 20),
            label: const Text('Bulk Import'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9B59B6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
            ),
          ),

          const SizedBox(width: 12),

          ElevatedButton.icon(
            onPressed: _isLoading ? null : _exportToExcel,
            icon: const Icon(Icons.file_download, size: 20),
            label: const Text('Export Excel'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27AE60),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilterButton(
      DateTime? date, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: date != null
              ? const Color(0xFF3498DB).withOpacity(0.1)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color:
                  date != null ? const Color(0xFF3498DB) : Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today,
                size: 18,
                color: date != null
                    ? const Color(0xFF3498DB)
                    : Colors.grey[600]),
            const SizedBox(width: 8),
            Text(
              date != null
                  ? '$label: ${DateFormat('dd/MM/yyyy').format(date)}'
                  : label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: date != null ? FontWeight.w600 : FontWeight.normal,
                color: date != null
                    ? const Color(0xFF3498DB)
                    : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCards() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        children: [
          _buildStatCard('Total POs',
              _stats!.totalPurchaseOrders.toString(),
              Icons.shopping_basket, Colors.blue),
          const SizedBox(width: 16),
          _buildStatCard('Issued',
              _stats!.issuedPurchaseOrders.toString(),
              Icons.send, Colors.teal),
          const SizedBox(width: 16),
          _buildStatCard('Received',
              _stats!.receivedPurchaseOrders.toString(),
              Icons.inventory_2, Colors.green),
          const SizedBox(width: 16),
          _buildStatCard('Total Value',
              '₹${_stats!.totalValue.toStringAsFixed(2)}',
              Icons.attach_money, Colors.orange),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey[700])),
                const SizedBox(height: 4),
                Text(value,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPOTable() {
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF34495E),
              borderRadius:
                  BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Checkbox(
                    value: _selectAll,
                    onChanged: _toggleSelectAll,
                    fillColor:
                        MaterialStateProperty.all(Colors.white),
                    checkColor: const Color(0xFF34495E),
                  ),
                ),
                _headerCell('DATE', flex: 2),
                _headerCell('PO NUMBER', flex: 2),
                _headerCell('REFERENCE#', flex: 2),
                _headerCell('VENDOR', flex: 3),
                _headerCell('STATUS', flex: 2),
                _headerCell('DELIVERY DATE', flex: 2),
                _headerCell('AMOUNT', flex: 2),
                const SizedBox(width: 60),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _purchaseOrders.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.grey[200]),
              itemBuilder: (context, index) =>
                  _buildPORow(_purchaseOrders[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(text,
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12)),
    );
  }

  Widget _buildPORow(PurchaseOrder po) {
    final isSelected = _selectedPOs.contains(po.id);
    return InkWell(
      onTap: () => _openEditPurchaseOrder(po.id),
      child: Container(
        padding: const EdgeInsets.all(16),
        color: isSelected ? Colors.blue[50] : null,
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleSelection(po.id)),
            ),
            Expanded(
              flex: 2,
              child: Text(
                  DateFormat('dd/MM/yyyy').format(po.purchaseOrderDate),
                  style: const TextStyle(fontSize: 14)),
            ),
            Expanded(
              flex: 2,
              child: InkWell(
                onTap: () => _openEditPurchaseOrder(po.id),
                child: Text(
                  po.purchaseOrderNumber,
                  style: const TextStyle(
                      color: Color(0xFF3498DB),
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(po.referenceNumber ?? '-',
                  style:
                      TextStyle(fontSize: 14, color: Colors.grey[600])),
            ),
            Expanded(
                flex: 3,
                child: Text(po.vendorName,
                    style: const TextStyle(fontSize: 14))),
            Expanded(flex: 2, child: _buildStatusBadge(po.status)),
            Expanded(
              flex: 2,
              child: Text(
                po.expectedDeliveryDate != null
                    ? DateFormat('dd/MM/yyyy')
                        .format(po.expectedDeliveryDate!)
                    : '-',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '₹${po.totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: 60,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'view',
                    child: ListTile(
                      leading: Icon(Icons.visibility,
                          size: 18, color: Color(0xFF3498DB)),
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
                  if (po.status == 'DRAFT') ...[
                    const PopupMenuItem(
                      value: 'issue',
                      child: ListTile(
                        leading: Icon(Icons.send,
                            size: 18, color: Color(0xFF27AE60)),
                        title: Text('Issue & Send',
                            style:
                                TextStyle(color: Color(0xFF27AE60))),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                  if (po.status == 'DRAFT' ||
                      po.status == 'ISSUED') ...[
                    const PopupMenuItem(
                      value: 'send',
                      child: ListTile(
                        leading: Icon(Icons.email_outlined, size: 18),
                        title: Text('Send Email'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                  const PopupMenuItem(
                    value: 'download',
                    child: ListTile(
                      leading: Icon(Icons.download, size: 18),
                      title: Text('Download PDF'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (po.status == 'ISSUED' ||
                      po.status == 'PARTIALLY_RECEIVED') ...[
                    const PopupMenuItem(
                      value: 'receive',
                      child: ListTile(
                        leading: Icon(Icons.inventory_2,
                            size: 18, color: Colors.teal),
                        title: Text('Record Receive',
                            style: TextStyle(color: Colors.teal)),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                  if (po.status == 'RECEIVED' ||
                      po.status == 'PARTIALLY_RECEIVED' ||
                      po.status == 'PARTIALLY_BILLED') ...[
                    const PopupMenuItem(
                      value: 'convert_bill',
                      child: ListTile(
                        leading: Icon(Icons.receipt_long,
                            size: 18, color: Color(0xFF27AE60)),
                        title: Text('Convert to Bill',
                            style:
                                TextStyle(color: Color(0xFF27AE60))),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                  if (po.status != 'CANCELLED' &&
                      po.status != 'CLOSED' &&
                      po.status != 'BILLED') ...[
                    const PopupMenuItem(
                      value: 'cancel',
                      child: ListTile(
                        leading: Icon(Icons.cancel_outlined,
                            size: 18, color: Colors.orange),
                        title: Text('Cancel PO',
                            style: TextStyle(color: Colors.orange)),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                  if (po.status == 'DRAFT') ...[
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete,
                            size: 18, color: Colors.red),
                        title: Text('Delete',
                            style: TextStyle(color: Colors.red)),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ],
                onSelected: (value) async {
                  switch (value) {
                    case 'view':
                      _viewPurchaseOrderDetails(po);
                      break;
                    case 'edit':
                      _openEditPurchaseOrder(po.id);
                      break;
                    case 'issue':
                      _issuePurchaseOrder(po);
                      break;
                    case 'send':
                      _sendPurchaseOrder(po);
                      break;
                    case 'download':
                      await _downloadPDF(po);
                      break;
                    case 'receive':
                      _recordReceive(po);
                      break;
                    case 'convert_bill':
                      _convertToBill(po);
                      break;
                    case 'cancel':
                      _cancelPurchaseOrder(po);
                      break;
                    case 'delete':
                      _deletePurchaseOrder(po);
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
    Color bg;
    Color fg;
    switch (status) {
      case 'DRAFT':
        bg = Colors.grey[200]!;
        fg = Colors.grey[800]!;
        break;
      case 'ISSUED':
        bg = Colors.blue[100]!;
        fg = Colors.blue[800]!;
        break;
      case 'PARTIALLY_RECEIVED':
        bg = Colors.cyan[100]!;
        fg = Colors.cyan[800]!;
        break;
      case 'RECEIVED':
        bg = Colors.teal[100]!;
        fg = Colors.teal[800]!;
        break;
      case 'PARTIALLY_BILLED':
        bg = Colors.orange[100]!;
        fg = Colors.orange[800]!;
        break;
      case 'BILLED':
        bg = Colors.green[100]!;
        fg = Colors.green[800]!;
        break;
      case 'CLOSED':
        bg = Colors.blueGrey[100]!;
        fg = Colors.blueGrey[800]!;
        break;
      case 'CANCELLED':
        bg = Colors.red[100]!;
        fg = Colors.red[800]!;
        break;
      default:
        bg = Colors.grey[200]!;
        fg = Colors.grey[800]!;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(status.replaceAll('_', ' '),
          style: TextStyle(
              color: fg, fontWeight: FontWeight.w600, fontSize: 11)),
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
            'Showing ${(_currentPage - 1) * _itemsPerPage + 1} - ${(_currentPage * _itemsPerPage).clamp(0, _totalPurchaseOrders)} of $_totalPurchaseOrders',
            style: TextStyle(color: Colors.grey[700]),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 1
                    ? () {
                        setState(() => _currentPage--);
                        _loadPurchaseOrders();
                      }
                    : null,
              ),
              ...List.generate(_totalPages.clamp(0, 5), (index) {
                final pageNum = index + 1;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () {
                      setState(() => _currentPage = pageNum);
                      _loadPurchaseOrders();
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
              }),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < _totalPages
                    ? () {
                        setState(() => _currentPage++);
                        _loadPurchaseOrders();
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_basket_outlined,
              size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('No purchase orders found',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700])),
          const SizedBox(height: 8),
          Text('Create your first purchase order to get started',
              style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _openNewPurchaseOrder,
            icon: const Icon(Icons.add),
            label: const Text('Create Purchase Order'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text('Error Loading Purchase Orders',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700])),
          const SizedBox(height: 8),
          Text(_errorMessage ?? 'Unknown error',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _refreshData,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3498DB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 16)),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// RECORD RECEIVE DIALOG
// ============================================================================

class RecordReceiveDialog extends StatefulWidget {
  final PurchaseOrder purchaseOrder;
  final VoidCallback onReceived;

  const RecordReceiveDialog(
      {Key? key, required this.purchaseOrder, required this.onReceived})
      : super(key: key);

  @override
  State<RecordReceiveDialog> createState() => _RecordReceiveDialogState();
}

class _RecordReceiveDialogState extends State<RecordReceiveDialog> {
  DateTime _receiveDate = DateTime.now();
  final List<Map<String, dynamic>> _receiveItems = [];
  final TextEditingController _notesController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _receiveItems.addAll(widget.purchaseOrder.items.map((item) => {
          'itemDetails': item.itemDetails,
          'quantityOrdered': item.quantity,
          'quantityReceived': item.quantity,
          'controller':
              TextEditingController(text: item.quantity.toString()),
        }));
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (var item in _receiveItems) {
      (item['controller'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  Future<void> _saveReceive() async {
    setState(() => _isSaving = true);
    try {
      final receiveData = {
        'receiveDate': _receiveDate.toIso8601String(),
        'items': _receiveItems
            .map((item) => {
                  'itemDetails': item['itemDetails'],
                  'quantityOrdered': item['quantityOrdered'],
                  'quantityReceived': item['quantityReceived'],
                })
            .toList(),
        'notes': _notesController.text.trim(),
      };

      await PurchaseOrderService.recordReceive(
          widget.purchaseOrder.id, receiveData);

      Navigator.pop(context);
      widget.onReceived();

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Purchase receive recorded successfully'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to record receive: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2,
                    color: Color(0xFF3498DB), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Record Purchase Receive',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
            Text('PO: ${widget.purchaseOrder.purchaseOrderNumber}',
                style: TextStyle(
                    color: Colors.grey[600], fontSize: 14)),
            const Divider(height: 32),

            // Receive Date
            InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _receiveDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) setState(() => _receiveDate = date);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Receive Date *',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.calendar_today),
                ),
                child: Text(
                    DateFormat('dd MMM yyyy').format(_receiveDate)),
              ),
            ),
            const SizedBox(height: 16),

            // Items table
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34495E),
                      borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8)),
                    ),
                    child: Row(
                      children: const [
                        Expanded(
                            flex: 3,
                            child: Text('ITEM',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12))),
                        SizedBox(
                            width: 100,
                            child: Text('ORDERED',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12))),
                        SizedBox(
                            width: 120,
                            child: Text('RECEIVED',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12))),
                      ],
                    ),
                  ),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _receiveItems.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: Colors.grey[200]),
                    itemBuilder: (context, index) {
                      final item = _receiveItems[index];
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                                flex: 3,
                                child: Text(item['itemDetails'],
                                    style: const TextStyle(fontSize: 14))),
                            SizedBox(
                              width: 100,
                              child: Text(
                                  item['quantityOrdered'].toString(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 14)),
                            ),
                            SizedBox(
                              width: 120,
                              child: TextFormField(
                                controller: item['controller'],
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(8)),
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                ),
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                onChanged: (value) {
                                  setState(() {
                                    item['quantityReceived'] =
                                        double.tryParse(value) ?? 0;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: 'Notes (Optional)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              maxLines: 2,
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveReceive,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save),
                label:
                    Text(_isSaving ? 'Saving...' : 'Record Receive'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3498DB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// PURCHASE ORDER DETAILS DIALOG
// ============================================================================

class PurchaseOrderDetailsDialog extends StatelessWidget {
  final PurchaseOrder purchaseOrder;

  const PurchaseOrderDetailsDialog({Key? key, required this.purchaseOrder})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shopping_basket,
                    color: Color(0xFF3498DB), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(purchaseOrder.purchaseOrderNumber,
                          style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2C3E50))),
                      Text('Purchase Order Details',
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey[600])),
                    ],
                  ),
                ),
                _statusBadge(purchaseOrder.status),
                const SizedBox(width: 12),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(height: 32),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section('Vendor Information', [
                      _row('Vendor Name', purchaseOrder.vendorName),
                      _row('Email', purchaseOrder.vendorEmail),
                      _row('Phone', purchaseOrder.vendorPhone),
                    ]),
                    const SizedBox(height: 24),
                    _section('Purchase Order Information', [
                      _row('PO Number',
                          purchaseOrder.purchaseOrderNumber),
                      _row('Reference Number',
                          purchaseOrder.referenceNumber),
                      _row('PO Date',
                          DateFormat('dd MMM yyyy').format(
                              purchaseOrder.purchaseOrderDate)),
                      _row('Expected Delivery',
                          purchaseOrder.expectedDeliveryDate != null
                              ? DateFormat('dd MMM yyyy').format(
                                  purchaseOrder.expectedDeliveryDate!)
                              : 'Not Set'),
                      _row('Payment Terms',
                          purchaseOrder.paymentTerms),
                      _row('Shipment Preference',
                          purchaseOrder.shipmentPreference),
                      _row('Delivery Address',
                          purchaseOrder.deliveryAddress),
                      _row('Salesperson', purchaseOrder.salesperson),
                      _row('Subject', purchaseOrder.subject),
                    ]),
                    const SizedBox(height: 24),
                    if (purchaseOrder.items.isNotEmpty)
                      _lineItems(purchaseOrder.items),
                    const SizedBox(height: 24),
                    _section('Amount Details', [
                      _row('Subtotal',
                          '₹${purchaseOrder.subTotal.toStringAsFixed(2)}'),
                      if (purchaseOrder.tdsAmount > 0)
                        _row('TDS',
                            '₹${purchaseOrder.tdsAmount.toStringAsFixed(2)}'),
                      if (purchaseOrder.tcsAmount > 0)
                        _row('TCS',
                            '₹${purchaseOrder.tcsAmount.toStringAsFixed(2)}'),
                      _row('CGST',
                          '₹${purchaseOrder.cgst.toStringAsFixed(2)}'),
                      _row('SGST',
                          '₹${purchaseOrder.sgst.toStringAsFixed(2)}'),
                      _row('IGST',
                          '₹${purchaseOrder.igst.toStringAsFixed(2)}'),
                      _row('Total Amount',
                          '₹${purchaseOrder.totalAmount.toStringAsFixed(2)}',
                          isBold: true),
                    ]),
                    if (purchaseOrder.vendorNotes != null &&
                        purchaseOrder.vendorNotes!.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _section('Vendor Notes', [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(purchaseOrder.vendorNotes!,
                              style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[800])),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color bg;
    Color fg;
    switch (status) {
      case 'ISSUED':
        bg = Colors.blue[100]!;
        fg = Colors.blue[800]!;
        break;
      case 'RECEIVED':
        bg = Colors.teal[100]!;
        fg = Colors.teal[800]!;
        break;
      case 'BILLED':
        bg = Colors.green[100]!;
        fg = Colors.green[800]!;
        break;
      default:
        bg = Colors.grey[200]!;
        fg = Colors.grey[800]!;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(status.replaceAll('_', ' '),
          style: TextStyle(
              color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C3E50))),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!)),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _row(String label, dynamic value, {bool isBold = false}) {
    if (value == null || value.toString().isEmpty)
      return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(label,
                style: TextStyle(
                    fontWeight: isBold
                        ? FontWeight.bold
                        : FontWeight.w600,
                    color: const Color(0xFF2C3E50),
                    fontSize: 14)),
          ),
          Expanded(
            child: Text(value.toString(),
                style: TextStyle(
                    color: Colors.grey[800],
                    fontSize: 14,
                    fontWeight: isBold
                        ? FontWeight.bold
                        : FontWeight.normal)),
          ),
        ],
      ),
    );
  }

  Widget _lineItems(List<PurchaseOrderItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Line Items',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C3E50))),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!)),
          child: Table(
            border:
                TableBorder.all(color: Colors.grey[300]!, width: 1),
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.grey[200]),
                children: const [
                  Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Item',
                          style: TextStyle(
                              fontWeight: FontWeight.bold))),
                  Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Qty',
                          style: TextStyle(
                              fontWeight: FontWeight.bold))),
                  Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Rate',
                          style: TextStyle(
                              fontWeight: FontWeight.bold))),
                  Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Amount',
                          style: TextStyle(
                              fontWeight: FontWeight.bold))),
                ],
              ),
              ...items.map<TableRow>((item) => TableRow(children: [
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(item.itemDetails)),
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(item.quantity.toString())),
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                            '₹${item.rate.toStringAsFixed(2)}')),
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                            '₹${item.amount.toStringAsFixed(2)}')),
                  ])),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// BULK IMPORT DIALOG
// ============================================================================

class BulkImportPurchaseOrdersDialog extends StatefulWidget {
  final VoidCallback onImportComplete;

  const BulkImportPurchaseOrdersDialog(
      {Key? key, required this.onImportComplete})
      : super(key: key);

  @override
  State<BulkImportPurchaseOrdersDialog> createState() =>
      _BulkImportPurchaseOrdersDialogState();
}

class _BulkImportPurchaseOrdersDialogState
    extends State<BulkImportPurchaseOrdersDialog> {
  bool isDownloading = false;
  bool isUploading = false;
  String? uploadedFileName;
  List<Map<String, dynamic>>? importResults;

  String _parsePhone(dynamic value) {
    if (value == null) return '';
    String s = value.toString().trim();
    if (s.toUpperCase().contains('E')) {
      try {
        return double.parse(s).round().toString();
      } catch (_) {
        return s;
      }
    }
    if (s.contains('.')) {
      try {
        return double.parse(s).round().toString();
      } catch (_) {
        return s;
      }
    }
    return s;
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    try {
      return double.parse(value.toString().trim());
    } catch (_) {
      return 0.0;
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    for (final fmt in [
      'dd/MM/yyyy',
      'dd-MM-yyyy',
      'yyyy-MM-dd',
      'MM/dd/yyyy'
    ]) {
      try {
        return DateFormat(fmt).parse(s);
      } catch (_) {}
    }
    return null;
  }

  dynamic _val(List<dynamic> row, int i) =>
      i < row.length ? row[i] : null;

  String _str(List<dynamic> row, int i, [String def = '']) {
    if (i >= row.length) return def;
    final v = row[i];
    return v == null ? def : v.toString().trim();
  }

  bool _isEmail(String e) =>
      RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(e);

  Future<void> _downloadTemplate() async {
    setState(() => isDownloading = true);
    try {
      final data = [
        [
          'PO Date* (dd/MM/yyyy)',
          'PO Number',
          'Reference Number',
          'Vendor Name*',
          'Vendor Email*',
          'Vendor Phone*',
          'Expected Delivery (dd/MM/yyyy)',
          'Payment Terms*',
          'Shipment Preference',
          'Status*',
          'Salesperson',
          'Subject',
          'Delivery Address',
          'Sub Total*',
          'CGST',
          'SGST',
          'IGST',
          'TDS Amount',
          'TCS Amount',
          'Total Amount*',
          'Vendor Notes',
          'Terms and Conditions',
        ],
        [
          '01/01/2024',
          'PO-2024-001',
          'REF-001',
          'ABC Suppliers',
          'purchase@abcsuppliers.com',
          '9876543210',
          '15/01/2024',
          'Net 30',
          'Standard',
          'DRAFT',
          'John Manager',
          'Office Supplies Order',
          '123, Industrial Area, Bengaluru',
          '100000.00',
          '9000.00',
          '9000.00',
          '0.00',
          '0.00',
          '0.00',
          '118000.00',
          'Please deliver before the date mentioned.',
          'Payment within 30 days of invoice.',
        ],
        [
          'INSTRUCTIONS:',
          '1. Fields marked * are required',
          '2. Date format: dd/MM/yyyy',
          '3. Status: DRAFT, ISSUED',
          '4. Payment Terms: Due on Receipt, Net 15, Net 30, Net 45, Net 60',
          '5. Phone: 10 digits',
          '6. Delete this row before uploading',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
        ],
      ];

      await ExportHelper.exportToExcel(
          data: data, filename: 'purchase_orders_import_template');

      setState(() => isDownloading = false);
      _success('Template downloaded successfully!');
    } catch (e) {
      setState(() => isDownloading = false);
      _error('Failed to download template: $e');
    }
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;

      setState(() {
        uploadedFileName = file.name;
        isUploading = true;
        importResults = null;
      });

      final bytes = file.bytes;
      if (bytes == null) throw Exception('Failed to read file');

      List<List<dynamic>> rows;
      final ext = file.extension?.toLowerCase() ?? '';

      if (ext == 'csv') {
        rows = _parseCSV(bytes);
      } else {
        rows = _parseExcel(bytes);
      }

      if (rows.length < 2) {
        throw Exception('File must contain header row and data');
      }

      final List<Map<String, dynamic>> toImport = [];
      final List<String> errors = [];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty ||
            row[0] == null ||
            row[0].toString().trim().isEmpty ||
            row[0].toString().toUpperCase().contains('INSTRUCTION')) {
          continue;
        }

        try {
          final poDate = _parseDate(_val(row, 0));
          final poNumber = _str(row, 1);
          final refNumber = _str(row, 2);
          final vendorName = _str(row, 3);
          final vendorEmail = _str(row, 4);
          final vendorPhone = _parsePhone(_val(row, 5));
          final deliveryDate = _parseDate(_val(row, 6));
          final paymentTerms = _str(row, 7, 'Net 30');
          final shipment = _str(row, 8);
          final status = _str(row, 9, 'DRAFT');
          final salesperson = _str(row, 10);
          final subject = _str(row, 11);
          final deliveryAddress = _str(row, 12);
          final subTotal = _parseDouble(_val(row, 13));
          final cgst = _parseDouble(_val(row, 14));
          final sgst = _parseDouble(_val(row, 15));
          final igst = _parseDouble(_val(row, 16));
          final tdsAmount = _parseDouble(_val(row, 17));
          final tcsAmount = _parseDouble(_val(row, 18));
          final totalAmount = _parseDouble(_val(row, 19));
          final vendorNotes = _str(row, 20);
          final terms = _str(row, 21);

          final rowErrors = <String>[];
          if (poDate == null) rowErrors.add('PO Date required');
          if (vendorName.isEmpty) rowErrors.add('Vendor Name required');
          if (vendorEmail.isEmpty) rowErrors.add('Vendor Email required');
          else if (!_isEmail(vendorEmail)) rowErrors.add('Invalid email');
          if (vendorPhone.isEmpty) rowErrors.add('Phone required');
          else if (vendorPhone.length != 10) rowErrors.add('Phone must be 10 digits');
          if (subTotal <= 0) rowErrors.add('Sub Total > 0');
          if (totalAmount <= 0) rowErrors.add('Total Amount > 0');

          if (rowErrors.isNotEmpty) {
            errors.add('Row ${i + 1}: ${rowErrors.join(", ")}');
            continue;
          }

          toImport.add({
            'purchaseOrderDate': poDate!.toIso8601String(),
            'purchaseOrderNumber': poNumber,
            'referenceNumber': refNumber,
            'vendorName': vendorName,
            'vendorEmail': vendorEmail,
            'vendorPhone': vendorPhone,
            'expectedDeliveryDate': deliveryDate?.toIso8601String(),
            'paymentTerms': paymentTerms,
            'shipmentPreference': shipment,
            'status': status.toUpperCase(),
            'salesperson': salesperson,
            'subject': subject,
            'deliveryAddress': deliveryAddress,
            'subTotal': subTotal,
            'cgst': cgst,
            'sgst': sgst,
            'igst': igst,
            'tdsAmount': tdsAmount,
            'tcsAmount': tcsAmount,
            'totalAmount': totalAmount,
            'vendorNotes': vendorNotes,
            'termsAndConditions': terms,
          });
        } catch (e) {
          errors.add('Row ${i + 1}: ${e.toString()}');
        }
      }

      if (toImport.isEmpty) {
        throw Exception('No valid purchase order data found');
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Import'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Found ${toImport.length} purchase order(s) to import.',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 16)),
                if (errors.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('${errors.length} row(s) skipped:',
                      style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[200]!)),
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      child: Text(errors.join('\n'),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.red)),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text('Proceed with import?'),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3498DB)),
                child: const Text('Import')),
          ],
        ),
      );

      if (confirmed != true) {
        setState(() {
          isUploading = false;
          uploadedFileName = null;
        });
        return;
      }

      final importResult =
          await PurchaseOrderService.bulkImportPurchaseOrders(toImport);

      setState(() {
        isUploading = false;
        importResults = [
          {
            'success': importResult['data']['successCount'],
            'failed': importResult['data']['failedCount'],
            'total': importResult['data']['totalProcessed'],
            'errors': importResult['data']['errors'] ?? [],
          }
        ];
      });

      if (importResult['success'] == true) {
        _success('Import completed successfully!');
        widget.onImportComplete();
      }
    } catch (e) {
      setState(() {
        isUploading = false;
        uploadedFileName = null;
      });
      _error('Failed to import: $e');
    }
  }

  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    final excel = excel_pkg.Excel.decodeBytes(bytes);
    final sheet = excel.tables.keys.first;
    final rows = excel.tables[sheet]?.rows ?? [];
    return rows.map((row) {
      return row.map((cell) {
        if (cell?.value == null) return '';
        if (cell!.value is excel_pkg.TextCellValue) {
          return (cell.value as excel_pkg.TextCellValue).value;
        }
        return cell.value;
      }).toList();
    }).toList();
  }

  List<List<dynamic>> _parseCSV(Uint8List bytes) {
    final csv = utf8.decode(bytes, allowMalformed: true);
    return csv
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .map(_parseCSVLine)
        .toList();
  }

  List<String> _parseCSVLine(String line) {
    final fields = <String>[];
    final buf = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (c == ',' && !inQuotes) {
        fields.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    fields.add(buf.toString().trim());
    return fields
        .map((f) =>
            f.startsWith('"') && f.endsWith('"')
                ? f.substring(1, f.length - 1)
                : f)
        .toList();
  }

  void _error(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4)));
  }

  void _success(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.upload_file,
                    color: Color(0xFF9B59B6), size: 28),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text('Bulk Import Purchase Orders',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold))),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(height: 32),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.blue[700], size: 20),
                      const SizedBox(width: 8),
                      Text('How to Import Purchase Orders',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.blue[700])),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Download the sample template\n'
                    '2. Fill in your purchase order data\n'
                    '3. Dates in dd/MM/yyyy format\n'
                    '4. Upload completed file (.xlsx, .xls, .csv)\n'
                    '5. Review and confirm import',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isDownloading || isUploading
                    ? null
                    : _downloadTemplate,
                icon: isDownloading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white)))
                    : const Icon(Icons.download),
                label: Text(isDownloading
                    ? 'Downloading...'
                    : 'Download Sample Template'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3498DB),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    isDownloading || isUploading ? null : _uploadFile,
                icon: isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF9B59B6))))
                    : const Icon(Icons.upload_file),
                label: Text(
                    isUploading ? 'Processing...' : 'Upload Excel or CSV File'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF9B59B6),
                    side: const BorderSide(color: Color(0xFF9B59B6)),
                    padding:
                        const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),

            if (uploadedFileName != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green[200]!)),
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: Colors.green[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(uploadedFileName!,
                          style: TextStyle(
                              color: Colors.green[700],
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],

            if (importResults != null) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              const Text('Import Results',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C3E50))),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!)),
                child: Column(
                  children: [
                    _resultRow('Total Processed',
                        importResults![0]['total'].toString(), Colors.blue),
                    const SizedBox(height: 8),
                    _resultRow('Successfully Imported',
                        importResults![0]['success'].toString(),
                        Colors.green),
                    const SizedBox(height: 8),
                    _resultRow('Failed',
                        importResults![0]['failed'].toString(),
                        Colors.red),
                    if ((importResults![0]['errors'] as List).isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('Errors:',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.red)),
                      const SizedBox(height: 8),
                      Container(
                        constraints:
                            const BoxConstraints(maxHeight: 150),
                        child: SingleChildScrollView(
                          child: Text(
                            (importResults![0]['errors'] as List)
                                .join('\n'),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3498DB),
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('Close'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12)),
          child: Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}