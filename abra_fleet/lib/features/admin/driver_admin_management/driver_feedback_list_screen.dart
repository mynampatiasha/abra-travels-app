// ============================================================================
// DRIVER FEEDBACK PAGE - Complete Implementation
// ============================================================================
// File: lib/screens/admin/driver_feedback_page.dart
// Features:
// ✅ Two-row filter layout
// ✅ Row 1: Country/State/City filters (from country_state_city_filter.dart)
// ✅ Row 2: Rating filter, Driver search, Search bar
// ✅ Excel Export (working download)
// ✅ PDF Export (working download)
// ✅ All filters work together
// ✅ Refresh button
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_html/html.dart' as html;
import '../../../core/utils/export_helper.dart';
import '../../../core/services/api_service.dart';
import '../widgets/country_state_city_filter.dart';

class DriverFeedbackPage extends StatefulWidget {
  const DriverFeedbackPage({Key? key}) : super(key: key);

  @override
  State<DriverFeedbackPage> createState() => _DriverFeedbackPageState();
}

class _DriverFeedbackPageState extends State<DriverFeedbackPage> {
  // ══════════════════════════════════════════════════════════════════════════
  // API SERVICE INSTANCE
  // ══════════════════════════════════════════════════════════════════════════
  final ApiService _apiService = ApiService();
  
  // ══════════════════════════════════════════════════════════════════════════
  // DATA
  // ══════════════════════════════════════════════════════════════════════════
  List<Map<String, dynamic>> _feedbackList = [];
  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  String? _errorMessage;

  // ══════════════════════════════════════════════════════════════════════════
  // FILTERS
  // ══════════════════════════════════════════════════════════════════════════
  
  // Row 1 Filters (from country_state_city_filter)
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _country;
  String? _state;
  String? _city;
  String? _localArea;

  // Row 2 Filters (feedback-specific)
  String _selectedRating = 'All';
  final List<String> _ratingFilters = ['All', '5', '4', '3', '2', '1'];
  
  String? _selectedDriverId;
  String? _selectedDriverName;
  List<Map<String, dynamic>> _drivers = [];
  
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ══════════════════════════════════════════════════════════════════════════
  // PAGINATION
  // ══════════════════════════════════════════════════════════════════════════
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalFeedback = 0;
  final int _itemsPerPage = 20;

