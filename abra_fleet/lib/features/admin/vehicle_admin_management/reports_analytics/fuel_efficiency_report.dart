// lib/features/reports_analytics/fuel_efficiency_report.dart
import 'package:flutter/material.dart';

// --- Data Model embedded directly in the file ---
class FuelEfficiencyReport {
  final String vehicleId;
  final double totalDistance;
  final double fuelConsumed;
  double get efficiency => fuelConsumed > 0 ? totalDistance / fuelConsumed : 0; // km/L

  FuelEfficiencyReport({
    required this.vehicleId,
    required this.totalDistance,
    required this.fuelConsumed,
  });
}

// --- Report Screen ---
class FuelEfficiencyScreen extends StatefulWidget {
  // 1. ADD THE onBack CALLBACK
  final VoidCallback onBack;

  // 2. UPDATE THE CONSTRUCTOR
  const FuelEfficiencyScreen({required this.onBack, super.key});

  @override
  State<FuelEfficiencyScreen> createState() => _FuelEfficiencyScreenState();
}

class _FuelEfficiencyScreenState extends State<FuelEfficiencyScreen> {
  bool _sortAscending = false;
  int _sortColumnIndex = 3;
  late List<FuelEfficiencyReport> _reports;

  @override
  void initState() {
    super.initState();
     _reports = [ // Mock Data
      FuelEfficiencyReport(vehicleId: 'KA01AB1234', totalDistance: 1250.5, fuelConsumed: 120.5),
      FuelEfficiencyReport(vehicleId: 'KA02CD5678', totalDistance: 980.2, fuelConsumed: 105.0),
      FuelEfficiencyReport(vehicleId: 'KA03EF9012', totalDistance: 1523.0, fuelConsumed: 115.8),
      FuelEfficiencyReport(vehicleId: 'KA04GH4567', totalDistance: 875.0, fuelConsumed: 95.2),
    ];
    onSort(_sortColumnIndex, _sortAscending); // Initial sort by efficiency
  }

   void onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      _reports.sort((a, b) {
        final valueA = _getSortValue(a, columnIndex);
        final valueB = _getSortValue(b, columnIndex);
        return ascending ? Comparable.compare(valueA, valueB) : Comparable.compare(valueB, valueA);
      });
    });
  }

  dynamic _getSortValue(FuelEfficiencyReport report, int index) {
    switch (index) {
      case 0: return report.vehicleId;
      case 1: return report.totalDistance;
      case 2: return report.fuelConsumed;
      case 3: return report.efficiency;
      default: return report.vehicleId;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 3. REMOVE THE SCAFFOLD AND APPBAR
    // This widget should only return its direct content. The overlay provides the frame.
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            columns: [
              DataColumn(label: const Text('Vehicle'), onSort: onSort),
              DataColumn(label: const Text('Distance (km)'), onSort: onSort, numeric: true),
              DataColumn(label: const Text('Fuel Used (L)'), onSort: onSort, numeric: true),
              DataColumn(label: const Text('Efficiency (km/L)'), onSort: onSort, numeric: true),
            ],
            rows: _reports.map((report) => DataRow(cells: [
              DataCell(Text(report.vehicleId)),
              DataCell(Text(report.totalDistance.toStringAsFixed(1))),
              DataCell(Text(report.fuelConsumed.toStringAsFixed(1))),
              DataCell(Text(report.efficiency.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
            ])).toList(),
          ),
        ),
      ),
    );
  }
}