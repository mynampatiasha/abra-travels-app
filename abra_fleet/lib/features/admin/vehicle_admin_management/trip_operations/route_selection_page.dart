import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/services/enhanced_location_service.dart';
import 'widgets/enhanced_location_search_widget.dart';

class RouteSelectionPage extends StatefulWidget {
  final LatLng? initialStartPoint;
  final LatLng? initialEndPoint;

  const RouteSelectionPage({
    Key? key,
    this.initialStartPoint,
    this.initialEndPoint,
  }) : super(key: key);

  @override
  _RouteSelectionPageState createState() => _RouteSelectionPageState();
}

class _RouteSelectionPageState extends State<RouteSelectionPage> {
  final MapController _mapController = MapController();
  
  LatLng? _startPoint;
  LatLng? _endPoint;
  LocationSearchResult? _startLocationResult;
  LocationSearchResult? _endLocationResult;
  
  List<LatLng> _routePoints = [];
  List<RouteInstruction> _routeInstructions = [];
  double _routeDistance = 0.0;
  double _routeDuration = 0.0;
  
  bool _isLoadingRoute = false;
  String? _routeError;
  
  LatLng? _currentMapCenter;

  // Default center: Bengaluru, Karnataka
  final LatLng _defaultCenter = LatLng(12.9716, 77.5946);

  @override
  void initState() {
    super.initState();
    _startPoint = widget.initialStartPoint;
    _endPoint = widget.initialEndPoint;
    _currentMapCenter = _defaultCenter;
    
    // Load initial addresses for existing points
    if (_startPoint != null) {
      _loadAddressForPoint(_startPoint!, true);
    }
    if (_endPoint != null) {
      _loadAddressForPoint(_endPoint!, false);
    }
    
    // Calculate route if both points exist
    if (_startPoint != null && _endPoint != null) {
      _calculateRoute();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadAddressForPoint(LatLng point, bool isStart) async {
    try {
      final result = await EnhancedLocationService.getAddressFromCoordinates(
        point.latitude,
        point.longitude,
      );
      
      if (result != null && mounted) {
        setState(() {
          if (isStart) {
            _startLocationResult = result;
          } else {
            _endLocationResult = result;
          }
        });
      }
    } catch (e) {
      print('Error loading address: $e');
    }
  }

  /// Calculate actual road route using OSRM (OpenStreetMap Routing Machine)
  Future<void> _calculateRoute() async {
    if (_startPoint == null || _endPoint == null) return;
    
    setState(() {
      _isLoadingRoute = true;
      _routeError = null;
    });

    try {
      // OSRM API endpoint - using public demo server
      final url = 'https://router.project-osrm.org/route/v1/driving/'
          '${_startPoint!.longitude},${_startPoint!.latitude};'
          '${_endPoint!.longitude},${_endPoint!.latitude}'
          '?overview=full&geometries=geojson&steps=true';

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry']['coordinates'] as List;
          
          // Parse route points
          final List<LatLng> points = geometry.map((coord) {
            return LatLng(coord[1] as double, coord[0] as double);
          }).toList();
          
          // Parse route instructions
          final List<RouteInstruction> instructions = [];
          if (route['legs'] != null && route['legs'].isNotEmpty) {
            final steps = route['legs'][0]['steps'] as List;
            for (var step in steps) {
              instructions.add(RouteInstruction(
                instruction: step['maneuver']['type'] ?? 'continue',
                distance: (step['distance'] as num).toDouble(),
                duration: (step['duration'] as num).toDouble(),
                name: step['name'] ?? '',
              ));
            }
          }
          
          setState(() {
            _routePoints = points;
            _routeInstructions = instructions;
            _routeDistance = (route['distance'] as num).toDouble() / 1000; // Convert to km
            _routeDuration = (route['duration'] as num).toDouble() / 60; // Convert to minutes
            _isLoadingRoute = false;
          });
          
          // Fit map bounds to show entire route
          _fitRouteBounds();
        } else {
          throw Exception('No route found');
        }
      } else {
        throw Exception('Failed to fetch route');
      }
    } catch (e) {
      print('Error calculating route: $e');
      setState(() {
        _routeError = 'Could not calculate route. Using direct line.';
        _routePoints = [_startPoint!, _endPoint!];
        _routeDistance = _calculateDirectDistance();
        _routeDuration = (_routeDistance / 40 * 60); // Rough estimate
        _isLoadingRoute = false;
      });
    }
  }

