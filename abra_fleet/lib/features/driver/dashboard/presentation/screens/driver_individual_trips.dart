// lib/screens/driver_individual_trips.dart
// ============================================================================
// DRIVER INDIVIDUAL TRIPS - Complete Trip Flow with Response Screen Navigation
// ============================================================================
// ✅ FIXED: Added null safety checks to prevent "Null check operator used on a null value" errors
// ============================================================================
// Tab layout:
//   Pending  → trips with status 'assigned' (not yet responded) OR 'accepted'
//              (driver accepted but trip not started yet)
//              Filters: date range, today, tomorrow, morning, evening chips
//   Accepted → shows the trip the driver tapped from Pending for active execution
//              Full start/arrive/depart/end flow (unchanged from original)
//   Closed   → trips completed OR declined
//              Filters: date range, completed, declined
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

// Import services
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/auth/presentation/screens/welcome_screen.dart';
import 'package:abra_fleet/core/services/individual_trip_service.dart';
import 'trip_map_navigation_screen.dart';
import 'package:abra_fleet/features/notifications/presentation/screens/screens/driver_trip_response_screen.dart';

const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kAccentColor = Color(0xFF1976D2);
const Color kDangerColor = Color(0xFFDC2626);
const Color kWarningColor = Color(0xFFF59E0B);
const Color kSuccessColor = Color(0xFF10B981);
const Color kWhatsAppColor = Color(0xFF25D366);

class DriverIndividualTripsScreen extends StatefulWidget {
  final VoidCallback? onNavigateToNotifications;
  final VoidCallback? onNavigateToReportTab;

  const DriverIndividualTripsScreen({
    super.key,
    this.onNavigateToNotifications,
    this.onNavigateToReportTab,
  });

  @override
  State<DriverIndividualTripsScreen> createState() => _DriverIndividualTripsScreenState();
}

