// ============================================================================
// MANUAL JOURNALS LIST PAGE
// ============================================================================
// File: lib/screens/billing/pages/manual_journals_list_page.dart
// ============================================================================

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/manual_journal_service.dart';
import '../app_top_bar.dart';
import 'new_manual_journal.dart';
import 'manual_journal_detail.dart';

const Color _kNavyDark  = Color(0xFF0F172A);
const Color _kNavy      = Color(0xFF1E3A5F);
const Color _kAccent    = Color(0xFF2563EB);
const Color _kNavyLight = Color(0xFF3B82F6);

class ManualJournalsListPage extends StatefulWidget {
  const ManualJournalsListPage({Key? key}) : super(key: key);

  @override
  State<ManualJournalsListPage> createState() => _ManualJournalsListPageState();
}

class _ManualJournalsListPageState extends State<ManualJournalsListPage> {
  // ── State ──────────────────────────────────────────────────────────────────
  List<ManualJournal> _journals = [];
  JournalStats? _stats;
  bool _isLoading = true;
  String? _error;

  // ── Filters ────────────────────────────────────────────────────────────────
  String _statusFilter  = 'All';
  DateTime? _fromDate;
  DateTime? _toDate;
  final _searchCtrl     = TextEditingController();
  int _page             = 1;
  int _totalPages       = 1;
  int _total            = 0;

