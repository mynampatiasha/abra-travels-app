// lib/features/admin/driver_admin_management/driver_admin_management_screen.dart
// UPDATED: Fixed feedback counts and removed auto-refresh

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/core/services/driver_service.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/features/admin/driver_admin_management/driver_admin_management_dialogs.dart';
import 'package:abra_fleet/features/admin/driver_admin_management/driver_list_page.dart';
import 'package:abra_fleet/core/services/vehicle_service.dart';
import 'driver_feedback_list_screen.dart';
import 'package:abra_fleet/features/admin/driver_admin_management/trip_verification_screen.dart';

class DriverDashboardPage extends StatefulWidget {
  final AuthRepository authRepository;

  const DriverDashboardPage({
    Key? key,
    required this.authRepository,
  }) : super(key: key);

  @override
  State<DriverDashboardPage> createState() => _DriverDashboardPageState();
}

class _DriverDashboardPageState extends State<DriverDashboardPage> {
  late DriverService _driverService;
  late VehicleService _vehicleService;
  
  Map<String, dynamic> _summary = {
    'total': 0,
    'active': 0,
    'onLeave': 0,
    'inactive': 0,
  };

  int _expiringDocumentsCount = 0;
  int _tripVerificationCount = 0; // ✅ Added for Trip Reports count
  bool _isLoading = false;

  // Real-time data variables
  Map<String, dynamic> _tripsData = {
    'totalTrips': 0,
    'completedTrips': 0,
    'ongoingTrips': 0,
    'cancelledTrips': 0,
  };

  Map<String, dynamic> _onTripData = {
    'driversOnTrip': 0,
    'activeTrips': [],
  };

  // ✅ FIXED: Feedback data
  Map<String, dynamic> _feedbackData = {
    'totalFeedback': 0,
    'pendingReviews': 0,
    'averageRating': 0.0,
    'rating5': 0,
    'rating4': 0,
    'rating3': 0,
    'rating2': 0,
    'rating1': 0,
  };

  // ✅ REMOVED: Auto-refresh timer (user must manually refresh)
  // Timer? _realTimeUpdateTimer;

  @override
  void initState() {
    super.initState();
    _driverService = DriverService();
    _vehicleService = VehicleService();
    
    print('[DriverDashboard] 🚀 Initializing driver dashboard...');
    _fetchSummary();
    
    // ✅ REMOVED: Auto-refresh - admin can manually refresh
    // _realTimeUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
    //   if (mounted) {
    //     _fetchSummary();
    //   }
    // });
  }

