// lib/features/admin/vehicle_admin_management/trip_operations/emergency_alert_screen.dart

import 'package:flutter/material.dart';
import 'package:abra_fleet/features/admin/vehicle_admin_management/trip_operations/emergency_map_screen.dart';
import 'package:abra_fleet/features/admin/vehicle_admin_management/trip_operations/live_map_screen.dart';

const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kTextPrimaryColor = Color(0xFF212121);
const Color kTextSecondaryColor = Color(0xFF757575);
const Color kEmergencyColor = Color(0xFFD32F2F);
const Color kWarningColor = Color(0xFFF57C00);
const Color kSuccessColor = Color(0xFF388E3C);
const Color kInfoBackgroundColor = Color(0xFFE3F2FD);

enum EmergencyType {
  accident,
  breakdown,
  medical,
  security,
  weather,
  other,
}

class EmergencyAlert {
  final String id;
  final String vehicleId;
  final String vehicleName;
  final String driverName;
  final EmergencyType type;
  final String description;
  final DateTime timestamp;
  final String location;
  final double? latitude;
  final double? longitude;
  final String status; // active, resolved, cancelled
  final int passengersAffected;

  EmergencyAlert({
    required this.id,
    required this.vehicleId,
    required this.vehicleName,
    required this.driverName,
    required this.type,
    required this.description,
    required this.timestamp,
    required this.location,
    this.latitude,
    this.longitude,
    required this.status,
    required this.passengersAffected,
  });
}

class EmergencyAlertScreen extends StatefulWidget {
  const EmergencyAlertScreen({Key? key}) : super(key: key);

  @override
  State<EmergencyAlertScreen> createState() => _EmergencyAlertScreenState();
}

class _EmergencyAlertScreenState extends State<EmergencyAlertScreen> {

  final List<EmergencyAlert> _activeAlerts = [
    EmergencyAlert(
      id: 'EM001',
      vehicleId: 'VH002',
      vehicleName: 'Van B-08',
      driverName: 'Jane Smith',
      type: EmergencyType.breakdown,
      description: 'Engine overheating on highway',
      timestamp: DateTime.now().subtract(const Duration(minutes: 15)),
      location: 'Kalyan Nagar',
      latitude: 12.9716,
      longitude: 77.5946,
      status: 'active',
      passengersAffected: 12,
    ),
  ];

  @override
  void dispose() {
    super.dispose();
  }

  String _getEmergencyTypeLabel(EmergencyType type) {
    switch (type) {
      case EmergencyType.accident:
        return 'Accident';
      case EmergencyType.breakdown:
        return 'Vehicle Breakdown';
      case EmergencyType.medical:
        return 'Medical Emergency';
      case EmergencyType.security:
        return 'Security Threat';
      case EmergencyType.weather:
        return 'Weather Hazard';
      case EmergencyType.other:
        return 'Other Emergency';
    }
  }

  IconData _getEmergencyTypeIcon(EmergencyType type) {
    switch (type) {
      case EmergencyType.accident:
        return Icons.car_crash;
      case EmergencyType.breakdown:
        return Icons.build_circle;
      case EmergencyType.medical:
        return Icons.medical_services;
      case EmergencyType.security:
        return Icons.security;
      case EmergencyType.weather:
        return Icons.thunderstorm;
      case EmergencyType.other:
        return Icons.warning;
    }
  }

