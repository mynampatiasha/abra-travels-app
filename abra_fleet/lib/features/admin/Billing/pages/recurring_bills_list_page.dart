// ============================================================================
// RECURRING BILLS LIST PAGE
// ============================================================================
// File: lib/screens/billing/recurring_bills_list_page.dart
// Same UI as recurring_invoices_list_page.dart
// Features: Stats, Filters, Import, Export, View Process, Pause/Resume/Stop
// Fully Responsive: Horizontal scroll table + adaptive cards/buttons
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import '../../../../core/utils/export_helper.dart';
import '../../../../core/services/recurring_bill_service.dart';
import '../app_top_bar.dart';
import 'new_recurring_bill.dart';

class RecurringBillsListPage extends StatefulWidget {
  const RecurringBillsListPage({Key? key}) : super(key: key);

  @override
  State<RecurringBillsListPage> createState() => _RecurringBillsListPageState();
}

class _RecurringBillsListPageState extends State<RecurringBillsListPage> {
  // Data
  List<RecurringBill> _bills = [];
  RecurringBillStats? _stats;
  bool _isLoading = true;
  String? _errorMessage;

  // Status filter
  String _selectedStatus = 'All';
  final List<String> _statusFilters = ['All', 'ACTIVE', 'PAUSED', 'STOPPED'];

  // Advanced date filter
  DateTime? _fromDate;
  DateTime? _toDate;
  String _dateFilterType = 'All';
  DateTime? _particularDate;

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

  // -----------------------------------------------------------------------
  // LOAD DATA
  // -----------------------------------------------------------------------

  Future<void> _loadBills() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      String? fromDateStr;
      String? toDateStr;

      if (_dateFilterType == 'Within Date Range') {
        fromDateStr = _fromDate?.toIso8601String();
        toDateStr = _toDate?.toIso8601String();
      } else if (_dateFilterType == 'Particular Date') {
        fromDateStr = _particularDate?.toIso8601String();
        toDateStr = _particularDate?.toIso8601String();
      } else if (_fromDate != null && _toDate != null) {
        fromDateStr = _fromDate?.toIso8601String();
        toDateStr = _toDate?.toIso8601String();
      }

