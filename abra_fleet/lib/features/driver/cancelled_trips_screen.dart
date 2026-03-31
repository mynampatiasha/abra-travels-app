// lib/features/driver/cancelled_trips_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:abra_fleet/core/services/backend_connection_manager.dart';
import 'package:abra_fleet/core/services/api_service.dart';

class CancelledTripsScreen extends StatefulWidget {
  const CancelledTripsScreen({super.key});

  @override
  State<CancelledTripsScreen> createState() => _CancelledTripsScreenState();
}

class _CancelledTripsScreenState extends State<CancelledTripsScreen> {
  late final ApiService _apiService;
  late Future<List<Map<String, dynamic>>> _cancelledTripsFuture;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _apiService = BackendConnectionManager().apiService;
    _fetchCancelledTrips();
  }

  void _fetchCancelledTrips() {
    setState(() {
      _cancelledTripsFuture = _getCancelledTrips();
    });
  }

  Future<List<Map<String, dynamic>>> _getCancelledTrips() async {
    try {
      final response = await _apiService.get('/api/roster/driver/cancelled-trips');

      if (response['success'] == true) {
        return List<Map<String, dynamic>>.from(response['data'] ?? []);
      } else {
        throw Exception(response['message'] ?? 'Failed to fetch cancelled trips');
      }
    } catch (e) {
      debugPrint('❌ Error fetching cancelled trips: $e');
      rethrow;
    }
  }

  Future<void> _acknowledgeCancellation(String tripId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _apiService.put('/api/roster/driver/acknowledge-cancellation/$tripId');

      if (response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Trip cancellation acknowledged'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchCancelledTrips();
        }
      } else {
        throw Exception(response['message'] ?? 'Failed to acknowledge cancellation');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to acknowledge: ${e.toString()}'),
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

  void _showTripDetails(Map<String, dynamic> trip) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(Icons.cancel, color: Colors.red),
                    const SizedBox(width: 8),
                    const Text(
                      'Cancelled Trip Details',
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
                        // Trip Information
                        _buildDetailSection(
                          'Trip Information',
                          [
                            _buildDetailRow('Trip ID', trip['readableId'] ?? trip['id']),
                            _buildDetailRow('Customer', trip['customerName'] ?? 'Unknown'),
                            _buildDetailRow('Type', trip['rosterType']?.toString().toUpperCase() ?? 'N/A'),
                            _buildDetailRow('Office Location', trip['officeLocation'] ?? 'N/A'),
                          ],
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Schedule Information
                        _buildDetailSection(
                          'Original Schedule',
                          [
                            _buildDetailRow('Date', _formatDate(trip['scheduledDate'])),
                            _buildDetailRow('Time', trip['scheduledTime'] ?? 'N/A'),
                            if (trip['loginPickupAddress'] != null && trip['loginPickupAddress'].isNotEmpty)
                              _buildDetailRow('Pickup Location', trip['loginPickupAddress']),
                            if (trip['logoutDropAddress'] != null && trip['logoutDropAddress'].isNotEmpty)
                              _buildDetailRow('Drop Location', trip['logoutDropAddress']),
                          ],
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Cancellation Information
                        _buildDetailSection(
                          'Cancellation Details',
                          [
                            _buildDetailRow('Reason', trip['cancellationReason'] ?? 'No reason provided'),
                            _buildDetailRow('Cancelled By', trip['cancelledBy'] ?? 'Unknown'),
                            _buildDetailRow('Cancelled At', _formatDateTime(trip['cancelledAt'])),
                            if (trip['adminNotes'] != null && trip['adminNotes'].isNotEmpty)
                              _buildDetailRow('Admin Notes', trip['adminNotes']),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Actions
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _acknowledgeCancellation(trip['id']);
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Acknowledge'),
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
            color: Color(0xFF0D47A1),
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

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      final dateTime = date is String ? DateTime.parse(date) : date as DateTime;
      return DateFormat('MMM dd, yyyy').format(dateTime);
    } catch (e) {
      return date.toString();
    }
  }

  String _formatDateTime(dynamic date) {
    if (date == null) return 'N/A';
    try {
      final dateTime = date is String ? DateTime.parse(date) : date as DateTime;
      return DateFormat('MMM dd, yyyy HH:mm').format(dateTime);
    } catch (e) {
      return date.toString();
    }
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

  Color _getCancellationReasonColor(String? reason) {
    if (reason != null && reason.toLowerCase().contains('leave')) {
      return Colors.blue;
    }
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cancelled Trips'),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchCancelledTrips,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _cancelledTripsFuture,
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
                    'Failed to load cancelled trips.',
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
                    onPressed: _fetchCancelledTrips,
                  ),
                ],
              ),
            );
          }

          final cancelledTrips = snapshot.data ?? [];
          
          if (cancelledTrips.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade400, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'No Cancelled Trips',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You don\'t have any cancelled trips.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: cancelledTrips.length,
            itemBuilder: (context, index) {
              final trip = cancelledTrips[index];
              return CancelledTripCard(
                trip: trip,
                onViewDetails: () => _showTripDetails(trip),
                onAcknowledge: () => _acknowledgeCancellation(trip['id']),
                formatDate: _formatDate,
                formatDateTime: _formatDateTime,
                getTripTypeIcon: _getTripTypeIcon,
                getCancellationReasonColor: _getCancellationReasonColor,
              );
            },
          );
        },
      ),
    );
  }
}

class CancelledTripCard extends StatelessWidget {
  final Map<String, dynamic> trip;
  final VoidCallback onViewDetails;
  final VoidCallback onAcknowledge;
  final String Function(dynamic) formatDate;
  final String Function(dynamic) formatDateTime;
  final IconData Function(String?) getTripTypeIcon;
  final Color Function(String?) getCancellationReasonColor;

  const CancelledTripCard({
    super.key,
    required this.trip,
    required this.onViewDetails,
    required this.onAcknowledge,
    required this.formatDate,
    required this.formatDateTime,
    required this.getTripTypeIcon,
    required this.getCancellationReasonColor,
  });

  @override
  Widget build(BuildContext context) {
    final cancellationReason = trip['cancellationReason'] ?? 'Unknown reason';
    final reasonColor = getCancellationReasonColor(cancellationReason);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  // Trip Type Icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      getTripTypeIcon(trip['rosterType']),
                      color: Colors.red.shade700,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Trip Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${trip['rosterType']?.toString().toUpperCase()} Trip',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (trip['readableId'] != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  trip['readableId'],
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          trip['customerName'] ?? 'Unknown Customer',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Cancelled Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'CANCELLED',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Trip Details
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      Icons.business,
                      'Office',
                      trip['officeLocation'] ?? 'N/A',
                    ),
                  ),
                  Expanded(
                    child: _buildInfoItem(
                      Icons.calendar_today,
                      'Date',
                      formatDate(trip['scheduledDate']),
                    ),
                  ),
                  Expanded(
                    child: _buildInfoItem(
                      Icons.access_time,
                      'Time',
                      trip['scheduledTime'] ?? 'N/A',
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Cancellation Details
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: reasonColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: reasonColor.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: reasonColor, size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          'Cancellation Details',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Reason: $cancellationReason',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cancelled by: ${trip['cancelledBy'] ?? 'Unknown'}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cancelled at: ${formatDateTime(trip['cancelledAt'])}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
              
              // Actions
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: onViewDetails,
                    icon: const Icon(Icons.info_outline),
                    label: const Text('View Details'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0D47A1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: onAcknowledge,
                    icon: const Icon(Icons.check),
                    label: const Text('Acknowledge'),
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