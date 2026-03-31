// lib/features/driver/dashboard/presentation/screens/reports_driver_page.dart
// ✅ UPDATED: TripInfo model now includes 'source' and 'tripType' fields
//             so the UI can show whether a trip came from client_created_trips,
//             trips collection, or roster-assigned-trips.
//             All original code is preserved — only additions made.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/auth/presentation/screens/welcome_screen.dart';
import 'package:abra_fleet/core/services/driver_reports_service.dart';

// Platform-specific imports
import 'package:flutter/foundation.dart';
import 'dart:io' show File;
import 'package:abra_fleet/app/utils/file_download_helper.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

// --- UI Constants ---
const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kWarningColor = Color(0xFFF59E0B);
const Color kDangerColor = Color(0xFFDC2626);
const Color kScaffoldBackgroundColor = Color(0xFFF1F5F9);
const Color kCardBackgroundColor = Colors.white;
const Color kPrimaryTextColor = Color(0xFF1E293B);
const Color kSecondaryTextColor = Color(0xFF64748B);
const Color kSecondaryButtonColor = Color(0xFF4B5563);

// Filter model for trip filters
class TripFilter {
  DateTime? startDate;
  DateTime? endDate;

  bool get isActive => startDate != null;

  void reset() {
    startDate = null;
    endDate = null;
  }
}

class ReportsDriverPage extends StatefulWidget {
  const ReportsDriverPage({Key? key}) : super(key: key);

  @override
  State<ReportsDriverPage> createState() => _ReportsDriverPageState();
}

class _ReportsDriverPageState extends State<ReportsDriverPage> {
  final DriverReportsService _reportsService = DriverReportsService();
  late Future<PerformanceSummary> _performanceSummaryFuture;
  late Future<DailyAnalytics> _dailyAnalyticsFuture;
  late Future<TripsResponse> _filteredTripsFuture;

  late TripFilter _tripFilter;

  @override
  void initState() {
    super.initState();
    _tripFilter = TripFilter();
    _fetchData();
  }

  void _fetchData() {
    setState(() {
      _performanceSummaryFuture = _reportsService.getPerformanceSummary();
      _dailyAnalyticsFuture = _reportsService.getDailyAnalytics();
      _filteredTripsFuture = _reportsService.getFilteredTrips(
        startDate: _tripFilter.startDate,
        endDate: _tripFilter.endDate,
      );
    });
  }

  void _refreshFilteredTrips() {
    setState(() {
      _filteredTripsFuture = _reportsService.getFilteredTrips(
        startDate: _tripFilter.startDate,
        endDate: _tripFilter.endDate,
      );
    });
  }

