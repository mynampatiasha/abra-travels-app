// lib/features/customer/dashboard/presentation/screens/my_leave_requests_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:abra_fleet/features/customer/dashboard/data/repositories/roster_repository.dart';
import 'package:abra_fleet/core/services/backend_connection_manager.dart';

class MyLeaveRequestsScreen extends StatefulWidget {
  const MyLeaveRequestsScreen({super.key});

  @override
  State<MyLeaveRequestsScreen> createState() => _MyLeaveRequestsScreenState();
}

class _MyLeaveRequestsScreenState extends State<MyLeaveRequestsScreen> {
  late final RosterRepository _rosterRepository;
  late Future<List<Map<String, dynamic>>> _leaveRequestsFuture;
  String _selectedStatus = 'all';

  @override
  void initState() {
    super.initState();
    _rosterRepository = RosterRepository(
      apiService: BackendConnectionManager().apiService,
    );
    _fetchLeaveRequests();
  }

  void _fetchLeaveRequests() {
    setState(() {
      _leaveRequestsFuture = _rosterRepository.getLeaveRequests(
        status: _selectedStatus == 'all' ? null : _selectedStatus,
      );
    });
  }

  Future<void> _cancelLeaveRequest(String leaveRequestId) async {
    final bool? confirmCancel = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Cancel Leave Request'),
          content: const Text('Are you sure you want to cancel this leave request?'),
          actions: <Widget>[
            TextButton(
              child: const Text('No'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Yes, Cancel'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmCancel == true) {
      try {
        final success = await _rosterRepository.cancelLeaveRequest(leaveRequestId);
        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Leave request cancelled successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchLeaveRequests();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to cancel leave request: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String _formatDateRange(String startDate, String endDate) {
    try {
      final start = DateTime.parse(startDate);
      final end = DateTime.parse(endDate);
      
      if (start.year == end.year && start.month == end.month) {
        return '${DateFormat('MMM dd').format(start)} - ${DateFormat('dd, yyyy').format(end)}';
      } else {
        return '${DateFormat('MMM dd, yyyy').format(start)} - ${DateFormat('MMM dd, yyyy').format(end)}';
      }
    } catch (e) {
      return '$startDate - $endDate';
    }
  }

  int _calculateDays(String startDate, String endDate) {
    try {
      final start = DateTime.parse(startDate);
      final end = DateTime.parse(endDate);
      return end.difference(start).inDays + 1;
    } catch (e) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Leave Requests'),
        backgroundColor: const Color(0xFF0D47A1), // App's specified primary color
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchLeaveRequests,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status Filter
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  'Filter by status:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedStatus,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All')),
                      ..._rosterRepository.getLeaveRequestStatusOptions().map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(_rosterRepository.getLeaveRequestStatusDisplayText(status)),
                        ),
                      ),
                    ],
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedStatus = newValue;
                        });
                        _fetchLeaveRequests();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          
          // Leave Requests List
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _leaveRequestsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          'Failed to load leave requests.',
                          style: TextStyle(fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.error.toString(),
                          style: TextStyle(color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          onPressed: _fetchLeaveRequests,
                        ),
                      ],
                    ),
                  );
                }

                final leaveRequests = snapshot.data;
                if (leaveRequests == null || leaveRequests.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.beach_access, color: Colors.grey.shade400, size: 64),
                        const SizedBox(height: 16),
                        const Text(
                          'No Leave Requests Found',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You haven\'t submitted any leave requests yet.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: leaveRequests.length,
                  itemBuilder: (context, index) {
                    final request = leaveRequests[index];
                    return LeaveRequestCard(
                      request: request,
                      onCancel: () => _cancelLeaveRequest(request['id']),
                      formatDate: _formatDate,
                      formatDateRange: _formatDateRange,
                      calculateDays: _calculateDays,
                      rosterRepository: _rosterRepository,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class LeaveRequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onCancel;
  final String Function(String) formatDate;
  final String Function(String, String) formatDateRange;
  final int Function(String, String) calculateDays;
  final RosterRepository rosterRepository;

  const LeaveRequestCard({
    super.key,
    required this.request,
    required this.onCancel,
    required this.formatDate,
    required this.formatDateRange,
    required this.calculateDays,
    required this.rosterRepository,
  });

  @override
  Widget build(BuildContext context) {
    final status = request['status'] ?? 'unknown';
    final startDate = request['startDate'] ?? '';
    final endDate = request['endDate'] ?? '';
    final reason = request['reason'] ?? '';
    final affectedTripsCount = request['affectedTripsCount'] ?? 0;
    final createdAt = request['createdAt'] ?? '';

    final statusColor = rosterRepository.getLeaveRequestStatusColor(status);
    final statusIcon = rosterRepository.getLeaveRequestStatusIcon(status);
    final statusText = rosterRepository.getLeaveRequestStatusDisplayText(status);

    return Card(
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.1),
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Status Badge and Days
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 16, color: statusColor),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (startDate.isNotEmpty && endDate.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D47A1).withOpacity(0.1), // App's specified primary color with opacity
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${calculateDays(startDate, endDate)} day(s)',
                      style: TextStyle(
                        color: const Color(0xFF0D47A1), // App's specified primary color
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            
            const Divider(height: 24),

            // Leave Period
            _buildDetailRow(
              Icons.calendar_month,
              'Leave Period:',
              startDate.isNotEmpty && endDate.isNotEmpty
                ? formatDateRange(startDate, endDate)
                : 'N/A',
            ),
            
            const SizedBox(height: 8),

            // Affected Trips
            _buildDetailRow(
              Icons.trip_origin,
              'Affected Trips:',
              '$affectedTripsCount trip(s)',
            ),

            // Reason (if provided)
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildDetailRow(
                Icons.edit_note,
                'Reason:',
                reason,
              ),
            ],

            // Created Date
            if (createdAt.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildDetailRow(
                Icons.access_time,
                'Submitted:',
                formatDate(createdAt),
              ),
            ],

            // Additional Status Information
            if (status == 'approved' && request['approvedAt'] != null) ...[
              const SizedBox(height: 8),
              _buildDetailRow(
                Icons.check_circle,
                'Approved:',
                formatDate(request['approvedAt']),
              ),
            ],

            if (status == 'rejected') ...[
              const SizedBox(height: 8),
              _buildDetailRow(
                Icons.cancel,
                'Rejected:',
                request['rejectedAt'] != null ? formatDate(request['rejectedAt']) : 'N/A',
              ),
              if (request['rejectionReason'] != null && request['rejectionReason'].isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildDetailRow(
                  Icons.info_outline,
                  'Reason:',
                  request['rejectionReason'],
                ),
              ],
            ],

            // Action Button (only for pending requests)
            if (status == 'pending_approval') ...[
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                    label: const Text('Cancel Request'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: onCancel,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: Colors.grey.shade800),
          ),
        ),
      ],
    );
  }
}