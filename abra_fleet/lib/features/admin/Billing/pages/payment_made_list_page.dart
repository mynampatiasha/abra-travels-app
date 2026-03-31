// FILE: payment_made_list_page.dart
// All changes vs original:
// ✅ Table header: Color(0xFF0D1B3E), fontSize 13, letterSpacing 0.4, headingRowHeight 52
// ✅ Data rows: fontSize 14, dataRowMin 58, dataRowMax 72, scrollbar thickness 8 radius 4
// ✅ Pagination: animated page buttons, ellipsis, navy active, styled nav containers
// ✅ Stats cards: gradient bg + gradient icon container, 4-in-row, h-scroll on mobile
// ✅ ALL original functionality 100% preserved

import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:universal_html/html.dart' as html;

import '../../../../app/config/api_config.dart';
import '../../../../core/services/payment_made_service.dart';
import '../../../../core/utils/export_helper.dart';
import '../app_top_bar.dart';
import 'new_payment_made.dart';

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

class PaymentMadeListPage extends StatefulWidget {
  const PaymentMadeListPage({Key? key}) : super(key: key);
  @override
  State<PaymentMadeListPage> createState() => _PaymentMadeListPageState();
}

class _PaymentMadeListPageState extends State<PaymentMadeListPage> {
  static const Color _primary = Color(0xFF27AE60);
  static const Color _navy    = Color(0xFF1e3a8a);
  static const Color _dark    = Color(0xFF2C3E50);
  static const Color _purple  = Color(0xFF9B59B6);
  static const Color _blue    = Color(0xFF2980B9);

  List<PaymentMade> _payments = [];
  PaymentMadeStats? _stats;
  bool _isLoading = true;
  String? _error;

  String _statusFilter   = 'All';
  String? _modeFilter;
  String? _typeFilter;
  String _dateFilterType = 'All';
  DateTime? _fromDate;
  DateTime? _toDate;
  DateTime? _particularDate;

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  int _page       = 1;
  int _totalPages = 1;
  int _totalCount = 0;
  static const int _pageSize = 20;

  final Set<String> _selected = {};
  bool _selectAll = false;

  final _hScrollCtrl      = ScrollController();
  final _vScrollCtrl      = ScrollController();
  final _statsHScrollCtrl = ScrollController();

  static const _statuses = [
    'All','DRAFT','RECORDED','PARTIALLY_APPLIED','APPLIED','REFUNDED','VOIDED',
  ];
  static const _modes = [
    'Cash','Cheque','Bank Transfer','UPI','Card','Online','NEFT','RTGS','IMPS',
  ];
  static const _types = ['PAYMENT','ADVANCE','EXCESS'];