      final response = await RecurringBillService.getRecurringBills(
        status: _selectedStatus == 'All' ? null : _selectedStatus,
        page: _currentPage,
        limit: _itemsPerPage,
        fromDate: fromDateStr,
        toDate: toDateStr,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
      );
      setState(() {
        _bills = response.recurringBills;
        _totalPages = response.pagination.pages;
        _totalBills = response.pagination.total;
        _isLoading = false;
      });
    } catch (e) {
      setState(() { _errorMessage = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _loadStats() async {
    try {
      final stats = await RecurringBillService.getStats();
      setState(() => _stats = stats);
    } catch (_) {}
  }

  Future<void> _refreshData() async {
    await Future.wait([_loadBills(), _loadStats()]);
    _showSuccess('Data refreshed');
  }

  // -----------------------------------------------------------------------
  // FILTER DIALOG
  // -----------------------------------------------------------------------

  void _showFilterDialog() {
    DateTime? tempFrom = _fromDate;
    DateTime? tempTo = _toDate;
    DateTime? tempParticular = _particularDate;
    String tempType = _dateFilterType;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Filter by Date'),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filter Type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<String>(
                      value: tempType,
                      isExpanded: true,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'All', child: Text('All Dates')),
                        DropdownMenuItem(value: 'Within Date Range', child: Text('Within Date Range')),
                        DropdownMenuItem(value: 'Particular Date', child: Text('Particular Date')),
                        DropdownMenuItem(value: 'Today', child: Text('Today')),
                        DropdownMenuItem(value: 'This Week', child: Text('This Week')),
                        DropdownMenuItem(value: 'This Month', child: Text('This Month')),
                        DropdownMenuItem(value: 'Last Month', child: Text('Last Month')),
                        DropdownMenuItem(value: 'This Year', child: Text('This Year')),
                      ],
                      onChanged: (v) {
                        setDialogState(() {
                          tempType = v ?? 'All';
                          final now = DateTime.now();
                          if (v == 'Today') {
                            tempFrom = now; tempTo = now;
                          } else if (v == 'This Week') {
                            tempFrom = now.subtract(Duration(days: now.weekday - 1));
                            tempTo = now.add(Duration(days: 7 - now.weekday));
                          } else if (v == 'This Month') {
                            tempFrom = DateTime(now.year, now.month, 1);
                            tempTo = DateTime(now.year, now.month + 1, 0);
                          } else if (v == 'Last Month') {
                            tempFrom = DateTime(now.year, now.month - 1, 1);
                            tempTo = DateTime(now.year, now.month, 0);
                          } else if (v == 'This Year') {
                            tempFrom = DateTime(now.year, 1, 1);
                            tempTo = DateTime(now.year, 12, 31);
                          } else if (v == 'All') {
                            tempFrom = null; tempTo = null; tempParticular = null;
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (tempType == 'Within Date Range') ...[
                    _buildDatePickerField(ctx, 'From Date', tempFrom, (d) => setDialogState(() => tempFrom = d)),
                    const SizedBox(height: 16),
                    _buildDatePickerField(ctx, 'To Date', tempTo, (d) => setDialogState(() => tempTo = d)),
                  ],
                  if (tempType == 'Particular Date')
                    _buildDatePickerField(ctx, 'Select Date', tempParticular, (d) => setDialogState(() => tempParticular = d)),
                  if (tempType != 'All' && tempType != 'Within Date Range' && tempType != 'Particular Date' && tempFrom != null && tempTo != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 18, color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'From ${DateFormat('dd/MM/yyyy').format(tempFrom!)} to ${DateFormat('dd/MM/yyyy').format(tempTo!)}',
                              style: const TextStyle(fontSize: 12, color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setDialogState(() {
                  tempFrom = null; tempTo = null; tempParticular = null; tempType = 'All';
                });
              },
              child: const Text('Clear', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _dateFilterType = tempType;
                  _fromDate = tempFrom;
                  _toDate = tempTo;
                  _particularDate = tempParticular;
                  _currentPage = 1;
                });
                Navigator.pop(ctx);
                _loadBills();
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3498DB), foregroundColor: Colors.white),
              child: const Text('Apply Filter'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatePickerField(BuildContext ctx, String label, DateTime? value, Function(DateTime) onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: ctx,
              initialDate: value ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) onPick(picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 20),
                const SizedBox(width: 12),
                Text(
                  value != null ? DateFormat('dd/MM/yyyy').format(value) : 'Select date',
                  style: TextStyle(color: value != null ? Colors.black : Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool get _hasActiveFilters => _dateFilterType != 'All' || _selectedStatus != 'All';

  void _clearAllFilters() {
    setState(() {
      _fromDate = null; _toDate = null; _particularDate = null;
      _dateFilterType = 'All'; _selectedStatus = 'All'; _currentPage = 1;
    });
    _loadBills();
  }

  // -----------------------------------------------------------------------
  // IMPORT DIALOG
  // -----------------------------------------------------------------------

  void _showImportDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _BulkImportDialog(
        onImportComplete: () {
          _refreshData();
          _showSuccess('Import completed successfully!');
        },
      ),
    );
  }

  // -----------------------------------------------------------------------
  // EXPORT
  // -----------------------------------------------------------------------

  Future<void> _exportToExcel() async {
    try {
      _showSuccess('Preparing Excel export...');
      final allBills = await RecurringBillService.getAllForExport(
        status: _selectedStatus == 'All' ? null : _selectedStatus,
      );
      if (allBills.isEmpty) { _showError('No data to export'); return; }

      List<List<dynamic>> data = [
        ['Profile Name', 'Vendor Name', 'Vendor Email', 'Status', 'Repeat Every',
          'Repeat Unit', 'Start Date', 'End Date', 'Next Bill Date',
          'Total Generated', 'Bill Creation Mode', 'Sub Total', 'GST Rate',
          'Total Amount', 'Payment Terms', 'Notes'],
      ];

      for (final b in allBills) {
        data.add([
          b.profileName, b.vendorName, b.vendorEmail, b.status,
          b.repeatEvery.toString(), b.repeatUnit,
          DateFormat('dd/MM/yyyy').format(b.startDate),
          b.endDate != null ? DateFormat('dd/MM/yyyy').format(b.endDate!) : 'Never',
          DateFormat('dd/MM/yyyy').format(b.nextBillDate),
          b.totalBillsGenerated.toString(), b.billCreationMode,
          b.subTotal.toStringAsFixed(2), b.gstRate.toStringAsFixed(2),
          b.totalAmount.toStringAsFixed(2), b.paymentTerms ?? 'Net 30',
          b.notes ?? '',
        ]);
      }

      await ExportHelper.exportToExcel(data: data, filename: 'recurring_bills');
      _showSuccess('✅ Excel downloaded with ${allBills.length} profiles!');
    } catch (e) {
      _showError('Export failed: $e');
    }
  }

  // -----------------------------------------------------------------------
  // ACTIONS
  // -----------------------------------------------------------------------

  Future<void> _pauseBill(RecurringBill bill) async {
    if (bill.status != 'ACTIVE') { _showError('Only active profiles can be paused'); return; }
    try {
      await RecurringBillService.pauseRecurringBill(bill.id);
      _showSuccess('Profile "${bill.profileName}" paused');
      _refreshData();
    } catch (e) { _showError('Failed to pause: $e'); }
  }

  Future<void> _resumeBill(RecurringBill bill) async {
    if (bill.status != 'PAUSED') { _showError('Only paused profiles can be resumed'); return; }
    try {
      await RecurringBillService.resumeRecurringBill(bill.id);
      _showSuccess('Profile "${bill.profileName}" resumed');
      _refreshData();
    } catch (e) { _showError('Failed to resume: $e'); }
  }

  Future<void> _stopBill(RecurringBill bill) async {
    final confirm = await _showConfirm(
      'Stop Recurring Profile',
      'Are you sure you want to permanently stop "${bill.profileName}"?\nThis will prevent any future bills from being generated.',
      'Stop',
      Colors.orange,
    );
    if (confirm == true) {
      try {
        await RecurringBillService.stopRecurringBill(bill.id);
        _showSuccess('Profile stopped');
        _refreshData();
      } catch (e) { _showError('Failed to stop: $e'); }
    }
  }

  Future<void> _deleteBill(RecurringBill bill) async {
    final confirm = await _showConfirm(
      'Delete Profile',
      'Are you sure you want to delete "${bill.profileName}"? This cannot be undone.',
      'Delete',
      Colors.red,
    );
    if (confirm == true) {
      try {
        await RecurringBillService.deleteRecurringBill(bill.id);
        _showSuccess('Profile deleted');
        _refreshData();
      } catch (e) { _showError('Failed to delete: $e'); }
    }
  }

  Future<void> _generateManualBill(RecurringBill bill) async {
    final confirm = await _showConfirm(
      'Generate Bill',
      'Generate a new bill from profile "${bill.profileName}"?',
      'Generate',
      const Color(0xFF3498DB),
    );
    if (confirm == true) {
      try {
        final result = await RecurringBillService.generateManualBill(bill.id);
        _showSuccess('Bill ${result.billNumber} generated successfully');
        _refreshData();
      } catch (e) { _showError('Failed to generate bill: $e'); }
    }
  }

  Future<void> _viewChildBills(RecurringBill bill) async {
    try {
      final response = await RecurringBillService.getChildBills(bill.id);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Child Bills — ${bill.profileName}'),
          content: SizedBox(
            width: 600,
            height: 400,
            child: response.bills.isEmpty
                ? const Center(child: Text('No bills generated yet'))
                : ListView.builder(
                    itemCount: response.bills.length,
                    itemBuilder: (_, i) {
                      final b = response.bills[i];
                      return ListTile(
                        leading: Icon(Icons.description,
                            color: _getBillStatusColor(b.status)),
                        title: Text(b.billNumber),
                        subtitle: Text(
                          'Date: ${DateFormat('dd/MM/yyyy').format(b.billDate)} | Amount: ₹${b.totalAmount.toStringAsFixed(2)}'),
                        trailing: _buildStatusBadge(b.status),
                      );
                    },
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    } catch (e) { _showError('Failed to load child bills: $e'); }
  }

  void _showProcessDialog() {
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
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        color: const Color(0xFF3498DB),
                        child: const Text(
                          'Recurring Bill Lifecycle Process',
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        child: InteractiveViewer(
                          panEnabled: true,
                          minScale: 0.5,
                          maxScale: 4.0,
                          child: Center(
                            child: Image.asset(
                              'assets/recurring_bill.dart.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.broken_image_outlined, size: 80, color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  Text('Image not found', style: TextStyle(fontSize: 18, color: Colors.grey[700])),
                                  const SizedBox(height: 8),
                                  Text('Place "recurring_bill.dart.png" in assets folder',
                                      style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                                ],
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
              top: 40,
              right: 40,
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

  Future<bool?> _showConfirm(String title, String content, String confirmLabel, Color confirmColor) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor, foregroundColor: Colors.white),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // HELPERS
  // -----------------------------------------------------------------------

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'ACTIVE': return Colors.green;
      case 'PAUSED': return Colors.orange;
      case 'STOPPED': return Colors.red;
      default: return Colors.blue;
    }
  }

  Color _getBillStatusColor(String status) {
    switch (status) {
      case 'PAID': return Colors.green;
      case 'OPEN': return Colors.orange;
      case 'OVERDUE': return Colors.red;
      case 'VOID': return Colors.grey;
      default: return Colors.blue;
    }
  }

  Widget _buildStatusBadge(String status) {
    Color bg, fg;
    switch (status) {
      case 'ACTIVE': bg = Colors.green[100]!; fg = Colors.green[800]!; break;
      case 'PAUSED': bg = Colors.orange[100]!; fg = Colors.orange[800]!; break;
      case 'STOPPED': bg = Colors.red[100]!; fg = Colors.red[800]!; break;
      case 'PAID': bg = Colors.green[100]!; fg = Colors.green[800]!; break;
      case 'OPEN': bg = Colors.orange[100]!; fg = Colors.orange[800]!; break;
      case 'OVERDUE': bg = Colors.red[100]!; fg = Colors.red[800]!; break;
      default: bg = Colors.blue[100]!; fg = Colors.blue[800]!;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(status, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }

  // -----------------------------------------------------------------------
  // BUILD
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Recurring Bills'),
      backgroundColor: Colors.grey[50],
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildTopBar(),
            if (_stats != null) _buildStatsCards(),
            _isLoading
                ? const SizedBox(height: 400, child: Center(child: CircularProgressIndicator()))
                : _errorMessage != null
                    ? SizedBox(height: 400, child: _buildErrorState())
                    : _bills.isEmpty
                        ? SizedBox(height: 400, child: _buildEmptyState())
                        : _buildTable(),
            if (!_isLoading && _bills.isNotEmpty) _buildPagination(),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // TOP BAR
  // -----------------------------------------------------------------------

  Widget _buildTopBar() {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;
      return Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: isWide ? _buildWideTopBar() : _buildNarrowTopBar(),
      );
    });
  }

  Widget _buildWideTopBar() {
    return Row(
      children: [
        // Status Filter
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<String>(
            value: _selectedStatus,
            underline: const SizedBox(),
            icon: const Icon(Icons.arrow_drop_down),
            items: _statusFilters.map((s) => DropdownMenuItem(
              value: s,
              child: Text(s == 'All' ? 'All Profiles' : s,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            )).toList(),
            onChanged: (v) { if (v != null) { setState(() { _selectedStatus = v; _currentPage = 1; }); _loadBills(); } },
          ),
        ),
        const Spacer(),
        // Search
        SizedBox(
          width: 260,
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search profiles...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (v) {
              setState(() => _searchQuery = v.toLowerCase());
              _loadBills();
            },
          ),
        ),
        const SizedBox(width: 8),
        // Filter
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.filter_list, size: 22),
              onPressed: _showFilterDialog,
              tooltip: 'Filter',
              style: IconButton.styleFrom(
                backgroundColor: _hasActiveFilters
                    ? const Color(0xFF3498DB).withOpacity(0.15)
                    : Colors.grey[200],
                padding: const EdgeInsets.all(10),
              ),
            ),
            if (_hasActiveFilters)
              Positioned(
                right: 8, top: 8,
                child: Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(color: Color(0xFF3498DB), shape: BoxShape.circle)),
              ),
          ],
        ),
        if (_hasActiveFilters) ...[
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: _clearAllFilters,
            icon: const Icon(Icons.clear, size: 16),
            label: const Text('Clear'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
        const SizedBox(width: 4),
        // Refresh
        IconButton(
          icon: const Icon(Icons.refresh, size: 22),
          onPressed: _isLoading ? null : _refreshData,
          tooltip: 'Refresh',
          style: IconButton.styleFrom(backgroundColor: Colors.grey[200], padding: const EdgeInsets.all(10)),
        ),
        const SizedBox(width: 8),
        // View Process
        IconButton(
          icon: const Icon(Icons.account_tree, size: 22, color: Color(0xFF3498DB)),
          onPressed: _showProcessDialog,
          tooltip: 'View Recurring Bill Process',
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF3498DB).withOpacity(0.1),
            padding: const EdgeInsets.all(10),
          ),
        ),
        const SizedBox(width: 8),
        // Import
        ElevatedButton.icon(
          onPressed: _showImportDialog,
          icon: const Icon(Icons.upload_file, size: 18),
          label: const Text('Import'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF9B59B6),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(width: 8),
        // Export
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _exportToExcel,
          icon: const Icon(Icons.file_download, size: 18),
          label: const Text('Export'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF27AE60),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(width: 8),
        // New
        ElevatedButton.icon(
          onPressed: () async {
            final result = await Navigator.push(context,
                MaterialPageRoute(builder: (_) => const NewRecurringBillScreen()));
            if (result == true) _refreshData();
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New Recurring Bill'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3498DB),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowTopBar() {
    return Column(
      children: [
        // Row 1: Search + Filter + Refresh
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search profiles...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  isDense: true,
                ),
                onChanged: (v) { setState(() => _searchQuery = v); _loadBills(); },
              ),
            ),
            const SizedBox(width: 8),
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.filter_list, size: 20),
                  onPressed: _showFilterDialog,
                  style: IconButton.styleFrom(
                    backgroundColor: _hasActiveFilters ? const Color(0xFF3498DB).withOpacity(0.15) : Colors.grey[200],
                    padding: const EdgeInsets.all(8),
                  ),
                ),
                if (_hasActiveFilters)
                  Positioned(
                    right: 6, top: 6,
                    child: Container(width: 7, height: 7,
                        decoration: const BoxDecoration(color: Color(0xFF3498DB), shape: BoxShape.circle)),
                  ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: _isLoading ? null : _refreshData,
              style: IconButton.styleFrom(backgroundColor: Colors.grey[200], padding: const EdgeInsets.all(8)),
            ),
            IconButton(
              icon: const Icon(Icons.account_tree, size: 20, color: Color(0xFF3498DB)),
              onPressed: _showProcessDialog,
              style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF3498DB).withOpacity(0.1), padding: const EdgeInsets.all(8)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Row 2: Status dropdown
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<String>(
            value: _selectedStatus,
            isExpanded: true,
            underline: const SizedBox(),
            items: _statusFilters.map((s) => DropdownMenuItem(
              value: s,
              child: Text(s == 'All' ? 'All Profiles' : s),
            )).toList(),
            onChanged: (v) { if (v != null) { setState(() { _selectedStatus = v; _currentPage = 1; }); _loadBills(); } },
          ),
        ),
        const SizedBox(height: 8),
        // Row 3: Action buttons
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: _showImportDialog,
              icon: const Icon(Icons.upload_file, size: 16),
              label: const Text('Import'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9B59B6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _exportToExcel,
              icon: const Icon(Icons.file_download, size: 16),
              label: const Text('Export'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF27AE60),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const NewRecurringBillScreen()));
                if (result == true) _refreshData();
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3498DB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // STATS CARDS
  // -----------------------------------------------------------------------

  Widget _buildStatsCards() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: LayoutBuilder(builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        final cards = [
          _statCard('Total Profiles', _stats!.totalProfiles.toString(), Icons.repeat, Colors.blue),
          _statCard('Active', _stats!.activeProfiles.toString(), Icons.check_circle, Colors.green),
          _statCard('Paused', _stats!.pausedProfiles.toString(), Icons.pause_circle, Colors.orange),
          _statCard('Stopped', _stats!.stoppedProfiles.toString(), Icons.stop_circle, Colors.red),
          _statCard('Total Generated', _stats!.totalBillsGenerated.toString(), Icons.description, Colors.purple),
        ];

        if (isWide) {
          return Row(
            children: cards.expand((c) => [Expanded(child: c), const SizedBox(width: 12)]).toList()
              ..removeLast(),
          );
        } else {
          final cardWidth = (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: cards.map((c) => SizedBox(width: cardWidth, child: c)).toList(),
          );
        }
      }),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
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
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // TABLE
  // -----------------------------------------------------------------------

  Widget _buildTable() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        return Scrollbar(
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 8,
          radius: const Radius.circular(4),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFF0D47A1)),
                  headingTextStyle: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.3),
                  headingRowHeight: 54,
                  dataRowMinHeight: 60,
                  dataRowMaxHeight: 72,
                  dataTextStyle: const TextStyle(fontSize: 13),
                  dataRowColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.hovered)) return Colors.blue.shade50;
                    return null;
                  }),
                  dividerThickness: 1,
                  columnSpacing: 20,
                  horizontalMargin: 16,
                  columns: [
                    DataColumn(
                      label: SizedBox(
                        width: 40,
                        child: Checkbox(
                          value: _selectAll,
                          onChanged: (v) {
                            setState(() {
                              _selectAll = v ?? false;
                              if (_selectAll) {
                                _selectedBills.addAll(_bills.map((b) => b.id));
                              } else {
                                _selectedBills.clear();
                              }
                            });
                          },
                          fillColor: WidgetStateProperty.all(Colors.white),
                          checkColor: const Color(0xFF0D47A1),
                        ),
                      ),
                    ),
                    const DataColumn(label: SizedBox(width: 180, child: Text('Profile Name', overflow: TextOverflow.ellipsis))),
                    const DataColumn(label: SizedBox(width: 160, child: Text('Vendor', overflow: TextOverflow.ellipsis))),
                    const DataColumn(label: SizedBox(width: 120, child: Text('Frequency', overflow: TextOverflow.ellipsis))),
                    const DataColumn(label: SizedBox(width: 120, child: Text('Next Bill Date', overflow: TextOverflow.ellipsis))),
                    const DataColumn(label: SizedBox(width: 100, child: Text('Status', overflow: TextOverflow.ellipsis))),
                    const DataColumn(label: SizedBox(width: 90, child: Text('Generated', overflow: TextOverflow.ellipsis))),
                    const DataColumn(label: SizedBox(width: 110, child: Text('Amount', overflow: TextOverflow.ellipsis))),
                    const DataColumn(label: SizedBox(width: 80, child: Text('Actions', overflow: TextOverflow.ellipsis))),
                  ],
                  rows: _bills.map((bill) => _buildRow(bill)).toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildRow(RecurringBill bill) {
    final isSelected = _selectedBills.contains(bill.id);
    final frequency = '${bill.repeatEvery} ${bill.repeatUnit}(s)';

    return DataRow(
      selected: isSelected,
      color: WidgetStateProperty.resolveWith((states) {
        if (isSelected) return Colors.blue.shade50;
        if (states.contains(WidgetState.hovered)) return Colors.blue.shade50;
        return null;
      }),
      cells: [
        DataCell(Checkbox(
          value: isSelected,
          onChanged: (_) {
            setState(() {
              if (isSelected) { _selectedBills.remove(bill.id); _selectAll = false; }
              else { _selectedBills.add(bill.id); if (_selectedBills.length == _bills.length) _selectAll = true; }
            });
          },
        )),
        // Profile Name
        DataCell(SizedBox(
          width: 180,
          child: InkWell(
            onTap: () async {
              final result = await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => NewRecurringBillScreen(recurringBillId: bill.id)));
              if (result == true) _refreshData();
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(bill.profileName,
                    style: const TextStyle(
                        color: Color(0xFF3498DB), fontWeight: FontWeight.w600, fontSize: 13,
                        decoration: TextDecoration.underline),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  bill.billCreationMode == 'auto_save' ? '🚀 Auto Save' : '📝 Save as Draft',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        )),
        // Vendor
        DataCell(SizedBox(
          width: 160,
          child: Text(bill.vendorName, overflow: TextOverflow.ellipsis),
        )),
        // Frequency
        DataCell(SizedBox(width: 120, child: Text(frequency))),
        // Next Bill Date
        DataCell(SizedBox(
          width: 120,
          child: Text(DateFormat('dd MMM yyyy').format(bill.nextBillDate),
              style: const TextStyle(fontWeight: FontWeight.w500)),
        )),
        // Status
        DataCell(SizedBox(width: 100, child: _buildStatusBadge(bill.status))),
        // Generated
        DataCell(SizedBox(
          width: 90,
          child: InkWell(
            onTap: () => _viewChildBills(bill),
            child: Text(bill.totalBillsGenerated.toString(),
                style: const TextStyle(
                    color: Color(0xFF3498DB), fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline),
                textAlign: TextAlign.center),
          ),
        )),
        // Amount
        DataCell(SizedBox(
          width: 110,
          child: Text('₹${bill.totalAmount.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.right),
        )),
        // Actions
        DataCell(SizedBox(
          width: 80,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (v) async {
              switch (v) {
                case 'edit': {
                  final result = await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => NewRecurringBillScreen(recurringBillId: bill.id)));
                  if (result == true) _refreshData();
                  break;
                }
                case 'generate': await _generateManualBill(bill); break;
                case 'child': await _viewChildBills(bill); break;
                case 'pause': await _pauseBill(bill); break;
                case 'resume': await _resumeBill(bill); break;
                case 'stop': await _stopBill(bill); break;
                case 'delete': await _deleteBill(bill); break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit, size: 18), title: Text('Edit'), contentPadding: EdgeInsets.zero)),
              const PopupMenuItem(value: 'generate', child: ListTile(leading: Icon(Icons.add_circle, size: 18), title: Text('Generate Bill'), contentPadding: EdgeInsets.zero)),
              const PopupMenuItem(value: 'child', child: ListTile(leading: Icon(Icons.list, size: 18), title: Text('View Child Bills'), contentPadding: EdgeInsets.zero)),
              if (bill.status == 'ACTIVE')
                const PopupMenuItem(value: 'pause', child: ListTile(leading: Icon(Icons.pause, size: 18), title: Text('Pause'), contentPadding: EdgeInsets.zero)),
              if (bill.status == 'PAUSED')
                const PopupMenuItem(value: 'resume', child: ListTile(leading: Icon(Icons.play_arrow, size: 18), title: Text('Resume'), contentPadding: EdgeInsets.zero)),
              const PopupMenuItem(value: 'stop', child: ListTile(leading: Icon(Icons.stop, size: 18, color: Colors.orange), title: Text('Stop', style: TextStyle(color: Colors.orange)), contentPadding: EdgeInsets.zero)),
              const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, size: 18, color: Colors.red), title: Text('Delete', style: TextStyle(color: Colors.red)), contentPadding: EdgeInsets.zero)),
            ],
          ),
        )),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // PAGINATION
  // -----------------------------------------------------------------------

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: Colors.white,
      child: LayoutBuilder(builder: (context, constraints) {
        final isWide = constraints.maxWidth > 500;
        return isWide
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Showing ${(_currentPage - 1) * _itemsPerPage + 1}–${(_currentPage * _itemsPerPage).clamp(0, _totalBills)} of $_totalBills',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  _buildPageControls(),
                ],
              )
            : Column(
                children: [
                  Text('Showing ${(_currentPage - 1) * _itemsPerPage + 1}–${(_currentPage * _itemsPerPage).clamp(0, _totalBills)} of $_totalBills',
                      style: TextStyle(color: Colors.grey[700])),
                  const SizedBox(height: 8),
                  _buildPageControls(),
                ],
              );
      }),
    );
  }

  Widget _buildPageControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: _currentPage > 1 ? () { setState(() => _currentPage--); _loadBills(); } : null,
        ),
        ...List.generate(_totalPages.clamp(0, 5), (i) {
          final pageNum = i + 1;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              onTap: () { setState(() => _currentPage = pageNum); _loadBills(); },
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: _currentPage == pageNum ? const Color(0xFF3498DB) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text('$pageNum',
                    style: TextStyle(
                      color: _currentPage == pageNum ? Colors.white : Colors.grey[700],
                      fontWeight: _currentPage == pageNum ? FontWeight.bold : FontWeight.normal,
                    )),
              ),
            ),
          );
        }),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _currentPage < _totalPages ? () { setState(() => _currentPage++); _loadBills(); } : null,
        ),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // EMPTY / ERROR STATES
  // -----------------------------------------------------------------------

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('No recurring bill profiles found',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[700])),
          const SizedBox(height: 8),
          Text('Create your first profile to automate bills',
              style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              final result = await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const NewRecurringBillScreen()));
              if (result == true) _refreshData();
            },
            icon: const Icon(Icons.add),
            label: const Text('Create Recurring Bill'),
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

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text('Error Loading Data',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[700])),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_errorMessage ?? 'Unknown error',
                style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _refreshData,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB), foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// BULK IMPORT DIALOG
