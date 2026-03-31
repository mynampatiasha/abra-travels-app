// ============================================================================
// BUDGETS LIST PAGE
// ============================================================================
// File: lib/screens/billing/pages/budgets_list_page.dart
// Full Zoho Books style — filters, import, export, view process, stats cards
// Navy blue theme — mirrors payment_made_list_page.dart structure
// ============================================================================

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
import '../../../../core/services/budget_service.dart';
import '../../../../core/utils/export_helper.dart';
import '../app_top_bar.dart';
import 'new_budget.dart';
import 'budget_detail.dart';

const Color _navy     = Color(0xFF0D1B3E);
const Color _navyMid  = Color(0xFF1A3A6B);
const Color _accent   = Color(0xFF3D8EFF);
const Color _dark     = Color(0xFF2C3E50);

// ============================================================================
// MAIN WIDGET
// ============================================================================

class BudgetsListPage extends StatefulWidget {
  const BudgetsListPage({Key? key}) : super(key: key);

  @override
  State<BudgetsListPage> createState() => _BudgetsListPageState();
}

class _BudgetsListPageState extends State<BudgetsListPage> {

  // ── data ──────────────────────────────────────────────────────────────────
  List<Budget> _budgets = [];
  BudgetStats? _stats;
  bool _isLoading = true;
  String? _error;

  // ── filters ───────────────────────────────────────────────────────────────
  String _statusFilter = 'All';        // All | Active | Inactive
  String _fyFilter     = 'All';
  String _periodFilter = 'All';

  // ── search ────────────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // ── pagination ────────────────────────────────────────────────────────────
  int _page       = 1;
  int _totalPages = 1;
  int _totalCount = 0;
  static const int _pageSize = 20;

  // ── selection ─────────────────────────────────────────────────────────────
  final Set<String> _selected = {};
  bool _selectAll = false;

  // ── scroll ────────────────────────────────────────────────────────────────
  final _hScroll = ScrollController();
  final _vScroll = ScrollController();

  static const _periods = ['All', 'Monthly', 'Quarterly', 'Yearly'];

