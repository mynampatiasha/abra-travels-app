// lib/features/admin/trip_verification/trip_verification_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:abra_fleet/core/services/trip_verification_service.dart';
import 'package:abra_fleet/core/services/driver_service.dart';
import 'package:abra_fleet/core/services/vehicle_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/features/admin/widgets/country_state_city_filter.dart';

class TripVerificationScreen extends StatefulWidget {
  final bool showBackButton;
  
  const TripVerificationScreen({
    Key? key,
    this.showBackButton = false,
  }) : super(key: key);

  @override
  State<TripVerificationScreen> createState() => _TripVerificationScreenState();
}

class _TripVerificationScreenState extends State<TripVerificationScreen> {
  final TripVerificationService _tripService = TripVerificationService();
  final DriverService _driverService = DriverService();
  final VehicleService _vehicleService = VehicleService();
  
  // Data
  List<Map<String, dynamic>> trips = [];
  List<Map<String, dynamic>> drivers = [];
  List<Map<String, dynamic>> vehicles = [];
  
  // Loading states
  bool isLoading = false;
  bool isLoadingFilters = true;
  
  // Filters
  DateTime? startDate;
  DateTime? endDate;
  String selectedDriverId = 'all';
  String selectedVehicleId = 'all';
  String selectedStatus = 'all';
  
  // Active filters for CountryStateCityFilter
  Map<String, dynamic> _activeFilters = {};
  
  // Search controllers for dropdowns
  final TextEditingController _driverSearchController = TextEditingController();
  final TextEditingController _vehicleSearchController = TextEditingController();
  
  // Filtered lists for search
  List<Map<String, dynamic>> filteredDrivers = [];
  List<Map<String, dynamic>> filteredVehicles = [];

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  @override
  void dispose() {
    _driverSearchController.dispose();
    _vehicleSearchController.dispose();
    super.dispose();
  }

  Future<void> _initializeScreen() async {
    await _loadFilterData();
    await _loadTrips();
  }

  // ============================================================================
  // Load filter data (drivers, vehicles) - FIXED
  // ============================================================================
  Future<void> _loadFilterData() async {
    setState(() => isLoadingFilters = true);
    
    try {
      print('🔄 Loading drivers and vehicles for filters...');
      
      // Fetch drivers using DriverService
      final driversResponse = await _driverService.getAllDrivers();
      
      // Fetch vehicles using VehicleService
      final vehiclesResponse = await _vehicleService.getVehicles();
      
      if (driversResponse['success'] == true) {
        final driversList = List<Map<String, dynamic>>.from(driversResponse['data'] ?? []);
        print('✅ Loaded ${driversList.length} drivers');
        
        setState(() {
          drivers = driversList.map((driver) {
            return {
              'id': driver['_id'] ?? driver['id'],
              'name': driver['personalInfo']?['name'] ?? driver['name'] ?? 'Unknown',
              'driverId': driver['driverId'] ?? '',
              'status': driver['status'] ?? 'active',
            };
          }).toList();
          filteredDrivers = List.from(drivers);
        });
      }
      
      if (vehiclesResponse['success'] == true) {
        final vehiclesList = List<Map<String, dynamic>>.from(vehiclesResponse['data'] ?? []);
        print('✅ Loaded ${vehiclesList.length} vehicles');
        
        setState(() {
          vehicles = vehiclesList.map((vehicle) {
            return {
              'id': vehicle['_id'] ?? vehicle['id'],
              'number': vehicle['registrationNumber'] ?? vehicle['number'] ?? 'Unknown',
              'makeModel': vehicle['makeModel'] ?? '',
              'status': vehicle['status'] ?? 'active',
            };
          }).toList();
          filteredVehicles = List.from(vehicles);
        });
      }
      
      setState(() => isLoadingFilters = false);
      
    } catch (e) {
      print('❌ Error loading filter data: $e');
      setState(() => isLoadingFilters = false);
      _showSnackBar('Error loading filters: $e', Colors.red);
    }
  }

  // ============================================================================
  // Load trips with current filters
  // ============================================================================
  Future<void> _loadTrips() async {
    setState(() => isLoading = true);
    
    try {
      final response = await _tripService.getTripsForVerification(
        startDate: startDate?.toIso8601String().split('T')[0],
        endDate: endDate?.toIso8601String().split('T')[0],
        driverId: selectedDriverId != 'all' ? selectedDriverId : null,
        vehicleId: selectedVehicleId != 'all' ? selectedVehicleId : null,
        status: selectedStatus != 'all' ? selectedStatus : null,
      );
      
      setState(() {
        trips = List<Map<String, dynamic>>.from(response['data'] ?? []);
        isLoading = false;
      });
      
      _showSnackBar('Loaded ${trips.length} trip(s)', Colors.green);
      
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar('Error loading trips: $e', Colors.red);
    }
  }

