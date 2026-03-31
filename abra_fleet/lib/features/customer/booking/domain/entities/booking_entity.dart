// File: lib/features/customer/booking/domain/entities/booking_entity.dart
// Defines the data structure for a Booking.

import 'package:flutter/foundation.dart'; // For @required or other utilities

enum BookingStatus {
  pending,        // Request made, waiting for driver assignment
  confirmed,      // Driver assigned, en route to pickup
  driverArrived,  // Driver has arrived at pickup location
  inProgress,     // Trip started with customer
  completed,      // Trip finished
  cancelledByCustomer,
  cancelledByDriver,
  cancelledBySystem,
  noDriverFound,
}

class BookingEntity {
  final String id; // Unique booking ID
  final String customerId;
  final String customerName; // For display
  final String pickupLocation;
  final String dropoffLocation;
  final String serviceType; // e.g., "Standard Ride", "XL Ride", "Package Delivery"
  final DateTime requestTime;
  DateTime? estimatedPickupTime;
  DateTime? actualPickupTime;
  DateTime? estimatedDropoffTime;
  DateTime? actualDropoffTime;
  BookingStatus status;
  String? driverId;
  String? driverName;
  String? driverPhoneNumber; // <<< ENSURE THIS FIELD IS PRESENT
  String? vehicleId;
  String? vehicleDetails; // e.g., "Toyota Camry - ABC 123"
  double? estimatedFare;
  double? actualFare;
  String? paymentMethodId; // Link to a payment method
  String? notesToDriver;

  BookingEntity({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.serviceType,
    required this.requestTime,
    this.estimatedPickupTime,
    this.actualPickupTime,
    this.estimatedDropoffTime,
    this.actualDropoffTime,
    this.status = BookingStatus.pending,
    this.driverId,
    this.driverName,
    this.driverPhoneNumber, // <<< ENSURE THIS IS IN THE CONSTRUCTOR
    this.vehicleId,
    this.vehicleDetails,
    this.estimatedFare,
    this.actualFare,
    this.paymentMethodId,
    this.notesToDriver,
  });

  String get statusDisplay {
    switch (status) {
      case BookingStatus.pending: return 'Pending Assignment';
      case BookingStatus.confirmed: return 'Driver Confirmed';
      case BookingStatus.driverArrived: return 'Driver Arrived';
      case BookingStatus.inProgress: return 'Trip In Progress';
      case BookingStatus.completed: return 'Completed';
      case BookingStatus.cancelledByCustomer: return 'Cancelled by You';
      case BookingStatus.cancelledByDriver: return 'Cancelled by Driver';
      case BookingStatus.cancelledBySystem: return 'Cancelled by System';
      case BookingStatus.noDriverFound: return 'No Driver Found';
      default: return 'Unknown';
    }
  }

  BookingEntity copyWith({
    String? id,
    String? customerId,
    String? customerName,
    String? pickupLocation,
    String? dropoffLocation,
    String? serviceType,
    DateTime? requestTime,
    ValueGetter<DateTime?>? estimatedPickupTime,
    ValueGetter<DateTime?>? actualPickupTime,
    ValueGetter<DateTime?>? estimatedDropoffTime,
    ValueGetter<DateTime?>? actualDropoffTime,
    BookingStatus? status,
    ValueGetter<String?>? driverId,
    ValueGetter<String?>? driverName,
    ValueGetter<String?>? driverPhoneNumber, // <<< ENSURE THIS IS IN COPYWITH
    ValueGetter<String?>? vehicleId,
    ValueGetter<String?>? vehicleDetails,
    ValueGetter<double?>? estimatedFare,
    ValueGetter<double?>? actualFare,
    ValueGetter<String?>? paymentMethodId,
    ValueGetter<String?>? notesToDriver,
  }) {
    return BookingEntity(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      dropoffLocation: dropoffLocation ?? this.dropoffLocation,
      serviceType: serviceType ?? this.serviceType,
      requestTime: requestTime ?? this.requestTime,
      estimatedPickupTime: estimatedPickupTime != null ? estimatedPickupTime() : this.estimatedPickupTime,
      actualPickupTime: actualPickupTime != null ? actualPickupTime() : this.actualPickupTime,
      estimatedDropoffTime: estimatedDropoffTime != null ? estimatedDropoffTime() : this.estimatedDropoffTime,
      actualDropoffTime: actualDropoffTime != null ? actualDropoffTime() : this.actualDropoffTime,
      status: status ?? this.status,
      driverId: driverId != null ? driverId() : this.driverId,
      driverName: driverName != null ? driverName() : this.driverName,
      driverPhoneNumber: driverPhoneNumber != null ? driverPhoneNumber() : this.driverPhoneNumber, // <<< ENSURE THIS IS IN COPYWITH
      vehicleId: vehicleId != null ? vehicleId() : this.vehicleId,
      vehicleDetails: vehicleDetails != null ? vehicleDetails() : this.vehicleDetails,
      estimatedFare: estimatedFare != null ? estimatedFare() : this.estimatedFare,
      actualFare: actualFare != null ? actualFare() : this.actualFare,
      paymentMethodId: paymentMethodId != null ? paymentMethodId() : this.paymentMethodId,
      notesToDriver: notesToDriver != null ? notesToDriver() : this.notesToDriver,
    );
  }
}