  @override
  void initState() {
    super.initState();
    _loadDrivers();
    _loadFeedback();
    _loadStats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // API CALLS
  // ══════════════════════════════════════════════════════════════════════════

  /// Load all drivers for the driver filter dropdown
  Future<void> _loadDrivers() async {
    try {
      final response = await _apiService.get('/api/admin/drivers');
      if (response['success'] == true) {
        setState(() {
          _drivers = List<Map<String, dynamic>>.from(response['data'] ?? []);
        });
      }
    } catch (e) {
      print('Error loading drivers: $e');
    }
  }

  /// Load feedback with all active filters
  Future<void> _loadFeedback() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Build query parameters
      final queryParams = <String, String>{
        'limit': _itemsPerPage.toString(),
        'skip': ((_currentPage - 1) * _itemsPerPage).toString(),
      };

      // Add rating filter
      if (_selectedRating != 'All') {
        queryParams['rating'] = _selectedRating;
      }

      // Add driver filter
      if (_selectedDriverId != null) {
        queryParams['driverId'] = _selectedDriverId!;
      }

      final response = await _apiService.get(
        '/api/admin/feedback/recent',
        queryParams: queryParams,
      );

      if (response['success'] == true) {
        List<Map<String, dynamic>> allFeedback = 
            List<Map<String, dynamic>>.from(response['data'] ?? []);

        // Apply client-side filters
        allFeedback = _applyClientSideFilters(allFeedback);

        setState(() {
          _feedbackList = allFeedback;
          _totalFeedback = allFeedback.length;
          _totalPages = (_totalFeedback / _itemsPerPage).ceil();
          if (_totalPages == 0) _totalPages = 1;
          _isLoading = false;
        });
      } else {
        throw Exception(response['message'] ?? 'Failed to load feedback');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Load statistics
  Future<void> _loadStats() async {
    try {
      final response = await _apiService.get('/api/admin/feedback/stats');
      if (response['success'] == true) {
        setState(() {
          _stats = response['data'];
        });
      }
    } catch (e) {
      print('Error loading stats: $e');
    }
  }

  /// Apply all client-side filters to feedback list
  List<Map<String, dynamic>> _applyClientSideFilters(
      List<Map<String, dynamic>> feedbackList) {
    var filtered = feedbackList;

    // 1. Date range filter
    if (_fromDate != null || _toDate != null) {
      filtered = filtered.where((feedback) {
        final submittedAt = feedback['submittedAt'];
        if (submittedAt == null) return false;

        DateTime feedbackDate;
        if (submittedAt is String) {
          feedbackDate = DateTime.parse(submittedAt);
        } else if (submittedAt is DateTime) {
          feedbackDate = submittedAt;
        } else {
          return false;
        }

        if (_fromDate != null && feedbackDate.isBefore(_fromDate!)) {
          return false;
        }
        if (_toDate != null &&
            feedbackDate.isAfter(_toDate!.add(const Duration(days: 1)))) {
          return false;
        }

        return true;
      }).toList();
    }

    // 2. Country filter
    if (_country != null && _country!.isNotEmpty) {
      filtered = filtered.where((feedback) {
        final pickupCountry = feedback['pickupLocation']?['country'] ?? '';
        return pickupCountry.toLowerCase() == _country!.toLowerCase();
      }).toList();
    }

    // 3. State filter
    if (_state != null && _state!.isNotEmpty) {
      filtered = filtered.where((feedback) {
        final pickupState = feedback['pickupLocation']?['state'] ?? '';
        return pickupState.toLowerCase() == _state!.toLowerCase();
      }).toList();
    }

    // 4. City filter
    if (_city != null && _city!.isNotEmpty) {
      filtered = filtered.where((feedback) {
        final pickupCity = feedback['pickupLocation']?['city'] ?? '';
        return pickupCity.toLowerCase() == _city!.toLowerCase();
      }).toList();
    }

    // 5. Local area filter
    if (_localArea != null && _localArea!.isNotEmpty) {
      filtered = filtered.where((feedback) {
        final pickupAddress = feedback['pickupLocation']?['address'] ?? '';
        return pickupAddress.toLowerCase().contains(_localArea!.toLowerCase());
      }).toList();
    }

    // 6. Search query filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((feedback) {
        final customerName = (feedback['customerName'] ?? '').toLowerCase();
        final driverName = (feedback['driverName'] ?? '').toLowerCase();
        final tripNumber = (feedback['tripNumber'] ?? '').toLowerCase();
        final feedbackText = (feedback['feedback'] ?? '').toLowerCase();

        return customerName.contains(_searchQuery) ||
            driverName.contains(_searchQuery) ||
            tripNumber.contains(_searchQuery) ||
            feedbackText.contains(_searchQuery);
      }).toList();
    }

    return filtered;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FILTER HANDLERS
  // ══════════════════════════════════════════════════════════════════════════

  /// Called when country/state/city filters change
  void _onLocationFilterApplied(Map<String, dynamic> filters) {
    setState(() {
      _fromDate = filters['fromDate'];
      _toDate = filters['toDate'];
      _country = filters['country'];
      _state = filters['state'];
      _city = filters['city'];
      _localArea = filters['localArea'];
      _currentPage = 1;
    });
    _loadFeedback();
  }

  /// Filter by rating
  void _filterByRating(String rating) {
    setState(() {
      _selectedRating = rating;
      _currentPage = 1;
    });
    _loadFeedback();
  }

  /// Filter by driver
  void _filterByDriver(String? driverId, String? driverName) {
    setState(() {
      _selectedDriverId = driverId;
      _selectedDriverName = driverName;
      _currentPage = 1;
    });
    _loadFeedback();
  }

