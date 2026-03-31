// lib/features/admin/dashboard/presentation/screens/incomplete_sos_alerts_screen.dart
// ============================================================================
// 🚨 INCOMPLETE SOS ALERTS SCREEN — FIXED VERSION
// FIXES:
//   ✅ PATCH → PUT for resolve (fixes 404)
//   ✅ Resolve dialog now requires photo proof + notes (camera or gallery)
//   ✅ Status query is now case-insensitive friendly ('ACTIVE')
//   ✅ Photo stored as base64 → sent to PUT /:id/resolve-with-proof
//   ✅ Customer live location shown in alert card
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:abra_fleet/core/services/safe_api_service.dart';
import 'package:abra_fleet/core/services/tms_service.dart';
import 'package:abra_fleet/core/services/error_handler_service.dart';
import 'package:abra_fleet/core/utils/export_helper.dart';
import 'package:abra_fleet/features/admin/widgets/country_state_city_filter.dart';
import 'package:url_launcher/url_launcher.dart';

class IncompleteSosAlertsScreen extends StatefulWidget {
  const IncompleteSosAlertsScreen({Key? key}) : super(key: key);

  @override
  State<IncompleteSosAlertsScreen> createState() =>
      _IncompleteSosAlertsScreenState();
}

class _IncompleteSosAlertsScreenState
    extends State<IncompleteSosAlertsScreen> with ErrorHandlerMixin {
  // ========================================================================
  // SERVICES
  // ========================================================================
  final SafeApiService _safeApi = SafeApiService();
  final TMSService _tmsService = TMSService();
  final ImagePicker _imagePicker = ImagePicker();

  // ========================================================================
  // STATE
  // ========================================================================
  List<IncompleteSOSAlert> _activeAlerts = [];
  List<IncompleteSOSAlert> _filteredAlerts = [];
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = true;
  bool _isLoadingEmployees = false;
  String? _errorMessage;

  // ── Filter panel ─────────────────────────────────────────────────────────
  bool _showFilters = false;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedCountry;
  String? _selectedState;
  String? _selectedCity;
  String? _selectedArea;
  final TextEditingController _domainController = TextEditingController();
  String _domainFilter = '';

  // ========================================================================
  // LIFECYCLE
  // ========================================================================
  @override
  void initState() {
    super.initState();
    _fetchActiveAlerts();
    _fetchEmployees();
  }

  @override
  void dispose() {
    _domainController.dispose();
    super.dispose();
  }

  // ========================================================================
  // FETCH ACTIVE SOS ALERTS
  // ========================================================================
  Future<void> _fetchActiveAlerts() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _safeApi.safeGet(
        '/api/sos',
        // ✅ FIX: backend now handles case-insensitive status match
        queryParams: {'status': 'ACTIVE', 'limit': '100'},
        context: 'Active SOS Alerts',
        fallback: {'status': 'success', 'data': []},
      );

      if (response['status'] == 'success' && response['data'] != null) {
        final List<dynamic> alertsJson = response['data'];
        final newActive = alertsJson
            .map((json) => IncompleteSOSAlert.fromJson(json))
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        if (mounted) {
          setState(() {
            _activeAlerts = newActive;
            _filteredAlerts = newActive;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _activeAlerts = [];
            _filteredAlerts = [];
          });
        }
      }
    } catch (e) {
      handleSilentError(e, context: 'Active SOS Alerts');
      if (mounted) {
        setState(() {
          _activeAlerts = [];
          _filteredAlerts = [];
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ========================================================================
  // FETCH EMPLOYEES
  // ========================================================================
  Future<void> _fetchEmployees() async {
    setState(() => _isLoadingEmployees = true);
    final response = await _tmsService.fetchEmployees();
    if (response['success'] == true && response['data'] != null) {
      setState(() {
        _employees =
            List<Map<String, dynamic>>.from(response['data']);
        _isLoadingEmployees = false;
      });
    } else {
      setState(() => _isLoadingEmployees = false);
    }
  }

  // ========================================================================
  // FILTERS
  // ========================================================================
  void _applyFilters() {
    List<IncompleteSOSAlert> filtered = List.from(_activeAlerts);
    if (_startDate != null && _endDate != null) {
      filtered = filtered
          .where((a) =>
              a.timestamp.isAfter(_startDate!) &&
              a.timestamp.isBefore(
                  _endDate!.add(const Duration(days: 1))))
          .toList();
    }
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
    if (_domainFilter.isNotEmpty) {
      filtered = filtered
          .where((a) => a.customerEmail
              .toLowerCase()
              .endsWith(_domainFilter.toLowerCase()))
          .toList();
    }
    setState(() => _filteredAlerts = filtered);
  }

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
      _filteredAlerts = _activeAlerts;
    });
  }

  // ========================================================================
  // EXPORT
  // ========================================================================
  Future<void> _exportToExcel() async {
    if (_filteredAlerts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No alerts to export'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preparing Excel export…'),
          backgroundColor: Color(0xFF0D47A1),
          duration: Duration(seconds: 2),
        ),
      );
      final List<List<dynamic>> data = [
        [
          'Alert Time', 'Customer Name', 'Customer Phone',
          'Customer Email', 'Address', 'Driver Name', 'Driver Phone',
          'Vehicle', 'Trip ID', 'Pickup Location', 'Drop Location',
          'Latitude', 'Longitude', 'Google Maps', 'Police Notified',
          'Police City', 'Status', 'Notes',
        ],
        ..._filteredAlerts.map((a) => [
              DateFormat('dd/MM/yyyy hh:mm a').format(a.timestamp),
              a.customerName, a.customerPhone, a.customerEmail,
              a.address, a.driverName ?? 'N/A', a.driverPhone ?? 'N/A',
              a.vehicleFullName, a.tripId ?? 'N/A',
              a.pickupLocation ?? 'N/A', a.dropLocation ?? 'N/A',
              a.latitude, a.longitude, a.googleMapsUrl,
              a.wasPoliceNotified ? 'Yes' : 'No',
              a.policeCity ?? 'N/A', a.status, a.notes,
            ]),
      ];
      await ExportHelper.exportToExcel(
        data: data,
        filename:
            'sos_alerts_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Text('✅ Exported ${_filteredAlerts.length} alerts'),
            ]),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to export: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ========================================================================
  // BUILD
  // ========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back to Admin Dashboard',
        ),
        title: const Text('🚨 Incomplete SOS Alerts'),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              _showFilters
                  ? Icons.filter_alt
                  : Icons.filter_alt_outlined,
              color: _showFilters ? Colors.yellow : Colors.white,
            ),
            onPressed: () =>
                setState(() => _showFilters = !_showFilters),
            tooltip: 'Toggle Filters',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchActiveAlerts,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_showFilters) _buildFiltersPanel(),
                _buildHeaderSection(),
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
  // FILTERS PANEL
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
        title: const Text('🔍 Filters',
            style:
                TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CountryStateCityFilter(
                  initialFromDate: _startDate,
                  initialToDate: _endDate,
                  initialCountry: _selectedCountry,
                  initialState: _selectedState,
                  initialCity: _selectedCity,
                  initialLocalArea: _selectedArea,
                  onFilterApplied: (filters) {
                    setState(() {
                      _startDate = filters['fromDate'] as DateTime?;
                      _endDate = filters['toDate'] as DateTime?;
                      _selectedCountry =
                          filters['country'] as String?;
                      _selectedState = filters['state'] as String?;
                      _selectedCity = filters['city'] as String?;
                      _selectedArea =
                          filters['localArea'] as String?;
                    });
                    _applyFilters();
                  },
                ),
                const SizedBox(height: 12),
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
                        label: const Text('Reset All',
                            style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _exportToExcel,
                    icon:
                        const Icon(Icons.file_download, size: 20),
                    label: Text(
                      _filteredAlerts.isEmpty
                          ? 'Export Excel'
                          : 'Export Excel  (${_filteredAlerts.length} alert${_filteredAlerts.length == 1 ? '' : 's'})',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3),
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

  Widget _buildDomainFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Company Domain',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF94A3B8))),
        const SizedBox(height: 4),
        SizedBox(
          height: 38,
          child: TextField(
            controller: _domainController,
            decoration: InputDecoration(
              hintText: 'e.g., @infosys.com',
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
                  const EdgeInsets.symmetric(horizontal: 10),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                      color: Color(0xFF0D47A1), width: 1.5)),
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
  // HEADER
  // ========================================================================
  Widget _buildHeaderSection() {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border:
            Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '🚨 Active Alerts (${_filteredAlerts.length})',
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red),
          ),
          if (_filteredAlerts.length != _activeAlerts.length)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[300]!),
              ),
              child: Text(
                'Filtered: ${_filteredAlerts.length} of ${_activeAlerts.length}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[900]),
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
      onRefresh: _fetchActiveAlerts,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredAlerts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) =>
            _buildAlertCard(_filteredAlerts[i]),
      ),
    );
  }

  // ========================================================================
  // ALERT CARD
  // ========================================================================
  Widget _buildAlertCard(IncompleteSOSAlert alert) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade300, width: 2),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.red.shade50, Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.warning_amber_rounded,
                        color: Colors.red.shade700, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(alert.customerName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                        if (alert.customerPhone.isNotEmpty)
                          Text(alert.customerPhone,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (alert.wasPoliceNotified)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.local_police,
                                  size: 12,
                                  color: Colors.blue.shade700),
                              const SizedBox(width: 4),
                              Text('Police Notified',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTimeAgo(alert.timestamp),
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.red[600],
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _buildInfoRow(Icons.location_on, alert.address),
              if (alert.driverName != null) ...[
                const SizedBox(height: 4),
                _buildInfoRow(
                    Icons.person,
                    'Driver: ${alert.driverName}'
                    '${alert.driverPhone != null ? ' (${alert.driverPhone})' : ''}'),
              ],
              if (alert.vehicleReg != null) ...[
                const SizedBox(height: 4),
                _buildInfoRow(Icons.directions_car,
                    'Vehicle: ${alert.vehicleFullName}'),
              ],
              if (alert.tripId != null) ...[
                const SizedBox(height: 4),
                _buildInfoRow(
                    Icons.route, 'Trip ID: ${alert.tripId}'),
              ],

              // ── Customer live location button ────────────────────
              const SizedBox(height: 8),
              if (alert.liveTrackingUrl != null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _openLiveTracking(alert.liveTrackingUrl!),
                    icon: const Icon(Icons.location_searching,
                        size: 16, color: Colors.blue),
                    label: const Text('View Customer Live Location',
                        style: TextStyle(
                            fontSize: 12, color: Colors.blue)),
                    style: OutlinedButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: 6),
                      side: const BorderSide(color: Colors.blue),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),

              const SizedBox(height: 12),

              // ── Action buttons ───────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _showAlertDetails(alert),
                      icon: const Icon(Icons.visibility,
                          size: 16),
                      label: const Text('Details',
                          style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ElevatedButton.icon(
                      // ✅ FIX: now opens proof dialog, not direct PATCH
                      onPressed: () =>
                          _showResolveWithProofDialog(alert),
                      icon: const Icon(Icons.check_circle,
                          size: 16),
                      label: const Text('Resolve',
                          style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _showRaiseTicketDialog(alert),
                      icon: const Icon(
                          Icons.confirmation_number,
                          size: 16),
                      label: const Text('Ticket',
                          style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange[600],
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
                      ),
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

  // ========================================================================
  // ✅ NEW: RESOLVE WITH PROOF DIALOG (camera + gallery, notes)
  // ========================================================================
  void _showResolveWithProofDialog(IncompleteSOSAlert alert) {
    final notesController = TextEditingController();
    XFile? pickedFile;
    Uint8List? imageBytes;
    bool isUploading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // ── Pick image ──────────────────────────────────────────
          Future<void> pickImage(ImageSource source) async {
            try {
              final picked = await _imagePicker.pickImage(
                source: source,
                maxWidth: 1280,
                maxHeight: 960,
                imageQuality: 75,
              );
              if (picked != null) {
                final bytes = await picked.readAsBytes();
                setDialogState(() {
                  pickedFile = picked;
                  imageBytes = bytes;
                });
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('Could not pick image: $e'),
                      backgroundColor: Colors.red),
                );
              }
            }
          }

          // ── Submit ──────────────────────────────────────────────
          Future<void> submit() async {
            if (notesController.text.trim().isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                    content:
                        Text('Please add resolution notes'),
                    backgroundColor: Colors.orange),
              );
              return;
            }
            if (imageBytes == null) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                    content: Text(
                        'Please add a photo as proof'),
                    backgroundColor: Colors.orange),
              );
              return;
            }
            setDialogState(() => isUploading = true);
            try {
              // ✅ Convert to base64 — no multipart, works on web + mobile
              final base64Photo = base64Encode(imageBytes!);
              final mimeType = pickedFile!.mimeType ??
                  'image/jpeg';

              // ✅ FIX: Use safePut → PUT /:id/resolve-with-proof
              final response = await _safeApi.safePut(
                '/api/sos/${alert.id}/resolve-with-proof',
                body: {
                  'adminNotes': notesController.text.trim(),
                  'resolution': {
                    'notes': notesController.text.trim(),
                    'photoBase64': base64Photo,
                    'photoMimeType': mimeType,
                    'resolvedBy': 'Admin',
                    'timestamp': DateTime.now()
                        .toUtc()
                        .toIso8601String(),
                  },
                },
                context: 'Resolve SOS Alert with Proof',
              );

              Navigator.of(ctx).pop();

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        '✅ SOS Alert resolved with proof'),
                    backgroundColor: Colors.green,
                  ),
                );
                _fetchActiveAlerts(); // refresh list
              }
            } catch (e) {
              setDialogState(() => isUploading = false);
              if (mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                      content: Text('Failed to resolve: $e'),
                      backgroundColor: Colors.red),
                );
              }
            }
          }

          return Dialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Container(
              constraints: const BoxConstraints(
                  maxWidth: 480, maxHeight: 640),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Title ─────────────────────────────────
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius:
                                  BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.check_circle,
                                color: Colors.green.shade700,
                                size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              '✅ Resolve SOS Alert',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight:
                                      FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: isUploading
                                ? null
                                : () =>
                                    Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Alert Summary ─────────────────────────
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius:
                              BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.red.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text('SOS Summary',
                                style: TextStyle(
                                    fontWeight:
                                        FontWeight.bold,
                                    fontSize: 13)),
                            const SizedBox(height: 6),
                            Text(
                                'Customer: ${alert.customerName}',
                                style: const TextStyle(
                                    fontSize: 12)),
                            if (alert.driverName != null)
                              Text(
                                  'Driver: ${alert.driverName}',
                                  style: const TextStyle(
                                      fontSize: 12)),
                            Text(
                                'Location: ${alert.address.length > 55 ? alert.address.substring(0, 55) + '…' : alert.address}',
                                style: const TextStyle(
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Photo proof ───────────────────────────
                      const Text('📸 Photo Proof *',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      const SizedBox(height: 4),
                      const Text(
                          'Take or pick a photo as evidence of resolution',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey)),
                      const SizedBox(height: 10),

                      if (imageBytes != null)
                        // ── Preview ──────────────────────────
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(10),
                              child: Image.memory(
                                imageBytes!,
                                width: double.infinity,
                                height: 160,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: GestureDetector(
                                onTap: () => setDialogState(
                                    () {
                                  pickedFile = null;
                                  imageBytes = null;
                                }),
                                child: Container(
                                  padding:
                                      const EdgeInsets.all(4),
                                  decoration:
                                      const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 16),
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        // ── Picker buttons ───────────────────
                        Row(
                          children: [
                            Expanded(
                              child: _buildPhotoPickerButton(
                                icon: Icons.camera_alt,
                                label: 'Camera',
                                color: Colors.blue,
                                onTap: kIsWeb
                                    ? () => pickImage(
                                        ImageSource.gallery)
                                    : () => pickImage(
                                        ImageSource.camera),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildPhotoPickerButton(
                                icon: Icons.photo_library,
                                label: 'Gallery',
                                color: Colors.purple,
                                onTap: () => pickImage(
                                    ImageSource.gallery),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 20),

                      // ── Resolution notes ──────────────────────
                      const Text('📝 Resolution Notes *',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: notesController,
                        maxLines: 4,
                        maxLength: 500,
                        decoration: InputDecoration(
                          hintText:
                              'Describe how this SOS was resolved…\ne.g. Customer confirmed safe. Police were not required.',
                          hintStyle: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[400]),
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(10)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Colors.green,
                                width: 2),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 20),

                      // ── Action buttons ────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isUploading
                                  ? null
                                  : () =>
                                      Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: isUploading
                                  ? null
                                  : submit,
                              icon: isUploading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child:
                                          CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation(
                                                Colors.white),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.check_circle,
                                      size: 18),
                              label: Text(isUploading
                                  ? 'Resolving…'
                                  : 'Mark Resolved'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.green[600],
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(
                                        vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPhotoPickerButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // OPEN LIVE TRACKING URL
  // ========================================================================
  Future<void> _openLiveTracking(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Could not open tracking URL'),
                backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error opening tracking URL: $e');
    }
  }

  // ========================================================================
  // RAISE TICKET DIALOG (unchanged from original)
  // ========================================================================
  void _showRaiseTicketDialog(IncompleteSOSAlert alert) {
    String? selectedEmployeeId;
    String? selectedEmployeeName;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Container(
              constraints: const BoxConstraints(
                  maxWidth: 500, maxHeight: 600),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius:
                              BorderRadius.circular(12),
                        ),
                        child: Icon(
                            Icons.confirmation_number,
                            color: Colors.orange.shade700,
                            size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('🎫 Raise Ticket for SOS',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.red.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text('🚨 SOS Alert Summary',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 8),
                        Text(
                            'Customer: ${alert.customerName}',
                            style:
                                const TextStyle(fontSize: 12)),
                        if (alert.driverName != null)
                          Text(
                              'Driver: ${alert.driverName}',
                              style: const TextStyle(
                                  fontSize: 12)),
                        if (alert.vehicleReg != null)
                          Text(
                              'Vehicle: ${alert.vehicleReg}',
                              style: const TextStyle(
                                  fontSize: 12)),
                        Text(
                          'Location: ${alert.address.length > 50 ? alert.address.substring(0, 50) : alert.address}…',
                          style:
                              const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Assign To Employee:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  const SizedBox(height: 12),
                  if (_isLoadingEmployees)
                    const Center(
                        child: CircularProgressIndicator())
                  else if (_employees.isEmpty)
                    const Text('No employees available',
                        style: TextStyle(color: Colors.red))
                  else
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonFormField<String>(
                        value: selectedEmployeeId,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.person),
                          hintText: 'Select Employee',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        items: _employees.map((e) {
                          return DropdownMenuItem<String>(
                            value: e['_id'].toString(),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                    e['name_parson'] ??
                                        'Unknown',
                                    style: const TextStyle(
                                        fontWeight:
                                            FontWeight.w600)),
                                if (e['email'] != null)
                                  Text(e['email'],
                                      style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              Colors.grey[600])),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (v) {
                          setDialogState(() {
                            selectedEmployeeId = v;
                            selectedEmployeeName = _employees
                                    .firstWhere((e) =>
                                        e['_id'].toString() ==
                                        v)['name_parson'] ??
                                'Unknown';
                          });
                        },
                      ),
                    ),
                  const SizedBox(height: 20),
                  if (selectedEmployeeId != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text('📋 Ticket Preview',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          const SizedBox(height: 8),
                          Text(
                              'Subject: SOS Alert - ${alert.customerName}',
                              style:
                                  const TextStyle(fontSize: 12)),
                          const Text('Priority: High',
                              style: TextStyle(fontSize: 12)),
                          Text(
                              'Assigned To: $selectedEmployeeName',
                              style:
                                  const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () =>
                              Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: selectedEmployeeId == null
                              ? null
                              : () async {
                                  Navigator.pop(context);
                                  await _raiseTicket(
                                      alert,
                                      selectedEmployeeId!,
                                      selectedEmployeeName!);
                                },
                          icon: const Icon(Icons.send),
                          label: const Text('Raise Ticket'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange[600],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ========================================================================
  // RAISE TICKET API
  // ========================================================================
  Future<void> _raiseTicket(
    IncompleteSOSAlert alert,
    String employeeId,
    String employeeName,
  ) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white)),
              ),
              SizedBox(width: 12),
              Text('Creating ticket…'),
            ]),
            backgroundColor: Color(0xFF0D47A1),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final ticketMessage = '''
🚨 **SOS ALERT - URGENT**

**Customer Details:**
- Name: ${alert.customerName}
- Phone: ${alert.customerPhone}
- Email: ${alert.customerEmail}

**Driver Details:**
${alert.driverName != null ? '- Driver: ${alert.driverName}' : '- Driver: N/A'}
${alert.driverPhone != null ? '- Phone: ${alert.driverPhone}' : ''}

**Vehicle Details:**
${alert.vehicleReg != null ? '- Vehicle: ${alert.vehicleFullName}' : '- Vehicle: N/A'}

**Location:**
${alert.address}

**Trip Information:**
${alert.tripId != null ? '- Trip ID: ${alert.tripId}' : '- Trip ID: N/A'}
${alert.pickupLocation != null ? '- Pickup: ${alert.pickupLocation}' : ''}
${alert.dropLocation != null ? '- Drop: ${alert.dropLocation}' : ''}

**Alert Time:** ${DateFormat('MMM dd, yyyy hh:mm a').format(alert.timestamp)}
**Coordinates:** ${alert.latitude}, ${alert.longitude}
**Google Maps:** ${alert.googleMapsUrl}
${alert.liveTrackingUrl != null ? '**Live Tracking:** ${alert.liveTrackingUrl}' : ''}

${alert.notes.isNotEmpty ? '**Notes:** ${alert.notes}' : ''}

---
⚠️ **Automated ticket from an active SOS alert. Please respond immediately.**
''';

      final response = await _tmsService.createTicket(
        subject: 'SOS Alert - ${alert.customerName}',
        message: ticketMessage,
        priority: 'High',
        timeline: 60,
        assignedTo: employeeId,
        status: 'Open',
      );

      if (response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const Icon(Icons.check_circle,
                    color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(
                        '✅ Ticket raised and assigned to $employeeName!')),
              ]),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        throw Exception(
            response['message'] ?? 'Failed to create ticket');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.error_outline,
                  color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                  child: Text('Failed to raise ticket: $e')),
            ]),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // ========================================================================
  // ALERT DETAILS DIALOG
  // ========================================================================
  void _showAlertDetails(IncompleteSOSAlert alert) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🚨 SOS Alert Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Customer: ${alert.customerName}'),
              Text('Phone: ${alert.customerPhone}'),
              Text('Email: ${alert.customerEmail}'),
              const SizedBox(height: 8),
              if (alert.driverName != null)
                Text('Driver: ${alert.driverName}'),
              if (alert.vehicleReg != null)
                Text('Vehicle: ${alert.vehicleFullName}'),
              const SizedBox(height: 8),
              Text('Location: ${alert.address}'),
              Text(
                  'Coordinates: ${alert.latitude}, ${alert.longitude}'),
              if (alert.liveTrackingUrl != null) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _openLiveTracking(
                      alert.liveTrackingUrl!),
                  child: Text(
                    '📍 Live Tracking: ${alert.liveTrackingUrl}',
                    style: const TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                        fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                  'Time: ${DateFormat('MMM dd, yyyy hh:mm a').format(alert.timestamp)}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // HELPERS
  // ========================================================================
  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: TextStyle(
                    color: Colors.grey[700], fontSize: 12))),
      ],
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline,
              size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text('No Active SOS Alerts',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            _filteredAlerts.isEmpty && _activeAlerts.isNotEmpty
                ? 'No alerts match your filters.'
                : 'All emergency alerts have been resolved.',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// MODEL
// ============================================================================
class IncompleteSOSAlert {
  final String id;
  final String customerName;
  final String customerEmail;
  final String customerPhone;
  final String address;
  final DateTime timestamp;
  final String? driverName;
  final String? driverPhone;
  final String? vehicleReg;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? tripId;
  final String? pickupLocation;
  final String? dropLocation;
  final double latitude;
  final double longitude;
  final String status;
  final String? policeEmailContacted;
  final String? emailSentStatus;
  final String? policeCity;
  final String notes;
  final String? liveTrackingUrl;

  IncompleteSOSAlert({
    required this.id,
    required this.customerName,
    required this.customerEmail,
    required this.customerPhone,
    required this.address,
    required this.timestamp,
    this.driverName,
    this.driverPhone,
    this.vehicleReg,
    this.vehicleMake,
    this.vehicleModel,
    this.tripId,
    this.pickupLocation,
    this.dropLocation,
    required this.latitude,
    required this.longitude,
    required this.status,
    this.policeEmailContacted,
    this.emailSentStatus,
    this.policeCity,
    this.notes = '',
    this.liveTrackingUrl,
  });

  factory IncompleteSOSAlert.fromJson(Map<String, dynamic> json) {
    double lat = 0.0, lon = 0.0;
    if (json['location'] != null &&
        json['location']['coordinates'] != null) {
      final c = json['location']['coordinates'] as List;
      if (c.length >= 2) {
        lon = (c[0] as num).toDouble();
        lat = (c[1] as num).toDouble();
      }
    } else if (json['gps'] != null) {
      lat = (json['gps']['latitude'] as num?)?.toDouble() ?? 0.0;
      lon = (json['gps']['longitude'] as num?)?.toDouble() ?? 0.0;
    }

    return IncompleteSOSAlert(
      id: json['_id']?.toString() ?? '',
      customerName:
          json['customerName']?.toString() ?? 'Unknown',
      customerEmail: json['customerEmail']?.toString() ?? '',
      customerPhone: json['customerPhone']?.toString() ?? '',
      address: json['address']?.toString() ??
          'Address not available',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'].toString())
          : DateTime.now(),
      driverName: json['driverName']?.toString(),
      driverPhone: json['driverPhone']?.toString(),
      vehicleReg: json['vehicleReg']?.toString(),
      vehicleMake: json['vehicleMake']?.toString(),
      vehicleModel: json['vehicleModel']?.toString(),
      tripId: json['tripId']?.toString(),
      pickupLocation: json['pickupLocation']?.toString(),
      dropLocation: json['dropLocation']?.toString(),
      latitude: lat,
      longitude: lon,
      status: json['status']?.toString() ?? 'ACTIVE',
      policeEmailContacted:
          json['policeEmailContacted']?.toString(),
      emailSentStatus: json['emailSentStatus']?.toString(),
      policeCity: json['policeCity']?.toString(),
      notes: json['adminNotes']?.toString() ??
          json['notes']?.toString() ??
          '',
      liveTrackingUrl: json['liveTrackingUrl']?.toString(),
    );
  }

  bool get wasPoliceNotified => emailSentStatus == 'sent';
  String get vehicleFullName =>
      vehicleMake != null && vehicleModel != null
          ? '$vehicleMake $vehicleModel${vehicleReg != null ? ' ($vehicleReg)' : ''}'
          : vehicleReg ?? 'N/A';
  String get googleMapsUrl =>
      'https://maps.google.com/?q=$latitude,$longitude';
}