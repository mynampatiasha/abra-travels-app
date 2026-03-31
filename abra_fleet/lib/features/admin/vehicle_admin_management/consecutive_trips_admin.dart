// lib/features/admin/fleet_management/consecutive_trips_admin.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart'; 

const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kTextPrimaryColor = Color(0xFF212121);
const Color kTextSecondaryColor = Color(0xFF757575);
const Color kSuccessColor = Color(0xFF4CAF50);
const Color kWarningColor = Color(0xFFFF9800);
const Color kDangerColor = Color(0xFFF44336);
const Color kBackgroundColor = Color(0xFFF5F5F5);

class ConsecutiveTripsAdminScreen extends StatefulWidget {
  final String vehicleId;
  final String vehicleNumber;

  const ConsecutiveTripsAdminScreen({
    Key? key,
    required this.vehicleId,
    required this.vehicleNumber,
  }) : super(key: key);

  @override
  State<ConsecutiveTripsAdminScreen> createState() =>
      _ConsecutiveTripsAdminScreenState();
}

class _ConsecutiveTripsAdminScreenState
    extends State<ConsecutiveTripsAdminScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  Map<String, dynamic>? _vehicleData;
  Map<String, dynamic>? _currentTrip;
  List<dynamic> _queuedTrips = [];
  List<dynamic> _filteredQueuedTrips = [];

  IO.Socket? _socket;
  bool _isConnectedToWebSocket = false;

  // Map controller
  final MapController _mapController = MapController();
  List<Marker> _markers = [];
  List<Polyline> _polylines = [];

  // Search and Filter controllers
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedTripTypeFilter = 'All';
  String _selectedStatusFilter = 'All';
  String _selectedSortBy = 'Time';
  bool _isSearchVisible = false;

  @override
  void initState() {
    super.initState();
    _fetchConsecutiveTrips();
    _initializeWebSocket();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  // ============================================
  // SEARCH AND FILTER METHODS
  // ============================================
  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _applyFilters();
    });
  }

  void _applyFilters() {
    _filteredQueuedTrips = _queuedTrips.where((trip) {
      // Search filter
      bool matchesSearch = true;
      if (_searchQuery.isNotEmpty) {
        final tripNumber = (trip['tripNumber'] ?? '').toString().toLowerCase();
        final company = (trip['company'] ?? '').toString().toLowerCase();
        final tripType = (trip['tripType'] ?? '').toString().toLowerCase();
        final passengerCount = (trip['totalPassengers'] ?? '').toString();
        
        matchesSearch = tripNumber.contains(_searchQuery) ||
            company.contains(_searchQuery) ||
            tripType.contains(_searchQuery) ||
            passengerCount.contains(_searchQuery);
      }

      // Trip type filter
      bool matchesTripType = true;
      if (_selectedTripTypeFilter != 'All') {
        matchesTripType = (trip['tripType'] ?? '').toString().toLowerCase() == 
            _selectedTripTypeFilter.toLowerCase();
      }

      // Status filter (for queued trips, we can filter by passenger count ranges)
      bool matchesStatus = true;
      if (_selectedStatusFilter != 'All') {
        final passengerCount = _safeNumericExtract(trip['totalPassengers']);
        switch (_selectedStatusFilter) {
          case 'Small (1-4)':
            matchesStatus = passengerCount >= 1 && passengerCount <= 4;
            break;
          case 'Medium (5-8)':
            matchesStatus = passengerCount >= 5 && passengerCount <= 8;
            break;
          case 'Large (9+)':
            matchesStatus = passengerCount >= 9;
            break;
        }
      }

      return matchesSearch && matchesTripType && matchesStatus;
    }).toList();

    // Apply sorting
    _filteredQueuedTrips.sort((a, b) {
      switch (_selectedSortBy) {
        case 'Time':
          final timeA = a['pickupTime'] ?? a['startTime'] ?? '';
          final timeB = b['pickupTime'] ?? b['startTime'] ?? '';
          return timeA.toString().compareTo(timeB.toString());
        case 'Passengers':
          final countA = _safeNumericExtract(a['totalPassengers']);
          final countB = _safeNumericExtract(b['totalPassengers']);
          return countB.compareTo(countA); // Descending order
        case 'Trip Number':
          final numA = a['tripNumber'] ?? '';
          final numB = b['tripNumber'] ?? '';
          return numA.toString().compareTo(numB.toString());
        case 'Company':
          final companyA = a['company'] ?? '';
          final companyB = b['company'] ?? '';
          return companyA.toString().compareTo(companyB.toString());
        default:
          return 0;
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _applyFilters();
    });
  }

  void _resetFilters() {
    setState(() {
      _selectedTripTypeFilter = 'All';
      _selectedStatusFilter = 'All';
      _selectedSortBy = 'Time';
      _searchController.clear();
      _searchQuery = '';
      _applyFilters();
    });
  }

  // ============================================
  // WEBSOCKET CONNECTION
  // ============================================
  void _initializeWebSocket() {
    try {
      print('🔌 Connecting to WebSocket...');

      _socket = IO.io(
        'http://localhost:3001', // ✅ FIXED PORT
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .build(),
      );

      _socket!.connect();

      _socket!.onConnect((_) {
        print('✅ WebSocket connected');
        setState(() => _isConnectedToWebSocket = true);

        // Identify as admin
        _socket!.emit('identify', {
          'userType': 'admin',
          'userId': 'admin-001',
        });
      });

      _socket!.on('identified', (data) {
        print('✅ Identified by server: $data');
      });

      // Listen for passenger status changes
      _socket!.on('passenger_status_changed', (data) {
        print('📥 Passenger status changed: $data');
        _handlePassengerStatusChange(data);
      });

      // Listen for vehicle location updates
      _socket!.on('vehicle_location_updated', (data) {
        print('📍 Vehicle location updated: $data');
        _handleVehicleLocationUpdate(data);
      });

      // Listen for trip updates
      _socket!.on('trip_started', (data) {
        print('🚀 Trip started: $data');
        _fetchConsecutiveTrips();
      });

      _socket!.on('trip_completed', (data) {
        print('🏁 Trip completed: $data');
        _fetchConsecutiveTrips();
      });

      _socket!.onDisconnect((_) {
        print('❌ WebSocket disconnected');
        setState(() => _isConnectedToWebSocket = false);
      });

      _socket!.onError((error) {
        print('❌ WebSocket error: $error');
      });
    } catch (e) {
      print('❌ WebSocket initialization failed: $e');
    }
  }



  // Handle real-time passenger status updates
  void _handlePassengerStatusChange(dynamic data) {
    if (_currentTrip == null) return;

    final tripId = data['tripId'];
    final rosterId = data['rosterId'];
    final status = data['status'];
    final timestamp = data['timestamp'];

    // Check if this update is for the current trip
    if (_currentTrip!['_id'] != tripId) return;

    setState(() {
      // Update passenger status in current trip
      final passengers = _currentTrip!['passengers'] as List;
      final passengerIndex = passengers.indexWhere((p) =>
          p['rosterId'].toString() == rosterId ||
          p['passengerId'].toString() == rosterId);

      if (passengerIndex != -1) {
        passengers[passengerIndex]['status'] = status;
        if (status == 'picked') {
          passengers[passengerIndex]['pickupTime'] = timestamp;
        } else if (status == 'dropped') {
          passengers[passengerIndex]['dropTime'] = timestamp;
        }
      }

      // Update counts
      _currentTrip!['passengersPickedCount'] = data['pickedCount'] ?? 0;
      _currentTrip!['passengersDroppedCount'] = data['droppedCount'] ?? 0;
      _currentTrip!['passengersWaitingCount'] = data['waitingCount'] ?? 0;

      // Update map markers
      _updateMapMarkers();
    });

    // Show snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          status == 'picked'
              ? '✅ Passenger picked up'
              : '🏁 Passenger dropped off',
        ),
        backgroundColor: kSuccessColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Handle real-time vehicle location updates
  void _handleVehicleLocationUpdate(dynamic data) {
    if (data['vehicleId'] != widget.vehicleId) return;

    setState(() {
      if (_vehicleData != null) {
        _vehicleData!['liveLocation'] = {
          'coordinates': [data['longitude'], data['latitude']],
        };
        _updateMapMarkers();
      }
    });
  }

  // ============================================
  // FETCH CONSECUTIVE TRIPS FROM API
  // ============================================
  Future<void> _fetchConsecutiveTrips() async {
  setState(() {
    _isLoading = true;
    _errorMessage = null;
  });

  try {
    // ✅ GET JWT TOKEN FROM SHARED PREFERENCES
    final prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('jwt_token');

    final url =
        'http://localhost:3001/api/admin/fleet/vehicle/${widget.vehicleId}/consecutive-trips';

    print('📡 Fetching consecutive trips: $url');
    print('🔑 Token present: ${token != null && token.isNotEmpty}');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );

    print('📥 Response status: ${response.statusCode}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        setState(() {
          _vehicleData = data['data']['vehicle'];
          _currentTrip = data['data']['currentTrip'];
          _queuedTrips = data['data']['queuedTrips'] ?? [];
          _filteredQueuedTrips = List.from(_queuedTrips);
          _isLoading = false;
        });

        print('✅ Consecutive trips loaded');
        print('   Current trip: ${_currentTrip?['tripNumber'] ?? 'None'}');
        print('   Queued trips: ${_queuedTrips.length}');

        // Apply filters after loading data
        _applyFilters();

        // Initialize map markers
        _updateMapMarkers();
      } else {
        setState(() {
          _errorMessage = data['message'] ?? 'Failed to load trips';
          _isLoading = false;
        });
      }
    } else if (response.statusCode == 401) {
      setState(() {
        _errorMessage = 'Unauthorized. Please log in again.';
        _isLoading = false;
      });
    } else {
      setState(() {
        _errorMessage = 'Server error: ${response.statusCode}';
        _isLoading = false;
      });
    }
  } catch (e) {
    print('❌ Error fetching consecutive trips: $e');
    setState(() {
      _errorMessage = 'Network error: $e';
      _isLoading = false;
    });
  }

}


