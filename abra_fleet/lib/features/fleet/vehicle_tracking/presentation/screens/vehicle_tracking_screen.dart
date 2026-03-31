// File: lib/features/fleet/vehicle_tracking/presentation/screens/vehicle_tracking_screen.dart
// Real-time vehicle tracking screen using OpenStreetMap with live location updates

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:abra_fleet/core/services/location_service.dart';
import 'package:abra_fleet/core/services/geocoding_service.dart';
import 'package:abra_fleet/core/widgets/fleet_map_widget.dart';
import 'package:abra_fleet/core/services/backend_connection_manager.dart';

// Mock vehicle data - in production this would come from your backend
class Vehicle {
  final String id;
  final String name;
  final String licensePlate;
  final String driverName;
  final LatLng position;
  final double? heading;
  final double? speed;
  final bool isOnline;
  final DateTime lastUpdate;
  final VehicleStatus status;
  final String? currentTrip;

  const Vehicle({
    required this.id,
    required this.name,
    required this.licensePlate,
    required this.driverName,
    required this.position,
    this.heading,
    this.speed,
    this.isOnline = true,
    required this.lastUpdate,
    this.status = VehicleStatus.idle,
    this.currentTrip,
  });

  Vehicle copyWith({
    String? id,
    String? name,
    String? licensePlate,
    String? driverName,
    LatLng? position,
    double? heading,
    double? speed,
    bool? isOnline,
    DateTime? lastUpdate,
    VehicleStatus? status,
    String? currentTrip,
  }) {
    return Vehicle(
      id: id ?? this.id,
      name: name ?? this.name,
      licensePlate: licensePlate ?? this.licensePlate,
      driverName: driverName ?? this.driverName,
      position: position ?? this.position,
      heading: heading ?? this.heading,
      speed: speed ?? this.speed,
      isOnline: isOnline ?? this.isOnline,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      status: status ?? this.status,
      currentTrip: currentTrip ?? this.currentTrip,
    );
  }
}

enum VehicleStatus {
  idle,
  driving,
  parked,
  maintenance,
  offline,
}

extension VehicleStatusExtension on VehicleStatus {
  String get displayName {
    switch (this) {
      case VehicleStatus.idle:
        return 'Idle';
      case VehicleStatus.driving:
        return 'Driving';
      case VehicleStatus.parked:
        return 'Parked';
      case VehicleStatus.maintenance:
        return 'Maintenance';
      case VehicleStatus.offline:
        return 'Offline';
    }
  }

  Color get color {
    switch (this) {
      case VehicleStatus.idle:
        return Colors.blue;
      case VehicleStatus.driving:
        return Colors.green;
      case VehicleStatus.parked:
        return Colors.orange;
      case VehicleStatus.maintenance:
        return Colors.red;
      case VehicleStatus.offline:
        return Colors.grey;
    }
  }

  IconData get icon {
    switch (this) {
      case VehicleStatus.idle:
        return Icons.directions_car;
      case VehicleStatus.driving:
        return Icons.directions_car;
      case VehicleStatus.parked:
        return Icons.local_parking;
      case VehicleStatus.maintenance:
        return Icons.build;
      case VehicleStatus.offline:
        return Icons.signal_wifi_off;
    }
  }
}

class VehicleTrackingScreen extends StatefulWidget {
  const VehicleTrackingScreen({super.key});

  @override
  State<VehicleTrackingScreen> createState() => _VehicleTrackingScreenState();
}

class _VehicleTrackingScreenState extends State<VehicleTrackingScreen> {
  final LocationService _locationService = LocationService();
  final GeocodingService _geocodingService = GeocodingService();
  Timer? _updateTimer;
  List<Vehicle> _vehicles = [];
  Vehicle? _selectedVehicle;
  LocationData? _currentLocation;
  bool _showCurrentLocation = true;
  bool _isLoading = true;
  MapType _currentMapType = MapType.openStreetMap;

