// lib/features/hrm_feedback/presentation/screens/hrm_attendance_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HrmAttendanceScreen extends StatefulWidget {
  const HrmAttendanceScreen({super.key});

  @override
  State<HrmAttendanceScreen> createState() => _HrmAttendanceScreenState();
}

class _HrmAttendanceScreenState extends State<HrmAttendanceScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedDate = DateTime.now();
  String _selectedDepartment = 'All';
  
  // Ensure unique department values
  final List<String> _departments = ['All', 'Drivers', 'Admin', 'Maintenance', 'Customer Service'];
  
  final List<AttendanceRecord> _attendanceRecords = [
    AttendanceRecord(
      employeeId: 'EMP001',
      employeeName: 'Rajesh Kumar',
      department: 'Drivers',
      checkIn: DateTime.now().subtract(const Duration(hours: 8)),
      checkOut: DateTime.now().subtract(const Duration(hours: 1)),
      status: AttendanceStatus.present,
      workingHours: 7.0,
    ),
    AttendanceRecord(
      employeeId: 'EMP002',
      employeeName: 'Priya Sharma',
      department: 'Admin',
      checkIn: DateTime.now().subtract(const Duration(hours: 9)),
      checkOut: null,
      status: AttendanceStatus.present,
      workingHours: 0.0,
    ),
    AttendanceRecord(
      employeeId: 'EMP003',
      employeeName: 'Amit Singh',
      department: 'Maintenance',
      checkIn: null,
      checkOut: null,
      status: AttendanceStatus.absent,
      workingHours: 0.0,
    ),
    AttendanceRecord(
      employeeId: 'EMP004',
      employeeName: 'Sunita Devi',
      department: 'Customer Service',
      checkIn: DateTime.now().subtract(const Duration(hours: 4)),
      checkOut: null,
      status: AttendanceStatus.halfDay,
      workingHours: 0.0,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Ensure selected department is valid
    if (!_departments.contains(_selectedDepartment)) {
      _selectedDepartment = _departments.first;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshAttendance() async {
    // Simulate refreshing attendance data
    setState(() {
      // In a real app, this would reload data from API
      // For now, we'll just trigger a rebuild
    });
    
    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Attendance data refreshed'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: RefreshIndicator(
        onRefresh: _refreshAttendance,
        child: Column(
          children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.access_time, color: Color(0xFF0D47A1), size: 28),
                    const SizedBox(width: 12),
                    const Text(
                      'Attendance Management',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0D47A1),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _refreshAttendance,
                          icon: const Icon(Icons.refresh, color: Color(0xFF0D47A1)),
                          tooltip: 'Refresh Data',
                        ),
                        const SizedBox(width: 8),
                        _buildDatePicker(),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildAttendanceSummary(),
              ],
            ),
          ),
          
          // Tab Bar
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF0D47A1),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF0D47A1),
              tabs: const [
                Tab(text: 'Daily Attendance'),
                Tab(text: 'Monthly Report'),
                Tab(text: 'Leave Requests'),
              ],
            ),
          ),
          
          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDailyAttendanceTab(),
                _buildMonthlyReportTab(),
                _buildLeaveRequestsTab(),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  
  }

  Widget _buildDatePicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: _selectDate,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today, size: 16, color: Color(0xFF0D47A1)),
            const SizedBox(width: 8),
            Text(
              DateFormat('MMM dd, yyyy').format(_selectedDate),
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Color(0xFF0D47A1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceSummary() {
    final presentCount = _attendanceRecords.where((r) => r.status == AttendanceStatus.present).length;
    final absentCount = _attendanceRecords.where((r) => r.status == AttendanceStatus.absent).length;
    final halfDayCount = _attendanceRecords.where((r) => r.status == AttendanceStatus.halfDay).length;
    final lateCount = _attendanceRecords.where((r) => r.status == AttendanceStatus.late).length;

    return Row(
      children: [
        _buildSummaryCard('Present', presentCount, Colors.green),
        const SizedBox(width: 12),
        _buildSummaryCard('Absent', absentCount, Colors.red),
        const SizedBox(width: 12),
        _buildSummaryCard('Half Day', halfDayCount, Colors.orange),
        const SizedBox(width: 12),
        _buildSummaryCard('Late', lateCount, Colors.amber),
      ],
    );
  }

  Widget _buildSummaryCard(String title, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyAttendanceTab() {
    final filteredRecords = _selectedDepartment == 'All' 
        ? _attendanceRecords 
        : _attendanceRecords.where((r) => r.department == _selectedDepartment).toList();

    return Column(
      children: [
        // Department Filter
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text('Department: ', style: TextStyle(fontWeight: FontWeight.w500)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _departments.contains(_selectedDepartment) ? _selectedDepartment : _departments.first,
                    items: _departments.map((dept) {
                      return DropdownMenuItem<String>(
                        value: dept,
                        child: Text(dept),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null && _departments.contains(value)) {
                        setState(() {
                          _selectedDepartment = value;
                        });
                      }
                    },
                  ),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  IconButton(
                    onPressed: _refreshAttendance,
                    icon: const Icon(Icons.refresh, color: Color(0xFF0D47A1)),
                    tooltip: 'Refresh Data',
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _showMarkAttendanceDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Mark Attendance'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D47A1),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Attendance List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredRecords.length,
            itemBuilder: (context, index) {
              final record = filteredRecords[index];
              return _buildAttendanceCard(record);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceCard(AttendanceRecord record) {
    Color statusColor;
    IconData statusIcon;
    
    switch (record.status) {
      case AttendanceStatus.present:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case AttendanceStatus.absent:
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      case AttendanceStatus.halfDay:
        statusColor = Colors.orange;
        statusIcon = Icons.schedule;
        break;
      case AttendanceStatus.late:
        statusColor = Colors.amber;
        statusIcon = Icons.access_time;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: statusColor.withOpacity(0.1),
              child: Icon(statusIcon, color: statusColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.employeeName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${record.employeeId} • ${record.department}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (record.checkIn != null) ...[
                        const Icon(Icons.login, size: 16, color: Colors.green),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('hh:mm a').format(record.checkIn!),
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 16),
                      ],
                      if (record.checkOut != null) ...[
                        const Icon(Icons.logout, size: 16, color: Colors.red),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('hh:mm a').format(record.checkOut!),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    record.status.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
                if (record.workingHours > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${record.workingHours.toStringAsFixed(1)}h',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyReportTab() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Monthly Report',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          Text(
            'Coming Soon',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveRequestsTab() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Leave Requests',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          Text(
            'Coming Soon',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  void _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _showMarkAttendanceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark Attendance'),
        content: const Text('This feature will be integrated with biometric systems or manual entry forms.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class AttendanceRecord {
  final String employeeId;
  final String employeeName;
  final String department;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final AttendanceStatus status;
  final double workingHours;

  AttendanceRecord({
    required this.employeeId,
    required this.employeeName,
    required this.department,
    this.checkIn,
    this.checkOut,
    required this.status,
    required this.workingHours,
  });
}

enum AttendanceStatus { present, absent, halfDay, late }