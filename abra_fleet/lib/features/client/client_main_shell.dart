// lib/features/client/presentation/screens/client_main_shell.dart
// ═══════════════════════════════════════════════════════════════
// ENTERPRISE CLIENT PORTAL - Redesigned for Infosys / Cognizant
// Design: "Enterprise Command Center" — MoveInSync / SafeTrax grade
// ═══════════════════════════════════════════════════════════════
// PART 1 OF 4 — Imports · Theme · Class · State · Init · Auth · Notifications
// ⚠️  Combine all 4 parts in order to get the complete file.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'package:abra_fleet/app/config/api_config.dart';
// import 'client_dashboard.dart'; // Removed - using ClientDashboardAnalytics directly
import 'client_dashboard_analytics.dart';
import 'client_employee_management.dart';
import 'client_roster_management.dart';
import 'client_sos_alerts.dart';
import 'client_profile_page.dart';
import 'client_reports_analytics_enhanced.dart';
import 'client_reports_dashboard.dart';
import 'client_based_all_vehicles.dart';
import 'package:abra_fleet/features/notifications/presentation/screens/client_notifications_screen.dart';
import 'package:abra_fleet/core/services/client_notification_service.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/auth/presentation/screens/welcome_screen.dart';
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:abra_fleet/features/admin/hrm/hrm_feedback.dart';
import 'client_trip_dashboard_part1.dart';
import 'client_all_trips.dart';

// ─────────────────────────────────────────────────────────────
// ENTERPRISE DESIGN SYSTEM  — FONT SIZES UPDATED TO CORPORATE STANDARD
// All sizes increased: body min 14px, labels 15-16px, headings 18-32px
// ─────────────────────────────────────────────────────────────
class EDS {
  // Core Palette
  static const Color navy       = Color(0xFF0F172A);
  static const Color navyMid    = Color(0xFF1E293B);
  static const Color blue       = Color(0xFF1D4ED8);
  static const Color blueLight  = Color(0xFF3B82F6);
  static const Color cyan       = Color(0xFF0891B2);
  static const Color cyanLight  = Color(0xFFE0F2FE);
  static const Color surface    = Color(0xFFFFFFFF);
  static const Color canvas     = Color(0xFFF1F5F9);
  static const Color border     = Color(0xFFE2E8F0);
  static const Color textPri    = Color(0xFF0F172A);
  static const Color textSec    = Color(0xFF64748B);
  static const Color textTer    = Color(0xFF94A3B8);
  static const Color green      = Color(0xFF059669);
  static const Color greenLight = Color(0xFFDCFCE7);
  static const Color amber      = Color(0xFFD97706);
  static const Color amberLight = Color(0xFFFEF3C7);
  static const Color red        = Color(0xFFDC2626);
  static const Color redLight   = Color(0xFFFEE2E2);
  static const Color purple     = Color(0xFF7C3AED);
  static const Color purpleLight= Color(0xFFEDE9FE);

  static const String fontDisplay = 'Outfit';
  static const String fontBody    = 'DM Sans';

  // ── UPDATED: display() — used for headings, module names, KPI values
  //    Old → New mapping:
  //    10 → 14 | 11 → 15 | 12 → 16 | 13 → 17 | 14 → 18 | 16 → 20
  //    18 → 22 | 20 → 24 | 22 → 26 | 24 → 28 | 28 → 32
  static TextStyle display(double size, {FontWeight w = FontWeight.w700, Color? color}) {
    final adjusted = _scaleDisplay(size);
    return TextStyle(
      fontSize: adjusted,
      fontWeight: w,
      color: color ?? textPri,
      letterSpacing: -0.5,
      height: 1.25,
    );
  }

  // ── UPDATED: body() — used for descriptions, labels, subtitles
  //    Old → New mapping:
  //    10 → 13 | 11 → 14 | 12 → 15 | 13 → 16 | 14 → 17 | 15 → 18
  static TextStyle body(double size, {FontWeight w = FontWeight.w400, Color? color}) {
    final adjusted = _scaleBody(size);
    return TextStyle(
      fontSize: adjusted,
      fontWeight: w,
      color: color ?? textSec,
      height: 1.55,
    );
  }

  // Scale helpers — centralised so one change updates everything
  static double _scaleDisplay(double s) {
    if (s <= 10) return 14;
    if (s <= 11) return 15;
    if (s <= 12) return 16;
    if (s <= 13) return 17;
    if (s <= 14) return 18;
    if (s <= 16) return 20;
    if (s <= 18) return 22;
    if (s <= 20) return 24;
    if (s <= 22) return 26;
    if (s <= 24) return 28;
    if (s <= 28) return 32;
    return s + 4;
  }

