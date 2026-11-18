// lib/features/client/presentation/screens/client_dashboard_analytics.dart
// ═══════════════════════════════════════════════════════════════════════════
// CLIENT DASHBOARD ANALYTICS
// Charts:
//   1. Bar  — Daily Trips last 7 days
//   2. Pie  — Employee / Customer Count (donut style)
//   3. Horizontal Bar — SOS Alert Status (Active vs Resolved)
// Data: Real API endpoints, same auth pattern as _fetchKpiCounts()
// Styling: 100% EDS design system
// FIX: Token read falls back to SharedPreferences for Flutter Web
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/core/utils/client_data_rules.dart';
import 'package:abra_fleet/core/services/customer_service.dart';

// ─────────────────────────────────────────────────────────────
// LOCAL EDS
// ─────────────────────────────────────────────────────────────
class _EDS {
  static const Color navy        = Color(0xFF0F172A);
  static const Color blue        = Color(0xFF1D4ED8);
  static const Color blueLight   = Color(0xFF3B82F6);
  static const Color cyan        = Color(0xFF0891B2);
  static const Color cyanLight   = Color(0xFFE0F2FE);
  static const Color surface     = Color(0xFFFFFFFF);
  static const Color canvas      = Color(0xFFF1F5F9);
  static const Color border      = Color(0xFFE2E8F0);
  static const Color textPri     = Color(0xFF0F172A);
  static const Color textSec     = Color(0xFF64748B);
  static const Color textTer     = Color(0xFF94A3B8);
  static const Color green       = Color(0xFF059669);
  static const Color greenLight  = Color(0xFFDCFCE7);
  static const Color amber       = Color(0xFFD97706);
  static const Color amberLight  = Color(0xFFFEF3C7);
  static const Color red         = Color(0xFFDC2626);
  static const Color redLight    = Color(0xFFFEE2E2);
  static const Color purple      = Color(0xFF7C3AED);
  static const Color purpleLight = Color(0xFFEDE9FE);

  static List<BoxShadow> shadowSm = [
    BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.06),
        blurRadius: 8, offset: const Offset(0, 2)),
  ];

  static BorderRadius radiusSm   = BorderRadius.circular(8);
  static BorderRadius radiusMd   = BorderRadius.circular(12);
  static BorderRadius radiusLg   = BorderRadius.circular(16);
  static BorderRadius radiusFull = BorderRadius.circular(100);

  static TextStyle display(double size,
      {FontWeight w = FontWeight.w700, Color? color}) =>
      TextStyle(
        fontSize: _sd(size), fontWeight: w,
        color: color ?? textPri, letterSpacing: -0.5, height: 1.25,
      );

  static TextStyle body(double size,
      {FontWeight w = FontWeight.w400, Color? color}) =>
      TextStyle(
        fontSize: _sb(size), fontWeight: w,
        color: color ?? textSec, height: 1.55,
      );

  static double _sd(double s) {
    if (s <= 10) return 14; if (s <= 11) return 15; if (s <= 12) return 16;
    if (s <= 13) return 17; if (s <= 14) return 18; if (s <= 16) return 20;
    if (s <= 18) return 22; if (s <= 20) return 24; if (s <= 22) return 26;
    if (s <= 24) return 28; if (s <= 28) return 32; return s + 4;
  }

  static double _sb(double s) {
    if (s <= 10) return 13; if (s <= 11) return 14; if (s <= 12) return 15;
    if (s <= 13) return 16; if (s <= 14) return 17; if (s <= 15) return 18;
    return s + 3;
  }
}

// ─────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────
class _TripStats {
  final int completed, ongoing, cancelled;
  final List<_DayCount> last7Days;
  _TripStats({required this.completed, required this.ongoing,
      required this.cancelled, required this.last7Days});
  int get total => completed + ongoing + cancelled;
}

class _DayCount {
  final String label;
  final int count;
  final int completed;
  final int scheduled;
  final int active;
  final int cancelled;
  _DayCount(this.label, this.count, {
    this.completed = 0,
    this.scheduled = 0,
    this.active    = 0,
    this.cancelled = 0,
  });
}

class _SOSStats {
  final int active, resolved, total;
  _SOSStats({required this.active, required this.resolved, required this.total});
}

class _AnalyticsData {
  final _TripStats trips;
  final _SOSStats sos;
  final int employeeCount;
  _AnalyticsData({required this.trips, required this.sos,
      required this.employeeCount});
}

