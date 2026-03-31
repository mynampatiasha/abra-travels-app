// File: lib/features/customer/booking/domain/repositories/booking_repository.dart
// Defines the contract for customer booking data operations.

import 'package:abra_fleet/features/customer/booking/domain/entities/booking_entity.dart';

abstract class BookingRepository {
  // Create a new booking request.
  // Takes booking details (pickup, dropoff, service type, customerId, etc.)
  // Returns the newly created BookingEntity (possibly with a pending status and server-generated ID).
  Future<BookingEntity> createBooking(BookingEntity bookingRequest);

  // Get the current active booking for a specific customer.
  // Returns null if no active booking.
  Future<BookingEntity?> getCurrentActiveBooking({required String customerId});

  // Cancel an active booking.
  Future<void> cancelBooking({required String bookingId, required String customerId});

  // Stream to listen for updates to the active booking (e.g., driver assigned, status changes).
  // This is crucial for the "Track Booking" screen.
  Stream<BookingEntity?> get activeBookingStream; // Could also take customerId if needed by implementation

// Optional: Get details of a specific past booking by ID (might be part of BookingHistoryRepository too)
// Future<BookingEntity?> getBookingDetails(String bookingId);
}
