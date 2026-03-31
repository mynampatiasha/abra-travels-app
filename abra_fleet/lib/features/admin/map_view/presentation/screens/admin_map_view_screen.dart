// File: lib/features/admin/map_view/presentation/screens/admin_map_view_screen.dart
// Admin screen for map view - Google Maps integration is temporarily disabled.

import 'package:flutter/material.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart'; // Map temporarily disabled
// import 'package:provider/provider.dart';
// import 'package:abra_fleet/features/admin/vehicle_management/presentation/providers/vehicle_provider.dart';
// import 'package:abra_fleet/features/admin/vehicle_management/domain/entities/vehicle_entity.dart';

class AdminMapViewScreen extends StatefulWidget {
  const AdminMapViewScreen({super.key});

  @override
  State<AdminMapViewScreen> createState() => _AdminMapViewScreenState();
}

class _AdminMapViewScreenState extends State<AdminMapViewScreen> {
  // --- Fields related to Google Maps are commented out or removed for now ---
  // final Completer<GoogleMapController> _mapController = Completer();
  // Set<Marker> _markers = {};
  // static const CameraPosition _initialCameraPosition = CameraPosition(...);
  // final Map<String, LatLng> _mockVehicleLocations = { ... };

  @override
  void initState() {
    super.initState();
    // No need to fetch vehicle locations if map is disabled
  }

  // void _buildMarkers(List<Vehicle> vehicles, Map<String, LatLng> locations) {
  //   // Marker building logic removed for now
  // }

  // void _simulateOneVehicleUpdate() {
  //   // Simulation logic removed for now
  // }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // final vehicleProvider = context.watch<VehicleProvider>(); // Not used if map is disabled

    return Scaffold(
      // AppBar is provided by MainAppShell
      body: Container( // Simple placeholder instead of GoogleMap
        color: Colors.blueGrey[50],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, size: 100, color: Colors.blueGrey[300]),
              const SizedBox(height: 20),
              Text(
                'Map View Temporarily Disabled',
                style: textTheme.headlineSmall?.copyWith(color: Colors.blueGrey[700]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30.0),
                child: Text(
                  'Google Maps integration is paused. Set up your API key to enable live map features.',
                  style: textTheme.titleMedium?.copyWith(color: Colors.blueGrey[500]),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              // You can add placeholder buttons for search/filter if desired,
              // similar to the earlier placeholder version of this screen.
              // For now, keeping it simple.
            ],
          ),
        ),
      ),
      // FloatingActionButton for simulating update removed for now
      // floatingActionButton: FloatingActionButton.extended(
      //   onPressed: _simulateOneVehicleUpdate, // This would cause an error now
      //   label: const Text('Simulate Update'),
      //   icon: const Icon(Icons.track_changes_rounded),
      // ),
    );
  }
}
