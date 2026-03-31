// File: lib/features/driver/trip_history/presentation/providers/trip_log_provider.dart
// Provider for managing driver's trip log state using ChangeNotifier.

import 'package:flutter/material.dart';
import 'package:abra_fleet/features/driver/trip_history/domain/entities/trip_log_entity.dart';
import 'package:abra_fleet/features/driver/trip_history/domain/repositories/trip_log_repository.dart';
// Import the mock implementation for now.
import 'package:abra_fleet/features/driver/trip_history/data/repositories/mock_trip_log_repository_impl.dart';

// Assuming DataState enum is defined in a shared location or one of the other providers.
// If not, you might need to define it here or import it.
// For this example, let's assume it's similar to what we used before.
// If you have a common DataState, import that. Otherwise:
enum DataState { initial, loading, loaded, error } // Define if not shared

class TripLogProvider extends ChangeNotifier {
  final TripLogRepository _tripLogRepository;
  final String? _driverId; // To fetch logs for a specific driver

  TripLogProvider({TripLogRepository? tripLogRepository, String? driverId})
      : _tripLogRepository = tripLogRepository ?? MockTripLogRepositoryImpl(),
        _driverId = driverId { // In a real app, driverId would be crucial
    // Optionally, fetch trip logs when the provider is created.
    // fetchTripLogs();
  }

  List<TripLogEntity> _tripLogs = [];
  DataState _state = DataState.initial;
  String? _errorMessage;

  // Getters for UI to access state
  List<TripLogEntity> get tripLogs => _tripLogs;
  DataState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == DataState.loading;

  // --- Methods to interact with the repositories ---

  Future<void> fetchTripLogs() async {
    _state = DataState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      // Pass driverId if your repositories's getTripLogs method expects it.
      // Our mock currently ignores it but a real API would use it.
      _tripLogs = await _tripLogRepository.getTripLogs(driverId: _driverId);
      _state = DataState.loaded;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst("Exception: ", "");
      _state = DataState.error;
      debugPrint('Error fetching trip logs: $_errorMessage');
    }
    notifyListeners();
  }

  Future<bool> addTripLog(TripLogEntity tripLog) async {
    // This method will be called by DriverTripReportingScreen after a trip ends.
    _state = DataState.loading; // Or a specific 'adding' state
    _errorMessage = null;
    // notifyListeners(); // Optional for immediate loading UI

    try {
      // The tripLog entity should be fully formed by DriverTripReportingScreen
      // including start/end times, odometer readings, notes, vehicle info.
      // The repositories (and backend) might assign a final ID.
      TripLogEntity addedTripLog = await _tripLogRepository.addTripLog(tripLog);

      // Add to the beginning of the list to show newest first, or re-fetch.
      // For simplicity, adding and then re-sorting (if repo doesn't return sorted).
      // Or, if addTripLog in repo adds it sorted / a re-fetch happens, this isn't needed.
      _tripLogs.insert(0, addedTripLog); // Assuming newest first is desired
      _tripLogs.sort((a, b) => b.startTime.compareTo(a.startTime)); // Ensure sort order

      _state = DataState.loaded;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst("Exception: ", "");
      _state = DataState.error;
      debugPrint('Error adding trip log: $_errorMessage');
      notifyListeners();
      return false;
    }
  }

  // Method to find a trip log by ID from the current list (if needed for details screen)
  TripLogEntity? getTripLogFromListById(String id) {
    try {
      return _tripLogs.firstWhere((log) => log.id == id);
    } catch (e) {
      return null; // Not found
    }
  }
}
