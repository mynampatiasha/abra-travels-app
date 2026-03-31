// lib/features/admin/rosters/widgets/group_details_dialog.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:abra_fleet/core/services/assignment_service.dart';
import 'package:abra_fleet/features/admin/customer_management/notification/rosters/vehicle_selection_dialog.dart';

class GroupDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> group;
  final AssignmentService assignmentService;
  final VoidCallback onAssignmentSuccess;

  const GroupDetailsDialog({
    super.key,
    required this.group,
    required this.assignmentService,
    required this.onAssignmentSuccess,
  });

  String _safeString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Map) {
      if (value.containsKey('address')) return _safeString(value['address']);
      if (value.containsKey('name')) return _safeString(value['name']);
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final rosters = List<Map<String, dynamic>>.from(group['rosters'] ?? []);
    final emailDomain = _safeString(group['emailDomain']);
    final officeLocation = _safeString(group['officeLocation']);
    final startTime = _safeString(group['startTime']);
    final rosterType = _safeString(group['rosterType']);
    final employeeCount = group['employeeCount'] ?? 0;
    final rosterIds = List<String>.from(group['rosterIds'] ?? []);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 800,
        constraints: const BoxConstraints(maxHeight: 900),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            _buildHeader(emailDomain, officeLocation, startTime, employeeCount, context),
            
            const Divider(height: 1),
            
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Group Info Card
                    _buildGroupInfoCard(officeLocation, startTime, rosterType, employeeCount),
                    
                    const SizedBox(height: 24),
                    
                    // Passengers List
                    const Text(
                      'Passengers in this Group',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Passenger cards
                    ...rosters.asMap().entries.map((entry) {
                      final index = entry.key;
                      final roster = entry.value;
                      return _buildPassengerCard(roster, index + 1);
                    }),
                  ],
                ),
              ),
            ),

            // Footer with actions
            _buildFooter(context, rosterIds),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String emailDomain, String officeLocation, String startTime, int count, BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.groups, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$officeLocation - $startTime',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '@$emailDomain • $count passengers',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupInfoCard(String officeLocation, String startTime, String rosterType, int count) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF10B981).withOpacity(0.1),
            const Color(0xFF10B981).withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildInfoItem(
              icon: Icons.location_on,
              label: 'Office Location',
              value: officeLocation,
              color: const Color(0xFF10B981),
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.grey.shade300,
            margin: const EdgeInsets.symmetric(horizontal: 16),
          ),
          Expanded(
            child: _buildInfoItem(
              icon: Icons.access_time,
              label: 'Pickup Time',
              value: startTime,
              color: const Color(0xFF3B82F6),
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.grey.shade300,
            margin: const EdgeInsets.symmetric(horizontal: 16),
          ),
          Expanded(
            child: _buildInfoItem(
              icon: Icons.people,
              label: 'Total Passengers',
              value: '$count',
              color: const Color(0xFF8B5CF6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildPassengerCard(Map<String, dynamic> roster, int sequence) {
    final customerName = _safeString(roster['customerName']);
    final customerEmail = _safeString(roster['customerEmail']);
    final customerPhone = _safeString(roster['customerPhone']);
    final pickupAddress = _safeString(roster['locations']?['pickup']?['address'] ?? 
                                     roster['pickupLocation']);
    final dropAddress = _safeString(roster['locations']?['drop']?['address'] ?? 
                                   roster['officeLocation']);
    final startTime = _safeString(roster['startTime']);
    final endTime = _safeString(roster['endTime']);
    final priority = _safeString(roster['priority']);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sequence number
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                '$sequence',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          
          // Passenger details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name and priority
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        customerName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    if (priority.toLowerCase() == 'high')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.priority_high, size: 14, color: Colors.red.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'HIGH PRIORITY',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Contact info
                Row(
                  children: [
                    Expanded(
                      child: _buildContactChip(
                        icon: Icons.email,
                        text: customerEmail,
                        color: const Color(0xFF3B82F6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildContactChip(
                        icon: Icons.phone,
                        text: customerPhone,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Locations
                _buildLocationRow(
                  icon: Icons.trip_origin,
                  label: 'Pickup',
                  address: pickupAddress,
                  color: const Color(0xFF10B981),
                ),
                const SizedBox(height: 10),
                _buildLocationRow(
                  icon: Icons.location_on,
                  label: 'Drop',
                  address: dropAddress,
                  color: const Color(0xFFEF4444),
                ),
                
                const SizedBox(height: 16),
                
                // Time info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.schedule, size: 18, color: Colors.grey.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Pickup: $startTime',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      if (endTime.isNotEmpty) ...[
                        const SizedBox(width: 16),
                        Icon(Icons.arrow_forward, size: 14, color: Colors.grey.shade400),
                        const SizedBox(width: 16),
                        Text(
                          'Drop: $endTime',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactChip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow({
    required IconData icon,
    required String label,
    required String address,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                address.isNotEmpty ? address : 'Not specified',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade800,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context, List<String> rosterIds) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: BorderSide(color: Colors.grey.shade400),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop(); // Close this dialog
                // Open vehicle selection dialog
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => VehicleSelectionDialog(
                    rosterIds: rosterIds,
                    assignmentService: assignmentService,
                    onAssignmentSuccess: onAssignmentSuccess,
                  ),
                );
              },
              icon: const Icon(Icons.local_shipping),
              label: Text('Assign Vehicle to ${rosterIds.length} Passengers'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}