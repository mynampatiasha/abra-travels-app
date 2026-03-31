import 'package:flutter/material.dart';
import '../../../../../core/services/roster_service.dart';
import '../../../../../core/services/api_service.dart';

class MyAddressRequestsScreen extends StatefulWidget {
  const MyAddressRequestsScreen({Key? key}) : super(key: key);

  @override
  State<MyAddressRequestsScreen> createState() => _MyAddressRequestsScreenState();
}

class _MyAddressRequestsScreenState extends State<MyAddressRequestsScreen> {
  late final RosterService _rosterService;
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String _selectedStatus = 'all';

  final List<Map<String, String>> _statusOptions = [
    {'value': 'all', 'label': 'All'},
    {'value': 'under_review', 'label': 'Under Review'},
    {'value': 'processing', 'label': 'Processing'},
    {'value': 'completed', 'label': 'Completed'},
    {'value': 'rejected', 'label': 'Rejected'},
  ];

  @override
  void initState() {
    super.initState();
    _rosterService = RosterService(apiService: ApiService());
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);

    try {
      final response = await _rosterService.getAddressChangeRequests(_selectedStatus);
      
      if (response['success'] == true && response['data'] != null) {
        setState(() {
          _requests = List<Map<String, dynamic>>.from(response['data']);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading requests: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'under_review':
        return Colors.orange;
      case 'processing':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'under_review':
        return 'Under Review';
      case 'processing':
        return 'Processing';
      case 'completed':
        return 'Completed';
      case 'rejected':
        return 'Rejected';
      default:
        return status;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'under_review':
        return Icons.pending;
      case 'processing':
        return Icons.sync;
      case 'completed':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Address Requests'),
        backgroundColor: const Color(0xFF2196F3),
      ),
      body: Column(
        children: [
          // Status Filter
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                const Text(
                  'Filter:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _statusOptions.map((option) {
                        final isSelected = _selectedStatus == option['value'];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(option['label']!),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                _selectedStatus = option['value']!;
                              });
                              _loadRequests();
                            },
                            selectedColor: const Color(0xFF2196F3),
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Requests List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _requests.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.location_off,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No address change requests',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadRequests,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _requests.length,
                          itemBuilder: (context, index) {
                            final request = _requests[index];
                            return _buildRequestCard(request);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final status = request['status'] ?? 'unknown';
    final statusColor = _getStatusColor(status);
    final createdAt = DateTime.parse(request['createdAt']);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getStatusIcon(status), size: 16, color: statusColor),
                      const SizedBox(width: 6),
                      Text(
                        _getStatusLabel(status),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Addresses
            _buildAddressRow(
              'Pickup',
              request['currentPickupAddress'] ?? '',
              request['newPickupAddress'] ?? '',
            ),
            const SizedBox(height: 12),
            _buildAddressRow(
              'Drop',
              request['currentDropAddress'] ?? '',
              request['newDropAddress'] ?? '',
            ),

            // Reason
            if (request['reason'] != null && request['reason'].toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.comment, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      request['reason'],
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Affected Trips Count
            if (request['affectedTripsCount'] != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Text(
                      '${request['affectedTripsCount']} upcoming trips affected',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Completion Details
            if (status == 'completed' && request['vehicleNumber'] != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              _buildCompletionDetails(request),
            ],

            // Rejection Reason
            if (status == 'rejected' && request['rejectionReason'] != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rejection Reason:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            request['rejectionReason'],
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.red.shade900,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildAddressRow(String label, String oldAddress, String newAddress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                oldAddress.isEmpty ? 'Not set' : oldAddress,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  decoration: TextDecoration.lineThrough,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.arrow_forward, size: 14, color: Colors.green.shade700),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                newAddress,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.green.shade700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompletionDetails(Map<String, dynamic> request) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, size: 18, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Text(
                'Assignment Details',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildDetailRow('Vehicle', '${request['vehicleNumber']} (${request['vehicleType']})'),
          _buildDetailRow('Driver', request['driverName'] ?? 'Not assigned'),
          if (request['pickupTime'] != null)
            _buildDetailRow('Pickup Time', request['pickupTime']),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
