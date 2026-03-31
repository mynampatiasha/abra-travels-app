import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/core/services/vehicle_service.dart';
import 'package:abra_fleet/core/utils/export_helper.dart';
import 'package:intl/intl.dart';
import 'package:country_state_city/country_state_city.dart' as csc;
import 'package:abra_fleet/features/admin/admin_live_location_whole_vehicles.dart';

class AdminClientTripsPage extends StatefulWidget {
  const AdminClientTripsPage({Key? key}) : super(key: key);

  @override
  _AdminClientTripsPageState createState() => _AdminClientTripsPageState();
}

class _AdminClientTripsPageState extends State<AdminClientTripsPage> {
  final VehicleService _vehicleService = VehicleService();

  List<Map<String, dynamic>> _allTrips = [];
  List<Map<String, dynamic>> _filteredTrips = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedFilter = 'All';
  Timer? _autoRefreshTimer;

  // Synced scroll controllers
  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _bodyScrollController = ScrollController();
  bool _isSyncingScroll = false;

  // ── NEW: Search query (Row 2) ─────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ── NEW: Row-1 CSC filter state ───────────────────────────────────────────
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _filterCountry;
  String? _filterState;
  String? _filterCity;
  String? _filterLocalArea;

  final List<String> _filterOptions = [
    'All',
    'Pending',
    'Assigned',
    'Accepted',
    'Confirmed',
    'Started',
    'Completed',
    'Declined',
  ];

  // Column widths
  static const double _colTripNum = 150.0;
  static const double _colClient = 170.0;
  static const double _colPhone = 140.0;
  static const double _colPickup = 200.0;
  static const double _colDrop = 200.0;
  static const double _colDist = 100.0;
  static const double _colTime = 150.0;
  static const double _colStatus = 130.0;
  static const double _colDriverResp = 150.0;
  static const double _colDriver = 160.0;
  static const double _colVehicle = 140.0;
  static const double _colActions = 220.0;

