// lib/features/admin/role_based_access/permission.dart
// ============================================================================
// 🔐 PERMISSION MANAGEMENT SCREEN
// UI styled to match careers.php — blue gradient cards, white clean layout
// Opens as an OVERLAY DIALOG (not Navigator.push)
// ============================================================================

import 'package:flutter/material.dart';
import 'package:abra_fleet/core/services/erp_users_management_service.dart';

// ============================================================================
// 🎨 THEME — matches careers.php color system
// ============================================================================
class _Theme {
  // Blues — from careers.php
  static const heroStart        = Color(0xFF0F172A); // .cr-hero gradient start
  static const heroEnd          = Color(0xFF1E40AF); // .cr-hero gradient end
  static const cardHeaderStart  = Color(0xFFEFF6FF); // .cr-card-hdr gradient
  static const cardHeaderEnd    = Color(0xFFDBEAFE); // .cr-card-hdr gradient
  static const iconBgStart      = Color(0xFF1E3A8A); // .cr-card-icon gradient
  static const iconBgEnd        = Color(0xFF3B82F6); // .cr-card-icon gradient
  static const primaryBlue      = Color(0xFF1E3A8A); // headings, borders active
  static const accentBlue       = Color(0xFF3B82F6); // sub text, tags
  static const lightBlue        = Color(0xFFBFDBFE); // borders
  static const bgPage           = Color(0xFFF8FAFC); // .cr-form-wrap bg
  static const cardBg           = Colors.white;
  static const cardBorder       = Color(0xFFE2E8F0); // default border
  static const textPrimary      = Color(0xFF1E293B); // .cr-lbl color
  static const textSecondary    = Color(0xFF64748B); // subtitles
  static const textMuted        = Color(0xFF94A3B8);

  // Access checkbox — green like .jt-t
  static const accessGreen      = Color(0xFF16A34A);
  static const accessGreenBg    = Color(0xFFF0FDF4);
  static const accessGreenBorder= Color(0xFF86EFAC);

  // Edit checkbox — blue
  static const editBlue         = Color(0xFF1E40AF);
  static const editBlueBg       = Color(0xFFEFF6FF);
  static const editBlueBorder   = Color(0xFFBFDBFE);

  // Danger
  static const danger           = Color(0xFFDC2626);
  static const dangerBg         = Color(0xFFFEF2F2);
  static const dangerBorder     = Color(0xFFFECACA);

  // Submit bar — matches .cr-submit-box
  static const submitStart      = Color(0xFF0F172A);
  static const submitEnd        = Color(0xFF1E3A8A);
}

// ============================================================================
// 🚀 STATIC HELPER — show as overlay dialog
// Call: PermissionManagementScreen.showOverlay(context, userId, userName)
// ============================================================================
class PermissionManagementScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const PermissionManagementScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  /// ✅ Open as full-screen overlay dialog (not Navigator.push)
  static Future<void> showOverlay(
    BuildContext context, {
    required String userId,
    required String userName,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(0),
        backgroundColor: Colors.transparent,
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: PermissionManagementScreen(
            userId: userId,
            userName: userName,
          ),
        ),
      ),
    );
  }

  @override
  State<PermissionManagementScreen> createState() =>
      _PermissionManagementScreenState();
}

