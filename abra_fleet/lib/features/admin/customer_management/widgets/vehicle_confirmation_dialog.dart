// File: lib/features/admin/customer_management/widgets/vehicle_confirmation_dialog.dart
// Dialog to confirm vehicle selection before route optimization
// ✅ UPDATED: Shows driver name & phone, clarifies distance types

import 'package:flutter/material.dart';

class VehicleConfirmationDialog extends StatelessWidget {
  final Map<String, dynamic> vehicle;
  final List<Map<String, dynamic>> customers;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const VehicleConfirmationDialog({
    super.key,
    required this.vehicle,
    required this.customers,
    required this.onConfirm,
    required this.onCancel,
  });

  /// Helper: Safe string extraction
  String _safeString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    if (value is String) return value.trim();
    if (value is Map && value.containsKey('name')) return _safeString(value['name'], fallback);
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Extract vehicle registration number (not name)
    final vehicleNumber = _safeString(vehicle['registrationNumber']) != '' 
        ? _safeString(vehicle['registrationNumber'])
        : _safeString(vehicle['vehicleNumber'], 'Unknown Vehicle');
    
    // ✅ Extract driver NAME and PHONE (not MongoDB ID)
    String driverName = 'No Driver Assigned';
    String driverPhone = '';
    
    // Try multiple sources for driver data
    if (vehicle['assignedDriver'] != null) {
      final driver = vehicle['assignedDriver'];
      
      if (driver is Map) {
        // Driver is populated object from backend
        driverName = _safeString(driver['name'], 'Unknown Driver');
        driverPhone = _safeString(driver['phone']) != '' 
            ? _safeString(driver['phone'])
            : _safeString(driver['phoneNumber'], '');
        
        // Fallback to personalInfo if main fields empty
        if (driverName == 'Unknown Driver' && driver['personalInfo'] is Map) {
          final personal = driver['personalInfo'] as Map;
          final firstName = _safeString(personal['firstName'], '');
          final lastName = _safeString(personal['lastName'], '');
          driverName = '$firstName $lastName'.trim();
          if (driverName.isEmpty) driverName = 'Unknown Driver';
        }
        
        if (driverPhone.isEmpty && driver['personalInfo'] is Map) {
          final personal = driver['personalInfo'] as Map;
          driverPhone = _safeString(personal['phone']);
        }
      } else if (driver is String && driver.isNotEmpty) {
        // Driver is just an ID - try to get name from vehicle fields
        driverName = _safeString(vehicle['driverName'], 'Driver Assigned');
        driverPhone = _safeString(vehicle['driverPhone'], '');
        
        // Also check assignedDriverName and assignedDriverEmail
        if (driverName == 'Driver Assigned') {
          driverName = _safeString(vehicle['assignedDriverName'], 'Driver Assigned');
        }
      }
    }
    
    // 🔥 NEW: Fallback to top-level vehicle fields
    if (driverName == 'No Driver Assigned' || driverName == 'Driver Assigned') {
      final fallbackName = _safeString(vehicle['driverName'], '');
      if (fallbackName.isNotEmpty) {
        driverName = fallbackName;
      }
      
      final fallbackAssignedName = _safeString(vehicle['assignedDriverName'], '');
      if (fallbackAssignedName.isNotEmpty) {
        driverName = fallbackAssignedName;
      }
    }
    
    if (driverPhone.isEmpty) {
      driverPhone = _safeString(vehicle['driverPhone'], '');
    }
    
    // ✅ Parse seat capacity safely
    int totalSeats = 4;
    if (vehicle['capacity'] is Map) {
      final cap = vehicle['capacity'] as Map;
      final passengers = cap['passengers'] ?? cap['seating'];
      totalSeats = int.tryParse(passengers.toString()) ?? 4;
    } else {
      final seatValue = vehicle['seatCapacity'] ?? vehicle['seatingCapacity'] ?? vehicle['passengers'];
      totalSeats = int.tryParse(seatValue.toString()) ?? 4;
    }
    
    final assignedSeats = (vehicle['assignedCustomers'] as List?)?.length ?? 0;
    final availableSeats = totalSeats - 1 - assignedSeats; // -1 for driver
    
    // ✅ Extract distance to cluster (initial distance from vehicle to customer group)
    double? distanceToCluster;
    final distValue = vehicle['distanceToCluster'];
    if (distValue != null) {
      if (distValue is double) distanceToCluster = distValue;
      else if (distValue is int) distanceToCluster = distValue.toDouble();
      else if (distValue is String) distanceToCluster = double.tryParse(distValue);
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.directions_car, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vehicle Auto-Detected',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Confirm vehicle selection to proceed',
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
                    // Vehicle Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200, width: 2),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade700,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.directions_car,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      vehicleNumber,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Registration Number',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),
                          
                          // ✅ UPDATED: Driver Details (Name + Phone)
                          Row(
                            children: [
                              Expanded(
                                child: _buildDriverInfoTile(
                                  driverName: driverName,
                                  driverPhone: driverPhone,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildInfoTile(
                                  icon: Icons.airline_seat_recline_normal,
                                  label: 'Available Seats',
                                  value: '$availableSeats / $totalSeats',
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          
                          // ✅ Distance to Cluster (Initial Distance)
                          if (distanceToCluster != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.purple.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.purple.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.straighten, color: Colors.purple, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Initial Distance',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${distanceToCluster.toStringAsFixed(1)} km from vehicle to customer group',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Customers to Assign
                    const Text(
                      'Customers to Assign',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.people, color: Colors.blue.shade700, size: 24),
                              const SizedBox(width: 8),
                              Text(
                                '${customers.length} Customers',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...customers.map((customer) {
                            final name = _safeString(customer['customerName']) != ''
                                ? _safeString(customer['customerName'])
                                : _safeString(customer['employeeDetails']?['name'], 'Unknown');
                            
                            final location = _safeString(customer['officeLocation']) != ''
                                ? _safeString(customer['officeLocation'])
                                : _safeString(customer['pickupLocation'], 'Unknown Location');
                            
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.person,
                                      size: 18,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          location,
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
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Info Box
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.green.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'This vehicle has been automatically selected based on proximity and availability. The route will optimize pickup sequence based on distance.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.green.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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
                    label: const Text('Confirm & Generate Route'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
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

  /// ✅ NEW: Driver Info Tile with Name + Phone
  Widget _buildDriverInfoTile({
    required String driverName,
    required String driverPhone,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Driver',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            driverName,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          if (driverPhone.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.phone, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  driverPhone,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}