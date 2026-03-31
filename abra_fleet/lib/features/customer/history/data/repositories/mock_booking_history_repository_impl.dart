// File: lib/features/customer/history/data/repositories/mock_booking_history_repository_impl.dart
// Mock implementation of BookingHistoryRepository for local development and testing.

import 'dart:async';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:abra_fleet/features/customer/history/domain/entities/booking_history_item_entity.dart';
import 'package:abra_fleet/features/customer/history/domain/repositories/booking_history_repository.dart';

class MockBookingHistoryRepositoryImpl implements BookingHistoryRepository {
  // In-memory list to store booking history items
  // For a mock, we can assume these are for a specific default customer
  final String _mockCustomerId = 'c001'; // Example customer ID

  final List<BookingHistoryItemEntity> _mockBookingHistory = [
    BookingHistoryItemEntity(
      bookingId: 'bk00120',
      serviceType: 'Standard Ride',
      bookingDate: DateTime.now().subtract(const Duration(days: 2, hours: 3)),
      pickupLocation: '123 Main St, Anytown',
      dropoffLocation: '789 Pine Ave, Anytown',
      status: 'Completed',
      fare: 15.75,
      vehicleDetails: 'Toyota Prius - XYZ 789',
      driverName: 'Jane D.',
    ),
    BookingHistoryItemEntity(
      bookingId: 'bk00115',
      serviceType: 'Package Delivery',
      bookingDate: DateTime.now().subtract(const Duration(days: 5, hours: 10)),
      pickupLocation: '456 Oak Rd, Anytown',
      dropoffLocation: '101 Maple Dr, Othertown',
      status: 'Completed',
      fare: 22.50,
      vehicleDetails: 'Cargo Van 1 - AB-123-CD',
      driverName: 'John S.',
    ),
    BookingHistoryItemEntity(
      bookingId: 'bk00110',
      serviceType: 'XL Ride',
      bookingDate: DateTime.now().subtract(const Duration(days: 10)),
      pickupLocation: 'City Mall Entrance A',
      dropoffLocation: 'Airport Terminal 2',
      status: 'Cancelled',
      vehicleDetails: 'SUV XL - GHI 456',
      driverName: 'Mike B.',
    ),
    BookingHistoryItemEntity(
      bookingId: 'bk00121',
      serviceType: 'Premium Ride',
      bookingDate: DateTime.now().subtract(const Duration(days: 1)),
      pickupLocation: 'Grand Hotel Downtown',
      dropoffLocation: 'Opera House',
      status: 'Completed',
      fare: 35.00,
      vehicleDetails: 'Mercedes S-Class - PREM 01',
      driverName: 'Sarah K.',
    ),
    // Add a booking for a different mock customer to test filtering (if we implement it)
    // BookingHistoryItemEntity(
    //   bookingId: 'bk00201',
    //   serviceType: 'Standard Ride',
    //   bookingDate: DateTime.now().subtract(const Duration(days: 4)),
    //   pickupLocation: 'Another Place',
    //   dropoffLocation: 'Somewhere Else',
    //   status: 'Completed',
    //   fare: 12.00,
    //   // customerId: 'c002' // Assuming BookingHistoryItemEntity might have customerId
    // ),
  ];
  // int _nextBookingIdCounter = 122; // If adding new history items was a feature here

  // Simulate network delay
  Future<void> _simulateDelay({int milliseconds = 250}) async {
    await Future.delayed(Duration(milliseconds: milliseconds));
  }

  @override
  Future<List<BookingHistoryItemEntity>> getBookingHistory({String? customerId}) async {
    await _simulateDelay(milliseconds: 450);
    // For this mock, if customerId is provided and matches _mockCustomerId, return all.
    // Otherwise, return an empty list or filter if your mock data is more complex.
    // For simplicity, we'll assume the current list is for the logged-in mock customer.
    // If customerId was part of BookingHistoryItemEntity, you could filter:
    // if (customerId != null) {
    //   return _mockBookingHistory.where((item) => item.customerId == customerId).toList();
    // }
    _mockBookingHistory.sort((a,b) => b.bookingDate.compareTo(a.bookingDate)); // Ensure sorted
    debugPrint('[MockBookingHistoryRepo] Returning ${_mockBookingHistory.length} booking history items.');
    return List<BookingHistoryItemEntity>.from(_mockBookingHistory); // Return a copy
  }

// Adding new history items would typically be a side effect of a booking completing,
// so an addBookingHistoryItem method might not be directly called from UI here.
// But if needed for testing or other purposes:
/*
  Future<BookingHistoryItemEntity> addBookingHistoryItem(BookingHistoryItemEntity item) async {
    await _simulateDelay();
    final newItemWithId = item.copyWith(
      bookingId: 'bk${(_nextBookingIdCounter++).toString().padLeft(3,'0')}'
    );
    _mockBookingHistory.insert(0, newItemWithId); // Add to top, assuming newest first
    debugPrint('[MockBookingHistoryRepo] Added booking history item: ${newItemWithId.bookingId}');
    return newItemWithId;
  }
  */
}
