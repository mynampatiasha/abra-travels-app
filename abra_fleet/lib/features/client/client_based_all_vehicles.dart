// lib/screens/client/client_based_all_vehicles.dart
// ============================================================================
// CLIENT LIVE VEHICLE TRACKING - Domain-Based Fleet Monitoring Dashboard
// ============================================================================
// Features:
// ✅ Real-time vehicle positions filtered by client's email domain
// ✅ 10-second polling for live updates
// ✅ Vehicle markers with status colors
// ✅ Route polylines from location history
// ✅ Stop markers (pickup/drop)
// ✅ Filters: Date, Status
// ✅ Vehicle details panel (click marker)
// ✅ Timeline playback slider
// ✅ Notification alerts badge
// ✅ DOMAIN FILTERING: Only shows trips with passengers from same domain
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:abra_fleet/app/config/api_config.dart';

class ClientBasedAllVehicles extends StatefulWidget {
  const ClientBasedAllVehicles({super.key});

  static const String routeName = '/client/live-tracking';

  @override
  State<ClientBasedAllVehicles> createState() =>
      _ClientBasedAllVehiclesState();
}

class _ClientBasedAllVehiclesState
    extends State<ClientBasedAllVehicles> {
  // ========================================================================
  // STATE VARIABLES
  // ========================================================================
  
  // Map controller
  final MapController _mapController = MapController();
  
  // Polling timer
  Timer? _pollingTimer;
  
  // Data
  List<Map<String, dynamic>> _vehicles = [];
  Map<String, dynamic>? _selectedVehicle;
  Map<String, dynamic> _alerts = {};
  Map<String, dynamic> _stats = {};
  
  // Loading states
  bool _isLoading = true;
  String? _errorMessage;
  
  // User info
  String? _userEmail;
  String? _userDomain;
  
  // Filters
  DateTime _selectedDate = DateTime.now();
  String _statusFilter = 'active'; // active, idle, completed, all
  
  // UI state
  bool _showVehicleList = true;
  bool _showDetailsPanel = false;
  
  // Playback state
  bool _isPlaybackMode = false;
  double _playbackTime = 0.0; // Minutes since midnight
  List<Map<String, dynamic>> _playbackLocations = [];
  
  // Notification badge
  int _alertCount = 0;

  @override
  void initState() {
    super.initState();
    debugPrint('🗺️ ClientBasedAllVehicles: initState');
    _loadUserInfo();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }



Future<void> _callDriver(String phone) async {
  final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
  final number = cleaned.startsWith('+') ? cleaned : '+91$cleaned';
  final uri = Uri.parse('tel:$number');
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnackBar('Could not place call to $number');
    }
  } catch (e) {
    _showSnackBar('Call error: $e');
  }
}
  // ========================================================================
  // USER INFO METHODS
  // ========================================================================

  Future<void> _loadUserInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('user_email');
      
      if (email != null && email.contains('@')) {
        final domain = email.split('@')[1];
        
        setState(() {
          _userEmail = email;
          _userDomain = domain;
        });
        
        debugPrint('👤 User Email: $email');
        debugPrint('🏢 User Domain: $domain');
        
        // Now load vehicles
        _loadLiveVehicles();
        _startPolling();
      } else {
        setState(() {
          _errorMessage = 'Unable to determine user email domain';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading user info: $e');
      setState(() {
        _errorMessage = 'Failed to load user information';
        _isLoading = false;
      });
    }
  }

  // ========================================================================
  // API METHODS
  // ========================================================================

  Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (e) {
      debugPrint('❌ Error getting token: $e');
      return null;
    }
  }

  void _startPolling() {
    // Poll every 10 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && !_isPlaybackMode) {
        _loadLiveVehicles(silent: true);
      }
    });
    debugPrint('✅ Polling started (every 10 seconds)');
  }

  Future<void> _loadLiveVehicles({bool silent = false}) async {
    try {
      if (!silent) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }

      final token = await _getToken();
      if (token == null) {
        throw Exception('No authentication token found');
      }

      if (_userDomain == null) {
        throw Exception('User domain not loaded');
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      
      // NO COMPANY FILTER - Backend will use user's email domain automatically
      final url = '${ApiConfig.baseUrl}/api/client/live-tracking/vehicles'
          '?date=$dateStr'
          '&status=$_statusFilter';

      debugPrint('🔍 Fetching client vehicles: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          final vehiclesData = data['data']['vehicles'] as List<dynamic>? ?? [];
          final alertsData = data['data']['alerts'] as Map<String, dynamic>? ?? {};
          final summaryData = data['data']['summary'] as Map<String, dynamic>? ?? {};

          if (mounted) {
            setState(() {
              _vehicles = vehiclesData.cast<Map<String, dynamic>>();
              _alerts = alertsData;
              _stats = summaryData;
              
              // Calculate alert count
              _alertCount = (alertsData['offline']?.length ?? 0) +
                           (alertsData['routeDeviation']?.length ?? 0) +
                           (alertsData['speeding']?.length ?? 0);
              
              _isLoading = false;
              _errorMessage = null;
            });

            if (!silent) {
              debugPrint('✅ Loaded ${_vehicles.length} vehicle(s) for domain: $_userDomain');
              debugPrint('   Alerts: $_alertCount');
            }
          }

          // Auto-zoom to fit all vehicles on first load
          if (!silent && _vehicles.isNotEmpty) {
            _fitMapToVehicles();
          }
        } else {
          throw Exception(data['message'] ?? 'Failed to load vehicles');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error loading vehicles: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load vehicles: $e';
          _isLoading = false;
        });
      }
    }
  }

