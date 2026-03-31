// lib/features/admin/vehicle_admin_management/trip_operations/live_map_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' show cos, sqrt, asin;
import 'package:abra_fleet/core/services/vehicle_service.dart';
import 'package:abra_fleet/features/admin/vehicle_admin_management/trip_operations/emergency_alert_screen.dart';
import 'package:abra_fleet/features/admin/vehicle_admin_management/consecutive_trips_admin.dart';


const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kTextPrimaryColor = Color(0xFF212121);
const Color kTextSecondaryColor = Color(0xFF757575);
const Color kSuccessColor = Color(0xFF4CAF50);
const Color kWarningColor = Color(0xFFFF9800);
const Color kDangerColor = Color(0xFFF44336);
const Color kBusColor = Color(0xFF2196F3);
const Color kCarColor = Color(0xFF9C27B0);

const LatLng DEFAULT_LOCATION = LatLng(13.0243, 77.6461);

class LiveMapScreen extends StatefulWidget {
  final EmergencyAlert? rescueMissionForAlert;
  final String? tripId;
  final String? tripNumber;

  const LiveMapScreen({
    Key? key, 
    this.rescueMissionForAlert,
    this.tripId,
    this.tripNumber,
  }) : super(key: key);

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  final MapController _mapController = MapController();
  final VehicleService _vehicleService = VehicleService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  List<Marker> _markers = [];
  List<Polyline> _polylines = [];
  Timer? _updateTimer;
  bool _isLoading = true;
  bool _isSearching = false;
  String? _errorMessage;
  
  List<VehicleLocationData> _vehicles = [];
  List<VehicleLocationData> _filteredVehicles = [];
  Map<String, List<LatLng>> _vehicleRoutes = {};
  String? _selectedVehicleId;
  bool _isLoadingRoute = false;
  
  LatLng? _searchedLocation;
  List<SearchResult> _searchResults = [];
  Timer? _searchDebounce;
  List<LocationSuggestion> _locationSuggestions = [];
  bool _showSuggestions = false;

  static const double _initialZoom = 12.0;

