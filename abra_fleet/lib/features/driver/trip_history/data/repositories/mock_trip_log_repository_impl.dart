// File: lib/features/driver/trip_history/data/repositories/mock_trip_log_repository_impl.dart
// Mock implementation of TripLogRepository for local development and testing.

import 'dart:async';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:abra_fleet/features/driver/trip_history/domain/entities/trip_log_entity.dart';
import 'package:abra_fleet/features/driver/trip_history/domain/repositories/trip_log_repository.dart';

class MockTripLogRepositoryImpl implements TripLogRepository {
  // In-memory list to store trip logs
  // For a mock, we can assume these are for a specific default driver or include driverId in TripLogEntity
  // Let's assume for now TripLogEntity might not have driverId, and this repo returns all for simplicity.
  // Or, if TripLogEntity has driverId, we can filter. Let's add a mock driverId.
  final String _mockDriverId = 'd001'; // Example driver ID for whom these logs belong

  final List<TripLogEntity> _mockTripLogs = [
    TripLogEntity(
      id: 'trip001',
      vehicleName: 'Cargo Van 1',
      vehicleLicensePlate: 'AB-123-CD',
      startTime: DateTime.now().subtract(const Duration(days: 1, hours: 4)),
      endTime: DateTime.now().subtract(const Duration(days: 1, hours: 1)),
      startOdometer: 12345.0,
      endOdometer: 12395.0,
      notes: 'Delivered all packages on time. Minor traffic on 5th Ave.',
      startLocation: 'Warehouse A',
      endLocation: 'City Center Hub',
    ),
    TripLogEntity(
      id: 'trip002',
      vehicleName: 'Delivery Bike 1',
      vehicleLicensePlate: 'EF-345-KL',
      startTime: DateTime.now().subtract(const Duration(days: 2, hours: 6)),
      endTime: DateTime.now().subtract(const Duration(days: 2, hours: 3, minutes: 30)),
      startOdometer: 5678.0,
      endOdometer: 5710.5,
      notes: 'Quick downtown deliveries.',
      startLocation: 'Downtown Dispatch',
      endLocation: 'Various Downtown Addresses',
    ),
    TripLogEntity(
      id: 'trip003',
      vehicleName: 'Cargo Van 1',
      vehicleLicensePlate: 'AB-123-CD',
      startTime: DateTime.now().subtract(const Duration(days: 3, hours: 2)),
      endTime: DateTime.now().subtract(const Duration(days: 3, hours: 0, minutes: 15)),
      startOdometer: 12200.0,
      endOdometer: 12265.0,
      startLocation: 'Main Depot',
      endLocation: 'North Suburbs Residential Area',
    ),
  ];
  int _nextTripIdCounter = 4; // To generate unique IDs for new trip logs

  // Simulate network delay
  Future<void> _simulateDelay({int milliseconds = 300}) async {
    await Future.delayed(Duration(milliseconds: milliseconds));
  }

  @override
  Future<TripLogEntity> addTripLog(TripLogEntity tripLog) async {
    await _simulateDelay();
    // In a real app, the tripLog passed might not have an ID if it's backend-generated.
    // For this mock, we'll assign one if not present, or use the one provided.
    final newTripLogWithId = tripLog.id.startsWith('trip_local_') || tripLog.id.isEmpty
        ? tripLog.copyWith(id: 'trip${(_nextTripIdCounter++).toString().padLeft(3, '0')}')
        : tripLog;

    _mockTripLogs.add(newTripLogWithId);
    // Sort by newest first after adding
    _mockTripLogs.sort((a, b) => b.startTime.compareTo(a.startTime));
    debugPrint('[MockTripLogRepo] Added Trip: ${newTripLogWithId.id} for ${newTripLogWithId.vehicleName}');
    return newTripLogWithId;
  }

  @override
  Future<List<TripLogEntity>> getTripLogs({String? driverId}) async {
    await _simulateDelay(milliseconds: 500);
    // For this mock, we'll ignore the driverId and return all logs,
    // or you could filter if your TripLogEntity contains a driverId.
    // Assuming the current list is for the logged-in mock driver.
    debugPrint('[MockTripLogRepo] Returning ${_mockTripLogs.length} trip logs.');
    return List<TripLogEntity>.from(_mockTripLogs); // Return a copy
  }

// getTripLogById might not be needed if details are shown from the list item
// But if you need to fetch a specific one by ID:
/*
  @override
  Future<TripLogEntity?> getTripLogById(String id) async {
    await _simulateDelay();
    try {
      final tripLog = _mockTripLogs.firstWhere((log) => log.id == id);
      debugPrint('[MockTripLogRepo] Found trip log by ID: ${tripLog.id}');
      return tripLog;
    } catch (e) {
      debugPrint('[MockTripLogRepo] Trip log with ID: $id not found.');
      return null;
    }
  }
  */
}
