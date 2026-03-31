// File: lib/features/admin/vehicle_management/presentation/widgets/seat_capacity_indicator.dart
// Widget to display vehicle seat capacity visually

import 'package:flutter/material.dart';
import 'package:abra_fleet/features/admin/vehicle_management/domain/entities/vehicle_entity.dart';
import 'package:abra_fleet/core/services/seat_capacity_service.dart';

class SeatCapacityIndicator extends StatelessWidget {
  final Vehicle vehicle;
  final bool showDetails;
  final bool compact;

  const SeatCapacityIndicator({
    super.key,
    required this.vehicle,
    this.showDetails = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final info = SeatCapacityService.getSeatCapacityInfo(vehicle);
    
    if (compact) {
      return _buildCompactView(info);
    }
    
    return _buildDetailedView(info);
  }

  Widget _buildCompactView(Map<String, dynamic> info) {
    final available = info['availableSeats'] as int;
    final occupied = info['occupiedSeats'] as int;
    final total = info['totalSeats'] as int;
    
    Color statusColor = Colors.green;
    if (available == 0) {
      statusColor = Colors.red;
    } else if (available <= 1) {
      statusColor = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.airline_seat_recline_normal, size: 14, color: statusColor),
          const SizedBox(width: 4),
          Text(
            '$available/$total',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedView(Map<String, dynamic> info) {
    final available = info['availableSeats'] as int;
    final occupied = info['occupiedSeats'] as int;
    final total = info['totalSeats'] as int;
    final hasDriver = info['hasDriver'] as bool;
    final driverSeats = info['driverSeats'] as int;
    final customerSeats = info['customerSeats'] as int;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.event_seat, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Seat Capacity',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Visual seat representation
          _buildSeatVisual(total, driverSeats, customerSeats),
          
          const SizedBox(height: 12),
          
          // Capacity breakdown
          if (showDetails) ...[
            _buildCapacityRow('Total Seats', total, Colors.grey.shade600),
            if (hasDriver)
              _buildCapacityRow('Driver', driverSeats, Colors.blue.shade700),
            if (customerSeats > 0)
              _buildCapacityRow('Customers', customerSeats, Colors.orange.shade700),
            _buildCapacityRow(
              'Available',
              available,
              available == 0 ? Colors.red : Colors.green.shade700,
              bold: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSeatVisual(int total, int driverSeats, int customerSeats) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(total, (index) {
        IconData icon;
        Color color;
        
        if (index < driverSeats) {
          // Driver seat
          icon = Icons.airline_seat_recline_extra;
          color = Colors.blue.shade700;
        } else if (index < driverSeats + customerSeats) {
          // Occupied customer seat
          icon = Icons.airline_seat_recline_normal;
          color = Colors.orange.shade700;
        } else {
          // Available seat
          icon = Icons.event_seat_outlined;
          color = Colors.green.shade700;
        }
        
        return Icon(icon, size: 24, color: color);
      }),
    );
  }

  Widget _buildCapacityRow(String label, int count, Color color, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog to show before/after seat assignment
class SeatCapacityDialog extends StatelessWidget {
  final Vehicle vehicle;
  final int customersToAssign;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const SeatCapacityDialog({
    super.key,
    required this.vehicle,
    required this.customersToAssign,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final validation = SeatCapacityService.validateAssignment(
      vehicle: vehicle,
      customerCount: customersToAssign,
    );
    
    final isValid = validation['valid'] as bool;
    final currentInfo = SeatCapacityService.getSeatCapacityInfo(vehicle);
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isValid ? Icons.check_circle : Icons.error,
            color: isValid ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(isValid ? 'Confirm Assignment' : 'Assignment Not Possible'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vehicle: ${vehicle.name} (${vehicle.licensePlate})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Current state
            _buildStateCard(
              'Current State',
              currentInfo['occupiedSeats'],
              currentInfo['availableSeats'],
              currentInfo['totalSeats'],
              Colors.blue,
            ),
            
            const SizedBox(height: 12),
            
            // After assignment
            if (isValid) ...[
              _buildStateCard(
                'After Assignment',
                currentInfo['occupiedSeats'] + customersToAssign,
                currentInfo['availableSeats'] - customersToAssign,
                currentInfo['totalSeats'],
                Colors.green,
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        validation['message'],
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
        if (isValid)
          ElevatedButton(
            onPressed: onConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Assignment'),
          ),
      ],
    );
  }

  Widget _buildStateCard(String title, int occupied, int available, int total, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Occupied', occupied, Colors.orange),
              _buildStatItem('Available', available, Colors.green),
              _buildStatItem('Total', total, Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
