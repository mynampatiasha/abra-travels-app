// lib/screens/driver_trip_dashboard.dart
// ============================================================================
// DRIVER TRIP DASHBOARD - Complete with Real API Integration
// ============================================================================
// ✅ FULL MERGE: Original code + WhatsApp features
// ✅ WhatsApp button on EACH stop card (per customer)
// ✅ "Message All Customers" bulk button in in-progress section
// ✅ Template picker bottom sheet (8 templates + custom)
// ✅ Fixed call button (works mobile + web)
// ✅ Full support dialog with copy-to-clipboard, responsive layout
// ✅ All original print() debug logs preserved
// ✅ All original helper methods preserved
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'dart:io' if (dart.library.html) 'dart:html' as platform;
import 'dart:async';

import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/auth/presentation/screens/welcome_screen.dart';
import 'package:abra_fleet/core/services/driver_trip_service.dart';
import 'package:abra_fleet/core/services/gps_monitoring_service.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/features/driver/dashboard/presentation/screens/vehicle_checklist.dart';

import 'trip_map_navigation_screen.dart';
import 'vehicle_checklist.dart';

const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kAccentColor = Color(0xFF1976D2);
const Color kDangerColor = Color(0xFFDC2626);
const Color kWarningColor = Color(0xFFF59E0B);
const Color kSuccessColor = Color(0xFF10B981);
const Color kWhatsAppColor = Color(0xFF25D366);

// ============================================================================
// WHATSAPP MESSAGE TEMPLATES
// ============================================================================
class WhatsAppTemplates {
  static List<Map<String, String>> get templates => [
        {
          'label': '🕐 Running Late',
          'message':
              'Hello, I am your Abra Travels driver. I am running a bit late and will arrive at your pickup location shortly. Sorry for the inconvenience!',
        },
        {
          'label': '🚗 Arrived at Pickup',
          'message':
              'Hello! I am your Abra Travels driver. I have arrived at your pickup location. Please come down, I am waiting for you.',
        },
        {
          'label': '⏱️ 5 Minutes Away',
          'message':
              'Hello, I am your Abra Travels driver. I will be reaching your pickup location in approximately 5 minutes. Please be ready!',
        },
        {
          'label': '⏱️ 10 Minutes Away',
          'message':
              'Hello, I am your Abra Travels driver. I will be reaching your pickup location in approximately 10 minutes. Please be ready!',
        },
        {
          'label': '🚦 Stuck in Traffic',
          'message':
              'Hello, I am your Abra Travels driver. I am currently stuck in traffic. I will reach your pickup location as soon as possible. Thank you for your patience!',
        },
        {
          'label': '📍 On My Way',
          'message':
              'Hello! I am your Abra Travels driver. I am on the way to your pickup location. Please stay ready. Contact me if you need any help.',
        },
        {
          'label': '✅ Trip Started',
          'message':
              'Hello! Your Abra Travels trip has started. I am on my way to pick you up. See you soon!',
        },
        {
          'label': '🔁 Wrong Location?',
          'message':
              'Hello! I am your Abra Travels driver. I am at the pickup location mentioned in the app. If you are at a different spot, please let me know.',
        },
      ];
}

// ============================================================================
// MAIN WIDGET
// ============================================================================
class DriverTripDashboard extends StatefulWidget {
  final VoidCallback? onNavigateToNotifications;
  final VoidCallback? onNavigateToReportTab;

  const DriverTripDashboard({
    super.key,
    this.onNavigateToNotifications,
    this.onNavigateToReportTab,
  });

  @override
  State<DriverTripDashboard> createState() => _DriverTripDashboardState();
}

class _DriverTripDashboardState extends State<DriverTripDashboard> {
  // ========================================================================
  // STATE VARIABLES
  // ========================================================================
  List<Map<String, dynamic>> trips = [];
  bool isLoading = true;
  String? errorMessage;

  int currentTripIndex = 0;
  TripStatus tripStatus = TripStatus.assigned;
  int currentStopIndex = 0;

  final TextEditingController startOdometerController = TextEditingController();
  final TextEditingController endOdometerController = TextEditingController();
  XFile? startOdometerPhoto;
  XFile? endOdometerPhoto;

  Map<String, PassengerStatus> passengerStatusMap = {};

  Timer? _locationTimer;
  Position? _currentPosition;
  StreamSubscription<ServiceStatus>? _gpsStatusSubscription;
  bool _isGPSWarningShown = false;

  final ImagePicker _imagePicker = ImagePicker();
  final DriverTripService _tripService = DriverTripService();
  final GPSMonitoringService _gpsMonitoringService = GPSMonitoringService();

  // ✅ ScrollController for auto-scrolling to next stop
  final ScrollController _routeScrollController = ScrollController();

  // ========================================================================
  // HELPER: Clean tripGroupId (remove date suffix)
  // ========================================================================
  String _cleanTripGroupId(String tripGroupId) {
    final parts = tripGroupId.split('-');
    if (parts.length < 2) return tripGroupId;

    final lastPart = parts.last;
    if (RegExp(r'^\d{2}$').hasMatch(lastPart) && parts.length >= 4) {
      final monthPart = parts[parts.length - 2];
      final yearPart = parts[parts.length - 3];

      if (RegExp(r'^\d{2}$').hasMatch(monthPart) &&
          RegExp(r'^\d{4}$').hasMatch(yearPart)) {
        print(
            '🧹 Cleaning tripGroupId: $tripGroupId → ${parts.sublist(0, parts.length - 3).join('-')}');
        return parts.sublist(0, parts.length - 3).join('-');
      }
    }

    return tripGroupId;
  }

