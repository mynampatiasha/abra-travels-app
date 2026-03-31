// ============================================================================
// ERP USERS MANAGEMENT SCREEN
// - Recurring Invoices UI pattern (3-breakpoint top bar, gradient stat
//   cards, dark navy table, ellipsis pagination)
// - AppTopBar (default)
// - Per-row: Permissions + Edit + Delete + Raise Ticket (all direct, no popup)
// ============================================================================
// File: lib/features/admin/role_based_access/erp_users_management_screen.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';

import 'package:abra_fleet/core/services/safe_api_service.dart';
import 'package:abra_fleet/core/services/error_handler_service.dart';
import 'package:abra_fleet/core/services/tms_service.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/admin/ERP/permission.dart';
import 'app_top_bar.dart';

// ─── colour palette (same as recurring_invoices_list_page) ───────────────────
const Color _navy   = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);
const Color _teal   = Color(0xFF00897B);

// ─── stat card helper ─────────────────────────────────────────────────────────
class _StatCardData {
  final String label, value;
  final IconData icon;
  final Color color;
  final List<Color> gradientColors;
  const _StatCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.gradientColors,
  });
}

// ============================================================================
//  MODEL
// ============================================================================
class ERPUser {
  final String id;
  final String name;
  final String username;
  final String email;
  final String phone;
  final String? office;
  final String? role;
  final String status;
  final DateTime? createdAt;
  final Map<String, dynamic>? permissions;

  const ERPUser({
    required this.id,
    required this.name,
    required this.username,
    required this.email,
    required this.phone,
    this.office,
    this.role,
    this.status = 'active',
    this.createdAt,
    this.permissions,
  });