// ============================================================================

class _BulkImportDialog extends StatefulWidget {
  final VoidCallback onImportComplete;
  const _BulkImportDialog({required this.onImportComplete});

  @override
  State<_BulkImportDialog> createState() => _BulkImportDialogState();
}

class _BulkImportDialogState extends State<_BulkImportDialog> {
  bool _isDownloading = false;
  bool _isUploading = false;
  String? _uploadedFileName;
  Map<String, dynamic>? _importResults;

  // Download sample template
  Future<void> _downloadTemplate() async {
    setState(() => _isDownloading = true);
    try {
      final data = [
        // Headers
        ['Profile Name*', 'Vendor Name*', 'Vendor Email', 'Repeat Every*', 'Repeat Unit*',
          'Start Date* (YYYY-MM-DD)', 'End Date (YYYY-MM-DD)', 'Bill Creation Mode',
          'Payment Terms', 'Item Description*', 'Quantity*', 'Rate*', 'GST Rate (%)', 'Notes'],
        // Sample Row 1
        ['Monthly Office Rent', 'ABC Vendor', 'abc@vendor.com', '1', 'months',
          '2024-01-01', '', 'save_as_draft', 'Net 30',
          'Office Space Rental', '1', '25000', '18', 'Monthly rent payment'],
        // Sample Row 2
        ['Weekly Supplies', 'XYZ Supplier', 'xyz@supplier.com', '1', 'weeks',
          '2024-01-01', '2024-12-31', 'auto_save', 'Net 15',
          'Office Supplies', '5', '500', '5', 'Weekly supplies'],
        // Instructions
        ['--- INSTRUCTIONS ---', 'Fields with * are required', '', '',
          'Repeat Unit: days / weeks / months / years', '', '', '', '',
          'Bill Creation Mode: save_as_draft OR auto_save', '', '', '', 'DELETE THIS ROW BEFORE UPLOADING'],
      ];

      await ExportHelper.exportToExcel(data: data, filename: 'recurring_bills_import_template');
      setState(() => _isDownloading = false);
      _showSuccess('Template downloaded successfully!');
    } catch (e) {
      setState(() => _isDownloading = false);
      _showError('Failed to download template: $e');
    }
  }