  @override
  void initState() {
    super.initState();
    _loadTrips();
    _startAutoRefresh();
    _syncScrollControllers();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _headerScrollController.dispose();
    _bodyScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _syncScrollControllers() {
    _headerScrollController.addListener(() {
      if (_isSyncingScroll) return;
      _isSyncingScroll = true;
      if (_bodyScrollController.hasClients) {
        _bodyScrollController.jumpTo(_headerScrollController.offset);
      }
      _isSyncingScroll = false;
    });

    _bodyScrollController.addListener(() {
      if (_isSyncingScroll) return;
      _isSyncingScroll = true;
      if (_headerScrollController.hasClients) {
        _headerScrollController.jumpTo(_bodyScrollController.offset);
      }
      _isSyncingScroll = false;
    });
  }

  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (mounted) {
        _loadTrips(silent: true);
      }
    });
  }

  Future<void> _loadTrips({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      if (token == null || token.isEmpty) {
        throw Exception('Please login to view trips');
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/client-trips/all'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            setState(() {
              _allTrips = List<Map<String, dynamic>>.from(data['data'] ?? []);
              _applyFilter();
              _isLoading = false;
            });
          }
        } else {
          throw Exception(data['message'] ?? 'Failed to load trips');
        }
      } else {
        throw Exception('Failed to load trips: ${response.statusCode}');
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilter() {
    setState(() {
      _filteredTrips = _allTrips.where((trip) {
        // ── Status chip filter ──────────────────────────────────────────────
        if (_selectedFilter != 'All') {
          final status = trip['status']?.toString().toLowerCase() ?? '';
          final filterLower = _selectedFilter.toLowerCase();
          if (filterLower == 'pending') {
            if (status != 'pending_assignment' && status != 'pending') return false;
          } else if (filterLower == 'confirmed') {
            if (!(status == 'accepted' && trip['adminConfirmed'] == true)) return false;
          } else {
            if (status != filterLower) return false;
          }
        }

        // ── NEW: Search filter ──────────────────────────────────────────────
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery;
          final matchesTripNum  = (trip['tripNumber']?.toString().toLowerCase().contains(q) ?? false);
          final matchesClient   = (trip['clientName']?.toString().toLowerCase().contains(q) ?? false);
          final matchesPhone    = (trip['clientPhone']?.toString().toLowerCase().contains(q) ?? false);
          final matchesDriver   = (trip['driverName']?.toString().toLowerCase().contains(q) ?? false);
          if (!matchesTripNum && !matchesClient && !matchesPhone && !matchesDriver) return false;
        }

        // ── NEW: Date range filter ──────────────────────────────────────────
        if (_fromDate != null || _toDate != null) {
          final created = DateTime.tryParse(trip['createdAt']?.toString() ?? '');
          if (created != null) {
            if (_fromDate != null && created.isBefore(_fromDate!)) return false;
            if (_toDate != null && created.isAfter(_toDate!.add(const Duration(days: 1)))) return false;
          }
        }

        return true;
      }).toList();
    });
  }

  // ── NEW: Export to Excel ──────────────────────────────────────────────────
  Future<void> _exportToExcel() async {
    if (_filteredTrips.isEmpty) {
      _showErrorSnackBar('No trips to export');
      return;
    }

    _showSuccessSnackBar('Preparing Excel export...');

    try {
      List<List<dynamic>> csvData = [
        [
          'Trip #', 'Client Name', 'Client Phone', 'Client Email',
          'Pickup Location', 'Drop Location', 'Distance (km)',
          'Scheduled Time', 'Status', 'Driver Response',
          'Driver Name', 'Driver Phone', 'Vehicle', 'Admin Confirmed', 'Created At',
        ],
      ];

      for (final trip in _filteredTrips) {
        final status = trip['status']?.toString().toLowerCase() ?? '';
        final adminConfirmed = trip['adminConfirmed'] == true;
        csvData.add([
          trip['tripNumber'] ?? '',
          trip['clientName'] ?? '',
          trip['clientPhone'] ?? '',
          trip['clientEmail'] ?? '',
          trip['pickupLocation']?['address'] ?? '',
          trip['dropLocation']?['address'] ?? '',
          trip['distance'] != null
              ? (trip['distance'] as num).toStringAsFixed(1)
              : '',
          _formatExportDate(trip['scheduledPickupTime']),
          _getStatusLabel(status, adminConfirmed: adminConfirmed),
          trip['driverResponse']?.toString().toUpperCase() ?? 'AWAITING',
          trip['driverName'] ?? '',
          trip['driverPhone'] ?? '',
          trip['vehicleNumber'] ?? '',
          adminConfirmed ? 'YES' : 'NO',
          _formatExportDate(trip['createdAt']),
        ]);
      }

      await ExportHelper.exportToExcel(
        data: csvData,
        filename: 'client_trips_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
      );

      _showSuccessSnackBar('✅ Excel exported with ${_filteredTrips.length} trips!');
    } catch (e) {
      _showErrorSnackBar('Export failed: $e');
    }
  }

  String _formatExportDate(dynamic d) {
    if (d == null) return '';
    try {
      return DateFormat('dd/MM/yyyy HH:mm')
          .format(DateTime.parse(d.toString()).toLocal());
    } catch (_) {
      return d.toString();
    }
  }

  // ── NEW: WhatsApp helpers ─────────────────────────────────────────────────
  void _showWhatsAppDialog(Map<String, dynamic> trip) {
    final clientName  = trip['clientName']?.toString()  ?? 'Client';
    final clientPhone = trip['clientPhone']?.toString()  ?? '';
    final driverName  = trip['driverName']?.toString();
    final driverPhone = trip['driverPhone']?.toString()  ?? '';
    final hasDriver   = driverName != null && driverPhone.isNotEmpty;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF25D366).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.chat, color: Color(0xFF25D366), size: 22),
          ),
          const SizedBox(width: 10),
          const Text('Open WhatsApp',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Trip: ${trip['tripNumber'] ?? ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          const Text('Who would you like to message?',
              style: TextStyle(fontSize: 14)),
          const SizedBox(height: 14),
          if (clientPhone.isNotEmpty)
            _waOption(
              icon: Icons.person,
              color: Colors.blue,
              label: 'Message Client',
              name: clientName,
              phone: clientPhone,
              onTap: () {
                Navigator.pop(context);
                _openWhatsApp(clientPhone, clientName);
              },
            ),
          if (hasDriver) ...[
            const SizedBox(height: 10),
            _waOption(
              icon: Icons.drive_eta,
              color: Colors.green,
              label: 'Message Driver',
              name: driverName!,
              phone: driverPhone,
              onTap: () {
                Navigator.pop(context);
                _openWhatsApp(driverPhone, driverName);
              },
            ),
          ],
          if (clientPhone.isEmpty && !hasDriver)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('No phone numbers available',
                  style: TextStyle(color: Colors.grey.shade500)),
            ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _waOption({
    required IconData icon,
    required Color color,
    required String label,
    required String name,
    required String phone,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: color)),
              Text(name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              Text(phone,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ]),
          ),
          Icon(Icons.arrow_forward_ios, size: 13, color: color.withOpacity(0.6)),
        ]),
      ),
    );
  }

  Future<void> _openWhatsApp(String phone, String name) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final number  = cleaned.startsWith('+') ? cleaned : '+91$cleaned';
    final uri     = Uri.parse('https://wa.me/$number');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showErrorSnackBar('Could not open WhatsApp for $name');
      }
    } catch (e) {
      _showErrorSnackBar('WhatsApp error: $e');
    }
  }

  // ── NEW: Share Live Location via WhatsApp ──────────────────────────────────
  Future<void> _shareWhatsAppLiveLocation(Map<String, dynamic> trip) async {
    final tripId = _extractTripId(trip);
    if (tripId == null || tripId.isEmpty) {
      _showErrorSnackBar('Trip ID not found');
      return;
    }

    // The tracking URL
    final liveUrl = '${ApiConfig.baseUrl}/live-track/$tripId';

    final tripNumber = trip['tripNumber'] ?? 'N/A';
    final customerName = trip['clientName'] ?? trip['customer']?['name'] ?? 'Customer';
    final driverName = trip['driverName'] ?? 'Driver';
    final vehicleNum = trip['vehicleNumber'] ?? 'N/A';

    final message =
        'Hello $customerName! 👋\n\n'
        'Your trip *$tripNumber* is now live. 🚗\n'
        'Driver: *$driverName*\n'
        'Vehicle: *$vehicleNum*\n\n'
        '📍 Track your ride in real time:\n'
        '$liveUrl\n\n'
        'Thank you for choosing Abra Fleet!';

    final customerPhone = trip['clientPhone'] ?? trip['customer']?['phone'] ?? '';
    final driverPhone = trip['driverPhone']?.toString() ?? '';

    if (customerPhone.isNotEmpty && driverPhone.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.share_location, color: Color(0xFF25D366), size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Share Live Location', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Trip: $tripNumber', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            const Text('Send live tracking link to:', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 14),
            _waOption(
              icon: Icons.person,
              color: Colors.blue,
              label: 'Send to Customer',
              name: customerName,
              phone: customerPhone,
              onTap: () {
                Navigator.pop(context);
                _openWhatsAppWithMessage(customerPhone, message);
              },
            ),
            const SizedBox(height: 10),
            _waOption(
              icon: Icons.drive_eta,
              color: Colors.green,
              label: 'Send to Driver',
              name: driverName,
              phone: driverPhone,
              onTap: () {
                Navigator.pop(context);
                _openWhatsAppWithMessage(driverPhone, message);
              },
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      return;
    }

    final phone = customerPhone.isNotEmpty ? customerPhone : driverPhone;
    if (phone.isEmpty) {
      _showErrorSnackBar('No phone number available to share location');
      return;
    }
    _openWhatsAppWithMessage(phone, message);
  }

  // Opens WhatsApp with a pre-filled message
  Future<void> _openWhatsAppWithMessage(String phone, String message) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final number = cleaned.startsWith('+') ? cleaned : '+91$cleaned';
    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse('https://wa.me/$number?text=$encoded');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showErrorSnackBar('Could not open WhatsApp');
      }
    } catch (e) {
      _showErrorSnackBar('WhatsApp error: $e');
    }
  }

  String? _extractTripId(Map<String, dynamic> trip) {
    if (trip['_id'] != null) {
      if (trip['_id'] is Map && trip['_id']['\$oid'] != null) {
        return trip['_id']['\$oid'].toString();
      } else {
        return trip['_id'].toString();
      }
    }
    return null;
  }

  // ── Existing helpers (unchanged) ──────────────────────────────────────────

  Color _getStatusColor(String? status, {bool adminConfirmed = false}) {
    if (status?.toLowerCase() == 'accepted' && adminConfirmed) {
      return Colors.green;
    }
    switch (status?.toLowerCase()) {
      case 'pending_assignment':
      case 'pending':
        return Colors.orange;
      case 'assigned':
        return Colors.blue;
      case 'accepted':
        return Colors.teal;
      case 'started':
      case 'in_progress':
        return Colors.indigo;
      case 'completed':
        return Colors.green;
      case 'declined':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String? status, {bool adminConfirmed = false}) {
    if (status?.toLowerCase() == 'accepted' && adminConfirmed) {
      return 'Confirmed';
    }
    switch (status?.toLowerCase()) {
      case 'pending_assignment':
      case 'pending':
        return 'Pending';
      case 'assigned':
        return 'Assigned';
      case 'accepted':
        return 'Accepted';
      case 'started':
        return 'In Progress';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'declined':
        return 'Declined';
      default:
        return status?.toUpperCase() ?? 'Unknown';
    }
  }

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'N/A';
    try {
      DateTime dt;
      if (dateTime is String) {
        dt = DateTime.parse(dateTime);
      } else if (dateTime is DateTime) {
        dt = dateTime;
      } else {
        return 'N/A';
      }
      return DateFormat('MMM dd, yyyy\nhh:mm a').format(dt.toLocal());
    } catch (e) {
      return 'N/A';
    }
  }

  String _formatDateTimeShort(dynamic dateTime) {
    if (dateTime == null) return 'N/A';
    try {
      DateTime dt;
      if (dateTime is String) {
        dt = DateTime.parse(dateTime);
      } else if (dateTime is DateTime) {
        dt = dateTime;
      } else {
        return 'N/A';
      }
      return DateFormat('MMM dd, hh:mm a').format(dt.toLocal());
    } catch (e) {
      return 'N/A';
    }
  }

  // ============================================================================
  // ASSIGN VEHICLE DIALOG - Navigate to Live Map (same as trip_operations.dart)
  // ============================================================================

  Future<void> _showAssignVehicleDialog(Map<String, dynamic> trip) async {
    final tripId = _extractTripId(trip);
    if (tripId == null) {
      _showErrorSnackBar('Trip ID not found');
      return;
    }

    final tripContext = TripAssignmentContext(
      tripId: tripId,
      tripNumber: trip['tripNumber']?.toString() ?? 'N/A',
      customerName: trip['clientName'] ?? trip['client']?['name'] ?? 'Client',
      customerPhone: trip['clientPhone'] ?? trip['client']?['phone'] ?? '',
      pickupAddress: trip['pickupLocation']?['address'] ?? 'N/A',
      dropAddress: trip['dropLocation']?['address'] ?? 'N/A',
      scheduledPickupTime: _formatDateTime(trip['scheduledPickupTime']),
      isReassign: trip['status']?.toString().toLowerCase() == 'declined',
    );

    final assigned = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AdminLiveLocationWholeVehicles(
          tripAssignmentContext: tripContext,
        ),
      ),
    );

    if (assigned == true && mounted) {
      _loadTrips();
    }
  }

  // ============================================================================
  // OLD METHODS - No longer needed (using navigation to live map instead)
  // ============================================================================
  
  // Commented out - vehicle assignment now handled via AdminLiveLocationWholeVehicles
  /*
  Future<List<Map<String, dynamic>>> _loadVehicles() async {
    try {
      final response = await _vehicleService.getVehicles(limit: 100);
      if (response['success'] == true) {
        final List<dynamic> vehiclesData = response['data'] ?? [];
        return vehiclesData
            .where((vehicle) {
              final status =
                  (vehicle['status'] ?? 'active').toString().toUpperCase();
              final hasDriver = _hasAssignedDriver(vehicle);
              return status == 'ACTIVE' && hasDriver;
            })
            .map((vehicle) {
          String mongoId = '';
          if (vehicle['_id'] != null) {
            if (vehicle['_id'] is Map) {
              mongoId = vehicle['_id']['\$oid'] ?? '';
            } else {
              mongoId = vehicle['_id'].toString();
            }
          }
          final assignedDriver = vehicle['assignedDriver'];
          String driverName = 'No Driver';
          String driverPhone = '';
          if (assignedDriver != null) {
            if (assignedDriver is Map) {
              driverName = assignedDriver['name'] ?? 'Unknown Driver';
              driverPhone = assignedDriver['phone'] ?? '';
            } else if (assignedDriver is String) {
              driverName = assignedDriver;
            }
          }
          return {
            'id': mongoId,
            'vehicleId': vehicle['vehicleId'] ?? '',
            'registration': vehicle['registrationNumber'] ?? '',
            'type': (vehicle['type'] ?? '').toString().toUpperCase(),
            'model': '${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''}'.trim(),
            'driverName': driverName,
            'driverPhone': driverPhone,
          };
        }).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  bool _hasAssignedDriver(Map<String, dynamic> vehicle) {
    final assignedDriver = vehicle['assignedDriver'];
    if (assignedDriver == null) return false;
    if (assignedDriver is Map) {
      return assignedDriver.isNotEmpty &&
          (assignedDriver['name'] != null ||
              assignedDriver['driverId'] != null);
    } else if (assignedDriver is String) {
      return assignedDriver.isNotEmpty;
    }
    return false;
  }

  Future<void> _assignVehicle(
      Map<String, dynamic> trip, String vehicleId) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Assigning vehicle...'),
          ]),
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      final tripId = trip['_id'] is Map
          ? trip['_id']['\$oid']
          : trip['_id'].toString();

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/client-trips/$tripId/assign-vehicle'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'vehicleId': vehicleId}),
      );

      if (mounted) Navigator.of(context).pop();

      final responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        if (mounted) {
          Navigator.of(context).pop();
          _showSuccessSnackBar(
              'Vehicle assigned! Driver has been notified to Accept/Decline.');
          _loadTrips();
        }
      } else {
        throw Exception(responseData['message'] ?? 'Failed to assign vehicle');
      }
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      _showErrorSnackBar('Failed to assign vehicle: ${e.toString()}');
    }
  }
  */

  Future<void> _confirmAccepted(Map<String, dynamic> trip) async {
    final tripId =
        trip['_id'] is Map ? trip['_id']['\$oid'] : trip['_id'].toString();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 28),
            const SizedBox(width: 12),
            const Text('Confirm Trip',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Confirm this trip to notify the client?',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow(Icons.person, 'Client', trip['clientName'] ?? 'N/A'),
                  const SizedBox(height: 6),
                  _infoRow(Icons.drive_eta, 'Driver',
                      trip['driverName'] ?? 'N/A'),
                  const SizedBox(height: 6),
                  _infoRow(Icons.directions_car, 'Vehicle',
                      trip['vehicleNumber'] ?? 'N/A'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '✅ Client will be notified immediately after confirmation.',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              await _confirmTrip(tripId);
            },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Confirm & Notify Client'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.green.shade700),
        const SizedBox(width: 8),
        Text('$label: ',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700)),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500))),
      ],
    );
  }

  Future<void> _confirmTrip(String tripId) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Confirming trip & notifying client...'),
          ]),
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      final response = await http.post(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/client-trips/$tripId/confirm-accepted'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (mounted) Navigator.of(context).pop();

      final responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        if (mounted) {
          _showSuccessSnackBar(
              '✅ Trip confirmed! Client has been notified.');
          _loadTrips();
        }
      } else {
        throw Exception(responseData['message'] ?? 'Failed to confirm trip');
      }
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      _showErrorSnackBar('Failed to confirm trip: ${e.toString()}');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 4),
    ));
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 4),
    ));
  }

  // ============================================================================
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF1A237E),
        title: const Text(
          'Client Trip Requests',
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
        centerTitle: true,
        actions: [
          // Auto refresh indicator
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Tooltip(
              message: 'Auto-refreshing every 20s',
              child: Icon(Icons.sync,
                  color: Colors.white.withOpacity(0.7), size: 18),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadTrips(),
            tooltip: 'Refresh Now',
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState()
          : _errorMessage != null
              ? _buildErrorState()
              : _buildBody(),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircularProgressIndicator(
            valueColor:
                AlwaysStoppedAnimation<Color>(Color(0xFF1A237E))),
        SizedBox(height: 20),
        Text('Loading client trips...',
            style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.red.shade50, shape: BoxShape.circle),
            child: Icon(Icons.error_outline,
                size: 64, color: Colors.red.shade700),
          ),
          const SizedBox(height: 24),
          Text('Failed to Load Trips',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade900)),
          const SizedBox(height: 12),
          Text(_errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _loadTrips,
          ),
        ]),
      ),
    );
  }

  Widget _buildBody() {
    return Column(children: [
      // ── NEW: Row 1 — Location & Date filters ──────────────────────────────
      _AdminCscFilterRow(
        fromDate: _fromDate,
        toDate: _toDate,
        country: _filterCountry,
        state: _filterState,
        city: _filterCity,
        localArea: _filterLocalArea,
        onChanged: (filters) {
          setState(() {
            _fromDate      = filters['fromDate'];
            _toDate        = filters['toDate'];
            _filterCountry = filters['country'];
            _filterState   = filters['state'];
            _filterCity    = filters['city'];
            _filterLocalArea = filters['localArea'];
          });
          _applyFilter();
        },
      ),
      // ── NEW: Row 2 — Search + Status chips + Export ───────────────────────
      _buildRow2(),
      // ── Existing stats cards ──────────────────────────────────────────────
      _buildStatsCards(),
      Expanded(
        child: _filteredTrips.isEmpty
            ? _buildEmptyState()
            : _buildTripsTable(),
      ),
    ]);
  }

  // ── NEW: Row 2 widget ─────────────────────────────────────────────────────
  Widget _buildRow2() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(children: [
        // Search bar
        SizedBox(
          width: 240,
          height: 40,
          child: TextField(
            controller: _searchController,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Search trip, client, driver…',
              hintStyle:
                  TextStyle(fontSize: 15, color: Colors.grey.shade500),
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                        _applyFilter();
                      })
                  : null,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            onChanged: (v) {
              setState(() => _searchQuery = v.toLowerCase());
              _applyFilter();
            },
          ),
        ),
        const SizedBox(width: 12),
        // Status filter chips
        Expanded(
          child: SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _filterOptions.length,
              itemBuilder: (context, index) {
                final filter = _filterOptions[index];
                final isSelected = _selectedFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(filter,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF424242))),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedFilter = filter;
                        _applyFilter();
                      });
                    },
                    selectedColor: const Color(0xFF1A237E),
                    backgroundColor: Colors.grey.shade100,
                    checkmarkColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFF1A237E)
                            : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Export Excel button
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _exportToExcel,
          icon: const Icon(Icons.file_download, size: 18),
          label: const Text('Export Excel',
              style:
                  TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF27AE60),
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ]),
    );
  }

  Widget _buildStatsCards() {
    final total = _allTrips.length;
    final pending = _allTrips.where((t) {
      final s = t['status']?.toString().toLowerCase() ?? '';
      return s == 'pending_assignment' || s == 'pending';
    }).length;
    final assigned = _allTrips
        .where((t) =>
            t['status']?.toString().toLowerCase() == 'assigned')
        .length;
    final accepted = _allTrips
        .where((t) =>
            t['status']?.toString().toLowerCase() == 'accepted')
        .length;
    final active = _allTrips.where((t) {
      final s = t['status']?.toString().toLowerCase() ?? '';
      return s == 'started' || s == 'in_progress';
    }).length;
    final completed = _allTrips
        .where((t) =>
            t['status']?.toString().toLowerCase() == 'completed')
        .length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _statCard('Total', total.toString(), Icons.all_inbox, Colors.blue),
          const SizedBox(width: 10),
          _statCard('Pending', pending.toString(),
              Icons.pending_actions, Colors.orange),
          const SizedBox(width: 10),
          _statCard('Assigned', assigned.toString(),
              Icons.assignment_ind, Colors.blue),
          const SizedBox(width: 10),
          _statCard(
              'Accepted', accepted.toString(), Icons.thumb_up, Colors.teal),
          const SizedBox(width: 10),
          _statCard('Active', active.toString(),
              Icons.directions_car, Colors.indigo),
          const SizedBox(width: 10),
          _statCard('Completed', completed.toString(),
              Icons.check_circle, Colors.green),
        ]),
      ),
    );
  }

  Widget _statCard(
      String label, String value, IconData icon, MaterialColor color) {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200, width: 1.5),
      ),
      child: Column(children: [
        Icon(icon, color: color.shade700, size: 28),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: color.shade900)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color.shade700),
            textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: Colors.grey.shade100, shape: BoxShape.circle),
            child: Icon(Icons.inbox_outlined,
                size: 80, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 28),
          Text(
              _selectedFilter == 'All'
                  ? 'No Client Trip Requests'
                  : 'No $_selectedFilter Trips',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800)),
          const SizedBox(height: 12),
          Text(
              _selectedFilter == 'All'
                  ? 'Client trip requests will appear here.'
                  : 'No trips with $_selectedFilter status.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade600,
                  height: 1.5)),
        ]),
      ),
    );
  }

  // ============================================================================
  // TABLE WITH SYNCED HORIZONTAL SCROLL  (original — unchanged except _colActions)
  // ============================================================================

  Widget _buildTripsTable() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(children: [
        // ── HEADER ──
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A237E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SingleChildScrollView(
            controller: _headerScrollController,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Row(children: [
              _headerCell('Trip #', _colTripNum),
              _headerCell('Client', _colClient),
              _headerCell('Phone', _colPhone),
              _headerCell('Pickup', _colPickup),
              _headerCell('Drop', _colDrop),
              _headerCell('Dist.', _colDist),
              _headerCell('Scheduled Time', _colTime),
              _headerCell('Status', _colStatus),
              _headerCell('Driver Response', _colDriverResp),
              _headerCell('Driver', _colDriver),
              _headerCell('Vehicle', _colVehicle),
              _headerCell('Actions', _colActions),
            ]),
          ),
        ),
        // ── BODY ── (NEW: Wrapped in SingleChildScrollView for unified horizontal scroll)
        Expanded(
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                // Handle horizontal scroll with mouse/trackpad
                if (event.scrollDelta.dx != 0 && _bodyScrollController.hasClients) {
                  final newOffset = (_bodyScrollController.offset + event.scrollDelta.dx)
                      .clamp(0.0, _bodyScrollController.position.maxScrollExtent);
                  _bodyScrollController.jumpTo(newOffset);
                }
              }
            },
            child: Scrollbar(
              controller: _bodyScrollController,
              child: SingleChildScrollView(
                controller: _bodyScrollController,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: _colTripNum + _colClient + _colPhone + _colPickup + 
                         _colDrop + _colDist + _colTime + _colStatus + 
                         _colDriverResp + _colDriver + _colVehicle + _colActions,
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _filteredTrips.length,
                    itemBuilder: (context, index) {
                      return _buildTableRow(_filteredTrips[index], index);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _headerCell(String title, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Text(title,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.3)),
    );
  }

  Widget _buildTableRow(Map<String, dynamic> trip, int index) {
    final isEven = index % 2 == 0;
    final status = trip['status']?.toString().toLowerCase() ?? '';
    final adminConfirmed = trip['adminConfirmed'] == true;
    final driverResponse = trip['driverResponse']?.toString();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: () => _showTripHistory(trip),
        hoverColor: const Color(0xFF1A237E).withOpacity(0.04),
        child: Container(
          decoration: BoxDecoration(
            color: isEven ? Colors.grey.shade50 : Colors.white,
            border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1)),
          ),
          child: Row(children: [
            // Trip Number
            _cell(trip['tripNumber'] ?? 'N/A', _colTripNum,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A237E),
                fontSize: 15),
            // Client
            _cell(trip['clientName'] ?? 'N/A', _colClient,
                fontWeight: FontWeight.w600),
            // Phone
            _cell(trip['clientPhone'] ?? 'N/A', _colPhone),
            // Pickup
            _cell(trip['pickupLocation']?['address'] ?? 'N/A', _colPickup,
                maxLines: 2, fontSize: 15),
            // Drop
            _cell(trip['dropLocation']?['address'] ?? 'N/A', _colDrop,
                maxLines: 2, fontSize: 15),
            // Distance
            _cell(
                trip['distance'] != null
                    ? '${(trip['distance'] as num).toStringAsFixed(1)} km'
                    : 'N/A',
                _colDist,
                fontWeight: FontWeight.w600),
            // Scheduled Time
            _cell(_formatDateTime(trip['scheduledPickupTime']), _colTime,
                fontSize: 15),
            // Status Badge
            _statusCell(status, _colStatus, adminConfirmed: adminConfirmed),
            // Driver Response
            _driverResponseCell(driverResponse, _colDriverResp),
            // Driver
            _cell(trip['driverName'] ?? '—', _colDriver,
                color: trip['driverName'] != null
                    ? const Color(0xFF212121)
                    : Colors.grey.shade400),
            // Vehicle
            _cell(trip['vehicleNumber'] ?? '—', _colVehicle,
                color: trip['vehicleNumber'] != null
                    ? const Color(0xFF212121)
                    : Colors.grey.shade400),
            // Actions — NEW: WhatsApp icon added
            _actionsCell(trip, status, adminConfirmed, _colActions),
          ]),
        ),
      ),
    );
  }

  Widget _cell(
    String text,
    double width, {
    int maxLines = 1,
    FontWeight? fontWeight,
    Color? color,
    double? fontSize,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize ?? 15,
          fontWeight: fontWeight,
          color: color ?? const Color(0xFF212121),
          height: 1.4,
        ),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _statusCell(String status, double width,
      {bool adminConfirmed = false}) {
    final color = _getStatusColor(status, adminConfirmed: adminConfirmed);
    final label = _getStatusLabel(status, adminConfirmed: adminConfirmed);
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4), width: 1.5),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color.lerp(color, Colors.black, 0.25)!),
        ),
      ),
    );
  }

  Widget _driverResponseCell(String? driverResponse, double width) {
    if (driverResponse == null) {
      return Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Text('Awaiting',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600)),
        ),
      );
    }

    final isAccepted = driverResponse == 'accept';
    final color = isAccepted ? Colors.green : Colors.red;
    final label = isAccepted ? '✅ Accepted' : '❌ Declined';

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4), width: 1.5),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color.shade800)),
      ),
    );
  }

  // ── Actions cell: original logic + NEW WhatsApp icon ─────────────────────
  Widget _actionsCell(Map<String, dynamic> trip, String status,
      bool adminConfirmed, double width) {
    Widget actionWidget;

    if (status == 'pending_assignment' || status == 'pending') {
      actionWidget = _actionButton(
        'Assign',
        Icons.assignment,
        Colors.blue.shade700,
        () => _showAssignVehicleDialog(trip),
      );
    } else if (status == 'assigned') {
      actionWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Text('Awaiting Driver',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade700)),
      );
    } else if (status == 'declined') {
      actionWidget = _actionButton(
        'Reassign',
        Icons.assignment_return,
        Colors.orange.shade700,
        () => _showAssignVehicleDialog(trip),
      );
    } else if (status == 'accepted' && !adminConfirmed) {
      actionWidget = _actionButton(
        'Confirm',
        Icons.check_circle,
        Colors.green.shade700,
        () => _confirmAccepted(trip),
      );
    } else if (status == 'accepted' && adminConfirmed) {
      actionWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: 18, color: Colors.green.shade700),
          const SizedBox(width: 4),
          Text('Confirmed',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.green.shade900)),
        ],
      );
    } else if (status == 'started' || status == 'in_progress') {
      actionWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_car, size: 18, color: Colors.indigo.shade700),
          const SizedBox(width: 4),
          Text('In Progress',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.indigo.shade900)),
        ],
      );
    } else if (status == 'completed') {
      actionWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 18, color: Colors.green.shade700),
          const SizedBox(width: 4),
          Text('Completed',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.green.shade900)),
        ],
      );
    } else {
      actionWidget = Text('—',
          style: TextStyle(fontSize: 15, color: Colors.grey.shade400));
    }

    // Show Share Live Location button only for started/in_progress trips
    final showShareButton = status == 'started' || status == 'in_progress';

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          actionWidget,
          const SizedBox(width: 6),
          // History icon (original)
          Tooltip(
            message: 'View History',
            child: InkWell(
              onTap: () => _showTripHistory(trip),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Icon(Icons.history,
                    size: 18, color: Colors.grey.shade700),
              ),
            ),
          ),
          const SizedBox(width: 5),
          // NEW: WhatsApp icon
          Tooltip(
            message: 'WhatsApp',
            child: InkWell(
              onTap: () => _showWhatsAppDialog(trip),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: const Color(0xFF25D366).withOpacity(0.4)),
                ),
                child: const Icon(Icons.chat,
                    size: 18, color: Color(0xFF25D366)),
              ),
            ),
          ),
          // Share Live Location button — only for started/in_progress trips
          if (showShareButton) ...[
            const SizedBox(width: 5),
            Tooltip(
              message: 'Share Live Location',
              child: InkWell(
                onTap: () => _shareWhatsAppLiveLocation(trip),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF25D366).withOpacity(0.4),
                    ),
                  ),
                  child: const Icon(Icons.share_location,
                      size: 18, color: Color(0xFF25D366)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionButton(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  // ============================================================================
  // FULL HISTORY DIALOG  (original — unchanged)
  // ============================================================================

  void _showTripHistory(Map<String, dynamic> trip) {
    final status = trip['status']?.toString().toLowerCase() ?? '';
    final adminConfirmed = trip['adminConfirmed'] == true;
    final statusHistory =
        trip['statusHistory'] as Map<String, dynamic>? ?? {};
    final driverResponse = trip['driverResponse']?.toString();
    final driverResponseNotes =
        trip['driverResponseNotes']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
            maxWidth: 620,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFF1A237E),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(children: [
                  const Icon(Icons.history, color: Colors.white, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Trip History',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          Text(trip['tripNumber'] ?? 'N/A',
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.white70)),
                        ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                        _getStatusLabel(status,
                            adminConfirmed: adminConfirmed),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ]),
              ),
              // Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Client Info
                      _historySection('👤 Client Information', [
                        _historyRow('Name', trip['clientName'] ?? 'N/A'),
                        _historyRow('Email', trip['clientEmail'] ?? 'N/A'),
                        _historyRow('Phone', trip['clientPhone'] ?? 'N/A'),
                      ]),
                      const SizedBox(height: 16),

                      // Trip Info
                      _historySection('🚗 Trip Information', [
                        _historyRow(
                            'Distance',
                            trip['distance'] != null
                                ? '${(trip['distance'] as num).toStringAsFixed(1)} km'
                                : 'N/A'),
                        _historyRow(
                            'Duration',
                            trip['estimatedDuration'] != null
                                ? '${trip['estimatedDuration']} minutes'
                                : 'N/A'),
                        _historyRow('Pickup Time',
                            _formatDateTimeShort(trip['scheduledPickupTime'])),
                        _historyRow('Pickup Location',
                            trip['pickupLocation']?['address'] ?? 'N/A'),
                        _historyRow('Drop Location',
                            trip['dropLocation']?['address'] ?? 'N/A'),
                      ]),
                      const SizedBox(height: 16),

                      // Assignment Info (if assigned)
                      if (trip['driverName'] != null ||
                          trip['vehicleNumber'] != null) ...[
                        _historySection('👨‍✈️ Assignment', [
                          if (trip['driverName'] != null)
                            _historyRow('Driver', trip['driverName']),
                          if (trip['driverPhone'] != null)
                            _historyRow('Driver Phone', trip['driverPhone']),
                          if (trip['vehicleNumber'] != null)
                            _historyRow('Vehicle', trip['vehicleNumber']),
                          _historyRow('Assigned At',
                              _formatDateTimeShort(trip['assignedAt'])),
                        ]),
                        const SizedBox(height: 16),
                      ],

                      // STATUS TIMELINE
                      _historySection('📋 Status Timeline', [
                        _timelineItem(
                          icon: Icons.add_circle,
                          color: Colors.blue,
                          title: 'Trip Created by Client',
                          subtitle: 'Status → Pending Assignment',
                          time: _formatDateTimeShort(
                              statusHistory['pending_assignment'] ??
                                  trip['createdAt']),
                          isFirst: true,
                        ),
                        if (statusHistory['assigned'] != null)
                          _timelineItem(
                            icon: Icons.assignment_ind,
                            color: Colors.blue,
                            title: 'Vehicle & Driver Assigned by Admin',
                            subtitle:
                                'Driver: ${trip['driverName'] ?? 'N/A'}\nVehicle: ${trip['vehicleNumber'] ?? 'N/A'}',
                            time: _formatDateTimeShort(
                                statusHistory['assigned']),
                          ),
                        if (driverResponse != null) ...[
                          _timelineItem(
                            icon: driverResponse == 'accept'
                                ? Icons.check_circle
                                : Icons.cancel,
                            color: driverResponse == 'accept'
                                ? Colors.green
                                : Colors.red,
                            title: driverResponse == 'accept'
                                ? '✅ Driver Accepted Trip'
                                : '❌ Driver Declined Trip',
                            subtitle: driverResponseNotes.isNotEmpty
                                ? 'Note: $driverResponseNotes'
                                : (driverResponse == 'accept'
                                    ? 'Waiting for Admin Confirmation'
                                    : 'Admin needs to reassign'),
                            time: _formatDateTimeShort(
                                trip['driverResponseTime']),
                            highlight: true,
                          ),
                        ],
                        if (statusHistory['declined'] != null &&
                            driverResponse != 'accept')
                          _timelineItem(
                            icon: Icons.assignment_return,
                            color: Colors.orange,
                            title: 'Admin Reassigning Driver',
                            subtitle: 'Waiting for new assignment',
                            time: _formatDateTimeShort(
                                statusHistory['declined']),
                          ),
                        if (adminConfirmed) ...[
                          _timelineItem(
                            icon: Icons.verified,
                            color: Colors.green,
                            title: '✅ Admin Confirmed Trip',
                            subtitle: 'Client has been notified!',
                            time: _formatDateTimeShort(
                                trip['adminConfirmedAt']),
                            highlight: true,
                          ),
                        ],
                        if (statusHistory['started'] != null)
                          _timelineItem(
                            icon: Icons.directions_car,
                            color: Colors.indigo,
                            title: 'Trip Started by Driver',
                            subtitle: 'Live tracking active',
                            time: _formatDateTimeShort(
                                statusHistory['started']),
                          ),
                        if (statusHistory['completed'] != null)
                          _timelineItem(
                            icon: Icons.flag,
                            color: Colors.green,
                            title: 'Trip Completed',
                            subtitle: 'Successfully delivered',
                            time: _formatDateTimeShort(
                                statusHistory['completed']),
                            isLast: true,
                          ),
                      ]),
                      const SizedBox(height: 16),

                      // Notes
                      if (trip['notes'] != null &&
                          trip['notes'].toString().isNotEmpty) ...[
                        _historySection('📝 Notes', [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.grey.shade200),
                            ),
                            child: Text(trip['notes'],
                                style: const TextStyle(
                                    fontSize: 13, height: 1.5)),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
              ),
              // Footer Actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20)),
                  border: Border(
                      top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Created: ${_formatDateTimeShort(trip['createdAt'])}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                    Row(children: [
                      if (status == 'pending_assignment' ||
                          status == 'pending' ||
                          status == 'declined')
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _showAssignVehicleDialog(trip);
                          },
                          icon: const Icon(Icons.assignment, size: 16),
                          label: Text(status == 'declined'
                              ? 'Reassign'
                              : 'Assign'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: status == 'declined'
                                ? Colors.orange.shade700
                                : Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      if (status == 'accepted' && !adminConfirmed)
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _confirmAccepted(trip);
                          },
                          icon: const Icon(Icons.check_circle, size: 16),
                          label: const Text('Confirm & Notify Client'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historySection(String title, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A237E))),
      const SizedBox(height: 10),
      ...children,
    ]);
  }

  Widget _historyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600))),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500))),
      ]),
    );
  }

  Widget _timelineItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String time,
    bool isFirst = false,
    bool isLast = false,
    bool highlight = false,
  }) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Timeline line + icon
      Column(children: [
        if (!isFirst)
          Container(width: 2, height: 12, color: Colors.grey.shade300),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        if (!isLast)
          Container(width: 2, height: 30, color: Colors.grey.shade300),
      ]),
      const SizedBox(width: 12),
      // Content
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: highlight
                  ? color.withOpacity(0.06)
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: highlight
                      ? color.withOpacity(0.3)
                      : Colors.grey.shade200),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: highlight
                              ? Color.lerp(color, Colors.black, 0.3)!
                              : Colors.black87)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ],
                  const SizedBox(height: 4),
                  Text(time,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontStyle: FontStyle.italic)),
                ]),
          ),
        ),
      ),
    ]);
  }
}

