// lib/features/admin/vehicle_admin_management/trip_operations/trip_operation.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/core/services/vehicle_service.dart';
import 'package:abra_fleet/features/admin/vehicle_admin_management/trip_operations/start_new_trip.dart';
import 'package:abra_fleet/features/admin/admin_live_location_whole_vehicles.dart';
import 'package:abra_fleet/features/admin/widgets/country_state_city_filter.dart';
import 'package:intl/intl.dart';
import 'package:universal_html/html.dart' as html;
import 'package:flutter/foundation.dart' show kIsWeb;

const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kTextPrimaryColor = Color(0xFF212121);
const Color kTextSecondaryColor = Color(0xFF757575);
const Color kSuccessColor = Color(0xFF4CAF50);
const Color kWarningColor = Color(0xFFF57C00);
const Color kErrorColor = Color(0xFFF44336);
const Color kInfoColor = Color(0xFF0288D1);
const Color kWhatsAppColor = Color(0xFF25D366);

class TripOperationScreen extends StatefulWidget {
  final VoidCallback onStartNewTrip;
  const TripOperationScreen({
    Key? key,
    required this.onStartNewTrip,
  }) : super(key: key);

  @override
  State<TripOperationScreen> createState() => _TripOperationScreenState();
}

class _TripOperationScreenState extends State<TripOperationScreen> {
  List<Map<String, dynamic>> _trips = [];
  List<Map<String, dynamic>> _filteredTrips = [];
  bool _isLoading = false;
  String? _errorMessage;

  String _selectedStatus = 'All';
  final List<String> _statusFilters = [
    'All',
    'assigned',
    'accepted',
    'declined',
    'confirmed',
    'started',
    'in_progress',
    'completed',
    'cancelled',
  ];

  DateTime? _fromDate;
  DateTime? _toDate;
  String? _country;
  String? _state;
  String? _city;
  String? _localArea;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final Set<String> _selectedTrips = {};
  bool _selectAll = false;

  Timer? _refreshTimer;
  final ScrollController _scrollController = ScrollController();
  final VehicleService _vehicleService = VehicleService();

  List<Widget> _overlayStack = [];

  @override
  void initState() {
    super.initState();
    _loadTrips();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) _loadTrips();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================================================
  // OVERLAY MANAGEMENT
  // ============================================================================
  void _pushOverlay(Widget overlay) {
    setState(() {
      _overlayStack.add(overlay);
    });
  }

  void _popOverlay() {
    if (_overlayStack.isNotEmpty) {
      setState(() {
        _overlayStack.removeLast();
      });
    }
  }

  void _clearAllOverlays() {
    setState(() {
      _overlayStack.clear();
    });
  }

