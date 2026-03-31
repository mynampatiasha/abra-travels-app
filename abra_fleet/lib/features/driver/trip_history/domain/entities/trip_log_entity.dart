// File: lib/features/driver/trip_history/domain/entities/trip_log_entity.dart
// Defines the data structure for a Driver's Trip Log entry.

import 'package:flutter/foundation.dart';

class TripLogEntity {
  final String id;
  final String vehicleName;
  final String vehicleLicensePlate;
  final DateTime startTime;
  final DateTime endTime;
  final double startOdometer;
  final double endOdometer;
  final String? notes;
  final String? startLocation; // Optional: Could be address or coordinates
  final String? endLocation;   // Optional

  TripLogEntity({
    required this.id,
    required this.vehicleName,
    required this.vehicleLicensePlate,
    required this.startTime,
    required this.endTime,
    required this.startOdometer,
    required this.endOdometer,
    this.notes,
    this.startLocation,
    this.endLocation,
  });

  double get distanceTravelled => endOdometer - startOdometer;
  Duration get tripDuration => endTime.difference(startTime);

  // For easier debugging
  @override
  String toString() {
    return 'TripLog(id: $id, vehicle: $vehicleName, start: $startTime, end: $endTime, distance: $distanceTravelled km)';
  }

  // Optional: copyWith method
  TripLogEntity copyWith({
    String? id,
    String? vehicleName,
    String? vehicleLicensePlate,
    DateTime? startTime,
    DateTime? endTime,
    double? startOdometer,
    double? endOdometer,
    ValueGetter<String?>? notes,
    ValueGetter<String?>? startLocation,
    ValueGetter<String?>? endLocation,
  }) {
    return TripLogEntity(
      id: id ?? this.id,
      vehicleName: vehicleName ?? this.vehicleName,
      vehicleLicensePlate: vehicleLicensePlate ?? this.vehicleLicensePlate,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      startOdometer: startOdometer ?? this.startOdometer,
      endOdometer: endOdometer ?? this.endOdometer,
      notes: notes != null ? notes() : this.notes,
      startLocation: startLocation != null ? startLocation() : this.startLocation,
      endLocation: endLocation != null ? endLocation() : this.endLocation,
    );
  }
}