  // ============================================================================
  @override
  void initState() {
    super.initState();
    _load();
    _loadStats();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  // ── Loads ─────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      bool? isActive;
      if (_statusFilter == 'Active')   isActive = true;
      if (_statusFilter == 'Inactive') isActive = false;

      final res = await BudgetService.getBudgets(
        isActive:      isActive,
        financialYear: _fyFilter == 'All' ? null : _fyFilter,
        budgetPeriod:  _periodFilter == 'All' ? null : _periodFilter,
        search:        _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
        page:  _page,
        limit: _pageSize,
      );
      setState(() {
        _budgets    = res.budgets;
        _totalPages = res.pages;
        _totalCount = res.total;
        _isLoading  = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _loadStats() async {
    try {
      final s = await BudgetService.getStats();
      if (mounted) setState(() => _stats = s);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    _page = 1;
    await Future.wait([_load(), _loadStats()]);
    _snack('Refreshed', Colors.blue);
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  Future<void> _goToNew() async {
    final result = await Navigator.push<bool>(
      context, MaterialPageRoute(builder: (_) => const NewBudgetScreen()));
    if (result == true) _refresh();
  }

  Future<void> _goToEdit(String id) async {
    final result = await Navigator.push<bool>(
      context, MaterialPageRoute(builder: (_) => NewBudgetScreen(budgetId: id)));
    if (result == true) _refresh();
  }

  void _goToDetail(String id) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => BudgetDetailPage(budgetId: id)));
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<void> _delete(Budget b) async {
    final ok = await _confirm('Delete "${b.budgetName}"?',
        'This will permanently delete the budget. This cannot be undone.', destructive: true);
    if (ok != true) return;
    try {
      await BudgetService.deleteBudget(b.id);
      _snack('"${b.budgetName}" deleted', Colors.red);
      _refresh();
    } catch (e) { _snack('Delete failed: $e', Colors.red); }
  }

  // ── Toggle Active ──────────────────────────────────────────────────────────

  Future<void> _toggle(Budget b) async {
    try {
      await BudgetService.toggleActive(b.id, !b.isActive);
      _snack(b.isActive ? 'Budget deactivated' : 'Budget activated',
          b.isActive ? Colors.orange : Colors.green);
      _refresh();
    } catch (e) { _snack('Failed: $e', Colors.red); }
  }

  // ── Clone ──────────────────────────────────────────────────────────────────

  Future<void> _clone(Budget b) async {
    final nameCtrl = TextEditingController(text: '${b.budgetName} (Copy)');
    final fyCtrl   = TextEditingController(text: _nextFY(b.financialYear));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Clone Budget'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'New Budget Name')),
          const SizedBox(height: 12),
          TextField(controller: fyCtrl, decoration: const InputDecoration(labelText: 'Financial Year (e.g. 2026-27)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white),
            child: const Text('Clone'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await BudgetService.cloneBudget(b.id, nameCtrl.text.trim(), fyCtrl.text.trim());
      _snack('Budget cloned ✓', Colors.green);
      _refresh();
    } catch (e) { _snack('Clone failed: $e', Colors.red); }
  }

  String _nextFY(String fy) {
    final parts = fy.split('-');
    final y = int.tryParse(parts[0]) ?? DateTime.now().year;
    final ny = y + 1;
    return '$ny-${(ny + 1).toString().substring(2)}';
  }

  // ── Export ─────────────────────────────────────────────────────────────────

  Future<void> _exportExcel() async {
    try {
      _snack('Preparing export…', Colors.blueGrey);
      final all = await BudgetService.getAllBudgets();
      if (all.isEmpty) { _snack('No data to export', Colors.orange); return; }

      final rows = <List<dynamic>>[
        ['Budget Name', 'Financial Year', 'Period', 'Currency', 'Status',
          'Total Budgeted', 'Total Actual', 'Variance', 'Account Count', 'Notes'],
        ...all.map((b) => [
          b.budgetName, b.financialYear, b.budgetPeriod, b.currency,
          b.isActive ? 'Active' : 'Inactive',
          b.totalBudgeted.toStringAsFixed(2),
          b.totalActual.toStringAsFixed(2),
          (b.totalBudgeted - b.totalActual).toStringAsFixed(2),
          b.accountLines.length.toString(),
          b.notes ?? '',
        ]),
      ];

      await ExportHelper.exportToExcel(
        data: rows,
        filename: 'budgets_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
      );
      _snack('✅ Exported ${all.length} budgets', Colors.green);
    } catch (e) { _snack('Export failed: $e', Colors.red); }
  }

  // ── Filter state ───────────────────────────────────────────────────────────

  bool get _hasFilters =>
      _statusFilter != 'All' || _fyFilter != 'All' || _periodFilter != 'All';

  void _clearFilters() {
    setState(() { _statusFilter = 'All'; _fyFilter = 'All'; _periodFilter = 'All'; _page = 1; });
    _load();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  Future<bool?> _confirm(String title, String body, {bool destructive = false}) =>
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
                  backgroundColor: destructive ? Colors.red : _accent, foregroundColor: Colors.white),
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
      appBar: AppTopBar(title: 'Budgets'),
      backgroundColor: const Color(0xFFF4F6F9),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildTopBar(),
          _buildStatsCards(),
          _buildTableSection(),
          _buildPagination(),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  // ── Top Bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
    ),
    child: LayoutBuilder(builder: (_, cs) {
      if (cs.maxWidth < 650)  return _topBarMobile();
      if (cs.maxWidth < 1100) return _topBarTablet();
      return _topBarDesktop();
    }),
  );

  Widget _topBarDesktop() => Row(children: [
    _statusDrop(),
    const SizedBox(width: 12),
    _fyDrop(),
    const SizedBox(width: 8),
    _periodDrop(),
    const SizedBox(width: 8),
    _searchField(width: 220),
    const SizedBox(width: 8),
    if (_hasFilters) _clearBtn(),
    const Spacer(),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    const SizedBox(width: 6),
    _iconBtn(Icons.account_tree_outlined, _showProcessDialog, tooltip: 'View Process', color: _accent),
    const SizedBox(width: 12),
    _actionBtn('New Budget', Icons.add_rounded, _accent, _goToNew),
    const SizedBox(width: 8),
    _actionBtn('Import', Icons.upload_file_rounded, const Color(0xFF9B59B6), _showImportDialog),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, const Color(0xFF2980B9), _exportExcel),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDrop(), const SizedBox(width: 8),
      _fyDrop(), const SizedBox(width: 8),
      _searchField(width: 180),
      const Spacer(),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
      const SizedBox(width: 4),
      _iconBtn(Icons.account_tree_outlined, _showProcessDialog, tooltip: 'View Process', color: _accent),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      _actionBtn('New Budget', Icons.add_rounded, _accent, _goToNew),
      const SizedBox(width: 8),
      _actionBtn('Import', Icons.upload_file_rounded, const Color(0xFF9B59B6), _showImportDialog),
      const SizedBox(width: 8),
      _actionBtn('Export', Icons.download_rounded, const Color(0xFF2980B9), _exportExcel),
      if (_hasFilters) ...[const SizedBox(width: 8), _clearBtn()],
    ]),
  ]);