// ─────────────────────────────────────────────────────────────
// MAIN WIDGET
// ─────────────────────────────────────────────────────────────
class ClientDashboardAnalytics extends StatefulWidget {
  const ClientDashboardAnalytics({Key? key}) : super(key: key);

  @override
  State<ClientDashboardAnalytics> createState() =>
      _ClientDashboardAnalyticsState();
}

class _ClientDashboardAnalyticsState extends State<ClientDashboardAnalytics>
    with SingleTickerProviderStateMixin {

  final _storage = const FlutterSecureStorage();

  _AnalyticsData? _data;
  bool _loading = true;
  String? _error;

  // Employee status counts (active / inactive / other). null until loaded.
  Map<String, int>? _empCounts;
  int _empReq = 0;
  // Which parts failed to load on the last refresh: trips, sos, employees, refresh
  final Set<String> _warnings = {};

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    debugPrint('📊 ClientDashboardAnalytics initState() called');
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _fetchAll();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // TOKEN + DOMAIN HELPER
  // ─────────────────────────────────────────────────────────────
  Future<Map<String, String>> _getAuthDetails() async {
    String token  = '';
    String domain = '';

    try {
      token = await _storage.read(key: 'auth_token') ?? '';
      final userDataStr = await _storage.read(key: 'user_data');
      if (userDataStr != null && userDataStr.isNotEmpty) {
        final ud = json.decode(userDataStr);
        final email = (ud['email'] as String? ?? '');
        if (email.contains('@')) domain = email.split('@').last.toLowerCase();
      }
    } catch (_) {}

    if (token.isEmpty || domain.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (token.isEmpty) token = prefs.getString('auth_token') ?? '';
        if (domain.isEmpty) {
          final raw = prefs.getString('user_data');
          if (raw != null && raw.isNotEmpty) {
            final ud = json.decode(raw);
            final email = (ud['email'] as String? ?? '');
            if (email.contains('@')) domain = email.split('@').last.toLowerCase();
            if (token.isEmpty) {
              token = ud['token'] ?? ud['accessToken'] ?? ud['access_token'] ?? '';
            }
          }
          if (domain.isEmpty) {
            final email = prefs.getString('email') ?? prefs.getString('user_email') ?? '';
            if (email.contains('@')) domain = email.split('@').last.toLowerCase();
          }
          if (token.isEmpty) {
            token = prefs.getString('jwt_token') ?? prefs.getString('token') ??
                    prefs.getString('access_token') ?? prefs.getString('jwt') ?? '';
          }
        }
      } catch (_) {}
    }

    debugPrint('📊 Analytics auth — token: ${token.isNotEmpty ? "✅ found (${token.length} chars)" : "❌ empty"}, domain: ${domain.isNotEmpty ? "✅ $domain" : "❌ empty"}');
    return {'token': token, 'domain': domain};
  }

  // ─────────────────────────────────────────────────────────────
  // DATA FETCHING
  // ─────────────────────────────────────────────────────────────
  Future<void> _fetchAll() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    final warn = <String>{};

    try {
      final auth   = await _getAuthDetails();
      final token  = auth['token']!;
      final domain = auth['domain']!;

      if (token.isEmpty) {
        throw Exception('Authentication token not found. Please log out and log in again.');
      }

      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final base = ApiConfig.baseUrl;

      // ══════════════════════════════════════════════════════════
      // CALL 1: Trip counts (ongoing, completed, cancelled)
      // /api/client/trips/dashboard — domain filtered server-side
      // ══════════════════════════════════════════════════════════
      final dashRes = await http.get(
        Uri.parse('$base/api/client/trips/dashboard'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      debugPrint('📊 Dashboard response: ${dashRes.statusCode}');

      int completed = 0, ongoing = 0, cancelled = 0;

      if (dashRes.statusCode == 200) {
        final body    = json.decode(dashRes.body);
        final summary = body['data'] as Map<String, dynamic>? ?? {};
        ongoing   = (summary['ongoing']   ?? 0) as int;
        completed = (summary['completed'] ?? 0) as int;
        cancelled = (summary['cancelled'] ?? 0) as int;
        debugPrint('📊 Counts — ongoing: $ongoing, completed: $completed, cancelled: $cancelled');
      } else if (dashRes.statusCode == 401) {
        throw Exception('Session expired (401). Please log out and log in again.');
      } else {
        throw Exception('Dashboard API error: ${dashRes.statusCode}');
      }

      // ══════════════════════════════════════════════════════════
      // CALL 2: Operational trips — daily bar chart
      // /api/client/trips/list (same endpoint as the Reports / trip
      // dashboard, domain-filtered server-side, roster-assigned-trips).
      // Trips are bucketed by their scheduled date in LOCAL time.
      // If the call fails the last good chart is kept and a hint shown.
      // ══════════════════════════════════════════════════════════
      List<_DayCount>? last7;
      try {
        final now = DateTime.now();
        final last7Keys = List.generate(
            7, (i) => _dayKey(DateTime(now.year, now.month, now.day - (6 - i)))).toSet();
        // Query one day wider on each side; exact bucketing is done below.
        final tripsUri = Uri.parse('$base/api/client/trips/list').replace(
          queryParameters: {
            'fromDate': _dayKey(DateTime(now.year, now.month, now.day - 7)),
            'toDate':   _dayKey(DateTime(now.year, now.month, now.day + 1)),
            'page':     '1',
            'limit':    '500',
          },
        );
        final myTripsRes = await http.get(tripsUri, headers: headers)
            .timeout(const Duration(seconds: 30));

        debugPrint('📊 Trips-list response: ${myTripsRes.statusCode}');

        if (myTripsRes.statusCode != 200) {
          throw Exception('HTTP ${myTripsRes.statusCode}');
        }
        final body = json.decode(myTripsRes.body);
        if (body['success'] != true) {
          throw Exception(body['message'] ?? 'trips list failed');
        }
        final trips = (body['data']?['trips'] as List?) ?? [];

        final Map<String, int> mapCompleted = {};
        final Map<String, int> mapScheduled = {};
        final Map<String, int> mapActive    = {};
        final Map<String, int> mapCancelled = {};

        for (final t in trips) {
          if (t is! Map) continue;
          final key = _localDayKey(t['scheduledDate'] ?? t['scheduledPickupTime']);
          if (key == null || !last7Keys.contains(key)) continue;

          final status = t['status']?.toString();
          if (isTripCompleted(status)) {
            mapCompleted[key] = (mapCompleted[key] ?? 0) + 1;
          } else if (isTripOngoing(status)) {
            mapActive[key] = (mapActive[key] ?? 0) + 1;
          } else if (isTripCancelled(status) ||
              (status ?? '').trim().toLowerCase() == 'canceled') {
            mapCancelled[key] = (mapCancelled[key] ?? 0) + 1;
          } else {
            // assigned, scheduled, pending... → Scheduled
            mapScheduled[key] = (mapScheduled[key] ?? 0) + 1;
          }
        }
        last7 = _buildLast7Days(mapCompleted, mapScheduled, mapActive, mapCancelled);
      } catch (e) {
        debugPrint('📊 Daily trips fetch failed (non-fatal): $e');
        warn.add('trips');
      }
      last7 ??= _data?.trips.last7Days ?? _buildLast7Days({}, {}, {}, {});

      // ══════════════════════════════════════════════════════════
      // CALL 3: Customers count
      // /api/admin/client-analytics/trip-stats — same source
      // as the original working code that gave 46
      // ══════════════════════════════════════════════════════════
      int employeeCount = _data?.employeeCount ?? 0; // keep last good value on failure
      try {
        final custRes = await http.get(
          Uri.parse('$base/api/admin/client-analytics/trip-stats?limit=200'),
          headers: headers,
        ).timeout(const Duration(seconds: 30));

        debugPrint('📊 Customer count response: ${custRes.statusCode}');
        if (custRes.statusCode != 200) warn.add('employees');

        if (custRes.statusCode == 200) {
          final body    = json.decode(custRes.body);
          final clients = body['data']?['clients'] as List? ?? [];
          for (final c in clients) {
            final cDomain = (c['domain'] ?? '').toString().toLowerCase();
            if (domain.isNotEmpty && cDomain != domain) continue;
            employeeCount = (c['customerCount'] ?? 0) as int;
            debugPrint('📊 Customer count for domain $domain: $employeeCount');
            break;
          }
        }
      } catch (e) {
        debugPrint('📊 Customer count fetch failed (non-fatal): $e');
        // Non-fatal — keep the last count and show a hint
        warn.add('employees');
      }

      // ══════════════════════════════════════════════════════════
      // CALL 4: SOS Stats — completely unchanged
      // ══════════════════════════════════════════════════════════
      final sosUrl = domain.isNotEmpty
          ? '$base/api/sos?organizationDomain=$domain&limit=500'
          : '$base/api/sos?limit=500';

      final sosRes = await http.get(
        Uri.parse(sosUrl),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      debugPrint('📊 SOS response: ${sosRes.statusCode}');

      // Keep the last good values if this call fails
      int sosActive   = _data?.sos.active   ?? 0;
      int sosResolved = _data?.sos.resolved ?? 0;
      int sosTotal    = _data?.sos.total    ?? 0;

      if (sosRes.statusCode == 200) {
        sosActive = 0;
        sosResolved = 0;
        final body   = json.decode(sosRes.body);
        final alerts = body['data'] as List? ?? [];
        sosTotal     = (body['pagination']?['total'] ?? alerts.length) as int;

        for (final a in alerts) {
          final status = (a is Map ? a['status'] : null)?.toString();
          if (isSosResolved(status)) {
            sosResolved++;
          } else {
            sosActive++;
          }
        }
        if (sosActive == 0 && sosResolved == 0 && sosTotal > 0) {
          sosActive = sosTotal;
        }
      } else {
        warn.add('sos');
      }

      if (!mounted) return;
      setState(() {
        _data = _AnalyticsData(
          trips: _TripStats(
            completed: completed,
            ongoing:   ongoing,
            cancelled: cancelled,
            last7Days: last7!,
          ),
          sos: _SOSStats(
            active:   sosActive,
            resolved: sosResolved,
            total:    sosTotal,
          ),
          employeeCount: employeeCount,
        );
        _loading = false;
        _warnings
          ..clear()
          ..addAll(warn);
      });
      _animCtrl.forward(from: 0);
      // Employee status breakdown loads separately so a slow API never
      // blocks the rest of the dashboard.
      _loadEmployeeStatus(domain);

    } catch (e) {
      debugPrint('📊 Analytics fetch error: $e');
      if (!mounted) return;
      final msg = e.toString();
      final authProblem = msg.contains('401') || msg.contains('Authentication');
      if (_data != null && !authProblem) {
        // Keep the last good numbers on screen and show a retry hint.
        setState(() {
          _loading = false;
          _warnings
            ..clear()
            ..add('refresh');
        });
        _animCtrl.forward(from: 0);
      } else {
        setState(() { _error = msg; _loading = false; });
      }
    }
  }

  /// Real employee status counts, same data source as Employee Management
  /// (CustomerService.getCustomersByDomain). Never blocks the dashboard.
  Future<void> _loadEmployeeStatus(String domain) async {
    if (domain.isEmpty) return;
    final req = ++_empReq;
    try {
      final customers = await CustomerService().getCustomersByDomain(domain);
      if (!mounted || req != _empReq) return;
      int active = 0, inactive = 0, other = 0;
      for (final c in customers) {
        switch (employeeStatusBucket(c.status)) {
          case 'active':
            active++;
            break;
          case 'inactive':
            inactive++;
            break;
          default:
            other++;
        }
      }
      setState(() {
        _empCounts = {'active': active, 'inactive': inactive, 'other': other};
        _warnings.remove('employees');
      });
    } catch (e) {
      debugPrint('📊 Employee status fetch failed (non-fatal): $e');
      if (!mounted || req != _empReq) return;
      setState(() => _warnings.add('employees'));
    }
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// yyyy-MM-dd as-is (already a calendar date); anything with a time part
  /// is converted to LOCAL time first.
  String? _localDayKey(dynamic raw) {
    final str = (raw ?? '').toString().trim();
    if (str.isEmpty) return null;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(str)) return str;
    final dt = DateTime.tryParse(str);
    return dt == null ? null : _dayKey(dt.toLocal());
  }

  List<_DayCount> _buildLast7Days(
    Map<String, int> mapCompleted,
    Map<String, int> mapScheduled,
    Map<String, int> mapActive,
    Map<String, int> mapCancelled,
  ) {
    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final today = DateTime.now();
    return List.generate(7, (i) {
      final d   = DateTime(today.year, today.month, today.day - (6 - i));
      final key = _dayKey(d);
      final label = i == 6 ? 'Today' : dayLabels[d.weekday - 1];
      final c = mapCompleted[key] ?? 0;
      final s = mapScheduled[key] ?? 0;
      final a = mapActive[key]    ?? 0;
      final x = mapCancelled[key] ?? 0;
      return _DayCount(label, c + s + a + x,
        completed: c, scheduled: s, active: a, cancelled: x);
    });
  }

  String _parseDateLabel(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
    } catch (_) { return ''; }
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    debugPrint('📊 ClientDashboardAnalytics build() — loading: $_loading, error: ${_error != null}, data: ${_data != null}');
    final isMobile = MediaQuery.of(context).size.width < 768;
    if (_loading) return _buildLoadingSkeleton(isMobile);
    if (_error != null) return _buildErrorState();

    return FadeTransition(
      opacity: _fadeAnim,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          if (isMobile) _buildPhoneSectionHeader() else Row(
            children: [
              Text('Analytics Overview',
                  style: _EDS.display(isMobile ? 20 : 22)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                    color: _EDS.greenLight,
                    borderRadius: _EDS.radiusFull),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 7, height: 7,
                        decoration: const BoxDecoration(
                            color: _EDS.green, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('Live Data',
                        style: _EDS.body(12,
                            w: FontWeight.w600, color: _EDS.green)),
                  ],
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: _fetchAll,
                borderRadius: _EDS.radiusSm,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _EDS.surface,
                    borderRadius: _EDS.radiusSm,
                    border: Border.all(color: _EDS.border),
                    boxShadow: _EDS.shadowSm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded,
                          color: _EDS.textSec, size: 16),
                      const SizedBox(width: 6),
                      Text('Refresh',
                          style: _EDS.body(13,
                              w: FontWeight.w600, color: _EDS.textSec)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_warnings.isNotEmpty) ...[
            SizedBox(height: isMobile ? 10 : 12),
            _buildWarningBar(),
          ],
          SizedBox(height: isMobile ? 14 : 18),
          (isMobile || MediaQuery.of(context).size.width < 1100)
              ? _buildMobileLayout()
              : _buildDesktopLayout(),
        ],
      ),
    );
  }

  /// Small hint shown when part of the data could not be loaded; the last
  /// good values stay on screen. Tap to retry.
  Widget _buildWarningBar() {
    final parts = <String>[
      if (_warnings.contains('trips')) 'daily trips',
      if (_warnings.contains('sos')) 'SOS alerts',
      if (_warnings.contains('employees')) 'employee counts',
    ];
    final text = _warnings.contains('refresh') || parts.isEmpty
        ? 'Could not refresh. Showing the last loaded numbers.'
        : 'Could not load ${parts.join(', ')}. Showing the last loaded numbers.';
    return InkWell(
      onTap: _fetchAll,
      borderRadius: _EDS.radiusSm,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _EDS.amberLight,
          borderRadius: _EDS.radiusSm,
        ),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, color: _EDS.amber, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: _EDS.body(12, w: FontWeight.w500, color: _EDS.amber)),
          ),
          const SizedBox(width: 8),
          Text('Retry',
              style: _EDS.body(12, w: FontWeight.w700, color: _EDS.amber)),
        ]),
      ),
    );
  }

  /// Phone header: title + Live chip wrap, Refresh is a 44px icon button.
  Widget _buildPhoneSectionHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Analytics Overview', style: _EDS.display(20)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                    color: _EDS.greenLight, borderRadius: _EDS.radiusFull),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                            color: _EDS.green, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('Live Data',
                        style: _EDS.body(12,
                            w: FontWeight.w600, color: _EDS.green)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Refresh',
          child: InkWell(
            onTap: _fetchAll,
            borderRadius: _EDS.radiusSm,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _EDS.surface,
                borderRadius: _EDS.radiusSm,
                border: Border.all(color: _EDS.border),
                boxShadow: _EDS.shadowSm,
              ),
              child: Icon(Icons.refresh_rounded, color: _EDS.textSec, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // LAYOUTS
  // ─────────────────────────────────────────────────────────────
  Widget _buildDesktopLayout() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Chart 1: Daily Trips Bar — wider
          Expanded(flex: 5, child: _buildDailyBarCard()),
          const SizedBox(width: 16),
          // Chart 2: Customers Pie — medium
          Expanded(flex: 4, child: _buildEmployeeDonutCard()),
          const SizedBox(width: 16),
          // Chart 3: SOS Horizontal Bar — wider
          Expanded(flex: 5, child: _buildSOSHorizontalBarCard()),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(children: [
      _buildDailyBarCard(),
      const SizedBox(height: 14),
      _buildEmployeeDonutCard(),
      const SizedBox(height: 14),
      _buildSOSHorizontalBarCard(),
    ]);
  }

  // ═════════════════════════════════════════════════════════════
  // CHART 1 — DAILY TRIPS BAR CHART
  // ═════════════════════════════════════════════════════════════
  Widget _buildDailyBarCard() {
    final days = _data!.trips.last7Days;
    final maxVal = days.map((d) => d.count).fold(0, (a, b) => a > b ? a : b);
    final yMax = (maxVal == 0 ? 10 : (maxVal * 1.3)).ceilToDouble();

    return _ChartCard(
      title: 'Daily Trips',
      subtitle: 'Last 7 days — ${_data!.trips.last7Days.fold(0, (sum, d) => sum + d.count)} trips${_warnings.contains('trips') ? ' (could not load)' : ''}',
      icon: Icons.bar_chart_rounded,
      iconColor: _EDS.blue,
      iconBg: const Color(0xFFEFF6FF),
      child: SizedBox(
        height: 220,
        child: Column(
          children: [
            Expanded(
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: yMax,
                  minY: 0,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBgColor: _EDS.navy,
                      tooltipRoundedRadius: 8,
                      getTooltipItem: (group, gI, rod, rI) => BarTooltipItem(
                        '${days[gI].label}\n',
                        const TextStyle(color: Colors.white70, fontSize: 12,
                            fontWeight: FontWeight.w500),
                        children: [TextSpan(
                          text: '${rod.toY.toInt()} trips',
                          style: const TextStyle(color: Colors.white, fontSize: 14,
                              fontWeight: FontWeight.w700),
                        )],
                      ),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: maxVal == 0 ? 5 : (yMax / 4).ceilToDouble(),
                      getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                          style: _EDS.body(11, color: _EDS.textTer)),
                    )),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= days.length) return const SizedBox();
                        final isToday = i == days.length - 1;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(days[i].label,
                              style: _EDS.body(11,
                                  w: isToday ? FontWeight.w700 : FontWeight.w400,
                                  color: isToday ? _EDS.blue : _EDS.textTer)),
                        );
                      },
                    )),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxVal == 0 ? 5 : (yMax / 4).ceilToDouble(),
                    getDrawingHorizontalLine: (_) => FlLine(
                        color: _EDS.border, strokeWidth: 1, dashArray: [4, 4]),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: days.asMap().entries.map((e) {
                    final day = e.value;
                    final total = day.count.toDouble();
                    if (total == 0) {
                      return BarChartGroupData(x: e.key, barRods: [
                        BarChartRodData(toY: 0, width: 22),
                      ]);
                    }
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: total,
                          width: 22,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                          rodStackItems: [
                            // Bottom → Completed (green)
                            BarChartRodStackItem(0, day.completed.toDouble(), const Color(0xFF43A047)),
                            // Scheduled/Accepted (blue)
                            BarChartRodStackItem(
                              day.completed.toDouble(),
                              (day.completed + day.scheduled).toDouble(),
                              const Color(0xFF2979FF),
                            ),
                            // Active/Ongoing (teal)
                            BarChartRodStackItem(
                              (day.completed + day.scheduled).toDouble(),
                              (day.completed + day.scheduled + day.active).toDouble(),
                              const Color(0xFF00BFA5),
                            ),
                            // Top → Cancelled (red)
                            BarChartRodStackItem(
                              (day.completed + day.scheduled + day.active).toDouble(),
                              total,
                              const Color(0xFFE53935),
                            ),
                          ],
                        ),
                      ],
                    );
                  }).toList(),
                ),
                swapAnimationDuration: const Duration(milliseconds: 400),
                swapAnimationCurve: Curves.easeInOut,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                _barLegend(const Color(0xFF43A047), 'Completed'),
                _barLegend(const Color(0xFF2979FF), 'Scheduled'),
                _barLegend(const Color(0xFF00BFA5), 'Active'),
                _barLegend(const Color(0xFFE53935), 'Cancelled'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════
  // CHART 2 — EMPLOYEE / CUSTOMER DONUT PIE CHART
  // ═════════════════════════════════════════════════════════════
  Widget _buildEmployeeDonutCard() {
    final emp      = _empCounts;
    final active   = emp?['active']   ?? 0;
    final inactive = emp?['inactive'] ?? 0;
    final other    = emp?['other']    ?? 0;
    // Until the status breakdown loads, show the total only.
    final count    = emp != null ? active + inactive + other : _data!.employeeCount;

    return _ChartCard(
      title: 'Employees',
      subtitle: 'Registered in portal',
      icon: Icons.people_alt_rounded,
      iconColor: _EDS.purple,
      iconBg: _EDS.purpleLight,
      child: count == 0
          ? _emptyState('No employees registered yet')
          : Column(children: [
              SizedBox(
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 3,
                        centerSpaceRadius: 58,
                        sections: emp == null
                            ? [
                                PieChartSectionData(
                                  value: count.toDouble(),
                                  color: _EDS.purpleLight,
                                  radius: 46,
                                  title: '',
                                ),
                              ]
                            : [
                                PieChartSectionData(
                                  value: active.toDouble(),
                                  color: _EDS.purple,
                                  radius: 48,
                                  title: '',
                                ),
                                PieChartSectionData(
                                  value: inactive > 0 ? inactive.toDouble() : 0.001,
                                  color: _EDS.purpleLight,
                                  radius: 44,
                                  title: '',
                                ),
                                if (other > 0)
                                  PieChartSectionData(
                                    value: other.toDouble(),
                                    color: _EDS.textTer,
                                    radius: 44,
                                    title: '',
                                  ),
                              ],
                      ),
                      swapAnimationDuration: const Duration(milliseconds: 400),
                      swapAnimationCurve: Curves.easeInOut,
                    ),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('$count',
                          style: _EDS.display(28, color: _EDS.textPri)),
                      Text('Total',
                          style: _EDS.body(12, color: _EDS.textSec)),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (emp != null)
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    _legendDot(_EDS.purple, 'Active', active, count),
                    _legendDot(_EDS.purpleLight, 'Inactive', inactive, count),
                    if (other > 0) _legendDot(_EDS.textTer, 'Other', other, count),
                  ],
                )
              else
                Text(
                  _warnings.contains('employees')
                      ? 'Status breakdown unavailable'
                      : 'Loading status breakdown…',
                  style: _EDS.body(12, color: _EDS.textTer),
                  textAlign: TextAlign.center,
                ),
            ]),
    );
  }

  // ═════════════════════════════════════════════════════════════
  // CHART 3 — SOS HORIZONTAL BAR CHART
  // ═════════════════════════════════════════════════════════════
  Widget _buildSOSHorizontalBarCard() {
    final sos     = _data!.sos;
    final active   = sos.active;
    final resolved = sos.resolved;
    final total    = sos.total;

    // Build horizontal bar data: Active and Resolved as two bars
    final barItems = [
      _HBarItem('Active',   active,   _EDS.red,   const Color(0xFFF87171)),
      _HBarItem('Resolved', resolved, _EDS.green, const Color(0xFF34D399)),
    ];
    final maxVal  = [active, resolved].fold(0, (a, b) => a > b ? a : b);
    final xMax    = (maxVal == 0 ? 10 : (maxVal * 1.35)).ceilToDouble();

    return _ChartCard(
      title: 'SOS Alerts',
      subtitle: total == 0 ? 'All clear' : '$total total alerts',
      icon: Icons.warning_amber_rounded,
      iconColor: total > 0 ? _EDS.red : _EDS.green,
      iconBg: total > 0 ? _EDS.redLight : _EDS.greenLight,
      child: total == 0
          ? _emptyState('No SOS alerts — all clear! ✅', color: _EDS.green)
          : SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.center,
                  maxY: xMax,
                  minY: 0,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBgColor: _EDS.navy,
                      tooltipRoundedRadius: 8,
                      getTooltipItem: (group, gI, rod, rI) {
                        final item = barItems[gI];
                        return BarTooltipItem(
                          '${item.label}\n',
                          const TextStyle(color: Colors.white70, fontSize: 12,
                              fontWeight: FontWeight.w500),
                          children: [TextSpan(
                            text: '${rod.toY.toInt()} alerts',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14,
                                fontWeight: FontWeight.w700),
                          )],
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    // Bottom — Y axis values (since we rotate to horizontal style)
                    bottomTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= barItems.length) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            barItems[i].label,
                            style: _EDS.body(12,
                                w: FontWeight.w600,
                                color: barItems[i].color),
                          ),
                        );
                      },
                    )),
                    leftTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: maxVal == 0 ? 5 : (xMax / 4).ceilToDouble(),
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: _EDS.body(11, color: _EDS.textTer),
                      ),
                    )),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxVal == 0 ? 5 : (xMax / 4).ceilToDouble(),
                    getDrawingHorizontalLine: (_) => FlLine(
                        color: _EDS.border, strokeWidth: 1, dashArray: [4, 4]),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: barItems.asMap().entries.map((e) {
                    final item = e.value;
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: item.value.toDouble(),
                          width: 52,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8)),
                          gradient: LinearGradient(
                            colors: [item.lightColor, item.color],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
                swapAnimationDuration: const Duration(milliseconds: 400),
                swapAnimationCurve: Curves.easeInOut,
              ),
            ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SHARED HELPERS
  // ─────────────────────────────────────────────────────────────
  Widget _legendDot(Color color, String label, int value, int total) {
    final pct = total > 0 ? (value / total * 100).toStringAsFixed(0) : '0';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text('$label ($value — $pct%)',
          style: _EDS.body(12, w: FontWeight.w500, color: _EDS.textSec)),
    ]);
  }

  Widget _emptyState(String msg, {Color? color}) {
    return SizedBox(
      height: 160,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inbox_rounded, color: color ?? _EDS.textTer, size: 36),
          const SizedBox(height: 10),
          Text(msg,
              style: _EDS.body(13, color: color ?? _EDS.textTer),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _buildErrorState() {
    debugPrint('📊 Showing error state: $_error');
    final isAuthError = _error?.contains('401') == true ||
        _error?.contains('token') == true ||
        _error?.contains('Authentication') == true ||
        _error?.contains('Session') == true;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _EDS.redLight,
        borderRadius: _EDS.radiusMd,
        border: Border.all(color: _EDS.red.withOpacity(0.5), width: 2),
      ),
      child: Row(children: [
        Icon(isAuthError ? Icons.lock_outline_rounded : Icons.error_outline_rounded,
            color: _EDS.red, size: 32),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              isAuthError ? 'Session Issue' : 'Failed to load analytics',
              style: _EDS.body(16, w: FontWeight.w700, color: _EDS.red),
            ),
            const SizedBox(height: 6),
            Text(
              isAuthError
                  ? 'Could not authenticate. Try logging out and back in.'
                  : (_error ?? 'Unknown error'),
              style: _EDS.body(13, color: _EDS.textSec),
            ),
          ]),
        ),
        ElevatedButton(
          onPressed: _fetchAll,
          style: ElevatedButton.styleFrom(
            backgroundColor: _EDS.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: Text('Retry',
              style: _EDS.body(14, w: FontWeight.w700, color: Colors.white)),
        ),
      ]),
    );
  }

  Widget _buildLoadingSkeleton(bool isMobile) {
    debugPrint('📊 Showing loading skeleton (isMobile: $isMobile)');
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _EDS.cyanLight.withOpacity(0.3),
        borderRadius: _EDS.radiusMd,
        border: Border.all(color: _EDS.cyan.withOpacity(0.5), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 180, height: 26,
                decoration: BoxDecoration(color: _EDS.border,
                    borderRadius: _EDS.radiusSm)),
            const Spacer(),
            Container(width: 80, height: 32,
                decoration: BoxDecoration(color: _EDS.border,
                    borderRadius: _EDS.radiusSm)),
          ]),
          const SizedBox(height: 18),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 48, height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    valueColor: AlwaysStoppedAnimation<Color>(_EDS.blue),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Loading Analytics...',
                    style: _EDS.body(14, w: FontWeight.w600, color: _EDS.blue)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          isMobile
              ? Column(children: List.generate(3, (_) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _skeletonCard(260))))
              : Row(children: [
                  Expanded(flex: 5, child: _skeletonCard(300)),
                  const SizedBox(width: 16),
                  Expanded(flex: 4, child: _skeletonCard(300)),
                  const SizedBox(width: 16),
                  Expanded(flex: 5, child: _skeletonCard(300)),
                ]),
        ],
      ),
    );
  }

  Widget _skeletonCard(double height) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: _EDS.surface,
        borderRadius: _EDS.radiusLg,
        border: Border.all(color: _EDS.border),
        boxShadow: _EDS.shadowSm,
      ),
      child: const Center(
        child: SizedBox(
          width: 28, height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(_EDS.blue),
          ),
        ),
      ),
    );
  }

  Widget _barLegend(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: _EDS.body(11, color: _EDS.textSec)),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════
// CHART CARD SHELL
// ═════════════════════════════════════════════════════════════
class _ChartCard extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Color iconColor, iconBg;
  final Widget child;

  const _ChartCard({
    required this.title, required this.subtitle,
    required this.icon, required this.iconColor,
    required this.iconBg, required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _EDS.surface,
        borderRadius: _EDS.radiusLg,
        border: Border.all(color: _EDS.border),
        boxShadow: _EDS.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                  color: iconBg, borderRadius: _EDS.radiusSm),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: _EDS.display(15, color: _EDS.textPri)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: _EDS.body(12, color: _EDS.textSec)),
              ],
            )),
          ]),
          const SizedBox(height: 20),
          Divider(color: _EDS.border, height: 1),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════
// HELPER MODELS
// ═════════════════════════════════════════════════════════════
class _HBarItem {
  final String label;
  final int value;
  final Color color, lightColor;
  _HBarItem(this.label, this.value, this.color, this.lightColor);
}