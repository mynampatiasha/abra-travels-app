// File: lib/features/driver/trip_history/presentation/screens/driver_trip_history_screen.dart
// Screen for Driver to view their past trip logs, now using TripLogProvider.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // For date and time formatting
// Import the TripLogEntity
import 'package:abra_fleet/features/driver/trip_history/domain/entities/trip_log_entity.dart';
// Import the TripLogProvider
import 'package:abra_fleet/features/driver/trip_history/presentation/providers/trip_log_provider.dart';
// Import the TripLogDetailsScreen
import 'package:abra_fleet/features/driver/trip_history/presentation/screens/driver_trip_log_details_screen.dart';

class DriverTripHistoryScreen extends StatefulWidget {
  const DriverTripHistoryScreen({super.key});

  @override
  State<DriverTripHistoryScreen> createState() => _DriverTripHistoryScreenState();
}

class _DriverTripHistoryScreenState extends State<DriverTripHistoryScreen> {
  // Local mock list is no longer needed here. Data comes from TripLogProvider.
  // TODO: Add filtering capabilities if needed (e.g., by date range)

  @override
  void initState() {
    super.initState();
    // Fetch trip logs when the screen is initialized.
    // The provider itself fetches on its init, but this ensures it's called if screen is revisited
    // or if initial fetch in provider was deferred.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TripLogProvider>(context, listen: false).fetchTripLogs();
    });
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

  void _navigateToTripDetails(BuildContext context, TripLogEntity tripLog) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DriverTripLogDetailsScreen(tripLog: tripLog),
      ),
    );
    // No result handling needed here for now from details screen for driver
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final DateFormat dateFormat = DateFormat('MMM dd, yyyy');
    final DateFormat timeFormat = DateFormat('hh:mm a');

    return Scaffold(
      // AppBar is provided by MainAppShell
      body: Consumer<TripLogProvider>( // Use Consumer to listen to TripLogProvider
        builder: (context, tripLogProvider, child) {
          // Use tripLogProvider.state which is DataState enum
          if (tripLogProvider.isLoading && tripLogProvider.tripLogs.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (tripLogProvider.state == DataState.error && tripLogProvider.tripLogs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text('Error: ${tripLogProvider.errorMessage ?? "Could not load trip history."}', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => tripLogProvider.fetchTripLogs(),
                    child: const Text('Retry'),
                  )
                ],
              ),
            );
          }

          if (tripLogProvider.tripLogs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off_rounded, size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text('No Trip History Found', style: textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Your completed trips will appear here.',
                    style: textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // Get the (already sorted by provider/repositories) list of trip logs
          final displayedTripLogs = tripLogProvider.tripLogs;

          return RefreshIndicator(
            onRefresh: () => tripLogProvider.fetchTripLogs(),
            child: ListView.separated(
              padding: const EdgeInsets.all(12.0),
              itemCount: displayedTripLogs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final trip = displayedTripLogs[index];
                final distance = trip.distanceTravelled.toStringAsFixed(1);
                final duration = _formatDuration(trip.tripDuration);

                return Card(
                  elevation: 2.0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _navigateToTripDetails(context, trip),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      trip.vehicleName,
                                      style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      trip.vehicleLicensePlate,
                                      style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                dateFormat.format(trip.startTime),
                                style: textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                          const Divider(height: 20.0, thickness: 1),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildStatColumn(context, 'Start Time', timeFormat.format(trip.startTime), Icons.play_circle_outline_rounded),
                              _buildStatColumn(context, 'End Time', timeFormat.format(trip.endTime), Icons.stop_circle_outlined),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildStatColumn(context, 'Duration', duration, Icons.timer_outlined),
                              _buildStatColumn(context, 'Distance', '$distance km', Icons.social_distance_rounded),
                            ],
                          ),
                          if (trip.notes != null && trip.notes!.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text('Notes:', style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(trip.notes!, style: textTheme.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                          ]
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  // Extracted helper widget for consistency, can be kept in this file or moved to a common widgets file.
  Widget _buildStatColumn(BuildContext context, String label, String value, IconData icon) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Row(
          children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.secondary),
            const SizedBox(width: 4),
            Text(value, style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }
}