  Widget _topBarMobile() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Expanded(child: _statusDrop()),
      const SizedBox(width: 8),
      _actionBtn('New', Icons.add_rounded, _accent, _goToNew),
    ]),
    const SizedBox(height: 10),
    _searchField(width: double.infinity),
    const SizedBox(height: 10),
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      _fyDrop(), const SizedBox(width: 6),
      _periodDrop(), const SizedBox(width: 6),
      if (_hasFilters) ...[_clearBtn(), const SizedBox(width: 6)],
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree_outlined, _showProcessDialog, tooltip: 'Process', color: _accent),
      const SizedBox(width: 6),
      _compactBtn('Import', const Color(0xFF9B59B6), _showImportDialog),
      const SizedBox(width: 6),
      _compactBtn('Export', const Color(0xFF2980B9), _exportExcel),
    ])),
  ]);

  // ─ Top bar widgets ────────────────────────────────────────────────────────

  Widget _statusDrop() => _filterDrop<String>(
    value: _statusFilter,
    items: ['All', 'Active', 'Inactive'],
    labels: ['All Budgets', 'Active', 'Inactive'],
    onChanged: (v) { setState(() { _statusFilter = v!; _page = 1; }); _load(); },
  );

  Widget _fyDrop() => _filterDrop<String>(
    value: _fyFilter,
    items: ['All', ..._generateFYOptions()],
    labels: ['All Years', ..._generateFYOptions()],
    onChanged: (v) { setState(() { _fyFilter = v!; _page = 1; }); _load(); },
  );

  Widget _periodDrop() => _filterDrop<String>(
    value: _periodFilter,
    items: _periods,
    labels: _periods.map((p) => p == 'All' ? 'All Periods' : p).toList(),
    onChanged: (v) { setState(() { _periodFilter = v!; _page = 1; }); _load(); },
  );

  Widget _filterDrop<T>({
    required T value,
    required List<T> items,
    required List<String> labels,
    required void Function(T?) onChanged,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
    child: DropdownButtonHideUnderline(child: DropdownButton<T>(
      value: value,
      isDense: true,
      items: List.generate(items.length, (i) =>
          DropdownMenuItem<T>(value: items[i], child: Text(labels[i], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))),
      onChanged: onChanged,
    )),
  );

  Widget _searchField({required double width}) {
    final tf = TextField(
      controller: _searchCtrl,
      decoration: InputDecoration(
        hintText: 'Search budgets…',
        hintStyle: const TextStyle(fontSize: 13),
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () {
                _searchCtrl.clear();
                setState(() { _searchQuery = ''; _page = 1; });
                _load();
              })
            : null,
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        isDense: true,
      ),
      onChanged: (v) {
        setState(() { _searchQuery = v; _page = 1; });
        Future.delayed(const Duration(milliseconds: 500), () { if (_searchQuery == v) _load(); });
      },
    );
    return width == double.infinity ? tf : SizedBox(width: width, child: tf);
  }

  Widget _clearBtn() => TextButton.icon(
    onPressed: _clearFilters,
    icon: const Icon(Icons.clear, size: 14),
    label: const Text('Clear', style: TextStyle(fontSize: 12)),
    style: TextButton.styleFrom(foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 8)),
  );

  Widget _iconBtn(IconData icon, VoidCallback? onTap, {String? tooltip, Color color = const Color(0xFF7F8C8D)}) =>
      Tooltip(message: tooltip ?? '', child: IconButton(
        icon: Icon(icon, size: 20, color: onTap == null ? Colors.grey.shade400 : color),
        onPressed: onTap,
        style: IconButton.styleFrom(backgroundColor: Colors.grey.shade100, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ));

  Widget _actionBtn(String label, IconData icon, Color bg, VoidCallback onTap) =>
      ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );

  Widget _compactBtn(String label, Color bg, VoidCallback onTap) =>
      ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), textStyle: const TextStyle(fontSize: 12)),
        child: Text(label),
      );

  // ── Stats Cards ───────────────────────────────────────────────────────────

  Widget _buildStatsCards() {
    if (_stats == null) {
      return Container(height: 80, color: Colors.white,
          child: const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))));
    }
    final cards = [
      _SC('Total Budgets',   _stats!.totalBudgets.toString(),               Icons.account_balance,               Colors.blue),
      _SC('Active Budgets',  _stats!.activeBudgets.toString(),               Icons.check_circle_outline,           Colors.green),
      _SC('Inactive',        _stats!.inactiveBudgets.toString(),             Icons.pause_circle_outline,           Colors.orange),
      _SC('Total Budgeted',  '₹${_fmtShort(_stats!.totalBudgeted)}',        Icons.account_balance_wallet_outlined, _accent),
      _SC('Total Actual',    '₹${_fmtShort(_stats!.totalActual)}',          Icons.receipt_long_outlined,          Colors.teal),
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (_, cs) {
        if (cs.maxWidth < 600) {
          return Wrap(spacing: 10, runSpacing: 10,
              children: cards.map((c) => SizedBox(width: (cs.maxWidth - 10) / 2, child: _statCard(c))).toList());
        }
        return Row(children: cards.map((c) =>
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _statCard(c)))).toList());
      }),
    );
  }

  Widget _statCard(_SC s) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: s.color.withOpacity(0.07),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: s.color.withOpacity(0.25)),
    ),
    child: Row(children: [
      Icon(s.icon, size: 28, color: s.color),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
        const SizedBox(height: 3),
        Text(s.value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: s.color), overflow: TextOverflow.ellipsis),
      ])),
    ]),
  );

  // ── Table ─────────────────────────────────────────────────────────────────

  Widget _buildTableSection() => Container(
    margin: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: _isLoading
        ? const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))
        : _error != null
            ? _errorState()
            : _budgets.isEmpty
                ? _emptyState()
                : _table(),
  );

  Widget _table() => Scrollbar(
    controller: _hScroll,
    thumbVisibility: true,
    trackVisibility: true,
    thickness: 7,
    radius: const Radius.circular(4),
    notificationPredicate: (n) => n.depth == 1,
    child: Scrollbar(
      controller: _vScroll,
      thumbVisibility: true,
      trackVisibility: true,
      thickness: 7,
      radius: const Radius.circular(4),
      notificationPredicate: (n) => n.depth == 0,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          scrollbars: true,
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
        ),
        child: SingleChildScrollView(
          controller: _vScroll,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFF1A252F)),
              headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.4),
              headingRowHeight: 48,
              dataRowMinHeight: 58,
              dataRowMaxHeight: 72,
              dataTextStyle: const TextStyle(fontSize: 13, color: _dark),
              dividerThickness: 0.8,
              columnSpacing: 16,
              horizontalMargin: 14,
              columns: [
                DataColumn(label: SizedBox(width: 36,
                  child: Checkbox(
                    value: _selectAll,
                    onChanged: (v) => setState(() {
                      _selectAll = v!;
                      if (_selectAll) _selected.addAll(_budgets.map((b) => b.id));
                      else _selected.clear();
                    }),
                    fillColor: WidgetStateProperty.all(Colors.white60),
                    checkColor: const Color(0xFF1A252F),
                  ),
                )),
                const DataColumn(label: SizedBox(width: 220, child: Text('BUDGET NAME'))),
                const DataColumn(label: SizedBox(width: 110, child: Text('FINANCIAL YEAR'))),
                const DataColumn(label: SizedBox(width: 110, child: Text('PERIOD'))),
                const DataColumn(label: SizedBox(width: 80,  child: Text('STATUS'))),
                const DataColumn(label: SizedBox(width: 130, child: Text('TOTAL BUDGETED')), numeric: true),
                const DataColumn(label: SizedBox(width: 130, child: Text('TOTAL ACTUAL')),   numeric: true),
                const DataColumn(label: SizedBox(width: 130, child: Text('VARIANCE')),       numeric: true),
                const DataColumn(label: SizedBox(width: 100, child: Text('ACCOUNTS'))),
                const DataColumn(label: SizedBox(width: 90,  child: Text('ACTIONS'))),
              ],
              rows: _budgets.map(_buildRow).toList(),
            ),
          ),
        ),
      ),
    ),
  );

  DataRow _buildRow(Budget b) {
    final sel      = _selected.contains(b.id);
    final variance = b.totalBudgeted - b.totalActual;
    final over     = variance < 0;

    return DataRow(
      selected: sel,
      color: WidgetStateProperty.resolveWith((s) {
        if (sel) return _accent.withOpacity(0.07);
        if (s.contains(WidgetState.hovered)) return _accent.withOpacity(0.04);
        return null;
      }),
      cells: [
        // Checkbox
        DataCell(SizedBox(width: 36, child: Checkbox(
          value: sel,
          onChanged: (_) => setState(() {
            if (sel) _selected.remove(b.id); else _selected.add(b.id);
            _selectAll = _selected.length == _budgets.length;
          }),
        ))),

        // Budget name — clickable → detail
        DataCell(SizedBox(width: 220,
          child: InkWell(
            onTap: () => _goToDetail(b.id),
            borderRadius: BorderRadius.circular(4),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(b.budgetName,
                style: const TextStyle(color: _accent, fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline, fontSize: 13),
                overflow: TextOverflow.ellipsis, maxLines: 2)),
          ),
        )),

        DataCell(SizedBox(width: 110, child: Text(b.financialYear, style: const TextStyle(fontSize: 13)))),

        DataCell(SizedBox(width: 110, child: _periodBadge(b.budgetPeriod))),

        DataCell(SizedBox(width: 80,  child: _statusBadge(b.isActive))),

        DataCell(SizedBox(width: 130, child: Text('₹${_fmt(b.totalBudgeted)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right))),

        DataCell(SizedBox(width: 130, child: Text('₹${_fmt(b.totalActual)}',
            style: TextStyle(fontSize: 13, color: Colors.teal.shade700), textAlign: TextAlign.right))),

        DataCell(SizedBox(width: 130, child: Text(
          '${over ? '-' : ''}₹${_fmt(variance.abs())}',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
              color: over ? Colors.red : Colors.green.shade700),
          textAlign: TextAlign.right,
        ))),

        DataCell(SizedBox(width: 100, child: Row(children: [
          Icon(Icons.list_alt, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 4),
          Text('${b.accountLines.length} accounts', style: const TextStyle(fontSize: 12)),
        ]))),

        // Actions
        DataCell(SizedBox(width: 90,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onSelected: (v) {
              switch (v) {
                case 'view':   _goToDetail(b.id); break;
                case 'edit':   _goToEdit(b.id); break;
                case 'clone':  _clone(b); break;
                case 'toggle': _toggle(b); break;
                case 'delete': _delete(b); break;
              }
            },
            itemBuilder: (_) => [
              _menuItem('view',   Icons.visibility_outlined,    'View Details',        Colors.blue),
              _menuItem('edit',   Icons.edit_outlined,           'Edit Budget',         Colors.orange),
              _menuItem('clone',  Icons.copy_outlined,           'Clone Budget',        Colors.purple),
              _menuItem('toggle', b.isActive ? Icons.toggle_off : Icons.toggle_on,
                  b.isActive ? 'Deactivate' : 'Activate',
                  b.isActive ? Colors.orange : Colors.green),
              const PopupMenuDivider(),
              _menuItem('delete', Icons.delete_outline, 'Delete', Colors.red),
            ],
          ),
        )),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String val, IconData icon, String label, Color color) =>
      PopupMenuItem<String>(value: val,
          child: Row(children: [Icon(icon, size: 16, color: color), const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 13))]));

  // ── Pagination ────────────────────────────────────────────────────────────

  Widget _buildPagination() {
    if (_budgets.isEmpty && !_isLoading) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: LayoutBuilder(builder: (_, cs) {
        final info = Text(
          'Showing ${((_page - 1) * _pageSize + 1).clamp(0, _totalCount)}–${(_page * _pageSize).clamp(0, _totalCount)} of $_totalCount',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        );
        final btns = _pageButtons();
        if (cs.maxWidth < 600) return Column(children: [info, const SizedBox(height: 10), btns]);
        return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [info, btns]);
      }),
    );
  }

  Widget _pageButtons() {
    final pages = List.generate(_totalPages.clamp(0, 7), (i) => i + 1);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(icon: const Icon(Icons.chevron_left), onPressed: _page > 1 ? () { setState(() => _page--); _load(); } : null),
      ...pages.map((n) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          onTap: () { setState(() => _page = n); _load(); },
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _page == n ? _accent : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(n.toString(), style: TextStyle(
                color: _page == n ? Colors.white : Colors.grey.shade700,
                fontWeight: _page == n ? FontWeight.bold : FontWeight.normal,
                fontSize: 13)),
          ),
        ),
      )),
      IconButton(icon: const Icon(Icons.chevron_right), onPressed: _page < _totalPages ? () { setState(() => _page++); _load(); } : null),
    ]);
  }

  // ── Empty / Error ─────────────────────────────────────────────────────────

  Widget _emptyState() => SizedBox(height: 300, child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.account_balance_outlined, size: 72, color: Colors.grey.shade300),
    const SizedBox(height: 16),
    Text('No budgets found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
    const SizedBox(height: 8),
    Text('Create your first budget to get started', style: TextStyle(color: Colors.grey.shade500)),
    const SizedBox(height: 24),
    ElevatedButton.icon(
      onPressed: _goToNew, icon: const Icon(Icons.add), label: const Text('Create Budget'),
      style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13)),
    ),
  ])));

  Widget _errorState() => SizedBox(height: 300, child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.error_outline, size: 60, color: Colors.red.shade300),
    const SizedBox(height: 16),
    Text('Failed to load', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
    const SizedBox(height: 8),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(_error ?? '', style: TextStyle(color: Colors.grey.shade500), textAlign: TextAlign.center)),
    const SizedBox(height: 20),
    ElevatedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Retry'),
        style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white)),
  ])));

  // ── View Process Dialog ───────────────────────────────────────────────────

  void _showProcessDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      builder: (ctx) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 340,
            constraints: const BoxConstraints(maxWidth: 340),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [_navy, _navyMid]),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
                ),
                child: Row(children: [
                  const Icon(Icons.account_tree_outlined, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Budget — Process Flow',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
                  InkWell(onTap: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close, color: Colors.white, size: 16)),
                ]),
              ),
              ClipRRect(
                borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8)),
                child: Image.asset(
                  'assets/budget.png',
                  width: 340,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _fallbackProcess(),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _fallbackProcess() {
    final steps = [
      {'icon': Icons.add_chart,          'label': 'Create\nBudget',   'color': Colors.blue},
      {'icon': Icons.list_alt,           'label': 'Add Account\nLines', 'color': Colors.indigo},
      {'icon': Icons.edit_calendar,      'label': 'Set Monthly\nAmounts','color': Colors.purple},
      {'icon': Icons.check_circle,       'label': 'Activate\nBudget',  'color': Colors.green},
      {'icon': Icons.compare_arrows,     'label': 'Track\nActuals',    'color': Colors.teal},
      {'icon': Icons.bar_chart,          'label': 'View\nReports',     'color': Colors.orange},
    ];
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 12,
        children: steps.expand((s) => [
          Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (s['color'] as Color).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: s['color'] as Color, width: 1.5),
              ),
              child: Column(children: [
                Icon(s['icon'] as IconData, color: s['color'] as Color, size: 24),
                const SizedBox(height: 4),
                Text(s['label'] as String, textAlign: TextAlign.center,
                    style: TextStyle(color: s['color'] as Color, fontSize: 9, fontWeight: FontWeight.bold)),
              ]),
            ),
          ]),
          if (s != steps.last)
            Padding(padding: const EdgeInsets.only(top: 16),
                child: Icon(Icons.arrow_forward_rounded, color: Colors.grey.shade400, size: 16)),
        ]).toList(),
      ),
    );
  }

  // ── Import Dialog ─────────────────────────────────────────────────────────

  void _showImportDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BudgetImportDialog(onSuccess: () { Navigator.pop(ctx); _refresh(); }),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<String> _generateFYOptions() {
    final now  = DateTime.now();
    final base = now.month >= 4 ? now.year : now.year - 1;
    return List.generate(5, (i) {
      final y = base - 2 + i;
      return '$y-${(y + 1).toString().substring(2)}';
    });
  }

  String _fmt(double v) => NumberFormat('#,##0.00').format(v);
  String _fmtShort(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000)   return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)     return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  Widget _statusBadge(bool active) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: active ? Colors.green.shade50 : Colors.grey.shade200,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(active ? 'Active' : 'Inactive',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
            color: active ? Colors.green.shade700 : Colors.grey.shade600)),
  );

  Widget _periodBadge(String period) {
    final colors = {
      'Monthly':   (bg: Colors.blue.shade50,   fg: Colors.blue.shade700),
      'Quarterly': (bg: Colors.purple.shade50, fg: Colors.purple.shade700),
      'Yearly':    (bg: Colors.teal.shade50,   fg: Colors.teal.shade700),
    };
    final c = colors[period] ?? (bg: Colors.grey.shade200, fg: Colors.grey.shade700);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(20)),
      child: Text(period, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.fg)),
    );
  }
}