  @override
  void initState() {
    super.initState();
    _load();
    _loadStats();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _hScrollCtrl.dispose();
    _vScrollCtrl.dispose();
    _statsHScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      DateTime? from = _fromDate, to = _toDate;
      if (_dateFilterType == 'Particular Date' && _particularDate != null) {
        from = _particularDate;
        to   = _particularDate!.add(const Duration(days: 1));
      }
      final res = await PaymentMadeService.getPayments(
        status:      _statusFilter == 'All' ? null : _statusFilter,
        paymentMode: _modeFilter,
        paymentType: _typeFilter,
        fromDate:    from,
        toDate:      to,
        search:      _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
        page:        _page,
        limit:       _pageSize,
      );
      setState(() {
        _payments   = res.payments;
        _totalPages = res.pagination.pages;
        _totalCount = res.pagination.total;
        _isLoading  = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _loadStats() async {
    try {
      setState(() => _stats = null);
      final s = await PaymentMadeService.getStats();
      if (mounted) setState(() => _stats = s);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    _page = 1;
    await Future.wait([_load(), _loadStats()]);
    _snack('Refreshed', _primary);
  }

  Future<void> _goToNew() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NewPaymentMadeScreen()),
    );
    if (result == true) _refresh();
  }

  Future<void> _goToEdit(String id) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NewPaymentMadeScreen(paymentId: id)),
    );
    if (result == true) _refresh();
  }

  Future<void> _delete(PaymentMade p) async {
    final ok = await _confirmDialog(
      'Delete ${p.paymentNumber}?',
      'This cannot be undone. Only Draft / Recorded payments can be deleted.',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await PaymentMadeService.deletePayment(p.id);
      _snack('${p.paymentNumber} deleted', Colors.red);
      _refresh();
    } catch (e) { _snack('Delete failed: $e', Colors.red); }
  }

  Future<void> _downloadPDF(PaymentMade p) async {
    try {
      _snack('Generating PDF...', Colors.blueGrey);
      final url = await PaymentMadeService.downloadPDF(p.id);
      if (kIsWeb) {
        html.AnchorElement(href: url)
          ..setAttribute('download', 'Payment-${p.paymentNumber}.pdf')
          ..setAttribute('target', '_blank')
          ..click();
      }
      _snack('PDF downloaded', _primary);
    } catch (e) { _snack('PDF failed: $e', Colors.red); }
  }

  Future<void> _exportExcel() async {
    try {
      _snack('Preparing export...', Colors.blueGrey);
      final all = await PaymentMadeService.getAllPayments();
      if (all.isEmpty) { _snack('No data to export', Colors.orange); return; }
      final rows = <List<dynamic>>[
        ['Payment #','Vendor Name','Vendor Email','Date','Mode','Type',
         'Reference #','Status','Amount','Sub Total','TDS','TCS',
         'CGST','SGST','Total Amount','Applied','Unused','Refunded','Notes'],
        ...all.map((p) => [
          p.paymentNumber, p.vendorName, p.vendorEmail ?? '',
          DateFormat('dd/MM/yyyy').format(p.paymentDate),
          p.paymentMode, p.paymentType, p.referenceNumber ?? '', p.status,
          p.amount.toStringAsFixed(2), p.subTotal.toStringAsFixed(2),
          p.tdsAmount.toStringAsFixed(2), p.tcsAmount.toStringAsFixed(2),
          p.cgst.toStringAsFixed(2), p.sgst.toStringAsFixed(2),
          p.totalAmount.toStringAsFixed(2), p.amountApplied.toStringAsFixed(2),
          p.amountUnused.toStringAsFixed(2), p.totalRefunded.toStringAsFixed(2),
          p.notes ?? '',
        ]),
      ];
      await ExportHelper.exportToExcel(
        data: rows,
        filename: 'payments_made_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
      );
      _snack('Exported ${all.length} payments', _primary);
    } catch (e) { _snack('Export failed: $e', Colors.red); }
  }

  bool get _hasFilters =>
      _statusFilter != 'All' || _modeFilter != null ||
      _typeFilter != null || _dateFilterType != 'All';

  void _clearFilters() {
    setState(() {
      _statusFilter = 'All'; _modeFilter = null; _typeFilter = null;
      _dateFilterType = 'All'; _fromDate = null; _toDate = null;
      _particularDate = null; _page = 1;
    });
    _load();
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  Future<bool?> _confirmDialog(String title, String body, {bool destructive = false}) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: destructive ? Colors.red : _primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );

  // ============================================================================
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Payments Made'),
      backgroundColor: const Color(0xFFF4F6F9),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBar(),
            _buildStatsCards(),
            _buildTableSection(),
            _buildPagination(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── TOP BAR ─────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth < 700)  return _topBarMobile();
        if (c.maxWidth < 1100) return _topBarTablet();
        return _topBarDesktop();
      }),
    );
  }

  Widget _topBarDesktop() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 12),
      _searchField(width: 260),
      const SizedBox(width: 8),
      _filterBtn(),
      if (_hasFilters) ...[const SizedBox(width: 4), _clearFilterBtn()],
      const Spacer(),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree_outlined, _showProcessDialog, tooltip: 'View Process', color: _primary),
      const SizedBox(width: 12),
      _actionBtn('New Payment', Icons.add_rounded, _primary, _goToNew),
      const SizedBox(width: 8),
      _actionBtn('Import', Icons.upload_file_rounded, _purple, _showImportDialog),
      const SizedBox(width: 8),
      _actionBtn('Export', Icons.download_rounded, _blue, _exportExcel),
    ]),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 8),
      _searchField(width: 200),
      const SizedBox(width: 8),
      _filterBtn(),
      if (_hasFilters) ...[const SizedBox(width: 4), _clearFilterBtn()],
      const Spacer(),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
      const SizedBox(width: 4),
      _iconBtn(Icons.account_tree_outlined, _showProcessDialog, tooltip: 'View Process', color: _primary),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      _actionBtn('New Payment', Icons.add_rounded, _primary, _goToNew),
      const SizedBox(width: 8),
      _actionBtn('Import', Icons.upload_file_rounded, _purple, _showImportDialog),
      const SizedBox(width: 8),
      _actionBtn('Export', Icons.download_rounded, _blue, _exportExcel),
    ]),
  ]);

  Widget _topBarMobile() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    // Single row: dropdown + search + New button
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 8),
      Expanded(child: _searchField(width: double.infinity)),
      const SizedBox(width: 8),
      _actionBtn('New', Icons.add_rounded, _primary, _goToNew),
    ]),
    const SizedBox(height: 10),
    // Row 2: Scrollable strip of utility buttons
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _filterBtn(),
        if (_hasFilters) ...[const SizedBox(width: 4), _clearFilterBtn()],
        const SizedBox(width: 6),
        _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
        const SizedBox(width: 6),
        _iconBtn(Icons.account_tree_outlined, _showProcessDialog, tooltip: 'Process', color: _primary),
        const SizedBox(width: 6),
        _compactBtn('Import', _purple, _showImportDialog),
        const SizedBox(width: 6),
        _compactBtn('Export', _blue, _exportExcel),
      ]),
    ),
  ]);

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
        value: _statusFilter,
        isDense: true,
        icon: const Icon(Icons.expand_more, size: 18, color: Color(0xFF1e3a8a)),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1e3a8a)),
        items: _statuses.map((s) => DropdownMenuItem(
          value: s,
          child: Text(s == 'All' ? 'All Payments' : s.replaceAll('_', ' ')),
        )).toList(),
        onChanged: (v) {
          if (v != null) { setState(() { _statusFilter = v; _page = 1; }); _load(); }
        },
      ),
    ),
  );

  Widget _searchField({required double width}) {
    final field = TextField(
      controller: _searchCtrl,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search payment #, vendor, ref...',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() { _searchQuery = ''; _page = 1; });
                  _load();
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
            borderSide: const BorderSide(color: Color(0xFF1e3a8a), width: 1.5)),
      ),
      onChanged: (v) {
        setState(() { _searchQuery = v; _page = 1; });
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_searchQuery == v) _load();
        });
      },
    );
    if (width == double.infinity) return field;
    return SizedBox(width: width, height: 44, child: field);
  }

  Widget _filterBtn() => Stack(children: [
    OutlinedButton.icon(
      onPressed: _showFilterDialog,
      icon: const Icon(Icons.tune_rounded, size: 16),
      label: Text('Filter', style: TextStyle(color: _hasFilters ? _primary : Colors.grey.shade700)),
      style: OutlinedButton.styleFrom(
        foregroundColor: _hasFilters ? _primary : Colors.grey.shade700,
        side: BorderSide(color: _hasFilters ? _primary : Colors.grey.shade300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    ),
    if (_hasFilters)
      Positioned(right: 6, top: 4,
        child: Container(width: 8, height: 8,
            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle))),
  ]);

  Widget _clearFilterBtn() => TextButton.icon(
    onPressed: _clearFilters,
    icon: const Icon(Icons.clear, size: 14),
    label: const Text('Clear', style: TextStyle(fontSize: 14)),
    style: TextButton.styleFrom(foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 8)),
  );

  Widget _iconBtn(IconData icon, VoidCallback? onTap, {String? tooltip, Color color = const Color(0xFF7F8C8D)}) =>
      Tooltip(
        message: tooltip ?? '',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.25)),
            ),
            child: Icon(icon, size: 20,
                color: onTap == null ? Colors.grey.shade400 : color),
          ),
        ),
      );

  Widget _actionBtn(String label, IconData icon, Color bg, VoidCallback? onTap) =>
      ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg, foregroundColor: Colors.white,
          disabledBackgroundColor: bg.withOpacity(0.5),
          elevation: 0,
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  Widget _compactBtn(String label, Color bg, VoidCallback? onTap) =>
      ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg, foregroundColor: Colors.white,
          disabledBackgroundColor: bg.withOpacity(0.5),
          elevation: 0,
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );

  // ── STATS CARDS ─────────────────────────────────────────────────────────────

  Widget _buildStatsCards() {
    if (_stats == null) {
      return Container(
        height: 90, color: Colors.white,
        child: const Center(child: SizedBox(width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    final cards = [
      _StatCardData(label: 'Total Payments', value: _stats!.totalPayments.toString(),
          icon: Icons.payments_outlined, color: Colors.blue,
          gradientColors: const [Color(0xFF5B9BD5), Color(0xFF2980B9)]),
      _StatCardData(label: 'Total Amount', value: '₹${_fmt(_stats!.totalAmount)}',
          icon: Icons.account_balance_wallet_outlined, color: _primary,
          gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      _StatCardData(label: 'Applied', value: '₹${_fmt(_stats!.totalApplied)}',
          icon: Icons.check_circle_outline, color: Colors.teal,
          gradientColors: const [Color(0xFF1ABC9C), Color(0xFF16A085)]),
      _StatCardData(label: 'Unused', value: '₹${_fmt(_stats!.totalUnused)}',
          icon: Icons.pending_outlined, color: Colors.orange,
          gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)]),
    ];
    return Container(
      width: double.infinity,
      color: const Color(0xFFF4F6F9),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(builder: (_, constraints) {
        final isMobile = constraints.maxWidth < 700;
        if (isMobile) {
          return SingleChildScrollView(
            controller: _statsHScrollCtrl,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: cards.asMap().entries.map((e) => Container(
                width: 160,
                margin: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0),
                child: _buildStatCard(e.value, compact: true),
              )).toList(),
            ),
          );
        }
        return Row(
          children: cards.asMap().entries.map((e) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0),
              child: _buildStatCard(e.value, compact: false),
            ),
          )).toList(),
        );
      }),
    );
  }

  Widget _buildStatCard(_StatCardData data, {required bool compact}) {
    return Container(
      padding: compact ? const EdgeInsets.all(12)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            data.gradientColors[0].withOpacity(0.15),
            data.gradientColors[1].withOpacity(0.08),
          ],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: data.color.withOpacity(0.22)),
        boxShadow: [BoxShadow(color: data.color.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: data.gradientColors,
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(data.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 10),
              Text(data.label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(data.value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: data.color),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ])
          : Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: data.gradientColors,
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: data.color.withOpacity(0.30), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Icon(data.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(data.label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Text(data.value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: data.color),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
            ]),
    );
  }

  // ── TABLE ────────────────────────────────────────────────────────────────────

  Widget _buildTableSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: _isLoading
          ? const SizedBox(height: 340, child: Center(child: CircularProgressIndicator()))
          : _error != null ? _errorState()
          : _payments.isEmpty ? _emptyState()
          : _table(),
    );
  }

  Widget _table() {
    return Scrollbar(
      controller: _hScrollCtrl,
      thumbVisibility: true, trackVisibility: true,
      thickness: 8, radius: const Radius.circular(4),
      notificationPredicate: (n) => n.depth == 1,
      child: Scrollbar(
        controller: _vScrollCtrl,
        thumbVisibility: true, trackVisibility: true,
        thickness: 8, radius: const Radius.circular(4),
        notificationPredicate: (n) => n.depth == 0,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: true,
            dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
          ),
          child: SingleChildScrollView(
            controller: _vScrollCtrl,
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              controller: _hScrollCtrl,
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFF0D1B3E)),
                headingTextStyle: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.4),
                headingRowHeight: 52,
                dataRowMinHeight: 58,
                dataRowMaxHeight: 72,
                dataTextStyle: const TextStyle(fontSize: 14, color: _dark),
                dataRowColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.hovered)) return const Color(0xFF1e3a8a).withOpacity(0.04);
                  return null;
                }),
                dividerThickness: 1,
                columnSpacing: 18,
                horizontalMargin: 16,
                columns: [
                  DataColumn(label: SizedBox(width: 36,
                    child: Checkbox(value: _selectAll, onChanged: (v) {
                      setState(() {
                        _selectAll = v!;
                        if (_selectAll) _selected.addAll(_payments.map((p) => p.id));
                        else _selected.clear();
                      });
                    }, fillColor: WidgetStateProperty.all(Colors.white), checkColor: const Color(0xFF0D1B3E)))),
                  const DataColumn(label: SizedBox(width: 140, child: Text('PAYMENT #'))),
                  const DataColumn(label: SizedBox(width: 170, child: Text('VENDOR'))),
                  const DataColumn(label: SizedBox(width: 110, child: Text('DATE'))),
                  const DataColumn(label: SizedBox(width: 110, child: Text('MODE'))),
                  const DataColumn(label: SizedBox(width: 90, child: Text('TYPE'))),
                  const DataColumn(label: SizedBox(width: 120, child: Text('STATUS'))),
                  const DataColumn(label: SizedBox(width: 120, child: Text('AMOUNT'))),
                  const DataColumn(label: SizedBox(width: 110, child: Text('APPLIED'))),
                  const DataColumn(label: SizedBox(width: 110, child: Text('UNUSED'))),
                  const DataColumn(label: SizedBox(width: 90, child: Text('ACTIONS'))),
                ],
                rows: _payments.map(_buildRow).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(PaymentMade p) {
    final sel = _selected.contains(p.id);
    return DataRow(
      selected: sel,
      color: WidgetStateProperty.resolveWith((s) {
        if (sel) return _primary.withOpacity(0.07);
        if (s.contains(WidgetState.hovered)) return _primary.withOpacity(0.04);
        return null;
      }),
      cells: [
        DataCell(SizedBox(width: 36, child: Checkbox(value: sel, onChanged: (_) {
          setState(() {
            if (sel) _selected.remove(p.id); else _selected.add(p.id);
            _selectAll = _selected.length == _payments.length;
          });
        }))),
        DataCell(SizedBox(width: 140,
          child: InkWell(
            onTap: () => _showDetailDialog(p),
            borderRadius: BorderRadius.circular(4),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(p.paymentNumber,
                style: const TextStyle(color: _primary, fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline, fontSize: 14),
                overflow: TextOverflow.ellipsis)),
          ),
        )),
        DataCell(SizedBox(width: 170, child: Column(mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.vendorName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              overflow: TextOverflow.ellipsis),
          if (p.vendorEmail != null && p.vendorEmail!.isNotEmpty)
            Text(p.vendorEmail!, style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                overflow: TextOverflow.ellipsis),
        ]))),
        DataCell(SizedBox(width: 110,
            child: Text(DateFormat('dd MMM yyyy').format(p.paymentDate),
                style: const TextStyle(fontSize: 13)))),
        DataCell(SizedBox(width: 110,
            child: Text(p.paymentMode, style: const TextStyle(fontSize: 13)))),
        DataCell(SizedBox(width: 90, child: _badge(p.paymentType, _typeColor(p.paymentType)))),
        DataCell(SizedBox(width: 120, child: _badge(p.status.replaceAll('_', ' '), _statusColor(p.status)))),
        DataCell(SizedBox(width: 120,
            child: Text('₹${_fmt(p.totalAmount)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)))),
        DataCell(SizedBox(width: 110,
            child: Text('₹${_fmt(p.amountApplied)}',
                style: TextStyle(fontSize: 13, color: Colors.teal.shade700)))),
        DataCell(SizedBox(width: 110,
            child: Text('₹${_fmt(p.amountUnused)}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: p.amountUnused > 0.01 ? Colors.orange.shade700 : Colors.grey.shade500)))),
        DataCell(SizedBox(width: 90,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onSelected: (v) {
              switch (v) {
                case 'view':   _showDetailDialog(p); break;
                case 'edit':   _goToEdit(p.id); break;
                case 'pdf':    _downloadPDF(p); break;
                case 'delete': _delete(p); break;
              }
            },
            itemBuilder: (_) => [
              _menuItem('view',   Icons.visibility_outlined,    'View Details', Colors.blue),
              _menuItem('edit',   Icons.edit_outlined,           'Edit Payment', Colors.orange),
              _menuItem('pdf',    Icons.picture_as_pdf_outlined, 'Download PDF', Colors.red),
              const PopupMenuDivider(),
              _menuItem('delete', Icons.delete_outline,          'Delete',       Colors.red),
            ],
          ),
        )),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String val, IconData icon, String label, Color color) =>
      PopupMenuItem<String>(
        value: val,
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 14)),
        ]),
      );

  // ── PAGINATION ───────────────────────────────────────────────────────────────

  Widget _buildPagination() {
    if (_payments.isEmpty && !_isLoading) return const SizedBox.shrink();

    List<int> pages;
    if (_totalPages <= 5) {
      pages = List.generate(_totalPages, (i) => i + 1);
    } else {
      final int start = (_page - 2).clamp(1, _totalPages - 4);
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
        final bool isNarrow = constraints.maxWidth < 500;

        final info = Text(
          'Showing ${((_page - 1) * _pageSize + 1).clamp(0, _totalCount)}'
          '–${(_page * _pageSize).clamp(0, _totalCount)} of $_totalCount',
          style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
        );

        final pageButtons = Row(mainAxisSize: MainAxisSize.min, children: [
          _pageNavBtn(icon: Icons.chevron_left, enabled: _page > 1,
              onTap: () { setState(() => _page--); _load(); }),
          const SizedBox(width: 4),
          if (!isNarrow && pages.first > 1) ...[
            _pageNumBtn(1),
            if (pages.first > 2)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text('...', style: TextStyle(color: Colors.grey[400]))),
          ],
          ...pages.map((p) => _pageNumBtn(p)),
          if (!isNarrow && pages.last < _totalPages) ...[
            if (pages.last < _totalPages - 1)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text('...', style: TextStyle(color: Colors.grey[400]))),
            _pageNumBtn(_totalPages),
          ],
          const SizedBox(width: 4),
          _pageNavBtn(icon: Icons.chevron_right, enabled: _page < _totalPages,
              onTap: () { setState(() => _page++); _load(); }),
        ]);

        if (isNarrow) return Column(children: [info, const SizedBox(height: 10), pageButtons]);
        return Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: [info, pageButtons],
        );
      }),
    );
  }

  Widget _pageNumBtn(int page) {
    final bool isActive = _page == page;
    return GestureDetector(
      onTap: () { if (!isActive) { setState(() => _page = page); _load(); } },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1e3a8a) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? const Color(0xFF1e3a8a) : Colors.grey[300]!),
        ),
        child: Center(child: Text('$page', style: TextStyle(
          fontSize: 13,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          color: isActive ? Colors.white : Colors.grey[700],
        ))),
      ),
    );
  }

  Widget _pageNavBtn({required IconData icon, required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Icon(icon, size: 18, color: enabled ? const Color(0xFF1e3a8a) : Colors.grey[300]),
      ),
    );
  }

  // ── EMPTY / ERROR ────────────────────────────────────────────────────────────

  Widget _emptyState() => SizedBox(height: 340, child: Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: _primary.withOpacity(0.06), shape: BoxShape.circle),
      child: Icon(Icons.payments_outlined, size: 64, color: _primary.withOpacity(0.4))),
    const SizedBox(height: 20),
    Text('No payments found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
    const SizedBox(height: 8),
    Text('Adjust filters or record your first payment', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
    const SizedBox(height: 28),
    ElevatedButton.icon(
      onPressed: _goToNew, icon: const Icon(Icons.add),
      label: const Text('Record Payment', style: TextStyle(fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white,
          elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    ),
  ])));

  Widget _errorState() => SizedBox(height: 340, child: Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
      child: Icon(Icons.error_outline, size: 56, color: Colors.red[400])),
    const SizedBox(height: 20),
    Text('Failed to Load Payments', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
    const SizedBox(height: 8),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(_error ?? '', style: TextStyle(color: Colors.grey.shade500), textAlign: TextAlign.center)),
    const SizedBox(height: 28),
    ElevatedButton.icon(
      onPressed: _refresh, icon: const Icon(Icons.refresh),
      label: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white,
          elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    ),
  ])));

  // ── DETAIL DIALOG ────────────────────────────────────────────────────────────

  void _showDetailDialog(PaymentMade p) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: EdgeInsets.symmetric(
          horizontal: MediaQuery.of(context).size.width > 800 ? 60 : 16, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 780, maxHeight: MediaQuery.of(context).size.height * 0.9),
          child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _primary.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.payments_outlined, color: _primary, size: 26)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.paymentNumber, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _dark)),
                Text(DateFormat('dd MMM yyyy').format(p.paymentDate),
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              ])),
              _badge(p.status.replaceAll('_', ' '), _statusColor(p.status)),
              const SizedBox(width: 10),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx),
                style: IconButton.styleFrom(backgroundColor: Colors.grey.shade100, shape: const CircleBorder())),
            ]),
            const Divider(height: 24),
            Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LayoutBuilder(builder: (_, c) {
                final wide = c.maxWidth > 520;
                final vendorSec = _detailCard('Vendor', [
                  _dRow('Vendor Name', p.vendorName, bold: true),
                  _dRow('Email', p.vendorEmail),
                ]);
                final paymentSec = _detailCard('Payment Info', [
                  _dRow('Payment Mode', p.paymentMode),
                  _dRow('Payment Type', p.paymentType),
                  _dRow('Reference #', p.referenceNumber),
                  _dRow('Status', p.status.replaceAll('_', ' ')),
                ]);
                return wide
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: vendorSec), const SizedBox(width: 12), Expanded(child: paymentSec)])
                    : Column(children: [vendorSec, const SizedBox(height: 12), paymentSec]);
              }),
              const SizedBox(height: 14),
              LayoutBuilder(builder: (_, c) {
                final wide = c.maxWidth > 520;
                final amountSec = _detailCard('Amount Breakdown', [
                  _dRow('Sub Total', '₹${_fmt(p.subTotal)}'),
                  if (p.tdsAmount > 0) _dRow('TDS (${p.tdsRate.toStringAsFixed(1)}%)', '- ₹${_fmt(p.tdsAmount)}', color: Colors.red),
                  if (p.tcsAmount > 0) _dRow('TCS (${p.tcsRate.toStringAsFixed(1)}%)', '₹${_fmt(p.tcsAmount)}'),
                  if (p.cgst > 0) _dRow('CGST', '₹${_fmt(p.cgst)}'),
                  if (p.sgst > 0) _dRow('SGST', '₹${_fmt(p.sgst)}'),
                  const Divider(height: 12),
                  _dRow('Total Amount', '₹${_fmt(p.totalAmount)}', bold: true, color: _primary),
                  _dRow('Applied to Bills', '₹${_fmt(p.amountApplied)}', color: Colors.teal),
                  _dRow('Unused Amount', '₹${_fmt(p.amountUnused)}', color: Colors.orange),
                  if (p.totalRefunded > 0) _dRow('Total Refunded', '₹${_fmt(p.totalRefunded)}', color: Colors.red),
                ]);
                final metaSec = _detailCard('Metadata', [
                  _dRow('Created At', DateFormat('dd MMM yyyy, hh:mm a').format(p.createdAt)),
                  _dRow('Updated At', DateFormat('dd MMM yyyy, hh:mm a').format(p.updatedAt)),
                  if (p.notes != null && p.notes!.isNotEmpty) _dRow('Notes', p.notes!),
                ]);
                return wide
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: amountSec), const SizedBox(width: 12), Expanded(child: metaSec)])
                    : Column(children: [amountSec, const SizedBox(height: 12), metaSec]);
              }),
              if (p.items.isNotEmpty) ...[
                const SizedBox(height: 14),
                _sectionLabel('Line Items (${p.items.length})'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                  child: SingleChildScrollView(scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                      headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _dark),
                      dataTextStyle: const TextStyle(fontSize: 12),
                      dataRowMinHeight: 40, columnSpacing: 20, horizontalMargin: 12,
                      columns: const [
                        DataColumn(label: Text('ITEM')), DataColumn(label: Text('TYPE')),
                        DataColumn(label: Text('QTY')),  DataColumn(label: Text('RATE')),
                        DataColumn(label: Text('DISC')), DataColumn(label: Text('AMOUNT')),
                      ],
                      rows: p.items.map((item) => DataRow(cells: [
                        DataCell(SizedBox(width: 180, child: Text(item.itemDetails, overflow: TextOverflow.ellipsis))),
                        DataCell(Text(item.itemType)),
                        DataCell(Text(item.quantity.toStringAsFixed(0))),
                        DataCell(Text('₹${_fmt(item.rate)}')),
                        DataCell(Text(item.discount > 0 ? '${item.discount}${item.discountType == "percentage" ? "%" : "₹"}' : '-')),
                        DataCell(Text('₹${_fmt(item.amount)}', style: const TextStyle(fontWeight: FontWeight.bold))),
                      ])).toList(),
                    ),
                  ),
                ),
              ],
              if (p.billsApplied.isNotEmpty) ...[
                const SizedBox(height: 14),
                _sectionLabel('Bills Applied To (${p.billsApplied.length})'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                    headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _dark),
                    dataTextStyle: const TextStyle(fontSize: 12),
                    dataRowMinHeight: 38, columnSpacing: 20, horizontalMargin: 12,
                    columns: const [DataColumn(label: Text('BILL #')), DataColumn(label: Text('APPLIED')), DataColumn(label: Text('DATE'))],
                    rows: p.billsApplied.map((b) => DataRow(cells: [
                      DataCell(Text(b.billNumber, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600))),
                      DataCell(Text('₹${_fmt(b.amountApplied)}')),
                      DataCell(Text(DateFormat('dd/MM/yyyy').format(b.appliedDate))),
                    ])).toList(),
                  ),
                ),
              ],
              if (p.refunds.isNotEmpty) ...[
                const SizedBox(height: 14),
                _sectionLabel('Refunds (${p.refunds.length})'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                    headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _dark),
                    dataTextStyle: const TextStyle(fontSize: 12),
                    dataRowMinHeight: 38, columnSpacing: 20, horizontalMargin: 12,
                    columns: const [DataColumn(label: Text('AMOUNT')), DataColumn(label: Text('MODE')), DataColumn(label: Text('DATE')), DataColumn(label: Text('NOTES'))],
                    rows: p.refunds.map((r) => DataRow(cells: [
                      DataCell(Text('₹${_fmt(r.amount)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                      DataCell(Text(r.refundMode)),
                      DataCell(Text(DateFormat('dd/MM/yy').format(r.refundDate))),
                      DataCell(Text(r.notes ?? '-', overflow: TextOverflow.ellipsis)),
                    ])).toList(),
                  ),
                ),
              ],
            ]))),
            const Divider(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () { Navigator.pop(ctx); _downloadPDF(p); },
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                label: const Text('Download PDF'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () { Navigator.pop(ctx); _goToEdit(p.id); },
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
                style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
              ),
            ]),
          ])),
        ),
      ),
    );
  }

  Widget _detailCard(String title, List<Widget> rows) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _dark, letterSpacing: 0.6)),
      const SizedBox(height: 10),
      ...rows,
    ]),
  );

  Widget _dRow(String label, String? value, {bool bold = false, Color? color}) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600))),
      Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: color ?? _dark))),
    ]));
  }

  Widget _sectionLabel(String t) => Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _dark));

  // ── FILTER DIALOG ────────────────────────────────────────────────────────────

  void _showFilterDialog() {
    String dft = _dateFilterType;
    DateTime? from = _fromDate, to = _toDate, part = _particularDate;
    String? mode = _modeFilter, type = _typeFilter;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Filter Payments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
        ]),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          _dlabel('Date Filter'),
          _ddrop<String>(ctx, dft,
            ['All','Within Date Range','Particular Date','Today','This Week','This Month','Last Month','This Year'],
            (v) {
              final now = DateTime.now();
              setS(() {
                dft = v!;
                if (v == 'Today') { from = DateTime(now.year, now.month, now.day); to = from!.add(const Duration(days: 1)); }
                else if (v == 'This Week') { final wd = now.weekday; from = now.subtract(Duration(days: wd - 1)); to = from!.add(const Duration(days: 6)); }
                else if (v == 'This Month') { from = DateTime(now.year, now.month); to = DateTime(now.year, now.month + 1, 0); }
                else if (v == 'Last Month') { from = DateTime(now.year, now.month - 1); to = DateTime(now.year, now.month, 0); }
                else if (v == 'This Year') { from = DateTime(now.year); to = DateTime(now.year, 12, 31); }
                else { from = null; to = null; part = null; }
              });
            },
          ),
          if (dft == 'Within Date Range') ...[
            const SizedBox(height: 14),
            _dlabel('From Date'),
            _datePickerTile(ctx, from, 'Select from date', (d) => setS(() => from = d)),
            const SizedBox(height: 12),
            _dlabel('To Date'),
            _datePickerTile(ctx, to, 'Select to date', (d) => setS(() => to = d)),
          ],
          if (dft == 'Particular Date') ...[
            const SizedBox(height: 14),
            _dlabel('Select Date'),
            _datePickerTile(ctx, part, 'Select date', (d) => setS(() => part = d)),
          ],
          const SizedBox(height: 16),
          _dlabel('Payment Mode'),
          _ddrop<String?>(ctx, mode, [null, ..._modes], (v) => setS(() => mode = v), hint: 'All Modes'),
          const SizedBox(height: 14),
          _dlabel('Payment Type'),
          _ddrop<String?>(ctx, type, [null, ..._types], (v) => setS(() => type = v), hint: 'All Types'),
        ]))),
        actions: [
          TextButton(child: const Text('Clear All', style: TextStyle(color: Colors.red)),
            onPressed: () => setS(() { dft = 'All'; from = null; to = null; part = null; mode = null; type = null; })),
          TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx)),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _dateFilterType = dft; _fromDate = from; _toDate = to;
                _particularDate = part; _modeFilter = mode; _typeFilter = type; _page = 1;
              });
              Navigator.pop(ctx);
              _load();
            },
            style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
            child: const Text('Apply Filters'),
          ),
        ],
      )),
    );
  }

  Widget _dlabel(String t) => Padding(padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _dark)));

  Widget _ddrop<T>(BuildContext ctx, T val, List<T> items, void Function(T?) onChanged, {String hint = ''}) =>
      Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButton<T>(
          value: val, isExpanded: true, underline: const SizedBox(),
          hint: Text(hint, style: const TextStyle(color: Colors.grey)),
          items: items.map((i) => DropdownMenuItem<T>(value: i,
              child: Text(i?.toString() ?? 'All', style: const TextStyle(fontSize: 14)))).toList(),
          onChanged: onChanged,
        ),
      );

  Widget _datePickerTile(BuildContext ctx, DateTime? date, String hint, void Function(DateTime) onPick) =>
      InkWell(
        onTap: () async {
          final d = await showDatePicker(context: ctx, initialDate: date ?? DateTime.now(),
              firstDate: DateTime(2020), lastDate: DateTime(2030));
          if (d != null) onPick(d);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey),
            const SizedBox(width: 10),
            Text(date != null ? DateFormat('dd MMM yyyy').format(date) : hint,
                style: TextStyle(color: date != null ? _dark : Colors.grey.shade500, fontSize: 14)),
          ]),
        ),
      );

  // ── PROCESS DIALOG ───────────────────────────────────────────────────────────

  void _showProcessDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      builder: (ctx) {
        final screenSize = MediaQuery.of(context).size;
        final dialogW = (screenSize.width * 0.88).clamp(320.0, 1000.0);
        final dialogH = screenSize.height * 0.85;
        return Center(child: Material(color: Colors.transparent, child: Container(
          width: dialogW, height: dialogH,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 30, offset: const Offset(0, 12))]),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(color: _primary,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12))),
              child: Row(children: [
                const Icon(Icons.account_tree_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                const Expanded(child: Text('Payments Made — Process Flow',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600))),
                InkWell(onTap: () => Navigator.pop(ctx), child: const Icon(Icons.close, color: Colors.white, size: 20)),
              ]),
            ),
            Expanded(child: ClipRRect(
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
              child: Image.asset('assets/payment_made.png',
                width: double.infinity, height: double.infinity, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _fallbackFlowDiagram()),
            )),
          ]),
        )));
      },
    );
  }

  Widget _fallbackFlowDiagram() {
    final steps = [
      {'icon': Icons.drafts_outlined,   'label': 'DRAFT',             'color': Colors.grey},
      {'icon': Icons.check_circle,      'label': 'RECORDED',          'color': Colors.blue},
      {'icon': Icons.attach_money,      'label': 'PARTIALLY\nAPPLIED','color': Colors.orange},
      {'icon': Icons.done_all,          'label': 'APPLIED',           'color': Colors.green},
      {'icon': Icons.undo,              'label': 'REFUNDED',          'color': Colors.purple},
      {'icon': Icons.cancel_outlined,   'label': 'VOIDED',            'color': Colors.red},
    ];
    return Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 16,
        children: steps.expand((s) => [
          Column(mainAxisSize: MainAxisSize.min, children: [
            Container(padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: (s['color'] as Color).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10), border: Border.all(color: s['color'] as Color, width: 2)),
              child: Column(children: [
                Icon(s['icon'] as IconData, color: s['color'] as Color, size: 28),
                const SizedBox(height: 6),
                Text(s['label'] as String, style: TextStyle(color: s['color'] as Color,
                    fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.center),
              ])),
          ]),
          if (s != steps.last)
            Padding(padding: const EdgeInsets.only(top: 20),
                child: Icon(Icons.arrow_forward_rounded, color: Colors.grey.shade400)),
        ]).toList(),
      ),
      const SizedBox(height: 20),
      Container(padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200)),
        child: const Text('Draft → Recorded → Partially Applied → Applied → Refunded / Voided',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 14))),
    ]));
  }

  // ── IMPORT DIALOG ────────────────────────────────────────────────────────────

  void _showImportDialog() {
    showDialog(context: context, barrierDismissible: false,
      builder: (ctx) => _ImportDialog(onSuccess: () { Navigator.pop(ctx); _refresh(); }));
  }

  // ── HELPERS ──────────────────────────────────────────────────────────────────

  String _fmt(double v) => NumberFormat('#,##0.00').format(v);

  Widget _badge(String label, ({Color bg, Color fg}) colors) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: colors.bg, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colors.fg)),
  );

  ({Color bg, Color fg}) _statusColor(String s) {
    switch (s) {
      case 'APPLIED':           return (bg: Colors.green.shade100,  fg: Colors.green.shade800);
      case 'PARTIALLY_APPLIED': return (bg: Colors.teal.shade100,   fg: Colors.teal.shade800);
      case 'RECORDED':          return (bg: Colors.blue.shade100,   fg: Colors.blue.shade800);
      case 'REFUNDED':          return (bg: Colors.purple.shade100, fg: Colors.purple.shade800);
      case 'VOIDED':            return (bg: Colors.red.shade100,    fg: Colors.red.shade800);
      default:                  return (bg: Colors.grey.shade200,   fg: Colors.grey.shade700);
    }
  }

  ({Color bg, Color fg}) _typeColor(String t) {
    switch (t) {
      case 'ADVANCE': return (bg: Colors.purple.shade100, fg: Colors.purple.shade800);
      case 'EXCESS':  return (bg: Colors.orange.shade100, fg: Colors.orange.shade800);
      default:        return (bg: Colors.blue.shade100,   fg: Colors.blue.shade800);
    }
  }
}

