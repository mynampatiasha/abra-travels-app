// lib/features/reports_analytics/driver_performance_report.dart
import 'package:flutter/material.dart';

// --- Data Model embedded directly in the file ---
class DriverPerformanceReport {
  final String driverName;
  final double safetyScore;
  final int trips;
  final int harshBrakingEvents;

  DriverPerformanceReport({
    required this.driverName,
    required this.safetyScore,
    required this.trips,
    required this.harshBrakingEvents,
  });
}

// --- Report Screen ---
class DriverPerformanceScreen extends StatefulWidget {
  // 1. ADD onBack CALLBACK
  final VoidCallback onBack;

  // 2. UPDATE CONSTRUCTOR
  const DriverPerformanceScreen({required this.onBack, super.key});

  @override
  State<DriverPerformanceScreen> createState() => _DriverPerformanceScreenState();
}

class _DriverPerformanceScreenState extends State<DriverPerformanceScreen> {
  bool _sortAscending = false;
  int _sortColumnIndex = 1;
  late List<DriverPerformanceReport> _reports;

  @override
  void initState() {
    super.initState();
    _reports = [ // Mock Data
      DriverPerformanceReport(driverName: 'Ahmed Hassan', safetyScore: 92.5, trips: 45, harshBrakingEvents: 3),
      DriverPerformanceReport(driverName: 'Mohammed Ali', safetyScore: 85.0, trips: 52, harshBrakingEvents: 12),
      DriverPerformanceReport(driverName: 'Fatima Khan', safetyScore: 98.2, trips: 48, harshBrakingEvents: 1),
      DriverPerformanceReport(driverName: 'Yusuf Ibrahim', safetyScore: 76.8, trips: 60, harshBrakingEvents: 25),
    ];
    onSort(_sortColumnIndex, _sortAscending); // Initial sort
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

  dynamic _getSortValue(DriverPerformanceReport report, int index) {
    switch (index) {
      case 0: return report.driverName;
      case 1: return report.safetyScore;
      case 2: return report.trips;
      case 3: return report.harshBrakingEvents;
      default: return report.driverName;
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
              DataColumn(label: const Text('Driver'), onSort: onSort),
              DataColumn(label: const Text('Safety Score'), onSort: onSort, numeric: true),
              DataColumn(label: const Text('Trips'), onSort: onSort, numeric: true),
              DataColumn(label: const Text('Harsh Braking'), onSort: onSort, numeric: true),
            ],
            rows: _reports.map((report) => DataRow(cells: [
              DataCell(Text(report.driverName)),
              DataCell(Text(report.safetyScore.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold))),
              DataCell(Text(report.trips.toString())),
              DataCell(Text(report.harshBrakingEvents.toString())),
            ])).toList(),
          ),
        ),
      ),
    );
  }
}