// lib/features/admin/dashboard/presentation/screens/resolved_alerts_view.dart
// ============================================================================
// ✅ RESOLVED SOS ALERTS VIEW
// FILTERS:
//   Row 1 → CountryStateCityFilter (From Date, To Date, Country, State, City, Area, Apply)
//   Row 2 → Company Domain filter  +  Reset All button
//   Row 3 → Export to Excel (full width, own row)
// ============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:intl/intl.dart';
// ignore: avoid_web_libraries_in_flutter
import 'package:universal_html/html.dart' as html;
import 'package:abra_fleet/core/utils/export_helper.dart';
import 'package:abra_fleet/features/admin/widgets/country_state_city_filter.dart';

// ============================================================================
// MODEL
// ============================================================================
class ResolvedSOSAlert {
  final String id;
  final String customerName;
  final String customerEmail;
  final String customerPhone;
  final String address;
  final DateTime timestamp;
  final DateTime? resolvedAt;
  final String? driverName;
  final String? driverPhone;
  final String? vehicleReg;
  final String? tripId;
  final Map<String, dynamic>? resolution;
  final String notes;

  ResolvedSOSAlert({
    required this.id,
    required this.customerName,
    required this.customerEmail,
    required this.customerPhone,
    required this.address,
    required this.timestamp,
    this.resolvedAt,
    this.driverName,
    this.driverPhone,
    this.vehicleReg,
    this.tripId,
    this.resolution,
    this.notes = '',
  });

  factory ResolvedSOSAlert.fromJson(Map<String, dynamic> json) {
    return ResolvedSOSAlert(
      id: json['_id']?.toString() ?? '',
      customerName: json['customerName']?.toString() ?? 'Unknown',
      customerEmail: json['customerEmail']?.toString() ?? '',
      customerPhone: json['customerPhone']?.toString() ?? '',
      address: json['address']?.toString() ?? 'Address not available',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'].toString())
          : DateTime.now(),
      resolvedAt: json['resolvedAt'] != null
          ? DateTime.parse(json['resolvedAt'].toString())
          : null,
      driverName: json['driverName']?.toString(),
      driverPhone: json['driverPhone']?.toString(),
      vehicleReg: json['vehicleReg']?.toString(),
      tripId: json['tripId']?.toString(),
      resolution: json['resolution'] as Map<String, dynamic>?,
      notes: json['resolution']?['notes']?.toString() ??
          json['notes']?.toString() ??
          '',
    );
  }

  bool get hasResolutionProof =>
      resolution != null &&
      resolution!['photoUrl'] != null &&
      resolution!['notes'] != null;
}

// ============================================================================
// WIDGET
// ============================================================================
class ResolvedAlertsView extends StatefulWidget {
  const ResolvedAlertsView({super.key});

  @override
  State<ResolvedAlertsView> createState() => _ResolvedAlertsViewState();
}

class _ResolvedAlertsViewState extends State<ResolvedAlertsView> {
  // ========================================================================
  // STATE VARIABLES
  // ========================================================================
  List<ResolvedSOSAlert> _resolvedAlerts = [];
  List<ResolvedSOSAlert> _filteredAlerts = [];
  bool _isLoading = true;
  String? _errorMessage;

  // ========================================================================
  // FILTER PANEL STATE
  // ========================================================================
  bool _showFilters = false;

  // ── Row 1: driven by CountryStateCityFilter callback ─────────────────────
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedCountry;
  String? _selectedState;
  String? _selectedCity;
  String? _selectedArea;

  // ── Row 2: Company Domain ─────────────────────────────────────────────────
  final TextEditingController _domainController = TextEditingController();
  String _domainFilter = '';

  // ========================================================================
  // LIFECYCLE
  // ========================================================================
  @override
  void initState() {
    super.initState();
    _fetchResolvedAlerts();
  }

  @override
  void dispose() {
    _domainController.dispose();
    super.dispose();
  }

