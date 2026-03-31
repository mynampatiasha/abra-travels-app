// lib/features/admin/customer_management/notification/edit_roster_assignment_screen.dart

import 'package:flutter/material.dart';
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:abra_fleet/core/services/backend_connection_manager.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class EditRosterAssignmentScreen extends StatefulWidget {
  final Map<String, dynamic> roster;
  final VoidCallback onBack;

  const EditRosterAssignmentScreen({
    super.key,
    required this.roster,
    required this.onBack,
  });

  @override
  State<EditRosterAssignmentScreen> createState() => _EditRosterAssignmentScreenState();
}

class _EditRosterAssignmentScreenState extends State<EditRosterAssignmentScreen> {
  bool _isLoading = false;
  bool _isUpdating = false;
  List<Map<String, dynamic>> _availableDrivers = [];
  List<Map<String, dynamic>> _availableVehicles = [];
  
  String? _selectedDriverId;
  String? _selectedVehicleId;
  String? _errorMessage;
  
  // Store original assignments for comparison
  String? _originalDriverId;
  String? _originalVehicleId;
  
  late final ApiService _apiService;
  
  @override
  void initState() {
    super.initState();
    final connectionManager = Provider.of<BackendConnectionManager>(context, listen: false);
    _apiService = connectionManager.apiService;
    
    // We load resources first, then we will match the current assignments to them
    // This ensures we have the list data to compare against
    _loadAvailableResources();
  }

  void _extractCurrentAssignments() {
    debugPrint('🔍 Extracting current assignments...');
    debugPrint('📦 Full roster data: ${widget.roster}');
    
    // --- DRIVER MATCHING LOGIC ---
    // We need to find the driver in _availableDrivers that matches the roster's driver.
    // The roster might have a Mongo ID (68e...) while the list uses "DRV-..." or vice versa.
    
    dynamic assignedDriver = widget.roster['assignedDriver'];
    String? rosterDriverKey;
    
    if (assignedDriver is Map) {
      // Try to get ANY identifier available in the roster object
      rosterDriverKey = assignedDriver['_id']?.toString() ?? assignedDriver['driverId']?.toString();
    } else if (assignedDriver is String) {
      rosterDriverKey = assignedDriver;
    }
    
    // Fallback to flat field
    rosterDriverKey ??= widget.roster['assignedDriverId']?.toString();

    // Now look for this key in our downloaded list
    if (rosterDriverKey != null && _availableDrivers.isNotEmpty) {
      try {
        final matchingDriver = _availableDrivers.firstWhere((d) {
          // Check against BOTH the _id and driverId of the driver in the list
          final mongoId = d['_id']?.toString();
          final driverCode = d['driverId']?.toString();
          return mongoId == rosterDriverKey || driverCode == rosterDriverKey;
        });
        
        // If found, use the ID format that _extractId returns (so the dropdown works)
        _originalDriverId = _extractId(matchingDriver);
        debugPrint('✅ Found matching driver in list: $_originalDriverId');
      } catch (e) {
        debugPrint('⚠️ Original driver ($rosterDriverKey) not found in available list');
        // If not found in list, we can't pre-select it in the dropdown cleanly,
        // but we can try to set it directly if formats match
        _originalDriverId = _extractIdFromValue(rosterDriverKey);
      }
    } else {
      debugPrint('ℹ️ No driver currently assigned');
    }
    
    // --- VEHICLE MATCHING LOGIC ---
    // Vehicles usually use MongoDB IDs consistently, but we apply same safety logic
    
    dynamic assignedVehicle = widget.roster['assignedVehicle'];
    String? rosterVehicleKey;
    
    if (assignedVehicle is Map) {
      rosterVehicleKey = assignedVehicle['_id']?.toString() ?? assignedVehicle['vehicleId']?.toString();
    } else if (assignedVehicle is String) {
      rosterVehicleKey = assignedVehicle;
    }
    
    rosterVehicleKey ??= widget.roster['assignedVehicleId']?.toString();

    if (rosterVehicleKey != null && _availableVehicles.isNotEmpty) {
      try {
        final matchingVehicle = _availableVehicles.firstWhere((v) {
          final mongoId = v['_id']?.toString();
          final vehicleCode = v['vehicleId']?.toString();
          return mongoId == rosterVehicleKey || vehicleCode == rosterVehicleKey;
        });
        
        _originalVehicleId = _extractId(matchingVehicle);
        debugPrint('✅ Found matching vehicle in list: $_originalVehicleId');
      } catch (e) {
         debugPrint('⚠️ Original vehicle ($rosterVehicleKey) not found in available list');
         _originalVehicleId = _extractIdFromValue(rosterVehicleKey);
      }
    }
    
    // Set initial selections
    _selectedDriverId = _originalDriverId;
    _selectedVehicleId = _originalVehicleId;
    
    debugPrint('✅ Final Extracted Driver ID: $_originalDriverId');
    debugPrint('✅ Final Extracted Vehicle ID: $_originalVehicleId');
  }

