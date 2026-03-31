// lib/screens/admin/admin_trip_dashboard.dart
// ============================================================================
// ADMIN TRIP DASHBOARD - COMPLETE WITH PROPER FILTERS & EXPORT
// ============================================================================
// ✅ Country/State/City filters in Row 1 (from country_state_city_filter.dart)
// ✅ Search, Domain, Date filters in Row 2
// ✅ Excel Export working (like invoice_list_page.dart)
// ✅ PDF Export working with proper data
// ✅ Fixed N/A values in exports
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/features/admin/admin_trip_details.dart';
import 'package:abra_fleet/features/admin/admin_report_generator.dart';
import 'package:abra_fleet/core/utils/export_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_html/html.dart' as html;

// ✅ Import the country/state/city filter widget
import 'package:abra_fleet/features/admin/widgets/country_state_city_filter.dart';

// ignore: avoid_classes_with_only_static_members
class MathHelpers {
  static int max(int a, int b) => a > b ? a : b;
}

// ============================================================================
// MAIN WIDGET
// ============================================================================
class AdminTripDashboard extends StatefulWidget {
  const AdminTripDashboard({super.key});
  static const String routeName = '/admin/trip-dashboard';

  @override
  State<AdminTripDashboard> createState() => AdminTripDashboardState();
}

// ============================================================================
// STATE CLASS
// ============================================================================
class AdminTripDashboardState extends State<AdminTripDashboard> {
  // ─── Summary / trips data ─────────────────────────────────────────────────
  Map<String, dynamic> summary = {};
  List<Map<String, dynamic>> trips = [];

  String selectedStatus = 'all';

  // ✅ Controllers for Row 2 filters
  final TextEditingController searchController = TextEditingController();
  final TextEditingController domainController = TextEditingController();

  // ✅ Date filters (Row 2)
  DateTime? fromDate;
  DateTime? toDate;

  // ✅ Location filters (Row 1 - from country_state_city_filter)
  String? selectedCountry;
  String? selectedState;
  String? selectedCity;
  String? localArea;

  bool isLoadingSummary = true;
  bool isLoadingTrips = true;
  bool isGeneratingReport = false;
  String? errorMessage;

  int currentPage = 1;
  final int itemsPerPage = 20;
  int totalPages = 1;
  int totalCount = 0;

  bool isFiltersExpanded = false;

