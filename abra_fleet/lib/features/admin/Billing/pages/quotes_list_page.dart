// ============================================================================
// QUOTES LIST PAGE - Complete Implementation with Import, Export & PDF Download
// ============================================================================
// File: lib/screens/billing/quotes_list_page.dart
// Features: Filter, Search, Bulk Import, Excel Export, PDF Download, Convert to Invoice/SO
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
import '../../../../core/services/quote_service.dart';
import '../app_top_bar.dart';
import 'new_quote.dart';

class QuotesListPage extends StatefulWidget {
  const QuotesListPage({Key? key}) : super(key: key);

  @override
  State<QuotesListPage> createState() => _QuotesListPageState();
}

class _QuotesListPageState extends State<QuotesListPage> {
  // Data
  List<Quote> _quotes = [];
  QuoteStats? _stats;
  bool _isLoading = true;
  String? _errorMessage;
  
  // Filters
  String _selectedStatus = 'All';
  final List<String> _statusFilters = [
    'All',
    'DRAFT',
    'SENT',
    'ACCEPTED',
    'DECLINED',
    'EXPIRED',
    'CONVERTED',
  ];
  
  // Date Range Filter
  DateTime? _fromDate;
  DateTime? _toDate;
  
  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalQuotes = 0;
  final int _itemsPerPage = 20;
  
  // Selection
  final Set<String> _selectedQuotes = {};
  bool _selectAll = false;
  
  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadQuotes();
    _loadStats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadQuotes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await QuoteService.getQuotes(
        status: _selectedStatus == 'All' ? null : _selectedStatus,
        page: _currentPage,
        limit: _itemsPerPage,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        fromDate: _fromDate,
        toDate: _toDate,
      );

      setState(() {
        _quotes = response.quotes;
        _totalPages = response.pagination.pages;
        _totalQuotes = response.pagination.total;
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
      final stats = await QuoteService.getStats();
      setState(() {
        _stats = stats;
      });
    } catch (e) {
      print('Error loading stats: $e');
    }
  }

  Future<void> _refreshData() async {
    await Future.wait([
      _loadQuotes(),
      _loadStats(),
    ]);
    _showSuccessSnackbar('Data refreshed successfully');
  }

  void _filterByStatus(String status) {
    setState(() {
      _selectedStatus = status;
      _currentPage = 1;
    });
    _loadQuotes();
  }

