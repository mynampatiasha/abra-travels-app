// lib/features/admin/customer_management/notification/roster/
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:abra_fleet/core/services/assignment_service.dart';

class VehicleSelectionDialog extends StatefulWidget {
  final List<String> rosterIds;
  final AssignmentService assignmentService;
  final VoidCallback onAssignmentSuccess;

  const VehicleSelectionDialog({
    super.key,
    required this.rosterIds,
    required this.assignmentService,
    required this.onAssignmentSuccess,
  });

  @override
  State<VehicleSelectionDialog> createState() => _VehicleSelectionDialogState();
}

class _VehicleSelectionDialogState extends State<VehicleSelectionDialog> {
  bool _isLoading = true;
  bool _isAssigning = false;
  String? _errorMessage;
  
  Map<String, dynamic>? _bestMatch;
  List<Map<String, dynamic>> _alternatives = [];
  List<Map<String, dynamic>> _allOptions = [];
  Map<String, dynamic>? _stats;
  
  final Color _themeColor = const Color(0xFF10B981);
  
  @override
  void initState() {
    super.initState();
    _loadMatchingVehicles();
  }
  
  Future<void> _loadMatchingVehicles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      debugPrint('\n' + '🔍' * 80);
      debugPrint('🔍 VEHICLE SELECTION DIALOG - LOADING VEHICLES');
      debugPrint('🔍' * 80);
      debugPrint('📋 Roster IDs: ${widget.rosterIds}');
      debugPrint('📊 Roster Count: ${widget.rosterIds.length}');
      
      final result = await widget.assignmentService.findMatchingVehicles(
        rosterIds: widget.rosterIds,
      );
      
      debugPrint('\n📥 RAW API RESPONSE RECEIVED:');
      debugPrint('   Response Type: ${result.runtimeType}');
      debugPrint('   Response Keys: ${result.keys.toList()}');
      debugPrint('   Success: ${result['success']}');
      
      // ✅ CRITICAL FIX: Access data from result['data'] not result directly
      final data = result['data'];
      if (data == null) {
        throw Exception('No data in response');
      }
      
      debugPrint('\n📊 PARSED DATA STRUCTURE:');
      debugPrint('   Data Type: ${data.runtimeType}');
      debugPrint('   Data Keys: ${data.keys.toList()}');
      debugPrint('   Best Match: ${data['bestMatch'] != null ? 'Found' : 'None'}');
      debugPrint('   Alternatives: ${data['alternatives']?.length ?? 0}');
      debugPrint('   All Options: ${data['allOptions']?.length ?? 0}');
      debugPrint('   Stats: ${data['stats']}');
      
      if (mounted) {
        setState(() {
          _bestMatch = data['bestMatch'];
          _alternatives = List<Map<String, dynamic>>.from(data['alternatives'] ?? []);
          _allOptions = List<Map<String, dynamic>>.from(data['allOptions'] ?? []);
          _stats = data['stats'];
          _isLoading = false;
        });
        
        debugPrint('\n✅ STATE UPDATED SUCCESSFULLY:');
        debugPrint('   Best Match: ${_bestMatch != null ? 'Set' : 'None'}');
        debugPrint('   Alternatives: ${_alternatives.length}');
        debugPrint('   All Options: ${_allOptions.length}');
        debugPrint('   Stats: $_stats');
      }
      