  // ─── Token helper ─────────────────────────────────────────────────────────
  Future<String?> getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (_) {
      return null;
    }
  }

  // ─── Utility ──────────────────────────────────────────────────────────────
  String extractTripId(dynamic id) {
    if (id == null) return '';
    if (id is Map) return (id['\$oid'] ?? id['oid'] ?? '').toString();
    return id.toString();
  }

  bool get hasActiveFilters =>
      fromDate != null ||
      toDate != null ||
      (selectedCountry != null && selectedCountry!.isNotEmpty) ||
      (selectedState != null && selectedState!.isNotEmpty) ||
      (selectedCity != null && selectedCity!.isNotEmpty) ||
      (localArea != null && localArea!.isNotEmpty) ||
      searchController.text.trim().isNotEmpty ||
      domainController.text.trim().isNotEmpty;

  // ─── Status helpers ───────────────────────────────────────────────────────
  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'started':
      case 'in_progress':
        return const Color(0xFF00C853);
      case 'assigned':
        return const Color(0xFF2979FF);
      case 'completed':
        return const Color(0xFF607D8B);
      case 'cancelled':
        return const Color(0xFFFF1744);
      default:
        return Colors.grey;
    }
  }

  String getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'started':
      case 'in_progress':
        return 'ONGOING';
      case 'assigned':
        return 'SCHEDULED';
      case 'completed':
        return 'COMPLETED';
      case 'cancelled':
        return 'CANCELLED';
      default:
        return status.toUpperCase();
    }
  }

  // ============================================================================
  // API METHODS
  // ============================================================================

  Future<void> loadDashboardSummary() async {
    try {
      setState(() {
        isLoadingSummary = true;
        errorMessage = null;
      });
      final token = await getToken();
      if (token == null) throw Exception('No auth token');

      final params = <String, String>{};
      if (fromDate != null) params['fromDate'] = DateFormat('yyyy-MM-dd').format(fromDate!);
      if (toDate != null) params['toDate'] = DateFormat('yyyy-MM-dd').format(toDate!);

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/admin/trips/dashboard')
          .replace(queryParameters: params.isNotEmpty ? params : null);

      final response = await http.get(uri,
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            summary = data['data'] as Map<String, dynamic>;
            isLoadingSummary = false;
          });
        } else {
          throw Exception(data['message']);
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load dashboard: $e';
        isLoadingSummary = false;
      });
    }
  }

  Future<void> loadTripList() async {
    try {
      setState(() => isLoadingTrips = true);
      final token = await getToken();
      if (token == null) throw Exception('No auth token');

      final params = <String, String>{
        'status': selectedStatus,
        'page': currentPage.toString(),
        'limit': itemsPerPage.toString(),
      };

      if (fromDate != null) params['fromDate'] = DateFormat('yyyy-MM-dd').format(fromDate!);
      if (toDate != null) params['toDate'] = DateFormat('yyyy-MM-dd').format(toDate!);
      if (searchController.text.trim().isNotEmpty) params['search'] = searchController.text.trim();
      if (selectedCountry != null && selectedCountry!.isNotEmpty) params['country'] = selectedCountry!;
      if (selectedState != null && selectedState!.isNotEmpty) params['state'] = selectedState!;
      if (selectedCity != null && selectedCity!.isNotEmpty) params['city'] = selectedCity!;
      if (localArea != null && localArea!.isNotEmpty) params['locationSearch'] = localArea!;
      if (domainController.text.trim().isNotEmpty) {
        String domain = domainController.text.trim();
        if (domain.startsWith('@')) domain = domain.substring(1);
        params['domain'] = domain;
      }

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/admin/trips/list')
          .replace(queryParameters: params);

      final response = await http.get(uri,
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final tripList = data['data']['trips'] as List<dynamic>;
          final pagination = data['data']['pagination'] as Map<String, dynamic>;
          setState(() {
            trips = tripList.cast<Map<String, dynamic>>();
            totalPages = pagination['totalPages'] ?? 1;
            totalCount = pagination['total'] ?? 0;
            isLoadingTrips = false;
          });
        } else {
          throw Exception(data['message']);
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error loading trips: $e');
      setState(() => isLoadingTrips = false);
    }
  }

  Future<void> refreshDashboard() async {
    await Future.wait([loadDashboardSummary(), loadTripList()]);
  }

  void clearAllFilters() {
    setState(() {
      fromDate = null;
      toDate = null;
      selectedCountry = null;
      selectedState = null;
      selectedCity = null;
      localArea = null;
      searchController.clear();
      domainController.clear();
      currentPage = 1;
    });
    refreshDashboard();
  }

  String buildFilterSummary() {
    final parts = <String>[];
    if (fromDate != null && toDate != null) {
      parts.add('${DateFormat('MMM dd').format(fromDate!)} - ${DateFormat('MMM dd yyyy').format(toDate!)}');
    } else if (fromDate != null) {
      parts.add('From ${DateFormat('MMM dd yyyy').format(fromDate!)}');
    } else if (toDate != null) {
      parts.add('Up to ${DateFormat('MMM dd yyyy').format(toDate!)}');
    }
    if (selectedCountry != null) parts.add(selectedCountry!);
    if (selectedState != null) parts.add(selectedState!);
    if (selectedCity != null) parts.add(selectedCity!);
    if (searchController.text.isNotEmpty) parts.add('"${searchController.text}"');
    return parts.isEmpty ? 'All Trips' : parts.join(', ');
  }

  // ✅ NEW: Export Buttons Row (PDF, Excel, WhatsApp)
  Widget _buildExportButtonsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // PDF Download Button
          Expanded(
            child: _buildExportButton(
              icon: Icons.picture_as_pdf,
              label: 'PDF',
              color: Colors.red,
              onPressed: isGeneratingReport ? null : generatePDFReport,
            ),
          ),
          const SizedBox(width: 8),
          
          // Excel Export Button
          Expanded(
            child: _buildExportButton(
              icon: Icons.table_chart,
              label: 'Excel',
              color: Colors.green,
              onPressed: isGeneratingReport ? null : generateExcelReport,
            ),
          ),
          const SizedBox(width: 8),
          
          // WhatsApp Button
          Expanded(
            child: _buildExportButton(
              icon: Icons.chat,
              label: 'WhatsApp',
              color: const Color(0xFF25D366),
              onPressed: _openWhatsAppShare,
            ),
          ),
        ],
      ),
    );
  }

  // ✅ NEW: Export Button Widget
  Widget _buildExportButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.1),
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: color.withOpacity(0.3)),
        ),
      ),
    );
  }

  // ✅ NEW: WhatsApp Share Function
  Future<void> _openWhatsAppShare() async {
    if (trips.isEmpty) {
      _showErrorSnackbar('No trips to share');
      return;
    }

    try {
      // Prepare trip summary message
      final statusLabel = selectedStatus == 'all' ? 'All Trips' : getStatusText(selectedStatus);
      final filterInfo = buildFilterSummary();
      
      String message = '📊 *Trip Dashboard Report*\n\n';
      message += '📅 *Filter:* $filterInfo\n';
      message += '📈 *Status:* $statusLabel\n';
      message += '🚗 *Total Trips:* $totalCount\n\n';
      
      message += '*Summary:*\n';
      message += '• Ongoing: ${summary['ongoing'] ?? 0}\n';
      message += '• Scheduled: ${summary['scheduled'] ?? 0}\n';
      message += '• Completed: ${summary['completed'] ?? 0}\n';
      message += '• Cancelled: ${summary['cancelled'] ?? 0}\n\n';
      
      message += '*Fleet Stats:*\n';
      message += '• Vehicles: ${summary['totalVehicles'] ?? 0}\n';
      message += '• Drivers: ${summary['totalDrivers'] ?? 0}\n';
      message += '• Customers: ${summary['totalCustomers'] ?? 0}\n\n';
      
      message += '📱 Generated from Abra Fleet Management';

      // Encode message for URL
      final encodedMessage = Uri.encodeComponent(message);
      final whatsappUrl = 'https://wa.me/?text=$encodedMessage';
      
      final uri = Uri.parse(whatsappUrl);
      
      if (kIsWeb) {
        // For web, open in new tab
        html.window.open(whatsappUrl, '_blank');
        _showSuccessSnackbar('✅ WhatsApp opened! Select contact to share.');
      } else {
        // For mobile/desktop
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          _showSuccessSnackbar('✅ WhatsApp opened! Select contact to share.');
        } else {
          throw 'Could not launch WhatsApp';
        }
      }
    } catch (e) {
      print('❌ WhatsApp Error: $e');
      _showErrorSnackbar('Failed to open WhatsApp: $e');
    }
  }

  // ✅ Download Options Dialog
  Future<void> showDownloadOptions() async {
    if (trips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No trips to generate report for'), backgroundColor: Colors.orange),
      );
      return;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.download, size: 48, color: Color(0xFF0D47A1)),
                const SizedBox(height: 16),
                const Text(
                  'Download Report',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose your preferred format',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                
                // Excel Option
                InkWell(
                  onTap: () => Navigator.pop(context, 'excel'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF0D47A1).withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFF0D47A1).withOpacity(0.05),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.table_chart, size: 32, color: Colors.green.shade700),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Download as Excel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              Text('Get data in spreadsheet format', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF0D47A1)),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // PDF Option
                InkWell(
                  onTap: () => Navigator.pop(context, 'pdf'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF0D47A1).withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFF0D47A1).withOpacity(0.05),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.picture_as_pdf, size: 32, color: Colors.red.shade700),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Download as PDF', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              Text('Get formatted PDF document', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF0D47A1)),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result != null) {
      if (result == 'excel') {
        await generateExcelReport();
      } else if (result == 'pdf') {
        await generatePDFReport();
      }
    }
  }

  // ✅ FIXED: Excel Export (like invoice_list_page.dart)
  Future<void> generateExcelReport() async {
    setState(() => isGeneratingReport = true);
    try {
      if (trips.isEmpty) {
        _showErrorSnackbar('No trips to export');
        return;
      }

      _showSuccessSnackbar('Preparing Excel export...');

      // Prepare CSV data
      List<List<dynamic>> csvData = [
        // Headers
        [
          'Trip Number',
          'Status',
          'Vehicle Number',
          'Vehicle Name',
          'Driver Name',
          'Driver Phone',
          'Scheduled Date',
          'Start Time',
          'End Time',
          'Total Stops',
          'Completed Stops',
          'Cancelled Stops',
          'Total Distance (km)',
          'Progress (%)',
        ],
      ];

      print('📊 Exporting ${trips.length} trips...');

      // Add data rows
      for (var trip in trips) {
        csvData.add([
          trip['tripNumber'] ?? 'N/A',
          getStatusText(trip['status'] ?? 'N/A'),
          trip['vehicleNumber'] ?? 'Unknown',
          trip['vehicleName'] ?? '',
          trip['driverName'] ?? 'Unknown',
          trip['driverPhone'] ?? '',
          trip['scheduledDate'] ?? '',
          trip['startTime'] ?? '',
          trip['endTime'] ?? '',
          trip['totalStops']?.toString() ?? '0',
          trip['completedStops']?.toString() ?? '0',
          trip['cancelledStops']?.toString() ?? '0',
          (trip['totalDistance'] ?? 0).toString(),
          (trip['progress'] ?? 0).toString(),
        ]);
      }

      // Use ExportHelper
      final filePath = await ExportHelper.exportToExcel(
        data: csvData,
        filename: 'trip_dashboard_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
      );

      _showSuccessSnackbar('✅ Excel file downloaded with ${trips.length} trips!');
    } catch (e) {
      print('❌ Excel Export Error: $e');
      _showErrorSnackbar('Failed to export Excel: $e');
    } finally {
      if (mounted) setState(() => isGeneratingReport = false);
    }
  }

  // ✅ FIXED: PDF Export with proper data
  Future<void> generatePDFReport() async {
    setState(() => isGeneratingReport = true);
    try {
      final token = await getToken();
      if (token == null) throw Exception('No auth token');
      
      // ✅ Build params with ALL current filters
      final params = <String, String>{'status': selectedStatus};
      if (fromDate != null) params['fromDate'] = DateFormat('yyyy-MM-dd').format(fromDate!);
      if (toDate != null) params['toDate'] = DateFormat('yyyy-MM-dd').format(toDate!);
      if (selectedCountry != null && selectedCountry!.isNotEmpty) params['country'] = selectedCountry!;
      if (selectedState != null && selectedState!.isNotEmpty) params['state'] = selectedState!;
      if (selectedCity != null && selectedCity!.isNotEmpty) params['city'] = selectedCity!;
      if (searchController.text.trim().isNotEmpty) params['search'] = searchController.text.trim();
      if (localArea != null && localArea!.isNotEmpty) params['locationSearch'] = localArea!;
      if (domainController.text.trim().isNotEmpty) {
        String domain = domainController.text.trim();
        if (domain.startsWith('@')) domain = domain.substring(1);
        params['domain'] = domain;
      }

      print('📊 Fetching bulk report with filters: $params');

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/admin/trips/bulk-report').replace(queryParameters: params);
      final response = await http.get(uri, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'});
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          print('✅ Bulk report data received');
          
          if (mounted) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminReportGenerator(
                  reportData: data['data'] as Map<String, dynamic>,
                  filterSummary: buildFilterSummary(),
                ),
              ),
            );
          }
        } else {
          throw Exception(data['message']);
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('❌ PDF generation error: $e');
      if (mounted) {
        _showErrorSnackbar('PDF generation failed: $e');
      }
    } finally {
      if (mounted) setState(() => isGeneratingReport = false);
    }
  }

  Future<void> pickDate({required bool isFrom}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: (isFrom ? fromDate : toDate) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF0D47A1))),
        child: child!,
      ),
    );
    if (date != null) {
      setState(() {
        if (isFrom) {
          fromDate = date;
          if (toDate != null && toDate!.isBefore(date)) toDate = null;
        } else {
          toDate = date;
          if (fromDate != null && fromDate!.isAfter(date)) fromDate = null;
        }
        currentPage = 1;
      });
      refreshDashboard();
    }
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ============================================================================
  // LIFECYCLE
  // ============================================================================
  @override
  void initState() {
    super.initState();
    loadDashboardSummary();
    loadTripList();
  }

  @override
  void dispose() {
    searchController.dispose();
    domainController.dispose();
    super.dispose();
  }

  // ============================================================================
  // BUILD
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: refreshDashboard,
        child: _buildBody(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0D47A1),
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
        tooltip: 'Back to Admin Dashboard',
      ),
      title: const Text('Trip Management', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
      actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: refreshDashboard, tooltip: 'Refresh'),
      ],
    );
  }

  Widget _buildBody() {
    if (isLoadingSummary) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading dashboard...'),
        ]),
      );
    }
    if (errorMessage != null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(errorMessage!, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: refreshDashboard, child: const Text('Retry')),
        ]),
      );
    }
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterToggleButton(),
          if (isFiltersExpanded) _buildFilterPanel(),
          if (hasActiveFilters) _buildActiveFiltersBanner(),
          _buildStatusCards(),
          const SizedBox(height: 12),
          _buildChartsRow(),
          const SizedBox(height: 12),
          _buildSummaryStatsCards(),
          const SizedBox(height: 12),
          _buildTripTableSection(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ─── Filter toggle button ─────────────────────────────────────────────────
  Widget _buildFilterToggleButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: ElevatedButton.icon(
        onPressed: () => setState(() => isFiltersExpanded = !isFiltersExpanded),
        icon: Icon(isFiltersExpanded ? Icons.filter_list_off : Icons.filter_list, size: 20),
        label: Text(isFiltersExpanded ? 'Hide Filters' : 'Show Filters'),
        style: ElevatedButton.styleFrom(
          backgroundColor: isFiltersExpanded ? const Color(0xFF0D47A1) : Colors.grey.shade100,
          foregroundColor: isFiltersExpanded ? Colors.white : Colors.grey.shade700,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: isFiltersExpanded ? 2 : 0,
        ),
      ),
    );
  }

  // ✅ NEW: Filter panel with 2 rows
  Widget _buildFilterPanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ ROW 1: Country/State/City Filter (from country_state_city_filter.dart)
          CountryStateCityFilter(
            initialFromDate: fromDate,
            initialToDate: toDate,
            initialCountry: selectedCountry,
            initialState: selectedState,
            initialCity: selectedCity,
            initialLocalArea: localArea,
            onFilterApplied: (filters) {
              setState(() {
                fromDate = filters['fromDate'] as DateTime?;
                toDate = filters['toDate'] as DateTime?;
                selectedCountry = filters['country'] as String?;
                selectedState = filters['state'] as String?;
                selectedCity = filters['city'] as String?;
                localArea = filters['localArea'] as String?;
                currentPage = 1;
              });
              loadTripList();
            },
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),

          // ✅ ROW 2: Search + Domain filters
          Row(
            children: [
              // Search
              Expanded(
                flex: 2,
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by vehicle, driver, trip number...',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () { 
                              searchController.clear(); 
                              setState(() => currentPage = 1); 
                              loadTripList(); 
                            })
                        : null,
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 1.5)),
                  ),
                  onSubmitted: (_) { setState(() => currentPage = 1); loadTripList(); },
                ),
              ),

              const SizedBox(width: 12),

              // Domain
              Expanded(
                child: TextField(
                  controller: domainController,
                  decoration: InputDecoration(
                    labelText: 'Company Domain',
                    hintText: 'e.g., infosys.com',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    prefixIcon: const Icon(Icons.business, size: 20),
                    suffixIcon: domainController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18), 
                            onPressed: () { 
                              domainController.clear(); 
                              setState(() => currentPage = 1); 
                              loadTripList(); 
                            })
                        : null,
                    filled: true,
                    fillColor: Colors.purple.shade50,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.purple.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.purple.shade300)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.purple, width: 1.5)),
                  ),
                  onSubmitted: (_) { setState(() => currentPage = 1); loadTripList(); },
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Action buttons
          Row(children: [
            if (hasActiveFilters) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: clearAllFilters,
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Clear All'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red, 
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            
            // ✅ NEW: Export buttons row (PDF, Excel, WhatsApp)
            Expanded(
              flex: 2,
              child: _buildExportButtonsRow(),
            ),
          ]),
        ],
      ),
    );
  }

  // ─── Status Cards (unchanged) ─────────────────────────────────────────────
  Widget _buildStatusCards() {
    final total = (summary['total'] ?? 0) as int;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('Trip Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          ),
          LayoutBuilder(builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 600 ? 5 : 3;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.1,
              children: [
                _buildStatusCard('Total', total, Icons.stacked_bar_chart, const Color(0xFF0D47A1), 'all'),
                _buildStatusCard('Ongoing', summary['ongoing'] ?? 0, Icons.directions_car, const Color(0xFF00BFA5), 'ongoing'),
                _buildStatusCard('Scheduled', summary['scheduled'] ?? 0, Icons.schedule, const Color(0xFF2979FF), 'scheduled'),
                _buildStatusCard('Completed', summary['completed'] ?? 0, Icons.check_circle, const Color(0xFF43A047), 'completed'),
                _buildStatusCard('Cancelled', summary['cancelled'] ?? 0, Icons.cancel, const Color(0xFFE53935), 'cancelled'),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatusCard(String title, int count, IconData icon, Color color, String status) {
    final isSelected = selectedStatus == status;
    return InkWell(
      onTap: () { setState(() { selectedStatus = status; currentPage = 1; }); loadTripList(); },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isSelected
                ? [color, color.withOpacity(0.75)]
                : [Colors.white, color.withOpacity(0.05)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? color : color.withOpacity(0.3), width: isSelected ? 2 : 1),
          boxShadow: [
            BoxShadow(
              color: isSelected ? color.withOpacity(0.35) : Colors.black.withOpacity(0.06),
              blurRadius: isSelected ? 12 : 4,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: isSelected ? Colors.white : color),
            const SizedBox(height: 6),
            Text('$count',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : color)),
            const SizedBox(height: 2),
            Text(title,
                style: TextStyle(fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white.withOpacity(0.9) : color.withOpacity(0.8)),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ─── Charts Row (unchanged) ───────────────────────────────────────────────
  Widget _buildChartsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: _buildPieChartCard()),
          const SizedBox(width: 12),
          Expanded(flex: 5, child: _buildBarChartCard()),
        ],
      ),
    );
  }

  Widget _buildPieChartCard() {
    final ongoing = (summary['ongoing'] ?? 0) as int;
    final scheduled = (summary['scheduled'] ?? 0) as int;
    final completed = (summary['completed'] ?? 0) as int;
    final cancelled = (summary['cancelled'] ?? 0) as int;
    final total = ongoing + scheduled + completed + cancelled;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Trip Distribution', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: total == 0
                ? const Center(child: Text('No data', style: TextStyle(color: Colors.grey)))
                : CustomPaint(
                    painter: _PieChartPainter(
                      values: [ongoing.toDouble(), scheduled.toDouble(), completed.toDouble(), cancelled.toDouble()],
                      colors: [const Color(0xFF00BFA5), const Color(0xFF2979FF), const Color(0xFF43A047), const Color(0xFFE53935)],
                      total: total.toDouble(),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('$total', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                          const Text('Total', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _pieLegend('Ongoing', ongoing, const Color(0xFF00BFA5)),
              _pieLegend('Scheduled', scheduled, const Color(0xFF2979FF)),
              _pieLegend('Completed', completed, const Color(0xFF43A047)),
              _pieLegend('Cancelled', cancelled, const Color(0xFFE53935)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pieLegend(String label, int count, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text('$label ($count)', style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
    ]);
  }

  Widget _buildBarChartCard() {
    final vehicles = (summary['totalVehicles'] ?? 0) as int;
    final drivers = (summary['totalDrivers'] ?? 0) as int;
    final customers = (summary['totalCustomers'] ?? 0) as int;
    final delayed = (summary['delayed'] ?? 0) as int;

    final maxVal = [vehicles, drivers, customers, delayed].reduce(MathHelpers.max).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fleet Statistics', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          const SizedBox(height: 16),
          _buildBarRow('Vehicles', vehicles, maxVal, const Color(0xFF1E88E5)),
          const SizedBox(height: 12),
          _buildBarRow('Drivers', drivers, maxVal, const Color(0xFFFF6F00)),
          const SizedBox(height: 12),
          _buildBarRow('Customers', customers, maxVal, const Color(0xFF8E24AA)),
          const SizedBox(height: 12),
          _buildBarRow('Delayed', delayed, maxVal, const Color(0xFFE53935)),
        ],
      ),
    );
  }

  Widget _buildBarRow(String label, int value, double maxVal, Color color) {
    final fraction = maxVal > 0 ? (value / maxVal).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
            Text('$value', style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        LayoutBuilder(builder: (ctx, cons) {
          return Stack(children: [
            Container(height: 10, width: cons.maxWidth, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(5))),
            AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              height: 10,
              width: cons.maxWidth * fraction,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                gradient: LinearGradient(colors: [color.withOpacity(0.7), color]),
              ),
            ),
          ]);
        }),
      ],
    );
  }

  Widget _buildSummaryStatsCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildStatCard(Icons.directions_car, 'Vehicles', summary['totalVehicles'] ?? 0, const Color(0xFF1E88E5)),
          const SizedBox(width: 10),
          _buildStatCard(Icons.person, 'Drivers', summary['totalDrivers'] ?? 0, const Color(0xFFFF6F00)),
          const SizedBox(width: 10),
          _buildStatCard(Icons.people, 'Customers', summary['totalCustomers'] ?? 0, const Color(0xFF8E24AA)),
          const SizedBox(width: 10),
          _buildStatCard(Icons.warning, 'Delayed', summary['delayed'] ?? 0, const Color(0xFFE53935)),
        ],
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [color.withOpacity(0.12), color.withOpacity(0.04)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.8), fontWeight: FontWeight.w500), textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  // ✅ Table section (unchanged)
  Widget _buildTripTableSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTableHeader(),
          const SizedBox(height: 8),
          _buildTable(),
          if (totalPages > 1) _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    final statusLabel = selectedStatus == 'all'
        ? 'All Trips'
        : selectedStatus[0].toUpperCase() + selectedStatus.substring(1);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('$statusLabel — $totalCount trip(s)',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
        if (totalPages > 1)
          Text('Page $currentPage / $totalPages',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildTable() {
    if (isLoadingTrips) {
      return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
    }
    if (trips.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Icon(Icons.inbox, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('No trips found', style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('Try adjusting your filters', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          if (hasActiveFilters) ...[
            const SizedBox(height: 20),
            TextButton.icon(onPressed: clearAllFilters, icon: const Icon(Icons.clear_all), label: const Text('Clear All Filters')),
          ],
        ]),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Scrollbar(
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 8,
          radius: const Radius.circular(4),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: true,
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
              },
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFF0D47A1)),
                headingTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.3,
                ),
                headingRowHeight: 56,
                dataRowMinHeight: 60,
                dataRowMaxHeight: 72,
                dataTextStyle: const TextStyle(fontSize: 14),
                dataRowColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.hovered)) return Colors.blue.shade50;
                  return null;
                }),
                dividerThickness: 1,
                columnSpacing: 24,
                horizontalMargin: 20,
                columns: const [
                  DataColumn(label: SizedBox(width: 130, child: Text('Trip #', overflow: TextOverflow.ellipsis))),
                  DataColumn(label: SizedBox(width: 150, child: Text('Vehicle', overflow: TextOverflow.ellipsis))),
                  DataColumn(label: SizedBox(width: 160, child: Text('Driver', overflow: TextOverflow.ellipsis))),
                  DataColumn(label: SizedBox(width: 140, child: Text('Phone', overflow: TextOverflow.ellipsis))),
                  DataColumn(label: SizedBox(width: 130, child: Text('Date', overflow: TextOverflow.ellipsis))),
                  DataColumn(label: SizedBox(width: 140, child: Text('Time', overflow: TextOverflow.ellipsis))),
                  DataColumn(label: SizedBox(width: 110, child: Text('Customers', overflow: TextOverflow.ellipsis))),
                  DataColumn(label: SizedBox(width: 100, child: Text('Stops', overflow: TextOverflow.ellipsis))),
                  DataColumn(label: SizedBox(width: 110, child: Text('Completed', overflow: TextOverflow.ellipsis))),
                  DataColumn(label: SizedBox(width: 110, child: Text('Cancelled', overflow: TextOverflow.ellipsis))),
                  DataColumn(label: SizedBox(width: 120, child: Text('Distance', overflow: TextOverflow.ellipsis))),
                  DataColumn(label: SizedBox(width: 130, child: Text('Status', overflow: TextOverflow.ellipsis))),
                  DataColumn(label: SizedBox(width: 130, child: Text('Progress', overflow: TextOverflow.ellipsis))),
                  DataColumn(label: SizedBox(width: 130, child: Text('Trip Type', overflow: TextOverflow.ellipsis))),
                  DataColumn(label: SizedBox(width: 110, child: Text('Actions', overflow: TextOverflow.ellipsis))),
                ],
                rows: trips.map((trip) => _buildRow(trip)).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(Map<String, dynamic> trip) {
    final status = trip['status']?.toString() ?? 'assigned';
    final progress = (trip['progress'] ?? 0).toDouble();
    final isDelayed = trip['isDelayed'] == true;
    Color statusColor = getStatusColor(status);
    if (isDelayed) statusColor = const Color(0xFFE53935);

    String scheduledDateStr = '';
    try {
      final raw = trip['scheduledDate']?.toString() ?? '';
      if (raw.isNotEmpty) scheduledDateStr = DateFormat('dd MMM yyyy').format(DateTime.parse(raw));
    } catch (_) {}

    return DataRow(
      onSelectChanged: (_) {
        final tripId = extractTripId(trip['_id']);
        if (tripId.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AdminTripDetails(tripId: tripId)),
          );
        }
      },
      cells: [
        DataCell(SizedBox(width: 130, child: Text(trip['tripNumber'] ?? 'N/A', 
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0D47A1))))),
        DataCell(SizedBox(width: 150, child: Text(trip['vehicleNumber'] ?? 'Unknown', 
            style: const TextStyle(fontSize: 14)))),
        DataCell(SizedBox(width: 160, child: Text(trip['driverName'] ?? 'Unknown', 
            style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis))),
        DataCell(SizedBox(width: 140, child: Text(trip['driverPhone'] ?? '—', 
            style: const TextStyle(fontSize: 14)))),
        DataCell(SizedBox(width: 130, child: Text(scheduledDateStr, 
            style: const TextStyle(fontSize: 14)))),
        DataCell(SizedBox(width: 140, child: Text('${trip['startTime'] ?? ''} - ${trip['endTime'] ?? ''}', 
            style: const TextStyle(fontSize: 13)))),
        DataCell(SizedBox(width: 110, child: Text('${trip['customerCount'] ?? 0}', 
            style: const TextStyle(fontSize: 14)))),
        DataCell(SizedBox(width: 100, child: Text('${trip['totalStops'] ?? 0}', 
            style: const TextStyle(fontSize: 14)))),
        DataCell(SizedBox(width: 110, child: Text('${trip['completedStops'] ?? 0}', 
            style: const TextStyle(fontSize: 14)))),
        DataCell(SizedBox(width: 110, child: Text('${trip['cancelledStops'] ?? 0}', 
            style: TextStyle(fontSize: 14, color: (trip['cancelledStops'] ?? 0) > 0 ? Colors.red : null)))),
        DataCell(SizedBox(width: 120, child: Text('${(trip['totalDistance'] ?? 0).toStringAsFixed(1)} km', 
            style: const TextStyle(fontSize: 14)))),
        DataCell(SizedBox(
          width: 130,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(getStatusText(status), 
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor), textAlign: TextAlign.center),
          ),
        )),
        DataCell(SizedBox(
          width: 130,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress / 100, backgroundColor: Colors.grey.shade200, 
                  valueColor: AlwaysStoppedAnimation(statusColor), minHeight: 8),
            ),
            const SizedBox(height: 4),
            Text('${progress.toInt()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor)),
          ]),
        )),
        DataCell(SizedBox(width: 130, child: Text(trip['tripType']?.toString().toUpperCase() ?? 'N/A', 
            style: const TextStyle(fontSize: 13)))),
        DataCell(SizedBox(
          width: 110,
          child: TextButton(
            onPressed: () {
              final tripId = extractTripId(trip['_id']);
              if (tripId.isEmpty) return;
              Navigator.push(context, MaterialPageRoute(builder: (_) => AdminTripDetails(tripId: tripId)));
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: const Color(0xFF0D47A1).withOpacity(0.08),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text('View', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0D47A1))),
          ),
        )),
      ],
    );
  }

  Widget _buildPagination() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: currentPage > 1 ? () { setState(() => currentPage--); loadTripList(); } : null,
        ),
        Text('$currentPage / $totalPages', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: currentPage < totalPages ? () { setState(() => currentPage++); loadTripList(); } : null,
        ),
      ]),
    );
  }

  Widget _buildActiveFiltersBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Wrap(
        spacing: 6, runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.filter_alt, size: 16, color: Colors.blue.shade700),
          Text('Active:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue.shade700)),
          if (fromDate != null || toDate != null)
            _filterChip(
              '📅 ${fromDate != null ? DateFormat('MMM dd').format(fromDate!) : 'Start'} → ${toDate != null ? DateFormat('MMM dd').format(toDate!) : 'End'}',
              () { setState(() { fromDate = null; toDate = null; currentPage = 1; }); refreshDashboard(); },
            ),
          if (selectedCountry != null) _filterChip('🌍 $selectedCountry', () { setState(() { selectedCountry = null; selectedState = null; selectedCity = null; currentPage = 1; }); loadTripList(); }),
          if (selectedState != null) _filterChip('📍 $selectedState', () { setState(() { selectedState = null; selectedCity = null; currentPage = 1; }); loadTripList(); }),
          if (selectedCity != null) _filterChip('🏙️ $selectedCity', () { setState(() { selectedCity = null; currentPage = 1; }); loadTripList(); }),
          if (localArea != null && localArea!.isNotEmpty) _filterChip('📝 "$localArea"', () { setState(() { localArea = null; currentPage = 1; }); loadTripList(); }),
          if (domainController.text.isNotEmpty) _filterChip('🏢 @${domainController.text.replaceAll('@', '')}', () { domainController.clear(); setState(() => currentPage = 1); loadTripList(); }),
          if (searchController.text.isNotEmpty) _filterChip('🔍 "${searchController.text}"', () { searchController.clear(); setState(() => currentPage = 1); loadTripList(); }),
        ],
      ),
    );
  }

  Widget _filterChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blue.shade200)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        const SizedBox(width: 4),
        GestureDetector(onTap: onRemove, child: Icon(Icons.close, size: 13, color: Colors.red.shade400)),
      ]),
    );
  }
}

