// File: lib/features/admin/driver_management/domain/repositories/driver_repository.dart
// Defines the contract for driver data operations.

import 'package:abra_fleet/features/admin/driver_management/domain/entities/driver_entity.dart'; // Import your Driver entity

abstract class DriverRepository {
  // Get a list of all drivers.
  Future<List<Driver>> getDrivers();

  // Get a specific driver by their ID.
  Future<Driver?> getDriverById(String id);

  // Add a new driver.
  // Returns the newly added driver (possibly with a server-generated ID).
  Future<Driver> addDriver(Driver driver);

  // Update an existing driver.
  Future<void> updateDriver(Driver driver);

  // Delete a driver by their ID.
  Future<void> deleteDriver(String id);
}