import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/core/utils/export_helper.dart';
import 'package:intl/intl.dart';
import 'package:country_state_city/country_state_city.dart' as csc;
import 'start_client_trip.dart';

class ClientAllTripsPage extends StatefulWidget {
  const ClientAllTripsPage({Key? key}) : super(key: key);

  @override
  _ClientAllTripsPageState createState() => _ClientAllTripsPageState();
}

class _ClientAllTripsPageState extends State<ClientAllTripsPage> {
  List<Map<String, dynamic>> _allTrips = [];
  List<Map<String, dynamic>> _filteredTrips = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedFilter = 'All';
  Timer? _refreshTimer;

  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _bodyScrollController = ScrollController();
  bool _isSyncingScroll = false;

  // ── NEW: Search (Row 2) ───────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ── NEW: Row-1 CSC filter state ───────────────────────────────────────────
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _filterCountry;
  String? _filterState;
  String? _filterCity;
  String? _filterLocalArea;

  // Client-visible filter options only
  final List<String> _filterOptions = [
    'All',
    'Pending',
    'Confirmed',
    'In Progress',
    'Completed',
    'Cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _loadTrips();
    _startAutoRefresh();
    _syncScrollControllers();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _headerScrollController.dispose();
    _bodyScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) _loadTrips(silent: true);
    });
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
        Uri.parse('${ApiConfig.baseUrl}/api/client-trips/my-trips'),
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
              _allTrips =
                  List<Map<String, dynamic>>.from(data['data'] ?? []);
              _applyFilter();
              _isLoading = false;
            });
          }
        } else {
          throw Exception(data['message'] ?? 'Failed to load trips');
        }
      } else {
        throw Exception('Failed to load: ${response.statusCode}');
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

  // ============================================================================
  // CLIENT STATUS LOGIC — show Pending until adminConfirmed  (original unchanged)
  // ============================================================================

  /// Returns the client-facing status label.
  /// Client should NOT see: assigned, accepted (unconfirmed), declined.
  /// Everything maps to "Pending" until admin confirms.
  String _getClientStatusLabel(Map<String, dynamic> trip) {
    final status = trip['status']?.toString().toLowerCase() ?? '';
    final adminConfirmed = trip['adminConfirmed'] == true;

    switch (status) {
      case 'pending_assignment':
      case 'pending':
      case 'assigned':   // admin assigned, driver not yet responded
      case 'declined':   // driver declined, admin reassigning — still pending to client
        return 'Pending';

      case 'accepted':
        return adminConfirmed ? 'Confirmed' : 'Pending';

      case 'started':
      case 'in_progress':
        return 'In Progress';

      case 'completed':
        return 'Completed';

      case 'cancelled':
        return 'Cancelled';

      default:
        return 'Pending';
    }
  }

  Color _getClientStatusColor(Map<String, dynamic> trip) {
    final label = _getClientStatusLabel(trip);
    switch (label) {
      case 'Pending':
        return Colors.orange;
      case 'Confirmed':
        return Colors.green;
      case 'In Progress':
        return Colors.indigo;
      case 'Completed':
        return Colors.green.shade700 as Color;
      case 'Cancelled':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  void _applyFilter() {
    setState(() {
      _filteredTrips = _allTrips.where((trip) {
        // ── Status chip filter ──────────────────────────────────────────────
        if (_selectedFilter != 'All') {
          final clientLabel = _getClientStatusLabel(trip);
          if (clientLabel.toLowerCase() != _selectedFilter.toLowerCase()) {
            return false;
          }
        }

        // ── NEW: Search filter ──────────────────────────────────────────────
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery;
          final matchesTripNum = (trip['tripNumber']?.toString().toLowerCase().contains(q) ?? false);
          final matchesPickup  = (trip['pickupLocation']?['address']?.toString().toLowerCase().contains(q) ?? false);
          final matchesDrop    = (trip['dropLocation']?['address']?.toString().toLowerCase().contains(q) ?? false);
          if (!matchesTripNum && !matchesPickup && !matchesDrop) return false;
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
          'Trip #', 'Status', 'Pickup Location', 'Drop Location',
          'Distance (km)', 'Scheduled Time', 'Driver', 'Vehicle', 'Created At',
        ],
      ];

      for (final trip in _filteredTrips) {
        final cs = _getClientStatusLabel(trip);
        final adminConfirmed = trip['adminConfirmed'] == true;
        final showDriver = adminConfirmed ||
            trip['status']?.toString().toLowerCase() == 'started' ||
            trip['status']?.toString().toLowerCase() == 'in_progress' ||
            trip['status']?.toString().toLowerCase() == 'completed';

        csvData.add([
          trip['tripNumber'] ?? '',
          cs,
          trip['pickupLocation']?['address'] ?? '',
          trip['dropLocation']?['address'] ?? '',
          trip['distance'] != null
              ? (trip['distance'] as num).toStringAsFixed(1)
              : '',
          _formatExportDate(trip['scheduledPickupTime']),
          showDriver ? (trip['driverName'] ?? '') : '',
          showDriver ? (trip['vehicleNumber'] ?? '') : '',
          _formatExportDate(trip['createdAt']),
        ]);
      }

      await ExportHelper.exportToExcel(
        data: csvData,
        filename:
            'my_trips_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
      );

      _showSuccessSnackBar(
          '✅ Excel exported with ${_filteredTrips.length} trips!');
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

  // ── NEW: WhatsApp — direct to driver (only when confirmed) ─────────────────
  Future<void> _openWhatsAppDriver(Map<String, dynamic> trip) async {
    final cs    = _getClientStatusLabel(trip);
    final phone = trip['driverPhone']?.toString() ?? '';
    final name  = trip['driverName']?.toString() ?? 'Driver';

    if (cs != 'Confirmed' && cs != 'In Progress' && cs != 'Completed') {
      _showErrorSnackBar('Driver info available only after trip is confirmed');
      return;
    }
    if (phone.isEmpty) {
      _showErrorSnackBar('Driver phone not available');
      return;
    }

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
    final customerName = trip['customerName'] ?? trip['customer']?['name'] ?? 'Customer';
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

    final customerPhone = trip['customerPhone'] ?? trip['customer']?['phone'] ?? '';
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
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
              Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text(phone, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            ]),
          ),
          Icon(Icons.arrow_forward_ios, size: 16, color: color),
        ]),
      ),
    );
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

  // ── Snack helpers (added — original had no snackbar helpers) ─────────────
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

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'N/A';
    try {
      DateTime dt;
      if (dateTime is String) {
        dt = DateTime.parse(dateTime).toLocal();
      } else if (dateTime is DateTime) {
        dt = dateTime.toLocal();
      } else {
        return 'N/A';
      }
      return DateFormat('MMM dd, yyyy\nhh:mm a').format(dt);
    } catch (_) {
      return 'N/A';
    }
  }

  String _formatDateShort(dynamic dateTime) {
    if (dateTime == null) return 'N/A';
    try {
      DateTime dt;
      if (dateTime is String) {
        dt = DateTime.parse(dateTime).toLocal();
      } else if (dateTime is DateTime) {
        dt = dateTime.toLocal();
      } else {
        return 'N/A';
      }
      return DateFormat('MMM dd, yyyy').format(dt);
    } catch (_) {
      return 'N/A';
    }
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
          'My Trip Requests',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0.3),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadTrips(),
            tooltip: 'Refresh',
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
        Text('Loading your trips...',
            style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade900)),
          const SizedBox(height: 12),
          Text(_errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 13, color: Colors.grey.shade700)),
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
      _ClientCscFilterRow(
        fromDate: _fromDate,
        toDate: _toDate,
        country: _filterCountry,
        state: _filterState,
        city: _filterCity,
        localArea: _filterLocalArea,
        onChanged: (filters) {
          setState(() {
            _fromDate        = filters['fromDate'];
            _toDate          = filters['toDate'];
            _filterCountry   = filters['country'];
            _filterState     = filters['state'];
            _filterCity      = filters['city'];
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

  // ── NEW: Row 2 ────────────────────────────────────────────────────────────
  Widget _buildRow2() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(children: [
        // Search bar
        SizedBox(
          width: 220,
          height: 40,
          child: TextField(
            controller: _searchController,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search trips…',
              hintStyle:
                  TextStyle(fontSize: 13, color: Colors.grey.shade500),
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 15),
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
        // Status chips
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
                            fontSize: 13,
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
        // New Trip button
        ElevatedButton.icon(
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const StartClientTripPage()),
            );
            if (result == true) _loadTrips();
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New Trip',
              style:
                  TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A237E),
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(width: 8),
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
    final pending = _allTrips
        .where((t) => _getClientStatusLabel(t) == 'Pending')
        .length;
    final confirmed = _allTrips
        .where((t) => _getClientStatusLabel(t) == 'Confirmed')
        .length;
    final completed = _allTrips
        .where((t) => _getClientStatusLabel(t) == 'Completed')
        .length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Expanded(
            child: _statCard('Total', total.toString(),
                Icons.local_taxi, Colors.blue)),
        const SizedBox(width: 10),
        Expanded(
            child: _statCard('Pending', pending.toString(),
                Icons.pending_actions, Colors.orange)),
        const SizedBox(width: 10),
        Expanded(
            child: _statCard('Confirmed', confirmed.toString(),
                Icons.verified, Colors.green)),
        const SizedBox(width: 10),
        Expanded(
            child: _statCard('Completed', completed.toString(),
                Icons.check_circle, Colors.teal)),
      ]),
    );
  }

  Widget _statCard(
      String label, String value, IconData icon, MaterialColor color) {
    return Container(
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
        const SizedBox(height: 4),
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
        padding: const EdgeInsets.all(32),
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
                  ? 'No Trips Yet'
                  : 'No $_selectedFilter Trips',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800)),
          const SizedBox(height: 12),
          Text(
              _selectedFilter == 'All'
                  ? 'Tap "New Trip" below to create your first trip request!'
                  : 'No trips found with $_selectedFilter status.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.5)),
        ]),
      ),
    );
  }

  // ============================================================================
  // TABLE  (original — unchanged, + NEW: Actions column & WhatsApp icon)
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
        // Header
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A237E),
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SingleChildScrollView(
            controller: _headerScrollController,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Row(children: [
              _headerCell('Trip #', 140),
              _headerCell('Status', 120),
              _headerCell('Pickup Location', 200),
              _headerCell('Drop Location', 200),
              _headerCell('Distance', 100),
              _headerCell('Scheduled Time', 150),
              _headerCell('Driver', 150),
              _headerCell('Vehicle', 140),
              _headerCell('Created', 130),
              // NEW: Actions column header (increased width for 3 buttons)
              _headerCell('Actions', 150),
            ]),
          ),
        ),
        // Body (NEW: Wrapped in SingleChildScrollView for unified horizontal scroll)
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
                  width: 140 + 120 + 200 + 200 + 100 + 150 + 150 + 140 + 130 + 150 + 20, // Sum of all column widths + extra spacing
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _filteredTrips.length,
                    itemBuilder: (context, index) {
                      return _buildRow(_filteredTrips[index], index);
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

  Widget _buildRow(Map<String, dynamic> trip, int index) {
    final isEven = index % 2 == 0;
    final clientLabel = _getClientStatusLabel(trip);
    final clientColor = _getClientStatusColor(trip);
    final adminConfirmed = trip['adminConfirmed'] == true;

    // Only show driver info when confirmed
    final showDriver = adminConfirmed ||
        trip['status']?.toString().toLowerCase() == 'started' ||
        trip['status']?.toString().toLowerCase() == 'in_progress' ||
        trip['status']?.toString().toLowerCase() == 'completed';

    final hasDriverPhone =
        (trip['driverPhone']?.toString() ?? '').isNotEmpty;

    // Show Share Live Location button only for started/in_progress trips
    final tripStatus = trip['status']?.toString().toLowerCase() ?? '';
    final showShareButton =
        tripStatus == 'started' ||
        tripStatus == 'in_progress' ||
        tripStatus == 'in progress';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: () => _showTripDetails(trip),
        hoverColor: const Color(0xFF1A237E).withOpacity(0.04),
        child: Container(
          decoration: BoxDecoration(
            color: isEven ? Colors.grey.shade50 : Colors.white,
            border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1)),
          ),
          child: Row(children: [
            _cell(trip['tripNumber'] ?? 'N/A', 140,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A237E),
                fontSize: 15),
            // Status — client-facing only
            _statusCell(clientLabel, clientColor, 120),
            _cell(trip['pickupLocation']?['address'] ?? 'N/A', 200,
                maxLines: 2, fontSize: 15),
            _cell(trip['dropLocation']?['address'] ?? 'N/A', 200,
                maxLines: 2, fontSize: 15),
            _cell(
                trip['distance'] != null
                    ? '${(trip['distance'] as num).toStringAsFixed(1)} km'
                    : 'N/A',
                100,
                fontWeight: FontWeight.w600,
                fontSize: 15),
            _cell(_formatDateTime(trip['scheduledPickupTime']), 150,
                fontSize: 15),
            // Driver — only visible when confirmed
            _cell(
                showDriver ? (trip['driverName'] ?? '—') : '—',
                150,
                fontSize: 15,
                color: showDriver && trip['driverName'] != null
                    ? Colors.green.shade700
                    : Colors.grey.shade400),
            // Vehicle — only visible when confirmed
            _cell(
                showDriver ? (trip['vehicleNumber'] ?? '—') : '—',
                140,
                fontSize: 15,
                color: showDriver && trip['vehicleNumber'] != null
                    ? const Color(0xFF212121)
                    : Colors.grey.shade400),
            _cell(_formatDateShort(trip['createdAt']), 130,
                fontSize: 15, color: Colors.grey.shade600),
            // NEW: Actions cell with WhatsApp icon + Share Live Location
            Container(
              width: showShareButton ? 150 : 100,
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Detail icon
                  Tooltip(
                    message: 'View Details',
                    child: InkWell(
                      onTap: () => _showTripDetails(trip),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.blue.shade200),
                        ),
                        child: Icon(Icons.info_outline,
                            size: 28, color: Colors.blue.shade700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  // WhatsApp icon — greyed when not confirmed
                  Tooltip(
                    message: showDriver && hasDriverPhone
                        ? 'WhatsApp Driver'
                        : 'Available after confirmation',
                    child: InkWell(
                      onTap: () => _openWhatsAppDriver(trip),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: showDriver && hasDriverPhone
                              ? const Color(0xFF25D366).withOpacity(0.1)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: showDriver && hasDriverPhone
                                ? const Color(0xFF25D366)
                                    .withOpacity(0.4)
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Icon(Icons.chat,
                            size: 28,
                            color: showDriver && hasDriverPhone
                                ? const Color(0xFF25D366)
                                : Colors.grey.shade400),
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
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF25D366).withOpacity(0.4),
                            ),
                          ),
                          child: const Icon(Icons.share_location,
                              size: 28, color: Color(0xFF25D366)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _cell(String text, double width, {
    int maxLines = 1,
    FontWeight? fontWeight,
    Color? color,
    double? fontSize,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Text(text,
          style: TextStyle(
              fontSize: fontSize ?? 15,
              fontWeight: fontWeight,
              color: color ?? const Color(0xFF212121),
              height: 1.4),
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis),
    );
  }

  Widget _statusCell(String label, Color color, double width) {
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
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color.lerp(color, Colors.black, 0.2)!)),
      ),
    );
  }

  // ============================================================================
  // TRIP DETAIL DIALOG  (original — unchanged, + WhatsApp button in footer)
  // ============================================================================

  void _showTripDetails(Map<String, dynamic> trip) {
    final clientLabel = _getClientStatusLabel(trip);
    final clientColor = _getClientStatusColor(trip);
    final adminConfirmed = trip['adminConfirmed'] == true;
    final realStatus = trip['status']?.toString().toLowerCase() ?? '';

    final showDriver = adminConfirmed ||
        realStatus == 'started' ||
        realStatus == 'in_progress' ||
        realStatus == 'completed';

    final hasDriverPhone =
        (trip['driverPhone']?.toString() ?? '').isNotEmpty;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.local_taxi, color: clientColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Trip Details',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(trip['tripNumber'] ?? 'N/A',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                ]),
          ),
        ]),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status
              _section('Status', [
                _detailRow('Current Status', clientLabel,
                    valueColor: clientColor),
                if (adminConfirmed)
                  _detailRow('Notification',
                      'You have been notified ✅',
                      valueColor: Colors.green),
                if (!adminConfirmed &&
                    (realStatus == 'pending_assignment' ||
                        realStatus == 'pending' ||
                        realStatus == 'assigned' ||
                        realStatus == 'accepted' ||
                        realStatus == 'declined'))
                  _detailRow('Next Step',
                      'Admin is processing your request...',
                      valueColor: Colors.orange.shade700),
              ]),
              const SizedBox(height: 14),
              _section('Trip Information', [
                _detailRow('Distance',
                    trip['distance'] != null
                        ? '${(trip['distance'] as num).toStringAsFixed(1)} km'
                        : 'N/A'),
                _detailRow('Est. Duration',
                    trip['estimatedDuration'] != null
                        ? '${trip['estimatedDuration']} minutes'
                        : 'N/A'),
                _detailRow('Pickup Time',
                    _formatDateTime(trip['scheduledPickupTime'])),
                if (trip['scheduledDropTime'] != null)
                  _detailRow('Drop Time',
                      _formatDateTime(trip['scheduledDropTime'])),
              ]),
              const SizedBox(height: 14),
              _section('Locations', [
                _detailRow('Pickup',
                    trip['pickupLocation']?['address'] ?? 'N/A'),
                _detailRow(
                    'Drop', trip['dropLocation']?['address'] ?? 'N/A'),
              ]),
              // Driver info — only show when confirmed
              if (showDriver && trip['driverName'] != null) ...[
                const SizedBox(height: 14),
                _section('Driver Details', [
                  _detailRow('Driver', trip['driverName']),
                  if (trip['driverPhone'] != null)
                    _detailRow('Driver Phone', trip['driverPhone']),
                  if (trip['vehicleNumber'] != null)
                    _detailRow('Vehicle', trip['vehicleNumber']),
                ]),
              ],
              if (trip['notes'] != null &&
                  trip['notes'].toString().isNotEmpty) ...[
                const SizedBox(height: 14),
                _section('Notes', [
                  Text(trip['notes'],
                      style:
                          const TextStyle(fontSize: 13, height: 1.5)),
                ]),
              ],
            ],
          ),
        ),
        actions: [
          // NEW: WhatsApp button in footer (only when driver available)
          if (showDriver && hasDriverPhone)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _openWhatsAppDriver(trip);
              },
              icon: const Icon(Icons.chat, size: 16),
              label: const Text('WhatsApp Driver'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A237E))),
      const SizedBox(height: 8),
      ...children,
    ]);
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 130,
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: valueColor ?? const Color(0xFF212121))),
        ),
      ]),
    );
  }
}

