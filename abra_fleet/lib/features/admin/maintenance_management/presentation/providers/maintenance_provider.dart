// File: lib/features/admin/maintenance_management/presentation/providers/maintenance_provider.dart
// Provider for managing maintenance task state using ChangeNotifier.

import 'package:flutter/material.dart';
import 'package:abra_fleet/features/admin/maintenance_management/domain/entities/maintenance_task_entity.dart';
import 'package:abra_fleet/features/admin/maintenance_management/domain/repositories/maintenance_repository.dart';
// Import the mock implementation for now.
import 'package:abra_fleet/features/admin/maintenance_management/data/repositories/mock_maintenance_repository_impl.dart';

// Re-using DataState enum or define a common one.
// Assuming DataState is available (e.g. from another provider or a common file)
// If not, uncomment and define here or in a shared location:
/*
enum DataState { initial, loading, loaded, error }
*/
// For self-containment, let's include it if not shared yet.
// Ensure this matches the definition in other providers or move to a common file.
enum DataState { initial, loading, loaded, error }

class MaintenanceProvider extends ChangeNotifier {
  final MaintenanceRepository _maintenanceRepository;

  MaintenanceProvider({MaintenanceRepository? maintenanceRepository})
      : _maintenanceRepository = maintenanceRepository ?? MockMaintenanceRepositoryImpl() {
    // Optionally, fetch tasks when the provider is created.
    // fetchMaintenanceTasks();
  }

  List<MaintenanceTaskEntity> _tasks = [];
  DataState _state = DataState.initial;
  String? _errorMessage;

  // Getters for UI to access state
  List<MaintenanceTaskEntity> get tasks => _tasks;
  DataState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == DataState.loading;

  // --- Methods to interact with the repositories ---

  Future<void> fetchMaintenanceTasks() async {
    _state = DataState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _tasks = await _maintenanceRepository.getMaintenanceTasks();
      _state = DataState.loaded;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst("Exception: ", "");
      _state = DataState.error;
      debugPrint('Error fetching maintenance tasks: $_errorMessage');
    }
    notifyListeners();
  }

  Future<bool> addMaintenanceTask(MaintenanceTaskEntity task) async {
    _state = DataState.loading;
    _errorMessage = null;
    // notifyListeners(); // Optional

    try {
      MaintenanceTaskEntity addedTask = await _maintenanceRepository.addMaintenanceTask(task);
      _tasks.add(addedTask);
      _state = DataState.loaded;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst("Exception: ", "");
      _state = DataState.error;
      debugPrint('Error adding maintenance task: $_errorMessage');
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateMaintenanceTask(MaintenanceTaskEntity task) async {
    _state = DataState.loading;
    _errorMessage = null;
    // notifyListeners(); // Optional

    try {
      await _maintenanceRepository.updateMaintenanceTask(task);
      final index = _tasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _tasks[index] = task;
      }
      _state = DataState.loaded;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst("Exception: ", "");
      _state = DataState.error;
      debugPrint('Error updating maintenance task: $_errorMessage');
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteMaintenanceTask(String id) async {
    _state = DataState.loading;
    _errorMessage = null;
    // notifyListeners(); // Optional

    try {
      await _maintenanceRepository.deleteMaintenanceTask(id);
      _tasks.removeWhere((t) => t.id == id);
      _state = DataState.loaded;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst("Exception: ", "");
      _state = DataState.error;
      debugPrint('Error deleting maintenance task: $_errorMessage');
      notifyListeners();
      return false;
    }
  }

  // Method to find a task by ID from the current list
  MaintenanceTaskEntity? getTaskFromListById(String id) {
    try {
      return _tasks.firstWhere((task) => task.id == id);
    } catch (e) {
      return null; // Not found
    }
  }
}
