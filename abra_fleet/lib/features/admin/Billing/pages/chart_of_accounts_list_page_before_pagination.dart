// ============================================================================
// CHART OF ACCOUNTS LIST PAGE
// ============================================================================
// File: lib/screens/billing/pages/chart_of_accounts_list_page.dart
// Zoho Books style: List (left) + Detail panel (right)
// Navy blue gradient theme | Fully responsive | Cursor-based scroll
// Import (download template → upload → parse → confirm → API)
// Export to Excel | View Process image
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
import '../../../../core/services/chart_of_account_service.dart';
import '../../../../core/utils/export_helper.dart';
import 'new_chart_of_account.dart';
import 'chart_of_account_detail.dart';

// ── Colors ────────────────────────────────────────────────────────────────────
const _kNavyDark   = Color(0xFF0F172A);
const _kNavy       = Color(0xFF1E3A5F);
const _kAccent     = Color(0xFF2563EB);
const _kPageBg     = Color(0xFFF8FAFC);

// ── Account Types ─────────────────────────────────────────────────────────────
const _kAllTypes = [
  'All',
  'Asset',
  'Liability',
  'Equity',
  'Income',
  'Expense',
  'Other Current Asset',
  'Fixed Asset',
  'Other Asset',
  'Accounts Receivable',
  'Cash',
  'Stock',
  'Other Current Liability',
  'Accounts Payable',
  'Non Current Liability',
  'Other Liability',
  'Cost Of Goods Sold',
  'Other Expense',
  'Other Income',
];

// ============================================================================
class ChartOfAccountsListPage extends StatefulWidget {
  const ChartOfAccountsListPage({Key? key}) : super(key: key);

  @override
  State<ChartOfAccountsListPage> createState() => _ChartOfAccountsListPageState();
}

class _ChartOfAccountsListPageState extends State<ChartOfAccountsListPage> {
  // ── Data ──────────────────────────────────────────────────────────────────
  List<ChartOfAccount> _accounts = [];
  CoaStats? _stats;
  bool _isLoading = true;
  String? _error;

  // ── Filters ───────────────────────────────────────────────────────────────
  String _typeFilter   = 'All';
  String _statusFilter = 'Active'; // Active | Inactive | All
  String _searchQuery  = '';

  // ── Selected account (detail panel) ──────────────────────────────────────
  ChartOfAccount? _selected;

  // ── Scroll ────────────────────────────────────────────────────────────────
  final _listScrollCtrl = ScrollController();
  final _hScrollCtrl    = ScrollController();
  final _searchCtrl     = TextEditingController();

  // ============================================================================
  @override
  void initState() {
    super.initState();
    _load();
    _loadStats();
  }

  @override
  void dispose() {
    _listScrollCtrl.dispose();
    _hScrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── API ───────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final result = await ChartOfAccountService.getAccounts(
        accountType: _typeFilter == 'All' ? null : _typeFilter,
        isActive: _statusFilter == 'All' ? null : _statusFilter == 'Active',
        search: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
        limit: 500,
      );
      setState(() {
        _accounts = result.accounts;
        _isLoading = false;
        // keep selection valid
        if (_selected != null) {
          final found = _accounts.where((a) => a.id == _selected!.id);
          _selected = found.isNotEmpty ? found.first : null;
        }
      });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _loadStats() async {
    try {
      final s = await ChartOfAccountService.getStats();
      if (mounted) setState(() => _stats = s);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    setState(() => _selected = null);
    await Future.wait([_load(), _loadStats()]);
    _snack('Refreshed', Colors.green);
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<void> _goToNew() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const NewChartOfAccountScreen()),
    );
    if (ok == true) _refresh();
  }

