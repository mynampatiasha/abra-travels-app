// File: lib/features/admin/vehicle_management/data/repositories/mock_vehicle_repository_impl.dart
// Mock implementation of VehicleRepository for local development and testing.

import 'dart:async';
import 'dart:math'; // For random location changes
import 'package:abra_fleet/features/admin/vehicle_management/domain/entities/vehicle_entity.dart';
import 'package:abra_fleet/features/admin/vehicle_management/domain/repositories/vehicle_repository.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode or similar checks if needed
import 'package:latlong2/latlong.dart'; // For LatLng

class MockVehicleRepositoryImpl implements VehicleRepository {
  final List<Vehicle> _mockVehicles = [
    Vehicle(id: 'v001', name: 'Cargo Van 1', model: 'Ford Transit', licensePlate: 'AB-123-CD', status: 'Active', assignedDriver: 'John Doe'),
    Vehicle(id: 'v002', name: 'Sedan Alpha', model: 'Toyota Camry', licensePlate: 'XY-789-ZW', status: 'Maintenance'),
    Vehicle(id: 'v003', name: 'Pickup Truck 03', model: 'RAM 1500', licensePlate: 'GH-456-JK', status: 'Active', assignedDriver: 'Jane Smith'),
    Vehicle(id: 'v004', name: 'Minibus Bravo', model: 'Mercedes Sprinter', licensePlate: 'MN-012-PQ', status: 'Inactive'),
    Vehicle(id: 'v006', name: 'Heavy Truck Zeta', model: 'Volvo FH16', licensePlate: 'QR-678-ST', status: 'Active', assignedDriver: 'Sarah Wilson'),
  ];
  int _nextIdCounter = 7;

  final Map<String, LatLng> _vehicleLocations = {
    'v001': const LatLng(12.9716, 77.5946),
    'v002': const LatLng(12.9800, 77.6000),
    'v003': const LatLng(12.9650, 77.5850),
    'v006': const LatLng(12.9750, 77.5750),
  };
  final Random _random = Random();

  Future<void> _simulateDelay({int milliseconds = 300}) async {
    await Future.delayed(Duration(milliseconds: milliseconds));
  }

  @override
  Future<Vehicle> addVehicle(Vehicle vehicle) async {
    await _simulateDelay();
    final newVehicleWithId = vehicle.copyWith(
      id: 'v${(_nextIdCounter++).toString().padLeft(3, '0')}',
    );
    _mockVehicles.add(newVehicleWithId);
    _vehicleLocations[newVehicleWithId.id] = LatLng(
        12.9700 + (_random.nextDouble() * 0.05 - 0.025),
        77.5900 + (_random.nextDouble() * 0.05 - 0.025)
    );
    debugPrint('[MockVehicleRepo] Added: ${newVehicleWithId.name}');
    return newVehicleWithId;
  }

  @override
  Future<void> deleteVehicle(String id) async {
    await _simulateDelay();
    final initialLength = _mockVehicles.length;
    _mockVehicles.removeWhere((vehicle) => vehicle.id == id);
    _vehicleLocations.remove(id);
    if (_mockVehicles.length < initialLength) {
      debugPrint('[MockVehicleRepo] Deleted vehicle with ID: $id');
    } else {
      debugPrint('[MockVehicleRepo] Vehicle with ID: $id not found for deletion.');
    }
  }

  @override
  Future<Vehicle?> getVehicleById(String id) async {
    await _simulateDelay();
    try {
      final vehicle = _mockVehicles.firstWhere((vehicle) => vehicle.id == id);
      debugPrint('[MockVehicleRepo] Found vehicle by ID: ${vehicle.name}');
      return vehicle;
    } catch (e) {
      debugPrint('[MockVehicleRepo] Vehicle with ID: $id not found.');
      return null;
    }
  }

  @override
  Future<List<Vehicle>> getVehicles() async {
    await _simulateDelay();
    debugPrint('[MockVehicleRepo] Returning ${_mockVehicles.length} vehicles.');
    return List<Vehicle>.from(_mockVehicles);
  }

  @override
  Future<void> updateVehicle(Vehicle vehicle) async {
    await _simulateDelay();
    final index = _mockVehicles.indexWhere((v) => v.id == vehicle.id);
    if (index != -1) {
      _mockVehicles[index] = vehicle;
      debugPrint('[MockVehicleRepo] Updated vehicle: ${vehicle.name}');
    } else {
      debugPrint('[MockVehicleRepo] Vehicle with ID: ${vehicle.id} not found for update.');
    }
  }

  @override
  Future<Map<String, LatLng>> getVehicleLocations() async {
    await _simulateDelay();
    debugPrint('[MockVehicleRepo] Returning ${_vehicleLocations.length} vehicle locations.');
    return Map<String, LatLng>.from(_vehicleLocations);
  }

  @override
  Future<Map<String, LatLng>> triggerVehicleLocationUpdate(String vehicleId) async {
    await _simulateDelay(milliseconds: 100);
    if (_vehicleLocations.containsKey(vehicleId)) {
      LatLng currentLocation = _vehicleLocations[vehicleId]!;
      double latChange = (_random.nextDouble() * 0.005) - 0.0025;
      double lngChange = (_random.nextDouble() * 0.005) - 0.0025;
      _vehicleLocations[vehicleId] = LatLng(currentLocation.latitude + latChange, currentLocation.longitude + lngChange);
      debugPrint('[MockVehicleRepo] Simulated location update for $vehicleId to: ${_vehicleLocations[vehicleId]}');
    } else {
      debugPrint('[MockVehicleRepo] Cannot simulate location for $vehicleId: No initial location.');
    }
    return Map<String, LatLng>.from(_vehicleLocations);
  }
}