  void _showStartNewTripOverlay() {
    _pushOverlay(
      Material(
        color: Colors.black54,
        child: Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.95,
            height: MediaQuery.of(context).size.height * 0.90,
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 12.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
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
                      IconButton(
                        onPressed: _popOverlay,
                        icon: const Icon(Icons.arrow_back, color: Colors.black),
                        tooltip: 'Back',
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.add_road, color: kPrimaryColor, size: 24),
                      const SizedBox(width: 8),
                      const Text(
                        'Start New Trip',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _clearAllOverlays,
                        child: const Text(
                          'Close',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    child: StartNewTripPage(
                      onBack: () {
                        _popOverlay();
                        _loadTrips();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // LOAD TRIPS
  // ============================================================================
  Future<void> _loadTrips() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      if (token == null || token.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Not authenticated';
            _isLoading = false;
          });
        }
        return;
      }

      String queryParams = 'limit=100';
      if (_selectedStatus != 'All') {
        queryParams += '&status=$_selectedStatus';
      }

      final response = await http.get(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/trips/start-trip-list?$queryParams'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        setState(() {
          _trips = List<Map<String, dynamic>>.from(data['data'] ?? []);
          _applyFilters();
          _isLoading = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Failed to load trips: ${response.statusCode}';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading trips: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  // ============================================================================
  // FILTERS
  // ============================================================================
  void _applyFilters() {
    List<Map<String, dynamic>> filtered = _trips;

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((trip) {
        final searchLower = _searchQuery.toLowerCase();
        return (trip['tripNumber']
                    ?.toString()
                    .toLowerCase()
                    .contains(searchLower) ??
                false) ||
            (trip['customerName']
                    ?.toString()
                    .toLowerCase()
                    .contains(searchLower) ??
                false) ||
            (trip['driverName']
                    ?.toString()
                    .toLowerCase()
                    .contains(searchLower) ??
                false) ||
            (trip['vehicleNumber']
                    ?.toString()
                    .toLowerCase()
                    .contains(searchLower) ??
                false);
      }).toList();
    }

    if (_country != null) {
      filtered = filtered
          .where((trip) => trip['country']?.toString() == _country)
          .toList();
    }

    if (_state != null) {
      filtered = filtered
          .where((trip) => trip['state']?.toString() == _state)
          .toList();
    }

    if (_city != null) {
      filtered = filtered
          .where((trip) => trip['city']?.toString() == _city)
          .toList();
    }

    if (_fromDate != null || _toDate != null) {
      filtered = filtered.where((trip) {
        final tripDate =
            DateTime.tryParse(trip['scheduledPickupTime']?.toString() ?? '');
        if (tripDate == null) return false;
        if (_fromDate != null && tripDate.isBefore(_fromDate!)) return false;
        if (_toDate != null &&
            tripDate.isAfter(_toDate!.add(const Duration(days: 1)))) {
          return false;
        }
        return true;
      }).toList();
    }

    setState(() {
      _filteredTrips = filtered;
    });
  }

  void _handleFilterChanged(Map<String, dynamic> filters) {
    setState(() {
      _fromDate = filters['fromDate'];
      _toDate = filters['toDate'];
      _country = filters['country'];
      _state = filters['state'];
      _city = filters['city'];
      _localArea = filters['localArea'];
      _applyFilters();
    });
  }

  // ============================================================================
  // EXPORT TO EXCEL
  // ============================================================================
  Future<void> _exportToExcel() async {
    try {
      if (_filteredTrips.isEmpty) {
        _showErrorSnackbar('No trips to export');
        return;
      }

      _showSuccessSnackbar('Preparing Excel export...');

      List<List<dynamic>> csvData = [
        [
          'Trip #',
          'Status',
          'Customer Name',
          'Customer Phone',
          'Customer Email',
          'Driver Name',
          'Driver Phone',
          'Vehicle',
          'Distance (km)',
          'Pickup Time',
          'Estimated Duration (min)',
          'Pickup Location',
          'Drop Location',
          'Created At',
        ],
      ];

      for (var trip in _filteredTrips) {
        csvData.add([
          trip['tripNumber'] ?? 'N/A',
          trip['status'] ?? 'N/A',
          trip['customerName'] ?? trip['customer']?['name'] ?? 'N/A',
          trip['customerPhone'] ?? trip['customer']?['phone'] ?? 'N/A',
          trip['customerEmail'] ?? trip['customer']?['email'] ?? 'N/A',
          trip['driverName'] ?? 'N/A',
          trip['driverPhone'] ?? 'N/A',
          trip['vehicleNumber'] ?? 'N/A',
          trip['distance']?.toStringAsFixed(1) ?? '0.0',
          _formatDateTime(trip['scheduledPickupTime']),
          trip['estimatedDuration']?.toString() ?? 'N/A',
          trip['pickupLocation']?['address'] ?? 'N/A',
          trip['dropLocation']?['address'] ?? 'N/A',
          _formatDateTime(trip['createdAt']),
        ]);
      }

      String csv = csvData.map((row) => row.join(',')).join('\n');

      if (kIsWeb) {
        final bytes = utf8.encode(csv);
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download',
              'trips_export_${DateTime.now().millisecondsSinceEpoch}.csv')
          ..click();
        html.Url.revokeObjectUrl(url);
      }

      _showSuccessSnackbar(
          '✅ Excel file downloaded with ${_filteredTrips.length} trips!');
    } catch (e) {
      _showErrorSnackbar('Failed to export: $e');
    }
  }

  // ============================================================================
  // CONFIRM ACCEPTED TRIP
  // ============================================================================
  Future<void> _confirmAcceptedTrip(Map<String, dynamic> trip) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: kSuccessColor),
            SizedBox(width: 12),
            Text('Confirm Trip'),
          ],
        ),
        content: Text(
          'Confirm trip ${trip['tripNumber']}?\n\n'
          'This will notify the customer that their trip is confirmed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kSuccessColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Trip'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        _showErrorSnackbar('Not authenticated');
        return;
      }

      final tripId = _extractTripId(trip);
      if (tripId == null) {
        _showErrorSnackbar('Trip ID not found');
        return;
      }