  Widget _buildLogoutButton(BuildContext context) {
    final authRepository = Provider.of<AuthRepository>(context, listen: false);

    return IconButton(
      icon: const Icon(Icons.logout, color: Colors.white),
      tooltip: 'Logout',
      onPressed: () async {
        final confirmLogout = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm Logout'),
            content: const Text('Are you sure you want to log out?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Logout'),
              ),
            ],
          ),
        );

        if (confirmLogout == true && context.mounted) {
          await authRepository.signOut();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const WelcomeScreen()),
            (Route<dynamic> route) => false,
          );
        }
      },
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => _FilterDialogWidget(
        filter: _tripFilter,
        onApply: () {
          _refreshFilteredTrips();
          Navigator.pop(context);
        },
        onReset: () {
          setState(() {
            _tripFilter.reset();
          });
          _refreshFilteredTrips();
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _handleGenerateReport(String type) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          margin: EdgeInsets.all(32),
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Generating report...', style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final generatedReport = await _reportsService.generateReport(type: type);
      Navigator.pop(context);
      _showReportActionsDialog(generatedReport.reportId);
    } catch (e) {
      Navigator.pop(context);
      _showCenteredMessage('Failed to generate report: $e', isError: true);
    }
  }

  Future<void> _handleGenerateCustomReport() async {
    if (!_tripFilter.isActive) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          margin: EdgeInsets.all(32),
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Generating custom report...', style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final generatedReport = await _reportsService.generateReport(
        startDate: _tripFilter.startDate,
        endDate: _tripFilter.endDate,
      );
      Navigator.pop(context);
      _showReportActionsDialog(generatedReport.reportId);
    } catch (e) {
      Navigator.pop(context);
      _showCenteredMessage('Failed to generate report: $e', isError: true);
    }
  }

  void _showCenteredMessage(String message, {bool isError = false}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? kDangerColor : Colors.green,
              size: 28,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showReportActionsDialog(String reportId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report Generated Successfully'),
        content: const Text('What would you like to do with this report?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('Share'),
            onPressed: () {
              Navigator.pop(context);
              _downloadAndShareFile(reportId);
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.file_download),
            label: const Text('Download'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              _downloadAndOpenFile(reportId);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAndOpenFile(String reportId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          margin: EdgeInsets.all(32),
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Downloading report...', style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      if (kIsWeb) {
        await _downloadFileWeb(reportId, shouldShare: false);
        Navigator.pop(context);
      } else {
        final filePath = await _reportsService.downloadReport(reportId);
        Navigator.pop(context);

        try {
          final file = await File(filePath).readAsBytes();
          final fileName = 'driver_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
          await FileDownloadHelper.downloadFile(file, fileName);
          _showCenteredMessage('Report downloaded and opened successfully!');
        } catch (e) {
          _showCenteredMessage('Downloaded but could not open file: $e', isError: true);
        }
      }
    } catch (e) {
      Navigator.pop(context);
      _showCenteredMessage('Download failed: $e', isError: true);
    }
  }

  Future<void> _downloadAndShareFile(String reportId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          margin: EdgeInsets.all(32),
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Preparing file...', style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      if (kIsWeb) {
        Navigator.pop(context);
        await _downloadFileWeb(reportId, shouldShare: true);
      } else {
        final filePath = await _reportsService.downloadReport(reportId);
        Navigator.pop(context);

        final result = await Share.shareXFiles(
          [XFile(filePath)],
          text: 'Driver Report',
          subject: 'Please find the attached driver report.',
        );

        if (result.status == ShareResultStatus.success) {
          _showCenteredMessage('File shared successfully!');
        }
      }
    } catch (e) {
      Navigator.pop(context);
      _showCenteredMessage('Could not share file: $e', isError: true);
    }
  }

  Future<void> _downloadFileWeb(String reportId, {bool shouldShare = false}) async {
    try {
      final token = await _reportsService.getAuthToken();
      final downloadUrl = '${DriverReportsService.baseUrl}/api/driver/reports/download/$reportId';

      final response = await http.get(
        Uri.parse(downloadUrl),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final fileName = 'driver_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
        await FileDownloadHelper.downloadFile(bytes, fileName);

        if (!shouldShare) {
          _showCenteredMessage('Report downloaded successfully!');
        }
      } else {
        throw Exception('Failed to download file: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kScaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Reports',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: kPrimaryColor,
        elevation: 4.0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh Data',
            onPressed: _fetchData,
          ),
          _buildLogoutButton(context),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFilteredTripsSection(),
            const SizedBox(height: 16),
            _buildPerformanceSummaryCard(),
            const SizedBox(height: 16),
            _buildDailyAnalyticsCard(),
            const SizedBox(height: 16),
            _buildTripReportsCard(),
            const SizedBox(height: 16),
            _buildGeneralReportCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildFilteredTripsSection() {
    return FutureBuilder<TripsResponse>(
      future: _filteredTripsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: Text('No trip data found.'));
        }

        final tripsResponse = snapshot.data!;

        // ✅ FILTER ONLY COMPLETED TRIPS
        final completedTrips = tripsResponse.trips.where((trip) => trip.status == 'completed').toList();

        return Column(
          children: [
            _buildFilterSection(tripsResponse.summary),
            const SizedBox(height: 16),
            _buildTripList(completedTrips), // ✅ Pass only completed trips
          ],
        );
      },
    );
  }

  Widget _buildFilterSection(TripsSummary summary) {
    return Card(
      elevation: 2.0,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      color: kCardBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Trip Filter',
                  style: TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                      color: kPrimaryTextColor),
                ),
                if (_tripFilter.isActive)
                  TextButton.icon(
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Clear', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      _tripFilter.reset();
                      _refreshFilteredTrips();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _showFilterDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 18, color: kPrimaryColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _tripFilter.isActive
                                  ? '${DateFormat.yMMMd().format(_tripFilter.startDate!)} to ${DateFormat.yMMMd().format(_tripFilter.endDate ?? DateTime.now())}'
                                  : 'Select Date Range',
                              style: TextStyle(
                                fontSize: 14,
                                color: _tripFilter.isActive
                                    ? kPrimaryTextColor
                                    : kSecondaryTextColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _showFilterDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Icon(Icons.tune, size: 18),
                ),
              ],
            ),
            if (_tripFilter.isActive) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kPrimaryColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Completed Trips in Period',
                          style: TextStyle(fontSize: 12, color: kSecondaryTextColor),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${summary.completedTrips} Trips',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: kPrimaryColor,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${summary.totalDistance} KM',
                      style: const TextStyle(
                          fontSize: 14,
                          color: kPrimaryColor,
                          fontWeight: FontWeight.bold),
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

  // ✅ TRIP LIST — Shows Trip Number + Date, expandable to show customers + source badge
  Widget _buildTripList(List<TripInfo> trips) {
    if (trips.isEmpty) {
      return _buildCard(
        title: "Completed Trips",
        icon: '🚐',
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Text("No completed trips found."),
          ),
        ),
      );
    }

    return _buildCard(
      title: 'Completed Trips (${trips.length})',
      icon: '🚐',
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: _fetchData,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  minimumSize: const Size(0, 32),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: trips.length,
            itemBuilder: (context, index) {
              final trip = trips[index];
              return _TripExpansionTile(trip: trip);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required String title, required Widget child, String? icon}) {
    return Card(
      elevation: 2.0,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      color: kCardBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) Text(icon, style: const TextStyle(fontSize: 20)),
                if (icon != null) const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 18.0, fontWeight: FontWeight.bold, color: kPrimaryTextColor),
                ),
              ],
            ),
            const SizedBox(height: 15.0),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceSummaryCard() {
    return FutureBuilder(
      future: _performanceSummaryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: Text('No performance data.'));
        }

        final summary = snapshot.data!;

        return _buildCard(
          title: 'Performance Summary',
          icon: '📈',
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _buildStatItem(
                number: summary.scheduledTrips.toString(),
                label: 'Scheduled',
                icon: Icons.schedule,
                color: kWarningColor,
              ),
              _buildStatItem(
                number: summary.completedTrips.toString(),
                label: 'Completed',
                icon: Icons.check_circle,
                color: Colors.green,
              ),
              _buildStatItem(
                number: '${summary.totalDistance.toStringAsFixed(1)} km',
                label: 'Distance',
                icon: Icons.route,
                color: kPrimaryColor,
              ),
              _buildStatItem(
                number: summary.avgRating.toStringAsFixed(1),
                label: 'Rating',
                icon: Icons.star,
                color: Colors.amber,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDailyAnalyticsCard() {
    return FutureBuilder<DailyAnalytics>(
      future: _dailyAnalyticsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: Text('No daily data.'));
        }

        final analytics = snapshot.data!;
        return _buildCard(
          title: 'Today\'s Analytics',
          icon: '📊',
          child: Column(
            children: [
              _buildReadOnlyField(
                label: 'Working Hours Today',
                value: analytics.workingHours,
                icon: Icons.access_time,
              ),
              const SizedBox(height: 12),
              _buildReadOnlyField(
                label: 'Trips Today',
                value: analytics.tripsToday.toString(),
                icon: Icons.local_shipping,
              ),
              const SizedBox(height: 12),
              _buildReadOnlyField(
                label: 'Distance Today',
                value: '${analytics.distanceToday} KM',
                icon: Icons.route,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTripReportsCard() {
    return _buildCard(
      title: 'Generate Reports',
      icon: '📋',
      child: Column(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                children: [
                  _buildStyledButton(
                    onPressed: () => _handleGenerateReport('daily'),
                    text: 'Generate Daily Report',
                    backgroundColor: kPrimaryColor,
                    icon: Icons.description,
                  ),
                  const SizedBox(height: 10),
                  _buildStyledButton(
                    onPressed: () => _handleGenerateReport('weekly'),
                    text: 'Generate Weekly Report',
                    backgroundColor: kSecondaryButtonColor,
                    icon: Icons.calendar_today,
                  ),
                  const SizedBox(height: 10),
                  _buildStyledButton(
                    onPressed: () => _handleGenerateReport('monthly'),
                    text: 'Generate Monthly Report',
                    backgroundColor: kSecondaryButtonColor,
                    icon: Icons.assessment,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralReportCard() {
    return _buildCard(
      title: 'Generate Custom Report',
      icon: '📄',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Use the "Trip Filter" at the top to select a date range, then click the button below to generate a report for that period.',
            style: TextStyle(color: kSecondaryTextColor, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.filter_alt, size: 18),
                  label: const Text('Generate From Filter',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  onPressed: _tripFilter.isActive ? _handleGenerateCustomReport : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade400,
                    padding: const EdgeInsets.symmetric(vertical: 14.0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                    elevation: 2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required String number,
    required String label,
    IconData? icon,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 8.0),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null)
            Icon(icon, size: 28, color: color ?? kPrimaryColor),
          if (icon != null) const SizedBox(height: 5),
          Text(
            number,
            style: TextStyle(
              fontSize: 22.0,
              fontWeight: FontWeight.bold,
              color: color ?? kPrimaryColor,
            ),
          ),
          const SizedBox(height: 3.0),
          Text(
            label,
            style: const TextStyle(fontSize: 11.0, color: kSecondaryTextColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyField({
    required String label,
    required String value,
    IconData? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: kPrimaryColor),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: kPrimaryTextColor,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: value,
          readOnly: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey[200],
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStyledButton({
    required VoidCallback onPressed,
    required String text,
    required Color backgroundColor,
    IconData? icon,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 18),
        label: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
          elevation: 2,
        ),
      ),
    );
  }
}

// ============================================================================
// ✅ UPDATED: Expandable Trip Tile
// Now shows a coloured source badge:
//   🟣 Client Request  (from client_created_trips)
//   🔵 Admin Trip      (from trips collection)
//   🟢 Roster          (from roster-assigned-trips)
// ============================================================================
class _TripExpansionTile extends StatelessWidget {
  final TripInfo trip;

  const _TripExpansionTile({required this.trip});

  /// Return badge colour and label based on the trip source/type
  _BadgeInfo _getBadge() {
    final src = trip.source ?? '';
    final typ = trip.tripType ?? '';

    if (src == 'client_created_trips' || typ == 'client') {
      return _BadgeInfo(
        label: 'Client Request',
        color: Colors.purple.shade100,
        textColor: Colors.purple.shade700,
      );
    } else if (src == 'trips' || typ == 'individual') {
      return _BadgeInfo(
        label: 'Admin Trip',
        color: Colors.blue.shade100,
        textColor: Colors.blue.shade700,
      );
    } else {
      // roster-assigned-trips
      return _BadgeInfo(
        label: 'Roster',
        color: Colors.green.shade100,
        textColor: Colors.green.shade700,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final badge = _getBadge();

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.green,
          child: Icon(Icons.check, color: Colors.white),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                trip.tripNumber,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(width: 8),
            // ✅ Source badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badge.color,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badge.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: badge.textColor,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          trip.startTime != null
              ? DateFormat('MMM dd, yyyy').format(trip.startTime!)
              : 'Date N/A',
          style: const TextStyle(fontSize: 13),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${trip.distance.toStringAsFixed(1)} km',
              style: const TextStyle(fontWeight: FontWeight.bold, color: kPrimaryColor),
            ),
            if (trip.rating != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 14),
                  const SizedBox(width: 2),
                  Text(trip.rating!.toStringAsFixed(1), style: const TextStyle(fontSize: 12)),
                ],
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '👥 Employees/Customers:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  trip.customerName,
                  style: const TextStyle(fontSize: 14, color: kSecondaryTextColor),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 16, color: Colors.green),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Pickup: ${trip.pickupLocation ?? "N/A"}',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.flag, size: 16, color: Colors.red),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Drop: ${trip.dropLocation ?? "Office"}',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge data helper class
class _BadgeInfo {
  final String label;
  final Color color;
  final Color textColor;
  _BadgeInfo({required this.label, required this.color, required this.textColor});
}

/// Filter Dialog Widget (original code preserved)
class _FilterDialogWidget extends StatefulWidget {
  final TripFilter filter;
  final VoidCallback onApply;
  final VoidCallback onReset;

  const _FilterDialogWidget({
    required this.filter,
    required this.onApply,
    required this.onReset,
  });

  @override
  State<_FilterDialogWidget> createState() => _FilterDialogWidgetState();
}

class _FilterDialogWidgetState extends State<_FilterDialogWidget> {
  late DateTime? _startDate;
  late DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _startDate = widget.filter.startDate;
    _endDate = widget.filter.endDate;
  }

  Future<void> _selectDate(bool isStartDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? (_startDate ?? DateTime.now()) : (_endDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Date Range', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Start Date:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            ListTile(
              title: Text(
                _startDate == null ? 'Select Start Date' : DateFormat.yMMMd().format(_startDate!),
              ),
              trailing: const Icon(Icons.calendar_today, size: 20),
              onTap: () => _selectDate(true),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              tileColor: const Color(0xFFF8FAFC),
            ),
            const SizedBox(height: 16),
            const Text('End Date:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            ListTile(
              title: Text(
                _endDate == null ? 'Select End Date (Optional)' : DateFormat.yMMMd().format(_endDate!),
              ),
              trailing: const Icon(Icons.calendar_today, size: 20),
              onTap: () => _selectDate(false),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              tileColor: const Color(0xFFF8FAFC),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onReset();
          },
          child: const Text('Reset', style: TextStyle(color: kWarningColor)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor),
          onPressed: _startDate != null
              ? () {
                  widget.filter.startDate = _startDate;
                  widget.filter.endDate = _endDate;
                  widget.onApply();
                }
              : null,
          child: const Text('Apply', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// Helper extension for capitalizing strings
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) {
      return "";
    }
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}