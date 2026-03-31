// lib/features/reports_analytics/reports_analytics_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'vehicle_utilization_report.dart';
import 'fuel_efficiency_report.dart';
import 'driver_performance_report.dart';

// --- UI Constants ---
const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kTextPrimaryColor = Color(0xFF212121);
const Color kTextSecondaryColor = Color(0xFF757575);

// --- Data Model ---
class FleetAnalytics {
  final double totalDistance;
  final double fuelConsumed;
  final double totalMaintenanceCost;
  final int activeVehicles;
  final int totalVehicles;

  FleetAnalytics({
    required this.totalDistance,
    required this.fuelConsumed,
    required this.totalMaintenanceCost,
    required this.activeVehicles,
    required this.totalVehicles,
  });
}

// --- Main Dashboard Screen ---
class ReportsAnalyticsScreen extends StatefulWidget {
  const ReportsAnalyticsScreen({super.key});

  @override
  State<ReportsAnalyticsScreen> createState() => _ReportsAnalyticsScreenState();
}

class _ReportsAnalyticsScreenState extends State<ReportsAnalyticsScreen> {
  late Future<FleetAnalytics> _analyticsFuture;
  DateTime? _startDate;
  DateTime? _endDate;
  
  // --- OVERLAY MANAGEMENT STATE ---
  final List<Widget> _overlayStack = [];

  void _pushOverlay(Widget overlay) {
    setState(() {
      _overlayStack.add(overlay);
    });
  }

  void _popOverlay() {
    if (_overlayStack.isNotEmpty) {
      setState(() {
        _overlayStack.removeLast();
      });
    }
  }
  
  void _clearAllOverlays() {
    setState(() {
      _overlayStack.clear();
    });
  }

  // --- OVERLAY DISPLAY METHODS ---
  void _showVehicleUtilizationReport() {
    _pushOverlay(
      _buildOverlayWrapper(
        title: 'Vehicle Utilization',
        // IMPORTANT: Ensure VehicleUtilizationScreen accepts an onBack callback
        child: VehicleUtilizationScreen(onBack: _popOverlay),
      ),
    );
  }

  void _showFuelEfficiencyReport() {
    _pushOverlay(
      _buildOverlayWrapper(
        title: 'Fuel Efficiency',
        // IMPORTANT: Ensure FuelEfficiencyScreen accepts an onBack callback
        child: FuelEfficiencyScreen(onBack: _popOverlay),
      ),
    );
  }

