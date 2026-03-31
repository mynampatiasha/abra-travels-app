// lib/features/admin/dashboard/presentation/screens/admin_vehicle_checklist_screen.dart
// ============================================================================
// 🚗 ADMIN VEHICLE CHECKLIST VIEWER
// Features:
//   ✅ Full horizontal + vertical scrollable table (cursor-based, whole table scrolls)
//   ✅ Cell padding + cell spacing, neat columns
//   ✅ Row 1: CountryStateCityFilter (date, country, state, city, area)
//   ✅ Row 2: Vehicle Number, Driver Name, Status (All Passed / Issues), Date range
//   ✅ Export to Excel (works like invoices_list_page.dart)
//   ✅ WhatsApp button per row → choose Driver or Custom contact
//   ✅ Raise Ticket button per row (like incomplete_sos_alerts_screen.dart)
//   ✅ Detail dialog with full history / audit trail
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:abra_fleet/core/services/safe_api_service.dart';
import 'package:abra_fleet/core/services/tms_service.dart';
import 'package:abra_fleet/core/utils/export_helper.dart';
import 'package:abra_fleet/features/admin/widgets/country_state_city_filter.dart';

// ─── Colors ──────────────────────────────────────────────────────────────────
const Color _kPrimary   = Color(0xFF0D47A1);
const Color _kSuccess   = Color(0xFF27AE60);
const Color _kWarning   = Color(0xFFF59E0B);
const Color _kDanger    = Color(0xFFDC2626);
const Color _kTableHead = Color(0xFF1E3A5F);
const Color _kRowEven   = Color(0xFFF8FAFC);
const Color _kRowOdd    = Colors.white;
const Color _kBorder    = Color(0xFFE2E8F0);

// ─── Cell dimensions ─────────────────────────────────────────────────────────
const double _kRowH    = 56.0;
const double _kHeadH   = 48.0;
const EdgeInsets _kCell = EdgeInsets.symmetric(horizontal: 14, vertical: 10);

// ============================================================================
// SCREEN
// ============================================================================

class AdminVehicleChecklistScreen extends StatefulWidget {
  const AdminVehicleChecklistScreen({Key? key}) : super(key: key);

  @override
  State<AdminVehicleChecklistScreen> createState() =>
      _AdminVehicleChecklistScreenState();
}

