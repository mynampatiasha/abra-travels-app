// ============================================================================
// INVOICES LIST PAGE - COMPLETE REDESIGN
// ============================================================================
// File: lib/screens/billing/invoices_list_page.dart
// UI matches credit_notes_list_page.dart:
//   ✅ 3-breakpoint top bar (Desktop ≥1100 / Tablet 700-1100 / Mobile <700)
//   ✅ Gradient stats cards — 4-in-a-row, horizontal scroll on mobile
//   ✅ Table: header 0xFF0D1B3E, fontSize 13, letterSpacing 0.4,
//             headingRowHeight 52, scrollbar thickness 8
//   ✅ Animated pagination with ellipsis
//   ✅ Import dialog (download template + upload xlsx/csv → backend)
//   ✅ Export Excel, PDF download, Send, Edit, Delete, View Details
//   ✅ Invoice Lifecycle dialog preserved
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_html/html.dart' as html;
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../../core/utils/export_helper.dart';
import '../../../../core/services/invoice_service.dart';
import '../../../../core/services/api_service.dart';
import '../../../../app/config/api_config.dart';
import '../app_top_bar.dart';
import 'new_invoice.dart';
import 'new_recurring_invoice.dart';

// ── Brand palette (matches credit notes) ─────────────────────────────────────
const Color _navy   = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);

// ── Stat card data ────────────────────────────────────────────────────────────
class _StatCardData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final List<Color> gradientColors;
  const _StatCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.gradientColors,
  });
}

// =============================================================================
class InvoicesListPage extends StatefulWidget {
  const InvoicesListPage({Key? key}) : super(key: key);

  @override
  State<InvoicesListPage> createState() => _InvoicesListPageState();
}

class _InvoicesListPageState extends State<InvoicesListPage> {
  // ── Data ───────────────────────────────────────────────────────────────────
  List<Invoice> _invoices = [];
  InvoiceStats? _stats;
  bool _isLoading = true;
  String? _errorMessage;

  // ── Filters ────────────────────────────────────────────────────────────────
  String _selectedStatus = 'All';
  final List<String> _statusFilters = [
    'All', 'DRAFT', 'SENT', 'UNPAID', 'PARTIALLY_PAID',
    'PAID', 'OVERDUE', 'CANCELLED',
  ];
  DateTime? _fromDate;
  DateTime? _toDate;

  // ── Pagination ─────────────────────────────────────────────────────────────
  int _currentPage    = 1;
  int _totalPages     = 1;
  int _totalInvoices  = 0;
  final int _itemsPerPage = 20;

  // ── Selection ──────────────────────────────────────────────────────────────
  final Set<String> _selectedInvoices = {};
  bool _selectAll = false;

  // ── Search ─────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ── Scroll ─────────────────────────────────────────────────────────────────
  final ScrollController _tableHScrollCtrl = ScrollController();
  final ScrollController _statsHScrollCtrl = ScrollController();

  // ==========================================================================
  @override
  void initState() {
    super.initState();
    _loadInvoices();
    _loadStats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tableHScrollCtrl.dispose();
    _statsHScrollCtrl.dispose();
    super.dispose();
  }

  // ==========================================================================
  //  DATA
  // ==========================================================================