  static double _scaleBody(double s) {
    if (s <= 10) return 13;
    if (s <= 11) return 14;
    if (s <= 12) return 15;
    if (s <= 13) return 16;
    if (s <= 14) return 17;
    if (s <= 15) return 18;
    return s + 3;
  }

  // Elevation shadows
  static List<BoxShadow> shadowSm = [
    BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.06),
              blurRadius: 8, offset: const Offset(0, 2)),
  ];
  static List<BoxShadow> shadowMd = [
    BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.08),
              blurRadius: 16, offset: const Offset(0, 4)),
    BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.04),
              blurRadius: 4, offset: const Offset(0, 1)),
  ];
  static List<BoxShadow> shadowLg = [
    BoxShadow(color: const Color(0xFF1D4ED8).withOpacity(0.15),
              blurRadius: 32, offset: const Offset(0, 8)),
    BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.06),
              blurRadius: 8, offset: const Offset(0, 2)),
  ];

  // Border radius
  static BorderRadius radiusSm   = BorderRadius.circular(8);
  static BorderRadius radiusMd   = BorderRadius.circular(12);
  static BorderRadius radiusLg   = BorderRadius.circular(16);
  static BorderRadius radiusXl   = BorderRadius.circular(20);
  static BorderRadius radiusFull = BorderRadius.circular(100);
}

// ─────────────────────────────────────────────────────────────
// MODULE DEFINITION
// ─────────────────────────────────────────────────────────────
class PortalModule {
  final String id;
  final String label;
  final String description;
  final IconData icon;
  final Color accent;
  final Color accentLight;
  final String? liveCountKey;
  final String liveLabel;

  const PortalModule({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.accent,
    required this.accentLight,
    this.liveCountKey,
    this.liveLabel = '',
  });
}

// ─────────────────────────────────────────────────────────────
// MAIN SHELL
// ─────────────────────────────────────────────────────────────
class ClientMainShell extends StatefulWidget {
  const ClientMainShell({Key? key}) : super(key: key);

  @override
  State<ClientMainShell> createState() => _ClientMainShellState();
}

