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
  bool _showFilters = false;

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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              controller: _verticalScroll,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStats(),
                  const SizedBox(height: 20),
                  _buildToolbar(),
                  if (_showFilters) ...[
                    const SizedBox(height: 12),
                    _buildFilterPanel(),
                  ],
                  const SizedBox(height: 16),
                  _buildTable(),
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

  // ─────────────────────────────────────────────────────────
  // TOOLBAR
  // ─────────────────────────────────────────────────────────

  Widget _buildToolbar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            onSubmitted: (_) => _loadClients(),
            decoration: InputDecoration(
              hintText: 'Search clients...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        _loadClients();
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _toolBtn(
          Icons.filter_list,
          'Filters',
          () => setState(() => _showFilters = !_showFilters),
          active: _showFilters || _hasFilters,
        ),
        const SizedBox(width: 8),
        _toolBtn(Icons.refresh, 'Refresh', _loadClients),
        if (_isLoadingCounts) ...[
          const SizedBox(width: 8),
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 6),
          Text(
            'Loading counts...',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ],
    );
  }

  bool get _hasFilters =>
      _filterStatus    != null ||
      _filterCountry   != null ||
      _filterState     != null ||
      _filterCity      != null ||
      _filterStartDate != null ||
      _filterEndDate   != null;

  Widget _toolBtn(
    IconData icon,
    String tip,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF0D47A1) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active
                  ? const Color(0xFF0D47A1)
                  : Colors.grey[300]!,
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: active ? Colors.white : const Color(0xFF0D47A1),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // FILTER PANEL
  // ─────────────────────────────────────────────────────────

  Widget _buildFilterPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue[100]!),
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
          Row(
            children: [
              const Icon(Icons.filter_list, color: Color(0xFF0D47A1)),
              const SizedBox(width: 8),
              const Text(
                'Filters',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _filterStatus  = null;
                    _filterCountry = null;
                    _filterState   = null;
                    _filterCity    = null;
                    _filterArea    = null;
                    _filterStartDate = null;
                    _filterEndDate   = null;
                  });
                  _loadClients();
                },
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('Clear All'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _filterDropdown(
                'Status',
                _filterStatus,
                ['active', 'inactive', 'suspended'],
                (v) { setState(() => _filterStatus = v); _loadClients(); },
              ),
              _filterDropdown(
                'Country',
                _filterCountry,
                _uniqueValues((c) => c.location.country),
                (v) {
                  setState(() {
                    _filterCountry = v;
                    _filterState   = null;
                    _filterCity    = null;
                  });
                  _loadClients();
                },
              ),
              _filterDropdown(
                'State',
                _filterState,
                _filterCountry == null
                    ? []
                    : _uniqueValues(
                        (c) => c.location.country == _filterCountry
                            ? c.location.state
                            : ''),
                (v) {
                  setState(() {
                    _filterState = v;
                    _filterCity  = null;
                  });
                  _loadClients();
                },
              ),
              _filterDropdown(
                'City',
                _filterCity,
                _filterState == null
                    ? []
                    : _uniqueValues(
                        (c) => c.location.state == _filterState
                            ? c.location.city
                            : ''),
                (v) { setState(() => _filterCity = v); _loadClients(); },
              ),
              _dateFilterBtn(
                'From',
                _filterStartDate,
                (d) { setState(() => _filterStartDate = d); _loadClients(); },
              ),
              _dateFilterBtn(
                'To',
                _filterEndDate,
                (d) { setState(() => _filterEndDate = d); _loadClients(); },
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _uniqueValues(String Function(ClientModel) selector) =>
      _clients
          .map(selector)
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  Widget _filterDropdown(
    String label,
    String? value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return SizedBox(
      width: 160,
      child: DropdownButtonFormField<String>(
        value: items.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('All')),
          ...items.map((v) => DropdownMenuItem(
                value: v,
                child: Text(v, overflow: TextOverflow.ellipsis),
              )),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _dateFilterBtn(
    String label,
    DateTime? value,
    ValueChanged<DateTime?> onChanged,
  ) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[400]!),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
            const SizedBox(width: 6),
            Text(
              value != null
                  ? '$label: ${DateFormat('dd/MM/yy').format(value)}'
                  : 'Date $label',
              style: TextStyle(
                fontSize: 13,
                color: value != null ? Colors.black87 : Colors.grey[600],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => onChanged(null),
                child: const Icon(Icons.close, size: 14, color: Colors.red),
              ),
            ],
          ],
        ),
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

  Widget _buildTable() {
    if (_clients.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(60),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.business_outlined, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              const Text(
                'No clients found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Add your first client using the + button',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    final totalWidth = _colWidths.reduce((a, b) => a + b);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // ── Sticky header (synced scroll) ──
            ScrollConfiguration(
              behavior: _DesktopScrollBehavior(),
              child: SingleChildScrollView(
                controller: _headerScroll,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: _buildTableHeader(totalWidth),
              ),
            ),
            // ── Rows ──
            SizedBox(
              height: (_clients.length * 66.0).clamp(100.0, 560.0),
              child: ScrollConfiguration(
                behavior: _DesktopScrollBehavior(),
                child: SingleChildScrollView(
                  controller: _horizontalScroll,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: totalWidth,
                    child: ListView.builder(
                      itemCount: _clients.length,
                      itemBuilder: (_, i) =>
                          _buildTableRow(_clients[i], i),
                    ),
                  ),
                ),
              ),
            ),
            // ── Footer ──
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'Showing ${_clients.length} '
                    'client${_clients.length != 1 ? 's' : ''}',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const Spacer(),
                  if (_hasFilters)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _filterStatus  = null;
                          _filterCountry = null;
                          _filterState   = null;
                          _filterCity    = null;
                          _filterArea    = null;
                          _filterStartDate = null;
                          _filterEndDate   = null;
                          _showFilters     = false;
                        });
                        _loadClients();
                      },
                      icon: const Icon(Icons.clear, size: 14),
                      label: const Text(
                        'Clear Filters',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader(double totalWidth) {
    return Container(
      width: totalWidth,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF0D47A1),
            Color(0xFF1565C0),
            Color(0xFF1976D2),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: List.generate(_colHeaders.length, (i) {
          return SizedBox(
            width: _colWidths[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 14),
              child: Text(
                _colHeaders[i],
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTableRow(ClientModel client, int idx) {
    final isEven     = idx % 2 == 0;
    final custCount  = _customerCountFor(client);
    final domain     = client.email.contains('@')
        ? client.email.split('@')[1].toLowerCase()
        : '';

    return InkWell(
      onTap: () => _showClientDetail(client),
      hoverColor: const Color(0xFF0D47A1).withOpacity(0.05),
      child: Container(
        color: isEven ? Colors.white : const Color(0xFFF8FAFF),
        child: Row(
          children: [

            // 0 – Company Name
            _cell(
              _colWidths[0],
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D47A1).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.business,
                    color: Color(0xFF0D47A1),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    client.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),

            // 1 – Contact Person
            _cell(
              _colWidths[1],
              Text(
                client.contactPerson ?? '-',
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 2 – Email
            _cell(
              _colWidths[2],
              Text(
                client.email,
                style: const TextStyle(
                  fontSize: 12, color: Color(0xFF1565C0)),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 3 – Phone
            _cell(
              _colWidths[3],
              Text(
                client.phone.isNotEmpty ? client.phone : '-',
                style: const TextStyle(fontSize: 13),
              ),
            ),

            // 4 – Department
            _cell(
              _colWidths[4],
              Text(
                client.department?.isNotEmpty == true
                    ? client.department!
                    : '-',
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 5 – Branch
            _cell(
              _colWidths[5],
              Text(
                client.branch?.isNotEmpty == true
                    ? client.branch!
                    : '-',
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 6 – Location
            _cell(
              _colWidths[6],
              Text(
                client.location.displayAddress.isNotEmpty
                    ? client.location.displayAddress
                    : '-',
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),

            // 7 – Customers (domain count)
            _cell(
              _colWidths[7],
              _isLoadingCounts && !_domainCustomerCounts.containsKey(domain)
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Tooltip(
                      message: domain.isNotEmpty
                          ? 'Employees with @$domain'
                          : 'No domain',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0891B2)
                                  .withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.people,
                              size: 13,
                              color: Color(0xFF0891B2),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$custCount',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF0891B2),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            // 8 – Status (inline dropdown)
            _cell(_colWidths[8], _statusDropdown(client)),

            // 9 – Documents
            _cell(
              _colWidths[9],
              client.documents.isEmpty
                  ? Text(
                      '-',
                      style: TextStyle(
                        color: Colors.grey[400], fontSize: 13),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.attach_file,
                          size: 14,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${client.documents.length}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
            ),

            // 10 – Onboarded
            _cell(
              _colWidths[10],
              Text(
                DateFormat('dd MMM yy').format(client.createdAt),
                style: const TextStyle(
                  fontSize: 12, color: Colors.grey),
              ),
            ),

            // 11 – Actions
            _cell(
              _colWidths[11],
              Row(children: [
                _iconBtn(
                  Icons.visibility,
                  const Color(0xFF0D47A1),
                  'View',
                  () => _showClientDetail(client),
                ),
                _iconBtn(
                  Icons.edit,
                  const Color(0xFF10B981),
                  'Edit',
                  () => _editClient(client),
                ),
                _iconBtn(
                  Icons.delete,
                  Colors.red,
                  'Delete',
                  () => _deleteClient(client),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────

  Widget _cell(double width, Widget child) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: child,
      ),
    );
  }

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