// ============================================================================
// NEW: Row-1 CSC Filter Widget
// ============================================================================

class _AdminCscFilterRow extends StatefulWidget {
  final DateTime? fromDate;
  final DateTime? toDate;
  final String? country;
  final String? state;
  final String? city;
  final String? localArea;
  final Function(Map<String, dynamic>) onChanged;

  const _AdminCscFilterRow({
    required this.fromDate,
    required this.toDate,
    required this.country,
    required this.state,
    required this.city,
    required this.localArea,
    required this.onChanged,
  });

  @override
  State<_AdminCscFilterRow> createState() => _AdminCscFilterRowState();
}

class _AdminCscFilterRowState extends State<_AdminCscFilterRow> {
  DateTime? _from;
  DateTime? _to;
  String? _country, _countryIso;
  String? _state, _stateIso;
  String? _city;
  final TextEditingController _localCtrl = TextEditingController();

  List<csc.Country> _countries = [];
  List<csc.State> _states = [];
  List<csc.City> _cities = [];
  bool _loadingCountries = true;
  bool _loadingStates = false;
  bool _loadingCities = false;

  @override
  void initState() {
    super.initState();
    _from    = widget.fromDate;
    _to      = widget.toDate;
    _country = widget.country;
    _state   = widget.state;
    _city    = widget.city;
    _localCtrl.text = widget.localArea ?? '';
    _fetchCountries();
  }