// ============================================
// SHOW TRIP DETAILS MODAL (NEW!)
// ============================================
void _showTripDetailsModal(Map<String, dynamic> trip) {
  final passengers = trip['passengers'] as List? ?? [];

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            // ✅ MODAL HEADER
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: kPrimaryColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trip['tripNumber'] ?? 'N/A',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${trip['tripType']?.toUpperCase() ?? 'N/A'} TRIP • ${_safeNumericExtract(trip['totalPassengers'])} Passengers',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ✅ TRIP INFO SUMMARY
            Container(
              padding: const EdgeInsets.all(16),
              color: kPrimaryColor.withOpacity(0.05),
              child: Row(
                children: [
                  Expanded(
                    child: _buildModalInfoTile(
                      Icons.schedule,
                      'Scheduled Time',
                      trip['pickupTime'] ?? trip['scheduledTime'] ?? 'N/A',
                    ),
                  ),
                  Container(width: 1, height: 40, color: Colors.grey[300]),
                  Expanded(
                    child: _buildModalInfoTile(
                      Icons.business,
                      'Company',
                      trip['company'] ?? 'N/A',
                    ),
                  ),
                ],
              ),
            ),

            // ✅ PASSENGERS LIST
            Expanded(
              child: passengers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          const Text(
                            'No passengers assigned',
                            style: TextStyle(
                              fontSize: 16,
                              color: kTextSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: passengers.length,
                      itemBuilder: (context, index) {
                        final passenger = passengers[index];
                        final pickupLocation = passenger['pickupLocation'];
                        final pickupAddress = pickupLocation != null
                            ? (pickupLocation['address'] ?? 'Location not available')
                            : 'Location not available';
                        final estimatedPickupTime = passenger['estimatedPickupTime'] ?? 'N/A';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: kPrimaryColor.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ✅ PASSENGER NAME & SEQUENCE
                                Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: const BoxDecoration(
                                        color: kPrimaryColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${_safeSequenceExtract(passenger['sequence'])}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            passenger['customerName'] ?? 'Unknown',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: kTextPrimaryColor,
                                            ),
                                          ),
                                          if (passenger['customerPhone'] != null)
                                            Text(
                                              passenger['customerPhone'],
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: kTextSecondaryColor,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),

                                // ✅ PICKUP LOCATION
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: kSuccessColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.location_on,
                                        color: kSuccessColor,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Pickup Location',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: kTextSecondaryColor,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            pickupAddress,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: kTextPrimaryColor,
                                            ),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // ✅ ESTIMATED PICKUP TIME
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: kWarningColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.schedule,
                                        color: kWarningColor,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Estimated Pickup Time: ',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: kTextSecondaryColor,
                                        ),
                                      ),
                                      Text(
                                        estimatedPickupTime,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: kWarningColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ============================================
// HELPER FOR MODAL INFO TILES
// ============================================
Widget _buildModalInfoTile(IconData icon, String label, String value) {
  return Column(
    children: [
      Icon(icon, color: kPrimaryColor, size: 20),
      const SizedBox(height: 6),
      Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: kTextSecondaryColor,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: kTextPrimaryColor,
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );
}


  // ============================================
  // UPDATE MAP MARKERS
  // ============================================
  void _updateMapMarkers() {
    _markers.clear();
    _polylines.clear();

    // Add vehicle marker
    if (_vehicleData != null && _vehicleData!['liveLocation'] != null) {
      final coords = _vehicleData!['liveLocation']['coordinates'];
      if (coords != null && coords.length == 2) {
        final vehicleLocation = LatLng(coords[1], coords[0]);

        _markers.add(
          Marker(
            point: vehicleLocation,
            width: 80,
            height: 80,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kPrimaryColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.directions_car,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: kPrimaryColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.vehicleNumber,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        // Center map on vehicle
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _mapController.move(vehicleLocation, 14);
          }
        });
      }
    }

    // Add passenger pickup markers
    if (_currentTrip != null && _currentTrip!['passengers'] != null) {
      final passengers = _currentTrip!['passengers'] as List;
      List<LatLng> routePoints = [];

      for (var i = 0; i < passengers.length; i++) {
        final passenger = passengers[i];
        final status = passenger['status'] ?? 'waiting';

        // For demo, generate locations around Bangalore
        // In production, you'd get actual pickup locations from the roster
        final lat = 12.9716 + (i * 0.01) - 0.05;
        final lng = 77.5946 + (i * 0.01) - 0.05;
        final location = LatLng(lat, lng);

        routePoints.add(location);

        _markers.add(
          Marker(
            point: location,
            width: 60,
            height: 80,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: status == 'picked'
                        ? kSuccessColor
                        : status == 'waiting'
                            ? kWarningColor
                            : Colors.grey,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '${_safeSequenceExtract(passenger['sequence'])}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: status == 'picked'
                          ? kSuccessColor
                          : status == 'waiting'
                              ? kWarningColor
                              : Colors.grey,
                    ),
                  ),
                  child: Text(
                    status == 'picked'
                        ? '✓'
                        : status == 'waiting'
                            ? '⏳'
                            : '○',
                    style: TextStyle(
                      fontSize: 12,
                      color: status == 'picked'
                          ? kSuccessColor
                          : status == 'waiting'
                              ? kWarningColor
                              : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      // Add route polyline
      if (routePoints.isNotEmpty) {
        _polylines.add(
          Polyline(
            points: routePoints,
            color: kPrimaryColor,
            strokeWidth: 3.0,
          ),
        );
      }
    }

    setState(() {});
  }

  // ============================================
  // BUILD UI
  // ============================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        backgroundColor: kPrimaryColor,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.vehicleNumber,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Consecutive Trips',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
        actions: [
          // Search toggle button
          IconButton(
            icon: Icon(_isSearchVisible ? Icons.search_off : Icons.search),
            onPressed: () {
              setState(() {
                _isSearchVisible = !_isSearchVisible;
                if (!_isSearchVisible) {
                  _clearSearch();
                }
              });
            },
          ),
          // Filter button
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
          // WebSocket connection indicator
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isConnectedToWebSocket
                        ? kSuccessColor
                        : kDangerColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isConnectedToWebSocket ? 'LIVE' : 'OFFLINE',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchConsecutiveTrips,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading trips...'),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 64, color: kDangerColor),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: kTextSecondaryColor),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _fetchConsecutiveTrips,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryColor,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchConsecutiveTrips,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildVehicleInfoCard(),
                        const SizedBox(height: 20),
                        if (_isSearchVisible) ...[
                          _buildSearchBar(),
                          const SizedBox(height: 16),
                        ],
                        _buildMapSection(),
                        const SizedBox(height: 20),
                        if (_currentTrip != null) ...[
                          _buildCurrentTripSection(),
                          const SizedBox(height: 20),
                        ] else ...[
                          _buildNoActiveTripCard(),
                          const SizedBox(height: 20),
                        ],
                        if (_queuedTrips.isNotEmpty) ...[
                          _buildQueuedTripsHeader(),
                          const SizedBox(height: 16),
                          _buildQueuedTripsSection(),
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }

  // ============================================
  // VEHICLE INFO CARD
  // ============================================
  Widget _buildVehicleInfoCard() {
    if (_vehicleData == null) return const SizedBox.shrink();

    final driver = _vehicleData!['driver'];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.directions_car,
                    color: kPrimaryColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _vehicleData!['registrationNumber'],
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: kTextPrimaryColor,
                        ),
                      ),
                      Text(
                        _vehicleData!['model'] ?? 'N/A',
                        style: const TextStyle(
                          fontSize: 14,
                          color: kTextSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            if (driver != null) ...[
              _buildInfoRow(
                  Icons.person, 'Driver', driver['name'] ?? 'Unassigned'),
              const SizedBox(height: 8),
              _buildInfoRow(Icons.phone, 'Contact',
                  driver['phone'] ?? 'Not available'),
              const SizedBox(height: 8),
            ],
            _buildInfoRow(Icons.airline_seat_recline_normal, 'Capacity',
                '${_vehicleData!['capacity']?['passengers'] ?? 'N/A'} seats'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: kTextSecondaryColor),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 14,
            color: kTextSecondaryColor,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: kTextPrimaryColor,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================
  // MAP SECTION (NEW!)
  // ============================================
  Widget _buildMapSection() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.map, color: kPrimaryColor, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Live Location & Route',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: kTextPrimaryColor,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isConnectedToWebSocket
                        ? kSuccessColor.withOpacity(0.1)
                        : kDangerColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: _isConnectedToWebSocket
                            ? kSuccessColor
                            : kDangerColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Real-time',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _isConnectedToWebSocket
                              ? kSuccessColor
                              : kDangerColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
            child: SizedBox(
              height: 300,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: const LatLng(12.9716, 77.5946), // Bangalore
                  initialZoom: 13.0,
                  minZoom: 10,
                  maxZoom: 18,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.abrafleet.app',
                  ),
                  PolylineLayer(
                    polylines: _polylines,
                  ),
                  MarkerLayer(
                    markers: _markers,
                  ),
                ],
              ),
            ),
          ),
          if (_currentTrip != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kPrimaryColor.withOpacity(0.05),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: kPrimaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Showing ${(_currentTrip!['passengers'] as List).length} pickup locations',
                      style: const TextStyle(
                        fontSize: 12,
                        color: kPrimaryColor,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _updateMapMarkers,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh'),
                    style: TextButton.styleFrom(
                      foregroundColor: kPrimaryColor,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ============================================
  // CURRENT TRIP SECTION
  // ============================================
  Widget _buildCurrentTripSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.route, color: kPrimaryColor, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Current Active Trip',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: kTextPrimaryColor,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: kWarningColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'In Progress',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 3,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Trip header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _currentTrip!['tripNumber'] ?? 'N/A',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: kPrimaryColor,
                      ),
                    ),
                    Text(
                      'Trip ${_safeNumericExtract(_currentTrip!['tripSequence'])}/${_safeNumericExtract(_currentTrip!['totalTripsForVehicle'])}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: kTextSecondaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Trip type and time
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _currentTrip!['tripType'] == 'login'
                            ? kSuccessColor.withOpacity(0.1)
                            : kPrimaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _currentTrip!['tripType']?.toUpperCase() ?? 'N/A',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _currentTrip!['tripType'] == 'login'
                              ? kSuccessColor
                              : kPrimaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.access_time,
                        size: 16, color: kTextSecondaryColor),
                    const SizedBox(width: 4),
                    Text(
                      '${_currentTrip!['pickupTime'] ?? _currentTrip!['startTime']}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: kTextSecondaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Progress indicator
                _buildProgressIndicator(),
                const SizedBox(height: 20),

                // Passengers list
                const Text(
                  'Passengers',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: kTextPrimaryColor,
                  ),
                ),
                const SizedBox(height: 12),
                ..._buildPassengersList(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressIndicator() {
    final totalPassengers = _safeNumericExtract(_currentTrip!['totalPassengers']);
    final pickedCount = _safeNumericExtract(_currentTrip!['passengersPickedCount']);
    final waitingCount = _safeNumericExtract(_currentTrip!['passengersWaitingCount']);

    final progress =
        totalPassengers > 0 ? pickedCount / totalPassengers : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Passenger Pickup: $pickedCount/$totalPassengers',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: kTextPrimaryColor,
              ),
            ),
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: kPrimaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              progress >= 1.0
                  ? kSuccessColor
                  : progress > 0.5
                      ? kWarningColor
                      : kPrimaryColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$waitingCount passengers waiting',
          style: TextStyle(
            fontSize: 12,
            color: kTextSecondaryColor,
          ),
        ),
      ],
    );
  }

  // ============================================
