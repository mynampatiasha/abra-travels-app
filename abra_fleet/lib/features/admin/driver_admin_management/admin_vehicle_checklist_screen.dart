import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'package:abra_fleet/core/services/safe_api_service.dart';
import 'package:abra_fleet/features/admin/widgets/country_state_city_filter.dart';

class ChecklistRecord {
  final String id;
  final String driverId;
  final String driverEmail;
  final String? driverName;
  final String? driverEmployeeId;
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
    this.driverName,
    this.driverEmployeeId,
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
}

class AdminVehicleChecklistScreen extends StatefulWidget {
  const AdminVehicleChecklistScreen({super.key});

  @override
  State<AdminVehicleChecklistScreen> createState() => _AdminVehicleChecklistScreenState();
}

class _AdminVehicleChecklistScreenState extends State<AdminVehicleChecklistScreen> {
  bool _loading = true;
  List<ChecklistRecord> _all = [];
  List<ChecklistRecord> _filtered = [];

  final _vehicleCtrl = TextEditingController();
  final _driverCtrl = TextEditingController();
  final ScrollController _horizontalScrollController = ScrollController();
  
  DateTime? _fromDate;
  DateTime? _toDate;
  String _statusFilter = 'All';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _vehicleCtrl.dispose();
    _driverCtrl.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final safeApi = SafeApiService();
      final res = await safeApi.safeGet(
        '/api/vehicle-checklist/history',
        queryParams: {'limit': '500'},
        context: 'Vehicle Checklists',
        fallback: {'success': false, 'data': {'checklists': []}},
      );
      if (res['success'] == true) {
        final List list = res['data']?['checklists'] as List? ?? [];
        _all = list.map((e) {
          final items = List<Map<String, dynamic>>.from(e['items'] ?? []);
          final failed = items.where((i) => i['checked'] == false).toList();
          return ChecklistRecord(
            id: e['_id'] ?? '',
            driverId: e['driverId'] ?? 'N/A',
            driverEmail: e['driverEmail'] ?? '',
            driverName: e['driverName'],
            driverEmployeeId: e['driverEmployeeId'],
            driverPhone: e['driverPhone'] ?? 'N/A',
            vehicleNumber: e['vehicleNumber'] ?? 'Unknown',
            date: e['date'] ?? 'N/A',
            submittedAt: e['submittedAt'] != null ? DateTime.parse(e['submittedAt']) : DateTime.now(),
            totalItems: e['totalItems'] ?? 0,
            checkedItems: e['checkedItems'] ?? 0,
            allPassed: e['allPassed'] ?? false,
            items: items,
            failedItems: failed,
          );
        }).toList();
        
        _all.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
      }
    } catch (e) {
      debugPrint('Error fetching checklists: ');
    }
    _applyFilters();
    setState(() => _loading = false);
  }

  void _applyFilters() {
    List<ChecklistRecord> f = List.from(_all);

    if (_fromDate != null) {
      f = f.where((r) => r.submittedAt.isAfter(_fromDate!.subtract(const Duration(seconds: 1)))).toList();
    }
    if (_toDate != null) {
      f = f.where((r) => r.submittedAt.isBefore(_toDate!.add(const Duration(days: 1)))).toList();
    }

    final v = _vehicleCtrl.text.trim().toLowerCase();
    if (v.isNotEmpty) {
      f = f.where((r) => r.vehicleNumber.toLowerCase().contains(v)).toList();
    }

    final d = _driverCtrl.text.trim().toLowerCase();
    if (d.isNotEmpty) {
      f = f.where((r) => r.driverEmail.toLowerCase().contains(d) || r.driverId.toLowerCase().contains(d) || (r.driverName ?? '').toLowerCase().contains(d)).toList();
    }

    if (_statusFilter == 'Passed') {
      f = f.where((r) => r.allPassed).toList();
    } else if (_statusFilter == 'Issues') {
      f = f.where((r) => !r.allPassed).toList();
    }

    setState(() => _filtered = f);
  }

  void _resetFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _statusFilter = 'All';
      _vehicleCtrl.clear();
      _driverCtrl.clear();
    });
    _applyFilters();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF0F2557), Color(0xFF1A3FC4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
        ),
        elevation: 2,
        shadowColor: const Color(0x590F2557),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back',
        ),
        title: const Text('Daily Vehicle Checklists', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(
                MediaQuery.of(context).size.width < 600 ? 12.0 : 24.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatsGrid(),
                  const SizedBox(height: 24),
                  
                  CountryStateCityFilter(
                    initialFromDate: _fromDate,
                    initialToDate: _toDate,
                    onFilterApplied: (f) {
                      setState(() {
                        _fromDate = f['fromDate'] as DateTime?;
                        _toDate = f['toDate'] as DateTime?;
                      });
                      _applyFilters();
                    },
                  ),
                  const SizedBox(height: 24),
                  
                  _buildFilterSection(),
                  const SizedBox(height: 24),
                  
                  _buildChecklistDirectory(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsGrid() {
    final passed = _all.where((c) => c.allPassed).length;
    final issues = _all.where((c) => !c.allPassed).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 1200 ? 4 : constraints.maxWidth > 800 ? 2 : 1;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 24,
          mainAxisSpacing: 24,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 3.5,
          children: [
            _buildStatCard(
              label: 'TOTAL CHECKLISTS',
              value: '',
              subtitle: 'All time',
              icon: Icons.assignment,
              iconColor: const Color(0xFF1A3FC4),
              bgColor: const Color(0xFFEFF6FF),
            ),
            _buildStatCard(
              label: 'PASSED',
              value: '',
              subtitle: 'All clear',
              icon: Icons.check_circle,
              iconColor: const Color(0xFF059669),
              bgColor: const Color(0xFFECFDF5),
            ),
            _buildStatCard(
              label: 'ISSUES FOUND',
              value: '',
              subtitle: 'Needs attention',
              icon: Icons.warning_amber_rounded,
              iconColor: const Color(0xFFD97706),
              bgColor: const Color(0xFFFFFBEB),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(color: Color(0xFF0F2557), fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: iconColor, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.search, size: 18, color: Color(0xFF0F2557)),
              SizedBox(width: 8),
              Text('Quick Search & Filter', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F2557))),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 20,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Vehicle Number', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _vehicleCtrl,
                      decoration: InputDecoration(
                        hintText: 'e.g. KA01AB1234',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Driver Name / ID', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _driverCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search driver...',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _statusFilter,
                          icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B)),
                          items: ['All', 'Passed', 'Issues'].map((String value) {
                            return DropdownMenuItem<String>(value: value, child: Text(value, style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B))));
                          }).toList(),
                          onChanged: (v) => setState(() => _statusFilter = v!),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _applyFilters,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Apply Filter'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F2557),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _resetFilters,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reset'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF64748B),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistDirectory() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.5))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.assignment, color: Color(0xFF0F2557), size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Checklist Records (\)',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F2557), letterSpacing: 0.2),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      onPressed: () {
                        _horizontalScrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                      },
                      icon: const Icon(Icons.arrow_back_ios_new, size: 14),
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFEFF6FF), foregroundColor: const Color(0xFF1A3FC4), padding: const EdgeInsets.all(8)),
                    ),
                    IconButton.filledTonal(
                      onPressed: () {
                        _horizontalScrollController.animateTo(_horizontalScrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                      },
                      icon: const Icon(Icons.arrow_forward_ios, size: 14),
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFEFF6FF), foregroundColor: const Color(0xFF1A3FC4), padding: const EdgeInsets.all(8)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Export Excel'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _fetch,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Refresh'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus},
            ),
            child: RawScrollbar(
              controller: _horizontalScrollController,
              thumbColor: const Color(0xFFCBD5E1),
              radius: const Radius.circular(8),
              thickness: 8,
              child: SingleChildScrollView(
                controller: _horizontalScrollController,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 48),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: DataTable(
                      headingRowColor: MaterialStateProperty.all(const Color(0xFF0F2557)),
                      headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.5),
                      dataRowMinHeight: 65,
                      dataRowMaxHeight: 65,
                      dividerThickness: 1,
                      border: TableBorder(
                        horizontalInside: const BorderSide(color: Color(0xFFF1F5F9), width: 1),
                        verticalInside: const BorderSide(color: Color(0xFFF1F5F9), width: 1),
                      ),
                      columns: const [
                        DataColumn(label: Text('DATE/TIME')),
                        DataColumn(label: Text('VEHICLE ID')),
                        DataColumn(label: Text('DRIVER')),
                        DataColumn(label: Text('STATUS')),
                        DataColumn(label: Text('ISSUES')),
                      ],
                      rows: _filtered.map((r) {
                        return DataRow(
                          cells: [
                            DataCell(Text(DateFormat('dd MMM yy - hh:mm a').format(r.submittedAt), style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569)))),
                            DataCell(Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                              child: Text(r.vehicleNumber, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                            )),
                            DataCell(Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(r.driverName ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(r.driverEmployeeId ?? 'No ID', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                              ],
                            )),
                            DataCell(_buildStatusBadge(r.allPassed ? 'Passed' : 'Issues')),
                            DataCell(Text(
                              r.failedItems.isEmpty ? 'None' : r.failedItems.map((e) => e['title']).join(', '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: r.failedItems.isEmpty ? Colors.grey : Colors.red, fontSize: 12),
                            )),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatusBadge(String status) {
    Color bg;
    Color textC;
    Color borderC;

    if (status.toLowerCase() == 'passed') {
      bg = const Color(0xFFECFDF5);
      textC = const Color(0xFF059669);
      borderC = const Color(0xFFA7F3D0);
    } else {
      bg = const Color(0xFFFEF2F2);
      textC = const Color(0xFFDC2626);
      borderC = const Color(0xFFFECACA);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: borderC),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: textC, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5),
      ),
    );
  }
}