// ============================================================================
// NEW: Row-1 Client CSC Filter Widget
// ============================================================================

class _ClientCscFilterRow extends StatefulWidget {
  final DateTime? fromDate;
  final DateTime? toDate;
  final String? country;
  final String? state;
  final String? city;
  final String? localArea;
  final Function(Map<String, dynamic>) onChanged;

  const _ClientCscFilterRow({
    required this.fromDate,
    required this.toDate,
    required this.country,
    required this.state,
    required this.city,
    required this.localArea,
    required this.onChanged,
  });

  @override
  State<_ClientCscFilterRow> createState() => _ClientCscFilterRowState();
}

class _ClientCscFilterRowState extends State<_ClientCscFilterRow> {
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
                  fontSize: 13,
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
          SizedBox(
            width: 148,
            height: 36,
            child: TextField(
              controller: _localCtrl,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Local Area…',
                hintStyle: TextStyle(
                    fontSize: 13, color: Colors.grey.shade500),
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
          SizedBox(
            height: 36,
            child: ElevatedButton.icon(
              onPressed: _notify,
              icon: const Icon(Icons.search, size: 14),
              label: const Text('Apply',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
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
                  Icon(Icons.close,
                      size: 11, color: Colors.red.shade400),
                  const SizedBox(width: 3),
                  Text('Clear',
                      style: TextStyle(
                          fontSize: 12,
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
              color: active
                  ? const Color(0xFF1A237E)
                  : Colors.grey.shade300,
              width: active ? 1.5 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.calendar_today_outlined,
              size: 13,
              color: active
                  ? const Color(0xFF1A237E)
                  : Colors.grey.shade500),
          const SizedBox(width: 5),
          Text(
            val != null
                ? '$label: ${DateFormat('dd/MM/yy').format(val)}'
                : label,
            style: TextStyle(
                fontSize: 13,
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
              child: Icon(Icons.close,
                  size: 12, color: Colors.grey.shade500),
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
                  fontSize: 13,
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
              child: Icon(Icons.close,
                  size: 12, color: Colors.grey.shade500),
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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
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
                  style:
                      const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText:
                        'Search ${type[0].toUpperCase()}${type.substring(1)}…',
                    hintStyle: const TextStyle(
                        color: Colors.white60, fontSize: 13),
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
                                fontSize: 13,
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