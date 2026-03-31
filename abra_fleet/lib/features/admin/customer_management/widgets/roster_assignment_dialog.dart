// File: lib/features/admin/customer_management/widgets/roster_assignment_dialog.dart
// Dialog for assigning rosters to vehicles with seat capacity validation

import 'package:flutter/material.dart';
import 'package:abra_fleet/features/admin/vehicle_management/domain/entities/vehicle_entity.dart';
import 'package:abra_fleet/core/services/seat_capacity_service.dart';
import 'package:abra_fleet/features/admin/vehicle_management/presentation/widgets/seat_capacity_indicator.dart';

class RosterAssignmentDialog extends StatefulWidget {
  final List<Map<String, dynamic>> selectedRosters;
  final List<Vehicle> availableVehicles;
  final Function(String vehicleId, List<String> rosterIds) onAssign;

  const RosterAssignmentDialog({
    super.key,
    required this.selectedRosters,
    required this.availableVehicles,
    required this.onAssign,
  });

  @override
  State<RosterAssignmentDialog> createState() => _RosterAssignmentDialogState();
}

class _RosterAssignmentDialogState extends State<RosterAssignmentDialog> {
  Vehicle? _selectedVehicle;
  String? _validationError;

  @override
  Widget build(BuildContext context) {
    final customerCount = widget.selectedRosters.length;

    return AlertDialog(
      title: const Text('Assign Rosters to Vehicle'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Selected rosters info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.people, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Text(
                      '$customerCount customer(s) selected',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Vehicle selection
              const Text(
                'Select Vehicle',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              
              // Vehicle list
              ...widget.availableVehicles.map((vehicle) {
                final isSelected = _selectedVehicle?.id == vehicle.id;
                final validation = SeatCapacityService.validateAssignment(
                  vehicle: vehicle,
                  customerCount: customerCount,
                );
                final isValid = validation['valid'] as bool;
                
                return _buildVehicleCard(vehicle, isSelected, isValid, validation);
              }).toList(),
              
              // Validation error
              if (_validationError != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _validationError!,
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedVehicle != null ? _handleAssign : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: const Text('Assign'),
        ),
      ],
    );
  }

  Widget _buildVehicleCard(
    Vehicle vehicle,
    bool isSelected,
    bool isValid,
    Map<String, dynamic> validation,
  ) {
    final info = SeatCapacityService.getSeatCapacityInfo(vehicle);
    
    Color borderColor = Colors.grey.shade300;
    if (isSelected) {
      borderColor = isValid ? Colors.green : Colors.red;
    } else if (!isValid) {
      borderColor = Colors.red.shade200;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? Colors.green.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              if (isValid) {
                _selectedVehicle = vehicle;
                _validationError = null;
              } else {
                _selectedVehicle = null;
                _validationError = validation['message'];
              }
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Selection indicator
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.green : Colors.grey,
                          width: 2,
                        ),
                        color: isSelected ? Colors.green : Colors.transparent,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, size: 16, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    
                    // Vehicle info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vehicle.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '${vehicle.licensePlate} • ${vehicle.model}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Status badge
                    if (!isValid)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.block, size: 14, color: Colors.red.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Not Available',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Seat capacity visualization
                _buildSeatCapacityRow(info, widget.selectedRosters.length),
                
                // Driver info
                if (vehicle.assignedDriver != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.person, size: 14, color: Colors.blue.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'Driver: ${vehicle.assignedDriver}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeatCapacityRow(Map<String, dynamic> info, int requestedSeats) {
    final available = info['availableSeats'] as int;
    final occupied = info['occupiedSeats'] as int;
    final total = info['totalSeats'] as int;
    final canFit = available >= requestedSeats;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: canFit ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: canFit ? Colors.green.shade200 : Colors.red.shade200,
        ),
      ),
      child: Column(
        children: [
          // Visual seats
          Row(
            children: [
              // Current state
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      children: List.generate(total, (index) {
                        if (index < occupied) {
                          return Icon(
                            Icons.airline_seat_recline_normal,
                            size: 20,
                            color: Colors.orange.shade700,
                          );
                        } else {
                          return Icon(
                            Icons.event_seat_outlined,
                            size: 20,
                            color: Colors.green.shade700,
                          );
                        }
                      }),
                    ),
                  ],
                ),
              ),
              
              // Arrow
              const Icon(Icons.arrow_forward, size: 20),
              
              // After assignment
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'After Assignment',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      children: List.generate(total, (index) {
                        final newOccupied = occupied + (canFit ? requestedSeats : 0);
                        if (index < newOccupied) {
                          return Icon(
                            Icons.airline_seat_recline_normal,
                            size: 20,
                            color: canFit ? Colors.orange.shade700 : Colors.red.shade700,
                          );
                        } else {
                          return Icon(
                            Icons.event_seat_outlined,
                            size: 20,
                            color: Colors.green.shade700,
                          );
                        }
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Text summary
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Available: $available seats',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: canFit ? Colors.green.shade900 : Colors.red.shade900,
                ),
              ),
              Text(
                'Requested: $requestedSeats seats',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleAssign() {
    if (_selectedVehicle == null) return;

    final validation = SeatCapacityService.validateAssignment(
      vehicle: _selectedVehicle!,
      customerCount: widget.selectedRosters.length,
    );

    if (!(validation['valid'] as bool)) {
      setState(() {
        _validationError = validation['message'];
      });
      return;
    }

    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (context) => SeatCapacityDialog(
        vehicle: _selectedVehicle!,
        customersToAssign: widget.selectedRosters.length,
        onConfirm: () {
          Navigator.of(context).pop(); // Close confirmation
          
          final rosterIds = widget.selectedRosters
              .map((r) => (r['id'] ?? r['_id'] ?? '').toString())
              .where((id) => id.isNotEmpty)
              .toList();
          
          widget.onAssign(_selectedVehicle!.id, rosterIds);
          Navigator.of(context).pop(); // Close assignment dialog
        },
        onCancel: () => Navigator.of(context).pop(),
      ),
    );
  }
}
