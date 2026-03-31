// lib/core/services/real_time_fleet_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'package:abra_fleet/app/config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Real-time Fleet Management Models
class CustomerPickupInfo {
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String customerEmail;
  final LatLng pickupLocation;
  final LatLng dropLocation;
  final String pickupAddress;
  final String dropAddress;
  final bool isLogin; // true for pickup, false for drop
  final DateTime scheduledTime;
  final String organizationId;
  final double distanceFromOffice; // Distance from office for optimization
  final CustomerStatus status;
  final DateTime? actualPickupTime;
  final DateTime? actualDropTime;
  final DateTime? estimatedArrival;
  final String? delayReason;
  final int sequenceNumber; // Optimized pickup sequence

  CustomerPickupInfo({
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.customerEmail,
    required this.pickupLocation,
    required this.dropLocation,
    required this.pickupAddress,
    required this.dropAddress,
    required this.isLogin,
    required this.scheduledTime,
    required this.organizationId,
    required this.distanceFromOffice,
    this.status = CustomerStatus.pending,
    this.actualPickupTime,
    this.actualDropTime,
    this.estimatedArrival,
    this.delayReason,
    this.sequenceNumber = 0,
  });

  factory CustomerPickupInfo.fromJson(Map<String, dynamic> json) {
    return CustomerPickupInfo(
      customerId: json['customerId'] ?? '',
      customerName: json['customerName'] ?? '',
      customerPhone: json['customerPhone'] ?? '',
      customerEmail: json['customerEmail'] ?? '',
      pickupLocation: LatLng(
        json['pickupLocation']['latitude']?.toDouble() ?? 0.0,
        json['pickupLocation']['longitude']?.toDouble() ?? 0.0,
      ),
      dropLocation: LatLng(
        json['dropLocation']['latitude']?.toDouble() ?? 0.0,
        json['dropLocation']['longitude']?.toDouble() ?? 0.0,
      ),
      pickupAddress: json['pickupAddress'] ?? '',
      dropAddress: json['dropAddress'] ?? '',
      isLogin: json['isLogin'] ?? true,
      scheduledTime: DateTime.parse(json['scheduledTime']),
      organizationId: json['organizationId'] ?? '',
      distanceFromOffice: json['distanceFromOffice']?.toDouble() ?? 0.0,
      status: CustomerStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => CustomerStatus.pending,
      ),
      actualPickupTime: json['actualPickupTime'] != null 
          ? DateTime.parse(json['actualPickupTime']) 
          : null,
      actualDropTime: json['actualDropTime'] != null 
          ? DateTime.parse(json['actualDropTime']) 
          : null,
      estimatedArrival: json['estimatedArrival'] != null 
          ? DateTime.parse(json['estimatedArrival']) 
          : null,
      delayReason: json['delayReason'],
      sequenceNumber: json['sequenceNumber'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerEmail': customerEmail,
      'pickupLocation': {
        'latitude': pickupLocation.latitude,
        'longitude': pickupLocation.longitude,
      },
      'dropLocation': {
        'latitude': dropLocation.latitude,
        'longitude': dropLocation.longitude,
      },
      'pickupAddress': pickupAddress,
      'dropAddress': dropAddress,
      'isLogin': isLogin,
      'scheduledTime': scheduledTime.toIso8601String(),
      'organizationId': organizationId,
      'distanceFromOffice': distanceFromOffice,
      'status': status.toString().split('.').last,
      'actualPickupTime': actualPickupTime?.toIso8601String(),
      'actualDropTime': actualDropTime?.toIso8601String(),
      'estimatedArrival': estimatedArrival?.toIso8601String(),
      'delayReason': delayReason,
      'sequenceNumber': sequenceNumber,
    };
  }

  CustomerPickupInfo copyWith({
    CustomerStatus? status,
    DateTime? actualPickupTime,
    DateTime? actualDropTime,
    DateTime? estimatedArrival,
    String? delayReason,
    int? sequenceNumber,
  }) {
    return CustomerPickupInfo(
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
      pickupLocation: pickupLocation,
      dropLocation: dropLocation,
      pickupAddress: pickupAddress,
      dropAddress: dropAddress,
      isLogin: isLogin,
      scheduledTime: scheduledTime,
      organizationId: organizationId,
      distanceFromOffice: distanceFromOffice,
      status: status ?? this.status,
      actualPickupTime: actualPickupTime ?? this.actualPickupTime,
      actualDropTime: actualDropTime ?? this.actualDropTime,
      estimatedArrival: estimatedArrival ?? this.estimatedArrival,
      delayReason: delayReason ?? this.delayReason,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
    );
  }
}

enum CustomerStatus {
  pending,
  notified,
  enRoute,
  arrived,
  pickedUp,
  dropped,
  noShow,
  cancelled
}

class LatLng {
  final double latitude;
  final double longitude;

  LatLng(this.latitude, this.longitude);

  @override
  String toString() => 'LatLng($latitude, $longitude)';
}

class OptimizedRoute {
  final List<CustomerPickupInfo> pickupSequence;
  final List<CustomerPickupInfo> dropSequence;
  final double totalDistance;
  final Duration estimatedDuration;
  final DateTime startTime;
  final DateTime estimatedEndTime;
  final List<RouteWaypoint> waypoints;

  OptimizedRoute({
    required this.pickupSequence,
    required this.dropSequence,
    required this.totalDistance,
    required this.estimatedDuration,
    required this.startTime,
    required this.estimatedEndTime,
    required this.waypoints,
  });
}

class RouteWaypoint {
  final LatLng location;
  final String address;
  final String customerName;
  final String action; // 'pickup' or 'drop'
  final DateTime estimatedTime;
  final Duration drivingTime;
  final double distanceFromPrevious;

  RouteWaypoint({
    required this.location,
    required this.address,
    required this.customerName,
    required this.action,
    required this.estimatedTime,
    required this.drivingTime,
    required this.distanceFromPrevious,
  });
}

class ETAUpdate {
  final String customerId;
  final DateTime originalETA;
  final DateTime updatedETA;
  final Duration delay;
  final String reason;
  final bool isDelayed;

  ETAUpdate({
    required this.customerId,
    required this.originalETA,
    required this.updatedETA,
    required this.delay,
    required this.reason,
    required this.isDelayed,
  });
}

class NotificationMessage {
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  NotificationMessage({
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.message,
    required this.type,
    required this.timestamp,
    required this.data,
  });
}

enum NotificationType {
  etaUpdate,
  delayAlert,
  arrivalNotification,
  pickupReminder,
  noShowAlert,
  routeChange
}

// Real-time Fleet Management Service
class RealTimeFleetService {
  static final RealTimeFleetService _instance = RealTimeFleetService._internal();
  factory RealTimeFleetService() => _instance;
  RealTimeFleetService._internal();