// =============================================================================
// IMPORT DIALOG — fully self-contained, fully preserved
// =============================================================================

class _ImportDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  const _ImportDialog({required this.onSuccess});
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  bool _dlLoading = false;
  bool _uploading = false;
  String? _filename;
  Map<String, dynamic>? _result;

  static const _primary = Color(0xFF27AE60);
  static const _purple  = Color(0xFF9B59B6);

  Future<void> _downloadTemplate() async {
    setState(() => _dlLoading = true);
    try {
      final rows = [
        ['Vendor Name *','Vendor Email *','Payment Date * (dd/MM/yyyy)','Payment Mode *',
         'Payment Type','Reference Number','Amount *','Notes','Bill Number (apply to)','Bill Amount Applied'],
        ['ABC Supplies Ltd','accounts@abc.com','01/03/2024','Bank Transfer','PAYMENT','NEFT-2024-001','75000.00','March payment','BILL-2403-0001','75000.00'],
        ['XYZ Logistics','billing@xyz.com','15/03/2024','UPI','ADVANCE','UPI-98765','25000.00','Advance for April','',''],
        ['INSTRUCTIONS','1. * = required','2. Date format: dd/MM/yyyy',
         '3. Modes: Cash/Cheque/Bank Transfer/UPI/Card/Online/NEFT/RTGS/IMPS',
         '4. Types: PAYMENT/ADVANCE/EXCESS','5. Delete this row before upload','','','',''],
      ];
      await ExportHelper.exportToExcel(
        data: rows,
        filename: 'payments_made_import_template_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      );
      _snack('Template downloaded', _primary);
    } catch (e) { _snack('Download failed: $e', Colors.red); }
    finally { setState(() => _dlLoading = false); }
  }

  Future<void> _pickAndImport() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['xlsx','xls','csv'], withData: true);
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.first;
      if (file.bytes == null) { _snack('Could not read file', Colors.red); return; }
      setState(() { _uploading = true; _filename = file.name; _result = null; });

      final ext = (file.extension ?? '').toLowerCase();
      final rows = ext == 'csv' ? _parseCSV(file.bytes!) : _parseExcel(file.bytes!);
      if (rows.length < 2) throw Exception('File must have a header row + at least one data row');

      final valid = <Map<String, dynamic>>[];
      final errors = <String>[];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        final vName     = _cell(row, 0);
        final vEmail    = _cell(row, 1);
        final dateStr   = _cell(row, 2);
        final mode      = _cell(row, 3, 'Bank Transfer');
        final type      = _cell(row, 4, 'PAYMENT').toUpperCase();
        final ref       = _cell(row, 5);
        final amountStr = _cell(row, 6);
        final notes     = _cell(row, 7);
        final billNum   = _cell(row, 8);
        final billAmtStr= _cell(row, 9);

        if (vName.isEmpty || vName.toUpperCase().contains('INSTRUCTION')) continue;

        final rowErr = <String>[];
        if (vName.isEmpty)  rowErr.add('Vendor Name required');
        if (vEmail.isEmpty) rowErr.add('Vendor Email required');
        final date = _parseDate(dateStr);
        if (date == null) rowErr.add('Invalid date "$dateStr"');
        final amount = double.tryParse(amountStr.replaceAll(',', ''));
        if (amount == null || amount <= 0) rowErr.add('Invalid amount "$amountStr"');
        if (rowErr.isNotEmpty) { errors.add('Row ${i + 1}: ${rowErr.join(', ')}'); continue; }

        valid.add({
          'vendorName': vName, 'vendorEmail': vEmail,
          'paymentDate': date!.toIso8601String(),
          'paymentMode': mode, 'paymentType': type,
          'referenceNumber': ref, 'amount': amount, 'notes': notes,
          'billsApplied': billNum.isNotEmpty
              ? [{'billNumber': billNum, 'amountApplied': double.tryParse(billAmtStr.replaceAll(',','')) ?? 0}]
              : [],
        });
      }

      if (valid.isEmpty && errors.isNotEmpty) {
        setState(() => _uploading = false);
        _snack('No valid rows found. Check errors.', Colors.red);
        _showErrors(errors);
        return;
      }

      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Confirm Import'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${valid.length} payment(s) ready to import',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('${errors.length} row(s) skipped due to errors',
                style: const TextStyle(color: Colors.orange, fontSize: 13)),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 110),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade200)),
              child: SingleChildScrollView(child: Text(errors.join('\n'),
                  style: const TextStyle(fontSize: 11, color: Colors.red))),
            ),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
            child: Text('Import ${valid.length} Payments'),
          ),
        ],
      ));

      if (ok != true) { setState(() { _uploading = false; _filename = null; }); return; }

      final res = await PaymentMadeService.bulkImport(valid, file.bytes!, file.name);
      setState(() { _uploading = false; _result = res['data']; });
      if (res['success'] == true) {
        _snack('Imported ${res['data']['successCount']} payments!', _primary);
        widget.onSuccess();
      }
    } catch (e) {
      setState(() { _uploading = false; _filename = null; });
      _snack('Import failed: $e', Colors.red);
    }
  }

  void _showErrors(List<String> errors) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Import Errors'),
      content: SizedBox(width: 480, height: 300, child: ListView(
        children: errors.map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text('• $e', style: const TextStyle(fontSize: 12, color: Colors.red)))).toList())),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    ));
  }

  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    final book = xl.Excel.decodeBytes(bytes);
    final sheet = book.tables[book.tables.keys.first];
    if (sheet == null) return [];
    return sheet.rows.map((row) => row.map((c) {
      if (c?.value == null) return '';
      if (c!.value is xl.TextCellValue)   return (c.value as xl.TextCellValue).value;
      if (c.value is xl.IntCellValue)     return (c.value as xl.IntCellValue).value.toString();
      if (c.value is xl.DoubleCellValue)  return (c.value as xl.DoubleCellValue).value.toString();
      return c.value.toString();
    }).toList()).toList();
  }

  List<List<dynamic>> _parseCSV(Uint8List bytes) {
    final str = utf8.decode(bytes, allowMalformed: true);
    return str.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).map((line) {
      final fields = <String>[]; final cur = StringBuffer(); bool inQ = false;
      for (int i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == '"') { if (inQ && i+1 < line.length && line[i+1] == '"') { cur.write('"'); i++; } else inQ = !inQ; }
        else if (ch == ',' && !inQ) { fields.add(cur.toString().trim()); cur.clear(); }
        else cur.write(ch);
      }
      fields.add(cur.toString().trim());
      return fields;
    }).toList();
  }

  String _cell(List row, int i, [String def = '']) =>
      i < row.length ? (row[i]?.toString().trim() ?? def) : def;

  DateTime? _parseDate(String s) {
    for (final fmt in ['dd/MM/yyyy','dd-MM-yyyy','yyyy-MM-dd','MM/dd/yyyy','dd MMM yyyy']) {
      try { return DateFormat(fmt).parseStrict(s); } catch (_) {}
    }
    return null;
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _purple.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.upload_file_rounded, color: _purple, size: 24)),
              const SizedBox(width: 12),
              const Expanded(child: Text('Bulk Import Payments', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
            const Divider(height: 24),
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.info_outline, color: Colors.blue.shade700, size: 16), const SizedBox(width: 8),
                  Text('How to import', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue.shade700))]),
                const SizedBox(height: 8),
                Text('1. Download the sample template below\n2. Fill in your payment data (keep columns in order)\n3. Dates must be in dd/MM/yyyy format\n4. Upload your completed file (.xlsx / .xls / .csv)\n5. Review the preview and confirm',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade800, height: 1.7)),
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: _dlLoading || _uploading ? null : _downloadTemplate,
              icon: _dlLoading ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(_dlLoading ? 'Downloading...' : 'Download Sample Excel Template'),
              style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            )),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: _dlLoading || _uploading ? null : _pickAndImport,
              icon: _uploading ? SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _purple))
                  : const Icon(Icons.upload_file_rounded, size: 18),
              label: Text(_uploading ? 'Processing...' : 'Choose & Upload Excel / CSV'),
              style: OutlinedButton.styleFrom(foregroundColor: _purple, side: const BorderSide(color: _purple),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            )),
            if (_filename != null) ...[
              const SizedBox(height: 10),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.shade200)),
                child: Row(children: [Icon(Icons.check_circle, color: Colors.green.shade700, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_filename!, style: TextStyle(color: Colors.green.shade700,
                      fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis))]),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              const Text('Import Results', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200)),
                child: Column(children: [
                  _resRow('Total Processed',      _result!['totalProcessed']?.toString() ?? '0', Colors.blue),
                  const SizedBox(height: 8),
                  _resRow('Successfully Imported', _result!['successCount']?.toString() ?? '0',   Colors.green),
                  const SizedBox(height: 8),
                  _resRow('Failed',               _result!['failedCount']?.toString() ?? '0',    Colors.red),
                  if ((_result!['failedCount'] ?? 0) > 0 && (_result!['errors'] as List?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    Container(constraints: const BoxConstraints(maxHeight: 80),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                      child: SingleChildScrollView(child: Text((_result!['errors'] as List).join('\n'),
                          style: const TextStyle(fontSize: 11, color: Colors.red)))),
                  ],
                ])),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                child: const Text('Done'),
              )),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _resRow(String label, String value, Color color) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
        child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14))),
    ],
  );
}