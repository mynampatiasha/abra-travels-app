// ============================================================================
// FILE: lib/features/driver/attendance/driver_attendance_widget.dart
// COMPLETE ATTENDANCE UI - ALL 4 CARDS + API LOGIC IN ONE FILE
// ============================================================================

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:abra_fleet/app/config/api_config.dart';

// ============================================================================
// MAIN WIDGET - Shows all 4 attendance cards
// ============================================================================
class DriverAttendanceWidget extends StatefulWidget {
  final String driverId;
  final String? driverName;

  const DriverAttendanceWidget({
    Key? key,
    required this.driverId,
    this.driverName,
  }) : super(key: key);

  @override
  State<DriverAttendanceWidget> createState() => DriverAttendanceWidgetState();
}

class DriverAttendanceWidgetState extends State<DriverAttendanceWidget> {
  // Use ApiConfig for base URL
  String get baseUrl => ApiConfig.baseUrl;
  
  // State
  Map<String, dynamic>? _todayAttendance;
  Map<String, dynamic>? _monthlyStats;
  List<dynamic> _attendanceHistory = [];
  Map<String, dynamic> _monthlyCalendar = {};
  
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    loadAllData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // Auto-refresh every 30 seconds
  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _loadTodayAttendance();
    });
  }

  // Load all attendance data
  Future<void> loadAllData() async {
    setState(() => _isLoading = true);
    
    await Future.wait([
      _loadTodayAttendance(),
      _loadMonthlyStats(),
      _loadAttendanceHistory(),
      _loadMonthlyCalendar(),
    ]);
    
    setState(() => _isLoading = false);
  }

  // Get auth token
  Future<String?> _getAuthToken() async {
        return await user?.getIdToken();
  }

  // API: Get today's attendance
  Future<void> _loadTodayAttendance() async {
    try {
      final token = await _getAuthToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/attendance/driver/${widget.driverId}/today'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _todayAttendance = data['attendance'];
        });
      }
    } catch (e) {
      print('Error loading today attendance: $e');
    }
  }

  // API: Get monthly stats
  Future<void> _loadMonthlyStats() async {
    try {
      final now = DateTime.now();
      final token = await _getAuthToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/attendance/driver/${widget.driverId}/stats?year=${now.year}&month=${now.month}'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _monthlyStats = data['stats'];
        });
      }
    } catch (e) {
      print('Error loading monthly stats: $e');
    }
  }

  // API: Get attendance history
  Future<void> _loadAttendanceHistory() async {
    try {
      final token = await _getAuthToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/attendance/driver/${widget.driverId}/history?limit=10'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _attendanceHistory = data['attendance'] ?? [];
        });
      }
    } catch (e) {
      print('Error loading history: $e');
    }
  }

  // API: Get monthly calendar
  Future<void> _loadMonthlyCalendar() async {
    try {
      final now = DateTime.now();
      final token = await _getAuthToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/attendance/driver/${widget.driverId}/calendar?year=${now.year}&month=${now.month}'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _monthlyCalendar = data['calendar'] ?? {};
        });
      }
    } catch (e) {
      print('Error loading calendar: $e');
    }
  }

  // PUBLIC METHOD: Auto-mark attendance (call from trip screen)
  Future<Map<String, dynamic>> autoMarkAttendance(String tripId) async {
    try {
      final token = await _getAuthToken();
      final position = await Geolocator.getCurrentPosition();
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/attendance/auto-mark'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'driverId': widget.driverId,
          'tripId': tripId,
          'location': {
            'latitude': position.latitude,
            'longitude': position.longitude,
          },
        }),
      );

      final data = json.decode(response.body);
      if (data['success']) {
        await loadAllData(); // Refresh all data
      }
      return data;
    } catch (e) {
      print('Error auto-marking attendance: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  // PUBLIC METHOD: Complete attendance (call from trip screen)
  Future<Map<String, dynamic>> completeAttendance(String tripId) async {
    try {
      final token = await _getAuthToken();
      final position = await Geolocator.getCurrentPosition();
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/attendance/complete'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'driverId': widget.driverId,
          'tripId': tripId,
          'location': {
            'latitude': position.latitude,
            'longitude': position.longitude,
          },
        }),
      );

      final data = json.decode(response.body);
      if (data['success']) {
        await loadAllData(); // Refresh all data
      }
      return data;
    } catch (e) {
      print('Error completing attendance: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: loadAllData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            _buildTodayCard(),
            const SizedBox(height: 16),
            _buildMonthlyStatsCard(),
            const SizedBox(height: 16),
            _buildHistoryCard(),
            const SizedBox(height: 16),
            _buildCalendarCard(),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // CARD 1: TODAY'S ATTENDANCE
  // =========================================================================
  Widget _buildTodayCard() {
    final attendance = _todayAttendance;
    final isWorking = attendance?['clockInTime'] != null && attendance?['clockOutTime'] == null;
    final status = attendance?['status'] ?? 'absent';
    
    Color statusColor = status == 'present' ? Colors.green : Colors.grey;
    if (attendance?['isLate'] == true) statusColor = Colors.orange;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [statusColor.withOpacity(0.1), Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_today, color: statusColor, size: 24),
                const SizedBox(width: 12),
                Text(
                  'TODAY\'S ATTENDANCE',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
                const Spacer(),
                if (isWorking)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const Divider(height: 24),
            
            if (attendance != null) ...[
              Text(
                DateTime.now().toString().split(' ')[0],
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    isWorking ? Icons.access_time : Icons.check_circle,
                    color: statusColor,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isWorking ? 'Present (Working)' : 'Present',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              // Clock times
              Row(
                children: [
                  Expanded(
                    child: _buildInfoColumn(
                      Icons.login,
                      'Clock In',
                      _formatTime(attendance['clockInTime']),
                      Colors.green,
                    ),
                  ),
                  Container(width: 1, height: 40, color: Colors.grey.shade300),
                  Expanded(
                    child: _buildInfoColumn(
                      Icons.logout,
                      'Clock Out',
                      _formatTime(attendance['clockOutTime']),
                      attendance['clockOutTime'] != null ? Colors.red : Colors.grey,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Stats
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStat(Icons.access_time, isWorking ? 'Working' : 'Hours', 
                      isWorking ? _getWorkingTime(attendance['clockInTime']) : '${attendance['totalHours'] ?? 0}h',
                      statusColor),
                    if ((attendance['totalTrips'] ?? 0) > 0)
                      _buildStat(Icons.route, 'Trips', 
                        '${attendance['completedTrips']}/${attendance['totalTrips']}', Colors.blue),
                    if ((attendance['totalDistance'] ?? 0) > 0)
                      _buildStat(Icons.speed, 'Distance', 
                        '${attendance['totalDistance']?.toStringAsFixed(1)}km', Colors.orange),
                  ],
                ),
              ),
              
              if (attendance['isLate'] == true) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Late by ${attendance['lateByMinutes']} minutes',
                        style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ] else ...[
              const Center(
                child: Column(
                  children: [
                    Icon(Icons.event_busy, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('No attendance for today'),
                    SizedBox(height: 8),
                    Text(
                      'Start a trip to mark attendance',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // CARD 2: MONTHLY STATISTICS
  // =========================================================================
  Widget _buildMonthlyStatsCard() {
    final stats = _monthlyStats;
    final now = DateTime.now();
    
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, color: Colors.blue.shade700, size: 24),
                const SizedBox(width: 12),
                Text(
                  'THIS MONTH (${_getMonthName(now.month)} ${now.year})',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            
            if (stats != null) ...[
              // Attendance circles
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatCircle('Present', stats['presentDays'].toString(), 
                          stats['workingDays'], Colors.green),
                        _buildStatCircle('Absent', stats['absentDays'].toString(), 
                          stats['workingDays'], Colors.red),
                        _buildStatCircle('Late', stats['lateDays'].toString(), 
                          stats['workingDays'], Colors.orange),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: (stats['presentPercentage'] ?? 0) / 100,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(
                        stats['presentPercentage'] >= 90 ? Colors.green : Colors.orange,
                      ),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Attendance: ${stats['presentPercentage']?.toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, 
                        color: Colors.blue.shade700),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              const Text('📊 Performance Summary', 
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              
              _buildInfoRow(Icons.access_time, 'Total Hours', 
                '${stats['totalHours']?.toStringAsFixed(1)}h', Colors.purple),
              const SizedBox(height: 8),
              _buildInfoRow(Icons.speed, 'Avg Hours/Day', 
                '${stats['avgHoursPerDay']?.toStringAsFixed(1)}h', Colors.indigo),
              const SizedBox(height: 8),
              _buildInfoRow(Icons.route, 'Total Trips', 
                '${stats['totalTrips']} trips', Colors.blue),
              const SizedBox(height: 8),
              _buildInfoRow(Icons.social_distance, 'Total Distance', 
                '${stats['totalDistance']?.toStringAsFixed(1)} km', Colors.orange),
            ] else
              const Center(
                child: Column(
                  children: [
                    Icon(Icons.analytics_outlined, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('No statistics available'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // CARD 3: ATTENDANCE HISTORY
  // =========================================================================
  Widget _buildHistoryCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: Colors.indigo.shade700, size: 24),
                const SizedBox(width: 12),
                Text(
                  'ATTENDANCE HISTORY',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade700,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            
            if (_attendanceHistory.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No history yet'),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _attendanceHistory.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final record = _attendanceHistory[index];
                  return _buildHistoryItem(record);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> record) {
    final status = record['status'] ?? 'absent';
    final isLate = record['isLate'] == true;
    final color = status == 'present' 
      ? (isLate ? Colors.orange : Colors.green)
      : Colors.red;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              border: Border.all(color: color, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateTime.parse(record['date']).day.toString(),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
                ),
                Text(
                  _getShortMonth(DateTime.parse(record['date']).month),
                  style: TextStyle(fontSize: 10, color: color),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(status == 'present' ? Icons.check_circle : Icons.cancel, 
                      color: color, size: 20),
                    const SizedBox(width: 6),
                    Text(
                      status == 'present' ? 'Present' : 'Absent',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
                    ),
                  ],
                ),
                if (record['clockInTime'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_formatTime(record['clockInTime'])} - ${_formatTime(record['clockOutTime'])}',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
                if (record['totalHours'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${record['totalHours']}h • ${record['completedTrips']}/${record['totalTrips']} trips',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // CARD 4: MONTHLY CALENDAR
  // =========================================================================
  Widget _buildCalendarCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_view_month, color: Colors.teal.shade700, size: 24),
                const SizedBox(width: 12),
                Text(
                  'MONTHLY CALENDAR',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal.shade700,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            
            // Day headers
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                .map((d) => SizedBox(
                  width: 40,
                  child: Center(
                    child: Text(d, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ))
                .toList(),
            ),
            const SizedBox(height: 8),
            
            // Calendar grid
            _buildCalendarGrid(),
            
            const SizedBox(height: 16),
            
            // Legend
            Wrap(
              spacing: 12,
              children: [
                _buildLegend('Present', Colors.green),
                _buildLegend('Late', Colors.orange),
                _buildLegend('Absent', Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final lastDay = DateTime(now.year, now.month + 1, 0);
    final startWeekday = firstDay.weekday % 7;
    final daysInMonth = lastDay.day;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: startWeekday + daysInMonth,
      itemBuilder: (context, index) {
        if (index < startWeekday) return const SizedBox();
        
        final day = index - startWeekday + 1;
        final date = DateTime(now.year, now.month, day);
        final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final attendance = _monthlyCalendar[dateStr];
        
        Color? bgColor;
        if (attendance != null) {
          final status = attendance['status'];
          final isLate = attendance['isLate'] == true;
          bgColor = status == 'present'
            ? (isLate ? Colors.orange.shade100 : Colors.green.shade100)
            : Colors.red.shade100;
        }
        
        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(day.toString(), style: const TextStyle(fontSize: 12)),
          ),
        );
      },
    );
  }

  // =========================================================================
  // HELPER WIDGETS
  // =========================================================================
  
  Widget _buildInfoColumn(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildStat(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildStatCircle(String label, String value, int total, Color color) {
    return Column(
      children: [
        SizedBox(
          width: 60,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: int.parse(value) / total,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(color),
                strokeWidth: 6,
              ),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildLegend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color.withOpacity(0.3),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  // =========================================================================
  // HELPER METHODS
  // =========================================================================
  
  String _formatTime(String? isoTime) {
    if (isoTime == null) return '-';
    try {
      final dt = DateTime.parse(isoTime);
      final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour;
      final min = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$min $period';
    } catch (e) {
      return '-';
    }
  }

  String _getWorkingTime(String? clockInTime) {
    if (clockInTime == null) return '0h 0m';
    try {
      final clockIn = DateTime.parse(clockInTime);
      final duration = DateTime.now().difference(clockIn);
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      return '${hours}h ${minutes}m';
    } catch (e) {
      return '0h 0m';
    }
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  String _getShortMonth(int month) {
    return _getMonthName(month);
  }
}
