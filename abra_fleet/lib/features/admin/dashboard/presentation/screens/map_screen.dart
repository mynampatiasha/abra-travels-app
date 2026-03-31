import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapScreen extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String customerName;
  final VoidCallback onBack; // Callback to close this view

  const MapScreen({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.customerName,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(latitude, longitude),
            initialZoom: 16.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.abra_fleet', // Replace with your actual package name
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(latitude, longitude),
                  width: 120,
                  height: 80,
                  child: Column(
                    children: [
                      Icon(Icons.location_on, color: Colors.red.shade700, size: 40),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.black54),
                        ),
                        child: Text(
                          customerName,
                          style: TextStyle(color: Colors.red[900], fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        Positioned(
          top: 16,
          left: 16,
          child: FloatingActionButton.small(
            onPressed: onBack,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            child: const Icon(Icons.close),
            tooltip: 'Close Map',
          ),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'Tracking SOS: $customerName',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ],
    );
  }
}