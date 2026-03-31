// File: lib/features/customer/history/domain/repositories/booking_history_repository.dart
// Defines the contract for customer booking history data operations.

import 'package:abra_fleet/features/customer/history/domain/entities/booking_history_item_entity.dart';

abstract class BookingHistoryRepository {
  // Get a list of booking history items for a specific customer.
  // In a real scenario, you'd pass a customerId.
  Future<List<BookingHistoryItemEntity>> getBookingHistory({String? customerId});

// Get details for a specific booking history item (optional,
// if the list item doesn't contain all necessary details).
// Future<BookingHistoryItemEntity?> getBookingHistoryDetail(String bookingId);

// Note: Adding new booking history items would typically happen when a booking
// is completed or cancelled, likely handled by a different "Booking" feature/repositories,
// not directly added through a "history" repositories.
// Similarly, customers usually can't delete their booking history.
}
