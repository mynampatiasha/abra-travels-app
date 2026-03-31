import 'package:flutter/foundation.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../services/mongodb_service.dart';

class MongoDBProvider with ChangeNotifier {
  final MongoDBService _mongoDBService = MongoDBService();
  bool _isLoading = false;
  String? _error;

  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // Set error message
  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  // Check database connection
  Future<bool> checkConnection() async {
    try {
      _setLoading(true);
      await _mongoDBService.database;
      _setError(null);
      return true;
    } catch (e) {
      _setError('Failed to connect to MongoDB: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // User Operations
  Future<bool> createUser(Map<String, dynamic> userData) async {
    try {
      _setLoading(true);
      await _mongoDBService.insertUser(userData);
      _setError(null);
      return true;
    } catch (e) {
      _setError('Failed to create user: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Driver Operations
  Future<bool> addDriver(Map<String, dynamic> driverData) async {
    try {
      _setLoading(true);
      await _mongoDBService.insertDriver(driverData);
      _setError(null);
      return true;
    } catch (e) {
      _setError('Failed to add driver: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<List<Map<String, dynamic>>> getDrivers() async {
    try {
      _setLoading(true);
      final drivers = await _mongoDBService.getAllDrivers();
      _setError(null);
      return drivers;
    } catch (e) {
      _setError('Failed to fetch drivers: $e');
      return [];
    } finally {
      _setLoading(false);
    }
  }

  // Vehicle Operations
  Future<bool> addVehicle(Map<String, dynamic> vehicleData) async {
    try {
      _setLoading(true);
      await _mongoDBService.insertVehicle(vehicleData);
      _setError(null);
      return true;
    } catch (e) {
      _setError('Failed to add vehicle: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<List<Map<String, dynamic>>> getVehicles() async {
    try {
      _setLoading(true);
      final vehicles = await _mongoDBService.getAllVehicles();
      _setError(null);
      return vehicles;
    } catch (e) {
      _setError('Failed to fetch vehicles: $e');
      return [];
    } finally {
      _setLoading(false);
    }
  }

  // Clean up
  Future<void> disposeProvider() async {
    await _mongoDBService.close();
  }
}
