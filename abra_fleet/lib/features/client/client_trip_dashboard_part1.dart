// lib/features/client/presentation/screens/client_trip_dashboard_part1.dart
// ============================================================================
// CLIENT TRIP DASHBOARD - PART 1 OF 2
// ============================================================================
// Contains: State, API calls, Charts (Pie + Bar), Filter panel, Summary cards
// Part 2:   Trip table (all statuses), pagination, utilities
// ============================================================================
// ✅ AUTO-FILTERS BY CLIENT DOMAIN - No manual domain filter needed
// ✅ Enhanced table with larger fonts (Headers: 14px, Data: 13px, better spacing)
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
import 'client_trip_dashboard_part2.dart';

// ✅ Import the country/state/city filter widget
import 'package:abra_fleet/features/admin/widgets/country_state_city_filter.dart';

// ============================================================================
// MAIN WIDGET
// ============================================================================
class ClientTripDashboard extends StatefulWidget {
  const ClientTripDashboard({super.key});
  static const String routeName = '/client/trip-dashboard';

  @override
  State<ClientTripDashboard> createState() => ClientTripDashboardState();
}

// ============================================================================
// STATE CLASS  (public so Part 2 mixin can access)
// ============================================================================
class ClientTripDashboardState extends State<ClientTripDashboard> {
  // ─── Summary / trips data ─────────────────────────────────────────────────
  Map<String, dynamic> summary = {};
  List<Map<String, dynamic>> trips = [];

  String selectedStatus = 'all';

  final TextEditingController searchController = TextEditingController();
  final TextEditingController manualLocationController = TextEditingController();

  DateTime? fromDate;
  DateTime? toDate;

  // Location cascade
  String? selectedCountry;
  String? selectedState;
  String? selectedCity;
  List<String> countryOptions = [];
  List<String> stateOptions = [];
  List<String> cityOptions = [];

  bool isLoadingSummary = true;
  bool isLoadingTrips = true;
  bool isLoadingLocations = false;
  bool isGeneratingReport = false;
  String? errorMessage;

  int currentPage = 1;
  final int itemsPerPage = 20;
  int totalPages = 1;
  int totalCount = 0;

  bool isFiltersExpanded = false;

  // ✅ Client-specific: domain info
  String? clientDomain;
  String? clientOrgName;