      setState(() => _isLoading = true);

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/trips/$tripId/confirm-accepted'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        _showSuccessSnackbar('✅ Trip confirmed! Customer notified.');
        _loadTrips();
      } else {
        final data = json.decode(response.body);
        _showErrorSnackbar(data['message'] ?? 'Failed to confirm trip');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Error confirming trip: $e');
    }
  }

  // ============================================================================
  // ASSIGN / REASSIGN VEHICLE
  // ============================================================================
  Future<void> _showAssignVehicleDialog(Map<String, dynamic> trip) async {
  final tripId = _extractTripId(trip);
  if (tripId == null) {
    _showErrorSnackbar('Trip ID not found');
    return;
  }

  final tripContext = TripAssignmentContext(
    tripId: tripId,
    tripNumber: trip['tripNumber']?.toString() ?? 'N/A',
    customerName: trip['customerName'] ??
        trip['customer']?['name'] ??
        'Customer',
    customerPhone: trip['customerPhone'] ??
        trip['customer']?['phone'] ??
        '',
    pickupAddress: trip['pickupLocation']?['address'] ?? 'N/A',
    dropAddress: trip['dropLocation']?['address'] ?? 'N/A',
    scheduledPickupTime: _formatDateTime(trip['scheduledPickupTime']),
    isReassign: trip['status']?.toString().toLowerCase() == 'declined',
  );

  final assigned = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => AdminLiveLocationWholeVehicles(
        tripAssignmentContext: tripContext,
      ),
    ),
  );

  if (assigned == true && mounted) {
    _loadTrips();
  }
}

  Future<List<Map<String, dynamic>>> _loadVehiclesViaService() async {
    try {
      final response = await _vehicleService.getVehicles(limit: 100);
      if (response['success'] == true) {
        final List<dynamic> vehiclesData = response['data'] ?? [];
        return vehiclesData
            .where((vehicle) {
              final status =
                  (vehicle['status'] ?? 'active').toString().toUpperCase();
              final hasDriver = _hasAssignedDriver(vehicle);
              return status == 'ACTIVE' && hasDriver;
            })
            .map<Map<String, dynamic>>((vehicle) {
              String mongoId = '';
              if (vehicle['_id'] != null) {
                if (vehicle['_id'] is Map) {
                  mongoId = vehicle['_id']['\$oid'] ?? '';
                } else {
                  mongoId = vehicle['_id'].toString();
                }
              }

              final assignedDriver = vehicle['assignedDriver'];
              String driverName = 'No Driver';
              String driverPhone = '';
              if (assignedDriver != null) {
                if (assignedDriver is Map) {
                  driverName = assignedDriver['name'] ?? 'Unknown Driver';
                  driverPhone = assignedDriver['phone'] ?? '';
                } else if (assignedDriver is String) {
                  driverName = assignedDriver;
                }
              }

              return {
                '_id': mongoId,
                'registrationNumber': vehicle['registrationNumber'] ?? '',
                'make': vehicle['make'] ?? '',
                'model': vehicle['model'] ?? '',
                'type': (vehicle['type'] ?? '').toString().toUpperCase(),
                'status': vehicle['status'] ?? 'active',
                'assignedDriver': {
                  'name': driverName,
                  'phone': driverPhone,
                },
              };
            })
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error loading vehicles via service: $e');
      return [];
    }
  }

  bool _hasAssignedDriver(Map<String, dynamic> vehicle) {
    final assignedDriver = vehicle['assignedDriver'];
    if (assignedDriver == null) return false;
    if (assignedDriver is Map) {
      return assignedDriver.isNotEmpty &&
          (assignedDriver['name'] != null ||
              assignedDriver['driverId'] != null);
    } else if (assignedDriver is String) {
      return assignedDriver.isNotEmpty;
    }
    return false;
  }

  Widget _buildVehicleSelectionDialog(
      Map<String, dynamic> trip, List<Map<String, dynamic>> vehicles) {
    final searchController = TextEditingController();
    final status = trip['status']?.toString().toLowerCase() ?? '';
    final isReassign = status == 'declined';

    return StatefulBuilder(
      builder: (context, setDialogState) {
        var filteredVehicles = vehicles.where((v) {
          if (searchController.text.isEmpty) return true;
          final search = searchController.text.toLowerCase();
          return (v['registrationNumber']
                      ?.toString()
                      .toLowerCase()
                      .contains(search) ??
                  false) ||
              (v['model']?.toString().toLowerCase().contains(search) ??
                  false) ||
              (v['make']?.toString().toLowerCase().contains(search) ?? false);
        }).toList();

        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            width: 600,
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isReassign
                          ? [const Color(0xFFE67E22), const Color(0xFFF39C12)]
                          : [kPrimaryColor, const Color(0xFF1976D2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_car, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isReassign
                                  ? 'Reassign Vehicle — Trip ${trip['tripNumber']}'
                                  : 'Assign Vehicle — Trip ${trip['tripNumber']}',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                            if (trip['customerName'] != null)
                              Text(
                                'Customer: ${trip['customerName']}',
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.white70),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search vehicles, drivers...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (value) => setDialogState(() {}),
                  ),
                ),
                Expanded(
                  child: filteredVehicles.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off,
                                  size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text('No vehicles found',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600])),
                            ],
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: filteredVehicles.length,
                          separatorBuilder: (context, index) =>
                              Divider(height: 1, color: Colors.grey[300]),
                          itemBuilder: (context, index) {
                            final vehicle = filteredVehicles[index];
                            final driver = vehicle['assignedDriver'];
                            String driverName = 'Unknown Driver';
                            String driverPhone = '';
                            if (driver is Map) {
                              driverName =
                                  driver['name']?.toString() ?? 'Unknown Driver';
                              driverPhone = driver['phone']?.toString() ?? '';
                            } else if (driver is String) {
                              driverName = driver;
                            }

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isReassign
                                    ? const Color(0xFFE67E22)
                                    : kPrimaryColor,
                                child: const Icon(Icons.directions_car,
                                    color: Colors.white, size: 24),
                              ),
                              title: Text(
                                vehicle['registrationNumber'] ?? 'N/A',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''}'
                                        .trim(),
                                    style: TextStyle(
                                        fontSize: 13, color: Colors.grey[700]),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(Icons.person,
                                          size: 14, color: kPrimaryColor),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          driverName,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: kPrimaryColor,
                                              fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (driverPhone.isNotEmpty)
                                    Text(driverPhone,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600])),
                                ],
                              ),
                              trailing: ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _assignVehicleToTrip(trip, vehicle);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isReassign
                                      ? const Color(0xFFE67E22)
                                      : kPrimaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                ),
                                child:
                                    Text(isReassign ? 'Reassign' : 'Assign'),
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Text(
                    '${filteredVehicles.length} vehicle(s) available',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _assignVehicleToTrip(
      Map<String, dynamic> trip, Map<String, dynamic> vehicle) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        _showErrorSnackbar('Not authenticated');
        return;
      }

      final tripId = _extractTripId(trip);
      if (tripId == null) {
        _showErrorSnackbar('Trip ID not found');
        return;
      }

      final vehicleId = _extractVehicleId(vehicle);
      if (vehicleId == null) {
        _showErrorSnackbar('Vehicle ID not found');
        return;
      }

      final status = trip['status']?.toString().toLowerCase() ?? '';
      final isReassign = status == 'declined';

      setState(() => _isLoading = true);
      _showSuccessSnackbar(
          isReassign ? 'Reassigning vehicle...' : 'Assigning vehicle...');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/client-trips/$tripId/reassign-vehicle'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'vehicleId': vehicleId}),
      );

      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _showSuccessSnackbar(isReassign
              ? '✅ Vehicle reassigned! New driver notified.'
              : '✅ Vehicle assigned! Driver notified to Accept/Decline.');
          _loadTrips();
        } else {
          _showErrorSnackbar(data['message'] ?? 'Failed to assign vehicle');
        }
      } else {
        final data = json.decode(response.body);
        _showErrorSnackbar(
            data['message'] ?? 'Failed to assign: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Error assigning vehicle: $e');
    }
  }

  // ============================================================================
  // DELETE TRIP
  // ============================================================================
  Future<void> _deleteTrip(Map<String, dynamic> trip) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: kErrorColor),
            SizedBox(width: 12),
            Text('Delete Trip'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete trip ${trip['tripNumber']}?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kErrorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        _showErrorSnackbar('Not authenticated');
        return;
      }

      final tripId = _extractTripId(trip);
      if (tripId == null) {
        _showErrorSnackbar('Trip ID not found');
        return;
      }

      setState(() => _isLoading = true);

      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/trips/$tripId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        _showSuccessSnackbar('✅ Trip deleted successfully');
        _loadTrips();
      } else {
        final data = json.decode(response.body);
        _showErrorSnackbar(data['message'] ?? 'Failed to delete trip');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Error deleting trip: $e');
    }
  }

  // ============================================================================
  // WHATSAPP CONTACT DIALOG (existing — for general contact)
  // ============================================================================
  void _showWhatsAppDialog(Map<String, dynamic> trip) {
    final customerName =
        trip['customerName'] ?? trip['customer']?['name'] ?? 'Customer';
    final customerPhone =
        trip['customerPhone'] ?? trip['customer']?['phone'] ?? '';
    final driverName = trip['driverName']?.toString();
    final driverPhone = trip['driverPhone']?.toString() ?? '';
    final hasDriver =
        driverName != null && driverName.isNotEmpty && driverPhone.isNotEmpty;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kWhatsAppColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.chat, color: kWhatsAppColor, size: 22),
          ),
          const SizedBox(width: 10),
          const Text('Open WhatsApp',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Trip: ${trip['tripNumber'] ?? ''}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          const Text('Who would you like to message?',
              style: TextStyle(fontSize: 14)),
          const SizedBox(height: 14),
          if (customerPhone.isNotEmpty)
            _waOption(
              icon: Icons.person,
              color: Colors.blue,
              label: 'Message Customer',
              name: customerName,
              phone: customerPhone,
              onTap: () {
                Navigator.pop(context);
                _openWhatsApp(customerPhone, customerName);
              },
            ),
          if (hasDriver) ...[
            const SizedBox(height: 10),
            _waOption(
              icon: Icons.drive_eta,
              color: Colors.green,
              label: 'Message Driver',
              name: driverName!,
              phone: driverPhone,
              onTap: () {
                Navigator.pop(context);
                _openWhatsApp(driverPhone, driverName);
              },
            ),
          ],
          if (customerPhone.isEmpty && !hasDriver)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('No phone numbers available',
                  style: TextStyle(color: Colors.grey.shade500)),
            ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // FIX 2 — WHATSAPP LIVE LOCATION SHARE
  // ============================================================================
  Future<void> _shareWhatsAppLiveLocation(Map<String, dynamic> trip) async {
    final tripId = _extractTripId(trip);
    if (tripId == null) {
      _showErrorSnackbar('Trip ID not found');
      return;
    }

    // The tracking URL — uses ApiConfig.baseUrl so it works both locally and in production
    final liveUrl = '${ApiConfig.baseUrl}/live-track/$tripId';

    final tripNumber = trip['tripNumber'] ?? 'N/A';
    final customerName =
        trip['customerName'] ?? trip['customer']?['name'] ?? 'Customer';
    final driverName = trip['driverName'] ?? 'Driver';
    final vehicleNum = trip['vehicleNumber'] ?? 'N/A';

    final message =
        'Hello $customerName! 👋\n\n'
        'Your trip *$tripNumber* is now live. 🚗\n'
        'Driver: *$driverName*\n'
        'Vehicle: *$vehicleNum*\n\n'
        '📍 Track your ride in real time:\n'
        '$liveUrl\n\n'
        'Thank you for choosing Abra Fleet!';

    final customerPhone =
        trip['customerPhone'] ?? trip['customer']?['phone'] ?? '';
    final driverPhone = trip['driverPhone']?.toString() ?? '';

    if (customerPhone.isNotEmpty && driverPhone.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kWhatsAppColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.share_location,
                  color: kWhatsAppColor, size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Share Live Location',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Trip: $tripNumber',
                style:
                    TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            const Text('Send live tracking link to:',
                style: TextStyle(fontSize: 14)),
            const SizedBox(height: 14),
            _waOption(
              icon: Icons.person,
              color: Colors.blue,
              label: 'Send to Customer',
              name: customerName,
              phone: customerPhone,
              onTap: () {
                Navigator.pop(context);
                _openWhatsAppWithMessage(customerPhone, message);
              },
            ),
            const SizedBox(height: 10),
            _waOption(
              icon: Icons.drive_eta,
              color: Colors.green,
              label: 'Send to Driver',
              name: driverName,
              phone: driverPhone,
              onTap: () {
                Navigator.pop(context);
                _openWhatsAppWithMessage(driverPhone, message);
              },
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      return;
    }

    final phone =
        customerPhone.isNotEmpty ? customerPhone : driverPhone;
    if (phone.isEmpty) {
      _showErrorSnackbar('No phone number available to share location');
      return;
    }
    _openWhatsAppWithMessage(phone, message);
  }

  // Opens WhatsApp with a pre-filled message
  Future<void> _openWhatsAppWithMessage(
      String phone, String message) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final number = cleaned.startsWith('+') ? cleaned : '+91$cleaned';
    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse('https://wa.me/$number?text=$encoded');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showErrorSnackbar('Could not open WhatsApp');
      }
    } catch (e) {
      _showErrorSnackbar('WhatsApp error: $e');
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color)),
                  Text(name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(phone,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600)),
                ]),
          ),
          Icon(Icons.arrow_forward_ios,
              size: 13, color: color.withOpacity(0.6)),
        ]),
      ),
    );
  }

  Future<void> _openWhatsApp(String phone, String name) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final number = cleaned.startsWith('+') ? cleaned : '+91$cleaned';
    final uri = Uri.parse('https://wa.me/$number');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showErrorSnackbar('Could not open WhatsApp for $name');
      }
    } catch (e) {
      _showErrorSnackbar('WhatsApp error: $e');
    }
  }

  // ============================================================================
  // TRIP HISTORY DIALOG
  // ============================================================================
  void _showTripHistory(Map<String, dynamic> trip) {
    final status = trip['status']?.toString().toLowerCase() ?? '';
    final adminConfirmed = trip['adminConfirmed'] == true;
    final statusHistory =
        trip['statusHistory'] as Map<String, dynamic>? ?? {};
    final driverResponse = trip['driverResponse']?.toString();
    final driverResponseNotes =
        trip['driverResponseNotes']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
            maxWidth: 640,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: kPrimaryColor,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(children: [
                  const Icon(Icons.history, color: Colors.white, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Trip History',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          Text(trip['tripNumber'] ?? 'N/A',
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.white70)),
                        ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                        _getStatusLabel(status,
                            adminConfirmed: adminConfirmed),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _historySection('👤 Customer Information', [
                        _historyRow('Name',
                            trip['customerName'] ?? trip['customer']?['name'] ?? 'N/A'),
                        _historyRow('Phone',
                            trip['customerPhone'] ?? trip['customer']?['phone'] ?? 'N/A'),
                        _historyRow('Email',
                            trip['customerEmail'] ?? trip['customer']?['email'] ?? 'N/A'),
                      ]),
                      const SizedBox(height: 16),
                      _historySection('🚗 Trip Information', [
                        _historyRow(
                            'Distance',
                            trip['distance'] != null
                                ? '${(trip['distance'] as num).toStringAsFixed(1)} km'
                                : 'N/A'),
                        _historyRow(
                            'Duration',
                            trip['estimatedDuration'] != null
                                ? '${trip['estimatedDuration']} minutes'
                                : 'N/A'),
                        _historyRow('Pickup Time',
                            _formatDateTime(trip['scheduledPickupTime'])),
                        _historyRow('Pickup Location',
                            trip['pickupLocation']?['address'] ?? 'N/A'),
                        _historyRow('Drop Location',
                            trip['dropLocation']?['address'] ?? 'N/A'),
                      ]),
                      const SizedBox(height: 16),
                      if (trip['driverName'] != null ||
                          trip['vehicleNumber'] != null) ...[
                        _historySection('👨‍✈️ Assignment', [
                          if (trip['driverName'] != null)
                            _historyRow('Driver', trip['driverName']),
                          if (trip['driverPhone'] != null)
                            _historyRow('Driver Phone', trip['driverPhone']),
                          if (trip['vehicleNumber'] != null)
                            _historyRow('Vehicle', trip['vehicleNumber']),
                          _historyRow('Assigned At',
                              _formatDateTime(trip['assignedAt'])),
                        ]),
                        const SizedBox(height: 16),
                      ],
                      _historySection('📋 Status Timeline', [
                        _timelineItem(
                          icon: Icons.add_circle,
                          color: Colors.blue,
                          title: 'Trip Created',
                          subtitle: 'Status → Pending Assignment',
                          time: _formatDateTime(
                              statusHistory['pending_assignment'] ??
                                  trip['createdAt']),
                          isFirst: true,
                        ),
                        if (statusHistory['assigned'] != null)
                          _timelineItem(
                            icon: Icons.assignment_ind,
                            color: Colors.blue,
                            title: 'Vehicle & Driver Assigned by Admin',
                            subtitle:
                                'Driver: ${trip['driverName'] ?? 'N/A'} • Vehicle: ${trip['vehicleNumber'] ?? 'N/A'}',
                            time: _formatDateTime(statusHistory['assigned']),
                          ),
                        if (driverResponse != null)
                          _timelineItem(
                            icon: driverResponse == 'accept'
                                ? Icons.check_circle
                                : Icons.cancel,
                            color: driverResponse == 'accept'
                                ? Colors.green
                                : Colors.red,
                            title: driverResponse == 'accept'
                                ? '✅ Driver Accepted Trip'
                                : '❌ Driver Declined Trip',
                            subtitle: driverResponseNotes.isNotEmpty
                                ? 'Note: $driverResponseNotes'
                                : (driverResponse == 'accept'
                                    ? 'Waiting for Admin Confirmation'
                                    : 'Admin needs to reassign'),
                            time: _formatDateTime(trip['driverResponseTime']),
                            highlight: true,
                          ),
                        if (statusHistory['declined'] != null &&
                            driverResponse != 'accept')
                          _timelineItem(
                            icon: Icons.assignment_return,
                            color: Colors.orange,
                            title: 'Admin Reassigning Driver',
                            subtitle: 'Waiting for new assignment',
                            time: _formatDateTime(statusHistory['declined']),
                          ),
                        if (adminConfirmed)
                          _timelineItem(
                            icon: Icons.verified,
                            color: Colors.green,
                            title: '✅ Admin Confirmed Trip',
                            subtitle: 'Customer has been notified!',
                            time: _formatDateTime(trip['adminConfirmedAt']),
                            highlight: true,
                          ),
                        if (statusHistory['started'] != null)
                          _timelineItem(
                            icon: Icons.directions_car,
                            color: Colors.indigo,
                            title: 'Trip Started by Driver',
                            subtitle: 'Live tracking active',
                            time: _formatDateTime(statusHistory['started']),
                          ),
                        if (statusHistory['completed'] != null)
                          _timelineItem(
                            icon: Icons.flag,
                            color: Colors.green,
                            title: 'Trip Completed',
                            subtitle: 'Successfully delivered',
                            time: _formatDateTime(statusHistory['completed']),
                            isLast: true,
                          ),
                      ]),
                      if (trip['notes'] != null &&
                          trip['notes'].toString().isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _historySection('📝 Notes', [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: Colors.grey.shade200),
                            ),
                            child: Text(trip['notes'],
                                style: const TextStyle(
                                    fontSize: 13, height: 1.5)),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20)),
                  border:
                      Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Created: ${_formatDateTime(trip['createdAt'])}',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600),
                    ),
                    Row(children: [
                      if (status == 'pending_assignment' ||
                          status == 'pending' ||
                          status == 'assigned' ||
                          status == 'declined')
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _showAssignVehicleDialog(trip);
                          },
                          icon: const Icon(Icons.assignment, size: 16),
                          label: Text(
                              status == 'declined' ? 'Reassign' : 'Assign'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: status == 'declined'
                                ? Colors.orange.shade700
                                : kPrimaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      if (status == 'accepted' && !adminConfirmed)
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _confirmAcceptedTrip(trip);
                          },
                          icon: const Icon(Icons.check_circle, size: 16),
                          label: const Text('Confirm Trip'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kSuccessColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historySection(String title, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: kPrimaryColor)),
      const SizedBox(height: 10),
      ...children,
    ]);
  }

  Widget _historyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600))),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500))),
      ]),
    );
  }

  Widget _timelineItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String time,
    bool isFirst = false,
    bool isLast = false,
    bool highlight = false,
  }) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        if (!isFirst)
          Container(width: 2, height: 12, color: Colors.grey.shade300),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        if (!isLast)
          Container(width: 2, height: 30, color: Colors.grey.shade300),
      ]),
      const SizedBox(width: 12),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: highlight
                  ? color.withOpacity(0.06)
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: highlight
                      ? color.withOpacity(0.3)
                      : Colors.grey.shade200),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: highlight
                              ? Color.lerp(color, Colors.black, 0.3)!
                              : Colors.black87)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600)),
                  ],
                  const SizedBox(height: 4),
                  Text(time,
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontStyle: FontStyle.italic)),
                ]),
          ),
        ),
      ),
    ]);
  }

  // ============================================================================
  // HELPERS
  // ============================================================================
  String? _extractTripId(Map<String, dynamic> trip) {
    if (trip['_id'] != null) {
      if (trip['_id'] is Map && trip['_id']['\$oid'] != null) {
        return trip['_id']['\$oid'].toString();
      } else {
        return trip['_id'].toString();
      }
    }
    return null;
  }

  String? _extractVehicleId(Map<String, dynamic> vehicle) {
    if (vehicle['_id'] != null) {
      if (vehicle['_id'] is Map && vehicle['_id']['\$oid'] != null) {
        return vehicle['_id']['\$oid'].toString();
      } else {
        return vehicle['_id'].toString();
      }
    }
    return null;
  }

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'N/A';
    try {
      DateTime dt;
      if (dateTime is String) {
        dt = DateTime.parse(dateTime);
      } else if (dateTime is DateTime) {
        dt = dateTime;
      } else {
        return 'N/A';
      }
      return DateFormat('dd/MM/yyyy HH:mm').format(dt.toLocal());
    } catch (e) {
      return dateTime.toString();
    }
  }

  String _getStatusLabel(String? status, {bool adminConfirmed = false}) {
    if (status?.toLowerCase() == 'accepted' && adminConfirmed) {
      return 'Confirmed';
    }
    switch (status?.toLowerCase()) {
      case 'pending_assignment':
      case 'pending':
        return 'Pending';
      case 'assigned':
        return 'Assigned';
      case 'accepted':
        return 'Accepted';
      case 'declined':
        return 'Declined';
      case 'confirmed':
        return 'Confirmed';
      case 'started':
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status?.toUpperCase() ?? 'Unknown';
    }
  }

  void _toggleSelection(String tripId) {
    setState(() {
      if (_selectedTrips.contains(tripId)) {
        _selectedTrips.remove(tripId);
      } else {
        _selectedTrips.add(tripId);
      }
      _selectAll = _selectedTrips.length == _trips.length;
    });
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        _selectedTrips.clear();
        for (var trip in _trips) {
          final tripId = _extractTripId(trip);
          if (tripId != null) _selectedTrips.add(tripId);
        }
      } else {
        _selectedTrips.clear();
      }
    });
  }

  void _showSuccessSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ]),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showErrorSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ]),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // ============================================================================
  // FIX 1 — TRACK TRIP: navigates to AdminLiveLocationWholeVehicles
  // ============================================================================
  void _trackTrip(Map<String, dynamic> trip) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AdminLiveLocationWholeVehicles(),
      ),
    );
  }

  // ============================================================================
  // BUILD
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.grey[50],
          body: _isLoading && _trips.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    children: [
                      _buildTopBar(),
                      _buildFiltersSection(),
                      if (_errorMessage != null && _trips.isEmpty)
                        _buildErrorState()
                      else if (_trips.isEmpty)
                        _buildEmptyState()
                      else
                        _buildTripsTable(),
                    ],
                  ),
                ),
        ),
        ..._overlayStack,
      ],
    );
  }

  // ============================================================================
  // TOP BAR
  // ============================================================================
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back,
                    color: kPrimaryColor, size: 28),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Back',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.local_shipping, color: kPrimaryColor, size: 32),
              const SizedBox(width: 12),
              const Text(
                'Trip Operations',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: kPrimaryColor,
                ),
              ),
              const SizedBox(width: 40),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: _selectedStatus,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.arrow_drop_down),
                  items: _statusFilters.map((status) {
                    return DropdownMenuItem(
                      value: status,
                      child: Text(
                        status == 'All' ? 'All Trips' : status.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedStatus = value;
                      });
                      _loadTrips();
                    }
                  },
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 250,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search trips...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                                _searchQuery = '';
                                _applyFilters();
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 12),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                      _applyFilters();
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: _isLoading && _trips.isNotEmpty
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 22),
                onPressed: _isLoading ? null : _loadTrips,
                tooltip: 'Refresh',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey[200],
                  padding: const EdgeInsets.all(10),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _showStartNewTripOverlay,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Start New Trip',
                    style: TextStyle(fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 2,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _exportToExcel,
                icon: const Icon(Icons.file_download, size: 18),
                label: const Text('Export Excel',
                    style: TextStyle(fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF27AE60),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // FILTERS SECTION
  // ============================================================================
  Widget _buildFiltersSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: CountryStateCityFilter(
        onFilterApplied: _handleFilterChanged,
        initialFromDate: _fromDate,
        initialToDate: _toDate,
        initialCountry: _country,
        initialState: _state,
        initialCity: _city,
        initialLocalArea: _localArea,
      ),
    );
  }

  // ============================================================================
  // TRIPS TABLE
  // ============================================================================
  Widget _buildTripsTable() {
    if (_filteredTrips.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No trips match your search',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try adjusting your filters',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    const double colCheck = 50.0;
    const double colTrip = 160.0;
    const double colStatus = 130.0;
    const double colCustomer = 180.0;
    const double colDriver = 180.0;
    const double colVehicle = 130.0;
    const double colDist = 100.0;
    const double colTime = 150.0;
    const double colActions = 320.0;

    const double totalWidth = colCheck +
        colTrip +
        colStatus +
        colCustomer +
        colDriver +
        colVehicle +
        colDist +
        colTime +
        colActions;

    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'Trip List',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: kPrimaryColor,
                  ),
                ),
                const Spacer(),
                Text(
                  'Showing ${_filteredTrips.length} of ${_trips.length} trips',
                  style: const TextStyle(
                    fontSize: 13,
                    color: kTextSecondaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalWidth,
              child: Column(
                children: [
                  Container(
                    color: kPrimaryColor,
                    child: Row(children: [
                      _hdr('', colCheck),
                      _hdr('TRIP #', colTrip),
                      _hdr('STATUS', colStatus),
                      _hdr('CUSTOMER', colCustomer),
                      _hdr('DRIVER', colDriver),
                      _hdr('VEHICLE', colVehicle),
                      _hdr('DISTANCE', colDist),
                      _hdr('PICKUP TIME', colTime),
                      _hdr('ACTIONS', colActions),
                    ]),
                  ),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _filteredTrips.length,
                    itemBuilder: (context, index) {
                      final trip = _filteredTrips[index];
                      final tripId = _extractTripId(trip);
                      final isSelected =
                          tripId != null && _selectedTrips.contains(tripId);
                      final isEven = index % 2 == 0;
                      final status =
                          trip['status']?.toString() ?? 'unknown';
                      final adminConfirmed = trip['adminConfirmed'] == true;

                      return InkWell(
                        onTap: () => _showTripHistory(trip),
                        hoverColor: kPrimaryColor.withOpacity(0.04),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isEven
                                ? Colors.grey.shade50
                                : Colors.white,
                            border: Border(
                                bottom: BorderSide(
                                    color: Colors.grey.shade200, width: 1)),
                          ),
                          child: Row(children: [
                            SizedBox(
                              width: colCheck,
                              child: Checkbox(
                                value: isSelected,
                                onChanged: (v) => tripId != null
                                    ? _toggleSelection(tripId)
                                    : null,
                              ),
                            ),
                            _tblCell(
                              trip['tripNumber'] ?? 'N/A',
                              colTrip,
                              fontWeight: FontWeight.bold,
                              color: kPrimaryColor,
                              fontSize: 13,
                            ),
                            SizedBox(
                              width: colStatus,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                child: _buildStatusBadge(status,
                                    adminConfirmed: adminConfirmed),
                              ),
                            ),
                            SizedBox(
                              width: colCustomer,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      trip['customerName'] ??
                                          trip['customer']?['name'] ??
                                          'N/A',
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      trip['customerPhone'] ??
                                          trip['customer']?['phone'] ??
                                          '',
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(
                              width: colDriver,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      trip['driverName'] ?? '—',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: trip['driverName'] != null
                                            ? kTextPrimaryColor
                                            : Colors.grey.shade400,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      trip['driverPhone'] ?? '',
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            _tblCell(
                              trip['vehicleNumber'] ?? '—',
                              colVehicle,
                              color: trip['vehicleNumber'] != null
                                  ? kTextPrimaryColor
                                  : Colors.grey.shade400,
                            ),
                            _tblCell(
                              '${trip['distance']?.toStringAsFixed(1) ?? '0'} km',
                              colDist,
                              fontWeight: FontWeight.w600,
                            ),
                            _tblCell(
                              _formatDateTime(trip['scheduledPickupTime']),
                              colTime,
                              fontSize: 12,
                            ),
                            SizedBox(
                              width: colActions,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                child: _buildActionButtons(
                                    trip, status, adminConfirmed),
                              ),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hdr(String title, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Text(title,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.3)),
    );
  }

  Widget _tblCell(
    String text,
    double width, {
    int maxLines = 1,
    FontWeight? fontWeight,
    Color? color,
    double? fontSize,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize ?? 15,
          fontWeight: fontWeight,
          color: color ?? kTextPrimaryColor,
          height: 1.4,
        ),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildStatusBadge(String status, {bool adminConfirmed = false}) {
    Color backgroundColor;
    Color textColor;
    String displayText =
        _getStatusLabel(status, adminConfirmed: adminConfirmed);

    switch (status.toLowerCase()) {
      case 'assigned':
        backgroundColor = Colors.orange[100]!;
        textColor = Colors.orange[900]!;
        break;
      case 'accepted':
        backgroundColor =
            adminConfirmed ? Colors.green[100]! : Colors.blue[100]!;
        textColor =
            adminConfirmed ? Colors.green[900]! : Colors.blue[900]!;
        break;
      case 'declined':
        backgroundColor = Colors.red[100]!;
        textColor = Colors.red[900]!;
        break;
      case 'confirmed':
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[900]!;
        break;
      case 'started':
      case 'in_progress':
        backgroundColor = Colors.purple[100]!;
        textColor = Colors.purple[900]!;
        break;
      case 'completed':
        backgroundColor = Colors.grey[200]!;
        textColor = Colors.grey[900]!;
        break;
      case 'cancelled':
        backgroundColor = Colors.red[200]!;
        textColor = Colors.red[900]!;
        break;
      default:
        backgroundColor = Colors.grey[100]!;
        textColor = Colors.grey[800]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        displayText,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ============================================================================
  // FIX 1 + FIX 2 — ACTION BUTTONS
  // For started/in_progress trips: Track button + Share Live Location button
  // ============================================================================
  Widget _buildActionButtons(
      Map<String, dynamic> trip, String status, bool adminConfirmed) {
    Widget primaryAction;

    if (status == 'accepted' && !adminConfirmed) {
      primaryAction = _actionBtn(
        'Confirm',
        Icons.check_circle,
        kSuccessColor,
        () => _confirmAcceptedTrip(trip),
      );
    } else if (status == 'declined') {
      primaryAction = _actionBtn(
        'Reassign',
        Icons.swap_horiz,
        const Color(0xFFE67E22),
        () => _showAssignVehicleDialog(trip),
      );
    } else if (status == 'pending_assignment' ||
        status == 'pending' ||
        status == 'assigned') {
      primaryAction = _actionBtn(
        status == 'assigned' ? 'Reassign' : 'Assign',
        Icons.assignment,
        kPrimaryColor,
        () => _showAssignVehicleDialog(trip),
      );
    } else if (status == 'started' || status == 'in_progress') {
      // FIX 1 + FIX 2: Track opens fleet map, Share sends live URL via WhatsApp
      primaryAction = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _actionBtn(
            'Track',
            Icons.map,
            kPrimaryColor,
            () => _trackTrip(trip),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Share Live Location via WhatsApp',
            child: InkWell(
              onTap: () => _shareWhatsAppLiveLocation(trip),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kWhatsAppColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: kWhatsAppColor.withOpacity(0.4)),
                ),
                child: const Icon(Icons.share_location,
                    size: 20, color: kWhatsAppColor),
              ),
            ),
          ),
        ],
      );
    } else {
      primaryAction = const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        primaryAction,
        const SizedBox(width: 6),
        Tooltip(
          message: 'View History',
          child: InkWell(
            onTap: () => _showTripHistory(trip),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Icon(Icons.history,
                  size: 20, color: Colors.grey.shade700),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: 'WhatsApp',
          child: InkWell(
            onTap: () => _showWhatsAppDialog(trip),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kWhatsAppColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: kWhatsAppColor.withOpacity(0.4)),
              ),
              child:
                  const Icon(Icons.chat, size: 20, color: kWhatsAppColor),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: 'Delete Trip',
          child: InkWell(
            onTap: () => _deleteTrip(trip),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kErrorColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: kErrorColor.withOpacity(0.3)),
              ),
              child: const Icon(Icons.delete_outline,
                  size: 20, color: kErrorColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  // ============================================================================
  // EMPTY STATE
  // ============================================================================
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No trips found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a new trip to see it here',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showStartNewTripOverlay,
              icon: const Icon(Icons.add),
              label: const Text('Start New Trip'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // ERROR STATE
  // ============================================================================
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(
              'Error Loading Trips',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage ?? 'Unknown error',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadTrips,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}