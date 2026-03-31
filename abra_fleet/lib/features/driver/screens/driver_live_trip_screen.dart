// ============================================================================
// COMPLETE FILE: lib/features/driver/dashboard/presentation/screens/driver_live_trip_screen.dart
// Driver Live Trip Screen - ENHANCED WITH ALL REAL-TIME FEATURES
// ============================================================================

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../../../../../core/services/backend_location_tracking_service.dart';
import '../../../../../core/services/driver_route_service.dart';
import '../../../../../core/services/trip_service.dart';

/// Driver's live trip screen with navigation and customer list
class DriverLiveTripScreen extends StatefulWidget {
  final String driverId;
  final String? vehicleId;

  const DriverLiveTripScreen({
    super.key,
    required this.driverId,
    this.vehicleId,
  });

  @override
  State<DriverLiveTripScreen> createState() => _DriverLiveTripScreenState();
}

class _DriverLiveTripScreenState extends State<DriverLiveTripScreen> {
  final BackendLocationTrackingService _trackingService = BackendLocationTrackingService();
  final DriverRouteService _routeService = DriverRouteService();
  final TripService _tripService = TripService();
  
  bool _isTripStarted = false;
  int _currentCustomerIndex = 0;
  TodayRouteResponse? _todayRoute;
  bool _isLoading = true;
  String? _currentTripId;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadTodayRoute();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _trackingService.stopTracking();
    super.dispose();
  }

  // =========================================================================
  // AUTO-REFRESH EVERY 30 SECONDS
  // =========================================================================
  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (_isTripStarted && mounted) {
          debugPrint('🔄 [AUTO-REFRESH] Refreshing trip data...');
          _refreshLiveTripData(silent: true);
        }
      },
    );
  }

  // =========================================================================
  // LOAD TODAY'S ROUTE
  // =========================================================================
  Future<void> _loadTodayRoute() async {
    try {
      debugPrint('═' * 80);
      debugPrint('📥 [LOAD ROUTE] Loading today\'s route...');
      debugPrint('═' * 80);
      
      final route = await _routeService.getTodayRoute();
      
      if (mounted) {
        setState(() {
          _todayRoute = route;
          _isTripStarted = _trackingService.isTracking;
          _isLoading = false;
          
          // Extract trip ID from route data
          if (route?.hasRoute == true && route?.customers != null && route!.customers!.isNotEmpty) {
            _currentTripId = route.tripId ?? route.customers!.first.tripId;
            debugPrint('✅ [LOAD ROUTE] Trip ID: $_currentTripId');
          }
        });
      }
      
      debugPrint('✅ [LOAD ROUTE] Route loaded successfully');
      debugPrint('   - Has route: ${route?.hasRoute}');
      debugPrint('   - Customers: ${route?.customers?.length ?? 0}');
      debugPrint('═' * 80);
      
    } catch (e, stackTrace) {
      debugPrint('❌ [LOAD ROUTE] Error: $e');
      debugPrint('   Stack trace: $stackTrace');
      
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error loading route: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // =========================================================================
  // REFRESH TRIP DATA
  // =========================================================================
  Future<void> _refreshLiveTripData({bool silent = false}) async {
    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Refreshing trip data...'),
            ],
          ),
          duration: Duration(seconds: 1),
        ),
      );
    }

    try {
      debugPrint('🔄 [REFRESH] Refreshing trip data...');
      
      final route = await _routeService.getTodayRoute();
      
      if (mounted) {
        setState(() {
          _todayRoute = route;
          _isTripStarted = _trackingService.isTracking;
        });
      }

      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Trip data refreshed successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      
      debugPrint('✅ [REFRESH] Data refreshed successfully');
      
    } catch (e) {
      debugPrint('❌ [REFRESH] Error: $e');
      
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to refresh: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // =========================================================================
  // START TRIP
  // =========================================================================
  Future<void> _startTrip() async {
    try {
      debugPrint('═' * 80);
      debugPrint('🚀 [START TRIP] Starting trip...');
      debugPrint('═' * 80);
      
      // Show loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Starting trip...'),
              ],
            ),
          ),
        );
      }

      // Step 1: Update trip status
      if (_currentTripId != null) {
        debugPrint('📝 [START TRIP] Updating trip status to STARTED');
        debugPrint('   Trip ID: $_currentTripId');
        
        final statusResult = await _tripService.startTrip(
          tripId: _currentTripId!,
          notes: 'Trip started by driver from mobile app',
        );

        if (!statusResult['success']) {
          if (mounted) Navigator.of(context).pop();
          throw Exception(statusResult['message'] ?? 'Failed to update trip status');
        }

        debugPrint('✅ [START TRIP] Trip status updated to STARTED');
      }

      // Step 2: Start GPS tracking
      debugPrint('🛰️ [START TRIP] Starting GPS tracking...');
      
      await _trackingService.startTracking(
        driverId: widget.driverId,
        tripId: _currentTripId,
        vehicleId: widget.vehicleId,
      );
      
      debugPrint('✅ [START TRIP] GPS tracking started');

      // Close loading
      if (mounted) Navigator.of(context).pop();

      setState(() {
        _isTripStarted = true;
      });

      debugPrint('═' * 80);
      debugPrint('✅ [START TRIP] Trip started successfully!');
      debugPrint('═' * 80);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🚀 Trip Started Successfully!',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                if (_currentTripId != null) 
                  Text('Trip ID: $_currentTripId', style: const TextStyle(fontSize: 13)),
                const Text('✅ GPS tracking active', style: TextStyle(fontSize: 13)),
                const Text('✅ Trip status updated', style: TextStyle(fontSize: 13)),
                const Text('✅ Admin notified', style: TextStyle(fontSize: 13)),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [START TRIP] Error: $e');
      debugPrint('   Stack trace: $stackTrace');
      
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '❌ Failed to Start Trip',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text('Error: $e', style: const TextStyle(fontSize: 13)),
                const Text('Please try again or contact support.', style: TextStyle(fontSize: 13)),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // =========================================================================
  // COMPLETE TRIP
  // =========================================================================
  Future<void> _completeTrip() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Trip?'),
        content: const Text('Have all customers been picked up?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      debugPrint('═' * 80);
      debugPrint('🏁 [COMPLETE TRIP] Completing trip...');
      debugPrint('═' * 80);
      
      // Show loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Completing trip...'),
              ],
            ),
          ),
        );
      }

      // Step 1: Update trip status
      if (_currentTripId != null) {
        debugPrint('📝 [COMPLETE TRIP] Updating trip status to COMPLETED');
        debugPrint('   Trip ID: $_currentTripId');
        
        final statusResult = await _tripService.completeTrip(
          tripId: _currentTripId!,
          notes: 'Trip completed by driver - all customers picked up',
        );

        if (!statusResult['success']) {
          if (mounted) Navigator.of(context).pop();
          throw Exception(statusResult['message'] ?? 'Failed to update trip status');
        }

        debugPrint('✅ [COMPLETE TRIP] Trip status updated to COMPLETED');
      }

      // Step 2: Stop GPS tracking
      debugPrint('🛑 [COMPLETE TRIP] Stopping GPS tracking...');
      
      await _trackingService.stopTracking();
      
      debugPrint('✅ [COMPLETE TRIP] GPS tracking stopped');

      // Close loading
      if (mounted) Navigator.of(context).pop();

      debugPrint('═' * 80);
      debugPrint('✅ [COMPLETE TRIP] Trip completed successfully!');
      debugPrint('═' * 80);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🏁 Trip Completed Successfully!',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                if (_currentTripId != null) 
                  Text('Trip ID: $_currentTripId', style: const TextStyle(fontSize: 13)),
                const Text('✅ GPS tracking stopped', style: TextStyle(fontSize: 13)),
                const Text('✅ Trip status updated', style: TextStyle(fontSize: 13)),
                const Text('✅ Admin notified', style: TextStyle(fontSize: 13)),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [COMPLETE TRIP] Error: $e');
      debugPrint('   Stack trace: $stackTrace');
      
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '❌ Failed to Complete Trip',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text('Error: $e', style: const TextStyle(fontSize: 13)),
                const Text('Please try again or contact support.', style: TextStyle(fontSize: 13)),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // =========================================================================
  // MARK CUSTOMER PICKED UP - FIXED WITH IMMEDIATE LOCAL UPDATE
  // =========================================================================
  Future<void> _markCustomerPickedUp(int index) async {
    // Basic safety check
    if (_todayRoute == null || _todayRoute!.customers == null || index >= _todayRoute!.customers!.length) {
      return;
    }

    final customer = _todayRoute!.customers![index];
    
    debugPrint('═' * 80);
    debugPrint('📍 [PICK UP] Initiating pickup for ${customer.name}');
    
    // ✅ 1. IMMEDIATE LOCAL UPDATE (Optimistic UI)
    // We update the UI instantly before waiting for the API
    setState(() {
      // Create a copy of the customer with the new status
      final updatedCustomer = CustomerAssignment(
        id: customer.id,
        customerId: customer.customerId,
        name: customer.name,
        phone: customer.phone,
        email: customer.email,
        tripType: customer.tripType,
        tripTypeLabel: customer.tripTypeLabel,
        shift: customer.shift,
        scheduledTime: customer.scheduledTime,
        fromLocation: customer.fromLocation,
        toLocation: customer.toLocation,
        fromCoordinates: customer.fromCoordinates,
        toCoordinates: customer.toCoordinates,
        status: 'picked_up', // Force status to picked_up
        distance: customer.distance,
        estimatedDuration: customer.estimatedDuration,
        tripId: customer.tripId,
        pickupSequence: customer.pickupSequence,
      );

      // Replace the item in the list
      _todayRoute!.customers![index] = updatedCustomer;
      
      // Update the summary counts locally
      if (_todayRoute!.routeSummary != null) {
        final completedCount = _todayRoute!.customers!.where((c) => 
          c.status == 'completed' || c.status == 'picked_up'
        ).length;
        
        // Rebuild the main object with new counts
        _todayRoute = TodayRouteResponse(
          hasRoute: _todayRoute!.hasRoute,
          message: _todayRoute!.message,
          vehicle: _todayRoute!.vehicle,
          routeSummary: RouteSummary(
            totalCustomers: _todayRoute!.routeSummary!.totalCustomers,
            completedCustomers: completedCount, 
            pendingCustomers: _todayRoute!.routeSummary!.totalCustomers - completedCount,
            totalDistance: _todayRoute!.routeSummary!.totalDistance,
            estimatedDuration: _todayRoute!.routeSummary!.estimatedDuration,
            routeType: _todayRoute!.routeSummary!.routeType,
            availableSeats: _todayRoute!.routeSummary!.availableSeats,
          ),
          customers: _todayRoute!.customers,
          routeOptimization: _todayRoute!.routeOptimization,
          rosterId: _todayRoute!.rosterId,
          scheduledDate: _todayRoute!.scheduledDate,
          tripId: _todayRoute!.tripId,
        );
      }
    });

    try {
      // ✅ 2. PAUSE AUTO-REFRESH
      // Stop the timer so it doesn't overwrite our local change with old server data
      _autoRefreshTimer?.cancel();

      // Show temporary feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Updating status...'),
            duration: Duration(milliseconds: 1000),
            backgroundColor: Colors.blue,
          ),
        );
      }

      // Get current location for the API
      Position? currentPosition;
      try {
        currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (e) {
        debugPrint('⚠️ [PICK UP] Could not get location: $e');
      }

      // ✅ 3. CALL BACKEND API
      final success = await _routeService.markCustomerPicked(
        customer.id,
        latitude: currentPosition?.latitude,
        longitude: currentPosition?.longitude,
      );

      if (!success) {
        throw Exception('Backend returned failure');
      }

      // If this is the first customer, set trip to IN_PROGRESS
      if (index == 0 && _currentTripId != null) {
        await _tripService.setTripInProgress(
          tripId: _currentTripId!,
          notes: 'Driver started customer pickups',
        );
      }

      // ✅ 4. RESTART AUTO-REFRESH
      // Wait 5 seconds before restarting to allow backend to process
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) _startAutoRefresh();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${customer.name} marked as picked up'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

    } catch (e) {
      debugPrint('❌ [PICK UP] Failed: $e');
      
      // REVERT UI ON FAILURE
      if (mounted) {
        _refreshLiveTripData(silent: true); // Force reload from server to reset UI
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to update: $e'),
            backgroundColor: Colors.red,
          ),
        );
        // Restart timer
        _startAutoRefresh();
      }
    }
  }

  // =========================================================================
  // NAVIGATE TO CUSTOMER
  // =========================================================================
  Future<void> _navigateToCustomer(double? lat, double? lng) async {
    if (lat == null || lng == null) {
      debugPrint('❌ [NAVIGATION] Missing coordinates');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Location coordinates not available'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    debugPrint('🗺️  [NAVIGATION] Opening Google Maps');
    debugPrint('   Destination: $lat, $lng');
    
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    
    try {
      final canLaunch = await canLaunchUrl(url);
      if (canLaunch) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        debugPrint('✅ [NAVIGATION] Google Maps opened');
      } else {
        debugPrint('❌ [NAVIGATION] Cannot launch Google Maps');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Could not open navigation')),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ [NAVIGATION] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Navigation error: ${e.toString()}')),
        );
      }
    }
  }

  // =========================================================================
  // FORMAT TIME
  // =========================================================================
  String _formatTime(String? timeString) {
    if (timeString == null || timeString.isEmpty) return 'N/A';
    
    try {
      // If it's ISO format (2026-01-02T03:00:00.000Z)
      if (timeString.contains('T')) {
        final dateTime = DateTime.parse(timeString);
        final hour = dateTime.hour;
        final minute = dateTime.minute.toString().padLeft(2, '0');
        final period = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        return '$displayHour:$minute $period';
      }
      // If it's already "08:30" or "8:30" format
      final parts = timeString.split(':');
      if (parts.length >= 2) {
        final hour = int.parse(parts[0]);
        final minute = parts[1].padLeft(2, '0');
        final period = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        return '$displayHour:$minute $period';
      }
      return timeString;
    } catch (e) {
      debugPrint('⚠️  [FORMAT TIME] Error formatting: $e');
      return timeString;
    }
  }

  // =========================================================================
  // BUILD UI
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Live Trip'),
          backgroundColor: Colors.blue,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_todayRoute == null || !_todayRoute!.hasRoute) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Live Trip'),
          backgroundColor: Colors.blue,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.route, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('No route assigned for today'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadTodayRoute,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final route = _todayRoute!;
    final customers = route.customers ?? [];
    final totalDistance = route.routeSummary?.totalDistance ?? 0.0;
    final vehicleNumber = route.vehicle?.registrationNumber ?? 'N/A';
    final completedCount = customers.where((c) => c.status == 'completed' || c.status == 'picked_up').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Trip'),
        backgroundColor: Colors.blue,
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _refreshLiveTripData(silent: false),
            tooltip: 'Refresh Trip Data',
          ),
          // Live tracking indicator
          if (_isTripStarted)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _trackingService.isTracking ? Colors.greenAccent : Colors.red,
                    shape: BoxShape.circle,
                    boxShadow: _trackingService.isTracking
                        ? [
                            BoxShadow(
                              color: Colors.greenAccent.withOpacity(0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            )
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          if (_isTripStarted)
            IconButton(
              icon: const Icon(Icons.check_circle),
              onPressed: _completeTrip,
              tooltip: 'Complete Trip',
            ),
        ],
      ),
      body: Column(
        children: [
          // Trip Summary Card
          Card(
            margin: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vehicleNumber,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$completedCount/${customers.length} Completed • ${totalDistance.toStringAsFixed(1)} km',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                      if (!_isTripStarted)
                        ElevatedButton.icon(
                          onPressed: _startTrip,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start Trip'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      if (_isTripStarted)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.gps_fixed, color: Colors.white, size: 16),
                              SizedBox(width: 4),
                              Text(
                                'Tracking Active',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Customer List
          // ✅ FIXED: Properly wrapped in Expanded widget with correct child parameter
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _refreshLiveTripData(silent: false),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: customers.length,
                itemBuilder: (context, index) {
                  final customer = customers[index];
                  final isPickedUp = customer.status == 'completed' || customer.status == 'picked_up';
                  final isCurrent = index == _currentCustomerIndex && !isPickedUp;
                  
                  // Get coordinates
                  final coords = customer.fromCoordinates ?? customer.toCoordinates;
                  final customerLat = coords?['lat'] ?? coords?['latitude'];
                  final customerLng = coords?['lng'] ?? coords?['longitude'];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: isPickedUp
                        ? Colors.green.shade50
                        : isCurrent
                            ? Colors.orange.shade50
                            : Colors.white,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isPickedUp
                            ? Colors.green
                            : isCurrent
                                ? Colors.orange
                                : Colors.grey,
                        child: isPickedUp
                            ? const Icon(Icons.check, color: Colors.white)
                            : Text(
                                '${customer.pickupSequence > 0 ? customer.pickupSequence : index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              customer.name,
                              style: TextStyle(
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                decoration: isPickedUp ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ),
                          // ✅ TRIP TYPE BADGE
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: customer.isLogin ? Colors.blue : Colors.orange,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              customer.tripTypeLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            customer.fromLocation ?? 'Address not available',
                            style: TextStyle(color: Colors.grey.shade700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.phone, size: 14, color: Colors.blue.shade700),
                              const SizedBox(width: 4),
                              Text(
                                customer.phone,
                                style: TextStyle(color: Colors.blue.shade700),
                              ),
                            ],
                          ),
                          if (customer.scheduledTime != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  _formatTime(customer.scheduledTime),
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      trailing: isPickedUp
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (customerLat != null && customerLng != null)
                                  IconButton(
                                    icon: const Icon(Icons.navigation, color: Colors.blue),
                                    onPressed: () => _navigateToCustomer(
                                      customerLat.toDouble(),
                                      customerLng.toDouble(),
                                    ),
                                    tooltip: 'Navigate',
                                  ),
                                ElevatedButton(
                                  onPressed: () => _markCustomerPickedUp(index),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Picked Up'),
                                ),
                              ],
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}