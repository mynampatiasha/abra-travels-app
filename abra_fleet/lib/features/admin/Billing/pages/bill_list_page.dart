// ============================================================================
// BILL LIST PAGE - Complete Implementation
// ============================================================================
// File: lib/screens/billing/bill_list_page.dart
// Features: Filter, Search, Bulk Import, Excel Export, PDF Download,
//           Record Payment, View Lifecycle, Vendor Management
// Matches: Zoho Books Bill functionality exactly
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
import '../../../../core/services/bill_service.dart';
import '../app_top_bar.dart';
import 'new_bill.dart';
import 'new_payment_made.dart';

class BillListPage extends StatefulWidget {
  const BillListPage({Key? key}) : super(key: key);

  @override
  State<BillListPage> createState() => _BillListPageState();
}

class _BillListPageState extends State<BillListPage> {
  // Data
  List<Bill> _bills = [];
  BillStats? _stats;
  bool _isLoading = true;
  String? _errorMessage;

  // Filters
  String _selectedStatus = 'All';
  final List<String> _statusFilters = [
    'All',
    'DRAFT',
    'OPEN',
    'PARTIALLY_PAID',
    'PAID',
    'OVERDUE',
    'VOID',
  ];

  // Date Range Filter
  DateTime? _fromDate;
  DateTime? _toDate;

  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalBills = 0;
  final int _itemsPerPage = 20;

  // Selection
  final Set<String> _selectedBills = {};
  bool _selectAll = false;

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Theme color for Bills (Red - matching Zoho Books)
  static const Color _primaryColor = Color(0xFFE74C3C);