class _AdminVehicleChecklistScreenState
    extends State<AdminVehicleChecklistScreen> {
  // ── Services ─────────────────────────────────────────────────────────────
  final SafeApiService _safeApi = SafeApiService();
  final TMSService     _tmsService = TMSService();

  // ── Data ─────────────────────────────────────────────────────────────────
  List<ChecklistRecord>  _all      = [];
  List<ChecklistRecord>  _filtered = [];
  List<Map<String, dynamic>> _employees = [];
  bool _loading         = true;
  bool _loadingEmployees = false;
  String? _error;

  // ── Filter panel (always visible) ─────────────────────────────────────────
  // Row 1 – CSC
  DateTime? _fromDate;
  DateTime? _toDate;
  String?   _country;
  String?   _state;
  String?   _city;
  String?   _area;

  // Row 2 – extra
  final _vehicleCtrl = TextEditingController();
  final _driverCtrl  = TextEditingController();
  String _statusFilter = 'All'; // 'All' | 'Passed' | 'Issues'

  // ── Scroll controllers (shared for header + body sync) ────────────────────
  final ScrollController _hScroll = ScrollController(); // horizontal
  final ScrollController _vScroll = ScrollController(); // vertical

  // ============================================================================
  // LIFECYCLE
  // ============================================================================

  @override
  void initState() {
    super.initState();
    _fetch();
    _fetchEmployees();
  }

  @override
  void dispose() {
    _vehicleCtrl.dispose();
    _driverCtrl.dispose();
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  // ============================================================================
  // FETCH DATA
  // ============================================================================

  Future<void> _fetch() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });

    try {
      final res = await _safeApi.safeGet(
        '/api/vehicle-checklist/history',
        queryParams: {'limit': '500'},
        context: 'Vehicle Checklists',
        fallback: {'success': false, 'data': {'checklists': []}},
      );

      if (res['success'] == true) {
        final list = res['data']?['checklists'] as List? ?? [];
        final records = list
            .map((j) => ChecklistRecord.fromJson(j as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

        if (mounted) setState(() { _all = records; _filtered = records; });
      } else {
        if (mounted) setState(() { _all = []; _filtered = []; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _all = []; _filtered = []; });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchEmployees() async {
    setState(() => _loadingEmployees = true);
    final res = await _tmsService.fetchEmployees();
    if (res['success'] == true && res['data'] != null) {
      setState(() {
        _employees = List<Map<String, dynamic>>.from(res['data']);
        _loadingEmployees = false;
      });
    } else {
      setState(() => _loadingEmployees = false);
    }
  }

  // ============================================================================
  // FILTERS
  // ============================================================================

  void _applyFilters() {
    List<ChecklistRecord> f = List.from(_all);

    // Date range
    if (_fromDate != null) {
      f = f.where((r) => r.submittedAt.isAfter(
          _fromDate!.subtract(const Duration(seconds: 1)))).toList();
    }
    if (_toDate != null) {
      f = f.where((r) => r.submittedAt.isBefore(
          _toDate!.add(const Duration(days: 1)))).toList();
    }

    // Vehicle number
    final v = _vehicleCtrl.text.trim().toLowerCase();
    if (v.isNotEmpty) {
      f = f.where((r) => r.vehicleNumber.toLowerCase().contains(v)).toList();
    }

    // Driver name / email
    final d = _driverCtrl.text.trim().toLowerCase();
    if (d.isNotEmpty) {
      f = f.where((r) =>
        r.driverEmail.toLowerCase().contains(d) ||
        r.driverId.toLowerCase().contains(d)).toList();
    }

    // Status
    if (_statusFilter == 'Passed') {
      f = f.where((r) => r.allPassed).toList();
    } else if (_statusFilter == 'Issues') {
      f = f.where((r) => !r.allPassed).toList();
    }

    setState(() => _filtered = f);
  }

  void _resetFilters() {
    setState(() {
      _fromDate = _toDate = _country = _state = _city = _area = null;
      _vehicleCtrl.clear();
      _driverCtrl.clear();
      _statusFilter = 'All';
      _filtered = _all;
    });
  }

  // ============================================================================
  // EXPORT
  // ============================================================================

  Future<void> _exportExcel() async {
    if (_filtered.isEmpty) {
      _snack('No records to export', _kWarning);
      return;
    }

    _snack('Preparing Excel export…', _kPrimary);

    final data = <List<dynamic>>[
      [
        'Submitted At', 'Driver ID', 'Driver Email',
        'Vehicle Number', 'Date', 'Total Items',
        'Checked Items', 'All Passed', 'Failed Items',
      ],
      ..._filtered.map((r) => [
        DateFormat('dd/MM/yyyy hh:mm a').format(r.submittedAt),
        r.driverId,
        r.driverEmail,
        r.vehicleNumber,
        r.date,
        r.totalItems,
        r.checkedItems,
        r.allPassed ? 'YES' : 'NO',
        r.failedItems.map((f) => f['title'] ?? '').join(', '),
      ]),
    ];

    try {
      await ExportHelper.exportToExcel(
        data: data,
        filename:
            'vehicle_checklists_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
      );
      _snack('✅ Exported ${_filtered.length} records', _kSuccess);
    } catch (e) {
      _snack('Export failed: $e', _kDanger);
    }
  }

  // ============================================================================
  // WHATSAPP
  // ============================================================================

  void _showWhatsAppDialog(ChecklistRecord r) {
    showDialog(
      context: context,
      builder: (_) => _WhatsAppDialog(record: r),
    );
  }

  // ============================================================================
  // RAISE TICKET
  // ============================================================================

  void _showRaiseTicketDialog(ChecklistRecord r) {
    String? selectedId;
    String? selectedName;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.confirmation_number,
                        color: Colors.orange.shade700, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('🎫 Raise Ticket for Checklist Issue',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                ]),
                const SizedBox(height: 16),

                // Summary
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('📋 Checklist Summary',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 8),
                      _kv('Vehicle', r.vehicleNumber),
                      _kv('Driver ID', r.driverId),
                      _kv('Date', r.date),
                      _kv('Status',
                          r.allPassed ? '✅ All Passed' : '⚠️ ${r.failedItems.length} Issues'),
                      if (r.failedItems.isNotEmpty)
                        _kv('Failed Items',
                            r.failedItems.map((f) => f['title'] ?? '').join(', ')),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                const Text('Assign To Employee:',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),

                // Employee dropdown
                if (_loadingEmployees)
                  const Center(child: CircularProgressIndicator())
                else if (_employees.isEmpty)
                  const Text('No employees found',
                      style: TextStyle(color: Colors.red))
                else
                  Container(
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8)),
                    child: DropdownButtonFormField<String>(
                      value: selectedId,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.person),
                        hintText: 'Select Employee',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      items: _employees.map((e) {
                        return DropdownMenuItem<String>(
                          value: e['_id'].toString(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(e['name_parson'] ?? 'Unknown',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              if (e['email'] != null)
                                Text(e['email'],
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600])),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (v) {
                        setD(() {
                          selectedId = v;
                          selectedName = _employees
                              .firstWhere(
                                  (e) => e['_id'].toString() == v)['name_parson']
                              ?? 'Unknown';
                        });
                      },
                    ),
                  ),
                const Spacer(),
                Row(children: [
                  Expanded(
                      child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'))),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: selectedId == null
                          ? null
                          : () async {
                              Navigator.pop(ctx);
                              await _raiseTicket(r, selectedId!, selectedName!);
                            },
                      icon: const Icon(Icons.send),
                      label: const Text('Raise Ticket'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[600],
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 12)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _raiseTicket(
      ChecklistRecord r, String empId, String empName) async {
    try {
      _snack('Creating ticket…', _kPrimary);

      final msg = '''
🚗 **VEHICLE CHECKLIST ISSUE**

**Vehicle:** ${r.vehicleNumber}
**Driver ID:** ${r.driverId}
**Driver Email:** ${r.driverEmail}
**Date:** ${r.date}
**Submitted At:** ${DateFormat('dd MMM yyyy hh:mm a').format(r.submittedAt)}

**Result:** ${r.allPassed ? '✅ All ${r.totalItems} items passed' : '⚠️ ${r.failedItems.length} items have issues'}
**Items Checked:** ${r.checkedItems}/${r.totalItems}

${r.failedItems.isNotEmpty ? '''**Failed Items:**
${r.failedItems.map((f) => '• ${f['title'] ?? ''}: ${f['note']?.isNotEmpty == true ? f['note'] : 'Not checked'}').join('\n')}''' : ''}

---
⚠️ Automated ticket from Daily Vehicle Checklist.
''';

      final res = await _tmsService.createTicket(
        subject: 'Vehicle Checklist Issue – ${r.vehicleNumber} (${r.date})',
        message: msg,
        priority: r.allPassed ? 'Normal' : 'High',
        timeline: 120,
        assignedTo: empId,
        status: 'Open',
      );

      if (res['success'] == true) {
        _snack('✅ Ticket raised and assigned to $empName', _kSuccess);
      } else {
        throw Exception(res['message'] ?? 'Failed');
      }
    } catch (e) {
      _snack('❌ Failed to raise ticket: $e', _kDanger);
    }
  }

  // ============================================================================
  // DETAIL DIALOG
  // ============================================================================

  void _showDetail(ChecklistRecord r) {
    showDialog(
      context: context,
      builder: (_) => _DetailDialog(record: r),
    );
  }

  // ============================================================================
  // HELPERS
  // ============================================================================

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  static Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 13, color: Colors.black87),
            children: [
              TextSpan(
                  text: '$k: ',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: v),
            ],
          ),
        ),
      );

  // ============================================================================
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('🚗 Daily Vehicle Checklists'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _fetch,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFiltersPanel(),
                _buildSummaryBar(),
                Expanded(child: _buildTable()),
              ],
            ),
    );
  }

  // ── Filters Panel ────────────────────────────────────────────────────────

  Widget _buildFiltersPanel() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.filter_alt, color: _kPrimary, size: 20),
              const SizedBox(width: 8),
              const Text('🔍 Filters',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _kPrimary)),
            ],
          ),
          const SizedBox(height: 16),

          // ── ROW 1: CountryStateCityFilter ─────────────────────────
          CountryStateCityFilter(
                  initialFromDate:  _fromDate,
                  initialToDate:    _toDate,
                  initialCountry:   _country,
                  initialState:     _state,
                  initialCity:      _city,
                  initialLocalArea: _area,
                  onFilterApplied:  (f) {
                    setState(() {
                      _fromDate = f['fromDate']  as DateTime?;
                      _toDate   = f['toDate']    as DateTime?;
                      _country  = f['country']   as String?;
                      _state    = f['state']      as String?;
                      _city     = f['city']       as String?;
                      _area     = f['localArea']  as String?;
                    });
                    _applyFilters();
                  },
                ),

          const SizedBox(height: 12),

          // ── ROW 2: Vehicle, Driver, Status, Reset, Export ─────────
          Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [

                // Vehicle Number
                _filterField(
                  label: 'Vehicle Number',
                  width: 160,
                  child: TextField(
                    controller: _vehicleCtrl,
                    onChanged: (_) => _applyFilters(),
                    decoration: _inputDec('e.g. KA01AB1234',
                        Icons.directions_car_outlined),
                    style: const TextStyle(fontSize: 15),
                  ),
                ),

                // Driver Name / ID
                _filterField(
                  label: 'Driver Name / ID',
                  width: 180,
                  child: TextField(
                    controller: _driverCtrl,
                    onChanged: (_) => _applyFilters(),
                    decoration:
                        _inputDec('Search driver…', Icons.person_outline),
                    style: const TextStyle(fontSize: 15),
                  ),
                ),

                // Status
                _filterField(
                  label: 'Checklist Status',
                  width: 160,
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(8)),
                    child: DropdownButton<String>(
                      value: _statusFilter,
                      underline: const SizedBox(),
                      isExpanded: true,
                      style: const TextStyle(
                          fontSize: 15, color: Colors.black87),
                      items: ['All', 'Passed', 'Issues']
                          .map((s) => DropdownMenuItem(
                              value: s, child: Text(s)))
                          .toList(),
                      onChanged: (v) {
                        setState(() => _statusFilter = v!);
                        _applyFilters();
                      },
                    ),
                  ),
                ),

                // Reset
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: _resetFilters,
                      icon: const Icon(Icons.clear, size: 18),
                      label: const Text('Reset All',
                          style: TextStyle(fontSize: 15)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ),

                // Export
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _exportExcel,
                      icon: const Icon(Icons.file_download, size: 20),
                      label: Text(
                        _filtered.isEmpty
                            ? 'Export Excel'
                            : 'Export Excel (${_filtered.length})',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kSuccess,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _filterField({
    required String label,
    required Widget child,
    double? width,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569))),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDec(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 15, color: Color(0xFF94A3B8)),
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF64748B)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _kPrimary, width: 2)),
      );

  // ── Summary bar ──────────────────────────────────────────────────────────

  Widget _buildSummaryBar() {
    final total   = _filtered.length;
    final passed  = _filtered.where((r) => r.allPassed).length;
    final issues  = total - passed;
    final showing = _filtered.length != _all.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          Text('Total: $total',
              style: const TextStyle(fontWeight: FontWeight.bold,
                  fontSize: 14, color: _kPrimary)),
          const SizedBox(width: 20),
          _badge('✅ Passed: $passed', _kSuccess),
          const SizedBox(width: 10),
          _badge('⚠️ Issues: $issues', issues > 0 ? _kDanger : Colors.grey),
          if (showing) ...[
            const SizedBox(width: 16),
            _badge('Filtered: ${_filtered.length} of ${_all.length}',
                Colors.orange),
          ],
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.35))),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color)),
      );

  // ── Table ────────────────────────────────────────────────────────────────

  // Column widths
  static const List<_Col> _cols = [
    _Col('#',            52),
    _Col('Submitted At', 170),
    _Col('Driver ID',    130),
    _Col('Driver Email', 200),
    _Col('Vehicle',      130),
    _Col('Date',         110),
    _Col('Checked',      90),
    _Col('Status',       110),
    _Col('Failed Items', 280),
    _Col('History',      90),
    _Col('WhatsApp',     90),
    _Col('Ticket',       80),
  ];

  Widget _buildTable() {
    if (_filtered.isEmpty) return _emptyState();

    // Total table width
    final tableW =
        _cols.fold<double>(0, (sum, c) => sum + c.width);

    return Scrollbar(
      controller: _hScroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _hScroll,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableW,
          child: Column(
            children: [
              // ── HEADER (sticky via Stack + positioned if needed, here just Column)
              _buildTableHeader(tableW),

              // ── BODY
              Expanded(
                child: Scrollbar(
                  controller: _vScroll,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _vScroll,
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) =>
                        _buildRow(_filtered[i], i),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader(double tableW) {
    return Container(
      height: _kHeadH,
      color: _kTableHead,
      child: Row(
        children: _cols.map((c) => _headCell(c)).toList(),
      ),
    );
  }

  Widget _headCell(_Col c) => Container(
        width: c.width,
        height: _kHeadH,
        padding: _kCell,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFF2C4A6E), width: 1)),
        ),
        child: Text(c.label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
                letterSpacing: 0.3)),
      );

  Widget _buildRow(ChecklistRecord r, int i) {
    final isEven = i % 2 == 0;
    return Container(
      height: _kRowH,
      color: isEven ? _kRowEven : _kRowOdd,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _kBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          // #
          _cell(Text('${i + 1}',
              style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500)),
              _cols[0].width),

          // Submitted At
          _cell(Text(
              DateFormat('dd MMM yy\nhh:mm a')
                  .format(r.submittedAt),
              style: const TextStyle(fontSize: 15)),
              _cols[1].width),

          // Driver ID
          _cell(Text(r.driverId,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w500)),
              _cols[2].width),

          // Driver Email
          _cell(Text(r.driverEmail,
              style: TextStyle(fontSize: 15, color: Colors.grey[700]),
              overflow: TextOverflow.ellipsis),
              _cols[3].width),

          // Vehicle
          _cell(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: _kPrimary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _kPrimary.withOpacity(0.2))),
              child: Text(r.vehicleNumber,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _kPrimary)),
            ),
            _cols[4].width,
          ),

          // Date
          _cell(Text(r.date,
              style: const TextStyle(fontSize: 15)),
              _cols[5].width),

          // Checked
          _cell(
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${r.checkedItems}/${r.totalItems}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                LinearProgressIndicator(
                  value: r.totalItems > 0
                      ? r.checkedItems / r.totalItems
                      : 0,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                      r.allPassed ? _kSuccess : _kWarning),
                  minHeight: 5,
                ),
              ],
            ),
            _cols[6].width,
          ),

          // Status
          _cell(
            _statusBadge(r.allPassed),
            _cols[7].width,
          ),

          // Failed Items
          _cell(
            r.failedItems.isEmpty
                ? Text('—',
                    style: TextStyle(
                        color: Colors.grey[400], fontSize: 12))
                : Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: r.failedItems
                        .take(3)
                        .map((f) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: _kDanger.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: _kDanger.withOpacity(0.25))),
                              child: Text(f['title'] ?? '',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: _kDanger,
                                      fontWeight: FontWeight.w500)),
                            ))
                        .toList()
                      ..addAll(r.failedItems.length > 3
                          ? [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(4)),
                                child: Text(
                                    '+${r.failedItems.length - 3} more',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey)),
                              )
                            ]
                          : []),
                  ),
            _cols[8].width,
          ),

          // History
          _cell(
            IconButton(
              icon: const Icon(Icons.history, size: 22, color: _kPrimary),
              tooltip: 'View full history',
              onPressed: () => _showDetail(r),
              padding: EdgeInsets.zero,
            ),
            _cols[9].width,
          ),

          // WhatsApp
          _cell(
            IconButton(
              icon: const Icon(Icons.chat, size: 22, color: Color(0xFF25D366)),
              tooltip: 'Send via WhatsApp',
              onPressed: () => _showWhatsAppDialog(r),
              padding: EdgeInsets.zero,
            ),
            _cols[10].width,
          ),

          // Ticket
          _cell(
            IconButton(
              icon: Icon(Icons.confirmation_number,
                  size: 22, color: Colors.orange[700]),
              tooltip: 'Raise Ticket',
              onPressed: () => _showRaiseTicketDialog(r),
              padding: EdgeInsets.zero,
            ),
            _cols[11].width,
          ),
        ],
      ),
    );
  }

  Widget _cell(Widget child, double width) => Container(
        width: width,
        height: _kRowH,
        padding: _kCell,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: _kBorder, width: 1)),
        ),
        child: Align(alignment: Alignment.centerLeft, child: child),
      );

  Widget _statusBadge(bool passed) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: passed
              ? _kSuccess.withOpacity(0.12)
              : _kDanger.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: passed
                  ? _kSuccess.withOpacity(0.4)
                  : _kDanger.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(passed ? Icons.check_circle : Icons.warning_amber,
                size: 16,
                color: passed ? _kSuccess : _kDanger),
            const SizedBox(width: 6),
            Text(passed ? 'Passed' : 'Issues',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: passed ? _kSuccess : _kDanger)),
          ],
        ),
      );

  Widget _emptyState() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.checklist_outlined, size: 72, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _filtered.isEmpty && _all.isNotEmpty
                  ? 'No records match your filters.'
                  : 'No checklist submissions yet.',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
                _filtered.isEmpty && _all.isNotEmpty
                    ? 'Try adjusting filters.'
                    : 'Drivers will submit checklists before starting their first trip.',
                style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
}

