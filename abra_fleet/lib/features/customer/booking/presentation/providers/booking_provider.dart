// File: lib/features/customer/booking/presentation/providers/booking_provider.dart
// Provider for managing customer's booking state using ChangeNotifier.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:abra_fleet/features/customer/booking/domain/entities/booking_entity.dart';
import 'package:abra_fleet/features/customer/booking/domain/repositories/booking_repository.dart';
// Import the mock implementation for now.
import 'package:abra_fleet/features/customer/booking/data/repositories/mock_booking_repository_impl.dart';

// Assuming DataState enum is defined in a shared location or one of the other providers.
// If not, define it here or import it.
// For this example, let's assume it's similar to what we used before.
enum DataState { initial, loading, loaded, error } // Define if not shared

class BookingProvider extends ChangeNotifier {
  final BookingRepository _bookingRepository;
  final String? _customerId; // To associate bookings with a specific customer

  BookingEntity? _activeBooking;
  StreamSubscription<BookingEntity?>? _activeBookingSubscription;

  DataState _state = DataState.initial; // General state for operations like createBooking
  String? _errorMessage;

  // Add bookings list and history
  List<BookingEntity> _bookings = [];
  List<BookingEntity> _bookingHistory = [];

  BookingProvider({BookingRepository? bookingRepository, String? customerId})
      : _bookingRepository = bookingRepository ?? MockBookingRepositoryImpl(),
        _customerId = customerId {
    _listenToActiveBookingStream();
    _loadBookingHistory();
    // Optionally, fetch current active booking when provider is created
    // fetchCurrentActiveBooking(); // This will be called by the stream listener initially
  }

  // Getters for UI
  BookingEntity? get activeBooking => _activeBooking;
  List<BookingEntity> get bookings => _bookings;
  List<BookingEntity> get bookingHistory => _bookingHistory;
  DataState get state => _state; // For create/cancel operations
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == DataState.loading; // For create/cancel operations
  bool get isTrackingActiveBooking => _activeBooking != null && _activeBooking?.status != BookingStatus.completed && _activeBooking?.status != BookingStatus.cancelledByCustomer && _activeBooking?.status != BookingStatus.cancelledByDriver && _activeBooking?.status != BookingStatus.cancelledBySystem && _activeBooking?.status != BookingStatus.noDriverFound;


  void _listenToActiveBookingStream() {
    _activeBookingSubscription?.cancel(); // Cancel previous subscription if any
    _activeBookingSubscription = _bookingRepository.activeBookingStream.listen(
            (booking) {
          _activeBooking = booking;
          _updateBookingsList(booking);
          debugPrint('[BookingProvider] Active booking updated: ${booking?.id} - Status: ${booking?.statusDisplay}');
          notifyListeners();
        },
        onError: (error) {
          debugPrint('[BookingProvider] Error in active booking stream: $error');
          _activeBooking = null; // Clear active booking on stream error
          _errorMessage = "Error tracking booking."; // Set a generic error
          notifyListeners();
        }
    );
  }

  void _updateBookingsList(BookingEntity? booking) {
    if (booking != null) {
      final existingIndex = _bookings.indexWhere((b) => b.id == booking.id);
      if (existingIndex >= 0) {
        _bookings[existingIndex] = booking;
      } else {
        _bookings.add(booking);
      }
    }
  }

  Future<void> _loadBookingHistory() async {
    if (_customerId == null) return;
    
    try {
      // For now, use mock data - in real implementation, fetch from repository
      _bookingHistory = [
        BookingEntity(
          id: 'booking_1',
          customerId: _customerId!,
          customerName: 'Customer',
          pickupLocation: '123 Main St',
          dropoffLocation: '456 Oak Ave',
          serviceType: 'Standard Ride',
          requestTime: DateTime.now().subtract(const Duration(days: 1)),
          status: BookingStatus.completed,
        ),
        BookingEntity(
          id: 'booking_2',
          customerId: _customerId!,
          customerName: 'Customer',
          pickupLocation: '789 Pine St',
          dropoffLocation: '321 Elm St',
          serviceType: 'XL Ride',
          requestTime: DateTime.now().subtract(const Duration(days: 3)),
          status: BookingStatus.completed,
        ),
      ];
      
      // Add to main bookings list as well
      _bookings.addAll(_bookingHistory);
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading booking history: $e');
    }
  }

  Future<bool> createBooking({
    required String customerName, // Assuming we get this from auth user
    required String pickupLocation,
    required String dropoffLocation,
    required String serviceType,
    String? notesToDriver,
  }) async {
    if (_customerId == null) {
      _errorMessage = "User not identified. Cannot create booking.";
      _state = DataState.error;
      notifyListeners();
      return false;
    }

    _state = DataState.loading;
    _errorMessage = null;
    notifyListeners();

    // Create a partial booking request entity
    final bookingRequest = BookingEntity(
      id: '', // ID will be generated by repository/backend
      customerId: _customerId!,
      customerName: customerName,
      pickupLocation: pickupLocation,
      dropoffLocation: dropoffLocation,
      serviceType: serviceType,
      requestTime: DateTime.now(), // Set by client, or could be set by backend
      notesToDriver: notesToDriver,
      // Other fields will be set by backend or default in entity
    );

    try {
      // The createBooking method in the repository will handle setting the initial active booking
      // and pushing it to the stream, which our _listenToActiveBookingStream will pick up.
      await _bookingRepository.createBooking(bookingRequest);
      // _activeBooking is updated via the stream, no need to set it directly here.
      _state = DataState.loaded; // Indicate creation attempt finished
      // notifyListeners(); // Already notified by the stream listener
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst("Exception: ", "");
      _state = DataState.error;
      debugPrint('Error creating booking: $_errorMessage');
      notifyListeners();
      return false;
    }
  }

  Future<void> fetchCurrentActiveBooking() async {
    if (_customerId == null) return; // Cannot fetch without customerId

    // This might not be needed if the stream provides the initial state correctly.
    // Or use it as an explicit refresh.
    // _state = DataState.loading; // Could set a specific loading state for this
    // notifyListeners();
    try {
      _activeBooking = await _bookingRepository.getCurrentActiveBooking(customerId: _customerId!);
    } catch (e) {
      _errorMessage = e.toString().replaceFirst("Exception: ", "");
      // _state = DataState.error;
    }
    // notifyListeners(); // Stream listener should handle updates
  }

  Future<bool> cancelActiveBooking() async {
    if (_activeBooking == null || _customerId == null) {
      _errorMessage = "No active booking to cancel or user not identified.";
      notifyListeners();
      return false;
    }

    _state = DataState.loading; // Or a specific 'cancelling' state
    _errorMessage = null;
    notifyListeners();

    try {
      await _bookingRepository.cancelBooking(bookingId: _activeBooking!.id, customerId: _customerId!);
      // _activeBooking will be updated to null or cancelled status via the stream.
      _state = DataState.loaded;
      // notifyListeners(); // Stream listener handles it
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst("Exception: ", "");
      _state = DataState.error;
      debugPrint('Error cancelling booking: $_errorMessage');
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _activeBookingSubscription?.cancel();
    // If MockBookingRepositoryImpl has a dispose method for its stream controller, call it.
    // This depends on how you manage repository lifecycle.
    // if (_bookingRepository is MockBookingRepositoryImpl) {
    //   (_bookingRepository as MockBookingRepositoryImpl).dispose();
    // }
    super.dispose();
  }
}