  Future<void> _loadInvoices() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final response = await InvoiceService.getInvoices(
        status:   _selectedStatus == 'All' ? null : _selectedStatus,
        page:     _currentPage,
        limit:    _itemsPerPage,
        fromDate: _fromDate,
        toDate:   _toDate,
      );
      setState(() {
        _invoices      = response.invoices;
        _totalPages    = response.pagination.pages;
        _totalInvoices = response.pagination.total;
        _isLoading     = false;
      });
    } catch (e) {
      setState(() { _errorMessage = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _loadStats() async {
    try {
      final stats = await InvoiceService.getStats();
      setState(() => _stats = stats);
    } catch (e) {
      debugPrint('Stats error: $e');
    }
  }

  Future<void> _refreshData() async {
    _currentPage = 1;
    await Future.wait([_loadInvoices(), _loadStats()]);
    _snackSuccess('Data refreshed successfully');
  }

  void _filterByStatus(String status) {
    setState(() { _selectedStatus = status; _currentPage = 1; });
    _loadInvoices();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedInvoices.contains(id)) {
        _selectedInvoices.remove(id);
      } else {
        _selectedInvoices.add(id);
      }
      _selectAll = _selectedInvoices.length == _invoices.length;
    });
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        _selectedInvoices.addAll(_invoices.map((inv) => inv.id));
      } else {
        _selectedInvoices.clear();
      }
    });
  }

  // ==========================================================================
  //  NAVIGATION
  // ==========================================================================

  void _openNewInvoice() async {
    final result = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const NewInvoiceScreen()));
    if (result == true) _refreshData();
  }

  void _openEditInvoice(String invoiceId) async {
    final result = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => NewInvoiceScreen(invoiceId: invoiceId)));
    if (result == true) _refreshData();
  }

  // ==========================================================================
  //  ACTIONS
  // ==========================================================================

  Future<void> _viewInvoiceDetails(Invoice invoice) async {
    setState(() => _isLoading = true);
    try {
      final fullInvoice = await InvoiceService.getInvoice(invoice.id);
      setState(() => _isLoading = false);
      final data = {
        'invoiceNumber':   fullInvoice.invoiceNumber,
        'status':          fullInvoice.status,
        'customerName':    fullInvoice.customerName,
        'customerEmail':   fullInvoice.customerEmail,
        'customerPhone':   fullInvoice.customerPhone,
        'customerAddress': fullInvoice.billingAddress != null
            ? '${fullInvoice.billingAddress!.street ?? ''}, '
              '${fullInvoice.billingAddress!.city ?? ''}, '
              '${fullInvoice.billingAddress!.state ?? ''} '
              '${fullInvoice.billingAddress!.pincode ?? ''}'
            : null,
        'invoiceDate':   fullInvoice.invoiceDate.toIso8601String(),
        'dueDate':       fullInvoice.dueDate.toIso8601String(),
        'paymentTerms':  fullInvoice.terms,
        'referenceNumber': fullInvoice.orderNumber,
        'lineItems': fullInvoice.items.map((item) => {
          'itemName':  item.itemDetails,
          'quantity':  item.quantity,
          'rate':      item.rate,
          'amount':    item.amount,
        }).toList(),
        'subtotal':     fullInvoice.subTotal,
        'taxAmount':    fullInvoice.cgst + fullInvoice.sgst + fullInvoice.igst,
        'discount':     0.0,
        'totalAmount':  fullInvoice.totalAmount,
        'amountPaid':   fullInvoice.amountPaid,
        'balanceDue':   fullInvoice.amountDue,
        'notes':        fullInvoice.customerNotes,
        'attachments':  [],
        'createdBy':    'System',
        'createdAt':    fullInvoice.createdAt.toIso8601String(),
        'updatedAt':    fullInvoice.updatedAt.toIso8601String(),
      };
      showDialog(
        context: context,
        builder: (_) => InvoiceDetailsDialog(invoiceData: data),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _snackError('Failed to load invoice details: $e');
    }
  }

  Future<void> _deleteInvoice(Invoice invoice) async {
    if (invoice.status != 'DRAFT') {
      _snackError('Only draft invoices can be deleted');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Invoice',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
            'Delete invoice ${invoice.invoiceNumber}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await InvoiceService.deleteInvoice(invoice.id);
        _snackSuccess('Invoice deleted successfully');
        _refreshData();
      } catch (e) {
        _snackError('Failed to delete invoice: $e');
      }
    }
  }

  Future<void> _sendInvoice(Invoice invoice) async {
    try {
      await InvoiceService.sendInvoice(invoice.id);
      _snackSuccess('Invoice sent to ${invoice.customerEmail}');
      _refreshData();
    } catch (e) {
      _snackError('Failed to send invoice: $e');
    }
  }

  Future<void> _downloadInvoicePDF(Invoice invoice) async {
    try {
      _snackSuccess('Preparing PDF download...');
      final pdfUrl = await InvoiceService.downloadPDF(invoice.id);
      if (kIsWeb) {
        html.AnchorElement(href: pdfUrl)
          ..setAttribute('download', '${invoice.invoiceNumber}.pdf')
          ..setAttribute('target', '_blank')
          ..click();
        _snackSuccess('✅ PDF download started for ${invoice.invoiceNumber}');
      } else {
        final uri = Uri.parse(pdfUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not launch PDF viewer';
        }
      }
    } catch (e) {
      _snackError('Failed to download PDF: $e');
    }
  }

  Future<void> _exportToExcel() async {
    if (_invoices.isEmpty) { _snackError('No invoices to export'); return; }
    try {
      _snackSuccess('Preparing Excel export...');
      List<List<dynamic>> csvData = [
        ['Date', 'Invoice #', 'Order Number', 'Customer Name', 'Customer Email',
         'Status', 'Due Date', 'Sub Total', 'CGST', 'SGST', 'IGST',
         'Total Amount', 'Amount Paid', 'Balance Due'],
      ];
      for (var inv in _invoices) {
        csvData.add([
          DateFormat('dd/MM/yyyy').format(inv.invoiceDate),
          inv.invoiceNumber,
          inv.orderNumber ?? '',
          inv.customerName,
          inv.customerEmail ?? '',
          inv.status,
          DateFormat('dd/MM/yyyy').format(inv.dueDate),
          inv.subTotal.toStringAsFixed(2),
          inv.cgst.toStringAsFixed(2),
          inv.sgst.toStringAsFixed(2),
          inv.igst.toStringAsFixed(2),
          inv.totalAmount.toStringAsFixed(2),
          inv.amountPaid.toStringAsFixed(2),
          inv.amountDue.toStringAsFixed(2),
        ]);
      }
      await ExportHelper.exportToExcel(data: csvData, filename: 'invoices');
      _snackSuccess('✅ Excel downloaded with ${_invoices.length} invoices!');
    } catch (e) {
      _snackError('Failed to export: $e');
    }
  }

  void _showImportDialog() {
    showDialog(
      context: context,
      builder: (_) => _BulkImportInvoicesDialog(
        onImportComplete: _refreshData,
      ),
    );
  }

  void _showInvoiceLifecycleDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
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
                          color: Color(0xFF3498DB),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Invoice Lifecycle Process',
                          style: TextStyle(color: Colors.white,
                              fontSize: 22, fontWeight: FontWeight.bold),
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
                                'assets/invoice.png',
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.broken_image_outlined,
                                        size: 80, color: Colors.grey[400]),
                                    const SizedBox(height: 16),
                                    Text('Image not found',
                                        style: TextStyle(fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey[700])),
                                    const SizedBox(height: 8),
                                    Text('Please ensure "assets/invoice.png" exists',
                                        style: TextStyle(fontSize: 14,
                                            color: Colors.grey[600])),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        color: Colors.grey[100],
                        child: Text(
                          'Tip: Pinch to zoom, drag to pan',
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40, right: 40,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.6),
                  padding: const EdgeInsets.all(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Date pickers ──────────────────────────────────────────────────────────

  Future<void> _selectFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() { _fromDate = picked; });
      _loadInvoices();
    }
  }

  Future<void> _selectToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() { _toDate = picked; });
      _loadInvoices();
    }
  }

  void _clearDateFilters() {
    setState(() { _fromDate = null; _toDate = null; });
    _loadInvoices();
  }

  bool get _hasDateFilters => _fromDate != null || _toDate != null;

  // ── Snackbars ─────────────────────────────────────────────────────────────

  void _snackSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 18),
        const SizedBox(width: 8), Text(msg),
      ]),
      backgroundColor: _green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _snackError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8), Expanded(child: Text(msg)),
      ]),
      backgroundColor: Colors.red[700],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ==========================================================================
  //  BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Invoices'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildTopBar(),
            if (_stats != null) _buildStatsCards(),
            _isLoading
                ? const SizedBox(
                    height: 400,
                    child: Center(
                        child: CircularProgressIndicator(color: _navy)))
                : _errorMessage != null
                    ? SizedBox(height: 400, child: _buildErrorState())
                    : _invoices.isEmpty
                        ? SizedBox(height: 400, child: _buildEmptyState())
                        : _buildInvoiceTable(),
            if (!_isLoading && _invoices.isNotEmpty) _buildPagination(),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  //  TOP BAR — 3 breakpoints
  //  Desktop (≥1100px): single Row, Spacer → actions far right
  //  Tablet  (700–1100): 2-row Column
  //  Mobile  (<700px):  Row1: dropdown+search+New | Row2: scrollable strip
  // ==========================================================================

  Widget _buildTopBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: LayoutBuilder(builder: (_, constraints) {
        final w = constraints.maxWidth;
        if (w >= 1100) return _topBarDesktop();
        if (w >= 700)  return _topBarTablet();
        return _topBarMobile();
      }),
    );
  }

  // ── Desktop ────────────────────────────────────────────────────────────────
  Widget _topBarDesktop() => Row(children: [
    _statusDropdown(),
    const SizedBox(width: 12),
    _searchField(width: 240),
    const SizedBox(width: 10),
    _dateChip(
      label: _fromDate != null
          ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}'
          : 'From Date',
      isActive: _fromDate != null,
      onTap: _selectFromDate,
    ),
    const SizedBox(width: 8),
    _dateChip(
      label: _toDate != null
          ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}'
          : 'To Date',
      isActive: _toDate != null,
      onTap: _selectToDate,
    ),
    if (_hasDateFilters) ...[
      const SizedBox(width: 6),
      _iconBtn(Icons.close, _clearDateFilters,
          tooltip: 'Clear Dates',
          color: Colors.red[600]!,
          bg: Colors.red[50]!),
    ],
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refreshData,
        tooltip: 'Refresh'),
    const SizedBox(width: 6),
    _iconBtn(Icons.account_tree_rounded, _showInvoiceLifecycleDialog,
        tooltip: 'View Invoice Process',
        color: _blue,
        bg: _blue.withOpacity(0.10)),
    const Spacer(),
    // New Invoice popup
    _newInvoiceButton(),
    const SizedBox(width: 8),
    _actionBtn('Import', Icons.upload_file_rounded, _purple, _showImportDialog),
    const SizedBox(width: 8),
    _actionBtn('Export Excel', Icons.download_rounded, _green,
        _isLoading ? null : _exportToExcel),
  ]);

  // ── Tablet ─────────────────────────────────────────────────────────────────
  Widget _topBarTablet() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        _statusDropdown(),
        const SizedBox(width: 10),
        _searchField(width: 200),
        const SizedBox(width: 8),
        _dateChip(
          label: _fromDate != null
              ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}'
              : 'From Date',
          isActive: _fromDate != null,
          onTap: _selectFromDate,
        ),
        const SizedBox(width: 6),
        _dateChip(
          label: _toDate != null
              ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}'
              : 'To Date',
          isActive: _toDate != null,
          onTap: _selectToDate,
        ),
        if (_hasDateFilters) ...[
          const SizedBox(width: 6),
          _iconBtn(Icons.close, _clearDateFilters,
              tooltip: 'Clear',
              color: Colors.red[600]!,
              bg: Colors.red[50]!),
        ],
        const SizedBox(width: 6),
        _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refreshData,
            tooltip: 'Refresh'),
        const SizedBox(width: 6),
        _iconBtn(Icons.account_tree_rounded, _showInvoiceLifecycleDialog,
            tooltip: 'View Process',
            color: _blue,
            bg: _blue.withOpacity(0.10)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _newInvoiceButton(),
        const SizedBox(width: 8),
        _actionBtn('Import', Icons.upload_file_rounded, _purple, _showImportDialog),
        const SizedBox(width: 8),
        _actionBtn('Export Excel', Icons.download_rounded, _green,
            _isLoading ? null : _exportToExcel),
      ]),
    ],
  );

  // ── Mobile ─────────────────────────────────────────────────────────────────
  Widget _topBarMobile() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        _statusDropdown(),
        const SizedBox(width: 8),
        Expanded(child: _searchField(width: double.infinity)),
        const SizedBox(width: 8),
        _newInvoiceButton(compact: true),
      ]),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _dateChip(
            label: _fromDate != null
                ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}'
                : 'From Date',
            isActive: _fromDate != null,
            onTap: _selectFromDate,
          ),
          const SizedBox(width: 6),
          _dateChip(
            label: _toDate != null
                ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}'
                : 'To Date',
            isActive: _toDate != null,
            onTap: _selectToDate,
          ),
          if (_hasDateFilters) ...[
            const SizedBox(width: 6),
            _iconBtn(Icons.close, _clearDateFilters,
                tooltip: 'Clear',
                color: Colors.red[600]!,
                bg: Colors.red[50]!),
          ],
          const SizedBox(width: 6),
          _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refreshData,
              tooltip: 'Refresh'),
          const SizedBox(width: 6),
          _iconBtn(Icons.account_tree_rounded, _showInvoiceLifecycleDialog,
              tooltip: 'View Process',
              color: _blue,
              bg: _blue.withOpacity(0.10)),
          const SizedBox(width: 6),
          _compactBtn('Import', _purple, _showImportDialog),
          const SizedBox(width: 6),
          _compactBtn('Export', _green, _isLoading ? null : _exportToExcel),
        ]),
      ),
    ],
  );

  // ── New Invoice popup button ───────────────────────────────────────────────
  Widget _newInvoiceButton({bool compact = false}) {
    return PopupMenuButton<String>(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (value) {
        if (value == 'invoice') {
          _openNewInvoice();
        } else if (value == 'recurring') {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const NewRecurringInvoiceScreen()),
          ).then((result) { if (result == true) _refreshData(); });
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'invoice',
          child: ListTile(
            leading: Icon(Icons.description, size: 20),
            title: Text('New Invoice'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'recurring',
          child: ListTile(
            leading: Icon(Icons.repeat, size: 20),
            title: Text('New Recurring Invoice'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      child: Container(
        height: 42,
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16, vertical: 11),
        decoration: BoxDecoration(
          color: _navy,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.add, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(compact ? 'New' : 'New Invoice',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, color: Colors.white, size: 16),
        ]),
      ),
    );
  }

  // ── Shared top-bar widgets ─────────────────────────────────────────────────

  Widget _statusDropdown() => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F9FC),
      border: Border.all(color: const Color(0xFFDDE3EE)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedStatus,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: _navy),
        items: _statusFilters
            .map((s) => DropdownMenuItem(
                value: s,
                child: Text(s == 'All'
                    ? 'All Invoices'
                    : s.replaceAll('_', ' '))))
            .toList(),
        onChanged: (v) { if (v != null) _filterByStatus(v); },
      ),
    ),
  );

  Widget _searchField({required double width}) {
    final field = TextField(
      controller: _searchController,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search invoices...',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () {
                  _searchController.clear();
                  setState(() { _searchQuery = ''; _currentPage = 1; });
                  _loadInvoices();
                })
            : null,
        filled: true,
        fillColor: const Color(0xFFF7F9FC),
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        isDense: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _navy, width: 1.5)),
      ),
      onChanged: (v) {
        setState(() { _searchQuery = v.toLowerCase(); _currentPage = 1; });
        Future.delayed(const Duration(milliseconds: 400), () {
          if (_searchQuery == v.toLowerCase()) _loadInvoices();
        });
      },
    );
    if (width == double.infinity) return field;
    return SizedBox(width: width, height: 44, child: field);
  }

  Widget _dateChip({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? _navy.withOpacity(0.08) : const Color(0xFFF7F9FC),
          border: Border.all(
              color: isActive ? _navy : const Color(0xFFDDE3EE)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.calendar_today,
              size: 15,
              color: isActive ? _navy : Colors.grey[500]),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive ? _navy : Colors.grey[600])),
        ]),
      ),
    );
  }

  Widget _iconBtn(
    IconData icon,
    VoidCallback? onTap, {
    String tooltip = '',
    Color color = const Color(0xFF7F8C8D),
    Color bg = const Color(0xFFF1F1F1),
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Icon(icon,
              size: 20,
              color: onTap == null ? Colors.grey[300] : color),
        ),
      ),
    );
  }

  Widget _actionBtn(
      String label, IconData icon, Color bg, VoidCallback? onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        disabledBackgroundColor: bg.withOpacity(0.5),
        elevation: 0,
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _compactBtn(String label, Color bg, VoidCallback? onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        disabledBackgroundColor: bg.withOpacity(0.5),
        elevation: 0,
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }

  // ==========================================================================
  //  STATS CARDS
  //  4-in-a-row always:
  //  Desktop → Expanded fills full width
  //  Mobile  → fixed 160px, horizontally scrollable
  // ==========================================================================

  Widget _buildStatsCards() {
    if (_stats == null) return const SizedBox.shrink();

    final List<_StatCardData> cards = [
      _StatCardData(
        label: 'Total Revenue',
        value: '₹${_stats!.totalRevenue.toStringAsFixed(2)}',
        icon: Icons.attach_money_rounded,
        color: _blue,
        gradientColors: const [Color(0xFF3498DB), Color(0xFF2980B9)],
      ),
      _StatCardData(
        label: 'Total Paid',
        value: '₹${_stats!.totalPaid.toStringAsFixed(2)}',
        icon: Icons.check_circle_outline_rounded,
        color: _green,
        gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)],
      ),
      _StatCardData(
        label: 'Total Due',
        value: '₹${_stats!.totalDue.toStringAsFixed(2)}',
        icon: Icons.pending_actions_rounded,
        color: const Color(0xFFE67E22),
        gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)],
      ),
      _StatCardData(
        label: 'Total Invoices',
        value: _stats!.totalInvoices.toString(),
        icon: Icons.description_outlined,
        color: _navy,
        gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)],
      ),
    ];

    return Container(
      width: double.infinity,
      color: const Color(0xFFF0F4F8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(builder: (_, constraints) {
        final isMobile = constraints.maxWidth < 700;
        if (isMobile) {
          return SingleChildScrollView(
            controller: _statsHScrollCtrl,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: cards.asMap().entries.map((entry) {
                final i = entry.key;
                final c = entry.value;
                return Container(
                  width: 160,
                  margin: EdgeInsets.only(right: i < cards.length - 1 ? 10 : 0),
                  child: _buildStatCard(c, compact: true),
                );
              }).toList(),
            ),
          );
        }
        return Row(
          children: cards.asMap().entries.map((entry) {
            final i = entry.key;
            final c = entry.value;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < cards.length - 1 ? 10 : 0),
                child: _buildStatCard(c, compact: false),
              ),
            );
          }).toList(),
        );
      }),
    );
  }

  Widget _buildStatCard(_StatCardData data, {required bool compact}) {
    return Container(
      padding: compact
          ? const EdgeInsets.all(12)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            data.gradientColors[0].withOpacity(0.15),
            data.gradientColors[1].withOpacity(0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: data.color.withOpacity(0.22)),
        boxShadow: [
          BoxShadow(
            color: data.color.withOpacity(0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: data.gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(data.icon, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 10),
                Text(data.label,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600],
                        fontWeight: FontWeight.w500),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(data.value,
                    style: TextStyle(fontSize: 15,
                        fontWeight: FontWeight.bold, color: data.color),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            )
          : Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: data.gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: data.color.withOpacity(0.30),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(data.icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(data.label,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600],
                              fontWeight: FontWeight.w500),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 5),
                      Text(data.value,
                          style: TextStyle(fontSize: 18,
                              fontWeight: FontWeight.bold, color: data.color),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ==========================================================================
  //  TABLE
  // ==========================================================================

  Widget _buildInvoiceTable() {
    // local search filter
    final filtered = _searchQuery.isEmpty
        ? _invoices
        : _invoices.where((inv) {
            return inv.invoiceNumber.toLowerCase().contains(_searchQuery) ||
                   inv.customerName.toLowerCase().contains(_searchQuery) ||
                   (inv.orderNumber?.toLowerCase().contains(_searchQuery) ?? false);
          }).toList();

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        return Scrollbar(
          controller: _tableHScrollCtrl,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 8,
          radius: const Radius.circular(4),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: SingleChildScrollView(
              controller: _tableHScrollCtrl,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor:
                      WidgetStateProperty.all(const Color(0xFF0D1B3E)),
                  headingTextStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 0.4),
                  headingRowHeight: 52,
                  dataRowMinHeight: 58,
                  dataRowMaxHeight: 72,
                  dataTextStyle: const TextStyle(fontSize: 14),
                  dataRowColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.hovered))
                      return _navy.withOpacity(0.04);
                    return null;
                  }),
                  dividerThickness: 1,
                  columnSpacing: 18,
                  horizontalMargin: 16,
                  columns: [
                    DataColumn(
                      label: SizedBox(
                        width: 36,
                        child: Checkbox(
                          value: _selectAll,
                          fillColor: WidgetStateProperty.all(Colors.white),
                          checkColor: const Color(0xFF0D1B3E),
                          onChanged: _toggleSelectAll,
                        ),
                      ),
                    ),
                    const DataColumn(
                        label: SizedBox(width: 110, child: Text('DATE'))),
                    const DataColumn(
                        label: SizedBox(width: 140, child: Text('INVOICE #'))),
                    const DataColumn(
                        label: SizedBox(width: 130, child: Text('ORDER #'))),
                    const DataColumn(
                        label: SizedBox(width: 170, child: Text('CUSTOMER'))),
                    const DataColumn(
                        label: SizedBox(width: 120, child: Text('STATUS'))),
                    const DataColumn(
                        label: SizedBox(width: 110, child: Text('DUE DATE'))),
                    const DataColumn(
                        label: SizedBox(width: 120, child: Text('AMOUNT'))),
                    const DataColumn(
                        label: SizedBox(width: 120, child: Text('BALANCE'))),
                    const DataColumn(
                        label: SizedBox(width: 80, child: Text('ACTIONS'))),
                  ],
                  rows: filtered.map((inv) => _buildInvoiceRow(inv)).toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildInvoiceRow(Invoice invoice) {
    final isSelected = _selectedInvoices.contains(invoice.id);
    return DataRow(
      selected: isSelected,
      color: WidgetStateProperty.resolveWith((states) {
        if (isSelected) return _navy.withOpacity(0.06);
        if (states.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
        return null;
      }),
      cells: [
        DataCell(Checkbox(
            value: isSelected,
            onChanged: (_) => _toggleSelection(invoice.id))),

        DataCell(SizedBox(
          width: 110,
          child: Text(DateFormat('dd MMM yyyy').format(invoice.invoiceDate)),
        )),

        DataCell(SizedBox(
          width: 140,
          child: InkWell(
            onTap: () => _openEditInvoice(invoice.id),
            child: Text(
              invoice.invoiceNumber,
              style: const TextStyle(
                  color: _navy,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )),

        DataCell(SizedBox(
          width: 130,
          child: Text(invoice.orderNumber ?? '-',
              style: TextStyle(color: Colors.grey[600]),
              overflow: TextOverflow.ellipsis),
        )),

        DataCell(SizedBox(
          width: 170,
          child: Row(children: [
            Container(
              width: 30, height: 30,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                  color: _navy.withOpacity(0.10), shape: BoxShape.circle),
              child: Center(
                child: Text(
                  invoice.customerName.isNotEmpty
                      ? invoice.customerName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: _navy, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
            Expanded(
              child: Text(invoice.customerName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ]),
        )),

        DataCell(SizedBox(
            width: 120, child: _buildStatusBadge(invoice.status))),

        DataCell(SizedBox(
          width: 110,
          child: Text(DateFormat('dd MMM yyyy').format(invoice.dueDate)),
        )),

        DataCell(SizedBox(
          width: 120,
          child: Text(
            '₹${invoice.totalAmount.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
            textAlign: TextAlign.right,
          ),
        )),

        DataCell(SizedBox(
          width: 120,
          child: Text(
            '₹${invoice.amountDue.toStringAsFixed(2)}',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: invoice.amountDue > 0 ? Colors.red[700] : _green),
            textAlign: TextAlign.right,
          ),
        )),

        DataCell(SizedBox(
          width: 80,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onSelected: (value) async {
              switch (value) {
                case 'view':   _viewInvoiceDetails(invoice); break;
                case 'edit':   _openEditInvoice(invoice.id); break;
                case 'send':   await _sendInvoice(invoice); break;
                case 'download': await _downloadInvoicePDF(invoice); break;
                case 'delete': await _deleteInvoice(invoice); break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'view',
                child: ListTile(
                    leading: Icon(Icons.visibility_outlined,
                        size: 17, color: _blue),
                    title: Text('View Details'),
                    contentPadding: EdgeInsets.zero),
              ),
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                    leading: Icon(Icons.edit_outlined, size: 17, color: _navy),
                    title: Text('Edit'),
                    contentPadding: EdgeInsets.zero),
              ),
              const PopupMenuItem(
                value: 'send',
                child: ListTile(
                    leading: Icon(Icons.send_outlined, size: 17, color: _green),
                    title: Text('Send Email'),
                    contentPadding: EdgeInsets.zero),
              ),
              const PopupMenuItem(
                value: 'download',
                child: ListTile(
                    leading: Icon(Icons.download_outlined,
                        size: 17, color: _purple),
                    title: Text('Download PDF'),
                    contentPadding: EdgeInsets.zero),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                    leading: Icon(Icons.delete_outline,
                        size: 17, color: Colors.red),
                    title: Text('Delete',
                        style: TextStyle(color: Colors.red)),
                    contentPadding: EdgeInsets.zero),
              ),
            ],
          ),
        )),
      ],
    );
  }

  // ── Status badge ──────────────────────────────────────────────────────────

  Widget _buildStatusBadge(String status) {
    final Map<String, List<Color>> statusColors = {
      'PAID':           [const Color(0xFFDCFCE7), const Color(0xFF15803D)],
      'DRAFT':          [const Color(0xFFFEF3C7), const Color(0xFFB45309)],
      'SENT':           [const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)],
      'UNPAID':         [const Color(0xFFFFEDD5), const Color(0xFFEA580C)],
      'PARTIALLY_PAID': [const Color(0xFFE0E7FF), const Color(0xFF4338CA)],
      'OVERDUE':        [const Color(0xFFFEE2E2), const Color(0xFFDC2626)],
      'CANCELLED':      [const Color(0xFFF1F5F9), const Color(0xFF64748B)],
    };
    final c = statusColors[status] ??
        [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c[0],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c[1].withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 6, height: 6,
            decoration: BoxDecoration(color: c[1], shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(status.replaceAll('_', ' '),
            style: TextStyle(
                color: c[1],
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.3)),
      ]),
    );
  }

  // ==========================================================================
  //  PAGINATION
  // ==========================================================================

  Widget _buildPagination() {
    List<int> pages;
    if (_totalPages <= 5) {
      pages = List.generate(_totalPages, (i) => i + 1);
    } else {
      final int start = (_currentPage - 2).clamp(1, _totalPages - 4);
      pages = List.generate(5, (i) => start + i);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEF2F7))),
      ),
      child: LayoutBuilder(builder: (_, constraints) {
        return Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: [
            Text(
              'Showing ${(_currentPage - 1) * _itemsPerPage + 1}–'
              '${(_currentPage * _itemsPerPage).clamp(0, _totalInvoices)}'
              ' of $_totalInvoices',
              style: TextStyle(fontSize: 13, color: Colors.grey[600],
                  fontWeight: FontWeight.w500),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _pageNavBtn(
                icon: Icons.chevron_left,
                enabled: _currentPage > 1,
                onTap: () {
                  setState(() => _currentPage--);
                  _loadInvoices();
                },
              ),
              const SizedBox(width: 4),
              if (pages.first > 1) ...[
                _pageNumBtn(1),
                if (pages.first > 2)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text('…',
                        style: TextStyle(color: Colors.grey[400])),
                  ),
              ],
              ...pages.map((p) => _pageNumBtn(p)),
              if (pages.last < _totalPages) ...[
                if (pages.last < _totalPages - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text('…',
                        style: TextStyle(color: Colors.grey[400])),
                  ),
                _pageNumBtn(_totalPages),
              ],
              const SizedBox(width: 4),
              _pageNavBtn(
                icon: Icons.chevron_right,
                enabled: _currentPage < _totalPages,
                onTap: () {
                  setState(() => _currentPage++);
                  _loadInvoices();
                },
              ),
            ]),
          ],
        );
      }),
    );
  }

  Widget _pageNumBtn(int page) {
    final bool isActive = _currentPage == page;
    return GestureDetector(
      onTap: () {
        if (!isActive) {
          setState(() => _currentPage = page);
          _loadInvoices();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: isActive ? _navy : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? _navy : Colors.grey[300]!),
        ),
        child: Center(
          child: Text('$page',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive ? Colors.white : Colors.grey[700])),
        ),
      ),
    );
  }

  Widget _pageNavBtn({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Icon(icon,
            size: 18, color: enabled ? _navy : Colors.grey[300]),
      ),
    );
  }

  // ==========================================================================
  //  EMPTY / ERROR STATES
  // ==========================================================================

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
                color: _navy.withOpacity(0.06), shape: BoxShape.circle),
            child: Icon(Icons.description_outlined,
                size: 64, color: _navy.withOpacity(0.4)),
          ),
          const SizedBox(height: 20),
          const Text('No invoices found',
              style: TextStyle(fontSize: 20,
                  fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty || _selectedStatus != 'All'
                ? 'Try adjusting your filters'
                : 'Create your first invoice to get started',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _openNewInvoice,
            icon: const Icon(Icons.add),
            label: const Text('Create Invoice',
                style: TextStyle(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                  horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: Colors.red[50], shape: BoxShape.circle),
            child: Icon(Icons.error_outline, size: 56, color: Colors.red[400]),
          ),
          const SizedBox(height: 20),
          const Text('Failed to Load Invoices',
              style: TextStyle(fontSize: 20,
                  fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(_errorMessage ?? 'An unknown error occurred',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                textAlign: TextAlign.center),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _refreshData,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again',
                style: TextStyle(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                  horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
// BULK IMPORT DIALOG
// =============================================================================

class _BulkImportInvoicesDialog extends StatefulWidget {
  final VoidCallback onImportComplete;
  const _BulkImportInvoicesDialog({required this.onImportComplete});

  @override
  State<_BulkImportInvoicesDialog> createState() =>
      _BulkImportInvoicesDialogState();
}

class _BulkImportInvoicesDialogState
    extends State<_BulkImportInvoicesDialog> {
  bool _isDownloading = false;
  bool _isUploading   = false;
  String? _uploadedFileName;
  Map<String, dynamic>? _importResults;

  // ── Download template ──────────────────────────────────────────────────────
  Future<void> _downloadTemplate() async {
    setState(() => _isDownloading = true);
    try {
      final List<List<dynamic>> templateData = [
        // Header row
        [
          'Customer Name*',
          'Customer Email*',
          'Invoice Date* (DD/MM/YYYY)',
          'Due Date (DD/MM/YYYY)',
          'Payment Terms',
          'Order Number',
          'Item Details*',
          'Quantity*',
          'Rate*',
          'Discount',
          'Discount Type (percentage/amount)',
          'GST Rate (%)',
          'Notes',
          'Status (DRAFT/SENT/UNPAID/PAID)',
        ],
        // Sample row 1
        [
          'Acme Corp',
          'billing@acme.com',
          '15/01/2026',
          '14/02/2026',
          'Net 30',
          'ORD-001',
          'Fleet Management Services - January',
          '1',
          '25000.00',
          '5',
          'percentage',
          '18',
          'Payment due within 30 days',
          'DRAFT',
        ],
        // Sample row 2
        [
          'TechCorp Solutions',
          'accounts@techcorp.com',
          '20/01/2026',
          '04/02/2026',
          'Net 15',
          'ORD-002',
          'Driver Hire - 10 Days',
          '10',
          '1500.00',
          '0',
          'percentage',
          '18',
          '',
          'SENT',
        ],
        // Instructions
        [
          'INSTRUCTIONS:',
          'Fields marked * are required',
          'Date format: DD/MM/YYYY',
          'Payment Terms: Due on Receipt / Net 15 / Net 30 / Net 45 / Net 60',
          'Status: DRAFT / SENT / UNPAID / PAID',
          'GST Rate: numeric value e.g. 18',
          'Delete this row before importing',
          '', '', '', '', '', '', '',
        ],
      ];

      await ExportHelper.exportToExcel(
        data: templateData,
        filename: 'invoices_import_template',
      );
      setState(() => _isDownloading = false);
      _showSuccess('Template downloaded successfully!');
    } catch (e) {
      setState(() => _isDownloading = false);
      _showError('Failed to download template: $e');
    }
  }

  // ── Upload & import file ───────────────────────────────────────────────────
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
        _uploadedFileName = file.name;
        _isUploading      = true;
        _importResults    = null;
      });

      final apiService = ApiService();
      final headers    = await apiService.getHeaders();

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${apiService.baseUrl}/api/invoices/import/bulk'),
      );

      // Add auth headers (skip Content-Type — multipart sets it automatically)
      headers.forEach((key, value) {
        if (key.toLowerCase() != 'content-type') {
          request.headers[key] = value;
        }
      });

      if (kIsWeb) {
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          file.bytes!,
          filename: file.name,
        ));
      } else {
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          file.path!,
          filename: file.name,
        ));
      }

      final streamed  = await request.send();
      final response  = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        setState(() {
          _isUploading   = false;
          _importResults = responseData['data'];
        });
        _showSuccess('Import completed successfully!');
        widget.onImportComplete();
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Import failed');
      }
    } catch (e) {
      setState(() { _isUploading = false; _uploadedFileName = null; });
      _showError('Failed to import: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 4),
    ));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: _green,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: _purple.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.upload_file_rounded,
                    color: _purple, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text('Bulk Import Invoices',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 20),

            // ── Info box ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: _blue.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _blue.withOpacity(0.3))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info_outline, color: _blue, size: 18),
                    const SizedBox(width: 8),
                    Text('How to Import',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, color: _blue)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Download the sample Excel template\n'
                    '2. Fill in your invoice data (required fields marked *)\n'
                    '3. Save as .xlsx or .csv\n'
                    '4. Upload the completed file below\n'
                    '5. Review import results',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Step 1: Download template ─────────────────────────────────────
            _importStep(
              step: '1',
              color: _blue,
              icon: Icons.download_rounded,
              title: 'Download Template',
              subtitle:
                  'Get the Excel template with required columns and sample data.',
              buttonLabel: 'Download Template',
              isLoading: _isDownloading,
              onPressed: _isDownloading || _isUploading
                  ? null
                  : _downloadTemplate,
            ),
            const SizedBox(height: 14),

            // ── Step 2: Upload file ───────────────────────────────────────────
            _importStep(
              step: '2',
              color: _green,
              icon: Icons.upload_rounded,
              title: 'Upload Filled File',
              subtitle:
                  'Fill the template and upload to import your invoices.',
              buttonLabel: 'Select Excel / CSV File',
              isLoading: _isUploading,
              onPressed: _isDownloading || _isUploading ? null : _uploadFile,
            ),

            // ── Uploaded filename ─────────────────────────────────────────────
            if (_uploadedFileName != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: _green.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _green.withOpacity(0.3))),
                child: Row(children: [
                  Icon(Icons.check_circle, color: _green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_uploadedFileName!,
                        style: TextStyle(
                            color: _green, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ],

            // ── Import results ────────────────────────────────────────────────
            if (_importResults != null) ...[
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
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!)),
                child: Column(children: [
                  _resultRow(
                      'Total Processed',
                      '${(_importResults!['imported'] ?? 0) + (_importResults!['errors'] ?? 0)}',
                      _blue),
                  const SizedBox(height: 8),
                  _resultRow('Successfully Imported',
                      '${_importResults!['imported'] ?? 0}', _green),
                  const SizedBox(height: 8),
                  _resultRow(
                      'Failed', '${_importResults!['errors'] ?? 0}', Colors.red),
                  if (_importResults!['errorDetails'] != null &&
                      (_importResults!['errorDetails'] as List).isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Errors:',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.red)),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: SingleChildScrollView(
                        child: Text(
                          (_importResults!['errorDetails'] as List)
                              .map((e) => 'Row ${e['row']}: ${e['error']}')
                              .join('\n'),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.red),
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _navy,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Close'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _importStep({
    required String step,
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required bool isLoading,
    required VoidCallback? onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Center(
              child: Text(step,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15))),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[600])),
              ]),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: onPressed,
          icon: isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white)))
              : Icon(icon, size: 16),
          label: Text(isLoading ? 'Please wait...' : buttonLabel,
              style: const TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            disabledBackgroundColor: color.withOpacity(0.5),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ]),
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
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12)),
          child: Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// =============================================================================
