import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:fl_chart/fl_chart.dart';

const Color kPrimaryColor = Color(0xFF0D47A1);

class ClientReportsAnalytics extends StatefulWidget {
  const ClientReportsAnalytics({Key? key}) : super(key: key);

  @override
  State<ClientReportsAnalytics> createState() => _ClientReportsAnalyticsState();
}

class _ClientReportsAnalyticsState extends State<ClientReportsAnalytics> {
  bool _isLoading = true;
  String _selectedFilter = 'today';
  String _selectedRevenueFilter = 'today';
  String _selectedMonth = '';
  
  // Data variables
  Map<String, dynamic> _companyAnalytics = {};
  Map<String, dynamic> _manpowerStats = {};
  Map<String, dynamic> _revenueStats = {};
  Map<String, dynamic> _ratingsData = {};
  Map<String, dynamic> _customerStats = {};
  Map<String, dynamic> _monthlyDistance = {};
  List<dynamic> _activeTrips = [];
  List<dynamic> _completedTrips = [];
  List<dynamic> _cancelledTrips = [];
  List<dynamic> _availableMonths = [];

  @override
  void initState() {
    super.initState();
    _loadAllReportsData();
  }

  Future<void> _loadAllReportsData() async {
    setState(() => _isLoading = true);
    
    try {
      await Future.wait([
        _fetchCompanyAnalytics(),
        _fetchManpowerStats(),
        _fetchRevenueStats(),
        _fetchRatingsData(),
        _fetchCustomerStats(),
        _fetchMonthlyDistance(),
        _fetchTripsData(),
      ]);
    } catch (e) {
      debugPrint('Error loading reports data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<String> _getAuthToken() async {
    // Get JWT token from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    
    if (token != null && token.isNotEmpty) {
      return token;
    }
    throw Exception('User not authenticated');
  }

  Future<void> _fetchCompanyAnalytics() async {
    try {
      final token = await _getAuthToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/admin-analytics/company-analytics?filter=$_selectedFilter'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() => _companyAnalytics = data);
        }
      }
    } catch (e) {
      debugPrint('Error fetching company analytics: $e');
    }
  }