// ============================================================================
// COLUMN DESCRIPTOR
// ============================================================================

class _Col {
  final String label;
  final double width;
  const _Col(this.label, this.width);
}

// ============================================================================
// DETAIL DIALOG — full history + audit trail
// ============================================================================

class _DetailDialog extends StatelessWidget {
  final ChecklistRecord record;
  const _DetailDialog({required this.record});

  @override
  Widget build(BuildContext context) {
    final r = record;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.88,
        height: MediaQuery.of(context).size.height * 0.88,
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: _kPrimary,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.checklist, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Vehicle: ${r.vehicleNumber}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        Text(
                            'Driver: ${r.driverId} ${r.driverEmail.isNotEmpty ? '(${r.driverEmail})' : ''}',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: r.allPassed
                            ? _kSuccess
                            : _kDanger,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(
                        r.allPassed ? '✅ All Passed' : '⚠️ Has Issues',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Audit Info ─────────────────────────────────────
                    _section('📋 Submission Details', [
                      _infoRow('Submitted At',
                          DateFormat('dd MMM yyyy – hh:mm a')
                              .format(r.submittedAt)),
                      _infoRow('Date', r.date),
                      _infoRow('Driver ID', r.driverId),
                      _infoRow('Driver Email', r.driverEmail),
                      _infoRow('Vehicle Number', r.vehicleNumber),
                      _infoRow('Total Items', r.totalItems.toString()),
                      _infoRow('Checked Items',
                          '${r.checkedItems} / ${r.totalItems}'),
                      _infoRow('All Passed', r.allPassed ? 'YES ✅' : 'NO ⚠️'),
                    ]),

                    const SizedBox(height: 20),

                    // ── Progress ───────────────────────────────────────
                    _section('📊 Completion Progress', [
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: r.totalItems > 0
                                  ? r.checkedItems / r.totalItems
                                  : 0,
                              minHeight: 14,
                              backgroundColor: Colors.grey[200],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  r.allPassed ? _kSuccess : _kWarning),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                            '${r.totalItems > 0 ? (r.checkedItems / r.totalItems * 100).toStringAsFixed(0) : 0}%',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                      ]),
                    ]),

