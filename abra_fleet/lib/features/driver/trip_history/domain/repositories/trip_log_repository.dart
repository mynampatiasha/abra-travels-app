// File: lib/features/driver/trip_history/domain/repositories/trip_log_repository.dart
// Defines the contract for trip log data operations.

import 'package:abra_fleet/features/driver/trip_history/domain/entities/trip_log_entity.dart'; // Import your TripLogEntity

abstract class TripLogRepository {
  // Get a list of trip logs for a specific driver.
  // In a real scenario, you'd pass a driverId.
  // For a mock, we might just return all or a predefined set for the "current" mock driver.
  Future<List<TripLogEntity>> getTripLogs({String? driverId}); // driverId might be optional for a mock

  // Add a new trip log.
  // This would typically be called when a driver ends a trip.
  Future<TripLogEntity> addTripLog(TripLogEntity tripLog);

// Get a specific trip log by its ID (optional, might not be needed if details are part of the list item)
// Future<TripLogEntity?> getTripLogById(String id);

// Note: Updating or deleting past trip logs might be an admin function,
// or not allowed for drivers. We'll keep it simple for now.
}