  Future<void> _fetchManpowerStats() async {
    try {
      final token = await _getAuthToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/admin-analytics/manpower-stats'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() => _manpowerStats = data['stats']);
        }
      }
    } catch (e) {
      debugPrint('Error fetching manpower stats: $e');
    }
  }

  Future<void> _fetchRevenueStats() async {
    try {
      final token = await _getAuthToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/admin-analytics/revenue-stats?filter=$_selectedRevenueFilter'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() => _revenueStats = data['revenue']);
        }
      }
    } catch (e) {
      debugPrint('Error fetching revenue stats: $e');
    }
  }

  Future<void> _fetchRatingsData() async {
    try {
      final token = await _getAuthToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/admin-analytics/ratings/overview'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() => _ratingsData = data['ratingsData']);
        }
      }
    } catch (e) {
      debugPrint('Error fetching ratings data: $e');
    }
  }

  Future<void> _fetchCustomerStats() async {
    try {
      final token = await _getAuthToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/customer/stats/dashboard'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() => _customerStats = data['data']);
        }
      }
    } catch (e) {
      debugPrint('Error fetching customer stats: $e');
    }
  }

  Future<void> _fetchMonthlyDistance() async {
    try {
      final token = await _getAuthToken();
      final url = _selectedMonth.isNotEmpty 
        ? '${ApiConfig.baseUrl}/customer/stats/monthly-distance?month=$_selectedMonth'
        : '${ApiConfig.baseUrl}/customer/stats/monthly-distance';
        
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            _monthlyDistance = data['data'];
            _availableMonths = data['data']['availableMonths'] ?? [];
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching monthly distance: $e');
    }
  }

  Future<void> _fetchTripsData() async {
    try {
      final token = await _getAuthToken();
      
      // Fetch active trips
      final activeResponse = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/admin-analytics/trips/active'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (activeResponse.statusCode == 200) {
        final data = json.decode(activeResponse.body);
        if (data['success']) {
          setState(() => _activeTrips = data['trips'] ?? []);
        }
      }

      // Fetch completed trips
      final completedResponse = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/admin-analytics/trips/completed-today'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (completedResponse.statusCode == 200) {
        final data = json.decode(completedResponse.body);
        if (data['success']) {
          setState(() => _completedTrips = data['trips'] ?? []);
        }
      }

      // Fetch cancelled trips
      final cancelledResponse = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/admin-analytics/trips/cancelled-today'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (cancelledResponse.statusCode == 200) {
        final data = json.decode(cancelledResponse.body);
        if (data['success']) {
          setState(() => _cancelledTrips = data['trips'] ?? []);
        }
      }
    } catch (e) {
      debugPrint('Error fetching trips data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAllReportsData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),
                    _buildFilterButtons(),
                    const SizedBox(height: 32),
                    _buildOverviewCards(),
                    const SizedBox(height: 32),
                    _buildChartsSection(),
                    const SizedBox(height: 32),
                    _buildDetailedReports(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kPrimaryColor, Color(0xFF1565C0)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.analytics_outlined,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Client Reports & Analytics',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Comprehensive overview of your fleet operations and performance metrics',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterButtons() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filter Options',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          
          // Time Period Filter
          Row(
            children: [
              const Text(
                'Time Period: ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 12),
              ...['today', 'week', 'month'].map((filter) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(filter.toUpperCase()),
                  selected: _selectedFilter == filter,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedFilter = filter);
                      _fetchCompanyAnalytics();
                    }
                  },
                  selectedColor: kPrimaryColor.withOpacity(0.2),
                  checkmarkColor: kPrimaryColor,
                ),
              )),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Revenue Filter
          Row(
            children: [
              const Text(
                'Revenue Period: ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 12),
              ...['today', 'week', 'month'].map((filter) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(filter.toUpperCase()),
                  selected: _selectedRevenueFilter == filter,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedRevenueFilter = filter);
                      _fetchRevenueStats();
                    }
                  },
                  selectedColor: Colors.green.withOpacity(0.2),
                  checkmarkColor: Colors.green,
                ),
              )),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Month Filter for Distance
          if (_availableMonths.isNotEmpty) ...[
            Row(
              children: [
                const Text(
                  'Distance Month: ',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _selectedMonth.isEmpty ? null : _selectedMonth,
                  hint: const Text('Select Month'),
                  items: _availableMonths.map<DropdownMenuItem<String>>((month) {
                    return DropdownMenuItem<String>(
                      value: month['key'],
                      child: Text(month['name']),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedMonth = value ?? '');
                    _fetchMonthlyDistance();
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOverviewCards() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.2,
      children: [
        _buildOverviewCard(
          'Total Customers',
          '${_manpowerStats['totalCustomers'] ?? 0}',
          Icons.people_outline,
          Colors.blue,
        ),
        _buildOverviewCard(
          'Total Drivers',
          '${_manpowerStats['totalDrivers'] ?? 0}',
          Icons.drive_eta_outlined,
          Colors.green,
        ),
        _buildOverviewCard(
          'Total Vehicles',
          '${_manpowerStats['totalVehicles'] ?? 0}',
          Icons.directions_bus_outlined,
          Colors.orange,
        ),
        _buildOverviewCard(
          'Active Trips',
          '${_manpowerStats['activeTrips'] ?? 0}',
          Icons.route_outlined,
          Colors.purple,
        ),
        _buildOverviewCard(
          'Completed Today',
          '${_manpowerStats['completedTripsToday'] ?? 0}',
          Icons.check_circle_outline,
          Colors.teal,
        ),
        _buildOverviewCard(
          'Cancelled Today',
          '${_manpowerStats['cancelledTripsToday'] ?? 0}',
          Icons.cancel_outlined,
          Colors.red,
        ),
        _buildOverviewCard(
          'Pending Rosters',
          '${_manpowerStats['pendingRosters'] ?? 0}',
          Icons.pending_actions_outlined,
          Colors.amber,
        ),
        _buildOverviewCard(
          'Average Rating',
          '${(_ratingsData['averageRating'] ?? 0).toStringAsFixed(1)}⭐',
          Icons.star_outline,
          Colors.indigo,
        ),
      ],
    );
  }

  Widget _buildOverviewCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartsSection() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: _buildRevenueChart(),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 1,
          child: _buildTripStatusChart(),
        ),
      ],
    );
  }

  Widget _buildRevenueChart() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Revenue Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      FlSpot(0, (_revenueStats['todayRevenue'] ?? 0).toDouble()),
                      FlSpot(1, (_revenueStats['weekRevenue'] ?? 0).toDouble()),
                      FlSpot(2, (_revenueStats['monthRevenue'] ?? 0).toDouble()),
                    ],
                    isCurved: true,
                    color: Colors.green,
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildRevenueItem('Today', '₹${_revenueStats['todayRevenue'] ?? 0}'),
              _buildRevenueItem('Week', '₹${_revenueStats['weekRevenue'] ?? 0}'),
              _buildRevenueItem('Month', '₹${_revenueStats['monthRevenue'] ?? 0}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueItem(String period, String amount) {
    return Column(
      children: [
        Text(
          amount,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        Text(
          period,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildTripStatusChart() {
    final totalTrips = _customerStats['totalTrips'] ?? {};
    final completed = (totalTrips['completed'] ?? 0).toDouble();
    final ongoing = (totalTrips['ongoing'] ?? 0).toDouble();
    final cancelled = (totalTrips['cancelled'] ?? 0).toDouble();
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trip Status',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: PieChart(
              PieChartData(
                sections: [
                  PieChartSectionData(
                    value: completed,
                    title: '${completed.toInt()}',
                    color: Colors.green,
                    radius: 50,
                  ),
                  PieChartSectionData(
                    value: ongoing,
                    title: '${ongoing.toInt()}',
                    color: Colors.blue,
                    radius: 50,
                  ),
                  PieChartSectionData(
                    value: cancelled,
                    title: '${cancelled.toInt()}',
                    color: Colors.red,
                    radius: 50,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Column(
            children: [
              _buildLegendItem('Completed', Colors.green, completed.toInt()),
              _buildLegendItem('Ongoing', Colors.blue, ongoing.toInt()),
              _buildLegendItem('Cancelled', Colors.red, cancelled.toInt()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$label: $value',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedReports() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildActiveTripsTable()),
            const SizedBox(width: 16),
            Expanded(child: _buildTopCompaniesTable()),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildMonthlyDistanceTable()),
            const SizedBox(width: 16),
            Expanded(child: _buildTopDriversTable()),
          ],
        ),
      ],
    );
  }

  Widget _buildActiveTripsTable() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Active Trips',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: _activeTrips.isEmpty
                ? const Center(
                    child: Text(
                      'No active trips',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  )
                : ListView.builder(
                    itemCount: _activeTrips.length > 5 ? 5 : _activeTrips.length,
                    itemBuilder: (context, index) {
                      final trip = _activeTrips[index];
                      return ListTile(
                        leading: const Icon(Icons.directions_car, color: Colors.blue),
                        title: Text(trip['customerName'] ?? 'Unknown Customer'),
                        subtitle: Text('Driver: ${trip['driverName'] ?? 'N/A'}'),
                        trailing: Text(
                          trip['status']?.toUpperCase() ?? 'UNKNOWN',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopCompaniesTable() {
    final companies = _companyAnalytics['mostActive'] ?? [];
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Top Companies',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: companies.isEmpty
                ? const Center(
                    child: Text(
                      'No company data available',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  )
                : ListView.builder(
                    itemCount: companies.length > 5 ? 5 : companies.length,
                    itemBuilder: (context, index) {
                      final company = companies[index];
                      return ListTile(
                        leading: const Icon(Icons.business, color: Colors.green),
                        title: Text(company['name'] ?? 'Unknown Company'),
                        subtitle: Text('Employees: ${company['totalEmployees'] ?? 0}'),
                        trailing: Text(
                          '₹${company['revenue'] ?? 0}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyDistanceTable() {
    final monthlyData = _monthlyDistance['selectedMonthData'];
    final dailyBreakdown = monthlyData?['dailyBreakdown'] ?? [];
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Monthly Distance ${monthlyData != null ? '(${monthlyData['monthName']})' : ''}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          if (monthlyData != null) ...[
            Text(
              'Total: ${monthlyData['totalDistance']} km',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: 250,
            child: dailyBreakdown.isNotEmpty
                ? ListView.builder(
                    itemCount: dailyBreakdown.length > 8 ? 8 : dailyBreakdown.length,
                    itemBuilder: (context, index) {
                      final day = dailyBreakdown[index];
                      return ListTile(
                        leading: const Icon(Icons.calendar_today, color: Colors.orange),
                        title: Text('Day ${day['day']}'),
                        subtitle: Text('${day['trips']} trips'),
                        trailing: Text(
                          '${day['distance']} km',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      );
                    },
                  )
                : const Center(
                    child: Text(
                      'Select a month to view daily breakdown',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopDriversTable() {
    final topDrivers = _ratingsData['topDrivers'] ?? [];
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Top Rated Drivers',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: topDrivers.isEmpty
                ? const Center(
                    child: Text(
                      'No driver ratings available',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  )
                : ListView.builder(
                    itemCount: topDrivers.length > 5 ? 5 : topDrivers.length,
                    itemBuilder: (context, index) {
                      final driver = topDrivers[index];
                      return ListTile(
                        leading: const Icon(Icons.person, color: Colors.purple),
                        title: Text(driver['driverName'] ?? 'Unknown Driver'),
                        subtitle: Text('${driver['totalRatings']} ratings'),
                        trailing: Text(
                          '${(driver['averageRating'] ?? 0).toStringAsFixed(1)}⭐',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}