  // Mock data - replace with real backend integration
  final List<Vehicle> _mockVehicles = [
    Vehicle(
      id: 'v001',
      name: 'Cargo Van 1',
      licensePlate: 'AB-123-CD',
      driverName: 'John Smith',
      position: const LatLng(37.7749, -122.4194), // San Francisco
      heading: 45.0,
      speed: 35.5,
      isOnline: true,
      lastUpdate: DateTime.now(),
      status: VehicleStatus.driving,
      currentTrip: 'Trip to Downtown',
    ),
    Vehicle(
      id: 'v002',
      name: 'Delivery Truck 2',
      licensePlate: 'EF-456-GH',
      driverName: 'Sarah Johnson',
      position: const LatLng(37.7849, -122.4094), // Slightly north
      heading: 180.0,
      speed: 0.0,
      isOnline: true,
      lastUpdate: DateTime.now().subtract(const Duration(minutes: 2)),
      status: VehicleStatus.parked,
    ),
    Vehicle(
      id: 'v003',
      name: 'Service Van 3',
      licensePlate: 'IJ-789-KL',
      driverName: 'Mike Wilson',
      position: const LatLng(37.7649, -122.4294), // Slightly south
      heading: 90.0,
      speed: 28.2,
      isOnline: true,
      lastUpdate: DateTime.now().subtract(const Duration(minutes: 1)),
      status: VehicleStatus.driving,
      currentTrip: 'Service Call #1234',
    ),
    Vehicle(
      id: 'v004',
      name: 'Maintenance Truck',
      licensePlate: 'MN-012-OP',
      driverName: 'David Brown',
      position: const LatLng(37.7549, -122.4394), // Southwest
      isOnline: false,
      lastUpdate: DateTime.now().subtract(const Duration(hours: 2)),
      status: VehicleStatus.maintenance,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initializeTracking();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _locationService.stopTracking();
    super.dispose();
  }

  Future<void> _initializeTracking() async {
    // Initialize location service
    await _locationService.initialize();
    
    // Get current location
    _currentLocation = await _locationService.getCurrentLocation();
    
    // Load initial vehicle data
    _vehicles = List.from(_mockVehicles);
    
    // Start real-time updates
    _startRealTimeUpdates();
    
    setState(() {
      _isLoading = false;
    });
  }

  void _startRealTimeUpdates() {
    // Simulate real-time vehicle updates
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _updateVehiclePositions();
    });

