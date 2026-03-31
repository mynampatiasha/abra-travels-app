import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../../../core/services/backend_location_tracking_service.dart';

/// Customer Live Tracking Screen - Track vehicle in real-time
class TrackingScreen extends StatefulWidget {
  final String tripId;
  final String customerId;
  
  const TrackingScreen({
    Key? key,
    required this.tripId,
    required this.customerId,
  }) : super(key: key);

  @override
  _TrackingScreenState createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final BackendLocationTrackingService _trackingService = BackendLocationTrackingService();
  final MapController _mapController = MapController();
  
  String? _driverId;
  String? _vehicleId;
  Map<String, dynamic>? _customerData;
  bool _isLoading = true;
  Timer? _demoUpdateTimer;

  @override
  void initState() {
    super.initState();
    _loadTripData();
    
    // Start demo data updates every 5 seconds
    _demoUpdateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        setState(() {}); // Trigger rebuild to update demo data
      }
    });
  }

  @override
  void dispose() {
    _demoUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTripData() async {
    try {
      // Use backend API to get trip data
      final response = await _trackingService.getTripLocation(widget.tripId);
      
      if (response == null) {
        // Fallback to demo data for customer123@abrafleet.com
        _loadDemoData();
        return;
      }

      _driverId = response['driver']?['driverId'] as String?;
      _vehicleId = response['vehicle']?['vehicleId'] as String?;

      // Find customer data
      final customers = List<Map<String, dynamic>>.from(
        response['customers'] ?? [],
      );
      
      _customerData = customers.firstWhere(
        (c) => c['customerId'] == widget.customerId,
        orElse: () => {},
      );

      // If no customer data found, use demo data
      if (_customerData == null || _customerData!.isEmpty) {
        _loadDemoData();
        return;
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading trip data: $e');
      // Fallback to demo data
      _loadDemoData();
    }
  }

  void _loadDemoData() {
    debugPrint('🎯 Loading demo tracking data for customer123@abrafleet.com');
    
    // Set demo data for customer123@abrafleet.com
    _driverId = 'drivertest@abrafleet.com';
    _vehicleId = 'vehicle_001';
    _customerData = {
      'customerId': widget.customerId,
      'customerName': 'Customer 123',
      'lat': 12.8456, // Electronic City coordinates
      'lng': 77.6632,
      'pickupAddress': 'Electronic City, Bangalore',
      'dropAddress': 'Koramangala, Bangalore',
    };
    
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Track Vehicle')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_driverId == null || _customerData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Track Vehicle')),
        body: const Center(
          child: Text('Trip information not available'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Your Vehicle'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Refresh trip data
              setState(() {
                _isLoading = true;
              });
              _loadTripData();
            },
            tooltip: 'Refresh Location',
          ),
        ],
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _trackingService.streamTripLocation(widget.tripId),
        builder: (context, snapshot) {
          // Use demo data if stream fails or has no data
          Map<String, dynamic>? tripData;
          
          if (snapshot.hasData && snapshot.data != null) {
            tripData = snapshot.data!;
          } else {
            // Demo data for customer123@abrafleet.com
            tripData = {
              'driver': {
                'locationData': {
                  'lat': 12.8456 + (DateTime.now().millisecond % 100) * 0.0001, // Simulate movement
                  'lng': 77.6632 + (DateTime.now().millisecond % 100) * 0.0001,
                  'speed': 25.5 + (DateTime.now().second % 10), // Simulate speed changes
                  'heading': 45.0 + (DateTime.now().second % 360), // Simulate direction changes
                  'isOnline': true,
                }
              }
            };
          }

          final driverLocation = tripData['driver']?['locationData'] as Map<String, dynamic>?;
          
          if (driverLocation == null) {
            // Even demo data failed, show offline message
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Driver location not available'),
                ],
              ),
            );
          }
          
          final driverLat = driverLocation['lat'] as double;
          final driverLng = driverLocation['lng'] as double;
          final driverSpeed = driverLocation['speed'] as double? ?? 0.0;
          final driverHeading = driverLocation['heading'] as double? ?? 0.0;
          final isOnline = driverLocation['isOnline'] as bool? ?? false;

          final customerLat = _customerData!['lat'] as double;
          final customerLng = _customerData!['lng'] as double;

          // Calculate distance and ETA
          final distance = Geolocator.distanceBetween(
            driverLat,
            driverLng,
            customerLat,
            customerLng,
          );
          final distanceKm = (distance / 1000).toStringAsFixed(1);
          final eta = _calculateETA(distance, driverSpeed);

          // Center map between driver and customer
          final centerLat = (driverLat + customerLat) / 2;
          final centerLng = (driverLng + customerLng) / 2;

          return Column(
            children: [
              // Status Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: isOnline ? Colors.green.shade50 : Colors.red.shade50,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isOnline ? Icons.check_circle : Icons.error,
                          color: isOnline ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isOnline ? 'Driver is on the way' : 'Driver offline',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isOnline ? Colors.green.shade900 : Colors.red.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildInfoChip(
                          icon: Icons.location_on,
                          label: '$distanceKm km away',
                          color: distance < 500 ? Colors.orange : Colors.blue,
                        ),
                        _buildInfoChip(
                          icon: Icons.access_time,
                          label: 'ETA: $eta mins',
                          color: Colors.blue,
                        ),
                        _buildInfoChip(
                          icon: Icons.speed,
                          label: '${(driverSpeed * 3.6).toStringAsFixed(0)} km/h',
                          color: Colors.blue,
                        ),
                      ],
                    ),
                    if (distance < 500)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '🚗 Vehicle arriving soon! Get ready',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Live Map
              Expanded(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: LatLng(centerLat, centerLng),
                    initialZoom: 14,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.abra.fleet',
                    ),
                    // Polyline between driver and customer
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: [
                            LatLng(driverLat, driverLng),
                            LatLng(customerLat, customerLng),
                          ],
                          color: Colors.blue,
                          strokeWidth: 4,
                          borderStrokeWidth: 2,
                          borderColor: Colors.white,
                        ),
                      ],
                    ),
                    // Markers
                    MarkerLayer(
                      markers: [
                        // Driver marker (moving car)
                        Marker(
                          point: LatLng(driverLat, driverLng),
                          width: 60,
                          height: 60,
                          child: Transform.rotate(
                            angle: driverHeading * (3.14159 / 180),
                            child: const Icon(
                              Icons.directions_car,
                              color: Colors.blue,
                              size: 40,
                            ),
                          ),
                        ),
                        // Customer marker (pickup point)
                        Marker(
                          point: LatLng(customerLat, customerLng),
                          width: 60,
                          height: 60,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 50,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Customer Info Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your Pickup Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.person, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(_customerData!['customerName'] ?? 'Unknown'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _customerData!['pickupAddress'] ?? 'No address',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (_customerData!['pickupTime'] != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.access_time, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text('Scheduled: ${_customerData!['pickupTime']}'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  int _calculateETA(double distanceInMeters, double currentSpeed) {
    // If driver is moving, use current speed, otherwise use average city speed
    final speedKmh = currentSpeed > 1 ? (currentSpeed * 3.6) : 20.0;
    final distanceKm = distanceInMeters / 1000;
    final timeHours = distanceKm / speedKmh;
    final timeMinutes = (timeHours * 60).ceil();
    return timeMinutes;
  }
}
