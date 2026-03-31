// File: lib/features/driver/trip_history/presentation/screens/driver_trip_log_details_screen.dart
// Screen for Driver to view detailed information about a specific trip log.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For date and time formatting
// Import the TripLogEntity
import 'package:abra_fleet/features/driver/trip_history/domain/entities/trip_log_entity.dart';

class DriverTripLogDetailsScreen extends StatelessWidget {
  final TripLogEntity tripLog;

  const DriverTripLogDetailsScreen({super.key, required this.tripLog});

  Widget _buildDetailRow(BuildContext context, String label, String? value, {IconData? icon, bool isHighlighted = false}) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: isHighlighted ? colorScheme.primary : colorScheme.secondary),
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
              style: isHighlighted
                  ? textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary)
                  : textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    if (duration.inHours > 0) {
      return "${duration.inHours}h ${twoDigitMinutes}m";
    } else if (duration.inMinutes > 0) {
      return "${twoDigitMinutes}m";
    } else {
      return "${duration.inSeconds}s";
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final DateFormat dateFormat = DateFormat('MMMM dd, yyyy'); // Full date
    final DateFormat timeFormat = DateFormat('hh:mm a');
    final String distance = tripLog.distanceTravelled.toStringAsFixed(1);
    final String duration = _formatDuration(tripLog.tripDuration);

    return Scaffold(
      appBar: AppBar(
        title: Text('Trip on ${dateFormat.format(tripLog.startTime)}'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Hero(
                tag: 'trip_log_icon_${tripLog.id}',
                child: Icon(Icons.receipt_long_rounded, size: 70, color: Theme.of(context).colorScheme.primary),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Trip Summary',
                style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Vehicle: ${tripLog.vehicleName} (${tripLog.vehicleLicensePlate})',
                style: textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 20.0),
            const Divider(thickness: 1),

            _buildDetailRow(context, 'Trip ID:', tripLog.id, icon: Icons.vpn_key_outlined),
            _buildDetailRow(context, 'Date:', dateFormat.format(tripLog.startTime), icon: Icons.calendar_today_outlined),
            const SizedBox(height: 10),

            _buildDetailRow(context, 'Start Time:', timeFormat.format(tripLog.startTime), icon: Icons.access_time_rounded),
            _buildDetailRow(context, 'Start Odometer:', '${tripLog.startOdometer.toStringAsFixed(0)} km', icon: Icons.speed_outlined),
            if (tripLog.startLocation != null && tripLog.startLocation!.isNotEmpty)
              _buildDetailRow(context, 'Start Location:', tripLog.startLocation, icon: Icons.location_on_outlined),
            const SizedBox(height: 10),

            _buildDetailRow(context, 'End Time:', timeFormat.format(tripLog.endTime), icon: Icons.access_time_filled_rounded),
            _buildDetailRow(context, 'End Odometer:', '${tripLog.endOdometer.toStringAsFixed(0)} km', icon: Icons.speed_rounded),
            if (tripLog.endLocation != null && tripLog.endLocation!.isNotEmpty)
              _buildDetailRow(context, 'End Location:', tripLog.endLocation, icon: Icons.location_on_rounded),
            const SizedBox(height: 10),

            _buildDetailRow(context, 'Trip Duration:', duration, icon: Icons.timer_outlined, isHighlighted: true),
            _buildDetailRow(context, 'Distance:', '$distance km', icon: Icons.social_distance_rounded, isHighlighted: true),

            if (tripLog.notes != null && tripLog.notes!.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 10),
              Text('Trip Notes:', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Container(
                  padding: const EdgeInsets.all(12),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(tripLog.notes!, style: textTheme.bodyLarge)
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
