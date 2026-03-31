// File: lib/features/admin/driver_management/presentation/providers/driver_provider.dart
// Provider for managing driver state using Firebase Auth and Firestore.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Firebase removed - using HTTP API
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:abra_fleet/features/admin/driver_management/domain/entities/driver_entity.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:abra_fleet/app/config/api_config.dart';

// Enum to represent different states of data fetching
enum DataState { initial, loading, loaded, error }

class DriverProvider extends ChangeNotifier {
  // Firebase removed

  List<Driver> _drivers = [];
  DataState _state = DataState.initial;
  String? _errorMessage;

  // Getters for UI to access state
  List<Driver> get drivers => _drivers;
  DataState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == DataState.loading;

  // Fetch all drivers from HTTP API
  Future<void> fetchDrivers() async {
    _state = DataState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      // ✅ HTTP API: Get drivers from backend (FIXED: use correct endpoint)
      final response = await ApiService().get('/api/admin/drivers');
      final driversData = List<Map<String, dynamic>>.from(response['data'] ?? []);
      
      _drivers = driversData
          .map((data) => Driver.fromMap(data, data['_id'] ?? data['id']))
          .toList();

      _state = DataState.loaded;
    } catch (e) {
      _errorMessage = 'Failed to fetch drivers: $e';
      _state = DataState.error;
      debugPrint('Error fetching drivers: $e');
    }
    notifyListeners();
  }

  // Fetch current driver's profile (for driver role)
  Future<Driver?> getDriverProfile() async {
    try {
      debugPrint('🔍 Fetching driver profile...');
      final response = await ApiService().get('/api/drivers/profile');
      
      debugPrint('📦 Raw response: $response');
      
      if (response['success'] == true && response['data'] != null) {
        final driverData = response['data'];
        debugPrint('✅ Driver profile data received:');
        debugPrint('   - Raw data keys: ${driverData.keys.toList()}');
        debugPrint('   - Name (flat): ${driverData['name']}');
        debugPrint('   - Email (flat): ${driverData['email']}');
        debugPrint('   - Phone (flat): ${driverData['phoneNumber']}');
        debugPrint('   - PersonalInfo: ${driverData['personalInfo']}');
        debugPrint('   - License: ${driverData['license']}');
        debugPrint('   - AssignedVehicle: ${driverData['assignedVehicle']}');
        debugPrint('   - Status: ${driverData['status']}');
        debugPrint('   - Driver ID: ${driverData['driverId']}');
        
        final driverId = driverData['_id'] ?? driverData['userId'] ?? driverData['id'] ?? driverData['driverId'];
        debugPrint('   - Using ID: $driverId');
        
        final driver = Driver.fromMap(driverData, driverId.toString());
        debugPrint('✅ Driver object created successfully:');
        debugPrint('   - Name: "${driver.name}"');
        debugPrint('   - Email: "${driver.email}"');
        debugPrint('   - Phone: "${driver.phoneNumber}"');
        debugPrint('   - License: "${driver.licenseNumber}"');
        debugPrint('   - Vehicle: "${driver.assignedVehicleId}"');
        debugPrint('   - Status: "${driver.status}"');
        
        return driver;
      } else {
        debugPrint('❌ Failed to fetch driver profile: ${response['message']}');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching driver profile: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  Future<bool> createDriver({
  required String name,
  required String email,
  required String phone,
  String? licenseNumber,
  String? address,
  required String password,
}) async {
  _state = DataState.loading;
  _errorMessage = null;
  notifyListeners();

  try {
    // Get JWT token from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    
    if (token == null || token.isEmpty) {
      throw Exception('Not authenticated. Please login again.');
    }

    final apiService = ApiService();
    final response = await apiService.post('/api/admin/drivers/create', body: {
      'name': name.trim(),
      'email': email.trim(),
      'phoneNumber': phone.trim(),
      'licenseNumber': licenseNumber?.trim(),
      'address': address?.trim(),
      'password': password.trim(),
      'role': 'driver',
      'status': 'Active',
      'createdAt': DateTime.now().toIso8601String(), // ✅ FIXED: Convert to ISO string
    });

    if (response['success'] == true) {
      final driverId = response['data']?['_id'] ?? response['data']?['id'];
      
      // Update local state
      final newDriver = Driver.fromMap(
        {
          'name': name.trim(),
          'email': email.trim(),
          'phoneNumber': phone.trim(),
          'licenseNumber': licenseNumber?.trim(),
          'address': address?.trim(),
          'role': 'driver',
          'status': 'Active',
          'createdAt': DateTime.now().toIso8601String(), // ✅ FIXED
        },
        driverId,
      );
      _drivers.add(newDriver);
      
      _state = DataState.loaded;
      notifyListeners();
      
      debugPrint('Driver created successfully: ${newDriver.email}');
      return true;
    } else {
      throw Exception(response['message'] ?? 'Failed to create driver');
    }
  } catch (e) {
    _errorMessage = 'Failed to create driver: $e';
    _state = DataState.error;
    debugPrint('Error creating driver: $e');
    notifyListeners();
    return false;
  }
}

  // Update an existing driver
  Future<bool> updateDriver(Driver driver) async {
    _state = DataState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      // ✅ HTTP API: Update driver via backend (FIXED: use correct endpoint)
      final driverData = driver.toMap();
      driverData['updatedAt'] = DateTime.now().toIso8601String();
      driverData.remove('createdAt'); // Don't update creation time
      
      await ApiService().put('/api/admin/drivers/${driver.id}', body: driverData);
      
      // Update local state
      final index = _drivers.indexWhere((d) => d.id == driver.id);
      if (index != -1) {
        _drivers[index] = driver;
      }
      
      _state = DataState.loaded;
      notifyListeners();
      
      debugPrint('Driver updated successfully: ${driver.email}');
      return true;
      
    } catch (e) {
      _errorMessage = 'Failed to update driver: $e';
      _state = DataState.error;
      debugPrint('Error updating driver: $e');
      notifyListeners();
      return false;
    }
  }

  // Delete a driver
  Future<bool> deleteDriver(String driverId) async {
    _state = DataState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      // ✅ HTTP API: Delete driver via backend (FIXED: use correct endpoint)
      await ApiService().delete('/api/admin/drivers/$driverId');
      
      // Update local state
      _drivers.removeWhere((d) => d.id == driverId);
      
      _state = DataState.loaded;
      notifyListeners();
      
      debugPrint('Driver deleted successfully: $driverId');
      return true;
      
    } catch (e) {
      _errorMessage = 'Failed to delete driver: $e';
      _state = DataState.error;
      debugPrint('Error deleting driver: $e');
      notifyListeners();
      return false;
    }
  }

  // Get driver by ID from local list
  Driver? getDriverFromListById(String id) {
    try {
      return _drivers.firstWhere((driver) => driver.id == id);
    } catch (e) {
      debugPrint('Driver not found: $id');
      return null;
    }
  }

  // Legacy method for backward compatibility
  Future<bool> addDriver(Driver driver) async {
    // This method is kept for backward compatibility with existing screens
    // In practice, you should use createDriver() for new drivers with auth
    _state = DataState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final driverData = driver.toMap();
      driverData['role'] = 'driver';
      driverData['createdAt'] = DateTime.now().toIso8601String();
      driverData['updatedAt'] = DateTime.now().toIso8601String();
      
      // ✅ HTTP API: Create driver via backend (FIXED: use correct endpoint)
      await ApiService().post('/api/admin/drivers', body: driverData);
      _drivers.add(driver);
      _state = DataState.loaded;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to add driver: $e';
      _state = DataState.error;
      notifyListeners();
      return false;
    }
  }



  // Clear error state
  void clearError() {
    _errorMessage = null;
    if (_state == DataState.error) {
      _state = DataState.loaded;
      notifyListeners();
    }
  }

  // Refresh drivers data
  Future<void> refreshDrivers() async {
    await fetchDrivers();
  }
}