                    if (r.failedItems.isNotEmpty) ...[
                      const SizedBox(height: 20),

                      // ── Failed Items ───────────────────────────────
                      _section(
                          '⚠️ Issues Reported (${r.failedItems.length})',
                          r.failedItems.map((f) {
                            final title    = f['title']    ?? '';
                            final category = f['category'] ?? '';
                            final note     = f['note']     ?? '';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: _kDanger.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: _kDanger.withOpacity(0.25))),
                              child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.cancel,
                                        color: _kDanger, size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(title,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  color: _kDanger)),
                                          if (category.isNotEmpty)
                                            Text('Category: $category',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey[600])),
                                          if (note.isNotEmpty)
                                            Container(
                                              margin:
                                                  const EdgeInsets.only(top: 4),
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                      color: Colors.grey[300]!)),
                                              child: Row(children: [
                                                const Icon(
                                                    Icons.notes,
                                                    size: 13,
                                                    color: Colors.grey),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                    child: Text(note,
                                                        style: const TextStyle(
                                                            fontSize: 12,
                                                            fontStyle:
                                                                FontStyle.italic))),
                                              ]),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ]),
                            );
                          }).toList()),
                    ],

                    const SizedBox(height: 20),

                    // ── All Items ──────────────────────────────────────
                    _section(
                        '📝 All Checklist Items (${r.items.length})',
                        _buildItemsByCategory(r.items)),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(top: BorderSide(color: _kBorder))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildItemsByCategory(List<Map<String, dynamic>> items) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final item in items) {
      final cat = item['category'] ?? 'Other';
      grouped.putIfAbsent(cat, () => []).add(item);
    }

    return grouped.entries.map((entry) {
      final catItems   = entry.value;
      final allChecked = catItems.every((i) => i['checked'] == true);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category header
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: allChecked
                    ? _kSuccess.withOpacity(0.08)
                    : _kWarning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: allChecked
                        ? _kSuccess.withOpacity(0.3)
                        : _kWarning.withOpacity(0.3))),
            child: Row(children: [
              Icon(
                allChecked ? Icons.check_circle : Icons.pending_outlined,
                size: 15,
                color: allChecked ? _kSuccess : _kWarning,
              ),
              const SizedBox(width: 8),
              Text(entry.key,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: allChecked ? _kSuccess : _kWarning)),
              const Spacer(),
              Text(
                  '${catItems.where((i) => i['checked'] == true).length}/${catItems.length}',
                  style: TextStyle(
                      fontSize: 11,
                      color: allChecked ? _kSuccess : _kWarning,
                      fontWeight: FontWeight.w600)),
            ]),
          ),

          // Items
          ...catItems.map((item) {
            final checked = item['checked'] == true;
            final note    = item['note']    ?? '';

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                  color: checked
                      ? Colors.white
                      : _kDanger.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: checked
                          ? _kBorder
                          : _kDanger.withOpacity(0.2))),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                        checked
                            ? Icons.check_circle
                            : Icons.cancel_outlined,
                        size: 18,
                        color: checked ? _kSuccess : _kDanger),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['title'] ?? '',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: checked
                                      ? Colors.black87
                                      : _kDanger)),
                          if (!checked && note.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(children: [
                                const Icon(Icons.comment,
                                    size: 12, color: Colors.grey),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(note,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.grey)),
                                ),
                              ]),
                            ),
                        ],
                      ),
                    ),
                  ]),
            );
          }).toList(),
        ],
      );
    }).toList();
  }

  static Widget _section(String title, List<Widget> children) =>
      Column(
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
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorder)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children),
          ),
        ],
      );

  static Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2C3E50),
                      fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      color: Colors.grey[800], fontSize: 13)),
            ),
          ],
        ),
      );
}