      debugPrint('🔍' * 80 + '\n');
    } catch (e, stackTrace) {
      debugPrint('\n❌ VEHICLE LOADING ERROR:');
      debugPrint('❌' * 80);
      debugPrint('❌ Error Type: ${e.runtimeType}');
      debugPrint('❌ Error Message: $e');
      debugPrint('❌ Stack Trace: $stackTrace');
      debugPrint('❌ Roster IDs: ${widget.rosterIds}');
      debugPrint('❌' * 80);
      
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }
  
  Future<void> _assignVehicle(String vehicleId) async {
    // Prevent multiple simultaneous assignments
    if (_isAssigning) {
      debugPrint('⚠️ Assignment already in progress, ignoring duplicate click');
      return;
    }
    
    // 🔍 COMPREHENSIVE ASSIGNMENT DEBUGGING
    debugPrint('\n' + '🚗' * 80);
    debugPrint('🚗 VEHICLE ASSIGNMENT DEBUG - START');
    debugPrint('🚗' * 80);
    debugPrint('📍 Location: VehicleSelectionDialog._assignVehicle()');
    debugPrint('⏰ Timestamp: ${DateTime.now().toIso8601String()}');
    debugPrint('🎯 Vehicle ID: $vehicleId');
    debugPrint('📋 Roster IDs: ${widget.rosterIds}');
    debugPrint('📊 Roster Count: ${widget.rosterIds.length}');
    debugPrint('🔄 Assignment Type: ${widget.rosterIds.length == 1 ? 'SINGLE ROSTER' : 'GROUP ASSIGNMENT'}');
    
    setState(() {
      _isAssigning = true;
    });
    
    debugPrint('\n📤 STARTING ASSIGNMENT PROCESS...');
    debugPrint('   State updated: _isAssigning = true');
    
    try {
      debugPrint('\n🎯 DETERMINING ASSIGNMENT METHOD...');
      
      Map<String, dynamic> result;
      
      if (widget.rosterIds.length == 1) {
        debugPrint('   ✅ Using SINGLE ROSTER assignment');
        debugPrint('   📋 Roster ID: ${widget.rosterIds.first}');
        debugPrint('   🚗 Vehicle ID: $vehicleId');
        debugPrint('   📞 Calling assignmentService.assignRoster()...');
        
        result = await widget.assignmentService.assignRoster(
          rosterId: widget.rosterIds.first,
          vehicleId: vehicleId,
        );
        
        debugPrint('   ✅ Single roster assignment completed');
      } else {
        debugPrint('   ✅ Using GROUP ASSIGNMENT');
        debugPrint('   📋 Roster IDs: ${widget.rosterIds}');
        debugPrint('   📊 Total Rosters: ${widget.rosterIds.length}');
        debugPrint('   🚗 Vehicle ID: $vehicleId');
        debugPrint('   📞 Calling assignmentService.assignGroup()...');
        
        result = await widget.assignmentService.assignGroup(
          rosterIds: widget.rosterIds,
          vehicleId: vehicleId,
        );
        
        debugPrint('   ✅ Group assignment completed');
      }
      
      debugPrint('\n📥 ASSIGNMENT RESULT RECEIVED:');
      debugPrint('   Result Type: ${result.runtimeType}');
      debugPrint('   Result Keys: ${result.keys.toList()}');
      debugPrint('   Success: ${result['success']}');
      debugPrint('   Message: ${result['message']}');
      
      if (mounted) {
        debugPrint('\n✅ WIDGET STILL MOUNTED - SHOWING SUCCESS');
        
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Assignment successful!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        
        debugPrint('   ✅ Success SnackBar shown');
        
        // Close dialog
        Navigator.of(context).pop(true);
        debugPrint('   ✅ Dialog closed');
        
        // Trigger refresh
        widget.onAssignmentSuccess();
        debugPrint('   ✅ Refresh callback triggered');
      } else {
        debugPrint('\n⚠️ WIDGET NOT MOUNTED - SKIPPING UI UPDATES');
      }
      
    } catch (e, stackTrace) {
      debugPrint('\n❌ ASSIGNMENT FAILED');
      debugPrint('❌' * 80);
      debugPrint('❌ Error Type: ${e.runtimeType}');
      debugPrint('❌ Error Message: $e');
      debugPrint('❌ Stack Trace: $stackTrace');
      debugPrint('❌ Vehicle ID: $vehicleId');
      debugPrint('❌ Roster IDs: ${widget.rosterIds}');
      debugPrint('❌ Assignment Type: ${widget.rosterIds.length == 1 ? 'SINGLE' : 'GROUP'}');
      debugPrint('❌' * 80);
      
      if (mounted) {
        debugPrint('   🔧 Widget mounted - showing error SnackBar');
        setState(() {
          _isAssigning = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Assignment failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        debugPrint('   ✅ Error SnackBar shown');
      } else {
        debugPrint('   ⚠️ Widget not mounted - skipping error UI');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAssigning = false;
        });
      }
    }
    
    debugPrint('\n🚗' * 80);
    debugPrint('🚗 VEHICLE ASSIGNMENT DEBUG - END');
    debugPrint('🚗' * 80 + '\n');
  }
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 700,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            _buildHeader(),
            
            const Divider(height: 1),
            
            // Content
            Expanded(
              child: _isLoading
                  ? _buildLoadingState()
                  : _errorMessage != null
                      ? _buildErrorState()
                      : _buildVehicleList(),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _themeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.local_shipping, color: _themeColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Vehicle',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.rosterIds.length == 1
                      ? 'Assign 1 roster to vehicle'
                      : 'Assign ${widget.rosterIds.length} rosters to vehicle',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          if (_stats != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Text(
                    '${_stats!['compatible'] ?? 0}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _themeColor,
                    ),
                  ),
                  const Text(
                    'Compatible',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: _themeColor),
          const SizedBox(height: 16),
          const Text(
            'Finding best vehicles...',
            style: TextStyle(fontSize: 16, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Analyzing distance, fuel, capacity, and driver ratings',
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }
  
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
          const SizedBox(height: 16),
          const Text(
            'Failed to find matching vehicles',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Unknown error occurred',
            style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadMatchingVehicles,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _themeColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildVehicleList() {
    debugPrint('\n' + '🚗' * 80);
    debugPrint('🚗 BUILDING VEHICLE LIST');
    debugPrint('🚗' * 80);
    debugPrint('📊 _allOptions.length: ${_allOptions.length}');
    debugPrint('📊 _allOptions.isEmpty: ${_allOptions.isEmpty}');
    debugPrint('📊 _bestMatch: ${_bestMatch != null ? 'Found' : 'None'}');
    debugPrint('📊 _alternatives.length: ${_alternatives.length}');
    debugPrint('📊 _stats: $_stats');
    
    if (_allOptions.isNotEmpty) {
      debugPrint('\n🚗 SAMPLE VEHICLE DATA:');
      final sample = _allOptions.first;
      debugPrint('   Keys: ${sample.keys.toList()}');
      debugPrint('   vehicleId: ${sample['vehicleId']}');
      debugPrint('   vehicleReg: ${sample['vehicleReg']}');
      debugPrint('   totalScore: ${sample['totalScore']}');
    }
    debugPrint('🚗' * 80 + '\n');
    
    if (_allOptions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No compatible vehicles found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'No vehicles are available for this assignment',
              style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadMatchingVehicles,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _themeColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
    
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Best Match
        if (_bestMatch != null) ...[
          _buildSectionHeader('🥇 Best Match', _bestMatch!['totalScore']),
          const SizedBox(height: 12),
          _buildVehicleCard(_bestMatch!, isBest: true),
          const SizedBox(height: 24),
        ],
        
        // Alternatives
        if (_alternatives.isNotEmpty) ...[
          _buildSectionHeader('Alternative Options', null),
          const SizedBox(height: 12),
          ..._alternatives.map((vehicle) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildVehicleCard(vehicle),
              )),
        ],
      ],
    );
  }
  
  Widget _buildSectionHeader(String title, int? score) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        if (score != null) ...[
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getScoreColor(score).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _getScoreColor(score)),
            ),
            child: Text(
              '$score/100',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _getScoreColor(score),
              ),
            ),
          ),
        ],
      ],
    );
  }
  
  Widget _buildVehicleCard(Map<String, dynamic> vehicle, {bool isBest = false}) {
    final vehicleId = vehicle['vehicleId'] ?? '';
    final vehicleReg = vehicle['vehicleReg'] ?? 'Unknown';
    final totalScore = vehicle['totalScore'] ?? 0;
    final breakdown = vehicle['breakdown'] ?? {};
    final details = vehicle['details'] ?? {};
    
    final driverName = details['driverName'] ?? 'Unknown';
    final driverRating = details['driverRating'] ?? '0.0';
    final distanceKm = details['distanceKm'] ?? 0.0;
    final fuelPercent = details['fuelPercent'] ?? 0;
    final availableSeats = details['availableSeats'] ?? 0;
    final totalSeats = details['totalSeats'] ?? 0;
    
    return Container(
      decoration: BoxDecoration(
        color: isBest ? _themeColor.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isBest ? _themeColor : const Color(0xFFE2E8F0),
          width: isBest ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Vehicle Icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _themeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.directions_car, color: _themeColor, size: 24),
                ),
                const SizedBox(width: 12),
                
                // Vehicle Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicleReg,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.person, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            driverName,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.star, size: 14, color: Colors.amber[700]),
                          const SizedBox(width: 4),
                          Text(
                            driverRating,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Score Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _getScoreColor(totalScore).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _getScoreColor(totalScore)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$totalScore',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _getScoreColor(totalScore),
                        ),
                      ),
                      Text(
                        '/100',
                        style: TextStyle(
                          fontSize: 11,
                          color: _getScoreColor(totalScore),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Stats Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(
                top: BorderSide(color: Colors.grey[200]!),
                bottom: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(Icons.route, '${distanceKm.toStringAsFixed(1)} km', 'Distance'),
                _buildStatItem(Icons.local_gas_station, '$fuelPercent%', 'Fuel'),
                _buildStatItem(Icons.event_seat, '$availableSeats/$totalSeats', 'Seats'),
              ],
            ),
          ),
          
          // Score Breakdown
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Score Breakdown:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildScoreChip('Distance', breakdown['distance'] ?? 0, 40),
                    _buildScoreChip('Fuel', breakdown['fuel'] ?? 0, 15),
                    _buildScoreChip('Utilization', breakdown['utilization'] ?? 0, 15),
                    _buildScoreChip('Capacity', breakdown['capacity'] ?? 0, 10),
                    _buildScoreChip('Rating', breakdown['driverRating'] ?? 0, 10),
                    _buildScoreChip('Hours', breakdown['driverHours'] ?? 0, 10),
                  ],
                ),
              ],
            ),
          ),
          
          // Assign Button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isAssigning ? null : () => _assignVehicle(vehicleId),
                icon: _isAssigning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.check_circle),
                label: Text(_isAssigning ? 'Assigning...' : 'Assign This Vehicle'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isBest ? _themeColor : Colors.blue[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF334155),
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }
  
  Widget _buildScoreChip(String label, int score, int maxScore) {
    final percentage = (score / maxScore * 100).clamp(0, 100).toInt();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getScoreColor(percentage).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _getScoreColor(percentage).withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: _getScoreColor(percentage),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$score/$maxScore',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _getScoreColor(percentage),
            ),
          ),
        ],
      ),
    );
  }
  
  Color _getScoreColor(int score) {
    if (score >= 80) return const Color(0xFF10B981); // Green
    if (score >= 60) return const Color(0xFF3B82F6); // Blue
    if (score >= 40) return const Color(0xFFF59E0B); // Orange
    return const Color(0xFFEF4444); // Red
  }
}