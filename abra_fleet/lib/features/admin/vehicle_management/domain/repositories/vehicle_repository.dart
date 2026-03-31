// File: lib/features/admin/vehicle_management/domain/repositories/vehicle_repository.dart
// Defines the contract for vehicle data operations, now including location methods.

import 'package:abra_fleet/features/admin/vehicle_management/domain/entities/vehicle_entity.dart';
import 'package:latlong2/latlong.dart'; // Import for LatLng

abstract class VehicleRepository {
  Future<List<Vehicle>> getVehicles();
  Future<Vehicle?> getVehicleById(String id);
  Future<Vehicle> addVehicle(Vehicle vehicle);
  Future<void> updateVehicle(Vehicle vehicle);
  Future<void> deleteVehicle(String id);

  // --- New methods for vehicle locations ---

  // Get current locations for all relevant vehicles
  // Returns a map where key is vehicleId and value is LatLng.
  Future<Map<String, LatLng>> getVehicleLocations();

  // Simulate/trigger an update for a specific vehicle's location.
  // In a real system, this might not exist if locations are pushed via a stream.
  // For our mock, this will change a vehicle's location and return all current locations.
  Future<Map<String, LatLng>> triggerVehicleLocationUpdate(String vehicleId);
}
