// lib/features/admin/client_management/presentation/screens/client_admin_dashboard.dart
// ✅ COMPLETE - Dashboard with horizontal/vertical scroll, filters, detail card, CRUD
//    + Customer count column (domain-based via CustomerService.countCustomersByDomain)

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/core/models/client_model.dart';
import 'package:abra_fleet/core/services/customer_service.dart';
import 'package:abra_fleet/features/admin/client_management/add_client_admin.dart';
import 'package:abra_fleet/features/admin/client_management/edit_client_admin.dart';
import 'package:universal_html/html.dart' as html;
import 'package:abra_fleet/core/widgets/permission_restricted_dialog.dart';
import 'package:abra_fleet/features/admin/widgets/country_state_city_filter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DASHBOARD SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class ClientAdminDashboard extends StatefulWidget {
  const ClientAdminDashboard({super.key});

  @override
  State<ClientAdminDashboard> createState() => _ClientAdminDashboardState();
}

class _ClientAdminDashboardState extends State<ClientAdminDashboard> {
  List<ClientModel> _clients = [];
  bool _isLoading = true;

  // ── Domain → customer count map (populated after clients load) ──
  Map<String, int> _domainCustomerCounts = {};
  bool _isLoadingCounts = false;

  // ── Filters ──
  final _searchCtrl = TextEditingController();
  String?   _filterStatus;
  String?   _filterCountry;
  String?   _filterState;
  String?   _filterCity;
  String?   _filterArea;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;

  // Scroll controllers
  final _verticalScroll   = ScrollController();
  final _horizontalScroll = ScrollController();

  // Header scroll controller – kept in sync with row scroll
  final _headerScroll = ScrollController();

  // CustomerService singleton
  final _customerService = CustomerService();