// BUILD PASSENGERS LIST WITH ACTUAL LOCATIONS
// ============================================
List<Widget> _buildPassengersList() {
  final passengers = _currentTrip!['passengers'] as List? ?? [];

  return passengers.map((passenger) {
    final status = passenger['status'] ?? 'waiting';
    final isPicked = status == 'picked';
    final isDropped = status == 'dropped';

    // ✅ GET ACTUAL PICKUP LOCATION
    final pickupLocation = passenger['pickupLocation'];
    final pickupAddress = pickupLocation != null 
        ? (pickupLocation['address'] ?? 'Location not available') 
        : 'Location not available';

    // ✅ GET ESTIMATED PICKUP TIME
    final estimatedPickupTime = passenger['estimatedPickupTime'] ?? 'N/A';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isPicked
            ? kSuccessColor.withOpacity(0.1)
            : isDropped
                ? Colors.grey.withOpacity(0.1)
                : kWarningColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPicked
              ? kSuccessColor
              : isDropped
                  ? Colors.grey
                  : kWarningColor,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isPicked
                  ? kSuccessColor
                  : isDropped
                      ? Colors.grey
                      : kWarningColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${_safeSequenceExtract(passenger['sequence'])}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  passenger['customerName'] ?? 'Unknown',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: kTextPrimaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                // ✅ SHOW ACTUAL PICKUP ADDRESS
                Text(
                  isPicked
                      ? 'Picked at ${_formatTime(passenger['pickupTime'])}'
                      : isDropped
                          ? 'Dropped'
                          : pickupAddress, // ✅ ACTUAL ADDRESS
                  style: const TextStyle(
                    fontSize: 12,
                    color: kTextSecondaryColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                // ✅ SHOW ESTIMATED PICKUP TIME FOR WAITING PASSENGERS
                if (!isPicked && !isDropped) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 12, color: kWarningColor),
                      const SizedBox(width: 4),
                      Text(
                        'ETA: $estimatedPickupTime',
                        style: const TextStyle(
                          fontSize: 11,
                          color: kWarningColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Icon(
            isPicked
                ? Icons.check_circle
                : isDropped
                    ? Icons.check_circle_outline
                    : Icons.schedule,
            color: isPicked
                ? kSuccessColor
                : isDropped
                    ? Colors.grey
                    : kWarningColor,
            size: 24,
          ),
        ],
      ),
    );
  }).toList();
}

  // ============================================
  // NO ACTIVE TRIP CARD
  // ============================================
  Widget _buildNoActiveTripCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.directions_car_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            const Text(
              'No Active Trip',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: kTextSecondaryColor,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Vehicle is currently idle or between trips',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: kTextSecondaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // SEARCH BAR
  // ============================================
  Widget _buildSearchBar() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.search, color: kPrimaryColor, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Search & Filter Trips',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: kTextPrimaryColor,
                  ),
                ),
                const Spacer(),
                if (_searchQuery.isNotEmpty || 
                    _selectedTripTypeFilter != 'All' || 
                    _selectedStatusFilter != 'All' || 
                    _selectedSortBy != 'Time')
                  TextButton.icon(
                    onPressed: _resetFilters,
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Reset'),
                    style: TextButton.styleFrom(
                      foregroundColor: kDangerColor,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by trip number, company, type, or passenger count...',
                prefixIcon: const Icon(Icons.search, color: kTextSecondaryColor),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: kTextSecondaryColor),
                        onPressed: _clearSearch,
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: kPrimaryColor),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildFilterChip(
                    'Type: $_selectedTripTypeFilter',
                    _selectedTripTypeFilter != 'All',
                    () => _showTripTypeFilter(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFilterChip(
                    'Size: $_selectedStatusFilter',
                    _selectedStatusFilter != 'All',
                    () => _showStatusFilter(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFilterChip(
                    'Sort: $_selectedSortBy',
                    _selectedSortBy != 'Time',
                    () => _showSortOptions(),
                  ),
                ),
              ],
            ),
            if (_filteredQueuedTrips.length != _queuedTrips.length) ...[
              const SizedBox(height: 8),
              Text(
                'Showing ${_filteredQueuedTrips.length} of ${_queuedTrips.length} trips',
                style: const TextStyle(
                  fontSize: 12,
                  color: kTextSecondaryColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? kPrimaryColor.withOpacity(0.1) : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? kPrimaryColor : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive ? kPrimaryColor : kTextSecondaryColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: isActive ? kPrimaryColor : kTextSecondaryColor,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // FILTER DIALOGS
  // ============================================
  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter & Sort Options'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Trip Type', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['All', 'Login', 'Logout'].map((type) {
                return FilterChip(
                  label: Text(type),
                  selected: _selectedTripTypeFilter == type,
                  onSelected: (selected) {
                    setState(() {
                      _selectedTripTypeFilter = type;
                      _applyFilters();
                    });
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Trip Size', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['All', 'Small (1-4)', 'Medium (5-8)', 'Large (9+)'].map((size) {
                return FilterChip(
                  label: Text(size),
                  selected: _selectedStatusFilter == size,
                  onSelected: (selected) {
                    setState(() {
                      _selectedStatusFilter = size;
                      _applyFilters();
                    });
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Sort By', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['Time', 'Passengers', 'Trip Number', 'Company'].map((sort) {
                return FilterChip(
                  label: Text(sort),
                  selected: _selectedSortBy == sort,
                  onSelected: (selected) {
                    setState(() {
                      _selectedSortBy = sort;
                      _applyFilters();
                    });
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _resetFilters();
              Navigator.pop(context);
            },
            child: const Text('Reset All'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showTripTypeFilter() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filter by Trip Type',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...['All', 'Login', 'Logout'].map((type) {
              return ListTile(
                title: Text(type),
                leading: Radio<String>(
                  value: type,
                  groupValue: _selectedTripTypeFilter,
                  onChanged: (value) {
                    setState(() {
                      _selectedTripTypeFilter = value!;
                      _applyFilters();
                    });
                    Navigator.pop(context);
                  },
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  void _showStatusFilter() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filter by Trip Size',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...['All', 'Small (1-4)', 'Medium (5-8)', 'Large (9+)'].map((size) {
              return ListTile(
                title: Text(size),
                leading: Radio<String>(
                  value: size,
                  groupValue: _selectedStatusFilter,
                  onChanged: (value) {
                    setState(() {
                      _selectedStatusFilter = value!;
                      _applyFilters();
                    });
                    Navigator.pop(context);
                  },
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sort Trips By',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...['Time', 'Passengers', 'Trip Number', 'Company'].map((sort) {
              return ListTile(
                title: Text(sort),
                leading: Radio<String>(
                  value: sort,
                  groupValue: _selectedSortBy,
                  onChanged: (value) {
                    setState(() {
                      _selectedSortBy = value!;
                      _applyFilters();
                    });
                    Navigator.pop(context);
                  },
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  // ============================================
  // QUEUED TRIPS HEADER
  // ============================================
  Widget _buildQueuedTripsHeader() {
    return Row(
      children: [
        const Icon(Icons.queue, color: kPrimaryColor, size: 20),
        const SizedBox(width: 8),
        const Text(
          'Queued Trips',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: kTextPrimaryColor,
          ),
        ),
        const Spacer(),
        if (_filteredQueuedTrips.length != _queuedTrips.length) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: kWarningColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Filtered',
              style: TextStyle(
                color: kWarningColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: kPrimaryColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${_filteredQueuedTrips.length}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================
  // QUEUED TRIPS SECTION
  // ============================================
  Widget _buildQueuedTripsSection() {
    if (_filteredQueuedTrips.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(
                _queuedTrips.isEmpty ? Icons.event_available : Icons.search_off,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                _queuedTrips.isEmpty ? 'No Queued Trips' : 'No Matching Trips',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: kTextSecondaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _queuedTrips.isEmpty 
                    ? 'All trips have been completed or no trips are scheduled'
                    : 'Try adjusting your search or filter criteria',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: kTextSecondaryColor,
                ),
              ),
              if (_queuedTrips.isNotEmpty) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Clear Filters'),
                  style: TextButton.styleFrom(
                    foregroundColor: kPrimaryColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      children: _filteredQueuedTrips.map((trip) => _buildQueuedTripCard(trip)).toList(),
    );
  }

  // ============================================
// QUEUED TRIP CARD (CLICKABLE)
// ============================================
Widget _buildQueuedTripCard(Map<String, dynamic> trip) {
  final isHighlighted = _searchQuery.isNotEmpty && (
    (trip['tripNumber'] ?? '').toString().toLowerCase().contains(_searchQuery) ||
    (trip['company'] ?? '').toString().toLowerCase().contains(_searchQuery) ||
    (trip['tripType'] ?? '').toString().toLowerCase().contains(_searchQuery)
  );

  return GestureDetector(
    onTap: () => _showTripDetailsModal(trip), // ✅ ADD CLICK HANDLER
    child: Card(
      elevation: isHighlighted ? 3 : 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isHighlighted 
            ? BorderSide(color: kPrimaryColor.withOpacity(0.5), width: 2)
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
                Expanded(
                  child: Text(
                    trip['tripNumber'] ?? 'N/A',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isHighlighted ? kPrimaryColor : kPrimaryColor,
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Trip ${_safeNumericExtract(trip['tripSequence'])}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: kTextSecondaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ✅ TAP INDICATOR
                    const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: kPrimaryColor,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.schedule, size: 16, color: kTextSecondaryColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Scheduled: ${trip['pickupTime'] ?? trip['scheduledTime'] ?? 'N/A'}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: kTextSecondaryColor,
                    ),
                  ),
                ),
                const Icon(Icons.people, size: 16, color: kTextSecondaryColor),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_safeNumericExtract(trip['totalPassengers'])}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: kPrimaryColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: trip['tripType'] == 'login'
                        ? kSuccessColor.withOpacity(0.1)
                        : kPrimaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    trip['tripType']?.toUpperCase() ?? 'N/A',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: trip['tripType'] == 'login'
                          ? kSuccessColor
                          : kPrimaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trip['company'] ?? 'N/A',
                    style: const TextStyle(
                      fontSize: 12,
                      color: kTextSecondaryColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isHighlighted)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: kWarningColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'MATCH',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            // ✅ TAP TO VIEW HINT
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: kPrimaryColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.touch_app, size: 14, color: kPrimaryColor),
                  SizedBox(width: 6),
                  Text(
                    'Tap to view passenger details',
                    style: TextStyle(
                      fontSize: 11,
                      color: kPrimaryColor,
                      fontWeight: FontWeight.w500,
                    ),
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

  // ============================================
  // HELPER METHODS
  // ============================================
  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return 'N/A';

    try {
      final dateTime = DateTime.parse(timestamp.toString());
      return DateFormat('hh:mm a').format(dateTime);
    } catch (e) {
      return timestamp.toString();
    }
  }

  // ✅ SAFE SEQUENCE EXTRACTION - Handles String/int/double conversion
  int _safeSequenceExtract(dynamic value) {
    if (value == null) return 0;
    
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed ?? 0;
    }
    
    return 0;
  }

  // ✅ SAFE NUMERIC EXTRACTION - Handles String/int/double conversion for counts
  int _safeNumericExtract(dynamic value) {
    if (value == null) return 0;
    
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed ?? 0;
    }
    
    return 0;
  }
}