  // ─── Token helper ─────────────────────────────────────────────────────────
  Future<String?> getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (_) {
      return null;
    }
  }

  // ✅ Load client info (domain) from SharedPreferences
  Future<void> _loadClientInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataRaw = prefs.getString('user_data');
      
      if (userDataRaw != null) {
        final userData = json.decode(userDataRaw);
        final email = userData['email'] ?? '';
        
        if (email.contains('@')) {
          setState(() {
            clientDomain = email.split('@')[1].toLowerCase();
            clientOrgName = userData['organizationName'] ?? 
                           userData['companyName'] ?? 
                           userData['name'] ?? 
                           'Your Organization';
          });
          
          debugPrint('✅ Client domain loaded: $clientDomain');
          debugPrint('✅ Client org: $clientOrgName');
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading client info: $e');
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
      manualLocationController.text.trim().isNotEmpty ||
      searchController.text.trim().isNotEmpty;

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
  // API METHODS - ✅ USING CLIENT ENDPOINTS
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

      // ✅ CLIENT ENDPOINT
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/client/trips/dashboard')
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
          
          debugPrint('✅ Dashboard summary loaded for domain: ${summary['domain']}');
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
      if (manualLocationController.text.trim().isNotEmpty) {
        params['locationSearch'] = manualLocationController.text.trim();
      }

      // ✅ CLIENT ENDPOINT (no domain param needed - auto-filtered)
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/client/trips/list')
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
          
          debugPrint('✅ Loaded ${trips.length} trips for domain: ${data['data']['filters']['domain']}');
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

  Future<void> loadCountryOptions() async {
    try {
      setState(() => isLoadingLocations = true);
      final token = await getToken();
      if (token == null) return;
      
      // ✅ Use admin endpoint (location options are not domain-specific)
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/trips/locations/countries'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() => countryOptions = List<String>.from(data['data'] ?? []));
        }
      }
    } catch (e) {
      debugPrint('Error loading countries: $e');
    } finally {
      setState(() => isLoadingLocations = false);
    }
  }

  Future<void> loadStateOptions(String country) async {
    try {
      setState(() {
        isLoadingLocations = true;
        stateOptions = [];
        cityOptions = [];
        selectedState = null;
        selectedCity = null;
      });
      final token = await getToken();
      if (token == null) return;
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/trips/locations/states?country=${Uri.encodeComponent(country)}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() => stateOptions = List<String>.from(data['data'] ?? []));
        }
      }
    } catch (e) {
      debugPrint('Error loading states: $e');
    } finally {
      setState(() => isLoadingLocations = false);
    }
  }

  Future<void> loadCityOptions(String country, String state) async {
    try {
      setState(() {
        isLoadingLocations = true;
        cityOptions = [];
        selectedCity = null;
      });
      final token = await getToken();
      if (token == null) return;
      final response = await http.get(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/admin/trips/locations/cities?country=${Uri.encodeComponent(country)}&state=${Uri.encodeComponent(state)}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() => cityOptions = List<String>.from(data['data'] ?? []));
        }
      }
    } catch (e) {
      debugPrint('Error loading cities: $e');
    } finally {
      setState(() => isLoadingLocations = false);
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
      stateOptions = [];
      cityOptions = [];
      searchController.clear();
      manualLocationController.clear();
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
    return parts.isEmpty ? 'All Trips - $clientOrgName' : parts.join(', ');
  }

  // ✅ NEW: Export Buttons Row (PDF, Excel, WhatsApp) - Horizontal Layout
  Widget _buildExportButtonsRow() {
    return Row(
      children: [
        // PDF Download Button
        Expanded(
          child: _buildExportButton(
            icon: Icons.picture_as_pdf,
            label: 'Generate PDF',
            color: Colors.red,
            onPressed: isGeneratingReport ? null : generatePDFReport,
          ),
        ),
        const SizedBox(width: 8),
        
        // Excel Export Button
        Expanded(
          child: _buildExportButton(
            icon: Icons.table_chart,
            label: 'Generate Excel',
            color: const Color(0xFF27AE60),
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
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  // ✅ NEW: Excel Export
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
        filename: 'client_trip_dashboard_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
      );

      _showSuccessSnackbar('✅ Excel file downloaded with ${trips.length} trips!');
    } catch (e) {
      print('❌ Excel Export Error: $e');
      _showErrorSnackbar('Failed to export Excel: $e');
    } finally {
      if (mounted) setState(() => isGeneratingReport = false);
    }
  }

  // ✅ NEW: PDF Report (using existing generateReport method)
  Future<void> generatePDFReport() async {
    await generateReport();
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
      message += '🏢 *Organization:* ${clientOrgName ?? "Your Company"}\n';
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

  Future<void> generateReport() async {
    if (trips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No trips to generate report for'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => isGeneratingReport = true);
    try {
      final token = await getToken();
      if (token == null) throw Exception('No auth token');
      final params = <String, String>{'status': selectedStatus};
      if (fromDate != null) params['fromDate'] = DateFormat('yyyy-MM-dd').format(fromDate!);
      if (toDate != null) params['toDate'] = DateFormat('yyyy-MM-dd').format(toDate!);
      if (selectedCountry != null && selectedCountry!.isNotEmpty) params['country'] = selectedCountry!;
      if (selectedState != null && selectedState!.isNotEmpty) params['state'] = selectedState!;
      if (selectedCity != null && selectedCity!.isNotEmpty) params['city'] = selectedCity!;
      if (searchController.text.trim().isNotEmpty) params['search'] = searchController.text.trim();
      if (manualLocationController.text.trim().isNotEmpty) params['locationSearch'] = manualLocationController.text.trim();

      // ✅ CLIENT ENDPOINT
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/client/trips/bulk-report').replace(queryParameters: params);
      final response = await http.get(uri, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report failed: $e'), backgroundColor: Colors.red),
        );
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

  // ============================================================================
  // LIFECYCLE
  // ============================================================================
  @override
  void initState() {
    super.initState();
    _loadClientInfo();
    loadDashboardSummary();
    loadTripList();
    loadCountryOptions();
  }

  @override
  void dispose() {
    searchController.dispose();
    manualLocationController.dispose();
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
        onPressed: () {
          Navigator.of(context).pop();
        },
        tooltip: 'Back to Dashboard',
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Trip Management', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          if (clientOrgName != null)
            Text(clientOrgName!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
        ],
      ),
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

  // ─── Filter toggle, panel, status cards, charts (same as admin) ───────────
  // (Copy from admin_trip_dashboard_part1.dart - lines 400-900)
  // ✅ REMOVE domain filter field from _buildFilterPanel()
  
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

  // ✅ FILTER PANEL WITH COUNTRY/STATE/CITY FILTER + EXPORT BUTTONS
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
            initialLocalArea: manualLocationController.text,
            onFilterApplied: (filters) {
              setState(() {
                fromDate = filters['fromDate'] as DateTime?;
                toDate = filters['toDate'] as DateTime?;
                selectedCountry = filters['country'] as String?;
                selectedState = filters['state'] as String?;
                selectedCity = filters['city'] as String?;
                final localArea = filters['localArea'] as String?;
                if (localArea != null) {
                  manualLocationController.text = localArea;
                }
                currentPage = 1;
              });
              loadTripList();
            },
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),

          // ✅ ROW 2: Search + Export Buttons
          Row(
            children: [
              // Search field
              Expanded(
                flex: 3,
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
              
              // Export buttons (PDF, Excel, WhatsApp)
              Expanded(
                flex: 4,
                child: _buildExportButtonsRow(),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Clear All button (if filters active)
          if (hasActiveFilters)
            OutlinedButton.icon(
              onPressed: clearAllFilters,
              icon: const Icon(Icons.clear_all, size: 18),
              label: const Text('Clear All Filters'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red, 
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
        ],
      ),
    );
  }

  // ✅ Copy status cards, charts, summary cards from admin (lines 550-850)
  // (Same implementation - no changes needed)
  
  Widget _buildStatusCards() {
    // ... (copy from admin_trip_dashboard_part1.dart lines 550-620)
    final total = (summary['total'] ?? 0) as int;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const Text('Trip Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                if (clientOrgName != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      clientOrgName!,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0891B2)),
                    ),
                  ),
                ],
              ],
            ),
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

  // Charts row, summary stats cards - same as admin
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
    // ... (copy from admin lines 670-730)
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
    // ... (copy from admin lines 732-800)
    final vehicles = (summary['totalVehicles'] ?? 0) as int;
    final drivers = (summary['totalDrivers'] ?? 0) as int;
    final customers = (summary['totalCustomers'] ?? 0) as int;
    final delayed = (summary['delayed'] ?? 0) as int;

    final maxVal = [vehicles, drivers, customers, delayed].reduce((a, b) => a > b ? a : b).toDouble();

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
    // ... (copy from admin lines 802-850)
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

  // ─── Helper widgets ───────────────────────────────────────────────────────
  Widget _buildDateButton(String label, DateTime? date, VoidCallback onTap) {
    // ... (copy from admin lines 900-930)
    final hasDate = date != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: hasDate ? const Color(0xFFE8EFF9) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: hasDate ? const Color(0xFF0D47A1) : Colors.grey.shade300, width: hasDate ? 1.5 : 1),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today, size: 16, color: hasDate ? const Color(0xFF0D47A1) : Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasDate ? DateFormat('MMM dd, yyyy').format(date) : label,
              style: TextStyle(fontSize: 12, fontWeight: hasDate ? FontWeight.w600 : FontWeight.normal,
                  color: hasDate ? const Color(0xFF0D47A1) : Colors.grey.shade500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasDate)
            GestureDetector(
              onTap: () {
                setState(() {
                  if (label.contains('From')) fromDate = null; else toDate = null;
                  currentPage = 1;
                });
                loadTripList();
              },
              child: const Icon(Icons.close, size: 14, color: Color(0xFF0D47A1)),
            ),
        ]),
      ),
    );
  }

  Widget _buildLocationDropdown({
    required String label, required IconData icon, required String? value,
    required List<String> items, required ValueChanged<String?> onChanged,
    required VoidCallback onClear, bool isLoading = false, bool enabled = true,
  }) {
    // ... (copy from admin lines 932-980)
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value != null ? const Color(0xFF0D47A1) : enabled ? Colors.grey.shade400 : Colors.grey.shade200,
          width: value != null ? 1.5 : 1,
        ),
        color: !enabled ? Colors.grey.shade200 : Colors.white,
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: isLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon, size: 18, color: enabled ? (value != null ? const Color(0xFF0D47A1) : Colors.grey.shade700) : Colors.grey.shade400),
          ),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                hint: Text(label, style: TextStyle(color: enabled ? Colors.grey.shade700 : Colors.grey.shade400, fontSize: 13)),
                isExpanded: true,
                icon: Icon(Icons.arrow_drop_down, size: 22, color: enabled ? Colors.grey.shade800 : Colors.grey.shade400),
                style: TextStyle(color: enabled ? Colors.black87 : Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w600),
                items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                onChanged: enabled ? onChanged : null,
                disabledHint: Text(value ?? label, style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
              ),
            ),
          ),
          if (value != null && enabled)
            GestureDetector(
              onTap: onClear,
              child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.close, size: 16, color: Color(0xFF0D47A1))),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionDivider(String text) {
    // ... (copy from admin lines 982-995)
    return Row(children: [
      Expanded(child: Divider(color: Colors.grey.shade300)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
      ),
      Expanded(child: Divider(color: Colors.grey.shade300)),
    ]);
  }

  Widget _buildActiveFiltersBanner() {
    // ... (copy from admin lines 997-1030)
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
          if (selectedCountry != null) _filterChip('🌍 $selectedCountry', () { setState(() { selectedCountry = null; selectedState = null; selectedCity = null; stateOptions = []; cityOptions = []; currentPage = 1; }); loadTripList(); }),
          if (selectedState != null) _filterChip('📍 $selectedState', () { setState(() { selectedState = null; selectedCity = null; cityOptions = []; currentPage = 1; }); loadTripList(); }),
          if (selectedCity != null) _filterChip('🏙️ $selectedCity', () { setState(() { selectedCity = null; currentPage = 1; }); loadTripList(); }),
          if (manualLocationController.text.isNotEmpty) _filterChip('📝 "${manualLocationController.text}"', () { manualLocationController.clear(); setState(() => currentPage = 1); loadTripList(); }),
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

  // ─── Trip table section (delegates to Part 2) ─────────────────────────────
  Widget _buildTripTableSection() {
    return _TripTableBuilder(state: this).build(context);
  }
}

// ============================================================================
// PIE CHART PAINTER (same as admin)
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
// DELEGATION CLASS (used by Part 1 to delegate table building to Part 2)
// ============================================================================
class _TripTableBuilder {
  final ClientTripDashboardState state;
  const _TripTableBuilder({required this.state});

  Widget build(BuildContext context) {
    return _TripTableWidget(state: state);
  }
}

// ============================================================================
// TRIP TABLE WIDGET - minimal scaffold (full implementation in Part 2)
// ============================================================================
// ============================================================================
// TRIP TABLE WIDGET - delegates to Part 2's enhanced table
// ============================================================================
class _TripTableWidget extends StatelessWidget {
  final ClientTripDashboardState state;
  const _TripTableWidget({required this.state});

  @override
  Widget build(BuildContext context) {
    return TripTableSectionEnhanced(state: state);
  }
}
