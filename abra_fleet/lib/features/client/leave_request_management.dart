// lib/features/client/leave_request_management.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:abra_fleet/core/services/backend_connection_manager.dart';
import 'package:abra_fleet/core/services/api_service.dart';

class LeaveRequestManagement extends StatefulWidget {
  const LeaveRequestManagement({super.key});

  @override
  State<LeaveRequestManagement> createState() => _LeaveRequestManagementState();
}

class _LeaveRequestManagementState extends State<LeaveRequestManagement> {
  late final ApiService _apiService;
  late Future<List<Map<String, dynamic>>> _leaveRequestsFuture;
  String _selectedStatus = 'all';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _apiService = BackendConnectionManager().apiService;
    _fetchLeaveRequests();
  }

  void _fetchLeaveRequests() {
    setState(() {
      _leaveRequestsFuture = _getLeaveRequests();
    });
  }

  Future<List<Map<String, dynamic>>> _getLeaveRequests() async {
    try {
      final queryParams = <String, String>{};
      if (_selectedStatus != 'all') {
        queryParams['status'] = _selectedStatus;
      }

      final queryString = queryParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final endpoint = '/api/roster/admin/leave-requests' + 
          (queryString.isNotEmpty ? '?$queryString' : '');

      final response = await _apiService.get(endpoint);

      if (response['success'] == true) {
        return List<Map<String, dynamic>>.from(response['data'] ?? []);
      } else {
        throw Exception(response['message'] ?? 'Failed to fetch leave requests');
      }
    } catch (e) {
      debugPrint('❌ Error fetching leave requests: $e');
      rethrow;
    }
  }

  Future<void> _approveLeaveRequest(String leaveRequestId, {String? note}) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _apiService.put(
        '/api/roster/admin/leave-request/$leaveRequestId/approve',
        body: {'note': note ?? ''},
      );

      if (response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Leave request approved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchLeaveRequests();
        }
      } else {
        throw Exception(response['message'] ?? 'Failed to approve leave request');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to approve: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _rejectLeaveRequest(String leaveRequestId, String reason) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _apiService.put(
        '/api/roster/admin/leave-request/$leaveRequestId/reject',
        body: {'reason': reason},
      );

      if (response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Leave request rejected successfully!'),
              backgroundColor: Colors.orange,
            ),
          );
          _fetchLeaveRequests();
        }
      } else {
        throw Exception(response['message'] ?? 'Failed to reject leave request');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reject: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showApprovalDialog(Map<String, dynamic> request) {
    final noteController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Approve Leave Request'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Employee: ${request['customerName']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Period: ${_formatDateRange(request['startDate'], request['endDate'])}'),
              const SizedBox(height: 8),
              Text('Affected Trips: ${request['affectedTripsCount']}'),
              const SizedBox(height: 16),
              const Text(
                'Are you sure you want to approve this leave request? This will cancel the associated trips.',
                style: TextStyle(color: Colors.orange),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Approval Note (Optional)',
                  hintText: 'Add any additional notes...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _isLoading ? null : () {
                Navigator.pop(context);
                _approveLeaveRequest(request['id'], note: noteController.text.trim());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Yes, Approve'),
            ),
          ],
        );
      },
    );
  }

  void _showRejectionDialog(Map<String, dynamic> request) {
    final reasonController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.cancel, color: Colors.red),
              SizedBox(width: 8),
              Text('Reject Leave Request'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Employee: ${request['customerName']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Period: ${_formatDateRange(request['startDate'], request['endDate'])}'),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Rejection Reason *',
                  hintText: 'e.g., No leave approved in our records',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _isLoading ? null : () {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please provide a rejection reason'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(context);
                _rejectLeaveRequest(request['id'], reason);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm Rejection'),
            ),
          ],
        );
      },
    );
  }

  void _showLeaveRequestDetails(Map<String, dynamic> request) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.8,
            height: MediaQuery.of(context).size.height * 0.8,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF0D47A1)), // App's specified primary color
                    const SizedBox(width: 8),
                    const Text(
                      'Leave Request Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(),
                
                // Content
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Employee Information
                        _buildDetailSection(
                          'Employee Information',
                          [
                            _buildDetailRow('Name', request['customerName']),
                            _buildDetailRow('Email', request['customerEmail']),
                            _buildDetailRow('Organization', request['organizationName'] ?? 'N/A'),
                          ],
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Leave Details
                        _buildDetailSection(
                          'Leave Details',
                          [
                            _buildDetailRow('Start Date', _formatDate(request['startDate'])),
                            _buildDetailRow('End Date', _formatDate(request['endDate'])),
                            _buildDetailRow('Duration', '${_calculateDays(request['startDate'], request['endDate'])} day(s)'),
                            _buildDetailRow('Reason', request['reason'] ?? 'No reason provided'),
                            _buildDetailRow('Status', _getStatusText(request['status'])),
                            _buildDetailRow('Submitted', _formatDate(request['createdAt'])),
                          ],
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Affected Trips
                        _buildAffectedTripsSection(request['affectedTrips'] ?? []),
                        
                        // Approval/Rejection Details
                        if (request['status'] == 'approved' || request['status'] == 'rejected') ...[
                          const SizedBox(height: 20),
                          _buildApprovalRejectionSection(request),
                        ],
                      ],
                    ),
                  ),
                ),
                
                // Actions
                if (request['status'] == 'pending_approval') ...[
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showRejectionDialog(request);
                        },
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        label: const Text('Reject'),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showApprovalDialog(request);
                        },
                        icon: const Icon(Icons.check_circle),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0D47A1), // App's specified primary color
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  Widget _buildAffectedTripsSection(List<dynamic> affectedTrips) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Affected Trips (${affectedTrips.length})',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.orange,
          ),
        ),
        const SizedBox(height: 12),
        if (affectedTrips.isEmpty)
          const Text('No trips will be affected')
        else
          ...affectedTrips.map((trip) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        trip['rosterType'] == 'login' ? Icons.login :
                        trip['rosterType'] == 'logout' ? Icons.logout :
                        Icons.swap_horiz,
                        size: 16,
                        color: const Color(0xFF0D47A1), // App's specified primary color
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${trip['rosterType']?.toString().toUpperCase()} - ${trip['officeLocation']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Time: ${trip['fromTime']} - ${trip['toTime']}'),
                  if (trip['loginPickupAddress'] != null && trip['loginPickupAddress'].isNotEmpty)
                    Text('Pickup: ${trip['loginPickupAddress']}'),
                  if (trip['logoutDropAddress'] != null && trip['logoutDropAddress'].isNotEmpty)
                    Text('Drop: ${trip['logoutDropAddress']}'),
                ],
              ),
            ),
          )),
      ],
    );
  }

  Widget _buildApprovalRejectionSection(Map<String, dynamic> request) {
    final isApproved = request['status'] == 'approved';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isApproved ? 'Approval Details' : 'Rejection Details',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isApproved ? Colors.green : Colors.red,
          ),
        ),
        const SizedBox(height: 12),
        _buildDetailRow(
          isApproved ? 'Approved By' : 'Rejected By',
          isApproved ? (request['approvedBy'] ?? 'N/A') : (request['rejectedBy'] ?? 'N/A'),
        ),
        _buildDetailRow(
          isApproved ? 'Approved At' : 'Rejected At',
          _formatDate(isApproved ? request['approvedAt'] : request['rejectedAt']),
        ),
        if (isApproved && request['approvalNote'] != null && request['approvalNote'].isNotEmpty)
          _buildDetailRow('Note', request['approvalNote']),
        if (!isApproved && request['rejectionReason'] != null)
          _buildDetailRow('Reason', request['rejectionReason']),
      ],
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      final dateTime = date is String ? DateTime.parse(date) : date as DateTime;
      return DateFormat('MMM dd, yyyy HH:mm').format(dateTime);
    } catch (e) {
      return date.toString();
    }
  }

  String _formatDateRange(dynamic startDate, dynamic endDate) {
    try {
      final start = startDate is String ? DateTime.parse(startDate) : startDate as DateTime;
      final end = endDate is String ? DateTime.parse(endDate) : endDate as DateTime;
      
      if (start.year == end.year && start.month == end.month) {
        return '${DateFormat('MMM dd').format(start)} - ${DateFormat('dd, yyyy').format(end)}';
      } else {
        return '${DateFormat('MMM dd, yyyy').format(start)} - ${DateFormat('MMM dd, yyyy').format(end)}';
      }
    } catch (e) {
      return '$startDate - $endDate';
    }
  }

  int _calculateDays(dynamic startDate, dynamic endDate) {
    try {
      final start = startDate is String ? DateTime.parse(startDate) : startDate as DateTime;
      final end = endDate is String ? DateTime.parse(endDate) : endDate as DateTime;
      return end.difference(start).inDays + 1;
    } catch (e) {
      return 0;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending_approval':
        return 'Pending Approval';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending_approval':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFf8fafc),
      child: Column(
        children: [
          // Header with filters
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Color(0xFFe2e8f0)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.beach_access, color: Color(0xFF0D47A1)), // App's specified primary color
                const SizedBox(width: 12),
                const Text(
                  'Leave Request Management',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                
                // Status Filter
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    value: _selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Filter by Status',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Requests')),
                      DropdownMenuItem(value: 'pending_approval', child: Text('Pending Approval')),
                      DropdownMenuItem(value: 'approved', child: Text('Approved')),
                      DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                      DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
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
                
                const SizedBox(width: 16),
                
                // Refresh Button
                ElevatedButton.icon(
                  onPressed: _fetchLeaveRequests,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1), // App's specified primary color
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          
          // Content
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
                          style: const TextStyle(color: Colors.grey),
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

                final leaveRequests = snapshot.data ?? [];
                
                if (leaveRequests.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox, color: Colors.grey.shade400, size: 64),
                        const SizedBox(height: 16),
                        const Text(
                          'No Leave Requests Found',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedStatus == 'all' 
                            ? 'No leave requests have been submitted yet.'
                            : 'No leave requests found for the selected status.',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: leaveRequests.map((request) => 
                      LeaveRequestCard(
                        request: request,
                        onApprove: () => _showApprovalDialog(request),
                        onReject: () => _showRejectionDialog(request),
                        onViewDetails: () => _showLeaveRequestDetails(request),
                        formatDate: _formatDate,
                        formatDateRange: _formatDateRange,
                        calculateDays: _calculateDays,
                        getStatusText: _getStatusText,
                        getStatusColor: _getStatusColor,
                      ),
                    ).toList(),
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

class LeaveRequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onViewDetails;
  final String Function(dynamic) formatDate;
  final String Function(dynamic, dynamic) formatDateRange;
  final int Function(dynamic, dynamic) calculateDays;
  final String Function(String) getStatusText;
  final Color Function(String) getStatusColor;

  const LeaveRequestCard({
    super.key,
    required this.request,
    required this.onApprove,
    required this.onReject,
    required this.onViewDetails,
    required this.formatDate,
    required this.formatDateRange,
    required this.calculateDays,
    required this.getStatusText,
    required this.getStatusColor,
  });

  @override
  Widget build(BuildContext context) {
    final status = request['status'] ?? 'unknown';
    final statusColor = getStatusColor(status);
    final statusText = getStatusText(status);
    final isPending = status == 'pending_approval';

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                // Employee Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request['customerName'] ?? 'Unknown Employee',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        request['customerEmail'] ?? '',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Leave Details
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    Icons.calendar_month,
                    'Leave Period',
                    formatDateRange(request['startDate'], request['endDate']),
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    Icons.access_time,
                    'Duration',
                    '${calculateDays(request['startDate'], request['endDate'])} day(s)',
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    Icons.trip_origin,
                    'Affected Trips',
                    '${request['affectedTripsCount'] ?? 0} trip(s)',
                  ),
                ),
              ],
            ),
            
            // Reason (if provided)
            if (request['reason'] != null && request['reason'].isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildInfoItem(
                Icons.edit_note,
                'Reason',
                request['reason'],
              ),
            ],
            
            // Submitted Date
            const SizedBox(height: 16),
            _buildInfoItem(
              Icons.schedule,
              'Submitted',
              formatDate(request['createdAt']),
            ),
            
            // Actions
            const SizedBox(height: 20),
            Row(
              children: [
                // View Details Button
                OutlinedButton.icon(
                  onPressed: onViewDetails,
                  icon: const Icon(Icons.info_outline),
                  label: const Text('View Details'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0D47A1), // App's specified primary color
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Action Buttons (only for pending requests)
                if (isPending) ...[
                  ElevatedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.cancel, size: 18),
                    label: const Text('Reject'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  ElevatedButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
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

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}