  @override
  void initState() {
    super.initState();
    _loadBills();
    _loadStats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================================
  // DATA LOADING
  // ============================================================================

  Future<void> _loadBills() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await BillService.getBills(
        status: _selectedStatus == 'All' ? null : _selectedStatus,
        page: _currentPage,
        limit: _itemsPerPage,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        fromDate: _fromDate,
        toDate: _toDate,
      );

      setState(() {
        _bills = response.bills;
        _totalPages = response.pagination.pages;
        _totalBills = response.pagination.total;
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
      final stats = await BillService.getStats();
      setState(() => _stats = stats);
    } catch (e) {
      debugPrint('Error loading stats: $e');
    }
  }

  Future<void> _refreshData() async {
    await Future.wait([_loadBills(), _loadStats()]);
    _showSuccessSnackbar('Data refreshed successfully');
  }

  // ============================================================================
  // FILTER & NAVIGATION
  // ============================================================================

  void _filterByStatus(String status) {
    setState(() {
      _selectedStatus = status;
      _currentPage = 1;
    });
    _loadBills();
  }

  void _toggleSelection(String billId) {
    setState(() {
      if (_selectedBills.contains(billId)) {
        _selectedBills.remove(billId);
      } else {
        _selectedBills.add(billId);
      }
      _selectAll = _selectedBills.length == _bills.length;
    });
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        _selectedBills.addAll(_bills.map((b) => b.id));
      } else {
        _selectedBills.clear();
      }
    });
  }

  void _openNewBill() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NewBillScreen()),
    );
    if (result == true) _refreshData();
  }

  void _openEditBill(String billId) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => NewBillScreen(billId: billId)),
    );
    if (result == true) _refreshData();
  }

  // ============================================================================
  // BILL ACTIONS
  // ============================================================================

  Future<void> _viewBillDetails(Bill bill) async {
    setState(() => _isLoading = true);
    try {
      final fullBill = await BillService.getBill(bill.id);
      setState(() => _isLoading = false);
      showDialog(
        context: context,
        builder: (context) => BillDetailsDialog(bill: fullBill),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Failed to load bill details: $e');
    }
  }

  Future<void> _deleteBill(Bill bill) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bill'),
        content: Text('Are you sure you want to delete bill ${bill.billNumber}?'),
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
        await BillService.deleteBill(bill.id);
        _showSuccessSnackbar('Bill deleted successfully');
        _refreshData();
      } catch (e) {
        _showErrorSnackbar('Failed to delete bill: $e');
      }
    }
  }

  Future<void> _submitBill(Bill bill) async {
    try {
      await BillService.submitBill(bill.id);
      _showSuccessSnackbar('Bill submitted successfully');
      _refreshData();
    } catch (e) {
      _showErrorSnackbar('Failed to submit bill: $e');
    }
  }

  Future<void> _voidBill(Bill bill) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Void Bill'),
        content: Text('Are you sure you want to void bill ${bill.billNumber}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Void Bill'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await BillService.voidBill(bill.id);
        _showSuccessSnackbar('Bill voided successfully');
        _refreshData();
      } catch (e) {
        _showErrorSnackbar('Failed to void bill: $e');
      }
    }
  }

  Future<void> _sendBill(Bill bill) async {
    try {
      await BillService.sendBill(bill.id);
      _showSuccessSnackbar('Bill sent to ${bill.vendorEmail}');
      _refreshData();
    } catch (e) {
      _showErrorSnackbar('Failed to send bill: $e');
    }
  }

  Future<void> _downloadBillPDF(Bill bill) async {
    try {
      _showSuccessSnackbar('Preparing PDF download...');
      
      // Get JWT token from localStorage
      final token = html.window.localStorage['flutter.jwt_token'];
      
      if (token == null || token.isEmpty) {
        _showErrorSnackbar('Authentication required. Please login again.');
        return;
      }
      
      // Construct PDF URL with authentication
      final pdfUrl = await BillService.downloadPDF(bill.id);

      if (kIsWeb) {
        // For web, we need to fetch with auth header and create blob
        final response = await html.HttpRequest.request(
          pdfUrl,
          method: 'GET',
          requestHeaders: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/pdf',
          },
          responseType: 'blob',
        );
        
        if (response.status == 200) {
          final blob = response.response as html.Blob;
          final url = html.Url.createObjectUrlFromBlob(blob);
          
          html.AnchorElement(href: url)
            ..setAttribute('download', '${bill.billNumber}.pdf')
            ..click();
            
          html.Url.revokeObjectUrl(url);
          _showSuccessSnackbar('✅ PDF downloaded: ${bill.billNumber}');
        } else {
          throw 'Failed to download PDF: ${response.statusText}';
        }
      } else {
        // For mobile, use url_launcher with the URL
        final uri = Uri.parse(pdfUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          _showSuccessSnackbar('✅ PDF opened for ${bill.billNumber}');
        } else {
          throw 'Could not launch PDF viewer';
        }
      }
    } catch (e) {
      _showErrorSnackbar('Failed to download PDF: $e');
    }
  }

  // ============================================================================
  // RECORD PAYMENT DIALOG
  // ============================================================================

  void _showRecordPaymentDialog(Bill bill) {
    final amountController = TextEditingController(
      text: bill.amountDue.toStringAsFixed(2),
    );
    final referenceController = TextEditingController();
    final notesController = TextEditingController();
    DateTime paymentDate = DateTime.now();
    String paymentMode = 'Bank Transfer';
    bool isSaving = false;

    final paymentModes = [
      'Cash',
      'Cheque',
      'Bank Transfer',
      'UPI',
      'Card',
      'Online',
      'NEFT',
      'RTGS',
      'IMPS',
    ];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.payment, color: _primaryColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Record Payment',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      bill.billNumber,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
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
                  // Summary box
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total Bill Amount',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            Text('₹${bill.totalAmount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Amount Paid',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            Text('₹${bill.amountPaid.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Amount Due',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            Text('₹${bill.amountDue.toStringAsFixed(2)}',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red[700])),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Amount field
                  TextFormField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText: 'Payment Amount *',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      helperText: 'Maximum: ₹${bill.amountDue.toStringAsFixed(2)}',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),

                  // Payment Date
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: paymentDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (picked != null) {
                        setDialogState(() => paymentDate = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Payment Date *',
                        prefixIcon: const Icon(Icons.calendar_today),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(
                        DateFormat('dd MMM yyyy').format(paymentDate),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Payment Mode
                  DropdownButtonFormField<String>(
                    value: paymentMode,
                    decoration: InputDecoration(
                      labelText: 'Payment Mode *',
                      prefixIcon: const Icon(Icons.account_balance),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    items: paymentModes.map((mode) {
                      return DropdownMenuItem(value: mode, child: Text(mode));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => paymentMode = val);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Reference Number
                  TextFormField(
                    controller: referenceController,
                    decoration: InputDecoration(
                      labelText: 'Reference / Transaction Number',
                      prefixIcon: const Icon(Icons.receipt),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Notes
                  TextFormField(
                    controller: notesController,
                    decoration: InputDecoration(
                      labelText: 'Notes',
                      prefixIcon: const Icon(Icons.note),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: isSaving
                  ? null
                  : () async {
                      final amount =
                          double.tryParse(amountController.text.trim()) ?? 0;
                      if (amount <= 0) {
                        _showErrorSnackbar('Please enter a valid payment amount');
                        return;
                      }
                      if (amount > bill.amountDue + 0.01) {
                        _showErrorSnackbar(
                            'Payment amount exceeds due amount (₹${bill.amountDue.toStringAsFixed(2)})');
                        return;
                      }

                      setDialogState(() => isSaving = true);
                      try {
                        await BillService.recordPayment(bill.id, {
                          'amount': amount,
                          'paymentDate': paymentDate.toIso8601String(),
                          'paymentMode': paymentMode,
                          'referenceNumber':
                              referenceController.text.trim(),
                          'notes': notesController.text.trim(),
                        });
                        Navigator.pop(context);
                        _showSuccessSnackbar(
                            '✅ Payment of ₹${amount.toStringAsFixed(2)} recorded successfully');
                        _refreshData();
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        _showErrorSnackbar('Failed to record payment: $e');
                      }
                    },
              icon: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(isSaving ? 'Recording...' : 'Record Payment'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // LIFECYCLE DIALOG
  // ============================================================================

  void _showBillLifecycleDialog() {
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
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          color: _primaryColor,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Bill Lifecycle Process',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
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
                                'assets/bill.png',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.account_tree_outlined,
                                        size: 80,
                                        color: Colors.grey[400],
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Life cycle of a Bill',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      // Fallback: Render lifecycle diagram
                                      _buildFallbackLifecycleDiagram(),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
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
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 40,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
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

  Widget _buildFallbackLifecycleDiagram() {
    final stages = [
      {'label': 'DRAFT', 'color': Colors.grey, 'icon': Icons.edit_note},
      {'label': 'OPEN', 'color': Colors.blue, 'icon': Icons.description},
      {'label': 'PARTIALLY PAID', 'color': Colors.orange, 'icon': Icons.payment},
      {'label': 'PAID', 'color': Colors.green, 'icon': Icons.check_circle},
      {'label': 'OVERDUE', 'color': Colors.red, 'icon': Icons.warning},
      {'label': 'VOID', 'color': Colors.grey[600], 'icon': Icons.cancel},
    ];

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < stages.length; i++) ...[
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (stages[i]['color'] as Color).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: (stages[i]['color'] as Color), width: 2),
                    ),
                    child: Column(
                      children: [
                        Icon(stages[i]['icon'] as IconData,
                            color: stages[i]['color'] as Color, size: 28),
                        const SizedBox(height: 6),
                        Text(
                          stages[i]['label'] as String,
                          style: TextStyle(
                            color: stages[i]['color'] as Color,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (i < stages.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.arrow_forward,
                      color: Colors.grey[400], size: 20),
                ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: const Text(
            'Bill Flow: Draft → Open (Submit) → Partially Paid / Paid (Record Payment) → Overdue (Past due date) | Can be Voided at any stage',
            style: TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // EXCEL EXPORT
  // ============================================================================

  Future<void> _exportToExcel() async {
    try {
      if (_bills.isEmpty) {
        _showErrorSnackbar('No bills to export');
        return;
      }

      _showSuccessSnackbar('Preparing Excel export...');

      List<List<dynamic>> csvData = [
        [
          'Date',
          'Bill Number',
          'PO Number',
          'Vendor Name',
          'Vendor Email',
          'Status',
          'Due Date',
          'Payment Terms',
          'Sub Total',
          'TDS',
          'TCS',
          'CGST',
          'SGST',
          'Total Amount',
          'Amount Paid',
          'Amount Due',
          'Notes',
        ],
      ];

      for (var bill in _bills) {
        csvData.add([
          DateFormat('dd/MM/yyyy').format(bill.billDate),
          bill.billNumber,
          bill.purchaseOrderNumber ?? '',
          bill.vendorName,
          bill.vendorEmail ?? '',
          bill.status,
          bill.dueDate != null
              ? DateFormat('dd/MM/yyyy').format(bill.dueDate!)
              : '',
          bill.paymentTerms,
          bill.subTotal.toStringAsFixed(2),
          bill.tdsAmount.toStringAsFixed(2),
          bill.tcsAmount.toStringAsFixed(2),
          bill.cgst.toStringAsFixed(2),
          bill.sgst.toStringAsFixed(2),
          bill.totalAmount.toStringAsFixed(2),
          bill.amountPaid.toStringAsFixed(2),
          bill.amountDue.toStringAsFixed(2),
          bill.notes ?? '',
        ]);
      }

      await ExportHelper.exportToExcel(
        data: csvData,
        filename: 'bills_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      );

      _showSuccessSnackbar(
          '✅ Excel file downloaded with ${_bills.length} bills!');
    } catch (e) {
      _showErrorSnackbar('Failed to export: $e');
    }
  }

  // ============================================================================
  // BULK IMPORT
  // ============================================================================

  void _handleBulkImport() {
    showDialog(
      context: context,
      builder: (context) => BulkImportBillsDialog(
        onImportComplete: () => _refreshData(),
      ),
    );
  }

  // ============================================================================
  // DATE FILTER
  // ============================================================================

  Future<void> _selectFromDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _fromDate = picked);
      _loadBills();
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
      _loadBills();
    }
  }

  void _clearDateFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    _loadBills();
  }

  // ============================================================================
  // SNACKBARS
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
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        title: 'Bills',
        showBack: true,
      ),
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
                    : _bills.isEmpty
                        ? _buildEmptyState()
                        : _buildBillTable(),
          ),
          if (!_isLoading && _bills.isNotEmpty) _buildPagination(),
        ],
      ),
    );
  }

  // ============================================================================
  // TOP BAR
  // ============================================================================

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          // Status Filter Dropdown
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
                    status == 'All' ? 'All Bills' : status.replaceAll('_', ' '),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) _filterByStatus(value);
              },
            ),
          ),

          const SizedBox(width: 12),

          // Search
          SizedBox(
            width: 280,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search bill#, vendor, PO#...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                          _loadBills();
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value.toLowerCase());
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (_searchQuery == value.toLowerCase()) _loadBills();
                });
              },
            ),
          ),

          const SizedBox(width: 12),

          // From Date
          InkWell(
            onTap: _selectFromDate,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: _fromDate != null
                    ? _primaryColor.withOpacity(0.1)
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _fromDate != null ? _primaryColor : Colors.grey[300]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today,
                      size: 17,
                      color: _fromDate != null ? _primaryColor : Colors.grey[600]),
                  const SizedBox(width: 7),
                  Text(
                    _fromDate != null
                        ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}'
                        : 'From Date',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _fromDate != null
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: _fromDate != null ? _primaryColor : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 10),

          // To Date
          InkWell(
            onTap: _selectToDate,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: _toDate != null
                    ? _primaryColor.withOpacity(0.1)
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _toDate != null ? _primaryColor : Colors.grey[300]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today,
                      size: 17,
                      color: _toDate != null ? _primaryColor : Colors.grey[600]),
                  const SizedBox(width: 7),
                  Text(
                    _toDate != null
                        ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}'
                        : 'To Date',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          _toDate != null ? FontWeight.w600 : FontWeight.normal,
                      color:
                          _toDate != null ? _primaryColor : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_fromDate != null || _toDate != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.red),
              onPressed: _clearDateFilters,
              tooltip: 'Clear Date Filters',
              style: IconButton.styleFrom(
                  backgroundColor: Colors.red[50], padding: const EdgeInsets.all(10)),
            ),
          ],

          const Spacer(),

          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh, size: 22),
            onPressed: _isLoading ? null : _refreshData,
            tooltip: 'Refresh',
            style: IconButton.styleFrom(
                backgroundColor: Colors.grey[200],
                padding: const EdgeInsets.all(10)),
          ),

          const SizedBox(width: 10),

          // View Process (Lifecycle)
          IconButton(
            icon: const Icon(Icons.account_tree, size: 22, color: _primaryColor),
            onPressed: _showBillLifecycleDialog,
            tooltip: 'View Bill Lifecycle Process',
            style: IconButton.styleFrom(
              backgroundColor: _primaryColor.withOpacity(0.1),
              padding: const EdgeInsets.all(10),
            ),
          ),

          const SizedBox(width: 10),

          // New Bill
          ElevatedButton.icon(
            onPressed: _openNewBill,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Bill'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),

          const SizedBox(width: 10),

          // Bulk Import
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _handleBulkImport,
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('Import'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9B59B6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),

          const SizedBox(width: 10),

          // Export Excel
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _exportToExcel,
            icon: const Icon(Icons.file_download, size: 18),
            label: const Text('Export Excel'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27AE60),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: Colors.white,
      child: Row(
        children: [
          _buildStatCard('Total Bills', _stats!.totalBills.toString(),
              Icons.receipt_long, Colors.blue),
          const SizedBox(width: 12),
          _buildStatCard(
              'Total Payable',
              '₹${_stats!.totalPayable.toStringAsFixed(0)}',
              Icons.account_balance_wallet,
              Colors.red),
          const SizedBox(width: 12),
          _buildStatCard('Total Paid',
              '₹${_stats!.totalPaid.toStringAsFixed(0)}', Icons.check_circle, Colors.green),
          const SizedBox(width: 12),
          _buildStatCard('Amount Due',
              '₹${_stats!.totalDue.toStringAsFixed(0)}', Icons.warning, Colors.orange),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                  const SizedBox(height: 4),
                  Text(value,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: color),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // BILL TABLE
  // ============================================================================

  Widget _buildBillTable() {
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
          // Header
          Container(
            padding: const EdgeInsets.all(14),
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
                _buildHeaderCell('BILL #', flex: 2),
                _buildHeaderCell('PO #', flex: 2),
                _buildHeaderCell('VENDOR', flex: 3),
                _buildHeaderCell('STATUS', flex: 2),
                _buildHeaderCell('DUE DATE', flex: 2),
                _buildHeaderCell('AMOUNT', flex: 2),
                _buildHeaderCell('DUE', flex: 2),
                const SizedBox(width: 50),
              ],
            ),
          ),

          // Rows
          Expanded(
            child: ListView.separated(
              itemCount: _bills.length,
              separatorBuilder: (context, index) =>
                  Divider(height: 1, color: Colors.grey[200]),
              itemBuilder: (context, index) =>
                  _buildBillRow(_bills[index]),
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
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildBillRow(Bill bill) {
    final isSelected = _selectedBills.contains(bill.id);

    return InkWell(
      onTap: () => _openEditBill(bill.id),
      child: Container(
        padding: const EdgeInsets.all(14),
        color: isSelected ? Colors.red[50] : null,
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Checkbox(
                value: isSelected,
                onChanged: (value) => _toggleSelection(bill.id),
              ),
            ),

            // Date
            Expanded(
              flex: 2,
              child: Text(
                DateFormat('dd/MM/yyyy').format(bill.billDate),
                style: const TextStyle(fontSize: 13),
              ),
            ),

            // Bill Number
            Expanded(
              flex: 2,
              child: InkWell(
                onTap: () => _openEditBill(bill.id),
                child: Text(
                  bill.billNumber,
                  style: const TextStyle(
                    color: _primaryColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),

            // PO Number
            Expanded(
              flex: 2,
              child: Text(
                bill.purchaseOrderNumber ?? '-',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ),

            // Vendor
            Expanded(
              flex: 3,
              child: Text(
                bill.vendorName,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Status
            Expanded(
              flex: 2,
              child: _buildStatusBadge(bill.status),
            ),

            // Due Date
            Expanded(
              flex: 2,
              child: Text(
                bill.dueDate != null
                    ? DateFormat('dd/MM/yyyy').format(bill.dueDate!)
                    : '-',
                style: TextStyle(
                  fontSize: 13,
                  color: bill.dueDate != null &&
                          bill.dueDate!.isBefore(DateTime.now()) &&
                          bill.status != 'PAID' &&
                          bill.status != 'VOID'
                      ? Colors.red
                      : null,
                ),
              ),
            ),

            // Amount
            Expanded(
              flex: 2,
              child: Text(
                '₹${bill.totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                textAlign: TextAlign.right,
              ),
            ),

            // Amount Due
            Expanded(
              flex: 2,
              child: Text(
                '₹${bill.amountDue.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: bill.amountDue > 0 ? Colors.red[700] : Colors.green,
                ),
                textAlign: TextAlign.right,
              ),
            ),

            // Actions Menu
            SizedBox(
              width: 50,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'view',
                    child: ListTile(
                      leading: Icon(Icons.visibility, size: 17,
                          color: Color(0xFF3498DB)),
                      title: Text('View Details'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit, size: 17),
                      title: Text('Edit'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (bill.status == 'DRAFT')
                    const PopupMenuItem(
                      value: 'submit',
                      child: ListTile(
                        leading: Icon(Icons.send, size: 17,
                            color: Color(0xFF27AE60)),
                        title: Text('Submit Bill',
                            style: TextStyle(color: Color(0xFF27AE60))),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (bill.status == 'OPEN' ||
                      bill.status == 'PARTIALLY_PAID' ||
                      bill.status == 'OVERDUE')
                    const PopupMenuItem(
                      value: 'payment',
                      child: ListTile(
                        leading: Icon(Icons.payment, size: 17,
                            color: Color(0xFF27AE60)),
                        title: Text('Record Payment',
                            style: TextStyle(color: Color(0xFF27AE60))),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'pdf',
                    child: ListTile(
                      leading: Icon(Icons.picture_as_pdf, size: 17),
                      title: Text('Download PDF'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (bill.status != 'PAID' && bill.status != 'VOID')
                    const PopupMenuItem(
                      value: 'void',
                      child: ListTile(
                        leading:
                            Icon(Icons.block, size: 17, color: Colors.orange),
                        title: Text('Void Bill',
                            style: TextStyle(color: Colors.orange)),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (bill.status == 'DRAFT')
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading:
                            Icon(Icons.delete, size: 17, color: Colors.red),
                        title: Text('Delete',
                            style: TextStyle(color: Colors.red)),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                ],
                onSelected: (value) async {
                  switch (value) {
                    case 'view':
                      _viewBillDetails(bill);
                      break;
                    case 'edit':
                      _openEditBill(bill.id);
                      break;
                    case 'submit':
                      _submitBill(bill);
                      break;
                    case 'payment':
                      // Navigate to new_payment_made.dart page
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NewPaymentMadeScreen(),
                        ),
                      );
                      // Refresh list if payment was recorded
                      if (result == true) {
                        _loadBills();
                      }
                      break;
                    case 'pdf':
                      _downloadBillPDF(bill);
                      break;
                    case 'void':
                      _voidBill(bill);
                      break;
                    case 'delete':
                      _deleteBill(bill);
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
    Color bgColor;
    Color textColor;

    switch (status) {
      case 'PAID':
        bgColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        break;
      case 'PARTIALLY_PAID':
        bgColor = Colors.orange[100]!;
        textColor = Colors.orange[800]!;
        break;
      case 'OVERDUE':
        bgColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        break;
      case 'OPEN':
        bgColor = Colors.blue[100]!;
        textColor = Colors.blue[800]!;
        break;
      case 'DRAFT':
        bgColor = Colors.grey[200]!;
        textColor = Colors.grey[800]!;
        break;
      case 'VOID':
      case 'CANCELLED':
        bgColor = Colors.blueGrey[100]!;
        textColor = Colors.blueGrey[800]!;
        break;
      default:
        bgColor = Colors.grey[200]!;
        textColor = Colors.grey[800]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
            color: textColor, fontWeight: FontWeight.w600, fontSize: 11),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ============================================================================
  // PAGINATION
  // ============================================================================

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${(_currentPage - 1) * _itemsPerPage + 1}–${(_currentPage * _itemsPerPage).clamp(0, _totalBills)} of $_totalBills bills',
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 1
                    ? () {
                        setState(() => _currentPage--);
                        _loadBills();
                      }
                    : null,
              ),
              ...List.generate(
                _totalPages.clamp(0, 5),
                (index) {
                  final pageNum = index + 1;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: InkWell(
                      onTap: () {
                        setState(() => _currentPage = pageNum);
                        _loadBills();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _currentPage == pageNum
                              ? _primaryColor
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
                        _loadBills();
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
  // EMPTY & ERROR STATES
  // ============================================================================

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No bills found',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700]),
          ),
          const SizedBox(height: 8),
          Text('Create your first bill to get started',
              style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _openNewBill,
            icon: const Icon(Icons.add),
            label: const Text('Create Bill'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
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
          Text('Error Loading Bills',
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
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// BILL DETAILS DIALOG
// ============================================================================

class BillDetailsDialog extends StatelessWidget {
  final Bill bill;

  const BillDetailsDialog({Key? key, required this.bill}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.88,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.receipt_long,
                    color: Color(0xFFE74C3C), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bill.billNumber,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2C3E50))),
                      Text('Bill Details',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[600])),
                    ],
                  ),
                ),
                _buildStatusBadge(bill.status),
                const SizedBox(width: 12),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(height: 28),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection('Vendor Information', [
                      _buildInfoRow('Vendor Name', bill.vendorName),
                      _buildInfoRow('Email', bill.vendorEmail),
                      _buildInfoRow('GSTIN', bill.vendorGSTIN),
                    ]),
                    const SizedBox(height: 20),
                    _buildSection('Bill Information', [
                      _buildInfoRow('Bill Number', bill.billNumber),
                      _buildInfoRow('PO Number', bill.purchaseOrderNumber),
                      _buildInfoRow('Bill Date',
                          DateFormat('dd MMM yyyy').format(bill.billDate)),
                      _buildInfoRow(
                          'Due Date',
                          bill.dueDate != null
                              ? DateFormat('dd MMM yyyy').format(bill.dueDate!)
                              : 'Not Set'),
                      _buildInfoRow('Payment Terms', bill.paymentTerms),
                      _buildInfoRow('Subject', bill.subject),
                    ]),
                    const SizedBox(height: 20),

                    if (bill.items.isNotEmpty) ...[
                      _buildLineItemsSection(bill.items),
                      const SizedBox(height: 20),
                    ],

                    _buildSection('Amount Details', [
                      _buildInfoRow('Sub Total',
                          '₹${bill.subTotal.toStringAsFixed(2)}'),
                      if (bill.tdsAmount > 0)
                        _buildInfoRow(
                            'TDS', '₹${bill.tdsAmount.toStringAsFixed(2)}'),
                      if (bill.tcsAmount > 0)
                        _buildInfoRow(
                            'TCS', '₹${bill.tcsAmount.toStringAsFixed(2)}'),
                      _buildInfoRow(
                          'CGST', '₹${bill.cgst.toStringAsFixed(2)}'),
                      _buildInfoRow(
                          'SGST', '₹${bill.sgst.toStringAsFixed(2)}'),
                      _buildInfoRow('Total Amount',
                          '₹${bill.totalAmount.toStringAsFixed(2)}',
                          isBold: true),
                      _buildInfoRow('Amount Paid',
                          '₹${bill.amountPaid.toStringAsFixed(2)}'),
                      _buildInfoRow(
                          'Amount Due',
                          '₹${bill.amountDue.toStringAsFixed(2)}',
                          isBold: true,
                          color: bill.amountDue > 0
                              ? Colors.red[700]
                              : Colors.green),
                    ]),

                    if (bill.payments.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _buildPaymentsSection(bill.payments),
                    ],

                    if (bill.notes != null && bill.notes!.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _buildSection('Notes', [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(bill.notes!,
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey[800])),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(height: 28),
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

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    switch (status) {
      case 'PAID':
        bgColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        break;
      case 'PARTIALLY_PAID':
        bgColor = Colors.orange[100]!;
        textColor = Colors.orange[800]!;
        break;
      case 'OVERDUE':
        bgColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        break;
      case 'OPEN':
        bgColor = Colors.blue[100]!;
        textColor = Colors.blue[800]!;
        break;
      default:
        bgColor = Colors.grey[200]!;
        textColor = Colors.grey[800]!;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration:
          BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
      child: Text(status,
          style: TextStyle(
              color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C3E50))),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
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

  Widget _buildInfoRow(String label, dynamic value,
      {bool isBold = false, Color? color}) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C3E50),
                    fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value.toString(),
              style: TextStyle(
                  color: color ?? Colors.grey[800],
                  fontSize: 13,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineItemsSection(List<BillItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Line Items',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C3E50))),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Table(
            border: TableBorder.all(color: Colors.grey[300]!, width: 1),
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
                      padding: EdgeInsets.all(10),
                      child: Text('Item',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('Qty',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('Rate',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('Amount',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
              ...items.map<TableRow>((item) {
                return TableRow(children: [
                  Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(item.itemDetails)),
                  Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(item.quantity.toString())),
                  Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text('₹${item.rate.toStringAsFixed(2)}')),
                  Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text('₹${item.amount.toStringAsFixed(2)}')),
                ]);
              }).toList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentsSection(List<BillPayment> payments) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Payment History',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C3E50))),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Table(
            border: TableBorder.all(color: Colors.grey[300]!, width: 1),
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(2),
              2: FlexColumnWidth(2),
              3: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.grey[200]),
                children: const [
                  Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('Date',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('Mode',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('Reference',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('Amount',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
              ...payments.map<TableRow>((p) {
                return TableRow(children: [
                  Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(DateFormat('dd MMM yyyy')
                          .format(p.paymentDate))),
                  Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(p.paymentMode)),
                  Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(p.referenceNumber ?? '-')),
                  Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                          '₹${p.amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w600))),
                ]);
              }).toList(),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// BULK IMPORT BILLS DIALOG
// ============================================================================

class BulkImportBillsDialog extends StatefulWidget {
  final VoidCallback onImportComplete;

  const BulkImportBillsDialog({Key? key, required this.onImportComplete})
      : super(key: key);

  @override
  State<BulkImportBillsDialog> createState() => _BulkImportBillsDialogState();
}

class _BulkImportBillsDialogState extends State<BulkImportBillsDialog> {
  bool isDownloading = false;
  bool isUploading = false;
  String? uploadedFileName;
  List<Map<String, dynamic>>? importResults;

  Future<void> _downloadTemplate() async {
    setState(() => isDownloading = true);
    try {
      List<List<dynamic>> templateData = [
        [
          'Bill Date* (dd/MM/yyyy)',
          'Bill Number',
          'PO Number',
          'Vendor Name*',
          'Vendor Email*',
          'Vendor GSTIN',
          'Due Date (dd/MM/yyyy)',
          'Payment Terms*',
          'Status*',
          'Subject',
          'Sub Total*',
          'TDS Amount',
          'TCS Amount',
          'CGST',
          'SGST',
          'Total Amount*',
          'Notes',
        ],
        [
          '01/01/2024',
          'BILL-2401-0001',
          'PO-001',
          'ABC Supplies Pvt Ltd',
          'accounts@abcsupplies.com',
          '29XXXXX1234X1Z5',
          '31/01/2024',
          'Net 30',
          'DRAFT',
          'Office Supplies - January',
          '100000.00',
          '0.00',
          '0.00',
          '9000.00',
          '9000.00',
          '118000.00',
          'Monthly supplies bill',
        ],
        [
          'INSTRUCTIONS:',
          '1. Fields marked with * are required',
          '2. Date format: dd/MM/yyyy',
          '3. Status: DRAFT, OPEN',
          '4. Payment Terms: Due on Receipt, Net 15, Net 30, Net 45, Net 60',
          '5. Total = SubTotal + CGST + SGST + TCS - TDS',
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
        ],
      ];

      await ExportHelper.exportToExcel(
        data: templateData,
        filename: 'bills_import_template',
      );
      setState(() => isDownloading = false);
      _showSnack('Template downloaded!', Colors.green);
    } catch (e) {
      setState(() => isDownloading = false);
      _showSnack('Failed: $e', Colors.red);
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

      if (rows.length < 2) throw Exception('File must contain header + data rows');

      List<Map<String, dynamic>> billsToImport = [];
      List<String> errors = [];

      for (int i = 1; i < rows.length; i++) {
        try {
          var row = rows[i];
          if (row.isEmpty ||
              row[0] == null ||
              row[0].toString().trim().isEmpty ||
              row[0].toString().toUpperCase().contains('INSTRUCTION')) continue;

          final billDate = _parseDate(_getVal(row, 0));
          final billNumber = _getStr(row, 1);
          final poNumber = _getStr(row, 2);
          final vendorName = _getStr(row, 3);
          final vendorEmail = _getStr(row, 4);
          final vendorGSTIN = _getStr(row, 5);
          final dueDate = _parseDate(_getVal(row, 6));
          final paymentTerms = _getStr(row, 7, 'Net 30');
          final status = _getStr(row, 8, 'DRAFT');
          final subject = _getStr(row, 9);
          final subTotal = _parseDbl(_getVal(row, 10));
          final tdsAmount = _parseDbl(_getVal(row, 11));
          final tcsAmount = _parseDbl(_getVal(row, 12));
          final cgst = _parseDbl(_getVal(row, 13));
          final sgst = _parseDbl(_getVal(row, 14));
          final totalAmount = _parseDbl(_getVal(row, 15));
          final notes = _getStr(row, 16);

          List<String> rowErrors = [];
          if (billDate == null) rowErrors.add('Bill Date required');
          if (vendorName.isEmpty) rowErrors.add('Vendor Name required');
          if (vendorEmail.isEmpty) rowErrors.add('Vendor Email required');
          if (subTotal <= 0) rowErrors.add('Sub Total > 0 required');
          if (totalAmount <= 0) rowErrors.add('Total Amount > 0 required');

          if (rowErrors.isNotEmpty) {
            errors.add('Row ${i + 1}: ${rowErrors.join(", ")}');
            continue;
          }

          billsToImport.add({
            'billDate': billDate!.toIso8601String(),
            'billNumber': billNumber,
            'purchaseOrderNumber': poNumber,
            'vendorName': vendorName,
            'vendorEmail': vendorEmail,
            'vendorGSTIN': vendorGSTIN,
            'dueDate': dueDate?.toIso8601String(),
            'paymentTerms': paymentTerms,
            'status': status.toUpperCase(),
            'subject': subject,
            'subTotal': subTotal,
            'tdsAmount': tdsAmount,
            'tcsAmount': tcsAmount,
            'cgst': cgst,
            'sgst': sgst,
            'totalAmount': totalAmount,
            'notes': notes,
            'items': [],
          });
        } catch (e) {
          errors.add('Row ${i + 1}: $e');
        }
      }

      if (billsToImport.isEmpty) throw Exception('No valid bill data found');

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Import'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Found ${billsToImport.length} bill(s) to import.',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 16)),
                if (errors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('${errors.length} row(s) skipped:',
                      style: const TextStyle(
                          color: Colors.red, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 150),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: SingleChildScrollView(
                      child: Text(errors.join('\n'),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.red)),
                    ),
                  ),
                ],
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
                  backgroundColor: const Color(0xFFE74C3C)),
              child: const Text('Import'),
            ),
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

      final importResult = await BillService.bulkImportBills(billsToImport);

      setState(() {
        isUploading = false;
        importResults = [
          {
            'success': importResult['data']?['successCount'] ?? billsToImport.length,
            'failed': importResult['data']?['failedCount'] ?? 0,
            'total': importResult['data']?['totalProcessed'] ?? billsToImport.length,
            'errors': importResult['data']?['errors'] ?? [],
          }
        ];
      });

      if (importResult['success'] == true) {
        _showSnack('Import completed!', Colors.green);
        widget.onImportComplete();
      }
    } catch (e) {
      setState(() {
        isUploading = false;
        uploadedFileName = null;
      });
      _showSnack('Failed to import: $e', Colors.red);
    }
  }

  dynamic _getVal(List<dynamic> row, int index) {
    if (index >= row.length) return null;
    return row[index];
  }

  String _getStr(List<dynamic> row, int index, [String def = '']) {
    if (index >= row.length) return def;
    final val = row[index];
    if (val == null) return def;
    return val.toString().trim();
  }

  double _parseDbl(dynamic val) {
    if (val == null) return 0.0;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    try {
      return double.parse(val.toString().trim());
    } catch (_) {
      return 0.0;
    }
  }

  DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    final str = val.toString().trim();
    if (str.isEmpty) return null;
    for (final fmt in ['dd/MM/yyyy', 'dd-MM-yyyy', 'yyyy-MM-dd', 'MM/dd/yyyy']) {
      try {
        return DateFormat(fmt).parse(str);
      } catch (_) {}
    }
    return null;
  }

  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    final ex = excel_pkg.Excel.decodeBytes(bytes);
    final sheet = ex.tables.keys.first;
    final rows = ex.tables[sheet]?.rows;
    if (rows == null || rows.isEmpty) throw Exception('Excel file is empty');
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
    final csvString = utf8.decode(bytes, allowMalformed: true);
    final lines = csvString.split(RegExp(r'\r?\n'));
    List<List<dynamic>> rows = [];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      rows.add(_parseCSVLine(trimmed));
    }
    return rows;
  }

  List<String> _parseCSVLine(String line) {
    List<String> fields = [];
    StringBuffer curr = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          curr.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        fields.add(curr.toString().trim());
        curr.clear();
      } else {
        curr.write(ch);
      }
    }
    fields.add(curr.toString().trim());
    return fields.map((f) {
      if (f.startsWith('"') && f.endsWith('"')) {
        return f.substring(1, f.length - 1);
      }
      return f;
    }).toList();
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 580,
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
                  child: Text(
                    'Bulk Import Bills',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50)),
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(height: 28),

            Container(
              padding: const EdgeInsets.all(14),
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
                          color: Colors.blue[700], size: 18),
                      const SizedBox(width: 8),
                      Text('How to Import Bills',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.blue[700])),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Download the sample template\n'
                    '2. Fill in your bill data\n'
                    '3. Dates in dd/MM/yyyy format\n'
                    '4. Upload completed file (.xlsx, .xls, .csv)\n'
                    '5. Review and confirm import',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isDownloading || isUploading ? null : _downloadTemplate,
                icon: isDownloading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                    : const Icon(Icons.download),
                label: Text(
                    isDownloading ? 'Downloading...' : 'Download Sample Template'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE74C3C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isDownloading || isUploading ? null : _uploadFile,
                icon: isUploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF9B59B6))))
                    : const Icon(Icons.upload_file),
                label: Text(isUploading ? 'Processing...' : 'Upload Excel or CSV File'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF9B59B6),
                  side: const BorderSide(color: Color(0xFF9B59B6)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            if (uploadedFileName != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[700], size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(uploadedFileName!,
                            style: TextStyle(
                                color: Colors.green[700],
                                fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
            ],

            if (importResults != null) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 14),
              const Text('Import Results',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C3E50))),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  children: [
                    _resultRow(
                        'Total Processed',
                        importResults![0]['total'].toString(),
                        Colors.blue),
                    const SizedBox(height: 8),
                    _resultRow('Successfully Imported',
                        importResults![0]['success'].toString(), Colors.green),
                    const SizedBox(height: 8),
                    _resultRow('Failed',
                        importResults![0]['failed'].toString(), Colors.red),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE74C3C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
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
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(value,
              style:
                  TextStyle(color: color, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}