  // Helper method to safely parse capacity value
  String? _parseCapacityValue(dynamic capacity) {
    try {
      if (capacity == null) return null;
      
      if (capacity is Map && capacity['passengers'] != null) {
        return capacity['passengers'].toString();
      } else if (capacity is num) {
        return capacity.toString();
      } else {
        return capacity.toString();
      }
    } catch (e) {
      print('Error parsing capacity value: $e');
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeLiveTracking();
    // MODIFIED: Removed setting the search controller text in rescue mode to keep it functional.
    // The AppBar title already indicates the current mode.
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initializeLiveTracking() async {
    await _fetchVehiclesFromBackend();
    _startLocationUpdates();
  }

  Future<void> _fetchVehiclesFromBackend() async {
    try {
      if (_vehicles.isEmpty) {
        setState(() => _isLoading = true);
      }
      
      final result = await _vehicleService.getVehicles(limit: 100);
      
      if (result['success']) {
        final vehiclesList = result['data'] as List;
        
        _vehicles = vehiclesList.map((vehicle) {
          LatLng location = DEFAULT_LOCATION;
          
          if (vehicle['liveLocation'] != null) {
            try {
              location = LatLng(
                double.parse(vehicle['liveLocation']['latitude'].toString()),
                double.parse(vehicle['liveLocation']['longitude'].toString()),
              );
            } catch (e) {
              print('Error parsing location: $e, using default');
            }
          }
          
          // Extract driver name safely from driver object or fallback
          String driverName = 'Unassigned';
          if (vehicle['driver'] != null) {
            if (vehicle['driver'] is Map) {
              driverName = vehicle['driver']['name']?.toString() ?? 'Unassigned';
            } else if (vehicle['driver'] is String) {
              driverName = vehicle['driver'];
            }
          } else if (vehicle['driverName'] != null) {
            driverName = vehicle['driverName'].toString();
          }

          // Extract capacity safely from different possible structures
          int capacity = 0;
          if (vehicle['capacity'] != null) {
            if (vehicle['capacity'] is Map) {
              capacity = vehicle['capacity']['passengers'] ?? vehicle['capacity']['seating'] ?? 0;
            } else if (vehicle['capacity'] is num) {
              capacity = vehicle['capacity'].toInt();
            }
          } else if (vehicle['seatingCapacity'] != null) {
            capacity = int.tryParse(vehicle['seatingCapacity'].toString()) ?? 0;
          }

          return VehicleLocationData(
            vehicleId: vehicle['_id'] ?? '',
            vehicleNumber: vehicle['registrationNumber'] ?? 'N/A',
            driverName: driverName,
            vehicleType: vehicle['type'] ?? vehicle['vehicleType'] ?? 'BUS',
            currentLocation: location,
            status: _parseStatus(vehicle['status']),
            passengerCount: vehicle['passengerCount'] ?? 0,
            capacity: capacity,
            speed: double.parse(vehicle['currentSpeed']?.toString() ?? '0'),
            lastUpdate: vehicle['lastLocationUpdate'] != null
                ? DateTime.parse(vehicle['lastLocationUpdate'])
                : DateTime.now(),
          );
        }).toList();
        
        // --- LOGIC BRANCH FOR RESCUE MODE ---
        if (widget.rescueMissionForAlert != null) {
          final alert = widget.rescueMissionForAlert!;
          final crashedLocation = LatLng(alert.latitude!, alert.longitude!);

          // Filter for nearby, available vehicles
          final availableVehicles = _vehicles.where((v) {
            return v.vehicleId != alert.vehicleId && v.status != VehicleStatus.offline;
          }).toList();
          final nearbyVehicles = _findNearestVehicles(crashedLocation, availableVehicles, maxDistanceKm: 25.0);
          _filteredVehicles = nearbyVehicles;

          // MODIFIED: Populate _searchResults so the "Nearby Rescuers" button works immediately.
          _searchResults = nearbyVehicles.map((v) {
            final distance = _calculateDistance(crashedLocation, v.currentLocation);
            return SearchResult(vehicle: v, distance: distance);
          }).toList()..sort((a, b) => a.distance.compareTo(b.distance));

          // Add a special marker for the distressed vehicle
          _markers.add(
            Marker(
              point: crashedLocation,
              width: 90,
              height: 90,
              child: GestureDetector( // MODIFIED: Added GestureDetector to make the marker tappable
                onTap: () => _showDistressAlertDetails(alert),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: kDangerColor, width: 3)
                      ),
                      child: const Icon(Icons.car_crash_sharp, color: kDangerColor, size: 32),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: kDangerColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(alert.vehicleName, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ),
            ),
          );

          // Center map on the crash location
          if (mounted && _mapController.camera.center != crashedLocation) {
             Future.delayed(const Duration(milliseconds: 100), () {
              _mapController.move(crashedLocation, 14.0);
            });
          }
        } else {
          // Normal mode operation
          _filteredVehicles = _vehicles;
          if (_searchedLocation == null) {
            _centerMapOnVehicles();
          }
        }
        
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
        
        _initializeMarkers();
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Failed to fetch vehicles';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching vehicles: $e');
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // MODIFIED: New method to show details of the distressed vehicle.
  void _showDistressAlertDetails(EmergencyAlert alert) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.5,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: kDangerColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.car_crash,
                          color: kDangerColor,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          'Emergency Details',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: kTextPrimaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildInfoRow(Icons.directions_car, 'Vehicle', alert.vehicleName),
                  _buildInfoRow(Icons.person, 'Driver', alert.driverName),
                  _buildInfoRow(Icons.location_on, 'Location', alert.location),
                  _buildInfoRow(Icons.access_time, 'Time', _formatTime(alert.timestamp)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onMarkerTapped(VehicleLocationData vehicle) {
    if (widget.rescueMissionForAlert != null) {
      // In rescue mode, tapping a marker starts the assignment process
      _confirmRescueAssignment(vehicle, widget.rescueMissionForAlert!);
    } else {
      // In normal mode, show options dialog
      _showVehicleOptionsDialog(vehicle);
    }
  }

  void _showVehicleOptionsDialog(VehicleLocationData vehicle) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(vehicle.vehicleNumber),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline, color: kPrimaryColor),
              title: const Text('View Details'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _selectedVehicleId = vehicle.vehicleId;
                });
                _showVehicleDetails(vehicle);
              },
            ),
            ListTile(
              leading: const Icon(Icons.route, color: kSuccessColor),
              title: const Text('Consecutive Trips'),
              onTap: () {
                Navigator.pop(context);
                _onVehicleMarkerTapped(vehicle.vehicleId, vehicle.vehicleNumber);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _onVehicleMarkerTapped(String vehicleId, String vehicleNumber) {
    print('🚗 Vehicle marker tapped: $vehicleNumber ($vehicleId)');
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConsecutiveTripsAdminScreen(
          vehicleId: vehicleId,
          vehicleNumber: vehicleNumber,
        ),
      ),
    );
  }