  /// Clear all filters
  void _clearAllFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _country = null;
      _state = null;
      _city = null;
      _localArea = null;
      _selectedRating = 'All';
      _selectedDriverId = null;
      _selectedDriverName = null;
      _searchQuery = '';
      _searchController.clear();
      _currentPage = 1;
    });
    _loadFeedback();
  }

  /// Refresh data
  Future<void> _refreshData() async {
    await Future.wait([
      _loadFeedback(),
      _loadStats(),
    ]);
    _showSuccessSnackbar('Data refreshed successfully');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EXPORT FUNCTIONS
  // ══════════════════════════════════════════════════════════════════════════

  /// Export to Excel - Frontend only (no backend required)
  Future<void> _exportToExcel() async {
    try {
      if (_feedbackList.isEmpty) {
        _showErrorSnackbar('No feedback data to export');
        return;
      }

      _showSuccessSnackbar('Preparing Excel export...');

      // Prepare data for export
      List<List<dynamic>> csvData = [
        // Headers
        [
          'Date',
          'Trip Number',
          'Customer Name',
          'Customer Email',
          'Customer Phone',
          'Driver Name',
          'Driver Email',
          'Driver Phone',
          'Vehicle Number',
          'Rating',
          'Feedback',
          'Ride Again',
          'Pickup Location',
          'Drop Location',
          'Trip ID',
        ],
      ];

      print('📊 Exporting ${_feedbackList.length} feedback entries...');

      // Add data rows
      for (var feedback in _feedbackList) {
        final submittedAt = feedback['submittedAt'];
        String dateStr = '';
        if (submittedAt != null) {
          try {
            final date = submittedAt is String
                ? DateTime.parse(submittedAt)
                : submittedAt as DateTime;
            dateStr = DateFormat('dd/MM/yyyy').format(date);
          } catch (e) {
            dateStr = submittedAt.toString();
          }
        }

        final pickupLocation = feedback['pickupLocation'];
        final dropLocation = feedback['dropLocation'];

        String pickupAddress = '';
        if (pickupLocation != null) {
          pickupAddress =
              '${pickupLocation['address'] ?? ''}, ${pickupLocation['city'] ?? ''}, ${pickupLocation['state'] ?? ''}, ${pickupLocation['country'] ?? ''}';
        }

        String dropAddress = '';
        if (dropLocation != null) {
          dropAddress =
              '${dropLocation['address'] ?? ''}, ${dropLocation['city'] ?? ''}, ${dropLocation['state'] ?? ''}, ${dropLocation['country'] ?? ''}';
        }

        csvData.add([
          dateStr,
          feedback['tripNumber'] ?? '',
          feedback['customerName'] ?? '',
          feedback['customerEmail'] ?? '',
          feedback['customerPhone'] ?? '',
          feedback['driverName'] ?? '',
          feedback['driverEmail'] ?? '',
          feedback['driverPhone'] ?? '',
          feedback['vehicleNumber'] ?? '',
          feedback['rating']?.toString() ?? '',
          feedback['feedback'] ?? '',
          feedback['rideAgain'] ?? 'not_specified',
          pickupAddress,
          dropAddress,
          feedback['tripId']?.toString() ?? '',
        ]);
      }

      // ✅ Frontend-only export using ExportHelper
      // This works exactly like invoices_list_page.dart - no backend needed
      await ExportHelper.exportToExcel(
        data: csvData,
        filename: 'driver_feedback_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
      );

      _showSuccessSnackbar(
          '✅ Excel file downloaded with ${_feedbackList.length} feedback entries!');
    } catch (e) {
      print('❌ Export Error: $e');
      _showErrorSnackbar('Failed to export: $e');
    }
  }

  /// Export to PDF - Uses backend for PDF generation with frontend data
  Future<void> _exportToPDF() async {
    try {
      if (_feedbackList.isEmpty) {
        _showErrorSnackbar('No feedback data to export');
        return;
      }

      _showSuccessSnackbar('Preparing PDF export...');

      // Build query parameters based on active filters
      final queryParams = <String, String>{};

      if (_fromDate != null) {
        queryParams['startDate'] = _fromDate!.toIso8601String();
      }
      if (_toDate != null) {
        queryParams['endDate'] = _toDate!.toIso8601String();
      }
      if (_selectedRating != 'All') {
        queryParams['rating'] = _selectedRating;
      }
      if (_selectedDriverId != null) {
        queryParams['driverId'] = _selectedDriverId!;
      }

      // Build URL with query parameters
      final baseUrl = _apiService.baseUrl;
      String pdfUrl = '$baseUrl/api/admin/feedback/export-pdf';
      
      if (queryParams.isNotEmpty) {
        final queryString = queryParams.entries
            .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
            .join('&');
        pdfUrl += '?$queryString';
      }

      print('📄 Requesting PDF from: $pdfUrl');

      if (kIsWeb) {
        // For web, open in new tab or download
        html.AnchorElement(href: pdfUrl)
          ..setAttribute('download',
              'driver_feedback_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf')
          ..setAttribute('target', '_blank')
          ..click();

        _showSuccessSnackbar('✅ PDF download started!');
      } else {
        // For mobile/desktop
        final uri = Uri.parse(pdfUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          _showSuccessSnackbar('✅ PDF opened successfully!');
        } else {
          throw 'Could not launch PDF viewer';
        }
      }
    } catch (e) {
      print('❌ PDF Export Error: $e');
      _showErrorSnackbar('Failed to export PDF: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UI HELPERS
  // ══════════════════════════════════════════════════════════════════════════

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

  bool get _hasFilters =>
      _fromDate != null ||
      _toDate != null ||
      (_country?.isNotEmpty ?? false) ||
      (_state?.isNotEmpty ?? false) ||
      (_city?.isNotEmpty ?? false) ||
      (_localArea?.isNotEmpty ?? false) ||
      _selectedRating != 'All' ||
      _selectedDriverId != null ||
      _searchQuery.isNotEmpty;

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildTopBar(),
            if (_stats != null) _buildStatsCards(),
            _buildFilterRow1(), // Country/State/City filters
            const SizedBox(height: 12),
            _buildFilterRow2(), // Rating, Driver, Search filters
            const SizedBox(height: 16),
            _isLoading
                ? const SizedBox(
                    height: 400,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _errorMessage != null
                    ? SizedBox(height: 400, child: _buildErrorState())
                    : _feedbackList.isEmpty
                        ? SizedBox(height: 400, child: _buildEmptyState())
                        : _buildFeedbackTable(),
            if (!_isLoading && _feedbackList.isNotEmpty) _buildPagination(),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TOP BAR
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        children: [
          // Back Arrow
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 24),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
          const SizedBox(width: 8),

          // Title
          const Text(
            'Driver Feedback Management',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50),
            ),
          ),

          const Spacer(),

          // Refresh Button
          IconButton(
            icon: const Icon(Icons.refresh, size: 24),
            onPressed: _isLoading ? null : _refreshData,
            tooltip: 'Refresh',
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey[200],
              padding: const EdgeInsets.all(12),
            ),
          ),

          const SizedBox(width: 12),

          // Clear All Filters Button
          if (_hasFilters)
            ElevatedButton.icon(
              onPressed: _clearAllFilters,
              icon: const Icon(Icons.clear_all, size: 18),
              label: const Text('Clear All Filters'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),

          const SizedBox(width: 12),

          // Export to Excel Button
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _exportToExcel,
            icon: const Icon(Icons.table_chart, size: 20),
            label: const Text('Export Excel'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27AE60),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Export to PDF Button
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _exportToPDF,
            icon: const Icon(Icons.picture_as_pdf, size: 20),
            label: const Text('Export PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE74C3C),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STATS CARDS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildStatsCards() {
    final overall = _stats?['overall'];
    if (overall == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        children: [
          _buildStatCard(
            'Total Feedback',
            overall['totalFeedback']?.toString() ?? '0',
            Icons.feedback,
            Colors.blue,
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            'Average Rating',
            '${overall['averageRating']?.toStringAsFixed(2) ?? '0.0'} / 5.0',
            Icons.star,
            Colors.amber,
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            '5 Star Ratings',
            overall['rating5Stars']?.toString() ?? '0',
            Icons.star,
            Colors.green,
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            '1 Star Ratings',
            overall['rating1Stars']?.toString() ?? '0',
            Icons.star_border,
            Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FILTER ROW 1 - Country/State/City Filters
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildFilterRow1() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: CountryStateCityFilter(
        onFilterApplied: _onLocationFilterApplied,
        initialFromDate: _fromDate,
        initialToDate: _toDate,
        initialCountry: _country,
        initialState: _state,
        initialCity: _city,
        initialLocalArea: _localArea,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FILTER ROW 2 - Rating, Driver, Search
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildFilterRow2() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Rating Filter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star, size: 18, color: Color(0xFF2563EB)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _selectedRating,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.arrow_drop_down),
                  items: _ratingFilters.map((rating) {
                    return DropdownMenuItem(
                      value: rating,
                      child: Text(
                        rating == 'All'
                            ? 'All Ratings'
                            : '$rating ${rating == '1' ? 'Star' : 'Stars'}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) _filterByRating(value);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Driver Filter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person, size: 18, color: Color(0xFF2563EB)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _selectedDriverId,
                  hint: const Text('All Drivers',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  underline: const SizedBox(),
                  icon: const Icon(Icons.arrow_drop_down),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('All Drivers',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    ..._drivers.map((driver) {
                      final driverId = driver['_id']?.toString() ?? '';
                      final driverName =
                          driver['personalInfo']?['name'] ??
                          driver['name'] ??
                          'Unknown';
                      return DropdownMenuItem(
                        value: driverId,
                        child: Text(
                          driverName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                  onChanged: (value) {
                    String? driverName;
                    if (value != null) {
                      final driver = _drivers.firstWhere(
                        (d) => d['_id']?.toString() == value,
                        orElse: () => {},
                      );
                      driverName = driver['personalInfo']?['name'] ??
                          driver['name'] ??
                          'Unknown';
                    }
                    _filterByDriver(value, driverName);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Search Bar
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by customer, driver, trip number, or feedback...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                          _loadFeedback();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
              onSubmitted: (value) {
                _loadFeedback();
              },
            ),
          ),

          const SizedBox(width: 12),

          // Search Button
          ElevatedButton.icon(
            onPressed: _loadFeedback,
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Search'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FEEDBACK TABLE
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildFeedbackTable() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF34495E),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                _buildHeaderCell('DATE', flex: 2),
                _buildHeaderCell('TRIP#', flex: 2),
                _buildHeaderCell('CUSTOMER', flex: 3),
                _buildHeaderCell('DRIVER', flex: 3),
                _buildHeaderCell('RATING', flex: 1),
                _buildHeaderCell('FEEDBACK', flex: 4),
                _buildHeaderCell('ACTIONS', flex: 2),
              ],
            ),
          ),

          // Table Rows
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _feedbackList.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: Colors.grey[200],
            ),
            itemBuilder: (context, index) {
              return _buildFeedbackRow(_feedbackList[index]);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildFeedbackRow(Map<String, dynamic> feedback) {
    final submittedAt = feedback['submittedAt'];
    String dateStr = '';
    if (submittedAt != null) {
      try {
        final date = submittedAt is String
            ? DateTime.parse(submittedAt)
            : submittedAt as DateTime;
        dateStr = DateFormat('dd/MM/yyyy').format(date);
      } catch (e) {
        dateStr = submittedAt.toString();
      }
    }

    final rating = feedback['rating'] ?? 0;
    final customerName = feedback['customerName'] ?? 'Unknown';
    final driverName = feedback['driverName'] ?? 'Unknown';
    final tripNumber = feedback['tripNumber'] ?? '-';
    final feedbackText = feedback['feedback'] ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date
          Expanded(
            flex: 2,
            child: Text(
              dateStr,
              style: const TextStyle(fontSize: 13),
            ),
          ),

          // Trip Number
          Expanded(
            flex: 2,
            child: Text(
              tripNumber,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3498DB),
              ),
            ),
          ),

          // Customer
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customerName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (feedback['customerEmail'] != null)
                  Text(
                    feedback['customerEmail'],
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),

          // Driver
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  driverName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (feedback['vehicleNumber'] != null)
                  Text(
                    feedback['vehicleNumber'],
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),

          // Rating
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Icon(
                  Icons.star,
                  size: 16,
                  color: _getRatingColor(rating),
                ),
                const SizedBox(width: 4),
                Text(
                  rating.toString(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _getRatingColor(rating),
                  ),
                ),
              ],
            ),
          ),

          // Feedback
          Expanded(
            flex: 4,
            child: Text(
              feedbackText,
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Actions
          Expanded(
            flex: 2,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.visibility, size: 18),
                  onPressed: () => _viewFeedbackDetails(feedback),
                  tooltip: 'View Details',
                  color: const Color(0xFF3498DB),
                ),
                IconButton(
                  icon: const Icon(Icons.reply, size: 18),
                  onPressed: () => _replyToFeedback(feedback),
                  tooltip: 'Reply',
                  color: const Color(0xFF27AE60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getRatingColor(int rating) {
    if (rating >= 4) return Colors.green;
    if (rating == 3) return Colors.orange;
    return Colors.red;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ══════════════════════════════════════════════════════════════════════════

  void _viewFeedbackDetails(Map<String, dynamic> feedback) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Feedback Details'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('Trip Number', feedback['tripNumber']),
                _buildDetailRow('Customer', feedback['customerName']),
                _buildDetailRow('Driver', feedback['driverName']),
                _buildDetailRow('Rating', '${feedback['rating']} / 5'),
                _buildDetailRow('Feedback', feedback['feedback']),
                if (feedback['rideAgain'] != null)
                  _buildDetailRow('Ride Again', feedback['rideAgain']),
                if (feedback['adminReply'] != null) ...[
                  const Divider(height: 24),
                  const Text(
                    'Admin Reply:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(feedback['adminReply']['message'] ?? ''),
                  Text(
                    'By: ${feedback['adminReply']['repliedBy']} on ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(feedback['adminReply']['repliedAt']))}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
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

  Widget _buildDetailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(value?.toString() ?? '-'),
          ),
        ],
      ),
    );
  }

  void _replyToFeedback(Map<String, dynamic> feedback) {
    final replyController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reply to Feedback'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Customer: ${feedback['customerName']}'),
              Text('Rating: ${feedback['rating']} / 5'),
              const SizedBox(height: 8),
              Text(
                'Feedback: ${feedback['feedback']}',
                style: TextStyle(color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: replyController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Your Reply',
                  border: OutlineInputBorder(),
                  hintText: 'Enter your reply to the customer...',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (replyController.text.trim().isEmpty) {
                _showErrorSnackbar('Please enter a reply');
                return;
              }

              try {
                final feedbackId = feedback['_id'];
                final response = await _apiService.post(
                  '/api/admin/feedback/$feedbackId/reply',
                  body: {'reply': replyController.text.trim()},
                );

                if (response['success'] == true) {
                  Navigator.pop(context);
                  _showSuccessSnackbar('Reply sent successfully');
                  _refreshData();
                } else {
                  throw Exception(response['message'] ?? 'Failed to send reply');
                }
              } catch (e) {
                _showErrorSnackbar('Failed to send reply: $e');
              }
            },
            child: const Text('Send Reply'),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PAGINATION
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${(_currentPage - 1) * _itemsPerPage + 1} - ${(_currentPage * _itemsPerPage).clamp(0, _totalFeedback)} of $_totalFeedback',
            style: TextStyle(color: Colors.grey[700]),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 1
                    ? () {
                        setState(() {
                          _currentPage--;
                        });
                        _loadFeedback();
                      }
                    : null,
              ),
              ...List.generate(
                _totalPages.clamp(0, 5),
                (index) {
                  final pageNum = index + 1;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _currentPage = pageNum;
                        });
                        _loadFeedback();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _currentPage == pageNum
                              ? const Color(0xFF3498DB)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          pageNum.toString(),
                          style: TextStyle(
                            color: _currentPage == pageNum
                                ? Colors.white
                                : Colors.grey[700],
                            fontWeight: _currentPage == pageNum
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < _totalPages
                    ? () {
                        setState(() {
                          _currentPage++;
                        });
                        _loadFeedback();
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EMPTY & ERROR STATES
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.feedback_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No feedback found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _hasFilters
                ? 'Try adjusting your filters'
                : 'No feedback has been submitted yet',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text(
            'Error Loading Feedback',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Unknown error',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _refreshData,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// Typedef for backward compatibility
typedef DriverFeedbackListScreen = DriverFeedbackPage;
