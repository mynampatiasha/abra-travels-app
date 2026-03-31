// ============================================================
// CHUNK 1 OF 3 - IMPORTS, STATE VARIABLES, DATA FETCHING
// FIXED: _fetchActiveTrips, _fetchCompletedTrips, _fetchMonthlyDistance, _fetchFeedbackStats, _fetchSOSAlerts
// ============================================================

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:abra_fleet/core/services/roster_service.dart';
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:abra_fleet/features/admin/widgets/country_state_city_filter.dart';
import 'package:abra_fleet/core/utils/export_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class ClientReportsAnalyticsEnhanced extends StatefulWidget {
  const ClientReportsAnalyticsEnhanced({Key? key}) : super(key: key);

  @override
  State<ClientReportsAnalyticsEnhanced> createState() =>
      _ClientReportsAnalyticsEnhancedState();
}

class _ClientReportsAnalyticsEnhancedState
    extends State<ClientReportsAnalyticsEnhanced> {
  // ─── LOADING STATE ──────────────────────────────────────────────────────────
  bool _isLoading = true;
  bool _isRefreshing = false;

  // ─── CLIENT IDENTITY ────────────────────────────────────────────────────────
  String? _clientOrganizationDomain;

  // ─── CATEGORY FILTER ────────────────────────────────────────────────────────
  String _selectedCategory = 'All';
  final List<String> _categories = [
    'All',
    'Employees',
    'Rosters',
    'SOS',
    'Trips',
    'Feedback',
  ];

  // ─── REPORT TYPE CHECKBOXES ─────────────────────────────────────────────────
  final Map<String, bool> _selectedReportTypes = {
    'employees': true,
    'rosters': true,
    'sos': true,
    'trips': true,
    'feedback': true,
  };

  // ─── LOCATION FILTERS ───────────────────────────────────────────────────────
  String? _selectedCountry;
  String? _selectedState;
  String? _selectedCity;
  String? _selectedArea;

  // ─── DATE FILTERS ───────────────────────────────────────────────────────────
  DateTime? _startDate;
  DateTime? _endDate;

  // ─── SERVICES ───────────────────────────────────────────────────────────────
  late RosterService _rosterService;

  // ─── DATA: EMPLOYEES ────────────────────────────────────────────────────────
  List<dynamic> _employees = [];
  int _activeEmployees = 0;
  int _inactiveEmployees = 0;

  // ─── DATA: ROSTERS ──────────────────────────────────────────────────────────
  List<dynamic> _pendingRosters = [];
  RosterStats _rosterStats = RosterStats.empty();

  // ─── DATA: SOS ──────────────────────────────────────────────────────────────
  List<dynamic> _activeSOS = [];
  List<dynamic> _resolvedSOS = [];
  int _totalRaisedSOS = 0;

  // ─── DATA: TRIPS ────────────────────────────────────────────────────────────
  List<dynamic> _activeTrips = [];
  List<dynamic> _scheduledTrips = [];
  List<dynamic> _completedTrips = [];
  List<dynamic> _cancelledTrips = [];
  int _totalTrips = 0;
  Map<String, dynamic> _dashboardStats = {};

  // ─── DATA: FEEDBACK ─────────────────────────────────────────────────────────
  int _totalFeedbacks = 0;
  int _pendingFeedbacks = 0;
  int _resolvedFeedbacks = 0;
  List<Map<String, dynamic>> _topDriversByFeedback = [];

  // ─── DATA: MONTHLY DISTANCE (kept for state compatibility) ──────────────────
  String _selectedMonth = '';
  Map<String, dynamic> _monthlyDistance = {};

  // =========================================================
  // INIT
  // =========================================================

  @override
  void initState() {
    super.initState();
    _rosterService = RosterService(apiService: ApiService());
    _initializeClientData();
  }

  // =========================================================
  // INITIALIZATION
  // =========================================================

  Future<void> _initializeClientData() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      final userEmail = prefs.getString('user_email');

      if (token == null || token.isEmpty) {
        throw Exception('Not authenticated - JWT token missing');
      }

      if (userEmail != null && userEmail.isNotEmpty) {
        final emailParts = userEmail.split('@');
        if (emailParts.length == 2) {
          _clientOrganizationDomain = '@${emailParts[1]}';
          debugPrint('🏢 Client organization domain: $_clientOrganizationDomain');
          await _loadAllReportsData();
        } else {
          throw Exception('Invalid email format: $userEmail');
        }
      } else {
        throw Exception('No email found for current user');
      }
    } catch (e) {
      debugPrint('❌ Error initializing client data: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: ${e.toString()}'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _initializeClientData(),
            ),
          ),
        );
      }
    }
  }

  // =========================================================
  // LOAD ALL DATA
  // =========================================================

  Future<void> _loadAllReportsData() async {
    if (_clientOrganizationDomain == null) return;

    setState(() {
      _isLoading = true;
      _isRefreshing = true;
    });

    try {
      await Future.wait([
        _fetchEmployees(),
        _fetchPendingRosters(),
        _fetchRosterStats(),
        _fetchSOSAlerts(),
        _fetchTrips(),       // ✅ SINGLE call replaces _fetchActiveTrips + _fetchCompletedTrips
        _fetchFeedbackStats(),
        // ✅ _fetchMonthlyDistance REMOVED - endpoint doesn't exist
      ]);

      await _fetchDashboardStats();

      debugPrint('✅ All reports data loaded successfully');
    } catch (e) {
      debugPrint('❌ Error loading reports data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: ${e.toString()}'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _loadAllReportsData(),
            ),
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  // =========================================================
  // AUTH HELPER
  // =========================================================

  Future<String> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token != null && token.isNotEmpty) return token;
    throw Exception('User not authenticated - JWT token missing');
  }

  // =========================================================
  // 1. FETCH EMPLOYEES — ✅ FIXED: Use /api/client/customers endpoint
  // =========================================================

  Future<void> _fetchEmployees() async {
    try {
      final token = await _getAuthToken();
      
      // ✅ FIX: Use client customers endpoint with domain filter
      final queryParams = <String, String>{
        'domain': _clientOrganizationDomain ?? '',
        'limit': '10000',
      };
      
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/client/customers')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final customers = List<Map<String, dynamic>>.from(data['data'] ?? []);
          int activeCount = 0;
          int inactiveCount = 0;

          for (final customer in customers) {
            final status = customer['status']?.toLowerCase() ?? 'unknown';
            if (status == 'active') {
              activeCount++;
            } else {
              inactiveCount++;
            }
          }

          setState(() {
            _employees = customers;
            _activeEmployees = activeCount;
            _inactiveEmployees = inactiveCount;
          });
          
          debugPrint('✅ Employees loaded: ${customers.length} total, $activeCount active');
        }
      }
    } catch (e) {
      debugPrint('❌ Error fetching employees: $e');
    }
  }

  // =========================================================
  // 2. FETCH ROSTERS — UNCHANGED (was already working)
  // =========================================================

  Future<void> _fetchPendingRosters() async {
    try {
      final rosters =
          await _rosterService.getPendingRosters(forceRefresh: true);
      final filteredRosters = rosters.where((roster) {
        final email = roster['customerEmail'];
        return email != null &&
            _clientOrganizationDomain != null &&
            email.endsWith(_clientOrganizationDomain!);
      }).toList();
      setState(() => _pendingRosters = filteredRosters);
    } catch (e) {
      debugPrint('❌ Error fetching pending rosters: $e');
    }
  }

  Future<void> _fetchRosterStats() async {
    try {
      final stats = await _rosterService.getRosterStats();
      setState(() => _rosterStats = stats);
    } catch (e) {
      debugPrint('❌ Error fetching roster stats: $e');
    }
  }

  // =========================================================
  // 3. FETCH SOS — ✅ FIXED: status=Active/Resolved (capitalized)
  // =========================================================

  Future<void> _fetchSOSAlerts() async {
    try {
      final token = await _getAuthToken();

      // ✅ FIX: Use EXACT same endpoints as client_sos_alerts.dart
      // Active alerts use status=ACTIVE (uppercase)
      final activeResponse = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/sos?status=ACTIVE&limit=100'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      
      // Resolved alerts use status=Resolved (capitalized)
      final resolvedResponse = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/sos?status=Resolved&limit=10000'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (activeResponse.statusCode == 200 &&
          resolvedResponse.statusCode == 200) {
        final activeData = json.decode(activeResponse.body);
        final resolvedData = json.decode(resolvedResponse.body);

        final allActiveSOS =
            List<Map<String, dynamic>>.from(activeData['data'] ?? []);
        final filteredActive = allActiveSOS.where((alert) {
          final email = alert['customerEmail'];
          return email != null &&
              _clientOrganizationDomain != null &&
              email.endsWith(_clientOrganizationDomain!);
        }).toList();

        final allResolvedSOS =
            List<Map<String, dynamic>>.from(resolvedData['data'] ?? []);
        final filteredResolved = allResolvedSOS.where((alert) {
          final email = alert['customerEmail'];
          return email != null &&
              _clientOrganizationDomain != null &&
              email.endsWith(_clientOrganizationDomain!);
        }).toList();

        setState(() {
          _activeSOS = filteredActive;
          _resolvedSOS = filteredResolved;
          _totalRaisedSOS = filteredActive.length + filteredResolved.length;
        });
        
        debugPrint('✅ SOS loaded: ${filteredActive.length} active, ${filteredResolved.length} resolved');
      }
    } catch (e) {
      debugPrint('❌ Error fetching SOS alerts: $e');
    }
  }

  // =========================================================
  // 4. FETCH TRIPS — ✅ EXACT COPY from client_trip_dashboard_part1.dart
  //    Uses /api/client/trips/dashboard for summary stats
  // =========================================================

  Future<void> _fetchTrips() async {
    try {
      final token = await _getAuthToken();

      // ✅ EXACT API CALL from client_trip_dashboard_part1.dart loadDashboardSummary()
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/client/trips/dashboard');

      final response = await http.get(uri,
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          // ✅ EXACT PARSING from client_trip_dashboard_part1.dart
          final summary = data['data'] as Map<String, dynamic>;
          
          final int total = (summary['total'] ?? 0) as int;
          final int ongoing = (summary['ongoing'] ?? 0) as int;
          final int scheduled = (summary['scheduled'] ?? 0) as int;
          final int completed = (summary['completed'] ?? 0) as int;
          final int cancelled = (summary['cancelled'] ?? 0) as int;
          final int totalDrivers = (summary['totalDrivers'] ?? 0) as int;
          final int totalVehicles = (summary['totalVehicles'] ?? 0) as int;
          final int totalCustomers = (summary['totalCustomers'] ?? 0) as int;
          final int delayed = (summary['delayed'] ?? 0) as int;

          setState(() {
            _totalTrips = total;
            // Store counts in lists for compatibility with existing code
            _activeTrips = List.generate(ongoing, (i) => {});
            _scheduledTrips = List.generate(scheduled, (i) => {});
            _completedTrips = List.generate(completed, (i) => {});
            _cancelledTrips = List.generate(cancelled, (i) => {});
            
            // Store dashboard stats
            _dashboardStats = {
              'total': total,
              'ongoing': ongoing,
              'scheduled': scheduled,
              'completed': completed,
              'cancelled': cancelled,
              'totalDrivers': totalDrivers,
              'totalVehicles': totalVehicles,
              'totalCustomers': totalCustomers,
              'delayed': delayed,
              'totalEmployees': _employees.length,
              'activeEmployees': _activeEmployees,
              'inactiveEmployees': _inactiveEmployees,
            };
          });

          debugPrint('✅ Trips loaded from dashboard: Total=$total, Ongoing=$ongoing, Scheduled=$scheduled, Completed=$completed, Cancelled=$cancelled');
        } else {
          throw Exception(data['message']);
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error fetching trips: $e');
      setState(() {
        _totalTrips = 0;
        _activeTrips = [];
        _scheduledTrips = [];
        _completedTrips = [];
        _cancelledTrips = [];
      });
    }
  }

  // =========================================================
  // 5. FETCH FEEDBACK — FIXED: uses /api/admin/feedback/recent
  //    (replaces broken /api/feedback/stats)
  //    Also computes top drivers by feedback count
  // =========================================================

  Future<void> _fetchFeedbackStats() async {
    try {
      final token = await _getAuthToken();

      // ✅ FIX: Use the working endpoint from driver_feedback_page.dart
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/feedback/recent'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('📡 Feedback response keys: ${data.keys.toList()}');

        // The working endpoint returns feedbacks array
        final allFeedbacks = List<Map<String, dynamic>>.from(
            data['feedbacks'] ?? data['data'] ?? []);

        // Filter by org domain
        final filteredFeedbacks = allFeedbacks.where((feedback) {
          final email = feedback['customerEmail'] ?? feedback['passengerEmail'];
          return email != null &&
              _clientOrganizationDomain != null &&
              email.endsWith(_clientOrganizationDomain!);
        }).toList();

        final pending =
            filteredFeedbacks.where((f) => f['status'] == 'pending').length;
        final resolved =
            filteredFeedbacks.where((f) => f['status'] == 'resolved').length;

        // ✅ TOP DRIVERS: count feedbacks per driver, sort descending
        final Map<String, Map<String, dynamic>> driverFeedbackMap = {};
        for (final feedback in filteredFeedbacks) {
          final driverName = feedback['driverName'] ?? feedback['driver_name'];
          if (driverName != null && driverName.toString().isNotEmpty) {
            if (!driverFeedbackMap.containsKey(driverName)) {
              driverFeedbackMap[driverName] = {
                'driverName': driverName,
                'vehicleNumber': feedback['vehicleNumber'] ?? feedback['vehicle_number'] ?? 'N/A',
                'count': 0,
              };
            }
            driverFeedbackMap[driverName]!['count'] =
                (driverFeedbackMap[driverName]!['count'] as int) + 1;
          }
        }

        final topDrivers = driverFeedbackMap.values.toList()
          ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

        setState(() {
          _totalFeedbacks = filteredFeedbacks.length;
          _pendingFeedbacks = pending;
          _resolvedFeedbacks = resolved;
          _topDriversByFeedback = topDrivers;
        });

        debugPrint('✅ Feedback loaded: ${filteredFeedbacks.length} total, ${topDrivers.length} drivers');
      }
    } catch (e) {
      debugPrint('❌ Error fetching feedback stats: $e');
      setState(() {
        _totalFeedbacks = 0;
        _pendingFeedbacks = 0;
        _resolvedFeedbacks = 0;
        _topDriversByFeedback = [];
      });
    }
  }

  // =========================================================
  // 6. DASHBOARD STATS — updated to use trip dashboard data
  // =========================================================

  Future<void> _fetchDashboardStats() async {
    try {
      // If trips already set totalDrivers/Vehicles via dashboard, keep them
      // Otherwise fall back to roster-based calculation
      if ((_dashboardStats['totalDrivers'] ?? 0) == 0) {
        final orgDrivers = <String>{};
        final orgVehicles = <String>{};
        for (final roster in _pendingRosters) {
          if (roster['driverName'] != null) orgDrivers.add(roster['driverName']);
          if (roster['vehicleNumber'] != null)
            orgVehicles.add(roster['vehicleNumber']);
        }
        setState(() => _dashboardStats = {
              'totalDrivers': orgDrivers.length,
              'totalVehicles': orgVehicles.length,
              'totalEmployees': _employees.length,
              'activeEmployees': _activeEmployees,
              'inactiveEmployees': _inactiveEmployees,
            });
      } else {
        // Update employee counts in existing dashboardStats
        setState(() {
          _dashboardStats['totalEmployees'] = _employees.length;
          _dashboardStats['activeEmployees'] = _activeEmployees;
          _dashboardStats['inactiveEmployees'] = _inactiveEmployees;
        });
      }
    } catch (e) {
      debugPrint('❌ Error calculating dashboard stats: $e');
    }
  }

  // =========================================================
  // HELPER CALCULATIONS
  // =========================================================

  int _getDepartmentCount() {
    final departments = <String>{};
    for (final employee in _employees) {
      departments
          .add(employee['department'] ?? employee['organization'] ?? 'General');
    }
    return departments.length;
  }

  String _calculateResolutionRate() {
    if (_totalRaisedSOS == 0) return '0';
    return (_resolvedSOS.length / _totalRaisedSOS * 100).toStringAsFixed(1);
  }

  String _calculateFeedbackResponseRate() {
    if (_totalFeedbacks == 0) return '0';
    return (_resolvedFeedbacks / _totalFeedbacks * 100).toStringAsFixed(1);
  }

  bool _shouldShowSection(String section) {
    // If a specific category is selected (not 'All'), only show that section
    if (_selectedCategory != 'All' && _selectedCategory != section) {
      return false;
    }
    // Also check the checkbox state
    return _selectedReportTypes[section.toLowerCase()] ?? true;
  }
  // ============================================================