  void _fitRouteBounds() {
    if (_routePoints.isEmpty) return;
    
    double minLat = _routePoints.first.latitude;
    double maxLat = _routePoints.first.latitude;
    double minLng = _routePoints.first.longitude;
    double maxLng = _routePoints.first.longitude;
    
    for (var point in _routePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    
    final bounds = LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );
    
    // Add padding
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  double _calculateDirectDistance() {
    if (_startPoint == null || _endPoint == null) return 0;
    
    final distance = Distance();
    return distance.as(
      LengthUnit.Kilometer,
      _startPoint!,
      _endPoint!,
    );
  }

  void _onStartLocationSelected(LocationSearchResult result) {
    setState(() {
      _startPoint = result.latLng;
      _startLocationResult = result;
    });

    _mapController.move(result.latLng, 15.0);
    
    // Calculate route if both points are set
    if (_endPoint != null) {
      _calculateRoute();
    }
  }

  void _onEndLocationSelected(LocationSearchResult result) {
    setState(() {
      _endPoint = result.latLng;
      _endLocationResult = result;
    });

    _mapController.move(result.latLng, 15.0);
    
    // Calculate route if both points are set
    if (_startPoint != null) {
      _calculateRoute();
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    // If no start point, set it
    if (_startPoint == null) {
      setState(() {
        _startPoint = point;
      });
      _loadAddressForPoint(point, true);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Text('Pickup location set! Now select drop location.'),
            ],
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } 
    // If start point exists but no end point, set end point
    else if (_endPoint == null) {
      setState(() {
        _endPoint = point;
      });
      _loadAddressForPoint(point, false);
      _calculateRoute();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Text('Drop location set! Calculating route...'),
            ],
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
    // If both points exist, show message to clear first
    else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text('Both locations are set. Clear one to select a new location.'),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  void _clearRoute() {
    setState(() {
      _startPoint = null;
      _endPoint = null;
      _startLocationResult = null;
      _endLocationResult = null;
      _routePoints = [];
      _routeInstructions = [];
      _routeDistance = 0.0;
      _routeDuration = 0.0;
      _routeError = null;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Text('Route cleared. Select new locations.'),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.blue.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _swapLocations() {
    if (_startPoint == null || _endPoint == null) return;
    
    setState(() {
      final tempPoint = _startPoint;
      final tempResult = _startLocationResult;
      
      _startPoint = _endPoint;
      _startLocationResult = _endLocationResult;
      
      _endPoint = tempPoint;
      _endLocationResult = tempResult;
    });
    
    _calculateRoute();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.swap_vert, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Text('Locations swapped!'),
          ],
        ),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.blue.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _confirmRoute() {
    if (_startPoint != null && _endPoint != null) {
      Navigator.pop(context, {
        'startPoint': _startPoint,
        'endPoint': _endPoint,
        'startAddress': _startLocationResult?.address ?? 
                       '${_startPoint!.latitude.toStringAsFixed(4)}, ${_startPoint!.longitude.toStringAsFixed(4)}',
        'endAddress': _endLocationResult?.address ?? 
                     '${_endPoint!.latitude.toStringAsFixed(4)}, ${_endPoint!.longitude.toStringAsFixed(4)}',
        'distance': _routeDistance,
        'duration': _routeDuration,
        'routePoints': _routePoints,
      });
    }
  }

  void _showRouteDetails() {
    if (_routeInstructions.isEmpty) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildRouteDetailsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Select Route',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_startPoint != null && _endPoint != null)
            IconButton(
              icon: const Icon(Icons.swap_vert),
              onPressed: _swapLocations,
              tooltip: 'Swap Locations',
            ),
          if (_startPoint != null || _endPoint != null)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: _clearRoute,
              tooltip: 'Clear Route',
            ),
        ],
      ),
      body: Column(
        children: [
          // Location Selection Panel
          _buildLocationSelectionPanel(),
          
          // Route Info Bar
          if (_routePoints.isNotEmpty) _buildRouteInfoBar(),
          
          // Map
          Expanded(
            child: Stack(
              children: [
                _buildMap(),
                
                // Loading overlay
                if (_isLoadingRoute)
                  Container(
                    color: Colors.black26,
                    child: Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              Text(
                                'Calculating route...',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                
                // Map controls
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Column(
                    children: [
                      // Zoom in
                      FloatingActionButton.small(
                        heroTag: 'zoom_in',
                        onPressed: () {
                          final currentZoom = _mapController.camera.zoom;
                          _mapController.move(
                            _mapController.camera.center,
                            currentZoom + 1,
                          );
                        },
                        backgroundColor: Colors.white,
                        child: const Icon(Icons.add, color: Color(0xFF0D47A1)),
                      ),
                      const SizedBox(height: 8),
                      // Zoom out
                      FloatingActionButton.small(
                        heroTag: 'zoom_out',
                        onPressed: () {
                          final currentZoom = _mapController.camera.zoom;
                          _mapController.move(
                            _mapController.camera.center,
                            currentZoom - 1,
                          );
                        },
                        backgroundColor: Colors.white,
                        child: const Icon(Icons.remove, color: Color(0xFF0D47A1)),
                      ),
                      const SizedBox(height: 8),
                      // Fit route
                      if (_routePoints.isNotEmpty)
                        FloatingActionButton.small(
                          heroTag: 'fit_route',
                          onPressed: _fitRouteBounds,
                          backgroundColor: Colors.white,
                          child: const Icon(Icons.fit_screen, color: Color(0xFF0D47A1)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _startPoint != null && _endPoint != null ? _confirmRoute : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D47A1),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              disabledBackgroundColor: Colors.grey.shade300,
              elevation: 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline),
                const SizedBox(width: 12),
                Text(
                  _startPoint != null && _endPoint != null
                      ? 'Confirm Route'
                      : 'Select Both Locations',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationSelectionPanel() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          // Start Location
          _buildLocationSearchCard(
            title: 'Pickup Location',
            icon: Icons.trip_origin,
            color: Colors.green,
            point: _startPoint,
            locationResult: _startLocationResult,
            onLocationSelected: _onStartLocationSelected,
            onClear: () {
              setState(() {
                _startPoint = null;
                _startLocationResult = null;
                _routePoints = [];
                _routeInstructions = [];
              });
            },
          ),
          
          const SizedBox(height: 12),
          
          // End Location
          _buildLocationSearchCard(
            title: 'Drop Location',
            icon: Icons.location_on,
            color: Colors.red,
            point: _endPoint,
            locationResult: _endLocationResult,
            onLocationSelected: _onEndLocationSelected,
            onClear: () {
              setState(() {
                _endPoint = null;
                _endLocationResult = null;
                _routePoints = [];
                _routeInstructions = [];
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSearchCard({
    required String title,
    required IconData icon,
    required Color color,
    required LatLng? point,
    required LocationSearchResult? locationResult,
    required Function(LocationSearchResult) onLocationSelected,
    required VoidCallback onClear,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: point != null ? color.withOpacity(0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: point != null ? color.withOpacity(0.3) : Colors.grey.shade300,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const Spacer(),
                if (point != null)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: onClear,
                    color: Colors.grey.shade600,
                    tooltip: 'Clear',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
          
          // Search Field or Selected Location
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: point == null
                ? EnhancedLocationSearchWidget(
                    hintText: 'Search for $title...',
                    onLocationSelected: onLocationSelected,
                    currentLocation: _currentMapCenter,
                    showCurrentLocationButton: true,
                    showNearbyPlaces: true,
                  )
                : Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: color, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (locationResult != null) ...[
                                Text(
                                  locationResult.shortName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: color,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  locationResult.address,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ] else ...[
                                Text(
                                  'Selected Location',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: color,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteInfoBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(
          top: BorderSide(color: Colors.blue.shade100),
          bottom: BorderSide(color: Colors.blue.shade100),
        ),
      ),
      child: Row(
        children: [
          // Distance
          Expanded(
            child: _buildInfoItem(
              icon: Icons.straighten,
              label: 'Distance',
              value: '${_routeDistance.toStringAsFixed(1)} km',
              color: Colors.blue.shade700,
            ),
          ),
          
          Container(
            width: 1,
            height: 40,
            color: Colors.blue.shade200,
          ),
          
          // Duration
          Expanded(
            child: _buildInfoItem(
              icon: Icons.access_time,
              label: 'Est. Time',
              value: '${_routeDuration.toStringAsFixed(0)} min',
              color: Colors.blue.shade700,
            ),
          ),
          
          Container(
            width: 1,
            height: 40,
            color: Colors.blue.shade200,
          ),
          
          // Route details button
          Expanded(
            child: InkWell(
              onTap: _routeInstructions.isNotEmpty ? _showRouteDetails : null,
              child: _buildInfoItem(
                icon: Icons.route,
                label: 'Details',
                value: _routeInstructions.isEmpty ? 'N/A' : '${_routeInstructions.length} steps',
                color: Colors.blue.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 14,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _defaultCenter,
        initialZoom: 12.0,
        onTap: _onMapTap,
        onPositionChanged: (position, hasGesture) {
          if (hasGesture) {
            _currentMapCenter = position.center;
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.abra.fleet',
        ),
        
        // Route polyline
        if (_routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                color: const Color(0xFF0D47A1),
                strokeWidth: 5.0,
                borderColor: Colors.white,
                borderStrokeWidth: 2.0,
              ),
            ],
          ),
        
        // Markers
        MarkerLayer(
          markers: [
            if (_startPoint != null)
              Marker(
                point: _startPoint!,
                width: 50,
                height: 50,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.trip_origin,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            if (_endPoint != null)
              Marker(
                point: _endPoint!,
                width: 50,
                height: 50,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildRouteDetailsSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    const Icon(Icons.route, color: Color(0xFF0D47A1)),
                    const SizedBox(width: 12),
                    const Text(
                      'Turn-by-Turn Directions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              
              const Divider(height: 1),
              
              // Route summary
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.blue.shade50,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '${_routeDistance.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0D47A1),
                            ),
                          ),
                          Text(
                            'Total Distance',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.grey.shade300,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '${_routeDuration.toStringAsFixed(0)} min',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0D47A1),
                            ),
                          ),
                          Text(
                            'Est. Duration',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const Divider(height: 1),
              
              // Instructions list
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _routeInstructions.length,
                  separatorBuilder: (context, index) => const Divider(height: 24),
                  itemBuilder: (context, index) {
                    final instruction = _routeInstructions[index];
                    return _buildInstructionItem(instruction, index + 1);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInstructionItem(RouteInstruction instruction, int step) {
    IconData icon = Icons.straight;
    Color iconColor = const Color(0xFF0D47A1);
    
    // Map instruction types to icons
    switch (instruction.instruction.toLowerCase()) {
      case 'turn-right':
      case 'turn right':
        icon = Icons.turn_right;
        break;
      case 'turn-left':
      case 'turn left':
        icon = Icons.turn_left;
        break;
      case 'straight':
      case 'continue':
        icon = Icons.straight;
        break;
      case 'slight-right':
        icon = Icons.turn_slight_right;
        break;
      case 'slight-left':
        icon = Icons.turn_slight_left;
        break;
      case 'sharp-right':
        icon = Icons.turn_sharp_right;
        break;
      case 'sharp-left':
        icon = Icons.turn_sharp_left;
        break;
      case 'arrive':
        icon = Icons.flag;
        iconColor = Colors.red;
        break;
      case 'depart':
        icon = Icons.trip_origin;
        iconColor = Colors.green;
        break;
      default:
        icon = Icons.navigation;
    }
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Step number
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(
              '$step',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: iconColor,
              ),
            ),
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Icon
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        
        const SizedBox(width: 12),
        
        // Instruction details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                instruction.name.isNotEmpty
                    ? instruction.name
                    : instruction.instruction.replaceAll('-', ' ').toUpperCase(),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.straighten, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${(instruction.distance / 1000).toStringAsFixed(2)} km',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${(instruction.duration / 60).toStringAsFixed(0)} min',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Route Instruction Model
class RouteInstruction {
  final String instruction;
  final double distance;
  final double duration;
  final String name;

  RouteInstruction({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.name,
  });
}