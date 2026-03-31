// lib/features/admin/customer_management/notification/roster_assignment_screen.dart
// COMPLETE FIXED VERSION

import 'package:flutter/material.dart';
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:abra_fleet/core/services/backend_connection_manager.dart';
import 'package:provider/provider.dart';

class RosterAssignmentScreen extends StatefulWidget {
  final VoidCallback onBack;
  final String? preSelectedRosterId;

  const RosterAssignmentScreen({
    super.key,
    required this.onBack,
    this.preSelectedRosterId,
  });

  @override
  State<RosterAssignmentScreen> createState() => _RosterAssignmentScreenState();
}

class _RosterAssignmentScreenState extends State<RosterAssignmentScreen> {
  bool _isLoading = false;
  bool _isAssigning = false;
  Map<String, dynamic>? _selectedRoster;
  List<Map<String, dynamic>> _pendingRosters = [];
  List<Map<String, dynamic>> _availableDrivers = [];
  List<Map<String, dynamic>> _availableVehicles = [];
  
  String? _selectedDriverId;
  String? _selectedVehicleId;
  String? _errorMessage;
  
  late final ApiService _apiService;
  
  @override
  void initState() {
    super.initState();
    final connectionManager = Provider.of<BackendConnectionManager>(context, listen: false);
    _apiService = connectionManager.apiService;
    _loadData();
  }

  // ============================================
  // FIXED _loadData() METHOD
  // ============================================
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      // STAGE 1: Fetch Pending Rosters
      try {
        debugPrint('📋 Fetching pending rosters...');
        final rostersResponse = await _apiService.get('/api/roster/admin/pending');
        debugPrint('Rosters Response: $rostersResponse');
        
        if (rostersResponse['success'] == true) {
          final rostersData = rostersResponse['data'];
          
          if (rostersData is List) {
            _pendingRosters = List<Map<String, dynamic>>.from(rostersData);
          } else if (rostersData is Map) {
            if (rostersData['rosters'] is List) {
              _pendingRosters = List<Map<String, dynamic>>.from(rostersData['rosters']);
            } else if (rostersData['data'] is List) {
              _pendingRosters = List<Map<String, dynamic>>.from(rostersData['data']);
            }
          }
          
          debugPrint('✅ Loaded ${_pendingRosters.length} pending rosters');
          
          if (widget.preSelectedRosterId != null && _pendingRosters.isNotEmpty) {
            _selectedRoster = _pendingRosters.firstWhere(
              (r) => r['_id'] == widget.preSelectedRosterId,
              orElse: () => _pendingRosters.first,
            );
            debugPrint('🎯 Pre-selected roster: ${_selectedRoster?['customerName']}');
          } else if (_pendingRosters.isNotEmpty) {
            _selectedRoster = _pendingRosters.first;
            debugPrint('📌 Auto-selected first roster');
          }
        } else {
          throw Exception(rostersResponse['message'] ?? 'Failed to load rosters');
        }
      } catch (e) {
        debugPrint('❌ Error loading rosters: $e');
        _errorMessage = 'Failed to load rosters: ${e.toString()}';
      }
      
      // STAGE 2: Fetch Available Drivers
      try {
        debugPrint('👤 Fetching available drivers...');
        final driversResponse = await _apiService.get('/api/admin/drivers?status=active');
        debugPrint('📦 RAW Drivers Response: $driversResponse');
        debugPrint('📦 Response Type: ${driversResponse.runtimeType}');
        
        if (driversResponse['success'] == true) {
          final driversData = driversResponse['data'];
          debugPrint('📦 Drivers Data: $driversData');
          debugPrint('📦 Drivers Data Type: ${driversData.runtimeType}');
          
          // Handle different response structures
          List<dynamic> driversList = [];
          
          if (driversData is List) {
            driversList = driversData;
            debugPrint('✅ Case 1: Data is direct list');
          } else if (driversData is Map) {
            if (driversData['drivers'] is List) {
              driversList = driversData['drivers'];
              debugPrint('✅ Case 2: Data has "drivers" key');
            } else if (driversData['data'] is List) {
              driversList = driversData['data'];
              debugPrint('✅ Case 3: Data has nested "data" key');
            } else {
              debugPrint('⚠️ Case 4: Map structure - keys: ${driversData.keys}');
              // Try to find any list in the map
              for (var key in driversData.keys) {
                if (driversData[key] is List) {
                  driversList = driversData[key];
                  debugPrint('✅ Found list under key: $key');
                  break;
                }
              }
            }
          }
          
          _availableDrivers = List<Map<String, dynamic>>.from(driversList);
          
          debugPrint('✅ Loaded ${_availableDrivers.length} available drivers');
          
          // Debug each driver
          for (var i = 0; i < _availableDrivers.length && i < 3; i++) {
            debugPrint('   Driver $i: ${_availableDrivers[i]}');
          }
          
          // CRITICAL FIX: Validate selected driver exists in new list
          if (_selectedDriverId != null) {
            final driverExists = _availableDrivers.any((d) => d['_id']?.toString() == _selectedDriverId);
            if (!driverExists) {
              debugPrint('⚠️ Previously selected driver not found, resetting selection');
              _selectedDriverId = null;
            }
          }
        } else {
          throw Exception(driversResponse['message'] ?? 'Failed to load drivers');
        }
      } catch (e, stackTrace) {
        debugPrint('❌ Error loading drivers: $e');
        debugPrint('Stack trace: $stackTrace');
        if (_errorMessage == null) {
          _errorMessage = 'Failed to load drivers: ${e.toString()}';
        }
      }
      
