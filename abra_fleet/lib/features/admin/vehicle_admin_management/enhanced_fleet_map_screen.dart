// lib/features/admin/vehicle_admin_management/enhanced_fleet_map_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/core/widgets/fleet_map_widget.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/features/admin/vehicle_admin_management/consecutive_trips_admin.dart';

const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kTextPrimaryColor = Color(0xFF212121);
const Color kTextSecondaryColor = Color(0xFF757575);
const Color kSuccessColor = Color(0xFF4CAF50);
const Color kWarningColor = Color(0xFFFF9800);
const Color kDangerColor = Color(0xFFF44336);
const Color kBackgroundColor = Color(0xFFF5F5F5);

enum VehicleStatus { all, active, idle, offline }
enum TripStatus { all, ongoing, completed, noTrips }

class VehicleData {
  final String id;
  final String registrationNumber;
  final String? driverName;
  final String? driverPhone;
  final String status;
  final Map<String, dynamic>? currentTrip;
  final int tripsToday;
  final double? latitude;
  final double? longitude;
  final DateTime? lastUpdate;
  final String? make;
  final String? model;

  VehicleData({
    required this.id,
    required this.registrationNumber,
    this.driverName,
    this.driverPhone,
    required this.status,
    this.currentTrip,
    required this.tripsToday,
    this.latitude,
    this.longitude,
    this.lastUpdate,
    this.make,
    this.model,
  });

  factory VehicleData.fromJson(Map<String, dynamic> json) {
    // Safe extraction of numeric values
    int safeTripsToday = 0;
    final tripsValue = json['tripsToday'];
    if (tripsValue != null) {
      if (tripsValue is int) {
        safeTripsToday = tripsValue;
      } else if (tripsValue is double) {
        safeTripsToday = tripsValue.toInt();
      } else if (tripsValue is String) {
        safeTripsToday = int.tryParse(tripsValue) ?? 0;
      }
    }

    // Safe extraction of driver information
    String? driverName;
    String? driverPhone;
    
    if (json['driver'] != null) {
      final driver = json['driver'];
      if (driver is Map<String, dynamic>) {
        // Handle name field - could be String or number
        final nameValue = driver['name'];
        if (nameValue != null) {
          driverName = nameValue.toString();
        }
        
        // Handle phone field - could be String or number
        final phoneValue = driver['phone'] ?? driver['phoneNumber'];
        if (phoneValue != null) {
          driverPhone = phoneValue.toString();
        }
      } else if (driver is String) {
        // Driver might be just an ID string
        driverName = driver;
      }
    }

    // Safe extraction of location data - handle both liveLocation and location formats
    double? lat, lng;
    
    // First try liveLocation (from backend)
    if (json['liveLocation'] != null) {
      final liveLocation = json['liveLocation'];
      if (liveLocation is Map<String, dynamic>) {
        if (liveLocation['coordinates'] != null && liveLocation['coordinates'] is List) {
          final coords = liveLocation['coordinates'] as List;
          if (coords.length >= 2) {
            lng = (coords[0] as num?)?.toDouble();
            lat = (coords[1] as num?)?.toDouble();
          }
        } else {
          lat = (liveLocation['latitude'] as num?)?.toDouble();
          lng = (liveLocation['longitude'] as num?)?.toDouble();
        }
      }
    }
    
    // Fallback to location field
    if (lat == null || lng == null) {
      if (json['location'] != null) {
        final location = json['location'];
        if (location is Map<String, dynamic>) {
          if (location['coordinates'] != null && location['coordinates'] is List) {
            final coords = location['coordinates'] as List;
            if (coords.length >= 2) {
              lng = (coords[0] as num?)?.toDouble();
              lat = (coords[1] as num?)?.toDouble();
            }
          } else {
            lat = (location['latitude'] as num?)?.toDouble();
            lng = (location['longitude'] as num?)?.toDouble();
          }
        }
      }
    }

    return VehicleData(
      id: json['_id']?.toString() ?? '',
      registrationNumber: json['registrationNumber']?.toString() ?? 'N/A',
      driverName: driverName,
      driverPhone: driverPhone,
      status: json['status']?.toString() ?? 'idle',
      currentTrip: json['currentTrip'] as Map<String, dynamic>?,
      tripsToday: safeTripsToday,
      latitude: lat,
      longitude: lng,
      lastUpdate: json['lastUpdate'] != null 
          ? DateTime.tryParse(json['lastUpdate'].toString())
          : null,
      make: json['make']?.toString(),
      model: json['model']?.toString(),
    );
  }

