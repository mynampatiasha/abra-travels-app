// lib/features/reports_analytics/vehicle_utilization_report.dart
import 'package:flutter/material.dart';

// --- Data Model embedded directly in the file ---
class VehicleUtilizationReport {
  final String vehicleId;
  final double totalDistance; // in km
  final int activeHours;
  final int idleHours;
  double get utilization => (activeHours + idleHours) > 0 ? activeHours / (activeHours + idleHours) : 0;

  VehicleUtilizationReport({
    required this.vehicleId,
    required this.totalDistance,
    required this.activeHours,
    required this.idleHours,
  });
}

// --- Report Screen ---
class VehicleUtilizationScreen extends StatefulWidget {
  // 1. ADD onBack CALLBACK
  final VoidCallback onBack;

  // 2. UPDATE CONSTRUCTOR
  const VehicleUtilizationScreen({required this.onBack, super.key});

  @override
  State<VehicleUtilizationScreen> createState() => _VehicleUtilizationScreenState();
}

class _VehicleUtilizationScreenState extends State<VehicleUtilizationScreen> {
  bool _sortAscending = true;
  int _sortColumnIndex = 0;
  late List<VehicleUtilizationReport> _reports;

  @override
  void initState() {
    super.initState();
    _reports = [ // Mock Data
      VehicleUtilizationReport(vehicleId: 'KA01AB1234', totalDistance: 1250.5, activeHours: 85, idleHours: 35),
      VehicleUtilizationReport(vehicleId: 'KA02CD5678', totalDistance: 980.2, activeHours: 60, idleHours: 60),
      VehicleUtilizationReport(vehicleId: 'KA03EF9012', totalDistance: 1523.0, activeHours: 110, idleHours: 10),
      VehicleUtilizationReport(vehicleId: 'KA04GH4567', totalDistance: 875.0, activeHours: 70, idleHours: 50),
    ];
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

  dynamic _getSortValue(VehicleUtilizationReport report, int index) {
    switch (index) {
      case 0: return report.vehicleId;
      case 1: return report.totalDistance;
      case 2: return report.activeHours;
      case 3: return report.utilization;
      default: return report.vehicleId;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 3. REMOVE SCAFFOLD AND APPBAR, RETURN CONTENT DIRECTLY
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
              DataColumn(label: const Text('Active Hours'), onSort: onSort, numeric: true),
              DataColumn(label: const Text('Utilization'), onSort: onSort, numeric: true),
            ],
            rows: _reports.map((report) => DataRow(cells: [
              DataCell(Text(report.vehicleId)),
              DataCell(Text(report.totalDistance.toStringAsFixed(1))),
              DataCell(Text(report.activeHours.toString())),
              DataCell(Text('${(report.utilization * 100).toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold))),
            ])).toList(),
          ),
        ),
      ),
    );
  }
}