      // STAGE 3: Fetch Available Vehicles (FIXED)
      try {
        debugPrint('🚗 Fetching available vehicles...');
        final vehiclesResponse = await _apiService.get('/api/admin/vehicles');
        debugPrint('📦 RAW Vehicles Response: $vehiclesResponse');
        debugPrint('📦 Response Type: ${vehiclesResponse.runtimeType}');
        
        if (vehiclesResponse['success'] == true) {
          final vehiclesData = vehiclesResponse['data'];
          debugPrint('📦 Vehicles Data: $vehiclesData');
          debugPrint('📦 Vehicles Data Type: ${vehiclesData.runtimeType}');
          
          // Handle different response structures
          List<dynamic> vehiclesList = [];
          
          if (vehiclesData is List) {
            vehiclesList = vehiclesData;
            debugPrint('✅ Case 1: Data is direct list');
          } else if (vehiclesData is Map) {
            if (vehiclesData['vehicles'] is List) {
              vehiclesList = vehiclesData['vehicles'];
              debugPrint('✅ Case 2: Data has "vehicles" key');
            } else if (vehiclesData['data'] is List) {
              vehiclesList = vehiclesData['data'];
              debugPrint('✅ Case 3: Data has nested "data" key');
            } else {
              debugPrint('⚠️ Case 4: Map structure - keys: ${vehiclesData.keys}');
              // Try to find any list in the map
              for (var key in vehiclesData.keys) {
                if (vehiclesData[key] is List) {
                  vehiclesList = vehiclesData[key];
                  debugPrint('✅ Found list under key: $key');
                  break;
                }
              }
            }
          }
          
          // Filter for ACTIVE/AVAILABLE vehicles
          _availableVehicles = List<Map<String, dynamic>>.from(
            vehiclesList.where((vehicle) {
              final status = vehicle['status']?.toString().toUpperCase() ?? '';
              return status == 'ACTIVE' || status == 'AVAILABLE';
            })
          );
          
          debugPrint('✅ Loaded ${_availableVehicles.length} available vehicles (filtered from ${vehiclesList.length} total)');
          
          // Debug each vehicle
          for (var i = 0; i < _availableVehicles.length && i < 3; i++) {
            debugPrint('   Vehicle $i: ${_availableVehicles[i]}');
          }
          
          // CRITICAL FIX: Validate selected vehicle exists in new list
          if (_selectedVehicleId != null) {
            final vehicleExists = _availableVehicles.any((v) => v['_id']?.toString() == _selectedVehicleId);
            if (!vehicleExists) {
              debugPrint('⚠️ Previously selected vehicle not found, resetting selection');
              _selectedVehicleId = null;
            }
          }
        } else {
          throw Exception(vehiclesResponse['message'] ?? 'Failed to load vehicles');
        }
      } catch (e, stackTrace) {
        debugPrint('❌ Error loading vehicles: $e');
        debugPrint('Stack trace: $stackTrace');
        if (_errorMessage == null) {
          _errorMessage = 'Failed to load vehicles: ${e.toString()}';
        }
      }
      
    } catch (e) {
      debugPrint('❌ Critical error loading data: $e');
      _errorMessage = 'Critical error: ${e.toString()}';
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        
        if (_errorMessage != null) {
          _showSnackBar(_errorMessage!, Colors.red);
        }
      }
    }
  }

  // ============================================
  // FIXED DRIVER DROPDOWN
  // ============================================
  Widget _buildDriverSelector() {
    // CRITICAL: Use 'driverId' instead of '_id' for drivers
    final validDriverIds = _availableDrivers
        .map((d) => d['driverId']?.toString())  // ← Changed from _id to driverId
        .where((id) => id != null)
        .toSet();
    
    final effectiveDriverValue = (_selectedDriverId != null && validDriverIds.contains(_selectedDriverId))
        ? _selectedDriverId
        : null;
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Assign Driver',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _availableDrivers.isEmpty ? Colors.red[50] : Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_availableDrivers.length} available',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _availableDrivers.isEmpty ? Colors.red[900] : Colors.green[900],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            if (_availableDrivers.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No drivers available for assignment',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[50],
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: effectiveDriverValue,
                    isExpanded: true,
                    hint: const Text('Select a driver'),
                    items: _availableDrivers.where((driver) => driver['driverId'] != null).map((driver) {
                      final driverId = driver['driverId'].toString();  // ← Changed from _id
                      return DropdownMenuItem<String>(
                        value: driverId,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.blue[100],
                              child: Text(
                                ((driver['name']?.toString() ?? 'D')[0]).toUpperCase(),
                                style: TextStyle(
                                  color: Colors.blue[900],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    driver['name']?.toString() ?? 'Unknown',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (driver['phone'] != null)
                                    Text(
                                      driver['phone'].toString(),
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
                      );
                    }).toList(),
                    onChanged: _isAssigning ? null : (value) {
                      setState(() => _selectedDriverId = value);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // FIXED VEHICLE DROPDOWN
  // ============================================
  Widget _buildVehicleSelector() {
    // CRITICAL: Compute valid value before building dropdown
    final validVehicleIds = _availableVehicles
        .map((v) => v['_id']?.toString())
        .where((id) => id != null)
        .toSet();
    
    final effectiveVehicleValue = (_selectedVehicleId != null && validVehicleIds.contains(_selectedVehicleId))
        ? _selectedVehicleId
        : null;
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_car, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Assign Vehicle',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _availableVehicles.isEmpty ? Colors.red[50] : Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_availableVehicles.length} available',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _availableVehicles.isEmpty ? Colors.red[900] : Colors.green[900],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            if (_availableVehicles.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No vehicles available for assignment',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[50],
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: effectiveVehicleValue,
                    isExpanded: true,
                    hint: const Text('Select a vehicle'),
                    items: _availableVehicles.where((vehicle) => vehicle['_id'] != null).map((vehicle) {
                      final vehicleId = vehicle['_id'].toString();
                      return DropdownMenuItem<String>(
                        value: vehicleId,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.local_shipping,
                                color: Colors.blue[700],
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    vehicle['registrationNumber']?.toString() ?? 'Unknown',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (vehicle['make'] != null || vehicle['model'] != null)
                                    Text(
                                      '${vehicle['make']?.toString() ?? ''} ${vehicle['model']?.toString() ?? ''}'.trim(),
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
                      );
                    }).toList(),
                    onChanged: _isAssigning ? null : (value) {
                      setState(() => _selectedVehicleId = value);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // REST OF THE METHODS (unchanged but included for completeness)
  // ============================================
  
  Future<void> _assignRoster() async {
  debugPrint('🔍 Starting validation...');
  
  if (_selectedRoster == null) {
    _showSnackBar('❌ Please select a roster', Colors.orange);
    return;
  }
  
  if (_selectedDriverId == null) {
    _showSnackBar('❌ Please select a driver', Colors.orange);
    return;
  }
  
  if (_selectedVehicleId == null) {
    _showSnackBar('❌ Please select a vehicle', Colors.orange);
    return;
  }
  
  debugPrint('✅ Validation passed');
  
  final confirmed = await _showConfirmationDialog();
  if (!confirmed) {
    debugPrint('❌ Assignment cancelled by user');
    return;
  }
  
  setState(() => _isAssigning = true);
  
  try {
    debugPrint('📤 Sending assignment request...');
    debugPrint('   Roster ID: ${_selectedRoster!['_id']}');
    debugPrint('   Driver ID: $_selectedDriverId');
    debugPrint('   Vehicle ID: $_selectedVehicleId');
    
    final response = await _apiService.post(
      '/api/roster/admin/assign',
      body: {
        'rosterId': _selectedRoster!['_id'],
        'driverId': _selectedDriverId,
        'vehicleId': _selectedVehicleId,
      },
    );
    
    debugPrint('📥 Assignment Response: $response');
    
    // ✅ FIX: Check mounted IMMEDIATELY after async operation
    if (!mounted) {
      debugPrint('⚠️ Widget disposed during assignment');
      return;
    }
    
    if (response['success'] == true) {
      debugPrint('✅ Assignment successful!');
      
      // ✅ Show success message
      _showSnackBar(
        '✓ Roster assigned successfully to ${_getDriverName()}!',
        Colors.green,
      );
      
      // ✅ Reset state
      setState(() {
        _selectedDriverId = null;
        _selectedVehicleId = null;
        _selectedRoster = null;
        _isAssigning = false; // Reset here before reload
      });
      
      // ✅ Wait a bit before reloading to let user see the success message
      await Future.delayed(const Duration(milliseconds: 500));
      
      // ✅ Check mounted again before reload
      if (!mounted) return;
      
      debugPrint('🔄 Reloading data...');
      await _loadData();
      
      if (_pendingRosters.isEmpty) {
        debugPrint('🎉 All rosters assigned!');
      }
    } else {
      final errorMsg = response['message'] ?? 'Assignment failed';
      debugPrint('❌ Assignment failed: $errorMsg');
      throw Exception(errorMsg);
    }
    
  } catch (e) {
    debugPrint('❌ Error during assignment: $e');
    
    // ✅ Check mounted before showing error
    if (!mounted) return;
    
    _showSnackBar('Error: ${e.toString()}', Colors.red);
    
    // ✅ Reset loading state
    if (mounted) {
      setState(() => _isAssigning = false);
    }
  }
}

  Future<bool> _showConfirmationDialog() async {
    final driver = _availableDrivers.firstWhere(
      (d) => d['_id'] == _selectedDriverId,
      orElse: () => {'name': 'Unknown Driver'},
    );
    final vehicle = _availableVehicles.firstWhere(
      (v) => v['_id'] == _selectedVehicleId,
      orElse: () => {'registrationNumber': 'Unknown Vehicle'},
    );
    
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.assignment_turned_in, color: Colors.orange),
            SizedBox(width: 8),
            Text('Confirm Assignment'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'You are about to assign:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            
            _buildDialogRow(
              icon: Icons.business,
              label: 'Customer',
              value: _selectedRoster?['customerName'] ?? 'Unknown',
            ),
            _buildDialogRow(
              icon: Icons.location_city,
              label: 'Office',
              value: _selectedRoster?['officeLocation'] ?? 'Unknown',
            ),
            const Divider(height: 24),
            
            _buildDialogRow(
              icon: Icons.person,
              label: 'Driver',
              value: driver['name'] ?? 'Unknown',
              highlight: true,
            ),
            
            _buildDialogRow(
              icon: Icons.directions_car,
              label: 'Vehicle',
              value: vehicle['registrationNumber'] ?? 'Unknown',
              highlight: true,
            ),
            
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Assignment'),
          ),
        ],
      ),
    ) ?? false;
  }

  Widget _buildDialogRow({
    required IconData icon,
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
                fontSize: 13,
                color: highlight ? Colors.orange[900] : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getDriverName() {
    final driver = _availableDrivers.firstWhere(
      (d) => d['_id'] == _selectedDriverId,
      orElse: () => {'name': 'Driver'},
    );
    return driver['name'] ?? 'Driver';
  }

  // Replace your _showSnackBar method with this fixed version:

void _showSnackBar(String message, Color color) {
  // ✅ CRITICAL FIX: Check if widget is still mounted before showing SnackBar
  if (!mounted) {
    debugPrint('⚠️ Widget not mounted, skipping SnackBar: $message');
    return;
  }
  
  // ✅ Use try-catch to handle any potential context issues
  try {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == Colors.green ? Icons.check_circle : 
              color == Colors.red ? Icons.error : Icons.info,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: color == Colors.green ? 2 : 3),
      ),
    );
  } catch (e) {
    // If SnackBar fails, just log it - don't crash the app
    debugPrint('⚠️ Failed to show SnackBar: $e');
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assign Roster'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isAssigning ? null : widget.onBack,
        ),
        actions: [
          if (_pendingRosters.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.pending_actions, size: 16, color: Colors.orange[900]),
                  const SizedBox(width: 4),
                  Text(
                    '${_pendingRosters.length} pending',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[900],
                    ),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: (_isLoading || _isAssigning) ? null : _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading data...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_pendingRosters.isEmpty) {
      return _buildEmptyState();
    }
    
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRosterSelector(),
            const SizedBox(height: 16),
            
            if (_selectedRoster != null) ...[
              _buildRosterDetails(),
              const SizedBox(height: 16),
              
              _buildDriverSelector(),
              const SizedBox(height: 16),
              
              _buildVehicleSelector(),
              const SizedBox(height: 24),
              
              _buildAssignButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRosterSelector() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.assignment, color: Colors.blue, size: 20),
                SizedBox(width: 8),
                Text(
                  'Select Roster',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[50],
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Map<String, dynamic>>(
                  value: _selectedRoster,
                  isExpanded: true,
                  hint: const Text('Choose a roster request'),
                  items: _pendingRosters.map((roster) {
                    return DropdownMenuItem<Map<String, dynamic>>(
                      value: roster,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(Icons.business, size: 16, color: Colors.blue[700]),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  roster['customerName'] ?? 'Unknown Customer',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  roster['officeLocation'] ?? 'No location',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: _isAssigning ? null : (value) {
                    setState(() {
                      _selectedRoster = value;
                      _selectedDriverId = null;
                      _selectedVehicleId = null;
                    });
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRosterDetails() {
    final roster = _selectedRoster!;
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Roster Details',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 20),
            
            _buildDetailRow('Customer', roster['customerName']?.toString() ?? 'N/A'),
            _buildDetailRow('Office', roster['officeLocation']?.toString() ?? 'N/A'),
            _buildDetailRow('Type', _getRosterTypeDisplay(roster['rosterType']?.toString())),
            
            if (roster['weeklyOffDays'] != null && (roster['weeklyOffDays'] as List).isNotEmpty)
              _buildDetailRow(
                'Weekly Off',
                (roster['weeklyOffDays'] as List).join(', '),
              ),
            
            _buildDetailRow(
              'Time',
              '${roster['startTime'] ?? 'N/A'} - ${roster['endTime'] ?? 'N/A'}',
            ),
            _buildDetailRow(
              'Period',
              '${_formatDate(roster['startDate'])} to ${_formatDate(roster['endDate'])}',
            ),
            
            if (roster['locations']?['pickup']?['address'] != null) ...[
              const Divider(height: 20),
              _buildDetailRow(
                'Pickup',
                roster['locations']['pickup']['address']?.toString() ?? 'N/A',
                icon: Icons.location_on,
                iconColor: Colors.green,
              ),
            ],
            
            if (roster['locations']?['drop']?['address'] != null) ...[
              _buildDetailRow(
                'Drop',
                roster['locations']['drop']['address']?.toString() ?? 'N/A',
                icon: Icons.location_off,
                iconColor: Colors.red,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAssignButton() {
    final canAssign = _selectedDriverId != null && 
                      _selectedVehicleId != null &&
                      !_isAssigning &&
                      _availableDrivers.isNotEmpty &&
                      _availableVehicles.isNotEmpty;
    
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        icon: _isAssigning 
          ? const SizedBox(
              width: 20, 
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white, 
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.assignment_turned_in, size: 22),
        label: Text(
          _isAssigning ? 'Assigning Roster...' : 'Assign Roster',
          style: const TextStyle(
            fontSize: 16, 
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: canAssign ? Colors.orange : Colors.grey[400],
          foregroundColor: Colors.white,
          elevation: canAssign ? 4 : 0,
          shadowColor: Colors.orange.withOpacity(0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: canAssign ? _assignRoster : null,
      ),
    );
  }

  Widget _buildDetailRow(
    String label, 
    String value, {
    IconData? icon, 
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: iconColor ?? Colors.grey[600]),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.green[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_outline, 
                size: 80, 
                color: Colors.green[400],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Pending Rosters',
              style: TextStyle(
                fontSize: 24, 
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'All roster requests have been assigned.\nGreat job!',
              style: TextStyle(
                fontSize: 16, 
                color: Colors.grey[600],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back to Dashboard'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: widget.onBack,
            ),
          ],
        ),
      ),
    );
  }

  String _getRosterTypeDisplay(String? type) {
    switch (type?.toLowerCase()) {
      case 'login':
        return 'Login Only';
      case 'logout':
        return 'Logout Only';
      case 'both':
        return 'Login & Logout';
      default:
        return type ?? 'N/A';
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      final dt = DateTime.parse(date.toString());
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (e) {
      return date.toString();
    }
  }
}