// ============================================================================
// STAT DATA
// ============================================================================

class _SC {
  final String label, value;
  final IconData icon;
  final Color color;
  const _SC(this.label, this.value, this.icon, this.color);
}

// ============================================================================
// IMPORT DIALOG
// ============================================================================

class _BudgetImportDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  const _BudgetImportDialog({required this.onSuccess});

  @override
  State<_BudgetImportDialog> createState() => _BudgetImportDialogState();
}

class _BudgetImportDialogState extends State<_BudgetImportDialog> {
  bool _dlLoading  = false;
  bool _uploading  = false;
  String? _filename;
  Map<String, dynamic>? _result;

  static const _accent  = Color(0xFF3D8EFF);
  static const _purple  = Color(0xFF9B59B6);

  static const _monthLabels = [
    'Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec','Jan','Feb','Mar'
  ];

  // ── Download Template ─────────────────────────────────────────────────────

  Future<void> _downloadTemplate() async {
    setState(() => _dlLoading = true);
    try {
      final header = [
        'Budget Name *', 'Financial Year * (e.g. 2025-26)', 'Budget Period (Monthly/Quarterly/Yearly)',
        'Account Name *', 'Account Type',
        ..._monthLabels.map((m) => '$m Amount'),
        'Annual Amount (if monthly not given)', 'Notes',
      ];
      final rows = <List<dynamic>>[
        header,
        // Sample 1
        ['FY 2025-26 Annual', '2025-26', 'Monthly', 'Sales', 'Income',
          50000, 55000, 60000, 65000, 70000, 75000, 80000, 85000, 90000, 95000, 100000, 110000,
          '', 'Revenue budget'],
        // Sample 2
        ['FY 2025-26 Annual', '2025-26', 'Monthly', 'Rent Expense', 'Expense',
          50000, 50000, 50000, 50000, 50000, 50000, 50000, 50000, 50000, 50000, 50000, 50000,
          '', 'Office rent'],
        // Sample 3 - annual only
        ['FY 2025-26 Annual', '2025-26', 'Monthly', 'Salary Expense', 'Expense',
          '', '', '', '', '', '', '', '', '', '', '', '',
          600000, 'Will be split equally across 12 months'],
        // Instructions
        ['INSTRUCTIONS', 'Delete rows 3-5 before importing',
          'Period options: Monthly, Quarterly, Yearly',
          'Account Name must match your Chart of Accounts exactly',
          'Account Type: Asset, Liability, Equity, Income, Expense, etc.',
          ..._monthLabels.map((_) => ''),
          'OR fill Annual Amount and leave monthly blank', ''],
      ];

      await ExportHelper.exportToExcel(
        data: rows,
        filename: 'budget_import_template_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      );
      _snack('Template downloaded ✓', Colors.green);
    } catch (e) { _snack('Download failed: $e', Colors.red); }
    finally { setState(() => _dlLoading = false); }
  }

  // ── Upload & Import ───────────────────────────────────────────────────────

  Future<void> _pickAndImport() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.first;
      if (file.bytes == null) { _snack('Could not read file', Colors.red); return; }

      setState(() { _uploading = true; _filename = file.name; _result = null; });

      List<List<dynamic>> rows;
      final ext = (file.extension ?? '').toLowerCase();
      rows = ext == 'csv' ? _parseCSV(file.bytes!) : _parseExcel(file.bytes!);

      if (rows.length < 2) throw Exception('File must have a header row + at least one data row');

      final valid  = <Map<String, dynamic>>[];
      final errors = <String>[];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        final budgetName  = _cell(row, 0);
        final fy          = _cell(row, 1);
        final period      = _cell(row, 2, 'Monthly');
        final accountName = _cell(row, 3);
        final accountType = _cell(row, 4, 'Expense');

        if (budgetName.isEmpty || budgetName.toUpperCase().contains('INSTRUCTION')) continue;
        if (budgetName.isEmpty) { errors.add('Row ${i+1}: Budget Name required'); continue; }
        if (fy.isEmpty)         { errors.add('Row ${i+1}: Financial Year required'); continue; }
        if (accountName.isEmpty){ errors.add('Row ${i+1}: Account Name required'); continue; }

        // Parse 12 monthly amounts (cols 5-16)
        List<double> monthly = List.generate(12, (m) {
          final v = _cell(row, 5 + m);
          return double.tryParse(v.replaceAll(',', '')) ?? 0;
        });

        // If all zero, try annual amount (col 17)
        final total = monthly.reduce((a, b) => a + b);
        if (total == 0) {
          final annual = double.tryParse(_cell(row, 17).replaceAll(',', '')) ?? 0;
          if (annual > 0) {
            final per = annual / 12;
            monthly = List.filled(12, per);
          }
        }

        valid.add({
          'budgetName':     budgetName,
          'financialYear':  fy,
          'budgetPeriod':   period,
          'accountName':    accountName,
          'accountType':    accountType,
          'monthlyAmounts': monthly,
          'notes':          _cell(row, 18),
        });
      }