  void _trackEmergencyVehicle(EmergencyAlert alert) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.map, color: kPrimaryColor),
          const SizedBox(width: 8),
          Text('Track ${alert.vehicleName}'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Opening live map view for emergency vehicle...'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kInfoBackgroundColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.location_on, size: 20, color: kPrimaryColor),
                    const SizedBox(width: 8),
                    Expanded(child: Text(alert.location)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.access_time, size: 20, color: kTextSecondaryColor),
                    const SizedBox(width: 8),
                    Text('${DateTime.now().difference(alert.timestamp).inMinutes} min ago'),
                  ]),
                  if (alert.latitude != null && alert.longitude != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'GPS: ${alert.latitude!.toStringAsFixed(4)}, ${alert.longitude!.toStringAsFixed(4)}',
                      style: const TextStyle(fontSize: 12, color: kTextSecondaryColor),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('📍 Features on map:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildMapFeatureItem('Vehicle location highlighted in red'),
            _buildMapFeatureItem('Real-time GPS tracking'),
            _buildMapFeatureItem('Nearest hospitals & emergency services'),
            _buildMapFeatureItem('Estimated arrival time of support'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.map),
            label: const Text('Open Map'),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EmergencyMapScreen(
                    vehicleName: alert.vehicleName,
                    vehicleId: alert.vehicleId,
                    emergencyType: _getEmergencyTypeLabel(alert.type),
                    location: alert.location,
                    latitude: alert.latitude ?? 12.9716,
                    longitude: alert.longitude ?? 77.5946,
                    description: alert.description,
                    passengersAffected: alert.passengersAffected,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        const Icon(Icons.check_circle, size: 16, color: kSuccessColor),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }

  void _resolveEmergency(EmergencyAlert alert) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resolve Emergency'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Mark this emergency as resolved?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(children: [
                Row(children: [
                  const Text('Vehicle: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(alert.vehicleName),
                ]),
                Row(children: [
                  const Text('Type: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(_getEmergencyTypeLabel(alert.type)),
                ]),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Emergency resolved successfully'),
                  ]),
                  backgroundColor: kSuccessColor,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kSuccessColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
  }

  void _broadcastAlert() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.notifications_active, color: kWarningColor),
            const SizedBox(width: 8),
            const Text('Broadcast Alert'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Send emergency notification to all fleet vehicles?',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kWarningColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kWarningColor),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ This will notify:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('• All active drivers (24 vehicles)'),
                  Text('• Fleet management team'),
                  Text('• Emergency response coordinators'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('Send Broadcast'),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Broadcast sent to all vehicles'),
                    ],
                  ),
                  backgroundColor: kSuccessColor,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kWarningColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showAlertHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AlertHistoryScreen(),
      ),
    );
  }

  void _notifyContacts() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.people, color: kPrimaryColor),
            const SizedBox(width: 8),
            const Text('Notify Emergency Contacts'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select contacts to notify:'),
            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text('Fleet Manager'),
              subtitle: const Text('+1 234-567-8900'),
              value: true,
              onChanged: (value) {},
            ),
            CheckboxListTile(
              title: const Text('Emergency Services'),
              subtitle: const Text('911'),
              value: true,
              onChanged: (value) {},
            ),
            CheckboxListTile(
              title: const Text('Passenger Families'),
              subtitle: const Text('12 contacts'),
              value: false,
              onChanged: (value) {},
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('Send Notifications'),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Notifications sent to selected contacts'),
                  backgroundColor: kSuccessColor,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const EmergencySettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEmergencyHeader(),
            const SizedBox(height: 24),
            if (_activeAlerts.isNotEmpty) ...[
              _buildActiveAlertsSection(),
              const SizedBox(height: 24),
            ],
            _buildEmergencyContacts(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kEmergencyColor, kEmergencyColor.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: kEmergencyColor.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.emergency,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Emergency Alert System',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Immediate response for critical situations',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_activeAlerts.length} Active',
              style: const TextStyle(
                color: kEmergencyColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveAlertsSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active, color: kEmergencyColor),
                const SizedBox(width: 8),
                const Text(
                  'Active Emergencies',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _showAlertHistory,
                  child: const Text('View All'),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            ..._activeAlerts.map((alert) => _buildActiveAlertCard(alert)),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveAlertCard(EmergencyAlert alert) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kEmergencyColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kEmergencyColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _getEmergencyTypeIcon(alert.type),
                color: kEmergencyColor,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.vehicleName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      _getEmergencyTypeLabel(alert.type),
                      style: TextStyle(
                        color: kTextSecondaryColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Chip(
                label: Text(
                  '${alert.passengersAffected} PAX',
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: kWarningColor.withOpacity(0.2),
                labelStyle: const TextStyle(color: kWarningColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            alert.description,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.location_on, size: 16, color: kTextSecondaryColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  alert.location,
                  style: TextStyle(
                    color: kTextSecondaryColor,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '${alert.timestamp.difference(DateTime.now()).inMinutes.abs()} min ago',
                style: TextStyle(
                  color: kTextSecondaryColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.assignment_ind, size: 18),
                  label: const Text('Assign Rescue Vehicle'),
                  onPressed: () {
                    // Safety check for GPS coordinates before navigating
                    if (alert.latitude == null || alert.longitude == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cannot assign rescue: Emergency location is missing GPS coordinates.'),
                          backgroundColor: kEmergencyColor,
                        ),
                      );
                      return;
                    }
                    // Navigate to the LiveMapScreen in "rescue mode"
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LiveMapScreen(
                          rescueMissionForAlert: alert,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kWarningColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.map, size: 16),
                      label: const Text('Track'),
                      onPressed: () => _trackEmergencyVehicle(alert),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kPrimaryColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Resolve'),
                      onPressed: () => _resolveEmergency(alert),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kSuccessColor,
                        side: const BorderSide(color: kSuccessColor),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyContacts() {
    final contacts = [
      {'name': 'Emergency Services', 'number': '911', 'icon': Icons.local_hospital},
      {'name': 'Fleet Manager', 'number': '+1 234-567-8900', 'icon': Icons.person},
      {'name': 'Police Department', 'number': '+1 234-567-8901', 'icon': Icons.local_police},
      {'name': 'Roadside Assistance', 'number': '+1 234-567-8902', 'icon': Icons.car_repair},
    ];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.contact_phone, color: kPrimaryColor),
                SizedBox(width: 8),
                Text(
                  'Emergency Contacts',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...contacts.map((contact) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: kPrimaryColor.withOpacity(0.1),
                    child: Icon(contact['icon'] as IconData, color: kPrimaryColor),
                  ),
                  title: Text(contact['name'] as String),
                  subtitle: Text(contact['number'] as String),
                  trailing: IconButton(
                    icon: const Icon(Icons.phone, color: kSuccessColor),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Calling ${contact['name']}...'),
                          backgroundColor: kSuccessColor,
                        ),
                      );
                    },
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

// Alert History Screen
class AlertHistoryScreen extends StatelessWidget {
  const AlertHistoryScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final historyAlerts = [
      {
        'id': 'EM003', 'vehicle': 'Bus A-12', 'type': 'Accident', 'date': '2025-10-11', 'status': 'Resolved', 'responseTime': '8 min',
      },
      {
        'id': 'EM002', 'vehicle': 'Van D-22', 'type': 'Medical Emergency', 'date': '2025-10-10', 'status': 'Resolved', 'responseTime': '5 min',
      },
      {
        'id': 'EM001', 'vehicle': 'Bus C-15', 'type': 'Weather Hazard', 'date': '2025-10-09', 'status': 'Resolved', 'responseTime': '12 min',
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alert History'),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Exporting alert history...'),
                  backgroundColor: kSuccessColor,
                ),
              );
            },
            tooltip: 'Export Report',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search alerts...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: () {},
                  tooltip: 'Filter',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: historyAlerts.length,
              itemBuilder: (context, index) {
                final alert = historyAlerts[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: kSuccessColor.withOpacity(0.1),
                      child: const Icon(Icons.check, color: kSuccessColor),
                    ),
                    title: Text(
                      '${alert['vehicle']} - ${alert['type']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('ID: ${alert['id']}'),
                        Text('Date: ${alert['date']}'),
                        Text('Response Time: ${alert['responseTime']}'),
                      ],
                    ),
                    trailing: Chip(
                      label: Text(alert['status'] as String),
                      backgroundColor: kSuccessColor.withOpacity(0.2),
                      labelStyle: const TextStyle(
                        color: kSuccessColor,
                        fontSize: 12,
                      ),
                    ),
                    isThreeLine: true,
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

// Emergency Settings Screen
class EmergencySettingsScreen extends StatefulWidget {
  const EmergencySettingsScreen({Key? key}) : super(key: key);

  @override
  State<EmergencySettingsScreen> createState() => _EmergencySettingsScreenState();
}

class _EmergencySettingsScreenState extends State<EmergencySettingsScreen> {
  bool _autoNotifyManager = true;
  bool _autoNotifyPolice = false;
  bool _soundAlert = true;
  bool _vibrationAlert = true;
  double _alertRadius = 5.0; // km

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Settings'),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Auto Notifications',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Notify Fleet Manager'),
                    subtitle: const Text('Automatically notify on all emergencies'),
                    value: _autoNotifyManager,
                    onChanged: (value) {
                      setState(() {
                        _autoNotifyManager = value;
                      });
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Notify Police'),
                    subtitle: const Text('For security and accident emergencies'),
                    value: _autoNotifyPolice,
                    onChanged: (value) {
                      setState(() {
                        _autoNotifyPolice = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Alert Preferences',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Sound Alert'),
                    subtitle: const Text('Play sound for new emergencies'),
                    value: _soundAlert,
                    onChanged: (value) {
                      setState(() {
                        _soundAlert = value;
                      });
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Vibration Alert'),
                    subtitle: const Text('Vibrate on emergency notifications'),
                    value: _vibrationAlert,
                    onChanged: (value) {
                      setState(() {
                        _vibrationAlert = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Geographic Settings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Alert Radius: ${_alertRadius.toStringAsFixed(1)} km'),
                  Slider(
                    value: _alertRadius,
                    min: 1,
                    max: 20,
                    divisions: 19,
                    label: '${_alertRadius.toStringAsFixed(1)} km',
                    onChanged: (value) {
                      setState(() {
                        _alertRadius = value;
                      });
                    },
                  ),
                  const Text(
                    'Find nearby emergency services within this radius',
                    style: TextStyle(
                      fontSize: 12,
                      color: kTextSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Emergency Contacts',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.add_circle, color: kPrimaryColor),
                    title: const Text('Add New Contact'),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Add contact feature coming soon'),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit, color: kPrimaryColor),
                    title: const Text('Manage Contacts'),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Manage contacts feature coming soon'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text(
                'Save Settings',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Settings saved successfully'),
                    backgroundColor: kSuccessColor,
                  ),
                );
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: Colors.white,
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