// INVOICE DETAILS DIALOG  (preserved from original)
// =============================================================================

class InvoiceDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> invoiceData;
  const InvoiceDetailsDialog({Key? key, required this.invoiceData})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final attachments = (invoiceData['attachments'] as List?) ?? [];
    final lineItems   = (invoiceData['lineItems'] as List?) ?? [];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width:  MediaQuery.of(context).size.width  * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              const Icon(Icons.description, color: Color(0xFF3498DB), size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(invoiceData['invoiceNumber'] ?? 'Unknown',
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C3E50))),
                  Text('Invoice Details',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                ]),
              ),
              _statusBadge(invoiceData['status'] ?? 'DRAFT'),
              const SizedBox(width: 12),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const Divider(height: 32),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section('Customer Information', [
                      _row('Customer Name', invoiceData['customerName']),
                      _row('Email', invoiceData['customerEmail']),
                      _row('Phone', invoiceData['customerPhone']),
                      _row('Address', invoiceData['customerAddress']),
                    ]),
                    const SizedBox(height: 24),
                    _section('Invoice Information', [
                      _row('Invoice Number', invoiceData['invoiceNumber']),
                      _row('Invoice Date', _fmtDate(invoiceData['invoiceDate'])),
                      _row('Due Date', _fmtDate(invoiceData['dueDate'])),
                      _row('Payment Terms', invoiceData['paymentTerms']),
                      _row('Reference Number', invoiceData['referenceNumber']),
                    ]),
                    if (lineItems.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _lineItemsSection(lineItems),
                    ],
                    const SizedBox(height: 24),
                    _section('Amount Details', [
                      _row('Subtotal',
                          '₹${invoiceData['subtotal']?.toStringAsFixed(2) ?? '0.00'}'),
                      _row('Tax Amount',
                          '₹${invoiceData['taxAmount']?.toStringAsFixed(2) ?? '0.00'}'),
                      _row('Total Amount',
                          '₹${invoiceData['totalAmount']?.toStringAsFixed(2) ?? '0.00'}',
                          bold: true),
                      if (invoiceData['amountPaid'] != null)
                        _row('Amount Paid',
                            '₹${invoiceData['amountPaid']?.toStringAsFixed(2) ?? '0.00'}'),
                      if (invoiceData['balanceDue'] != null)
                        _row('Balance Due',
                            '₹${invoiceData['balanceDue']?.toStringAsFixed(2) ?? '0.00'}',
                            bold: true),
                    ]),
                    if (invoiceData['notes'] != null &&
                        invoiceData['notes'].toString().isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _section('Notes', [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(invoiceData['notes'].toString(),
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey[800])),
                        ),
                      ]),
                    ],
                    const SizedBox(height: 24),
                    _section('Audit Information', [
                      _row('Created By', invoiceData['createdBy']),
                      _row('Created Date', _fmtDate(invoiceData['createdAt'])),
                      _row('Last Modified', _fmtDate(invoiceData['updatedAt'])),
                    ]),
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
    final Map<String, List<Color>> colors = {
      'PAID':           [const Color(0xFFDCFCE7), const Color(0xFF15803D)],
      'DRAFT':          [const Color(0xFFFEF3C7), const Color(0xFFB45309)],
      'SENT':           [const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)],
      'UNPAID':         [const Color(0xFFFFEDD5), const Color(0xFFEA580C)],
      'PARTIALLY_PAID': [const Color(0xFFE0E7FF), const Color(0xFF4338CA)],
      'OVERDUE':        [const Color(0xFFFEE2E2), const Color(0xFFDC2626)],
    };
    final c = colors[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: c[0], borderRadius: BorderRadius.circular(12)),
      child: Text(status.replaceAll('_', ' '),
          style: TextStyle(
              color: c[1], fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
    ]);
  }

  Widget _row(String label, dynamic value, {bool bold = false}) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 180,
          child: Text(label,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                  color: const Color(0xFF2C3E50),
                  fontSize: 14)),
        ),
        Expanded(
          child: Text(value.toString(),
              style: TextStyle(
                  color: Colors.grey[800],
                  fontSize: 14,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ),
      ]),
    );
  }

  Widget _lineItemsSection(List lineItems) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                Padding(padding: EdgeInsets.all(12),
                    child: Text('Item', style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(padding: EdgeInsets.all(12),
                    child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(padding: EdgeInsets.all(12),
                    child: Text('Rate', style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(padding: EdgeInsets.all(12),
                    child: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            ...lineItems.map<TableRow>((item) => TableRow(children: [
              Padding(padding: const EdgeInsets.all(12),
                  child: Text(item['itemName'] ?? '')),
              Padding(padding: const EdgeInsets.all(12),
                  child: Text(item['quantity']?.toString() ?? '0')),
              Padding(padding: const EdgeInsets.all(12),
                  child: Text('₹${item['rate']?.toStringAsFixed(2) ?? '0.00'}')),
              Padding(padding: const EdgeInsets.all(12),
                  child: Text('₹${item['amount']?.toStringAsFixed(2) ?? '0.00'}')),
            ])),
          ],
        ),
      ),
    ]);
  }

  String _fmtDate(dynamic date) {
    if (date == null) return '';
    try {
      final DateTime dt =
          date is DateTime ? date : DateTime.parse(date.toString());
      return DateFormat('dd MMM yyyy').format(dt);
    } catch (_) {
      return date.toString();
    }
  }
}