  Future<void> _goToEdit(ChartOfAccount acc) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => NewChartOfAccountScreen(accountId: acc.id)),
    );
    if (ok == true) _refresh();
  }

  void _goToDetail(ChartOfAccount acc) {
    final w = MediaQuery.of(context).size.width;
    if (w >= 900) {
      // Wide: show in right panel
      setState(() => _selected = acc);
    } else {
      // Narrow: navigate to full page
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChartOfAccountDetailPage(accountId: acc.id)),
      ).then((_) => _refresh());
    }
  }

  // ── Toggle Active ─────────────────────────────────────────────────────────

  Future<void> _toggleActive(ChartOfAccount acc) async {
    if (acc.isSystemAccount) {
      _snack('System accounts cannot be deactivated', Colors.orange);
      return;
    }
    try {
      await ChartOfAccountService.toggleActive(acc.id, !acc.isActive);
      _snack(acc.isActive ? 'Account deactivated' : 'Account activated', Colors.green);
      _refresh();
    } catch (e) {
      _snack('Failed: $e', Colors.red);
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> _delete(ChartOfAccount acc) async {
    if (acc.isSystemAccount) {
      _snack('System accounts cannot be deleted', Colors.orange);
      return;
    }
    if (acc.transactionCount > 0) {
      _snack('Cannot delete account with transactions', Colors.orange);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Account?'),
        content: Text('Delete "${acc.accountName}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ChartOfAccountService.deleteAccount(acc.id);
      if (_selected?.id == acc.id) setState(() => _selected = null);
      _snack('Account deleted', Colors.red);
      _refresh();
    } catch (e) {
      _snack('Delete failed: $e', Colors.red);
    }
  }

  // ── Export ────────────────────────────────────────────────────────────────

  Future<void> _exportExcel() async {
    try {
      _snack('Preparing export…', Colors.blueGrey);
      final all = await ChartOfAccountService.getAllAccounts();
      if (all.isEmpty) { _snack('No data to export', Colors.orange); return; }
      final rows = <List<dynamic>>[
        ['Account Code', 'Account Name', 'Account Type', 'Account Sub Type',
          'Parent Account', 'Description', 'Currency', 'Status',
          'Closing Balance', 'Balance Type', 'System Account', 'Transactions'],
        ...all.map((a) => [
          a.accountCode, a.accountName, a.accountType, a.accountSubType,
          a.parentAccountName ?? '', a.description ?? '', a.currency,
          a.isActive ? 'Active' : 'Inactive',
          a.closingBalance.toStringAsFixed(2), a.balanceType,
          a.isSystemAccount ? 'Yes' : 'No', a.transactionCount.toString(),
        ]),
      ];
      await ExportHelper.exportToExcel(
        data: rows,
        filename: 'chart_of_accounts_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
      );
      _snack('✅ Exported ${all.length} accounts', Colors.green);
    } catch (e) {
      _snack('Export failed: $e', Colors.red);
    }
  }

  // ── Import ────────────────────────────────────────────────────────────────

  void _showImportDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ImportDialog(onSuccess: () { Navigator.pop(ctx); _refresh(); }),
    );
  }

  // ── View Process ──────────────────────────────────────────────────────────

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
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [_kNavyDark, _kNavy]),
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_tree_outlined, color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Chart of Accounts — Process Flow',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
                      InkWell(onTap: () => Navigator.pop(ctx),
                          child: const Icon(Icons.close, color: Colors.white, size: 16)),
                    ],
                  ),
                ),
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10)),
                  child: Image.asset(
                    'assets/chart_of_accounts.png',
                    width: 340,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildFallbackFlow(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackFlow() {
    final steps = [
      {'label': 'Create\nAccount', 'icon': Icons.add_circle_outline, 'color': Colors.blue},
      {'label': 'Link to\nModule', 'icon': Icons.link, 'color': Colors.teal},
      {'label': 'Post\nJournal', 'icon': Icons.book_outlined, 'color': Colors.orange},
      {'label': 'Balance\nUpdates', 'icon': Icons.account_balance, 'color': Colors.purple},
      {'label': 'View\nReports', 'icon': Icons.bar_chart, 'color': Colors.green},
    ];
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8, runSpacing: 12,
          children: steps.expand((s) => [
            Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (s['color'] as Color).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: s['color'] as Color),
                ),
                child: Column(children: [
                  Icon(s['icon'] as IconData, color: s['color'] as Color, size: 24),
                  const SizedBox(height: 4),
                  Text(s['label'] as String,
                      style: TextStyle(fontSize: 10, color: s['color'] as Color, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                ]),
              ),
            ]),
            if (s != steps.last)
              Padding(padding: const EdgeInsets.only(top: 12),
                  child: Icon(Icons.arrow_forward, color: Colors.grey.shade400, size: 16)),
          ]).toList(),
        ),
      ]),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color,
          behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 3)));
  }

  // ============================================================================
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: LayoutBuilder(builder: (_, c) {
              if (c.maxWidth >= 900) {
                // Wide: split layout
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 380, child: _buildAccountList()),
                    const VerticalDivider(width: 1),
                    Expanded(child: _selected != null
                        ? _buildDetailPanel(_selected!)
                        : _buildEmptyDetail()),
                  ],
                );
              }
              // Narrow: list only
              return _buildAccountList();
            }),
          ),
        ],
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_kNavyDark, _kNavy],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: const Text('Chart of Accounts',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: _refresh,
              tooltip: 'Refresh',
            ),
            IconButton(
              icon: const Icon(Icons.account_tree_outlined, color: Colors.white),
              onPressed: _showProcessDialog,
              tooltip: 'View Process',
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  // ── Top Bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: LayoutBuilder(builder: (_, c) {
        final isMobile = c.maxWidth < 650;
        if (isMobile) return _topBarMobile();
        return _topBarDesktop();
      }),
    );
  }

  Widget _topBarDesktop() => Row(children: [
    // Status dropdown
    _statusDropdown(),
    const SizedBox(width: 10),
    // Type dropdown
    _typeDropdown(),
    const SizedBox(width: 10),
    // Search
    SizedBox(
      width: 240,
      child: _searchField(),
    ),
    const Spacer(),
    _actionBtn('Import', Icons.upload_file_rounded, const Color(0xFF9B59B6), _showImportDialog),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, const Color(0xFF2980B9), _exportExcel),
    const SizedBox(width: 8),
    _actionBtn('New Account', Icons.add_rounded, _kAccent, _goToNew),
  ]);

  Widget _topBarMobile() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Expanded(child: _statusDropdown()),
      const SizedBox(width: 8),
      _actionBtn('New', Icons.add_rounded, _kAccent, _goToNew),
    ]),
    const SizedBox(height: 8),
    _searchField(),
    const SizedBox(height: 8),
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _typeDropdown(),
        const SizedBox(width: 8),
        _compactBtn('Import', const Color(0xFF9B59B6), _showImportDialog),
        const SizedBox(width: 8),
        _compactBtn('Export', const Color(0xFF2980B9), _exportExcel),
      ]),
    ),
  ]);

  Widget _statusDropdown() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _statusFilter,
        isDense: true,
        items: ['Active', 'Inactive', 'All'].map((s) =>
            DropdownMenuItem(value: s, child: Text('$s Accounts',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))).toList(),
        onChanged: (v) { if (v != null) { setState(() => _statusFilter = v); _load(); } },
      ),
    ),
  );

  Widget _typeDropdown() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _typeFilter,
        isDense: true,
        hint: const Text('All Types', style: TextStyle(fontSize: 13)),
        items: _kAllTypes.map((t) =>
            DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
        onChanged: (v) { if (v != null) { setState(() => _typeFilter = v); _load(); } },
      ),
    ),
  );

  Widget _searchField() => TextField(
    controller: _searchCtrl,
    decoration: InputDecoration(
      hintText: 'Search accounts…',
      hintStyle: const TextStyle(fontSize: 13),
      prefixIcon: const Icon(Icons.search, size: 18),
      suffixIcon: _searchQuery.isNotEmpty
          ? IconButton(icon: const Icon(Icons.clear, size: 16),
              onPressed: () { _searchCtrl.clear(); setState(() { _searchQuery = ''; }); _load(); })
          : null,
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      isDense: true,
    ),
    onChanged: (v) {
      setState(() => _searchQuery = v);
      Future.delayed(const Duration(milliseconds: 500), () { if (_searchQuery == v) _load(); });
    },
  );

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

  Widget _compactBtn(String label, Color bg, VoidCallback onTap) => ElevatedButton(
    onPressed: onTap,
    style: ElevatedButton.styleFrom(
        backgroundColor: bg, foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontSize: 12)),
    child: Text(label),
  );

  // ── Account List (left panel) ─────────────────────────────────────────────

  Widget _buildAccountList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.error_outline, size: 60, color: Colors.red.shade300),
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(color: Colors.grey.shade600), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Retry'),
            style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white)),
      ]));
    }
    if (_accounts.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.account_tree_outlined, size: 72, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text('No accounts found', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: _goToNew, icon: const Icon(Icons.add), label: const Text('Add Account'),
            style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white)),
      ]));
    }

    // Group by account type
    final grouped = <String, List<ChartOfAccount>>{};
    for (final acc in _accounts) {
      grouped.putIfAbsent(acc.accountType, () => []).add(acc);
    }

    return Container(
      color: Colors.white,
      child: Scrollbar(
        controller: _listScrollCtrl,
        thumbVisibility: true,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
          ),
          child: ListView(
            controller: _listScrollCtrl,
            children: [
              // Header row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_kNavyDark, _kNavy]),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
                ),
                child: Row(children: [
                  const Expanded(child: Text('ACCOUNT NAME',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5))),
                  const SizedBox(width: 8),
                  SizedBox(width: 130, child: Text('TYPE',
                      style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      textAlign: TextAlign.right)),
                ]),
              ),
              // Grouped list
              ...grouped.entries.expand((entry) => [
                // Group header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: const Color(0xFFF1F5F9),
                  child: Text(entry.key.toUpperCase(),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                          color: Colors.grey.shade600, letterSpacing: 0.8)),
                ),
                // Accounts in group
                ...entry.value.map((acc) => _buildAccountRow(acc)),
              ]),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountRow(ChartOfAccount acc) {
    final isSelected = _selected?.id == acc.id;
    return InkWell(
      onTap: () => _goToDetail(acc),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? _kAccent.withOpacity(0.08) : Colors.transparent,
          border: Border(
            left: BorderSide(color: isSelected ? _kAccent : Colors.transparent, width: 3),
            bottom: BorderSide(color: Colors.grey.shade100, width: 1),
          ),
        ),
        child: Row(
          children: [
            // Active indicator dot
            Container(
              width: 7, height: 7,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: acc.isActive ? Colors.green : Colors.grey.shade400,
                shape: BoxShape.circle,
              ),
            ),
            // Account name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(acc.accountName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? _kAccent : const Color(0xFF1E293B),
                      ),
                      overflow: TextOverflow.ellipsis),
                  if (acc.accountCode.isNotEmpty)
                    Text(acc.accountCode,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Type + actions
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(acc.accountType,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (!acc.isSystemAccount)
                  InkWell(
                    onTap: () => _goToEdit(acc),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text('Edit',
                          style: TextStyle(fontSize: 13, color: _kAccent, fontWeight: FontWeight.w600)),
                    ),
                  ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, size: 16, color: Colors.grey.shade500),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: EdgeInsets.zero,
                  onSelected: (v) {
                    switch (v) {
                      case 'edit':   _goToEdit(acc); break;
                      case 'toggle': _toggleActive(acc); break;
                      case 'delete': _delete(acc); break;
                    }
                  },
                  itemBuilder: (_) => [
                    if (!acc.isSystemAccount) ...[
                      PopupMenuItem(value: 'edit', child: Row(children: [const Icon(Icons.edit_outlined, size: 16, color: Colors.blue), const SizedBox(width: 8), const Text('Edit', style: TextStyle(fontSize: 13))])),
                      PopupMenuItem(value: 'toggle', child: Row(children: [
                        Icon(acc.isActive ? Icons.block : Icons.check_circle_outline, size: 16, color: acc.isActive ? Colors.orange : Colors.green),
                        const SizedBox(width: 8),
                        Text(acc.isActive ? 'Deactivate' : 'Activate', style: const TextStyle(fontSize: 13)),
                      ])),
                      const PopupMenuDivider(),
                      PopupMenuItem(value: 'delete', child: Row(children: [const Icon(Icons.delete_outline, size: 16, color: Colors.red), const SizedBox(width: 8), const Text('Delete', style: TextStyle(fontSize: 13, color: Colors.red))])),
                    ] else
                      const PopupMenuItem(enabled: false, child: Text('System Account', style: TextStyle(fontSize: 12, color: Colors.grey))),
                  ],
                ),
              ]),
            ]),
          ],
        ),
      ),
    );
  }

  // ── Detail Panel (right, wide screens) ───────────────────────────────────

  Widget _buildEmptyDetail() => Container(
    color: _kPageBg,
    child: Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.account_balance_wallet_outlined, size: 72, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text('Select an account to view details',
            style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
      ]),
    ),
  );

  Widget _buildDetailPanel(ChartOfAccount acc) {
    return Container(
      color: _kPageBg,
      child: Column(
        children: [
          // Panel header
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_kNavyDark, _kNavy]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(acc.accountName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    Text(acc.accountType,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ]),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: acc.isActive ? Colors.green.shade100 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(acc.isActive ? 'Active' : 'Inactive',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                          color: acc.isActive ? Colors.green.shade800 : Colors.grey.shade600)),
                ),
                const SizedBox(width: 8),
                if (!acc.isSystemAccount)
                  ElevatedButton.icon(
                    onPressed: () => _goToEdit(acc),
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: const Text('Edit'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                const SizedBox(width: 8),
                // Full detail button
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ChartOfAccountDetailPage(accountId: acc.id))).then((_) => _refresh()),
                  icon: const Icon(Icons.open_in_full, size: 14),
                  label: const Text('Full View'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kNavy, side: const BorderSide(color: _kNavy),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Closing balance
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Row(children: [
              Expanded(child: _infoTile('Closing Balance',
                  '₹${NumberFormat('#,##0.00').format(acc.closingBalance)} (${acc.balanceType})',
                  color: _kAccent)),
              const SizedBox(width: 16),
              Expanded(child: _infoTile('Account Code', acc.accountCode.isNotEmpty ? acc.accountCode : '-')),
              const SizedBox(width: 16),
              Expanded(child: _infoTile('Currency', acc.currency)),
              const SizedBox(width: 16),
              Expanded(child: _infoTile('System Account', acc.isSystemAccount ? 'Yes' : 'No')),
            ]),
          ),
          const Divider(height: 1),
          // Description
          if (acc.description != null && acc.description!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: Colors.white,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Description', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(acc.description!, style: const TextStyle(fontSize: 14, color: Color(0xFF374151))),
              ]),
            ),
            const Divider(height: 1),
          ],
          // Transactions section
          Expanded(
            child: _DetailTransactions(accountId: acc.id),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(String label, String value, {Color? color}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color ?? const Color(0xFF0F172A))),
    ],
  );
}

