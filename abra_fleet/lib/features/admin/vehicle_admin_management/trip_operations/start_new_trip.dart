import 'package:flutter/material.dart';
import 'package:abra_fleet/core/services/vehicle_service.dart';
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:abra_fleet/app/config/api_config.dart';
import 'route_selection_page.dart';

class StartNewTripPage extends StatefulWidget {
  final VoidCallback onBack;

  const StartNewTripPage({
    Key? key,
    required this.onBack,
  }) : super(key: key);

  @override
  _StartNewTripPageState createState() => _StartNewTripPageState();
}

class _StartNewTripPageState extends State<StartNewTripPage> {
  final VehicleService _vehicleService = VehicleService();
  final ApiService _apiService = ApiService();
  
  String? _selectedVehicleId;
  LatLng? _startPoint;
  LatLng? _endPoint;
  String? _startAddress;
  String? _endAddress;
  DateTime? _selectedPickupTime;
  DateTime? _selectedDropTime;
  
  // Customer details controllers
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerEmailController = TextEditingController();
  final TextEditingController _customerPhoneController = TextEditingController();
  
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _filteredVehicles = [];
  bool _isLoadingVehicles = true;
  String? _vehicleLoadError;
  final _vehicleSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadVehicles();
    _selectedPickupTime = DateTime.now().add(const Duration(minutes: 30));
  }

  @override
  void dispose() {
    _vehicleSearchController.dispose();
    _customerNameController.dispose();
    _customerEmailController.dispose();
    _customerPhoneController.dispose();
    super.dispose();
  }

  Future<void> _selectPickupTime() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedPickupTime ?? DateTime.now().add(const Duration(minutes: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );

    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedPickupTime ?? DateTime.now().add(const Duration(minutes: 30))),
      );

      if (pickedTime != null) {
        setState(() {
          _selectedPickupTime = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  Future<void> _selectDropTime() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDropTime ?? (_selectedPickupTime?.add(const Duration(hours: 1)) ?? DateTime.now().add(const Duration(hours: 1))),
      firstDate: _selectedPickupTime ?? DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );

    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDropTime ?? (_selectedPickupTime?.add(const Duration(hours: 1)) ?? DateTime.now().add(const Duration(hours: 1)))),
      );

      if (pickedTime != null) {
        setState(() {
          _selectedDropTime = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  Widget _buildCustomerDetailsCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Customer Details',
          style: TextStyle(
            fontSize: 16.0,
            fontWeight: FontWeight.bold,
            color: Color(0xFF212121),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Customer Name
                TextField(
                  controller: _customerNameController,
                  decoration: InputDecoration(
                    labelText: 'Customer Name *',
                    hintText: 'Enter customer full name',
                    prefixIcon: const Icon(Icons.person, color: Color(0xFF0D47A1)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                
                // Customer Email
                TextField(
                  controller: _customerEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Customer Email',
                    hintText: 'Enter customer email (optional)',
                    prefixIcon: const Icon(Icons.email, color: Color(0xFF0D47A1)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Customer Phone
                TextField(
                  controller: _customerPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Customer Phone *',
                    hintText: 'Enter customer phone number',
                    prefixIcon: const Icon(Icons.phone, color: Color(0xFF0D47A1)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Customer will be notified via email and phone',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
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
    );
  }

  Widget _buildTimeSelectionCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Trip Schedule',
          style: TextStyle(
            fontSize: 16.0,
            fontWeight: FontWeight.bold,
            color: Color(0xFF212121),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule, color: Colors.blue.shade600, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pickup Time',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF424242),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedPickupTime != null
                                ? '${_selectedPickupTime!.day}/${_selectedPickupTime!.month}/${_selectedPickupTime!.year} at ${_selectedPickupTime!.hour.toString().padLeft(2, '0')}:${_selectedPickupTime!.minute.toString().padLeft(2, '0')}'
                                : 'Not selected',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _selectPickupTime,
                      child: Text(_selectedPickupTime != null ? 'Change' : 'Select'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.schedule_outlined, color: Colors.orange.shade600, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Drop Time (Optional)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF424242),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedDropTime != null
                                ? '${_selectedDropTime!.day}/${_selectedDropTime!.month}/${_selectedDropTime!.year} at ${_selectedDropTime!.hour.toString().padLeft(2, '0')}:${_selectedDropTime!.minute.toString().padLeft(2, '0')}'
                                : 'Will be calculated automatically',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _selectDropTime,
                      child: Text(_selectedDropTime != null ? 'Change' : 'Set'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _loadVehicles() async {
    setState(() {
      _isLoadingVehicles = true;
      _vehicleLoadError = null;
    });

    try {
      print('🚗 Loading vehicles for trip creation...');
      final response = await _vehicleService.getVehicles(limit: 100);

      if (response['success'] == true) {
        final List<dynamic> vehiclesData = response['data'] ?? [];
        print('📊 Received ${vehiclesData.length} vehicles from API');
        
        setState(() {
          _vehicles = vehiclesData
              .where((vehicle) {
                final status = (vehicle['status'] ?? 'active').toString().toUpperCase();
                final hasDriver = _hasAssignedDriver(vehicle);
                return status == 'ACTIVE' && hasDriver;
              })
              .map((vehicle) {
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

            String seatingCapacity = '';
            try {
              if (vehicle['seatCapacity'] != null) {
                seatingCapacity = vehicle['seatCapacity'].toString();
              } else if (vehicle['seatingCapacity'] != null) {
                seatingCapacity = vehicle['seatingCapacity'].toString();
              } else if (vehicle['capacity'] != null) {
                final capacity = vehicle['capacity'];
                if (capacity is Map && capacity['passengers'] != null) {
                  seatingCapacity = capacity['passengers'].toString();
                } else if (capacity is num) {
                  seatingCapacity = capacity.toString();
                } else {
                  seatingCapacity = capacity.toString();
                }
              } else {
                seatingCapacity = '4';
              }
            } catch (e) {
              print('Error parsing seating capacity for vehicle ${vehicle['vehicleId']}: $e');
              seatingCapacity = '4';
            }

            return {
              'id': mongoId,
              'vehicleId': vehicle['vehicleId'] ?? '',
              'registration': vehicle['registrationNumber'] ?? '',
              'type': (vehicle['type'] ?? '').toString().toUpperCase(),
              'model': '${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''}'.trim(),
              'status': (vehicle['status'] ?? 'active').toString().toUpperCase(),
              'seatingCapacity': seatingCapacity,
              'driverName': driverName,
              'driverPhone': driverPhone,
              'assignedDriver': assignedDriver,
            };
          }).toList();
          
          _filteredVehicles = _vehicles;
          print('✅ Processed ${_vehicles.length} active vehicles with drivers');
          _isLoadingVehicles = false;
        });
      } else {
        setState(() {
          _vehicleLoadError = response['message'] ?? 'Failed to load vehicles';
          _isLoadingVehicles = false;
        });
      }
    } catch (e) {
      print('❌ Error loading vehicles: $e');
      setState(() {
        _vehicleLoadError = 'Error loading vehicles: $e';
        _isLoadingVehicles = false;
      });
    }
  }

  bool _hasAssignedDriver(Map<String, dynamic> vehicle) {
    final assignedDriver = vehicle['assignedDriver'];
    if (assignedDriver == null) return false;
    
    if (assignedDriver is Map) {
      return assignedDriver.isNotEmpty && 
             (assignedDriver['name'] != null || assignedDriver['driverId'] != null);
    } else if (assignedDriver is String) {
      return assignedDriver.isNotEmpty;
    }
    
    return false;
  }

  Future<void> _openRouteSelection() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => RouteSelectionPage(
          initialStartPoint: _startPoint,
          initialEndPoint: _endPoint,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _startPoint = result['startPoint'] as LatLng?;
        _endPoint = result['endPoint'] as LatLng?;
        _startAddress = result['startAddress'] as String?;
        _endAddress = result['endAddress'] as String?;
      });
    }
  }

  double _calculateRouteDistance() {
    if (_startPoint == null || _endPoint == null) return 0;
    
    final distance = Distance();
    return distance.as(
      LengthUnit.Kilometer,
      _startPoint!,
      _endPoint!,
    );
  }

  Map<String, dynamic>? _getSelectedVehicle() {
    if (_selectedVehicleId == null) return null;
    try {
      return _vehicles.firstWhere((v) => v['id'] == _selectedVehicleId);
    } catch (e) {
      return null;
    }
  }

  Future<void> _startTrip() async {
    // Validation
    if (_customerNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Please enter customer name'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (_customerPhoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Please enter customer phone number'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final vehicle = _getSelectedVehicle();
    
    print('=== START TRIP ===');
    print('Vehicle MongoDB ID: $_selectedVehicleId');
    print('Vehicle ID: ${vehicle?['vehicleId']}');
    print('Registration: ${vehicle?['registration']}');
    print('Customer Name: ${_customerNameController.text}');
    print('Customer Email: ${_customerEmailController.text}');
    print('Customer Phone: ${_customerPhoneController.text}');
    print('Start Point: ${_startPoint!.latitude}, ${_startPoint!.longitude}');
    print('End Point: ${_endPoint!.latitude}, ${_endPoint!.longitude}');
    print('Total Distance: ${_calculateRouteDistance().toStringAsFixed(2)} km');
    print('==================');
    
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Creating trip...'),
            ],
          ),
        ),
      );
      
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      
      if (token == null || token.isEmpty) {
        throw Exception('User not authenticated. Please login again.');
      }
      
      print('✅ User authenticated with JWT token');
      
      final tripData = {
        'vehicleId': _selectedVehicleId,
        'startPoint': {
          'latitude': _startPoint!.latitude,
          'longitude': _startPoint!.longitude,
          'address': _startAddress ?? 'Pickup Location',
        },
        'endPoint': {
          'latitude': _endPoint!.latitude,
          'longitude': _endPoint!.longitude,
          'address': _endAddress ?? 'Drop Location',
        },
        'distance': _calculateRouteDistance(),
        'scheduledPickupTime': (_selectedPickupTime ?? DateTime.now().add(const Duration(minutes: 30))).toIso8601String(),
        'scheduledDropTime': _selectedDropTime?.toIso8601String(),
        'customerName': _customerNameController.text.trim(),
        'customerEmail': _customerEmailController.text.trim(),
        'customerPhone': _customerPhoneController.text.trim(),
        'tripType': 'manual',
        'notes': 'Trip created from admin panel',
      };
      
      print('📋 Trip data prepared: ${tripData.keys}');
      
      final responseData = await _apiService.createTrip(tripData);
      
      if (mounted) Navigator.of(context).pop();
      
      if (responseData['success'] == true) {
        print('✅ Trip created successfully');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '✅ Trip Created Successfully!',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('Trip Number: ${responseData['data']['tripNumber']}'),
                  Text('Driver: ${responseData['data']['driver']['name']}'),
                  Text('Customer: ${_customerNameController.text}'),
                  Text('Distance: ${_calculateRouteDistance().toStringAsFixed(1)} km'),
                  const SizedBox(height: 4),
                  const Text('✅ Driver notified  ✅ Customer notified'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        
        _showTripCreatedDialog(responseData['data']);
        
      } else {
        throw Exception(responseData['message'] ?? 'Failed to create trip');
      }
      
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      
      print('❌ Error creating trip: $e');
      
      String errorMessage = 'Failed to create trip';
      String? errorDetails;
      
      if (e.toString().contains('ApiException:')) {
        try {
          final errorJson = e.toString().replaceFirst('ApiException: ', '');
          final errorData = json.decode(errorJson);
          errorMessage = errorData['message'] ?? errorMessage;
          errorDetails = errorData['details']?.toString();
        } catch (parseError) {
          errorMessage = e.toString().replaceFirst('ApiException: ', '');
        }
      } else {
        errorMessage = e.toString();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '❌ Failed to Create Trip',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text('Error: $errorMessage'),
                if (errorDetails != null) ...[
                  const SizedBox(height: 4),
                  Text('Details: $errorDetails', style: const TextStyle(fontSize: 12)),
                ],
                const SizedBox(height: 4),
                const Text('Please check your connection and try again.'),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'RETRY',
              textColor: Colors.white,
              onPressed: () => _startTrip(),
            ),
          ),
        );
      }
    }
  }
  
  void _showTripCreatedDialog(Map<String, dynamic> tripData) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Trip Created Successfully!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTripDetailRow('Trip Number:', tripData['tripNumber'] ?? 'N/A'),
              _buildTripDetailRow('Status:', tripData['status'] ?? 'N/A'),
              const Divider(height: 20),
              
              const Text(
                'Customer Details:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              _buildTripDetailRow('Name:', tripData['customer']['name'] ?? 'N/A'),
              _buildTripDetailRow('Email:', tripData['customer']['email'] ?? 'N/A'),
              _buildTripDetailRow('Phone:', tripData['customer']['phone'] ?? 'N/A'),
              const Divider(height: 20),
              
              const Text(
                'Vehicle & Driver:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              _buildTripDetailRow('Vehicle:', tripData['vehicle']['number'] ?? 'N/A'),
              _buildTripDetailRow('Driver:', tripData['driver']['name'] ?? 'N/A'),
              _buildTripDetailRow('Driver Phone:', tripData['driver']['phone'] ?? 'N/A'),
              const Divider(height: 20),
              
              const Text(
                'Trip Details:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              _buildTripDetailRow('Distance:', '${tripData['trip']['distance']?.toStringAsFixed(1) ?? 'N/A'} km'),
              _buildTripDetailRow('Pickup Time:', _formatDateTime(tripData['trip']['pickupTime'])),
              _buildTripDetailRow('Est. Duration:', '${tripData['trip']['estimatedDuration'] ?? 'N/A'} minutes'),
              const Divider(height: 20),
              
              const Text(
                'Notifications Sent:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    tripData['notifications']['driver'] == true ? Icons.check_circle : Icons.cancel,
                    color: tripData['notifications']['driver'] == true ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text('Driver Notified'),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    tripData['notifications']['customer'] == true ? Icons.check_circle : Icons.cancel,
                    color: tripData['notifications']['customer'] == true ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text('Customer Notified'),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    tripData['notifications']['admin'] == true ? Icons.check_circle : Icons.cancel,
                    color: tripData['notifications']['admin'] == true ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text('Admin Notified'),
                ],
              ),
              
              if (tripData['nextSteps'] != null) ...[
                const Divider(height: 20),
                const Text(
                  'Next Steps:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                ...((tripData['nextSteps'] as List).map((step) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(child: Text(step.toString())),
                    ],
                  ),
                ))),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Clear form
              _customerNameController.clear();
              _customerEmailController.clear();
              _customerPhoneController.clear();
              setState(() {
                _selectedVehicleId = null;
                _startPoint = null;
                _endPoint = null;
                _startAddress = null;
                _endAddress = null;
                _selectedPickupTime = DateTime.now().add(const Duration(minutes: 30));
                _selectedDropTime = null;
              });
            },
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Create Another'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D47A1),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(context).pop();
              // Clear form for new trip
              _customerNameController.clear();
              _customerEmailController.clear();
              _customerPhoneController.clear();
              setState(() {
                _selectedVehicleId = null;
                _startPoint = null;
                _endPoint = null;
                _startAddress = null;
                _endAddress = null;
                _selectedPickupTime = DateTime.now().add(const Duration(minutes: 30));
                _selectedDropTime = null;
              });
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildTripDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null) return 'N/A';
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateTimeStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCustomerDetailsCard(),
          const SizedBox(height: 24.0),
          _buildVehicleDropdown(),
          const SizedBox(height: 24.0),
          _buildRouteSelectionButton(),
          const SizedBox(height: 24.0),
          _buildTimeSelectionCard(),
          const SizedBox(height: 24.0),
          if (_getSelectedVehicle() != null) _buildVehicleInfoCard(),
          const SizedBox(height: 24.0),
          if (_startPoint != null && _endPoint != null) _buildRouteInfoCard(),
          const SizedBox(height: 24.0),
          _buildAiSuggestionCard(),
          const SizedBox(height: 32.0),
          _buildActionButtons(),
        ],
      ),
    );
  }

  void _filterVehicles(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredVehicles = _vehicles;
      } else {
        _filteredVehicles = _vehicles.where((vehicle) {
          final searchLower = query.toLowerCase();
          return (vehicle['registration'] ?? '').toLowerCase().contains(searchLower) ||
                 (vehicle['model'] ?? '').toLowerCase().contains(searchLower) ||
                 (vehicle['type'] ?? '').toLowerCase().contains(searchLower) ||
                 (vehicle['driverName'] ?? '').toLowerCase().contains(searchLower) ||
                 (vehicle['vehicleId'] ?? '').toLowerCase().contains(searchLower);
        }).toList();
      }
    });
  }

  Widget _buildVehicleDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text(
                  'Select Vehicle',
                  style: TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF212121),
                  ),
                ),
                const SizedBox(width: 8),
                if (_isLoadingVehicles)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12.0),
        if (_vehicleLoadError != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _vehicleLoadError!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 14),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadVehicles,
                  color: Colors.red.shade700,
                  tooltip: 'Retry',
                ),
              ],
            ),
          )
        else if (_vehicles.isEmpty && !_isLoadingVehicles)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No vehicles with driver assignment found',
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'To start a new trip, you need vehicles that have drivers assigned to them.',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please assign drivers to existing vehicles in the Driver Management section.',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade600, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Go to Drivers → Select a driver → Assign Vehicle',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
        else
          _buildSearchableDropdown(),
      ],
    );
  }

  Widget _buildSearchableDropdown() {
    return InkWell(
      onTap: () => _showVehicleSelectionDialog(),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Icon(Icons.directions_car, color: Colors.grey.shade600, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: _selectedVehicleId != null
                  ? _buildSelectedVehicleDisplay()
                  : Text(
                      'Tap to select a vehicle',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 15,
                      ),
                    ),
            ),
            Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedVehicleDisplay() {
    final vehicle = _getSelectedVehicle();
    if (vehicle == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          vehicle['registration'] ?? 'N/A',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: Color(0xFF212121),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${vehicle['model']} • ${vehicle['type']} • ${vehicle['seatingCapacity']} seats',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Icon(Icons.person, size: 12, color: Colors.blue.shade600),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                vehicle['driverName'] ?? 'N/A',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showVehicleSelectionDialog() {
    _vehicleSearchController.clear();
    _filteredVehicles = _vehicles;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                  maxWidth: 500,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.directions_car, color: Color(0xFF0D47A1)),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Select Vehicle',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF212121),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _vehicleSearchController,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: 'Search by vehicle number, model, type, or driver name',
                              prefixIcon: const Icon(Icons.search, color: Color(0xFF0D47A1)),
                              suffixIcon: _vehicleSearchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 20),
                                      onPressed: () {
                                        setDialogState(() {
                                          _vehicleSearchController.clear();
                                          _filterVehicles('');
                                        });
                                      },
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            onChanged: (value) {
                              setDialogState(() {
                                _filterVehicles(value);
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _filteredVehicles.length != _vehicles.length
                                ? 'Showing ${_filteredVehicles.length} of ${_vehicles.length} vehicles'
                                : '${_vehicles.length} vehicles available',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _filteredVehicles.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      size: 64,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No vehicles found',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _vehicleSearchController.text.isNotEmpty
                                          ? 'Try adjusting your search'
                                          : 'No vehicles available',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: _filteredVehicles.length,
                              itemBuilder: (context, index) {
                                final vehicle = _filteredVehicles[index];
                                final isSelected = vehicle['id'] == _selectedVehicleId;
                                
                                return InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedVehicleId = vehicle['id'];
                                    });
                                    Navigator.pop(context);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.blue.shade50
                                          : Colors.transparent,
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.grey.shade200,
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        if (isSelected)
                                          Icon(
                                            Icons.check_circle,
                                            color: Colors.blue.shade700,
                                            size: 24,
                                          )
                                        else
                                          Icon(
                                            Icons.radio_button_unchecked,
                                            color: Colors.grey.shade400,
                                            size: 24,
                                          ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      vehicle['registration'] ?? 'N/A',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 15,
                                                        color: isSelected
                                                            ? Colors.blue.shade900
                                                            : const Color(0xFF212121),
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.green.shade100,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      vehicle['status'] ?? 'ACTIVE',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.green.shade800,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${vehicle['model']} • ${vehicle['type']} • ${vehicle['seatingCapacity']} seats',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.person,
                                                    size: 14,
                                                    color: Colors.blue.shade600,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      vehicle['driverName'] ?? 'No Driver',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.blue.shade700,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRouteSelectionButton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Trip Route',
          style: TextStyle(
            fontSize: 16.0,
            fontWeight: FontWeight.bold,
            color: Color(0xFF212121),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: _startPoint != null && _endPoint != null 
                  ? Colors.green.shade300 
                  : Colors.grey.shade300,
            ),
            borderRadius: BorderRadius.circular(8),
            color: _startPoint != null && _endPoint != null 
                ? Colors.green.shade50 
                : Colors.white,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openRouteSelection,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _startPoint != null && _endPoint != null
                              ? Icons.check_circle
                              : Icons.map,
                          color: _startPoint != null && _endPoint != null
                              ? Colors.green.shade700
                              : Colors.grey.shade600,
                          size: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _startPoint != null && _endPoint != null
                                    ? 'Route Selected'
                                    : 'Select Route on Map',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _startPoint != null && _endPoint != null
                                      ? Colors.green.shade900
                                      : Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _startPoint != null && _endPoint != null
                                    ? 'Tap to view or change route'
                                    : 'Search or pin locations on the map',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                    if (_startPoint != null && _endPoint != null) ...[
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Column(
                        children: [
                          _buildRouteLocationRow(
                            'Pickup Location',
                            Icons.trip_origin,
                            Colors.green,
                            _startAddress ?? 'Location selected',
                            _startPoint!,
                          ),
                          const SizedBox(height: 12),
                          _buildRouteLocationRow(
                            'Drop Location',
                            Icons.location_on,
                            Colors.red,
                            _endAddress ?? 'Location selected',
                            _endPoint!,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRouteLocationRow(
    String label,
    IconData icon,
    Color color,
    String address,
    LatLng point,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  address,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF212121),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteInfoCard() {
    final distance = _calculateRouteDistance();
    final estimatedTime = (distance / 40 * 60).round();
    
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Route Summary',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  Icons.straighten,
                  'Distance',
                  '${distance.toStringAsFixed(1)} km',
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryItem(
                  Icons.access_time,
                  'Est. Time',
                  '$estimatedTime min',
                  Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    IconData icon,
    String label,
    String value,
    MaterialColor color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, color: color.shade700, size: 24),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color.shade900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleInfoCard() {
    final vehicle = _getSelectedVehicle();
    if (vehicle == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.purple.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Selected Vehicle Details',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildVehicleDetailItem(
            Icons.directions_car,
            'Vehicle',
            '${vehicle['registration']} - ${vehicle['model']}',
            Colors.purple,
          ),
          const SizedBox(height: 12),
          _buildVehicleDetailItem(
            Icons.category,
            'Type',
            '${vehicle['type']} • ${vehicle['seatingCapacity']} seats',
            Colors.purple,
          ),
          const SizedBox(height: 12),
          _buildVehicleDetailItem(
            Icons.person,
            'Driver',
            vehicle['driverName'] ?? 'No Driver',
            Colors.green,
          ),
          if (vehicle['driverPhone'] != null && 
              vehicle['driverPhone'].toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildVehicleDetailItem(
              Icons.phone,
              'Driver Contact',
              vehicle['driverPhone'],
              Colors.blue,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVehicleDetailItem(
    IconData icon,
    String label,
    String value,
    MaterialColor color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: color.shade700, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF212121),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiSuggestionCard() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFE3F2FD),
            const Color(0xFFBBDEFB),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: const Color(0xFF0288D1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Color(0xFF01579B),
              size: 24,
            ),
          ),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Trip Suggestion',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF01579B),
                    fontSize: 16.0,
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  _startPoint != null && _endPoint != null && _selectedVehicleId != null && _customerNameController.text.isNotEmpty
                      ? 'All details filled! Ready to create trip for ${_customerNameController.text}.'
                      : _vehicles.isEmpty
                          ? 'Assign drivers to vehicles first, then fill in all trip details.'
                          : 'Fill in customer details, select vehicle and route to create trip.',
                  style: const TextStyle(
                    color: Color(0xFF01579B),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final bool canStartTrip = _selectedVehicleId != null && 
                               _startPoint != null && 
                               _endPoint != null &&
                               _customerNameController.text.trim().isNotEmpty &&
                               _customerPhoneController.text.trim().isNotEmpty;

    return ElevatedButton.icon(
      icon: const Icon(Icons.rocket_launch, size: 22),
      label: const Text(
        'Start Trip',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      onPressed: canStartTrip ? _startTrip : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 54),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        elevation: canStartTrip ? 2 : 0,
      ),
    );
  }
}