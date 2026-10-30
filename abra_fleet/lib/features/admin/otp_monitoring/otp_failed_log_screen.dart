// ============================================================================
// lib/features/admin/otp_monitoring/otp_failed_log_screen.dart
// OTP VERIFICATION LOG — Invoices-list style UI
// ============================================================================
// ✅ Summary stat cards (Total, Verified, Pending Override, Failed, Approved)
// ✅ Filter bar: Status, OTP Type, Date From/To, Search
// ✅ Responsive table (desktop) / card list (mobile)
// ✅ Per-row: Review Override button for pending items
// ✅ Navy color scheme matching new_invoice.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import '../../../core/services/otp_service.dart';
import '../../../app/config/api_config.dart';
import 'otp_override_approval_screen.dart';

// ── Color palette (matches new_invoice.dart)
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _success    = Color(0xFF10B981);
const Color _warning    = Color(0xFFF59E0B);
const Color _danger     = Color(0xFFDC2626);
const Color _purple     = Color(0xFF7C3AED);

class OtpFailedLogScreen extends StatefulWidget {
  const OtpFailedLogScreen({super.key});

  @override
  State<OtpFailedLogScreen> createState() => _OtpFailedLogScreenState();
}

class _OtpFailedLogScreenState extends State<OtpFailedLogScreen> {
  final OtpService _otpService = OtpService();

  List<Map<String, dynamic>> _allLogs = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;

  // ── Filters
  String _statusFilter = 'All';
  String _typeFilter   = 'All';
  DateTime? _fromDate;
  DateTime? _toDate;
  final TextEditingController _searchCtrl = TextEditingController();

  final List<String> _statusOptions = ['All', 'Verified', 'Pending', 'Override Pending', 'Override Approved', 'Override Rejected', 'No-Show', 'Failed'];
  final List<String> _typeOptions   = ['All', 'Step-In', 'Step-Out'];

  // ── Pagination
  int _currentPage  = 1;
  final int _perPage = 20;