  // Upload and import file
  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        allowMultiple: false,
        withData: true,
        withReadStream: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      setState(() { _uploadedFileName = file.name; _isUploading = true; _importResults = null; });

      final bytes = file.bytes;
      if (bytes == null) throw Exception('Failed to read file. Please try again.');

      List<List<dynamic>> rows;
      final ext = file.extension?.toLowerCase() ?? '';
      if (ext == 'csv') {
        rows = _parseCSV(bytes);
      } else if (ext == 'xlsx' || ext == 'xls') {
        rows = _parseExcel(bytes);
      } else {
        throw Exception('Unsupported format. Use .xlsx, .xls, or .csv');
      }

      if (rows.length < 2) throw Exception('File must have a header row and at least one data row');

      // Parse rows into bill objects
      final billsToImport = <Map<String, dynamic>>[];
      final errors = <String>[];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        // Skip empty rows and instruction rows
        if (row.isEmpty || _str(row, 0).isEmpty || _str(row, 0).startsWith('---')) continue;

        try {
          final profileName = _str(row, 0);
          final vendorName = _str(row, 1);
          final repeatEvery = int.tryParse(_str(row, 3));
          final repeatUnit = _str(row, 4);
          final startDate = _str(row, 5);

          if (profileName.isEmpty) throw Exception('Profile Name is required');
          if (vendorName.isEmpty) throw Exception('Vendor Name is required');
          if (repeatEvery == null || repeatEvery <= 0) throw Exception('Repeat Every must be a positive number');
          if (!['days', 'weeks', 'months', 'years'].contains(repeatUnit)) {
            throw Exception('Repeat Unit must be: days, weeks, months, or years');
          }
          if (startDate.isEmpty) throw Exception('Start Date is required');

          // Validate start date
          DateTime.parse(startDate);

          final itemDesc = _str(row, 9);
          final qty = double.tryParse(_str(row, 10)) ?? 0;
          final rate = double.tryParse(_str(row, 11)) ?? 0;

          if (itemDesc.isEmpty) throw Exception('Item Description is required');
          if (qty <= 0) throw Exception('Quantity must be greater than 0');
          if (rate <= 0) throw Exception('Rate must be greater than 0');

          final gstRate = double.tryParse(_str(row, 12)) ?? 18.0;
          final amount = qty * rate;
          final gstAmount = amount * gstRate / 100;

          billsToImport.add({
            'profileName': profileName,
            'vendorId': 'imported_${vendorName.toLowerCase().replaceAll(' ', '_')}',
            'vendorName': vendorName,
            'vendorEmail': _str(row, 2),
            'repeatEvery': repeatEvery,
            'repeatUnit': repeatUnit,
            'startDate': startDate,
            'endDate': _str(row, 6).isNotEmpty ? _str(row, 6) : null,
            'billCreationMode': _str(row, 7).isNotEmpty ? _str(row, 7) : 'save_as_draft',
            'paymentTerms': _str(row, 8).isNotEmpty ? _str(row, 8) : 'Net 30',
            'items': [{
              'itemDetails': itemDesc,
              'quantity': qty,
              'rate': rate,
              'discount': 0,
              'discountType': 'percentage',
              'amount': amount,
            }],
            'gstRate': gstRate,
            'notes': _str(row, 13),
          });
        } catch (e) {
          errors.add('Row ${i + 1}: ${e.toString()}');
        }
      }

      if (billsToImport.isEmpty) {
        throw Exception('No valid data found. Please check file format and required fields.');
      }

      // Show confirmation
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Confirm Import'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${billsToImport.length} profile(s) ready to import.',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                if (errors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('${errors.length} row(s) skipped:',
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.red[50], borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[200]!)),
                    child: SingleChildScrollView(
                        child: Text(errors.join('\n'), style: const TextStyle(fontSize: 12, color: Colors.red))),
                  ),
                ],
                const SizedBox(height: 12),
                const Text('Do you want to proceed?'),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3498DB)),
              child: const Text('Import', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        setState(() { _isUploading = false; _uploadedFileName = null; });
        return;
      }

      // Call API
      final importResult = await RecurringBillService.bulkImportRecurringBills(billsToImport);

      setState(() {
        _isUploading = false;
        _importResults = {
          'success': importResult['data']['successCount'],
          'failed': importResult['data']['failedCount'],
          'total': importResult['data']['totalProcessed'],
          'errors': importResult['data']['errors'] ?? [],
        };
      });

      if ((importResult['data']['successCount'] ?? 0) > 0) {
        widget.onImportComplete();
      }
    } catch (e) {
      setState(() { _isUploading = false; _uploadedFileName = null; });
      _showError('Import failed: ${e.toString()}');
    }
  }

  String _str(List<dynamic> row, int index, [String def = '']) {
    if (index >= row.length || row[index] == null) return def;
    return row[index].toString().trim();
  }

  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    final ex = excel_pkg.Excel.decodeBytes(bytes);
    final sheet = ex.tables.keys.first;
    final rows = ex.tables[sheet]?.rows ?? [];
    return rows.map((row) => row.map((cell) {
      if (cell?.value == null) return '';
      if (cell!.value is excel_pkg.TextCellValue) return (cell.value as excel_pkg.TextCellValue).value;
      return cell.value;
    }).toList()).toList();
  }

  List<List<dynamic>> _parseCSV(Uint8List bytes) {
    final str = utf8.decode(bytes, allowMalformed: true);
    final lines = str.split(RegExp(r'\r?\n'));
    return lines
        .where((l) => l.trim().isNotEmpty)
        .map((line) {
          final fields = <String>[];
          final buffer = StringBuffer();
          bool inQ = false;
          for (int i = 0; i < line.length; i++) {
            final c = line[i];
            if (c == '"') {
              if (inQ && i + 1 < line.length && line[i + 1] == '"') { buffer.write('"'); i++; }
              else { inQ = !inQ; }
            } else if (c == ',' && !inQ) {
              fields.add(buffer.toString().trim());
              buffer.clear();
            } else {
              buffer.write(c);
            }
          }
          fields.add(buffer.toString().trim());
          return fields.map((f) => f.startsWith('"') && f.endsWith('"')
              ? f.substring(1, f.length - 1) : f).toList();
        })
        .toList();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 580,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.upload_file, color: Color(0xFF9B59B6), size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Bulk Import Recurring Bills',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const Divider(height: 28),

              // Instructions
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
                    Row(children: [
                      Icon(Icons.info_outline, color: Colors.blue[700], size: 18),
                      const SizedBox(width: 8),
                      Text('How to Import', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue[700])),
                    ]),
                    const SizedBox(height: 8),
                    const Text('1. Download the sample template below\n'
                        '2. Fill in your recurring bill data\n'
                        '3. Delete the instructions row before uploading\n'
                        '4. Upload the completed .xlsx or .csv file',
                        style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Download template
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isDownloading || _isUploading ? null : _downloadTemplate,
                  icon: _isDownloading
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download),
                  label: Text(_isDownloading ? 'Downloading...' : 'Download Sample Template'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3498DB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Upload file
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isDownloading || _isUploading ? null : _uploadFile,
                  icon: _isUploading
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF9B59B6)))
                      : const Icon(Icons.upload_file),
                  label: Text(_isUploading ? 'Processing...' : 'Upload Excel / CSV File'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF9B59B6),
                    side: const BorderSide(color: Color(0xFF9B59B6)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),

              if (_uploadedFileName != null && !_isUploading) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
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
                        child: Text(_uploadedFileName!,
                            style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ],

              // Import results
              if (_importResults != null) ...[
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                const Text('Import Results',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
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
                      _resultRow('Total Processed', '${_importResults!['total']}', Colors.blue),
                      const SizedBox(height: 6),
                      _resultRow('Successfully Imported', '${_importResults!['success']}', Colors.green),
                      const SizedBox(height: 6),
                      _resultRow('Failed', '${_importResults!['failed']}', Colors.red),
                      if ((_importResults!['errors'] as List).isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('Errors:', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 130),
                          child: SingleChildScrollView(
                            child: Text(
                              (_importResults!['errors'] as List).join('\n'),
                              style: const TextStyle(fontSize: 12, color: Colors.red),
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
                      backgroundColor: const Color(0xFF3498DB), foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ],
          ),
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
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}