  void _showDriverPerformanceReport() {
    _pushOverlay(
      _buildOverlayWrapper(
        title: 'Driver Performance',
        // IMPORTANT: Ensure DriverPerformanceScreen accepts an onBack callback
        child: DriverPerformanceScreen(onBack: _popOverlay),
      ),
    );
  }


  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = now;
    _analyticsFuture = _fetchAnalyticsData();
  }
  
  Future<FleetAnalytics> _fetchAnalyticsData() async {
    await Future.delayed(const Duration(milliseconds: 800));
    return FleetAnalytics(
      totalDistance: 12500 + ((_startDate?.day ?? 1) * 100.0),
      fuelConsumed: 1100,
      totalMaintenanceCost: 45000,
      activeVehicles: 48,
      totalVehicles: 50,
    );
  }

  void _showDateFilterOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.calendar_view_day),
            title: const Text('Select a Specific Day'),
            onTap: () async {
              Navigator.pop(context);
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: _startDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (pickedDate != null) {
                setState(() {
                  _startDate = pickedDate;
                  _endDate = pickedDate;
                  _analyticsFuture = _fetchAnalyticsData();
                });
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.date_range),
            title: const Text('Select a Date Range'),
            onTap: () async {
              Navigator.pop(context);
              final pickedRange = await showDateRangePicker(
                context: context,
                initialDateRange: _startDate != null && _endDate != null
                    ? DateTimeRange(start: _startDate!, end: _endDate!)
                    : null,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (pickedRange != null) {
                setState(() {
                  _startDate = pickedRange.start;
                  _endDate = pickedRange.end;
                  _analyticsFuture = _fetchAnalyticsData();
                });
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The Stack allows overlays to be shown on top of the main screen
    return Stack(
      children: [
        Scaffold(
          // The AppBar is removed to use the overlay pattern
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 8),
                _buildActiveFilterDisplay(),
                const SizedBox(height: 12),
                FutureBuilder<FleetAnalytics>(
                  future: _analyticsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Center(child: Text('Failed to load analytics data.'));
                    }
                    return _buildDashboardContent(snapshot.data!);
                  },
                ),
              ],
            ),
          ),
        ),
        // This spreads the list of overlays on top of the Scaffold
        ..._overlayStack,
      ],
    );
  }

  // --- WIDGETS ---

  Widget _buildOverlayWrapper({
    required String title,
    required Widget child,
  }) {
    // This wrapper provides the consistent pop-up UI
    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.95,
          height: MediaQuery.of(context).size.height * 0.90,
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _popOverlay,
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 12),
                    // Dynamic icon based on title
                    Icon(
                      title == 'Vehicle Utilization'
                          ? Icons.pie_chart_outline_rounded
                          : title == 'Fuel Efficiency'
                              ? Icons.local_gas_station_rounded
                              : Icons.speed_rounded,
                      color: kPrimaryColor,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _clearAllOverlays,
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Fleet Dashboard',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kTextPrimaryColor),
        ),
        IconButton(
          icon: const Icon(Icons.filter_list, color: kPrimaryColor),
          onPressed: _showDateFilterOptions,
          tooltip: 'Filter by Date',
        ),
      ],
    );
  }

  Widget _buildActiveFilterDisplay() {
    if (_startDate == null) return const SizedBox.shrink();

    final formatter = DateFormat('dd MMM yyyy');
    final start = formatter.format(_startDate!);
    final end = _endDate != null ? formatter.format(_endDate!) : '';
    
    final isSameDay = _endDate != null && 
                      _startDate!.year == _endDate!.year &&
                      _startDate!.month == _endDate!.month &&
                      _startDate!.day == _endDate!.day;

    final filterText = isSameDay ? 'For: $start' : 'Range: $start - $end';

    return Chip(
      label: Text(filterText),
      backgroundColor: kPrimaryColor.withOpacity(0.1),
      labelStyle: const TextStyle(color: kPrimaryColor, fontWeight: FontWeight.w500),
      deleteIcon: const Icon(Icons.cancel, size: 18),
      onDeleted: () {
        setState(() {
          _startDate = null;
          _endDate = null;
          _analyticsFuture = _fetchAnalyticsData();
        });
      },
    );
  }
  
  Widget _buildDashboardContent(FleetAnalytics data) {
    final numberFormat = NumberFormat('#,##0');
    final double uptime = data.totalVehicles > 0 ? (data.activeVehicles / data.totalVehicles) * 100 : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.5,
          children: [
            KpiCard(label: 'Total Distance', value: '${numberFormat.format(data.totalDistance)} km', icon: Icons.map_outlined),
            KpiCard(label: 'Maintenance Cost', value: '₹${numberFormat.format(data.totalMaintenanceCost)}', icon: Icons.build_circle_outlined, iconColor: Colors.orange),
            KpiCard(label: 'Fuel Consumed', value: '${numberFormat.format(data.fuelConsumed)} L', icon: Icons.local_gas_station_outlined, iconColor: Colors.red),
            KpiCard(label: 'Fleet Uptime', value: '${uptime.toStringAsFixed(1)}%', icon: Icons.check_circle_outline, iconColor: Colors.green),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Detailed Reports',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        // --- UPDATED onTap HANDLERS ---
        _buildReportNavCard(
          icon: Icons.pie_chart_outline_rounded,
          title: 'Vehicle Utilization',
          description: 'Usage patterns, idle time, and efficiency.',
          onTap: _showVehicleUtilizationReport, // Changed from Navigator
        ),
        const SizedBox(height: 12),
        _buildReportNavCard(
          icon: Icons.local_gas_station_rounded,
          title: 'Fuel Efficiency',
          description: 'Consumption analysis and cost optimization.',
          onTap: _showFuelEfficiencyReport, // Changed from Navigator
        ),
        const SizedBox(height: 12),
        _buildReportNavCard(
          icon: Icons.speed_rounded,
          title: 'Driver Performance',
          description: 'Safety scores, ratings, and feedback analysis.',
          onTap: _showDriverPerformanceReport, // Changed from Navigator
        ),
      ],
    );
  }

  Widget _buildReportNavCard({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(icon, size: 32, color: kPrimaryColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: kTextPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: kTextSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Reusable KPI Widget ---
class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  const KpiCard({
    Key? key,
    required this.label,
    required this.value,
    required this.icon,
    this.iconColor = kPrimaryColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28, color: iconColor),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: kPrimaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: kTextSecondaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}