  @override
  void dispose() {
    // ✅ REMOVED: Timer cleanup
    // _realTimeUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchSummary() async {
    if (!mounted) return;
    
    setState(() => _isLoading = true);

    try {
      // Ensure authentication is ready before making API calls
      print('[DriverDashboard] 🔐 Verifying authentication...');
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? await widget.authRepository.getAuthToken();
      
      if (token == null || token.isEmpty) {
        print('[DriverDashboard] ⚠️ No auth token available, waiting...');
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Fetch all data in parallel
      await Future.wait([
        _fetchDriverSummary(),
        _fetchTripsData(),
        _fetchOnTripData(),
        _fetchExpiringDocuments(),
        _fetchFeedbackData(), // ✅ FIXED: Fetch feedback data
        _fetchTripVerificationCount(), // ✅ Added: Fetch trip verification count
      ]);
    } catch (e) {
      print('[DriverDashboard] ❌ Error fetching summary: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchDriverSummary() async {
    try {
      final response = await _driverService.getDrivers();
      
      if (response['success'] == true) {
        if (response['summary'] != null) {
          if (mounted) {
            setState(() {
              _summary = response['summary'];
            });
          }
        } else {
          final drivers = List<Map<String, dynamic>>.from(response['data'] ?? []);
          final activeDrivers = drivers.where((d) => d['status']?.toString().toLowerCase() == 'active').length;
          final onLeaveDrivers = drivers.where((d) => d['status']?.toString().toLowerCase() == 'on_leave').length;
          final inactiveDrivers = drivers.where((d) => d['status']?.toString().toLowerCase() == 'inactive').length;
          
          if (mounted) {
            setState(() {
              _summary = {
                'total': drivers.length,
                'active': activeDrivers,
                'onLeave': onLeaveDrivers,
                'inactive': inactiveDrivers,
              };
            });
          }
        }
      }
    } catch (e) {
      print('[DriverDashboard] ❌ Error fetching driver summary: $e');
    }
  }

  Future<void> _fetchTripsData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/analytics/trips/completed-today'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _tripsData = {
              'totalTrips': data['count'] ?? 0,
              'completedTrips': data['count'] ?? 0,
              'ongoingTrips': 0,
              'cancelledTrips': 0,
            };
          });
        }
      }
    } catch (e) {
      print('[DriverDashboard] ⚠️ Error fetching trips data: $e');
    }
  }

  Future<void> _fetchOnTripData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/analytics/trips/active'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && mounted) {
          final activeTrips = List<Map<String, dynamic>>.from(data['trips'] ?? []);
          final uniqueDrivers = <String>{};
          
          for (final trip in activeTrips) {
            if (trip['driverId'] != null) {
              uniqueDrivers.add(trip['driverId'].toString());
            }
          }
          
          setState(() {
            _onTripData = {
              'driversOnTrip': uniqueDrivers.length,
              'activeTrips': activeTrips,
            };
          });
        }
      }
    } catch (e) {
      print('[DriverDashboard] ⚠️ Error fetching on-trip data: $e');
    }
  }

  // ✅ FIXED: Fetch feedback data from backend
  Future<void> _fetchFeedbackData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      
      print('[DriverDashboard] 📊 Fetching feedback data...');
      
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/feedback/stats'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      );

      print('[DriverDashboard] Feedback response status: ${response.statusCode}');
      print('[DriverDashboard] Feedback response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _feedbackData = {
              'totalFeedback': data['totalFeedback'] ?? 0,
              'pendingReviews': data['pendingReviews'] ?? 0,
              'averageRating': (data['averageRating'] ?? 0.0).toDouble(),
              'rating5': data['ratingBreakdown']?['5'] ?? 0,
              'rating4': data['ratingBreakdown']?['4'] ?? 0,
              'rating3': data['ratingBreakdown']?['3'] ?? 0,
              'rating2': data['ratingBreakdown']?['2'] ?? 0,
              'rating1': data['ratingBreakdown']?['1'] ?? 0,
            };
          });
          print('[DriverDashboard] ✅ Feedback data updated: $_feedbackData');
        }
      }
    } catch (e) {
      print('[DriverDashboard] ⚠️ Error fetching feedback data: $e');
      // Set default values on error
      if (mounted) {
        setState(() {
          _feedbackData = {
            'totalFeedback': 0,
            'pendingReviews': 0,
            'averageRating': 0.0,
            'rating5': 0,
            'rating4': 0,
            'rating3': 0,
            'rating2': 0,
            'rating1': 0,
          };
        });
      }
    }
  }

  // ✅ Added: Fetch trip verification count from trip_verification_service
  Future<void> _fetchTripVerificationCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      
      print('[DriverDashboard] 📊 Fetching trip verification count...');
      
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/trips/verification?limit=1000'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      );

      print('[DriverDashboard] Trip verification response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _tripVerificationCount = data['count'] ?? 0;
          });
          print('[DriverDashboard] ✅ Trip verification count updated: $_tripVerificationCount');
        }
      }
    } catch (e) {
      print('[DriverDashboard] ⚠️ Error fetching trip verification count: $e');
      if (mounted) {
        setState(() {
          _tripVerificationCount = 0;
        });
      }
    }
  }

  Future<void> _fetchExpiringDocuments() async {
    try {
      final expiringCount = await _fetchExpiringDocumentsCount();
      if (mounted) {
        setState(() {
          _expiringDocumentsCount = expiringCount;
        });
      }
    } catch (e) {
      print('[DriverDashboard] ⚠️ Error fetching expiring documents: $e');
    }
  }

  // Show On Trip Details Dialog
  Future<void> _showOnTripDetailsDialog() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.directions_car, color: Colors.orange[700]),
              const SizedBox(width: 12),
              const Text('Drivers On Trip'),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 500),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchActiveTripsDetails(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }
                
                final activeTrips = snapshot.data ?? [];
                
                if (activeTrips.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No drivers currently on trip'),
                      ],
                    ),
                  );
                }
                
                return SingleChildScrollView(
                  child: Column(
                    children: activeTrips.map((trip) => _buildTripCard(trip)).toList(),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // Show Total Trips Details Dialog
  Future<void> _showTotalTripsDetailsDialog() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.bar_chart, color: Colors.blue[700]),
              const SizedBox(width: 12),
              const Text('Trip Statistics'),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 400),
            child: FutureBuilder<Map<String, dynamic>>(
              future: _fetchTripStatistics(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }
                
                final stats = snapshot.data ?? {};
                
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTripStatsOverview(stats),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      _buildTripBreakdown(stats),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // Fetch active trips details
  Future<List<Map<String, dynamic>>> _fetchActiveTripsDetails() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/analytics/trips/active'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['trips'] ?? []);
        }
      }
      return [];
    } catch (e) {
      print('Error fetching active trips: $e');
      return [];
    }
  }

  // Fetch trip statistics
  Future<Map<String, dynamic>> _fetchTripStatistics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      
      final responses = await Future.wait([
        http.get(
          Uri.parse('${ApiConfig.baseUrl}/api/admin/analytics/trips/completed-today'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
        ),
        http.get(
          Uri.parse('${ApiConfig.baseUrl}/api/admin/analytics/trips/active'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
        ),
        http.get(
          Uri.parse('${ApiConfig.baseUrl}/api/admin/analytics/trips/cancelled-today'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
        ),
      ]);

      final completedData = json.decode(responses[0].body);
      final activeData = json.decode(responses[1].body);
      final cancelledData = json.decode(responses[2].body);

      return {
        'completedToday': completedData['count'] ?? 0,
        'activeTrips': activeData['count'] ?? 0,
        'cancelledToday': cancelledData['count'] ?? 0,
        'totalToday': (completedData['count'] ?? 0) + (activeData['count'] ?? 0) + (cancelledData['count'] ?? 0),
      };
    } catch (e) {
      print('Error fetching trip statistics: $e');
      return {};
    }
  }

  // Build trip card widget
  Widget _buildTripCard(Map<String, dynamic> trip) {
    final tripId = trip['tripId'] ?? trip['_id'] ?? 'Unknown';
    final driverName = trip['driverName'] ?? 'Unknown Driver';
    final customerName = trip['customerName'] ?? 'Unknown Customer';
    final vehicleNumber = trip['vehicleNumber'] ?? 'Unknown Vehicle';
    final status = trip['status'] ?? 'unknown';
    
    Color statusColor;
    switch (status.toLowerCase()) {
      case 'in_progress':
      case 'ongoing':
        statusColor = Colors.blue;
        break;
      case 'scheduled':
        statusColor = Colors.orange;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Trip: $tripId',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Driver: $driverName'),
            Text('Customer: $customerName'),
            Text('Vehicle: $vehicleNumber'),
          ],
        ),
      ),
    );
  }

  // Build trip stats overview
  Widget _buildTripStatsOverview(Map<String, dynamic> stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Today\'s Trip Overview',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Total Today',
                stats['totalToday']?.toString() ?? '0',
                Icons.route,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Completed',
                stats['completedToday']?.toString() ?? '0',
                Icons.check_circle,
                Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Active',
                stats['activeTrips']?.toString() ?? '0',
                Icons.directions_car,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Cancelled',
                stats['cancelledToday']?.toString() ?? '0',
                Icons.cancel,
                Colors.red,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Build trip breakdown
  Widget _buildTripBreakdown(Map<String, dynamic> stats) {
    final total = stats['totalToday'] ?? 0;
    final completed = stats['completedToday'] ?? 0;
    final active = stats['activeTrips'] ?? 0;
    final cancelled = stats['cancelledToday'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Performance Breakdown',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (total > 0) ...[
          _buildProgressBar('Completed', completed, total, Colors.green),
          _buildProgressBar('Active', active, total, Colors.orange),
          _buildProgressBar('Cancelled', cancelled, total, Colors.red),
        ] else
          const Text('No trips recorded today'),
      ],
    );
  }

  // Build stat card
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // Build progress bar
  Widget _buildProgressBar(String label, int value, int total, Color color) {
    final percentage = total > 0 ? (value / total) : 0.0;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: percentage,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$value (${(percentage * 100).toStringAsFixed(0)}%)',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<int> _fetchExpiringDocumentsCount() async {
    try {
      final response = await _driverService.getDrivers(limit: 100);
      if (response['success'] == true) {
        final drivers = List<Map<String, dynamic>>.from(response['data'] ?? []);
        int count = 0;
        final now = DateTime.now();
        final thirtyDaysFromNow = now.add(const Duration(days: 30));
        
        for (final driver in drivers) {
          final documents = (driver['documents'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
          for (final doc in documents) {
            final expiryDate = doc['expiryDate'];
            if (expiryDate != null) {
              try {
                final expiry = DateTime.parse(expiryDate);
                if (expiry.isBefore(thirtyDaysFromNow) && expiry.isAfter(now.subtract(const Duration(days: 1)))) {
                  count++;
                  break; // Count each driver only once
                }
              } catch (e) {
                // Invalid date format, skip
              }
            }
          }
        }
        return count;
      }
    } catch (e) {
      print('[DriverDashboard] Error fetching expiring documents: $e');
    }
    return 0;
  }

  Future<void> _showDocumentExpiryDialog() async {
    // Show loading dialog first
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    // Fetch actual expiring documents count
    final expiringCount = await _fetchExpiringDocumentsCount();
    
    // Close loading dialog
    if (mounted) Navigator.pop(context);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange.shade700),
            const SizedBox(width: 12),
            const Text('Document Expiry Alerts'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              expiringCount > 0 
                ? 'Found $expiringCount driver(s) with documents expiring within 30 days.'
                : 'No documents are expiring within the next 30 days.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            const Text('This feature tracks:'),
            const SizedBox(height: 8),
            const Text('• Expired driver licenses'),
            const Text('• Expiring medical certificates'),
            const Text('• Other critical documents'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (expiringCount > 0)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToDriverListWithFilter('expiring_soon');
              },
              child: const Text('View Drivers'),
            ),
        ],
      ),
    );
  }

  void _showDriverListOverlay() async {
    // ✅ Using Navigator.push() with MaterialPageRoute for standard navigation
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DriverListPage(
          authRepository: widget.authRepository,
          driverService: _driverService,
          vehicleService: _vehicleService,
          isEmbedded: false, // Changed to false since it's now a full page
        ),
      ),
    );
    // ✅ REMOVED: Auto-refresh after return (user can manually refresh)
    // print('[DriverDashboard] 🔄 Returned from driver list overlay, refreshing summary...');
    // await _fetchSummary();
  }

  void _navigateToDriverListWithFilter(String documentFilter) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) => DriverListPage(
          authRepository: widget.authRepository,
          driverService: _driverService,
          vehicleService: _vehicleService,
          initialDocumentFilter: documentFilter,
        ),
      ),
    );
    // ✅ REMOVED: Auto-refresh after return (user can manually refresh)
    // print('[DriverDashboard] 🔄 Returned from driver list (filtered), refreshing summary...');
    // await _fetchSummary();
  }

  // Show Bulk Import Dialog
  Future<void> _showBulkImportDialog() async {
    final result = await showDialog(
      context: context,
      builder: (context) => BulkImportDriversDialog(driverService: _driverService),
    );
    
    if (result == true) {
      // Refresh summary after bulk import
      _fetchSummary();
    }
  }

  // Navigate to Trip Verification Screen
  void _navigateToTripVerification() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const TripVerificationScreen(showBackButton: true),
      ),
    );
    
    // ✅ REMOVED: Auto-refresh after return (user can manually refresh)
    // print('[DriverDashboard] 🔄 Returned from trip verification, refreshing...');
    // await _fetchSummary();
  }

  // ✅ Navigate directly to Driver Feedback List Screen
  void _navigateToDriverFeedback() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DriverFeedbackPage(),
      ),
    );
  }



  // Show Export Dialog
  Future<void> _showExportDialog() async {
    await showDialog(
      context: context,
      builder: (context) => ExportDriversDialog(driverService: _driverService),
    );
  }

  // Show Import Dialog
  Future<void> _showImportDialog() async {
    final result = await showDialog(
      context: context,
      builder: (context) => ImportDriversDialog(driverService: _driverService),
    );
    
    if (result == true) {
      // Refresh summary after import
      _fetchSummary();
    }
  }

  // Show Add Driver Dialog
  Future<void> _showAddDriverDialog() async {
    final result = await showDialog(
      context: context,
      builder: (context) => AddDriverDialog(driverService: _driverService),
    );
    
    if (result == true) {
      // Refresh summary after adding driver
      _fetchSummary();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          // Header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.people, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Advanced Driver Management',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    Text(
                      'Complete driver lifecycle management with analytics',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () async {
                    await _fetchSummary();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Dashboard refreshed'),
                          duration: Duration(seconds: 1),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1565C0),
                    side: const BorderSide(color: Color(0xFF1565C0)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _showExportDialog,
                  icon: const Icon(Icons.file_download),
                  label: const Text('Export'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1565C0),
                    side: const BorderSide(color: Color(0xFF1565C0)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _showImportDialog,
                  icon: const Icon(Icons.file_upload),
                  label: const Text('Import'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1565C0),
                    side: const BorderSide(color: Color(0xFF1565C0)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _showAddDriverDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Driver'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          // Dashboard Cards
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // First Row - 3 Cards
                        Row(
                          children: [
                            Expanded(
                              child: DashboardCard(
                                title: 'TOTAL DRIVERS',
                                value: _summary['total']?.toString() ?? '0',
                                subtitle: 'Click to view all drivers',
                                subtitleColor: const Color(0xFF666666),
                                icon: Icons.people,
                                iconBgColor: const Color(0xFF1565C0),
                                borderColor: const Color(0xFF1565C0),
                                onTap: _showDriverListOverlay,
                                isCompact: false,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: DashboardCard(
                                title: 'DRIVER FEEDBACK',
                                value: _feedbackData['totalFeedback']?.toString() ?? '0',
                                subtitle: '${_feedbackData['pendingReviews'] ?? 0} pending reviews',
                                subtitleColor: const Color(0xFF9333EA),
                                icon: Icons.feedback,
                                iconBgColor: const Color(0xFFF3E8FF),
                                iconColor: const Color(0xFF9333EA),
                                borderColor: const Color(0xFF9333EA),
                                onTap: _navigateToDriverFeedback, // ✅ Navigate directly to feedback list
                                isCompact: false,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: DashboardCard(
                                title: 'ACTIVE NOW',
                                value: _summary['active']?.toString() ?? '0',
                                subtitle: 'Currently on duty',
                                subtitleColor: const Color(0xFF10B981),
                                icon: Icons.check,
                                iconBgColor: const Color(0xFFD1FAE5),
                                iconColor: const Color(0xFF10B981),
                                borderColor: const Color(0xFF10B981),
                                isCompact: false,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Second Row - 1 Card (Trip Reports)
                        Row(
                          children: [
                            Expanded(
                              child: DashboardCard(
                                title: 'TRIP REPORTS',
                                value: _tripVerificationCount.toString(),
                                subtitle: 'View odometer & verification',
                                subtitleColor: const Color(0xFF7C3AED),
                                icon: Icons.assignment,
                                iconBgColor: const Color(0xFFF3E8FF),
                                iconColor: const Color(0xFF7C3AED),
                                borderColor: const Color(0xFF7C3AED),
                                onTap: _navigateToTripVerification,
                                isCompact: false,
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Empty placeholders for consistent layout
                            Expanded(child: Container()),
                            const SizedBox(width: 16),
                            Expanded(child: Container()),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class DashboardCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color subtitleColor;
  final IconData icon;
  final Color iconBgColor;
  final Color iconColor;
  final Color borderColor;
  final VoidCallback? onTap;
  final bool isCompact;

  const DashboardCard({
    Key? key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.subtitleColor,
    required this.icon,
    required this.iconBgColor,
    this.iconColor = Colors.white,
    required this.borderColor,
    this.onTap,
    this.isCompact = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: borderColor, width: 4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: EdgeInsets.all(isCompact ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: isCompact ? 10 : 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF666666),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Container(
                  width: isCompact ? 32 : 40,
                  height: isCompact ? 32 : 40,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: isCompact ? 18 : 24),
                ),
              ],
            ),
            SizedBox(height: isCompact ? 8 : 12),
            Text(
              value,
              style: TextStyle(
                fontSize: isCompact ? 24 : 32,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A1A),
              ),
            ),
            SizedBox(height: isCompact ? 4 : 8),
            Row(
              children: [
                if (subtitle.contains('+') || subtitle.contains('%'))
                  Icon(
                    Icons.arrow_upward,
                    size: isCompact ? 12 : 14,
                    color: subtitleColor,
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: isCompact ? 11 : 13,
                      color: subtitleColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}