class _DriverIndividualTripsScreenState extends State<DriverIndividualTripsScreen>
    with SingleTickerProviderStateMixin {
  // ========================================================================
  // STATE VARIABLES
  // ========================================================================

  // Tab Controller
  late TabController _tabController;

  // ── API data ──────────────────────────────────────────────────────────────
  // Pending tab = assigned (not yet responded) + accepted (responded but not started)
  List<Map<String, dynamic>> pendingTrips  = [];
  // Closed tab = completed + declined
  List<Map<String, dynamic>> closedTrips   = [];

  // The single trip the driver selected from Pending to execute in Accepted tab
  Map<String, dynamic>? activeTrip;

  // Legacy: kept so existing Accepted-tab widgets work unchanged
  List<Map<String, dynamic>> trips         = [];
  int currentTripIndex                     = 0;

  bool isLoading   = true;
  String? errorMessage;

  // ── Accepted-tab trip state ───────────────────────────────────────────────
  TripStatus tripStatus    = TripStatus.assigned;
  int currentStopIndex     = 0;

  // ── Odometer ─────────────────────────────────────────────────────────────
  final TextEditingController startOdometerController = TextEditingController();
  final TextEditingController endOdometerController   = TextEditingController();
  XFile? startOdometerPhoto;
  XFile? endOdometerPhoto;

  // ── Passenger attendance ──────────────────────────────────────────────────
  Map<String, PassengerStatus> passengerStatusMap = {};

  // ── GPS tracking ──────────────────────────────────────────────────────────
  Timer? _locationTimer;
  Position? _currentPosition;

  // ── Services ─────────────────────────────────────────────────────────────
  final ImagePicker _imagePicker            = ImagePicker();
  final IndividualTripService _tripService  = IndividualTripService();
  final ScrollController _routeScrollController = ScrollController();

  // ── Pending tab filters ───────────────────────────────────────────────────
  DateTime? _pendingFromDate;
  DateTime? _pendingToDate;
  // 'all' | 'today' | 'tomorrow' | 'morning' | 'evening'
  String _pendingQuickFilter = 'all';

  // ── Closed tab filters ────────────────────────────────────────────────────
  DateTime? _closedFromDate;
  DateTime? _closedToDate;
  // 'all' | 'completed' | 'declined'
  String _closedStatusFilter = 'all';

  // ========================================================================
  // LIFECYCLE METHODS
  // ========================================================================

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _initializeApp();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    startOdometerController.dispose();
    endOdometerController.dispose();
    _locationTimer?.cancel();
    _routeScrollController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      setState(() {
        // Keep trips list in sync for the Accepted-tab widgets that use currentTrip
        if (activeTrip != null) {
          trips = [activeTrip!];
          currentTripIndex = 0;
        }
      });
    }
  }

  // ========================================================================
  // INITIALIZATION
  // ========================================================================

  Future<void> _initializeApp() async {
    print('\n' + '🚀' * 40);
    print('INDIVIDUAL TRIPS INITIALIZATION');
    print('🚀' * 40);

    await _requestPermissions();
    await _loadTrips();

    print('✅ Individual trips initialized');
    print('🚀' * 40 + '\n');
  }

  Future<void> _requestPermissions() async {
    print('📍 Requesting location permissions...');

    final locationStatus = await Permission.location.request();
    if (locationStatus.isGranted) {
      print('✅ Location permission granted');
      await _getCurrentLocation();
    } else {
      print('❌ Location permission denied');
      _showSnackBar('Location permission is required for GPS tracking', kDangerColor);
    }

    final cameraStatus = await Permission.camera.request();
    if (cameraStatus.isGranted) {
      print('✅ Camera permission granted');
    } else {
      print('❌ Camera permission denied');
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      print('📍 Current location: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
    } catch (e) {
      print('❌ Failed to get location: $e');
    }
  }

  // ========================================================================
  // API DATA LOADING
  // ========================================================================

  Future<void> _loadTrips() async {
    setState(() {
      isLoading    = true;
      errorMessage = null;
    });

    try {
      print('📋 Loading individual trips from API...');

      // Load all three types of trips from backend
      final fetchedPendingTrips  = await _tripService.getPendingTrips();
      final fetchedAcceptedTrips = await _tripService.getAcceptedTrips();
      final fetchedClosedTrips   = await _tripService.getCompletedTrips();

      setState(() {
        // ── Pending tab = assigned + accepted (not yet started) ──────────
        final allPending = [...fetchedPendingTrips, ...fetchedAcceptedTrips];
        pendingTrips = _transformTripsToLocalFormat(allPending);

        // ── Closed tab = completed + declined ────────────────────────────
        closedTrips = _transformTripsToLocalFormat(fetchedClosedTrips);

        // ── If an active trip was set, try to refresh it ─────────────────
        if (activeTrip != null) {
          final activeId = (activeTrip!['apiData'] as Map<String, dynamic>)['_id'];
          final found = pendingTrips.firstWhere(
            (t) => (t['apiData'] as Map<String, dynamic>)['_id'] == activeId,
            orElse: () => <String, dynamic>{},
          );
          if (found.isNotEmpty) {
            activeTrip = found;
            trips = [activeTrip!];
            currentTripIndex = 0;
            tripStatus = _getTripStatus(activeTrip!);
          }
        }

        isLoading = false;

        print('📍 Current trip index: $currentTripIndex');
        print('📊 Trip status: $tripStatus');
        print('🎯 Current stop index: $currentStopIndex');

        // Start GPS tracking if trip is in progress
        if (tripStatus == TripStatus.inProgress) {
          _startLocationTracking();
        }
      });

      print('✅ Loaded ${pendingTrips.length} pending, ${closedTrips.length} closed trip(s)');
    } catch (e) {
      print('❌ Error loading trips: $e');
      setState(() {
        errorMessage = e.toString();
        isLoading    = false;
      });
      _showSnackBar('Failed to load trips: $e', kDangerColor);
    }
  }

  // ========================================================================
  // DATA TRANSFORMATION — preserved exactly from original
  // ========================================================================

  List<Map<String, dynamic>> _transformTripsToLocalFormat(List<Map<String, dynamic>> apiTrips) {
    print('\n' + '🔄' * 40);
    print('TRANSFORMING API TRIPS TO LOCAL FORMAT');
    print('🔄' * 40);

    return apiTrips.map((apiTrip) {
      print('\n📦 Processing API Trip:');
      print('   Trip ID: ${apiTrip['_id']}');
      print('   Trip Number: ${apiTrip['tripNumber']}');
      print('   Status: ${apiTrip['status']}');

      // ✅ FIX: Extract times from scheduledPickupTime/pickupTime with proper null safety
      String pickupTime = '00:00';
      String dropTime   = '00:00';

      if (apiTrip['scheduledPickupTime'] != null) {
        try {
          final dateTime = DateTime.parse(apiTrip['scheduledPickupTime'].toString());
          pickupTime = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
        } catch (e) {
          print('   ⚠️ Failed to parse scheduledPickupTime: $e');
        }
      }

      if (pickupTime == '00:00' && apiTrip['pickupTime'] != null) {
        try {
          final dateTime = DateTime.parse(apiTrip['pickupTime'].toString());
          pickupTime = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
        } catch (e) {
          print('   ⚠️ Failed to parse pickupTime: $e');
        }
      }

      if (apiTrip['scheduledDropTime'] != null) {
        try {
          final dateTime = DateTime.parse(apiTrip['scheduledDropTime'].toString());
          dropTime = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
        } catch (e) {
          print('   ⚠️ Failed to parse scheduledDropTime: $e');
        }
      }

      if (dropTime == '00:00' && apiTrip['dropTime'] != null) {
        try {
          final dateTime = DateTime.parse(apiTrip['dropTime'].toString());
          dropTime = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
        } catch (e) {
          print('   ⚠️ Failed to parse dropTime: $e');
        }
      }

      // ✅ FIX: Get vehicle number with proper null safety
      String vehicleNumber = 'Not Assigned';
      if (apiTrip['vehicleNumber'] != null && apiTrip['vehicleNumber'].toString().isNotEmpty) {
        vehicleNumber = apiTrip['vehicleNumber'].toString();
      } else if (apiTrip['vehicle'] != null && apiTrip['vehicle'] is Map) {
        final vehicle = apiTrip['vehicle'] as Map<String, dynamic>;
        if (vehicle['registrationNumber'] != null) {
          vehicleNumber = vehicle['registrationNumber'].toString();
        }
      }

      // ✅ FIX: Get customer details with proper null safety
      String customerName  = 'Unknown Customer';
      String customerPhone = '';

      if (apiTrip['customer'] != null && apiTrip['customer'] is Map) {
        final customer = apiTrip['customer'] as Map<String, dynamic>;
        customerName  = customer['name']?.toString()  ?? apiTrip['customerName']?.toString()  ?? 'Unknown Customer';
        customerPhone = customer['phone']?.toString() ?? apiTrip['customerPhone']?.toString() ?? '';
      } else {
        customerName  = apiTrip['customerName']?.toString()  ?? 'Unknown Customer';
        customerPhone = apiTrip['customerPhone']?.toString() ?? '';
      }

      print('   🚗 Vehicle: $vehicleNumber');
      print('   👤 Customer: $customerName ($customerPhone)');
      print('   ⏰ Times: $pickupTime - $dropTime');

      // ✅ FIX: Build stops list with proper null safety
      final List<TripStop> stops = [];

      Map<String, dynamic>? pickupLocation = apiTrip['pickupLocation'] as Map<String, dynamic>?;
      String pickupAddress = pickupLocation?['address']?.toString() ?? 'Pickup Location';
      double pickupLat     = (pickupLocation?['latitude']  ?? 0).toDouble();
      double pickupLng     = (pickupLocation?['longitude'] ?? 0).toDouble();

      Map<String, dynamic>? dropLocation = apiTrip['dropLocation'] as Map<String, dynamic>?;
      String dropAddress = dropLocation?['address']?.toString() ?? 'Drop Location';
      double dropLat     = (dropLocation?['latitude']  ?? 0).toDouble();
      double dropLng     = (dropLocation?['longitude'] ?? 0).toDouble();

      stops.add(TripStop(
        id: '${apiTrip['_id']}_pickup',
        type: StopType.pickup,
        location: pickupAddress,
        latitude: pickupLat,
        longitude: pickupLng,
        estimatedTime: pickupTime,
        status: _parseStopStatus(apiTrip['status']),
        passengers: [
          Passenger(
            id: apiTrip['customer']?['_id']?.toString() ?? '',
            name: customerName,
            phone: customerPhone,
          )
        ],
        distanceToOffice: (apiTrip['distance'] ?? 0).toDouble(),
      ));

      stops.add(TripStop(
        id: '${apiTrip['_id']}_drop',
        type: StopType.drop,
        location: dropAddress,
        latitude: dropLat,
        longitude: dropLng,
        estimatedTime: dropTime,
        status: StopStatus.pending,
        passengers: [
          Passenger(
            id: apiTrip['customer']?['_id']?.toString() ?? '',
            name: customerName,
            phone: customerPhone,
          )
        ],
        distanceToOffice: 0.0,
      ));

      print('   ✅ Created ${stops.length} stops');

      final trip = Trip(
        id: apiTrip['_id']?.toString() ?? '',
        customerNumber: customerPhone,
        customerName: customerName,
        tripNumber: int.tryParse(apiTrip['tripNumber']?.toString() ?? '1') ?? 1,
        status: _parseTripStatus(apiTrip['status']),
        scheduledStart: pickupTime,
        scheduledEnd: dropTime,
        vehicleNumber: vehicleNumber,
        route: '$pickupAddress → $dropAddress',
        totalPassengers: 1,
        distance: '${apiTrip['distance'] ?? 0} km',
        stops: stops,
        actualDistance: (apiTrip['actualDistance'] ?? 0).toDouble(),
        rawPickupTime: apiTrip['scheduledPickupTime']?.toString() ?? apiTrip['pickupTime']?.toString(),
      );

      print('   ✅ TRIP CREATED SUCCESSFULLY\n');

      return {'trip': trip, 'apiData': apiTrip};
    }).toList();
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
    if (statusStr == 'assigned')                        return TripStatus.assigned;
    if (statusStr == 'accepted')                        return TripStatus.assigned;
    if (statusStr == 'started' || statusStr == 'in_progress') return TripStatus.inProgress;
    if (statusStr == 'completed')                       return TripStatus.completed;
    if (statusStr == 'declined')                        return TripStatus.declined;
    return TripStatus.assigned;
  }

  TripStatus _getTripStatus(Map<String, dynamic> tripData) {
    final trip = tripData['trip'] as Trip;
    return trip.status;
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

  // ✅ FIXED: Add null safety to currentTrip getter
  Trip? get currentTrip {
    if (trips.isEmpty || currentTripIndex >= trips.length) return null;
    return trips[currentTripIndex]['trip'] as Trip;
  }

  // ✅ FIXED: Add null safety to currentTripApiData getter
  Map<String, dynamic>? get currentTripApiData {
    if (trips.isEmpty || currentTripIndex >= trips.length) return null;
    return trips[currentTripIndex]['apiData'] as Map<String, dynamic>;
  }

  // ========================================================================
  // PENDING FILTERS
  // ========================================================================

  List<Map<String, dynamic>> get filteredPendingTrips {
    return pendingTrips.where((tripData) {
      final trip    = tripData['trip'] as Trip;
      final rawTime = trip.rawPickupTime;

      // ── quick filter ──
      if (_pendingQuickFilter != 'all' && rawTime != null) {
        try {
          final dt      = DateTime.parse(rawTime);
          final now     = DateTime.now();
          final today   = DateTime(now.year, now.month, now.day);
          final tomorrow = today.add(const Duration(days: 1));
          final tripDay = DateTime(dt.year, dt.month, dt.day);

          if (_pendingQuickFilter == 'today'    && tripDay != today)    return false;
          if (_pendingQuickFilter == 'tomorrow' && tripDay != tomorrow) return false;
          if (_pendingQuickFilter == 'morning'  && !(dt.hour >= 4 && dt.hour < 12)) return false;
          if (_pendingQuickFilter == 'evening'  && !(dt.hour >= 17))   return false;
        } catch (_) {}
      }

      // ── date range filter ──
      if ((_pendingFromDate != null || _pendingToDate != null) && rawTime != null) {
        try {
          final dt      = DateTime.parse(rawTime);
          final tripDay = DateTime(dt.year, dt.month, dt.day);
          if (_pendingFromDate != null &&
              tripDay.isBefore(DateTime(_pendingFromDate!.year, _pendingFromDate!.month, _pendingFromDate!.day))) {
            return false;
          }
          if (_pendingToDate != null &&
              tripDay.isAfter(DateTime(_pendingToDate!.year, _pendingToDate!.month, _pendingToDate!.day))) {
            return false;
          }
        } catch (_) {}
      }

      return true;
    }).toList();
  }

  // ========================================================================
  // CLOSED FILTERS
  // ========================================================================

  List<Map<String, dynamic>> get filteredClosedTrips {
    return closedTrips.where((tripData) {
      final trip    = tripData['trip'] as Trip;
      final apiData = tripData['apiData'] as Map<String, dynamic>;

      if (_closedStatusFilter == 'completed' && trip.status != TripStatus.completed) return false;
      if (_closedStatusFilter == 'declined'  && trip.status != TripStatus.declined)  return false;

      final rawTime = apiData['actualEndTime']?.toString()
          ?? apiData['actualStartTime']?.toString()
          ?? apiData['createdAt']?.toString();

      if ((_closedFromDate != null || _closedToDate != null) && rawTime != null) {
        try {
          final dt  = DateTime.parse(rawTime);
          final day = DateTime(dt.year, dt.month, dt.day);
          if (_closedFromDate != null &&
              day.isBefore(DateTime(_closedFromDate!.year, _closedFromDate!.month, _closedFromDate!.day))) {
            return false;
          }
          if (_closedToDate != null &&
              day.isAfter(DateTime(_closedToDate!.year, _closedToDate!.month, _closedToDate!.day))) {
            return false;
          }
        } catch (_) {}
      }

      return true;
    }).toList();
  }

  // ========================================================================
  // GPS TRACKING
  // ========================================================================

  void _startLocationTracking() {
    print('📍 Starting GPS tracking...');

    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        _currentPosition = position;

        // ✅ FIXED: Check if currentTripApiData is null
        final apiData = currentTripApiData;
        if (apiData == null) {
          print('⚠️ No current trip API data available');
          return;
        }

        final tripId = apiData['_id'];
        await _tripService.updateLocation(
          tripId: tripId,
          latitude: position.latitude,
          longitude: position.longitude,
          speed: position.speed,
          heading: position.heading,
        );

        print('📍 Location updated: ${position.latitude}, ${position.longitude}');
      } catch (e) {
        print('❌ Location update failed: $e');
      }
    });
  }

  void _stopLocationTracking() {
    print('🛑 Stopping GPS tracking...');
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  // ========================================================================
  // OPEN A PENDING TRIP IN THE ACCEPTED TAB
  // Tapping "Start Trip" / "View Details" on a pending card → switch to Accepted tab
  // ========================================================================

  void _openTripInAcceptedTab(Map<String, dynamic> tripData) {
    setState(() {
      activeTrip        = tripData;
      trips             = [tripData];
      currentTripIndex  = 0;
      tripStatus        = _getTripStatus(tripData);
      currentStopIndex  = _getCurrentStopIndexFromBackend();

      // Reset odometer/photos for the new trip
      startOdometerController.clear();
      endOdometerController.clear();
      startOdometerPhoto = null;
      endOdometerPhoto   = null;
      passengerStatusMap.clear();
    });
    _tabController.animateTo(1);
  }

  // ========================================================================
  // NAVIGATION TO TRIP RESPONSE SCREEN (for unresponded trips)
  // ========================================================================

  Future<void> _navigateToTripResponse(Map<String, dynamic> tripData) async {
    final apiData = tripData['apiData'] as Map<String, dynamic>;
    final trip    = tripData['trip'] as Trip;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DriverTripResponseScreen(
          tripId: apiData['_id'].toString(),
          tripNumber: apiData['tripNumber'].toString(),
          tripData: {
            'vehicleNumber': trip.vehicleNumber,
            'distance': apiData['distance'],
            'pickupTime': apiData['scheduledPickupTime'] ?? apiData['pickupTime'],
            'customerName': trip.customerName,
            'customerPhone': trip.customerNumber,
            'pickupLocation': apiData['pickupLocation'],
            'dropLocation': apiData['dropLocation'],
          },
        ),
      ),
    );

    if (result == true || result == null) {
      await _loadTrips();
    }
  }

  // ========================================================================
  // TRIP MANAGEMENT — preserved exactly from original
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
          if (isStart) startOdometerPhoto = photo;
          else         endOdometerPhoto   = photo;
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
    // ✅ FIXED: Check if currentTripApiData is null
    final apiData = currentTripApiData;
    if (apiData == null) {
      _showSnackBar('No trip data available', kDangerColor);
      return;
    }

    if (startOdometerController.text.isEmpty || startOdometerPhoto == null) {
      _showSnackBar('Please enter starting odometer and capture photo', kWarningColor);
      return;
    }

    try {
      setState(() => isLoading = true);

      final tripId = apiData['_id'];

      String numericOnly = startOdometerController.text.replaceAll(RegExp(r'[^0-9]'), '');
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

      print('🚀 Starting trip: $tripId');
      print('📏 Odometer reading: $reading km');

      await _tripService.startTrip(
        tripId: tripId,
        photo: startOdometerPhoto!,
        odometerReading: reading,
      );

      setState(() {
        tripStatus = TripStatus.inProgress;
        isLoading  = false;
      });

      _showSnackBar('Trip started successfully!', kSuccessColor);
      _startLocationTracking();

      // ✅ FIXED: Check if currentTrip is null before navigating
      final trip = currentTrip;
      if (trip == null) {
        print('⚠️ No current trip available for navigation');
        return;
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TripMapNavigationScreen(
              tripGroupId: tripId,
              stops: trip.stops.map((stop) => {
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
                  'name': stop.passengers.isNotEmpty ? stop.passengers.first.name : 'Unknown',
                  'phone': stop.passengers.isNotEmpty ? stop.passengers.first.phone : '',
                }
              }).toList(),
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
    // ✅ FIXED: Check if currentTrip and currentTripApiData are null
    final trip    = currentTrip;
    final apiData = currentTripApiData;

    if (trip == null || apiData == null) {
      _showSnackBar('No trip data available', kDangerColor);
      return;
    }

    try {
      final stop   = trip.stops[currentStopIndex];
      final tripId = apiData['_id'];

      print('📍 Marking arrival');
      print('   Trip ID: $tripId');
      print('   Stop ID: ${stop.id}');

      await _tripService.markArrived(
        tripId: tripId,
        latitude: _currentPosition?.latitude,
        longitude: _currentPosition?.longitude,
      );

      setState(() {
        trip.stops[currentStopIndex].status = StopStatus.arrived;
      });

      _showSnackBar('✅ Marked as arrived - Customer notified!', kSuccessColor);
    } catch (e) {
      print('❌ Error marking arrival: $e');
      _showSnackBar('Failed to mark arrival: $e', kDangerColor);
    }
  }

  Future<void> _markDeparted() async {
    // ✅ FIXED: Check if currentTrip and currentTripApiData are null
    final trip    = currentTrip;
    final apiData = currentTripApiData;

    if (trip == null || apiData == null) {
      _showSnackBar('No trip data available', kDangerColor);
      return;
    }

    try {
      final stop   = trip.stops[currentStopIndex];
      final tripId = apiData['_id'];

      print('\n🚗 MARKING DEPARTURE');
      print('   Current Stop: ${currentStopIndex + 1}/${trip.stops.length}');
      print('   Stop Type: ${stop.type}');
      print('   Trip ID: $tripId');
      print('   Stop ID: ${stop.id}');

      await _tripService.markDeparted(
        tripId: tripId,
        latitude: _currentPosition?.latitude,
        longitude: _currentPosition?.longitude,
      );

      print('✅ API call successful');

      setState(() {
        trip.stops[currentStopIndex].status = StopStatus.completed;

        if (currentStopIndex < trip.stops.length - 1) {
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
          trip.status = TripStatus.completed;
          print('🎉 ALL STOPS COMPLETED!');
        }
      });

      if (currentStopIndex < trip.stops.length) {
        final nextStop     = trip.stops[currentStopIndex];
        final nextStopName = nextStop.passengers.isNotEmpty
            ? nextStop.passengers.first.name
            : nextStop.type == StopType.pickup ? 'Pickup location' : 'Drop location';

        if (stop.type == StopType.pickup) {
          _showSnackBar(
            '✅ Picked up ${stop.passengers.first.name}! Next: $nextStopName',
            kSuccessColor,
          );
        } else {
          _showSnackBar('✅ Drop completed! Next: $nextStopName', kSuccessColor);
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
    // ✅ FIXED: Check if currentTrip is null
    final trip = currentTrip;
    if (trip == null) return;

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
            const Text('Trip Summary:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('• Total Stops: ${trip.stops.length}'),
            Text('• Passengers: ${trip.totalPassengers}'),
            Text('• Distance: ${trip.distance}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
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

    // ✅ FIXED: Check if currentTripApiData and currentTrip are null
    final apiData = currentTripApiData;
    final trip    = currentTrip;

    if (apiData == null || trip == null) {
      _showSnackBar('No trip data available', kDangerColor);
      return;
    }

    final tripId = apiData['_id'];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TripMapNavigationScreen(
          tripGroupId: tripId,
          stops: trip.stops.map((stop) => {
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
              'name': stop.passengers.isNotEmpty ? stop.passengers.first.name : 'Unknown',
              'phone': stop.passengers.isNotEmpty ? stop.passengers.first.phone : '',
            }
          }).toList(),
          currentStopIndex: currentStopIndex,
        ),
      ),
    );
  }

  // ========================================================================
  // ✅ SHARE LIVE LOCATION
  // ========================================================================
  Future<void> _shareLiveLocation() async {
    if (tripStatus != TripStatus.inProgress) {
      _showSnackBar('Please start the trip first', kWarningColor);
      return;
    }

    try {
      // ✅ Check if currentTripApiData and currentTrip are null
      final apiData = currentTripApiData;
      final trip = currentTrip;
      
      if (apiData == null || trip == null) {
        _showSnackBar('No trip data available', kDangerColor);
        return;
      }

      // ✅ Use MongoDB _id directly
      final mongoId = apiData['_id']?.toString() ?? 
                      apiData['\$oid']?.toString() ?? '';
      
      // Fallback to tripNumber if _id is not available
      final trackingId = mongoId.isNotEmpty 
          ? mongoId 
          : apiData['tripNumber']?.toString() ?? '';
      
      print('🔍 mongoId: $mongoId');
      print('🔍 trackingId: $trackingId');
      
      final liveUrl = 'https://abra-fleet-management.com/live-track/$trackingId';
      
      // ✅ Get trip details
      final tripNumber = apiData['tripNumber']?.toString() ?? 
                         'Trip #${trip.tripNumber}';
      final driverName = apiData['driverName']?.toString() ?? 'Driver';
      final vehicleNum = trip.vehicleNumber;

      print('🔗 Live URL: $liveUrl');
      print('📋 Trip Number: $tripNumber');

      // ✅ Collect all customers with phone numbers
      final List<Map<String, String>> customers = [];
      for (final stop in trip.stops) {
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

  // ========================================================================
  // ✅ WHATSAPP HELPERS
  // ========================================================================
  Future<void> _openWhatsAppWithMessage(String phone, String message) async {
    try {
      final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
      final encodedMessage = Uri.encodeComponent(message);
      final whatsappUrl = 'https://wa.me/$cleanPhone?text=$encodedMessage';
      final uri = Uri.parse(whatsappUrl);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        print('✅ WhatsApp opened successfully');
      } else {
        _showSnackBar('Could not open WhatsApp', kDangerColor);
      }
    } catch (e) {
      print('❌ Error opening WhatsApp: $e');
      _showSnackBar('Failed to open WhatsApp: $e', kDangerColor);
    }
  }

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
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Text(
                    phone,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: kWhatsAppColor),
          ],
        ),
      ),
    );
  }

  Future<void> _updatePassengerStatus(String passengerId, PassengerStatus status) async {
    try {
      print('👥 Updating passenger status LOCALLY: $status for passenger: $passengerId');
      setState(() { passengerStatusMap[passengerId] = status; });
      _showSnackBar(
        status == PassengerStatus.boarded ? '✅ Marked as boarded' : '✅ Marked as not boarded',
        kSuccessColor,
      );
    } catch (e) {
      print('❌ Error updating passenger status: $e');
      _showSnackBar('Failed to update status: $e', kDangerColor);
    }
  }

  Future<void> _endTrip() async {
    if (endOdometerController.text.isEmpty || endOdometerPhoto == null) {
      _showSnackBar('Please enter ending odometer and capture photo', kWarningColor);
      return;
    }

    // ✅ FIXED: Check if currentTripApiData is null
    final apiData = currentTripApiData;
    if (apiData == null) {
      _showSnackBar('No trip data available', kDangerColor);
      return;
    }

    try {
      setState(() => isLoading = true);

      final tripId      = apiData['_id'];
      String numericOnly = endOdometerController.text.replaceAll(RegExp(r'[^0-9]'), '');

      if (numericOnly.isEmpty) {
        setState(() => isLoading = false);
        _showSnackBar('Please enter a valid odometer reading', kWarningColor);
        return;
      }

      final reading = int.parse(numericOnly);
      print('🏁 Ending trip: $tripId');

      final result   = await _tripService.endTrip(
        tripId: tripId,
        photo: endOdometerPhoto!,
        odometerReading: reading,
      );

      final distance = result['actualDistance'] ?? 0;

      setState(() {
        // Mark active trip as completed
        if (trips.isNotEmpty) {
          trips[currentTripIndex]['trip'].status         = TripStatus.completed;
          trips[currentTripIndex]['trip'].actualDistance = distance.toDouble();
        }

        // Auto-advance
        currentTripIndex = _getCurrentTripIndex();
        if (trips.isNotEmpty) {
          tripStatus = trips[currentTripIndex]['trip'].status;
        }

        // Reset form
        startOdometerController.clear();
        endOdometerController.clear();
        startOdometerPhoto = null;
        endOdometerPhoto   = null;
        currentStopIndex   = 0;
        passengerStatusMap.clear();

        // Clear active trip so Accepted tab shows placeholder
        activeTrip = null;
        trips      = [];

        isLoading = false;
      });

      _showSnackBar('✅ Trip completed! Distance: $distance km', kSuccessColor);
      _stopLocationTracking();

      // Reload trips and return to Pending tab
      await _loadTrips();
      _tabController.animateTo(0);

      print('📍 Moved to trip index: $currentTripIndex');
      print('📊 New trip status: $tripStatus');
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar('Failed to end trip: $e', kDangerColor);
    }
  }

  // ========================================================================
  // REFRESH DATA
  // ========================================================================

  Future<void> _refreshData() async {
    await _loadTrips();
    _showSnackBar('Data refreshed', kSuccessColor);
  }

  // ========================================================================
  // BUILD METHOD
  // ========================================================================

  @override
  Widget build(BuildContext context) {
    final authRepository = Provider.of<AuthRepository>(context, listen: false);

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
              'Individual Trips',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
          _buildLogoutButton(context, authRepository),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.pending_actions, size: 18),
                  const SizedBox(width: 6),
                  const Text('Pending'),
                  if (pendingTrips.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${pendingTrips.length}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, size: 18),
                  const SizedBox(width: 6),
                  const Text('Accepted'),
                  if (activeTrip != null)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '1',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.done_all, size: 18),
                  const SizedBox(width: 6),
                  const Text('Closed'),
                  if (closedTrips.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${closedTrips.length}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPendingTab(),
          _buildAcceptedTab(),
          _buildClosedTab(),
        ],
      ),
    );
  }

  // ========================================================================
  // PENDING TAB — assigned + accepted trips with filters
  // ========================================================================

  Widget _buildPendingTab() {
    if (isLoading && pendingTrips.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: kDangerColor),
            const SizedBox(height: 16),
            Text('Error: $errorMessage'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _refreshData, child: const Text('Retry')),
          ],
        ),
      );
    }

    final displayed = filteredPendingTrips;

    return Column(
      children: [
        _buildPendingFilters(),
        Expanded(
          child: displayed.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        pendingTrips.isEmpty ? 'No pending trips' : 'No trips match filters',
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        pendingTrips.isEmpty
                            ? 'New trip requests will appear here'
                            : 'Try different filters',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _refreshData, child: const Text('Refresh')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refreshData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: displayed.length,
                    itemBuilder: (context, index) {
                      return _buildPendingTripCard(displayed[index]);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildPendingFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _quickChip('All',      'all',      _pendingQuickFilter, (v) => setState(() => _pendingQuickFilter = v)),
                const SizedBox(width: 6),
                _quickChip('Today',    'today',    _pendingQuickFilter, (v) => setState(() => _pendingQuickFilter = v)),
                const SizedBox(width: 6),
                _quickChip('Tomorrow', 'tomorrow', _pendingQuickFilter, (v) => setState(() => _pendingQuickFilter = v)),
                const SizedBox(width: 6),
                _quickChip('Morning',  'morning',  _pendingQuickFilter, (v) => setState(() => _pendingQuickFilter = v)),
                const SizedBox(width: 6),
                _quickChip('Evening',  'evening',  _pendingQuickFilter, (v) => setState(() => _pendingQuickFilter = v)),
                const SizedBox(width: 6),
                _dateRangeButton(
                  fromDate: _pendingFromDate,
                  toDate: _pendingToDate,
                  onPicked: (from, to) => setState(() { _pendingFromDate = from; _pendingToDate = to; }),
                  onClear: () => setState(() { _pendingFromDate = null; _pendingToDate = null; }),
                ),
              ],
            ),
          ),
          if (_pendingFromDate != null || _pendingToDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '📅 ${_pendingFromDate != null ? _fmtDate(_pendingFromDate!) : "..."} → ${_pendingToDate != null ? _fmtDate(_pendingToDate!) : "..."}',
                style: const TextStyle(fontSize: 11, color: Colors.blue),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPendingTripCard(Map<String, dynamic> tripData) {
    final trip        = tripData['trip'] as Trip;
    final apiData     = tripData['apiData'] as Map<String, dynamic>;
    final backendStatus = apiData['status']?.toString() ?? '';
    final isAccepted  = backendStatus == 'accepted';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isAccepted
            ? const BorderSide(color: Colors.green, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isAccepted ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Trip #${trip.tripNumber}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: (isAccepted ? Colors.green : Colors.orange).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isAccepted ? '✅ ACCEPTED' : 'PENDING',
                    style: TextStyle(
                      color: isAccepted ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Customer', trip.customerName,  Colors.black87),
            _buildInfoRow('Phone',    trip.customerNumber, Colors.black87),
            _buildInfoRow('Route',    trip.route,          Colors.black87),
            _buildInfoRow('Time',     '${trip.scheduledStart} - ${trip.scheduledEnd}', Colors.black87),
            _buildInfoRow('Distance', trip.distance,       Colors.black87),
            _buildInfoRow('Vehicle',  trip.vehicleNumber,  Colors.black87),
            const SizedBox(height: 16),
            // Buttons
            Row(
              children: [
                // Show "Respond to Trip" only for unresponded (assigned) trips
                if (!isAccepted) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isLoading ? null : () => _navigateToTripResponse(tripData),
                      icon: const Icon(Icons.reply, size: 18),
                      label: const Text('RESPOND'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kPrimaryColor,
                        side: const BorderSide(color: kPrimaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isLoading ? null : () => _openTripInAcceptedTab(tripData),
                    icon: Icon(isAccepted ? Icons.play_arrow : Icons.visibility, size: 18),
                    label: Text(isAccepted ? 'START TRIP' : 'VIEW DETAILS'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isAccepted ? Colors.green : kPrimaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // ACCEPTED TAB — shows the single active trip's full flow
  // ========================================================================

  Widget _buildAcceptedTab() {
    if (isLoading && activeTrip == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: kDangerColor),
            const SizedBox(height: 16),
            Text('Error: $errorMessage'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _refreshData, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (activeTrip == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No trip selected',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap a trip in the Pending tab to execute it here',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _tabController.animateTo(0),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go to Pending'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    // Full trip execution flow — original code
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildVehicleInfo(),
          const SizedBox(height: 16),
          _buildCurrentTripDetails(),
        ],
      ),
    );
  }

  // ========================================================================
  // CLOSED TAB — completed + declined with filters
  // ========================================================================

  Widget _buildClosedTab() {
    if (isLoading && closedTrips.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: kDangerColor),
            const SizedBox(height: 16),
            Text('Error: $errorMessage'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _refreshData, child: const Text('Retry')),
          ],
        ),
      );
    }

    final displayed = filteredClosedTrips;

    return Column(
      children: [
        _buildClosedFilters(),
        Expanded(
          child: displayed.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        closedTrips.isEmpty ? 'No closed trips' : 'No trips match filters',
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        closedTrips.isEmpty
                            ? 'Completed & declined trips will appear here'
                            : 'Try different filters',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _refreshData, child: const Text('Refresh')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refreshData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: displayed.length,
                    itemBuilder: (context, index) => _buildClosedTripCard(displayed[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildClosedFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _quickChip('All',       'all',       _closedStatusFilter, (v) => setState(() => _closedStatusFilter = v)),
                const SizedBox(width: 6),
                _quickChip('Completed', 'completed', _closedStatusFilter, (v) => setState(() => _closedStatusFilter = v), color: Colors.green),
                const SizedBox(width: 6),
                _quickChip('Declined',  'declined',  _closedStatusFilter, (v) => setState(() => _closedStatusFilter = v), color: Colors.red),
                const SizedBox(width: 6),
                _dateRangeButton(
                  fromDate: _closedFromDate,
                  toDate: _closedToDate,
                  onPicked: (from, to) => setState(() { _closedFromDate = from; _closedToDate = to; }),
                  onClear: () => setState(() { _closedFromDate = null; _closedToDate = null; }),
                ),
              ],
            ),
          ),
          if (_closedFromDate != null || _closedToDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '📅 ${_closedFromDate != null ? _fmtDate(_closedFromDate!) : "..."} → ${_closedToDate != null ? _fmtDate(_closedToDate!) : "..."}',
                style: const TextStyle(fontSize: 11, color: Colors.blue),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildClosedTripCard(Map<String, dynamic> tripData) {
    final trip     = tripData['trip'] as Trip;
    final apiData  = tripData['apiData'] as Map<String, dynamic>;

    final isDeclined  = trip.status == TripStatus.declined;
    final isCompleted = trip.status == TripStatus.completed;

    final actualDistance = apiData['actualDistance']?.toDouble() ?? trip.actualDistance ?? 0.0;
    final startOdometer  = apiData['startOdometer']?['reading'] ?? 0;
    final endOdometer    = apiData['endOdometer']?['reading']   ?? 0;
    final declineReason  = apiData['driverDeclineReason']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDeclined ? Colors.red.shade200 : Colors.green.shade200,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Trip #${trip.tripNumber}',
                    style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDeclined ? Colors.red.shade100 : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isDeclined ? Icons.cancel : Icons.check_circle,
                        color: isDeclined ? Colors.red : Colors.green,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isDeclined ? 'DECLINED' : 'COMPLETED',
                        style: TextStyle(
                          color: isDeclined ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Show actual distance prominently for completed trips
            if (isCompleted) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '📏 Actual Distance',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                        Text(
                          '${actualDistance.toStringAsFixed(1)} km',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ],
                    ),
                    if (startOdometer > 0 && endOdometer > 0) ...[
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Start Odometer', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                              Text('$startOdometer km', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('End Odometer', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                              Text('$endOdometer km', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Declined: show reason box
            if (isDeclined && declineReason.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Decline Reason',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red)),
                          const SizedBox(height: 2),
                          Text(declineReason, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Trip duration with times
            if (apiData['actualStartTime'] != null && apiData['actualEndTime'] != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Started', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                        Text(_formatTime(apiData['actualStartTime']),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Icon(Icons.access_time, size: 16, color: Colors.blue),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Ended', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                        Text(_formatTime(apiData['actualEndTime']),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            _buildInfoRow('Customer', trip.customerName,  Colors.black87),
            _buildInfoRow('Phone',    trip.customerNumber, Colors.black87),
            _buildInfoRow('Route',    trip.route,          Colors.black87),
            _buildInfoRow('Vehicle',  trip.vehicleNumber,  Colors.black87),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // UI HELPERS
  // ========================================================================

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

  Widget _buildLogoutButton(BuildContext context, AuthRepository authRepository) {
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
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Logout'),
              ),
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

  // ✅ FIXED: Add null safety check to _buildVehicleInfo
  Widget _buildVehicleInfo() {
    final trip = currentTrip;
    if (trip == null) return const SizedBox.shrink();

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
              const Text('Vehicle Number', style: TextStyle(color: Colors.white70, fontSize: 12)),
              Text(
                trip.vehicleNumber,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ✅ FIXED: Add null safety check to _buildCurrentTripDetails
  Widget _buildCurrentTripDetails() {
    final trip = currentTrip;
    if (trip == null) {
      return const Center(child: Text('No trip data available'));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Current Trip Details',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: kPrimaryColor, borderRadius: BorderRadius.circular(8)),
                child: Text('Trip #${trip.tripNumber}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8)),
            child: Column(
              children: [
                _buildInfoRow('Route', trip.route, Colors.black87),
                _buildInfoRow('Scheduled Time', '${trip.scheduledStart} - ${trip.scheduledEnd}', Colors.black87),
                _buildInfoRow('Total Distance', trip.distance, Colors.black87),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (tripStatus == TripStatus.assigned)  _buildStartTripSection(),
          if (tripStatus == TripStatus.inProgress) _buildInProgressSection(),
          if (tripStatus == TripStatus.completed)  _buildCompletedSection(),
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
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          Flexible(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: valueColor),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
              Text(
                'Start Trip - Enter Odometer Reading',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[800]),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: startOdometerController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Starting Odometer (km)',
              hintText: 'Enter current odometer reading',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                color: startOdometerPhoto != null ? Colors.green[50] : Colors.white,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    startOdometerPhoto != null ? Icons.check_circle : Icons.camera_alt,
                    color: startOdometerPhoto != null ? Colors.green : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    startOdometerPhoto != null ? 'Photo Captured ✓' : 'Capture Odometer Photo',
                    style: TextStyle(
                      color: startOdometerPhoto != null ? Colors.green : Colors.grey[600],
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('START TRIP',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ FIXED: Add null safety check to _buildInProgressSection
  Widget _buildInProgressSection() {
    final trip = currentTrip;
    if (trip == null) return const Center(child: Text('No trip data available'));

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
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Starting Odometer: ${startOdometerController.text} km',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _openMapNavigation,
            icon: const Icon(Icons.map, size: 24),
            label: const Text('OPEN MAP NAVIGATION',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        const Text('Route Progress', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),

        SizedBox(
          height: 400,
          child: SingleChildScrollView(
            controller: _routeScrollController,
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: trip.stops.asMap().entries.map((entry) {
                final index       = entry.key;
                final stop        = entry.value;
                final isCurrentStop = index == currentStopIndex;
                final isCompleted   = stop.status == StopStatus.completed;
                return _buildStopCard(stop, index, isCurrentStop, isCompleted);
              }).toList(),
            ),
          ),
        ),

        if (currentStopIndex == trip.stops.length - 1 &&
            trip.stops[currentStopIndex].status == StopStatus.completed)
          _buildEndTripSection(),
      ],
    );
  }

  Widget _buildStopCard(TripStop stop, int index, bool isCurrentStop, bool isCompleted) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: isCurrentStop ? kPrimaryColor : isCompleted ? Colors.green : Colors.grey[300]!,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(8),
        color: isCurrentStop ? Colors.blue[50] : isCompleted ? Colors.green[50] : Colors.grey[50],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCompleted ? Icons.check_circle : isCurrentStop ? Icons.navigation : Icons.location_on,
                color: isCompleted ? Colors.green : isCurrentStop ? kPrimaryColor : Colors.grey,
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
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(stop.location, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                    if (stop.distanceToOffice > 0)
                      Text('Distance: ${stop.distanceToOffice.toStringAsFixed(1)} km',
                          style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                    const SizedBox(height: 8),
                    ...stop.passengers.map((passenger) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(passenger.name,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                              ),
                              if (passenger.phone.isNotEmpty)
                                InkWell(
                                  onTap: () async {
                                    final uri = Uri(scheme: 'tel', path: passenger.phone);
                                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                                  },
                                  child: Text('📞 ${passenger.phone}',
                                      style: const TextStyle(fontSize: 10, color: kPrimaryColor)),
                                ),
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
                      backgroundColor: Colors.orange, padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: isLoading
                      ? const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('MARK AS ARRIVED', style: TextStyle(fontWeight: FontWeight.bold)),
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
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 8),
                      ...stop.passengers.map((passenger) {
                        final status = passengerStatusMap[passenger.id];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(passenger.name, style: const TextStyle(fontSize: 12)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: isLoading
                                          ? null
                                          : () => _updatePassengerStatus(
                                              passenger.id, PassengerStatus.boarded),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: status == PassengerStatus.boarded
                                            ? Colors.green
                                            : Colors.grey[200],
                                        foregroundColor: status == PassengerStatus.boarded
                                            ? Colors.white
                                            : Colors.black87,
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                      ),
                                      child: const Text('✓ Boarded',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: isLoading
                                          ? null
                                          : () => _updatePassengerStatus(
                                              passenger.id, PassengerStatus.notBoarded),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: status == PassengerStatus.notBoarded
                                            ? Colors.red
                                            : Colors.grey[200],
                                        foregroundColor: status == PassengerStatus.notBoarded
                                            ? Colors.white
                                            : Colors.black87,
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                      ),
                                      child: const Text('✗ Not Boarded',
                                          style: TextStyle(fontSize: 12)),
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
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: isLoading
                      ? const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('DEPART FROM STOP',
                          style: TextStyle(fontWeight: FontWeight.bold)),
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
              Text(
                'End Trip - Enter Odometer Reading',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800]),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: endOdometerController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Ending Odometer (km)',
              hintText: 'Enter current odometer reading',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (value) => setState(() {}),
          ),
          if (endOdometerController.text.isNotEmpty && startOdometerController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Trip Distance: ${(double.tryParse(endOdometerController.text) ?? 0) - (double.tryParse(startOdometerController.text) ?? 0)} km',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _captureOdometerPhoto(false),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: endOdometerPhoto != null ? Colors.green[50] : Colors.white,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    endOdometerPhoto != null ? Icons.check_circle : Icons.camera_alt,
                    color: endOdometerPhoto != null ? Colors.green : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    endOdometerPhoto != null ? 'Photo Captured ✓' : 'Capture End Odometer Photo',
                    style: TextStyle(
                      color: endOdometerPhoto != null ? Colors.green : Colors.grey[600],
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
              onPressed: (isLoading || endOdometerController.text.isEmpty || endOdometerPhoto == null)
                  ? null
                  : _endTrip,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: isLoading
                  ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('END TRIP',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ FIXED: Add null safety check to _buildCompletedSection
  Widget _buildCompletedSection() {
    final trip = currentTrip;
    if (trip == null) return const Center(child: Text('No trip data available'));

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
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          const SizedBox(height: 8),
          Text(
            'Distance Traveled: ${trip.actualDistance?.toStringAsFixed(1) ?? "0"} km',
            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
          ),
          if (currentTripIndex < trips.length - 1) ...[
            const SizedBox(height: 12),
            Text('Loading next trip...', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ],
      ),
    );
  }

  // ========================================================================
  // FILTER HELPER WIDGETS
  // ========================================================================

  Widget _quickChip(String label, String value, String current, ValueChanged<String> onTap,
      {Color color = Colors.blue}) {
    final selected = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? color : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _dateRangeButton({
    required DateTime? fromDate,
    required DateTime? toDate,
    required Function(DateTime, DateTime) onPicked,
    required VoidCallback onClear,
  }) {
    final hasRange = fromDate != null || toDate != null;
    return GestureDetector(
      onTap: () async {
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2024),
          lastDate: DateTime(2030),
          initialDateRange: fromDate != null && toDate != null
              ? DateTimeRange(start: fromDate, end: toDate)
              : null,
          builder: (context, child) => Theme(
            data: ThemeData.light().copyWith(
              colorScheme: const ColorScheme.light(primary: kPrimaryColor),
            ),
            child: child!,
          ),
        );
        if (picked != null) onPicked(picked.start, picked.end);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: hasRange ? kPrimaryColor.withOpacity(0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: hasRange ? kPrimaryColor : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.date_range, size: 14, color: hasRange ? kPrimaryColor : Colors.black87),
            const SizedBox(width: 4),
            Text(
              'Date Range',
              style: TextStyle(
                fontSize: 12,
                color: hasRange ? kPrimaryColor : Colors.black87,
                fontWeight: hasRange ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (hasRange) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 14, color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  // ========================================================================
  // HELPER METHODS
  // ========================================================================

  String _formatTime(dynamic timeValue) {
    if (timeValue == null) return '00:00';
    try {
      final dateTime = DateTime.parse(timeValue.toString());
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '00:00';
    }
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

enum TripStatus { assigned, inProgress, completed, declined }
enum StopStatus { pending, arrived, completed }
enum StopType   { pickup, drop }
enum PassengerStatus { boarded, notBoarded }

class Trip {
  final String id;
  final String customerNumber;
  final String customerName;
  final int    tripNumber;
  TripStatus   status;
  final String scheduledStart;
  final String scheduledEnd;
  final String vehicleNumber;
  final String route;
  final int    totalPassengers;
  final String distance;
  final List<TripStop> stops;
  double?      actualDistance;
  final String? rawPickupTime; // ISO string used by pending-tab filters

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
    this.rawPickupTime,
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