  factory ERPUser.fromJson(Map<String, dynamic> json) {
    return ERPUser(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name_parson']?.toString() ?? json['name']?.toString() ?? '',
      username: json['username']?.toString() ?? json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      office: json['office']?.toString(),
      role: json['role']?.toString() ?? 'employee',
      status: json['status']?.toString() ?? json['estado']?.toString() ?? 'active',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      permissions: json['permissions'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name_parson': name,
    'username': username,
    'email': email,
    'phone': phone,
    if (office != null) 'office': office,
    'role': role ?? 'employee',
    'status': status,
  };
}

// ============================================================================
//  MAIN SCREEN
// ============================================================================
class ERPUsersManagementScreen extends StatefulWidget {
  const ERPUsersManagementScreen({super.key});

  @override
  State<ERPUsersManagementScreen> createState() =>
      _ERPUsersManagementScreenState();
}

class _ERPUsersManagementScreenState extends State<ERPUsersManagementScreen>
    with ErrorHandlerMixin {
  final SafeApiService _safeApi = SafeApiService();

  // ── data ──────────────────────────────────────────────────────────────────
  List<ERPUser> _users        = [];
  List<ERPUser> _filtered     = [];
  bool    _isLoading          = true;
  String? _errorMessage;
  String? _currentUserRole;

  // ── search ────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();

  // ── filter ────────────────────────────────────────────────────────────────
  String _selectedStatus = 'All';
  String _selectedRole   = 'All';
  bool   _showFilters    = false;
  final List<String> _statusFilters = ['All', 'active', 'inactive'];
  final List<String> _roleFilters   = ['All', 'admin', 'employee', 'super_admin'];

  // ── pagination ────────────────────────────────────────────────────────────
  int _currentPage       = 1;
  int _totalPages        = 1;
  final int _itemsPerPage = 20;

  // ── scroll ────────────────────────────────────────────────────────────────
  final ScrollController _tableHScrollCtrl = ScrollController();
  final ScrollController _statsHScrollCtrl = ScrollController();

  // ── selection ─────────────────────────────────────────────────────────────
  Set<int> _selectedRows = {};
  bool _selectAll = false;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _resolveCurrentRole();
    _fetchUsers();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tableHScrollCtrl.dispose();
    _statsHScrollCtrl.dispose();
    super.dispose();
  }

  // ── API ───────────────────────────────────────────────────────────────────
  Future<void> _resolveCurrentRole() async {
    try {
      final authRepo = Provider.of<AuthRepository>(context, listen: false);
      final user = authRepo.currentUser;
      if (mounted) setState(() => _currentUserRole = user.role?.toLowerCase());
    } catch (e) {
      handleSilentError(e, context: 'Resolve Current Role');
    }
  }

  bool get _canManage =>
      _currentUserRole == 'super_admin' || _currentUserRole == 'admin';

  Future<void> _fetchUsers() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final response = await _safeApi.safeGet(
        '/api/erp-users',
        context: 'Fetch ERP Users',
        fallback: {'success': false, 'data': []},
      );
      if (response['success'] != false && response['data'] != null) {
        final users = (response['data'] as List)
            .map((j) => ERPUser.fromJson(j))
            .toList();
        if (mounted) {
          setState(() { _users = users; _isLoading = false; });
          _applyFilters();
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      handleSilentError(e, context: 'Fetch ERP Users');
      if (mounted) setState(() { _isLoading = false; _errorMessage = e.toString(); });
    }
  }

  Future<bool> _createUser(Map<String, dynamic> body) async {
    try {
      final r = await _safeApi.safePost('/api/erp-users', body: body,
          context: 'Create ERP User', fallback: {'success': false});
      return r['success'] != false;
    } catch (e) { handleSilentError(e, context: 'Create ERP User'); return false; }
  }

  Future<bool> _updateUser(String id, Map<String, dynamic> body) async {
    try {
      final r = await _safeApi.safePut('/api/erp-users/$id', body: body,
          context: 'Update ERP User', fallback: {'success': false});
      return r['success'] != false;
    } catch (e) { handleSilentError(e, context: 'Update ERP User'); return false; }
  }

  Future<bool> _deleteUser(String id) async {
    try {
      final r = await _safeApi.safeDelete('/api/erp-users/$id',
          context: 'Delete ERP User', fallback: {'success': false});
      return r['success'] != false;
    } catch (e) { handleSilentError(e, context: 'Delete ERP User'); return false; }
  }

  // ── filter / search ───────────────────────────────────────────────────────
  void _applyFilters() {
    setState(() {
      final q = _searchController.text.toLowerCase();
      _filtered = _users.where((u) {
        if (q.isNotEmpty &&
            !u.name.toLowerCase().contains(q) &&
            !u.email.toLowerCase().contains(q) &&
            !u.username.toLowerCase().contains(q) &&
            !u.phone.contains(q)) return false;
        if (_selectedStatus != 'All' && u.status != _selectedStatus) return false;
        if (_selectedRole   != 'All' && (u.role ?? '') != _selectedRole) return false;
        return true;
      }).toList();
      _totalPages  = (_filtered.length / _itemsPerPage).ceil().clamp(1, 9999);
      if (_currentPage > _totalPages) _currentPage = _totalPages;
      _selectedRows.clear();
      _selectAll = false;
    });
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _selectedStatus = 'All';
      _selectedRole   = 'All';
      _currentPage    = 1;
      _showFilters    = false;
    });
    _applyFilters();
  }

  bool get _hasAnyFilter =>
      _selectedStatus != 'All' || _selectedRole != 'All' ||
      _searchController.text.isNotEmpty;

  List<ERPUser> get _currentPageItems {
    final start = (_currentPage - 1) * _itemsPerPage;
    final end   = (start + _itemsPerPage).clamp(0, _filtered.length);
    return _filtered.sublist(start, end);
  }

  // ── selection ─────────────────────────────────────────────────────────────
  void _toggleSelectAll(bool? v) {
    setState(() {
      _selectAll = v ?? false;
      _selectedRows = _selectAll
          ? Set.from(List.generate(_currentPageItems.length, (i) => i))
          : {};
    });
  }

  void _toggleRow(int i) {
    setState(() {
      _selectedRows.contains(i) ? _selectedRows.remove(i) : _selectedRows.add(i);
      _selectAll = _selectedRows.length == _currentPageItems.length;
    });
  }

  // ── actions ───────────────────────────────────────────────────────────────
  void _openNew() {
    showDialog(
      context: context,
      builder: (_) => _UserDialog(
        title: 'Add New User',
        onSave: (data) async {
          final ok = await _createUser(data);
          if (ok) { _showSuccess('User created successfully!'); _fetchUsers(); }
          else _showError('Failed to create user');
        },
      ),
    );
  }

  void _openEdit(ERPUser user) {
    showDialog(
      context: context,
      builder: (_) => _UserDialog(
        title: 'Edit User',
        user: user,
        onSave: (data) async {
          final ok = await _updateUser(user.id, data);
          if (ok) { _showSuccess('User updated successfully!'); _fetchUsers(); }
          else _showError('Failed to update user');
        },
      ),
    );
  }

  void _confirmDelete(ERPUser user) {
    showDialog(
      context: context,
      builder: (_) => _ConfirmDeleteDialog(
        userName: user.name,
        onConfirm: () async {
          final ok = await _deleteUser(user.id);
          if (ok) { _showSuccess('User deleted successfully!'); _fetchUsers(); }
          else _showError('Failed to delete user');
        },
      ),
    );
  }

  void _openPermissions(ERPUser user) {
    PermissionManagementScreen.showOverlay(
      context,
      userId: user.id,
      userName: user.name,
    );
  }

  void _raiseTicket(ERPUser user) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RaiseTicketOverlay(
        user: user,
        onTicketRaised: (msg) => _showSuccess(msg),
        onError: (msg) => _showError(msg),
      ),
    );
  }

  // ── snackbars ─────────────────────────────────────────────────────────────
  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: _green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: _red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
  }

  // =========================================================================
  //  BUILD
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Role Access Control'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(
        child: Column(children: [
          _buildTopBar(),
          if (_showFilters) _buildFiltersBar(),
          _buildStatsCards(),
          _isLoading
              ? const SizedBox(
                  height: 400,
                  child: Center(child: CircularProgressIndicator(color: _navy)))
              : _errorMessage != null
                  ? SizedBox(height: 400, child: _buildErrorState())
                  : _filtered.isEmpty
                      ? SizedBox(height: 400, child: _buildEmptyState())
                      : _buildTable(),
          if (!_isLoading && _filtered.isNotEmpty) _buildPagination(),
        ]),
      ),
    );
  }

  // ── top bar ───────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 1100) return _topBarDesktop();
        if (c.maxWidth >= 700)  return _topBarTablet();
        return _topBarMobile();
      }),
    );
  }

  Widget _topBarDesktop() => Row(children: [
    _statusDropdown(),
    const SizedBox(width: 12),
    _roleDropdown(),
    const SizedBox(width: 12),
    _searchField(width: 220),
    const SizedBox(width: 10),
    _iconBtn(Icons.filter_list,
        () => setState(() => _showFilters = !_showFilters),
        tooltip: 'Filters',
        color: _showFilters ? _navy : const Color(0xFF7F8C8D),
        bg: _showFilters ? _navy.withOpacity(0.08) : const Color(0xFFF1F1F1)),
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded,
        _isLoading ? null : _fetchUsers,
        tooltip: 'Refresh'),
    const Spacer(),
    if (_canManage) _actionBtn('New User', Icons.add_rounded, _navy, _openNew),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 10),
      _roleDropdown(),
      const SizedBox(width: 8),
      Expanded(child: _searchField(width: double.infinity)),
      const SizedBox(width: 8),
      _iconBtn(Icons.filter_list,
          () => setState(() => _showFilters = !_showFilters),
          tooltip: 'Filters'),
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded,
          _isLoading ? null : _fetchUsers,
          tooltip: 'Refresh'),
    ]),
    if (_canManage) ...[
      const SizedBox(height: 10),
      _actionBtn('New User', Icons.add_rounded, _navy, _openNew),
    ],
  ]);

  Widget _topBarMobile() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Expanded(child: _searchField(width: double.infinity)),
      const SizedBox(width: 8),
      if (_canManage) _actionBtn('New', Icons.add_rounded, _navy, _openNew),
    ]),
    const SizedBox(height: 10),
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      _statusDropdown(),
      const SizedBox(width: 8),
      _roleDropdown(),
      const SizedBox(width: 8),
      _iconBtn(Icons.filter_list,
          () => setState(() => _showFilters = !_showFilters)),
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded,
          _isLoading ? null : _fetchUsers, tooltip: 'Refresh'),
    ])),
  ]);

  // ── filters bar ───────────────────────────────────────────────────────────
  Widget _buildFiltersBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFF7F9FC),
      child: LayoutBuilder(builder: (_, c) {
        final clearBtn = TextButton.icon(
          onPressed: _clearFilters,
          icon: const Icon(Icons.clear, size: 16),
          label: const Text('Clear All'),
          style: TextButton.styleFrom(foregroundColor: _red),
        );
        if (c.maxWidth < 700) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Filters', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navy)),
            const SizedBox(height: 8),
            _advDropdown(_selectedStatus, _statusFilters,
                (v) { setState(() { _selectedStatus = v!; _currentPage = 1; }); _applyFilters(); }),
            const SizedBox(height: 8),
            _advDropdown(_selectedRole, _roleFilters,
                (v) { setState(() { _selectedRole = v!; _currentPage = 1; }); _applyFilters(); }),
            const SizedBox(height: 8),
            if (_hasAnyFilter) Align(alignment: Alignment.centerRight, child: clearBtn),
          ]);
        }
        return Row(children: [
          const Text('Filters:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
          const SizedBox(width: 12),
          SizedBox(width: 160, child: _advDropdown(_selectedStatus, _statusFilters,
              (v) { setState(() { _selectedStatus = v!; _currentPage = 1; }); _applyFilters(); })),
          const SizedBox(width: 10),
          SizedBox(width: 160, child: _advDropdown(_selectedRole, _roleFilters,
              (v) { setState(() { _selectedRole = v!; _currentPage = 1; }); _applyFilters(); })),
          const Spacer(),
          if (_hasAnyFilter) clearBtn,
        ]);
      }),
    );
  }

  Widget _advDropdown(String value, List<String> items, ValueChanged<String?> onChanged) {
    return Container(
      height: 40, padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFDDE3EE)),
          borderRadius: BorderRadius.circular(10)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value, isExpanded: true,
          icon: const Icon(Icons.expand_more, size: 18),
          style: const TextStyle(fontSize: 13, color: Color(0xFF2C3E50)),
          items: items.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ── reusable widgets ──────────────────────────────────────────────────────
  Widget _statusDropdown() => Container(
    height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        border: Border.all(color: const Color(0xFFDDE3EE)),
        borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedStatus,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _navy),
        items: _statusFilters.map((s) => DropdownMenuItem(
            value: s, child: Text(s == 'All' ? 'All Status' : s.toUpperCase()))).toList(),
        onChanged: (v) {
          if (v != null) { setState(() { _selectedStatus = v; _currentPage = 1; }); _applyFilters(); }
        },
      ),
    ),
  );

  Widget _roleDropdown() => Container(
    height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        border: Border.all(color: const Color(0xFFDDE3EE)),
        borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedRole,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _navy),
        items: _roleFilters.map((s) => DropdownMenuItem(
            value: s, child: Text(s == 'All' ? 'All Roles' : s.toUpperCase()))).toList(),
        onChanged: (v) {
          if (v != null) { setState(() { _selectedRole = v; _currentPage = 1; }); _applyFilters(); }
        },
      ),
    ),
  );

  Widget _searchField({required double width}) {
    final field = TextField(
      controller: _searchController,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search by name, email, username…',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () { _searchController.clear(); setState(() => _currentPage = 1); _applyFilters(); })
            : null,
        filled: true, fillColor: const Color(0xFFF7F9FC),
        contentPadding: const EdgeInsets.symmetric(vertical: 0), isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
      ),
    );
    if (width == double.infinity) return field;
    return SizedBox(width: width, height: 44, child: field);
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap,
      {String tooltip = '', Color color = const Color(0xFF7F8C8D), Color bg = const Color(0xFFF1F1F1)}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.25))),
          child: Icon(icon, size: 20, color: onTap == null ? Colors.grey[300] : color),
        ),
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color bg, VoidCallback? onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg, foregroundColor: Colors.white,
        disabledBackgroundColor: bg.withOpacity(0.5),
        elevation: 0, minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── stat cards ────────────────────────────────────────────────────────────
  Widget _buildStatsCards() {
    final total    = _users.length;
    final active   = _users.where((u) => u.status == 'active').length;
    final inactive = _users.where((u) => u.status != 'active').length;
    final admins   = _users.where((u) => (u.role ?? '') == 'admin' || (u.role ?? '') == 'super_admin').length;
    final employees= _users.where((u) => (u.role ?? '') == 'employee').length;

    final cards = [
      _StatCardData(label: 'Total Users', value: total.toString(), icon: Icons.people_rounded, color: _navy, gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)]),
      _StatCardData(label: 'Active', value: active.toString(), icon: Icons.check_circle_outline, color: _green, gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      _StatCardData(label: 'Inactive', value: inactive.toString(), icon: Icons.cancel_outlined, color: _red, gradientColors: const [Color(0xFFFF6B6B), Color(0xFFE74C3C)]),
      _StatCardData(label: 'Admins', value: admins.toString(), icon: Icons.admin_panel_settings_outlined, color: _purple, gradientColors: const [Color(0xFFBB8FCE), Color(0xFF9B59B6)]),
      _StatCardData(label: 'Employees', value: employees.toString(), icon: Icons.badge_outlined, color: _blue, gradientColors: const [Color(0xFF5DADE2), Color(0xFF2980B9)]),
    ];

    return Container(
      width: double.infinity,
      color: const Color(0xFFF0F4F8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(builder: (_, c) {
        final isMobile = c.maxWidth < 700;
        if (isMobile) {
          return SingleChildScrollView(
            controller: _statsHScrollCtrl, scrollDirection: Axis.horizontal,
            child: Row(children: cards.asMap().entries.map((e) => Container(
              width: 160, margin: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0),
              child: _buildStatCard(e.value, compact: true),
            )).toList()),
          );
        }
        return Row(children: cards.asMap().entries.map((e) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0),
            child: _buildStatCard(e.value, compact: false),
          ),
        )).toList());
      }),
    );
  }

  Widget _buildStatCard(_StatCardData d, {required bool compact}) {
    return Container(
      padding: compact
          ? const EdgeInsets.all(12)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [d.gradientColors[0].withOpacity(0.15), d.gradientColors[1].withOpacity(0.08)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d.color.withOpacity(0.22)),
        boxShadow: [BoxShadow(color: d.color.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(d.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 10),
              Text(d.label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(d.value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: d.color)),
            ])
          : Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: d.color.withOpacity(0.30), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Icon(d.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Text(d.value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: d.color)),
              ])),
            ]),
    );
  }

  // ── table ─────────────────────────────────────────────────────────────────
  Widget _buildTable() {
    final items = _currentPageItems;
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))]),
      child: LayoutBuilder(builder: (context, constraints) {
        return Scrollbar(
          controller: _tableHScrollCtrl,
          thumbVisibility: true, trackVisibility: true, thickness: 8, radius: const Radius.circular(4),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad}),
            child: SingleChildScrollView(
              controller: _tableHScrollCtrl, scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFF0D1B3E)),
                  headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.4),
                  headingRowHeight: 52, dataRowMinHeight: 64, dataRowMaxHeight: 80,
                  dataTextStyle: const TextStyle(fontSize: 13),
                  dataRowColor: WidgetStateProperty.resolveWith((s) {
                    if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
                    return null;
                  }),
                  dividerThickness: 1, columnSpacing: 18, horizontalMargin: 16,
                  columns: [
                    DataColumn(label: SizedBox(width: 36,
                        child: Checkbox(value: _selectAll,
                            fillColor: WidgetStateProperty.all(Colors.white),
                            checkColor: const Color(0xFF0D1B3E),
                            onChanged: _toggleSelectAll))),
                    const DataColumn(label: SizedBox(width: 220, child: Text('USER'))),
                    const DataColumn(label: SizedBox(width: 220, child: Text('EMAIL'))),
                    const DataColumn(label: SizedBox(width: 140, child: Text('PHONE'))),
                    const DataColumn(label: SizedBox(width: 130, child: Text('ROLE'))),
                    const DataColumn(label: SizedBox(width: 100, child: Text('STATUS'))),
                    const DataColumn(label: SizedBox(width: 300, child: Text('ACTIONS'))),
                  ],
                  rows: items.asMap().entries.map((e) => _buildRow(e.key, e.value)).toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildRow(int index, ERPUser user) {
    final isSel = _selectedRows.contains(index);
    return DataRow(
      selected: isSel,
      color: WidgetStateProperty.resolveWith((s) {
        if (isSel) return _navy.withOpacity(0.06);
        if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
        return null;
      }),
      cells: [
        // Checkbox
        DataCell(Checkbox(value: isSel, onChanged: (_) => _toggleRow(index))),

        // User (avatar + name + username)
        DataCell(SizedBox(width: 220, child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF2463AE), Color(0xFF1e3a8a)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              shape: BoxShape.circle,
            ),
            child: Center(child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            )),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(user.name, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 13)),
            Text('@${user.username}', overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ])),
        ]))),

        // Email
        DataCell(SizedBox(width: 220,
            child: Text(user.email, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)))),

        // Phone
        DataCell(SizedBox(width: 140,
            child: Text(user.phone.isEmpty ? '—' : user.phone,
                style: const TextStyle(fontSize: 13)))),

        // Role badge
        DataCell(SizedBox(width: 130, child: _roleBadge(user.role ?? 'employee'))),

        // Status badge
        DataCell(SizedBox(width: 100, child: _statusBadge(user.status))),

        // Actions — all direct, no popup
        DataCell(SizedBox(width: 300,
            child: _canManage
                ? Row(children: [
                    _rowActionBtn(
                      icon: Icons.security_rounded,
                      label: 'Permissions',
                      color: _teal,
                      onTap: () => _openPermissions(user),
                    ),
                    const SizedBox(width: 6),
                    _rowActionBtn(
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                      color: _orange,
                      onTap: () => _openEdit(user),
                    ),
                    const SizedBox(width: 6),
                    _rowActionBtn(
                      icon: Icons.confirmation_number_outlined,
                      label: 'Ticket',
                      color: _purple,
                      onTap: () => _raiseTicket(user),
                    ),
                    const SizedBox(width: 6),
                    _rowActionBtn(
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      color: _red,
                      onTap: () => _confirmDelete(user),
                    ),
                  ])
                : const SizedBox())),
      ],
    );
  }

  Widget _rowActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.30), width: 1.2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ]),
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final isActive = status.toLowerCase() == 'active';
    final bg    = isActive ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2);
    final fg    = isActive ? const Color(0xFF15803D) : const Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20), border: Border.all(color: fg.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(status.toUpperCase(), style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 11)),
      ]),
    );
  }

  Widget _roleBadge(String role) {
    final Color color;
    switch (role.toLowerCase()) {
      case 'super_admin': color = _red;    break;
      case 'admin':       color = _purple; break;
      default:            color = _blue;   break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.30))),
      child: Text(role.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }

  // ── pagination ────────────────────────────────────────────────────────────
  Widget _buildPagination() {
    List<int> pages;
    if (_totalPages <= 5) {
      pages = List.generate(_totalPages, (i) => i + 1);
    } else {
      final start = (_currentPage - 2).clamp(1, _totalPages - 4);
      pages = List.generate(5, (i) => start + i);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFEEF2F7)))),
      child: LayoutBuilder(builder: (_, c) {
        return Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: [
            Text(
              'Showing ${(_currentPage - 1) * _itemsPerPage + 1}–${(_currentPage * _itemsPerPage).clamp(0, _filtered.length)} of ${_filtered.length}'
              '${_filtered.length != _users.length ? ' (filtered from ${_users.length})' : ''}',
              style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _pageNavBtn(icon: Icons.chevron_left, enabled: _currentPage > 1,
                  onTap: () { setState(() => _currentPage--); }),
              const SizedBox(width: 4),
              if (pages.first > 1) ...[
                _pageNumBtn(1),
                if (pages.first > 2) Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text('…', style: TextStyle(color: Colors.grey[400]))),
              ],
              ...pages.map(_pageNumBtn),
              if (pages.last < _totalPages) ...[
                if (pages.last < _totalPages - 1) Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text('…', style: TextStyle(color: Colors.grey[400]))),
                _pageNumBtn(_totalPages),
              ],
              const SizedBox(width: 4),
              _pageNavBtn(icon: Icons.chevron_right, enabled: _currentPage < _totalPages,
                  onTap: () { setState(() => _currentPage++); }),
            ]),
          ],
        );
      }),
    );
  }

  Widget _pageNumBtn(int page) {
    final isActive = _currentPage == page;
    return GestureDetector(
      onTap: () { if (!isActive) setState(() => _currentPage = page); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 2), width: 34, height: 34,
        decoration: BoxDecoration(
            color: isActive ? _navy : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isActive ? _navy : Colors.grey[300]!)),
        child: Center(child: Text('$page', style: TextStyle(
            fontSize: 13, fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? Colors.white : Colors.grey[700]))),
      ),
    );
  }

  Widget _pageNavBtn({required IconData icon, required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
            color: enabled ? Colors.white : Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!)),
        child: Icon(icon, size: 18, color: enabled ? _navy : Colors.grey[300]),
      ),
    );
  }

  // ── empty / error states ──────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(color: _navy.withOpacity(0.06), shape: BoxShape.circle),
          child: Icon(Icons.people_outline, size: 64, color: _navy.withOpacity(0.4))),
      const SizedBox(height: 20),
      const Text('No Users Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
      const SizedBox(height: 8),
      Text(_hasAnyFilter ? 'Try adjusting your filters' : 'Add your first ERP user',
          style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      const SizedBox(height: 28),
      ElevatedButton.icon(
        onPressed: _hasAnyFilter ? _clearFilters : _openNew,
        icon: Icon(_hasAnyFilter ? Icons.filter_list_off : Icons.add),
        label: Text(_hasAnyFilter ? 'Clear Filters' : 'Add User',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white,
            elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ])));
  }

  Widget _buildErrorState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
          child: Icon(Icons.error_outline, size: 56, color: Colors.red[400])),
      const SizedBox(height: 20),
      const Text('Failed to Load Users', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(_errorMessage ?? 'Unknown error',
              style: TextStyle(color: Colors.grey[500]), textAlign: TextAlign.center)),
      const SizedBox(height: 28),
      ElevatedButton.icon(
        onPressed: _fetchUsers, icon: const Icon(Icons.refresh),
        label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white,
            elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ])));
  }
}