  @override
  void dispose() {
    _localCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchCountries() async {
    try {
      final list = await csc.getAllCountries();
      if (mounted) {
        setState(() {
          _countries = list..sort((a, b) => a.name.compareTo(b.name));
          _loadingCountries = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCountries = false);
    }
  }

  Future<void> _fetchStates(String countryIso) async {
    setState(() {
      _loadingStates = true;
      _states = [];
      _cities = [];
      _state = null;
      _stateIso = null;
      _city = null;
    });
    try {
      final list = await csc.getStatesOfCountry(countryIso);
      if (mounted) {
        setState(() {
          _states = list..sort((a, b) => a.name.compareTo(b.name));
          _loadingStates = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingStates = false);
    }
  }

  Future<void> _fetchCities(String countryIso, String stateIso) async {
    setState(() {
      _loadingCities = true;
      _cities = [];
      _city = null;
    });
    try {
      final list = await csc.getStateCities(countryIso, stateIso);
      if (mounted) {
        setState(() {
          _cities = list..sort((a, b) => a.name.compareTo(b.name));
          _loadingCities = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCities = false);
    }
  }

  void _notify() {
    widget.onChanged({
      'fromDate':  _from,
      'toDate':    _to,
      'country':   _country,
      'state':     _state,
      'city':      _city,
      'localArea': _localCtrl.text.trim().isEmpty
          ? null
          : _localCtrl.text.trim(),
    });
  }

  bool get _hasFilters =>
      _from != null ||
      _to != null ||
      (_country?.isNotEmpty ?? false) ||
      (_state?.isNotEmpty ?? false) ||
      (_city?.isNotEmpty ?? false) ||
      _localCtrl.text.trim().isNotEmpty;

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          isFrom ? (_from ?? DateTime.now()) : (_to ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) _from = picked;
      else _to = picked;
    });
    _notify();
  }

  void _clearAll() {
    setState(() {
      _from = null; _to = null;
      _country = null; _countryIso = null;
      _state = null; _stateIso = null;
      _city = null;
      _states = []; _cities = [];
      _localCtrl.clear();
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          const Icon(Icons.filter_alt_outlined,
              size: 16, color: Color(0xFF1A237E)),
          const SizedBox(width: 6),
          const Text('Location & Date',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A237E))),
          const SizedBox(width: 12),
          _datePill('From', _from, () => _pickDate(true),
              () { setState(() => _from = null); _notify(); }),
          const SizedBox(width: 8),
          _datePill('To', _to, () => _pickDate(false),
              () { setState(() => _to = null); _notify(); }),
          const SizedBox(width: 8),
          _dropPill(
            label: 'Country',
            value: _country ?? 'All Countries',
            active: _country != null,
            loading: _loadingCountries,
            onTap: () => _showPicker('country'),
            onClear: _country != null
                ? () {
                    setState(() {
                      _country = null; _countryIso = null;
                      _state = null; _stateIso = null;
                      _city = null; _states = []; _cities = [];
                    });
                    _notify();
                  }
                : null,
          ),
          const SizedBox(width: 8),
          _dropPill(
            label: 'State',
            value: _state ?? (_country == null ? 'Select Country' : 'All States'),
            active: _state != null,
            loading: _loadingStates,
            disabled: _country == null,
            onTap: _country != null ? () => _showPicker('state') : null,
            onClear: _state != null
                ? () {
                    setState(() {
                      _state = null; _stateIso = null;
                      _city = null; _cities = [];
                    });
                    _notify();
                  }
                : null,
          ),
          const SizedBox(width: 8),
          _dropPill(
            label: 'City',
            value: _city ?? (_state == null ? 'Select State' : 'All Cities'),
            active: _city != null,
            loading: _loadingCities,
            disabled: _state == null,
            onTap: _state != null ? () => _showPicker('city') : null,
            onClear: _city != null
                ? () { setState(() => _city = null); _notify(); }
                : null,
          ),
          const SizedBox(width: 8),
          // Local area text field
          SizedBox(
            width: 148,
            height: 36,
            child: TextField(
              controller: _localCtrl,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Local Area…',
                hintStyle: TextStyle(
                    fontSize: 15, color: Colors.grey.shade500),
                prefixIcon:
                    const Icon(Icons.pin_drop_outlined, size: 14),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 0),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              onChanged: (_) {
                setState(() {});
                _notify();
              },
            ),
          ),
          const SizedBox(width: 8),
          // Apply button
          SizedBox(
            height: 36,
            child: ElevatedButton.icon(
              onPressed: _notify,
              icon: const Icon(Icons.search, size: 14),
              label: const Text('Apply',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          if (_hasFilters) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: _clearAll,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.close, size: 15, color: Colors.red.shade400),
                  const SizedBox(width: 3),
                  Text('Clear',
                      style: TextStyle(
                          fontSize: 15,
                          color: Colors.red.shade600,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _datePill(String label, DateTime? val, VoidCallback onTap,
      VoidCallback onClear) {
    final active = val != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF1A237E).withOpacity(0.07)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active ? const Color(0xFF1A237E) : Colors.grey.shade300,
              width: active ? 1.5 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.calendar_today_outlined,
              size: 13,
              color: active ? const Color(0xFF1A237E) : Colors.grey.shade500),
          const SizedBox(width: 5),
          Text(
            val != null
                ? '$label: ${DateFormat('dd/MM/yy').format(val)}'
                : label,
            style: TextStyle(
                fontSize: 15,
                color: active
                    ? const Color(0xFF1A237E)
                    : Colors.grey.shade600,
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.normal),
          ),
          if (active) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onClear,
              child: Icon(Icons.close, size: 12, color: Colors.grey.shade500),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _dropPill({
    required String label,
    required String value,
    required bool active,
    required bool loading,
    VoidCallback? onTap,
    VoidCallback? onClear,
    bool disabled = false,
  }) {
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 36,
        constraints: const BoxConstraints(minWidth: 100, maxWidth: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: disabled
              ? Colors.grey.shade100
              : active
                  ? const Color(0xFF1A237E).withOpacity(0.07)
                  : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: disabled
                ? Colors.grey.shade200
                : active
                    ? const Color(0xFF1A237E)
                    : Colors.grey.shade300,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (loading)
            const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(Icons.location_on_outlined,
                size: 13,
                color: disabled
                    ? Colors.grey.shade400
                    : active
                        ? const Color(0xFF1A237E)
                        : Colors.grey.shade500),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 15,
                  color: disabled
                      ? Colors.grey.shade400
                      : active
                          ? const Color(0xFF1A237E)
                          : Colors.grey.shade700,
                  fontWeight:
                      active ? FontWeight.w700 : FontWeight.normal),
            ),
          ),
          if (active && onClear != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onClear,
              child:
                  Icon(Icons.close, size: 12, color: Colors.grey.shade500),
            ),
          ] else if (!disabled)
            Icon(Icons.keyboard_arrow_down,
                size: 14, color: Colors.grey.shade500),
        ]),
      ),
    );
  }

