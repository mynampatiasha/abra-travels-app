// File: lib/features/customer/history/presentation/screens/customer_booking_history_screen.dart
// Enhanced placeholder screen for Customer to view their booking history, with navigation to details.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

// Import the BookingHistoryItemEntity
import 'package:abra_fleet/features/customer/history/domain/entities/booking_history_item_entity.dart';
// Import the Provider
import 'package:abra_fleet/features/customer/history/presentation/providers/booking_history_provider.dart';
// Import the Details screen
import 'package:abra_fleet/features/customer/history/presentation/screens/customer_booking_history_details_screen.dart';

// Assuming DataState enum is defined in BookingHistoryProvider or a shared location

class CustomerBookingHistoryScreen extends StatefulWidget {
  const CustomerBookingHistoryScreen({super.key});

  @override
  State<CustomerBookingHistoryScreen> createState() => _CustomerBookingHistoryScreenState();
}

class _CustomerBookingHistoryScreenState extends State<CustomerBookingHistoryScreen> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<BookingHistoryProvider>(context, listen: false).fetchBookingHistory();
    });
  }

  void _navigateToBookingDetails(BuildContext context, BookingHistoryItemEntity booking) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomerBookingHistoryDetailsScreen(bookingItem: booking),
      ),
    );
  }

  Color _getStatusColor(BuildContext context, String status) {
    switch (status.toLowerCase()) {
      case 'completed': return Colors.green.shade700;
      case 'cancelled': return Colors.red.shade700;
      case 'driver arrived': return Colors.blue.shade700;
      default: return Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey.shade700;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed': return Icons.check_circle_outline_rounded;
      case 'cancelled': return Icons.cancel_outlined;
      case 'driver arrived': return Icons.pin_drop_outlined;
      default: return Icons.history_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final DateFormat dateFormat = DateFormat('MMM dd, yyyy - hh:mm a');

    return Scaffold(
      body: Consumer<BookingHistoryProvider>(
        builder: (context, bookingHistoryProvider, child) {
          if (bookingHistoryProvider.isLoading && bookingHistoryProvider.bookingHistoryItems.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          // Assuming DataState enum is accessible via bookingHistoryProvider.state
          if (bookingHistoryProvider.state == DataState.error && bookingHistoryProvider.bookingHistoryItems.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text('Error: ${bookingHistoryProvider.errorMessage ?? "Could not load booking history."}', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => bookingHistoryProvider.fetchBookingHistory(),
                    child: const Text('Retry'),
                  )
                ],
              ),
            );
          }

          if (bookingHistoryProvider.bookingHistoryItems.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.list_alt_rounded, size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text('No Booking History Yet', style: textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Your past service requests will appear here.',
                    style: textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final displayedBookingHistory = bookingHistoryProvider.bookingHistoryItems;

          return RefreshIndicator(
            onRefresh: () => bookingHistoryProvider.fetchBookingHistory(),
            child: ListView.separated(
              padding: const EdgeInsets.all(12.0),
              itemCount: displayedBookingHistory.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final booking = displayedBookingHistory[index];
                return Card(
                  elevation: 2.0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: Hero(
                      tag: 'booking_history_icon_${booking.bookingId}',
                      child: CircleAvatar(
                        backgroundColor: _getStatusColor(context, booking.status).withOpacity(0.15),
                        child: Icon(_getStatusIcon(booking.status), color: _getStatusColor(context, booking.status)),
                      ),
                    ),
                    title: Text(
                      booking.serviceType,
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'To: ${booking.dropoffLocation}\nOn: ${dateFormat.format(booking.bookingDate)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      booking.fare != null ? '\$${booking.fare!.toStringAsFixed(2)}' : '',
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    onTap: () => _navigateToBookingDetails(context, booking),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
