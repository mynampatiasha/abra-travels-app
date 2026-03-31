// File: lib/features/customer/history/domain/entities/booking_history_item_entity.dart
// Defines the data structure for a Customer's Booking History Item.

import 'package:flutter/foundation.dart'; // For @required or other utilities

class BookingHistoryItemEntity {
  final String bookingId;
  final String serviceType; // e.g., "Standard Ride", "Package Delivery"
  final DateTime bookingDate; // Could be start time of the service
  final String pickupLocation;
  final String dropoffLocation;
  final String status; // e.g., "Completed", "Cancelled", "Driver Arrived"
  final double? fare;
  final String? vehicleDetails; // e.g., "Toyota Camry - ABC 123"
  final String? driverName;

  const BookingHistoryItemEntity({
    required this.bookingId,
    required this.serviceType,
    required this.bookingDate,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.status,
    this.fare,
    this.vehicleDetails,
    this.driverName,
  });

  @override
  String toString() {
    return 'BookingHistoryItem(id: $bookingId, service: $serviceType, date: $bookingDate, status: $status)';
  }

  // Optional: copyWith method
  BookingHistoryItemEntity copyWith({
    String? bookingId,
    String? serviceType,
    DateTime? bookingDate,
    String? pickupLocation,
    String? dropoffLocation,
    String? status,
    ValueGetter<double?>? fare,
    ValueGetter<String?>? vehicleDetails,
    ValueGetter<String?>? driverName,
  }) {
    return BookingHistoryItemEntity(
      bookingId: bookingId ?? this.bookingId,
      serviceType: serviceType ?? this.serviceType,
      bookingDate: bookingDate ?? this.bookingDate,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      dropoffLocation: dropoffLocation ?? this.dropoffLocation,
      status: status ?? this.status,
      fare: fare != null ? fare() : this.fare,
      vehicleDetails: vehicleDetails != null ? vehicleDetails() : this.vehicleDetails,
      driverName: driverName != null ? driverName() : this.driverName,
    );
  }
}