  void _showPicker(String type) {
    final List<dynamic> items;
    final String? selected;
    if (type == 'country') {
      items = _countries;
      selected = _country;
    } else if (type == 'state') {
      items = _states;
      selected = _state;
    } else {
      items = _cities;
      selected = _city;
    }

    String getLabel(dynamic i) => i is csc.Country
        ? i.name
        : i is csc.State
            ? i.name
            : (i as csc.City).name;

    final searchCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          contentPadding: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: SizedBox(
            width: 300,
            height: 400,
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Color(0xFF1A237E),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(14)),
                ),
                child: TextField(
                  controller: searchCtrl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText:
                        'Search ${type[0].toUpperCase()}${type.substring(1)}…',
                    hintStyle: const TextStyle(
                        color: Colors.white60, fontSize: 15),
                    prefixIcon: const Icon(Icons.search,
                        color: Colors.white60, size: 18),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onChanged: (_) => ss(() {}),
                ),
              ),
              Expanded(
                child: Builder(builder: (_) {
                  final q = searchCtrl.text.toLowerCase();
                  final filtered = q.isEmpty
                      ? items
                      : items
                          .where((i) =>
                              getLabel(i).toLowerCase().contains(q))
                          .toList();
                  if (filtered.isEmpty) {
                    return const Center(
                        child: Text('No results',
                            style: TextStyle(color: Colors.grey)));
                  }
                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final item = filtered[i];
                      final label = getLabel(item);
                      final isSel = label == selected;
                      return ListTile(
                        dense: true,
                        selected: isSel,
                        selectedColor: const Color(0xFF1A237E),
                        title: Text(label,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: isSel
                                    ? FontWeight.w700
                                    : FontWeight.normal)),
                        trailing: isSel
                            ? const Icon(Icons.check,
                                size: 16, color: Color(0xFF1A237E))
                            : null,
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() {
                            if (type == 'country') {
                              final c = item as csc.Country;
                              _country = c.name;
                              _countryIso = c.isoCode;
                              _state = null; _stateIso = null;
                              _city = null; _states = []; _cities = [];
                              _fetchStates(c.isoCode);
                            } else if (type == 'state') {
                              final s = item as csc.State;
                              _state = s.name;
                              _stateIso = s.isoCode;
                              _city = null; _cities = [];
                              _fetchCities(_countryIso!, s.isoCode);
                            } else {
                              _city = (item as csc.City).name;
                            }
                          });
                          _notify();
                        },
                      );
                    },
                  );
                }),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// OLD ASSIGN VEHICLE DIALOG - No longer needed (using navigation instead)
