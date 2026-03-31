// File: lib/features/admin/customer_management/widgets/route_optimization_dialog.dart
// Dialog to show optimized route with pickup sequence
// ✅ UPDATED: Shows driver name & phone, clarifies distance types, uses AM/PM format

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class RouteOptimizationDialog extends StatelessWidget {
  final Map<String, dynamic> routePlan;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const RouteOptimizationDialog({
    super.key,
    required this.routePlan,
    required this.onConfirm,
    required this.onCancel,
  });

  /// Helper: Safe string extraction
  String _safeString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    if (value is String) return value.trim();
    if (value is Map && value.containsKey('name')) return _safeString(value['name'], fallback);
    if (value is Map && value.containsKey('address')) return _safeString(value['address'], fallback);
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final route = (routePlan['route'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    
    // Parse total distance (complete pickup route distance)
    final totalDistanceValue = routePlan['totalDistance'];
    final totalDistance = totalDistanceValue is double ? totalDistanceValue : 
                         (totalDistanceValue is int ? totalDistanceValue.toDouble() : 
                         (totalDistanceValue is String ? double.tryParse(totalDistanceValue) ?? 0.0 : 0.0));
    
    // Parse total time
    final totalTimeValue = routePlan['totalTime'];
    final totalTime = totalTimeValue is int ? totalTimeValue : 
                     (totalTimeValue is String ? int.tryParse(totalTimeValue) ?? 0 : 
                     (totalTimeValue is double ? totalTimeValue.toInt() : 0));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 700,
        constraints: const BoxConstraints(maxHeight: 800),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade700,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.route, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Optimized Route Plan',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Furthest customer picked first, nearest picked last',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: onCancel,
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Vehicle Info Card
                    _buildVehicleCard(),
                    
                    const SizedBox(height: 20),
                    
                    // Summary Stats (Total Route Distance)
                    _buildSummaryStats(totalDistance, totalTime, route.length),
                    
                    const SizedBox(height: 20),
                    
                    // Route Timeline
                    const Text(
                      'Pickup Sequence',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Starting point
                    _buildStartPoint(),
                    
                    // Customer pickups
                    ...route.map((stop) => _buildRouteStop(stop)),
                    
                    // End point
                    if (route.isNotEmpty) _buildEndPoint(route.last),
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: onConfirm,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Confirm & Assign'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
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

  /// ✅ UPDATED: Vehicle card with driver name + phone
  Widget _buildVehicleCard() {
    final vehicleNumber = _safeString(routePlan['vehicle']?['registrationNumber']) != ''
        ? _safeString(routePlan['vehicle']?['registrationNumber'])
        : _safeString(routePlan['vehicleNumber'], 'Unknown Vehicle');
    
    // ✅ Extract driver NAME and PHONE (not MongoDB ID)
    String driverName = 'Unknown Driver';
    String driverPhone = '';
    
    final driverData = routePlan['vehicle']?['assignedDriver'] ?? routePlan['driverName'];
    
    if (driverData is Map) {
      driverName = _safeString(driverData['name'], 'Unknown Driver');
      driverPhone = _safeString(driverData['phone']) != ''
          ? _safeString(driverData['phone'])
          : _safeString(driverData['phoneNumber'], '');
      
      // Fallback to personalInfo
      if (driverName == 'Unknown Driver' && driverData['personalInfo'] is Map) {
        final personal = driverData['personalInfo'] as Map;
        final firstName = _safeString(personal['firstName'], '');
        final lastName = _safeString(personal['lastName'], '');
        driverName = '$firstName $lastName'.trim();
        if (driverName.isEmpty) driverName = 'Unknown Driver';
      }
      
      if (driverPhone.isEmpty && driverData['personalInfo'] is Map) {
        final personal = driverData['personalInfo'] as Map;
        driverPhone = _safeString(personal['phone']);
      }
    } else if (driverData is String && driverData.isNotEmpty) {
      // Don't show MongoDB ID
      if (!(driverData.length == 24 && RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(driverData))) {
        driverName = driverData;
      }
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade700,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.directions_car, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicleNumber,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Driver: $driverName',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (driverPhone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.phone, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        driverPhone,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
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

  /// ✅ UPDATED: Summary with "Total Route Distance" clarification
  Widget _buildSummaryStats(double distance, int time, int stops) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.route,
            label: 'Total Route Distance',
            sublabel: 'All pickups combined',
            value: '${distance.toStringAsFixed(1)} km',
            color: Colors.orange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.access_time,
            label: 'Total Time',
            sublabel: 'Including all stops',
            value: '${time} mins',
            color: Colors.purple,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.people,
            label: 'Customers',
            sublabel: 'To be picked up',
            value: '$stops',
            color: Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    String? sublabel,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStartPoint() {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_on, color: Colors.white, size: 24),
              ),
              Container(
                width: 3,
                height: 40,
                color: Colors.grey.shade300,
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Starting Point',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Driver Location',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
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

  /// ✅ UPDATED: Route stop with AM/PM time format and ready-by time
  Widget _buildRouteStop(Map<String, dynamic> stop) {
    final sequenceValue = stop['sequence'];
    final sequence = sequenceValue is int ? sequenceValue : 
                    (sequenceValue is String ? int.tryParse(sequenceValue) ?? 0 : 
                    (sequenceValue is double ? sequenceValue.toInt() : 0));
    
    final customerName = _safeString(stop['customerName'], 'Unknown Customer');
    final location = stop['location'] as Map<String, dynamic>?;
    final address = _safeString(location?['address'], 'Unknown Address');
    
    // Distance from previous stop
    final distanceValue = stop['distanceFromPrevious'];
    final distance = distanceValue is double ? distanceValue : 
                    (distanceValue is int ? distanceValue.toDouble() : 
                    (distanceValue is String ? double.tryParse(distanceValue) ?? 0.0 : 0.0));
    
    // Time estimation
    final timeValue = stop['estimatedTime'];
    final time = timeValue is int ? timeValue : 
                (timeValue is String ? int.tryParse(timeValue) ?? 0 : 
                (timeValue is double ? timeValue.toInt() : 0));
    
    // ✅ Parse pickup time and ready-by time
    final eta = stop['eta'] as DateTime? ?? DateTime.now();
    
    // Parse ready-by time (20 minutes before pickup)
    DateTime readyByTime = eta.subtract(const Duration(minutes: 20));
    if (stop['readyByTime'] != null) {
      final readyByStr = stop['readyByTime'].toString();
      try {
        // Try parsing HH:mm format
        final timeParts = readyByStr.split(':');
        if (timeParts.length >= 2) {
          readyByTime = DateTime(
            eta.year, eta.month, eta.day,
            int.parse(timeParts[0]),
            int.parse(timeParts[1]),
          );
        }
      } catch (e) {
        // Use default (20 min before)
      }
    }
    
    // Cumulative distance
    final cumulativeDistanceValue = stop['cumulativeDistance'];
    final cumulativeDistance = cumulativeDistanceValue is double ? cumulativeDistanceValue : 
                              (cumulativeDistanceValue is int ? cumulativeDistanceValue.toDouble() : 
                              (cumulativeDistanceValue is String ? double.tryParse(cumulativeDistanceValue) ?? 0.0 : 0.0));

    final route = routePlan['route'] as List? ?? [];

    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$sequence',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              if (sequence < route.length)
                Container(
                  width: 3,
                  height: 40,
                  color: Colors.grey.shade300,
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
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
                      Expanded(
                        child: Text(
                          'Pickup: $customerName',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      // ✅ Show pickup time in AM/PM format
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          DateFormat('h:mm a').format(eta),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // ✅ Show ready-by time
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.alarm, size: 16, color: Colors.orange.shade700),
                        const SizedBox(width: 6),
                        Text(
                          'BE READY BY: ${DateFormat('h:mm a').format(readyByTime)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          address,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildInfoChip(
                        icon: Icons.straighten,
                        label: '${distance.toStringAsFixed(1)} km',
                        sublabel: 'from prev stop',
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      _buildInfoChip(
                        icon: Icons.access_time,
                        label: '$time mins',
                        sublabel: 'drive time',
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      _buildInfoChip(
                        icon: Icons.route,
                        label: '${cumulativeDistance.toStringAsFixed(1)} km',
                        sublabel: 'total so far',
                        color: Colors.purple,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEndPoint(Map<String, dynamic> lastStop) {
    final eta = lastStop['eta'] as DateTime? ?? DateTime.now();
    
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.red.shade700,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.flag, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Route Complete - Arrive at Office',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Estimated arrival: ${DateFormat('h:mm a').format(eta)}',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
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

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    String? sublabel,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}