  // ✅ IMPROVED: Extract ID from various value types
  String? _extractIdFromValue(dynamic value) {
    if (value == null) return null;
    
    // If it's a string, just return it (REMOVED strict length check to allow "DRV-123")
    if (value is String && value.isNotEmpty) {
      return value;
    }
    
    // If it's a Map with $oid
    if (value is Map && value['\$oid'] != null) {
      return value['\$oid'].toString();
    }
    
    // If it's a Map with _id
    if (value is Map && value['_id'] != null) {
      return _extractIdFromValue(value['_id']);
    }
    
    return null;
  }

  // ✅ FIXED: Robust ID extraction that prioritizes the correct ID field
  String? _extractId(Map<String, dynamic> item) {
    // 1. Check for 'driverId' (e.g. DRV-123) - This is what your list uses
    if (item['driverId'] != null) {
      final val = item['driverId'].toString();
      if (val.isNotEmpty) return val;
    }

    // 2. Check for MongoDB '_id'
    final mongoId = item['_id'];
    if (mongoId != null) {
      if (mongoId is String && mongoId.length == 24) return mongoId;
      if (mongoId is Map && mongoId['\$oid'] != null) return mongoId['\$oid'].toString();
    }
    
    // 3. Check for 'vehicleId'
    final vehicleId = item['vehicleId'];
    if (vehicleId != null) {
      if (vehicleId is String && vehicleId.isNotEmpty) return vehicleId;
      if (vehicleId is Map && vehicleId['\$oid'] != null) return vehicleId['\$oid'].toString();
    }
    
    // 4. Plain 'id'
    final id = item['id'];
    if (id != null) return id.toString();
    
    // Debug info if nothing found
    // debugPrint('⚠️ Could not extract ID from: ${item.keys.toList()}');
    return null;
  }

  Future<void> _loadAvailableResources() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    debugPrint('🔄 Loading available drivers and vehicles...');
    