// ============================================================================

/*
class _AssignVehicleDialog extends StatefulWidget {
  final Map<String, dynamic> trip;
  final List<Map<String, dynamic>> vehicles;
  final Function(String) onAssign;

  const _AssignVehicleDialog({
    required this.trip,
    required this.vehicles,
    required this.onAssign,
  });

  @override
  State<_AssignVehicleDialog> createState() => _AssignVehicleDialogState();
}

class _AssignVehicleDialogState extends State<_AssignVehicleDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredVehicles = [];
  String? _selectedVehicleId;

  @override
  void initState() {
    super.initState();
    _filteredVehicles = widget.vehicles;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterVehicles(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredVehicles = widget.vehicles;
      } else {
        _filteredVehicles = widget.vehicles.where((vehicle) {
          final q = query.toLowerCase();
          return (vehicle['registration'] ?? '').toLowerCase().contains(q) ||
              (vehicle['model'] ?? '').toLowerCase().contains(q) ||
              (vehicle['type'] ?? '').toLowerCase().contains(q) ||
              (vehicle['driverName'] ?? '').toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
          maxWidth: 550,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF1A237E),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.directions_car,
                    color: Colors.white, size: 26),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(
                  widget.trip['status']?.toString().toLowerCase() ==
                          'declined'
                      ? 'Reassign Vehicle & Driver'
                      : 'Assign Vehicle & Driver',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                )),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
              const SizedBox(height: 8),
              Text('Trip: ${widget.trip['tripNumber'] ?? 'N/A'}',
                  style:
                      const TextStyle(fontSize: 13, color: Colors.white70)),
              Text('Client: ${widget.trip['clientName'] ?? 'N/A'}',
                  style:
                      const TextStyle(fontSize: 13, color: Colors.white70)),
            ]),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by vehicle, driver, or type...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _filterVehicles('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
              ),
              onChanged: _filterVehicles,
            ),
          ),
          // Vehicle List
          Expanded(
            child: _filteredVehicles.isEmpty
                ? const Center(
                    child: Text('No vehicles found',
                        style:
                            TextStyle(fontSize: 16, color: Colors.grey)))
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredVehicles.length,
                    itemBuilder: (context, index) {
                      final vehicle = _filteredVehicles[index];
                      final isSelected =
                          vehicle['id'] == _selectedVehicleId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          onTap: () => setState(
                              () => _selectedVehicleId = vehicle['id']),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.blue.shade50
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF1A237E)
                                    : Colors.grey.shade300,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(children: [
                              Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: isSelected
                                    ? const Color(0xFF1A237E)
                                    : Colors.grey.shade400,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          vehicle['registration'] ?? 'N/A',
                                          style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: isSelected
                                                  ? const Color(0xFF1A237E)
                                                  : Colors.black87)),
                                      const SizedBox(height: 3),
                                      Text(
                                          '${vehicle['model']} • ${vehicle['type']}',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600)),
                                      const SizedBox(height: 4),
                                      Row(children: [
                                        Icon(Icons.person,
                                            size: 13,
                                            color: Colors.blue.shade700),
                                        const SizedBox(width: 4),
                                        Text(
                                            vehicle['driverName'] ??
                                                'No Driver',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    Colors.blue.shade700)),
                                      ]),
                                    ]),
                              ),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // Actions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _selectedVehicleId != null
                      ? () => widget.onAssign(_selectedVehicleId!)
                      : null,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Assign & Notify Driver'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
*/