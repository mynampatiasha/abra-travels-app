// lib/features/hrm_feedback/presentation/screens/hrm_portal_screen.dart

import 'package:flutter/material.dart';
import 'package:abra_fleet/features/admin/hrm/hrm_employees_screen.dart';  // ← ADD THIS
//import 'package:abra_fleet/features/hrm_feedback/presentation/screens/hrm_departments_screen.dart';
import 'hrm_notice_board_screen.dart';
import 'hrm_attendance_screen.dart';
import 'hrm_leave_requests_screen.dart';  // ← ADD LEAVE REQUESTS

class HrmPortalScreen extends StatefulWidget {
  const HrmPortalScreen({super.key});

  @override
  State<HrmPortalScreen> createState() => _HrmPortalScreenState();
}

class _HrmPortalScreenState extends State<HrmPortalScreen> {
  int _selectedIndex = 0;

  // Force rebuild by adding a key
  final GlobalKey _portalKey = GlobalKey();

  final List<Map<String, dynamic>> _hrmModules = [
    {
      'title': 'Employees',
      'icon': Icons.people,
      'color': Colors.blue,
      'screen': const HrmEmployeesScreen(),
    },
    // {
    //   'title': 'Departments',
    //   'icon': Icons.business,
    //   'color': Colors.purple,
    //   'screen': const HrmDepartmentsScreen(),
    // },
    {
      'title': 'Notice Board',
      'icon': Icons.announcement,
      'color': Colors.purple,
      'screen': const HrmNoticeBoardScreen(),
    },
    {
      'title': 'Attendance',
      'icon': Icons.access_time,
      'color': Colors.teal,
      'screen': const HrmAttendanceScreen(),
    },
    {
      'title': 'Leave Requests',
      'icon': Icons.beach_access,
      'color': Colors.orange,
      'screen': const HrmLeaveRequestsScreen(),
    },
  ];

  @override
  void initState() {
    super.initState();
    // Debug: Print module count to verify configuration
    print('🔍 HRM Portal initialized with ${_hrmModules.length} modules');
    for (int i = 0; i < _hrmModules.length; i++) {
      print('🔍 Module $i: ${_hrmModules[i]['title']}');
    }
  }

  void _refreshPortal() {
    // Refresh the portal data
    setState(() {
      // In a real app, this would reload any cached data
      // For now, we'll just trigger a rebuild and show a message
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('HRM Portal refreshed'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _portalKey, // Add key to force rebuild
      appBar: AppBar(
        title: const Text('HRM Portal'),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _refreshPortal,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Portal',
          ),
        ],
      ),
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 280,
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(
                right: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D47A1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.people, color: Colors.white, size: 28),
                      SizedBox(width: 12),
                      Text(
                        'HRM Modules',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _hrmModules.length,
                    itemBuilder: (context, index) {
                      print('🔍 Building module $index: ${_hrmModules[index]['title']}');
                      final module = _hrmModules[index];
                      final isSelected = _selectedIndex == index;
                      
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: Material(
                          color: isSelected ? module['color'].withOpacity(0.1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              setState(() {
                                _selectedIndex = index;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: isSelected 
                                  ? Border.all(color: module['color'], width: 2)
                                  : null,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: module['color'].withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      module['icon'],
                                      color: module['color'],
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      module['title'],
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                        color: isSelected ? module['color'] : Colors.grey[700],
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      Icons.arrow_forward_ios,
                                      size: 16,
                                      color: module['color'],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Main Content
          Expanded(
            child: _getSelectedScreen(),
          ),
        ],
      ),
    );
  }

  Widget _getSelectedScreen() {
    final module = _hrmModules[_selectedIndex];
    
    // Return the direct screen for all modules
    return module['screen'];
  }
}