class _PermissionManagementScreenState
    extends State<PermissionManagementScreen> {
  final ERPUsersManagementService _service = ERPUsersManagementService();

  Map<String, Map<String, dynamic>> _permissions = {};
  bool _isLoading = true;
  bool _isSaving = false;

  // ========================================================================
  // 🗂️ MODULE STRUCTURE — matches careers.php step-card pattern
  // Each module = one "cr-card" equivalent
  // ========================================================================
  final List<Map<String, dynamic>> _modules = [
    {
      'title': 'Dashboard',
      'subtitle': 'Main overview and analytics',
      'icon': Icons.dashboard_rounded,
      'permissions': {'dashboard': 'Dashboard Access'},
    },
    {
      'title': 'HRM (Human Resources)',
      'subtitle': 'Employee, payroll, leave and attendance',
      'icon': Icons.people_alt,
      'permissions': {
        'hrm_employees':      'Employees',
        'hrm_departments':    'Departments',
        'hrm_attendance':     'Attendance',
        'hrm_leave_requests': 'Leave Requests',
        'hrm_payroll':        'Payroll',
        'hrm_notice_board':   'Notice Board',
        'hrm_kpq':            'KPQ',
        'hrm_kpi_evaluation': 'KPI Evaluation',
      },
    },
    {
      'title': 'TMS (Ticket Management)',
      'subtitle': 'Support tickets and issue tracking',
      'icon': Icons.confirmation_number_rounded,
      'permissions': {
        'raise_ticket':   'Raise a Ticket',
        'my_tickets':     'My Tickets',
        'all_tickets':    'All Tickets (Admin)',
        'closed_tickets': 'Closed Tickets',
      },
    },
    {
      'title': 'Feedback Management',
      'subtitle': 'Customer and driver feedback',
      'icon': Icons.feedback_outlined,
      'permissions': {
        'feedback_management': 'Feedback Management',
      },
    },
    {
      'title': 'Client Management',
      'subtitle': 'Client details and contracts',
      'icon': Icons.business_outlined,
      'permissions': {
        'client_details': 'Client Details',
      },
    },
    {
      'title': 'Customer Management',
      'subtitle': 'Customer accounts and approvals',
      'icon': Icons.people_outline,
      'permissions': {
        'all_customers':    'All Customers',
        'pending_approvals': 'Pending Approvals',
      },
    },
    {
      'title': 'Driver Management',
      'subtitle': 'Driver list, trips and feedback',
      'icon': Icons.groups_outlined,
      'permissions': {
        'drivers':            'Drivers List',
        'driver_trip_reports':'Trip Reports',
        'driver_feedback':    'Driver Feedback',
      },
    },
    {
      'title': 'Vehicles',
      'subtitle': 'Fleet, maintenance and GPS',
      'icon': Icons.directions_car_outlined,
      'permissions': {
        'vehicle_master':        'Vehicle Master',
        'vehicle_checklist':     'Vehicle Checklist',
        'gps_tracking':          'GPS Tracking',
        'maintenance_management':'Maintenance Management',
      },
    },
    {
      'title': 'Operations',
      'subtitle': 'Rosters and trip operations',
      'icon': Icons.work_outline,
      'permissions': {
        'pending_rosters': 'Pending Rosters',
        'trip_operation':  'Admin Trip Operations',
        'operations_client_trips': 'Client Trip Operations',
      },
    },
    {
      'title': 'Fleet Map View',
      'subtitle': 'Live vehicle tracking map',
      'icon': Icons.map_outlined,
      'permissions': {
        'fleet_map': 'Fleet Map View',
      },
    },
    {
      'title': 'Trips Summary',
      'subtitle': 'Trip history and analytics',
      'icon': Icons.local_shipping_outlined,
      'permissions': {
        'trips_summary': 'Trips Summary',
      },
    },
    {
      'title': 'SOS Alerts',
      'subtitle': 'Emergency alerts monitoring',
      'icon': Icons.sos_rounded,
      'permissions': {
        'incomplete_alerts': 'Incomplete Alerts',
        'resolved_alerts':   'Resolved Alerts',
      },
    },
    {
      'title': 'Finance Module',
      'subtitle': 'Billing and invoices',
      'icon': Icons.receipt_long_outlined,
      'permissions': {
        'billing': 'Finance / Billing',
      },
    },
    {
      'title': 'Reports',
      'subtitle': 'Analytics and data exports',
      'icon': Icons.analytics_outlined,
      'permissions': {
        'reports': 'Reports & Analytics',
      },
    },
    {
      'title': 'Role Access Control',
      'subtitle': 'Manage user roles and permissions',
      'icon': Icons.admin_panel_settings_outlined,
      'permissions': {
        'role_access_control': 'Role Access Control',
      },

    },
    {
      'title': 'Abra Tours & Travels (T&T)',
      'subtitle': 'Tour packages, leads and careers',
      'icon': Icons.tour_outlined,
      'permissions': {
        'tt_tour_packages': 'Tour Packages',
        'tt_custom_quotes': 'Custom Quotes',
        'tt_sales_leads':   'Sales Leads',
        'tt_manual_leads':  'Manual Leads',
        'tt_careers':       'Careers',
      },
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  // ========================================================================
  // 🔌 LOAD PERMISSIONS
  // ========================================================================
  Future<void> _loadPermissions() async {
    setState(() => _isLoading = true);
    try {
      final response = await _service.fetchPermissions(widget.userId);
      debugPrint('📋 Raw response: $response');

      if (response['success'] != false) {
        dynamic rawData = response['data'];

        // Handle nested: { data: { permissions: {...} } }
        if (rawData is Map && rawData.containsKey('permissions')) {
          rawData = rawData['permissions'];
        }
        // Handle: { permissions: {...} } at root level
        if (rawData == null) rawData = response['permissions'];

        debugPrint('📋 rawData type: ${rawData.runtimeType}');

        if (rawData is Map<String, dynamic>) {
          final Map<String, Map<String, dynamic>> converted = {};
          rawData.forEach((key, value) {
            if (value is Map) {
              final ca = value['can_access'];
              final ed = value['edit_delete'];
              converted[key] = {
                'can_access': ca == true || ca == 1 || ca == '1' || ca == 'true',
                'edit_delete': ed == true || ed == 1 || ed == '1' || ed == 'true',
              };
            } else if (value is bool) {
              converted[key] = {'can_access': value, 'edit_delete': false};
            } else if (value is int) {
              converted[key] = {'can_access': value == 1, 'edit_delete': false};
            } else {
              converted[key] = {'can_access': false, 'edit_delete': false};
            }
          });
          debugPrint('✅ Loaded ${converted.length} permissions');
          if (mounted) setState(() => _permissions = converted);
        }
      }
    } catch (e) {
      debugPrint('❌ Load error: $e');
      _showToast('Failed to load permissions', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ========================================================================
  // 💾 SAVE PERMISSIONS
  // ========================================================================
  Future<void> _savePermissions() async {
    setState(() => _isSaving = true);
    try {
      final response =
          await _service.savePermissions(widget.userId, _permissions);
      if (response['success'] == true) {
        _showToast('Permissions saved successfully!');
        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) Navigator.of(context).pop();
      } else {
        _showToast(
          'Failed to save: ${response['message'] ?? 'Unknown error'}',
          isError: true,
        );
      }
    } catch (e) {
      debugPrint('❌ Save error: $e');
      _showToast('Error saving permissions', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ========================================================================
  // PERMISSION HELPERS
  // ========================================================================
  void _toggle(String key, String type, bool value) {
    setState(() {
      _permissions[key] ??= {};
      _permissions[key]![type] = value;
      // If removing access, also remove edit_delete
      if (type == 'can_access' && !value) {
        _permissions[key]!['edit_delete'] = false;
      }
    });
  }

  void _selectAllInModule(Map<String, String> perms, bool value) {
    setState(() {
      for (final key in perms.keys) {
        _permissions[key] ??= {};
        _permissions[key]!['can_access'] = value;
        _permissions[key]!['edit_delete'] = value;
      }
    });
  }

  void _selectAllGlobal(bool value) {
    setState(() {
      for (final module in _modules) {
        final perms = module['permissions'] as Map<String, String>;
        for (final key in perms.keys) {
          _permissions[key] ??= {};
          _permissions[key]!['can_access'] = value;
          _permissions[key]!['edit_delete'] = value;
        }
      }
    });
  }

  bool _getAccess(String key) =>
      _permissions[key]?['can_access'] == true;

  bool _getEdit(String key) =>
      _permissions[key]?['edit_delete'] == true;

  int _enabledCount(Map<String, String> perms) =>
      perms.keys.where((k) => _getAccess(k)).length;

  // ========================================================================
  // 🎨 BUILD
  // ========================================================================
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _Theme.bgPage,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              _buildHero(),
              _buildQuickActions(),
              Expanded(
                child: _isLoading
                    ? _buildLoading()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        itemCount: _modules.length,
                        itemBuilder: (_, i) => _buildModuleCard(_modules[i]),
                      ),
              ),
              _buildSubmitBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ── HERO — matches .cr-hero dark gradient + .jdm-head style ──
  Widget _buildHero() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_Theme.heroStart, _Theme.heroEnd],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
      child: Row(
        children: [
          // Icon box — matches .cr-card-icon
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3B82F6), Color(0xFF1E40AF)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.security, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Badge — matches .cr-hero-badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.13),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.25), width: 1),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: const Text(
                    'Role Access Control',
                    style: TextStyle(
                      color: Color(0xFF93C5FD),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Manage Permissions',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'for ${widget.userName}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Close button — matches .jdm-close
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ── QUICK ACTIONS — matches .cr-submit-box button pattern ──
  Widget _buildQuickActions() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          _quickBtn(
            label: 'Select All',
            icon: Icons.check_circle_outline,
            color: _Theme.accessGreen,
            bgColor: _Theme.accessGreenBg,
            borderColor: _Theme.accessGreenBorder,
            onTap: () => _selectAllGlobal(true),
          ),
          const SizedBox(width: 8),
          _quickBtn(
            label: 'Select Edit',
            icon: Icons.edit_outlined,
            color: _Theme.editBlue,
            bgColor: _Theme.editBlueBg,
            borderColor: _Theme.editBlueBorder,
            onTap: () {
              setState(() {
                for (final module in _modules) {
                  final perms = module['permissions'] as Map<String, String>;
                  for (final key in perms.keys) {
                    _permissions[key] ??= {};
                    _permissions[key]!['edit_delete'] = true;
                  }
                }
              });
            },
          ),
          const SizedBox(width: 8),
          _quickBtn(
            label: 'Clear All',
            icon: Icons.clear_all,
            color: _Theme.danger,
            bgColor: _Theme.dangerBg,
            borderColor: _Theme.dangerBorder,
            onTap: () => _selectAllGlobal(false),
          ),
        ],
      ),
    );
  }

  Widget _quickBtn({
    required String label,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── MODULE CARD — matches .cr-card from careers.php ──
  Widget _buildModuleCard(Map<String, dynamic> module) {
    final title = module['title'] as String;
    final subtitle = module['subtitle'] as String;
    final icon = module['icon'] as IconData;
    final perms = module['permissions'] as Map<String, String>;
    final enabled = _enabledCount(perms);
    final total = perms.length;
    final hasAny = enabled > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasAny ? _Theme.lightBlue : _Theme.cardBorder,
          width: hasAny ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Card Header — matches .cr-card-hdr
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_Theme.cardHeaderStart, _Theme.cardHeaderEnd],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(17),
                topRight: Radius.circular(17),
              ),
              border: Border(
                bottom: BorderSide(
                  color: _Theme.lightBlue,
                  width: hasAny ? 2 : 1,
                ),
              ),
            ),
            child: Row(
              children: [
                // Icon box — matches .cr-card-icon
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_Theme.iconBgStart, _Theme.iconBgEnd],
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: _Theme.primaryBlue,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: _Theme.accentBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Enabled count badge — matches .vac-badge
                if (hasAny)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: _Theme.primaryBlue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$enabled/$total',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                // All / Clear buttons — matches .dtab style
                _moduleAction('All', _Theme.accessGreen,
                    () => _selectAllInModule(perms, true)),
                const SizedBox(width: 4),
                _moduleAction('Clear', _Theme.danger,
                    () => _selectAllInModule(perms, false)),
              ],
            ),
          ),

          // Card Body — matches .cr-card-body
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              children: [
                // Column headers
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, top: 4),
                  child: Row(
                    children: [
                      const Expanded(child: SizedBox()),
                      _colHeader('Access', _Theme.accessGreen),
                      const SizedBox(width: 4),
                      _colHeader('Edit / Delete', _Theme.accentBlue),
                    ],
                  ),
                ),
                ...perms.entries
                    .map((e) => _buildPermRow(e.key, e.value))
                    .toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _moduleAction(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          border: Border.all(color: color.withOpacity(0.35), width: 1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _colHeader(String label, Color color) {
    return SizedBox(
      width: 80,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ── PERMISSION ROW — matches job card row layout ──
  Widget _buildPermRow(String key, String label) {
    final canAccess = _getAccess(key);
    final canEdit = _getEdit(key);

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        // Matches .job-card hover — subtle bg tint when enabled
        color: canAccess
            ? _Theme.accessGreenBg
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: canAccess ? _Theme.accessGreenBorder : _Theme.cardBorder,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Permission label — matches .jc-desc style
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: canAccess ? FontWeight.w700 : FontWeight.w500,
                color: canAccess ? _Theme.textPrimary : _Theme.textSecondary,
              ),
            ),
          ),
          // Access checkbox
          SizedBox(
            width: 80,
            child: Center(
              child: _styledCheckbox(
                value: canAccess,
                activeColor: _Theme.accessGreen,
                onChanged: (v) => _toggle(key, 'can_access', v ?? false),
              ),
            ),
          ),
          // Edit/Delete checkbox — disabled if no access
          SizedBox(
            width: 80,
            child: Center(
              child: _styledCheckbox(
                value: canEdit,
                activeColor: _Theme.editBlue,
                enabled: canAccess,
                onChanged: canAccess
                    ? (v) => _toggle(key, 'edit_delete', v ?? false)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _styledCheckbox({
    required bool value,
    required Color activeColor,
    bool enabled = true,
    ValueChanged<bool?>? onChanged,
  }) {
    return Transform.scale(
      scale: 1.1,
      child: Checkbox(
        value: value,
        onChanged: enabled ? onChanged : null,
        activeColor: activeColor,
        checkColor: Colors.white,
        side: BorderSide(
          color: enabled
              ? (value ? activeColor : const Color(0xFFCBD5E1))
              : const Color(0xFFE2E8F0),
          width: 1.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  // ── SUBMIT BAR — matches .cr-submit-box ──
  Widget _buildSubmitBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [_Theme.submitStart, _Theme.submitEnd],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        children: [
          // Cancel — matches .btn-hs outlined style
          Expanded(
            child: GestureDetector(
              onTap: _isSaving ? null : () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.3), width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Save — matches .btn-submit style
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _isSaving ? null : _savePermissions,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFF1E40AF)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3B82F6).withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isSaving)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    else
                      const Icon(Icons.save_rounded,
                          color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _isSaving ? 'Saving...' : 'Save Permissions',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: _Theme.primaryBlue),
          SizedBox(height: 14),
          Text(
            'Loading permissions...',
            style: TextStyle(
              color: _Theme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? _Theme.danger : _Theme.accessGreen,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(20),
        duration: Duration(milliseconds: isError ? 3000 : 1500),
      ),
    );
  }
}