// ============================================================================
//  RAISE TICKET OVERLAY
// ============================================================================
class _RaiseTicketOverlay extends StatefulWidget {
  final ERPUser user;
  final void Function(String) onTicketRaised;
  final void Function(String) onError;
  const _RaiseTicketOverlay({
    required this.user,
    required this.onTicketRaised,
    required this.onError,
  });

  @override
  State<_RaiseTicketOverlay> createState() => _RaiseTicketOverlayState();
}

class _RaiseTicketOverlayState extends State<_RaiseTicketOverlay> {
  final _tmsService = TMSService();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filtered  = [];
  Map<String, dynamic>?      _selectedEmp;
  bool   _loading   = true;
  bool   _assigning = false;
  String _priority  = 'Medium';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    final resp = await _tmsService.fetchEmployees();
    if (resp['success'] == true && resp['data'] != null) {
      setState(() {
        _employees = List<Map<String, dynamic>>.from(resp['data']);
        _filtered  = _employees;
        _loading   = false;
      });
    } else {
      setState(() => _loading = false);
      widget.onError('Failed to load employees');
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _employees
          : _employees.where((e) =>
              (e['name_parson'] ?? '').toLowerCase().contains(q) ||
              (e['email'] ?? '').toLowerCase().contains(q) ||
              (e['role'] ?? '').toLowerCase().contains(q)).toList();
    });
  }

  String _buildTicketMessage() {
    final u = widget.user;
    return 'ERP User "${u.name}" (@${u.username}) requires attention.\n\n'
           'User Details:\n'
           '• Email   : ${u.email}\n'
           '• Phone   : ${u.phone.isEmpty ? 'N/A' : u.phone}\n'
           '• Role    : ${u.role ?? 'employee'}\n'
           '• Status  : ${u.status}\n'
           '${u.office != null ? '• Office  : ${u.office}\n' : ''}\n'
           'Please review and take necessary action.';
  }

  Future<void> _assign() async {
    if (_selectedEmp == null) return;
    setState(() => _assigning = true);
    try {
      final resp = await _tmsService.createTicket(
        subject:    'ERP User: ${widget.user.name}',
        message:    _buildTicketMessage(),
        priority:   _priority,
        timeline:   1440,
        assignedTo: _selectedEmp!['_id'].toString(),
      );
      setState(() => _assigning = false);
      if (resp['success'] == true) {
        widget.onTicketRaised('Ticket assigned to ${_selectedEmp!['name_parson']}');
        if (mounted) Navigator.pop(context);
      } else {
        widget.onError(resp['message'] ?? 'Failed to create ticket');
      }
    } catch (e) {
      setState(() => _assigning = false);
      widget.onError('Failed to assign ticket: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        width: 520,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.80),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF2463AE)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Raise a Ticket', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('User: ${widget.user.name}',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12), overflow: TextOverflow.ellipsis),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),

          // Body
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Auto message preview
              const Text('Auto-generated message', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFDDE3EE))),
                child: Text(_buildTicketMessage(), style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.5)),
              ),
              const SizedBox(height: 20),

              // Priority
              const Text('Priority', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
              const SizedBox(height: 8),
              Row(children: ['Low', 'Medium', 'High'].map((pr) {
                final isSel = _priority == pr;
                final color = pr == 'High' ? _red : pr == 'Medium' ? _orange : _green;
                return Expanded(child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () => setState(() => _priority = pr),
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSel ? color : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isSel ? color : Colors.grey[300]!),
                        boxShadow: isSel ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))] : [],
                      ),
                      child: Center(child: Text(pr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSel ? Colors.white : Colors.grey[700]))),
                    ),
                  ),
                ));
              }).toList()),
              const SizedBox(height: 20),

              // Employee search
              const Text('Assign To', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search employees…',
                  prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
                  filled: true, fillColor: const Color(0xFFF7F9FC),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
                ),
              ),
              const SizedBox(height: 8),

              // Employee list
              _loading
                  ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: _navy)))
                  : _filtered.isEmpty
                      ? Container(height: 80, alignment: Alignment.center,
                          child: Text('No employees found', style: TextStyle(color: Colors.grey[500])))
                      : Container(
                          constraints: const BoxConstraints(maxHeight: 260),
                          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF2F7)),
                            itemBuilder: (_, i) {
                              final emp   = _filtered[i];
                              final isSel = _selectedEmp?['_id'] == emp['_id'];
                              return InkWell(
                                onTap: () => setState(() => _selectedEmp = isSel ? null : emp),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  color: isSel ? _navy.withOpacity(0.06) : Colors.transparent,
                                  child: Row(children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: isSel ? _navy : _navy.withOpacity(0.10),
                                      child: Text(
                                        (emp['name_parson'] ?? 'U')[0].toUpperCase(),
                                        style: TextStyle(color: isSel ? Colors.white : _navy, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(emp['name_parson'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      if (emp['email'] != null)
                                        Text(emp['email'], style: TextStyle(fontSize: 11, color: Colors.grey[600]), overflow: TextOverflow.ellipsis),
                                      if (emp['role'] != null)
                                        Container(
                                          margin: const EdgeInsets.only(top: 3),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: _navy.withOpacity(0.08), borderRadius: BorderRadius.circular(4)),
                                          child: Text(emp['role'].toString().toUpperCase(),
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _navy)),
                                        ),
                                    ])),
                                    if (isSel) const Icon(Icons.check_circle, color: _navy, size: 20),
                                  ]),
                                ),
                              );
                            },
                          )),
            ]),
          )),

          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F9FC),
              border: Border(top: BorderSide(color: Color(0xFFEEF2F7))),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
            ),
            child: Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey[700],
                  side: BorderSide(color: Colors.grey[300]!),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: (_selectedEmp == null || _assigning) ? null : _assign,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy, foregroundColor: Colors.white,
                  disabledBackgroundColor: _navy.withOpacity(0.4),
                  elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _assigning
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        _selectedEmp != null ? 'Assign to ${_selectedEmp!['name_parson'] ?? ''}' : 'Select Employee',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
              )),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ============================================================================
