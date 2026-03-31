// File: lib/features/customer/tracking/presentation/screens/customer_track_booking_screen.dart
// Enhanced placeholder screen for Customer to track their active booking,
// now with callback to navigate to Book tab and corrected icon.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:abra_fleet/features/customer/booking/domain/entities/booking_entity.dart';
import 'package:abra_fleet/features/customer/booking/presentation/providers/booking_provider.dart';

class CustomerTrackBookingScreen extends StatelessWidget {
  final VoidCallback? onNavigateToBookTab; // Callback to navigate to the Book tab

  const CustomerTrackBookingScreen({
    super.key,
    this.onNavigateToBookTab, // Accept the callback
  });

  Widget _buildDetailItem(BuildContext context, IconData icon, String label, String? value, {bool isEmphasized = false}) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 10),
          Text('$label: ', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          Expanded(child: Text(value ?? 'N/A', style: isEmphasized
              ? textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)
              : textTheme.bodyLarge, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildStatusSpecificContent(BuildContext context, BookingEntity activeBooking) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    switch (activeBooking.status) {
      case BookingStatus.pending:
        return Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Searching for a driver...', style: textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Pickup: ${activeBooking.pickupLocation}', style: textTheme.bodyMedium, textAlign: TextAlign.center),
            Text('Drop-off: ${activeBooking.dropoffLocation}', style: textTheme.bodyMedium, textAlign: TextAlign.center),
          ],
        );
      case BookingStatus.confirmed:
        return Column(
          children: [
            Icon(Icons.local_shipping_outlined, size: 40, color: colorScheme.primary), // CORRECTED ICON
            const SizedBox(height: 12),
            Text('Driver ${activeBooking.driverName ?? 'Assigned'} is on the way!', style: textTheme.titleLarge),
            if (activeBooking.estimatedPickupTime != null)
              Text('ETA: ${DateFormat('hh:mm a').format(activeBooking.estimatedPickupTime!)}', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Vehicle: ${activeBooking.vehicleDetails ?? 'N/A'}', style: textTheme.bodyMedium),
          ],
        );
      case BookingStatus.driverArrived:
        return Column(
          children: [
            Icon(Icons.pin_drop_rounded, size: 40, color: colorScheme.primary),
            const SizedBox(height: 12),
            Text('Your driver, ${activeBooking.driverName ?? 'Driver'}, has arrived!', style: textTheme.titleLarge?.copyWith(color: Colors.green.shade700)),
            const SizedBox(height: 8),
            Text('Vehicle: ${activeBooking.vehicleDetails ?? 'N/A'}', style: textTheme.bodyMedium),
            Text('Please meet at your pickup location.', style: textTheme.bodyMedium),
          ],
        );
      case BookingStatus.inProgress:
        return Column(
          children: [
            Icon(Icons.navigation_rounded, size: 40, color: colorScheme.primary),
            const SizedBox(height: 12),
            Text('Trip to ${activeBooking.dropoffLocation} in progress.', style: textTheme.titleLarge),
            const SizedBox(height: 8),
            if (activeBooking.estimatedDropoffTime != null)
              Text('Estimated Arrival: ${DateFormat('hh:mm a').format(activeBooking.estimatedDropoffTime!)}', style: textTheme.titleMedium),
          ],
        );
      case BookingStatus.completed:
        return Text('Your trip to ${activeBooking.dropoffLocation} is complete!', style: textTheme.titleLarge?.copyWith(color: Colors.green.shade700));
      case BookingStatus.cancelledByCustomer:
      case BookingStatus.cancelledByDriver:
      case BookingStatus.cancelledBySystem:
        return Text('This booking was cancelled.', style: textTheme.titleLarge?.copyWith(color: Colors.red.shade700));
      default:
        return Text('Tracking status: ${activeBooking.statusDisplay}', style: textTheme.titleLarge);
    }
  }


  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Consumer<BookingProvider>(
        builder: (context, bookingProvider, child) {
          final BookingEntity? activeBooking = bookingProvider.activeBooking;

          if (bookingProvider.isLoading && activeBooking == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (activeBooking == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.explore_off_rounded, size: 80, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text('No Active Ride', style: textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(
                      'Ready for your next journey? Book a service now!',
                      style: textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.local_taxi_rounded),
                      label: const Text('Book Now'),
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12)),
                      onPressed: () {
                        onNavigateToBookTab?.call(); // Call the callback
                      },
                    )
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  color: Colors.blueGrey[50],
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.route_rounded, size: 60, color: Colors.blueGrey[400]),
                        const SizedBox(height: 12),
                        Text('Live Map Placeholder', style: textTheme.titleLarge?.copyWith(color: Colors.blueGrey[700])),
                        const SizedBox(height: 8),
                        _buildStatusSpecificContent(context, activeBooking),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20.0),
                      topRight: Radius.circular(20.0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        spreadRadius: 0,
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activeBooking.estimatedPickupTime != null
                              ? 'ETA: ${DateFormat('hh:mm a').format(activeBooking.estimatedPickupTime!)}'
                              : activeBooking.statusDisplay,
                          style: textTheme.headlineSmall?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        if (activeBooking.driverName != null)
                          Text(
                            'Your driver, ${activeBooking.driverName}, is on the way.',
                            style: textTheme.titleMedium,
                          ),
                        if (activeBooking.driverName == null && activeBooking.status == BookingStatus.confirmed)
                          Text('Driver assigned. Details incoming.', style: textTheme.titleMedium),

                        const Divider(height: 24.0),
                        _buildDetailItem(context, Icons.directions_car_outlined, 'Vehicle', activeBooking.vehicleDetails ?? 'Assigning...'),
                        _buildDetailItem(context, Icons.my_location, 'Pickup', activeBooking.pickupLocation),
                        _buildDetailItem(context, Icons.flag_rounded, 'Drop-off', activeBooking.dropoffLocation),
                        if (activeBooking.driverName != null)
                          _buildDetailItem(context, Icons.person_pin_rounded, 'Driver', activeBooking.driverName),
                        if (activeBooking.driverPhoneNumber != null)
                          _buildDetailItem(context, Icons.phone_rounded, 'Driver Contact', activeBooking.driverPhoneNumber!),

                        const SizedBox(height: 20.0),
                        Row(
                          children: [
                            if (activeBooking.driverPhoneNumber != null && (activeBooking.status == BookingStatus.confirmed || activeBooking.status == BookingStatus.driverArrived || activeBooking.status == BookingStatus.inProgress))
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.call_rounded),
                                  label: const Text('Call Driver'),
                                  onPressed: () { /* Placeholder */ },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    side: BorderSide(color: colorScheme.primary),
                                  ),
                                ),
                              ),
                            if (activeBooking.driverPhoneNumber != null && (activeBooking.status == BookingStatus.confirmed || activeBooking.status == BookingStatus.driverArrived || activeBooking.status == BookingStatus.inProgress))
                              const SizedBox(width: 12),

                            if (activeBooking.status == BookingStatus.pending || activeBooking.status == BookingStatus.confirmed)
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: bookingProvider.state == DataState.loading && bookingProvider.activeBooking?.id == activeBooking.id
                                      ? const SizedBox(width:18, height:18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.cancel_outlined),
                                  label: Text(bookingProvider.state == DataState.loading  && bookingProvider.activeBooking?.id == activeBooking.id ? 'Cancelling...' : 'Cancel Ride'),
                                  onPressed: (bookingProvider.state == DataState.loading && bookingProvider.activeBooking?.id == activeBooking.id)
                                      ? null
                                      : () async {
                                    final bool? confirmCancel = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Cancel Booking?'),
                                          content: const Text('Are you sure you want to cancel this booking?'),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
                                            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Yes, Cancel'), style: TextButton.styleFrom(foregroundColor: Colors.red)),
                                          ],
                                        ));
                                    if (confirmCancel == true) {
                                      await bookingProvider.cancelActiveBooking();
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    backgroundColor: Colors.red.shade50,
                                    foregroundColor: Colors.red.shade700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