// ============================================================================
// WHATSAPP DIALOG
// ============================================================================

class _WhatsAppDialog extends StatefulWidget {
  final ChecklistRecord record;
  const _WhatsAppDialog({required this.record});

  @override
  State<_WhatsAppDialog> createState() => _WhatsAppDialogState();
}

class _WhatsAppDialogState extends State<_WhatsAppDialog> {
  String _target = 'driver'; // 'driver' | 'custom'
  final _phoneCtrl = TextEditingController();
  final _msgCtrl   = TextEditingController();

  @override
  void initState() {
    super.initState();
    _msgCtrl.text = _defaultMsg();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  String _defaultMsg() {
    final r = widget.record;
    final lines = <String>[
      '🚗 *Daily Vehicle Checklist Update*',
      '',
      'Vehicle: *${r.vehicleNumber}*',
      'Date: *${r.date}*',
      'Status: *${r.allPassed ? '✅ All items passed' : '⚠️ ${r.failedItems.length} item(s) have issues'}*',
      'Checked: ${r.checkedItems}/${r.totalItems} items',
    ];

    if (r.failedItems.isNotEmpty) {
      lines.add('');
      lines.add('*Issues Found:*');
      for (final f in r.failedItems) {
        final note = f['note']?.toString().trim() ?? '';
        lines.add(
            '• ${f['title'] ?? ''}'
            '${note.isNotEmpty ? ': $note' : ''}');
      }
    }

    lines.addAll(['', 'Please take necessary action. Thank you.']);
    return lines.join('\n');
  }

  Future<void> _send() async {
    String phone = _target == 'driver'
        ? widget.record.driverPhone
        : _phoneCtrl.text.trim();

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter a phone number'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    // Normalise: remove spaces/dashes, add + if missing
    phone = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!phone.startsWith('+')) phone = '+91$phone'; // default India

    final encoded = Uri.encodeComponent(_msgCtrl.text.trim());
    final url     = 'https://wa.me/${phone.replaceAll('+', '')}?text=$encoded';
    final uri     = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) Navigator.pop(context);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open WhatsApp'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints:
            const BoxConstraints(maxWidth: 480, maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.chat,
                    color: Color(0xFF25D366), size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('📲 Send via WhatsApp',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 16),

            // Who to send
            const Text('Send To:',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Row(children: [
              _chip('Driver', 'driver'),
              const SizedBox(width: 10),
              _chip('Anyone (Custom)', 'custom'),
            ]),
            const SizedBox(height: 12),

            // Phone
            if (_target == 'driver') ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.phone, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    widget.record.driverPhone.isNotEmpty
                        ? widget.record.driverPhone
                        : 'No phone on record (enter manually below)',
                    style: TextStyle(
                        fontSize: 13,
                        color: widget.record.driverPhone.isNotEmpty
                            ? Colors.black87
                            : Colors.orange),
                  ),
                ]),
              ),
              if (widget.record.driverPhone.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Driver Phone Number',
                      hintText: '+91XXXXXXXXXX',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone),
                      isDense: true,
                    ),
                  ),
                ),
            ] else ...[
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Recipient Phone Number',
                  hintText: '+91XXXXXXXXXX or 9XXXXXXXXX',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                  isDense: true,
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Message
            const Text('Message:',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 6),
            Flexible(
              child: TextField(
                controller: _msgCtrl,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Edit message…',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),

            const SizedBox(height: 16),

            // Buttons
            Row(children: [
              Expanded(
                  child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'))),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _send,
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Open WhatsApp'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value) => GestureDetector(
        onTap: () => setState(() => _target = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              color: _target == value
                  ? const Color(0xFF25D366)
                  : Colors.grey[200],
              borderRadius: BorderRadius.circular(20)),
          child: Text(label,
              style: TextStyle(
                  color: _target == value ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ),
      );
}

// ============================================================================
// DATA MODEL
// ============================================================================

class ChecklistRecord {
  final String id;
  final String driverId;
  final String driverEmail;
  final String driverPhone;
  final String vehicleNumber;
  final String date;
  final DateTime submittedAt;
  final int totalItems;
  final int checkedItems;
  final bool allPassed;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> failedItems;

  ChecklistRecord({
    required this.id,
    required this.driverId,
    required this.driverEmail,
    required this.driverPhone,
    required this.vehicleNumber,
    required this.date,
    required this.submittedAt,
    required this.totalItems,
    required this.checkedItems,
    required this.allPassed,
    required this.items,
    required this.failedItems,
  });

  factory ChecklistRecord.fromJson(Map<String, dynamic> j) {
    final items = (j['items'] as List? ?? [])
        .map((i) => Map<String, dynamic>.from(i as Map))
        .toList();

    final failed = (j['failedItems'] as List? ?? [])
        .map((i) => Map<String, dynamic>.from(i as Map))
        .toList();

    // Derive failed from items if failedItems is empty
    final effectiveFailed = failed.isNotEmpty
        ? failed
        : items.where((i) => i['checked'] != true).toList();

    return ChecklistRecord(
      id:            j['_id']?.toString() ?? '',
      driverId:      j['driverId']?.toString() ?? '',
      driverEmail:   j['driverEmail']?.toString() ?? '',
      driverPhone:   j['driverPhone']?.toString() ?? '',
      vehicleNumber: j['vehicleNumber']?.toString() ?? '',
      date:          j['date']?.toString() ?? '',
      submittedAt:   j['submittedAt'] != null
          ? DateTime.tryParse(j['submittedAt'].toString()) ??
              DateTime.now()
          : DateTime.now(),
      totalItems:    (j['totalItems'] as num?)?.toInt() ?? 0,
      checkedItems:  (j['checkedItems'] as num?)?.toInt() ?? 0,
      allPassed:     j['allPassed'] == true,
      items:         items,
      failedItems:   effectiveFailed,
    );
  }
}