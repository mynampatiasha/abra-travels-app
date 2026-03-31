// File: lib/features/customer/dashboard/presentation/screens/mystats_screen.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import '../../../dashboard/data/services/customer_stats_service.dart';

class MyStatsScreen extends StatefulWidget {
  // UPDATE: Add a callback for back navigation
  final VoidCallback? onNavigateBack;
  
  const MyStatsScreen({
    super.key,
    this.onNavigateBack, // Make it optional
  });

  @override
  State<MyStatsScreen> createState() => MyStatsScreenState();
}

class MyStatsScreenState extends State<MyStatsScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  final CustomerStatsService _statsService = CustomerStatsService();

  // Data variables
  Map<String, dynamic> _statsData = {};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _loadStatsData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  // Public method to allow parent to refresh this screen's data
  Future<void> loadStatsData() async {
    return _loadStatsData();
  }

  Future<void> _loadStatsData() async {
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }

      debugPrint('📊 Loading customer stats data...');

      // Fetch all stats data from backend
      final allStats = await _statsService.getAllStats();

      debugPrint('✅ Stats data received: ${allStats.keys}');
      debugPrint('📈 Total trips: ${allStats['totalTrips']}');
      debugPrint('📏 Total distance: ${allStats['totalDistance']}');

      if (mounted) {
        _animationController.reset();
        setState(() {
          _statsData = allStats;
          _isLoading = false;
        });
        _animationController.forward();
      }

    } catch (e) {
      debugPrint('❌ Error loading stats: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load statistics: ${e.toString()}';
          _statsData = {}; 
        });
      }
    }
  }

  // Your existing _getSampleData method is preserved
  Map<String, dynamic> _getSampleData() {
    return {
      'totalTrips': {'completed': 45, 'ongoing': 3, 'cancelled': 7},
      'onTimeDelivery': {'onTime': 42, 'delayed': 8},
      'totalDistance': 2847.5,
      'monthlyDistance': [
        {'month': 'Jan', 'distance': 245.2},
        {'month': 'Feb', 'distance': 312.8},
        {'month': 'Mar', 'distance': 289.4},
        {'month': 'Apr', 'distance': 356.7},
        {'month': 'May', 'distance': 398.2},
        {'month': 'Jun', 'distance': 434.1},
      ],
      'weeklyBookings': [2, 4, 3, 5, 2, 6, 4, 3, 5, 2, 4, 3],
      'topRoutes': [
        {'route': 'Airport → Downtown', 'count': 15},
        {'route': 'Home → Office', 'count': 12},
        {'route': 'Mall → Residential', 'count': 8},
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = screenSize.width > 1200;
    final isMobile = screenSize.width <= 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 1,
        
        title: const Text(
          'Activity Report',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              _loadStatsData();
            },
            tooltip: 'Refresh Stats',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildErrorState()
          : AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(isDesktop ? 32.0 : isMobile ? 16.0 : 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatsHeader(context, isDesktop, isMobile),
                SizedBox(height: isDesktop ? 32 : 24),
                _buildTripCounters(context, isDesktop, isMobile),
                const SizedBox(height: 24),
                _buildDistanceSummary(context, isDesktop, isMobile),
                const SizedBox(height: 24),
                _buildMonthlyDistanceChart(context, isDesktop, isMobile),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  // Your existing _buildErrorState and _buildStatsHeader methods are preserved
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red[300],
          ),
          const SizedBox(height: 16),
          Text(
            'Unable to load statistics',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ?? 'An error occurred while fetching your stats. Please try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadStatsData,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader(BuildContext context, bool isDesktop, bool isMobile) {
    final lastUpdated = _statsData['lastUpdated'];

    return Container(
      padding: EdgeInsets.all(isDesktop ? 32 : 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).primaryColor,
            Theme.of(context).primaryColor.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withOpacity(0.3),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Trip Statistics',
                  style: TextStyle(
                    fontSize: isDesktop ? 28 : isMobile ? 20 : 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Track your travel patterns and service usage',
                  style: TextStyle(
                    fontSize: isDesktop ? 16 : 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                if (lastUpdated != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Last updated: ${_formatDateTime(lastUpdated)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 24),
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.analytics_rounded,
                color: Colors.white,
                size: 50,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // UPDATE: This widget is updated to include the total trips badge.
  Widget _buildTripCounters(BuildContext context, bool isDesktop, bool isMobile) {
    final trips = _statsData['totalTrips'] as Map<String, dynamic>? ?? {};
    final num completed = trips['completed'] ?? 0;
    final num ongoing = trips['ongoing'] ?? 0;
    final num cancelled = trips['cancelled'] ?? 0;
    final num total = trips['total'] ?? (completed + ongoing + cancelled);
    
    if (total == 0 && !_isLoading) {
       return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
              )
            ]
        ),
        height: 150,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, color: Colors.grey[400], size: 48),
              const SizedBox(height: 16),
              Text(
                'No trips or rosters found',
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Create a new roster to get started!',
                style: TextStyle(color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // This is the new Row for the title and the badge
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Total Trips Booked',
              style: TextStyle(
                fontSize: isDesktop ? 24 : 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(width: 12),
            // The new circle badge
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
              child: Text(
                total.toString(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
  children: [
    Expanded(
      child: _buildStatCard(
        'Completed',
        completed.toString(),
        Colors.green,
        Icons.check_circle,
        _animation.value,
      ),
    ),
    Expanded(
      child: _buildStatCard(
        'Today',  // ← Changed from "Ongoing"
        ongoing.toString(),
        Colors.blue,
        Icons.today,
        _animation.value,
      ),
    ),
    Expanded(
      child: _buildStatCard(
        'Cancelled',
        cancelled.toString(),
        Colors.red,
        Icons.cancel,
        _animation.value,
      ),
    ),
  ],
),
        const SizedBox(height: 16),
        Container(
          height: 100,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: total > 0 ? [completed, ongoing, cancelled].reduce(max).toDouble() + 10 : 10,
              barGroups: [
                BarChartGroupData(
                  x: 0,
                  barRods: [
                    BarChartRodData(
                      toY: completed.toDouble() * _animation.value,
                      color: Colors.green,
                      width: 40,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
                BarChartGroupData(
                  x: 1,
                  barRods: [
                    BarChartRodData(
                      toY: ongoing.toDouble() * _animation.value,
                      color: Colors.blue,
                      width: 40,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
                BarChartGroupData(
                  x: 2,
                  barRods: [
                    BarChartRodData(
                      toY: cancelled.toDouble() * _animation.value,
                      color: Colors.red,
                      width: 40,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ],
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final titles = ['Completed', 'Ongoing', 'Cancelled'];
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          titles[value.toInt()],
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(show: false),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
      ],
    );
  }

  // Build distance summary card with vehicle and driver details
  Widget _buildDistanceSummary(BuildContext context, bool isDesktop, bool isMobile) {
    final totalDistance = _statsData['totalDistance'] ?? 0.0;
    final recentTrip = _statsData['recentTrip']; // Backend provides this data
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).primaryColor.withOpacity(0.8),
            Theme.of(context).primaryColor,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withOpacity(0.3),
            spreadRadius: 0,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.route,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Distance Traveled',
                      style: TextStyle(
                        fontSize: isDesktop ? 18 : 16,
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        final animatedDistance = (totalDistance * _animation.value);
                        return Text(
                          '${animatedDistance.toStringAsFixed(1)} km',
                          style: TextStyle(
                            fontSize: isDesktop ? 36 : 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // Vehicle and Driver details section
          if (recentTrip != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.white.withOpacity(0.8),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Recent Trip Details',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Vehicle Number
                            Row(
                              children: [
                                const Icon(Icons.directions_car, color: Colors.white, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Vehicle: ',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  recentTrip['vehicleNumber'] ?? 'N/A',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Driver Name
                            Row(
                              children: [
                                const Icon(Icons.person, color: Colors.white, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Driver: ',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 13,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    recentTrip['driverName'] ?? 'N/A',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Driver Phone
                            Row(
                              children: [
                                const Icon(Icons.phone, color: Colors.white, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Phone: ',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  recentTrip['driverPhone'] ?? 'N/A',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            // Distance for this trip
                            if (recentTrip['distance'] != null && recentTrip['distance'] > 0) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.straighten, color: Colors.white, size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Trip Distance: ',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    '${(recentTrip['distance'] ?? 0).toStringAsFixed(1)} km',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            // Show message when no recent trip data is available
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.white.withOpacity(0.6),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No recent trip details available',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // All your other _build... methods are preserved and unchanged.
    Widget _buildOnTimeDeliveryChart(BuildContext context, bool isDesktop, bool isMobile) {
    final delivery = _statsData['onTimeDelivery'] as Map<String, dynamic>? ?? {};
    final onTime = delivery['onTime'] ?? 0;
    final delayed = delivery['delayed'] ?? 0;
    final total = onTime + delayed;

    if (total == 0) {
      return _buildChartContainer(
        'On-Time vs Delayed Deliveries',
        Container(
          height: 200,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, color: Colors.grey[400], size: 48),
                const SizedBox(height: 16),
                Text(
                  'No completed trips yet',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final onTimePercentage = (onTime / total * 100).round();

    return _buildChartContainer(
      'On-Time vs Delayed Deliveries',
      Container(
        height: 200,
        child: PieChart(
          PieChartData(
            sections: [
              PieChartSectionData(
                color: Colors.green,
                value: onTime.toDouble() * _animation.value,
                title: '${onTimePercentage}%\nOn-Time',
                titleStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                radius: 80,
              ),
              PieChartSectionData(
                color: Colors.orange,
                value: delayed.toDouble() * _animation.value,
                title: '${100 - onTimePercentage}%\nDelayed',
                titleStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                radius: 80,
              ),
            ],
            sectionsSpace: 2,
            centerSpaceRadius: 40,
          ),
        ),
      ),
    );
  }

  Widget _buildDistanceChart(BuildContext context, bool isDesktop, bool isMobile) {
    final monthlyData = _statsData['monthlyDistance'] as List<dynamic>? ?? [];
    final totalDistance = _statsData['totalDistance'] ?? 0.0;

    if (monthlyData.isEmpty) {
      return _buildChartContainer(
        'Distance Covered Over Time (${totalDistance.toStringAsFixed(1)} km total)',
        Container(
          height: 200,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, color: Colors.grey[400], size: 48),
                const SizedBox(height: 16),
                Text(
                  'No distance data available',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final chartData = List<Map<String, dynamic>>.from(monthlyData);

    return _buildChartContainer(
      'Distance Covered Over Time (${totalDistance.toStringAsFixed(1)} km total)',
      Container(
        height: 200,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 100,
            ),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    if (value.toInt() < chartData.length) {
                      return Text(
                        chartData[value.toInt()]['month'],
                        style: const TextStyle(fontSize: 12),
                      );
                    }
                    return const Text('');
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    return Text('${value.toInt()}km', style: const TextStyle(fontSize: 10));
                  },
                  interval: 100,
                ),
              ),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: chartData.asMap().entries.map((entry) {
                  return FlSpot(
                    entry.key.toDouble(),
                    (entry.value['distance'] ?? 0.0).toDouble() * _animation.value,
                  );
                }).toList(),
                isCurved: true,
                color: Theme.of(context).primaryColor,
                barWidth: 3,
                dotData: FlDotData(show: true),
                belowBarData: BarAreaData(
                  show: true,
                  color: Theme.of(context).primaryColor.withOpacity(0.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon, double animationValue) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              final numericValue = int.tryParse(value) ?? 0;
              final animatedValue = (numericValue * animationValue).round();
              return Text(
                animatedValue.toString(),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              );
            },
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartContainer(String title, Widget chart) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 0,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          chart,
        ],
      ),
    );
  }

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'Unknown';

    try {
      final DateTime dt = dateTime is String ? DateTime.parse(dateTime) : dateTime;
      final now = DateTime.now();
      final difference = now.difference(dt);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}h ago';
      } else {
        return '${dt.day}/${dt.month}/${dt.year}';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  // Monthly Distance for Billing - Simple Data Display
  Widget _buildMonthlyDistanceChart(BuildContext context, bool isDesktop, bool isMobile) {
    return _buildMonthlyDistanceBilling(context, isDesktop, isMobile);
  }

  // Monthly Distance Billing - Data-driven, no charts
  Widget _buildMonthlyDistanceBilling(BuildContext context, bool isDesktop, bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 0,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.receipt_long, color: Colors.blue, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monthly Distance for Billing',
                      style: TextStyle(
                        fontSize: isDesktop ? 20 : 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    Text(
                      'Track your monthly travel for billing purposes',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Monthly Distance Billing Widget
          _MonthlyDistanceBillingWidget(),
        ],
      ),
    );
  }
}

// Monthly Distance Billing Widget - Separate StatefulWidget for clean data management
class _MonthlyDistanceBillingWidget extends StatefulWidget {
  @override
  _MonthlyDistanceBillingWidgetState createState() => _MonthlyDistanceBillingWidgetState();
}

class _MonthlyDistanceBillingWidgetState extends State<_MonthlyDistanceBillingWidget> {
  final CustomerStatsService _statsService = CustomerStatsService();
  
  Map<String, dynamic> _billingData = {};
  bool _isLoading = true;
  String? _selectedMonth;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBillingData();
  }

  Future<void> _loadBillingData({String? month}) async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final data = await _statsService.getMonthlyDistanceForBilling(
        selectedMonth: month,
      );

      if (mounted) {
        setState(() {
          _billingData = data;
          _selectedMonth = month;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load billing data: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 200,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Container(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red[300], size: 48),
              const SizedBox(height: 16),
              Text(
                'Error loading billing data',
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => _loadBillingData(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final totalDistance = _billingData['totalDistance'] ?? 0.0;
    final todayDistance = _billingData['todayDistance'] ?? 0.0;
    final todayTrips = _billingData['todayTrips'] ?? 0;
    final availableMonths = _billingData['availableMonths'] as List<dynamic>? ?? [];
    final selectedMonthData = _billingData['selectedMonthData'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary Cards
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Total Distance',
                '${totalDistance.toStringAsFixed(1)} km',
                Icons.straighten,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                'Today\'s Distance',
                todayTrips > 0 ? '${todayDistance.toStringAsFixed(1)} km' : 'No trips today',
                Icons.today,
                Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Month Filter Dropdown
        if (availableMonths.isNotEmpty) ...[
          Row(
            children: [
              Text(
                'Select Month for Billing Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedMonth,
                    hint: Text(
                      'All Time',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                    items: [
                      // "All Time" option
                      DropdownMenuItem<String>(
                        value: null,
                        child: Row(
                          children: [
                            Icon(Icons.all_inclusive, size: 16, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              'All Time',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Month options
                      ...availableMonths.map((month) {
                        final monthKey = month['key'];
                        final monthName = month['name']; // Use full name for dropdown
                        return DropdownMenuItem<String>(
                          value: monthKey,
                          child: Row(
                            children: [
                              Icon(Icons.calendar_month, size: 16, color: Colors.blue),
                              const SizedBox(width: 8),
                              Text(
                                monthName,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                    onChanged: (String? newValue) {
                      _loadBillingData(month: newValue);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],

        // Selected Month Data
        if (selectedMonthData != null) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade50, Colors.blue.shade100],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_month, color: Colors.blue.shade700, size: 24),
                    const SizedBox(width: 12),
                    Text(
                      selectedMonthData['monthName'] ?? 'Selected Month',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Distance',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blue.shade600,
                            ),
                          ),
                          Text(
                            '${selectedMonthData['totalDistance']?.toStringAsFixed(1) ?? '0.0'} km',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Trips',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blue.shade600,
                            ),
                          ),
                          Text(
                            '${selectedMonthData['totalTrips'] ?? 0}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Daily Breakdown
                if (selectedMonthData['dailyBreakdown'] != null && 
                    (selectedMonthData['dailyBreakdown'] as List).isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Daily Breakdown',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Column(
                        children: (selectedMonthData['dailyBreakdown'] as List).map((dayData) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.withOpacity(0.1)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${dayData['day']}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        dayData['date'] ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        '${dayData['trips']} trip${dayData['trips'] == 1 ? '' : 's'}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${dayData['distance']?.toStringAsFixed(1) ?? '0.0'} km',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ] else if (_selectedMonth != null) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[400], size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'No distance traveled in selected month',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Complete some trips to see monthly data',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else if (availableMonths.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[400], size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'No monthly data available',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Complete some trips to see billing data',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: color.withOpacity(0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}