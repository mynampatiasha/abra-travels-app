// File: lib/features/admin/driver_management/data/repositories/mock_driver_repository_impl.dart
// Mock implementation of DriverRepository for local development and testing.

import 'dart:async';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:abra_fleet/features/admin/driver_management/domain/entities/driver_entity.dart';
import 'package:abra_fleet/features/admin/driver_management/domain/repositories/driver_repository.dart';

class MockDriverRepositoryImpl implements DriverRepository {
  // In-memory list to store drivers
  final List<Driver> _mockDrivers = [
    Driver(id: 'd001', name: 'Johnathan Doe', email: 'john.doe@example.com', phoneNumber: '555-1234', licenseNumber: 'DLX12345', status: 'Active', assignedVehicleId: 'v001', licenseExpiryDate: DateTime(2026, 12, 31)),
    Driver(id: 'd002', name: 'Jane A. Smith', email: 'jane.smith@example.com', phoneNumber: '555-5678', licenseNumber: 'DLY67890', status: 'On Leave', licenseExpiryDate: DateTime(2025, 6, 15)),
    Driver(id: 'd003', name: 'Mike P. Brown', email: 'mike.brown@example.com', phoneNumber: '555-9012', licenseNumber: 'DLZ24680', status: 'Active', assignedVehicleId: 'v005', licenseExpiryDate: DateTime(2027, 3, 22)),
    Driver(id: 'd004', name: 'Sarah Wilson', email: 'sarah.wilson@example.com', phoneNumber: '555-3456', licenseNumber: 'DLA13579', status: 'Inactive', licenseExpiryDate: DateTime(2024, 8, 10)),
  ];
  int _nextIdCounter = 5; // To generate unique IDs for new drivers

  // Simulate network delay
  Future<void> _simulateDelay() async {
    await Future.delayed(const Duration(milliseconds: 400));
  }

  @override
  Future<Driver> addDriver(Driver driver) async {
    await _simulateDelay();
    final newDriverWithId = driver.copyWith(
      id: 'd${(_nextIdCounter++).toString().padLeft(3, '0')}',
    );
    _mockDrivers.add(newDriverWithId);
    debugPrint('[MockDriverRepo] Added: ${newDriverWithId.name}');
    return newDriverWithId;
  }

  @override
  Future<void> deleteDriver(String id) async {
    await _simulateDelay();
    final initialLength = _mockDrivers.length;
    _mockDrivers.removeWhere((driver) => driver.id == id);
    if (_mockDrivers.length < initialLength) {
      debugPrint('[MockDriverRepo] Deleted driver with ID: $id');
    } else {
      debugPrint('[MockDriverRepo] Driver with ID: $id not found for deletion.');
      // throw Exception('Driver with ID $id not found'); // Optional: throw error
    }
  }

  @override
  Future<Driver?> getDriverById(String id) async {
    await _simulateDelay();
    try {
      final driver = _mockDrivers.firstWhere((driver) => driver.id == id);
      debugPrint('[MockDriverRepo] Found driver by ID: ${driver.name}');
      return driver;
    } catch (e) {
      debugPrint('[MockDriverRepo] Driver with ID: $id not found.');
      return null;
    }
  }

  @override
  Future<List<Driver>> getDrivers() async {
    await _simulateDelay();
    debugPrint('[MockDriverRepo] Returning ${_mockDrivers.length} drivers.');
    return List<Driver>.from(_mockDrivers); // Return a copy
  }

  @override
  Future<void> updateDriver(Driver driver) async {
    await _simulateDelay();
    final index = _mockDrivers.indexWhere((d) => d.id == driver.id);
    if (index != -1) {
      _mockDrivers[index] = driver;
      debugPrint('[MockDriverRepo] Updated driver: ${driver.name}');
    } else {
      debugPrint('[MockDriverRepo] Driver with ID: ${driver.id} not found for update.');
      // throw Exception('Driver with ID ${driver.id} not found for update'); // Optional
    }
  }
}