    // Start location tracking for current user
    _locationService.startTracking(
      onLocationUpdate: (location) {
        setState(() {
          _currentLocation = location;
        });
      },
    );
  }

  void _updateVehiclePositions() {
    // Simulate vehicle movement for demo purposes
    setState(() {
      _vehicles = _vehicles.map((vehicle) {
        if (!vehicle.isOnline || vehicle.status == VehicleStatus.maintenance) {
          return vehicle;
        }

        // Simulate small position changes
        final random = DateTime.now().millisecond / 1000.0;
        final latOffset = (random - 0.5) * 0.001; // Small random movement
        final lngOffset = (random - 0.3) * 0.001;
        
        final newPosition = LatLng(
          vehicle.position.latitude + latOffset,
          vehicle.position.longitude + lngOffset,
        );

        // Simulate speed changes
        double? newSpeed = vehicle.speed;
        if (vehicle.status == VehicleStatus.driving) {
          newSpeed = 20 + (random * 40); // 20-60 km/h
        } else if (vehicle.status == VehicleStatus.parked) {
          newSpeed = 0.0;
        }

        return vehicle.copyWith(
          position: newPosition,
          speed: newSpeed,
          lastUpdate: DateTime.now(),
        );
      }).toList();
    });
  }

  Future<String> _getAddressFromCoordinates(LatLng position) async {
    try {
      final locationString = '${position.latitude}, ${position.longitude}';
      return await _geocodingService.getAddressFromLocation(locationString);
    } catch (e) {
      return '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
    }
  }

  List<VehicleMarker> _buildVehicleMarkers() {
    return _vehicles.map((vehicle) => VehicleMarker(
      vehicleId: vehicle.id,
      vehicleName: vehicle.name,
      position: vehicle.position,
      heading: vehicle.heading,
      isOnline: vehicle.isOnline,
      lastUpdate: vehicle.lastUpdate,
      color: vehicle.status.color,
      icon: vehicle.status.icon,
    )).toList();
  }

  Widget _buildVehicleList() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Fleet Status (${_vehicles.length} vehicles)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    _buildStatusIndicator('Online', _vehicles.where((v) => v.isOnline).length, Colors.green),
                    const SizedBox(width: 16),
                    _buildStatusIndicator('Offline', _vehicles.where((v) => !v.isOnline).length, Colors.red),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _vehicles.length,
              itemBuilder: (context, index) {
                final vehicle = _vehicles[index];
                return _buildVehicleListItem(vehicle);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$count $label',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleListItem(Vehicle vehicle) {
    final isSelected = _selectedVehicle?.id == vehicle.id;
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue.shade50 : null,
        borderRadius: BorderRadius.circular(8),
        border: isSelected ? Border.all(color: Colors.blue.shade200) : null,
      ),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: vehicle.status.color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: vehicle.status.color,
              width: 2,
            ),
          ),
          child: Icon(
            vehicle.status.icon,
            color: vehicle.status.color,
            size: 20,
          ),
        ),
        title: Text(
          vehicle.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${vehicle.driverName} • ${vehicle.licensePlate}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            Row(
              children: [
                Text(
                  vehicle.status.displayName,
                  style: TextStyle(
                    fontSize: 11,
                    color: vehicle.status.color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (vehicle.speed != null && vehicle.speed! > 0) ...[
                  Text(' • ', style: TextStyle(color: Colors.grey.shade400)),
                  Text(
                    '${vehicle.speed!.toStringAsFixed(0)} km/h',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              vehicle.isOnline ? Icons.circle : Icons.circle_outlined,
              color: vehicle.isOnline ? Colors.green : Colors.red,
              size: 12,
            ),
            const SizedBox(height: 2),
            Text(
              _formatLastUpdate(vehicle.lastUpdate),
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        onTap: () {
          setState(() {
            _selectedVehicle = isSelected ? null : vehicle;
          });
        },
      ),
    );
  }

  String _formatLastUpdate(DateTime lastUpdate) {
    final now = DateTime.now();
    final difference = now.difference(lastUpdate);
    
    if (difference.inMinutes < 1) {
      return 'Now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h';
    } else {
      return '${difference.inDays}d';
    }
  }

  Widget _buildMapControls() {
    return Positioned(
      top: 16,
      left: 16,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(_showCurrentLocation ? Icons.my_location : Icons.location_disabled),
              onPressed: () {
                setState(() {
                  _showCurrentLocation = !_showCurrentLocation;
                });
              },
              tooltip: _showCurrentLocation ? 'Hide My Location' : 'Show My Location',
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: PopupMenuButton<MapType>(
              icon: const Icon(Icons.layers),
              tooltip: 'Map Style',
              onSelected: (MapType type) {
                setState(() {
                  _currentMapType = type;
                });
              },
              itemBuilder: (context) => MapType.values.map((type) => PopupMenuItem(
                value: type,
                child: Row(
                  children: [
                    Icon(
                      _currentMapType == type ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(_getMapTypeLabel(type)),
                  ],
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _getMapTypeLabel(MapType type) {
    switch (type) {
      case MapType.openStreetMap:
        return 'Standard';
      case MapType.openStreetMapHot:
        return 'Humanitarian';
      case MapType.cartoDB:
        return 'Light';
      case MapType.cartoDBDark:
        return 'Dark';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Tracking'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _updateVehiclePositions();
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Stack(
        children: [
          FleetMapWidget(
            initialCenter: _currentLocation?.latLng ?? const LatLng(37.7749, -122.4194),
            initialZoom: 13.0,
            mapType: _currentMapType,
            vehicles: _buildVehicleMarkers(),
            currentLocation: _showCurrentLocation ? _currentLocation : null,
            showCurrentLocation: _showCurrentLocation,
            showZoomControls: true,
            onVehicleTap: (vehicleMarker) {
              final vehicle = _vehicles.firstWhere((v) => v.id == vehicleMarker.vehicleId);
              setState(() {
                _selectedVehicle = vehicle;
              });
              
              // Show vehicle details
              showModalBottomSheet(
                context: context,
                builder: (context) => _buildVehicleDetails(vehicle),
              );
            },
          ),
          _buildMapControls(),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildVehicleList(),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleDetails(Vehicle vehicle) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: vehicle.status.color.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: vehicle.status.color, width: 2),
                ),
                child: Icon(
                  vehicle.status.icon,
                  color: vehicle.status.color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${vehicle.driverName} • ${vehicle.licensePlate}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildDetailRow('Status', vehicle.status.displayName, vehicle.status.color),
          if (vehicle.speed != null)
            _buildDetailRow('Speed', '${vehicle.speed!.toStringAsFixed(1)} km/h'),
          if (vehicle.currentTrip != null)
            _buildDetailRow('Current Trip', vehicle.currentTrip!),
          _buildDetailRow('Last Update', _formatLastUpdate(vehicle.lastUpdate)),
          FutureBuilder<String>(
            future: _getAddressFromCoordinates(vehicle.position),
            builder: (context, snapshot) {
              final address = snapshot.data ?? 
                '${vehicle.position.latitude.toStringAsFixed(6)}, ${vehicle.position.longitude.toStringAsFixed(6)}';
              return _buildDetailRow('Location', address);
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.message),
                  label: const Text('Message Driver'),
                  onPressed: () {
                    // TODO: Implement messaging
                    Navigator.pop(context);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.route),
                  label: const Text('View Route'),
                  onPressed: () {
                    // TODO: Implement route viewing
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.black87,
                fontWeight: valueColor != null ? FontWeight.w500 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