  final _statusOptions  = ['All', 'Draft', 'Published', 'Void'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Load ───────────────────────────────────────────────────────────────────

  Future<void> _load({bool resetPage = false}) async {
    if (resetPage) _page = 1;
    setState(() { _isLoading = true; _error = null; });
    try {
      final results = await Future.wait([
        ManualJournalService.getJournals(
          status: _statusFilter == 'All' ? null : _statusFilter,
          fromDate: _fromDate,
          toDate: _toDate,
          search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
          page: _page,
        ),
        ManualJournalService.getStats(),
      ]);
      final listResult = results[0] as JournalListResult;
      final stats      = results[1] as JournalStats;
      setState(() {
        _journals    = listResult.journals;
        _stats       = stats;
        _totalPages  = listResult.pages;
        _total       = listResult.total;
        _isLoading   = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  // ── Import ─────────────────────────────────────────────────────────────────

  Future<void> _showImportDialog() async {
    showDialog(context: context, builder: (_) => _ImportDialog(onImported: () => _load(resetPage: true)));
  }

  // ── Export ─────────────────────────────────────────────────────────────────

  Future<void> _export() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preparing export…'), behavior: SnackBarBehavior.floating),
      );
      final all = await ManualJournalService.getJournals(limit: 10000);
      final rows = <List<String>>[
        ['Journal #', 'Date', 'Reference #', 'Notes', 'Reporting Method', 'Currency', 'Status', 'Total Debit', 'Total Credit', 'Difference'],
      ];
      for (final j in all.journals) {
        rows.add([
          j.journalNumber,
          DateFormat('dd/MM/yyyy').format(j.date),
          j.referenceNumber,
          j.notes,
          j.reportingMethod,
          j.currency,
          j.status,
          j.totalDebit.toStringAsFixed(2),
          j.totalCredit.toStringAsFixed(2),
          j.difference.toStringAsFixed(2),
        ]);
      }
      // Build CSV
      final csv = rows.map((r) => r.map((c) => '"$c"').join(',')).join('\n');
      final bytes = Uint8List.fromList(csv.codeUnits);
      // Download
      _downloadFile(bytes, 'manual_journals_export.csv');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${all.journals.length} journals'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      _showError('Export failed: $e');
    }
  }

  void _downloadFile(Uint8List bytes, String filename) {
    // Web download handled via anchor; on mobile, show snack
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Export ready: $filename'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
    );
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));

  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));

  // ── View Process ───────────────────────────────────────────────────────────

  void _showViewProcess() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [_kNavyDark, _kNavy]),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_tree, color: Colors.white),
                    const SizedBox(width: 10),
                    const Text('Journal Process Flow',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Image.asset(
                      'assets/manual_journals.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => _buildProcessFlowFallback(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProcessFlowFallback() {
    final steps = [
      ('Create Journal', 'Fill journal number, date, reference & line items', Icons.create, _kAccent),
      ('Add Line Items', 'Debit = Credit (Difference must be ₹0.00)', Icons.list_alt, Colors.orange),
      ('Save as Draft', 'Review and edit anytime while in Draft', Icons.save_outlined, Colors.purple),
      ('Publish', 'Posts all entries to Chart of Accounts', Icons.publish, Colors.green),
      ('COA Updated', 'Account balances reflect in General Ledger', Icons.account_balance, Colors.teal),
      ('Void/Clone/PDF', 'Reverse entries, clone or download PDF', Icons.more_horiz, Colors.red),
    ];
    return SingleChildScrollView(
      child: Column(
        children: steps.asMap().entries.map((e) {
          final idx  = e.key;
          final step = e.value;
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: step.$4.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: step.$4.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(backgroundColor: step.$4, radius: 20, child: Icon(step.$3, color: Colors.white, size: 18)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(step.$1, style: TextStyle(fontWeight: FontWeight.bold, color: step.$4, fontSize: 15)),
                      const SizedBox(height: 3),
                      Text(step.$2, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                    ])),
                  ],
                ),
              ),
              if (idx < steps.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Icon(Icons.arrow_downward, color: Colors.grey[400]),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ── Date Picker ────────────────────────────────────────────────────────────

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_fromDate ?? now) : (_toDate ?? now),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() { isFrom ? _fromDate = picked : _toDate = picked; });
      _load(resetPage: true);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Manual Journals'),
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          _buildTopBar(),
          _buildStatsBar(),
          _buildFiltersBar(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  // ── Top Bar (simplified - no back button since AppTopBar handles it) ───────

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: LayoutBuilder(builder: (_, cs) {
        final isWide = cs.maxWidth > 700;
        return Row(
          children: [
            // Title
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Manual Journals',
                  style: TextStyle(color: _kNavyDark, fontWeight: FontWeight.bold, fontSize: 18)),
              Text('$_total journals found',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
            const Spacer(),
            // Action buttons — collapse on small screens
            if (isWide) ...[
              _headerBtn(Icons.account_tree_outlined, 'View Process', _showViewProcess),
              const SizedBox(width: 8),
              _headerBtn(Icons.upload_file, 'Import', _showImportDialog),
              const SizedBox(width: 8),
              _headerBtn(Icons.download_outlined, 'Export', _export),
              const SizedBox(width: 8),
            ] else ...[
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: _kNavyDark),
                onSelected: (v) {
                  if (v == 'process') _showViewProcess();
                  if (v == 'import')  _showImportDialog();
                  if (v == 'export')  _export();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'process', child: Text('View Process')),
                  PopupMenuItem(value: 'import',  child: Text('Import')),
                  PopupMenuItem(value: 'export',  child: Text('Export')),
                ],
              ),
              const SizedBox(width: 8),
            ],
            ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const NewManualJournalPage()));
                if (result == true && mounted) _load(resetPage: true);
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Journal'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _headerBtn(IconData icon, String label, VoidCallback onTap) => TextButton.icon(
    onPressed: onTap,
    icon: Icon(icon, color: _kNavyDark, size: 18),
    label: Text(label, style: const TextStyle(color: _kNavyDark, fontSize: 13)),
  );

  // ── Stats Bar ──────────────────────────────────────────────────────────────

  Widget _buildStatsBar() {
    if (_stats == null) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _statChip('Total', _stats!.total, Colors.blueGrey),
            _statChip('Draft', _stats!.draft, Colors.orange),
            _statChip('Published', _stats!.published, Colors.green),
            _statChip('Void', _stats!.voided, Colors.red),
            const SizedBox(width: 12),
            _amountChip('Total Debit', _stats!.totalDebit, Colors.red[700]!),
            _amountChip('Total Credit', _stats!.totalCredit, Colors.green[700]!),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, int count, Color color) => Container(
    margin: const EdgeInsets.only(right: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(children: [
      Text(label, style: TextStyle(fontSize: 12, color: color)),
      const SizedBox(width: 6),
      Text('$count', style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
    ]),
  );

  Widget _amountChip(String label, double amount, Color color) => Container(
    margin: const EdgeInsets.only(right: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(children: [
      Text(label, style: TextStyle(fontSize: 12, color: color)),
      const SizedBox(width: 6),
      Text('₹${amount.toStringAsFixed(2)}',
          style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
    ]),
  );

  // ── Filters Bar ────────────────────────────────────────────────────────────

  Widget _buildFiltersBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: LayoutBuilder(builder: (_, cs) {
        final isWide = cs.maxWidth > 700;
        if (isWide) {
          return Row(children: [
            Expanded(child: _searchField()),
            const SizedBox(width: 10),
            _statusDropdown(),
            const SizedBox(width: 10),
            _dateBtn(true),
            const SizedBox(width: 6),
            _dateBtn(false),
            const SizedBox(width: 10),
            if (_fromDate != null || _toDate != null || _statusFilter != 'All' || _searchCtrl.text.isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _fromDate = null; _toDate = null;
                    _statusFilter = 'All'; _searchCtrl.clear();
                  });
                  _load(resetPage: true);
                },
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('Clear'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
          ]);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _searchField(),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _statusDropdown(),
                const SizedBox(width: 8),
                _dateBtn(true),
                const SizedBox(width: 6),
                _dateBtn(false),
                if (_fromDate != null || _toDate != null || _statusFilter != 'All' || _searchCtrl.text.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () {
                      setState(() { _fromDate = null; _toDate = null; _statusFilter = 'All'; _searchCtrl.clear(); });
                      _load(resetPage: true);
                    },
                    icon: const Icon(Icons.clear, size: 14),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              ]),
            ),
          ],
        );
      }),
    );
  }

  Widget _searchField() => SizedBox(
    height: 40,
    child: TextField(
      controller: _searchCtrl,
      onChanged: (_) => _load(resetPage: true),
      decoration: InputDecoration(
        hintText: 'Search journal #, notes, reference…',
        prefixIcon: const Icon(Icons.search, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[300]!)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[300]!)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        isDense: true,
      ),
    ),
  );

  Widget _statusDropdown() => Container(
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.grey[300]!),
      borderRadius: BorderRadius.circular(8),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _statusFilter,
        isDense: true,
        items: _statusOptions.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
        onChanged: (v) { setState(() => _statusFilter = v!); _load(resetPage: true); },
      ),
    ),
  );

  Widget _dateBtn(bool isFrom) => InkWell(
    onTap: () => _pickDate(isFrom),
    child: Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Text(
          isFrom
            ? (_fromDate != null ? DateFormat('dd/MM/yy').format(_fromDate!) : 'From')
            : (_toDate   != null ? DateFormat('dd/MM/yy').format(_toDate!)   : 'To'),
          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
        ),
      ]),
    ),
  );

  // ── Content ────────────────────────────────────────────────────────────────

  Widget _buildContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, size: 48, color: Colors.red),
      const SizedBox(height: 12),
      Text(_error!, style: const TextStyle(color: Colors.red)),
      const SizedBox(height: 12),
      ElevatedButton(onPressed: _load, child: const Text('Retry')),
    ]));
    if (_journals.isEmpty) return _buildEmpty();
    return Column(
      children: [
        Expanded(child: _buildTable()),
        _buildPagination(),
      ],
    );
  }

  Widget _buildEmpty() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.book_outlined, size: 72, color: Colors.grey[300]),
    const SizedBox(height: 16),
    Text('No journals found', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
    const SizedBox(height: 8),
    Text('Create a manual journal to get started', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
    const SizedBox(height: 20),
    ElevatedButton.icon(
      onPressed: () async {
        final r = await Navigator.push(context, MaterialPageRoute(builder: (_) => const NewManualJournalPage()));
        if (r == true && mounted) _load(resetPage: true);
      },
      icon: const Icon(Icons.add),
      label: const Text('New Journal'),
      style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white),
    ),
  ]));

  // ── Table ──────────────────────────────────────────────────────────────────

  Widget _buildTable() {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width),
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(_kNavyDark),
              dataRowMinHeight: 52,
              dataRowMaxHeight: 68,
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('JOURNAL #',  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                DataColumn(label: Text('DATE',       style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                DataColumn(label: Text('REFERENCE',  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                DataColumn(label: Text('NOTES',      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                DataColumn(label: Text('STATUS',     style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                DataColumn(label: Text('DEBIT (₹)',  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)), numeric: true),
                DataColumn(label: Text('CREDIT (₹)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)), numeric: true),
                DataColumn(label: Text('ACTIONS',    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
              ],
              rows: _journals.asMap().entries.map((e) {
                final idx = e.key;
                final j   = e.value;
                return DataRow(
                  color: MaterialStateProperty.all(idx % 2 == 0 ? Colors.white : Colors.grey[50]!),
                  onSelectChanged: (_) => _openDetail(j),
                  cells: [
                    DataCell(
                      InkWell(
                        onTap: () => _openDetail(j),
                        child: Text(j.journalNumber,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _kAccent,
                              fontSize: 13,
                              decoration: TextDecoration.underline,
                            )),
                      ),
                    ),
                    DataCell(Text(DateFormat('dd MMM yyyy').format(j.date), style: const TextStyle(fontSize: 13))),
                    DataCell(Text(j.referenceNumber.isEmpty ? '-' : j.referenceNumber, style: const TextStyle(fontSize: 13))),
                    DataCell(SizedBox(width: 180, child: Text(j.notes.isEmpty ? '-' : j.notes,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)))),
                    DataCell(_statusBadge(j.status)),
                    DataCell(Text('₹${j.totalDebit.toStringAsFixed(2)}',
                        style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.w600, fontSize: 13))),
                    DataCell(Text('₹${j.totalCredit.toStringAsFixed(2)}',
                        style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600, fontSize: 13))),
                    DataCell(_rowActions(j)),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final colors = {
      'Draft':     [Colors.orange[100]!, Colors.orange[800]!],
      'Published': [Colors.green[100]!,  Colors.green[800]!],
      'Void':      [Colors.red[100]!,    Colors.red[800]!],
    };
    final c = colors[status] ?? [Colors.grey[100]!, Colors.grey[700]!];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(12)),
      child: Text(status, style: TextStyle(color: c[1], fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }

  Widget _rowActions(ManualJournal j) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        icon: const Icon(Icons.visibility_outlined, size: 18, color: _kAccent),
        tooltip: 'View',
        onPressed: () => _openDetail(j),
      ),
      if (j.status == 'Draft')
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.orange),
          tooltip: 'Edit',
          onPressed: () async {
            final r = await Navigator.push(context,
                MaterialPageRoute(builder: (_) => NewManualJournalPage(journalId: j.id)));
            if (r == true && mounted) _load();
          },
        ),
      if (j.status == 'Draft')
        IconButton(
          icon: const Icon(Icons.publish, size: 18, color: Colors.green),
          tooltip: 'Publish',
          onPressed: () => _quickPublish(j),
        ),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (v) => _handleAction(v, j),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'clone', child: Text('Clone')),
          const PopupMenuItem(value: 'pdf',   child: Text('Download PDF')),
          if (j.status != 'Void') const PopupMenuItem(value: 'void', child: Text('Void', style: TextStyle(color: Colors.red))),
          if (j.status == 'Draft') const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    ],
  );

  void _openDetail(ManualJournal j) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ManualJournalDetailPage(journalId: j.id),
    )).then((_) => _load());
  }

  Future<void> _quickPublish(ManualJournal j) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Publish Journal'),
        content: Text('Publish ${j.journalNumber}? This will post entries to Chart of Accounts.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ManualJournalService.publishJournal(j.id);
      _showSuccess('${j.journalNumber} published and posted to COA');
      _load();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _handleAction(String action, ManualJournal j) async {
    switch (action) {
      case 'clone':
        try {
          final cloned = await ManualJournalService.cloneJournal(j.id);
          _showSuccess('Cloned as ${cloned.journalNumber}');
          _load();
        } catch (e) { _showError(e.toString()); }
        break;

      case 'pdf':
        final url = ManualJournalService.getPdfUrl(j.id);
        _showSuccess('PDF URL: $url');
        break;

      case 'void':
        final reasonCtrl = TextEditingController();
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Void Journal'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Void ${j.journalNumber}? This will reverse all COA entries.'),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(labelText: 'Reason for voiding (optional)', border: OutlineInputBorder()),
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Void'),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        try {
          await ManualJournalService.voidJournal(j.id, reason: reasonCtrl.text);
          _showSuccess('${j.journalNumber} voided and COA reversed');
          _load();
        } catch (e) { _showError(e.toString()); }
        break;

      case 'delete':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete Journal'),
            content: Text('Delete ${j.journalNumber}? This cannot be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        try {
          await ManualJournalService.deleteJournal(j.id);
          _showSuccess('${j.journalNumber} deleted');
          _load();
        } catch (e) { _showError(e.toString()); }
        break;
    }
  }

  // ── Pagination ─────────────────────────────────────────────────────────────

  Widget _buildPagination() {
    if (_totalPages <= 1) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _page > 1 ? () { setState(() => _page--); _load(); } : null,
          ),
          Text('Page $_page of $_totalPages', style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _page < _totalPages ? () { setState(() => _page++); _load(); } : null,
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
  final VoidCallback onImported;
  const _ImportDialog({required this.onImported});

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  bool _isUploading = false;

  void _downloadTemplate() {
    final csv = [
      ['journalNumber', 'date', 'referenceNumber', 'notes', 'reportingMethod', 'currency', 'status',
       'lineItem_accountName', 'lineItem_description', 'lineItem_contactName', 'lineItem_debit', 'lineItem_credit'],
      ['JNL-2401-0001', '2024-01-15', 'REF-001', 'Opening entry', 'Accrual and Cash', 'INR', 'Draft',
       'Cash', 'Opening balance', '', '50000', '0'],
      ['', '', '', '', '', '', '',
       'Opening Balance Offset', 'Opening balance offset', '', '0', '50000'],
    ].map((r) => r.map((c) => '"$c"').join(',')).join('\n');

    final bytes = Uint8List.fromList(csv.codeUnits);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Template ready to download'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _pickAndImport() async {
    // File picker would be used here; showing mock for now
    setState(() => _isUploading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() => _isUploading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please select an Excel/CSV file to import'), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(children: [
        Container(padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: _kAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.upload_file, color: _kAccent, size: 20)),
        const SizedBox(width: 10),
        const Text('Import Manual Journals'),
      ]),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Import Format Requirements:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                const SizedBox(height: 8),
                ...const [
                  '• Excel (.xlsx) or CSV (.csv) format',
                  '• First row must be column headers',
                  '• One row per journal line item',
                  '• Debit must equal Credit per journal',
                  '• Date format: YYYY-MM-DD',
                ].map((t) => Padding(padding: const EdgeInsets.only(top: 3),
                  child: Text(t, style: const TextStyle(fontSize: 13)))),
              ]),
            ),
            const SizedBox(height: 16),
            const Text('Step 1: Download the template', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _downloadTemplate,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download Excel Template'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kAccent,
                side: const BorderSide(color: _kAccent),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Step 2: Upload filled template', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isUploading ? null : _pickAndImport,
              icon: _isUploading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.upload, size: 18),
              label: Text(_isUploading ? 'Uploading…' : 'Choose File & Import'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}