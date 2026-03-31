// File: lib/features/customer/booking/data/repositories/mock_booking_repository_impl.dart
// Mock implementation of BookingRepository for local development and testing.

import 'dart:async';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:abra_fleet/features/customer/booking/domain/entities/booking_entity.dart';
import 'package:abra_fleet/features/customer/booking/domain/repositories/booking_repository.dart';

class MockBookingRepositoryImpl implements BookingRepository {
  final List<BookingEntity> _allBookings = [];
  BookingEntity? _currentActiveBooking;
  int _nextBookingIdCounter = 1;

  final _activeBookingStreamController = StreamController<BookingEntity?>.broadcast();

  MockBookingRepositoryImpl() {
    _activeBookingStreamController.add(null);
  }

  Future<void> _simulateDelay({int milliseconds = 500}) async {
    await Future.delayed(Duration(milliseconds: milliseconds));
  }

  @override
  Future<BookingEntity> createBooking(BookingEntity bookingRequest) async {
    await _simulateDelay(milliseconds: 1000);

    final newBooking = bookingRequest.copyWith(
      id: 'bk${(_nextBookingIdCounter++).toString().padLeft(3, '0')}',
      status: BookingStatus.pending,
      requestTime: DateTime.now(),
    );

    _allBookings.add(newBooking);
    _currentActiveBooking = newBooking;
    _activeBookingStreamController.add(_currentActiveBooking);

    debugPrint('[MockBookingRepo] Created Booking: ${newBooking.id} for ${newBooking.customerName}');

    Future.delayed(const Duration(seconds: 5), () {
      if (_currentActiveBooking?.id == newBooking.id && _currentActiveBooking?.status == BookingStatus.pending) {
        _currentActiveBooking = _currentActiveBooking?.copyWith(
          status: BookingStatus.confirmed,
          driverId: () => 'd_mock_007',
          driverName: () => 'Mock Driver James',
          driverPhoneNumber: () => '555-0987', // <<< ENSURE THIS IS SET
          vehicleDetails: () => 'Toyota Prius - MOCK123',
          vehicleId: () => 'v_mock_007',
          estimatedPickupTime: () => DateTime.now().add(const Duration(minutes: 10)),
        );
        _activeBookingStreamController.add(_currentActiveBooking);
        debugPrint('[MockBookingRepo] Booking ${newBooking.id} Confirmed (Driver Assigned)');

        Future.delayed(const Duration(seconds: 10), () {
          if (_currentActiveBooking?.id == newBooking.id && _currentActiveBooking?.status == BookingStatus.confirmed) {
            _currentActiveBooking = _currentActiveBooking?.copyWith(
              status: BookingStatus.driverArrived,
              actualPickupTime: () => DateTime.now(),
            );
            _activeBookingStreamController.add(_currentActiveBooking);
            debugPrint('[MockBookingRepo] Booking ${newBooking.id} Driver Arrived');
          }
        });
      }
    });

    return newBooking;
  }

  @override
  Future<BookingEntity?> getCurrentActiveBooking({required String customerId}) async {
    await _simulateDelay();
    debugPrint('[MockBookingRepo] Getting active booking: ${_currentActiveBooking?.id}');
    return _currentActiveBooking;
  }

  @override
  Future<void> cancelBooking({required String bookingId, required String customerId}) async {
    await _simulateDelay();
    if (_currentActiveBooking?.id == bookingId) {
      _currentActiveBooking = _currentActiveBooking?.copyWith(
        status: BookingStatus.cancelledByCustomer,
      );
      _activeBookingStreamController.add(_currentActiveBooking);
      debugPrint('[MockBookingRepo] Cancelled Booking: $bookingId by customer $customerId');
      Future.delayed(const Duration(seconds: 2), () {
        if (_currentActiveBooking?.id == bookingId && _currentActiveBooking?.status == BookingStatus.cancelledByCustomer) {
          _currentActiveBooking = null;
          _activeBookingStreamController.add(null);
        }
      });

    } else {
      debugPrint('[MockBookingRepo] Active booking $bookingId not found for cancellation or customer mismatch.');
    }
  }

  @override
  Stream<BookingEntity?> get activeBookingStream => _activeBookingStreamController.stream;

  void simulateTripCompletion(String bookingId) {
    if (_currentActiveBooking?.id == bookingId) {
      _currentActiveBooking = _currentActiveBooking?.copyWith(
        status: BookingStatus.completed,
        actualDropoffTime: () => DateTime.now(),
        actualFare: () => (_currentActiveBooking?.estimatedFare ?? 10.0) + 2.50,
      );
      _activeBookingStreamController.add(_currentActiveBooking);
      debugPrint('[MockBookingRepo] Booking ${bookingId} marked as COMPLETED (simulated).');
      Future.delayed(const Duration(seconds: 3), () {
        if (_currentActiveBooking?.id == bookingId && _currentActiveBooking?.status == BookingStatus.completed) {
          _currentActiveBooking = null;
          _activeBookingStreamController.add(null);
        }
      });
    }
  }

  void dispose() {
    _activeBookingStreamController.close();
  }
}