  // ============================================================================
  // Search functionality for dropdowns
  // ============================================================================
  void _filterDrivers(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredDrivers = List.from(drivers);
      } else {
        filteredDrivers = drivers.where((driver) {
          final name = driver['name'].toString().toLowerCase();
          final driverId = driver['driverId'].toString().toLowerCase();
          final searchQuery = query.toLowerCase();
          return name.contains(searchQuery) || driverId.contains(searchQuery);
        }).toList();
      }
    });
  }

  void _filterVehicles(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredVehicles = List.from(vehicles);
      } else {
        filteredVehicles = vehicles.where((vehicle) {
          final number = vehicle['number'].toString().toLowerCase();
          final makeModel = vehicle['makeModel'].toString().toLowerCase();
          final searchQuery = query.toLowerCase();
          return number.contains(searchQuery) || makeModel.contains(searchQuery);
        }).toList();
      }
    });
  }

  // ============================================================================
  // Show searchable driver dropdown
  // ============================================================================
  Future<void> _showDriverSearchDialog() async {
    _driverSearchController.clear();
    filteredDrivers = List.from(drivers);
    
    final selectedDriver = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Select Driver'),
          content: SizedBox(
            width: 400,
            height: 500,
            child: Column(
              children: [
                // Search bar
                TextField(
                  controller: _driverSearchController,
                  decoration: const InputDecoration(
                    labelText: 'Search driver',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      if (value.isEmpty) {
                        filteredDrivers = List.from(drivers);
                      } else {
                        filteredDrivers = drivers.where((driver) {
                          final name = driver['name'].toString().toLowerCase();
                          final driverId = driver['driverId'].toString().toLowerCase();
                          final searchQuery = value.toLowerCase();
                          return name.contains(searchQuery) || driverId.contains(searchQuery);
                        }).toList();
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),
                // List
                Expanded(
                  child: ListView(
                    children: [
                      ListTile(
                        title: const Text('All Drivers'),
                        leading: const Icon(Icons.people),
                        onTap: () => Navigator.pop(context, {'id': 'all', 'name': 'All Drivers'}),
                      ),
                      const Divider(),
                      ...filteredDrivers.map((driver) {
                        return ListTile(
                          title: Text(driver['name']),
                          subtitle: Text('ID: ${driver['driverId']}'),
                          leading: Icon(
                            Icons.person,
                            color: driver['status'] == 'active' ? Colors.green : Colors.grey,
                          ),
                          onTap: () => Navigator.pop(context, driver),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );

    if (selectedDriver != null) {
      setState(() {
        selectedDriverId = selectedDriver['id'];
      });
      await _loadTrips();
    }
  }

  // ============================================================================
  // Show searchable vehicle dropdown
  // ============================================================================
  Future<void> _showVehicleSearchDialog() async {
    _vehicleSearchController.clear();
    filteredVehicles = List.from(vehicles);
    
    final selectedVehicle = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Select Vehicle'),
          content: SizedBox(
            width: 400,
            height: 500,
            child: Column(
              children: [
                // Search bar
                TextField(
                  controller: _vehicleSearchController,
                  decoration: const InputDecoration(
                    labelText: 'Search vehicle',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      if (value.isEmpty) {
                        filteredVehicles = List.from(vehicles);
                      } else {
                        filteredVehicles = vehicles.where((vehicle) {
                          final number = vehicle['number'].toString().toLowerCase();
                          final makeModel = vehicle['makeModel'].toString().toLowerCase();
                          final searchQuery = value.toLowerCase();
                          return number.contains(searchQuery) || makeModel.contains(searchQuery);
                        }).toList();
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),
                // List
                Expanded(
                  child: ListView(
                    children: [
                      ListTile(
                        title: const Text('All Vehicles'),
                        leading: const Icon(Icons.directions_car),
                        onTap: () => Navigator.pop(context, {'id': 'all', 'number': 'All Vehicles'}),
                      ),
                      const Divider(),
                      ...filteredVehicles.map((vehicle) {
                        return ListTile(
                          title: Text(vehicle['number']),
                          subtitle: Text(vehicle['makeModel']),
                          leading: Icon(
                            Icons.directions_car,
                            color: vehicle['status'] == 'active' ? Colors.green : Colors.grey,
                          ),
                          onTap: () => Navigator.pop(context, vehicle),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );

    if (selectedVehicle != null) {
      setState(() {
        selectedVehicleId = selectedVehicle['id'];
      });
      await _loadTrips();
    }
  }

  // ============================================================================
  // Show date picker
  // ============================================================================
  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate 
          ? (startDate ?? DateTime.now()) 
          : (endDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          startDate = picked;
        } else {
          endDate = picked;
        }
      });
      await _loadTrips();
    }
  }

  // ============================================================================
  // Clear all filters
  // ============================================================================
  Future<void> _clearFilters() async {
    setState(() {
      startDate = null;
      endDate = null;
      selectedDriverId = 'all';
      selectedVehicleId = 'all';
      selectedStatus = 'all';
    });
    await _loadTrips();
  }

  // ============================================================================
  // Show odometer photo
  // ============================================================================
  Future<void> _showOdometerPhoto(String photoId, String title) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[700],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.camera_alt, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Photo
              Expanded(
                child: Container(
                  color: Colors.black,
                  child: Center(
                    child: Image.network(
                      _tripService.getOdometerPhotoUrl(photoId),
                      headers: {'Authorization': 'Bearer $token'},
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, color: Colors.white, size: 48),
                              SizedBox(height: 16),
                              Text(
                                'Failed to load photo',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // Show trip details dialog
  // ============================================================================
  void _showTripDetails(Map<String, dynamic> trip) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[700],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Trip ${trip['tripNumber'] ?? trip['id']}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _buildTripDetailsContent(trip),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // Build trip details content
  // ============================================================================
  Widget _buildTripDetailsContent(Map<String, dynamic> trip) {
    final stops = List<Map<String, dynamic>>.from(trip['stops'] ?? []);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Trip Summary
        _buildSectionTitle('Trip Summary'),
        const SizedBox(height: 12),
        _buildInfoCard([
          _buildInfoRow('Driver', trip['driverName'] ?? 'Unknown'),
          _buildInfoRow('Phone', trip['driverPhone'] ?? 'N/A'),
          _buildInfoRow('Vehicle', trip['vehicleNumber'] ?? 'N/A'),
          _buildInfoRow('Date', trip['scheduledDate'] ?? 'N/A'),
          _buildInfoRow('Time', '${trip['startTime'] ?? '00:00'} - ${trip['endTime'] ?? '00:00'}'),
          _buildInfoRow('Status', _getStatusBadge(trip['status'])),
        ]),
        
        const SizedBox(height: 24),
        
        // Odometer Readings
        _buildSectionTitle('Odometer Readings'),
        const SizedBox(height: 12),
        Row(
          children: [
            // Start Odometer
            Expanded(
              child: _buildOdometerCard(
                'START ODOMETER',
                trip['startOdometer'],
                Colors.green,
              ),
            ),
            const SizedBox(width: 16),
            // End Odometer
            Expanded(
              child: _buildOdometerCard(
                'END ODOMETER',
                trip['endOdometer'],
                Colors.red,
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 24),
        
        // Distance Analysis
        if (trip['actualDistance'] != null) ...[
          _buildSectionTitle('Distance Analysis'),
          const SizedBox(height: 12),
          _buildInfoCard([
            _buildInfoRow(
              'Odometer Distance',
              '${trip['actualDistance']?.toStringAsFixed(1) ?? '0'} km',
            ),
            _buildInfoRow(
              'GPS Distance',
              '${trip['totalDistance']?.toStringAsFixed(1) ?? '0'} km',
            ),
            if (trip['actualDistance'] != null && trip['totalDistance'] != null)
              _buildInfoRow(
                'Discrepancy',
                _getDiscrepancyText(
                  trip['actualDistance'].toDouble(),
                  trip['totalDistance'].toDouble(),
                ),
              ),
          ]),
          const SizedBox(height: 24),
        ],
        
        // Stops
        _buildSectionTitle('Route & Stops (${stops.length})'),
        const SizedBox(height: 12),
        ...stops.asMap().entries.map((entry) {
          final index = entry.key;
          final stop = entry.value;
          return _buildStopCard(stop, index + 1);
        }).toList(),
        
        const SizedBox(height: 24),
        
        // Customer Feedback
        if (trip['feedbackSubmitted'] == true && trip['customerFeedback'] != null) ...[
          _buildSectionTitle('Customer Feedback'),
          const SizedBox(height: 12),
          _buildFeedbackCard(trip['customerFeedback']),
        ],
      ],
    );
  }

  // ============================================================================
  // Build odometer card
  // ============================================================================
  Widget _buildOdometerCard(String title, Map<String, dynamic>? odometer, Color color) {
    final hasData = odometer != null && odometer['reading'] != null;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.3), width: 2),
        borderRadius: BorderRadius.circular(8),
        color: color.withOpacity(0.05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 12),
          if (hasData) ...[
            Text(
              '${odometer['reading']} km',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _formatTimestamp(odometer['timestamp']),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (odometer['photoId'] != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showOdometerPhoto(
                    odometer['photoId'],
                    title,
                  ),
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text('View Photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
          ] else ...[
            const Text(
              'Not available',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================================
  // Build stop card
  // ============================================================================
  Widget _buildStopCard(Map<String, dynamic> stop, int sequence) {
    final type = stop['type'] ?? 'pickup';
    final isPickup = type == 'pickup';
    final status = stop['status'] ?? 'pending';
    
    Color statusColor;
    IconData statusIcon;
    
    switch (status) {
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'arrived':
        statusColor = Colors.orange;
        statusIcon = Icons.location_on;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.pending;
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
        color: status == 'completed' ? Colors.green[50] : Colors.grey[50],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isPickup ? Colors.blue : Colors.orange,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    sequence.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isPickup ? '📍 Pickup' : '🏁 Drop',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon, size: 12, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                status.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (stop['customer'] != null)
                      Text(
                        stop['customer']['name'] ?? 'Unknown',
                        style: const TextStyle(fontSize: 12),
                      ),
                    if (stop['location'] != null)
                      Text(
                        stop['location']['address'] ?? 'Unknown location',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (stop['arrivedAt'] != null || stop['departedAt'] != null) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              children: [
                if (stop['arrivedAt'] != null)
                  Expanded(
                    child: Text(
                      'Arrived: ${_formatTimestamp(stop['arrivedAt'])}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                if (stop['departedAt'] != null)
                  Expanded(
                    child: Text(
                      'Departed: ${_formatTimestamp(stop['departedAt'])}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================================
  // Build feedback card
  // ============================================================================
  Widget _buildFeedbackCard(Map<String, dynamic> feedback) {
    final rating = feedback['rating'] ?? 0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.amber[300]!),
        borderRadius: BorderRadius.circular(8),
        color: Colors.amber[50],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star, color: Colors.amber, size: 24),
              const SizedBox(width: 8),
              Text(
                '$rating/5 Stars',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (feedback['feedback'] != null && feedback['feedback'].toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              feedback['feedback'],
              style: const TextStyle(fontSize: 14),
            ),
          ],
          if (feedback['submittedAt'] != null) ...[
            const SizedBox(height: 8),
            Text(
              'Submitted: ${_formatTimestamp(feedback['submittedAt'])}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================================
  // Helper widgets
  // ============================================================================
  
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey[50],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (value is Widget)
            value
          else
            Text(
              value.toString(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _getStatusBadge(String? status) {
    Color color;
    String text;
    
    switch (status) {
      case 'completed':
        color = Colors.green;
        text = 'Completed';
        break;
      case 'in_progress':
        color = Colors.blue;
        text = 'In Progress';
        break;
      case 'started':
        color = Colors.orange;
        text = 'Started';
        break;
      default:
        color = Colors.grey;
        text = status ?? 'Unknown';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _getDiscrepancyText(double odometer, double gps) {
    final diff = (odometer - gps).abs();
    final percentage = (diff / odometer * 100);
    
    Color color;
    if (percentage < 2) {
      color = Colors.green;
    } else if (percentage < 5) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }
    
    return Text(
      '${diff.toStringAsFixed(1)} km (${percentage.toStringAsFixed(1)}%)',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: color,
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    
    try {
      DateTime dt;
      if (timestamp is String) {
        dt = DateTime.parse(timestamp);
      } else if (timestamp is Map && timestamp['\$date'] != null) {
        dt = DateTime.parse(timestamp['\$date']);
      } else {
        return timestamp.toString();
      }
      
      return DateFormat('MMM dd, yyyy hh:mm a').format(dt);
    } catch (e) {
      return timestamp.toString();
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ============================================================================
  // BUILD UI
  // ============================================================================
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Trip Reports & Verification'),
        backgroundColor: const Color(0xFF1565C0),
        elevation: 0,
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTrips,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters Section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Filters',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                if (isLoadingFilters)
                  const Center(child: CircularProgressIndicator())
                else
                  _buildFilters(),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          // Trips Table
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : trips.isEmpty
                    ? _buildEmptyState()
                    : _buildTripsTable(),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // Build filters - UPDATED with CountryStateCityFilter
  // ============================================================================
  Widget _buildFilters() {
    // Get display names
    String driverDisplayName = 'All Drivers';
    String vehicleDisplayName = 'All Vehicles';
    
    if (selectedDriverId != 'all') {
      final driver = drivers.firstWhere(
        (d) => d['id'] == selectedDriverId,
        orElse: () => {'name': 'Unknown'},
      );
      driverDisplayName = driver['name'];
    }
    
    if (selectedVehicleId != 'all') {
      final vehicle = vehicles.firstWhere(
        (v) => v['id'] == selectedVehicleId,
        orElse: () => {'number': 'Unknown'},
      );
      vehicleDisplayName = vehicle['number'];
    }
    
    return Column(
      children: [
        // CountryStateCityFilter widget (replaces From Date and To Date)
        CountryStateCityFilter(
          onFilterApplied: (filterData) {
            setState(() {
              _activeFilters = filterData;
              
              // Map date filters
              if (filterData['startDate'] != null) {
                startDate = filterData['startDate'];
              } else {
                startDate = null;
              }
              
              if (filterData['endDate'] != null) {
                endDate = filterData['endDate'];
              } else {
                endDate = null;
              }
            });
            
            _loadTrips();
            
            // Show success message
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Filters applied successfully!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // Driver - Searchable
            Expanded(
              child: InkWell(
                onTap: _showDriverSearchDialog,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Driver',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    suffixIcon: Icon(Icons.search),
                  ),
                  child: Text(
                    driverDisplayName,
                    style: TextStyle(
                      color: selectedDriverId != 'all' ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Vehicle - Searchable
            Expanded(
              child: InkWell(
                onTap: _showVehicleSearchDialog,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Vehicle',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    suffixIcon: Icon(Icons.search),
                  ),
                  child: Text(
                    vehicleDisplayName,
                    style: TextStyle(
                      color: selectedVehicleId != 'all' ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Status
            Expanded(
              child: DropdownButtonFormField<String>(
                value: selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All Status')),
                  DropdownMenuItem(value: 'completed', child: Text('Completed')),
                  DropdownMenuItem(value: 'in_progress', child: Text('In Progress')),
                  DropdownMenuItem(value: 'started', child: Text('Started')),
                ],
                onChanged: (value) {
                  setState(() => selectedStatus = value!);
                  _loadTrips();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: _clearFilters,
              icon: const Icon(Icons.clear),
              label: const Text('Clear Filters'),
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================================
  // Build trips table
  // ============================================================================
  Widget _buildTripsTable() {
    return SingleChildScrollView(
      child: Container(
        margin: const EdgeInsets.all(16),
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
            // Table Header
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
                  const SizedBox(width: 40), // For expand icon
                  const Expanded(flex: 2, child: Text('Trip ID', style: TextStyle(fontWeight: FontWeight.bold))),
                  const Expanded(flex: 2, child: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                  const Expanded(flex: 2, child: Text('Driver', style: TextStyle(fontWeight: FontWeight.bold))),
                  const Expanded(flex: 2, child: Text('Vehicle', style: TextStyle(fontWeight: FontWeight.bold))),
                  const Expanded(flex: 2, child: Text('Start → End', style: TextStyle(fontWeight: FontWeight.bold))),
                  const Expanded(flex: 1, child: Text('Distance', style: TextStyle(fontWeight: FontWeight.bold))),
                  const Expanded(flex: 1, child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                  const SizedBox(width: 100), // For actions
                ],
              ),
            ),
            
            // Table Rows
            ...trips.map((trip) => _buildTripRow(trip)).toList(),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // Build trip row
  // ============================================================================
  Widget _buildTripRow(Map<String, dynamic> trip) {
    final tripId = trip['id'];
    
    return InkWell(
      onTap: () => _showTripDetails(trip),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Icon(
                Icons.visibility,
                size: 20,
                color: Colors.grey[600],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                trip['tripNumber']?.toString() ?? tripId.substring(0, 8),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                trip['scheduledDate'] ?? 'N/A',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                trip['driverName'] ?? 'Unknown',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                trip['vehicleNumber'] ?? 'N/A',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '${trip['startOdometer']?['reading'] ?? '?'} → ${trip['endOdometer']?['reading'] ?? '?'}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                trip['actualDistance'] != null 
                    ? '${trip['actualDistance'].toStringAsFixed(1)} km'
                    : 'N/A',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              flex: 1,
              child: _getStatusBadge(trip['status']),
            ),
            SizedBox(
              width: 100,
              child: TextButton(
                onPressed: () => _showTripDetails(trip),
                child: const Text('Details', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // Build empty state
  // ============================================================================
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No trips found',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _clearFilters,
            icon: const Icon(Icons.clear),
            label: const Text('Clear Filters'),
          ),
        ],
      ),
    );
  }
}