// ============================================================================
// PIE CHART PAINTER (unchanged)
// ============================================================================
class _PieChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final double total;

  _PieChartPainter({required this.values, required this.colors, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    double startAngle = -math.pi / 2;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 28;

    for (int i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweepAngle = (values[i] / total) * 2 * math.pi;
      paint.color = colors[i];
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
    final bgPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 20, bgPaint);
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.total != total;
}

// ============================================================================
// TRIP TABLE SECTION — FULL (Part 2)
// ============================================================================
/// A rich, scrollable table that supports all status views with a gradient
/// header, cursor-friendly horizontal + vertical scroll, and detailed columns.
class TripTableSectionFull extends StatefulWidget {
  final AdminTripDashboardState state;
  const TripTableSectionFull({super.key, required this.state});

  @override
  State<TripTableSectionFull> createState() => _TripTableSectionFullState();
}

class _TripTableSectionFullState extends State<TripTableSectionFull> {
  // Sorted column tracking
  int? _sortColumnIndex;
  bool _sortAscending = true;

  // ─── Column definitions ───────────────────────────────────────────────────
  static const List<_ColumnDef> _columns = [
    _ColumnDef(key: 'tripNumber',    label: 'Trip #',        width: 120, sortable: true),
    _ColumnDef(key: 'vehicleNumber', label: 'Vehicle No.',   width: 130, sortable: true),
    _ColumnDef(key: 'vehicleName',   label: 'Vehicle Name',  width: 140, sortable: false),
    _ColumnDef(key: 'driverName',    label: 'Driver Name',   width: 150, sortable: true),
    _ColumnDef(key: 'driverPhone',   label: 'Driver Phone',  width: 130, sortable: false),
    _ColumnDef(key: 'scheduledDate', label: 'Date',          width: 120, sortable: true),
    _ColumnDef(key: 'time',          label: 'Scheduled Time',width: 130, sortable: false),
    _ColumnDef(key: 'customerCount', label: 'Customers',     width: 100, sortable: true),
    _ColumnDef(key: 'totalStops',    label: 'Total Stops',   width: 100, sortable: true),
    _ColumnDef(key: 'completedStops',label: 'Completed',     width: 100, sortable: true),
    _ColumnDef(key: 'cancelledStops',label: 'Cancelled',     width: 100, sortable: true),
    _ColumnDef(key: 'totalDistance', label: 'Distance (km)', width: 120, sortable: true),
    _ColumnDef(key: 'totalTime',     label: 'Duration (min)',width: 120, sortable: false),
    _ColumnDef(key: 'status',        label: 'Status',        width: 120, sortable: true),
    _ColumnDef(key: 'progress',      label: 'Progress',      width: 120, sortable: true),
    _ColumnDef(key: 'tripType',      label: 'Trip Type',     width: 110, sortable: false),
    _ColumnDef(key: 'actualStart',   label: 'Actual Start',  width: 120, sortable: false),
    _ColumnDef(key: 'actualEnd',     label: 'Actual End',    width: 120, sortable: false),
    _ColumnDef(key: 'actions',       label: 'Actions',       width: 100, sortable: false),
  ];

  // ─── Sort logic ───────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _sortedTrips {
    final trips = List<Map<String, dynamic>>.from(widget.state.trips);
    if (_sortColumnIndex == null) return trips;

    final col = _columns[_sortColumnIndex!];
    trips.sort((a, b) {
      dynamic va = a[col.key];
      dynamic vb = b[col.key];
      if (va == null && vb == null) return 0;
      if (va == null) return _sortAscending ? 1 : -1;
      if (vb == null) return _sortAscending ? -1 : 1;
      int cmp;
      if (va is num && vb is num) {
        cmp = va.compareTo(vb);
      } else {
        cmp = va.toString().compareTo(vb.toString());
      }
      return _sortAscending ? cmp : -cmp;
    });
    return trips;
  }

  Color _getStatusColor(String status) => widget.state.getStatusColor(status);
  String _getStatusText(String status) => widget.state.getStatusText(status);

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try { return DateFormat('dd MMM yyyy').format(DateTime.parse(raw)); } catch (_) { return raw; }
  }

  String _formatTime(dynamic dt) {
    if (dt == null) return '—';
    try { return DateFormat('HH:mm').format(DateTime.parse(dt.toString())); } catch (_) { return '—'; }
  }

  // ============================================================================
  // BUILD
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(),
          const SizedBox(height: 10),
          _buildStatusTabBar(),
          const SizedBox(height: 10),
          _buildTableCard(),
          if (widget.state.totalPages > 1) _buildPagination(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ─── Section header ───────────────────────────────────────────────────────
  Widget _buildSectionHeader() {
    final statusLabel = widget.state.selectedStatus == 'all'
        ? 'All Trips'
        : widget.state.selectedStatus[0].toUpperCase() + widget.state.selectedStatus.substring(1);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$statusLabel Trips',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          Text('${widget.state.totalCount} records found',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ]),
        if (widget.state.totalPages > 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFF0D47A1).withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
            child: Text('Page ${widget.state.currentPage} / ${widget.state.totalPages}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0D47A1))),
          ),
      ],
    );
  }

  // ─── Status tab bar ───────────────────────────────────────────────────────
  Widget _buildStatusTabBar() {
    final tabs = [
      _TabItem('all', 'All', Icons.stacked_bar_chart, const Color(0xFF0D47A1)),
      _TabItem('ongoing', 'Ongoing', Icons.directions_car, const Color(0xFF00BFA5)),
      _TabItem('scheduled', 'Scheduled', Icons.schedule, const Color(0xFF2979FF)),
      _TabItem('completed', 'Completed', Icons.check_circle, const Color(0xFF43A047)),
      _TabItem('cancelled', 'Cancelled', Icons.cancel, const Color(0xFFE53935)),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tabs.map((tab) {
          final isSelected = widget.state.selectedStatus == tab.status;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () {
                widget.state.setState(() { widget.state.selectedStatus = tab.status; widget.state.currentPage = 1; });
                widget.state.loadTripList();
              },
              borderRadius: BorderRadius.circular(24),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? tab.color : tab.color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: tab.color.withOpacity(isSelected ? 1.0 : 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(tab.icon, size: 15, color: isSelected ? Colors.white : tab.color),
                  const SizedBox(width: 6),
                  Text(tab.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : tab.color)),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Table card ───────────────────────────────────────────────────────────
  Widget _buildTableCard() {
    if (widget.state.isLoadingTrips) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading trips...'),
        ]),
      );
    }

    if (widget.state.trips.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
        ),
        child: Column(children: [
          Icon(Icons.inbox_rounded, size: 72, color: Colors.grey.shade200),
          const SizedBox(height: 16),
          Text('No trips found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text('Adjust your filters or date range', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          if (widget.state.hasActiveFilters) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: widget.state.clearAllFilters,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear All Filters'),
            ),
          ],
        ]),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Scrollbar(
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 8,
          radius: const Radius.circular(4),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: true,
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
              },
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Scrollbar(
                thumbVisibility: true,
                trackVisibility: true,
                thickness: 8,
                radius: const Radius.circular(4),
                notificationPredicate: (n) => n.depth == 1,
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: _buildDataTable(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Data table ───────────────────────────────────────────────────────────
  Widget _buildDataTable() {
    final sorted = _sortedTrips;

    return DataTable(
      sortColumnIndex: _sortColumnIndex,
      sortAscending: _sortAscending,
      headingRowHeight: 48,
      dataRowMinHeight: 52,
      dataRowMaxHeight: 60,
      dividerThickness: 0.6,
      columnSpacing: 20,
      horizontalMargin: 16,
      // Blue gradient header
      headingRowColor: WidgetStateProperty.all(const Color(0xFF0D47A1)),
      headingTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 12,
        letterSpacing: 0.3,
      ),
      dataRowColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.blue.shade50;
        if (states.contains(WidgetState.hovered)) return const Color(0xFFF0F4FF);
        return null;
      }),
      columns: _buildColumns(),
      rows: sorted.asMap().entries.map((entry) => _buildDataRow(context, entry.key, entry.value)).toList(),
    );
  }

  List<DataColumn> _buildColumns() {
    return _columns.asMap().entries.map((entry) {
      final i = entry.key;
      final col = entry.value;
      return DataColumn(
        label: MouseRegion(
          cursor: col.sortable ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: SizedBox(
            width: col.width,
            child: Row(children: [
              Flexible(
                child: Text(col.label, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              if (col.sortable) ...[
                const SizedBox(width: 4),
                Icon(
                  _sortColumnIndex == i
                      ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                      : Icons.unfold_more,
                  size: 14, color: Colors.white70,
                ),
              ],
            ]),
          ),
        ),
        numeric: false,
        onSort: col.sortable
            ? (colIndex, ascending) {
                setState(() {
                  _sortColumnIndex = colIndex;
                  _sortAscending = ascending;
                });
              }
            : null,
      );
    }).toList();
  }

  DataRow _buildDataRow(BuildContext context, int index, Map<String, dynamic> trip) {
    final status = trip['status']?.toString() ?? 'assigned';
    final progress = (trip['progress'] ?? 0).toDouble();
    final isDelayed = trip['isDelayed'] == true;
    Color statusColor = _getStatusColor(status);
    if (isDelayed) statusColor = const Color(0xFFE53935);
    final isEven = index % 2 == 0;

    return DataRow(
      onSelectChanged: (_) {
        // Navigate to trip details when row is clicked
        final tripId = widget.state.extractTripId(trip['_id']);
        if (tripId.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AdminTripDetails(tripId: tripId),
            ),
          );
        }
      },
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) return const Color(0xFFE8F0FE);
        return isEven ? Colors.white : const Color(0xFFF8FAFF);
      }),
      cells: [
        // Trip #
        _cell(110, child: Text(trip['tripNumber'] ?? 'N/A',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)))),
        // Vehicle No.
        _cell(130, child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(child: Text(trip['vehicleNumber'] ?? '—', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
        ])),
        // Vehicle Name
        _cell(140, child: Text(trip['vehicleName']?.toString().isNotEmpty == true ? trip['vehicleName'] : '—',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700), overflow: TextOverflow.ellipsis)),
        // Driver Name
        _cell(150, child: Row(children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: const Color(0xFF0D47A1).withOpacity(0.12),
            child: Text(
              (trip['driverName']?.toString() ?? 'U').substring(0, 1).toUpperCase(),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(trip['driverName'] ?? '—',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
        ])),
        // Driver Phone
        _cell(130, child: Text(trip['driverPhone']?.toString().isNotEmpty == true ? trip['driverPhone'] : '—',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
        // Date
        _cell(120, child: Text(_formatDate(trip['scheduledDate']?.toString()),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        // Time
        _cell(130, child: Text('${trip['startTime'] ?? '—'} → ${trip['endTime'] ?? '—'}',
            style: const TextStyle(fontSize: 11))),
        // Customers
        _cell(100, child: _countBadge(trip['customerCount'] ?? 0, const Color(0xFF8E24AA))),
        // Total Stops
        _cell(100, child: _countBadge(trip['totalStops'] ?? 0, const Color(0xFF1E88E5))),
        // Completed
        _cell(100, child: _countBadge(trip['completedStops'] ?? 0, const Color(0xFF43A047))),
        // Cancelled
        _cell(100, child: _countBadge(trip['cancelledStops'] ?? 0,
            (trip['cancelledStops'] ?? 0) > 0 ? const Color(0xFFE53935) : Colors.grey)),
        // Distance
        _cell(120, child: Row(children: [
          const Icon(Icons.route, size: 13, color: Colors.grey),
          const SizedBox(width: 4),
          Text('${(trip['totalDistance'] ?? 0).toStringAsFixed(1)} km', style: const TextStyle(fontSize: 12)),
        ])),
        // Duration
        _cell(120, child: Text(
          trip['totalTime'] != null && trip['totalTime'] != 0 ? '${trip['totalTime']} min' : '—',
          style: const TextStyle(fontSize: 12),
        )),
        // Status badge
        _cell(120, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withOpacity(0.4)),
          ),
          child: Text(_getStatusText(status),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor), textAlign: TextAlign.center),
        )),
        // Progress
        _cell(120, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${progress.toInt()}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor)),
            if (isDelayed)
              const Row(children: [
                Icon(Icons.warning_amber, size: 12, color: Color(0xFFE53935)),
                SizedBox(width: 2),
                Text('Late', style: TextStyle(fontSize: 9, color: Color(0xFFE53935))),
              ]),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              minHeight: 7,
            ),
          ),
        ])),
        // Trip Type
        _cell(110, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(trip['tripType']?.toString().toUpperCase() ?? '—',
              style: TextStyle(fontSize: 10, color: Colors.indigo.shade700, fontWeight: FontWeight.w600)),
        )),
        // Actual Start
        _cell(120, child: Text(_formatTime(trip['actualStartTime']), style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
        // Actual End
        _cell(120, child: Text(_formatTime(trip['actualEndTime']), style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
        // Actions
        _cell(100, child: ElevatedButton(
          onPressed: () {
            final tripId = widget.state.extractTripId(trip['_id']);
            if (tripId.isEmpty) return;
            Navigator.push(context, MaterialPageRoute(builder: (_) => AdminTripDetails(tripId: tripId)));
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D47A1),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
          child: const Text('View', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        )),
      ],
    );
  }

  // ─── Cell helper ──────────────────────────────────────────────────────────
  DataCell _cell(double width, {required Widget child}) {
    return DataCell(SizedBox(width: width, child: child));
  }

  Widget _countBadge(int count, Color color) {
    return Container(
      width: 40,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$count',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
    );
  }

  // ─── Pagination ───────────────────────────────────────────────────────────
  Widget _buildPagination() {
    final s = widget.state;
    final totalPages = s.totalPages;
    final currentPage = s.currentPage;

    // Build page buttons (max 5 visible)
    final pages = <int>[];
    final start = (currentPage - 2).clamp(1, math.max(1, totalPages - 4));
    final end = (start + 4).clamp(1, totalPages);
    for (int i = start.toInt(); i <= end.toInt(); i++) pages.add(i);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Prev
          _pageBtn(Icons.first_page, currentPage > 1, () { s.setState(() => s.currentPage = 1); s.loadTripList(); }),
          const SizedBox(width: 4),
          _pageBtn(Icons.chevron_left, currentPage > 1, () { s.setState(() => s.currentPage--); s.loadTripList(); }),
          const SizedBox(width: 8),
          // Page numbers
          ...pages.map((p) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              onTap: () { s.setState(() => s.currentPage = p); s.loadTripList(); },
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: p == currentPage ? const Color(0xFF0D47A1) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: p == currentPage ? const Color(0xFF0D47A1) : Colors.grey.shade300),
                ),
                alignment: Alignment.center,
                child: Text('$p',
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: p == currentPage ? Colors.white : Colors.grey.shade700,
                    )),
              ),
            ),
          )),
          const SizedBox(width: 8),
          // Next
          _pageBtn(Icons.chevron_right, currentPage < totalPages, () { s.setState(() => s.currentPage++); s.loadTripList(); }),
          const SizedBox(width: 4),
          _pageBtn(Icons.last_page, currentPage < totalPages, () { s.setState(() => s.currentPage = totalPages); s.loadTripList(); }),
          const SizedBox(width: 16),
          Text('${s.totalCount} total', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _pageBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: enabled ? Colors.grey.shade300 : Colors.grey.shade200),
        ),
        child: Icon(icon, size: 18, color: enabled ? Colors.grey.shade700 : Colors.grey.shade300),
      ),
    );
  }
}

// ─── Simple data classes ──────────────────────────────────────────────────────
class _ColumnDef {
  final String key;
  final String label;
  final double width;
  final bool sortable;
  const _ColumnDef({required this.key, required this.label, required this.width, required this.sortable});
}

class _TabItem {
  final String status;
  final String label;
  final IconData icon;
  final Color color;
  const _TabItem(this.status, this.label, this.icon, this.color);
}
