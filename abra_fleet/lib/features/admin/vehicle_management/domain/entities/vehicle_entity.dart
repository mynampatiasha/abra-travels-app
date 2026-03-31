// File: lib/features/admin/vehicle_management/domain/entities/vehicle_entity.dart
// Defines the data structure for a Vehicle.

import 'package:flutter/foundation.dart';

class VehicleDocument {
  final String id;
  final String documentType; // 'registration', 'insurance', 'permit', 'fitness', etc.
  final String documentName;
  final String documentUrl;
  final DateTime uploadDate;
  final DateTime? expiryDate;
  final String uploadedBy;

  VehicleDocument({
    required this.id,
    required this.documentType,
    required this.documentName,
    required this.documentUrl,
    required this.uploadDate,
    this.expiryDate,
    required this.uploadedBy,
  });

  bool get isExpired => expiryDate != null && expiryDate!.isBefore(DateTime.now());
  bool get isExpiringSoon => expiryDate != null && 
      expiryDate!.isAfter(DateTime.now()) && 
      expiryDate!.isBefore(DateTime.now().add(const Duration(days: 30)));
  
  int? get daysUntilExpiry {
    if (expiryDate == null) return null;
    return expiryDate!.difference(DateTime.now()).inDays;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'documentType': documentType,
      'documentName': documentName,
      'documentUrl': documentUrl,
      'uploadDate': uploadDate.toIso8601String(),
      'expiryDate': expiryDate?.toIso8601String(),
      'uploadedBy': uploadedBy,
    };
  }

  factory VehicleDocument.fromJson(Map<String, dynamic> json) {
    return VehicleDocument(
      id: json['id'] ?? '',
      documentType: json['documentType'] ?? '',
      documentName: json['documentName'] ?? '',
      documentUrl: json['documentUrl'] ?? '',
      uploadDate: json['uploadDate'] != null ? DateTime.parse(json['uploadDate']) : DateTime.now(),
      expiryDate: json['expiryDate'] != null ? DateTime.parse(json['expiryDate']) : null,
      uploadedBy: json['uploadedBy'] ?? '',
    );
  }
}

class DriverDocument {
  final String id;
  final String documentType; // 'license', 'medical', 'background_check', etc.
  final String documentName;
  final String documentUrl;
  final DateTime uploadDate;
  final DateTime? expiryDate;
  final String uploadedBy;

  DriverDocument({
    required this.id,
    required this.documentType,
    required this.documentName,
    required this.documentUrl,
    required this.uploadDate,
    this.expiryDate,
    required this.uploadedBy,
  });

  bool get isExpired => expiryDate != null && expiryDate!.isBefore(DateTime.now());
  bool get isExpiringSoon => expiryDate != null && 
      expiryDate!.isAfter(DateTime.now()) && 
      expiryDate!.isBefore(DateTime.now().add(const Duration(days: 30)));
  
  int? get daysUntilExpiry {
    if (expiryDate == null) return null;
    return expiryDate!.difference(DateTime.now()).inDays;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'documentType': documentType,
      'documentName': documentName,
      'documentUrl': documentUrl,
      'uploadDate': uploadDate.toIso8601String(),
      'expiryDate': expiryDate?.toIso8601String(),
      'uploadedBy': uploadedBy,
    };
  }

  factory DriverDocument.fromJson(Map<String, dynamic> json) {
    return DriverDocument(
      id: json['id'] ?? '',
      documentType: json['documentType'] ?? '',
      documentName: json['documentName'] ?? '',
      documentUrl: json['documentUrl'] ?? '',
      uploadDate: json['uploadDate'] != null ? DateTime.parse(json['uploadDate']) : DateTime.now(),
      expiryDate: json['expiryDate'] != null ? DateTime.parse(json['expiryDate']) : null,
      uploadedBy: json['uploadedBy'] ?? '',
    );
  }
}

class Vehicle {
  final String id;
  final String name;
  final String model;
  final String licensePlate;
  final String status;
  final String? assignedDriver;
  final String? assignedDriverId;
  final DateTime? onboardedDate;
  final List<VehicleDocument> documents;
  final List<DriverDocument> driverDocuments;
  final int seatCapacity; // Total seats including driver
  final int assignedCustomers; // Currently assigned customers
  final String? vendor; // Vendor from which vehicle is sourced

  Vehicle({
    required this.id,
    required this.name,
    required this.model,
    required this.licensePlate,
    required this.status,
    this.assignedDriver,
    this.assignedDriverId,
    this.onboardedDate,
    this.documents = const [],
    this.driverDocuments = const [],
    this.seatCapacity = 4, // Default 4 seats
    this.assignedCustomers = 0,
    this.vendor,
  });

  bool get hasExpiredDocuments => 
      documents.any((doc) => doc.isExpired) || 
      driverDocuments.any((doc) => doc.isExpired);

  bool get hasExpiringSoonDocuments => 
      documents.any((doc) => doc.isExpiringSoon) || 
      driverDocuments.any((doc) => doc.isExpiringSoon);

