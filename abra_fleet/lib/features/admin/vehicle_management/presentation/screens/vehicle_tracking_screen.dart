// lib/features/admin/vehicle_management/presentation/screens/vehicle_tracking_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../providers/trip_tracking_provider.dart';

class VehicleTrackingScreen extends StatefulWidget {
  final String vehicleId;
  final String? tripId;

  const VehicleTrackingScreen({
    Key? key,
    required this.vehicleId,
    this.tripId,
  }) : super(key: key);

  @override
  _VehicleTrackingScreenState createState() => _VehicleTrackingScreenState();
}

class _VehicleTrackingScreenState extends State<VehicleTrackingScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final CameraPosition _initialPosition = const CameraPosition(
    target: LatLng(0, 0), // Default position, will be updated
    zoom: 15,
  );

  @override
  void initState() {
    super.initState();
    // Start tracking if tripId is provided
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.tripId != null) {
        context.read<TripTrackingProvider>().startTracking(widget.tripId!);
      }
    });
  }

  @override
  void dispose() {
    // Stop tracking when screen is disposed
    context.read<TripTrackingProvider>().stopTracking();
    _mapController?.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Tracking'),
        actions: [
          // Status indicator in app bar
          Consumer<TripTrackingProvider>(
            builder: (context, tripProvider, _) {
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Row(
                  children: [
                    _buildStatusIndicator(tripProvider.status),
                    const SizedBox(width: 8),
                    Text(
                      tripProvider.status.toUpperCase(),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Map view
          Expanded(
            child: Consumer<TripTrackingProvider>(
              builder: (context, tripProvider, _) {
                // Update marker when location changes
                if (tripProvider.currentLocation != null) {
                  final marker = Marker(
                    markerId: const MarkerId('vehicle_location'),
                    position: tripProvider.currentLocation!,
                    infoWindow: const InfoWindow(title: 'Your Vehicle'),
                  );
                  _markers.clear();
                  _markers.add(marker);

                  // Move camera to new location
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLng(tripProvider.currentLocation!),
                  );
                }

                return GoogleMap(
                  onMapCreated: _onMapCreated,
                  initialCameraPosition: _initialPosition,
                  markers: _markers,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: true,
                );
              },
            ),
          ),
          // Control buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Consumer<TripTrackingProvider>(
                  builder: (context, tripProvider, _) {
                    return ElevatedButton.icon(
                      onPressed: tripProvider.isTracking
                          ? null
                          : () {
                              if (widget.tripId != null) {
                                tripProvider.startTracking(widget.tripId!);
                              }
                            },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Tracking'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    );
                  },
                ),
                Consumer<TripTrackingProvider>(
                  builder: (context, tripProvider, _) {
                    return ElevatedButton.icon(
                      onPressed: tripProvider.isTracking
                          ? () {
                              tripProvider.stopTracking();
                            }
                          : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(String status) {
    Color color;
    switch (status) {
      case 'connected':
        color = Colors.green;
        break;
      case 'connecting':
        color = Colors.orange;
        break;
      case 'error':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}