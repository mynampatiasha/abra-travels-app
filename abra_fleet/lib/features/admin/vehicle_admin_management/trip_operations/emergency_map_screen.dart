import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

// lib/features/admin/vehicle_admin_management/trip_operations/emergency_map_screen.dart

const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kEmergencyColor = Color(0xFFD32F2F);
const Color kSuccessColor = Color(0xFF388E3C);
const Color kWarningColor = Color(0xFFF57C00);

class EmergencyMapScreen extends StatefulWidget {
  final String vehicleName;
  final String vehicleId;
  final String emergencyType;
  final String location;
  final double latitude;
  final double longitude;
  final String description;
  final int passengersAffected;

  const EmergencyMapScreen({
    Key? key,
    required this.vehicleName,
    required this.vehicleId,
    required this.emergencyType,
    required this.location,
    required this.latitude,
    required this.longitude,
    required this.description,
    required this.passengersAffected,
  }) : super(key: key);

  @override
  State<EmergencyMapScreen> createState() => _EmergencyMapScreenState();
}

class _EmergencyMapScreenState extends State<EmergencyMapScreen> {
  final MapController _mapController = MapController();
  bool _showEmergencyServices = true;
  bool _showRoute = false;
  bool _satelliteView = false;

  // Mock nearby emergency services
  final List<Map<String, dynamic>> _nearbyServices = [
    {
      'name': 'City Hospital',
      'type': 'hospital',
      'lat': 12.9750,
      'lng': 77.5980,
      'distance': '2.3 km',
      'eta': '5 min',
      'icon': Icons.local_hospital,
    },
    {
      'name': 'Police Station',
      'type': 'police',
      'lat': 12.9700,
      'lng': 77.5900,
      'distance': '1.5 km',
      'eta': '3 min',
      'icon': Icons.local_police,
    },
    {
      'name': 'Fire Station',
      'type': 'fire',
      'lat': 12.9780,
      'lng': 77.6020,
      'distance': '3.1 km',
      'eta': '7 min',
      'icon': Icons.fire_truck,
    },
  ];

  @override
  void initState() {
    super.initState();
    // Center map on emergency location
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(
        LatLng(widget.latitude, widget.longitude),
        15.0,
      );
    });
  }

  Color _getServiceColor(String type) {
    switch (type) {
      case 'hospital':
        return Colors.red;
      case 'police':
        return Colors.blue;
      case 'fire':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  List<Marker> _buildMarkers() {
    List<Marker> markers = [];

    // Emergency vehicle marker (RED - large)
    markers.add(
      Marker(
        width: 80.0,
        height: 80.0,
        point: LatLng(widget.latitude, widget.longitude),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: kEmergencyColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                widget.vehicleName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              decoration: BoxDecoration(
                color: kEmergencyColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: kEmergencyColor.withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(
                Icons.emergency,
                color: Colors.white,
                size: 32,
              ),
            ),
          ],
        ),
      ),
    );

    // Nearby emergency services markers
    if (_showEmergencyServices) {
      for (var service in _nearbyServices) {
        markers.add(
          Marker(
            width: 60.0,
            height: 60.0,
            point: LatLng(service['lat'], service['lng']),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getServiceColor(service['type']),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    service['icon'],
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // OpenStreetMap
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(widget.latitude, widget.longitude),
              initialZoom: 15.0,
              minZoom: 5.0,
              maxZoom: 18.0,
            ),
            children: [
              TileLayer(
                urlTemplate: _satelliteView
                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.abra.fleet',
              ),
              MarkerLayer(
                markers: _buildMarkers(),
              ),
              // Circle around emergency vehicle
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: LatLng(widget.latitude, widget.longitude),
                    color: kEmergencyColor.withOpacity(0.2),
                    borderColor: kEmergencyColor,
                    borderStrokeWidth: 2,
                    radius: 100, // meters
                  ),
                ],
              ),
            ],
          ),

          // Top Control Panel
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopPanel(),
          ),

          // Map Controls
          Positioned(
            right: 16,
            top: 120,
            child: _buildMapControls(),
          ),

          // Emergency Info Card
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _buildEmergencyInfoCard(),
          ),

          // Nearby Services List
          if (_showEmergencyServices)
            Positioned(
              right: 16,
              top: 250,
              child: _buildNearbyServicesList(),
            ),
        ],
      ),
    );
  }

  Widget _buildTopPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: kEmergencyColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.emergency,
                          color: kEmergencyColor,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.vehicleName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.emergencyType,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: kEmergencyColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.passengersAffected}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapControls() {
    return Column(
      children: [
        // Zoom In
        _buildControlButton(
          icon: Icons.add,
          onPressed: () {
            _mapController.move(
              _mapController.camera.center,
              _mapController.camera.zoom + 1,
            );
          },
        ),
        const SizedBox(height: 8),
        // Zoom Out
        _buildControlButton(
          icon: Icons.remove,
          onPressed: () {
            _mapController.move(
              _mapController.camera.center,
              _mapController.camera.zoom - 1,
            );
          },
        ),
        const SizedBox(height: 8),
        // Center on Emergency
        _buildControlButton(
          icon: Icons.my_location,
          onPressed: () {
            _mapController.move(
              LatLng(widget.latitude, widget.longitude),
              15.0,
            );
          },
          color: kEmergencyColor,
        ),
        const SizedBox(height: 8),
        // Toggle Satellite View
        _buildControlButton(
          icon: _satelliteView ? Icons.map : Icons.satellite,
          onPressed: () {
            setState(() {
              _satelliteView = !_satelliteView;
            });
          },
        ),
        const SizedBox(height: 8),
        // Toggle Services
        _buildControlButton(
          icon: Icons.local_hospital,
          onPressed: () {
            setState(() {
              _showEmergencyServices = !_showEmergencyServices;
            });
          },
          color: _showEmergencyServices ? kSuccessColor : null,
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: color ?? kPrimaryColor),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildEmergencyInfoCard() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Emergency Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              widget.location,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.phone, size: 18),
                    label: const Text('Call 911'),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Calling emergency services...'),
                          backgroundColor: kEmergencyColor,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kEmergencyColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.navigation, size: 18),
                    label: const Text('Navigate'),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Opening navigation...'),
                          backgroundColor: kPrimaryColor,
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kPrimaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _buildNearbyServicesList() {
    return Container(
      width: 200,
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kPrimaryColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.near_me, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'Nearby Services',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(8),
              itemCount: _nearbyServices.length,
              itemBuilder: (context, index) {
                final service = _nearbyServices[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      service['icon'],
                      color: _getServiceColor(service['type']),
                      size: 20,
                    ),
                    title: Text(
                      service['name'],
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '${service['distance']} • ${service['eta']}',
                      style: const TextStyle(fontSize: 10),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.directions, size: 18),
                      onPressed: () {
                        _mapController.move(
                          LatLng(service['lat'], service['lng']),
                          16.0,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}