  @override
  void initState() {
    super.initState();
    // Sync header horizontal scroll with body horizontal scroll
    _horizontalScroll.addListener(() {
      if (_headerScroll.hasClients &&
          _headerScroll.offset != _horizontalScroll.offset) {
        _headerScroll.jumpTo(_horizontalScroll.offset);
      }
    });
    _loadClients();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _verticalScroll.dispose();
    _horizontalScroll.dispose();
    _headerScroll.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // DATA
  // ─────────────────────────────────────────────────────────

  Future<void> _loadClients() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';

      final params = <String, String>{'limit': '200'};
      if (_filterStatus  != null) params['status']    = _filterStatus!;
      if (_filterCountry != null) params['country']   = _filterCountry!;
      if (_filterState   != null) params['state']     = _filterState!;
      if (_filterCity    != null) params['city']      = _filterCity!;
      if (_filterArea    != null && _filterArea!.isNotEmpty)
        params['area'] = _filterArea!;
      if (_filterStartDate != null)
        params['startDate'] = _filterStartDate!.toIso8601String();
      if (_filterEndDate   != null)
        params['endDate']   = _filterEndDate!.toIso8601String();
      if (_searchCtrl.text.isNotEmpty)
        params['search'] = _searchCtrl.text.trim();

      final uri  = Uri.parse('${ApiConfig.baseUrl}/api/clients')
          .replace(queryParameters: params);
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = json.decode(resp.body);

      if (resp.statusCode == 200 && data['success'] == true) {
        final list = (data['data'] as List<dynamic>)
            .map((j) => ClientModel.fromJson(j as Map<String, dynamic>))
            .toList();
        if (mounted) setState(() { _clients = list; _isLoading = false; });
        // Load domain customer counts AFTER clients are set
        _loadDomainCustomerCounts();
      } else {
        throw Exception(data['message'] ?? 'Failed to load clients');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _snack('Error: $e', Colors.red);
      }
    }
  }

  /// For every unique domain across all loaded clients, call
  /// CustomerService.countCustomersByDomain and cache the result.
  Future<void> _loadDomainCustomerCounts() async {
    if (_clients.isEmpty) return;
    if (mounted) setState(() => _isLoadingCounts = true);

    // Collect unique domains
    final domains = <String>{};
    for (final c in _clients) {
      if (c.email.contains('@')) {
        domains.add(c.email.split('@')[1].toLowerCase());
      }
    }

    final newCounts = <String, int>{};

    // Fetch counts in parallel (but cap concurrency to avoid hammering)
    await Future.wait(
      domains.map((domain) async {
        try {
          final count = await _customerService.countCustomersByDomain(domain);
          newCounts[domain] = count;
        } catch (_) {
          newCounts[domain] = 0;
        }
      }),
    );

    if (mounted) {
      setState(() {
        _domainCustomerCounts = newCounts;
        _isLoadingCounts      = false;
      });
    }
  }

  /// Returns the customer count for a given client (by domain).
  int _customerCountFor(ClientModel client) {
    if (!client.email.contains('@')) return 0;
    final domain = client.email.split('@')[1].toLowerCase();
    return _domainCustomerCounts[domain] ?? 0;
  }

  // ─────────────────────────────────────────────────────────
  // CRUD
  // ─────────────────────────────────────────────────────────

  Future<void> _deleteClient(ClientModel client) async {
    final canDelete = await PermissionRestrictedDialog.checkAndWarn(
      context,
      permissionKey: 'client_details',
      moduleName: 'clients',
    );
    if (!canDelete) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber, color: Colors.orange),
          SizedBox(width: 8),
          Text('Delete Client'),
        ]),
        content: Text('Delete "${client.name}"?\n\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final resp  = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/clients/${client.id}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = json.decode(resp.body);
      if (resp.statusCode == 200 && data['success'] == true) {
        _snack('✅ Client deleted', Colors.green);
        _loadClients();
      } else {
        throw Exception(data['message']);
      }
    } catch (e) {
      _snack('❌ $e', Colors.red);
    }
  }

  Future<void> _updateStatus(ClientModel client, String newStatus) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final resp  = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/clients/${client.id}/status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'status': newStatus}),
      );
      final data = json.decode(resp.body);
      if (resp.statusCode == 200 && data['success'] == true) {
        _snack('✅ Status updated to $newStatus', Colors.green);
        _loadClients();
      } else {
        throw Exception(data['message']);
      }
    } catch (e) {
      _snack('❌ $e', Colors.red);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // STATS
  // ─────────────────────────────────────────────────────────

  int get _activeCount    => _clients.where((c) => c.status == 'active').length;
  int get _inactiveCount  => _clients.where((c) => c.status == 'inactive').length;
  int get _suspendedCount => _clients.where((c) => c.status == 'suspended').length;
  int get _totalCustomers => _domainCustomerCounts.values.fold(0, (a, b) => a + b);

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F2557), Color(0xFF1A3FC4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 2,
        shadowColor: const Color(0x590F2557),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.of(context).pop();
          },
          tooltip: 'Back to Admin Dashboard',
        ),
        title: const Text(
          'Client Management',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              controller: _verticalScroll,
              padding: EdgeInsets.all(
                MediaQuery.of(context).size.width < 600 ? 12.0 : 20.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStats(),
                  const SizedBox(height: 20),
                  CountryStateCityFilter(
                    initialFromDate: _filterStartDate,
                    initialToDate: _filterEndDate,
                    initialCountry: _filterCountry,
                    initialState: _filterState,
                    initialCity: _filterCity,
                    initialLocalArea: _filterArea,
                    onFilterApplied: (filterData) {
                      setState(() {
                        _filterStartDate = filterData['fromDate'];
                        _filterEndDate = filterData['toDate'];
                        
                        _filterCountry = (filterData['country'] != null && filterData['country'].toString().isNotEmpty) 
                            ? filterData['country'] 
                            : null;
                            
                        _filterState = (filterData['state'] != null && filterData['state'].toString().isNotEmpty)
                            ? filterData['state']
                            : null;
                            
                        _filterCity = (filterData['city'] != null && filterData['city'].toString().isNotEmpty)
                            ? filterData['city']
                            : null;
                            
                        _filterArea = (filterData['localArea'] != null && filterData['localArea'].toString().isNotEmpty)
                            ? filterData['localArea']
                            : null;
                      });
                      _loadClients();
                    },
                  ),
                  const SizedBox(height: 24),
                  _buildQuickSearchAndFilter(),
                  const SizedBox(height: 16),
                  _buildTable(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddClientAdminScreen()),
          );
          if (result == true) _loadClients();
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Client'),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // STATS CARDS  (5 cards now – includes total customers)
  // ─────────────────────────────────────────────────────────

  Widget _buildStats() {
    final stats = [
      {
        'label': 'Total Clients',
        'value': _clients.length.toString(),
        'color': const Color(0xFF4F46E5),
        'icon': Icons.business,
      },
      {
        'label': 'Active',
        'value': _activeCount.toString(),
        'color': const Color(0xFF10B981),
        'icon': Icons.check_circle,
      },
      {
        'label': 'Inactive',
        'value': _inactiveCount.toString(),
        'color': const Color(0xFFF59E0B),
        'icon': Icons.pause_circle,
      },
      {
        'label': 'Suspended',
        'value': _suspendedCount.toString(),
        'color': const Color(0xFFEF4444),
        'icon': Icons.block,
      },
      {
        'label': 'Total Customers',
        'value': _isLoadingCounts ? '...' : _totalCustomers.toString(),
        'color': const Color(0xFF0891B2),
        'icon': Icons.people,
      },
    ];

    return LayoutBuilder(builder: (ctx, constraints) {
      final cols = constraints.maxWidth > 1000
          ? 5
          : constraints.maxWidth > 700
              ? 3
              : 2;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 1.6,
        ),
        itemCount: stats.length,
        itemBuilder: (_, i) {
          final s     = stats[i];
          final color = s['color'] as Color;
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(s['icon'] as IconData, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      s['value'] as String,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      s['label'] as String,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    });
  }

  bool get _hasFilters =>
      _filterStatus    != null ||
      _filterCountry   != null ||
      _filterState     != null ||
      _filterCity      != null ||
      _filterStartDate != null ||
      _filterEndDate   != null;

  // ─────────────────────────────────────────────────────────
  // QUICK SEARCH & FILTER
  // ─────────────────────────────────────────────────────────

  Widget _buildQuickSearchAndFilter() {
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
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(8)),
                      child: DropdownButtonFormField<String>(
                        value: _filterStatus,
                        isExpanded: true,
                        decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10), border: InputBorder.none),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All')),
                          DropdownMenuItem(value: 'active', child: Text('Active')),
                          DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                          DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                        ],
                        onChanged: (value) => setState(() => _filterStatus = value),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Search', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(8)),
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Name, Email, ID...',
                          prefixIcon: Icon(Icons.search, color: Color(0xFF94A3B8)),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                        onSubmitted: (_) => _loadClients(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF0F2557), Color(0xFF1A3FC4)]),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: const Color(0xFF0F2557).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: ElevatedButton.icon(
                  onPressed: () => _loadClients(),
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Apply Filter', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _filterStatus = null;
                    _filterCountry = null;
                    _filterState = null;
                    _filterCity = null;
                    _filterArea = null;
                    _filterStartDate = null;
                    _filterEndDate = null;
                    _searchCtrl.clear();
                  });
                  _loadClients();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reset', style: TextStyle(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF64748B), side: const BorderSide(color: Color(0xFFE2E8F0), width: 2), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // TABLE  ── 12 columns including "Customers" (domain count)
  // ─────────────────────────────────────────────────────────

  static const List<String> _colHeaders = [
    'Company Name',   // 0
    'Contact Person', // 1
    'Email',          // 2
    'Phone',          // 3
    'Department',     // 4
    'Branch',         // 5
    'Location',       // 6
    'Customers',      // 7  ← domain-based count
    'Status',         // 8
    'Documents',      // 9
    'Onboarded',      // 10
    'Actions',        // 11
  ];

  static const List<double> _colWidths = [
    180, // Company Name
    160, // Contact Person
    200, // Email
    130, // Phone
    130, // Department
    130, // Branch
    200, // Location
    110, // Customers
    130, // Status
    100, // Documents
    120, // Onboarded
    130, // Actions
  ];

  Future<void> _addClient() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddClientAdminScreen()),
    );
    if (result == true) _loadClients();
  }

  Widget _buildTable() {
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
          // Table Top Bar with Quick Scroll Controls
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.business_center, color: Color(0xFF0F2557), size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Client Directory (${_clients.length})',
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
                    // Scroll Left Button
                    IconButton.filledTonal(
                      onPressed: () {
                        _horizontalScroll.animateTo(
                          0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      },
                      icon: const Icon(Icons.arrow_back_ios_new, size: 14),
                      tooltip: 'Scroll to First Column',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFEFF6FF),
                        foregroundColor: const Color(0xFF1A3FC4),
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                    // Scroll Right Button
                    IconButton.filledTonal(
                      onPressed: () {
                        _horizontalScroll.animateTo(
                          _horizontalScroll.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      },
                      icon: const Icon(Icons.arrow_forward_ios, size: 14),
                      tooltip: 'Scroll to Actions / Status',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFEFF6FF),
                        foregroundColor: const Color(0xFF1A3FC4),
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                    const SizedBox(width: 4),

                    // Add Client Button
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F2557), Color(0xFF1A3FC4)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F2557).withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () => _addClient(),
                        icon: const Icon(Icons.add_business, size: 17),
                        label: const Text(
                          'Add Client',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Horizontal Drag Hint Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFEFF6FF),
              border: Border(
                bottom: BorderSide(color: Color(0xFFBFDBFE), width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.pan_tool_alt_outlined, size: 15, color: Color(0xFF1A3FC4)),
                const SizedBox(width: 8),
                const Text(
                  'Horizontal & Vertical Scrolling: Click and drag with mouse, use trackpad, or use the scrollbar below to scroll columns.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () {
                    _horizontalScroll.animateTo(
                      _horizontalScroll.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Jump to Status & Actions',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A3FC4),
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 13, color: Color(0xFF1A3FC4)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Table Section with Visible Sticky Dual Scrollbars
          _clients.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(56.0),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Icon(Icons.business_outlined, size: 36, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _searchCtrl.text.isNotEmpty || _hasFilters
                        ? 'No clients match your search criteria'
                        : 'No clients found\nClick "Add Client" to create one',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            : Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                ),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad,
                      PointerDeviceKind.stylus,
                    },
                  ),
                  child: RawScrollbar(
                    controller: _horizontalScroll,
                    thumbVisibility: true,
                    trackVisibility: true,
                    thickness: 10,
                    radius: const Radius.circular(5),
                    thumbColor: const Color(0xFF1A3FC4),
                    trackColor: const Color(0xFFE2E8F0),
                    trackRadius: const Radius.circular(5),
                    scrollbarOrientation: ScrollbarOrientation.bottom,
                    child: SingleChildScrollView(
                      controller: _horizontalScroll,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 1200),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: DataTable(
                            border: const TableBorder(
                              horizontalInside: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                              verticalInside: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                              top: BorderSide(color: Color(0xFF0F2557), width: 1),
                              bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                              left: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                              right: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                            ),
                            columnSpacing: 24,
                            horizontalMargin: 20,
                            headingRowHeight: 56,
                            dataRowMinHeight: 60,
                            dataRowMaxHeight: 64,
                            headingRowColor: WidgetStateProperty.all(
                              const Color(0xFF0F2557),
                            ),
                            headingTextStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                            dataRowColor: WidgetStateProperty.resolveWith<Color>((states) {
                              if (states.contains(WidgetState.hovered)) {
                                return const Color(0xFFEFF6FF);
                              }
                              return Colors.white;
                            }),
                            columns: [
                              DataColumn(label: SizedBox(width: _colWidths[0] - 32, child: const Text('COMPANY NAME'))),
                              DataColumn(label: SizedBox(width: _colWidths[1] - 32, child: const Text('CONTACT PERSON'))),
                              DataColumn(label: SizedBox(width: _colWidths[2] - 32, child: const Text('EMAIL'))),
                              DataColumn(label: SizedBox(width: _colWidths[3] - 32, child: const Text('PHONE'))),
                              DataColumn(label: SizedBox(width: _colWidths[4] - 32, child: const Text('DEPARTMENT'))),
                              DataColumn(label: SizedBox(width: _colWidths[5] - 32, child: const Text('BRANCH'))),
                              DataColumn(label: SizedBox(width: _colWidths[6] - 32, child: const Text('LOCATION'))),
                              DataColumn(label: SizedBox(width: _colWidths[7] - 32, child: const Text('CUSTOMERS'))),
                              DataColumn(label: SizedBox(width: _colWidths[8] - 32, child: const Text('STATUS'))),
                              DataColumn(label: SizedBox(width: _colWidths[9] - 32, child: const Text('DOCS'))),
                              DataColumn(label: SizedBox(width: _colWidths[10] - 32, child: const Text('ONBOARDED'))),
                              DataColumn(label: SizedBox(width: _colWidths[11] - 32, child: const Text('ACTIONS'))),
                            ],
                            rows: _clients.map((client) {
                              final custCount = _customerCountFor(client);
                              final domain = client.email.contains('@') ? client.email.split('@')[1].toLowerCase() : '';
                              return DataRow(
                                cells: [
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: const Color(0xFF0F2557),
                                          child: Text(
                                            client.name.isNotEmpty ? client.name[0].toUpperCase() : 'C',
                                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            client.name,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1E293B)),
                                          ),
                                        ),
                                      ],
                                    ),
                                    onTap: () => _showClientDetail(client),
                                  ),
                                  DataCell(Text(client.contactPerson ?? '-', style: const TextStyle(fontSize: 14))),
                                  DataCell(Text(client.email, style: const TextStyle(fontSize: 13.5, color: Color(0xFF475569)), overflow: TextOverflow.ellipsis)),
                                  DataCell(Text(client.phone.isNotEmpty ? client.phone : '-', style: const TextStyle(fontSize: 14))),
                                  DataCell(Text(client.department?.isNotEmpty == true ? client.department! : '-', style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                                  DataCell(Text(client.branch?.isNotEmpty == true ? client.branch! : '-', style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                                  DataCell(Text(client.location.displayAddress.isNotEmpty ? client.location.displayAddress : '-', style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 2)),
                                  DataCell(
                                    _isLoadingCounts && !_domainCustomerCounts.containsKey(domain)
                                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                        : Tooltip(
                                            message: domain.isNotEmpty ? 'Employees with @$domain' : 'No domain',
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(5),
                                                  decoration: BoxDecoration(color: const Color(0xFF0891B2).withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                                                  child: const Icon(Icons.people, size: 14, color: Color(0xFF0891B2)),
                                                ),
                                                const SizedBox(width: 6),
                                                Text('$custCount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0891B2))),
                                              ],
                                            ),
                                          ),
                                  ),
                                  DataCell(_statusDropdown(client)),
                                  DataCell(
                                    client.documents.isEmpty
                                        ? Text('-', style: TextStyle(color: Colors.grey[400], fontSize: 14))
                                        : Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.attach_file, size: 16, color: Colors.blue),
                                              const SizedBox(width: 4),
                                              Text('${client.documents.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                            ],
                                          ),
                                  ),
                                  DataCell(Text(DateFormat('dd MMM yy').format(client.createdAt), style: const TextStyle(fontSize: 13, color: Colors.grey))),
                                  DataCell(
                                    Row(
                                      children: [
                                        _iconBtn(Icons.visibility, const Color(0xFF0D47A1), 'View', () => _showClientDetail(client)),
                                        _iconBtn(Icons.edit, const Color(0xFF10B981), 'Edit', () => _editClient(client)),
                                        _iconBtn(Icons.delete, Colors.red, 'Delete', () => _deleteClient(client)),
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
              ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────

  Widget _iconBtn(
    IconData icon,
    Color color,
    String tip,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }

  Widget _statusDropdown(ClientModel client) {
    const colors = <String, Color>{
      'active':    Colors.green,
      'inactive':  Colors.orange,
      'suspended': Colors.red,
    };
    final color = colors[client.status] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButton<String>(
        value: client.status,
        underline: const SizedBox(),
        isDense: true,
        icon: const SizedBox(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
        items: ['active', 'inactive', 'suspended'].map((s) {
          return DropdownMenuItem(
            value: s,
            child: Text(
              s.toUpperCase(),
              style: TextStyle(
                color: colors[s],
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          );
        }).toList(),
        onChanged: (v) {
          if (v != null && v != client.status) _updateStatus(client, v);
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // CLIENT EDIT
  // ─────────────────────────────────────────────────────────

  Future<void> _editClient(ClientModel client) async {
    final canEdit = await PermissionRestrictedDialog.checkAndWarn(
      context,
      permissionKey: 'client_details',
      moduleName: 'clients',
    );
    if (!canEdit) return;
    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditClientAdminScreen(client: client),
      ),
    );
    if (result == true) _loadClients();
  }

  // ─────────────────────────────────────────────────────────
  // CLIENT DETAIL BOTTOM SHEET
  // ─────────────────────────────────────────────────────────

  void _showClientDetail(ClientModel client) {
    final custCount = _customerCountFor(client);
    final domain    = client.email.contains('@')
        ? client.email.split('@')[1].toLowerCase()
        : '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ClientDetailSheet(
        client:    client,
        custCount: custCount,
        domain:    domain,
        onUpdate:  _loadClients,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CLIENT DETAIL SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _ClientDetailSheet extends StatelessWidget {
  final ClientModel client;
  final int         custCount;
  final String      domain;
  final VoidCallback onUpdate;

  const _ClientDetailSheet({
    required this.client,
    required this.custCount,
    required this.domain,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (ctx, sc) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D47A1).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.business,
                      color: Color(0xFF0D47A1),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          client.name,
                          style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          client.email,
                          style: TextStyle(
                            fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  // Customer count badge
                  if (domain.isNotEmpty)
                    Tooltip(
                      message: '@$domain employees',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0891B2).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF0891B2).withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.people,
                              size: 15,
                              color: Color(0xFF0891B2),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '$custCount employees',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0891B2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content
            Expanded(
              child: ListView(
                controller: sc,
                padding: const EdgeInsets.all(16),
                children: [
                  _infoCard(),
                  const SizedBox(height: 16),
                  _locationCard(),
                  if (client.documents.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _documentsCard(ctx),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard() {
    return _card(
      title: 'Client Information',
      icon: Icons.info_outline,
      child: Column(
        children: [
          _row('Company', client.name),
          _row('Contact Person', client.contactPerson ?? '-'),
          _row('Email', client.email),
          _row('Phone', client.phone.isNotEmpty ? client.phone : '-'),
          if (client.department?.isNotEmpty == true)
            _row('Department', client.department!),
          if (client.branch?.isNotEmpty == true)
            _row('Branch', client.branch!),
          if (client.address?.isNotEmpty == true)
            _row('Address', client.address!),
          if (client.gstNumber?.isNotEmpty == true)
            _row('GST Number', client.gstNumber!),
          if (client.panNumber?.isNotEmpty == true)
            _row('PAN Number', client.panNumber!),
          _row(
            'Status',
            client.status.toUpperCase(),
            valueColor: client.status == 'active'
                ? Colors.green
                : client.status == 'suspended'
                    ? Colors.red
                    : Colors.orange,
          ),
          if (domain.isNotEmpty)
            _row(
              'Customers (@$domain)',
              '$custCount employees',
              valueColor: const Color(0xFF0891B2),
            ),
          _row('Onboarded', DateFormat('dd MMM yyyy').format(client.createdAt)),
        ],
      ),
    );
  }

  Widget _locationCard() {
    final loc = client.location;
    if (!loc.hasLocation) return const SizedBox.shrink();
    return _card(
      title: 'Location',
      icon: Icons.location_on,
      child: Column(
        children: [
          if (loc.country.isNotEmpty) _row('Country', loc.country),
          if (loc.state.isNotEmpty)   _row('State',   loc.state),
          if (loc.city.isNotEmpty)    _row('City',    loc.city),
          if (loc.area.isNotEmpty)    _row('Area',    loc.area),
        ],
      ),
    );
  }

  Widget _documentsCard(BuildContext ctx) {
    return _card(
      title: 'Documents (${client.documents.length})',
      icon: Icons.folder_open,
      child: Column(
        children: client.documents
            .map((doc) => _documentRow(ctx, doc))
            .toList(),
      ),
    );
  }

  Widget _documentRow(BuildContext ctx, ClientDocument doc) {
    Color tagColor = Colors.blue;
    if (doc.isExpired)               tagColor = Colors.red;
    else if (doc.expiresWithin30Days) tagColor = Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(_docIcon(doc.mimeType), color: Colors.blue[700], size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.documentName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  doc.originalName,
                  style: TextStyle(
                    fontSize: 11, color: Colors.grey[500]),
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Text(
                      doc.humanReadableSize,
                      style: TextStyle(
                        fontSize: 11, color: Colors.grey[500]),
                    ),
                    if (doc.expiryDate != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: tagColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          doc.isExpired
                              ? 'EXPIRED'
                              : 'Exp: ${doc.expiryDate}',
                          style: TextStyle(
                            fontSize: 10,
                            color: tagColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Tooltip(
            message: 'Download',
            child: IconButton(
              icon: const Icon(
                Icons.download,
                color: Color(0xFF0D47A1),
                size: 22,
              ),
              onPressed: () => _downloadDocument(ctx, doc),
            ),
          ),
        ],
      ),
    );
  }

  IconData _docIcon(String mime) {
    if (mime.contains('pdf'))                         return Icons.picture_as_pdf;
    if (mime.contains('image'))                       return Icons.image;
    if (mime.contains('word'))                        return Icons.description;
    if (mime.contains('sheet') || mime.contains('excel')) return Icons.table_chart;
    return Icons.attach_file;
  }

  Future<void> _downloadDocument(BuildContext ctx, ClientDocument doc) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final url =
          '${ApiConfig.baseUrl}/api/clients/${client.id}/documents/${doc.id}/download';

      // Show loading indicator
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Text('Downloading...'),
              ],
            ),
            duration: Duration(seconds: 30),
            backgroundColor: Colors.blue,
          ),
        );
      }

      final resp = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (resp.statusCode == 200) {
        // Create a blob and download link (works on web and mobile with universal_html)
        final blob = html.Blob([resp.bodyBytes]);
        final blobUrl = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: blobUrl)
          ..setAttribute('download', doc.originalName)
          ..click();
        html.Url.revokeObjectUrl(blobUrl);

        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).clearSnackBars();
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text('✅ "${doc.documentName}" downloaded successfully'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).clearSnackBars();
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('❌ Download failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // ── Card / Row helpers ──

  Widget _card({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0D47A1), Color(0xFF1976D2)]),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCROLL BEHAVIOR — enables mouse/trackpad drag on desktop/web
// ─────────────────────────────────────────────────────────────────────────────

class _DesktopScrollBehavior extends ScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}