Future<void> _shareWhatsAppLiveLocation(Map<String, dynamic> vehicle) async {
  final tripId = vehicle['tripId']?.toString();
  if (tripId == null || tripId.isEmpty) {
    _showSnackBar('Trip ID not found');
    return;
  }

  final liveUrl = '${ApiConfig.baseUrl}/live-track/$tripId';
  final vehicleNumber = vehicle['vehicleNumber']?.toString() ?? 'N/A';
  final driverName = vehicle['driverName']?.toString() ?? 'Driver';
  final customerName = vehicle['currentStop']?['customer']?['name']?.toString() ?? 'Customer';

  final message =
      'Hello $customerName! 👋\n\n'
      'Your trip with vehicle *$vehicleNumber* is now live. 🚗\n'
      'Driver: *$driverName*\n\n'
      '📍 Track your ride in real time:\n'
      '$liveUrl\n\n'
      'Thank you for choosing Abra Fleet!';

  final customerPhone = vehicle['currentStop']?['customer']?['phone']?.toString() ?? '';
  final driverPhone = vehicle['driverPhone']?.toString() ?? '';

  final phone = customerPhone.isNotEmpty ? customerPhone : driverPhone;
  if (phone.isEmpty) {
    _showSnackBar('No phone number available to share location');
    return;
  }
  _openWhatsAppWithMessage(phone, message);
}

Future<void> _openWhatsAppWithMessage(String phone, String message) async {
  final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
  final number = cleaned.startsWith('+') ? cleaned : '+91$cleaned';
  final encoded = Uri.encodeComponent(message);
  final uri = Uri.parse('https://wa.me/$number?text=$encoded');
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showSnackBar('Could not open WhatsApp');
    }
  } catch (e) {
    _showSnackBar('WhatsApp error: $e');
  }
}

void _showSnackBar(String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
  );
}

 Future<void> _loadVehicleDetails(String tripId) async {
  try {
    final token = await _getToken();
    if (token == null) return;

    final url = '${ApiConfig.baseUrl}/api/client/live-tracking/trip/$tripId';

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) {
        setState(() {
          _selectedVehicle = data['data'];
          _showDetailsPanel = true;
        });
        debugPrint('✅ Trip details loaded: ${_selectedVehicle!['vehicleNumber']}');
      }
    }
  } catch (e) {
    debugPrint('❌ Error loading trip details: $e');
  }
}
  Future<void> _loadPlaybackHistory(String vehicleId, String time) async {
    try {
      final token = await _getToken();
      if (token == null) return;

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final url = '${ApiConfig.baseUrl}/api/client/live-tracking/history'
          '?vehicleId=$vehicleId'
          '&date=$dateStr'
          '&time=$time';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          final locations = data['data']['locations'] as List<dynamic>? ?? [];
          
          setState(() {
            _playbackLocations = locations.cast<Map<String, dynamic>>();
          });

          debugPrint('✅ Playback history loaded: ${_playbackLocations.length} points');
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading playback history: $e');
    }
  }

  // ========================================================================
  // MAP METHODS
  // ========================================================================

  void _fitMapToVehicles() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || _vehicles.isEmpty) return;

    final List<LatLng> coordinates = [];
    for (final vehicle in _vehicles) {
      final location = vehicle['currentLocation'];
      if (location != null &&
          location['latitude'] != null &&
          location['longitude'] != null) {
        coordinates.add(LatLng(
          location['latitude'].toDouble(),
          location['longitude'].toDouble(),
        ));
      }
    }

    if (coordinates.isNotEmpty) {
      try {
        final bounds = LatLngBounds.fromPoints(coordinates);
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(50),
          ),
        );
      } catch (e) {
        debugPrint('⚠️ fitCamera skipped: $e');
      }
    }
  });
}