  // ========================================================================
  // LIFECYCLE METHODS
  // ========================================================================

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    startOdometerController.dispose();
    endOdometerController.dispose();
    _locationTimer?.cancel();
    _gpsStatusSubscription?.cancel();
    _routeScrollController.dispose();
    _gpsMonitoringService.dispose();
    super.dispose();
  }

  // ========================================================================
  // INITIALIZATION
  // ========================================================================

  Future<void> _initializeApp() async {
    print('\n' + '🚀' * 40);
    print('DRIVER DASHBOARD INITIALIZATION');
    print('🚀' * 40);

    await _requestPermissions();
    await _loadTrips();
    await _checkDailyChecklist();

    print('✅ Dashboard initialized');
    print('🚀' * 40 + '\n');
  }

  Future<void> _requestPermissions() async {
    print('📍 Requesting location permissions...');

    final locationStatus = await ph.Permission.location.request();
    if (locationStatus.isGranted) {
      print('✅ Location permission granted');
      await _getCurrentLocation();
    } else {
      print('❌ Location permission denied');
      _showSnackBar(
          'Location permission is required for GPS tracking', kDangerColor);
    }

    final cameraStatus = await ph.Permission.camera.request();
    if (cameraStatus.isGranted) {
      print('✅ Camera permission granted');
    } else {
      print('❌ Camera permission denied');
    }
  }

  Future<void> _checkDailyChecklist() async {
    final checklistApi = ChecklistApiService();

    final vehicleNumber = trips.isNotEmpty
        ? (trips[currentTripIndex]['trip'] as Trip).vehicleNumber
        : 'Unknown';

    final alreadyDone = await checklistApi.isTodayChecklistDone(vehicleNumber);
    if (alreadyDone) return;
    if (!mounted) return;

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VehicleChecklistDialog(vehicleNumber: vehicleNumber),
    );
  }

  Future<void> _getCurrentLocation() async {
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      print(
          '📍 Current location: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
    } catch (e) {
      print('❌ Failed to get location: $e');
    }
  }

  // ========================================================================
  // API DATA LOADING
  // ========================================================================

  Future<void> _loadTrips() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      print('📋 Loading trips from API...');

      final fetchedTrips = await _tripService.getTodaysTrips();

      setState(() {
        trips = _transformTripsToLocalFormat(fetchedTrips);
        isLoading = false;

        if (trips.isNotEmpty) {
          currentTripIndex = _getCurrentTripIndex();
          tripStatus = _getTripStatus(trips[currentTripIndex]);
          currentStopIndex = _getCurrentStopIndexFromBackend();

          print('📍 Current trip index: $currentTripIndex');
          print('📊 Trip status: $tripStatus');
          print('🎯 Current stop index: $currentStopIndex');
        }
      });

      print('✅ Loaded ${trips.length} trip(s)');

      if (tripStatus == TripStatus.inProgress) {
        _startLocationTracking();
      }
    } catch (e) {
      print('❌ Error loading trips: $e');
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
      _showSnackBar('Failed to load trips: $e', kDangerColor);
    }
  }

  // ========================================================================
  // DATA TRANSFORMATION
  // ========================================================================

  List<Map<String, dynamic>> _transformTripsToLocalFormat(
      List<Map<String, dynamic>> apiTrips) {
    print('\n' + '🔄' * 40);
    print('TRANSFORMING API TRIPS TO LOCAL FORMAT');
    print('🔄' * 40);

    return apiTrips.map((apiTrip) {
      print('\n📦 Processing API Trip:');
      print('   Trip Group ID: ${apiTrip['tripGroupId']}');
      print('   Status: ${apiTrip['status']}');
      print('   Start Time: ${apiTrip['startTime']}');
      print('   End Time: ${apiTrip['endTime']}');
      print('   Total Distance: ${apiTrip['totalDistance']}');
      print('   Total Stops: ${apiTrip['totalStops']}');

      final stopsData = apiTrip['stops'] as List? ?? [];
      print('   📊 Raw stops array length: ${stopsData.length}');

      if (stopsData.isEmpty) {
        print('   ⚠️ WARNING: No stops found in API response!');
      }

      final stopsList = stopsData.map<TripStop>((stopData) {
        final stop = stopData as Map<String, dynamic>;
        final stopType = stop['type']?.toString() ?? 'pickup';

        print('   \n   📍 Processing stop:');
        print('      Type: $stopType');
        print('      Stop ID: ${stop['stopId']}');

        List<Passenger> passengers = [];

        if (stopType == 'pickup' && stop['customer'] != null) {
          final customer = stop['customer'] as Map<String, dynamic>;
          final customerName = customer['name']?.toString() ?? 'Unknown Customer';
          final customerPhone = customer['phone']?.toString() ?? '';

          print('      Customer: $customerName');
          print('      Phone: $customerPhone');

          passengers.add(Passenger(
            id: stop['stopId']?.toString() ?? stop['rosterId']?.toString() ?? '',
            name: customerName,
            phone: customerPhone,
          ));
        } else if (stopType == 'drop' && stop['passengers'] != null) {
          final passengerList = stop['passengers'] as List;
          print('      Passengers: ${passengerList.length}');

          for (int i = 0; i < passengerList.length; i++) {
            final passengerName = passengerList[i].toString();
            print('         - $passengerName');
            passengers.add(Passenger(
              id: 'passenger_$i',
              name: passengerName,
              phone: '',
            ));
          }
        }

        final location = stop['location'] as Map<String, dynamic>?;
        final address = location?['address']?.toString() ?? 'Unknown Location';
        print('      Address: $address');

        double latitude = 0.0;
        double longitude = 0.0;

        if (location != null && location['coordinates'] != null) {
          final coords = location['coordinates'];

          if (coords is Map) {
            latitude = (coords['latitude'] ?? 0).toDouble();
            longitude = (coords['longitude'] ?? 0).toDouble();
          } else if (coords is List && coords.length >= 2) {
            longitude = (coords[0] ?? 0).toDouble();
            latitude = (coords[1] ?? 0).toDouble();
          }
        }

        print('      Coordinates: ($latitude, $longitude)');

        final estimatedTime = stop['estimatedTime']?.toString() ??
            stop['pickupTime']?.toString() ??
            '00:00';
        print('      Estimated Time: $estimatedTime');

        final distanceToOffice = (stop['distanceToOffice'] ?? 0.0).toDouble();
        print(
            '      Distance to Office: ${distanceToOffice.toStringAsFixed(1)} km');

        return TripStop(
          id: stop['stopId']?.toString() ?? stop['_id']?.toString() ?? '',
          type: stopType == 'pickup' ? StopType.pickup : StopType.drop,
          location: address,
          latitude: latitude,
          longitude: longitude,
          estimatedTime: estimatedTime,
          status: _parseStopStatus(stop['status']),
          passengers: passengers,
          distanceToOffice: distanceToOffice,
        );
      }).toList();

      print('\n   ✅ Total stops created: ${stopsList.length}');

      int totalPassengers = 0;
      for (var stop in stopsList) {
        if (stop.type == StopType.pickup) totalPassengers += stop.passengers.length;
      }

      print('   👥 Total passengers: $totalPassengers');

      String routeName = _buildRouteName(stopsList);
      print('   🛣️  Route: $routeName');

      String scheduledStart = '00:00';
      String scheduledEnd = '00:00';

      if (apiTrip['startTime'] != null) {
        scheduledStart = apiTrip['startTime'].toString();
      } else if (apiTrip['stops'] != null &&
          (apiTrip['stops'] as List).isNotEmpty) {
        final firstStop = (apiTrip['stops'] as List).first;
        scheduledStart = firstStop['estimatedTime']?.toString() ??
            firstStop['time']?.toString() ??
            '00:00';
      }

      if (apiTrip['endTime'] != null) {
        scheduledEnd = apiTrip['endTime'].toString();
      } else if (apiTrip['stops'] != null &&
          (apiTrip['stops'] as List).isNotEmpty) {
        final stops = apiTrip['stops'] as List;
        final lastStop = stops.last;
        scheduledEnd = lastStop['estimatedTime']?.toString() ??
            lastStop['time']?.toString() ??
            '00:00';
      }

      final totalDistance = (apiTrip['totalDistance'] ?? 0.0).toDouble();

      print(
          '   ⏰ Times: $scheduledStart - $scheduledEnd (extracted from ${apiTrip['startTime'] != null ? 'direct fields' : 'stops array'})');
      print('   📏 Distance: ${totalDistance.toStringAsFixed(1)} km');

      final trip = Trip(
        id: apiTrip['tripGroupId']?.toString() ??
            apiTrip['_id']?.toString() ??
            '',
        customerNumber: apiTrip['customerNumber']?.toString() ?? '',
        customerName: apiTrip['customerName']?.toString() ?? 'Multiple Customers',
        tripNumber: apiTrip['tripNumber'] ?? 1,
        status: _parseTripStatus(apiTrip['status']),
        scheduledStart: scheduledStart,
        scheduledEnd: scheduledEnd,
        vehicleNumber: apiTrip['vehicleNumber']?.toString() ?? 'Unknown',
        route: routeName,
        totalPassengers: totalPassengers,
        distance: '${totalDistance.toStringAsFixed(1)} km',
        stops: stopsList,
        actualDistance: (apiTrip['actualDistance'] ?? 0.0).toDouble(),
      );

      print('\n   ✅ TRIP CREATED SUCCESSFULLY');
      print('   ═══════════════════════════════════════');

      return {'trip': trip, 'apiData': apiTrip};
    }).toList();
  }

  String _buildRouteName(List<TripStop> stops) {
    final pickupStops = stops.where((s) => s.type == StopType.pickup).toList();

    if (pickupStops.isEmpty) return 'Route';

    if (pickupStops.length == 1) {
      final customerName = pickupStops.first.passengers.isNotEmpty
          ? pickupStops.first.passengers.first.name
          : 'Pickup';
      return '$customerName → Office';
    } else {
      return '${pickupStops.length} Pickups → Office';
    }
  }

  int _getCurrentTripIndex() {
    for (int i = 0; i < trips.length; i++) {
      final trip = trips[i]['trip'] as Trip;
      if (trip.status != TripStatus.completed) return i;
    }
    return trips.isNotEmpty ? trips.length - 1 : 0;
  }

  int _getCurrentStopIndexFromBackend() {
    if (trips.isEmpty || currentTripIndex >= trips.length) return 0;

    final trip = trips[currentTripIndex]['trip'] as Trip;

    for (int i = 0; i < trip.stops.length; i++) {
      if (trip.stops[i].status != StopStatus.completed) return i;
    }

    return trip.stops.isNotEmpty ? trip.stops.length - 1 : 0;
  }

  Map<String, int> _getTripStatusCounts() {
    int completed = 0;
    int current = 0;
    int upcoming = 0;

    for (var tripData in trips) {
      final trip = tripData['trip'] as Trip;

      switch (trip.status) {
        case TripStatus.completed:
          completed++;
          break;
        case TripStatus.inProgress:
          current++;
          break;
        case TripStatus.assigned:
          upcoming++;
          break;
      }
    }

    return {
      'completed': completed,
      'current': current,
      'upcoming': upcoming,
    };
  }

  double _extractLatitude(dynamic coords) {
    if (coords == null) return 0.0;
    if (coords is Map) {
      final lat = coords['latitude'] ?? coords[1];
      return (lat is num) ? lat.toDouble() : 0.0;
    }
    if (coords is List && coords.length >= 2) {
      return (coords[1] is num) ? coords[1].toDouble() : 0.0;
    }
    return 0.0;
  }

  double _extractLongitude(dynamic coords) {
    if (coords == null) return 0.0;
    if (coords is Map) {
      final lng = coords['longitude'] ?? coords[0];
      return (lng is num) ? lng.toDouble() : 0.0;
    }
    if (coords is List && coords.length >= 2) {
      return (coords[0] is num) ? coords[0].toDouble() : 0.0;
    }
    return 0.0;
  }

  List<Passenger> _extractPassengers(Map<String, dynamic> stop) {
    final List<Passenger> passengers = [];

    if (stop['type'] == 'pickup' && stop['customer'] != null) {
      final customer = stop['customer'];
      passengers.add(Passenger(
        id: stop['stopId'] ?? stop['rosterId'] ?? '',
        name: customer['name'] ?? 'Unknown',
        phone: customer['phone'] ?? '',
      ));
    } else if (stop['type'] == 'drop' && stop['passengers'] != null) {
      final passengerNames = stop['passengers'] as List;
      for (int i = 0; i < passengerNames.length; i++) {
        passengers.add(Passenger(
          id: 'passenger_$i',
          name: passengerNames[i],
          phone: '',
        ));
      }
    }

    return passengers;
  }

  StopStatus _parseStopStatus(dynamic status) {
    if (status == null) return StopStatus.pending;
    final statusStr = status.toString().toLowerCase();
    if (statusStr.contains('progress') || statusStr.contains('arrived')) {
      return StopStatus.arrived;
    }
    if (statusStr.contains('complete')) return StopStatus.completed;
    return StopStatus.pending;
  }

  TripStatus _parseTripStatus(dynamic status) {
    if (status == null) return TripStatus.assigned;
    final statusStr = status.toString().toLowerCase();
    if (statusStr.contains('start') || statusStr.contains('progress')) {
      return TripStatus.inProgress;
    }
    if (statusStr.contains('complete')) return TripStatus.completed;
    return TripStatus.assigned;
  }

  TripStatus _getTripStatus(Map<String, dynamic> tripData) {
    final trip = tripData['trip'] as Trip;
    return trip.status;
  }

  String _extractScheduledStart(List<TripStop> stops) {
    if (stops.isEmpty) return '00:00';
    return stops.first.estimatedTime ?? '00:00';
  }

  String _extractScheduledEnd(List<TripStop> stops) {
    if (stops.isEmpty) return '00:00';
    return stops.last.estimatedTime ?? '00:00';
  }

  Trip get currentTrip => trips[currentTripIndex]['trip'];
  Map<String, dynamic> get currentTripApiData => trips[currentTripIndex]['apiData'];

  // ========================================================================
  // GPS TRACKING
  // ========================================================================

  void _startLocationTracking() {
    print('📍 Starting GPS tracking...');

    // ✅ Start monitoring GPS status
    _startGPSMonitoring();

    _locationTimer?.cancel();
    _locationTimer =
        Timer.periodic(const Duration(seconds: 60), (timer) async {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        _currentPosition = position;

        final rawTripGroupId = currentTripApiData['tripGroupId'];
        final tripGroupId = _cleanTripGroupId(rawTripGroupId);
        await _tripService.updateLocation(
          tripGroupId: tripGroupId,
          latitude: position.latitude,
          longitude: position.longitude,
          speed: position.speed,
          heading: position.heading,
        );

        print(
            '📍 Location updated: ${position.latitude}, ${position.longitude}');
      } catch (e) {
        print('❌ Location update failed: $e');
      }
    });
  }

  void _stopLocationTracking() {
    print('🛑 Stopping GPS tracking...');
    _locationTimer?.cancel();
    _locationTimer = null;
    
    // ✅ Stop monitoring GPS status
    _stopGPSMonitoring();
  }

  // ========================================================================
  // ✅ NEW: GPS STATUS MONITORING
  // ========================================================================
  
  void _startGPSMonitoring() {
    print('👁️ Starting GPS status monitoring...');
    
    _gpsStatusSubscription?.cancel();
    _gpsStatusSubscription = _gpsMonitoringService.getServiceStatusStream().listen((status) {
      print('📡 GPS Status changed: $status');
      
      if (status == ServiceStatus.disabled) {
        _handleGPSDisabled();
      } else if (status == ServiceStatus.enabled) {
        _handleGPSEnabled();
      }
    });
  }
  
  void _stopGPSMonitoring() {
    print('🛑 Stopping GPS status monitoring...');
    _gpsStatusSubscription?.cancel();
    _gpsStatusSubscription = null;
    _isGPSWarningShown = false;
  }
  
  Future<void> _handleGPSDisabled() async {
    print('⚠️ GPS DISABLED DETECTED!');
    
    if (_isGPSWarningShown) return; // Don't show multiple dialogs
    _isGPSWarningShown = true;
    
    // Send alert to backend
    try {
      final rawTripGroupId = currentTripApiData['tripGroupId'];
      final tripGroupId = _cleanTripGroupId(rawTripGroupId);
      
      await _tripService.reportGPSDisabled(tripGroupId: tripGroupId);
      print('✅ GPS disabled alert sent to backend');
    } catch (e) {
      print('❌ Failed to send GPS alert: $e');
    }
    
    // Show non-dismissible warning dialog
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false, // Cannot dismiss by tapping outside
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false, // Cannot dismiss with back button
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kDangerColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.location_off, color: kDangerColor, size: 28),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '⚠️ GPS Disabled',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Location tracking is mandatory during active trips.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text(
                'Please enable GPS/Location services to continue tracking your trip.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kWarningColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kWarningColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline, color: kWarningColor, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Admin has been notified about GPS being disabled.',
                        style: TextStyle(fontSize: 12, color: kWarningColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton.icon(
              onPressed: () async {
                await Geolocator.openLocationSettings();
              },
              icon: const Icon(Icons.settings, color: Colors.white),
              label: const Text('Open Settings', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _handleGPSEnabled() {
    print('✅ GPS ENABLED');
    
    if (_isGPSWarningShown) {
      _isGPSWarningShown = false;
      
      // Close the warning dialog if it's showing
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      
      _showSnackBar('✅ GPS enabled. Tracking resumed.', kSuccessColor);
    }
  }

  // ========================================================================
  // ✅ SHARE LIVE LOCATION
  // ========================================================================
  // ========================================================================
  // ✅ WHATSAPP HELPERS
  // ========================================================================

  /// Opens template picker then sends WhatsApp to ONE customer
  Future<void> _openWhatsAppForCustomer(
      String phone, String customerName) async {
    if (phone.isEmpty) {
      _showSnackBar(
          'No phone number available for $customerName', kWarningColor);
      return;
    }
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final selected = await _showTemplatePickerSheet(customerName);
    if (selected == null) return;
    await _launchWhatsAppMessage(cleanPhone, selected);
  }

  /// Message All: shows one template picker, then opens WhatsApp for every pickup customer
  Future<void> _messageAllCustomers() async {
    final List<Map<String, String>> targets = [];
    for (final stop in currentTrip.stops) {
      if (stop.type == StopType.pickup) {
        for (final p in stop.passengers) {
          if (p.phone.isNotEmpty) {
            targets.add({'name': p.name, 'phone': p.phone});
          }
        }
      }
    }

    if (targets.isEmpty) {
      _showSnackBar('No customer phone numbers available', kWarningColor);
      return;
    }

    final selected =
        await _showTemplatePickerSheet('All Customers (${targets.length})');
    if (selected == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kWhatsAppColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.chat, color: kWhatsAppColor),
            ),
            const SizedBox(width: 12),
            const Text('Message All Customers'),
          ],
        ),
        content: Text(
          'This will open WhatsApp for ${targets.length} customer(s) one by one with the selected message.\n\nProceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kWhatsAppColor),
            child: const Text('Send to All',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    for (final target in targets) {
      final cleanPhone = target['phone']!.replaceAll(RegExp(r'[^\d+]'), '');
      await _launchWhatsAppMessage(cleanPhone, selected);
      await Future.delayed(const Duration(milliseconds: 600));
    }

    _showSnackBar(
        'WhatsApp opened for ${targets.length} customer(s)!', kSuccessColor);
  }

  /// Core WhatsApp launcher - works on mobile AND web
 /// Core WhatsApp launcher - works on mobile AND web
Future<void> _launchWhatsAppMessage(String cleanPhone, String message) async {
  final encodedMessage = Uri.encodeComponent(message);
  final whatsappAppUri = Uri.parse('whatsapp://send?phone=$cleanPhone&text=$encodedMessage');
  final whatsappWebUri = Uri.parse('https://wa.me/$cleanPhone?text=$encodedMessage');

  try {
    if (kIsWeb) {
      await launchUrl(whatsappWebUri, mode: LaunchMode.externalApplication);
    } else {
      if (await canLaunchUrl(whatsappAppUri)) {
        await launchUrl(whatsappAppUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(whatsappWebUri, mode: LaunchMode.externalApplication);
      }
    }
  } catch (e) {
    _showSnackBar('Could not open WhatsApp: $e', kDangerColor);
  }
}

  /// ✅ FIXED: Call customer - works on both mobile and web
  Future<void> _callCustomer(String phone, String name) async {
    if (phone.isEmpty) {
      _showSnackBar('No phone number for $name', kWarningColor);
      return;
    }
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (kIsWeb) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.phone, color: Colors.green),
              const SizedBox(width: 8),
              Text('Call $name'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Dial this number:'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Text(
                  cleanPhone,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final uri = Uri(scheme: 'tel', path: cleanPhone);
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
              icon: const Icon(Icons.phone),
              label: const Text('Call'),
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
          ],
        ),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: cleanPhone);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _showSnackBar('Could not open dialer', kDangerColor);
      }
    } catch (e) {
      _showSnackBar('Error making call: $e', kDangerColor);
    }
  }

  // ========================================================================
  // ✅ TEMPLATE PICKER BOTTOM SHEET
  // ========================================================================
  Future<String?> _showTemplatePickerSheet(String customerName) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TemplatePickerSheet(customerName: customerName),
    );
  }

  // ========================================================================
  // TRIP MANAGEMENT
  // ========================================================================

  Future<void> _captureOdometerPhoto(bool isStart) async {
    try {
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select Photo Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final XFile? photo = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (photo != null) {
        setState(() {
          if (isStart) {
            startOdometerPhoto = photo;
          } else {
            endOdometerPhoto = photo;
          }
        });

        _showSnackBar(
          '${isStart ? "Start" : "End"} odometer photo captured successfully!',
          kSuccessColor,
        );
      }
    } catch (e) {
      print('❌ Error capturing photo: $e');
      _showSnackBar('Error capturing photo: $e', kDangerColor);
    }
  }

  Future<void> _startTrip() async {
    if (startOdometerController.text.isEmpty || startOdometerPhoto == null) {
      _showSnackBar(
        'Please enter starting odometer and capture photo',
        kWarningColor,
      );
      return;
    }

    try {
      setState(() => isLoading = true);

      final rawTripGroupId = currentTripApiData['tripGroupId'];
      final tripGroupId = _cleanTripGroupId(rawTripGroupId);

      String numericOnly =
          startOdometerController.text.replaceAll(RegExp(r'[^0-9]'), '');

      if (numericOnly.isEmpty) {
        setState(() => isLoading = false);
        _showSnackBar('Please enter a valid odometer reading', kWarningColor);
        return;
      }

      final reading = int.parse(numericOnly);

      if (reading <= 0) {
        setState(() => isLoading = false);
        _showSnackBar('Odometer reading must be greater than 0', kWarningColor);
        return;
      }

      print('🚀 Starting trip: $tripGroupId');
      print('📏 Odometer reading: $reading km');

      await _tripService.startTrip(
        tripGroupId: tripGroupId,
        photo: startOdometerPhoto!,
        odometerReading: reading,
      );

      setState(() {
        tripStatus = TripStatus.inProgress;
        trips[currentTripIndex]['apiData']['startOdometer'] = {
          'reading': reading,
        };
        print('✅ Stored startOdometer in apiData: $reading km');
        isLoading = false;
      });

      _showSnackBar('Trip started successfully!', kSuccessColor);
      _startLocationTracking();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TripMapNavigationScreen(
              tripGroupId: tripGroupId,
              stops: currentTrip.stops
                  .map((stop) => {
                        'stopId': stop.id,
                        'type':
                            stop.type == StopType.pickup ? 'pickup' : 'drop',
                        'location': {
                          'address': stop.location,
                          'coordinates': {
                            'latitude': stop.latitude,
                            'longitude': stop.longitude,
                          }
                        },
                        'customer': {
                          'name': stop.passengers.isNotEmpty
                              ? stop.passengers.first.name
                              : 'Unknown',
                          'phone': stop.passengers.isNotEmpty
                              ? stop.passengers.first.phone
                              : '',
                        }
                      })
                  .toList(),
              currentStopIndex: currentStopIndex,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      print('❌ Error starting trip: $e');
      _showSnackBar('Failed to start trip: $e', kDangerColor);
    }
  }

  Future<void> _markArrived() async {
    try {
      final stop = currentTrip.stops[currentStopIndex];
      final tripGroupId = currentTripApiData['tripGroupId'];

      print('📍 Marking arrival');
      print('   Trip Group ID: $tripGroupId');
      print('   Stop ID: ${stop.id}');

      await _tripService.markArrived(
        tripGroupId: tripGroupId,
        stopId: stop.id,
        latitude: _currentPosition?.latitude,
        longitude: _currentPosition?.longitude,
      );

      setState(() {
        currentTrip.stops[currentStopIndex].status = StopStatus.arrived;
      });

      _showSnackBar(
          '✅ Marked as arrived - Customer notified!', kSuccessColor);
    } catch (e) {
      print('❌ Error marking arrival: $e');
      _showSnackBar('Failed to mark arrival: $e', kDangerColor);
    }
  }

  Future<void> _markDeparted() async {
    try {
      final stop = currentTrip.stops[currentStopIndex];
      final tripGroupId = currentTripApiData['tripGroupId'];

      print('\n🚗 MARKING DEPARTURE');
      print(
          '   Current Stop: ${currentStopIndex + 1}/${currentTrip.stops.length}');
      print('   Stop Type: ${stop.type}');
      print('   Trip Group ID: $tripGroupId');
      print('   Stop ID: ${stop.id}');

      await _tripService.markDeparted(
        tripGroupId: tripGroupId,
        stopId: stop.id,
        latitude: _currentPosition?.latitude,
        longitude: _currentPosition?.longitude,
      );

      print('✅ API call successful');

      setState(() {
        currentTrip.stops[currentStopIndex].status = StopStatus.completed;

        if (currentStopIndex < currentTrip.stops.length - 1) {
          currentStopIndex++;
          print('📍 Moved to Stop ${currentStopIndex + 1}');

          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted && _routeScrollController.hasClients) {
              final double targetPosition = (currentStopIndex * 212.0);

              _routeScrollController.animateTo(
                targetPosition,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
              );

              print('📜 Auto-scrolled to Stop ${currentStopIndex + 1}');
            }
          });
        } else {
          currentTrip.status = TripStatus.completed;
          print('🎉 ALL STOPS COMPLETED!');
        }
      });

      if (currentStopIndex < currentTrip.stops.length) {
        final nextStop = currentTrip.stops[currentStopIndex];
        final nextStopName = nextStop.passengers.isNotEmpty
            ? nextStop.passengers.first.name
            : 'Drop location';

        if (stop.type == StopType.pickup) {
          _showSnackBar(
              '✅ Picked up ${stop.passengers.first.name}! Next: $nextStopName',
              kSuccessColor);
        } else {
          _showSnackBar(
              '✅ Drop completed! Next: $nextStopName', kSuccessColor);
        }
      } else {
        _showSnackBar('🎉 All stops completed! Trip finished!', kSuccessColor);
        _showTripCompletionDialog();
      }
    } catch (e) {
      print('❌ Error marking departure: $e');
      _showSnackBar('Failed to mark departure: $e', kDangerColor);
    }
  }

  void _showTripCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.celebration, color: Colors.green, size: 32),
            SizedBox(width: 12),
            Text('Trip Completed!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('All passengers have been dropped off.'),
            const SizedBox(height: 16),
            const Text('Trip Summary:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('• Total Stops: ${currentTrip.stops.length}'),
            Text('• Passengers: ${currentTrip.totalPassengers}'),
            Text('• Distance: ${currentTrip.distance}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('DONE'),
          ),
        ],
      ),
    );
  }

  void _openMapNavigation() {
    if (tripStatus != TripStatus.inProgress) {
      _showSnackBar('Please start the trip first', kWarningColor);
      return;
    }

    final rawTripGroupId = currentTripApiData['tripGroupId'];
    final tripGroupId = _cleanTripGroupId(rawTripGroupId);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TripMapNavigationScreen(
          tripGroupId: tripGroupId,
          stops: currentTrip.stops
              .map((stop) => {
                    'stopId': stop.id,
                    'type': stop.type == StopType.pickup ? 'pickup' : 'drop',
                    'location': {
                      'address': stop.location,
                      'coordinates': {
                        'latitude': stop.latitude,
                        'longitude': stop.longitude,
                      }
                    },
                    'customer': {
                      'name': stop.passengers.isNotEmpty
                          ? stop.passengers.first.name
                          : 'Unknown',
                      'phone': stop.passengers.isNotEmpty
                          ? stop.passengers.first.phone
                          : '',
                    }
                  })
              .toList(),
          currentStopIndex: currentStopIndex,
        ),
      ),
    );
  }

  Future<void> _updatePassengerStatus(
      String passengerId, PassengerStatus status) async {
    try {
      print(
          '👥 Updating passenger status LOCALLY: $status for passenger: $passengerId');

      setState(() {
        passengerStatusMap[passengerId] = status;
      });

      _showSnackBar(
        status == PassengerStatus.boarded
            ? '✅ Marked as boarded'
            : '✅ Marked as not boarded',
        kSuccessColor,
      );
    } catch (e) {
      print('❌ Error updating passenger status: $e');
      _showSnackBar('Failed to update status: $e', kDangerColor);
    }
  }

  Future<void> _endTrip() async {
    if (endOdometerController.text.isEmpty || endOdometerPhoto == null) {
      _showSnackBar(
        'Please enter ending odometer and capture photo',
        kWarningColor,
      );
      return;
    }

    try {
      setState(() => isLoading = true);

      final rawTripGroupId = currentTripApiData['tripGroupId'];
      final tripGroupId = _cleanTripGroupId(rawTripGroupId);

      String numericOnly =
          endOdometerController.text.replaceAll(RegExp(r'[^0-9]'), '');

      if (numericOnly.isEmpty) {
        setState(() => isLoading = false);
        _showSnackBar('Please enter a valid odometer reading', kWarningColor);
        return;
      }

      final reading = int.parse(numericOnly);

      print('🏁 Ending trip: $tripGroupId');

      final result = await _tripService.endTrip(
        tripGroupId: tripGroupId,
        photo: endOdometerPhoto!,
        odometerReading: reading,
      );

      final distance = result['actualDistance'] ?? 0;

      print('📏 Backend returned actualDistance: $distance km');

      final startOdometerReading =
          currentTripApiData['startOdometer']?['reading'] ??
              int.tryParse(startOdometerController.text
                      .replaceAll(RegExp(r'[^0-9]'), '')) ??
              0;

      setState(() {
        trips[currentTripIndex]['trip'].status = TripStatus.completed;
        trips[currentTripIndex]['trip'].actualDistance = distance.toDouble();

        trips[currentTripIndex]['apiData']['actualDistance'] = distance;
        trips[currentTripIndex]['apiData']['status'] = 'completed';

        trips[currentTripIndex]['apiData']['startOdometer'] = {
          'reading': startOdometerReading,
        };
        trips[currentTripIndex]['apiData']['endOdometer'] = {
          'reading': reading,
        };

        print(
            '✅ Updated trip object actualDistance: ${trips[currentTripIndex]['trip'].actualDistance}');
        print(
            '✅ Updated apiData actualDistance: ${trips[currentTripIndex]['apiData']['actualDistance']}');
        print('✅ Updated apiData startOdometer: $startOdometerReading km');
        print('✅ Updated apiData endOdometer: $reading km');

        currentTripIndex = _getCurrentTripIndex();
        tripStatus = trips[currentTripIndex]['trip'].status;

        startOdometerController.clear();
        endOdometerController.clear();
        startOdometerPhoto = null;
        endOdometerPhoto = null;
        currentStopIndex = 0;
        passengerStatusMap.clear();

        isLoading = false;
      });

      _showSnackBar('✅ Trip completed! Distance: $distance km', kSuccessColor);
      _stopLocationTracking();

      print('📍 Moved to trip index: $currentTripIndex');
      print('📊 New trip status: $tripStatus');
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar('Failed to end trip: $e', kDangerColor);
    }
  }

  Future<void> _refreshData() async {
    await _loadTrips();
    _showSnackBar('Data refreshed', kSuccessColor);
  }

  Future<void> _shareLiveLocation() async {
    if (tripStatus != TripStatus.inProgress) {
      _showSnackBar('Please start the trip first', kWarningColor);
      return;
    }

    try {
      // ✅ FIX: Use MongoDB _id directly, not tripGroupId
      // _id = "69804b4455d83112afcc3491" (exact match for fetchTripById)
      final mongoId = currentTripApiData['_id']?.toString() ?? 
                      currentTripApiData['\$oid']?.toString() ?? '';
      
      // Fallback to full tripGroupId (fetchTripByGroupId will exact-match it)
      final trackingId = mongoId.isNotEmpty 
          ? mongoId 
          : currentTripApiData['tripGroupId']?.toString() ?? '';
      
      print('🔍 mongoId: $mongoId');
      print('🔍 trackingId: $trackingId');
      
      final liveUrl = '${ApiConfig.baseUrl}/live-track/$trackingId';
      
      // ✅ FIX: tripNumber is a string like "TRIP-20260228-556629-28"
      final tripNumber = currentTripApiData['tripNumber']?.toString() ?? 
                         'Trip #${currentTrip.tripNumber}';
      final driverName = currentTripApiData['driverName']?.toString() ?? 'Driver';
      final vehicleNum = currentTrip.vehicleNumber;

      print('🔗 Live URL: $liveUrl');
      print('📋 Trip Number: $tripNumber');

      final List<Map<String, String>> customers = [];
      for (final stop in currentTrip.stops) {
        if (stop.type == StopType.pickup) {
          for (final passenger in stop.passengers) {
            if (passenger.phone.isNotEmpty) {
              customers.add({
                'name': passenger.name,
                'phone': passenger.phone,
              });
            }
          }
        }
      }

      print('📱 Found ${customers.length} customers with phone numbers');

      if (customers.isEmpty) {
        _showSnackBar('No customer phone numbers available to share location', kWarningColor);
        return;
      }

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kWhatsAppColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.share_location, color: kWhatsAppColor, size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Share Live Location',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tripNumber,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                const Text('Send live tracking link to:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                ...customers.map((customer) {
                  final customerName = customer['name']!;
                  final customerPhone = customer['phone']!;
                  
                  final message =
                      'Hello $customerName! 👋\n\n'
                      'Your trip *$tripNumber* is now live. 🚗\n'
                      'Driver: *$driverName*\n'
                      'Vehicle: *$vehicleNum*\n\n'
                      '📍 Track your ride in real time:\n'
                      '$liveUrl\n\n'
                      'Thank you for choosing Abra Fleet!';
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _waOption(
                      icon: Icons.person,
                      color: Colors.blue,
                      label: customerName,
                      name: customerPhone,
                      phone: customerPhone,
                      onTap: () {
                        Navigator.pop(context);
                        _openWhatsAppWithMessage(customerPhone, message);
                      },
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    } catch (e) {
      print('❌ Error sharing live location: $e');
      _showSnackBar('Failed to share live location: $e', kDangerColor);
    }
  }

  // Helper widget to display customer/driver option cards
  Widget _waOption({
    required IconData icon,
    required Color color,
    required String label,
    required String name,
    required String phone,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color)),
                Text(name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                Text(phone,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade600)),
              ]),
          ),
        ]),
      ),
    );
  }

  // Opens WhatsApp with a pre-filled message
  Future<void> _openWhatsAppWithMessage(String phone, String message) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final number = cleaned.startsWith('+') ? cleaned : '+91$cleaned';
    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse('https://wa.me/$number?text=$encoded');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showSnackBar('Could not open WhatsApp', kDangerColor);
      }
    } catch (e) {
      print('❌ Error opening WhatsApp: $e');
      _showSnackBar('Failed to open WhatsApp: $e', kDangerColor);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ========================================================================
  // SUPPORT DIALOG - ORIGINAL FULL VERSION with copy-to-clipboard
  // ========================================================================

  Future<void> _showSupportDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isMobile = screenWidth <= 600;

        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: isMobile ? screenWidth * 0.9 : 500,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(isMobile ? 20 : 24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [kPrimaryColor, Color(0xFF1565C0)],
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
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.headset_mic,
                          color: Colors.white,
                          size: isMobile ? 28 : 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'We\'re Here to Help!',
                              style: TextStyle(
                                fontSize: isMobile ? 18 : 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Choose your preferred way to reach us',
                              style: TextStyle(
                                fontSize: isMobile ? 12 : 13,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(isMobile ? 16 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: EdgeInsets.all(isMobile ? 14 : 16),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.blue.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.access_time_rounded,
                                  color: Colors.blue[700], size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Available 24/7',
                                      style: TextStyle(
                                        fontSize: isMobile ? 14 : 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[800],
                                      ),
                                    ),
                                    Text(
                                      'All Days • Round the Clock',
                                      style: TextStyle(
                                        fontSize: isMobile ? 11 : 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Contact Us',
                          style: TextStyle(
                            fontSize: isMobile ? 15 : 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildSupportOptionCard(
                          context,
                          icon: Icons.phone,
                          title: 'Call Us',
                          subtitle: '+91 886-728-8076',
                          color: const Color(0xFF4299E1),
                          onTap: () => _launchPhoneCall(context),
                          onCopy: () => _copyToClipboard(
                              context, '+918867288076', 'Phone number'),
                          isMobile: isMobile,
                        ),
                        const SizedBox(height: 10),
                        _buildSupportOptionCard(
                          context,
                          icon: Icons.chat_bubble,
                          title: 'WhatsApp',
                          subtitle: 'Chat with us instantly',
                          color: kWhatsAppColor,
                          onTap: () => _launchSupportWhatsApp(context),
                          isMobile: isMobile,
                        ),
                        const SizedBox(height: 10),
                        _buildSupportOptionCard(
                          context,
                          icon: Icons.email,
                          title: 'Email Us',
                          subtitle: 'support@fleet.abra-travels.com',
                          color: const Color(0xFFED8936),
                          onTap: () => _launchEmail(context),
                          onCopy: () => _copyToClipboard(context,
                              'support@fleet.abra-travels.com', 'Email address'),
                          isMobile: isMobile,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSupportOptionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    VoidCallback? onCopy,
    required bool isMobile,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: isMobile ? 14 : 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: isMobile ? 11 : 12,
                        color: Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onCopy != null)
                IconButton(
                  icon: Icon(Icons.copy, color: Colors.grey[600], size: 18),
                  onPressed: onCopy,
                  tooltip: 'Copy',
                ),
              Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchPhoneCall(BuildContext context) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: '+918867288076');
    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        _showSnackBar('Unable to open phone dialer', kDangerColor);
      }
    } catch (e) {
      _showSnackBar('Error: $e', kDangerColor);
    }
  }

  // ✅ NEW - works on mobile + web
Future<void> _launchSupportWhatsApp(BuildContext context) async {
  final whatsappAppUri = Uri.parse('whatsapp://send?phone=918867288076');
  final whatsappWebUri = Uri.parse('https://wa.me/918867288076');

  try {
    if (kIsWeb) {
      await launchUrl(whatsappWebUri, mode: LaunchMode.externalApplication);
    } else {
      if (await canLaunchUrl(whatsappAppUri)) {
        await launchUrl(whatsappAppUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(whatsappWebUri, mode: LaunchMode.externalApplication);
      }
    }
  } catch (e) {
    _showSnackBar('Could not open WhatsApp: $e', kDangerColor);
  }
}

  Future<void> _launchEmail(BuildContext context) async {
    const String email = 'support@fleet.abra-travels.com';
    const String subject = 'Support Request';
    const String body = 'Hello Abra Travels Support Team,\n\n';

    try {
      final Uri emailUri = Uri(
        scheme: 'mailto',
        path: email,
        query:
            'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
      );

      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch email';
      }
    } catch (e) {
      _showSnackBar(
          'Unable to open email client. Email copied to clipboard.',
          kWarningColor);
      _copyToClipboard(context, 'support@fleet.abra-travels.com', 'Email address');
    }
  }

  void _copyToClipboard(
      BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Text('$label copied to clipboard!'),
          ],
        ),
        backgroundColor: Colors.green[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildLogoutButton(
      BuildContext context, AuthRepository authRepository) {
    return IconButton(
      icon: const Icon(Icons.logout, color: Colors.white),
      tooltip: 'Logout',
      onPressed: () async {
        final confirmLogout = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm Logout'),
            content: const Text('Are you sure you want to log out?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Logout')),
            ],
          ),
        );

        if (confirmLogout == true && context.mounted) {
          await authRepository.signOut();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const WelcomeScreen()),
            (Route<dynamic> route) => false,
          );
        }
      },
    );
  }

  // ========================================================================
  // BUILD METHOD
  // ========================================================================

  @override
  Widget build(BuildContext context) {
    final authRepository =
        Provider.of<AuthRepository>(context, listen: false);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              height: 32,
              width: 32,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.directions_bus, size: 32);
              },
            ),
            const SizedBox(width: 12),
            const Text(
              'Abra Travels',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: kPrimaryColor,
        elevation: 4.0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refreshData,
            tooltip: 'Refresh',
          ),
          if (widget.onNavigateToNotifications != null)
            IconButton(
              icon: const Icon(Icons.notifications, color: Colors.white),
              onPressed: widget.onNavigateToNotifications,
              tooltip: 'Notifications',
            ),
          IconButton(
            icon: const Icon(Icons.headset_mic_outlined, color: Colors.white),
            onPressed: () => _showSupportDialog(context),
            tooltip: 'Support',
          ),
          _buildLogoutButton(context, authRepository),
        ],
      ),
      body: isLoading && trips.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 64, color: kDangerColor),
                      const SizedBox(height: 16),
                      Text('Error: $errorMessage'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _refreshData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : trips.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.inbox_outlined,
                              size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('No trips assigned for today'),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _refreshData,
                            child: const Text('Refresh'),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildVehicleInfo(),
                          const SizedBox(height: 16),
                          _buildTripOverview(),
                          const SizedBox(height: 16),
                          _buildCurrentTripDetails(),
                          const SizedBox(height: 16),
                          _buildQuickStats(),
                        ],
                      ),
                    ),
    );
  }

  // ========================================================================
  // UI SECTIONS
  // ========================================================================

  Widget _buildVehicleInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kPrimaryColor, kAccentColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_car, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Vehicle Number',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              Text(
                currentTrip.vehicleNumber,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTripOverview() {
    final counts = _getTripStatusCounts();
    final completedCount = counts['completed'] ?? 0;
    final currentCount = counts['current'] ?? 0;
    final upcomingCount = counts['upcoming'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.access_time,
                      size: 20, color: kPrimaryColor),
                  const SizedBox(width: 8),
                  Text(
                    "Today's Trips (${trips.length})",
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (trips.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kPrimaryColor, width: 1),
                  ),
                  child: Text(
                    'Viewing Trip ${currentTripIndex + 1}/${trips.length}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: kPrimaryColor),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (completedCount > 0) ...[
            _buildCollapsedSection(
              title: '✅ Completed ($completedCount)',
              color: Colors.green,
              tripsList: trips
                  .where((t) =>
                      (t['trip'] as Trip).status == TripStatus.completed)
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],
          if (currentCount > 0 ||
              (trips.isNotEmpty &&
                  trips[currentTripIndex]['trip'].status ==
                      TripStatus.inProgress)) ...[
            _buildCurrentTripPreview(),
            const SizedBox(height: 12),
          ],
          if (upcomingCount > 0)
            _buildCollapsedSection(
              title: '⏰ Upcoming ($upcomingCount)',
              color: Colors.orange,
              tripsList: trips
                  .where((t) =>
                      (t['trip'] as Trip).status == TripStatus.assigned)
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildCurrentTripPreview() {
    final trip = currentTrip;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kPrimaryColor, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.navigation,
                      color: kPrimaryColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Current Trip #${trip.tripNumber}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: kPrimaryColor),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: kPrimaryColor,
                    borderRadius: BorderRadius.circular(12)),
                child: const Text('IN PROGRESS',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(trip.route,
              style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.people, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text('${trip.totalPassengers} passengers',
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey[600])),
              const SizedBox(width: 12),
              Icon(Icons.route, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(trip.distance,
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey[600])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedSection({
    required String title,
    required Color color,
    required List<Map<String, dynamic>> tripsList,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Icon(Icons.check_circle, size: 18, color: color),
            ],
          ),
          const SizedBox(height: 8),
          ...tripsList.map((tripData) {
            final trip = tripData['trip'] as Trip;
            final apiData = tripData['apiData'] as Map<String, dynamic>;
            final pickupStops =
                trip.stops.where((s) => s.type == StopType.pickup).toList();
            String tripDescription = '';

            if (pickupStops.length == 1 &&
                pickupStops.first.passengers.isNotEmpty) {
              tripDescription = pickupStops.first.passengers.first.name;
            } else if (pickupStops.length > 1) {
              tripDescription = '${pickupStops.length} pickups';
            } else {
              tripDescription = 'Trip';
            }

            final actualDistance =
                apiData['actualDistance']?.toDouble() ??
                    trip.actualDistance ??
                    0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4)),
                    child: Text('#${trip.tripNumber}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${trip.scheduledStart} • $tripDescription • ${trip.totalPassengers} pax',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[700]),
                    ),
                  ),
                  if (actualDistance > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Text(
                        '${actualDistance.toStringAsFixed(1)} km',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[800]),
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildCurrentTripDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Current Trip Details',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: kPrimaryColor,
                    borderRadius: BorderRadius.circular(8)),
                child: Text('Trip #${currentTrip.tripNumber}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8)),
            child: Column(
              children: [
                _buildInfoRow(
                    'Route', currentTrip.route, Colors.black87),
                _buildInfoRow(
                  'Scheduled Time',
                  '${currentTrip.scheduledStart} - ${currentTrip.scheduledEnd}',
                  Colors.black87,
                ),
                _buildInfoRow(
                    'Total Distance', currentTrip.distance, Colors.black87),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (tripStatus == TripStatus.assigned) _buildStartTripSection(),
          if (tripStatus == TripStatus.inProgress)
            _buildInProgressSection(),
          if (tripStatus == TripStatus.completed) _buildCompletedSection(),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: valueColor)),
        ],
      ),
    );
  }

  Widget _buildStartTripSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        border: Border.all(color: Colors.orange[300]!, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange[800]),
              const SizedBox(width: 8),
              Text('Start Trip - Enter Odometer Reading',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[800])),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: startOdometerController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Starting Odometer (km)',
              hintText: 'Enter current odometer reading',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _captureOdometerPhoto(true),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: startOdometerPhoto != null
                    ? Colors.green[50]
                    : Colors.white,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    startOdometerPhoto != null
                        ? Icons.check_circle
                        : Icons.camera_alt,
                    color: startOdometerPhoto != null
                        ? Colors.green
                        : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    startOdometerPhoto != null
                        ? 'Photo Captured ✓'
                        : 'Capture Odometer Photo',
                    style: TextStyle(
                      color: startOdometerPhoto != null
                          ? Colors.green
                          : Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isLoading ? null : _startTrip,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('START TRIP',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // ✅ IN PROGRESS SECTION - Map + Message All + Stop cards
  // ============================================================================
  Widget _buildInProgressSection() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green[50],
            border: Border.all(color: Colors.green[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Text('Trip Started - GPS tracking active',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                  'Starting Odometer: ${startOdometerController.text} km',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey[700])),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Map navigation button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _openMapNavigation,
            icon: const Icon(Icons.map, size: 24),
            label: const Text('OPEN MAP NAVIGATION',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // ✅ MESSAGE ALL CUSTOMERS button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _messageAllCustomers,
            icon: const Icon(Icons.chat, size: 22, color: Colors.white),
            label: const Text(
              'MESSAGE ALL CUSTOMERS',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kWhatsAppColor,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // ✅ SHARE LIVE LOCATION button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _shareLiveLocation,
            icon: const Icon(Icons.share_location, size: 22, color: Colors.white),
            label: const Text(
              'SHARE LIVE LOCATION',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),

        const SizedBox(height: 16),

        const Text('Route Progress',
            style:
                TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),

        SizedBox(
          height: 400,
          child: SingleChildScrollView(
            controller: _routeScrollController,
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: currentTrip.stops.asMap().entries.map((entry) {
                final index = entry.key;
                final stop = entry.value;
                final isCurrentStop = index == currentStopIndex;
                final isCompleted =
                    stop.status == StopStatus.completed;
                return _buildStopCard(
                    stop, index, isCurrentStop, isCompleted);
              }).toList(),
            ),
          ),
        ),

        if (currentStopIndex == currentTrip.stops.length - 1 &&
            currentTrip.stops[currentStopIndex].status ==
                StopStatus.completed)
          _buildEndTripSection(),
      ],
    );
  }

  // ============================================================================
  // ✅ STOP CARD - with per-customer Call + WhatsApp buttons
  // ============================================================================
  Widget _buildStopCard(
      TripStop stop, int index, bool isCurrentStop, bool isCompleted) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: isCurrentStop
              ? kPrimaryColor
              : isCompleted
                  ? Colors.green
                  : Colors.grey[300]!,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(8),
        color: isCurrentStop
            ? Colors.blue[50]
            : isCompleted
                ? Colors.green[50]
                : Colors.grey[50],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCompleted
                    ? Icons.check_circle
                    : isCurrentStop
                        ? Icons.navigation
                        : Icons.location_on,
                color: isCompleted
                    ? Colors.green
                    : isCurrentStop
                        ? kPrimaryColor
                        : Colors.grey,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Stop ${index + 1} - ${stop.type == StopType.pickup ? "📍 Pickup" : "🏁 Drop"}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isCompleted
                                ? Colors.green
                                : stop.status == StopStatus.arrived
                                    ? Colors.orange
                                    : Colors.grey[400],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isCompleted
                                ? 'Done'
                                : stop.status == StopStatus.arrived
                                    ? 'At Stop'
                                    : 'Pending',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(stop.location,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[700])),
                    if (stop.distanceToOffice > 0)
                      Text(
                        'Distance to office: ${stop.distanceToOffice.toStringAsFixed(1)} km',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey[600]),
                      ),
                    const SizedBox(height: 8),

                    // ✅ PASSENGERS with Call + WhatsApp per customer
                    ...stop.passengers.map((passenger) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.person,
                                      size: 14, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      passenger.name,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                              if (passenger.phone.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    // ✅ Call button
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _callCustomer(
                                            passenger.phone,
                                            passenger.name),
                                        icon: const Icon(Icons.phone,
                                            size: 15,
                                            color: Colors.green),
                                        label: Text(
                                          passenger.phone,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.green),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(
                                              color: Colors.green),
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 6),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // ✅ WhatsApp button
                                    ElevatedButton.icon(
                                      onPressed: () =>
                                          _openWhatsAppForCustomer(
                                              passenger.phone,
                                              passenger.name),
                                      icon: const Icon(Icons.chat,
                                          size: 15, color: Colors.white),
                                      label: const Text(
                                        'WhatsApp',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.white),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: kWhatsAppColor,
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 6),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        elevation: 0,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ],
          ),
          if (isCurrentStop && stop.status != StopStatus.completed) ...[
            const SizedBox(height: 12),
            if (stop.status == StopStatus.pending)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _markArrived,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('MARK AS ARRIVED',
                          style:
                              TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            if (stop.status == StopStatus.arrived) ...[
              if (stop.type == StopType.pickup) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Passenger Attendance:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                      const SizedBox(height: 8),
                      ...stop.passengers.map((passenger) {
                        final status =
                            passengerStatusMap[passenger.id];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(passenger.name,
                                  style: const TextStyle(
                                      fontSize: 12)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: isLoading
                                          ? null
                                          : () =>
                                              _updatePassengerStatus(
                                                  passenger.id,
                                                  PassengerStatus
                                                      .boarded),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: status ==
                                                PassengerStatus.boarded
                                            ? Colors.green
                                            : Colors.grey[200],
                                        foregroundColor: status ==
                                                PassengerStatus.boarded
                                            ? Colors.white
                                            : Colors.black87,
                                        padding:
                                            const EdgeInsets.symmetric(
                                                vertical: 8),
                                      ),
                                      child: const Text('✓ Boarded',
                                          style: TextStyle(
                                              fontSize: 12)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: isLoading
                                          ? null
                                          : () =>
                                              _updatePassengerStatus(
                                                  passenger.id,
                                                  PassengerStatus
                                                      .notBoarded),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: status ==
                                                PassengerStatus
                                                    .notBoarded
                                            ? Colors.red
                                            : Colors.grey[200],
                                        foregroundColor: status ==
                                                PassengerStatus
                                                    .notBoarded
                                            ? Colors.white
                                            : Colors.black87,
                                        padding:
                                            const EdgeInsets.symmetric(
                                                vertical: 8),
                                      ),
                                      child: const Text(
                                          '✗ Not Boarded',
                                          style: TextStyle(
                                              fontSize: 12)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _markDeparted,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    padding:
                        const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('DEPART FROM STOP',
                          style:
                              TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildEndTripSection() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        border: Border.all(color: Colors.red[300]!, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag, color: Colors.red[800]),
              const SizedBox(width: 8),
              Text('End Trip - Enter Odometer Reading',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red[800])),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: endOdometerController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Ending Odometer (km)',
              hintText: 'Enter current odometer reading',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (value) {
              setState(() {});
            },
          ),
          if (endOdometerController.text.isNotEmpty &&
              startOdometerController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Trip Distance: ${(double.tryParse(endOdometerController.text) ?? 0) - (double.tryParse(startOdometerController.text) ?? 0)} km',
                style:
                    TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _captureOdometerPhoto(false),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border:
                    Border.all(color: Colors.grey[300]!, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: endOdometerPhoto != null
                    ? Colors.green[50]
                    : Colors.white,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    endOdometerPhoto != null
                        ? Icons.check_circle
                        : Icons.camera_alt,
                    color: endOdometerPhoto != null
                        ? Colors.green
                        : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    endOdometerPhoto != null
                        ? 'Photo Captured ✓'
                        : 'Capture End Odometer Photo',
                    style: TextStyle(
                      color: endOdometerPhoto != null
                          ? Colors.green
                          : Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (isLoading ||
                      endOdometerController.text.isEmpty ||
                      endOdometerPhoto == null)
                  ? null
                  : _endTrip,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('END TRIP',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedSection() {
    final actualDistance =
        currentTripApiData['actualDistance']?.toDouble() ??
            currentTrip.actualDistance ??
            0.0;

    int startOdometer = 0;
    int endOdometer = 0;

    if (currentTripApiData['startOdometer'] != null) {
      if (currentTripApiData['startOdometer'] is Map) {
        startOdometer =
            currentTripApiData['startOdometer']['reading'] ?? 0;
      } else if (currentTripApiData['startOdometer'] is int) {
        startOdometer = currentTripApiData['startOdometer'];
      }
    }

    if (currentTripApiData['endOdometer'] != null) {
      if (currentTripApiData['endOdometer'] is Map) {
        endOdometer =
            currentTripApiData['endOdometer']['reading'] ?? 0;
      } else if (currentTripApiData['endOdometer'] is int) {
        endOdometer = currentTripApiData['endOdometer'];
      }
    }

    if (startOdometer == 0 && endOdometer == 0 && actualDistance > 0) {
      print('⚠️ No odometer readings found, showing distance only');
    }

    final startTime = currentTrip.scheduledStart;
    final endTime = currentTrip.scheduledEnd;

    print('📊 Completed Section Data:');
    print('   actualDistance: $actualDistance km');
    print('   startOdometer: $startOdometer km');
    print('   endOdometer: $endOdometer km');
    print('   times: $startTime - $endTime');

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.green[50],
        border: Border.all(color: Colors.green, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Trip Completed!',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.green),
          ),
          const SizedBox(height: 16),
          Text(
            'Distance Traveled: ${actualDistance.toStringAsFixed(1)} km',
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
          ),
          const SizedBox(height: 16),
          if (startOdometer > 0 || endOdometer > 0)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                children: [
                  _buildInfoRow('Start Odometer',
                      '$startOdometer km', Colors.black87),
                  const Divider(height: 16),
                  _buildInfoRow(
                      'End Odometer', '$endOdometer km', Colors.black87),
                  const Divider(height: 16),
                  _buildInfoRow(
                    'Trip Distance',
                    '${actualDistance.toStringAsFixed(1)} km',
                    Colors.green,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8)),
            child: Column(
              children: [
                _buildCompletedRow(Icons.access_time, 'Trip Duration',
                    '$startTime - $endTime'),
                const SizedBox(height: 8),
                _buildCompletedRow(Icons.people, 'Passengers',
                    '${currentTrip.totalPassengers}'),
                const SizedBox(height: 8),
                _buildCompletedRow(Icons.location_on, 'Stops',
                    '${currentTrip.stops.length}'),
              ],
            ),
          ),
          if (currentTripIndex < trips.length - 1) ...[
            const SizedBox(height: 16),
            Text(
              'Loading next trip...',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompletedRow(
      IconData icon, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey),
            const SizedBox(width: 8),
            Text(label,
                style:
                    TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        Text(value,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildQuickStats() {
    final counts = _getTripStatusCounts();
    final completedCount = counts['completed'] ?? 0;
    final currentCount = counts['current'] ?? 0;
    final upcomingCount = counts['upcoming'] ?? 0;

    return Row(
      children: [
        Expanded(
            child: _buildStatCard('Completed', completedCount.toString(),
                Colors.green, Icons.check_circle)),
        const SizedBox(width: 12),
        Expanded(
            child: _buildStatCard('Current', currentCount.toString(),
                kPrimaryColor, Icons.navigation)),
        const SizedBox(width: 12),
        Expanded(
            child: _buildStatCard('Upcoming', upcomingCount.toString(),
                Colors.orange, Icons.schedule)),
      ],
    );
  }

  Widget _buildStatCard(
      String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ✅ TEMPLATE PICKER SHEET
// ============================================================================
class _TemplatePickerSheet extends StatefulWidget {
  final String customerName;
  const _TemplatePickerSheet({required this.customerName});

  @override
  State<_TemplatePickerSheet> createState() => _TemplatePickerSheetState();
}

class _TemplatePickerSheetState extends State<_TemplatePickerSheet> {
  bool _showCustomInput = false;
  final TextEditingController _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kWhatsAppColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.chat,
                      color: kWhatsAppColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('WhatsApp Message',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      Text('To: ${widget.customerName}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.grey),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.60,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              children: [
                ...WhatsAppTemplates.templates.map((template) {
                  final emoji =
                      template['label']!.split(' ').first;
                  final label = template['label']!
                      .split(' ')
                      .skip(1)
                      .join(' ');
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                          color: kWhatsAppColor.withOpacity(0.2)),
                    ),
                    child: ListTile(
                      leading: Text(emoji,
                          style: const TextStyle(fontSize: 22)),
                      title: Text(label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      subtitle: Text(
                        template['message']!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600]),
                      ),
                      trailing: const Icon(Icons.send,
                          color: kWhatsAppColor, size: 20),
                      onTap: () => Navigator.pop(
                          context, template['message']),
                    ),
                  );
                }).toList(),
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side:
                        BorderSide(color: Colors.blue.shade100),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Text('✏️',
                            style: TextStyle(fontSize: 22)),
                        title: const Text('Custom Message',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                        subtitle: const Text(
                            'Type your own message',
                            style: TextStyle(fontSize: 12)),
                        trailing: Icon(
                          _showCustomInput
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: Colors.blue,
                        ),
                        onTap: () => setState(() =>
                            _showCustomInput = !_showCustomInput),
                      ),
                      if (_showCustomInput)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              16, 0, 16, 12),
                          child: Column(
                            children: [
                              TextField(
                                controller: _customController,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  hintText:
                                      'Type your message here...',
                                  border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(8)),
                                  contentPadding:
                                      const EdgeInsets.all(12),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    if (_customController.text
                                        .trim()
                                        .isNotEmpty) {
                                      Navigator.pop(
                                          context,
                                          _customController.text
                                              .trim());
                                    }
                                  },
                                  icon: const Icon(Icons.send,
                                      size: 16),
                                  label: const Text(
                                      'Send Custom Message'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(
                                                8)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================
enum TripStatus { assigned, inProgress, completed }

enum StopStatus { pending, arrived, completed }

enum StopType { pickup, drop }

enum PassengerStatus { boarded, notBoarded }

class Trip {
  final String id;
  final String customerNumber;
  final String customerName;
  final int tripNumber;
  TripStatus status;
  final String scheduledStart;
  final String scheduledEnd;
  final String vehicleNumber;
  final String route;
  final int totalPassengers;
  final String distance;
  final List<TripStop> stops;
  double? actualDistance;

  Trip({
    required this.id,
    required this.customerNumber,
    required this.customerName,
    required this.tripNumber,
    required this.status,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.vehicleNumber,
    required this.route,
    required this.totalPassengers,
    required this.distance,
    required this.stops,
    this.actualDistance,
  });
}

class TripStop {
  final String id;
  final StopType type;
  final String location;
  final double latitude;
  final double longitude;
  final List<Passenger> passengers;
  StopStatus status;
  final double distanceToOffice;
  final String estimatedTime;

  TripStop({
    required this.id,
    required this.type,
    required this.location,
    required this.latitude,
    required this.longitude,
    required this.passengers,
    required this.status,
    required this.distanceToOffice,
    required this.estimatedTime,
  });
}

class Passenger {
  final String id;
  final String name;
  final String phone;

  Passenger({
    required this.id,
    required this.name,
    required this.phone,
  });
}