  // ========================================================================
  // FETCH RESOLVED SOS ALERTS
  // ========================================================================
  Future<void> _fetchResolvedAlerts() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      debugPrint('📥 Fetching resolved SOS alerts from backend...');

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      if (token == null || token.isEmpty) {
        throw Exception('User not authenticated');
      }

      final url = Uri.parse(
          '${ApiConfig.baseUrl}/api/sos?status=Resolved&limit=100');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          final List<dynamic> alertsJson = data['data'];
          final List<ResolvedSOSAlert> newResolved = alertsJson
              .map((json) => ResolvedSOSAlert.fromJson(json))
              .toList();

          newResolved.sort((a, b) {
            final aDate = a.resolvedAt ?? a.timestamp;
            final bDate = b.resolvedAt ?? b.timestamp;
            return bDate.compareTo(aDate);
          });

          debugPrint('✅ Loaded ${newResolved.length} resolved alerts');

          if (mounted) {
            setState(() {
              _resolvedAlerts = newResolved;
              _filteredAlerts = newResolved;
            });
          }
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        throw Exception('Failed to load alerts: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error fetching resolved alerts: $e');
      if (mounted) {
        setState(() => _errorMessage = e.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load alerts: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ========================================================================
  // APPLY FILTERS
  // ========================================================================
  void _applyFilters() {
    List<ResolvedSOSAlert> filtered = List.from(_resolvedAlerts);

    // Date Range (from CSC widget) — filters on resolvedAt if available, else timestamp
    if (_startDate != null && _endDate != null) {
      filtered = filtered.where((a) {
        final date = a.resolvedAt ?? a.timestamp;
        return date.isAfter(_startDate!) &&
            date.isBefore(_endDate!.add(const Duration(days: 1)));
      }).toList();
    }

    // Location (from CSC widget)
    for (final loc in [
      _selectedCountry,
      _selectedState,
      _selectedCity,
      _selectedArea
    ]) {
      if (loc != null && loc.isNotEmpty) {
        filtered = filtered
            .where((a) =>
                a.address.toLowerCase().contains(loc.toLowerCase()))
            .toList();
      }
    }

    // Domain (Row 2)
    if (_domainFilter.isNotEmpty) {
      filtered = filtered
          .where((a) => a.customerEmail
              .toLowerCase()
              .endsWith(_domainFilter.toLowerCase()))
          .toList();
    }

    setState(() => _filteredAlerts = filtered);
    debugPrint(
        '🔍 Filtered: ${_filteredAlerts.length} of ${_resolvedAlerts.length}');
  }

  // ========================================================================
  // RESET ALL FILTERS
  // ========================================================================
  void _resetFilters() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _selectedCountry = null;
      _selectedState = null;
      _selectedCity = null;
      _selectedArea = null;
      _domainController.clear();
      _domainFilter = '';
      _filteredAlerts = _resolvedAlerts;
    });
    debugPrint('🔄 Filters reset');
  }

  // ========================================================================
  // EXPORT TO EXCEL
  // ========================================================================
  Future<void> _exportToExcel() async {
    if (_filteredAlerts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No alerts to export'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preparing Excel export…'),
          backgroundColor: Color(0xFF2E7D32),
          duration: Duration(seconds: 2),
        ),
      );

      final List<List<dynamic>> data = [
        // Headers
        [
          'Alert Time',
          'Resolved At',
          'Customer Name',
          'Customer Phone',
          'Customer Email',
          'Address',
          'Driver Name',
          'Driver Phone',
          'Vehicle',
          'Trip ID',
          'Resolution Notes',
          'Resolved By',
          'Has Photo Proof',
          'Notes',
        ],
        // Rows
        ..._filteredAlerts.map((a) => [
              DateFormat('dd/MM/yyyy hh:mm a').format(a.timestamp),
              a.resolvedAt != null
                  ? DateFormat('dd/MM/yyyy hh:mm a').format(a.resolvedAt!)
                  : 'N/A',
              a.customerName,
              a.customerPhone,
              a.customerEmail,
              a.address,
              a.driverName ?? 'N/A',
              a.driverPhone ?? 'N/A',
              a.vehicleReg ?? 'N/A',
              a.tripId ?? 'N/A',
              a.resolution?['notes']?.toString() ?? 'N/A',
              a.resolution?['resolvedBy']?.toString() ?? 'N/A',
              a.hasResolutionProof ? 'Yes' : 'No',
              a.notes,
            ]),
      ];

      await ExportHelper.exportToExcel(
        data: data,
        filename:
            'resolved_sos_alerts_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                  '✅ Exported ${_filteredAlerts.length} resolved alerts to Excel'),
            ]),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ========================================================================
  // IMAGE DOWNLOAD (original functionality preserved)
  // ========================================================================
  Future<void> _downloadImage(String imageUrl, String filename) async {
    try {
      debugPrint('📥 Downloading image: $imageUrl');

      if (kIsWeb) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⏳ Preparing download...'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 2),
            ),
          );
        }

        final response = await http.get(Uri.parse(imageUrl));

        if (response.statusCode == 200) {
          final blob = html.Blob([response.bodyBytes]);
          final url = html.Url.createObjectUrlFromBlob(blob);

          final anchor = html.AnchorElement(href: url)
            ..setAttribute('download', filename)
            ..style.display = 'none';

          html.document.body?.append(anchor);
          anchor.click();
          html.document.body?.children.remove(anchor);
          html.Url.revokeObjectUrl(url);

          debugPrint('✅ Download triggered for web');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('✅ Download started! Check your downloads folder.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          throw Exception('Failed to fetch image: ${response.statusCode}');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Download feature is available on web only'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error downloading image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ========================================================================
  // DELETE SOS (original functionality preserved)
  // ========================================================================
  Future<void> _deleteSOS(String sosId) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: const Text(
            'This action is permanent and cannot be undone. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      debugPrint('🗑️ Deleting SOS alert: $sosId');

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      if (token == null || token.isEmpty) {
        throw Exception('User not authenticated');
      }

      final url = Uri.parse('${ApiConfig.baseUrl}/api/sos/$sosId');
      final response = await http.delete(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('📡 Delete response: ${response.statusCode}');

      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ SOS alert has been deleted.'),
            backgroundColor: Colors.green,
          ),
        );
        await _fetchResolvedAlerts();
      } else {
        throw Exception('Failed to delete SOS: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error deleting alert: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting alert: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ========================================================================
  // BUILD — MAIN UI
  // ========================================================================
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Top bar with filter toggle + refresh ──────────────────
                _buildTopBar(),

                // ── Filters panel (shown/hidden) ──────────────────────────
                if (_showFilters) _buildFiltersPanel(),

                // ── Count header ──────────────────────────────────────────
                _buildHeaderSection(),

                // ── Content ───────────────────────────────────────────────
                Expanded(
                  child: _filteredAlerts.isEmpty
                      ? _buildEmptyState()
                      : _buildAlertsList(),
                ),
              ],
            ),
    );
  }

  // ========================================================================
  // TOP BAR (filter toggle + refresh — mirrors incomplete screen)
  // ========================================================================
  Widget _buildTopBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Filter toggle
          IconButton(
            icon: Icon(
              _showFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
              color: _showFilters
                  ? const Color(0xFF2E7D32)
                  : Colors.grey[600],
            ),
            onPressed: () => setState(() => _showFilters = !_showFilters),
            tooltip: 'Toggle Filters',
            style: IconButton.styleFrom(
              backgroundColor: _showFilters
                  ? Colors.green.shade50
                  : Colors.grey.shade100,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _showFilters ? 'Hide Filters' : 'Show Filters',
            style: TextStyle(
              fontSize: 13,
              color: _showFilters
                  ? const Color(0xFF2E7D32)
                  : Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchResolvedAlerts,
            tooltip: 'Refresh Alerts',
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey.shade100,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // FILTERS PANEL  (3 rows — identical structure to incomplete screen)
  // ========================================================================
  Widget _buildFiltersPanel() {
    return Container(
      color: Colors.white,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: const Text(
          '🔍 Filters',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── ROW 1: CountryStateCityFilter ──────────────────────────
                CountryStateCityFilter(
                  initialFromDate: _startDate,
                  initialToDate: _endDate,
                  initialCountry: _selectedCountry,
                  initialState: _selectedState,
                  initialCity: _selectedCity,
                  initialLocalArea: _selectedArea,
                  onFilterApplied: (filters) {
                    setState(() {
                      _startDate       = filters['fromDate']  as DateTime?;
                      _endDate         = filters['toDate']    as DateTime?;
                      _selectedCountry = filters['country']   as String?;
                      _selectedState   = filters['state']     as String?;
                      _selectedCity    = filters['city']      as String?;
                      _selectedArea    = filters['localArea'] as String?;
                    });
                    _applyFilters();
                  },
                ),

                const SizedBox(height: 12),

                // ── ROW 2: Domain filter  +  Reset All ────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: _buildDomainFilter()),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 38,
                      child: OutlinedButton.icon(
                        onPressed: _resetFilters,
                        icon: const Icon(Icons.clear, size: 16),
                        label: const Text(
                          'Reset All',
                          style: TextStyle(fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ── ROW 3: Export button — full width ─────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _exportToExcel,
                    icon: const Icon(Icons.file_download, size: 20),
                    label: Text(
                      _filteredAlerts.isEmpty
                          ? 'Export Excel'
                          : 'Export Excel  (${_filteredAlerts.length} alert${_filteredAlerts.length == 1 ? '' : 's'})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF27AE60),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),

              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // DOMAIN FILTER WIDGET  (Row 2 left side)
  // ========================================================================
  Widget _buildDomainFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Company Domain',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 38,
          child: TextField(
            controller: _domainController,
            decoration: InputDecoration(
              hintText: 'e.g., @infosys.com, @wipro.com',
              hintStyle: const TextStyle(
                  fontSize: 12, color: Color(0xFF94A3B8)),
              prefixIcon: const Icon(Icons.business,
                  size: 16, color: Color(0xFF94A3B8)),
              suffixIcon: _domainFilter.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _domainController.clear();
                        setState(() => _domainFilter = '');
                        _applyFilters();
                      },
                      child: const Icon(Icons.close,
                          size: 14, color: Color(0xFF94A3B8)),
                    )
                  : null,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                    color: Color(0xFF2E7D32), width: 1.5),
              ),
            ),
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF1E293B)),
            onChanged: (v) {
              setState(() => _domainFilter = v);
              _applyFilters();
            },
          ),
        ),
      ],
    );
  }

  // ========================================================================
  // COUNT HEADER
  // ========================================================================
  Widget _buildHeaderSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '✅ Resolved Alerts (${_filteredAlerts.length})',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2E7D32),
            ),
          ),
          if (_filteredAlerts.length != _resolvedAlerts.length)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[300]!),
              ),
              child: Text(
                'Filtered: ${_filteredAlerts.length} of ${_resolvedAlerts.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[900],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ========================================================================
  // ALERTS LIST
  // ========================================================================
  Widget _buildAlertsList() {
    return RefreshIndicator(
      onRefresh: _fetchResolvedAlerts,
      child: ListView.separated(
        padding: const EdgeInsets.all(16.0),
        itemCount: _filteredAlerts.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final alert = _filteredAlerts[index];
          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.green.shade200, width: 1),
            ),
            child: InkWell(
              onTap: () => _showAlertDetails(alert),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.check_circle,
                              color: Colors.green.shade700, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                alert.customerName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              if (alert.customerPhone.isNotEmpty)
                                Text(
                                  alert.customerPhone,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (alert.hasResolutionProof)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.photo_camera,
                                    size: 14,
                                    color: Colors.blue.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  'Proof',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(Icons.location_on, alert.address),
                    const SizedBox(height: 4),
                    if (alert.driverName != null) ...[
                      _buildInfoRow(
                          Icons.person, 'Driver: ${alert.driverName}'),
                      const SizedBox(height: 4),
                    ],
                    if (alert.vehicleReg != null) ...[
                      _buildInfoRow(Icons.directions_car,
                          'Vehicle: ${alert.vehicleReg}'),
                      const SizedBox(height: 4),
                    ],
                    _buildInfoRow(
                      Icons.access_time,
                      'Resolved: ${_formatDateTime(alert.resolvedAt ?? alert.timestamp)}',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => _showAlertDetails(alert),
                          icon: const Icon(Icons.visibility, size: 16),
                          label: const Text('View Details'),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.blue[700]),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () => _deleteSOS(alert.id),
                          icon: const Icon(Icons.delete_forever, size: 16),
                          label: const Text('Delete'),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.red[700]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ========================================================================
  // ALERT DETAILS DIALOG (original functionality — fully preserved)
  // ========================================================================
  void _showAlertDetails(ResolvedSOSAlert alert) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints:
              const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: Colors.green.shade700, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Resolved SOS Alert',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _formatDateTime(
                                alert.resolvedAt ?? alert.timestamp),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailSection('Customer Information', [
                        _buildDetailRow('Name', alert.customerName),
                        if (alert.customerEmail.isNotEmpty)
                          _buildDetailRow('Email', alert.customerEmail),
                        if (alert.customerPhone.isNotEmpty)
                          _buildDetailRow('Phone', alert.customerPhone),
                      ]),
                      const SizedBox(height: 16),
                      if (alert.driverName != null ||
                          alert.vehicleReg != null) ...[
                        _buildDetailSection('Trip Information', [
                          if (alert.driverName != null)
                            _buildDetailRow('Driver', alert.driverName!),
                          if (alert.driverPhone != null)
                            _buildDetailRow(
                                'Driver Phone', alert.driverPhone!),
                          if (alert.vehicleReg != null)
                            _buildDetailRow('Vehicle', alert.vehicleReg!),
                          if (alert.tripId != null)
                            _buildDetailRow('Trip ID', alert.tripId!),
                        ]),
                        const SizedBox(height: 16),
                      ],
                      _buildDetailSection('Location', [
                        _buildDetailRow('Address', alert.address),
                      ]),
                      const SizedBox(height: 16),
                      if (alert.hasResolutionProof) ...[
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Resolution Proof',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => _downloadImage(
                                '${ApiConfig.baseUrl}${alert.resolution!['photoUrl']}',
                                alert.resolution!['photoFilename'] ??
                                    'sos_proof.jpg',
                              ),
                              icon: const Icon(Icons.download, size: 16),
                              label: const Text('Download'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (alert.resolution!['photoUrl'] != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              '${ApiConfig.baseUrl}${alert.resolution!['photoUrl']}',
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  height: 200,
                                  color: Colors.grey[200],
                                  child: const Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.broken_image,
                                            size: 48, color: Colors.grey),
                                        SizedBox(height: 8),
                                        Text('Failed to load image'),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  height: 200,
                                  color: Colors.grey[200],
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 12),
                        if (alert.resolution!['notes'] != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Resolution Notes:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  alert.resolution!['notes'],
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        if (alert.resolution!['resolvedBy'] != null)
                          Text(
                            'Resolved by: ${alert.resolution!['resolvedBy']}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ========================================================================
  // HELPER WIDGETS
  // ========================================================================
  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
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
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: Colors.grey[700]),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return 'Today at ${DateFormat('HH:mm').format(dateTime)}';
    } else if (difference.inDays == 1) {
      return 'Yesterday at ${DateFormat('HH:mm').format(dateTime)}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return DateFormat('MMM dd, yyyy HH:mm').format(dateTime);
    }
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _fetchResolvedAlerts,
      child: ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          const Icon(Icons.check_circle_outline,
              color: Colors.grey, size: 80),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'No resolved alerts found.',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}