void _centerOnVehicle(Map<String, dynamic> vehicle) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    final location = vehicle['currentLocation'];
    if (location != null &&
        location['latitude'] != null &&
        location['longitude'] != null) {
      try {
        _mapController.move(
          LatLng(
            location['latitude'].toDouble(),
            location['longitude'].toDouble(),
          ),
          15.0,
        );
      } catch (e) {
        debugPrint('⚠️ centerOnVehicle skipped: $e');
      }
    }
  });
}

  // ========================================================================
  // UI BUILD METHODS
  // ========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0D47A1),
      foregroundColor: Colors.white,
      elevation: 2,
      // ============================================================
      // BACK ARROW BUTTON
      // ============================================================
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          Navigator.of(context).pop();
        },
        tooltip: 'Back',
      ),
      // ============================================================
      // END OF BACK ARROW BUTTON
      // ============================================================
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Live Vehicle Tracking'),
          if (_userDomain != null)
            Text(
              '@$_userDomain',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
        ],
      ),
      actions: [
        // Alert badge
        if (_alertCount > 0)
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_active),
                onPressed: _showAlertsDialog,
                tooltip: 'View alerts',
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    '$_alertCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        
        // Refresh button
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _loadLiveVehicles(),
          tooltip: 'Refresh',
        ),
        
        // Filter button
        IconButton(
          icon: const Icon(Icons.filter_list),
          onPressed: _showFiltersDialog,
          tooltip: 'Filters',
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading live vehicles...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadLiveVehicles(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Map
        _buildMap(),
        
        // Vehicle list (left sidebar)
        if (_showVehicleList) _buildVehicleListPanel(),
        
        // Vehicle details panel (right sidebar)
        if (_showDetailsPanel && _selectedVehicle != null)
          _buildDetailsPanel(),
        
        // Stats bar (bottom)
        _buildStatsBar(),
        
        // Toggle buttons
        Positioned(
          top: 16,
          right: 16,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'toggle_list',
                onPressed: () {
                  setState(() {
                    _showVehicleList = !_showVehicleList;
                  });
                },
                backgroundColor: Colors.white,
                child: Icon(
                  _showVehicleList ? Icons.chevron_left : Icons.list,
                  color: const Color(0xFF0D47A1),
                ),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'fit_map',
                onPressed: _fitMapToVehicles,
                backgroundColor: Colors.white,
                child: const Icon(
                  Icons.zoom_out_map,
                  color: Color(0xFF0D47A1),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMap() {
  return FlutterMap(
    mapController: _mapController,
    options: const MapOptions(
      initialCenter: LatLng(12.9716, 77.5946),
      initialZoom: 11.0,
      minZoom: 5.0,
      maxZoom: 18.0,
    ),
    children: [
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.abrafleet.client',
        maxZoom: 19,
      ),
      // ✅ NO PolylineLayer — lines removed
      // ✅ NO stop MarkerLayer — pickup/drop pins removed
      MarkerLayer(
        markers: _buildVehicleMarkers(),
      ),
    ],
  );
}

  List<Polyline> _buildRoutePolylines() {
    final polylines = <Polyline>[];

    for (final vehicle in _vehicles) {
      final locationHistory = vehicle['locationHistory'] as List<dynamic>? ?? [];
      
      if (locationHistory.isEmpty) continue;

      final points = <LatLng>[];
      
      for (final loc in locationHistory) {
        if (loc['latitude'] != null && loc['longitude'] != null) {
          points.add(LatLng(
            loc['latitude'].toDouble(),
            loc['longitude'].toDouble(),
          ));
        }
      }

      if (points.length >= 2) {
        polylines.add(Polyline(
          points: points,
          color: _getStatusColor(vehicle['status']).withOpacity(0.6),
          strokeWidth: 3.0,
        ));
      }
    }

    return polylines;
  }

  List<Marker> _buildStopMarkers() {
    final markers = <Marker>[];

    if (_selectedVehicle != null) {
      final stops = _selectedVehicle!['stops'] as List<dynamic>? ?? [];

      for (final stop in stops) {
        final location = stop['location'];
        final coordinates = location?['coordinates'];

        if (coordinates != null &&
            coordinates['latitude'] != null &&
            coordinates['longitude'] != null) {
          markers.add(Marker(
            point: LatLng(
              coordinates['latitude'].toDouble(),
              coordinates['longitude'].toDouble(),
            ),
            width: 40,
            height: 40,
            child: _buildStopMarkerWidget(stop),
          ));
        }
      }
    }

    return markers;
  }

  Widget _buildStopMarkerWidget(Map<String, dynamic> stop) {
    final type = stop['type']?.toString() ?? '';
    final status = stop['status']?.toString() ?? 'pending';
    
    Color color;
    IconData icon;
    
    if (status == 'completed') {
      color = Colors.green;
      icon = Icons.check_circle;
    } else if (status == 'arrived') {
      color = Colors.orange;
      icon = Icons.location_on;
    } else {
      color = Colors.red;
      icon = type == 'drop' ? Icons.flag : Icons.location_on;
    }

    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }

  List<Marker> _buildVehicleMarkers() {
    final markers = <Marker>[];

    for (final vehicle in _vehicles) {
      final location = vehicle['currentLocation'];
      
      if (location == null ||
          location['latitude'] == null ||
          location['longitude'] == null) {
        continue;
      }

      markers.add(Marker(
        point: LatLng(
          location['latitude'].toDouble(),
          location['longitude'].toDouble(),
        ),
        width: 60,
        height: 60,
        child: GestureDetector(
          // ✅ NEW
onTap: () {
  if (vehicle['tripId'] != null) {
    _loadVehicleDetails(vehicle['tripId']);
  }
  _centerOnVehicle(vehicle);
},
          child: _buildVehicleMarkerWidget(vehicle),
        ),
      ));
    }

    return markers;
  }

  Widget _buildVehicleMarkerWidget(Map<String, dynamic> vehicle) {
    final status = vehicle['status']?.toString() ?? 'assigned';
    final isIdle = vehicle['isIdle'] == true;
    final vehicleNumber = vehicle['vehicleNumber']?.toString() ?? '?';
    final speed = vehicle['currentLocation']?['speed']?.toString() ?? '0';
    
    Color color = _getStatusColor(status);
    if (isIdle) {
      color = Colors.orange;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Vehicle icon
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
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
            size: 24,
          ),
        ),
        
        // Vehicle number label
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 4,
              ),
            ],
          ),
          child: Text(
            vehicleNumber,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleListPanel() {
    return Positioned(
      left: 0,
      top: 0,
      bottom: 60, // Leave space for stats bar
      width: 300,
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D47A1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Vehicles',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_vehicles.length} active',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            
            // Vehicle list
            Expanded(
              child: _vehicles.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.directions_car_outlined,
                              size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No vehicles found'),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _vehicles.length,
                      itemBuilder: (context, index) {
                        final vehicle = _vehicles[index];
                        return _buildVehicleListItem(vehicle);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleListItem(Map<String, dynamic> vehicle) {
    final vehicleNumber = vehicle['vehicleNumber']?.toString() ?? 'Unknown';
    final driverName = vehicle['driverName']?.toString() ?? 'Unknown';
    final status = vehicle['status']?.toString() ?? 'assigned';
    final isIdle = vehicle['isIdle'] == true;
    final progress = vehicle['progress']?.toDouble() ?? 0.0;
    final currentStop = vehicle['currentStop'];
    final speed = vehicle['currentLocation']?['speed']?.toString() ?? '0';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: InkWell(
        // ✅ NEW
onTap: () {
  if (vehicle['tripId'] != null) {
    _loadVehicleDetails(vehicle['tripId']);
  }
  _centerOnVehicle(vehicle);
},
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: isIdle
                          ? Colors.orange
                          : _getStatusColor(status),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      vehicleNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Text(
                    '$speed km/h',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              // Driver name
              Row(
                children: [
                  Icon(Icons.person, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      driverName,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
              
              // Current stop
              if (currentStop != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        currentStop['customer']?['name'] ?? 'Next stop',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              
              // Progress bar
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress / 100,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _getStatusColor(status),
                  ),
                  minHeight: 4,
                ),
              ),
              
              const SizedBox(height: 4),
              
              Text(
                '${progress.toInt()}% complete',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsPanel() {
    final vehicle = _selectedVehicle!;
    final vehicleNumber = vehicle['vehicleNumber']?.toString() ?? 'Unknown';
    final driverName = vehicle['driverName']?.toString() ?? 'Unknown';
    final driverPhone = vehicle['driverPhone']?.toString() ?? '';
    final status = vehicle['status']?.toString() ?? 'assigned';
    final stops = vehicle['stops'] as List<dynamic>? ?? [];
    final currentStopIndex = vehicle['currentStopIndex'] ?? 0;

    return Positioned(
      right: 0,
      top: 0,
      bottom: 60,
      width: 350,
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D47A1),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vehicleNumber,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          driverName,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _showDetailsPanel = false;
                        _selectedVehicle = null;
                        _isPlaybackMode = false;
                      });
                    },
                  ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Driver contact
// Driver contact
if (driverPhone.isNotEmpty) ...[
  ElevatedButton.icon(
    onPressed: () => _callDriver(driverPhone),
    icon: const Icon(Icons.phone, size: 18),
    label: Text(driverPhone),
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.green,
      foregroundColor: Colors.white,
    ),
  ),
  const SizedBox(height: 12),
],
// ✅ Share Live Location button
ElevatedButton.icon(
  onPressed: () => _shareWhatsAppLiveLocation(vehicle),
  icon: const Icon(Icons.share_location, size: 18),
  label: const Text('Share Live Location'),
  style: ElevatedButton.styleFrom(
    backgroundColor: const Color(0xFF25D366),
    foregroundColor: Colors.white,
  ),
),
const SizedBox(height: 16),
                    
                    // Status
                    _buildInfoRow('Status', _getStatusText(status)),
                    const SizedBox(height: 12),
                    
                    // Progress
                    _buildInfoRow(
                      'Progress',
                      'Stop $currentStopIndex of ${stops.length}',
                    ),
                    const SizedBox(height: 16),
                    
                    // Timeline playback
                    if (vehicle['locationHistory'] != null &&
                        (vehicle['locationHistory'] as List).isNotEmpty) ...[
                      const Divider(),
                      const SizedBox(height: 8),
                      
                      Row(
                        children: [
                          const Text(
                            'Timeline Playback',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const Spacer(),
                          Switch(
                            value: _isPlaybackMode,
                            onChanged: (value) {
                              setState(() {
                                _isPlaybackMode = value;
                                if (value) {
                                  _pollingTimer?.cancel();
                                } else {
                                  _startPolling();
                                }
                              });
                            },
                          ),
                        ],
                      ),
                      
                      if (_isPlaybackMode) ...[
                        const SizedBox(height: 16),
                        
                        Row(
                          children: [
                            Text(
                              _formatPlaybackTime(_playbackTime),
                              style: const TextStyle(fontSize: 13),
                            ),
                            const Spacer(),
                            Text(
                              '23:59',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                        
                        Slider(
                          value: _playbackTime,
                          min: 0,
                          max: 1439, // 23:59 in minutes
                          divisions: 1439,
                          onChanged: (value) {
                            setState(() {
                              _playbackTime = value;
                            });
                            
                            // Load history for this time
                            final timeStr = _formatPlaybackTime(value);
                            _loadPlaybackHistory(
                              vehicle['vehicleId'],
                              timeStr,
                            );
                          },
                        ),
                      ],
                      
                      const SizedBox(height: 8),
                      const Divider(),
                    ],
                    
                    // Stops list
                    const SizedBox(height: 16),
                    const Text(
                      'Route Stops',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    ...stops.asMap().entries.map((entry) {
                      final index = entry.key;
                      final stop = entry.value as Map<String, dynamic>;
                      return _buildStopItem(stop, index == currentStopIndex);
                    }).toList(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildStopItem(Map<String, dynamic> stop, bool isCurrent) {
    final type = stop['type']?.toString() ?? '';
    final status = stop['status']?.toString() ?? 'pending';
    final customer = stop['customer'];
    final customerName = customer?['name']?.toString() ?? 'Drop point';
    final address = stop['location']?['address']?.toString() ?? '';
    final estimatedTime = stop['estimatedTime']?.toString() ?? '';

    Color statusColor;
    IconData statusIcon;
    
    if (status == 'completed') {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (status == 'arrived') {
      statusColor = Colors.orange;
      statusIcon = Icons.access_time;
    } else {
      statusColor = Colors.grey;
      statusIcon = Icons.circle_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrent ? Colors.blue.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCurrent ? Colors.blue : Colors.grey.shade300,
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status icon
          Icon(statusIcon, color: statusColor, size: 20),
          const SizedBox(width: 12),
          
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customerName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    address,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                
                if (estimatedTime.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 12, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        estimatedTime,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 60,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _buildStatItem(
              'Total',
              _stats['total']?.toString() ?? '0',
              Colors.blue,
            ),
            _buildStatItem(
              'Active',
              _stats['active']?.toString() ?? '0',
              Colors.green,
            ),
            _buildStatItem(
              'Idle',
              _stats['idle']?.toString() ?? '0',
              Colors.orange,
            ),
            _buildStatItem(
              'Offline',
              _stats['offline']?.toString() ?? '0',
              Colors.red,
            ),
            _buildStatItem(
              'Completed',
              _stats['completed']?.toString() ?? '0',
              Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // DIALOG METHODS
  // ========================================================================

  void _showFiltersDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filters'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date picker
                const Text('Date:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 6)),
                      lastDate: DateTime.now(),
                    );
                    
                    if (date != null) {
                      setDialogState(() {
                        _selectedDate = date;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 18),
                        const SizedBox(width: 8),
                        Text(DateFormat('MMM dd, yyyy').format(_selectedDate)),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Status filter
                const Text('Status:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _statusFilter,
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'idle', child: Text('Idle')),
                    DropdownMenuItem(value: 'completed', child: Text('Completed')),
                    DropdownMenuItem(value: 'all', child: Text('All')),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      _statusFilter = value!;
                    });
                  },
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                // Filters are already set in dialog state
              });
              _loadLiveVehicles();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _showAlertsDialog() {
    final offline = _alerts['offline'] as List<dynamic>? ?? [];
    final routeDeviation = _alerts['routeDeviation'] as List<dynamic>? ?? [];
    final speeding = _alerts['speeding'] as List<dynamic>? ?? [];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Text('Alerts ($_alertCount)'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              if (offline.isNotEmpty) ...[
                const Text(
                  '🚨 Offline Vehicles',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...offline.map((alert) {
                  final alertMap = alert as Map<String, dynamic>;
                  return ListTile(
                    leading: const Icon(Icons.wifi_off, color: Colors.red),
                    title: Text(alertMap['vehicleNumber'] ?? 'Unknown'),
                    subtitle: Text(
                      'Offline for ${alertMap['duration']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    dense: true,
                  );
                }).toList(),
                const Divider(),
              ],
              
              if (routeDeviation.isNotEmpty) ...[
                const Text(
                  '⚠️ Route Deviations',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...routeDeviation.map((alert) {
                  final alertMap = alert as Map<String, dynamic>;
                  return ListTile(
                    leading: const Icon(Icons.route, color: Colors.orange),
                    title: Text(alertMap['vehicleNumber'] ?? 'Unknown'),
                    subtitle: Text(
                      '${alertMap['deviation']} km off route',
                      style: const TextStyle(fontSize: 12),
                    ),
                    dense: true,
                  );
                }).toList(),
                const Divider(),
              ],
              
              if (speeding.isNotEmpty) ...[
                const Text(
                  '⚡ Speeding Vehicles',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...speeding.map((alert) {
                  final alertMap = alert as Map<String, dynamic>;
                  return ListTile(
                    leading: const Icon(Icons.speed, color: Colors.red),
                    title: Text(alertMap['vehicleNumber'] ?? 'Unknown'),
                    subtitle: Text(
                      '${alertMap['speed']} km/h',
                      style: const TextStyle(fontSize: 12),
                    ),
                    dense: true,
                  );
                }).toList(),
              ],
              
              if (_alertCount == 0) ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 48),
                        SizedBox(height: 8),
                        Text('No alerts'),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // UTILITY METHODS
  // ========================================================================

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'started':
      case 'in_progress':
        return Colors.green;
      case 'assigned':
        return Colors.blue;
      case 'completed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'started':
        return 'Started';
      case 'in_progress':
        return 'In Progress';
      case 'assigned':
        return 'Assigned';
      case 'completed':
        return 'Completed';
      default:
        return status;
    }
  }

  String _formatPlaybackTime(double minutes) {
    final hours = (minutes / 60).floor();
    final mins = (minutes % 60).floor();
    return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
  }
}