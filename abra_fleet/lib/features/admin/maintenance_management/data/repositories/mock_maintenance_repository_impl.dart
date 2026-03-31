// File: lib/features/admin/maintenance_management/data/repositories/mock_maintenance_repository_impl.dart
// Mock implementation of MaintenanceRepository for local development and testing.

import 'dart:async';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:abra_fleet/features/admin/maintenance_management/domain/entities/maintenance_task_entity.dart';
import 'package:abra_fleet/features/admin/maintenance_management/domain/repositories/maintenance_repository.dart';

class MockMaintenanceRepositoryImpl implements MaintenanceRepository {
  // In-memory list to store maintenance tasks
  final List<MaintenanceTaskEntity> _mockTasks = [
    MaintenanceTaskEntity(
      id: 'mt001',
      vehicleId: 'v001',
      vehicleName: 'Cargo Van 1',
      taskDescription: 'Regular Oil Change & Filter Replacement',
      scheduledDate: DateTime.now().add(const Duration(days: 7)),
      status: MaintenanceStatus.upcoming,
      priority: MaintenancePriority.medium,
    ),
    MaintenanceTaskEntity(
        id: 'mt002',
        vehicleId: 'v002',
        vehicleName: 'Sedan Alpha',
        taskDescription: 'Brake Pad Inspection and Replacement',
        scheduledDate: DateTime.now().subtract(const Duration(days: 2)), // Past due
        status: MaintenanceStatus.overdue,
        priority: MaintenancePriority.high,
        notes: 'Driver reported squeaking noises.'
    ),
    MaintenanceTaskEntity(
        id: 'mt003',
        vehicleId: 'v003',
        vehicleName: 'Pickup Truck 03',
        taskDescription: 'Tire Rotation and Pressure Check',
        scheduledDate: DateTime.now().add(const Duration(days: 1)),
        status: MaintenanceStatus.inProgress,
        priority: MaintenancePriority.medium,
        assignedMechanic: 'Workshop B'
    ),
    MaintenanceTaskEntity(
        id: 'mt004',
        vehicleId: 'v001',
        vehicleName: 'Cargo Van 1',
        taskDescription: 'Annual Service Check',
        scheduledDate: DateTime.now().subtract(const Duration(days: 30)),
        completionDate: DateTime.now().subtract(const Duration(days: 28)),
        status: MaintenanceStatus.completed,
        priority: MaintenancePriority.low,
        cost: 150.00,
        notes: 'All checks passed.'
    ),
  ];
  int _nextIdCounter = 5; // To generate unique IDs for new tasks

  // Simulate network delay
  Future<void> _simulateDelay({int milliseconds = 350}) async {
    await Future.delayed(Duration(milliseconds: milliseconds));
  }

  @override
  Future<MaintenanceTaskEntity> addMaintenanceTask(MaintenanceTaskEntity task) async {
    await _simulateDelay();
    final newTaskWithId = task.copyWith(
      id: 'mt${(_nextIdCounter++).toString().padLeft(3, '0')}',
    );
    _mockTasks.add(newTaskWithId);
    debugPrint('[MockMaintenanceRepo] Added Task: ${newTaskWithId.taskDescription} for ${newTaskWithId.vehicleName}');
    return newTaskWithId;
  }

  @override
  Future<void> deleteMaintenanceTask(String id) async {
    await _simulateDelay();
    final initialLength = _mockTasks.length;
    _mockTasks.removeWhere((task) => task.id == id);
    if (_mockTasks.length < initialLength) {
      debugPrint('[MockMaintenanceRepo] Deleted task with ID: $id');
    } else {
      debugPrint('[MockMaintenanceRepo] Task with ID: $id not found for deletion.');
      // throw Exception('Task with ID $id not found'); // Optional
    }
  }

  @override
  Future<MaintenanceTaskEntity?> getMaintenanceTaskById(String id) async {
    await _simulateDelay();
    try {
      final task = _mockTasks.firstWhere((task) => task.id == id);
      debugPrint('[MockMaintenanceRepo] Found task by ID: ${task.taskDescription}');
      return task;
    } catch (e) {
      debugPrint('[MockMaintenanceRepo] Task with ID: $id not found.');
      return null;
    }
  }

  @override
  Future<List<MaintenanceTaskEntity>> getMaintenanceTasks() async {
    await _simulateDelay(milliseconds: 550);
    debugPrint('[MockMaintenanceRepo] Returning ${_mockTasks.length} maintenance tasks.');
    return List<MaintenanceTaskEntity>.from(_mockTasks); // Return a copy
  }

  @override
  Future<void> updateMaintenanceTask(MaintenanceTaskEntity task) async {
    await _simulateDelay();
    final index = _mockTasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _mockTasks[index] = task;
      debugPrint('[MockMaintenanceRepo] Updated task: ${task.taskDescription}');
    } else {
      debugPrint('[MockMaintenanceRepo] Task with ID: ${task.id} not found for update.');
      // throw Exception('Task with ID ${task.id} not found for update'); // Optional
    }
  }
}