      if (valid.isEmpty) {
        setState(() => _uploading = false);
        _snack('No valid rows found', Colors.red);
        return;
      }

      // Confirm
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Confirm Import'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${valid.length} account line(s) ready to import',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('${errors.length} row(s) skipped', style: const TextStyle(color: Colors.orange, fontSize: 13)),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 100),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
              child: SingleChildScrollView(
                  child: Text(errors.join('\n'), style: const TextStyle(fontSize: 11, color: Colors.red))),
            ),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white),
            child: Text('Import ${valid.length} Lines'),
          ),
        ],
      ));

      if (ok != true) { setState(() { _uploading = false; _filename = null; }); return; }

      final res = await BudgetService.bulkImport(valid, file.bytes!, file.name);
      setState(() { _uploading = false; _result = res['data']; });
      if (res['success'] == true) {
        _snack('✅ Imported ${res['data']['successCount']} lines!', Colors.green);
        widget.onSuccess();
      }
    } catch (e) {
      setState(() { _uploading = false; _filename = null; });
      _snack('Import failed: $e', Colors.red);
    }
  }

  // ── Parsers ───────────────────────────────────────────────────────────────

  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    final book  = xl.Excel.decodeBytes(bytes);
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
      final fields = <String>[];
      final cur    = StringBuffer();
      bool inQ = false;
      for (int i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == '"') { if (inQ && i + 1 < line.length && line[i+1] == '"') { cur.write('"'); i++; } else inQ = !inQ; }
        else if (ch == ',' && !inQ) { fields.add(cur.toString().trim()); cur.clear(); }
        else cur.write(ch);
      }
      fields.add(cur.toString().trim());
      return fields;
    }).toList();
  }

  String _cell(List row, int i, [String def = '']) =>
      i < row.length ? (row[i]?.toString().trim() ?? def) : def;

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Header
            Row(children: [
              Container(padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: _purple.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.upload_file_rounded, color: _purple, size: 24)),
              const SizedBox(width: 12),
              const Expanded(child: Text('Bulk Import Budgets', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),

            const Divider(height: 24),

            // Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.info_outline, color: Colors.blue.shade700, size: 16), const SizedBox(width: 8),
                  Text('How to import', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue.shade700))]),
                const SizedBox(height: 8),
                Text('1. Download the sample template below\n2. Fill in budget name, financial year, account name & amounts\n3. Each row = one account line in a budget\n4. Multiple rows with same Budget Name = same budget\n5. Upload completed file (.xlsx / .csv)',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade800, height: 1.7)),
              ]),
            ),

            const SizedBox(height: 16),

            // Download
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: _dlLoading || _uploading ? null : _downloadTemplate,
              icon: _dlLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(_dlLoading ? 'Downloading…' : 'Download Sample Excel Template'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF27AE60), foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            )),

            const SizedBox(height: 10),

            // Upload
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: _dlLoading || _uploading ? null : _pickAndImport,
              icon: _uploading
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _purple))
                  : const Icon(Icons.upload_file_rounded, size: 18),
              label: Text(_uploading ? 'Processing…' : 'Choose & Upload Excel / CSV'),
              style: OutlinedButton.styleFrom(foregroundColor: _purple, side: const BorderSide(color: _purple),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            )),

            if (_filename != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade200)),
                child: Row(children: [Icon(Icons.check_circle, color: Colors.green.shade700, size: 16), const SizedBox(width: 8),
                  Expanded(child: Text(_filename!, style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis))]),
              ),
            ],

            // Results
            if (_result != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              const Text('Import Results', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                child: Column(children: [
                  _resRow('Total Processed', _result!['totalProcessed']?.toString() ?? '0', Colors.blue),
                  const SizedBox(height: 8),
                  _resRow('Successfully Imported', _result!['successCount']?.toString() ?? '0', Colors.green),
                  const SizedBox(height: 8),
                  _resRow('Failed', _result!['failedCount']?.toString() ?? '0', Colors.red),
                ]),
              ),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                child: const Text('Done'),
              )),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _resRow(String label, String value, Color color) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
            child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13))),
      ]);
}