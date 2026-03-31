// File: lib/features/customer/history/presentation/providers/booking_history_provider.dart
// Provider for managing customer's booking history state using ChangeNotifier.

import 'package:flutter/material.dart';
import 'package:abra_fleet/features/customer/history/domain/entities/booking_history_item_entity.dart';
import 'package:abra_fleet/features/customer/history/domain/repositories/booking_history_repository.dart';
// Import the mock implementation for now.
import 'package:abra_fleet/features/customer/history/data/repositories/mock_booking_history_repository_impl.dart';

// Assuming DataState enum is defined in a shared location or one of the other providers.
// If not, you might need to define it here or import it.
// For this example, let's assume it's similar to what we used before.
// If you have a common DataState, import that. Otherwise:
enum DataState { initial, loading, loaded, error } // Define if not shared

class BookingHistoryProvider extends ChangeNotifier {
  final BookingHistoryRepository _bookingHistoryRepository;
  final String? _customerId; // To fetch history for a specific customer

  BookingHistoryProvider({BookingHistoryRepository? bookingHistoryRepository, String? customerId})
      : _bookingHistoryRepository = bookingHistoryRepository ?? MockBookingHistoryRepositoryImpl(),
        _customerId = customerId { // In a real app, customerId would be crucial
    // Fetch booking history when the provider is created.
    fetchBookingHistory();
  }

  List<BookingHistoryItemEntity> _bookingHistoryItems = [];
  DataState _state = DataState.initial;
  String? _errorMessage;

  // Getters for UI to access state
  List<BookingHistoryItemEntity> get bookingHistoryItems => _bookingHistoryItems;
  DataState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == DataState.loading;

  // --- Methods to interact with the repositories ---

  Future<void> fetchBookingHistory() async {
    _state = DataState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      // Pass customerId if your repositories's getBookingHistory method expects it.
      // Our mock currently ignores it but a real API would use it.
      _bookingHistoryItems = await _bookingHistoryRepository.getBookingHistory(customerId: _customerId);
      _state = DataState.loaded;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst("Exception: ", "");
      _state = DataState.error;
      debugPrint('Error fetching booking history: $_errorMessage');
    }
    notifyListeners();
  }

  // Customers usually don't add to their own history directly;
  // this happens as a side effect of completing a booking.
  // So, an `addBookingHistoryItem` method might not be exposed directly for UI use here.
  // It would be handled by a "Booking" feature/provider.

  // Method to find a booking history item by ID from the current list (if needed for details screen)
  BookingHistoryItemEntity? getBookingHistoryItemFromListById(String bookingId) {
    try {
      return _bookingHistoryItems.firstWhere((item) => item.bookingId == bookingId);
    } catch (e) {
      return null; // Not found
    }
  }
}