  // ── Scroll
  final ScrollController _hScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _searchCtrl.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  // ── Data loading
  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    try {
      final data = await _otpService.getFailedOTPLog(limit: 500);
      setState(() {
        _allLogs = data;
        _loading = false;
      });
      _applyFilters();
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) _showSnack('Failed to load: $e', _danger);
    }
  }

  void _applyFilters() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _allLogs.where((log) {
        // Search
        if (q.isNotEmpty) {
          final name = (log['passengerName'] ?? '').toString().toLowerCase();
          final trip = (log['tripGroupId'] ?? '').toString().toLowerCase();
          if (!name.contains(q) && !trip.contains(q)) return false;
        }
        // Status
        if (_statusFilter != 'All') {
          final s = _resolveStatus(log);
          if (s != _statusFilter) return false;
        }
        // Type
        if (_typeFilter != 'All') {
          final t = log['type'] == 'step_in' ? 'Step-In' : 'Step-Out';
          if (t != _typeFilter) return false;
        }
        // Date
        final created = DateTime.tryParse(log['createdAt']?.toString() ?? '')?.toLocal();
        if (_fromDate != null && created != null && created.isBefore(_fromDate!)) return false;
        if (_toDate != null && created != null && created.isAfter(_toDate!.add(const Duration(days: 1)))) return false;
        return true;
      }).toList();
      _currentPage = 1;
    });
  }

  String _resolveStatus(Map<String, dynamic> log) {
    if (log['overrideStatus'] == 'no_show') return 'No-Show';
    if (log['verified'] == true) return 'Verified';
    switch (log['overrideStatus']) {
      case 'approved': return 'Override Approved';
      case 'requested': return 'Override Pending';
      case 'rejected': return 'Override Rejected';
      default: return (log['attempts'] ?? 0) >= 3 ? 'Failed' : 'Pending';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Verified': return _success;
      case 'Override Approved': return _success;
      case 'Override Pending': return _warning;
      case 'Override Rejected': return _danger;
      case 'No-Show': return Colors.grey;
      case 'Failed': return _danger;
      default: return _navyLight;
    }
  }

  // ── Stats
  Map<String, int> get _stats {
    int total    = _allLogs.length;
    int verified = _allLogs.where((l) => l['verified'] == true && l['overrideStatus'] != 'no_show').length;
    int pending  = _allLogs.where((l) => l['overrideStatus'] == 'requested').length;
    int approved = _allLogs.where((l) => l['overrideStatus'] == 'approved').length;
    int noShow   = _allLogs.where((l) => l['overrideStatus'] == 'no_show').length;
    int failed   = _allLogs.where((l) => l['verified'] != true && (l['attempts'] ?? 0) >= 3 && l['overrideStatus'] == 'none').length;
    return {'total': total, 'verified': verified, 'pending': pending, 'approved': approved, 'failed': failed, 'noShow': noShow};
  }

  // ── Pagination
  List<Map<String, dynamic>> get _paginated {
    final start = (_currentPage - 1) * _perPage;
    final end = (start + _perPage).clamp(0, _filtered.length);
    return _filtered.sublist(start, end);
  }

  int get _totalPages => (_filtered.length / _perPage).ceil().clamp(1, 9999);

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: _navyLight)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() { if (isFrom) _fromDate = picked; else _toDate = picked; });
      _applyFilters();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1100;
    final isTablet  = MediaQuery.of(context).size.width >= 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _navyDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('OTP Verification Log', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadLogs, tooltip: 'Refresh'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _navyLight))
          : Column(
              children: [
                _buildStatCards(isDesktop, isTablet),
                _buildFilterBar(isDesktop),
                _buildResultCount(),
                Expanded(
                  child: _filtered.isEmpty
                      ? _buildEmpty()
                      : isDesktop
                          ? _buildDesktopTable()
                          : _buildMobileList(),
                ),
                if (_filtered.isNotEmpty) _buildPagination(),
              ],
            ),
    );
  }

  // ── Stat cards (gradient, like invoices_list_page)
  Widget _buildStatCards(bool isDesktop, bool isTablet) {
    final s = _stats;
    final cards = [
      _StatCard('Total Events', '${s['total']}', Icons.lock_clock, _navyLight, [_navyMid, _navyLight]),
      _StatCard('Verified', '${s['verified']}', Icons.check_circle, _success, [const Color(0xFF059669), _success]),
      _StatCard('Override Pending', '${s['pending']}', Icons.pending_actions, _warning, [const Color(0xFFD97706), _warning]),
      _StatCard('Override Approved', '${s['approved']}', Icons.verified, _purple, [const Color(0xFF6D28D9), _purple]),
      _StatCard('No-Show', '${s['noShow']}', Icons.person_off, Colors.grey.shade600, [Colors.grey.shade700, Colors.grey.shade500]),
      _StatCard('Failed', '${s['failed']}', Icons.error, _danger, [const Color(0xFFB91C1C), _danger]),
    ];

    if (isDesktop) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Row(
          children: cards.map((c) => Expanded(child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _buildStatCard(c),
          ))).toList(),
        ),
      );
    }

    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        itemCount: cards.length,
        itemBuilder: (_, i) => SizedBox(
          width: 160,
          child: Padding(padding: const EdgeInsets.only(right: 10), child: _buildStatCard(cards[i])),
        ),
      ),
    );
  }

  Widget _buildStatCard(_StatCard c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c.gradient),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: c.color.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
            child: Icon(c.icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(c.value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
                Text(c.label, style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Filter bar
  Widget _buildFilterBar(bool isDesktop) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Search
          SizedBox(
            width: isDesktop ? 220 : double.infinity,
            height: 38,
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search passenger / trip...',
                hintStyle: const TextStyle(fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 18, color: _navyLight),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _navyLight)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
              ),
            ),
          ),
          // Status
          _filterDropdown('Status', _statusFilter, _statusOptions, (v) { setState(() => _statusFilter = v!); _applyFilters(); }),
          // Type
          _filterDropdown('Type', _typeFilter, _typeOptions, (v) { setState(() => _typeFilter = v!); _applyFilters(); }),
          // Date from
          _dateButton(_fromDate, 'From', () => _pickDate(true)),
          // Date to
          _dateButton(_toDate, 'To', () => _pickDate(false)),
          // Clear
          if (_statusFilter != 'All' || _typeFilter != 'All' || _fromDate != null || _toDate != null || _searchCtrl.text.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                setState(() { _statusFilter = 'All'; _typeFilter = 'All'; _fromDate = null; _toDate = null; _searchCtrl.clear(); });
                _applyFilters();
              },
              icon: const Icon(Icons.clear, size: 14, color: _danger),
              label: const Text('Clear', style: TextStyle(color: _danger, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _filterDropdown(String hint, String value, List<String> options, ValueChanged<String?> onChanged) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFFF8FAFC),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          style: const TextStyle(color: _navyDark, fontSize: 12),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: onChanged,
          isDense: true,
        ),
      ),
    );
  }

  Widget _dateButton(DateTime? date, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: date != null ? _navyLight : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          color: date != null ? _navyLight.withOpacity(0.06) : const Color(0xFFF8FAFC),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today, size: 14, color: date != null ? _navyLight : Colors.grey),
            const SizedBox(width: 6),
            Text(
              date != null ? DateFormat('dd MMM yy').format(date) : label,
              style: TextStyle(fontSize: 12, color: date != null ? _navyLight : Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCount() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Text('${_filtered.length} record${_filtered.length == 1 ? '' : 's'}',
              style: const TextStyle(color: _navyMid, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ── Desktop table
  Widget _buildDesktopTable() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Table header
            Container(
              color: _navyDark,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: const Row(
                children: [
                  Expanded(flex: 3, child: _TH('Passenger')),
                  Expanded(flex: 2, child: _TH('Driver')),
                  Expanded(flex: 2, child: _TH('OTP Type')),
                  Expanded(flex: 1, child: _TH('Attempts')),
                  Expanded(flex: 2, child: _TH('Status')),
                  Expanded(flex: 2, child: _TH('Stop / Reason')),
                  Expanded(flex: 2, child: _TH('Date & Time')),
                  Expanded(flex: 2, child: _TH('Action')),
                ],
              ),
            ),
            // Rows
            Expanded(
              child: ListView.separated(
                itemCount: _paginated.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF2F7)),
                itemBuilder: (_, i) => _buildTableRow(_paginated[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableRow(Map<String, dynamic> log) {
    final status = _resolveStatus(log);
    final color  = _statusColor(status);
    final created = DateTime.tryParse(log['createdAt']?.toString() ?? '')?.toLocal();
    final isPending = log['overrideStatus'] == 'requested';

    return Container(
      color: isPending ? _warning.withOpacity(0.04) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 3, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(log['passengerName'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w600, color: _navyDark, fontSize: 13)),
              if ((log['companyName'] ?? '').toString().isNotEmpty)
                Text(log['companyName'].toString(), style: const TextStyle(fontSize: 11, color: _navyLight, fontWeight: FontWeight.w500)),
              if ((log['employeeId'] ?? '').toString().isNotEmpty)
                Text('ID: ${log['employeeId']}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
              if ((log['passengerEmail'] ?? '').toString().isNotEmpty)
                Text(log['passengerEmail'].toString(), style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          )),
          Expanded(flex: 2, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (log['driverName'] ?? '').toString().isNotEmpty ? log['driverName'].toString() : '-',
                style: const TextStyle(fontWeight: FontWeight.w500, color: _navyMid, fontSize: 12),
              ),
              if ((log['driverPhone'] ?? '').toString().isNotEmpty)
                Text(log['driverPhone'].toString(), style: const TextStyle(fontSize: 10, color: Colors.grey)),
              if ((log['vehicleNumber'] ?? '').toString().isNotEmpty)
                Text(log['vehicleNumber'].toString(), style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          )),
          Expanded(flex: 2, child: _typeBadge(log['type']?.toString())),
          Expanded(flex: 1, child: Text(
            '${log['attempts'] ?? 0}/3',
            style: TextStyle(fontWeight: FontWeight.w600, color: (log['attempts'] ?? 0) >= 3 ? _danger : _navyMid, fontSize: 13),
          )),
          Expanded(flex: 2, child: _statusBadge(status, color)),
          Expanded(flex: 2, child: Text(
            (log['stopAddress'] ?? log['overrideReason'] ?? '-').toString(),
            style: const TextStyle(fontSize: 12, color: _navyMid),
            overflow: TextOverflow.ellipsis,
          )),
          Expanded(flex: 2, child: Text(
            created != null ? DateFormat('dd MMM yy, hh:mm a').format(created) : '-',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          )),
          Expanded(flex: 2, child: isPending
              ? ElevatedButton(
                  onPressed: () => _openApproval(log),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _warning,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  child: const Text('Review Override'),
                )
              : Text(status == 'Verified' ? '✓ Done' : '-', style: TextStyle(color: color, fontSize: 12))),
        ],
      ),
    );
  }

  // ── Mobile card list
  Widget _buildMobileList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _paginated.length,
      itemBuilder: (_, i) => _buildMobileCard(_paginated[i]),
    );
  }

  Widget _buildMobileCard(Map<String, dynamic> log) {
    final status  = _resolveStatus(log);
    final color   = _statusColor(status);
    final created = DateTime.tryParse(log['createdAt']?.toString() ?? '')?.toLocal();
    final isPending = log['overrideStatus'] == 'requested';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(log['passengerName'] ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: _navyDark, fontSize: 14)),
                    if ((log['companyName'] ?? '').toString().isNotEmpty)
                      Text(log['companyName'].toString(),
                          style: const TextStyle(fontSize: 12, color: _navyLight, fontWeight: FontWeight.w500)),
                    if ((log['employeeId'] ?? '').toString().isNotEmpty)
                      Text('Employee ID: ${log['employeeId']}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                )),
                _statusBadge(status, color),
              ],
            ),
            const SizedBox(height: 6),
            Row(children: [
              _typeBadge(log['type']?.toString()),
              const SizedBox(width: 8),
              Text('Attempts: ${log['attempts'] ?? 0}/3',
                  style: TextStyle(fontSize: 12, color: (log['attempts'] ?? 0) >= 3 ? _danger : _navyMid, fontWeight: FontWeight.w600)),
            ]),
            if ((log['driverName'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.person, size: 13, color: _navyMid),
                const SizedBox(width: 4),
                Text('Driver: ${log['driverName']}', style: const TextStyle(fontSize: 12, color: _navyMid)),
                if ((log['driverPhone'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.phone, size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(log['driverPhone'].toString(), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ]),
            ],
            if ((log['vehicleNumber'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.directions_bus, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text(log['vehicleNumber'].toString(), style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            ],
            if ((log['stopAddress'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.location_on, size: 13, color: _navyLight),
                const SizedBox(width: 4),
                Expanded(child: Text(log['stopAddress'].toString(), style: const TextStyle(fontSize: 12, color: _navyMid), overflow: TextOverflow.ellipsis)),
              ]),
            ],
            if ((log['overrideReason'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Reason: ${log['overrideReason']}', style: const TextStyle(fontSize: 12, color: _navyMid)),
            ],
            if (created != null) ...[
              const SizedBox(height: 4),
              Text(DateFormat('dd MMM yyyy, hh:mm a').format(created),
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
            if (isPending) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _openApproval(log),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _warning,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('Review Override', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openApproval(Map<String, dynamic> log) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OtpOverrideApprovalScreen(otpRecord: log)),
    ).then((_) => _loadLogs());
  }

  Widget _typeBadge(String? type) {
    final isStepIn = type == 'step_in';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isStepIn ? _navyLight : _purple).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isStepIn ? 'Step-In' : 'Step-Out',
        style: TextStyle(color: isStepIn ? _navyLight : _purple, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _statusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildEmpty() => const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
        SizedBox(height: 16),
        Text('No OTP records found', style: TextStyle(color: Colors.grey, fontSize: 16)),
        SizedBox(height: 8),
        Text('Try adjusting your filters', style: TextStyle(color: Colors.grey, fontSize: 13)),
      ],
    ),
  );

  // ── Pagination
  Widget _buildPagination() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${((_currentPage - 1) * _perPage) + 1}–${((_currentPage * _perPage).clamp(0, _filtered.length))} of ${_filtered.length}',
            style: const TextStyle(fontSize: 12, color: _navyMid),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
                color: _navyLight,
              ),
              Text('$_currentPage / $_totalPages', style: const TextStyle(fontSize: 13, color: _navyDark, fontWeight: FontWeight.w600)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < _totalPages ? () => setState(() => _currentPage++) : null,
                color: _navyLight,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Helpers
class _StatCard {
  final String label, value;
  final IconData icon;
  final Color color;
  final List<Color> gradient;
  const _StatCard(this.label, this.value, this.icon, this.color, this.gradient);
}

class _TH extends StatelessWidget {
  final String text;
  const _TH(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.4),
  );
}
