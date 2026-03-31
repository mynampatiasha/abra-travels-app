// File: lib/core/widgets/fleet_map_widget.dart
// Reusable OpenStreetMap widget for fleet management with vehicle tracking capabilities

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:abra_fleet/core/services/location_service.dart';

enum MapType {
  openStreetMap,
  openStreetMapHot,
  cartoDB,
  cartoDBDark,
}

class VehicleMarker {
  final String vehicleId;
  final String vehicleName;
  final LatLng position;
  final double? heading;
  final bool isOnline;
  final DateTime lastUpdate;
  final Color color;
  final IconData icon;

  const VehicleMarker({
    required this.vehicleId,
    required this.vehicleName,
    required this.position,
    this.heading,
    this.isOnline = true,
    required this.lastUpdate,
    this.color = Colors.blue,
    this.icon = Icons.directions_car,
  });
}

class RoutePolyline {
  final String routeId;
  final List<LatLng> points;
  final Color color;
  final double strokeWidth;
  final String? label;

  const RoutePolyline({
    required this.routeId,
    required this.points,
    this.color = Colors.blue,
    this.strokeWidth = 3.0,
    this.label,
  });
}

class FleetMapWidget extends StatefulWidget {
  final MapController? controller;
  final LatLng? initialCenter;
  final double initialZoom;
  final MapType mapType;
  final List<VehicleMarker> vehicles;
  final List<RoutePolyline> routes;
  final List<Marker>? markers;
  final LocationData? currentLocation;
  final bool showCurrentLocation;
  final bool showZoomControls;
  final bool showMapTypeSelector;
  final bool enableInteraction;
  final Function(LatLng)? onTap;
  final Function(VehicleMarker)? onVehicleTap;
  final Function(LatLng, double)? onPositionChanged;
  final double? height;
  final EdgeInsets? padding;

  const FleetMapWidget({
    super.key,
    this.controller,
    this.initialCenter,
    this.initialZoom = 13.0,
    this.mapType = MapType.openStreetMap,
    this.vehicles = const [],
    this.routes = const [],
    this.markers,
    this.currentLocation,
    this.showCurrentLocation = true,
    this.showZoomControls = true,
    this.showMapTypeSelector = false,
    this.enableInteraction = true,
    this.onTap,
    this.onVehicleTap,
    this.onPositionChanged,
    this.height,
    this.padding,
  });

  @override
  State<FleetMapWidget> createState() => _FleetMapWidgetState();
}

class _FleetMapWidgetState extends State<FleetMapWidget> {
  late MapController _mapController;
  MapType _currentMapType = MapType.openStreetMap;

  @override
  void initState() {
    super.initState();
    _mapController = widget.controller ?? MapController();
    _currentMapType = widget.mapType;
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  String _getTileUrl(MapType mapType) {
    switch (mapType) {
      case MapType.openStreetMap:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapType.openStreetMapHot:
        return 'https://tile.openstreetmap.fr/hot/{z}/{x}/{y}.png';
      case MapType.cartoDB:
        return 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png';
      case MapType.cartoDBDark:
        return 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png';
    }
  }

  String _getMapTypeLabel(MapType mapType) {
    switch (mapType) {
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

  LatLng _getInitialCenter() {
    try {
      if (widget.initialCenter != null) return widget.initialCenter!;
      if (widget.currentLocation != null) return widget.currentLocation!.latLng;
      if (widget.vehicles.isNotEmpty) return widget.vehicles.first.position;
      return const LatLng(12.9716, 77.5946); // Default to Bangalore, India
    } catch (e) {
      debugPrint('Error getting initial center: $e');
      return const LatLng(12.9716, 77.5946); // Default to Bangalore, India
    }
  }

  List<Marker> _buildMarkers() {
    List<Marker> markers = [];

    // Add custom markers if provided
    if (widget.markers != null) {
      markers.addAll(widget.markers!);
    }

    // Add current location marker
    if (widget.showCurrentLocation && widget.currentLocation != null) {
      markers.add(
        Marker(
          point: widget.currentLocation!.latLng,
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.3),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blue, width: 2),
            ),
            child: const Icon(
              Icons.my_location,
              color: Colors.blue,
              size: 20,
            ),
          ),
        ),
      );
    }