  void _confirmRescueAssignment(VehicleLocationData rescueVehicle, EmergencyAlert distressedAlert) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Assignment?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('You are assigning:'),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.directions_car, color: kPrimaryColor),
              title: Text('${rescueVehicle.vehicleNumber} (${rescueVehicle.driverName})'),
              subtitle: const Text('To assist'),
            ),
            ListTile(
              leading: const Icon(Icons.car_crash, color: kDangerColor),
              title: Text('${distressedAlert.vehicleName} (${distressedAlert.driverName})'),
              subtitle: Text(distressedAlert.location),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('Confirm & Send'),
            onPressed: () {
              // Pop the dialog
              Navigator.pop(context); 
              // Pop the map screen to return to the alerts page
              Navigator.pop(context); 

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Rescue assignment sent to ${rescueVehicle.driverName}!'),
                  backgroundColor: kSuccessColor,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
  
  VehicleStatus _parseStatus(String? status) {
    switch (status?.toUpperCase()) {
      case 'ACTIVE':
      case 'IN_TRANSIT':
        return VehicleStatus.active;
      case 'IDLE':
      case 'PARKED':
        return VehicleStatus.idle;
      case 'OFFLINE':
      case 'MAINTENANCE':
        return VehicleStatus.offline;
      default:
        return VehicleStatus.idle;
    }
  }

  void _startLocationUpdates() {
    _updateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if(mounted) {
        _fetchVehiclesFromBackend();
      } else {
        timer.cancel();
      }
    });
  }

  void _initializeMarkers() {
    // Clear markers, but keep the special rescue one if it exists
    _markers.removeWhere((m) => m.key != null); 
    
    for (var vehicle in _filteredVehicles) {
      _markers.add(_createMarker(vehicle));
    }
    
    if (_searchedLocation != null) {
      _markers.add(_createSearchMarker(_searchedLocation!));
    }
    
    if(mounted) {
      setState(() {});
    }
  }

  Marker _createSearchMarker(LatLng location) {
    return Marker(
      point: location,
      width: 50,
      height: 50,
      child: const Icon(
        Icons.place,
        color: Colors.red,
        size: 50,
        shadows: [
          Shadow(
            color: Colors.black54,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
    );
  }

  Marker _createMarker(VehicleLocationData vehicle) {
    final markerInfo = _getMarkerInfo(vehicle);
    
    return Marker(
      key: ValueKey(vehicle.vehicleId), // Use a key to differentiate markers
      point: vehicle.currentLocation,
      width: 60,
      height: 80,
      child: GestureDetector(
        onTap: () => _onMarkerTapped(vehicle),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: markerInfo['color'] as Color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                markerInfo['icon'] as IconData,
                color: Colors.white,
                size: 24,
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: markerInfo['color'] as Color, width: 1),
              ),
              child: Text(
                vehicle.vehicleNumber,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: markerInfo['color'] as Color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _getMarkerInfo(VehicleLocationData vehicle) {
    IconData icon;
    Color color;
    
    if (vehicle.vehicleType.toUpperCase().contains('BUS')) {
      icon = Icons.directions_bus;
      color = vehicle.status == VehicleStatus.active ? kBusColor : 
              vehicle.status == VehicleStatus.idle ? kWarningColor : kDangerColor;
    } else if (vehicle.vehicleType.toUpperCase().contains('CAR')) {
      icon = Icons.directions_car;
      color = vehicle.status == VehicleStatus.active ? kCarColor : 
              vehicle.status == VehicleStatus.idle ? kWarningColor : kDangerColor;
    } else if (vehicle.vehicleType.toUpperCase().contains('TRUCK')) {
      icon = Icons.local_shipping;
      color = vehicle.status == VehicleStatus.active ? const Color(0xFFFF6F00) : 
              vehicle.status == VehicleStatus.idle ? kWarningColor : kDangerColor;
    } else {
      icon = Icons.location_on;
      color = kPrimaryColor;
    }
    
    return {'icon': icon, 'color': color};
  }

  void _onSearchChanged(String query) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    
    if (query.isEmpty) {
      setState(() {
        _locationSuggestions.clear();
        _showSuggestions = false;
        _searchResults.clear();
        // MODIFIED: In rescue mode, clearing search should revert to nearby rescuers, not all vehicles.
        if (widget.rescueMissionForAlert == null) {
          _filteredVehicles = _vehicles;
        }
        _searchedLocation = null;
      });
      _initializeMarkers();
      return;
    }
    
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _fetchLocationSuggestions(query);
    });
  }

  Future<void> _fetchLocationSuggestions(String query) async {
    if (query.trim().isEmpty) return;
    
    setState(() => _isSearching = true);
    
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final url = 'https://nominatim.openstreetmap.org/search?q=$encodedQuery&format=json&limit=5&addressdetails=1';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'FleetManagementApp/1.0'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final List<dynamic> results = jsonDecode(response.body);
        
        setState(() {
          _locationSuggestions = results.map((result) => LocationSuggestion(
            displayName: result['display_name'],
            latitude: double.parse(result['lat']),
            longitude: double.parse(result['lon']),
          )).toList();
          _showSuggestions = _locationSuggestions.isNotEmpty;
        });
      }
    } catch (e) {
      print('Error fetching location suggestions: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error searching: ${e.toString()}')),
      );
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<String> _getAddressFromCoordinates(double latitude, double longitude) async {
    try {
      final url = 'https://nominatim.openstreetmap.org/reverse?lat=$latitude&lon=$longitude&format=json&addressdetails=1';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'FleetManagementApp/1.0'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['address'];
        List<String> parts = [];
        
        if (address['road'] != null) parts.add(address['road']);
        if (address['suburb'] != null) parts.add(address['suburb']);
        if (address['city'] != null) parts.add(address['city']);
        else if (address['town'] != null) parts.add(address['town']);
        else if (address['village'] != null) parts.add(address['village']);
        
        if (parts.isEmpty && data['display_name'] != null) {
          final displayParts = (data['display_name'] as String).split(',');
          return displayParts.take(3).join(', ');
        }
        
        return parts.join(', ');
      }
    } catch (e) {
      print('Error fetching address: $e');
    }
    
    return 'Lat: ${latitude.toStringAsFixed(6)}, Lon: ${longitude.toStringAsFixed(6)}';
  }

  void _onLocationSelected(LocationSuggestion location) {
    final searchLocation = LatLng(location.latitude, location.longitude);
    
    _searchFocusNode.unfocus();
    
    final nearbyVehicles = _findNearestVehicles(searchLocation, _vehicles, maxDistanceKm: 50.0);
    
    final results = nearbyVehicles.map((v) {
      final distance = _calculateDistance(searchLocation, v.currentLocation);
      return SearchResult(vehicle: v, distance: distance);
    }).toList()..sort((a, b) => a.distance.compareTo(b.distance));
    
    setState(() {
      _searchedLocation = searchLocation;
      _filteredVehicles = nearbyVehicles;
      _searchResults = results;
      _showSuggestions = false;
      _locationSuggestions.clear();
      _searchController.text = location.displayName.split(',')[0];
    });
    
    _initializeMarkers();
    
    Future.delayed(const Duration(milliseconds: 100), () {
      _mapController.move(searchLocation, 14);
    });
    
    if (_searchResults.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          _showSearchResults();
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No vehicles found within 50km of this location'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Show All',
            onPressed: () {
              setState(() {
                _filteredVehicles = _vehicles;
                _searchedLocation = searchLocation;
              });
              _initializeMarkers();
              _mapController.move(searchLocation, 12);
            },
          ),
        ),
      );
    }
  }

  List<VehicleLocationData> _findNearestVehicles(LatLng location, List<VehicleLocationData> vehicles, {int limit = 20, double maxDistanceKm = 50.0}) {
    final vehiclesWithDistance = vehicles.map((v) {
      final distance = _calculateDistance(location, v.currentLocation);
      return {
        'vehicle': v,
        'distance': distance,
      };
    }).where((item) {
      return (item['distance'] as double) <= maxDistanceKm;
    }).toList();
    
    vehiclesWithDistance.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));
    
    return vehiclesWithDistance
        .take(limit)
        .map((item) => item['vehicle'] as VehicleLocationData)
        .toList();
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((point2.latitude - point1.latitude) * p) / 2 +
        cos(point1.latitude * p) *
            cos(point2.latitude * p) *
            (1 - cos((point2.longitude - point1.longitude) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  void _showSearchResults() {
    // MODIFIED: Ensure there are results before showing the sheet.
    if (_searchResults.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No nearby vehicles to show.')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: kPrimaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Nearby Vehicles (${_searchResults.length})',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final result = _searchResults[index];
                    final vehicle = result.vehicle;
                    final markerInfo = _getMarkerInfo(vehicle);
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      elevation: 2,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: markerInfo['color'] as Color,
                          child: Icon(
                            markerInfo['icon'] as IconData,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          vehicle.vehicleNumber,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.person, size: 14, color: kTextSecondaryColor),
                                const SizedBox(width: 4),
                                Text(
                                  vehicle.driverName,
                                  style: const TextStyle(
                                    color: kTextSecondaryColor,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.speed, size: 14, color: kTextSecondaryColor),
                                const SizedBox(width: 4),
                                Text(
                                  '${vehicle.speed.toStringAsFixed(1)} km/h',
                                  style: const TextStyle(
                                    color: kTextSecondaryColor,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(Icons.people, size: 14, color: kTextSecondaryColor),
                                const SizedBox(width: 4),
                                Text(
                                  '${vehicle.passengerCount}/${vehicle.capacity}',
                                  style: const TextStyle(
                                    color: kTextSecondaryColor,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: kPrimaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                result.distance < 1 
                                    ? '${(result.distance * 1000).toStringAsFixed(0)}m'
                                    : '${result.distance.toStringAsFixed(1)}km',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: kPrimaryColor,
                                  fontSize: 14,
                                ),
                              ),
                              const Text(
                                'away',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: kTextSecondaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _mapController.move(vehicle.currentLocation, 16);
                          _onMarkerTapped(vehicle);
                        },
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

  void _showVehicleDetails(VehicleLocationData vehicle) {
    final distance = _searchedLocation != null 
        ? _calculateDistance(_searchedLocation!, vehicle.currentLocation)
        : null;
    
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: _vehicleService.getVehicleDetailsForMap(vehicle.vehicleId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Loading vehicle details...'),
                          ],
                        ),
                      );
                    }

                    if (snapshot.hasError || !snapshot.hasData || !snapshot.data!['success']) {
                      return _buildVehicleDetailsSheet(vehicle, distance);
                    }

                    final data = snapshot.data!['data'];
                    final vehicleData = data['vehicle'];
                    final assignedCustomersData = data['assignedCustomers'];

                    return SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildVehicleHeader(vehicleData, vehicle, distance),
                          const SizedBox(height: 24),
                          _buildDriverSection(vehicleData, assignedCustomersData),
                          const SizedBox(height: 24),
                          _buildCapacitySection(assignedCustomersData),
                          const SizedBox(height: 24),
                          _buildAssignedCustomersSection(assignedCustomersData),
                          const SizedBox(height: 24),
                          _buildVehicleSpecsSection(vehicleData),
                          const SizedBox(height: 24),
                          _buildLocationSection(vehicle),
                          const SizedBox(height: 24),
                          _buildActionButtons(vehicle),
                          const SizedBox(height: 20),
                        ],
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

  Widget _buildVehicleDetailsSheet(VehicleLocationData vehicle, double? distanceFromSearch) {
    final markerInfo = _getMarkerInfo(vehicle);
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (markerInfo['color'] as Color).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          markerInfo['icon'] as IconData,
                          color: markerInfo['color'] as Color,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vehicle.vehicleNumber,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: kTextPrimaryColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                _buildStatusChip(vehicle.status),
                                const SizedBox(width: 8),
                                Text(
                                  '${vehicle.speed.toStringAsFixed(1)} km/h',
                                  style: const TextStyle(
                                    color: kTextSecondaryColor,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (distanceFromSearch != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.near_me, color: kPrimaryColor),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              distanceFromSearch < 1 
                                  ? '${(distanceFromSearch * 1000).toStringAsFixed(0)} meters from searched location'
                                  : '${distanceFromSearch.toStringAsFixed(2)} km from searched location',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: kPrimaryColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _buildInfoRow(Icons.directions_bus, 'Vehicle Type', vehicle.vehicleType),
                  _buildInfoRow(Icons.person, 'Driver', vehicle.driverName),
                  _buildInfoRow(Icons.people, 'Passengers', 
                    '${vehicle.passengerCount}/${vehicle.capacity}'),
                  
                  FutureBuilder<String>(
                    future: _getAddressFromCoordinates(
                      vehicle.currentLocation.latitude,
                      vehicle.currentLocation.longitude,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Icon(Icons.location_on, size: 20, color: kTextSecondaryColor),
                              const SizedBox(width: 12),
                              const Text(
                                'Location: ',
                                style: TextStyle(
                                  color: kTextSecondaryColor,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ],
                          ),
                        );
                      }
                      
                      return Column(
                        children: [
                          _buildInfoRow(
                            Icons.location_on, 
                            'Location', 
                            snapshot.data ?? 'Unknown location'
                          ),
                          Theme(
                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              childrenPadding: EdgeInsets.zero,
                              title: const Text(
                                'Show GPS Coordinates',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: kTextSecondaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              children: [
                                _buildInfoRow(Icons.gps_fixed, 'Latitude', 
                                  vehicle.currentLocation.latitude.toStringAsFixed(6)),
                                _buildInfoRow(Icons.gps_fixed, 'Longitude', 
                                  vehicle.currentLocation.longitude.toStringAsFixed(6)),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  
                  _buildInfoRow(Icons.access_time, 'Last Update', 
                    _formatTime(vehicle.lastUpdate)),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.phone),
                          label: const Text('Call Driver'),
                          onPressed: vehicle.driverName != 'Unassigned' ? () {} : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.route),
                          label: const Text('View Route'),
                          onPressed: () {
                            Navigator.pop(context);
                            _showVehicleRoute(vehicle);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kPrimaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: kPrimaryColor),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(VehicleStatus status) {
    Color color;
    String label;
    switch (status) {
      case VehicleStatus.active:
        color = kSuccessColor;
        label = 'Active';
        break;
      case VehicleStatus.idle:
        color = kWarningColor;
        label = 'Idle';
        break;
      case VehicleStatus.offline:
        color = kDangerColor;
        label = 'Offline';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: kTextSecondaryColor),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: const TextStyle(
              color: kTextSecondaryColor,
              fontSize: 14,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: kTextPrimaryColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showVehicleRoute(VehicleLocationData vehicle) async {
    setState(() => _isLoadingRoute = true);
    
    _showRouteLoadingDialog();

    try {
      final result = await _vehicleService.getVehicleRouteHistory(
        vehicleId: vehicle.vehicleId,
        days: 1,
      );

      if (mounted) Navigator.pop(context);

      if (result['success']) {
        final routeData = result['data'] as List;
        
        if (routeData.isEmpty) {
          _showNoRouteDialog();
          return;
        }

        List<LatLng> routePoints = [];
        try {
          for (var point in routeData) {
            final lat = double.parse(point['latitude'].toString());
            final lng = double.parse(point['longitude'].toString());
            routePoints.add(LatLng(lat, lng));
          }
        } catch (e) {
          print('Error parsing route points: $e');
          _showErrorDialog('Error parsing route data');
          return;
        }

        setState(() {
          _vehicleRoutes[vehicle.vehicleId] = routePoints;
          _polylines.clear();
          
          final markerInfo = _getMarkerInfo(vehicle);
          _polylines.add(
            Polyline(
              points: routePoints,
              color: markerInfo['color'] as Color,
              strokeWidth: 4.0,
            ),
          );
        });

        _fitBounds(routePoints);
      } else {
        _showErrorDialog(result['message'] ?? 'Failed to fetch route');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      print('Error showing route: $e');
      _showErrorDialog('Error: ${e.toString()}');
    } finally {
      setState(() => _isLoadingRoute = false);
    }
  }

  void _showRouteLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading route history...'),
          ],
        ),
      ),
    );
  }

  void _showNoRouteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No Route Data'),
        content: const Text('No route history available for this vehicle.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _fitBounds(List<LatLng> points) {
    if (points.isEmpty) return;

    double minLat = points[0].latitude;
    double maxLat = points[0].latitude;
    double minLng = points[0].longitude;
    double maxLng = points[0].longitude;

    for (var point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    final bounds = LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  void _centerMapOnVehicles() {
    if (_filteredVehicles.isNotEmpty) {
      final points = _filteredVehicles.map((v) => v.currentLocation).toList();
      _fitBounds(points);
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    if (difference.inSeconds < 60) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _locationSuggestions.clear();
      _showSuggestions = false;
      _searchResults.clear();
       // MODIFIED: In rescue mode, clearing search should revert to nearby rescuers, not all vehicles.
      if (widget.rescueMissionForAlert == null) {
        _filteredVehicles = _vehicles;
      } else {
        // Re-run the logic to find nearby vehicles relative to the crash
        final alert = widget.rescueMissionForAlert!;
        final crashedLocation = LatLng(alert.latitude!, alert.longitude!);
        final availableVehicles = _vehicles.where((v) => v.vehicleId != alert.vehicleId && v.status != VehicleStatus.offline).toList();
        _filteredVehicles = _findNearestVehicles(crashedLocation, availableVehicles, maxDistanceKm: 25.0);
      }
      _searchedLocation = null;
      _polylines.clear();
    });
    _initializeMarkers();
    _centerMapOnVehicles();
  }

  @override
  Widget build(BuildContext context) {
    final bool inRescueMode = widget.rescueMissionForAlert != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: kPrimaryColor,
        elevation: 0,
        title: Text(inRescueMode ? 'Rescue Assignment' : 'Live Vehicle Tracking'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              // MODIFIED: Removed `readOnly` and conditional fill color to make search always active.
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search location (e.g., Kalyan Nagar, Indiranagar)',
                  fillColor: Colors.white,
                  filled: true,
                  prefixIcon: _isSearching 
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : const Icon(Icons.search, color: kPrimaryColor),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: kTextSecondaryColor),
                          onPressed: _clearSearch,
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          if (_isLoading)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading vehicles...'),
                ],
              ),
            )
          else
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: DEFAULT_LOCATION,
                initialZoom: _initialZoom,
                minZoom: 3,
                maxZoom: 18,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.app',
                  maxZoom: 19,
                ),
                PolylineLayer(
                  polylines: _polylines,
                ),
                MarkerLayer(
                  markers: _markers,
                ),
              ],
            ),
          
          if (!inRescueMode && !_showSuggestions)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: _buildVehicleCountCard(),
            ),
          
          if (_showSuggestions && _locationSuggestions.isNotEmpty)
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: GestureDetector(
                onTap: () {},
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 350),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kPrimaryColor.withOpacity(0.2), width: 1),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: kPrimaryColor.withOpacity(0.05),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_searching, color: kPrimaryColor, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                '${_locationSuggestions.length} locations found',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: kPrimaryColor,
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _showSuggestions = false;
                                    _locationSuggestions.clear();
                                  });
                                },
                                child: const Icon(
                                  Icons.close,
                                  size: 20,
                                  color: kTextSecondaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _locationSuggestions.length,
                            separatorBuilder: (context, index) => Divider(
                              height: 1,
                              indent: 56,
                              color: Colors.grey[300],
                            ),
                            itemBuilder: (context, index) {
                              final suggestion = _locationSuggestions[index];
                              final parts = suggestion.displayName.split(',');
                              final mainName = parts.isNotEmpty ? parts[0].trim() : suggestion.displayName;
                              final address = parts.length > 1 ? parts.sublist(1).join(',').trim() : '';
                              
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _onLocationSelected(suggestion),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: kPrimaryColor.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                            Icons.location_on,
                                            color: kPrimaryColor,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                mainName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                  color: kTextPrimaryColor,
                                                ),
                                              ),
                                              if (address.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  address,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: kTextSecondaryColor,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons.arrow_forward_ios,
                                          size: 14,
                                          color: kTextSecondaryColor,
                                        ),
                                      ],
                                    ),
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
              ),
            ),
          
          Positioned(
            right: 16,
            bottom: 80,
            child: Column(
              children: [
                FloatingActionButton(
                  heroTag: 'recenter',
                  onPressed: _centerMapOnVehicles,
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.my_location, color: kPrimaryColor),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'refresh',
                  onPressed: () => _fetchVehiclesFromBackend(),
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.refresh, color: kPrimaryColor),
                ),
              ],
            ),
          ),
          
          // MODIFIED: Replaced the single FAB with a column of FABs for more flexibility.
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (inRescueMode) ...[
                     FloatingActionButton.extended(
                        onPressed: _showSearchResults,
                        backgroundColor: kWarningColor,
                        icon: const Icon(Icons.support, color: Colors.white),
                        label: const Text('Nearby Rescuers', style: TextStyle(color: Colors.white)),
                      ),
                      const SizedBox(height: 12),
                  ],
                  FloatingActionButton.extended(
                    onPressed: _showVehicleList,
                    backgroundColor: kPrimaryColor,
                    icon: const Icon(Icons.list),
                    label: const Text('All Vehicles'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      // MODIFIED: Removed the original FAB to avoid conflicts with the new positioned column of FABs.
      floatingActionButton: null,
    );
  }

  Widget _buildVehicleCountCard() {
    int activeCount = _filteredVehicles.where((v) => v.status == VehicleStatus.active).length;
    int idleCount = _filteredVehicles.where((v) => v.status == VehicleStatus.idle).length;
    int offlineCount = _filteredVehicles.where((v) => v.status == VehicleStatus.offline).length;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildCountChip('Active', activeCount, kSuccessColor),
            _buildCountChip('Idle', idleCount, kWarningColor),
            _buildCountChip('Offline', offlineCount, kDangerColor),
          ],
        ),
      ),
    );
  }

  Widget _buildCountChip(String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: kTextSecondaryColor,
          ),
        ),
      ],
    );
  }

  void _showVehicleList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'All Vehicles (${_vehicles.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _vehicles.length,
                  itemBuilder: (context, index) {
                    final vehicle = _vehicles[index];
                    final markerInfo = _getMarkerInfo(vehicle);
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      elevation: 1,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: markerInfo['color'] as Color,
                          child: Icon(
                            markerInfo['icon'] as IconData,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          vehicle.vehicleNumber,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${vehicle.driverName} • ${vehicle.passengerCount}/${vehicle.capacity}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${vehicle.speed.toStringAsFixed(1)} km/h',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _buildStatusChip(vehicle.status),
                          ],
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _mapController.move(vehicle.currentLocation, 15);
                          _onMarkerTapped(vehicle);
                        },
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

  // Enhanced helper methods for detailed vehicle information display
  Widget _buildVehicleHeader(Map<String, dynamic> vehicleData, VehicleLocationData vehicle, double? distance) {
    final markerInfo = _getMarkerInfo(vehicle);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            (markerInfo['color'] as Color).withOpacity(0.1),
            (markerInfo['color'] as Color).withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: (markerInfo['color'] as Color).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: markerInfo['color'] as Color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  markerInfo['icon'] as IconData,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.vehicleNumber,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: kTextPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${vehicleData['make'] ?? ''} ${vehicleData['model'] ?? ''}'.trim(),
                      style: TextStyle(
                        fontSize: 16,
                        color: kTextSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(vehicle.status),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _getStatusText(vehicle.status),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildInfoChip(Icons.speed, '${vehicle.speed.toStringAsFixed(1)} km/h'),
              const SizedBox(width: 12),
              _buildInfoChip(Icons.access_time, _formatTime(vehicle.lastUpdate)),
              if (distance != null) ...[
                const SizedBox(width: 12),
                _buildInfoChip(Icons.near_me, distance < 1 
                    ? '${(distance * 1000).toStringAsFixed(0)}m away'
                    : '${distance.toStringAsFixed(1)}km away'),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDriverSection(Map<String, dynamic> vehicleData, Map<String, dynamic>? assignedCustomersData) {
    final driver = assignedCustomersData?['driver'];
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person, color: kPrimaryColor, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Assigned Driver',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: kTextPrimaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (driver != null) ...[
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: kPrimaryColor,
                  child: Text(
                    driver['name']?.toString().substring(0, 1).toUpperCase() ?? 'D',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driver['name']?.toString() ?? 'Unknown Driver',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (driver['phone'] != null && driver['phone'].toString().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.phone, size: 14, color: kTextSecondaryColor),
                            const SizedBox(width: 4),
                            Text(
                              driver['phone'].toString(),
                              style: TextStyle(
                                fontSize: 14,
                                color: kTextSecondaryColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (driver['email'] != null && driver['email'].toString().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.email, size: 14, color: kTextSecondaryColor),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                driver['email'].toString(),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: kTextSecondaryColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (driver['phone'] != null && driver['phone'].toString().isNotEmpty)
                  IconButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Calling ${driver['phone']}')),
                      );
                    },
                    icon: const Icon(Icons.call, color: kSuccessColor),
                  ),
              ],
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange[700]),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'No driver assigned to this vehicle',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCapacitySection(Map<String, dynamic>? assignedCustomersData) {
    final capacity = assignedCustomersData?['capacity'];
    if (capacity == null) return const SizedBox.shrink();

    final total = capacity['total'] ?? 0;
    final occupied = capacity['occupied'] ?? 0;
    final available = capacity['available'] ?? 0;
    final percentage = capacity['percentage'] ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.airline_seat_recline_normal, color: kPrimaryColor, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Seat Capacity',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: kTextPrimaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildCapacityCard('Total', total.toString(), kPrimaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCapacityCard('Occupied', occupied.toString(), kWarningColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCapacityCard('Available', available.toString(), kSuccessColor),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Utilization', style: TextStyle(fontWeight: FontWeight.w500)),
                  Text('${percentage.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: percentage / 100,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  percentage > 80 ? kDangerColor : percentage > 50 ? kWarningColor : kSuccessColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCapacityCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
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
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignedCustomersSection(Map<String, dynamic>? assignedCustomersData) {
    final customers = assignedCustomersData?['customers'] as List<dynamic>? ?? [];
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people, color: kSuccessColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Assigned Customers (${customers.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: kTextPrimaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (customers.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey),
                  SizedBox(width: 12),
                  Text(
                    'No customers assigned to this vehicle',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ] else ...[
            ...customers.take(3).map((customer) => _buildCustomerTile(customer)).toList(),
            if (customers.length > 3) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, color: kPrimaryColor, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${customers.length - 3} more customers',
                      style: TextStyle(
                        color: kPrimaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCustomerTile(Map<String, dynamic> customer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: kSuccessColor,
            child: Text(
              customer['customerName']?.toString().substring(0, 1).toUpperCase() ?? 'C',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer['customerName']?.toString() ?? 'Unknown Customer',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (customer['organization'] != null && customer['organization'].toString() != 'N/A') ...[
                  const SizedBox(height: 2),
                  Text(
                    customer['organization'].toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: kTextSecondaryColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (customer['loginTime'] != null && customer['loginTime'].toString() != 'N/A')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: kPrimaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                customer['loginTime'].toString(),
                style: TextStyle(
                  fontSize: 10,
                  color: kPrimaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVehicleSpecsSection(Map<String, dynamic> vehicleData) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: kPrimaryColor, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Vehicle Specifications',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: kTextPrimaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildSpecItem('Type', vehicleData['type']?.toString() ?? 'N/A')),
              Expanded(child: _buildSpecItem('Year', vehicleData['year']?.toString() ?? 'N/A')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildSpecItem('Engine', vehicleData['specifications']?['engineType']?.toString() ?? 'N/A')),
              Expanded(child: _buildSpecItem('Fuel', vehicleData['specifications']?['fuelType']?.toString() ?? 'N/A')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildSpecItem('Mileage', '${vehicleData['specifications']?['mileage']?.toString() ?? 'N/A'} km/l')),
              Expanded(child: _buildSpecItem('Capacity', '${_parseCapacityValue(vehicleData['capacity']) ?? 'N/A'} seats')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpecItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: kTextSecondaryColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildLocationSection(VehicleLocationData vehicle) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on, color: Colors.purple[700], size: 20),
              const SizedBox(width: 8),
              const Text(
                'Current Location',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: kTextPrimaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<String>(
            future: _getAddressFromCoordinates(
              vehicle.currentLocation.latitude,
              vehicle.currentLocation.longitude,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Loading address...'),
                  ],
                );
              }
              
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    snapshot.data ?? 'Unknown location',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Lat: ${vehicle.currentLocation.latitude.toStringAsFixed(6)}, '
                    'Lng: ${vehicle.currentLocation.longitude.toStringAsFixed(6)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: kTextSecondaryColor,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(VehicleLocationData vehicle) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.phone),
            label: const Text('Call Driver'),
            onPressed: vehicle.driverName != 'Unassigned' ? () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Calling ${vehicle.driverName}')),
              );
            } : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.route),
            label: const Text('View Route'),
            onPressed: () {
              Navigator.pop(context);
              _showVehicleRoute(vehicle);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: kPrimaryColor,
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: const BorderSide(color: kPrimaryColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: kTextSecondaryColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: kTextSecondaryColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(VehicleStatus status) {
    switch (status) {
      case VehicleStatus.active:
        return kSuccessColor;
      case VehicleStatus.idle:
        return kWarningColor;
      case VehicleStatus.offline:
        return kDangerColor;
    }
  }

  String _getStatusText(VehicleStatus status) {
    switch (status) {
      case VehicleStatus.active:
        return 'ACTIVE';
      case VehicleStatus.idle:
        return 'IDLE';
      case VehicleStatus.offline:
        return 'OFFLINE';
    }
  }
}

class VehicleLocationData {
  final String vehicleId;
  final String vehicleNumber;
  final String driverName;
  final String vehicleType;
  LatLng currentLocation;
  final VehicleStatus status;
  final int passengerCount;
  final int capacity;
  final double speed;
  final DateTime lastUpdate;

  VehicleLocationData({
    required this.vehicleId,
    required this.vehicleNumber,
    required this.driverName,
    required this.vehicleType,
    required this.currentLocation,
    required this.status,
    required this.passengerCount,
    required this.capacity,
    required this.speed,
    required this.lastUpdate,
  });
}

class SearchResult {
  final VehicleLocationData vehicle;
  final double distance;

  SearchResult({
    required this.vehicle,
    required this.distance,
  });
}

class LocationSuggestion {
  final String displayName;
  final double latitude;
  final double longitude;

  LocationSuggestion({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });
}

enum VehicleStatus {
  active,
  idle,
  offline,
}