// File: lib/features/admin/driver_management/domain/entities/driver_entity.dart
// Defines the data structure for a Driver.

// Firebase removed - using DateTime instead of Timestamp

// Using 'equatable' can be beneficial here if you plan to compare Driver instances.
// If you add it, include 'equatable: ^2.0.5' (or latest) in pubspec.yaml.
// import 'package:equatable/equatable.dart';

// class Driver extends Equatable {
class Driver {
  final String id; // Unique identifier for the driver
  final String name;
  final String email; // Can be the same as their login email
  final String phoneNumber;
  final String? licenseNumber;
  final DateTime? licenseExpiryDate;
  final String status; // e.g., "Active", "On Leave", "Inactive"
  final String? assignedVehicleId; // ID of the vehicle currently assigned
  final String? address;
  final String role;
  final DateTime createdAt; // Non-nullable with default value in constructor

  Driver({
    required this.id,
    required this.name,
    required this.email,
    required this.phoneNumber,
    this.licenseNumber,
    this.licenseExpiryDate,
    this.status = 'Active',
    this.assignedVehicleId,
    this.address,
    this.role = 'driver',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // If using Equatable:
  // @override
  // List<Object?> get props => [
  //   id, name, email, phoneNumber, licenseNumber, licenseExpiryDate, status, assignedVehicleId
  // ];

  @override
  String toString() {
    return 'Driver(id: $id, name: $name, email: $email, phone: $phoneNumber, license: $licenseNumber, status: $status)';
  }

  // Optional: copyWith method for easier updates if using immutable state patterns
  Driver copyWith({
    String? id,
    String? name,
    String? email,
    String? phoneNumber,
    String? licenseNumber,
    DateTime? licenseExpiryDate,
    String? status,
    String? assignedVehicleId,
    String? address,
    String? role,
    DateTime? createdAt,
  }) {
    return Driver(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      licenseExpiryDate: licenseExpiryDate ?? this.licenseExpiryDate,
      status: status ?? this.status,
      assignedVehicleId: assignedVehicleId ?? this.assignedVehicleId,
      address: address ?? this.address,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // Convert Driver to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'licenseNumber': licenseNumber,
      'licenseExpiryDate': licenseExpiryDate?.toIso8601String(),
      'status': status,
      'assignedVehicleId': assignedVehicleId,
      'address': address,
      'role': role,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  // Create Driver from Map (Backend API data)
  factory Driver.fromMap(Map<String, dynamic> map, String id) {
    DateTime parseCreatedAt(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    DateTime? parseLicenseExpiry(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    // Handle both flat structure (processed by backend) and nested structure (raw data)
    final personalInfo = map['personalInfo'] as Map<String, dynamic>?;
    final license = map['license'] as Map<String, dynamic>?;
    final assignedVehicle = map['assignedVehicle'] as Map<String, dynamic>?;

    // Priority: flat fields first (from backend processing), then nested fields
    String driverName = '';
    if (map['name'] != null && map['name'].toString().isNotEmpty) {
      // Backend already processed the name
      driverName = map['name'].toString();
    } else if (personalInfo != null) {
      // Fallback to nested structure
      final firstName = personalInfo['firstName']?.toString() ?? '';
      final lastName = personalInfo['lastName']?.toString() ?? '';
      driverName = '$firstName $lastName'.trim();
    }

    String driverEmail = '';
    if (map['email'] != null && map['email'].toString().isNotEmpty) {
      driverEmail = map['email'].toString();
    } else if (personalInfo != null && personalInfo['email'] != null) {
      driverEmail = personalInfo['email'].toString();
    }

    String driverPhone = '';
    if (map['phoneNumber'] != null && map['phoneNumber'].toString().isNotEmpty) {
      driverPhone = map['phoneNumber'].toString();
    } else if (personalInfo != null && personalInfo['phone'] != null) {
      driverPhone = personalInfo['phone'].toString();
    }

    String? licenseNum;
    if (map['licenseNumber'] != null && map['licenseNumber'].toString().isNotEmpty) {
      licenseNum = map['licenseNumber'].toString();
    } else if (license != null && license['licenseNumber'] != null) {
      licenseNum = license['licenseNumber'].toString();
    }

    DateTime? licenseExpiry;
    if (map['licenseExpiryDate'] != null) {
      licenseExpiry = parseLicenseExpiry(map['licenseExpiryDate']);
    } else if (license != null && license['expiryDate'] != null) {
      licenseExpiry = parseLicenseExpiry(license['expiryDate']);
    }

    String? vehicleId;
    if (map['assignedVehicleId'] != null && map['assignedVehicleId'].toString().isNotEmpty) {
      vehicleId = map['assignedVehicleId'].toString();
    } else if (assignedVehicle != null) {
      vehicleId = assignedVehicle['vehicleId']?.toString() ?? 
                  assignedVehicle['registrationNumber']?.toString();
    } else if (map['assignedVehicle'] != null && map['assignedVehicle'] is String) {
      vehicleId = map['assignedVehicle'].toString();
    }

    return Driver(
      id: id,
      name: driverName,
      email: driverEmail,
      phoneNumber: driverPhone,
      licenseNumber: licenseNum,
      licenseExpiryDate: licenseExpiry,
      status: map['status']?.toString() ?? 'Active',
      assignedVehicleId: vehicleId,
      address: map['address']?.toString(),
      role: map['role']?.toString() ?? 'driver',
      createdAt: parseCreatedAt(map['createdAt'] ?? map['joinedDate']),
    );
  }
}
