// File: lib/features/admin/vehicle_management/presentation/providers/vehicle_provider.dart
// FIXED VERSION - Counts individual documents, not vehicles

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:abra_fleet/features/admin/vehicle_management/domain/entities/vehicle_entity.dart';
import 'package:abra_fleet/features/admin/vehicle_management/domain/repositories/vehicle_repository.dart';
import 'package:abra_fleet/features/admin/vehicle_management/data/repositories/api_vehicle_repository_impl.dart';

enum VehicleDataState { initial, loading, loaded, error }

class VehicleProvider extends ChangeNotifier {
  final VehicleRepository _vehicleRepository;

  VehicleProvider({VehicleRepository? vehicleRepository})
      : _vehicleRepository = vehicleRepository ?? ApiVehicleRepositoryImpl() {
    fetchVehiclesAndLocations();
  }

  List<Vehicle> _vehicles = [];
  VehicleDataState _vehicleListState = VehicleDataState.initial;
  String? _vehicleListErrorMessage;

  Map<String, LatLng> _vehicleLocations = {};
  VehicleDataState _locationState = VehicleDataState.initial;
  String? _locationErrorMessage;

  // Getters
  List<Vehicle> get vehicles => _vehicles;
  VehicleDataState get vehicleListState => _vehicleListState;
  String? get vehicleListErrorMessage => _vehicleListErrorMessage;
  bool get isLoadingVehicles => _vehicleListState == VehicleDataState.loading;

  Map<String, LatLng> get vehicleLocations => _vehicleLocations;
  VehicleDataState get locationState => _locationState;
  String? get locationErrorMessage => _locationErrorMessage;
  bool get isLoadingLocations => _locationState == VehicleDataState.loading;

  Future<void> fetchVehiclesAndLocations() async {
    _vehicleListState = VehicleDataState.loading;
    _locationState = VehicleDataState.loading;
    _vehicleListErrorMessage = null;
    _locationErrorMessage = null;
    notifyListeners();

    try {
      _vehicles = await _vehicleRepository.getVehicles();
      _vehicleListState = VehicleDataState.loaded;
      _vehicleLocations = await _vehicleRepository.getVehicleLocations();
      _locationState = VehicleDataState.loaded;
    } catch (e) {
      final errorMessage = e.toString().replaceFirst("Exception: ", "");
      _vehicleListErrorMessage = errorMessage;
      _vehicleListState = VehicleDataState.error;
      _locationErrorMessage = errorMessage;
      _locationState = VehicleDataState.error;
      debugPrint('Error fetching vehicles and/or locations: $errorMessage');
    }
    notifyListeners();
  }

  Future<void> fetchVehicles() async {
    _vehicleListState = VehicleDataState.loading;
    _vehicleListErrorMessage = null;
    notifyListeners();

    try {
      _vehicles = await _vehicleRepository.getVehicles();
      _vehicleListState = VehicleDataState.loaded;
    } catch (e) {
      _vehicleListErrorMessage = e.toString().replaceFirst("Exception: ", "");
      _vehicleListState = VehicleDataState.error;
      debugPrint('Error fetching vehicles: $_vehicleListErrorMessage');
    }
    notifyListeners();
  }

  Future<void> fetchVehicleLocations() async {
    _locationState = VehicleDataState.loading;
    _locationErrorMessage = null;
    notifyListeners();
    try {
      _vehicleLocations = await _vehicleRepository.getVehicleLocations();
      _locationState = VehicleDataState.loaded;
    } catch (e) {
      _locationErrorMessage = e.toString().replaceFirst("Exception: ", "");
      _locationState = VehicleDataState.error;
      debugPrint('Error fetching vehicle locations: $_locationErrorMessage');
    }
    notifyListeners();
  }