  List<VehicleDocument> get expiredVehicleDocuments => 
      documents.where((doc) => doc.isExpired).toList();

  List<VehicleDocument> get expiringSoonVehicleDocuments => 
      documents.where((doc) => doc.isExpiringSoon).toList();

  List<DriverDocument> get expiredDriverDocuments => 
      driverDocuments.where((doc) => doc.isExpired).toList();

  List<DriverDocument> get expiringSoonDriverDocuments => 
      driverDocuments.where((doc) => doc.isExpiringSoon).toList();

  // Seat capacity calculations
  int get availableSeats {
    // If driver is assigned, they take 1 seat
    final driverSeats = assignedDriver != null ? 1 : 0;
    final available = seatCapacity - driverSeats - assignedCustomers;
    return available > 0 ? available : 0;
  }

  int get occupiedSeats {
    final driverSeats = assignedDriver != null ? 1 : 0;
    return driverSeats + assignedCustomers;
  }

  bool get isFull => availableSeats == 0;

  bool canAccommodate(int customerCount) {
    return availableSeats >= customerCount;
  }

  @override
  String toString() {
    return 'Vehicle(id: $id, name: $name, model: $model, licensePlate: $licensePlate, status: $status, assignedDriver: $assignedDriver, onboardedDate: $onboardedDate, capacity: $seatCapacity, available: $availableSeats)';
  }

  Vehicle copyWith({
    String? id,
    String? name,
    String? model,
    String? licensePlate,
    String? status,
    ValueGetter<String?>? assignedDriver,
    ValueGetter<String?>? assignedDriverId,
    ValueGetter<DateTime?>? onboardedDate,
    List<VehicleDocument>? documents,
    List<DriverDocument>? driverDocuments,
    int? seatCapacity,
    int? assignedCustomers,
    ValueGetter<String?>? vendor,
  }) {
    return Vehicle(
      id: id ?? this.id,
      name: name ?? this.name,
      model: model ?? this.model,
      licensePlate: licensePlate ?? this.licensePlate,
      status: status ?? this.status,
      assignedDriver: assignedDriver != null ? assignedDriver() : this.assignedDriver,
      assignedDriverId: assignedDriverId != null ? assignedDriverId() : this.assignedDriverId,
      onboardedDate: onboardedDate != null ? onboardedDate() : this.onboardedDate,
      documents: documents ?? this.documents,
      driverDocuments: driverDocuments ?? this.driverDocuments,
      seatCapacity: seatCapacity ?? this.seatCapacity,
      assignedCustomers: assignedCustomers ?? this.assignedCustomers,
      vendor: vendor != null ? vendor() : this.vendor,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'model': model,
      'licensePlate': licensePlate,
      'status': status,
      'assignedDriver': assignedDriver,
      'assignedDriverId': assignedDriverId,
      'onboardedDate': onboardedDate?.toIso8601String(),
      'documents': documents.map((doc) => doc.toJson()).toList(),
      'driverDocuments': driverDocuments.map((doc) => doc.toJson()).toList(),
      'seatCapacity': seatCapacity,
      'assignedCustomers': assignedCustomers,
      'vendor': vendor,
    };
  }

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    // Parse seat capacity from various possible fields safely
    int capacity = 4; // Default
    try {
      if (json['seatCapacity'] != null) {
        capacity = int.tryParse(json['seatCapacity'].toString()) ?? 4;
      } else if (json['seatingCapacity'] != null) {
        capacity = int.tryParse(json['seatingCapacity'].toString()) ?? 4;
      } else if (json['capacity'] != null) {
        final capacityField = json['capacity'];
        if (capacityField is Map && capacityField['passengers'] != null) {
          capacity = int.tryParse(capacityField['passengers'].toString()) ?? 4;
        } else if (capacityField is num) {
          capacity = capacityField.toInt();
        } else {
          capacity = int.tryParse(capacityField.toString()) ?? 4;
        }
      }
    } catch (e) {
      print('Error parsing vehicle capacity: $e');
      capacity = 4; // Safe fallback
    }

    return Vehicle(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      model: json['model'] ?? '',
      licensePlate: json['licensePlate'] ?? '',
      status: json['status'] ?? 'Active',
      assignedDriver: json['assignedDriver'],
      assignedDriverId: json['assignedDriverId'],
      onboardedDate: json['onboardedDate'] != null ? DateTime.parse(json['onboardedDate']) : null,
      documents: (json['documents'] as List<dynamic>?)
          ?.map((doc) => VehicleDocument.fromJson(doc as Map<String, dynamic>))
          .toList() ?? [],
      driverDocuments: (json['driverDocuments'] as List<dynamic>?)
          ?.map((doc) => DriverDocument.fromJson(doc as Map<String, dynamic>))
          .toList() ?? [],
      seatCapacity: capacity,
      assignedCustomers: json['assignedCustomers'] ?? 0,
      vendor: json['vendor'],
    );
  }
}
