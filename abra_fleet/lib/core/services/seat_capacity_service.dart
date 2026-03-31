// File: lib/core/services/seat_capacity_service.dart
// Service for managing vehicle seat capacity and roster assignments

import 'package:abra_fleet/features/admin/vehicle_management/domain/entities/vehicle_entity.dart';

class SeatCapacityService {
  /// Calculate available seats for a vehicle
  /// Takes into account driver (1 seat) and currently assigned customers
  static int calculateAvailableSeats(Vehicle vehicle) {
    // If driver is assigned, they take 1 seat
    final driverSeats = vehicle.assignedDriver != null ? 1 : 0;
    final available = vehicle.seatCapacity - driverSeats - vehicle.assignedCustomers;
    return available > 0 ? available : 0;
  }

  /// Check if vehicle can accommodate additional customers
  static bool canAccommodateCustomers(Vehicle vehicle, int customerCount) {
    final available = calculateAvailableSeats(vehicle);
    return available >= customerCount;
  }

  /// Get seat capacity info for display
  static Map<String, dynamic> getSeatCapacityInfo(Vehicle vehicle) {
    final driverSeats = vehicle.assignedDriver != null ? 1 : 0;
    final available = calculateAvailableSeats(vehicle);
    final occupied = driverSeats + vehicle.assignedCustomers;

    return {
      'totalSeats': vehicle.seatCapacity,
      'driverSeats': driverSeats,
      'customerSeats': vehicle.assignedCustomers,
      'occupiedSeats': occupied,
      'availableSeats': available,
      'isFull': available == 0,
      'hasDriver': vehicle.assignedDriver != null,
    };
  }

  /// Generate user-friendly capacity message
  static String getCapacityMessage(Vehicle vehicle, {int? requestedSeats}) {
    final info = getSeatCapacityInfo(vehicle);
    
    if (requestedSeats != null) {
      if (requestedSeats > info['availableSeats']) {
        return 'Cannot assign $requestedSeats customer(s). Only ${info['availableSeats']} seat(s) available.';
      }
    }

    if (info['isFull']) {
      return 'Vehicle is full (${info['occupiedSeats']}/${info['totalSeats']} seats occupied)';
    }

    final parts = <String>[];
    if (info['hasDriver']) {
      parts.add('Driver: 1 seat');
    }
    if (info['customerSeats'] > 0) {
      parts.add('Customers: ${info['customerSeats']} seat(s)');
    }
    parts.add('Available: ${info['availableSeats']} seat(s)');

    return parts.join(' | ');
  }

  /// Validate roster assignment
  static Map<String, dynamic> validateAssignment({
    required Vehicle vehicle,
    required int customerCount,
  }) {
    final info = getSeatCapacityInfo(vehicle);
    
    // Check if vehicle has a driver
    if (!info['hasDriver']) {
      return {
        'valid': false,
        'message': 'Vehicle must have an assigned driver before assigning customers.',
      };
    }

    // Check if vehicle is active
    if (vehicle.status.toLowerCase() != 'active') {
      return {
        'valid': false,
        'message': 'Vehicle is not active. Status: ${vehicle.status}',
      };
    }

    // Check seat availability
    if (!canAccommodateCustomers(vehicle, customerCount)) {
      return {
        'valid': false,
        'message': 'Insufficient seats. Requested: $customerCount, Available: ${info['availableSeats']}',
        'availableSeats': info['availableSeats'],
        'requestedSeats': customerCount,
      };
    }

    return {
      'valid': true,
      'message': 'Assignment valid',
      'availableSeats': info['availableSeats'],
      'remainingSeats': info['availableSeats'] - customerCount,
    };
  }
}
