// lib/features/admin/leave_trip_management.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:abra_fleet/core/services/backend_connection_manager.dart';
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:abra_fleet/core/services/geocoding_service.dart';
import 'package:abra_fleet/features/notifications/presentation/providers/notification_provider.dart';

class LeaveTripManagement extends StatefulWidget {
  const LeaveTripManagement({super.key});

  @override
  State<LeaveTripManagement> createState() => _LeaveTripManagementState();
}

class _LeaveTripManagementState extends State<LeaveTripManagement> {
  late final ApiService _apiService;
  final GeocodingService _geocodingService = GeocodingService();
  late Future<List<Map<String, dynamic>>> _approvedLeaveRequestsFuture;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    debugPrint('🚀 LeaveTripManagement initState called');
    debugPrint('🚀 Initializing API service...');
    _apiService = BackendConnectionManager().apiService;
    debugPrint('🚀 API service initialized: $_apiService');
    debugPrint('🚀 Fetching approved leave requests...');
    _fetchApprovedLeaveRequests();
    debugPrint('🚀 initState complete');
  }

  void _fetchApprovedLeaveRequests() {
    setState(() {
      _approvedLeaveRequestsFuture = _getApprovedLeaveRequests();
    });
  }

  Future<List<Map<String, dynamic>>> _getApprovedLeaveRequests() async {
    try {
      debugPrint('🔄 Fetching approved leave requests...');
      final response = await _apiService.get('/api/roster/admin/approved-leave-requests');
      
      debugPrint('📊 Response received: ${response.toString()}');

      if (response['success'] == true) {
        final data = List<Map<String, dynamic>>.from(response['data'] ?? []);
        debugPrint('✅ Successfully fetched ${data.length} approved leave requests');
        return data;
      } else {
        debugPrint('❌ API returned error: ${response['message']}');
        throw Exception(response['message'] ?? 'Failed to fetch approved leave requests');
      }
    } catch (e) {
      debugPrint('❌ Error fetching approved leave requests: $e');
      debugPrint('❌ Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  Future<void> _cancelTrips(String leaveRequestId, {String? adminNotes}) async {
    debugPrint('🗑️ ========================================');
    debugPrint('🗑️ CANCEL TRIPS INITIATED');
    debugPrint('🗑️ ========================================');
    debugPrint('🗑️ Leave Request ID: $leaveRequestId');
    debugPrint('🗑️ Admin Notes: ${adminNotes ?? "(none)"}');
    debugPrint('🗑️ Current loading state: $_isLoading');
    
    setState(() {
      _isLoading = true;
    });
    debugPrint('🗑️ Loading state set to: true');

    try {
      debugPrint('🗑️ Preparing API request...');
      final endpoint = '/api/roster/admin/cancel-leave-trips/$leaveRequestId';
      final body = {'adminNotes': adminNotes ?? ''};
      
      debugPrint('🗑️ API Endpoint: $endpoint');
      debugPrint('🗑️ Request Body: $body');
      debugPrint('🗑️ Making POST request...');
      
      final response = await _apiService.post(endpoint, body: body);
      
      debugPrint('🗑️ ========================================');
      debugPrint('🗑️ API RESPONSE RECEIVED');
      debugPrint('🗑️ ========================================');
      debugPrint('🗑️ Response: ${response.toString()}');
      debugPrint('🗑️ Success: ${response['success']}');
      debugPrint('🗑️ Message: ${response['message']}');

      if (response['success'] == true) {
        debugPrint('✅ Trip cancellation successful!');
        
        if (mounted) {
          debugPrint('✅ Widget is mounted, showing success message');
          
          // Show success snackbar
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Trips cancelled successfully!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          debugPrint('✅ Success snackbar shown');
          
          // Refresh the list
          debugPrint('🔄 Refreshing leave requests list...');
          _fetchApprovedLeaveRequests();
          debugPrint('✅ Refresh initiated');
          
          // Refresh notification count
          debugPrint('🔔 Refreshing notification count...');
          Provider.of<NotificationProvider>(context, listen: false)
              .fetchUnreadNotificationCount(adminOnly: true);
          debugPrint('✅ Notification count refresh initiated');
          
          // Note: Floating notification will be shown automatically by the 
          // NotificationService when the backend sends the notification
        } else {
          debugPrint('⚠️ Widget not mounted, skipping UI updates');
        }
      } else {
        debugPrint('❌ API returned success=false');
        throw Exception(response['message'] ?? 'Failed to cancel trips');
      }
    } catch (e) {
      debugPrint('❌ ========================================');
      debugPrint('❌ ERROR CANCELLING TRIPS');
      debugPrint('❌ ========================================');
      debugPrint('❌ Error: $e');
      debugPrint('❌ Error Type: ${e.runtimeType}');
      debugPrint('❌ Stack Trace: ${StackTrace.current}');
      
      if (mounted) {
        debugPrint('❌ Widget mounted, showing error snackbar');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel trips: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        debugPrint('❌ Error snackbar shown');
      } else {
        debugPrint('⚠️ Widget not mounted, skipping error UI');
      }
    } finally {
      debugPrint('🗑️ Cleanup: Setting loading state to false');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        debugPrint('🗑️ Loading state set to: false');
      } else {
        debugPrint('⚠️ Widget not mounted, skipping state update');
      }
      debugPrint('🗑️ ========================================');
      debugPrint('🗑️ CANCEL TRIPS COMPLETED');
      debugPrint('🗑️ ========================================');
    }
  }

  void _showCancelTripsDialog(Map<String, dynamic> leaveRequest) {
    debugPrint('💬 ========================================');
    debugPrint('💬 CANCEL TRIPS DIALOG OPENED');
    debugPrint('💬 ========================================');
    debugPrint('💬 Leave Request ID: ${leaveRequest['id']}');
    debugPrint('💬 Customer Name: ${leaveRequest['customerName']}');
    debugPrint('💬 Customer Email: ${leaveRequest['customerEmail']}');
    debugPrint('💬 Leave Period: ${leaveRequest['startDate']} to ${leaveRequest['endDate']}');
    
    final notesController = TextEditingController();
    final affectedTrips = List<Map<String, dynamic>>.from(leaveRequest['affectedTrips'] ?? []);
    
    debugPrint('💬 Affected Trips Count: ${affectedTrips.length}');
    if (affectedTrips.isNotEmpty) {
      debugPrint('💬 Affected Trips Details:');
      for (var i = 0; i < affectedTrips.length; i++) {
        final trip = affectedTrips[i];
        debugPrint('💬   Trip ${i + 1}:');
        debugPrint('💬     - ID: ${trip['id']}');
        debugPrint('💬     - Readable ID: ${trip['readableId']}');
        debugPrint('💬     - Type: ${trip['rosterType']}');
        debugPrint('💬     - Date: ${trip['fromDate']}');
        debugPrint('💬     - Time: ${trip['fromTime']}');
        debugPrint('💬     - Driver: ${trip['assignedDriver']?['driverName'] ?? 'Unassigned'}');
      }
    }
    debugPrint('💬 ========================================');
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        debugPrint('💬 Building dialog widget...');
        return Dialog(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.5,
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header (Fixed at top)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber, color: Colors.orange, size: 28),
                      const SizedBox(width: 12),
                      const Text(
                        'Cancel Trips',
                        style: TextStyle(
                          fontSize: 24,
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
                ),
                const Divider(height: 1),
                
                // Scrollable Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                
                // Warning Message
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          const Text(
                            'Important Notice',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You are about to cancel ${affectedTrips.length} trip(s) for ${leaveRequest['customerName']}. '
                        'The drivers assigned to these trips will be notified immediately. This action cannot be undone.',
                        style: TextStyle(color: Colors.orange.shade800),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Leave Request Details
                _buildLeaveRequestDetails(leaveRequest),
                
                const SizedBox(height: 20),
                
                // Affected Trips List
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Trips to be Cancelled (${affectedTrips.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    affectedTrips.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20.0),
                              child: Text(
                                'No trips to cancel',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: affectedTrips.length,
                            itemBuilder: (context, index) {
                          final trip = affectedTrips[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _getTripTypeIcon(trip['rosterType']),
                                        size: 16,
                                        color: const Color(0xFF0D47A1),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: FutureBuilder<String>(
                                          future: _geocodingService.getAddressFromLocation(trip['officeLocation'] ?? ''),
                                          builder: (context, snapshot) {
                                            final address = snapshot.data ?? trip['officeLocation'] ?? 'Unknown';
                                            return Text(
                                              '${trip['rosterType']?.toString().toUpperCase()} - $address',
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            );
                                          },
                                        ),
                                      ),
                                      const Spacer(),
                                      if (trip['readableId'] != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade50,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            trip['readableId'],
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.blue.shade700,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.access_time, size: 14, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${trip['fromTime']} - ${trip['toTime']}',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      const SizedBox(width: 16),
                                      const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatDate(trip['fromDate']),
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ],
                                  ),
                                  if (trip['assignedDriver'] != null) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.person, size: 14, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Driver: ${trip['assignedDriver']['driverName'] ?? 'Unknown'}',
                                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                
                        const SizedBox(height: 20),
                        
                        // Admin Notes
                        TextField(
                          controller: notesController,
                          decoration: const InputDecoration(
                            labelText: 'Admin Notes (Optional)',
                            hintText: 'Add any internal notes about this cancellation...',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Fixed Actions at Bottom
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          debugPrint('🚫 Cancel button clicked - closing dialog without action');
                          Navigator.pop(context);
                        },
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : () {
                          debugPrint('🔴 ========================================');
                          debugPrint('🔴 CANCEL TRIPS BUTTON CLICKED');
                          debugPrint('🔴 ========================================');
                          debugPrint('🔴 Leave Request ID: ${leaveRequest['id']}');
                          debugPrint('🔴 Admin Notes: ${notesController.text.trim()}');
                          debugPrint('🔴 Is Loading: $_isLoading');
                          debugPrint('🔴 Closing dialog...');
                          
                          Navigator.pop(context);
                          debugPrint('🔴 Dialog closed');
                          debugPrint('🔴 Calling _cancelTrips method...');
                          
                          _cancelTrips(leaveRequest['id'], adminNotes: notesController.text.trim());
                        },
                        icon: const Icon(Icons.cancel),
                        label: const Text('Cancel Trips'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLeaveRequestDetails(Map<String, dynamic> leaveRequest) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Leave Request Details',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDetailItem('Employee', leaveRequest['customerName']),
              ),
              Expanded(
                child: _buildDetailItem('Organization', leaveRequest['organizationName'] ?? 'N/A'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildDetailItem('Leave Period', _formatDateRange(leaveRequest['startDate'], leaveRequest['endDate'])),
              ),
              Expanded(
                child: _buildDetailItem('Approved By', leaveRequest['approvedBy']),
              ),
            ],
          ),
          if (leaveRequest['reason'] != null && leaveRequest['reason'].isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildDetailItem('Reason', leaveRequest['reason']),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
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
    );
  }

  IconData _getTripTypeIcon(String? rosterType) {
    switch (rosterType) {
      case 'login':
        return Icons.login;
      case 'logout':
        return Icons.logout;
      case 'both':
        return Icons.swap_horiz;
      default:
        return Icons.trip_origin;
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      final dateTime = date is String ? DateTime.parse(date) : date as DateTime;
      return DateFormat('MMM dd, yyyy').format(dateTime);
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

  @override
  Widget build(BuildContext context) {
    debugPrint('🎨 Building LeaveTripManagement widget');
    debugPrint('🎨 Context: $context');
    debugPrint('🎨 Mounted: $mounted');
    
    return Container(
      color: const Color(0xFFf8fafc),
      child: Column(
        children: [
          // Header
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
                const Icon(Icons.cancel_schedule_send, color: Color(0xFF0D47A1)),
                const SizedBox(width: 12),
                const Text(
                  'Trip Cancellation Management',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                
                // Refresh Button
                ElevatedButton.icon(
                  onPressed: () {
                    debugPrint('🔄 Refresh button clicked');
                    _fetchApprovedLeaveRequests();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _approvedLeaveRequestsFuture,
              builder: (context, snapshot) {
                debugPrint('🔍 FutureBuilder state: ${snapshot.connectionState}');
                debugPrint('🔍 Has error: ${snapshot.hasError}');
                debugPrint('🔍 Has data: ${snapshot.hasData}');
                
                if (snapshot.connectionState == ConnectionState.waiting) {
                  debugPrint('⏳ Loading approved leave requests...');
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading approved leave requests...'),
                      ],
                    ),
                  );
                }

                if (snapshot.hasError) {
                  debugPrint('❌ Error in FutureBuilder: ${snapshot.error}');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          'Failed to load approved leave requests.',
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
                          onPressed: _fetchApprovedLeaveRequests,
                        ),
                      ],
                    ),
                  );
                }

                final approvedRequests = snapshot.data ?? [];
                debugPrint('✅ Loaded ${approvedRequests.length} approved leave requests');
                
                if (approvedRequests.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade400, size: 64),
                        const SizedBox(height: 16),
                        const Text(
                          'All Trips Processed',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'No approved leave requests require trip cancellation.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: approvedRequests.map((request) => 
                      ApprovedLeaveRequestCard(
                        request: request,
                        onCancelTrips: () {
                          debugPrint('🎯 ========================================');
                          debugPrint('🎯 CANCEL TRIPS CARD BUTTON CLICKED');
                          debugPrint('🎯 ========================================');
                          debugPrint('🎯 Request ID: ${request['id']}');
                          debugPrint('🎯 Customer: ${request['customerName']}');
                          debugPrint('🎯 Trips Count: ${request['affectedTripsCount']}');
                          debugPrint('🎯 Opening cancel dialog...');
                          _showCancelTripsDialog(request);
                        },
                        formatDate: _formatDate,
                        formatDateRange: _formatDateRange,
                        calculateDays: _calculateDays,
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

class ApprovedLeaveRequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onCancelTrips;
  final String Function(dynamic) formatDate;
  final String Function(dynamic, dynamic) formatDateRange;
  final int Function(dynamic, dynamic) calculateDays;

  const ApprovedLeaveRequestCard({
    super.key,
    required this.request,
    required this.onCancelTrips,
    required this.formatDate,
    required this.formatDateRange,
    required this.calculateDays,
  });

  @override
  Widget build(BuildContext context) {
    final affectedTrips = List<Map<String, dynamic>>.from(request['affectedTrips'] ?? []);

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
                
                // Urgent Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Action Required',
                    style: TextStyle(
                      color: Colors.orange,
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
                    'Trips to Cancel',
                    '${affectedTrips.length} trip(s)',
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Approval Details
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    Icons.person_outline,
                    'Approved By',
                    request['approvedBy'] ?? 'Unknown',
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    Icons.schedule,
                    'Approved At',
                    formatDate(request['approvedAt']),
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
            
            // Affected Trips Preview
            if (affectedTrips.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Trips to be Cancelled:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              ...affectedTrips.take(3).map((trip) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      _getTripTypeIcon(trip['rosterType']),
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TripLocationText(
                        rosterType: trip['rosterType']?.toString().toUpperCase() ?? '',
                        officeLocation: trip['officeLocation'] ?? '',
                        fromTime: trip['fromTime'] ?? '',
                      ),
                    ),
                    if (trip['assignedDriver'] != null)
                      Text(
                        'Driver: ${trip['assignedDriver']['driverName'] ?? 'Unknown'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              )),
              if (affectedTrips.length > 3)
                Text(
                  'and ${affectedTrips.length - 3} more...',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade600,
                  ),
                ),
            ],
            
            // Actions
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: onCancelTrips,
                  icon: const Icon(Icons.cancel_schedule_send),
                  label: const Text('Cancel Trips'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
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

  IconData _getTripTypeIcon(String? rosterType) {
    switch (rosterType) {
      case 'login':
        return Icons.login;
      case 'logout':
        return Icons.logout;
      case 'both':
        return Icons.swap_horiz;
      default:
        return Icons.trip_origin;
    }
  }
}

// Helper widget to display trip location with geocoding
class _TripLocationText extends StatelessWidget {
  final String rosterType;
  final String officeLocation;
  final String fromTime;

  const _TripLocationText({
    required this.rosterType,
    required this.officeLocation,
    required this.fromTime,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: GeocodingService().getAddressFromLocation(officeLocation),
      builder: (context, snapshot) {
        final address = snapshot.data ?? officeLocation;
        return Text(
          '$rosterType - $address ($fromTime)',
          style: const TextStyle(fontSize: 14),
        );
      },
    );
  }
}