class _ClientMainShellState extends State<ClientMainShell>
    with TickerProviderStateMixin {

  final _storage = const FlutterSecureStorage();

  int _activeScreen = -1;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  int _notificationCount = 0;
  final Map<String, int> _liveCounts = {
    // 'employees': 0,
    // 'sos': 0,
    // 'roster_pending': 0,
  };

  final _notificationService = ClientNotificationService();

  String? _userId;
  String? _userName;
  String? _userEmail;
  String? _clientOrgName;

  static const List<PortalModule> _modules = [
    PortalModule(
      id: 'employees',
      label: 'Employee Management',
      description: 'Manage employee profiles, onboarding & assignments',
      icon: Icons.people_alt_rounded,
      accent: EDS.blue,
      accentLight: Color(0xFFEFF6FF),
      liveCountKey: 'employees',
      liveLabel: 'Total Employees',
    ),
    PortalModule(
      id: 'trips',
      label: 'Trips Summary',
      description: 'View and manage all trip schedules and assignments',
      icon: Icons.calendar_month_rounded,
      accent: EDS.cyan,
      accentLight: EDS.cyanLight,
      liveCountKey: 'roster_pending',
      liveLabel: 'View Trips',
    ),
    PortalModule(
      id: 'sos',
      label: 'SOS Alerts',
      description: 'Real-time emergency alerts & incident tracking',
      icon: Icons.warning_amber_rounded,
      accent: EDS.red,
      accentLight: EDS.redLight,
      liveCountKey: 'sos',
      liveLabel: 'Active Alerts',
    ),
    PortalModule(
      id: 'reports',
      label: 'Reports & Analytics',
      description: 'Fleet performance, compliance & utilisation reports',
      icon: Icons.analytics_rounded,
      accent: EDS.purple,
      accentLight: EDS.purpleLight,
      liveCountKey: null,
      liveLabel: 'View Reports',
    ),
    PortalModule(
      id: 'live_map',
      label: 'Live Map Tracking',
      description: 'Real-time GPS tracking of all assigned vehicles',
      icon: Icons.map_rounded,
      accent: EDS.green,
      accentLight: EDS.greenLight,
      liveCountKey: null,
      liveLabel: 'Track Live',
    ),
    PortalModule(
      id: 'feedback',
      label: 'Feedback Management',
      description: 'Employee feedback, ratings & grievance resolution',
      icon: Icons.feedback_rounded,
      accent: EDS.amber,
      accentLight: EDS.amberLight,
      liveCountKey: null,
      liveLabel: 'View Feedback',
    ),
    PortalModule(
      id: 'profile',
      label: 'Organization Profile',
      description: 'Manage your organization details & settings',
      icon: Icons.business_rounded,
      accent: Color(0xFF9333EA),
      accentLight: Color(0xFFFAF5FF),
      liveCountKey: null,
      liveLabel: 'Edit Profile',
    ),
    // ── Dashboard module commented out (analytics now shown above modules) ──
    // PortalModule(
    //   id: 'dashboard',
    //   label: 'Dashboard',
    //   description: 'Overview of fleet operations and key metrics',
    //   icon: Icons.dashboard_rounded,
    //   accent: Color(0xFF0891B2),
    //   accentLight: Color(0xFFCFFAFE),
    //   liveCountKey: null,
    //   liveLabel: 'View Dashboard',
    // ),
  ];

  Widget _screenForModule(String id) {
    switch (id) {
      case 'employees':   return const ClientEmployeeManagement();
      case 'trips':       return ClientTripDashboard();
      case 'sos':         return const ClientSOSAlerts();
      case 'reports':     return const ClientReportsAnalyticsEnhanced();
      case 'live_map':    return const ClientBasedAllVehicles();
      case 'feedback':    return const HRMFeedbackScreen();
      case 'profile':     return const ClientProfilePage();
      case 'dashboard':   return _buildHomeGrid(MediaQuery.of(context).size.width < 768);
      default:            return const SizedBox.shrink();
    }
  }

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();

    _loadUserData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _notificationService.setupListener(context);
        _setupPolling();
      }
    });
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_data');
    final userData = raw != null ? jsonDecode(raw) : null;

    if (!mounted) return;
    setState(() {
      _userId        = userData?['id'];
      _userName      = userData?['name'] ?? 'User';
      _userEmail     = userData?['email'] ?? '';
      _clientOrgName = userData?['organizationName'] ??
                       userData?['companyName']      ??
                       userData?['name']             ??
                       'Your Organization';
    });
    _fetchKpiCounts();
  }

  Future<void> _fetchKpiCounts() async {
    try {
      final userDataStr = await _storage.read(key: 'user_data');
      if (userDataStr == null) return;
      final userData = json.decode(userDataStr);
      final email = userData['email'] as String? ?? '';
      if (email.isEmpty) return;

      final domain = email.contains('@') ? email.split('@').last : '';
      if (domain.isEmpty) return;

      final token = await _storage.read(key: 'auth_token') ?? '';
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final baseUrl = ApiConfig.baseUrl;

      final analyticsRes = await http.get(
        Uri.parse('$baseUrl/api/admin/client-analytics/trip-stats?limit=50'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      int employeeCount = 0;
      if (analyticsRes.statusCode == 200) {
        final body = json.decode(analyticsRes.body);
        final clients = body['data']?['clients'] as List? ?? [];
        for (final c in clients) {
          if ((c['domain'] ?? '').toString().toLowerCase() == domain.toLowerCase()) {
            employeeCount = (c['customerCount'] ?? 0) as int;
            break;
          }
        }
      }

      final sosRes = await http.get(
        Uri.parse('$baseUrl/api/sos?status=ACTIVE&organizationDomain=$domain&limit=500'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      int sosCount = 0;
      if (sosRes.statusCode == 200) {
        final body = json.decode(sosRes.body);
        sosCount = (body['pagination']?['total'] ?? (body['data'] as List? ?? []).length) as int;
      }

      final rosterRes = await http.get(
        Uri.parse('$baseUrl/api/roster/admin/pending'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      int rosterPending = 0;
      if (rosterRes.statusCode == 200) {
        final body = json.decode(rosterRes.body);
        rosterPending = (body['count'] ?? (body['data'] as List? ?? []).length) as int;
      }

      if (mounted) {
        setState(() {
          _liveCounts['employees']      = employeeCount;
          _liveCounts['sos']            = sosCount;
          _liveCounts['roster_pending'] = rosterPending;
        });
      }
    } catch (e) {
      debugPrint('KPI fetch error: $e');
    }
  }

  void _setupPolling() {
    Stream.periodic(const Duration(seconds: 10)).asyncMap((_) async {
      try {
        final api = ApiService();
        final res = await api.get('/api/notifications/unread-count');
        return res;
      } catch (_) {
        return {'success': false, 'count': 0};
      }
    }).listen((res) {
      if (!mounted) return;
      setState(() {
        _notificationCount =
            res['success'] == true ? (res['count'] as int? ?? 0) : 0;
      });
    });

    _fetchKpiCounts();
    Stream.periodic(const Duration(seconds: 30)).listen((_) {
      if (!mounted) return;
      _fetchKpiCounts();
    });
  }

  void _navigateTo(String moduleId) {
    if (moduleId == 'live_map') {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const ClientBasedAllVehicles()));
      return;
    }
    if (moduleId == 'trips') {
      // Show dialog to choose between Employee Trip History or Organization Trip History
      _showTripHistoryDialog();
      return;
    }
    if (moduleId == 'reports') {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => ClientReportsAnalyticsEnhanced()));
      return;
    }
    _fadeController.reset();
    setState(() => _activeScreen = _modules.indexWhere((m) => m.id == moduleId));
    _fadeController.forward();
  }

  void _goHome() {
    _fadeController.reset();
    setState(() => _activeScreen = -1);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _notificationService.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // ROOT BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 768;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: EDS.canvas,
        body: Column(
          children: [
            isMobile ? _buildMobileHeader() : _buildDesktopNavBar(),
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: _activeScreen == -1
                    ? _buildHomeGrid(isMobile)
                    : _buildModuleScreen(isMobile),
              ),
            ),
            if (isMobile && _activeScreen != -1) _buildMobileBottomNav(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // DESKTOP TOP NAVIGATION BAR  — increased from 68 → 76px height
  // ─────────────────────────────────────────────────────────────
  Widget _buildDesktopNavBar() {
    return Container(
      height: 76,   // ↑ was 68
      decoration: BoxDecoration(
        color: EDS.navy,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Row(
          children: [
            // ── Brand pill ─────────────────────────────────────
            GestureDetector(
              onTap: _goHome,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: EDS.radiusMd,
                      border: Border.all(
                          color: Colors.white.withOpacity(0.15), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34,   // ↑ was 28
                          height: 34,
                          decoration: BoxDecoration(
                            color: EDS.blue,
                            borderRadius: EDS.radiusSm,
                          ),
                          child: Center(
                            child: Text(
                              (_clientOrgName ?? 'O').substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,   // ↑ was 14
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _clientOrgName ?? 'Organization',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,   // ↑ was 15
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                              ),
                            ),
                            Text(
                              'Fleet Management Portal',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.55),
                                fontSize: 13,   // ↑ was 10
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 24),

            // ── Breadcrumb ──────────────────────────────────────
            if (_activeScreen != -1) ...[
              Icon(Icons.chevron_right,
                  color: Colors.white.withOpacity(0.35), size: 18),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: EDS.blue.withOpacity(0.25),
                  borderRadius: EDS.radiusSm,
                  border: Border.all(color: EDS.blueLight.withOpacity(0.4)),
                ),
                child: Text(
                  _modules[_activeScreen].label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,   // ↑ was 13
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],

            const Spacer(),

            if (_activeScreen != -1)
              _navIconBtn(
                icon: Icons.home_rounded,
                tooltip: 'Back to Home',
                onTap: _goHome,
              ),

            const SizedBox(width: 4),

            _navIconBtn(
              icon: Icons.headset_mic_outlined,
              tooltip: 'Support',
              onTap: () => _showSupportDialog(),
            ),

            const SizedBox(width: 4),

            // Notifications
            Stack(
              clipBehavior: Clip.none,
              children: [
                _navIconBtn(
                  icon: Icons.notifications_outlined,
                  tooltip: 'Notifications',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => const ClientNotificationsScreen())),
                ),
                if (_notificationCount > 0)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      width: 20,   // ↑ was 18
                      height: 20,
                      decoration: BoxDecoration(
                        color: EDS.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: EDS.navy, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          _notificationCount > 9 ? '9+' : '$_notificationCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,   // ↑ was 8
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 16),

            // ── User pill ─────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: EDS.radiusFull,
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 16,   // ↑ was 14
                    backgroundColor: EDS.blue,
                    child: Text(
                      (_userName ?? 'U').substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,   // ↑ was 13
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _userName ?? 'User',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,   // ↑ was 13
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Transport Manager',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.55),
                          fontSize: 12,   // ↑ was 10
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _showLogoutDialog,
                    child: Tooltip(
                      message: 'Logout',
                      child: Icon(
                        Icons.logout_rounded,
                        color: Colors.white.withOpacity(0.6),
                        size: 18,   // ↑ was 16
                      ),
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

  // ─────────────────────────────────────────────────────────────
  // MOBILE HEADER
  // ─────────────────────────────────────────────────────────────
  Widget _buildMobileHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 12, 16, 12),
      decoration: BoxDecoration(
        color: EDS.navy,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_activeScreen != -1)
            GestureDetector(
              onTap: _goHome,
              child: Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: EDS.radiusSm,
                ),
                child: const Icon(Icons.arrow_back_rounded,
                    color: Colors.white, size: 20),
              ),
            ),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _activeScreen == -1
                      ? (_clientOrgName ?? 'Portal')
                      : _modules[_activeScreen].label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                if (_activeScreen == -1)
                  Text(
                    'Fleet Management Portal',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
              ],
            ),
          ),

          Stack(
            clipBehavior: Clip.none,
            children: [
              _navIconBtn(
                icon: Icons.notifications_outlined,
                tooltip: 'Notifications',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => const ClientNotificationsScreen())),
              ),
              if (_notificationCount > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: EDS.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: EDS.navy, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        '$_notificationCount',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
          _navIconBtn(
            icon: Icons.logout_rounded,
            tooltip: 'Logout',
            onTap: _showLogoutDialog,
          ),
        ],
      ),
    );
  }

  Widget _navIconBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: EDS.radiusSm,
        child: Container(
          width: 44,   // ↑ was 40
          height: 44,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: EDS.radiusSm,
          ),
          child: Icon(icon, color: Colors.white.withOpacity(0.75), size: 24),
        ),
      ),
    );
  }

  Widget _buildModuleScreen(bool isMobile) {
    final module = _modules[_activeScreen];
    return _screenForModule(module.id);
  }

  // ─────────────────────────────────────────────────────────────
  // HOME GRID
  // ─────────────────────────────────────────────────────────────
  Widget _buildHomeGrid(bool isMobile) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 32,
        vertical: 28,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGreetingBanner(isMobile),
          SizedBox(height: isMobile ? 22 : 30),
          
          // ── Dashboard Analytics Card ──
          const ClientDashboardAnalytics(),
          SizedBox(height: isMobile ? 28 : 36),

          // Section header
          Row(
            children: [
              Text('Modules', style: EDS.display(isMobile ? 20 : 22)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: EDS.cyanLight,
                  borderRadius: EDS.radiusFull,
                ),
                child: Text(
                  '${_modules.length} available',
                  style: EDS.body(13, w: FontWeight.w600, color: EDS.cyan),
                  // ↑ was body(11)
                ),
              ),
            ],
          ),

          SizedBox(height: isMobile ? 16 : 20),

          isMobile
              ? _buildMobileModuleList()
              : _buildDesktopModuleGrid(),

          SizedBox(height: isMobile ? 28 : 36),
          _buildPoweredByFooter(isMobile),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // GREETING BANNER
  // ─────────────────────────────────────────────────────────────
  Widget _buildGreetingBanner(bool isMobile) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good Morning'
        : hour < 17
            ? 'Good Afternoon'
            : 'Good Evening';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 20 : 32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF1D4ED8), Color(0xFF0891B2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.55, 1.0],
        ),
        borderRadius: EDS.radiusXl,
        boxShadow: EDS.shadowLg,
      ),
      child: Stack(
        children: [
          if (!isMobile) ...[
            Positioned(
              right: -20, top: -20,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
            Positioned(
              right: 40, bottom: -30,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
          ],

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Live badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: EDS.radiusFull,
                  border: Border.all(color: Colors.white.withOpacity(0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4ADE80),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        'All Systems Operational',
                        style: EDS.body(isMobile ? 12 : 13, w: FontWeight.w600, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: isMobile ? 12 : 18),

              Text(
                '$greeting, ${_userName ?? 'there'}!',
                style: EDS.display(isMobile ? 20 : 30, color: Colors.white),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),

              const SizedBox(height: 6),

              Text(
                'Welcome to the ${_clientOrgName ?? 'your organization'} Fleet Portal',
                style: EDS.body(isMobile ? 13 : 17,
                    color: Colors.white.withOpacity(0.8)),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),

              SizedBox(height: isMobile ? 14 : 22),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _bannerChip(icon: Icons.calendar_today_rounded, label: _formattedDate(), isMobile: isMobile),
                  if ((_liveCounts['employees'] ?? 0) > 0)
                    _bannerChip(
                      icon: Icons.people_alt_rounded,
                      label: '${_liveCounts['employees'] ?? 0} Employees',
                      isMobile: isMobile,
                    ),
                  if ((_liveCounts['sos'] ?? 0) > 0)
                    _bannerChip(
                      icon: Icons.warning_amber_rounded,
                      label: '${_liveCounts['sos']} SOS Active',
                      isAlert: true,
                      isMobile: isMobile,
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bannerChip({
    required IconData icon,
    required String label,
    bool isAlert = false,
    bool isMobile = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: isMobile ? 5 : 7),
      decoration: BoxDecoration(
        color: isAlert
            ? EDS.red.withOpacity(0.25)
            : Colors.white.withOpacity(0.15),
        borderRadius: EDS.radiusFull,
        border: Border.all(
          color: isAlert
              ? EDS.red.withOpacity(0.4)
              : Colors.white.withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: isMobile ? 13 : 15),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: EDS.body(isMobile ? 12 : 14, w: FontWeight.w600, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formattedDate() {
    final now = DateTime.now();
    const days   = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  // ─────────────────────────────────────────────────────────────




  // ─────────────────────────────────────────────────────────────
  // MODULE GRID — DESKTOP
  // ─────────────────────────────────────────────────────────────
  Widget _buildDesktopModuleGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1.05,   // slightly taller for bigger text
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _modules.length,
      itemBuilder: (_, i) => _buildModuleCard(_modules[i], compact: false),
    );
  }

  Widget _buildMobileModuleList() {
    return Column(
      children: _modules
          .map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildModuleCard(m, compact: true),
              ))
          .toList(),
    );
  }

  Widget _buildModuleCard(PortalModule module, {required bool compact}) {
    final count = module.liveCountKey != null
        ? _liveCounts[module.liveCountKey!]
        : null;
    final hasAlert = (count ?? 0) > 0 && module.id == 'sos';

    return _HoverCard(
      onTap: () => _navigateTo(module.id),
      child: compact
          ? _mobileModuleCardContent(module, count, hasAlert)
          : _desktopModuleCardContent(module, count, hasAlert),
    );
  }

  Widget _desktopModuleCardContent(
      PortalModule module, int? count, bool hasAlert) {
    return Padding(
      padding: const EdgeInsets.all(22),   // ↑ was 20
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,   // ↑ was 44
                height: 50,
                decoration: BoxDecoration(
                  color: module.accentLight,
                  borderRadius: EDS.radiusMd,
                ),
                child: Icon(module.icon, color: module.accent, size: 26),   // ↑ was 22
              ),
              const Spacer(),
              if (count != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: hasAlert ? EDS.redLight : module.accentLight,
                    borderRadius: EDS.radiusFull,
                  ),
                  child: Text(
                    '$count',
                    style: EDS.body(14, w: FontWeight.w700,   // ↑ was body(12)
                        color: hasAlert ? EDS.red : module.accent),
                  ),
                ),
              Icon(Icons.arrow_forward_rounded, color: EDS.textTer, size: 18),
            ],
          ),
          const Spacer(),
          Text(module.label, style: EDS.display(16, color: EDS.textPri)),
          // ↑ was display(14)
          const SizedBox(height: 5),
          Text(module.description,
              style: EDS.body(13, color: EDS.textSec),   // ↑ was body(11)
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 14),
          // CTA strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: module.accentLight,
              borderRadius: EDS.radiusSm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(module.liveLabel,
                    style: EDS.body(13, w: FontWeight.w600, color: module.accent)),
                    // ↑ was body(11)
                const SizedBox(width: 5),
                Icon(Icons.chevron_right, color: module.accent, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileModuleCardContent(
      PortalModule module, int? count, bool hasAlert) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: module.accentLight,
              borderRadius: EDS.radiusMd,
            ),
            child: Icon(module.icon, color: module.accent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  module.label,
                  style: EDS.display(14, color: EDS.textPri),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 3),
                Text(
                  module.description,
                  style: EDS.body(12, color: EDS.textSec),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (count != null && count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: hasAlert ? EDS.redLight : module.accentLight,
                borderRadius: EDS.radiusFull,
              ),
              child: Text('$count',
                  style: EDS.body(12, w: FontWeight.w700,
                      color: hasAlert ? EDS.red : module.accent)),
            ),
          const SizedBox(width: 4),
          Icon(Icons.arrow_forward_ios_rounded, color: EDS.textTer, size: 14),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // POWERED BY FOOTER
  // ─────────────────────────────────────────────────────────────
  Widget _buildPoweredByFooter(bool isMobile) {
    return Center(
      child: Column(
        children: [
          Divider(color: EDS.border, height: 1),
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: EDS.blue,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.directions_bus,
                    color: Colors.white, size: 15),
              ),
              const SizedBox(width: 10),
              Text(
                'Powered by Abra Fleet',
                style: EDS.body(14, w: FontWeight.w500, color: EDS.textTer),
                // ↑ was body(12)
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '© ${DateTime.now().year} Abra Fleet Management System',
            style: EDS.body(13, color: EDS.textTer),   // ↑ was body(10)
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // MOBILE BOTTOM NAVIGATION
  // ─────────────────────────────────────────────────────────────
  Widget _buildMobileBottomNav() {
    final quickModules = [
      _modules.firstWhere((m) => m.id == 'employees'),
      _modules.firstWhere((m) => m.id == 'trips'),
      _modules.firstWhere((m) => m.id == 'sos'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: EDS.surface,
        border: Border(top: BorderSide(color: EDS.border, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          0, 0, 0, MediaQuery.of(context).padding.bottom),
      child: Row(
        children: [
          Expanded(
            child: _bottomTab(
              icon: Icons.home_rounded,
              label: 'Home',
              isActive: false,
              onTap: _goHome,
              activeColor: EDS.blue,
            ),
          ),
          ...quickModules.map((m) {
            final idx = _modules.indexOf(m);
            return Expanded(
              child: _bottomTab(
                icon: m.icon,
                label: m.label.split(' ').first,
                isActive: _activeScreen == idx,
                onTap: () => _navigateTo(m.id),
                activeColor: m.accent,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _bottomTab({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required Color activeColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),   // ↑ was 10
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: isActive ? activeColor : EDS.textTer,
                size: 24),   // ↑ was 22
            const SizedBox(height: 4),
            Text(
              label,
              style: EDS.body(12,   // ↑ was body(10)
                  w: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? activeColor : EDS.textTer),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TRIP HISTORY SELECTION DIALOG
  // ─────────────────────────────────────────────────────────────
  void _showTripHistoryDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: EDS.radiusMd),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: EDS.cyanLight,
                  borderRadius: EDS.radiusSm,
                ),
                child: const Icon(Icons.calendar_month_rounded, color: EDS.cyan, size: 24),
              ),
              const SizedBox(height: 14),
              Text('Select Trip History', style: EDS.display(18)),
              const SizedBox(height: 6),
              Text(
                'Choose which trip history to view',
                style: EDS.body(13, color: EDS.textSec),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              
              // Employee Trip History Button
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ClientTripDashboard()),
                  );
                },
                borderRadius: EDS.radiusSm,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: EDS.blue.withOpacity(0.08),
                    borderRadius: EDS.radiusSm,
                    border: Border.all(color: EDS.blue.withOpacity(0.3), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: EDS.blue,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.person_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Employee Trip History',
                              style: EDS.display(14, color: EDS.blue),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'View trips for individual employees',
                              style: EDS.body(11, color: EDS.textSec),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded, color: EDS.blue, size: 14),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 10),
              
              // Organization Trip History Button
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ClientAllTripsPage()),
                  );
                },
                borderRadius: EDS.radiusSm,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: EDS.cyan.withOpacity(0.08),
                    borderRadius: EDS.radiusSm,
                    border: Border.all(color: EDS.cyan.withOpacity(0.3), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: EDS.cyan,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.business_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Organization Trip History',
                              style: EDS.display(14, color: EDS.cyan),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'View all trips across organization',
                              style: EDS.body(11, color: EDS.textSec),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded, color: EDS.cyan, size: 14),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 14),
              
              // Cancel Button
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: EDS.textSec,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // LOGOUT DIALOG - Compact size matching admin_main_shell.dart
  // ─────────────────────────────────────────────────────────────
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _handleLogout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SUPPORT DIALOG
  // ─────────────────────────────────────────────────────────────
  void _showSupportDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: EDS.radiusXl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E3A8A), Color(0xFF1D4ED8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: EDS.radiusMd,
                      ),
                      child: const Icon(Icons.headset_mic_rounded,
                          color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Support Center',
                              style: EDS.display(18, color: Colors.white)),
                              // ↑ was display(16)
                          const SizedBox(height: 3),
                          Text("We're here 24 × 7 to help you",
                              style: EDS.body(14,
                                  color: Colors.white.withOpacity(0.75))),
                                  // ↑ was body(12)
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 22),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Body
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: EDS.cyanLight,
                        borderRadius: EDS.radiusMd,
                        border: Border.all(color: EDS.cyan.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.access_time_rounded,
                              color: EDS.cyan, size: 22),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Available 24 / 7',
                                  style: EDS.body(15,
                                      w: FontWeight.w700,
                                      color: EDS.textPri)),
                                      // ↑ was body(13)
                              Text('All days • Round the clock',
                                  style: EDS.body(13)),   // ↑ was body(11)
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    _supportCard(
                      icon: Icons.phone_rounded,
                      title: 'Call Support',
                      subtitle: '+91 886-728-8076',
                      color: EDS.blue,
                      onTap: () => _launchUrl('tel:+918867288076'),
                    ),
                    const SizedBox(height: 10),
                    _supportCard(
                      icon: Icons.chat_bubble_rounded,
                      title: 'WhatsApp',
                      subtitle: 'Chat with us instantly',
                      color: const Color(0xFF25D366),
                      onTap: () => _launchUrl('https://wa.me/918867288076'),
                    ),
                    const SizedBox(height: 10),
                    _supportCard(
                      icon: Icons.email_rounded,
                      title: 'Email Support',
                      subtitle: 'support@fleet.abra-travels.com',
                      color: EDS.amber,
                      onTap: () => _launchUrl(
                          'mailto:support@fleet.abra-travels.com?subject=Fleet Portal Support'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _supportCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: EDS.radiusMd,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: EDS.surface,
          borderRadius: EDS.radiusMd,
          border: Border.all(color: EDS.border),
          boxShadow: EDS.shadowSm,
        ),
        child: Row(
          children: [
            Container(
              width: 46,   // ↑ was 42
              height: 46,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: EDS.radiusSm,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: EDS.body(16, w: FontWeight.w700, color: EDS.textPri)),
                      // ↑ was body(14)
                  const SizedBox(height: 2),
                  Text(subtitle, style: EDS.body(14)),   // ↑ was body(12)
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: EDS.textTer, size: 16),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // LOGOUT HANDLER
  // ─────────────────────────────────────────────────────────────
  void _handleLogout() async {
    try {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        );
      }

      final authRepo = Provider.of<AuthRepository>(context, listen: false);
      await authRepo.signOut();
      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: $e'),
            backgroundColor: EDS.red,
          ),
        );
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unable to open: $url'),
              backgroundColor: EDS.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ URL launch error: $e');
    }
  }
} // ← end of _ClientMainShellState

// ═════════════════════════════════════════════════════════════
// SUPPORTING CLASSES
// ═════════════════════════════════════════════════════════════




class _HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _HoverCard({required this.child, required this.onTap});

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
          decoration: BoxDecoration(
            color: EDS.surface,
            borderRadius: EDS.radiusLg,
            border: Border.all(
              color: _hovered
                  ? EDS.blueLight.withOpacity(0.4)
                  : EDS.border,
              width: _hovered ? 1.5 : 1,
            ),
            boxShadow: _hovered ? EDS.shadowMd : EDS.shadowSm,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class NavigationItem {
  final IconData icon;
  final String label;
  final String route;

  NavigationItem({
    required this.icon,
    required this.label,
    required this.route,
  });
}

class PlaceholderScreen extends StatelessWidget {
  final String title;
  const PlaceholderScreen({Key? key, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: EDS.canvas,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: EDS.border,
                borderRadius: EDS.radiusXl,
              ),
              child: Icon(Icons.construction_rounded,
                  color: EDS.textTer, size: 40),
            ),
            const SizedBox(height: 22),
            Text(title, style: EDS.display(22, color: EDS.textPri)),
            // ↑ was display(20)
            const SizedBox(height: 10),
            Text('This section is under development',
                style: EDS.body(16)),   // ↑ was body(15)
          ],
        ),
      ),
    );
  }
}