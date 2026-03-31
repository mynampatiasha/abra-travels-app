import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AssignedCustomersDialog extends StatelessWidget {
  final Map<String, dynamic> vehicleData;
  final List<Map<String, dynamic>> customers;
  final Map<String, dynamic>? driver;
  final Map<String, dynamic>? capacity;

  const AssignedCustomersDialog({
    super.key,
    required this.vehicleData,
    required this.customers,
    this.driver,
    this.capacity,
  });

  @override
  Widget build(BuildContext context) {
    final vehicleName = vehicleData['name'] ?? vehicleData['vehicleNumber'] ?? 'Unknown';
    
    // Use capacity data from backend if available, otherwise calculate
    final int seatCapacity;
    final int availableSeats;
    
    if (capacity != null) {
      // Use pre-calculated capacity from backend
      seatCapacity = capacity!['total'] ?? 0;
      availableSeats = capacity!['available'] ?? 0;
    } else {
      // Fallback: calculate manually
      seatCapacity = vehicleData['seatingCapacity'] ?? vehicleData['seatCapacity'] ?? 0;
      availableSeats = seatCapacity - 1 - customers.length;
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 700,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.directions_car, color: Colors.white, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vehicleName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${customers.length} customers assigned • $availableSeats/$seatCapacity seats available',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
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
            ),

            // Driver Info (if available)
            if (driver != null)
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.grey.shade100,
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.green.shade100,
                      child: Icon(Icons.person, color: Colors.green.shade700),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Driver: ${driver!['name'] ?? 'Unknown'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          if (driver!['phone'] != null)
                            Text(
                              driver!['phone'],
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Customer List
            Flexible(
              child: customers.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No Customers Assigned',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'This vehicle is currently empty',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: customers.length,
                      separatorBuilder: (_, __) => const Divider(height: 24),
                      itemBuilder: (context, index) {
                        final customer = customers[index];
                        return _buildCustomerCard(customer, index + 1);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard(Map<String, dynamic> customer, int sequence) {
    // Safe string conversion helper
    String _safeString(dynamic value, [String defaultValue = 'N/A']) {
      if (value == null) return defaultValue;
      if (value is String) return value;
      if (value is Map) return value.toString();
      return value.toString();
    }
    
    final loginTime = _safeString(customer['loginTime']);
    final logoutTime = _safeString(customer['logoutTime']);
    final loginLocation = _safeString(customer['loginLocation']);
    final logoutLocation = _safeString(customer['logoutLocation']);
    final rosterType = _safeString(customer['rosterType'], 'both');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blue.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Customer Name & Sequence
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      '$sequence',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _safeString(customer['customerName'], 'Unknown'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _safeString(customer['organization']),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildRosterTypeBadge(rosterType),
              ],
            ),
            const SizedBox(height: 16),

            // Time Slots
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                children: [
                  // Login Time
                  if (rosterType == 'login' || rosterType == 'both')
                    Row(
                      children: [
                        Icon(Icons.login, size: 18, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pickup: $loginTime',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade900,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                loginLocation,
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                  // Divider between login and logout
                  if (rosterType == 'both')
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(color: Colors.green.shade300, height: 1),
                    ),

                  // Logout Time
                  if (rosterType == 'logout' || rosterType == 'both')
                    Row(
                      children: [
                        Icon(Icons.logout, size: 18, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Drop: $logoutTime',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade900,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                logoutLocation,
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // Contact Info
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.phone, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  _safeString(customer['customerPhone']),
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 16),
                Icon(Icons.email, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _safeString(customer['customerEmail']),
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRosterTypeBadge(String rosterType) {
    Color color;
    String label;
    IconData icon;

    switch (rosterType) {
      case 'login':
        color = Colors.green;
        label = 'Pickup Only';
        icon = Icons.login;
        break;
      case 'logout':
        color = Colors.orange;
        label = 'Drop Only';
        icon = Icons.logout;
        break;
      default:
        color = Colors.blue;
        label = 'Both Ways';
        icon = Icons.swap_horiz;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