  late StreamController<List<CustomerPickupInfo>> _customersController;
  late StreamController<OptimizedRoute> _routeController;
  late StreamController<ETAUpdate> _etaController;
  late StreamController<NotificationMessage> _notificationController;

  Stream<List<CustomerPickupInfo>> get customersStream => 
      _customersController.stream;
  Stream<OptimizedRoute> get routeStream => 
      _routeController.stream;
  Stream<ETAUpdate> get etaStream => 
      _etaController.stream;
  Stream<NotificationMessage> get notificationStream => 
      _notificationController.stream;

  List<CustomerPickupInfo> _customers = [];
  OptimizedRoute? _currentRoute;
  Position? _currentDriverLocation;
  Timer? _locationUpdateTimer;
  Timer? _etaUpdateTimer;

  // Office location (configurable)
  final LatLng _officeLocation = LatLng(12.9716, 77.5946); // Bangalore default

  // Initialize the service
  Future<void> initialize() async {
    print('\n🔧 ========== REAL TIME FLEET SERVICE INITIALIZATION ==========');
    print('📅 Timestamp: ${DateTime.now().toIso8601String()}');
    
    try {
      // Initialize controllers
      print('🔄 Initializing stream controllers...');
      _customersController = StreamController<List<CustomerPickupInfo>>.broadcast();
      _routeController = StreamController<OptimizedRoute>.broadcast();
      _etaController = StreamController<ETAUpdate>.broadcast();
      _notificationController = StreamController<NotificationMessage>.broadcast();
      print('✅ Stream controllers initialized');
      
      // Load data and start tracking
      print('🔄 Loading today\'s customers...');
      await _loadTodaysCustomers();
      print('✅ Customer loading completed');
      
      print('🔄 Starting location tracking...');
      _startLocationTracking();
      print('✅ Location tracking started');
      
      print('🔄 Starting ETA updates...');
      _startETAUpdates();
      print('✅ ETA updates started');
      
      print('========== REAL TIME FLEET SERVICE INITIALIZATION COMPLETE ==========\n');
    } catch (e, stackTrace) {
      print('\n❌ ========== FLEET SERVICE INITIALIZATION ERROR ==========');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      print('========== FLEET SERVICE INITIALIZATION ERROR END ==========\n');
      rethrow;
    }
  }

