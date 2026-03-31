import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/core/services/backend_connection_manager.dart';
import 'package:abra_fleet/core/services/roster_service.dart';
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:abra_fleet/core/services/safe_api_service.dart';
import 'package:abra_fleet/core/services/error_handler_service.dart';
import 'package:abra_fleet/core/services/recent_activities_service.dart';
import 'package:abra_fleet/core/services/permission_service.dart';
import 'package:abra_fleet/core/services/vehicle_service.dart';
import 'package:abra_fleet/core/services/client_service.dart';
import 'package:abra_fleet/core/services/customer_service.dart';
import 'package:abra_fleet/core/services/driver_service.dart';

import 'package:abra_fleet/features/auth/domain/entities/user_entity.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';

class DashboardSummaryItem {
  final String title;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final String? subtitle;
  final VoidCallback? onTap;

  const DashboardSummaryItem({
    required this.title,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    this.subtitle,
    this.onTap,
  });
}

class AdminDashboardScreen extends StatefulWidget {
  final Function(int tabIndex)? onNavigateRequest;

  const AdminDashboardScreen({
    super.key,
    this.onNavigateRequest,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final SafeApiService _safeApi = SafeApiService();
  final PermissionService _permissionService = PermissionService();
  final VehicleService _vehicleService = VehicleService();
  final ClientService _clientService = ClientService();
  final CustomerService _customerService = CustomerService();
  final DriverService _driverService = DriverService();

  int _totalCustomers = 0;
  int _totalDrivers = 0;
  int _totalClients = 0;
  bool _isLoadingStats = false;

  bool _isLoadingAnalytics = false;
  List<Map<String, dynamic>> _topClientAnalytics = [];


  bool _isLoadingFleet = false;
  Map<String, int> _fleetCounts = {
    'available': 0,
    'inUse': 0,
    'maintenance': 0,
    'outOfService': 0,
  };

  RosterService? _rosterService;
  RosterStats _rosterStats = RosterStats.empty();
  bool _isLoadingRosterStats = false;

  List<RecentActivity> _recentActivities = [];
  bool _isLoadingActivities = false;

  bool _isOnline = true;
  Timer? _realTimeUpdateTimer;
  
  // Simple circuit breaker state
  int _consecutiveFailures = 0;
  DateTime? _lastFailureTime;
  bool _circuitBreakerOpen = false;
  
  bool get canMakeRequest {
    if (!_circuitBreakerOpen) return true;
    
    // Check if 5 minutes have passed since last failure
    if (_lastFailureTime != null) {
      final timeSinceLastFailure = DateTime.now().difference(_lastFailureTime!);
      if (timeSinceLastFailure > const Duration(minutes: 5)) {
        debugPrint('🔄 Circuit breaker timeout passed, resetting...');
        _resetCircuitBreaker();
        return true;
      }
    }
    
    return false;
  }
  
  void _recordFailure() {
    _consecutiveFailures++;
    _lastFailureTime = DateTime.now();
    
    if (_consecutiveFailures >= 3 && !_circuitBreakerOpen) {
      _circuitBreakerOpen = true;
      debugPrint('⛔ Backend connection lost after $_consecutiveFailures failures');
      debugPrint('⏰ Will retry after 5 minutes');
    }
  }
  
  void _recordSuccess() {
    if (_consecutiveFailures > 0 || _circuitBreakerOpen) {
      debugPrint('✅ Backend connection restored');
      _resetCircuitBreaker();
    }
  }
  
  void _resetCircuitBreaker() {
    _consecutiveFailures = 0;
    _circuitBreakerOpen = false;
    _lastFailureTime = null;
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_rosterService == null) {
      try {
        final connectionManager = context.read<BackendConnectionManager>();
        _rosterService = RosterService(apiService: connectionManager.apiService);
      } catch (e) {
        final connectionManager = BackendConnectionManager();
        _rosterService = RosterService(apiService: connectionManager.apiService);
      }

      _refreshDashboard();

      _realTimeUpdateTimer = Timer.periodic(const Duration(seconds: 45), (timer) {
        if (mounted) _refreshDashboard();
      });
    }
  }

  @override
  void dispose() {
    _realTimeUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshDashboard() async {
    if (!mounted) return;
    if (!canMakeRequest) return;

    _checkConnectionStatus();
    _loadRosterStats();
    _loadDashboardStats();
    _loadBusinessAnalytics();
    _loadFleetOverview();
    _loadRecentActivities();
  }

  Future<void> _checkConnectionStatus() async {
    try {
      final isOnline = await _safeApi.isOnline();
      if (mounted && _isOnline != isOnline) {
        setState(() => _isOnline = isOnline);
      }
    } catch (e) {
      // Silent fail
    }
  }

Future<void> _loadDashboardStats() async {
  if (!mounted) return;
  
  setState(() => _isLoadingStats = true);

  try {
    debugPrint('📊 Loading dashboard statistics...');
    
    final customerStatsFuture = _customerService.getCustomerStats()
        .timeout(const Duration(seconds: 90))
        .catchError((e) {
          debugPrint('❌ Customer stats error: $e');
          return {'total': 0, 'active': 0, 'inactive': 0, 'pending': 0};
        });
    
    final clientStatsFuture = _clientService.getClientStatistics()
        .timeout(const Duration(seconds: 90))
        .catchError((e) {
          debugPrint('❌ Client stats error: $e');
          return {'total': 0, 'active': 0, 'inactive': 0, 'pending': 0};
        });
    
    final driverStatsFuture = _driverService.getDriverStats()
        .timeout(const Duration(seconds: 90))
        .catchError((e) {
          debugPrint('❌ Driver stats error: $e');
          return {'total': 0, 'active': 0, 'onLeave': 0, 'inactive': 0};
        });
    
    final results = await Future.wait<Map<String, dynamic>>([
      customerStatsFuture,
      clientStatsFuture,
      driverStatsFuture,
    ]);

    if (mounted) {
      final customerStats = results[0] as Map<String, dynamic>;
      final clientStats = results[1] as Map<String, dynamic>;
      final driverStats = results[2] as Map<String, dynamic>;
      
      setState(() {
        _totalCustomers = (customerStats['total'] as num?)?.toInt() ?? 0;
        _totalClients = (clientStats['total'] as num?)?.toInt() ?? 0;
        _totalDrivers = (driverStats['total'] as num?)?.toInt() ?? 0;
        _isLoadingStats = false;
      });

      debugPrint('✅ Dashboard Stats: Customers=$_totalCustomers, Clients=$_totalClients, Drivers=$_totalDrivers');
      _recordSuccess(); // Record successful API call
    }
  } catch (e, stackTrace) {
    debugPrint('❌ Error loading dashboard stats: $e');
    _recordFailure(); // Record failure
    if (mounted) {
      setState(() => _isLoadingStats = false);
    }
  }
}

Future<void> _loadBusinessAnalytics() async {
  if (!mounted) return;
  
  setState(() => _isLoadingAnalytics = true);

  try {
    debugPrint('📊 Loading business analytics with trip statistics...');
    
    // Call the backend API endpoint
    final response = await _safeApi.safeGet(
      '/api/admin/client-analytics/trip-stats',
      queryParams: {'limit': '10'}, // Get top 10 clients
      context: 'Load Business Analytics',
      fallback: {'success': false, 'data': null},
    ).timeout(const Duration(seconds: 90));
    
    debugPrint('📡 API Response: ${response['success']}');
    
    if (response['success'] == true && response['data'] != null) {
      final clientsData = response['data']['clients'] as List<dynamic>;
      
      debugPrint('✅ Fetched ${clientsData.length} clients with trip statistics');
      
      // Parse the response into our local format
      List<Map<String, dynamic>> analyticsData = [];

      for (var client in clientsData) {
        final clientMap = {
          'name': client['companyName'] ?? 'Unknown',
          'customerCount': (client['customerCount'] as num?)?.toInt() ?? 0,
          'totalTrips': (client['totalTrips'] as num?)?.toInt() ?? 0,
          'completedTrips': (client['completedTrips'] as num?)?.toInt() ?? 0,
          'ongoingTrips': (client['ongoingTrips'] as num?)?.toInt() ?? 0,
          'scheduledTrips': (client['scheduledTrips'] as num?)?.toInt() ?? 0,
          'cancelledTrips': (client['cancelledTrips'] as num?)?.toInt() ?? 0,
          'revenue': (client['estimatedRevenue'] as num?)?.toDouble() ?? 0.0,
          'domain': client['domain'] ?? '',
        };
        
        analyticsData.add(clientMap);
        
        debugPrint('   📊 ${clientMap['name']}: '
                   '${clientMap['customerCount']} employees, '
                   '${clientMap['totalTrips']} trips');
      }

      if (mounted) {
        setState(() {
          _topClientAnalytics = analyticsData;
          _isLoadingAnalytics = false;
        });
        
        debugPrint('✅ Business analytics loaded: ${_topClientAnalytics.length} top clients');
        _recordSuccess(); // Record successful API call
        
        // Log the data for verification
        for (var client in _topClientAnalytics) {
          debugPrint('   • ${client['name']}: '
                     'Employees=${client['customerCount']}, '
                     'Trips=${client['totalTrips']} '
                     '(Completed=${client['completedTrips']}, '
                     'Ongoing=${client['ongoingTrips']}, '
                     'Scheduled=${client['scheduledTrips']}, '
                     'Cancelled=${client['cancelledTrips']})');
        }
      }
    } else {
      throw Exception('Invalid response from analytics endpoint');
    }
  } catch (e, stackTrace) {
    debugPrint('❌ Error loading analytics: $e');
    debugPrint('Stack trace: $stackTrace');
    _recordFailure(); // Record failure
    
    if (mounted) {
      setState(() {
        _topClientAnalytics = [];
        _isLoadingAnalytics = false;
      });
    }
  }
}

// ============================================================================
// FIX: Update _loadFleetOverview() to use limit=100 (backend max)
// ============================================================================
// Replace your _loadFleetOverview() method with this corrected version
// ============================================================================

Future<void> _loadFleetOverview() async {
  if (!mounted) return;
  setState(() => _isLoadingFleet = true);

  try {
    debugPrint('🚗 Fleet Overview: Fetching vehicles...');
    
    // ✅ FIX: Use limit=100 (backend maximum) instead of 1000
    final result = await _vehicleService.getVehicles(page: 1, limit: 100)
        .timeout(const Duration(seconds: 90), onTimeout: () {
          return {'success': false, 'message': 'Request timeout', 'data': []};
        });
    
    if (result['success'] == true) {
      List vehicles = result['data'] ?? [];
      
      // ✅ Check if there are more pages and fetch all vehicles
      final pagination = result['pagination'];
      if (pagination != null && pagination['pages'] != null && pagination['pages'] > 1) {
        debugPrint('📄 Multiple pages detected (${pagination['pages']} pages), fetching all...');
        
        // Fetch remaining pages
        for (int page = 2; page <= pagination['pages']; page++) {
          try {
            final pageResult = await _vehicleService.getVehicles(page: page, limit: 100)
                .timeout(const Duration(seconds: 90));
            
            if (pageResult['success'] == true && pageResult['data'] != null) {
              vehicles.addAll(pageResult['data']);
              debugPrint('   ✅ Fetched page $page');
            }
          } catch (e) {
            debugPrint('   ⚠️ Error fetching page $page: $e');
          }
        }
      }
      
      debugPrint('✅ Total vehicles fetched: ${vehicles.length}');
      
      if (vehicles.isEmpty) {
        if (mounted) {
          setState(() {
            _fleetCounts = {
              'available': 0,
              'inUse': 0,
              'maintenance': 0,
              'outOfService': 0
            };
            _isLoadingFleet = false;
          });
        }
        _recordSuccess(); // Record successful API call even if empty
        return;
      }
      
      int available = 0, inUse = 0, maintenance = 0, outOfService = 0;

      for (var v in vehicles) {
        // ✅ Convert status to UPPERCASE for comparison (backend returns UPPERCASE)
        String status = (v['status'] ?? 'INACTIVE').toString().toUpperCase();
        
        // Check if vehicle has active assignments
        int assignedCustomers = 0;
        if (v['assignedCustomersCount'] != null) {
          assignedCustomers = (v['assignedCustomersCount'] is int) 
              ? v['assignedCustomersCount'] 
              : int.tryParse(v['assignedCustomersCount'].toString()) ?? 0;
        }
        
        bool hasActiveTrip = v['currentTripId'] != null && 
                            v['currentTripId'].toString().isNotEmpty &&
                            v['currentTripId'].toString() != 'null';
        
        bool isUnavailable = v['isAvailable'] == false;
        
        // Categorize based on status (UPPERCASE comparison)
        if (status == 'MAINTENANCE') {
          maintenance++;
        } else if (status == 'INACTIVE' || status == 'RETIRED') {
          outOfService++;
        } else if (status == 'ACTIVE') {
          // Active vehicles - check if in use or available
          if (hasActiveTrip || assignedCustomers > 0 || isUnavailable) {
            inUse++;
          } else {
            available++;
          }
        } else {
          // Unknown status = out of service
          outOfService++;
        }
      }

      if (mounted) {
        setState(() {
          _fleetCounts = {
            'available': available,
            'inUse': inUse,
            'maintenance': maintenance,
            'outOfService': outOfService,
          };
          _isLoadingFleet = false;
        });
        
        debugPrint('📊 Fleet Overview Counts:');
        debugPrint('   ✅ Available: $available');
        debugPrint('   🚙 In Use: $inUse');
        debugPrint('   🔧 Maintenance: $maintenance');
        debugPrint('   ❌ Out of Service: $outOfService');
        
        _recordSuccess(); // Record successful API call
      }
    } else {
      throw Exception(result['message'] ?? 'Failed to fetch vehicles');
    }
  } catch (e, stackTrace) {
    debugPrint('❌ Error loading fleet overview: $e');
    debugPrint('Stack trace: $stackTrace');
    _recordFailure(); // Record failure
    
    if (mounted) {
      setState(() {
        _isLoadingFleet = false;
        _fleetCounts = {
          'available': 0,
          'inUse': 0,
          'maintenance': 0,
          'outOfService': 0
        };
      });
    }
  }
}

// ============================================================================
// CHANGES MADE:
// ============================================================================
// 1. Changed limit from 1000 to 100 (backend maximum allowed)
// 2. Added pagination support to fetch all vehicles if there are multiple pages
// 3. Status comparison changed to UPPERCASE (backend returns UPPERCASE)
// 4. Added detailed debug logging to track the process
//
// This will now:
// - Not get 400 error (respects backend limit of 100)
// - Fetch ALL vehicles across multiple pages if needed
// - Correctly categorize vehicles by UPPERCASE status
// ============================================================================

  Future<void> _loadRosterStats() async {
    if (_rosterService == null) return;
    if (_rosterStats.total == 0) setState(() => _isLoadingRosterStats = true);
    try {
      final stats = await _rosterService!.getRosterStats();
      if (mounted) setState(() { _rosterStats = stats; _isLoadingRosterStats = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoadingRosterStats = false);
    }
  }

  Future<void> _loadRecentActivities() async {
    if (!mounted) return;
    setState(() => _isLoadingActivities = true);
    try {
      final activities = await RecentActivitiesService.fetchRecentActivities();
      if (mounted) setState(() { _recentActivities = activities; _isLoadingActivities = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoadingActivities = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authRepository = Provider.of<AuthRepository>(context, listen: false);
    final currentUser = authRepository.currentUser;
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = screenSize.width > 1200;
    final isMobile = screenSize.width <= 800;

    final summaryItems = [
      DashboardSummaryItem(
        title: 'Total Clients',
        value: _isLoadingStats ? '...' : _totalClients.toString(),
        icon: Icons.business,
        iconColor: Colors.white,
        backgroundColor: const Color(0xFF8B5CF6),
        subtitle: 'Partner Companies',
        onTap: null, // Made non-clickable
      ),
      DashboardSummaryItem(
        title: 'Total Customers',
        value: _isLoadingStats ? '...' : _totalCustomers.toString(),
        icon: Icons.groups,
        iconColor: Colors.white,
        backgroundColor: const Color(0xFFF59E0B),
        subtitle: 'Employees Registered',
        onTap: null, // Made non-clickable
      ),
      DashboardSummaryItem(
        title: 'Total Drivers',
        value: _isLoadingStats ? '...' : _totalDrivers.toString(),
        icon: Icons.local_shipping,
        iconColor: Colors.white,
        backgroundColor: const Color(0xFF10B981),
        subtitle: 'Active & Available',
        onTap: null, // Made non-clickable
      ),
      DashboardSummaryItem(
        title: 'Pending Rosters',
        value: _rosterStats.pending.toString(),
        icon: Icons.calendar_today,
        iconColor: Colors.white,
        backgroundColor: _rosterStats.pending > 0 ? const Color(0xFFF97316) : Colors.grey,
        subtitle: 'Action Required',
        onTap: null, // Made non-clickable
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          // Show subtle banner if backend connection is lost for more than 5 minutes
          if (_circuitBreakerOpen && _lastFailureTime != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border(
                  bottom: BorderSide(color: Colors.orange.shade200, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Backend connection unavailable. Data may be outdated. Retrying automatically...',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _resetCircuitBreaker();
                      _refreshDashboard();
                    },
                    child: Text(
                      'Retry Now',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // Main content
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshDashboard,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(isDesktop ? 32.0 : 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, currentUser, isDesktop),
                    const SizedBox(height: 32),
                    
                    _buildStatsGrid(context, summaryItems, isDesktop),
                    const SizedBox(height: 32),

                    _buildBusinessAnalyticsSection(context, isDesktop),
                    const SizedBox(height: 32),

                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: _buildRecentActivity(context)),
                          const SizedBox(width: 32),
                          Expanded(flex: 2, child: _buildFleetOverviewCard(context)),
                        ],
                      )
                    else
                      Column(
                        children: [
                          _buildFleetOverviewCard(context),
                          const SizedBox(height: 32),
                          _buildRecentActivity(context),
                        ],
                      ),
                      
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


Widget _buildBusinessAnalyticsSection(BuildContext context, bool isDesktop) {
  return Container(
    padding: const EdgeInsets.all(24),
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Business Analytics',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isLoadingAnalytics 
                      ? 'Loading client data...'
                      : 'Top ${_topClientAnalytics.length} Clients by Trip Activity',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
            Row(
              children: [
                if (_isLoadingAnalytics)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadBusinessAnalytics,
                  tooltip: 'Refresh Analytics',
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        
        // Legend
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _buildLegendItem('Employees', const Color(0xFF0D47A1)),
            _buildLegendItem('Completed', const Color(0xFF4CAF50)),
            _buildLegendItem('Ongoing', const Color(0xFF2196F3)),
            _buildLegendItem('Scheduled', const Color(0xFFF59E0B)),
            _buildLegendItem('Cancelled', const Color(0xFFF44336)),
          ],
        ),
        
        const SizedBox(height: 32),
        
        // Chart Content
        if (_isLoadingAnalytics)
          const SizedBox(
            height: 400,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_topClientAnalytics.isEmpty)
          const SizedBox(
            height: 400,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.analytics_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    "No client data available",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Client analytics will appear here once trips are created",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          )
        else
          // Scrollable chart container
          Container(
            height: 500,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                // Dynamic width based on number of clients
                width: max(900, _topClientAnalytics.length * 120.0),
                padding: const EdgeInsets.all(16),
                child: _buildSimpleBarChart(),
              ),
            ),
          ),
      ],
    ),
  );
}

  
  Widget _buildSimpleBarChart() {
  final double maxY = _calculateMaxY();
  
  // Bar colors
  final barColors = [
    const Color(0xFF0D47A1), // Employees - Dark Blue
    const Color(0xFF4CAF50), // Completed - Green
    const Color(0xFF2196F3), // Ongoing - Light Blue
    const Color(0xFFF59E0B), // Scheduled - Orange
    const Color(0xFFF44336), // Cancelled - Red
  ];
  
  // Build bar groups - each bar gets its own X position
  List<BarChartGroupData> barGroups = [];
  int xPosition = 0;
  
  for (int clientIndex = 0; clientIndex < _topClientAnalytics.length; clientIndex++) {
    final client = _topClientAnalytics[clientIndex];
    
    final values = [
      (client['customerCount'] as int).toDouble(),
      (client['completedTrips'] as int).toDouble(),
      (client['ongoingTrips'] as int).toDouble(),
      (client['scheduledTrips'] as int).toDouble(),
      (client['cancelledTrips'] as int).toDouble(),
    ];
    
    // Create 5 separate bars for this client
    for (int barIndex = 0; barIndex < 5; barIndex++) {
      barGroups.add(
        BarChartGroupData(
          x: xPosition++,
          barRods: [
            BarChartRodData(
              toY: values[barIndex],
              color: barColors[barIndex],
              width: 16,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
          ],
        ),
      );
    }
    
    // Add gap after each client (skip last client)
    if (clientIndex < _topClientAnalytics.length - 1) {
      xPosition++; // Extra space between clients
    }
  }
  
  return BarChart(
    BarChartData(
      alignment: BarChartAlignment.start,
      maxY: maxY,
      barTouchData: BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          tooltipBgColor: Colors.blueGrey.withOpacity(0.8),
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            // Calculate which client and which bar type
            int position = group.x.toInt();
            int clientIndex = 0;
            int barTypeIndex = 0;
            int currentPos = 0;
            
            for (int i = 0; i < _topClientAnalytics.length; i++) {
              for (int j = 0; j < 5; j++) {
                if (currentPos == position) {
                  clientIndex = i;
                  barTypeIndex = j;
                  break;
                }
                currentPos++;
              }
              if (currentPos > position) break;
              currentPos++; // Gap between clients
            }
            
            final client = _topClientAnalytics[clientIndex];
            final labels = [
              'Employees: ${client['customerCount']}',
              'Completed: ${client['completedTrips']}',
              'Ongoing: ${client['ongoingTrips']}',
              'Scheduled: ${client['scheduledTrips']}',
              'Cancelled: ${client['cancelledTrips']}',
            ];
            
            return BarTooltipItem(
              '${client['name']}\n${labels[barTypeIndex]}',
              const TextStyle(color: Colors.white, fontSize: 12),
            );
          },
        ),
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              // Show count above each bar
              int position = value.toInt();
              int clientIndex = 0;
              int barTypeIndex = 0;
              int currentPos = 0;
              
              for (int i = 0; i < _topClientAnalytics.length; i++) {
                for (int j = 0; j < 5; j++) {
                  if (currentPos == position) {
                    clientIndex = i;
                    barTypeIndex = j;
                    
                    final client = _topClientAnalytics[clientIndex];
                    final values = [
                      client['customerCount'],
                      client['completedTrips'],
                      client['ongoingTrips'],
                      client['scheduledTrips'],
                      client['cancelledTrips'],
                    ];
                    
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        values[barTypeIndex].toString(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: barColors[barTypeIndex],
                        ),
                      ),
                    );
                  }
                  currentPos++;
                }
                currentPos++; // Gap
                if (currentPos > position) break;
              }
              
              return const Text('');
            },
            reservedSize: 20,
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              // Show company name below center of each group
              int position = value.toInt();
              int currentPos = 0;
              
              for (int i = 0; i < _topClientAnalytics.length; i++) {
                // Check if this position is the middle of this client's bars (position 2 out of 0-4)
                if (position == currentPos + 2) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      _topClientAnalytics[i]['name'],
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                currentPos += 6; // 5 bars + 1 gap
              }
              
              return const Text('');
            },
            reservedSize: 40,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) {
              return Text(
                value.toInt().toString(),
                style: const TextStyle(fontSize: 10),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
      ),
      barGroups: barGroups,
    ),
  );
}
  
  double _calculateMaxY() {
  if (_topClientAnalytics.isEmpty) return 100;
  
  int maxValue = 0;
  
  for (var data in _topClientAnalytics) {
    final values = [
      data['customerCount'] as int,
      data['completedTrips'] as int,
      data['ongoingTrips'] as int,
      data['scheduledTrips'] as int,
      data['cancelledTrips'] as int,
    ];
    
    final currentMax = values.reduce((a, b) => a > b ? a : b);
    if (currentMax > maxValue) {
      maxValue = currentMax;
    }
  }
  
  // Add 20% padding to max value
  return (maxValue * 1.2).ceilToDouble();
}
  
  Widget _buildLegendItem(String label, Color color) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

  Widget _buildFleetOverviewCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Fleet Overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[800])),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadFleetOverview,
                tooltip: 'Refresh Fleet Data',
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          if (_isLoadingFleet)
             const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          else
            Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildFleetStatusBox(count: _fleetCounts['available']!, label: 'Available', color: const Color(0xFF4CAF50), icon: Icons.check_circle)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildFleetStatusBox(count: _fleetCounts['inUse']!, label: 'In Use', color: const Color(0xFF2196F3), icon: Icons.directions_car)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildFleetStatusBox(count: _fleetCounts['maintenance']!, label: 'Maintenance', color: const Color(0xFFFF9800), icon: Icons.build)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildFleetStatusBox(count: _fleetCounts['outOfService']!, label: 'Out of Service', color: const Color(0xFFF44336), icon: Icons.warning)),
                  ],
                ),
                const SizedBox(height: 24),
                // Fleet Overview Button - COMMENTED OUT AS PER USER REQUEST
                // SizedBox(
                //   width: double.infinity,
                //   child: ElevatedButton.icon(
                //     onPressed: () => widget.onNavigateRequest?.call(11),
                //     icon: const Icon(Icons.directions_car, size: 20),
                //     label: const Text('View Fleet Overview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                //     style: ElevatedButton.styleFrom(
                //       backgroundColor: const Color(0xFF0D47A1),
                //       foregroundColor: Colors.white,
                //       padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                //       shape: RoundedRectangleBorder(
                //         borderRadius: BorderRadius.circular(12),
                //       ),
                //       elevation: 2,
                //     ),
                //   ),
                // ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFleetStatusBox({required int count, required String label, required Color color, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(count.toString(), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[700])),
        ],
      ),
    );
  }

  Widget _buildRecentActivity(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent Activity', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[800])),
          const SizedBox(height: 16),
          _isLoadingActivities
              ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
              : _recentActivities.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("No recent activities")))
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _recentActivities.length > 5 ? 5 : _recentActivities.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final activity = _recentActivities[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.withOpacity(0.1),
                            child: Icon(Icons.notifications_outlined, color: Colors.blue[800], size: 20),
                          ),
                          title: Text(activity.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: Text(activity.subtitle, style: const TextStyle(fontSize: 12)),
                          trailing: Text(activity.timeAgo, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        );
                      },
                    ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context, List<DashboardSummaryItem> items, bool isDesktop) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isDesktop ? 4 : 2,
        crossAxisSpacing: 16.0,
        mainAxisSpacing: 16.0,
        childAspectRatio: 1.4,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildSummaryCard(items[index]),
    );
  }

  Widget _buildSummaryCard(DashboardSummaryItem item) {
    // If onTap is null, return a non-clickable container
    if (item.onTap == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: item.backgroundColor.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
          border: Border(left: BorderSide(color: item.backgroundColor, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(item.icon, color: item.backgroundColor, size: 28),
                Text(item.value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey[800])),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                if (item.subtitle != null)
                  Text(item.subtitle!, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          ],
        ),
      );
    }
    
    // If onTap is provided, return a clickable card
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: item.backgroundColor.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
            border: Border(left: BorderSide(color: item.backgroundColor, width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(item.icon, color: item.backgroundColor, size: 28),
                  Text(item.value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                  if (item.subtitle != null)
                    Text(item.subtitle!, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, UserEntity currentUser, bool isDesktop) {
    return Container(
      padding: EdgeInsets.all(isDesktop ? 32 : 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF0D47A1), Color(0xFF1976D2)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: const Color(0xFF0D47A1).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome Back, ${currentUser.name ?? 'Admin'}!', style: TextStyle(fontSize: isDesktop ? 28 : 22, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                Text('Fleet Business Analytics Dashboard', style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.9))),
              ],
            ),
          ),
          if (_isOnline)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.greenAccent)),
              child: const Row(children: [Icon(Icons.wifi, color: Colors.white, size: 16), SizedBox(width: 8), Text('Online', style: TextStyle(color: Colors.white))]),
            ),
        ],
      ),
    );
  }
}