import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:abra_fleet/core/services/maintenance_service.dart';
import 'package:abra_fleet/features/admin/widgets/country_state_city_filter.dart';
import 'dart:ui';

class MaintenanceReport {
  final String id;
  final DateTime date;
  final String vehicleId;
  final String maintenanceType;
  final double cost;
  final String technicianName;
  final String notes;

  MaintenanceReport({
    required this.id,
    required this.date,
    required this.vehicleId,
    required this.maintenanceType,
    required this.cost,
    required this.technicianName,
    required this.notes,
  });
}

class MaintenanceReportsScreen extends StatefulWidget {
  final VoidCallback onBack;
  const MaintenanceReportsScreen({required this.onBack, Key? key}) : super(key: key);

  @override
  State<MaintenanceReportsScreen> createState() => _MaintenanceReportsScreenState();
}

class _MaintenanceReportsScreenState extends State<MaintenanceReportsScreen> {
  bool _loading = true;
  List<MaintenanceReport> _all = [];
  List<MaintenanceReport> _filtered = [];

  final TextEditingController _searchCtrl = TextEditingController();
  final MaintenanceService _maintenanceService = MaintenanceService();
  final ScrollController _horizontalScrollController = ScrollController();

  // Filters
  DateTime? _fromDate;
  DateTime? _toDate;
  String _maintType = 'All';

  @override
  void initState() {
    super.initState();
    _fetch();
  }
  
  @override
  void dispose() {
    _searchCtrl.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final result = await _maintenanceService.getMaintenanceReports(page: 1, limit: 100);
      if (result['success']) {
        final List<dynamic> data = result['data'] ?? [];
        _all = data.map((e) => MaintenanceReport(
          id: e['_id'] ?? '',
          date: e['date'] != null ? DateTime.parse(e['date'].toString()) : DateTime.now(),
          vehicleId: e['vehicleNumber'] ?? 'Unknown',
          maintenanceType: e['type'] ?? 'Unknown',
          cost: (e['cost'] ?? 0).toDouble(),
          technicianName: e['technician'] ?? 'Unknown',
          notes: e['notes'] ?? '',
        )).toList();
      }
    } catch (e) {
      debugPrint('Error: ');
      _all = [
        MaintenanceReport(id: 'R001', date: DateTime.now().subtract(const Duration(days: 1)), vehicleId: 'KA01AB1234', maintenanceType: 'Oil Change', cost: 1200, technicianName: 'Ahmed Hassan', notes: 'Used synthetic oil.'),
        MaintenanceReport(id: 'R002', date: DateTime.now().subtract(const Duration(days: 5)), vehicleId: 'KA02CD5678', maintenanceType: 'Tire Rotation', cost: 800, technicianName: 'Mohammed Ali', notes: 'Checked tire pressure.'),
      ];
    }
    _applyFilters();
    setState(() => _loading = false);
  }

  void _applyFilters() {
    List<MaintenanceReport> f = List.from(_all);

    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      f = f.where((r) => 
        r.vehicleId.toLowerCase().contains(q) || 
        r.maintenanceType.toLowerCase().contains(q) ||
        r.technicianName.toLowerCase().contains(q)).toList();
    }

    if (_fromDate != null) {
      f = f.where((r) => r.date.isAfter(_fromDate!.subtract(const Duration(seconds: 1)))).toList();
    }
    if (_toDate != null) {
      f = f.where((r) => r.date.isBefore(_toDate!.add(const Duration(days: 1)))).toList();
    }

    if (_maintType != 'All') {
      f = f.where((r) => r.maintenanceType == _maintType).toList();
    }

    setState(() => _filtered = f);
  }

  void _resetFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _maintType = 'All';
      _searchCtrl.clear();
    });
    _applyFilters();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
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
                  
                  _buildReportsDirectory(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsGrid() {
    final totalCost = _all.fold(0.0, (sum, item) => sum + item.cost);
    final thisMonth = _all.where((c) => c.date.month == DateTime.now().month).length;

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
              label: 'TOTAL REPORTS',
              value: '',
              subtitle: 'All time',
              icon: Icons.analytics_outlined,
              iconColor: const Color(0xFF1A3FC4),
              bgColor: const Color(0xFFEFF6FF),
            ),
            _buildStatCard(
              label: 'THIS MONTH',
              value: '',
              subtitle: 'Recent maintenance',
              icon: Icons.calendar_today,
              iconColor: const Color(0xFF059669),
              bgColor: const Color(0xFFECFDF5),
            ),
            _buildStatCard(
              label: 'TOTAL EXPENSE',
              value: 'â‚¹',
              subtitle: 'Cumulative cost',
              icon: Icons.currency_rupee,
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
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
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
                width: 250,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Search', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Vehicle, Technician...',
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
                    const Text('Maintenance Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
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
                          value: _maintType,
                          icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B)),
                          items: ['All', 'Oil Change', 'Tire Rotation', 'Brake Service', 'AC Service', 'General Inspection'].map((String value) {
                            return DropdownMenuItem<String>(value: value, child: Text(value, style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B))));
                          }).toList(),
                          onChanged: (v) => setState(() => _maintType = v!),
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

  Widget _buildReportsDirectory() {
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
                    const Icon(Icons.analytics, color: Color(0xFF0F2557), size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Maintenance Reports (\)',
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
                      label: const Text('Export'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Report'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A3FC4),
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
                        DataColumn(label: Text('DATE')),
                        DataColumn(label: Text('VEHICLE ID')),
                        DataColumn(label: Text('TYPE')),
                        DataColumn(label: Text('COST')),
                        DataColumn(label: Text('TECHNICIAN')),
                        DataColumn(label: Text('NOTES')),
                      ],
                      rows: _filtered.map((r) {
                        return DataRow(
                          cells: [
                            DataCell(Text(DateFormat('dd MMM yy').format(r.date), style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569)))),
                            DataCell(Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                              child: Text(r.vehicleId, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                            )),
                            DataCell(Text(r.maintenanceType, style: const TextStyle(color: Color(0xFF334155)))),
                            DataCell(Text('â‚¹', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF15803D)))),
                            DataCell(Text(r.technicianName, style: const TextStyle(color: Color(0xFF334155)))),
                            DataCell(SizedBox(
                              width: 150,
                              child: Text(r.notes, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
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
}