  bool get hasLocation => latitude != null && longitude != null && 
                          latitude!.isFinite && longitude!.isFinite &&
                          latitude! >= -90 && latitude! <= 90 &&
                          longitude! >= -180 && longitude! <= 180;
  
  LatLng? get position {
    if (!hasLocation) return null;
    try {
      return LatLng(latitude!, longitude!);
    } catch (e) {
      debugPrint('Error creating LatLng for vehicle $id: $e');
      return null;
    }
  }
  
  String get displayName {
    if (make != null && model != null) {
      return '$make $model ($registrationNumber)';
    }
    return registrationNumber;
  }

  Color get statusColor {
    switch (status.toLowerCase()) {
      case 'active':
        return kSuccessColor;
      case 'idle':
        return kWarningColor;
      default:
        return kDangerColor;
    }
  }

  IconData get statusIcon {
    switch (status.toLowerCase()) {
      case 'active':
        return Icons.check_circle;
      case 'idle':
        return Icons.pause_circle;
      default:
        return Icons.cancel;
    }
  }

  bool get hasOngoingTrip => currentTrip != null;
}

class EnhancedFleetMapScreen extends StatefulWidget {
  const EnhancedFleetMapScreen({Key? key}) : super(key: key);

  @override
  State<EnhancedFleetMapScreen> createState() => _EnhancedFleetMapScreenState();
}

