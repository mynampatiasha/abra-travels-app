// File: lib/features/admin/reports/presentation/screens/vehicle_performance_report_screen.dart
// Screen to display a vehicle performance report.

import 'package:flutter/material.dart';
import 'dart:math'; // For random data

// Simple data model for this report's data
class VehiclePerformanceData {
  final String vehicleName;
  final String licensePlate;
  final double totalDistance; // in km
  final double totalFuel; // in liters
  final Duration totalActiveHours;
  final Duration totalIdleHours;

  VehiclePerformanceData({
    required this.vehicleName,
    required this.licensePlate,
    required this.totalDistance,
    required this.totalFuel,
    required this.totalActiveHours,
    required this.totalIdleHours,
  });

  // Calculated property for fuel efficiency
  double get fuelEfficiency { // km/l
    if (totalFuel <= 0) return 0;
    return totalDistance / totalFuel;
  }
}

class VehiclePerformanceReportScreen extends StatefulWidget {
  const VehiclePerformanceReportScreen({super.key});

  @override
  State<VehiclePerformanceReportScreen> createState() => _VehiclePerformanceReportScreenState();
}

class _VehiclePerformanceReportScreenState extends State<VehiclePerformanceReportScreen> {
  // Mock data for the report (in a real app, this would be fetched from a provider/repository)
  final List<VehiclePerformanceData> _reportData = [
    VehiclePerformanceData(vehicleName: 'Cargo Van 1', licensePlate: 'AB-123-CD', totalDistance: 1250.5, totalFuel: 156.3, totalActiveHours: const Duration(hours: 40, minutes: 30), totalIdleHours: const Duration(hours: 8, minutes: 15)),
    VehiclePerformanceData(vehicleName: 'Sedan Alpha', licensePlate: 'XY-789-ZW', totalDistance: 850.2, totalFuel: 85.0, totalActiveHours: const Duration(hours: 28, minutes: 45), totalIdleHours: const Duration(hours: 5, minutes: 20)),
    VehiclePerformanceData(vehicleName: 'Pickup Truck 03', licensePlate: 'GH-456-JK', totalDistance: 1500.0, totalFuel: 214.2, totalActiveHours: const Duration(hours: 55, minutes: 10), totalIdleHours: const Duration(hours: 12, minutes: 5)),
    VehiclePerformanceData(vehicleName: 'Heavy Truck Zeta', licensePlate: 'QR-678-ST', totalDistance: 2105.8, totalFuel: 421.1, totalActiveHours: const Duration(hours: 70, minutes: 0), totalIdleHours: const Duration(hours: 15, minutes: 30)),
  ];

  Widget _buildSummaryMetric(BuildContext context, {required IconData icon, required String label, required String value, required Color color}) {
    return Card(
      elevation: 0,
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black87)),
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChartPlaceholder(BuildContext context) {
    // This is a simple visual representation, not a real chart.
    // Use a package like fl_chart for actual charting.
    final maxValue = _reportData.map((d) => d.totalDistance).reduce(max);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Distance by Vehicle (km)', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _reportData.map((data) {
                final barHeight = (data.totalDistance / maxValue) * 120.0; // Max height of 120
                return Column(
                  children: [
                    Container(
                      height: barHeight,
                      width: 25,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 4),
                    Text(data.vehicleName.split(' ').first, style: Theme.of(context).textTheme.bodySmall)
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    // Calculate overall totals
    final double overallDistance = _reportData.map((d) => d.totalDistance).fold(0, (a, b) => a + b);
    final double overallFuel = _reportData.map((d) => d.totalFuel).fold(0, (a, b) => a + b);
    final Duration overallActiveTime = _reportData.map((d) => d.totalActiveHours).fold(Duration.zero, (a, b) => a + b);
    final double overallEfficiency = overallFuel > 0 ? overallDistance / overallFuel : 0;


    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Performance Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range_rounded),
            tooltip: 'Select Date Range',
            onPressed: () {
              // TODO: Implement date range picker
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Date range picker placeholder')),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text('Report Summary', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          Text('Showing data for: Last 30 Days', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.5,
            ),
            children: [
              _buildSummaryMetric(context, icon: Icons.multiple_stop_rounded, label: 'Total Distance', value: '${overallDistance.toStringAsFixed(0)} km', color: Colors.blue.shade800),
              _buildSummaryMetric(context, icon: Icons.local_gas_station_rounded, label: 'Avg. Efficiency', value: '${overallEfficiency.toStringAsFixed(1)} km/l', color: Colors.green.shade800),
              _buildSummaryMetric(context, icon: Icons.timer_rounded, label: 'Total Active Time', value: '${overallActiveTime.inHours}h ${overallActiveTime.inMinutes.remainder(60)}m', color: Colors.orange.shade800),
              _buildSummaryMetric(context, icon: Icons.directions_car, label: 'Total Vehicles', value: _reportData.length.toString(), color: Colors.purple.shade800),
            ],
          ),
          const SizedBox(height: 24),
          _buildBarChartPlaceholder(context),
          const SizedBox(height: 24),
          Text('Detailed Breakdown', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            elevation: 2,
            child: DataTable(
              columnSpacing: 12,
              columns: const [
                DataColumn(label: Text('Vehicle', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Distance', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                DataColumn(label: Text('Fuel (km/l)', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                DataColumn(label: Text('Active (h)', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
              ],
              rows: _reportData.map((data) => DataRow(
                  cells: [
                    // CORRECTED from data.name to data.vehicleName
                    DataCell(Text(data.vehicleName, overflow: TextOverflow.ellipsis)),
                    DataCell(Text(data.totalDistance.toStringAsFixed(0))),
                    DataCell(Text(data.fuelEfficiency.toStringAsFixed(1))),
                    DataCell(Text(data.totalActiveHours.inHours.toString())),
                  ]
              )).toList(),
            ),
          )
        ],
      ),
    );
  }
}