  // Load today's customers assigned to the driver
  Future<void> _loadTodaysCustomers() async {
    try {
      print('\n📋 ========== LOADING TODAY\'S CUSTOMERS ==========');
      print('📅 Timestamp: ${DateTime.now().toIso8601String()}');
      
      // Get JWT token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null || token.isEmpty) {
        print('❌ No JWT token found');
        print('   User must be logged in to fetch customers');
        _addToCustomersStream([]);
        return;
      }

      // Get user data from SharedPreferences
      final userId = prefs.getString('user_id');
      final userEmail = prefs.getString('user_email');
      final userName = prefs.getString('user_name');

      print('✅ Authenticated user found:');
      print('   User ID: $userId');
      print('   Email: $userEmail');
      print('   Name: $userName');

      // ✅ FIX: Use the working API endpoint instead of the broken one
      final workingApiUrl = '${ApiConfig.baseUrl}/api/driver/route/today';
      print('🔄 Making API request to WORKING endpoint: $workingApiUrl');
      
      final response = await http.get(
        Uri.parse(workingApiUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('📡 API Response received:');
      print('   Status Code: ${response.statusCode}');
      print('   Headers: ${response.headers}');
      print('   Body Length: ${response.body.length} characters');

      if (response.statusCode == 200) {
        print('✅ Successful API response');
        
        final data = json.decode(response.body);
        print('📊 Parsed JSON data:');
        print('   Status: ${data['status']}');
        print('   Data keys: ${data['data']?.keys?.toList()}');
        
        // ✅ FIX: Parse the working API response format
        final routeData = data['data'];
        final bool hasRoute = routeData?['hasRoute'] ?? false;
        final List<dynamic> customersJson = routeData?['customers'] ?? [];
        
        print('📋 Route data:');
        print('   Has Route: $hasRoute');
        print('   Customers Length: ${customersJson.length}');
        
        if (!hasRoute || customersJson.isEmpty) {
          print('⚠️  No route or customers found in API response');
          print('   Has Route: $hasRoute');
          print('   Customers: ${customersJson.length}');
          _addToCustomersStream([]);
          return;
        }

        print('✅ Processing ${customersJson.length} customers:');
        for (int i = 0; i < customersJson.length; i++) {
          final customerJson = customersJson[i];
          print('   ${i + 1}. Customer JSON keys: ${customerJson.keys.toList()}');
          print('      Customer ID: ${customerJson['customerId']}');
          print('      Customer Name: ${customerJson['name']}');
          print('      Phone: ${customerJson['phone']}');
          print('      Trip Type: ${customerJson['tripType']}');
          print('      Status: ${customerJson['status']}');
        }
        
        // ✅ FIX: Convert working API format to real-time fleet format
        _customers = customersJson
            .map((json) {
              try {
                // Convert working API format to CustomerPickupInfo format
                return CustomerPickupInfo(
                  customerId: json['customerId'] ?? json['id'] ?? '',
                  customerName: json['name'] ?? 'Unknown Customer',
                  customerPhone: json['phone'] ?? '+91-9876543210',
                  customerEmail: json['email'] ?? 'customer@example.com',
                  pickupLocation: LatLng(
                    json['fromCoordinates']?['latitude']?.toDouble() ?? 12.9716,
                    json['fromCoordinates']?['longitude']?.toDouble() ?? 77.5946,
                  ),
                  dropLocation: LatLng(
                    json['toCoordinates']?['latitude']?.toDouble() ?? 12.9716,
                    json['toCoordinates']?['longitude']?.toDouble() ?? 77.5946,
                  ),
                  pickupAddress: json['fromLocation'] ?? 'Pickup Location',
                  dropAddress: json['toLocation'] ?? 'Drop Location',
                  isLogin: json['tripType'] == 'pickup' || json['tripTypeLabel'] == 'LOGIN',
                  scheduledTime: DateTime.now(), // Use current time as base
                  organizationId: 'ORG-001',
                  distanceFromOffice: json['distance']?.toDouble() ?? 0.0,
                  status: _parseCustomerStatus(json['status']),
                  sequenceNumber: 0, // Will be set during optimization
                );
              } catch (e) {
                print('❌ Error parsing customer JSON: $e');
                print('   JSON: $json');
                rethrow;
              }
            })
            .toList();

        print('✅ Successfully parsed ${_customers.length} customer objects');

        // Calculate distances from office and optimize route
        print('🔄 Calculating distances from office...');
        await _calculateDistancesFromOffice();
        print('✅ Distance calculations completed');
        
        print('🔄 Optimizing route...');
        await _optimizeRoute();
        print('✅ Route optimization completed');
        
        print('🔄 Adding customers to stream...');
        _addToCustomersStream(_customers);
        print('✅ Customers added to stream');
        
        print('📊 Final customer summary:');
        print('   Total customers: ${_customers.length}');
        print('   Pickup customers: ${_customers.where((c) => c.isLogin).length}');
        print('   Drop customers: ${_customers.where((c) => !c.isLogin).length}');
        
      } else {
        print('❌ API request failed:');
        print('   Status Code: ${response.statusCode}');
        print('   Response Body: ${response.body}');
        
        // Try to parse error message
        try {
          final errorData = json.decode(response.body);
          print('   Error Message: ${errorData['message']}');
          print('   Error Details: ${errorData['error']}');
        } catch (e) {
          print('   Could not parse error response as JSON');
        }
        
        _addToCustomersStream([]);
      }
      
      print('========== LOADING TODAY\'S CUSTOMERS COMPLETE ==========\n');
      
    } catch (e, stackTrace) {
      print('\n❌ ========== CUSTOMER LOADING ERROR ==========');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      print('========== CUSTOMER LOADING ERROR END ==========\n');
      
      _addToCustomersStream([]);
    }
  }

  // Helper method to parse customer status
  CustomerStatus _parseCustomerStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'assigned':
        return CustomerStatus.pending;
      case 'picked_up':
      case 'pickedup':
        return CustomerStatus.pickedUp;
      case 'dropped':
      case 'dropped_off':
        return CustomerStatus.dropped;
      case 'no_show':
      case 'noshow':
        return CustomerStatus.noShow;
      case 'cancelled':
        return CustomerStatus.cancelled;
      default:
        return CustomerStatus.pending;
    }
  }

  // Calculate distances from office for route optimization
  Future<void> _calculateDistancesFromOffice() async {
    print('\n📏 ========== CALCULATING DISTANCES FROM OFFICE ==========');
    print('Office location: ${_officeLocation.latitude}, ${_officeLocation.longitude}');
    print('Customers to process: ${_customers.length}');
    
    for (int i = 0; i < _customers.length; i++) {
      final customer = _customers[i];
      final targetLocation = customer.isLogin ? customer.pickupLocation : customer.dropLocation;
      
      final distance = _calculateDistance(
        _officeLocation,
        targetLocation,
      );
      
      print('   ${i + 1}. ${customer.customerName}');
      print('      Type: ${customer.isLogin ? "PICKUP" : "DROP"}');
      print('      Location: ${targetLocation.latitude}, ${targetLocation.longitude}');
      print('      Distance from office: ${distance.toStringAsFixed(2)} km');
      
      // Note: The customer model doesn't have a setter for distance
      // This would need to be updated in the copyWith method or model
    }
    
    print('========== DISTANCE CALCULATIONS COMPLETE ==========\n');
  }

  // Intelligent Route Optimization
  // Public method to optimize route (called from dashboard)
  Future<void> optimizeRoute() async {
    await _optimizeRoute();
  }

  // Pickup: Farthest first (to avoid backtracking)
  // Drop: Nearest to office first (to minimize total travel time)
  Future<void> _optimizeRoute() async {
    print('\n🗺️  ========== ROUTE OPTIMIZATION ==========');
    
    if (_customers.isEmpty) {
      print('⚠️  No customers to optimize route for');
      print('========== ROUTE OPTIMIZATION COMPLETE (EMPTY) ==========\n');
      return;
    }

    print('📊 Starting route optimization for ${_customers.length} customers');

    final loginCustomers = _customers.where((c) => c.isLogin).toList();
    final logoutCustomers = _customers.where((c) => !c.isLogin).toList();

    print('📋 Customer breakdown:');
    print('   Pickup customers: ${loginCustomers.length}');
    print('   Drop customers: ${logoutCustomers.length}');

    // Optimize pickup sequence: Farthest from office first
    print('🔄 Optimizing pickup sequence (farthest first)...');
    loginCustomers.sort((a, b) => b.distanceFromOffice.compareTo(a.distanceFromOffice));
    
    if (loginCustomers.isNotEmpty) {
      print('   Pickup sequence:');
      for (int i = 0; i < loginCustomers.length; i++) {
        print('     ${i + 1}. ${loginCustomers[i].customerName} (${loginCustomers[i].distanceFromOffice.toStringAsFixed(2)} km)');
      }
    }
    
    // Optimize drop sequence: Nearest to office first
    print('🔄 Optimizing drop sequence (nearest first)...');
    logoutCustomers.sort((a, b) => a.distanceFromOffice.compareTo(b.distanceFromOffice));
    
    if (logoutCustomers.isNotEmpty) {
      print('   Drop sequence:');
      for (int i = 0; i < logoutCustomers.length; i++) {
        print('     ${i + 1}. ${logoutCustomers[i].customerName} (${logoutCustomers[i].distanceFromOffice.toStringAsFixed(2)} km)');
      }
    }

    // Assign sequence numbers
    print('🔄 Assigning sequence numbers...');
    for (int i = 0; i < loginCustomers.length; i++) {
      final index = _customers.indexWhere((c) => c.customerId == loginCustomers[i].customerId);
      if (index != -1) {
        _customers[index] = _customers[index].copyWith(sequenceNumber: i + 1);
        print('   Pickup ${i + 1}: ${_customers[index].customerName}');
      }
    }

    for (int i = 0; i < logoutCustomers.length; i++) {
      final index = _customers.indexWhere((c) => c.customerId == logoutCustomers[i].customerId);
      if (index != -1) {
        _customers[index] = _customers[index].copyWith(sequenceNumber: i + 1);
        print('   Drop ${i + 1}: ${_customers[index].customerName}');
      }
    }

    // Create optimized route
    print('🔄 Creating optimized route with waypoints and ETAs...');
    await _createOptimizedRoute(loginCustomers, logoutCustomers);
    
    print('✅ Route optimization completed successfully');
    print('========== ROUTE OPTIMIZATION COMPLETE ==========\n');
  }

  // Create optimized route with waypoints and ETAs
  Future<void> _createOptimizedRoute(
    List<CustomerPickupInfo> pickups,
    List<CustomerPickupInfo> drops,
  ) async {
    final waypoints = <RouteWaypoint>[];
    final startTime = DateTime.now();
    var currentTime = startTime;
    var currentLocation = _officeLocation;
    var totalDistance = 0.0;

    // Add pickup waypoints
    for (final customer in pickups) {
      final distance = _calculateDistance(currentLocation, customer.pickupLocation);
      final drivingTime = _estimateDrivingTime(distance);
      
      currentTime = currentTime.add(drivingTime);
      
      waypoints.add(RouteWaypoint(
        location: customer.pickupLocation,
        address: customer.pickupAddress,
        customerName: customer.customerName,
        action: 'pickup',
        estimatedTime: currentTime,
        drivingTime: drivingTime,
        distanceFromPrevious: distance,
      ));

      // Update customer ETA
      final index = _customers.indexWhere((c) => c.customerId == customer.customerId);
      if (index != -1) {
        _customers[index] = _customers[index].copyWith(estimatedArrival: currentTime);
      }

      currentLocation = customer.pickupLocation;
      totalDistance += distance;
      
      // Add 2-3 minutes for pickup time
      currentTime = currentTime.add(const Duration(minutes: 2));
    }

    // Add drop waypoints
    for (final customer in drops) {
      final distance = _calculateDistance(currentLocation, customer.dropLocation);
      final drivingTime = _estimateDrivingTime(distance);
      
      currentTime = currentTime.add(drivingTime);
      
      waypoints.add(RouteWaypoint(
        location: customer.dropLocation,
        address: customer.dropAddress,
        customerName: customer.customerName,
        action: 'drop',
        estimatedTime: currentTime,
        drivingTime: drivingTime,
        distanceFromPrevious: distance,
      ));

      // Update customer ETA
      final index = _customers.indexWhere((c) => c.customerId == customer.customerId);
      if (index != -1) {
        _customers[index] = _customers[index].copyWith(estimatedArrival: currentTime);
      }

      currentLocation = customer.dropLocation;
      totalDistance += distance;
      
      // Add 1-2 minutes for drop time
      currentTime = currentTime.add(const Duration(minutes: 1));
    }

    _currentRoute = OptimizedRoute(
      pickupSequence: pickups,
      dropSequence: drops,
      totalDistance: totalDistance,
      estimatedDuration: currentTime.difference(startTime),
      startTime: startTime,
      estimatedEndTime: currentTime,
      waypoints: waypoints,
    );

    _addToRouteStream(_currentRoute!);
  }

  // Start real-time location tracking
  void _startLocationTracking() {
    _startEnhancedLocationTracking();
  }

  // Start ETA updates
  void _startETAUpdates() {
    _etaUpdateTimer = Timer.periodic(const Duration(minutes: 2), (timer) async {
      // Only recalculate ETAs if we have real customers (not demo data)
      if (_customers.isNotEmpty && _customers.any((c) => c.customerName != 'Unknown Customer')) {
        await _recalculateETAs();
      }
    });
  }

  // Update ETAs based on current driver location
  Future<void> _updateETAsBasedOnLocation() async {
    if (_currentDriverLocation == null || _currentRoute == null) return;

    final driverLocation = LatLng(
      _currentDriverLocation!.latitude,
      _currentDriverLocation!.longitude,
    );

    // Find next customer to pick up or drop
    final nextCustomer = _findNextCustomer();
    if (nextCustomer == null) return;

    final targetLocation = nextCustomer.status == CustomerStatus.pending
        ? nextCustomer.pickupLocation
        : nextCustomer.dropLocation;

    final distance = _calculateDistance(driverLocation, targetLocation);
    final drivingTime = _estimateDrivingTime(distance);
    final newETA = DateTime.now().add(drivingTime);

    // Check if there's a significant delay (more than 5 minutes)
    if (nextCustomer.estimatedArrival != null) {
      final delay = newETA.difference(nextCustomer.estimatedArrival!);
      
      if (delay.inMinutes > 5) {
        // Don't send ETA updates for unknown/demo customers
        if (nextCustomer.customerName == 'Unknown Customer') {
          print('⚠️ Skipping ETA update for demo customer: ${nextCustomer.customerName}');
          return;
        }
        
        // Send delay notification
        await _sendDelayNotification(nextCustomer, delay);
        
        _addToEtaStream(ETAUpdate(
          customerId: nextCustomer.customerId,
          originalETA: nextCustomer.estimatedArrival!,
          updatedETA: newETA,
          delay: delay,
          reason: 'Traffic conditions',
          isDelayed: true,
        ));
      }
    }

    // Update customer ETA
    final index = _customers.indexWhere((c) => c.customerId == nextCustomer.customerId);
    if (index != -1) {
      _customers[index] = _customers[index].copyWith(estimatedArrival: newETA);
      _addToCustomersStream(_customers);
    }
  }

  // Find the next customer to service
  CustomerPickupInfo? _findNextCustomer() {
    // First, find pending pickups in sequence order
    final pendingPickups = _customers
        .where((c) => c.isLogin && c.status == CustomerStatus.pending)
        .toList();
    
    if (pendingPickups.isNotEmpty) {
      pendingPickups.sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
      return pendingPickups.first;
    }

    // Then, find pending drops in sequence order
    final pendingDrops = _customers
        .where((c) => !c.isLogin && c.status == CustomerStatus.pickedUp)
        .toList();
    
    if (pendingDrops.isNotEmpty) {
      pendingDrops.sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
      return pendingDrops.first;
    }

    return null;
  }

  // Recalculate all ETAs
  Future<void> _recalculateETAs() async {
    if (_currentRoute == null) return;

    // Recalculate route based on current progress
    final remainingCustomers = _customers
        .where((c) => c.status != CustomerStatus.dropped && c.status != CustomerStatus.cancelled)
        .toList();

    if (remainingCustomers.isNotEmpty) {
      await _optimizeRoute();
    }
  }

  // Check for delays and send notifications
  Future<void> _checkForDelaysAndNotify() async {
    final now = DateTime.now();
    
    for (final customer in _customers) {
      if (customer.estimatedArrival == null) continue;
      
      final timeDiff = customer.estimatedArrival!.difference(now);
      
      // Send arrival notification 10 minutes before ETA
      if (timeDiff.inMinutes == 10 && customer.status == CustomerStatus.pending) {
        await _sendArrivalNotification(customer);
      }
      
      // Send "driver arrived" notification when within 2 minutes
      if (timeDiff.inMinutes <= 2 && customer.status == CustomerStatus.enRoute) {
        await _updateCustomerStatus(customer.customerId, CustomerStatus.arrived);
        await _sendArrivedNotification(customer);
      }
    }
  }

  // Send delay notification to customer
  Future<void> _sendDelayNotification(CustomerPickupInfo customer, Duration delay) async {
    final message = 'Hi ${customer.customerName}, your driver is running ${delay.inMinutes} minutes late due to traffic. Updated ETA: ${_formatTime(customer.estimatedArrival!.add(delay))}. Thank you for your patience.';
    
    final notification = NotificationMessage(
      customerId: customer.customerId,
      customerName: customer.customerName,
      customerPhone: customer.customerPhone,
      message: message,
      type: NotificationType.delayAlert,
      timestamp: DateTime.now(),
      data: {
        'delay_minutes': delay.inMinutes,
        'new_eta': customer.estimatedArrival!.add(delay).toIso8601String(),
      },
    );

    _addToNotificationStream(notification);
    await _sendSMSNotification(customer.customerPhone, message);
  }

  // Send arrival notification (10 minutes before)
  Future<void> _sendArrivalNotification(CustomerPickupInfo customer) async {
    final message = 'Hi ${customer.customerName}, your driver will arrive in approximately 10 minutes at ${customer.pickupAddress}. Please be ready. Driver: ${await _getDriverName()}';
    
    final notification = NotificationMessage(
      customerId: customer.customerId,
      customerName: customer.customerName,
      customerPhone: customer.customerPhone,
      message: message,
      type: NotificationType.arrivalNotification,
      timestamp: DateTime.now(),
      data: {
        'eta_minutes': 10,
        'pickup_address': customer.pickupAddress,
      },
    );

    _addToNotificationStream(notification);
    await _sendSMSNotification(customer.customerPhone, message);
    await _updateCustomerStatus(customer.customerId, CustomerStatus.notified);
  }

  // Send "driver arrived" notification
  Future<void> _sendArrivedNotification(CustomerPickupInfo customer) async {
    final message = 'Hi ${customer.customerName}, your driver has arrived at ${customer.pickupAddress}. Please come to the pickup point. Driver: ${await _getDriverName()}';
    
    final notification = NotificationMessage(
      customerId: customer.customerId,
      customerName: customer.customerName,
      customerPhone: customer.customerPhone,
      message: message,
      type: NotificationType.pickupReminder,
      timestamp: DateTime.now(),
      data: {
        'pickup_address': customer.pickupAddress,
        'action': 'driver_arrived',
      },
    );

    _addToNotificationStream(notification);
    await _sendSMSNotification(customer.customerPhone, message);
  }

  // Update customer status
  Future<void> _updateCustomerStatus(String customerId, CustomerStatus status) async {
    final index = _customers.indexWhere((c) => c.customerId == customerId);
    if (index != -1) {
      _customers[index] = _customers[index].copyWith(status: status);
      _addToCustomersStream(_customers);

      // Send status update to backend
      await _sendStatusUpdateToBackend(customerId, status);
    }
  }

  // Mark customer as picked up
  Future<void> markCustomerPickedUp(String customerId) async {
    await _updateCustomerStatus(customerId, CustomerStatus.pickedUp);
    
    final customer = _customers.firstWhere((c) => c.customerId == customerId);
    final updatedCustomer = customer.copyWith(
      actualPickupTime: DateTime.now(),
      status: CustomerStatus.pickedUp,
    );
    
    final index = _customers.indexWhere((c) => c.customerId == customerId);
    _customers[index] = updatedCustomer;
    _addToCustomersStream(_customers);

    // Recalculate route for remaining customers
    await _optimizeRoute();
  }

  // Mark customer as dropped
  Future<void> markCustomerDropped(String customerId) async {
    await _updateCustomerStatus(customerId, CustomerStatus.dropped);
    
    final customer = _customers.firstWhere((c) => c.customerId == customerId);
    final updatedCustomer = customer.copyWith(
      actualDropTime: DateTime.now(),
      status: CustomerStatus.dropped,
    );
    
    final index = _customers.indexWhere((c) => c.customerId == customerId);
    _customers[index] = updatedCustomer;
    _addToCustomersStream(_customers);

    // Send completion notification
    final message = 'Hi ${customer.customerName}, you have been safely dropped at ${customer.dropAddress}. Thank you for choosing Abra Travels!';
    await _sendSMSNotification(customer.customerPhone, message);
  }

  // Mark customer as no-show
  Future<void> markCustomerNoShow(String customerId, String reason) async {
    await _updateCustomerStatus(customerId, CustomerStatus.noShow);
    
    final customer = _customers.firstWhere((c) => c.customerId == customerId);
    final updatedCustomer = customer.copyWith(
      status: CustomerStatus.noShow,
      delayReason: reason,
    );
    
    final index = _customers.indexWhere((c) => c.customerId == customerId);
    _customers[index] = updatedCustomer;
    _addToCustomersStream(_customers);

    // Recalculate route without this customer
    await _optimizeRoute();
  }

  // Send SMS notification
  Future<void> _sendSMSNotification(String phoneNumber, String message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null || token.isEmpty) return;

      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/notifications/sms'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'phoneNumber': phoneNumber,
          'message': message,
          'type': 'driver_update',
        }),
      );
    } catch (e) {
      debugPrint('Error sending SMS: $e');
    }
  }

  // Broadcast message to all customers
  Future<void> broadcastMessage(String message, {List<String>? customerIds}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null || token.isEmpty) return;

      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/broadcast-message'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'message': message,
          'customerIds': customerIds,
          'messageType': 'broadcast',
        }),
      );

      // Send notification to UI
      final notification = NotificationMessage(
        customerId: 'broadcast',
        customerName: 'All Customers',
        customerPhone: '',
        message: 'Broadcast sent: $message',
        type: NotificationType.routeChange,
        timestamp: DateTime.now(),
        data: {'broadcast': true, 'recipientCount': customerIds?.length ?? _customers.length},
      );

      _addToNotificationStream(notification);
    } catch (e) {
      debugPrint('Error broadcasting message: $e');
    }
  }

  // Send emergency alert
  Future<void> sendEmergencyAlert({String? customMessage}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null || token.isEmpty) return;

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition();
      } catch (e) {
        debugPrint('Could not get location for emergency alert: $e');
      }

      final message = customMessage ?? 
          'EMERGENCY ALERT: Driver needs immediate assistance. ${position != null ? 'Location: https://maps.google.com/?q=${position.latitude},${position.longitude}' : 'Location unavailable'}';

      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/emergency-alert'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'message': message,
          'location': position != null ? {
            'latitude': position.latitude,
            'longitude': position.longitude,
          } : null,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      // Send notification to UI
      final notification = NotificationMessage(
        customerId: 'emergency',
        customerName: 'Emergency Alert',
        customerPhone: '',
        message: 'Emergency alert sent to support team',
        type: NotificationType.routeChange,
        timestamp: DateTime.now(),
        data: {'emergency': true, 'location': position != null},
      );

      _addToNotificationStream(notification);
    } catch (e) {
      debugPrint('Error sending emergency alert: $e');
    }
  }

  // Get real-time traffic and route updates
  Future<void> updateRouteWithTraffic() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null || token.isEmpty) return;

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/route-optimization?includeTraffic=true'),
        headers: {
          'Authorization': 'Bearer ${token}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['data']['route'] != null) {
          // Update route with traffic-optimized data
          await _processTrafficOptimizedRoute(data['data']['route']);
        }
      }
    } catch (e) {
      debugPrint('Error updating route with traffic: $e');
    }
  }

  // Process traffic-optimized route
  Future<void> _processTrafficOptimizedRoute(Map<String, dynamic> routeData) async {
    // Update ETAs based on real traffic conditions
    final waypoints = routeData['waypoints'] as List<dynamic>? ?? [];
    
    for (final waypoint in waypoints) {
      final customerId = waypoint['customerId'];
      final newETA = DateTime.parse(waypoint['estimatedTime']);
      
      final customerIndex = _customers.indexWhere((c) => c.customerId == customerId);
      if (customerIndex != -1) {
        final oldETA = _customers[customerIndex].estimatedArrival;
        
        if (oldETA != null) {
          final delay = newETA.difference(oldETA);
          
          // If delay is significant (more than 5 minutes), notify customer
          if (delay.inMinutes > 5) {
            await _sendDelayNotification(_customers[customerIndex], delay);
          }
        }
        
        _customers[customerIndex] = _customers[customerIndex].copyWith(
          estimatedArrival: newETA,
        );
      }
    }
    
    _addToCustomersStream(_customers);
  }

  // Auto-notify customers based on proximity
  Future<void> _autoNotifyCustomersOnProximity() async {
    if (_currentDriverLocation == null) return;

    final driverLocation = LatLng(
      _currentDriverLocation!.latitude,
      _currentDriverLocation!.longitude,
    );

    for (final customer in _customers) {
      if (customer.status != CustomerStatus.pending && customer.status != CustomerStatus.notified) {
        continue;
      }

      final targetLocation = customer.isLogin ? customer.pickupLocation : customer.dropLocation;
      final distance = _calculateDistance(driverLocation, targetLocation);

      // Notify when driver is within 1 km and hasn't been notified yet
      if (distance <= 1.0 && customer.status == CustomerStatus.pending) {
        await _sendProximityNotification(customer);
        await _updateCustomerStatus(customer.customerId, CustomerStatus.notified);
      }
      
      // Mark as arrived when within 100 meters
      if (distance <= 0.1 && customer.status == CustomerStatus.notified) {
        await _updateCustomerStatus(customer.customerId, CustomerStatus.arrived);
        await _sendArrivedNotification(customer);
      }
    }
  }

  // Send proximity notification (when driver is nearby)
  Future<void> _sendProximityNotification(CustomerPickupInfo customer) async {
    final message = 'Hi ${customer.customerName}, your driver is nearby and will arrive in 2-3 minutes at ${customer.isLogin ? customer.pickupAddress : customer.dropAddress}. Please be ready!';
    
    final notification = NotificationMessage(
      customerId: customer.customerId,
      customerName: customer.customerName,
      customerPhone: customer.customerPhone,
      message: message,
      type: NotificationType.arrivalNotification,
      timestamp: DateTime.now(),
      data: {
        'proximity': true,
        'distance_km': 1.0,
        'address': customer.isLogin ? customer.pickupAddress : customer.dropAddress,
      },
    );

    _addToNotificationStream(notification);
    await _sendSMSNotification(customer.customerPhone, message);
  }

  // Enhanced location tracking with geofencing and smart notifications
  void _startEnhancedLocationTracking() {
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        
        _currentDriverLocation = position;
        
        // Send location update to backend
        await _sendLocationUpdateToBackend(position);
        
        // Update ETAs based on current location
        await _updateETAsBasedOnLocation();
        
        // Auto-notify customers based on proximity
        await _autoNotifyCustomersOnProximity();
        
        // Check for delays and send notifications
        await _checkForDelaysAndNotify();
        
        // Update route with real-time traffic (every 5 minutes)
        if (DateTime.now().minute % 5 == 0) {
          await updateRouteWithTraffic();
        }
        
        // Smart customer notifications based on ETA
        await _sendSmartCustomerNotifications();
        
      } catch (e) {
        debugPrint('Error in enhanced location tracking: $e');
      }
    });
  }

  // Send location update to backend for real-time tracking
  Future<void> _sendLocationUpdateToBackend(Position position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null || token.isEmpty) return;

      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/location-update'),
        headers: {
          'Authorization': 'Bearer ${token}',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'speed': position.speed,
          'heading': position.heading,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('Error sending location update: $e');
    }
  }

  // Smart customer notifications based on ETA and context
  Future<void> _sendSmartCustomerNotifications() async {
    final now = DateTime.now();
    
    for (final customer in _customers) {
      if (customer.estimatedArrival == null) continue;
      
      final timeDiff = customer.estimatedArrival!.difference(now);
      
      // Send "driver starting" notification 15 minutes before pickup
      if (timeDiff.inMinutes == 15 && customer.status == CustomerStatus.pending) {
        await _sendDriverStartingNotification(customer);
      }
      
      // Send arrival notification 10 minutes before ETA
      if (timeDiff.inMinutes == 10 && customer.status == CustomerStatus.pending) {
        await _sendArrivalNotification(customer);
        await _updateCustomerStatus(customer.customerId, CustomerStatus.enRoute);
      }
      
      // Send "driver arrived" notification when within 2 minutes
      if (timeDiff.inMinutes <= 2 && customer.status == CustomerStatus.enRoute) {
        await _updateCustomerStatus(customer.customerId, CustomerStatus.arrived);
        await _sendArrivedNotification(customer);
      }

      // Send reminder if customer hasn't been picked up 5 minutes after arrival
      if (customer.status == CustomerStatus.arrived && 
          now.difference(customer.estimatedArrival!).inMinutes > 5) {
        await _sendPickupReminderNotification(customer);
      }
    }
  }

  // Send "driver starting" notification
  Future<void> _sendDriverStartingNotification(CustomerPickupInfo customer) async {
    final driverName = await _getDriverName();
    final message = 'Hi ${customer.customerName}, your driver $driverName is starting the route and will reach you in approximately 15 minutes. Please be ready at ${customer.pickupAddress}.';
    
    final notification = NotificationMessage(
      customerId: customer.customerId,
      customerName: customer.customerName,
      customerPhone: customer.customerPhone,
      message: message,
      type: NotificationType.routeChange,
      timestamp: DateTime.now(),
      data: {
        'notification_type': 'driver_starting',
        'eta_minutes': 15,
        'pickup_address': customer.pickupAddress,
      },
    );

    _addToNotificationStream(notification);
    await _sendSMSNotification(customer.customerPhone, message);
  }

  // Send pickup reminder notification
  Future<void> _sendPickupReminderNotification(CustomerPickupInfo customer) async {
    final message = 'Hi ${customer.customerName}, your driver is waiting at ${customer.pickupAddress}. Please come to the pickup point to avoid delays for other passengers.';
    
    final notification = NotificationMessage(
      customerId: customer.customerId,
      customerName: customer.customerName,
      customerPhone: customer.customerPhone,
      message: message,
      type: NotificationType.pickupReminder,
      timestamp: DateTime.now(),
      data: {
        'notification_type': 'pickup_reminder',
        'pickup_address': customer.pickupAddress,
      },
    );

    _addToNotificationStream(notification);
    await _sendSMSNotification(customer.customerPhone, message);
  }

  // Advanced route optimization with machine learning insights
  Future<void> optimizeRouteWithML() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null || token.isEmpty) return;

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/ml-route-optimization'),
        headers: {
          'Authorization': 'Bearer ${token}',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'currentLocation': _currentDriverLocation != null ? {
            'latitude': _currentDriverLocation!.latitude,
            'longitude': _currentDriverLocation!.longitude,
          } : null,
          'customers': _customers.map((c) => c.toJson()).toList(),
          'timeOfDay': DateTime.now().hour,
          'dayOfWeek': DateTime.now().weekday,
          'weatherConditions': await _getWeatherConditions(),
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['data']['optimizedRoute'] != null) {
          await _processMLOptimizedRoute(data['data']['optimizedRoute']);
        }
      }
    } catch (e) {
      debugPrint('Error optimizing route with ML: $e');
    }
  }

  // Process ML-optimized route
  Future<void> _processMLOptimizedRoute(Map<String, dynamic> routeData) async {
    // Update customer sequence based on ML optimization
    final waypoints = routeData['waypoints'] as List<dynamic>? ?? [];
    
    for (final waypoint in waypoints) {
      final customerId = waypoint['customerId'];
      final newSequence = waypoint['sequence'];
      final newETA = DateTime.parse(waypoint['estimatedTime']);
      
      final customerIndex = _customers.indexWhere((c) => c.customerId == customerId);
      if (customerIndex != -1) {
        _customers[customerIndex] = _customers[customerIndex].copyWith(
          sequenceNumber: newSequence,
          estimatedArrival: newETA,
        );
      }
    }
    
    _addToCustomersStream(_customers);
    
    // Notify about route optimization
    final notification = NotificationMessage(
      customerId: 'system',
      customerName: 'System',
      customerPhone: '',
      message: 'Route optimized using AI for better efficiency',
      type: NotificationType.routeChange,
      timestamp: DateTime.now(),
      data: {'ml_optimized': true, 'efficiency_gain': routeData['efficiencyGain']},
    );

    _addToNotificationStream(notification);
  }

  // Get weather conditions for route optimization
  Future<Map<String, dynamic>> _getWeatherConditions() async {
    try {
      // In production, integrate with weather API
      // For now, return simulated data
      return {
        'condition': 'clear',
        'temperature': 28,
        'humidity': 65,
        'windSpeed': 10,
        'visibility': 'good'
      };
    } catch (e) {
      return {'condition': 'unknown'};
    }
  }

  // Predictive ETA calculation using historical data
  Future<void> calculatePredictiveETAs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null || token.isEmpty) return;

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/predictive-eta'),
        headers: {
          'Authorization': 'Bearer ${token}',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'driverLocation': _currentDriverLocation != null ? {
            'latitude': _currentDriverLocation!.latitude,
            'longitude': _currentDriverLocation!.longitude,
          } : null,
          'customers': _customers.map((c) => c.toJson()).toList(),
          'historicalData': true,
          'trafficPatterns': true,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final predictions = data['data']['predictions'] as List<dynamic>? ?? [];
        
        for (final prediction in predictions) {
          final customerId = prediction['customerId'];
          final predictedETA = DateTime.parse(prediction['predictedETA']);
          final confidence = prediction['confidence'];
          
          final customerIndex = _customers.indexWhere((c) => c.customerId == customerId);
          if (customerIndex != -1) {
            _customers[customerIndex] = _customers[customerIndex].copyWith(
              estimatedArrival: predictedETA,
            );
          }
        }
        
        _addToCustomersStream(_customers);
      }
    } catch (e) {
      debugPrint('Error calculating predictive ETAs: $e');
    }
  }

  // Send batch notifications to multiple customers
  Future<void> sendBatchNotifications(List<String> customerIds, String message, {String? messageType}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null || token.isEmpty) return;

      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/batch-notifications'),
        headers: {
          'Authorization': 'Bearer ${token}',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'customerIds': customerIds,
          'message': message,
          'messageType': messageType ?? 'batch_notification',
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      // Send notification to UI
      final notification = NotificationMessage(
        customerId: 'batch',
        customerName: 'Batch Notification',
        customerPhone: '',
        message: 'Batch notification sent to ${customerIds.length} customers',
        type: NotificationType.routeChange,
        timestamp: DateTime.now(),
        data: {'batch': true, 'recipientCount': customerIds.length},
      );

      _addToNotificationStream(notification);
    } catch (e) {
      debugPrint('Error sending batch notifications: $e');
    }
  }

  // Get real-time analytics
  Future<Map<String, dynamic>> getRealTimeAnalytics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null || token.isEmpty) return {};

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/real-time-analytics'),
        headers: {
          'Authorization': 'Bearer ${token}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['data'] ?? {};
      }
    } catch (e) {
      debugPrint('Error getting real-time analytics: $e');
    }
    return {};
  }

  // Smart delay prediction
  Future<bool> predictDelayRisk() async {
    if (_currentDriverLocation == null || _currentRoute == null) return false;

    try {
      final nextCustomer = _findNextCustomer();
      if (nextCustomer == null) return false;

      final driverLocation = LatLng(
        _currentDriverLocation!.latitude,
        _currentDriverLocation!.longitude,
      );

      final targetLocation = nextCustomer.status == CustomerStatus.pending
          ? nextCustomer.pickupLocation
          : nextCustomer.dropLocation;

      final distance = _calculateDistance(driverLocation, targetLocation);
      final estimatedTime = _estimateDrivingTime(distance);
      
      // Check if we're likely to be late
      if (nextCustomer.estimatedArrival != null) {
        final timeToETA = nextCustomer.estimatedArrival!.difference(DateTime.now());
        
        // If estimated driving time is more than time to ETA, we might be late
        if (estimatedTime.inMinutes > timeToETA.inMinutes) {
          // Send proactive delay notification
          await _sendProactiveDelayNotification(nextCustomer, estimatedTime.inMinutes - timeToETA.inMinutes);
          return true;
        }
      }
    } catch (e) {
      debugPrint('Error predicting delay risk: $e');
    }
    
    return false;
  }

  // Send proactive delay notification
  Future<void> _sendProactiveDelayNotification(CustomerPickupInfo customer, int delayMinutes) async {
    final message = 'Hi ${customer.customerName}, due to current traffic conditions, your driver may be ${delayMinutes} minutes late. We apologize for the inconvenience and appreciate your patience.';
    
    final notification = NotificationMessage(
      customerId: customer.customerId,
      customerName: customer.customerName,
      customerPhone: customer.customerPhone,
      message: message,
      type: NotificationType.delayAlert,
      timestamp: DateTime.now(),
      data: {
        'proactive_delay': true,
        'predicted_delay_minutes': delayMinutes,
      },
    );

    _addToNotificationStream(notification);
    await _sendSMSNotification(customer.customerPhone, message);
  }

  // Send status update to backend
  Future<void> _sendStatusUpdateToBackend(String customerId, CustomerStatus status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null || token.isEmpty) return;

      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/customer-status'),
        headers: {
          'Authorization': 'Bearer ${token}',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'customerId': customerId,
          'status': status.toString().split('.').last,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('Error updating status: $e');
    }
  }

  // Utility methods
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371; // Earth's radius in kilometers
    
    final double lat1Rad = point1.latitude * (pi / 180);
    final double lat2Rad = point2.latitude * (pi / 180);
    final double deltaLatRad = (point2.latitude - point1.latitude) * (pi / 180);
    final double deltaLngRad = (point2.longitude - point1.longitude) * (pi / 180);

    final double a = sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(deltaLngRad / 2) * sin(deltaLngRad / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  Duration _estimateDrivingTime(double distanceKm) {
    // Estimate based on average city speed (25 km/h including traffic)
    final hours = distanceKm / 25.0;
    return Duration(minutes: (hours * 60).round());
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<String> _getDriverName() async {
    // JWT token is retrieved when needed from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    return 'Driver';
  }

  // Get current route information
  OptimizedRoute? getCurrentRoute() => _currentRoute;

  // Get customers list
  List<CustomerPickupInfo> getCustomers() => List.unmodifiable(_customers);

  // Get next customer in sequence
  CustomerPickupInfo? getNextCustomer() => _findNextCustomer();

  // Get driver's current location
  Position? getCurrentLocation() => _currentDriverLocation;

  // Check if driver is running late
  bool isRunningLate() {
    final nextCustomer = _findNextCustomer();
    if (nextCustomer?.estimatedArrival == null) return false;
    
    return DateTime.now().isAfter(nextCustomer!.estimatedArrival!);
  }

  // Get estimated delay for next customer
  Duration? getEstimatedDelay() {
    final nextCustomer = _findNextCustomer();
    if (nextCustomer?.estimatedArrival == null) return null;
    
    final now = DateTime.now();
    if (now.isAfter(nextCustomer!.estimatedArrival!)) {
      return now.difference(nextCustomer.estimatedArrival!);
    }
    return null;
  }

  // Get completion percentage
  double getCompletionPercentage() {
    if (_customers.isEmpty) return 0.0;
    
    final completedCount = _customers.where((c) => 
      c.status == CustomerStatus.dropped || 
      c.status == CustomerStatus.cancelled
    ).length;
    
    return completedCount / _customers.length;
  }

  // Get active customers count
  int getActiveCustomersCount() {
    return _customers.where((c) => 
      c.status != CustomerStatus.dropped && 
      c.status != CustomerStatus.cancelled &&
      c.status != CustomerStatus.noShow
    ).length;
  }

  // Force refresh all data
  Future<void> forceRefresh() async {
    await _loadTodaysCustomers();
  }

  // Helper methods for safe controller access
  void _addToCustomersStream(List<CustomerPickupInfo> customers) {
    print('\n📡 ========== ADDING CUSTOMERS TO STREAM ==========');
    print('📊 Adding ${customers.length} customers to stream');
    
    if (customers.isEmpty) {
      print('⚠️  Empty customer list being sent to stream');
      print('   This will result in "No customers" UI state');
    } else {
      print('✅ Customer data being sent to UI:');
      for (int i = 0; i < customers.length; i++) {
        final customer = customers[i];
        print('   ${i + 1}. ${customer.customerName} (${customer.isLogin ? "PICKUP" : "DROP"})');
      }
    }
    
    try {
      _customersController.add(customers);
      print('✅ Successfully added customers to stream');
    } catch (e) {
      print('❌ Error adding customers to stream: $e');
    }
    
    print('========== CUSTOMERS STREAM UPDATE SENT ==========\n');
  }

  void _addToRouteStream(OptimizedRoute route) {
    print('\n🗺️  ========== ADDING ROUTE TO STREAM ==========');
    print('📊 Route details:');
    print('   Pickup sequence: ${route.pickupSequence.length}');
    print('   Drop sequence: ${route.dropSequence.length}');
    print('   Total distance: ${route.totalDistance.toStringAsFixed(2)} km');
    print('   Estimated duration: ${route.estimatedDuration.inMinutes} minutes');
    
    try {
      _routeController.add(route);
      print('✅ Successfully added route to stream');
    } catch (e) {
      print('❌ Error adding route to stream: $e');
    }
    
    print('========== ROUTE STREAM UPDATE SENT ==========\n');
  }

  void _addToEtaStream(ETAUpdate eta) {
    print('\n⏰ ========== ADDING ETA UPDATE TO STREAM ==========');
    print('📊 ETA update for customer: ${eta.customerId}');
    print('   Delay: ${eta.delay.inMinutes} minutes');
    print('   Reason: ${eta.reason}');
    
    try {
      _etaController.add(eta);
      print('✅ Successfully added ETA update to stream');
    } catch (e) {
      print('❌ Error adding ETA update to stream: $e');
    }
    
    print('========== ETA STREAM UPDATE SENT ==========\n');
  }

  void _addToNotificationStream(NotificationMessage notification) {
    print('\n🔔 ========== ADDING NOTIFICATION TO STREAM ==========');
    print('📊 Notification for: ${notification.customerName}');
    print('   Message: ${notification.message}');
    print('   Type: ${notification.type}');
    
    try {
      _notificationController.add(notification);
      print('✅ Successfully added notification to stream');
    } catch (e) {
      print('❌ Error adding notification to stream: $e');
    }
    
    print('========== NOTIFICATION STREAM UPDATE SENT ==========\n');
  }

  // Dispose resources
  void dispose() {
    _locationUpdateTimer?.cancel();
    _etaUpdateTimer?.cancel();
    _customersController.close();
    _routeController.close();
    _etaController.close();
    _notificationController.close();
  }
}