// ============================================================================
// DETAIL TRANSACTIONS WIDGET (used in right panel)
// ============================================================================

class _DetailTransactions extends StatefulWidget {
  final String accountId;
  const _DetailTransactions({required this.accountId});

  @override
  State<_DetailTransactions> createState() => _DetailTransactionsState();
}

class _DetailTransactionsState extends State<_DetailTransactions> {
  List<AccountTransaction> _txns = [];
  bool _loading = true;
  final _hScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_DetailTransactions old) {
    super.didUpdateWidget(old);
    if (old.accountId != widget.accountId) _load();
  }

  @override
  void dispose() { _hScroll.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final t = await ChartOfAccountService.getTransactions(widget.accountId);
      if (mounted) setState(() { _txns = t; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kPageBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('Transactions',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _txns.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('There are no transactions available',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                      ]))
                    : Scrollbar(
                        controller: _hScroll,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _hScroll,
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                            headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF374151)),
                            dataTextStyle: const TextStyle(fontSize: 12),
                            dataRowMinHeight: 44,
                            columnSpacing: 20,
                            horizontalMargin: 20,
                            columns: const [
                              DataColumn(label: Text('DATE')),
                              DataColumn(label: Text('DESCRIPTION')),
                              DataColumn(label: Text('REF TYPE')),
                              DataColumn(label: Text('REF #')),
                              DataColumn(label: Text('DEBIT')),
                              DataColumn(label: Text('CREDIT')),
                              DataColumn(label: Text('BALANCE')),
                            ],
                            rows: _txns.map((t) => DataRow(cells: [
                              DataCell(Text(DateFormat('dd MMM yyyy').format(t.date))),
                              DataCell(SizedBox(width: 200, child: Text(t.description, overflow: TextOverflow.ellipsis))),
                              DataCell(Text(t.referenceType)),
                              DataCell(Text(t.referenceNumber, style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.w600))),
                              DataCell(Text(t.debit > 0 ? '₹${NumberFormat('#,##0.00').format(t.debit)}' : '-',
                                  style: const TextStyle(color: Colors.red))),
                              DataCell(Text(t.credit > 0 ? '₹${NumberFormat('#,##0.00').format(t.credit)}' : '-',
                                  style: const TextStyle(color: Colors.green))),
                              DataCell(Text('₹${NumberFormat('#,##0.00').format(t.balance)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold))),
                            ])).toList(),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// IMPORT DIALOG
// ============================================================================

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

  static const _kAccent = Color(0xFF2563EB);
  static const _purple  = Color(0xFF9B59B6);

  Future<void> _downloadTemplate() async {
    setState(() => _dlLoading = true);
    try {
      final rows = <List<dynamic>>[
        // Header
        ['Account Code *', 'Account Name *', 'Account Type *', 'Account Sub Type *',
          'Parent Account Name', 'Description', 'Currency', 'Is Active (Yes/No)'],
        // Sample 1
        ['1001', 'Cash in Hand', 'Asset', 'Cash', '', 'Physical cash held', 'INR', 'Yes'],
        // Sample 2
        ['1002', 'HDFC Bank Account', 'Asset', 'Cash', '', 'Main bank account', 'INR', 'Yes'],
        // Sample 3
        ['5001', 'Rent Expense', 'Expense', 'Expense', '', 'Monthly office rent', 'INR', 'Yes'],
        // Sample 4
        ['4001', 'Sales Revenue', 'Income', 'Income', '', 'Main sales income', 'INR', 'Yes'],
        // Instructions
        ['INSTRUCTIONS ▶', '* = required', 'Account Types: Asset/Liability/Equity/Income/Expense',
          'Sub Types: Cash/Bank/Stock/Fixed Asset/Other Current Asset/Accounts Receivable etc.',
          'Currency default = INR', 'Delete this row before uploading', '', ''],
      ];
      await ExportHelper.exportToExcel(
        data: rows,
        filename: 'chart_of_accounts_template_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      );
      _snack('Template downloaded ✓', Colors.green);
    } catch (e) {
      _snack('Download failed: $e', Colors.red);
    } finally {
      setState(() => _dlLoading = false);
    }
  }

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
      if (ext == 'csv') {
        rows = _parseCSV(file.bytes!);
      } else {
        rows = _parseExcel(file.bytes!);
      }

      if (rows.length < 2) throw Exception('File must have a header row + at least one data row');

      final valid = <Map<String, dynamic>>[];
      final errors = <String>[];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        final code    = _cell(row, 0);
        final name    = _cell(row, 1);
        final type    = _cell(row, 2);
        final subType = _cell(row, 3, type);
        final parent  = _cell(row, 4);
        final desc    = _cell(row, 5);
        final currency= _cell(row, 6, 'INR');
        final active  = _cell(row, 7, 'Yes');

        if (name.isEmpty || name.toUpperCase().contains('INSTRUCTION')) continue;

        final rowErr = <String>[];
        if (name.isEmpty) rowErr.add('Account Name required');
        if (type.isEmpty) rowErr.add('Account Type required');

        if (rowErr.isNotEmpty) { errors.add('Row ${i + 1}: ${rowErr.join(', ')}'); continue; }

        valid.add({
          'accountCode': code,
          'accountName': name,
          'accountType': type,
          'accountSubType': subType,
          'parentAccountName': parent,
          'description': desc,
          'currency': currency.isEmpty ? 'INR' : currency,
          'isActive': active.toLowerCase() != 'no',
        });
      }

      if (valid.isEmpty && errors.isNotEmpty) {
        setState(() => _uploading = false);
        _snack('No valid rows found', Colors.red);
        return;
      }

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Confirm Import'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${valid.length} account(s) ready to import',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('${errors.length} row(s) skipped', style: const TextStyle(color: Colors.orange, fontSize: 13)),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 100),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                child: SingleChildScrollView(child: Text(errors.join('\n'),
                    style: const TextStyle(fontSize: 11, color: Colors.red))),
              ),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white),
              child: Text('Import ${valid.length} Accounts'),
            ),
          ],
        ),
      );

      if (ok != true) { setState(() { _uploading = false; _filename = null; }); return; }

      final res = await ChartOfAccountService.bulkImport(valid, file.bytes!, file.name);
      setState(() { _uploading = false; _result = res['data']; });
      if (res['success'] == true) {
        _snack('✅ Imported ${res['data']['successCount']} accounts!', Colors.green);
        widget.onSuccess();
      }
    } catch (e) {
      setState(() { _uploading = false; _filename = null; });
      _snack('Import failed: $e', Colors.red);
    }
  }

  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    final book = xl.Excel.decodeBytes(bytes);
    final sheet = book.tables[book.tables.keys.first];
    if (sheet == null) return [];
    return sheet.rows.map((row) => row.map((c) {
      if (c?.value == null) return '';
      if (c!.value is xl.TextCellValue) return (c.value as xl.TextCellValue).value;
      if (c.value is xl.IntCellValue) return (c.value as xl.IntCellValue).value.toString();
      if (c.value is xl.DoubleCellValue) return (c.value as xl.DoubleCellValue).value.toString();
      return c.value.toString();
    }).toList()).toList();
  }

  List<List<dynamic>> _parseCSV(Uint8List bytes) {
    final str = utf8.decode(bytes, allowMalformed: true);
    return str.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).map((line) {
      final fields = <String>[]; final cur = StringBuffer(); bool inQ = false;
      for (int i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == '"') { if (inQ && i + 1 < line.length && line[i + 1] == '"') { cur.write('"'); i++; } else inQ = !inQ; }
        else if (ch == ',' && !inQ) { fields.add(cur.toString().trim()); cur.clear(); }
        else cur.write(ch);
      }
      fields.add(cur.toString().trim());
      return fields;
    }).toList();
  }

  String _cell(List row, int i, [String def = '']) => i < row.length ? (row[i]?.toString().trim() ?? def) : def;

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _purple.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.upload_file_rounded, color: _purple, size: 24)),
              const SizedBox(width: 12),
              const Expanded(child: Text('Bulk Import Accounts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
            const Divider(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.info_outline, color: Colors.blue.shade700, size: 16), const SizedBox(width: 8), Text('How to import', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue.shade700))]),
                const SizedBox(height: 8),
                Text('1. Download the sample template below\n2. Fill in your account data\n3. Upload your completed file (.xlsx / .csv)\n4. Review and confirm import',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade800, height: 1.7)),
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: _dlLoading || _uploading ? null : _downloadTemplate,
              icon: _dlLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.download_rounded, size: 18),
              label: Text(_dlLoading ? 'Downloading…' : 'Download Sample Excel Template'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
            )),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: _dlLoading || _uploading ? null : _pickAndImport,
              icon: _uploading ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _purple)) : const Icon(Icons.upload_file_rounded, size: 18),
              label: Text(_uploading ? 'Processing…' : 'Choose & Upload Excel / CSV'),
              style: OutlinedButton.styleFrom(foregroundColor: _purple, side: const BorderSide(color: _purple), padding: const EdgeInsets.symmetric(vertical: 14)),
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
            if (_result != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text('Import Results', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              _resRow('Total Processed', _result!['totalProcessed']?.toString() ?? '0', Colors.blue),
              const SizedBox(height: 6),
              _resRow('Successfully Imported', _result!['successCount']?.toString() ?? '0', Colors.green),
              const SizedBox(height: 6),
              _resRow('Failed', _result!['failedCount']?.toString() ?? '0', Colors.red),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
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
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
        child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13))),
    ],
  );
}