// CHUNK 2 OF 3 — BUILD METHOD + UI WIDGETS
// CHANGED: _buildFeedbackOverview now shows top drivers table
// Everything else is IDENTICAL to previous chunk2
// ============================================================

  // =========================================================
  // BUILD METHOD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final hasAnyData = _employees.isNotEmpty ||
        _pendingRosters.isNotEmpty ||
        _totalRaisedSOS > 0 ||
        _activeTrips.isNotEmpty ||
        _completedTrips.isNotEmpty ||
        _totalFeedbacks > 0 ||
        _rosterStats.completed > 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Client Reports & Analytics'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadAllReportsData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // ✅ STEP 1: CATEGORY FILTER CARDS
                  _buildCategoryFilterCards(),

                  // ✅ STEP 2: TOP BAR (PDF/Excel/WhatsApp + Filters + Checkboxes)
                  _buildTopBar(),

                  // ✅ STEP 3: ALL REPORTS CONTENT
                  _buildAllReportsContent(),
                ],
              ),
            ),
    );
  }

  // =========================================================
  // CATEGORY FILTER CARDS
  // =========================================================

  Widget _buildCategoryFilterCards() {
    final Map<String, Color> categoryColors = {
      'All': const Color(0xFF1565C0),
      'Employees': const Color(0xFF2E7D32),
      'Rosters': const Color(0xFF7B1FA2),
      'SOS': const Color(0xFFD32F2F),
      'Trips': const Color(0xFF00796B),
      'Feedback': const Color(0xFFF57C00),
    };

    final Map<String, IconData> categoryIcons = {
      'All': Icons.dashboard,
      'Employees': Icons.people,
      'Rosters': Icons.assignment,
      'SOS': Icons.warning_amber,
      'Trips': Icons.directions_car,
      'Feedback': Icons.feedback,
    };

    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = _selectedCategory == category;
          final color = categoryColors[category] ?? Colors.blue;
          final icon = categoryIcons[category] ?? Icons.category;

          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _selectedCategory = category),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 140,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? color : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? color : Colors.grey.shade300,
                      width: isSelected ? 2.5 : 1.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: color.withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            )
                          ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        color: isSelected ? Colors.white : color,
                        size: 28,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        category,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w600,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // =========================================================
  // TOP BAR
  // =========================================================

  Widget _buildTopBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── ACTION BUTTONS ──────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _generatePDF,
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text('PDF',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 2,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _exportToExcel,
                  icon: const Icon(Icons.table_chart, size: 18),
                  label: const Text('Excel',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 2,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _shareViaWhatsApp,
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('WhatsApp',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 2,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── LOCATION / DATE FILTERS ─────────────────────────────────────────
          CountryStateCityFilter(
            initialFromDate: _startDate,
            initialToDate: _endDate,
            initialCountry: _selectedCountry,
            initialState: _selectedState,
            initialCity: _selectedCity,
            initialLocalArea: _selectedArea,
            onFilterApplied: (filters) {
              setState(() {
                _startDate = filters['fromDate'];
                _endDate = filters['toDate'];
                _selectedCountry = filters['country'];
                _selectedState = filters['state'];
                _selectedCity = filters['city'];
                _selectedArea = filters['localArea'];
              });
              _loadAllReportsData();
            },
          ),

          const SizedBox(height: 14),

          // ── CHECKBOX SECTION FILTERS ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.filter_alt,
                        size: 18, color: Color(0xFF1565C0)),
                    const SizedBox(width: 8),
                    const Text(
                      'Report Sections',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          final allSelected = _selectedReportTypes.values
                              .every((v) => v);
                          _selectedReportTypes.updateAll(
                              (key, value) => !allSelected);
                        });
                      },
                      icon: const Icon(Icons.select_all, size: 16),
                      label: Text(
                        _selectedReportTypes.values.every((v) => v)
                            ? 'Deselect All'
                            : 'Select All',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _buildCheckboxFilter(
                        'Employees', 'employees', Icons.people),
                    _buildCheckboxFilter(
                        'Rosters', 'rosters', Icons.assignment),
                    _buildCheckboxFilter(
                        'SOS', 'sos', Icons.warning_amber),
                    _buildCheckboxFilter(
                        'Trips', 'trips', Icons.directions_car),
                    _buildCheckboxFilter(
                        'Feedback', 'feedback', Icons.feedback),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // CHECKBOX FILTER WIDGET
  // =========================================================

  Widget _buildCheckboxFilter(
      String label, String key, IconData icon) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedReportTypes[key] =
              !(_selectedReportTypes[key] ?? false);
        });
        // ✅ NO _loadAllReportsData() - display filter only
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _selectedReportTypes[key] == true
              ? const Color(0xFF1565C0).withOpacity(0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _selectedReportTypes[key] == true
                ? const Color(0xFF1565C0)
                : Colors.grey[300]!,
            width: _selectedReportTypes[key] == true ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _selectedReportTypes[key] == true
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
              size: 18,
              color: _selectedReportTypes[key] == true
                  ? const Color(0xFF1565C0)
                  : Colors.grey[600],
            ),
            const SizedBox(width: 6),
            Icon(icon, size: 16, color: Colors.grey[700]),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: _selectedReportTypes[key] == true
                    ? FontWeight.w600
                    : FontWeight.normal,
                color: _selectedReportTypes[key] == true
                    ? const Color(0xFF1565C0)
                    : Colors.grey[800],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // SECTION HEADER
  // =========================================================

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue, size: 28),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  // =========================================================
  // ALL REPORTS CONTENT
  // =========================================================

  Widget _buildAllReportsContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── EMPLOYEES ──────────────────────────────────────────────────────
          if (_shouldShowSection('Employees')) ...[
            _buildSectionHeader('EMPLOYEE STATISTICS', Icons.people),
            const SizedBox(height: 16),
            _buildEmployeeOverview(),
            const SizedBox(height: 32),
            if (_selectedCategory == 'All') ...[
              const Divider(thickness: 2),
              const SizedBox(height: 32),
            ],
          ],

          // ── ROSTERS ────────────────────────────────────────────────────────
          if (_shouldShowSection('Rosters')) ...[
            _buildSectionHeader('ROSTER STATISTICS', Icons.assignment),
            const SizedBox(height: 16),
            _buildRosterOverview(),
            const SizedBox(height: 32),
            if (_selectedCategory == 'All') ...[
              const Divider(thickness: 2),
              const SizedBox(height: 32),
            ],
          ],

          // ── SOS ────────────────────────────────────────────────────────────
          if (_shouldShowSection('SOS')) ...[
            _buildSectionHeader('SOS ANALYTICS', Icons.warning_amber),
            const SizedBox(height: 16),
            _buildSOSOverview(),
            const SizedBox(height: 16),
            _buildSOSStatusPieChart(),
            const SizedBox(height: 32),
            if (_selectedCategory == 'All') ...[
              const Divider(thickness: 2),
              const SizedBox(height: 32),
            ],
          ],

          // ── TRIPS ──────────────────────────────────────────────────────────
          if (_shouldShowSection('Trips')) ...[
            _buildSectionHeader('TRIP STATISTICS', Icons.directions_car),
            const SizedBox(height: 16),
            _buildTripOverview(),
            const SizedBox(height: 16),
            // ✅ ADD: Charts Row (Pie + Bar) - EXACT COPY from client_trip_dashboard_part1.dart
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: _buildTripStatusPieChart()),
                const SizedBox(width: 12),
                Expanded(flex: 5, child: _buildFleetStatisticsBarChart()),
              ],
            ),
            const SizedBox(height: 32),
            if (_selectedCategory == 'All') ...[
              const Divider(thickness: 2),
              const SizedBox(height: 32),
            ],
          ],

          // ── FEEDBACK ───────────────────────────────────────────────────────
          if (_shouldShowSection('Feedback')) ...[
            _buildSectionHeader('FEEDBACK STATISTICS', Icons.feedback),
            const SizedBox(height: 16),
            _buildFeedbackOverview(),
            const SizedBox(height: 32),
          ],

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // =========================================================
  // STAT CARD
  // =========================================================

  Widget _statCard(
      String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const Spacer(),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  // =========================================================
  // EMPLOYEE OVERVIEW
  // =========================================================

  Widget _buildEmployeeOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Employee Overview',
            style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              SizedBox(
                width: 160,
                child: _statCard('Total', '${_employees.length}',
                    Icons.people, const Color(0xFF1565C0)),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: _statCard('Active', '$_activeEmployees',
                    Icons.person, Colors.green),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: _statCard('Inactive', '$_inactiveEmployees',
                    Icons.person_off, Colors.orange),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: _statCard('Departments',
                    '${_getDepartmentCount()}', Icons.business, Colors.purple),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================
  // ROSTER OVERVIEW
  // =========================================================

  Widget _buildRosterOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Roster Overview',
            style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              SizedBox(
                width: 160,
                child: _statCard('Pending',
                    '${_pendingRosters.length}', Icons.pending_actions, Colors.orange),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: _statCard('Assigned', '${_rosterStats.assigned}',
                    Icons.assignment_turned_in, Colors.cyan),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: _statCard('In Progress',
                    '${_rosterStats.inProgress}', Icons.pending, Colors.blue),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: _statCard('Completed',
                    '${_rosterStats.completed}', Icons.task_alt, Colors.green),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildRosterStatusPieChart(),
      ],
    );
  }

  // =========================================================
  // ROSTER STATUS PIE CHART (Pending vs Assigned)
  // =========================================================

  Widget _buildRosterStatusPieChart() {
    final pending = _rosterStats.pending.toDouble();
    final assigned = _rosterStats.assigned.toDouble();
    final total = pending + assigned;

    if (total == 0) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Roster Status Distribution',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: PieChart(PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 50,
                sections: [
                  if (pending > 0)
                    PieChartSectionData(
                      value: pending,
                      title:
                          '${((pending / total) * 100).toStringAsFixed(0)}%',
                      color: Colors.orange,
                      radius: 60,
                      titleStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  if (assigned > 0)
                    PieChartSectionData(
                      value: assigned,
                      title:
                          '${((assigned / total) * 100).toStringAsFixed(0)}%',
                      color: Colors.cyan,
                      radius: 60,
                      titleStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                ],
              )),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 16, children: [
              if (pending > 0) _legendItem('Pending', Colors.orange),
              if (assigned > 0) _legendItem('Assigned', Colors.cyan),
            ]),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // ROSTER STATUS BAR CHART
  // =========================================================

  Widget _buildRosterStatusBarChart() {
    final maxY = [
      _rosterStats.pending,
      _rosterStats.assigned,
      _rosterStats.inProgress,
      _rosterStats.completed
    ].reduce((a, b) => a > b ? a : b).toDouble();

    if (maxY == 0) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Roster Status Distribution',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: BarChart(BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY * 1.2,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) {
                        const labels = [
                          'Pending',
                          'Assigned',
                          'In Progress',
                          'Completed'
                        ];
                        if (val.toInt() >= 0 &&
                            val.toInt() < labels.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(labels[val.toInt()],
                                style: const TextStyle(fontSize: 11)),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (val, meta) => Text(
                          '${val.toInt()}',
                          style: const TextStyle(fontSize: 10)),
                    ),
                  ),
                  topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: true),
                barGroups: [
                  BarChartGroupData(x: 0, barRods: [
                    BarChartRodData(
                        toY: _rosterStats.pending.toDouble(),
                        color: Colors.orange,
                        width: 30,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)))
                  ]),
                  BarChartGroupData(x: 1, barRods: [
                    BarChartRodData(
                        toY: _rosterStats.assigned.toDouble(),
                        color: Colors.cyan,
                        width: 30,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)))
                  ]),
                  BarChartGroupData(x: 2, barRods: [
                    BarChartRodData(
                        toY: _rosterStats.inProgress.toDouble(),
                        color: Colors.blue,
                        width: 30,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)))
                  ]),
                  BarChartGroupData(x: 3, barRods: [
                    BarChartRodData(
                        toY: _rosterStats.completed.toDouble(),
                        color: Colors.green,
                        width: 30,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)))
                  ]),
                ],
              )),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // SOS OVERVIEW
  // =========================================================

  Widget _buildSOSOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SOS Overview',
            style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              SizedBox(
                width: 160,
                child: _statCard('Total Raised', '$_totalRaisedSOS',
                    Icons.emergency, const Color(0xFF1565C0)),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: _statCard('Active', '${_activeSOS.length}',
                    Icons.warning_amber, Colors.red),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: _statCard('Resolved', '${_resolvedSOS.length}',
                    Icons.check_circle, Colors.green),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: _statCard('Resolution Rate',
                    '${_calculateResolutionRate()}%', Icons.trending_up, Colors.teal),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================
  // SOS STATUS PIE CHART
  // =========================================================

  Widget _buildSOSStatusPieChart() {
    if (_totalRaisedSOS == 0) return const SizedBox.shrink();

    final active = _activeSOS.length.toDouble();
    final resolved = _resolvedSOS.length.toDouble();
    final total = active + resolved;

    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SOS Status Distribution',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: PieChart(PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 50,
                sections: [
                  if (active > 0)
                    PieChartSectionData(
                      value: active,
                      title:
                          '${((active / total) * 100).toStringAsFixed(0)}%',
                      color: Colors.red,
                      radius: 60,
                      titleStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  if (resolved > 0)
                    PieChartSectionData(
                      value: resolved,
                      title:
                          '${((resolved / total) * 100).toStringAsFixed(0)}%',
                      color: Colors.green,
                      radius: 60,
                      titleStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                ],
              )),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 16, children: [
              if (active > 0) _legendItem('Active', Colors.red),
              if (resolved > 0) _legendItem('Resolved', Colors.green),
            ]),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // TRIP OVERVIEW
  // =========================================================

  // =========================================================
  // TRIP OVERVIEW — ✅ EXACT COPY from client_trip_dashboard_part1.dart _buildStatusCards()
  // =========================================================

  Widget _buildTripOverview() {
    final total = (_dashboardStats['total'] ?? 0) as int;
    final ongoing = (_dashboardStats['ongoing'] ?? 0) as int;
    final scheduled = (_dashboardStats['scheduled'] ?? 0) as int;
    final completed = (_dashboardStats['completed'] ?? 0) as int;
    final cancelled = (_dashboardStats['cancelled'] ?? 0) as int;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text('Trip Overview', 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
        ),
        LayoutBuilder(builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth > 600 ? 5 : 3;
          return GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.1,
            children: [
              _buildTripStatusCard('Total', total, Icons.stacked_bar_chart, const Color(0xFF0D47A1)),
              _buildTripStatusCard('Ongoing', ongoing, Icons.directions_car, const Color(0xFF00BFA5)),
              _buildTripStatusCard('Scheduled', scheduled, Icons.schedule, const Color(0xFF2979FF)),
              _buildTripStatusCard('Completed', completed, Icons.check_circle, const Color(0xFF43A047)),
              _buildTripStatusCard('Cancelled', cancelled, Icons.cancel, const Color(0xFFE53935)),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildTripStatusCard(String title, int count, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, color.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(height: 6),
          Text('$count',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(title,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500,
                  color: color.withOpacity(0.8)),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // =========================================================
  // TRIP DISTRIBUTION PIE CHART — ✅ EXACT COPY from client_trip_dashboard_part1.dart _buildPieChartCard()
  // =========================================================

  Widget _buildTripStatusPieChart() {
    final ongoing = (_dashboardStats['ongoing'] ?? 0) as int;
    final scheduled = (_dashboardStats['scheduled'] ?? 0) as int;
    final completed = (_dashboardStats['completed'] ?? 0) as int;
    final cancelled = (_dashboardStats['cancelled'] ?? 0) as int;
    final total = ongoing + scheduled + completed + cancelled;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Trip Distribution', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: total == 0
                ? const Center(child: Text('No data', style: TextStyle(color: Colors.grey)))
                : CustomPaint(
                    painter: _TripPieChartPainter(
                      values: [ongoing.toDouble(), scheduled.toDouble(), completed.toDouble(), cancelled.toDouble()],
                      colors: [const Color(0xFF00BFA5), const Color(0xFF2979FF), const Color(0xFF43A047), const Color(0xFFE53935)],
                      total: total.toDouble(),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('$total', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                          const Text('Total', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _pieLegend('Ongoing', ongoing, const Color(0xFF00BFA5)),
              _pieLegend('Scheduled', scheduled, const Color(0xFF2979FF)),
              _pieLegend('Completed', completed, const Color(0xFF43A047)),
              _pieLegend('Cancelled', cancelled, const Color(0xFFE53935)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pieLegend(String label, int count, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text('$label ($count)', style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
    ]);
  }

  // =========================================================
  // FLEET STATISTICS BAR CHART — ✅ EXACT COPY from client_trip_dashboard_part1.dart _buildBarChartCard()
  // =========================================================

  Widget _buildFleetStatisticsBarChart() {
    final vehicles = (_dashboardStats['totalVehicles'] ?? 0) as int;
    final drivers = (_dashboardStats['totalDrivers'] ?? 0) as int;
    final customers = (_dashboardStats['totalCustomers'] ?? 0) as int;
    final delayed = (_dashboardStats['delayed'] ?? 0) as int;

    final maxVal = [vehicles, drivers, customers, delayed].reduce((a, b) => a > b ? a : b).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fleet Statistics', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          const SizedBox(height: 16),
          _buildBarRow('Vehicles', vehicles, maxVal, const Color(0xFF1E88E5)),
          const SizedBox(height: 12),
          _buildBarRow('Drivers', drivers, maxVal, const Color(0xFFFF6F00)),
          const SizedBox(height: 12),
          _buildBarRow('Customers', customers, maxVal, const Color(0xFF8E24AA)),
          const SizedBox(height: 12),
          _buildBarRow('Delayed', delayed, maxVal, const Color(0xFFE53935)),
        ],
      ),
    );
  }

  Widget _buildBarRow(String label, int value, double maxVal, Color color) {
    final fraction = maxVal > 0 ? (value / maxVal).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
            Text('$value', style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        LayoutBuilder(builder: (ctx, cons) {
          return Stack(children: [
            Container(height: 10, width: cons.maxWidth, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(5))),
            AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              height: 10,
              width: cons.maxWidth * fraction,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                gradient: LinearGradient(colors: [color.withOpacity(0.7), color]),
              ),
            ),
          ]);
        }),
      ],
    );
  }

  // =========================================================
  // TRIP LIST CARD
  // =========================================================

  Widget _buildTripListCard(
      String title, List<dynamic> trips, Color accentColor) {
    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 22,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Text('$title (${trips.length})',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ...trips.take(5).map((trip) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: accentColor.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.directions_car,
                          color: accentColor, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(trip['customerName'] ?? 'N/A',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            Text(
                                'Driver: ${trip['driverName'] ?? 'N/A'}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      Text(trip['vehicleNumber'] ?? 'N/A',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                )),
            if (trips.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Showing 5 of ${trips.length} trips',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // FEEDBACK OVERVIEW — UPDATED: shows stat cards + top drivers table
  // =========================================================

  Widget _buildFeedbackOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Stat cards row ──────────────────────────────────────────────────
        const Text('Feedback Overview',
            style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              SizedBox(
                width: 160,
                child: _statCard('Total', '$_totalFeedbacks',
                    Icons.feedback, const Color(0xFF1565C0)),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: _statCard('Pending', '$_pendingFeedbacks',
                    Icons.pending, Colors.orange),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: _statCard('Resolved', '$_resolvedFeedbacks',
                    Icons.check_circle, Colors.green),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: _statCard(
                    'Response Rate',
                    '${_calculateFeedbackResponseRate()}%',
                    Icons.trending_up,
                    Colors.teal),
              ),
            ],
          ),
        ),

        // ── Top Drivers by Feedback ─────────────────────────────────────────
        if (_topDriversByFeedback.isNotEmpty) ...[
          const SizedBox(height: 24),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.emoji_events,
                          color: Color(0xFFF57C00), size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        'Top Drivers by Feedback',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Text(
                        '${_topDriversByFeedback.length} driver${_topDriversByFeedback.length == 1 ? '' : 's'}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Table header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(
                            width: 30,
                            child: Text('#',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13))),
                        Expanded(
                          flex: 3,
                          child: Text('Driver',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('Vehicle',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ),
                        SizedBox(
                          width: 70,
                          child: Text('Feedbacks',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Table rows
                  ..._topDriversByFeedback
                      .asMap()
                      .entries
                      .map((entry) {
                    final idx = entry.key;
                    final driver = entry.value;
                    final isEven = idx % 2 == 0;
                    Color rankColor = Colors.grey;
                    if (idx == 0) rankColor = const Color(0xFFFFD700); // gold
                    if (idx == 1) rankColor = const Color(0xFFC0C0C0); // silver
                    if (idx == 2) rankColor = const Color(0xFFCD7F32); // bronze

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isEven
                            ? Colors.grey[50]
                            : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 30,
                            child: idx < 3
                                ? Icon(Icons.circle,
                                    color: rankColor, size: 16)
                                : Text(
                                    '${idx + 1}',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w600),
                                  ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              driver['driverName'] ?? 'N/A',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              driver['vehicleNumber'] ?? 'N/A',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[700]),
                            ),
                          ),
                          SizedBox(
                            width: 70,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF57C00)
                                      .withOpacity(0.15),
                                  borderRadius:
                                      BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${driver['count']}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFF57C00)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
  // ============================================================
// CHUNK 3 OF 3 - PDF, EXCEL, WHATSAPP + CLOSING BRACE
// ============================================================

  // =========================================================
  // PDF GENERATION - UNTOUCHED
  // =========================================================

  Future<void> _generatePDF() async {
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text(
                'Client Reports & Analytics',
                style: pw.TextStyle(
                    fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 20),
            if (_clientOrganizationDomain != null)
              pw.Text('Organization: $_clientOrganizationDomain',
                  style: const pw.TextStyle(fontSize: 14)),
            pw.SizedBox(height: 10),
            pw.Text(
                'Generated: ${DateFormat('MMM dd, yyyy - hh:mm a').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 20),

            // Employee Management
            if (_shouldShowSection('Employees')) ...[
              pw.Header(level: 1, text: 'Employee Management'),
              pw.Table.fromTextArray(
                headers: ['Metric', 'Value'],
                data: [
                  ['Total Employees', '${_employees.length}'],
                  ['Active Employees', '$_activeEmployees'],
                  ['Inactive Employees', '$_inactiveEmployees'],
                  ['Departments', '${_getDepartmentCount()}'],
                ],
              ),
              pw.SizedBox(height: 20),
            ],

            // Roster Management
            if (_shouldShowSection('Rosters')) ...[
              pw.Header(level: 1, text: 'Roster Management'),
              pw.Table.fromTextArray(
                headers: ['Metric', 'Value'],
                data: [
                  ['Pending Rosters', '${_pendingRosters.length}'],
                  ['Assigned Rosters', '${_rosterStats.assigned}'],
                  ['In Progress', '${_rosterStats.inProgress}'],
                  ['Completed Rosters', '${_rosterStats.completed}'],
                ],
              ),
              pw.SizedBox(height: 20),
            ],

            // SOS Alerts
            if (_shouldShowSection('SOS')) ...[
              pw.Header(level: 1, text: 'SOS Alerts'),
              pw.Table.fromTextArray(
                headers: ['Metric', 'Value'],
                data: [
                  ['Total SOS Raised', '$_totalRaisedSOS'],
                  ['Active SOS', '${_activeSOS.length}'],
                  ['Resolved SOS', '${_resolvedSOS.length}'],
                  ['Resolution Rate', '${_calculateResolutionRate()}%'],
                ],
              ),
              pw.SizedBox(height: 20),
            ],

            // Trip Management
            if (_shouldShowSection('Trips')) ...[
              pw.Header(level: 1, text: 'Trip Management'),
              pw.Table.fromTextArray(
                headers: ['Metric', 'Value'],
                data: [
                  ['Active Trips', '${_activeTrips.length}'],
                  ['Completed Today', '${_completedTrips.length}'],
                  [
                    'Total Drivers',
                    '${_dashboardStats['totalDrivers'] ?? 0}'
                  ],
                  [
                    'Total Vehicles',
                    '${_dashboardStats['totalVehicles'] ?? 0}'
                  ],
                ],
              ),
              pw.SizedBox(height: 20),
            ],

            // Feedback Management
            if (_shouldShowSection('Feedback')) ...[
              pw.Header(level: 1, text: 'Feedback Management'),
              pw.Table.fromTextArray(
                headers: ['Metric', 'Value'],
                data: [
                  ['Total Feedbacks', '$_totalFeedbacks'],
                  ['Pending Feedbacks', '$_pendingFeedbacks'],
                  ['Resolved Feedbacks', '$_resolvedFeedbacks'],
                  [
                    'Response Rate',
                    '${_calculateFeedbackResponseRate()}%'
                  ],
                ],
              ),
            ],
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ PDF generated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error generating PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // =========================================================
  // EXCEL EXPORT - UNTOUCHED
  // =========================================================

  Future<void> _exportToExcel() async {
    try {
      final List<List<dynamic>> excelData = [];

      excelData.add(['Client Reports & Analytics']);
      excelData
          .add(['Organization: ${_clientOrganizationDomain ?? "N/A"}']);
      excelData.add([
        'Generated: ${DateFormat('MMM dd, yyyy - hh:mm a').format(DateTime.now())}'
      ]);
      excelData.add([]);

      if (_shouldShowSection('Employees')) {
        excelData.add(['EMPLOYEE MANAGEMENT']);
        excelData.add(['Metric', 'Value']);
        excelData.add(['Total Employees', _employees.length]);
        excelData.add(['Active Employees', _activeEmployees]);
        excelData.add(['Inactive Employees', _inactiveEmployees]);
        excelData.add(['Departments', _getDepartmentCount()]);
        excelData.add([]);
      }

      if (_shouldShowSection('Rosters')) {
        excelData.add(['ROSTER MANAGEMENT']);
        excelData.add(['Metric', 'Value']);
        excelData.add(['Pending Rosters', _pendingRosters.length]);
        excelData.add(['Assigned Rosters', _rosterStats.assigned]);
        excelData.add(['In Progress', _rosterStats.inProgress]);
        excelData.add(['Completed Rosters', _rosterStats.completed]);
        excelData.add([]);
      }

      if (_shouldShowSection('SOS')) {
        excelData.add(['SOS ALERTS']);
        excelData.add(['Metric', 'Value']);
        excelData.add(['Total SOS Raised', _totalRaisedSOS]);
        excelData.add(['Active SOS', _activeSOS.length]);
        excelData.add(['Resolved SOS', _resolvedSOS.length]);
        excelData
            .add(['Resolution Rate', '${_calculateResolutionRate()}%']);
        excelData.add([]);
      }

      if (_shouldShowSection('Trips')) {
        excelData.add(['TRIP MANAGEMENT']);
        excelData.add(['Metric', 'Value']);
        excelData.add(['Active Trips', _activeTrips.length]);
        excelData.add(['Completed Today', _completedTrips.length]);
        excelData.add(
            ['Total Drivers', _dashboardStats['totalDrivers'] ?? 0]);
        excelData.add(
            ['Total Vehicles', _dashboardStats['totalVehicles'] ?? 0]);
        excelData.add([]);
      }

      if (_shouldShowSection('Feedback')) {
        excelData.add(['FEEDBACK MANAGEMENT']);
        excelData.add(['Metric', 'Value']);
        excelData.add(['Total Feedbacks', _totalFeedbacks]);
        excelData.add(['Pending Feedbacks', _pendingFeedbacks]);
        excelData.add(['Resolved Feedbacks', _resolvedFeedbacks]);
        excelData.add([
          'Response Rate',
          '${_calculateFeedbackResponseRate()}%'
        ]);
      }

      final fileName =
          'client_reports_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      await ExportHelper.exportToExcel(
          data: excelData, filename: fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Excel file exported successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error exporting to Excel: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting to Excel: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // =========================================================
  // WHATSAPP SHARE - UNTOUCHED
  // =========================================================

  Future<void> _shareViaWhatsApp() async {
    try {
      final StringBuffer message = StringBuffer();

      message.writeln('📊 *Client Reports & Analytics*');
      message.writeln('');
      message.writeln(
          '🏢 Organization: ${_clientOrganizationDomain ?? "N/A"}');
      message.writeln(
          '📅 Generated: ${DateFormat('MMM dd, yyyy - hh:mm a').format(DateTime.now())}');
      message.writeln('');
      message.writeln('━━━━━━━━━━━━━━━━━━━━');
      message.writeln('');

      if (_shouldShowSection('Employees')) {
        message.writeln('👥 *EMPLOYEE MANAGEMENT*');
        message.writeln('• Total Employees: ${_employees.length}');
        message.writeln('• Active: $_activeEmployees');
        message.writeln('• Inactive: $_inactiveEmployees');
        message.writeln('• Departments: ${_getDepartmentCount()}');
        message.writeln('');
      }

      if (_shouldShowSection('Rosters')) {
        message.writeln('📋 *ROSTER MANAGEMENT*');
        message.writeln('• Pending: ${_pendingRosters.length}');
        message.writeln('• Assigned: ${_rosterStats.assigned}');
        message.writeln('• In Progress: ${_rosterStats.inProgress}');
        message.writeln('• Completed: ${_rosterStats.completed}');
        message.writeln('');
      }

      if (_shouldShowSection('SOS')) {
        message.writeln('🚨 *SOS ALERTS*');
        message.writeln('• Total Raised: $_totalRaisedSOS');
        message.writeln('• Active: ${_activeSOS.length}');
        message.writeln('• Resolved: ${_resolvedSOS.length}');
        message.writeln(
            '• Resolution Rate: ${_calculateResolutionRate()}%');
        message.writeln('');
      }

      if (_shouldShowSection('Trips')) {
        message.writeln('🚗 *TRIP MANAGEMENT*');
        message.writeln('• Active Trips: ${_activeTrips.length}');
        message.writeln('• Completed Today: ${_completedTrips.length}');
        message.writeln(
            '• Total Drivers: ${_dashboardStats['totalDrivers'] ?? 0}');
        message.writeln(
            '• Total Vehicles: ${_dashboardStats['totalVehicles'] ?? 0}');
        message.writeln('');
      }

      if (_shouldShowSection('Feedback')) {
        message.writeln('💬 *FEEDBACK MANAGEMENT*');
        message.writeln('• Total: $_totalFeedbacks');
        message.writeln('• Pending: $_pendingFeedbacks');
        message.writeln('• Resolved: $_resolvedFeedbacks');
        message.writeln(
            '• Response Rate: ${_calculateFeedbackResponseRate()}%');
      }

      final encodedMessage =
          Uri.encodeComponent(message.toString());
      final whatsappUrl = kIsWeb
          ? 'https://web.whatsapp.com/send?text=$encodedMessage'
          : 'whatsapp://send?text=$encodedMessage';

      final uri = Uri.parse(whatsappUrl);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch WhatsApp');
      }
    } catch (e) {
      debugPrint('❌ Error sharing via WhatsApp: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Error sharing via WhatsApp: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

// ============================================================
// END OF CLASS
// ============================================================
}

// ============================================================================
// PIE CHART PAINTER — ✅ EXACT COPY from client_trip_dashboard_part1.dart
// ============================================================================

class _TripPieChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final double total;

  _TripPieChartPainter({required this.values, required this.colors, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    double startAngle = -math.pi / 2;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 28;

    for (int i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweepAngle = (values[i] / total) * 2 * math.pi;
      paint.color = colors[i];
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
    final bgPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 20, bgPaint);
  }

  @override
  bool shouldRepaint(covariant _TripPieChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.total != total;
}