class _EnhancedFleetMapScreenState extends State<EnhancedFleetMapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  
  List<VehicleData> _allVehicles = [];
  List<VehicleData> _filteredVehicles = [];
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _refreshTimer;
  
  // Filter states
  VehicleStatus _selectedVehicleStatus = VehicleStatus.all;
  TripStatus _selectedTripStatus = TripStatus.all;
  bool _showOnlyWithLocation = false;
  String _selectedDriverFilter = 'All';
  String _selectedMakeFilter = 'All';
  String _selectedSortBy = 'Registration';
  
  // UI states
  bool _showFilters = false;
  bool _showVehicleList = true;
  bool _showAdvancedFilters = false;

  @override
  void initState() {
    super.initState();
    _fetchVehicles();
    _startAutoRefresh();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _fetchVehicles();
    });
  }

  void _onSearchChanged() {
    _applyFilters();
  }

  Future<void> _fetchVehicles() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get JWT token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('jwt_token');

      final url = '${ApiConfig.baseUrl}/api/admin/fleet/vehicles/live-status';
      
      debugPrint('📡 Fetching vehicles from: $url');
      debugPrint('🔑 Token present: ${token != null && token.isNotEmpty}');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timed out. Please check if the backend server is running.');
        },
      );

      debugPrint('📥 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final List<dynamic> vehiclesJson = data['data'] ?? [];
          
          setState(() {
            _allVehicles = vehiclesJson
                .map((json) => VehicleData.fromJson(json))
                .toList();
            _isLoading = false;
          });

          _applyFilters();
          _fitMapToVehicles();

          debugPrint('✅ Loaded ${_allVehicles.length} vehicles');
        } else {
          setState(() {
            _errorMessage = data['message'] ?? 'Failed to load vehicles';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Server error: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error fetching vehicles: $e');
      setState(() {
        _errorMessage = 'Network error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    List<VehicleData> filtered = List.from(_allVehicles);

    // Apply search filter
    final searchQuery = _searchController.text.toLowerCase().trim();
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((vehicle) {
        return vehicle.registrationNumber.toLowerCase().contains(searchQuery) ||
               (vehicle.driverName?.toLowerCase().contains(searchQuery) ?? false) ||
               (vehicle.driverPhone?.toLowerCase().contains(searchQuery) ?? false) ||
               (vehicle.make?.toLowerCase().contains(searchQuery) ?? false) ||
               (vehicle.model?.toLowerCase().contains(searchQuery) ?? false) ||
               vehicle.id.toLowerCase().contains(searchQuery);
      }).toList();
    }

    // Apply vehicle status filter
    if (_selectedVehicleStatus != VehicleStatus.all) {
      filtered = filtered.where((vehicle) {
        switch (_selectedVehicleStatus) {
          case VehicleStatus.active:
            return vehicle.status.toLowerCase() == 'active';
          case VehicleStatus.idle:
            return vehicle.status.toLowerCase() == 'idle';
          case VehicleStatus.offline:
            return vehicle.status.toLowerCase() != 'active' && 
                   vehicle.status.toLowerCase() != 'idle';
          default:
            return true;
        }
      }).toList();
    }

    // Apply trip status filter
    if (_selectedTripStatus != TripStatus.all) {
      filtered = filtered.where((vehicle) {
        switch (_selectedTripStatus) {
          case TripStatus.ongoing:
            return vehicle.hasOngoingTrip;
          case TripStatus.completed:
            return !vehicle.hasOngoingTrip && vehicle.tripsToday > 0;
          case TripStatus.noTrips:
            return vehicle.tripsToday == 0;
          default:
            return true;
        }
      }).toList();
    }

    // Apply driver filter
    if (_selectedDriverFilter != 'All') {
      if (_selectedDriverFilter == 'Assigned') {
        filtered = filtered.where((vehicle) => vehicle.driverName != null).toList();
      } else if (_selectedDriverFilter == 'Unassigned') {
        filtered = filtered.where((vehicle) => vehicle.driverName == null).toList();
      }
    }

    // Apply make filter
    if (_selectedMakeFilter != 'All') {
      filtered = filtered.where((vehicle) => 
          vehicle.make?.toLowerCase() == _selectedMakeFilter.toLowerCase()).toList();
    }

    // Apply location filter
    if (_showOnlyWithLocation) {
      filtered = filtered.where((vehicle) => vehicle.hasLocation).toList();
    }

    // Apply sorting
    filtered.sort((a, b) {
      switch (_selectedSortBy) {
        case 'Registration':
          return a.registrationNumber.compareTo(b.registrationNumber);
        case 'Driver':
          final driverA = a.driverName ?? 'ZZZ'; // Put unassigned at end
          final driverB = b.driverName ?? 'ZZZ';
          return driverA.compareTo(driverB);
        case 'Status':
          return a.status.compareTo(b.status);
        case 'Trips Today':
          return b.tripsToday.compareTo(a.tripsToday); // Descending
        case 'Last Update':
          final timeA = a.lastUpdate ?? DateTime(1970);
          final timeB = b.lastUpdate ?? DateTime(1970);
          return timeB.compareTo(timeA); // Most recent first
        case 'Make/Model':
          final makeA = '${a.make ?? ''} ${a.model ?? ''}';
          final makeB = '${b.make ?? ''} ${b.model ?? ''}';
          return makeA.compareTo(makeB);
        default:
          return 0;
      }
    });

    setState(() {
      _filteredVehicles = filtered;
    });
  }

  void _fitMapToVehicles() {
    final vehiclesWithLocation = _filteredVehicles
        .where((v) => v.hasLocation)
        .toList();

    if (vehiclesWithLocation.isNotEmpty) {
      final positions = vehiclesWithLocation
          .map((v) => v.position!)
          .toList();
      
      if (positions.length == 1) {
        _mapController.move(positions.first, 15.0);
      } else {
        final bounds = FleetMapUtils.calculateBounds(positions);
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(50),
          ),
        );
      }
    }
  }

  List<VehicleMarker> _buildVehicleMarkers() {
    try {
      return _filteredVehicles
          .where((vehicle) {
            // Only include vehicles with valid location data
            return vehicle.hasLocation && 
                   vehicle.position != null &&
                   vehicle.id.isNotEmpty &&
                   vehicle.displayName.isNotEmpty;
          })
          .map((vehicle) {
            try {
              return VehicleMarker(
                vehicleId: vehicle.id,
                vehicleName: vehicle.displayName,
                position: vehicle.position!,
                isOnline: vehicle.status.toLowerCase() == 'active',
                lastUpdate: vehicle.lastUpdate ?? DateTime.now(),
                color: vehicle.statusColor,
                icon: vehicle.hasOngoingTrip ? Icons.directions_car : Icons.local_taxi,
              );
            } catch (e) {
              debugPrint('Error creating marker for vehicle ${vehicle.id}: $e');
              return null;
            }
          })
          .whereType<VehicleMarker>() // Filter out null values
          .toList();
    } catch (e) {
      debugPrint('Error building vehicle markers: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: Column(
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: kPrimaryColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fleet Map View',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Real-time Vehicle Tracking',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(_showVehicleList ? Icons.map : Icons.list, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      _showVehicleList = !_showVehicleList;
                    });
                  },
                  tooltip: _showVehicleList ? 'Map Only' : 'Show List',
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _fetchVehicles,
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          
          // Search and Filter Bar
          _buildSearchAndFilterBar(),
          
          // Stats Bar
          if (!_isLoading) _buildStatsBar(),
          
          // Main Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        const Text('Loading fleet data...'),
                      ],
                    ),
                  )
                : _errorMessage != null
                    ? _buildErrorState()
                    : _showVehicleList
                        ? Row(
                            children: [
                              // Map View - Takes up most of the space
                              Expanded(
                                flex: 3, // Increased from 2 to 3 for better map visibility
                                child: Container(
                                  width: double.infinity,
                                  height: double.infinity,
                                  child: _buildMapView(),
                                ),
                              ),
                              // Vehicle List - Fixed width sidebar
                              Container(
                                width: 350, // Reduced from 400 to 350 for more map space
                                height: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border(
                                    left: BorderSide(
                                      color: Colors.grey.shade300,
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: _buildVehicleList(),
                              ),
                            ],
                          )
                        : Container(
                            width: double.infinity,
                            height: double.infinity,
                            child: _buildMapView(),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            children: [
              // Search Field
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search vehicles, drivers, models, or IDs...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              // Filter Toggle Button
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _showFilters = !_showFilters;
                  });
                },
                icon: Icon(_showFilters ? Icons.filter_list_off : Icons.filter_list),
                label: Text(_showFilters ? 'Hide Filters' : 'Filters'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _showFilters ? kPrimaryColor : Colors.grey.shade100,
                  foregroundColor: _showFilters ? Colors.white : kTextPrimaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              
              const SizedBox(width: 8),
              
              // Advanced Filters Toggle
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _showAdvancedFilters = !_showAdvancedFilters;
                  });
                },
                icon: Icon(_showAdvancedFilters ? Icons.tune : Icons.tune),
                label: Text(_showAdvancedFilters ? 'Basic' : 'Advanced'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _showAdvancedFilters ? kWarningColor : Colors.orange.shade100,
                  foregroundColor: _showAdvancedFilters ? Colors.white : Colors.orange.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              
              const SizedBox(width: 8),
              
              // Fit to Vehicles Button
              ElevatedButton.icon(
                onPressed: _fitMapToVehicles,
                icon: const Icon(Icons.center_focus_strong),
                label: const Text('Fit All'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade100,
                  foregroundColor: Colors.blue.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
          
          // Filter Options
          if (_showFilters) ...[
            const SizedBox(height: 16),
            _showAdvancedFilters ? _buildAdvancedFilterOptions() : _buildBasicFilterOptions(),
          ],
        ],
      ),
    );
  }

  Widget _buildBasicFilterOptions() {
    return Row(
      children: [
        // Vehicle Status Filter
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Vehicle Status',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: kTextSecondaryColor,
                ),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<VehicleStatus>(
                value: _selectedVehicleStatus,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: VehicleStatus.values.map((status) {
                  return DropdownMenuItem(
                    value: status,
                    child: Text(_getVehicleStatusLabel(status)),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedVehicleStatus = value!;
                  });
                  _applyFilters();
                },
              ),
            ],
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Trip Status Filter
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Trip Status',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: kTextSecondaryColor,
                ),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<TripStatus>(
                value: _selectedTripStatus,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: TripStatus.values.map((status) {
                  return DropdownMenuItem(
                    value: status,
                    child: Text(_getTripStatusLabel(status)),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedTripStatus = value!;
                  });
                  _applyFilters();
                },
              ),
            ],
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Location Filter
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Location',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: kTextSecondaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Checkbox(
                  value: _showOnlyWithLocation,
                  onChanged: (value) {
                    setState(() {
                      _showOnlyWithLocation = value ?? false;
                    });
                    _applyFilters();
                  },
                ),
                const Text('With GPS only'),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAdvancedFilterOptions() {
    // Get unique makes for filter dropdown
    final uniqueMakes = _allVehicles
        .where((v) => v.make != null)
        .map((v) => v.make!)
        .toSet()
        .toList()
      ..sort();

    return Column(
      children: [
        // First row - Basic filters
        Row(
          children: [
            // Vehicle Status Filter
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Vehicle Status',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: kTextSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<VehicleStatus>(
                    value: _selectedVehicleStatus,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: VehicleStatus.values.map((status) {
                      return DropdownMenuItem(
                        value: status,
                        child: Text(_getVehicleStatusLabel(status)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedVehicleStatus = value!;
                      });
                      _applyFilters();
                    },
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Trip Status Filter
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Trip Status',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: kTextSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<TripStatus>(
                    value: _selectedTripStatus,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: TripStatus.values.map((status) {
                      return DropdownMenuItem(
                        value: status,
                        child: Text(_getTripStatusLabel(status)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedTripStatus = value!;
                      });
                      _applyFilters();
                    },
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Driver Assignment Filter
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Driver Assignment',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: kTextSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: _selectedDriverFilter,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: ['All', 'Assigned', 'Unassigned'].map((filter) {
                      return DropdownMenuItem(
                        value: filter,
                        child: Text(filter),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedDriverFilter = value!;
                      });
                      _applyFilters();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 12),
        
        // Second row - Advanced filters
        Row(
          children: [
            // Vehicle Make Filter
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Vehicle Make',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: kTextSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: _selectedMakeFilter,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: ['All', ...uniqueMakes].map((make) {
                      return DropdownMenuItem(
                        value: make,
                        child: Text(make),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedMakeFilter = value!;
                      });
                      _applyFilters();
                    },
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Sort By Filter
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sort By',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: kTextSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: _selectedSortBy,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: ['Registration', 'Driver', 'Status', 'Trips Today', 'Last Update', 'Make/Model'].map((sort) {
                      return DropdownMenuItem(
                        value: sort,
                        child: Text(sort),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedSortBy = value!;
                      });
                      _applyFilters();
                    },
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Location Filter and Reset Button
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Options',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: kTextSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Checkbox(
                              value: _showOnlyWithLocation,
                              onChanged: (value) {
                                setState(() {
                                  _showOnlyWithLocation = value ?? false;
                                });
                                _applyFilters();
                              },
                            ),
                            const Expanded(child: Text('GPS only', style: TextStyle(fontSize: 12))),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _resetAllFilters,
                        icon: const Icon(Icons.clear_all, size: 16),
                        label: const Text('Reset'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kDangerColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _resetAllFilters() {
    setState(() {
      _selectedVehicleStatus = VehicleStatus.all;
      _selectedTripStatus = TripStatus.all;
      _selectedDriverFilter = 'All';
      _selectedMakeFilter = 'All';
      _selectedSortBy = 'Registration';
      _showOnlyWithLocation = false;
      _searchController.clear();
    });
    _applyFilters();
  }

  Widget _buildStatsBar() {
    final totalVehicles = _allVehicles.length;
    final filteredCount = _filteredVehicles.length;
    final activeCount = _filteredVehicles.where((v) => v.status.toLowerCase() == 'active').length;
    final idleCount = _filteredVehicles.where((v) => v.status.toLowerCase() == 'idle').length;
    final offlineCount = _filteredVehicles.where((v) => 
        v.status.toLowerCase() != 'active' && v.status.toLowerCase() != 'idle').length;
    final ongoingTripsCount = _filteredVehicles.where((v) => v.hasOngoingTrip).length;
    final withLocationCount = _filteredVehicles.where((v) => v.hasLocation).length;
    final assignedDriversCount = _filteredVehicles.where((v) => v.driverName != null).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey.shade50,
      child: Column(
        children: [
          // First row - Main stats
          Row(
            children: [
              _buildStatChip('Total', '$filteredCount/$totalVehicles', kPrimaryColor),
              const SizedBox(width: 8),
              _buildStatChip('Active', '$activeCount', kSuccessColor),
              const SizedBox(width: 8),
              _buildStatChip('Idle', '$idleCount', kWarningColor),
              const SizedBox(width: 8),
              _buildStatChip('Offline', '$offlineCount', kDangerColor),
              const Spacer(),
              Text(
                'Last updated: ${DateTime.now().toString().substring(11, 19)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Second row - Additional stats
          Row(
            children: [
              _buildStatChip('Ongoing Trips', '$ongoingTripsCount', Colors.blue),
              const SizedBox(width: 8),
              _buildStatChip('With GPS', '$withLocationCount', Colors.green),
              const SizedBox(width: 8),
              _buildStatChip('Assigned Drivers', '$assignedDriversCount', Colors.purple),
              const Spacer(),
              if (filteredCount != totalVehicles)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: kWarningColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kWarningColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.filter_list, size: 12, color: kWarningColor),
                      const SizedBox(width: 4),
                      Text(
                        'Filtered',
                        style: TextStyle(
                          fontSize: 11,
                          color: kWarningColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapView() {
    try {
      final vehicleMarkers = _buildVehicleMarkers();
      
      return Container(
        width: double.infinity,
        height: double.infinity,
        child: FleetMapWidget(
          controller: _mapController,
          vehicles: vehicleMarkers,
          showZoomControls: true,
          showMapTypeSelector: true,
          onVehicleTap: (vehicle) {
            try {
              _showVehicleDetails(vehicle.vehicleId);
            } catch (e) {
              debugPrint('Error showing vehicle details: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: ${e.toString()}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          height: double.infinity,
        ),
      );
    } catch (e) {
      debugPrint('Error building map view: $e');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Error loading map: ${e.toString()}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _fetchVehicles();
                });
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildVehicleList() {
    return Column(
      children: [
        // List Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.directions_car, size: 20),
              const SizedBox(width: 8),
              Text(
                'Vehicles (${_filteredVehicles.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        
        // Vehicle List
        Expanded(
          child: _filteredVehicles.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 48, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'No vehicles match your filters',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _filteredVehicles.length,
                  itemBuilder: (context, index) {
                    final vehicle = _filteredVehicles[index];
                    return _buildVehicleListItem(vehicle);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildVehicleListItem(VehicleData vehicle) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: vehicle.statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            vehicle.hasOngoingTrip ? Icons.directions_car : Icons.local_taxi,
            color: vehicle.statusColor,
            size: 20,
          ),
        ),
        title: Text(
          vehicle.registrationNumber,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (vehicle.driverName != null)
              Text(
                'Driver: ${vehicle.driverName}',
                style: const TextStyle(fontSize: 12),
              ),
            Row(
              children: [
                Icon(vehicle.statusIcon, size: 12, color: vehicle.statusColor),
                const SizedBox(width: 4),
                Text(
                  vehicle.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    color: vehicle.statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${vehicle.tripsToday} trips',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (vehicle.hasLocation)
              IconButton(
                icon: const Icon(Icons.my_location, size: 18),
                onPressed: () {
                  _mapController.move(vehicle.position!, 16.0);
                },
                tooltip: 'Locate on Map',
              ),
            if (vehicle.hasOngoingTrip)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: kSuccessColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'TRIP',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: kSuccessColor,
                  ),
                ),
              ),
          ],
        ),
        onTap: () => _showVehicleDetails(vehicle.id),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: kDangerColor),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kTextSecondaryColor),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _fetchVehicles,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showVehicleDetails(String vehicleId) {
    try {
      // First try to find the vehicle in all vehicles
      VehicleData? vehicle;
      
      try {
        vehicle = _allVehicles.firstWhere((v) => v.id == vehicleId);
      } catch (e) {
        // If not found in all vehicles, try filtered vehicles
        if (_filteredVehicles.isNotEmpty) {
          try {
            vehicle = _filteredVehicles.firstWhere((v) => v.id == vehicleId);
          } catch (e) {
            // If still not found, use the first filtered vehicle
            vehicle = _filteredVehicles.first;
          }
        } else {
          // If no vehicles available, show error
          _showVehicleNotFoundDialog();
          return;
        }
      }

      if (vehicle == null) {
        _showVehicleNotFoundDialog();
        return;
      }

      // At this point, vehicle is guaranteed to be non-null
      final nonNullVehicle = vehicle!;

      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: nonNullVehicle.statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.directions_car,
                        color: nonNullVehicle.statusColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nonNullVehicle.displayName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Row(
                            children: [
                              Icon(nonNullVehicle.statusIcon, size: 14, color: nonNullVehicle.statusColor),
                              const SizedBox(width: 4),
                              Text(
                                nonNullVehicle.status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: nonNullVehicle.statusColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 16),
                
                // Vehicle Details
                _buildDetailRow('Registration', nonNullVehicle.registrationNumber),
                if (nonNullVehicle.make != null && nonNullVehicle.make!.isNotEmpty)
                  _buildDetailRow('Make & Model', '${nonNullVehicle.make} ${nonNullVehicle.model ?? ''}'),
                if (nonNullVehicle.driverName != null && nonNullVehicle.driverName!.isNotEmpty)
                  _buildDetailRow('Driver', nonNullVehicle.driverName!),
                if (nonNullVehicle.driverPhone != null && nonNullVehicle.driverPhone!.isNotEmpty)
                  _buildDetailRow('Driver Phone', nonNullVehicle.driverPhone!),
                _buildDetailRow('Trips Today', nonNullVehicle.tripsToday.toString()),
                _buildDetailRow('Current Status', nonNullVehicle.status.toUpperCase()),
                
                if (nonNullVehicle.hasOngoingTrip && nonNullVehicle.currentTrip != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Current Trip',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kSuccessColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kSuccessColor.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Trip ID: ${nonNullVehicle.currentTrip?['_id']?.toString() ?? 'N/A'}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (nonNullVehicle.currentTrip?['pickupLocation'] != null)
                          Text('Pickup: ${nonNullVehicle.currentTrip!['pickupLocation']}'),
                        if (nonNullVehicle.currentTrip?['dropLocation'] != null)
                          Text('Drop: ${nonNullVehicle.currentTrip!['dropLocation']}'),
                      ],
                    ),
                  ),
                ],
                
                if (nonNullVehicle.hasLocation) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            if (nonNullVehicle.position != null) {
                              _mapController.move(nonNullVehicle.position!, 16.0);
                            }
                          },
                          icon: const Icon(Icons.my_location),
                          label: const Text('Show on Map'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            // Navigate to consecutive trips screen
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ConsecutiveTripsAdminScreen(
                                  vehicleId: nonNullVehicle.id,
                                  vehicleNumber: nonNullVehicle.registrationNumber,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.route),
                          label: const Text('View Trips'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kSuccessColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error showing vehicle details: $e');
      _showVehicleNotFoundDialog();
    }
  }

  void _showVehicleNotFoundDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Text('Vehicle Not Found'),
          ],
        ),
        content: const Text(
          'The selected vehicle could not be found or is no longer available. Please refresh the vehicle list and try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _fetchVehicles(); // Refresh the vehicle list
            },
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? 'N/A',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getVehicleStatusLabel(VehicleStatus status) {
    switch (status) {
      case VehicleStatus.all:
        return 'All Status';
      case VehicleStatus.active:
        return 'Active';
      case VehicleStatus.idle:
        return 'Idle';
      case VehicleStatus.offline:
        return 'Offline';
    }
  }

  String _getTripStatusLabel(TripStatus status) {
    switch (status) {
      case TripStatus.all:
        return 'All Trips';
      case TripStatus.ongoing:
        return 'Ongoing Trips';
      case TripStatus.completed:
        return 'Completed Today';
      case TripStatus.noTrips:
        return 'No Trips';
    }
  }
}