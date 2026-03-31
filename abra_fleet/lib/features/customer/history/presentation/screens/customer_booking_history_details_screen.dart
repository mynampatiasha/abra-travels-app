// File: lib/features/customer/history/presentation/screens/customer_booking_history_details_screen.dart
// Screen for Customer to view detailed information about a specific past booking.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For date and time formatting
// Import the BookingHistoryItemEntity
import 'package:abra_fleet/features/customer/history/domain/entities/booking_history_item_entity.dart';

class CustomerBookingHistoryDetailsScreen extends StatelessWidget {
  final BookingHistoryItemEntity bookingItem;

  const CustomerBookingHistoryDetailsScreen({super.key, required this.bookingItem});

  Widget _buildDetailRow(BuildContext context, String label, String? value, {IconData? icon, bool isEmphasized = false}) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: isEmphasized ? colorScheme.primary : colorScheme.secondary),
            const SizedBox(width: 12),
          ] else ...[
            const SizedBox(width: 32), // Placeholder for alignment
          ],
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value ?? 'N/A',
              style: isEmphasized
                  ? textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary)
                  : textTheme.bodyLarge,
            ),
          ),
        ],
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
      case 'completed': return Icons.check_circle_rounded;
      case 'cancelled': return Icons.cancel_rounded;
      case 'driver arrived': return Icons.pin_drop_outlined;
      default: return Icons.history_rounded;
    }
  }


  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final DateFormat dateTimeFormat = DateFormat('MMMM dd, yyyy \'at\' hh:mm a');
    final DateFormat dateFormat = DateFormat('MMMM dd, yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text('Booking #${bookingItem.bookingId.substring(0,bookingItem.bookingId.length > 6 ? 6 : bookingItem.bookingId.length)}...'), // Shortened ID
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Hero(
                tag: 'booking_history_icon_${bookingItem.bookingId}',
                child: Icon(
                  _getStatusIcon(bookingItem.status),
                  size: 70,
                  color: _getStatusColor(context, bookingItem.status),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                bookingItem.serviceType,
                style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Status: ${bookingItem.status}',
                style: textTheme.titleMedium?.copyWith(color: _getStatusColor(context, bookingItem.status)),
              ),
            ),
            const SizedBox(height: 20.0),
            const Divider(thickness: 1),

            _buildDetailRow(context, 'Booking ID:', bookingItem.bookingId, icon: Icons.vpn_key_outlined),
            _buildDetailRow(context, 'Date:', dateTimeFormat.format(bookingItem.bookingDate), icon: Icons.calendar_today_outlined),
            const SizedBox(height: 10),

            _buildDetailRow(context, 'Pickup:', bookingItem.pickupLocation, icon: Icons.my_location_outlined),
            _buildDetailRow(context, 'Drop-off:', bookingItem.dropoffLocation, icon: Icons.flag_outlined),
            const SizedBox(height: 10),

            if (bookingItem.vehicleDetails != null && bookingItem.vehicleDetails!.isNotEmpty)
              _buildDetailRow(context, 'Vehicle:', bookingItem.vehicleDetails, icon: Icons.directions_car_outlined),
            if (bookingItem.driverName != null && bookingItem.driverName!.isNotEmpty)
              _buildDetailRow(context, 'Driver:', bookingItem.driverName, icon: Icons.person_outline_rounded),

            if (bookingItem.fare != null) ...[
              const SizedBox(height: 10),
              _buildDetailRow(context, 'Fare:', '\$${bookingItem.fare!.toStringAsFixed(2)}', icon: Icons.attach_money_rounded, isEmphasized: true),
            ],

            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Rebook'),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Rebook this service (Placeholder)')),
                    );
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.rate_review_outlined),
                  label: const Text('Feedback'),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Leave feedback (Placeholder)')),
                    );
                  },
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