    // Add vehicle markers
    for (VehicleMarker vehicle in widget.vehicles) {
      markers.add(
        Marker(
          point: vehicle.position,
          width: 50,
          height: 50,
          child: GestureDetector(
            onTap: () => widget.onVehicleTap?.call(vehicle),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Vehicle marker background
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: vehicle.isOnline ? vehicle.color : Colors.grey,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: vehicle.isOnline ? Colors.white : Colors.grey.shade400,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Transform.rotate(
                    angle: vehicle.heading != null ? (vehicle.heading! * 3.14159 / 180) : 0,
                    child: Icon(
                      vehicle.icon,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                // Online status indicator
                if (vehicle.isOnline)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 1)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return markers;
  }

  List<Polyline> _buildPolylines() {
    return widget.routes.map((route) => Polyline(
      points: route.points,
      color: route.color,
      strokeWidth: route.strokeWidth,
    )).toList();
  }

  Widget _buildMapTypeSelector() {
    if (!widget.showMapTypeSelector) return const SizedBox.shrink();

    return Positioned(
      top: 16,
      right: 16,
      child: Container(
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
          tooltip: 'Map Type',
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
    );
  }

  Widget _buildZoomControls() {
    if (!widget.showZoomControls) return const SizedBox.shrink();

    return Positioned(
      bottom: 16,
      right: 16,
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
            child: Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    try {
                      final camera = _mapController.camera;
                      _mapController.move(camera.center, camera.zoom + 1);
                    } catch (e) {
                      debugPrint('Error zooming in: $e');
                    }
                  },
                  tooltip: 'Zoom In',
                ),
                Container(
                  height: 1,
                  color: Colors.grey.shade300,
                ),
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: () {
                    try {
                      final camera = _mapController.camera;
                      _mapController.move(camera.center, camera.zoom - 1);
                    } catch (e) {
                      debugPrint('Error zooming out: $e');
                    }
                  },
                  tooltip: 'Zoom Out',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (widget.currentLocation != null)
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
                icon: const Icon(Icons.my_location),
                onPressed: () {
                  try {
                    _mapController.move(
                      widget.currentLocation!.latLng,
                      16.0,
                    );
                  } catch (e) {
                    debugPrint('Error moving to current location: $e');
                  }
                },
                tooltip: 'My Location',
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      padding: widget.padding,
      child: Stack(
        children: [
          _buildFlutterMap(),
          _buildMapTypeSelector(),
          _buildZoomControls(),
        ],
      ),
    );
  }

  Widget _buildFlutterMap() {
    try {
      return FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _getInitialCenter(),
          initialZoom: widget.initialZoom,
          interactionOptions: InteractionOptions(
            flags: widget.enableInteraction 
              ? InteractiveFlag.all 
              : InteractiveFlag.none,
          ),
          onTap: widget.onTap != null 
            ? (tapPosition, point) => widget.onTap!(point)
            : null,
          onPositionChanged: widget.onPositionChanged != null
            ? (position, hasGesture) {
                try {
                  widget.onPositionChanged!(
                    position.center, 
                    position.zoom,
                  );
                } catch (e) {
                  debugPrint('Error in onPositionChanged: $e');
                }
              }
            : null,
        ),
        children: [
          TileLayer(
            urlTemplate: _getTileUrl(_currentMapType),
            userAgentPackageName: 'com.example.abra_fleet',
            maxZoom: 19,
            subdomains: const ['a', 'b', 'c'],
          ),
          if (widget.routes.isNotEmpty)
            PolylineLayer(
              polylines: _buildPolylines(),
            ),
          MarkerLayer(
            markers: _buildMarkers(),
          ),
        ],
      );
    } catch (e) {
      debugPrint('Error building FlutterMap: $e');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Map Error: ${e.toString()}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  // Trigger rebuild
                });
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
  }
}

/// Helper methods for common map operations
class FleetMapUtils {
  /// Calculate bounds for a list of points
  static LatLngBounds calculateBounds(List<LatLng> points) {
    if (points.isEmpty) {
      return LatLngBounds(
        const LatLng(0, 0),
        const LatLng(0, 0),
      );
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (LatLng point in points) {
      minLat = minLat < point.latitude ? minLat : point.latitude;
      maxLat = maxLat > point.latitude ? maxLat : point.latitude;
      minLng = minLng < point.longitude ? minLng : point.longitude;
      maxLng = maxLng > point.longitude ? maxLng : point.longitude;
    }

    return LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );
  }

  /// Fit map to show all vehicles
  static void fitToVehicles(MapController controller, List<VehicleMarker> vehicles) {
    if (vehicles.isEmpty) return;

    List<LatLng> points = vehicles.map((v) => v.position).toList();
    LatLngBounds bounds = calculateBounds(points);
    
    controller.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  /// Create vehicle marker with default styling
  static VehicleMarker createVehicleMarker({
    required String vehicleId,
    required String vehicleName,
    required LatLng position,
    double? heading,
    bool isOnline = true,
    Color? color,
    IconData? icon,
  }) {
    return VehicleMarker(
      vehicleId: vehicleId,
      vehicleName: vehicleName,
      position: position,
      heading: heading,
      isOnline: isOnline,
      lastUpdate: DateTime.now(),
      color: color ?? (isOnline ? Colors.blue : Colors.grey),
      icon: icon ?? Icons.directions_car,
    );
  }
}