  void _toggleSelection(String quoteId) {
    setState(() {
      if (_selectedQuotes.contains(quoteId)) {
        _selectedQuotes.remove(quoteId);
      } else {
        _selectedQuotes.add(quoteId);
      }
      _selectAll = _selectedQuotes.length == _quotes.length;
    });
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        _selectedQuotes.addAll(_quotes.map((q) => q.id));
      } else {
        _selectedQuotes.clear();
      }
    });
  }

  void _openNewQuote() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NewQuoteScreen()),
    );

    if (result == true) {
      _refreshData();
    }
  }

  void _openEditQuote(String quoteId) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => NewQuoteScreen(quoteId: quoteId)),
    );

    if (result == true) {
      _refreshData();
    }
  }

  Future<void> _viewQuoteDetails(Quote quote) async {
    setState(() => _isLoading = true);
    
    try {
      final fullQuote = await QuoteService.getQuote(quote.id);
      setState(() => _isLoading = false);
      
      showDialog(
        context: context,
        builder: (context) => QuoteDetailsDialog(quote: fullQuote),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Failed to load quote details: ${e.toString()}');
    }
  }

  Future<void> _deleteQuote(Quote quote) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Quote'),
        content: Text('Are you sure you want to delete quote ${quote.quoteNumber}?'),
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
        await QuoteService.deleteQuote(quote.id);
        _showSuccessSnackbar('Quote deleted successfully');
        _refreshData();
      } catch (e) {
        _showErrorSnackbar('Failed to delete quote: $e');
      }
    }
  }

  Future<void> _sendQuote(Quote quote) async {
    try {
      await QuoteService.sendQuote(quote.id);
      _showSuccessSnackbar('Quote sent to ${quote.customerEmail}');
      _refreshData();
    } catch (e) {
      _showErrorSnackbar('Failed to send quote: $e');
    }
  }

  Future<void> _downloadQuotePDF(Quote quote) async {
    try {
      _showSuccessSnackbar('Preparing PDF download...');
      
      final pdfUrl = await QuoteService.downloadPDF(quote.id);
      
      if (kIsWeb) {
        html.AnchorElement(href: pdfUrl)
          ..setAttribute('download', '${quote.quoteNumber}.pdf')
          ..setAttribute('target', '_blank')
          ..click();
        
        _showSuccessSnackbar('✅ PDF download started for ${quote.quoteNumber}');
      } else {
        final uri = Uri.parse(pdfUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          _showSuccessSnackbar('✅ PDF opened for ${quote.quoteNumber}');
        } else {
          throw 'Could not launch PDF viewer';
        }
      }
    } catch (e) {
      print('PDF Download Error: $e');
      _showErrorSnackbar('Failed to download PDF: $e');
    }
  }

  Future<void> _convertToInvoice(Quote quote) async {
    // ✅ Check if quote is already converted
    if (quote.status == 'CONVERTED') {
      _showErrorSnackbar('This quote has already been converted. Please refresh the page.');
      return;
    }

    // ✅ Check if quote status is valid for conversion
    if (quote.status != 'ACCEPTED' && quote.status != 'SENT') {
      _showErrorSnackbar('Only ACCEPTED or SENT quotes can be converted to invoices. Current status: ${quote.status}');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Convert to Invoice'),
        content: Text('Convert quote ${quote.quoteNumber} to an invoice?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF27AE60)),
            child: const Text('Convert'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await QuoteService.convertToInvoice(quote.id);
        _showSuccessSnackbar('Quote converted to invoice successfully');
        _refreshData();
        
        // ✅ Navigate to Invoices List Page after successful conversion
        if (mounted) {
          // Navigate to invoices list page
          Navigator.pushReplacementNamed(context, '/admin/billing/invoices');
        }
      } catch (e) {
        _showErrorSnackbar('Failed to convert to invoice: $e');
      }
    }
  }

  Future<void> _convertToSalesOrder(Quote quote) async {
    // ✅ Check if quote is already converted
    if (quote.status == 'CONVERTED') {
      _showErrorSnackbar('This quote has already been converted. Please refresh the page.');
      return;
    }

    // ✅ Check if quote status is valid for conversion
    if (quote.status != 'ACCEPTED' && quote.status != 'SENT') {
      _showErrorSnackbar('Only ACCEPTED or SENT quotes can be converted to sales orders. Current status: ${quote.status}');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Convert to Sales Order'),
        content: Text('Convert quote ${quote.quoteNumber} to a sales order?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3498DB)),
            child: const Text('Convert'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await QuoteService.convertToSalesOrder(quote.id);
        _showSuccessSnackbar('Quote converted to sales order successfully');
        _refreshData();
      } catch (e) {
        _showErrorSnackbar('Failed to convert to sales order: $e');
      }
    }
  }

  Future<void> _acceptQuote(Quote quote) async {
    try {
      await QuoteService.acceptQuote(quote.id);
      _showSuccessSnackbar('Quote marked as accepted');
      _refreshData();
    } catch (e) {
      _showErrorSnackbar('Failed to accept quote: $e');
    }
  }

  Future<void> _declineQuote(Quote quote) async {
    final reasonController = TextEditingController();
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline Quote'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Decline quote ${quote.quoteNumber}?'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await QuoteService.declineQuote(
          quote.id,
          reasonController.text.trim().isEmpty ? null : reasonController.text.trim(),
        );
        _showSuccessSnackbar('Quote marked as declined');
        _refreshData();
      } catch (e) {
        _showErrorSnackbar('Failed to decline quote: $e');
      }
    }
  }

  Future<void> _cloneQuote(Quote quote) async {
    try {
      await QuoteService.cloneQuote(quote.id);
      _showSuccessSnackbar('Quote duplicated successfully');
      _refreshData();
    } catch (e) {
      _showErrorSnackbar('Failed to clone quote: $e');
    }
  }

  Future<void> _exportToExcel() async {
    try {
      if (_quotes.isEmpty) {
        _showErrorSnackbar('No quotes to export');
        return;
      }

      _showSuccessSnackbar('Preparing Excel export...');

      List<List<dynamic>> csvData = [
        [
          'Date',
          'Quote Number',
          'Reference Number',
          'Customer Name',
          'Customer Email',
          'Status',
          'Expiry Date',
          'Sub Total',
          'CGST',
          'SGST',
          'IGST',
          'Total Amount',
        ],
      ];

      for (var quote in _quotes) {
        csvData.add([
          DateFormat('dd/MM/yyyy').format(quote.quoteDate),
          quote.quoteNumber,
          quote.referenceNumber ?? '',
          quote.customerName,
          quote.customerEmail ?? '',
          quote.status,
          DateFormat('dd/MM/yyyy').format(quote.expiryDate),
          quote.subTotal.toStringAsFixed(2),
          quote.cgst.toStringAsFixed(2),
          quote.sgst.toStringAsFixed(2),
          quote.igst.toStringAsFixed(2),
          quote.totalAmount.toStringAsFixed(2),
        ]);
      }

      await ExportHelper.exportToExcel(
        data: csvData,
        filename: 'quotes',
      );

      _showSuccessSnackbar('✅ Excel file downloaded with ${_quotes.length} quotes!');
    } catch (e) {
      _showErrorSnackbar('Failed to export: $e');
    }
  }

  // ============================================================================
  // BULK IMPORT FUNCTIONALITY
  // ============================================================================
  
  void _handleBulkImport() {
    showDialog(
      context: context,
      builder: (context) => BulkImportQuotesDialog(
        onImportComplete: () {
          _refreshData();
        },
      ),
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
      setState(() {
        _fromDate = picked;
      });
      _loadQuotes();
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
      setState(() {
        _toDate = picked;
      });
      _loadQuotes();
    }
  }
  
  void _clearDateFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    _loadQuotes();
  }

  // 🆕 NEW: Show Quote Lifecycle Dialog
  void _showQuoteLifecycleDialog() {
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
                          color: Color(0xFF3498DB),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Quote Lifecycle Process',
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
                                'assets/qoute.png',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.broken_image_outlined,
                                        size: 80,
                                        color: Colors.grey[400],
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Image not found',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Please ensure "assets/qoute.png" exists',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
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
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
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
      appBar: AppTopBar(title: 'Quotes'),
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
                    : _quotes.isEmpty
                        ? _buildEmptyState()
                        : _buildQuoteTable(),
          ),
          if (!_isLoading && _quotes.isNotEmpty) _buildPagination(),
        ],
      ),
    );
  }

 Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // IconButton(
            //   icon: const Icon(Icons.arrow_back, size: 24),
            //   onPressed: () => Navigator.pop(context),
            //   tooltip: 'Back',
            // ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                      status == 'All' ? 'All Quotes' : status.replaceAll('_', ' '),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) _filterByStatus(value);
                },
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search quotes...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  isDense: true,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (_searchQuery == value.toLowerCase()) {
                      _loadQuotes();
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 10),
            InkWell(
              onTap: _selectFromDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: _fromDate != null ? const Color(0xFF1e3a8a).withOpacity(0.1) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _fromDate != null ? const Color(0xFF1e3a8a) : Colors.grey[300]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today, size: 16, color: _fromDate != null ? const Color(0xFF1e3a8a) : Colors.grey[600]),
                    const SizedBox(width: 6),
                    Text(
                      _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _fromDate != null ? FontWeight.w600 : FontWeight.normal,
                        color: _fromDate != null ? const Color(0xFF1e3a8a) : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: _selectToDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: _toDate != null ? const Color(0xFF1e3a8a).withOpacity(0.1) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _toDate != null ? const Color(0xFF1e3a8a) : Colors.grey[300]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today, size: 16, color: _toDate != null ? const Color(0xFF1e3a8a) : Colors.grey[600]),
                    const SizedBox(width: 6),
                    Text(
                      _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _toDate != null ? FontWeight.w600 : FontWeight.normal,
                        color: _toDate != null ? const Color(0xFF1e3a8a) : Colors.grey[700],
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
                  backgroundColor: Colors.red[50],
                  padding: const EdgeInsets.all(10),
                ),
              ),
            ],
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh, size: 22),
              onPressed: _isLoading ? null : _refreshData,
              tooltip: 'Refresh',
              style: IconButton.styleFrom(
                backgroundColor: Colors.grey[200],
                padding: const EdgeInsets.all(10),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.account_tree, size: 22, color: Color(0xFF1e3a8a)),
              onPressed: _showQuoteLifecycleDialog,
              tooltip: 'View Quote Process',
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF1e3a8a).withOpacity(0.1),
                padding: const EdgeInsets.all(10),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _openNewQuote,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Quote', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1e3a8a),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _handleBulkImport,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Bulk Import', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9B59B6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _exportToExcel,
              icon: const Icon(Icons.file_download, size: 18),
              label: const Text('Export Excel', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF27AE60),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          _buildStatCard('Total Quotes', _stats!.totalQuotes.toString(), Icons.description, Colors.blue),
          const SizedBox(width: 16),
          _buildStatCard('Accepted', _stats!.acceptedQuotes.toString(), Icons.check_circle, Colors.green),
          const SizedBox(width: 16),
          _buildStatCard('Pending', _stats!.sentQuotes.toString(), Icons.pending, Colors.orange),
          const SizedBox(width: 16),
          _buildStatCard('Total Value', '₹${_stats!.totalValue.toStringAsFixed(2)}', Icons.attach_money, Colors.purple),
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
                Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                const SizedBox(height: 4),
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuoteTable() {
    return Container(
      margin: const EdgeInsets.all(12),
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
          // Fixed Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFF1e3a8a),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Checkbox(
                      value: _selectAll,
                      onChanged: _toggleSelectAll,
                      fillColor: MaterialStateProperty.all(Colors.white),
                      checkColor: const Color(0xFF1e3a8a),
                    ),
                  ),
                  _buildHeaderCell('DATE', width: 100),
                  _buildHeaderCell('QUOTE#', width: 120),
                  _buildHeaderCell('REFERENCE#', width: 120),
                  _buildHeaderCell('CUSTOMER', width: 160),
                  _buildHeaderCell('STATUS', width: 110),
                  _buildHeaderCell('EXPIRY', width: 100),
                  _buildHeaderCell('AMOUNT', width: 110),
                  const SizedBox(width: 50),
                ],
              ),
            ),
          ),
          // Scrollable Body
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  children: List.generate(_quotes.length, (index) {
                    return Column(
                      children: [
                        _buildQuoteRow(_quotes[index]),
                        if (index < _quotes.length - 1)
                          Divider(height: 1, color: Colors.grey[200]),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, {double width = 100}) {
    return SizedBox(
      width: width,
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

  Widget _buildQuoteRow(Quote quote) {
    final isSelected = _selectedQuotes.contains(quote.id);

    return InkWell(
      onTap: () => _openEditQuote(quote.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        color: isSelected ? Colors.blue[50] : null,
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Checkbox(
                value: isSelected,
                onChanged: (value) => _toggleSelection(quote.id),
              ),
            ),
            SizedBox(
              width: 100,
              child: Text(
                DateFormat('dd/MM/yyyy').format(quote.quoteDate),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            SizedBox(
              width: 120,
              child: InkWell(
                onTap: () => _openEditQuote(quote.id),
                child: Text(
                  quote.quoteNumber,
                  style: const TextStyle(
                    color: Color(0xFF1e3a8a),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: Text(
                quote.referenceNumber ?? '-',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ),
            SizedBox(
              width: 160,
              child: Text(
                quote.customerName,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 110,
              child: _buildStatusBadge(quote.status),
            ),
            SizedBox(
              width: 100,
              child: Text(
                DateFormat('dd/MM/yyyy').format(quote.expiryDate),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            SizedBox(
              width: 110,
              child: Text(
                '₹${quote.totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: 50,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'view',
                    child: ListTile(
                      leading: Icon(Icons.visibility, size: 18, color: Color(0xFF1e3a8a)),
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
                  if (quote.status == 'SENT' || quote.status == 'DRAFT') ...[
                    const PopupMenuItem(
                      value: 'send',
                      child: ListTile(
                        leading: Icon(Icons.send, size: 18),
                        title: Text('Send'),
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
                  if ((quote.status == 'ACCEPTED' || quote.status == 'SENT') && quote.status != 'CONVERTED') ...[
                    const PopupMenuItem(
                      value: 'convert_invoice',
                      child: ListTile(
                        leading: Icon(Icons.receipt_long, size: 18, color: Color(0xFF27AE60)),
                        title: Text('Convert to Invoice', style: TextStyle(color: Color(0xFF27AE60))),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'convert_so',
                      child: ListTile(
                        leading: Icon(Icons.shopping_cart, size: 18, color: Color(0xFF1e3a8a)),
                        title: Text('Convert to Sales Order', style: TextStyle(color: Color(0xFF1e3a8a))),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                  if (quote.status == 'SENT') ...[
                    const PopupMenuItem(
                      value: 'accept',
                      child: ListTile(
                        leading: Icon(Icons.check_circle, size: 18, color: Color(0xFF27AE60)),
                        title: Text('Mark as Accepted', style: TextStyle(color: Color(0xFF27AE60))),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'decline',
                      child: ListTile(
                        leading: Icon(Icons.cancel, size: 18, color: Colors.red),
                        title: Text('Mark as Declined', style: TextStyle(color: Colors.red)),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                  const PopupMenuItem(
                    value: 'clone',
                    child: ListTile(
                      leading: Icon(Icons.copy, size: 18),
                      title: Text('Duplicate'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
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
                      _viewQuoteDetails(quote);
                      break;
                    case 'edit':
                      _openEditQuote(quote.id);
                      break;
                    case 'send':
                      _sendQuote(quote);
                      break;
                    case 'download':
                      await _downloadQuotePDF(quote);
                      break;
                    case 'convert_invoice':
                      _convertToInvoice(quote);
                      break;
                    case 'convert_so':
                      _convertToSalesOrder(quote);
                      break;
                    case 'accept':
                      _acceptQuote(quote);
                      break;
                    case 'decline':
                      _declineQuote(quote);
                      break;
                    case 'clone':
                      _cloneQuote(quote);
                      break;
                    case 'delete':
                      _deleteQuote(quote);
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
      case 'ACCEPTED':
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        break;
      case 'DRAFT':
        backgroundColor = Colors.grey[200]!;
        textColor = Colors.grey[800]!;
        break;
      case 'SENT':
        backgroundColor = Colors.blue[100]!;
        textColor = Colors.blue[800]!;
        break;
      case 'DECLINED':
        backgroundColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        break;
      case 'EXPIRED':
        backgroundColor = Colors.orange[100]!;
        textColor = Colors.orange[800]!;
        break;
      case 'CONVERTED':
        backgroundColor = Colors.purple[100]!;
        textColor = Colors.purple[800]!;
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

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${(_currentPage - 1) * _itemsPerPage + 1} - ${(_currentPage * _itemsPerPage).clamp(0, _totalQuotes)} of $_totalQuotes',
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
                        _loadQuotes();
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
                        _loadQuotes();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _currentPage == pageNum ? const Color(0xFF3498DB) : Colors.transparent,
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
                        });
                        _loadQuotes();
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
          Icon(Icons.description_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No quotes found',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[700]),
          ),
          const SizedBox(height: 8),
          Text('Create your first quote to get started', style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _openNewQuote,
            icon: const Icon(Icons.add),
            label: const Text('Create Quote'),
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
          Text(
            'Error Loading Quotes',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[700]),
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

// ============================================================================
// BULK IMPORT QUOTES DIALOG
// ============================================================================

class BulkImportQuotesDialog extends StatefulWidget {
  final VoidCallback onImportComplete;

  const BulkImportQuotesDialog({
    Key? key,
    required this.onImportComplete,
  }) : super(key: key);

  @override
  State<BulkImportQuotesDialog> createState() => _BulkImportQuotesDialogState();
}

class _BulkImportQuotesDialogState extends State<BulkImportQuotesDialog> {
  bool isDownloading = false;
  bool isUploading = false;
  String? uploadedFileName;
  List<Map<String, dynamic>>? importResults;
  
  // ============================================================================
  // HELPER: PARSE VALUES
  // ============================================================================
  
  String _parsePhoneNumber(dynamic value) {
    if (value == null) return '';
    
    String strValue = value.toString().trim();
    if (strValue.isEmpty) return '';
    
    // Check if it's in scientific notation (e.g., 9.88E+09)
    if (strValue.toUpperCase().contains('E')) {
      try {
        double numValue = double.parse(strValue);
        int intValue = numValue.round();
        return intValue.toString();
      } catch (e) {
        print('⚠️ Failed to parse scientific notation: $strValue');
        return strValue;
      }
    }
    
    // Remove any decimal points for regular numbers
    if (strValue.contains('.')) {
      try {
        double numValue = double.parse(strValue);
        int intValue = numValue.round();
        return intValue.toString();
      } catch (e) {
        return strValue;
      }
    }
    
    return strValue;
  }
  
  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    
    try {
      return double.parse(value.toString().trim());
    } catch (e) {
      return 0.0;
    }
  }
  
  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    
    String strValue = value.toString().trim();
    if (strValue.isEmpty) return null;
    
    // Try multiple date formats
    List<String> formats = [
      'dd/MM/yyyy',
      'dd-MM-yyyy',
      'yyyy-MM-dd',
      'MM/dd/yyyy',
    ];
    
    for (String format in formats) {
      try {
        return DateFormat(format).parse(strValue);
      } catch (e) {
        continue;
      }
    }
    
    return null;
  }
  
  // ============================================================================
  // DOWNLOAD SAMPLE TEMPLATE
  // ============================================================================
  
  Future<void> _downloadTemplate() async {
    setState(() => isDownloading = true);
    
    try {
      // Create sample Excel template with headers and example data
      List<List<dynamic>> templateData = [
        // Headers
        [
          'Quote Date* (dd/MM/yyyy)',
          'Quote Number*',
          'Reference Number',
          'Customer Name*',
          'Customer Email*',
          'Customer Phone*',
          'Expiry Date* (dd/MM/yyyy)',
          'Status*',
          'Salesperson',
          'Project Name',
          'Subject*',
          'Sub Total*',
          'CGST',
          'SGST',
          'IGST',
          'TDS Amount',
          'TCS Amount',
          'Total Amount*',
          'Customer Notes',
          'Terms and Conditions',
        ],
        // Example row 1
        [
          '01/01/2024',
          'QT-2024-001',
          'REF-001',
          'ABC Corporation',
          'contact@abccorp.com',
          '9876543210',
          '31/01/2024',
          'DRAFT',
          'John Sales',
          'Website Development',
          'Quotation for Website Development Services',
          '100000.00',
          '9000.00',
          '9000.00',
          '0.00',
          '0.00',
          '0.00',
          '118000.00',
          'Please review the quotation and let us know if you have any questions.',
          'Payment terms: 50% advance, 50% on completion. Validity: 30 days.',
        ],
        // Example row 2
        [
          '02/01/2024',
          'QT-2024-002',
          'REF-002',
          'XYZ Enterprises',
          'info@xyzent.com',
          '9123456789',
          '15/02/2024',
          'SENT',
          'Jane Sales',
          'Mobile App Development',
          'Quote for Mobile Application Development',
          '250000.00',
          '22500.00',
          '22500.00',
          '0.00',
          '0.00',
          '0.00',
          '295000.00',
          'Looking forward to working with you.',
          'Payment: 30% advance, 40% on milestone, 30% on delivery.',
        ],
        // Instructions row
        [
          'INSTRUCTIONS:',
          '1. Fields marked with * are required',
          '2. Date format must be dd/MM/yyyy (e.g., 31/12/2024)',
          '3. Status options: DRAFT, SENT, ACCEPTED, DECLINED, EXPIRED, CONVERTED',
          '4. Phone should be 10 digits',
          '5. Email must be valid format',
          '6. All amounts should be numbers (decimals allowed)',
          '7. CGST + SGST or IGST should be calculated correctly',
          '8. Total Amount = Sub Total + CGST + SGST + IGST + TCS - TDS',
          '9. Delete this instruction row before uploading',
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
        filename: 'quotes_import_template',
      );
      
      setState(() => isDownloading = false);
      
      _showSuccess('Template downloaded successfully!');
    } catch (e) {
      setState(() => isDownloading = false);
      _showError('Failed to download template: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // UPLOAD AND IMPORT FILE
  // ============================================================================
  
  Future<void> _uploadFile() async {
    try {
      print('📁 Opening file picker...');
      
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        allowMultiple: false,
        withData: true,
        withReadStream: false,
      );
      
      print('📁 File picker result: ${result != null ? "File selected" : "Cancelled"}');
      
      if (result == null || result.files.isEmpty) {
        print('❌ No file selected');
        return;
      }
      
      final file = result.files.first;
      print('✅ Selected file: ${file.name}, Extension: ${file.extension}, Size: ${file.size} bytes');
      
      setState(() {
        uploadedFileName = file.name;
        isUploading = true;
        importResults = null;
      });
      
      // Read file bytes
      Uint8List? bytes = file.bytes;
      if (bytes == null) {
        print('❌ Failed to read file bytes');
        throw Exception('Failed to read file. Please try again.');
      }
      
      print('✅ File bytes read successfully: ${bytes.length} bytes');
      
      // Determine file type and parse accordingly
      List<List<dynamic>> rows;
      final extension = file.extension?.toLowerCase() ?? '';
      
      print('🔍 Processing file type: $extension');
      
      if (extension == 'csv') {
        print('📊 Parsing as CSV...');
        rows = _parseCSVImproved(bytes);
      } else if (extension == 'xlsx' || extension == 'xls') {
        print('📊 Parsing as Excel...');
        rows = _parseExcel(bytes);
      } else {
        throw Exception('Unsupported file format. Please use .xlsx, .xls, or .csv files only.');
      }
      
      print('✅ Parsed ${rows.length} rows from file');
      
      if (rows.isEmpty) {
        throw Exception('File is empty or could not be read');
      }
      
      if (rows.length < 2) {
        throw Exception('File must contain at least a header row and one data row');
      }
      
      // Log first few rows for debugging
      print('📋 First row (headers): ${rows[0]}');
      if (rows.length > 1) {
        print('📋 Second row (data): ${rows[1]}');
      }
      
      // Skip header row and parse data
      List<Map<String, dynamic>> quotesToImport = [];
      List<String> errors = [];
      
      for (int i = 1; i < rows.length; i++) {
        try {
          var row = rows[i];
          
          // Skip empty rows or instruction rows
          if (row.isEmpty || 
              row[0] == null ||
              row[0].toString().trim().isEmpty ||
              row[0].toString().toUpperCase().contains('INSTRUCTION')) {
            print('⏭️ Skipping row $i (empty or instruction)');
            continue;
          }
          
          print('🔄 Processing row $i: ${row.take(5).join(", ")}...');
          
          // Parse quote data with safe access
          DateTime? quoteDate = _parseDate(_getValue(row, 0));
          String quoteNumber = _getStringValue(row, 1);
          String referenceNumber = _getStringValue(row, 2);
          String customerName = _getStringValue(row, 3);
          String customerEmail = _getStringValue(row, 4);
          String customerPhone = _parsePhoneNumber(_getValue(row, 5));
          DateTime? expiryDate = _parseDate(_getValue(row, 6));
          String status = _getStringValue(row, 7, 'DRAFT');
          String salesperson = _getStringValue(row, 8);
          String projectName = _getStringValue(row, 9);
          String subject = _getStringValue(row, 10);
          double subTotal = _parseDouble(_getValue(row, 11));
          double cgst = _parseDouble(_getValue(row, 12));
          double sgst = _parseDouble(_getValue(row, 13));
          double igst = _parseDouble(_getValue(row, 14));
          double tdsAmount = _parseDouble(_getValue(row, 15));
          double tcsAmount = _parseDouble(_getValue(row, 16));
          double totalAmount = _parseDouble(_getValue(row, 17));
          String customerNotes = _getStringValue(row, 18);
          String termsConditions = _getStringValue(row, 19);
          
          // Validate required fields
          List<String> rowErrors = [];
          
          if (quoteDate == null) {
            rowErrors.add('Quote Date is required and must be in dd/MM/yyyy format');
          }
          if (quoteNumber.isEmpty) {
            rowErrors.add('Quote Number is required');
          }
          if (customerName.isEmpty) {
            rowErrors.add('Customer Name is required');
          }
          if (customerEmail.isEmpty) {
            rowErrors.add('Customer Email is required');
          } else if (!_isValidEmail(customerEmail)) {
            rowErrors.add('Invalid email format');
          }
          if (customerPhone.isEmpty) {
            rowErrors.add('Customer Phone is required');
          } else if (customerPhone.length != 10) {
            rowErrors.add('Phone Number must be 10 digits');
          }
          if (expiryDate == null) {
            rowErrors.add('Expiry Date is required and must be in dd/MM/yyyy format');
          }
          if (subject.isEmpty) {
            rowErrors.add('Subject is required');
          }
          if (subTotal <= 0) {
            rowErrors.add('Sub Total must be greater than 0');
          }
          if (totalAmount <= 0) {
            rowErrors.add('Total Amount must be greater than 0');
          }
          
          // Validate status
          final validStatuses = ['DRAFT', 'SENT', 'ACCEPTED', 'DECLINED', 'EXPIRED', 'CONVERTED'];
          if (!validStatuses.contains(status.toUpperCase())) {
            rowErrors.add('Status must be one of: ${validStatuses.join(", ")}');
          }
          
          if (rowErrors.isNotEmpty) {
            errors.add('Row ${i + 1}: ${rowErrors.join(", ")}');
            print('❌ Row $i validation failed: ${rowErrors.join(", ")}');
            continue;
          }
          
          print('✅ Row $i validated successfully');
          
          quotesToImport.add({
            'quoteDate': quoteDate!.toIso8601String(),
            'quoteNumber': quoteNumber,
            'referenceNumber': referenceNumber,
            'customerName': customerName,
            'customerEmail': customerEmail,
            'customerPhone': customerPhone,
            'expiryDate': expiryDate!.toIso8601String(),
            'status': status.toUpperCase(),
            'salesperson': salesperson,
            'projectName': projectName,
            'subject': subject,
            'subTotal': subTotal,
            'cgst': cgst,
            'sgst': sgst,
            'igst': igst,
            'tdsAmount': tdsAmount,
            'tcsAmount': tcsAmount,
            'totalAmount': totalAmount,
            'customerNotes': customerNotes,
            'termsConditions': termsConditions,
          });
        } catch (e) {
          errors.add('Row ${i + 1}: ${e.toString()}');
          print('❌ Error processing row $i: $e');
        }
      }
      
      print('📊 Import Summary:');
      print('  - Total rows processed: ${rows.length - 1}');
      print('  - Valid quotes: ${quotesToImport.length}');
      print('  - Errors: ${errors.length}');
      
      if (quotesToImport.isEmpty) {
        throw Exception('No valid quote data found in the file. Please check the format and required fields.');
      }
      
      // Show confirmation dialog with count
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Import'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Found ${quotesToImport.length} quote(s) to import.',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                if (errors.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    '${errors.length} row(s) skipped due to errors:',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      child: Text(
                        errors.join('\n'),
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text('Do you want to proceed with the import?'),
              ],
            ),
          ),
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
      
      print('🚀 Starting bulk import API call...');
      
      // Call bulk import API (You'll need to implement this in QuoteService)
      // For now, showing a mock result
      final importResult = await QuoteService.bulkImportQuotes(quotesToImport);
      
      print('✅ Bulk import completed: ${importResult['data']}');
      
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
        _showSuccess('Import completed successfully!');
        widget.onImportComplete();
      }
    } catch (e, stackTrace) {
      print('❌ Upload Error: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        isUploading = false;
        uploadedFileName = null;
      });
      _showError('Failed to import: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // HELPER: SAFE VALUE EXTRACTION
  // ============================================================================
  
  dynamic _getValue(List<dynamic> row, int index) {
    if (index >= row.length) return null;
    return row[index];
  }
  
  String _getStringValue(List<dynamic> row, int index, [String defaultValue = '']) {
    if (index >= row.length) return defaultValue;
    final value = row[index];
    if (value == null) return defaultValue;
    return value.toString().trim();
  }
  
  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }
  
  // ============================================================================
  // PARSE EXCEL FILE
  // ============================================================================
  
  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    try {
      print('📊 Decoding Excel file...');
      var excel = excel_pkg.Excel.decodeBytes(bytes);
      
      print('📊 Excel sheets: ${excel.tables.keys.join(", ")}');
      
      // Get first sheet
      var sheet = excel.tables.keys.first;
      var rows = excel.tables[sheet]?.rows;
      
      if (rows == null || rows.isEmpty) {
        throw Exception('Excel file is empty');
      }
      
      print('📊 Found ${rows.length} rows in Excel');
      
      // Convert Excel rows to List<List<dynamic>>
      List<List<dynamic>> result = rows.map((row) {
        return row.map((cell) {
          if (cell?.value == null) return '';
          
          if (cell!.value is excel_pkg.TextCellValue) {
            return (cell.value as excel_pkg.TextCellValue).value;
          }
          
          return cell.value;
        }).toList();
      }).toList();
      
      print('✅ Excel parsed successfully');
      return result;
    } catch (e, stackTrace) {
      print('❌ Excel parsing error: $e');
      print('Stack trace: $stackTrace');
      throw Exception('Failed to parse Excel file: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // PARSE CSV FILE - IMPROVED VERSION
  // ============================================================================
  
  List<List<dynamic>> _parseCSVImproved(Uint8List bytes) {
    try {
      print('📊 Decoding CSV file...');
      
      String csvString = utf8.decode(bytes, allowMalformed: true);
      
      print('📊 CSV file size: ${csvString.length} characters');
      
      List<String> lines = csvString.split(RegExp(r'\r?\n'));
      
      print('📊 Found ${lines.length} lines in CSV');
      
      List<List<dynamic>> rows = [];
      
      for (int i = 0; i < lines.length; i++) {
        String line = lines[i].trim();
        
        if (line.isEmpty) {
          continue;
        }
        
        List<String> fields = _parseCSVLine(line);
        
        if (i == 0) {
          print('📋 CSV Headers: ${fields.join(" | ")}');
        }
        
        rows.add(fields);
      }
      
      print('✅ CSV parsed successfully: ${rows.length} rows');
      return rows;
    } catch (e, stackTrace) {
      print('❌ CSV parsing error: $e');
      print('Stack trace: $stackTrace');
      throw Exception('Failed to parse CSV file: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // PARSE CSV LINE (PROPER CSV PARSING WITH QUOTES)
  // ============================================================================
  
  List<String> _parseCSVLine(String line) {
    List<String> fields = [];
    StringBuffer currentField = StringBuffer();
    bool inQuotes = false;
    
    for (int i = 0; i < line.length; i++) {
      String char = line[i];
      
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          currentField.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        fields.add(currentField.toString().trim());
        currentField.clear();
      } else {
        currentField.write(char);
      }
    }
    
    fields.add(currentField.toString().trim());
    
    return fields.map((field) {
      if (field.startsWith('"') && field.endsWith('"')) {
        return field.substring(1, field.length - 1);
      }
      return field;
    }).toList();
  }
  
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }
  
  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
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
            // Header
            Row(
              children: [
                const Icon(Icons.upload_file, color: Color(0xFF9B59B6), size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Bulk Import Quotes',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 32),
            
            // Instructions
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
                      Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'How to Import Quotes',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Download the sample template with all required fields\n'
                    '2. Fill in your quote data (follow the format exactly)\n'
                    '3. Ensure dates are in dd/MM/yyyy format\n'
                    '4. Upload the completed file (.xlsx, .xls, or .csv)\n'
                    '5. Review validation results and confirm import',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Download Template Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isDownloading || isUploading ? null : _downloadTemplate,
                icon: isDownloading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.download),
                label: Text(isDownloading ? 'Downloading...' : 'Download Sample Template'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3498DB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Upload File Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isDownloading || isUploading ? null : _uploadFile,
                icon: isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF9B59B6)),
                        ),
                      )
                    : const Icon(Icons.upload_file),
                label: Text(
                  isUploading 
                      ? 'Processing...' 
                      : 'Upload Excel or CSV File',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF9B59B6),
                  side: const BorderSide(color: Color(0xFF9B59B6)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            
            if (uploadedFileName != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        uploadedFileName!,
                        style: TextStyle(
                          color: Colors.green[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            // Import Results
            if (importResults != null) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Import Results',
                style: TextStyle(
                  fontSize: 16,
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
                child: Column(
                  children: [
                    _buildResultRow('Total Processed', importResults![0]['total'].toString(), Colors.blue),
                    const SizedBox(height: 8),
                    _buildResultRow('Successfully Imported', importResults![0]['success'].toString(), Colors.green),
                    const SizedBox(height: 8),
                    _buildResultRow('Failed', importResults![0]['failed'].toString(), Colors.red),
                    if ((importResults![0]['errors'] as List).isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Errors:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: SingleChildScrollView(
                          child: Text(
                            (importResults![0]['errors'] as List).join('\n'),
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
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3498DB),
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
  
  Widget _buildResultRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// Quote Details Dialog
class QuoteDetailsDialog extends StatelessWidget {
  final Quote quote;

  const QuoteDetailsDialog({Key? key, required this.quote}) : super(key: key);

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
                const Icon(Icons.description, color: Color(0xFF3498DB), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quote.quoteNumber,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)),
                      ),
                      Text('Quote Details', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                    ],
                  ),
                ),
                _buildStatusBadge(quote.status),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 32),
            
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection(
                      'Customer Information',
                      [
                        _buildInfoRow('Customer Name', quote.customerName),
                        _buildInfoRow('Email', quote.customerEmail),
                        _buildInfoRow('Phone', quote.customerPhone),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    _buildSection(
                      'Quote Information',
                      [
                        _buildInfoRow('Quote Number', quote.quoteNumber),
                        _buildInfoRow('Reference Number', quote.referenceNumber),
                        _buildInfoRow('Quote Date', DateFormat('dd MMM yyyy').format(quote.quoteDate)),
                        _buildInfoRow('Expiry Date', DateFormat('dd MMM yyyy').format(quote.expiryDate)),
                        _buildInfoRow('Salesperson', quote.salesperson),
                        _buildInfoRow('Project Name', quote.projectName),
                        _buildInfoRow('Subject', quote.subject),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    if (quote.items.isNotEmpty) ...[
                      _buildLineItemsSection(quote.items),
                      const SizedBox(height: 24),
                    ],
                    
                    _buildSection(
                      'Amount Details',
                      [
                        _buildInfoRow('Subtotal', '₹${quote.subTotal.toStringAsFixed(2)}'),
                        if (quote.tdsAmount > 0)
                          _buildInfoRow('TDS', '₹${quote.tdsAmount.toStringAsFixed(2)}'),
                        if (quote.tcsAmount > 0)
                          _buildInfoRow('TCS', '₹${quote.tcsAmount.toStringAsFixed(2)}'),
                        _buildInfoRow('CGST', '₹${quote.cgst.toStringAsFixed(2)}'),
                        _buildInfoRow('SGST', '₹${quote.sgst.toStringAsFixed(2)}'),
                        _buildInfoRow('IGST', '₹${quote.igst.toStringAsFixed(2)}'),
                        _buildInfoRow('Total Amount', '₹${quote.totalAmount.toStringAsFixed(2)}', isBold: true),
                      ],
                    ),
                    
                    if (quote.customerNotes != null && quote.customerNotes!.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildSection(
                        'Customer Notes',
                        [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(quote.customerNotes!, style: TextStyle(fontSize: 14, color: Colors.grey[800])),
                          ),
                        ],
                      ),
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
                  child: const Text('Close'),
                ),
              ],
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
      case 'ACCEPTED':
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        break;
      case 'DRAFT':
        backgroundColor = Colors.grey[200]!;
        textColor = Colors.grey[800]!;
        break;
      case 'SENT':
        backgroundColor = Colors.blue[100]!;
        textColor = Colors.blue[800]!;
        break;
      case 'DECLINED':
        backgroundColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        break;
      case 'EXPIRED':
        backgroundColor = Colors.orange[100]!;
        textColor = Colors.orange[800]!;
        break;
      case 'CONVERTED':
        backgroundColor = Colors.purple[100]!;
        textColor = Colors.purple[800]!;
        break;
      default:
        backgroundColor = Colors.blue[100]!;
        textColor = Colors.blue[800]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(status, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
  
  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
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
  
  Widget _buildInfoRow(String label, dynamic value, {bool isBold = false}) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: const Color(0xFF2C3E50), fontSize: 14)),
          ),
          Expanded(
            child: Text(
              value.toString(),
              style: TextStyle(color: Colors.grey[800], fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLineItemsSection(List<QuoteItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Line Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
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
              3: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.grey[200]),
                children: const [
                  Padding(padding: EdgeInsets.all(12), child: Text('Item', style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(padding: EdgeInsets.all(12), child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(padding: EdgeInsets.all(12), child: Text('Rate', style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(padding: EdgeInsets.all(12), child: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
              ...items.map<TableRow>((item) {
                return TableRow(
                  children: [
                    Padding(padding: const EdgeInsets.all(12), child: Text(item.itemDetails)),
                    Padding(padding: const EdgeInsets.all(12), child: Text(item.quantity.toString())),
                    Padding(padding: const EdgeInsets.all(12), child: Text('₹${item.rate.toStringAsFixed(2)}')),
                    Padding(padding: const EdgeInsets.all(12), child: Text('₹${item.amount.toStringAsFixed(2)}')),
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