//  USER DIALOG (ADD / EDIT)
// ============================================================================
class _UserDialog extends StatefulWidget {
  final String title;
  final ERPUser? user;
  final Function(Map<String, dynamic>) onSave;
  const _UserDialog({required this.title, this.user, required this.onSave});

  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _usernameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _passwordCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl     = TextEditingController(text: widget.user?.name ?? '');
    _usernameCtrl = TextEditingController(text: widget.user?.username ?? '');
    _emailCtrl    = TextEditingController(text: widget.user?.email ?? '');
    _phoneCtrl    = TextEditingController(text: widget.user?.phone ?? '');
    _passwordCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _usernameCtrl.dispose();
    _emailCtrl.dispose(); _phoneCtrl.dispose(); _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF2463AE)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.person_add, color: Colors.white, size: 22)),
              const SizedBox(width: 14),
              Expanded(child: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),

          // Form
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(children: [
                _formField(controller: _nameCtrl, label: 'Full Name', icon: Icons.person,
                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null),
                const SizedBox(height: 14),
                _formField(controller: _emailCtrl, label: 'Email', icon: Icons.email,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) { if (v?.isEmpty ?? true) return 'Required'; if (!v!.contains('@')) return 'Invalid email'; return null; }),
                const SizedBox(height: 14),
                _formField(controller: _phoneCtrl, label: 'Phone', icon: Icons.phone,
                    keyboardType: TextInputType.phone,
                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null),
                const SizedBox(height: 14),
                _formField(controller: _usernameCtrl, label: 'Username', icon: Icons.account_circle,
                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null),
                const SizedBox(height: 14),
                _formField(
                    controller: _passwordCtrl,
                    label: widget.user == null ? 'Password' : 'Password (leave blank to keep)',
                    icon: Icons.lock, obscureText: true,
                    validator: (v) {
                      if (widget.user == null && (v?.isEmpty ?? true)) return 'Required';
                      return null;
                    }),
              ]),
            ),
          )),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey[300]!),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: ElevatedButton(
                onPressed: _handleSave,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _navy, foregroundColor: Colors.white,
                    elevation: 0, padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Save', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              )),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _formField({
    required TextEditingController controller,
    required String label, required IconData icon,
    TextInputType? keyboardType, bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller, keyboardType: keyboardType,
      obscureText: obscureText, validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _navy, size: 20),
        filled: true, fillColor: const Color(0xFFF7F9FC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _red)),
      ),
    );
  }

  void _handleSave() {
    if (_formKey.currentState?.validate() ?? false) {
      widget.onSave({
        'name_parson': _nameCtrl.text.trim(),
        'email':       _emailCtrl.text.trim(),
        'phone':       _phoneCtrl.text.trim(),
        'username':    _usernameCtrl.text.trim(),
        if (_passwordCtrl.text.isNotEmpty) 'password': _passwordCtrl.text,
      });
      Navigator.pop(context);
    }
  }
}

// ============================================================================
//  CONFIRM DELETE DIALOG
// ============================================================================
class _ConfirmDeleteDialog extends StatelessWidget {
  final String userName;
  final VoidCallback onConfirm;
  const _ConfirmDeleteDialog({required this.userName, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
              child: Icon(Icons.warning_amber_rounded, color: Colors.red[400], size: 40)),
          const SizedBox(height: 20),
          const Text('Delete User?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text('Are you sure you want to delete "$userName"?',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          const SizedBox(height: 6),
          Text('This action cannot be undone.',
              style: TextStyle(fontSize: 12, color: Colors.red[400], fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey[300]!),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
            )),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              onPressed: () { Navigator.pop(context); onConfirm(); },
              style: ElevatedButton.styleFrom(
                  backgroundColor: _red, foregroundColor: Colors.white,
                  elevation: 0, padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Delete', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            )),
          ]),
        ]),
      ),
    );
  }
}