  Future<void> triggerVehicleLocationUpdate(String vehicleId) async {
    try {
      _vehicleLocations = await _vehicleRepository.triggerVehicleLocationUpdate(vehicleId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error triggering vehicle location update: $e');
    }
  }

  Future<bool> addVehicle(Vehicle vehicle) async {
    _vehicleListState = VehicleDataState.loading;
    _vehicleListErrorMessage = null;
    notifyListeners();

    try {
      Vehicle addedVehicle = await _vehicleRepository.addVehicle(vehicle);
      _vehicles.add(addedVehicle);
      await fetchVehicleLocations();
      _vehicleListState = VehicleDataState.loaded;
      return true;
    } catch (e) {
      _vehicleListErrorMessage = e.toString().replaceFirst("Exception: ", "");
      _vehicleListState = VehicleDataState.error;
      debugPrint('Error adding vehicle: $_vehicleListErrorMessage');
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateVehicle(Vehicle vehicle) async {
    _vehicleListState = VehicleDataState.loading;
    _vehicleListErrorMessage = null;
    notifyListeners();

    try {
      await _vehicleRepository.updateVehicle(vehicle);
      final index = _vehicles.indexWhere((v) => v.id == vehicle.id);
      if (index != -1) {
        _vehicles[index] = vehicle;
      }
      _vehicleListState = VehicleDataState.loaded;
      notifyListeners();
      return true;
    } catch (e) {
      _vehicleListErrorMessage = e.toString().replaceFirst("Exception: ", "");
      _vehicleListState = VehicleDataState.error;
      debugPrint('Error updating vehicle: $_vehicleListErrorMessage');
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteVehicle(String id) async {
    _vehicleListState = VehicleDataState.loading;
    _vehicleListErrorMessage = null;
    notifyListeners();

    try {
      await _vehicleRepository.deleteVehicle(id);
      _vehicles.removeWhere((v) => v.id == id);
      _vehicleLocations.remove(id);
      _vehicleListState = VehicleDataState.loaded;
      notifyListeners();
      return true;
    } catch (e) {
      _vehicleListErrorMessage = e.toString().replaceFirst("Exception: ", "");
      _vehicleListState = VehicleDataState.error;
      debugPrint('Error deleting vehicle: $_vehicleListErrorMessage');
      notifyListeners();
      return false;
    }
  }

  Vehicle? getVehicleFromListById(String id) {
    try {
      return _vehicles.firstWhere((vehicle) => vehicle.id == id);
    } catch (e) {
      return null;
    }
  }

  // ============================================
  // 🔧 FIXED: Count individual documents, not vehicles
  // ============================================
  
  /// Check for expired/expiring documents and return counts
  /// NOW counts individual DOCUMENTS instead of VEHICLES
  Map<String, int> getDocumentExpiryStatus() {
    int expiredCount = 0;
    int expiringSoonCount = 0;
    
    debugPrint('🔍 ========== DOCUMENT EXPIRY CHECK ==========');
    debugPrint('📊 Total Vehicles: ${_vehicles.length}');
    
    for (var vehicle in _vehicles) {
      // Count vehicle documents
      for (var doc in vehicle.documents) {
        if (doc.isExpired) {
          expiredCount++;
          debugPrint('❌ EXPIRED: ${vehicle.licensePlate} - ${doc.documentType}: ${doc.documentName}');
        } else if (doc.isExpiringSoon) {
          expiringSoonCount++;
          debugPrint('⏰ EXPIRING: ${vehicle.licensePlate} - ${doc.documentType}: ${doc.documentName} (${doc.daysUntilExpiry} days)');
        }
      }
      
      // Count driver documents
      for (var doc in vehicle.driverDocuments) {
        if (doc.isExpired) {
          expiredCount++;
          debugPrint('❌ EXPIRED (Driver): ${vehicle.licensePlate} - ${doc.documentType}: ${doc.documentName}');
        } else if (doc.isExpiringSoon) {
          expiringSoonCount++;
          debugPrint('⏰ EXPIRING (Driver): ${vehicle.licensePlate} - ${doc.documentType}: ${doc.documentName}');
        }
      }
    }
    
    debugPrint('📈 TOTAL EXPIRED: $expiredCount');
    debugPrint('📈 TOTAL EXPIRING SOON: $expiringSoonCount');
    debugPrint('📈 TOTAL ISSUES: ${expiredCount + expiringSoonCount}');
    debugPrint('🔍 ========================================\n');
    
    return {
      'expired': expiredCount,
      'expiringSoon': expiringSoonCount,
      'total': expiredCount + expiringSoonCount,
    };
  }

  /// Get detailed list of all expired documents with vehicle info
  List<Map<String, dynamic>> getExpiredDocumentsList() {
    List<Map<String, dynamic>> expiredDocs = [];
    
    for (var vehicle in _vehicles) {
      // Vehicle documents
      for (var doc in vehicle.documents) {
        if (doc.isExpired) {
          final daysOverdue = doc.expiryDate != null 
              ? DateTime.now().difference(doc.expiryDate!).inDays 
              : 0;
          expiredDocs.add({
            'vehicleId': vehicle.id,
            'vehicleReg': vehicle.licensePlate,
            'documentType': doc.documentType,
            'documentName': doc.documentName,
            'expiryDate': doc.expiryDate,
            'daysOverdue': daysOverdue,
            'isDriverDoc': false,
          });
        }
      }
      
      // Driver documents
      for (var doc in vehicle.driverDocuments) {
        if (doc.isExpired) {
          final daysOverdue = doc.expiryDate != null 
              ? DateTime.now().difference(doc.expiryDate!).inDays 
              : 0;
          expiredDocs.add({
            'vehicleId': vehicle.id,
            'vehicleReg': vehicle.licensePlate,
            'documentType': doc.documentType,
            'documentName': doc.documentName,
            'expiryDate': doc.expiryDate,
            'daysOverdue': daysOverdue,
            'isDriverDoc': true,
          });
        }
      }
    }
    
    // Sort by days overdue (most overdue first)
    expiredDocs.sort((a, b) => (b['daysOverdue'] as int).compareTo(a['daysOverdue'] as int));
    
    return expiredDocs;
  }

  /// Get detailed list of all expiring soon documents with vehicle info
  List<Map<String, dynamic>> getExpiringSoonDocumentsList() {
    List<Map<String, dynamic>> expiringSoonDocs = [];
    
    for (var vehicle in _vehicles) {
      // Vehicle documents
      for (var doc in vehicle.documents) {
        if (doc.isExpiringSoon && !doc.isExpired) {
          final daysRemaining = doc.expiryDate != null 
              ? doc.expiryDate!.difference(DateTime.now()).inDays 
              : 0;
          expiringSoonDocs.add({
            'vehicleId': vehicle.id,
            'vehicleReg': vehicle.licensePlate,
            'documentType': doc.documentType,
            'documentName': doc.documentName,
            'expiryDate': doc.expiryDate,
            'daysRemaining': daysRemaining,
            'isDriverDoc': false,
          });
        }
      }
      
      // Driver documents
      for (var doc in vehicle.driverDocuments) {
        if (doc.isExpiringSoon && !doc.isExpired) {
          final daysRemaining = doc.expiryDate != null 
              ? doc.expiryDate!.difference(DateTime.now()).inDays 
              : 0;
          expiringSoonDocs.add({
            'vehicleId': vehicle.id,
            'vehicleReg': vehicle.licensePlate,
            'documentType': doc.documentType,
            'documentName': doc.documentName,
            'expiryDate': doc.expiryDate,
            'daysRemaining': daysRemaining,
            'isDriverDoc': true,
          });
        }
      }
    }
    
    // Sort by days remaining (soonest first)
    expiringSoonDocs.sort((a, b) => (a['daysRemaining'] as int).compareTo(b['daysRemaining'] as int));
    
    return expiringSoonDocs;
  }

  // ============================================
  // LEGACY METHODS (Keep for backward compatibility)
  // ============================================

  /// Get total count of vehicles with document issues
  int get vehiclesWithDocumentIssuesCount {
    return _vehicles.where((v) => v.hasExpiredDocuments || v.hasExpiringSoonDocuments).length;
  }

  /// Get list of vehicles with expired documents
  List<Vehicle> get vehiclesWithExpiredDocuments {
    return _vehicles.where((v) => v.hasExpiredDocuments).toList();
  }

  /// Get list of vehicles with expiring soon documents
  List<Vehicle> get vehiclesWithExpiringSoonDocuments {
    return _vehicles.where((v) => v.hasExpiringSoonDocuments).toList();
  }
}