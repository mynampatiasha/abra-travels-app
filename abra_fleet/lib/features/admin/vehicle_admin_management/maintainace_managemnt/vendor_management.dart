import 'package:flutter/material.dart';
import 'package:abra_fleet/features/admin/widgets/country_state_city_filter.dart';
import 'dart:ui';

class VendorModel {
  final String id;
  final String name;
  final String category;
  final String contactName;
  final String phone;
  final String email;
  final String status;
  final String address;

  VendorModel({
    required this.id,
    required this.name,
    required this.category,
    required this.contactName,
    required this.phone,
    required this.email,
    required this.status,
    required this.address,
  });
}

class VendorManagementScreen extends StatefulWidget {
  const VendorManagementScreen({Key? key}) : super(key: key);

  @override
  State<VendorManagementScreen> createState() => _VendorManagementScreenState();
}

class _VendorManagementScreenState extends State<VendorManagementScreen> {
  bool _loading = true;
  List<VendorModel> _all = [];
  List<VendorModel> _filtered = [];

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  // Filters
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
    _searchCtrl.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    // Mock fetch delay
    await Future.delayed(const Duration(milliseconds: 600));
    _all = [
      VendorModel(id: 'V001', name: 'Gulf Auto Care', category: 'General Service', contactName: 'Rajesh', phone: '+919876543210', email: 'rajesh@gulfauto.com', status: 'Active', address: 'Bangalore'),
      VendorModel(id: 'V002', name: 'Tyre Experts', category: 'Tires', contactName: 'Vikram', phone: '+919876543211', email: 'vikram@tyreexperts.com', status: 'Active', address: 'Mumbai'),
      VendorModel(id: 'V003', name: 'Cool Air AC Repair', category: 'AC Service', contactName: 'Sameer', phone: '+919876543212', email: 'sameer@coolair.com', status: 'Inactive', address: 'Delhi'),
    ];
    _applyFilters();
    setState(() => _loading = false);
  }

  void _applyFilters() {
    List<VendorModel> f = List.from(_all);

    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      f = f.where((r) => 
        r.name.toLowerCase().contains(q) || 
        r.category.toLowerCase().contains(q) ||
        r.contactName.toLowerCase().contains(q)).toList();
    }

    if (_statusFilter != 'All') {
      f = f.where((r) => r.status == _statusFilter).toList();
    }

    setState(() => _filtered = f);
  }

  void _resetFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _statusFilter = 'All';
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
                  
                  _buildVendorDirectory(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsGrid() {
    final activeVendors = _all.where((c) => c.status == 'Active').length;
    final inactiveVendors = _all.where((c) => c.status == 'Inactive').length;

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
              label: 'TOTAL VENDORS',
              value: '',
              subtitle: 'All registered',
              icon: Icons.store,
              iconColor: const Color(0xFF1A3FC4),
              bgColor: const Color(0xFFEFF6FF),
            ),
            _buildStatCard(
              label: 'ACTIVE VENDORS',
              value: '',
              subtitle: 'Currently active',
              icon: Icons.check_circle,
              iconColor: const Color(0xFF059669),
              bgColor: const Color(0xFFECFDF5),
            ),
            _buildStatCard(
              label: 'INACTIVE',
              value: '',
              subtitle: 'Need attention',
              icon: Icons.pause_circle,
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
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF0F2557),
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: iconColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
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
              Text(
                'Quick Search & Filter',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F2557),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 20,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              // Search
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
                        hintText: 'Name, Email, ID...',
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
              // Status Dropdown
              SizedBox(
                width: 200,
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
                          items: ['All', 'Active', 'Inactive'].map((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value, style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B))),
                            );
                          }).toList(),
                          onChanged: (v) => setState(() => _statusFilter = v!),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Buttons
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

  Widget _buildVendorDirectory() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.store, color: Color(0xFF0F2557), size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Vendor Directory (\)',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F2557),
                        letterSpacing: 0.2,
                      ),
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
                      tooltip: 'Scroll to First Column',
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFEFF6FF), foregroundColor: const Color(0xFF1A3FC4), padding: const EdgeInsets.all(8)),
                    ),
                    IconButton.filledTonal(
                      onPressed: () {
                        _horizontalScrollController.animateTo(_horizontalScrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                      },
                      icon: const Icon(Icons.arrow_forward_ios, size: 14),
                      tooltip: 'Scroll to Last Column',
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
                      label: const Text('Add Vendor'),
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
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.mouse, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 8),
                const Text(
                  'Horizontal & Vertical Scrolling: Click and drag with mouse, use trackpad, or use the scrollbar below.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          // The Table
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
                        DataColumn(label: Text('VENDOR ID')),
                        DataColumn(label: Text('NAME')),
                        DataColumn(label: Text('CATEGORY')),
                        DataColumn(label: Text('CONTACT')),
                        DataColumn(label: Text('PHONE')),
                        DataColumn(label: Text('STATUS')),
                        DataColumn(label: Text('ACTIONS')),
                      ],
                      rows: _filtered.map((v) {
                        final isActive = v.status == 'Active';
                        return DataRow(
                          cells: [
                            DataCell(Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                              child: Text(v.id, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569), fontSize: 13)),
                            )),
                            DataCell(Text(v.name, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1E293B)))),
                            DataCell(Text(v.category)),
                            DataCell(Text(v.contactName)),
                            DataCell(Text(v.phone)),
                            DataCell(_buildStatusBadge(v.status)),
                            DataCell(
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 18, color: Color(0xFF3B82F6)),
                                    onPressed: () {},
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 18, color: Color(0xFFEF4444)),
                                    onPressed: () {},
                                  ),
                                ],
                              ),
                            ),
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

    if (status.toLowerCase() == 'active') {
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