    try {
      // Fetch drivers
      try {
        debugPrint('📞 Fetching drivers from API...');
        final driversResponse = await _apiService.get('/api/admin/drivers?status=active');
        // debugPrint('📥 Drivers response: $driversResponse');
        
        if (driversResponse['success'] == true) {
          final driversData = driversResponse['data'];
          List<dynamic> driversList = [];
          
          if (driversData is List) {
            driversList = driversData;
          } else if (driversData is Map) {
            if (driversData['drivers'] is List) {
              driversList = driversData['drivers'];
            } else if (driversData['data'] is List) {
              driversList = driversData['data'];
            }
          }
          
          _availableDrivers = List<Map<String, dynamic>>.from(driversList);
          debugPrint('✅ Loaded ${_availableDrivers.length} drivers');
        } else {
          throw Exception('Failed to load drivers: ${driversResponse['message']}');
        }
      } catch (e) {
        debugPrint('❌ Error loading drivers: $e');
        _errorMessage = 'Failed to load drivers: $e';
      }
      
      // Fetch vehicles
      try {
        debugPrint('📞 Fetching vehicles from API...');
        final vehiclesResponse = await _apiService.get('/api/admin/vehicles');
        
        if (vehiclesResponse['success'] == true) {
          final vehiclesData = vehiclesResponse['data'];
          List<dynamic> vehiclesList = [];
          
          if (vehiclesData is List) {
            vehiclesList = vehiclesData;
          } else if (vehiclesData is Map) {
            if (vehiclesData['vehicles'] is List) {
              vehiclesList = vehiclesData['vehicles'];
            } else if (vehiclesData['data'] is List) {
              vehiclesList = vehiclesData['data'];
            }
          }
          
          // Filter for active vehicles
          _availableVehicles = List<Map<String, dynamic>>.from(
            vehiclesList.where((vehicle) {
              final status = vehicle['status']?.toString().toUpperCase() ?? '';
              return status == 'ACTIVE' || status == 'AVAILABLE' || status.isEmpty;
            })
          );
          
          debugPrint('✅ Loaded ${_availableVehicles.length} vehicles');
        } else {
          throw Exception('Failed to load vehicles: ${vehiclesResponse['message']}');
        }
      } catch (e) {
        debugPrint('❌ Error loading vehicles: $e');
        if (_errorMessage == null) {
          _errorMessage = 'Failed to load vehicles: $e';
        } else {
          _errorMessage = '$_errorMessage\nFailed to load vehicles: $e';
        }
      }

      // ✅ Call this AFTER loading to ensure we can match IDs
      _extractCurrentAssignments();
      
    } catch (e) {
      debugPrint('❌ Critical error loading resources: $e');
      _errorMessage = 'Failed to load data: $e';
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        
        if (_errorMessage != null) {
          _showSnackBar(_errorMessage!, Colors.red);
        }
        
        // Additional validation after loading
        _validateSelections();
      }
    }
  }

  // ✅ NEW: Validate that current selections exist in loaded lists
  void _validateSelections() {
    if (_selectedDriverId != null) {
      final driverExists = _availableDrivers.any((d) => _extractId(d) == _selectedDriverId);
      if (!driverExists) {
        debugPrint('⚠️ Selected driver $_selectedDriverId not found in available drivers list');
      }
    }
    
    if (_selectedVehicleId != null) {
      final vehicleExists = _availableVehicles.any((v) => _extractId(v) == _selectedVehicleId);
      if (!vehicleExists) {
        debugPrint('⚠️ Selected vehicle $_selectedVehicleId not found in available vehicles list');
      }
    }
  }

  Future<void> _updateAssignment() async {
    if (_selectedDriverId == null || _selectedVehicleId == null) {
      _showSnackBar('Please select both driver and vehicle', Colors.orange);
      return;
    }
    
    // Check if anything changed
    if (_selectedDriverId == _originalDriverId && _selectedVehicleId == _originalVehicleId) {
      _showSnackBar('No changes detected', Colors.orange);
      return;
    }
    
    final confirmed = await _showConfirmationDialog();
    if (!confirmed) return;
    
    setState(() => _isUpdating = true);
    
    try {
      // Extract roster ID - handle both formats
      String? rosterId;
      
      if (widget.roster['_id'] != null) {
        final rosterIdValue = widget.roster['_id'];
        if (rosterIdValue is String) {
          rosterId = rosterIdValue;
        } else if (rosterIdValue is Map && rosterIdValue['\$oid'] != null) {
          rosterId = rosterIdValue['\$oid'].toString();
        }
      }
      
      if (rosterId == null || rosterId.isEmpty) {
        rosterId = widget.roster['id']?.toString();
      }
      
      if (rosterId == null || rosterId.isEmpty) {
        throw Exception('Invalid roster ID - cannot extract from roster data');
      }
      
      debugPrint('═══════════════════════════════════════════');
      debugPrint('📤 PREPARING UPDATE REQUEST');
      debugPrint('═══════════════════════════════════════════');
      debugPrint('Roster ID: $rosterId');
      debugPrint('Selected Driver ID: $_selectedDriverId');
      debugPrint('Selected Vehicle ID: $_selectedVehicleId');
      
      // ✅ FIX: Removed strict length check for IDs.
      // We trust the value selected from the dropdown/list.
      
      debugPrint('═══════════════════════════════════════════');
      
      final requestBody = {
        'driverId': _selectedDriverId,
        'vehicleId': _selectedVehicleId,
      };
      
      debugPrint('📦 Request Body: $requestBody');
      
      // Make the API call
      final endpoint = '/api/roster/admin/edit-assignment/$rosterId';
      debugPrint('🌐 PUT: $endpoint');
      
      final response = await _apiService.put(
        endpoint,
        body: requestBody,
      );
      
      debugPrint('📥 Update Response: $response');
      
      // ✅ FIX: Check if mounted before proceeding
      if (!mounted) return;
      
      if (response['success'] == true) {
        _showSnackBar('✓ Assignment updated successfully!', Colors.green);
        
        // Wait a bit before going back
        await Future.delayed(const Duration(milliseconds: 800));
        
        if (mounted) {
          widget.onBack();
        }
      } else {
        throw Exception(response['message'] ?? 'Update failed - no error message');
      }
      
    } catch (e) {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('❌ ERROR UPDATING ASSIGNMENT');
      debugPrint('═══════════════════════════════════════════');
      debugPrint('Error: $e');
      
      // ✅ FIX: Check if mounted before showing error
      if (mounted) {
        String errorMessage = e.toString();
        if (errorMessage.contains('404')) {
          errorMessage = 'Roster not found (404). The roster may have been deleted.';
        } else if (errorMessage.contains('Network error')) {
          errorMessage = 'Network error. Please check your connection.';
        }
        _showSnackBar('Error: $errorMessage', Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<bool> _showConfirmationDialog() async {
    final oldDriver = _availableDrivers.firstWhere(
      (d) => _extractId(d) == _originalDriverId,
      orElse: () => {'name': widget.roster['assignedDriverName'] ?? 'Previous Driver'},
    );
    final newDriver = _availableDrivers.firstWhere(
      (d) => _extractId(d) == _selectedDriverId,
      orElse: () => {'name': 'Unknown Driver'},
    );
    final oldVehicle = _availableVehicles.firstWhere(
      (v) => _extractId(v) == _originalVehicleId,
      orElse: () => {'registrationNumber': widget.roster['assignedVehicleReg'] ?? 'Previous Vehicle'},
    );
    final newVehicle = _availableVehicles.firstWhere(
      (v) => _extractId(v) == _selectedVehicleId,
      orElse: () => {'registrationNumber': 'Unknown Vehicle'},
    );
    
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit, color: Colors.blue),
            SizedBox(width: 8),
            Text('Confirm Changes'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You are about to update the assignment:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              
              _buildDialogRow(
                icon: Icons.business,
                label: 'Customer',
                value: widget.roster['customerName'] ?? 'Unknown',
              ),
              
              const Divider(height: 24),
              
              // Driver Change
              if (_selectedDriverId != _originalDriverId) ...[
                const Text(
                  'Driver Change:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 8),
                _buildChangeRow(
                  icon: Icons.person,
                  label: 'From',
                  value: oldDriver['name'] ?? 'N/A',
                  color: Colors.red,
                ),
                _buildChangeRow(
                  icon: Icons.person,
                  label: 'To',
                  value: newDriver['name'] ?? 'N/A',
                  color: Colors.green,
                ),
                const SizedBox(height: 12),
              ],
              
              // Vehicle Change
              if (_selectedVehicleId != _originalVehicleId) ...[
                const Text(
                  'Vehicle Change:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 8),
                _buildChangeRow(
                  icon: Icons.directions_car,
                  label: 'From',
                  value: oldVehicle['registrationNumber'] ?? 'N/A',
                  color: Colors.red,
                ),
                _buildChangeRow(
                  icon: Icons.directions_car,
                  label: 'To',
                  value: newVehicle['registrationNumber'] ?? 'N/A',
                  color: Colors.green,
                ),
              ],
              
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'The customer and assigned personnel will be notified',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Update Assignment'),
          ),
        ],
      ),
    ) ?? false;
  }

  Widget _buildChangeRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogRow({
    required IconData icon,
    required String label,
    required String value,
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
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    
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
          duration: Duration(seconds: color == Colors.green ? 2 : 4),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ Failed to show SnackBar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Assignment'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isUpdating ? null : widget.onBack,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: (_isLoading || _isUpdating) ? null : _loadAvailableResources,
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
          : RefreshIndicator(
              onRefresh: _loadAvailableResources,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRosterInfo(),
                    const SizedBox(height: 16),
                    
                    _buildCurrentAssignment(),
                    const SizedBox(height: 24),
                    
                    const Text(
                      'Update Assignment',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    _buildDriverSelector(),
                    const SizedBox(height: 16),
                    
                    _buildVehicleSelector(),
                    const SizedBox(height: 24),
                    
                    _buildUpdateButton(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildRosterInfo() {
    final roster = widget.roster;
    
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
                const Icon(Icons.assignment, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Roster Information',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 20),
            
            _buildInfoRow('Customer', roster['customerName']?.toString() ?? 'N/A'),
            _buildInfoRow('Office', roster['officeLocation']?.toString() ?? 'N/A'),
            _buildInfoRow('Type', _formatRosterType(roster['rosterType']?.toString())),
            _buildInfoRow(
              'Period',
              '${_formatDate(roster['startDate'] ?? roster['fromDate'])} to ${_formatDate(roster['endDate'] ?? roster['toDate'])}',
            ),
            _buildInfoRow(
              'Time',
              '${roster['startTime'] ?? roster['fromTime'] ?? 'N/A'} - ${roster['endTime'] ?? roster['toTime'] ?? 'N/A'}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentAssignment() {
    return Card(
      elevation: 2,
      color: Colors.orange[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_turned_in, color: Colors.orange[700], size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Current Assignment',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 20),
            
            Row(
              children: [
                const Icon(Icons.person, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assigned Driver',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      Text(
                        widget.roster['assignedDriverName']?.toString() ?? 'Not assigned',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            Row(
              children: [
                const Icon(Icons.directions_car, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assigned Vehicle',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      Text(
                        widget.roster['assignedVehicleReg']?.toString() ?? 'Not assigned',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ✅ FIXED: Driver selector using robust IDs
  Widget _buildDriverSelector() {
    // Get all valid driver IDs
    final validDriverIds = _availableDrivers
        .map((d) => _extractId(d))
        .where((id) => id != null && id.isNotEmpty)
        .toSet();
    
    // Check if current selection is valid
    final effectiveDriverValue = (_selectedDriverId != null && validDriverIds.contains(_selectedDriverId))
        ? _selectedDriverId
        : null;
    
    final isOrphan = _selectedDriverId != null && effectiveDriverValue == null;
    
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
                  'Select New Driver',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_availableDrivers.length} available',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.green[900],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isOrphan ? Colors.orange : Colors.grey[300]!
                ),
                borderRadius: BorderRadius.circular(8),
                color: _availableDrivers.isEmpty ? Colors.grey[200] : Colors.grey[50],
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: effectiveDriverValue,
                  isExpanded: true,
                  hint: Text(
                    _availableDrivers.isEmpty 
                      ? 'No drivers available' 
                      : 'Select a driver',
                    style: TextStyle(
                      color: _availableDrivers.isEmpty ? Colors.grey : null,
                    ),
                  ),
                  items: _availableDrivers.isEmpty 
                    ? null
                    : _availableDrivers
                        .where((driver) => _extractId(driver) != null)
                        .map((driver) {
                      final driverId = _extractId(driver)!;
                      final isOriginal = driverId == _originalDriverId;
                      
                      return DropdownMenuItem<String>(
                        value: driverId,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: isOriginal ? Colors.orange[100] : Colors.blue[100],
                              child: Text(
                                ((driver['name']?.toString() ?? 'D')[0]).toUpperCase(),
                                style: TextStyle(
                                  color: isOriginal ? Colors.orange[900] : Colors.blue[900],
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
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          driver['name']?.toString() ?? 'Unknown',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      if (isOriginal)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.orange,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'Current',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
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
                  onChanged: (_isUpdating || _availableDrivers.isEmpty) ? null : (value) {
                    setState(() => _selectedDriverId = value);
                  },
                ),
              ),
            ),
            
            if (isOrphan)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange[700], size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Previously selected driver not found in active list.',
                        style: TextStyle(fontSize: 11, color: Colors.orange[700]),
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

  // ✅ FIXED: Vehicle selector
  Widget _buildVehicleSelector() {
    final validVehicleIds = _availableVehicles
        .map((v) => _extractId(v))
        .where((id) => id != null && id.isNotEmpty)
        .toSet();
    
    final effectiveVehicleValue = (_selectedVehicleId != null && validVehicleIds.contains(_selectedVehicleId))
        ? _selectedVehicleId
        : null;
    
    final isOrphan = _selectedVehicleId != null && effectiveVehicleValue == null;
    
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
                  'Select New Vehicle',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_availableVehicles.length} available',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.green[900],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isOrphan ? Colors.orange : Colors.grey[300]!
                ),
                borderRadius: BorderRadius.circular(8),
                color: _availableVehicles.isEmpty ? Colors.grey[200] : Colors.grey[50],
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: effectiveVehicleValue,
                  isExpanded: true,
                  hint: Text(
                    _availableVehicles.isEmpty 
                      ? 'No vehicles available' 
                      : 'Select a vehicle',
                    style: TextStyle(
                      color: _availableVehicles.isEmpty ? Colors.grey : null,
                    ),
                  ),
                  items: _availableVehicles.isEmpty
                    ? null
                    : _availableVehicles
                        .where((vehicle) => _extractId(vehicle) != null)
                        .map((vehicle) {
                      final vehicleId = _extractId(vehicle)!;
                      final isOriginal = vehicleId == _originalVehicleId;
                      
                      return DropdownMenuItem<String>(
                        value: vehicleId,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isOriginal ? Colors.orange[50] : Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.local_shipping,
                                color: isOriginal ? Colors.orange[700] : Colors.blue[700],
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          vehicle['registrationNumber']?.toString() ?? 'Unknown',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      if (isOriginal)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.orange,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'Current',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
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
                  onChanged: (_isUpdating || _availableVehicles.isEmpty) ? null : (value) {
                    setState(() => _selectedVehicleId = value);
                  },
                ),
              ),
            ),
            
            if (isOrphan)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange[700], size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Previously selected vehicle not found in active list.',
                        style: TextStyle(fontSize: 11, color: Colors.orange[700]),
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

  Widget _buildUpdateButton() {
    final hasChanges = _selectedDriverId != _originalDriverId || 
                       _selectedVehicleId != _originalVehicleId;
    final canUpdate = _selectedDriverId != null && 
                      _selectedVehicleId != null &&
                      hasChanges &&
                      !_isUpdating;
    
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        icon: _isUpdating 
          ? const SizedBox(
              width: 20, 
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white, 
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.save, size: 22),
        label: Text(
          _isUpdating ? 'Updating Assignment...' : 'Update Assignment',
          style: const TextStyle(
            fontSize: 16, 
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: canUpdate ? Colors.blue : Colors.grey[400],
          foregroundColor: Colors.white,
          elevation: canUpdate ? 4 : 0,
          shadowColor: Colors.blue.withOpacity(0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: canUpdate ? _updateAssignment : null,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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

  String _formatRosterType(String? type) {
    if (type == null) return 'N/A';
    switch (type.toLowerCase()) {
      case 'login':
        return 'Login Only';
      case 'logout':
        return 'Logout Only';
      case 'both':
        return 'Login & Logout';
      default:
        return type;
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      final dateTime = date is DateTime ? date : DateTime.parse(date.toString());
      return DateFormat('MMM dd, yyyy').format(dateTime);
    } catch (e) {
      return date.toString();
    }
  }
}