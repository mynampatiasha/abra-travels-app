// File: lib/features/admin/customer_management/admin_pending_customers.dart
// ✅ REDESIGNED VERSION - Matches All Customers (hr-appraisal.php) UI
//
// Features:
// - Navy gradient AppBar with back button
// - Stat cards (Total Pending, Registered Today, Awaiting 7+ Days, Approved Today)
// - CountryStateCityFilter (shared widget)
// - Universal search bar
// - Export pending customers to Excel
// - Styled DataTable: grid borders, fixed columns, dual scrollbars, hover
// - Approve / Reject / Bulk Approve logic preserved

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:abra_fleet/features/admin/widgets/country_state_city_filter.dart';
import 'package:abra_fleet/app/config/api_config.dart';

// For web download - conditional import
import 'package:abra_fleet/download_helper_stub.dart'
    if (dart.library.html) 'package:abra_fleet/download_helper_web.dart' as download_helper;

class AdminPendingCustomersPage extends StatefulWidget {
  const AdminPendingCustomersPage({Key? key}) : super(key: key);

  @override
  State<AdminPendingCustomersPage> createState() => _AdminPendingCustomersPageState();
}

class _AdminPendingCustomersPageState extends State<AdminPendingCustomersPage> {
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  
  bool _isLoading = false;
  bool _isExporting = false;
  bool _isDataLoaded = false;
  
  // Backend API URL
  static String get _backendUrl => ApiConfig.baseUrl;
  
  // Filter state
  Map<String, dynamic> _activeFilters = {};
  List<Map<String, dynamic>> _allPendingCustomers = [];

  // Pagination state
  int _currentPage = 1;
  final int _rowsPerPage = 10;

  // Helper method to get auth token
  Future<String?> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await _loadPendingCustomers();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isDataLoaded = true;
        });
      }
    }
  }

  Future<void> _refreshData() async {
    await _loadData();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DATA LOADING
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _loadPendingCustomers() async {
    try {
      final response = await ApiService().get('/api/admin/customers', queryParams: {
        'status': 'pending',
        'isPendingApproval': 'true',
      });
      final customers = List<Map<String, dynamic>>.from(response['customers'] ?? response['data'] ?? []);
      
      for (var c in customers) c['role'] = 'CUSTOMER';

      customers.sort((a, b) {
        final aDate = _parseDate(a['registrationDate'] ?? a['createdAt']) ?? DateTime(2000);
        final bDate = _parseDate(b['registrationDate'] ?? b['createdAt']) ?? DateTime(2000);
        return bDate.compareTo(aDate);
      });

      _allPendingCustomers = customers;
      return customers;
    } catch (e) {
      debugPrint('Error loading pending customers: $e');
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FILTERING
  // ─────────────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _getFilteredCustomers() {
    List<Map<String, dynamic>> filtered = List.from(_allPendingCustomers);

    // Apply CountryStateCityFilter filters
    filtered = _applyLocalFilters(filtered);

    // Apply universal search
    if (_searchController.text.isNotEmpty) {
      final searchTerm = _searchController.text.toLowerCase();
      filtered = filtered.where((c) {
        final name = (c['name'] ?? '').toString().toLowerCase();
        final email = (c['email'] ?? '').toString().toLowerCase();
        final phone = (c['phoneNumber'] ?? c['phone'] ?? '').toString().toLowerCase();
        final company = (c['companyName'] ?? c['company'] ?? '').toString().toLowerCase();
        final department = (c['department'] ?? '').toString().toLowerCase();
        final empId = (c['employeeId'] ?? '').toString().toLowerCase();
        return name.contains(searchTerm) ||
               email.contains(searchTerm) ||
               phone.contains(searchTerm) ||
               company.contains(searchTerm) ||
               department.contains(searchTerm) ||
               empId.contains(searchTerm);
      }).toList();
    }

    return filtered;
  }

  List<Map<String, dynamic>> _applyLocalFilters(List<Map<String, dynamic>> customers) {
    if (_activeFilters.isEmpty) return customers;
    
    return customers.where((customer) {
      // Date range filter
      if (_activeFilters.containsKey('startDate') && _activeFilters.containsKey('endDate')) {
        final startDate = _activeFilters['startDate'] as DateTime;
        final endDate = _activeFilters['endDate'] as DateTime;
        final customerDate = _parseDate(customer['registrationDate'] ?? customer['createdAt']);
        if (customerDate == null || 
            customerDate.isBefore(startDate) || 
            customerDate.isAfter(endDate)) {
          return false;
        }
      }
      
      // Country filter
      if (_activeFilters.containsKey('country')) {
        final country = _activeFilters['country'] as String;
        final customerCountry = customer['country']?.toString() ?? '';
        if (!customerCountry.toLowerCase().contains(country.toLowerCase())) {
          return false;
        }
      }
      
      // State filter
      if (_activeFilters.containsKey('state')) {
        final state = _activeFilters['state'] as String;
        if (customer['state']?.toString().toLowerCase() != state.toLowerCase()) {
          return false;
        }
      }
      
      // City filter
      if (_activeFilters.containsKey('city')) {
        final city = _activeFilters['city'] as String;
        final customerCity = customer['city']?.toString() ?? '';
        if (!customerCity.toLowerCase().contains(city.toLowerCase())) {
          return false;
        }
      }
      
      // Area filter
      if (_activeFilters.containsKey('area')) {
        final area = _activeFilters['area'] as String;
        final customerArea = customer['area']?.toString() ?? '';
        if (!customerArea.toLowerCase().contains(area.toLowerCase())) {
          return false;
        }
      }
      
      return true;
    }).toList();
  }

  DateTime? _parseDate(dynamic timestamp) {
    if (timestamp == null) return null;
    try {
      if (timestamp is String) return DateTime.parse(timestamp);
      if (timestamp is int) return DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (timestamp is DateTime) return timestamp;
    } catch (e) {
      debugPrint('Error parsing date: $e');
    }
    return null;
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return '—';
    try {
      DateTime date;
      if (timestamp is String) {
        date = DateTime.parse(timestamp);
      } else if (timestamp is int) {
        date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else if (timestamp is DateTime) {
        date = timestamp;
      } else {
        return '—';
      }
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return '—';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EXPORT
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _exportPendingCustomers() async {
    if (_isExporting) return;
    
    setState(() => _isExporting = true);

    try {
      debugPrint('\n📊 EXPORTING PENDING CUSTOMERS TO EXCEL');
      debugPrint('─' * 80);

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      if (token == null) {
        throw Exception('Authentication required');
      }

      // Build query parameters — always include pending filter
      final queryParams = <String, String>{
        'status': 'pending',
        'isPendingApproval': 'true',
      };
      
      if (_searchController.text.isNotEmpty) {
        queryParams['search'] = _searchController.text;
      }
      
      if (_activeFilters.containsKey('country')) {
        queryParams['country'] = _activeFilters['country'];
      }
      if (_activeFilters.containsKey('state')) {
        queryParams['state'] = _activeFilters['state'];
      }
      if (_activeFilters.containsKey('city')) {
        queryParams['city'] = _activeFilters['city'];
      }
      if (_activeFilters.containsKey('startDate')) {
        queryParams['startDate'] = (_activeFilters['startDate'] as DateTime).toIso8601String();
      }
      if (_activeFilters.containsKey('endDate')) {
        queryParams['endDate'] = (_activeFilters['endDate'] as DateTime).toIso8601String();
      }

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/admin/customers/legacy/export')
          .replace(queryParameters: queryParams);

      debugPrint('📡 Export URL: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(
        const Duration(minutes: 2),
        onTimeout: () {
          throw Exception('Export timeout - Please try again');
        },
      );

      debugPrint('📥 Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final timestamp = DateTime.now().toIso8601String().split('T')[0];
        final filename = 'pending_customers_export_$timestamp.xlsx';

        if (kIsWeb) {
          download_helper.downloadFile(bytes, filename);
        } else {
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/$filename');
          await file.writeAsBytes(bytes);
          
          if (!mounted) return;
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File saved to: ${file.path}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
        }

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Excel file exported successfully! ($filename)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        throw Exception('Export failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Export error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Export failed: ${e.toString()}')),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _exportPendingCustomers,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // APPROVE / REJECT / BULK APPROVE (BUSINESS LOGIC PRESERVED)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleApprove(Map<String, dynamic> customer, String customerId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Approve Customer'),
          content: Text('Are you sure you want to approve ${customer['name']}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              child: const Text('Approve'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        debugPrint('\n${'=' * 80}');
        debugPrint('🟢 CUSTOMER APPROVAL PROCESS STARTED');
        debugPrint('=' * 80);
        debugPrint('Customer Name: ${customer['name']}');
        debugPrint('Customer ID: $customerId');
        debugPrint('Customer Email: ${customer['email']}');
        debugPrint('Customer Company: ${customer['companyName'] ?? 'N/A'}');
        debugPrint('-' * 80);
        
        // Step 1: Update via HTTP API
        debugPrint('Step 1: Updating ${customer['role']} via HTTP API...');
        
        final endpoint = customer['role'] == 'DRIVER' 
            ? '/api/admin/drivers/$customerId'
            : '/api/admin/customers/$customerId';
            
        await ApiService().put(endpoint, body: {
          'status': 'active', // Note: backend converts to lowercase usually, but 'active' is standard
          'isPendingApproval': false,
          'approvedAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        });
        debugPrint('✅ Customer updated successfully');
        debugPrint('-' * 80);
        
        // Step 2: Send email notification via backend
        debugPrint('Step 2: Sending email notification...');
        try {
          final token = await _getAuthToken();
          if (token != null) {
            final requestBody = {
              'customerId': customerId,
              'customerEmail': customer['email'],
              'customerName': customer['name'],
            };
            
            final response = await http.post(
              Uri.parse('$_backendUrl/api/customer-approval/approve'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(requestBody),
            );
            
            debugPrint('Backend response status: ${response.statusCode}');
            
            if (response.statusCode == 200) {
              final responseData = jsonDecode(response.body);
              if (responseData['emailSent'] == true) {
                debugPrint('✅✅✅ EMAIL SENT SUCCESSFULLY! ✅✅✅');
              } else {
                debugPrint('⚠️ EMAIL NOT SENT');
              }
            }
          }
        } catch (emailError) {
          debugPrint('❌ Email notification error: $emailError');
        }
        
        debugPrint('=' * 80);
        debugPrint('APPROVAL PROCESS COMPLETED');
        debugPrint('=' * 80 + '\n');

        if (mounted) {
          _showSuccessSnackBar('${customer['name']} has been approved successfully!');
          _refreshData();
        }
      } catch (e) {
        debugPrint('❌ APPROVAL PROCESS FAILED: $e');
        if (mounted) {
          _showErrorSnackBar('Failed to approve customer: $e');
        }
      }
    }
  }

  Future<void> _handleBulkApprove(List<Map<String, dynamic>> customers) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Approve All Customers'),
          content: Text(
            'Are you sure you want to approve all ${customers.length} pending customers?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              child: const Text('Approve All'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      
      int successCount = 0;
      int failCount = 0;
      
      try {
        debugPrint('\n${'=' * 80}');
        debugPrint('🟢 BULK CUSTOMER APPROVAL PROCESS STARTED');
        debugPrint('=' * 80);
        debugPrint('Total customers to approve: ${customers.length}');
        
        for (var customer in customers) {
          try {
            final customerId = customer['id'] ?? customer['_id'];
            debugPrint('Approving: ${customer['name']} (ID: $customerId)');
            
            final endpoint = customer['role'] == 'DRIVER' 
                ? '/api/admin/drivers/$customerId'
                : '/api/admin/customers/$customerId';

            await ApiService().put(endpoint, body: {
              'status': 'active',
              'isPendingApproval': false,
              'approvedAt': DateTime.now().toIso8601String(),
              'updatedAt': DateTime.now().toIso8601String(),
            });
            
            // Send email notification
            try {
              final token = await _getAuthToken();
              if (token != null) {
                await http.post(
                  Uri.parse('$_backendUrl/api/customer-approval/approve'),
                  headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer $token',
                  },
                  body: jsonEncode({
                    'customerId': customerId,
                    'customerEmail': customer['email'],
                    'customerName': customer['name'],
                  }),
                );
              }
            } catch (emailError) {
              debugPrint('⚠️ Email notification failed for ${customer['name']}: $emailError');
            }
            
            successCount++;
            debugPrint('✅ Approved: ${customer['name']}');
          } catch (e) {
            failCount++;
            debugPrint('❌ Failed to approve ${customer['name']}: $e');
          }
        }
        
        debugPrint('BULK APPROVAL COMPLETED — Success: $successCount, Failed: $failCount');

        if (mounted) {
          if (failCount == 0) {
            _showSuccessSnackBar('All $successCount customers approved successfully!');
          } else {
            _showErrorSnackBar('Approved $successCount customers, $failCount failed');
          }
          _refreshData();
        }
      } catch (e) {
        debugPrint('BULK APPROVAL PROCESS FAILED: $e');
        if (mounted) {
          _showErrorSnackBar('Bulk approval failed: $e');
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _handleReject(Map<String, dynamic> customer, String customerId) async {
    final TextEditingController reasonController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Reject Customer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Are you sure you want to reject ${customer['name']}?'),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: 'Reason for rejection',
                  hintText: 'Enter reason...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
              ),
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        debugPrint('\n${'=' * 80}');
        debugPrint('🔴 CUSTOMER REJECTION PROCESS STARTED');
        debugPrint('=' * 80);
        debugPrint('Customer Name: ${customer['name']}');
        debugPrint('Customer ID: $customerId');
        
        final rejectionReason = reasonController.text.trim();
        
        // Step 1: Update via HTTP API
        final endpoint = customer['role'] == 'DRIVER' 
            ? '/api/admin/drivers/$customerId'
            : '/api/admin/customers/$customerId';
            
        await ApiService().put(endpoint, body: {
          'status': 'rejected',
          'isPendingApproval': false,
          'rejectionReason': rejectionReason,
          'rejectedAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        });
        debugPrint('✅ Customer updated successfully');
        
        // Step 2: Send rejection email notification
        try {
          final token = await _getAuthToken();
          if (token != null) {
            final requestBody = {
              'customerId': customerId,
              'customerEmail': customer['email'],
              'customerName': customer['name'],
              'reason': rejectionReason,
            };
            
            final response = await http.post(
              Uri.parse('$_backendUrl/api/customer-approval/reject'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(requestBody),
            );
            
            debugPrint('Backend response status: ${response.statusCode}');
            
            if (response.statusCode == 200) {
              final responseData = jsonDecode(response.body);
              if (responseData['emailSent'] == true) {
                debugPrint('✅ Rejection email sent');
              }
            }
          }
        } catch (emailError) {
          debugPrint('❌ Email notification error: $emailError');
        }
        
        debugPrint('REJECTION PROCESS COMPLETED\n');

        if (mounted) {
          _showErrorSnackBar('${customer['name']} has been rejected.');
          _refreshData();
        }
      } catch (e) {
        debugPrint('REJECTION PROCESS FAILED: $e');
        if (mounted) {
          _showErrorSnackBar('Failed to reject customer: $e');
        }
      }
    }

    reasonController.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SNACKBARS
  // ─────────────────────────────────────────────────────────────────────────

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.cancel, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F2557), Color(0xFF1A3FC4)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back to Admin Dashboard',
        ),
        title: const Text(
          'Pending Customers Approval',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
      body: _isLoading && !_isDataLoaded
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _refreshData,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Stats Cards ──
                  _buildStatsGrid(),
                  const SizedBox(height: 24),

                  // ── CountryStateCityFilter (shared widget) ──
                  CountryStateCityFilter(
                    onFilterApplied: (filterData) {
                      setState(() {
                        _activeFilters = {};
                        if (filterData['fromDate'] != null) {
                          _activeFilters['startDate'] = filterData['fromDate'];
                        }
                        if (filterData['toDate'] != null) {
                          _activeFilters['endDate'] = filterData['toDate'];
                        }
                        if (filterData['country'] != null && filterData['country'].toString().isNotEmpty) {
                          _activeFilters['country'] = filterData['country'];
                        }
                        if (filterData['state'] != null && filterData['state'].toString().isNotEmpty) {
                          _activeFilters['state'] = filterData['state'];
                        }
                        if (filterData['city'] != null && filterData['city'].toString().isNotEmpty) {
                          _activeFilters['city'] = filterData['city'];
                        }
                        if (filterData['localArea'] != null && filterData['localArea'].toString().isNotEmpty) {
                          _activeFilters['area'] = filterData['localArea'];
                        }
                        _currentPage = 1;
                      });
                    },
                  ),
                  const SizedBox(height: 24),

                  // ── Search Bar ──
                  _buildSearchSection(),
                  const SizedBox(height: 24),

                  // ── Table ──
                  _buildPendingCustomerDirectory(),
                ],
              ),
            ),
          ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATS CARDS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStatsGrid() {
    final total = _allPendingCustomers.length;
    final today = DateTime.now();
    final registeredToday = _allPendingCustomers.where((c) {
      final d = _parseDate(c['registrationDate'] ?? c['createdAt']);
      if (d == null) return false;
      return d.year == today.year && d.month == today.month && d.day == today.day;
    }).length;
    final waiting7Plus = _allPendingCustomers.where((c) {
      final d = _parseDate(c['registrationDate'] ?? c['createdAt']);
      if (d == null) return false;
      return today.difference(d).inDays >= 7;
    }).length;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            label: 'Total Pending',
            value: total.toString(),
            subtitle: 'Awaiting approval',
            icon: Icons.hourglass_top_rounded,
            color: const Color(0xFFF59E0B),
            iconBg: const Color(0xFFFFFBEB),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            label: 'Registered Today',
            value: registeredToday.toString(),
            subtitle: 'New registrations',
            icon: Icons.person_add_alt_1_rounded,
            color: const Color(0xFF3B82F6),
            iconBg: const Color(0xFFEFF6FF),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            label: 'Waiting 7+ Days',
            value: waiting7Plus.toString(),
            subtitle: 'Needs attention',
            icon: Icons.warning_amber_rounded,
            color: const Color(0xFFEF4444),
            iconBg: const Color(0xFFFEF2F2),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            label: 'Filtered Results',
            value: _getFilteredCustomers().length.toString(),
            subtitle: 'Currently showing',
            icon: Icons.filter_list_rounded,
            color: const Color(0xFF10B981),
            iconBg: const Color(0xFFECFDF5),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color iconBg,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.2), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEARCH SECTION
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSearchSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.search, size: 18, color: Color(0xFF0F2557)),
              SizedBox(width: 8),
              Text(
                'Quick Search',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F2557),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              // Universal Search Field
              Expanded(
                flex: 3,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() {
                      _currentPage = 1;
                    }),
                    decoration: InputDecoration(
                      hintText: 'Search by Name, Email, Phone, Company, Department, Employee ID...',
                      hintStyle: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF64748B)),
                      suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18, color: Color(0xFF94A3B8)),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _currentPage = 1;
                              });
                            },
                          )
                        : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Apply / Reset buttons
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F2557), Color(0xFF1A3FC4)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F2557).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () => setState(() {
                    _currentPage = 1;
                  }),
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text(
                    'Apply Filter',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _searchController.clear();
                    _activeFilters = {};
                    _currentPage = 1;
                  });
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text(
                  'Reset',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF64748B),
                  side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TABLE DIRECTORY
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPendingCustomerDirectory() {
    final filteredCustomers = _getFilteredCustomers();

    final totalItems = filteredCustomers.length;
    final totalPages = totalItems == 0 ? 1 : ((totalItems - 1) ~/ _rowsPerPage) + 1;
    if (_currentPage > totalPages) _currentPage = totalPages;
    if (_currentPage < 1) _currentPage = 1;
    final startIndex = (_currentPage - 1) * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage) > totalItems ? totalItems : startIndex + _rowsPerPage;
    final pagedCustomers = totalItems == 0
        ? <Map<String, dynamic>>[]
        : filteredCustomers.sublist(startIndex, endIndex);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Table Top Bar ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.approval, color: Color(0xFF0F2557), size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Pending Approvals (${filteredCustomers.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F2557),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Scroll Left Button
                    IconButton.filledTonal(
                      onPressed: () {
                        _horizontalScrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      },
                      icon: const Icon(Icons.arrow_back_ios_new, size: 14),
                      tooltip: 'Scroll to First Column',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFEFF6FF),
                        foregroundColor: const Color(0xFF1A3FC4),
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                    // Scroll Right Button
                    IconButton.filledTonal(
                      onPressed: () {
                        if (_horizontalScrollController.hasClients) {
                          _horizontalScrollController.animateTo(
                            _horizontalScrollController.position.maxScrollExtent,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        }
                      },
                      icon: const Icon(Icons.arrow_forward_ios, size: 14),
                      tooltip: 'Scroll to Actions',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFEFF6FF),
                        foregroundColor: const Color(0xFF1A3FC4),
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                    const SizedBox(width: 4),

                    // Export Button
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF10B981), Color(0xFF059669)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _isExporting ? null : _exportPendingCustomers,
                        icon: _isExporting
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.file_download_outlined, size: 17),
                        label: Text(
                          _isExporting ? 'Exporting...' : 'Export',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),

                    // Approve All Button
                    if (filteredCustomers.isNotEmpty)
                      Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF10B981), Color(0xFF047857)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withOpacity(0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : () => _handleBulkApprove(filteredCustomers),
                          icon: _isLoading
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle, size: 17),
                          label: Text(
                            _isLoading ? 'Approving...' : 'Approve All',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),

                    // Refresh Button
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D9488), Color(0xFF0F766E)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0D9488).withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () => _refreshData(),
                        icon: const Icon(Icons.refresh, size: 17),
                        label: const Text(
                          'Refresh',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Scroll Hint Banner ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFEFF6FF),
              border: Border(
                bottom: BorderSide(color: Color(0xFFBFDBFE), width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.pan_tool_alt_outlined, size: 15, color: Color(0xFF1A3FC4)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Horizontal & Vertical Scrolling: Click and drag with mouse, use trackpad, or use the scrollbar below to scroll columns.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () {
                    if (_horizontalScrollController.hasClients) {
                      _horizontalScrollController.animateTo(
                        _horizontalScrollController.position.maxScrollExtent,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Jump to Actions',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A3FC4),
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 13, color: Color(0xFF1A3FC4)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Table Content ──
          filteredCustomers.isEmpty
            ? _buildEmptyState()
            : Container(
                height: 560,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                ),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad,
                      PointerDeviceKind.stylus,
                    },
                  ),
                  child: RawScrollbar(
                    controller: _horizontalScrollController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    thickness: 10,
                    radius: const Radius.circular(5),
                    thumbColor: const Color(0xFF1A3FC4),
                    trackColor: const Color(0xFFE2E8F0),
                    trackRadius: const Radius.circular(5),
                    scrollbarOrientation: ScrollbarOrientation.bottom,
                    child: RawScrollbar(
                      controller: _verticalScrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      thickness: 10,
                      radius: const Radius.circular(5),
                      thumbColor: const Color(0xFF0F2557),
                      trackColor: const Color(0xFFE2E8F0),
                      trackRadius: const Radius.circular(5),
                      scrollbarOrientation: ScrollbarOrientation.right,
                      child: SingleChildScrollView(
                        controller: _horizontalScrollController,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: SingleChildScrollView(
                          controller: _verticalScrollController,
                          scrollDirection: Axis.vertical,
                          physics: const BouncingScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 1400),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: DataTable(
                                border: const TableBorder(
                                  horizontalInside: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                                  verticalInside: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                                  top: BorderSide(color: Color(0xFF0F2557), width: 1),
                                  bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                                  left: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                                  right: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                                ),
                                columnSpacing: 16,
                                horizontalMargin: 16,
                                headingRowHeight: 48,
                                dataRowMinHeight: 52,
                                dataRowMaxHeight: 56,
                                headingRowColor: MaterialStateProperty.all(
                                  const Color(0xFF0F2557),
                                ),
                                headingTextStyle: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                                dataRowColor: MaterialStateProperty.resolveWith<Color>((states) {
                                  if (states.contains(MaterialState.hovered)) {
                                    return const Color(0xFFEFF6FF);
                                  }
                                  return Colors.white;
                                }),
                                columns: const [
                                  DataColumn(label: SizedBox(width: 170, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('NAME')))),
                                  DataColumn(label: SizedBox(width: 220, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('EMAIL')))),
                                  DataColumn(label: SizedBox(width: 130, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('PHONE')))),
                                  DataColumn(label: SizedBox(width: 160, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('COMPANY')))),
                                  DataColumn(label: SizedBox(width: 150, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('DEPARTMENT')))),
                                  DataColumn(label: SizedBox(width: 110, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('EMPLOYEE ID')))),
                                  DataColumn(label: SizedBox(width: 80, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('ROLE')))),
                                  DataColumn(label: SizedBox(width: 140, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('REGISTRATION DATE')))),
                                  DataColumn(label: SizedBox(width: 180, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('ACTIONS')))),
                                ],
                                rows: pagedCustomers.map<DataRow>((customer) {
                                  final customerId = customer['_id'] ?? customer['id'] ?? '';
                                  final name = customer['name'] ?? '—';
                                  final email = customer['email'] ?? '—';
                                  final phone = customer['phoneNumber'] ?? customer['phone'] ?? '';
                                  final company = customer['companyName'] ?? customer['company'] ?? '';
                                  final department = customer['department'] ?? '';
                                  final empId = customer['employeeId'] ?? '';
                                  final role = (customer['role'] ?? 'customer').toString();
                                  final regDate = customer['registrationDate'] ?? customer['createdAt'];

                                  final hasPhone = phone.isNotEmpty && phone != 'N/A';
                                  final hasCompany = company.isNotEmpty && company != 'N/A';
                                  final hasDept = department.isNotEmpty && department != 'N/A';
                                  final hasEmpId = empId.isNotEmpty && empId.toUpperCase() != 'N/A';

                                  return DataRow(
                                    cells: [
                                      // Name
                                      DataCell(
                                        SizedBox(
                                          width: 170,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                CircleAvatar(
                                                  radius: 14,
                                                  backgroundColor: const Color(0xFF0F2557),
                                                  child: Text(
                                                    name.isNotEmpty ? name[0].toUpperCase() : 'C',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    name,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 13,
                                                      color: Color(0xFF1E293B),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Email
                                      DataCell(
                                        SizedBox(
                                          width: 220,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            child: Text(
                                              email,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Phone
                                      DataCell(
                                        SizedBox(
                                          width: 130,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            child: Text(
                                              hasPhone ? phone : '—',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: hasPhone ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                                                fontWeight: hasPhone ? FontWeight.w600 : FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Company
                                      DataCell(
                                        SizedBox(
                                          width: 160,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            child: hasCompany
                                              ? Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFEFF6FF),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: const Color(0xFFBFDBFE)),
                                                  ),
                                                  child: Text(
                                                    company,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: Color(0xFF1E40AF),
                                                    ),
                                                  ),
                                                )
                                              : const Text(
                                                  '—',
                                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w600),
                                                ),
                                          ),
                                        ),
                                      ),
                                      // Department
                                      DataCell(
                                        SizedBox(
                                          width: 150,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            child: Text(
                                              hasDept ? department : '—',
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: hasDept ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Employee ID
                                      DataCell(
                                        SizedBox(
                                          width: 110,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            child: hasEmpId
                                              ? Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFF1F5F9),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                                  ),
                                                  child: Text(
                                                    empId,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w700,
                                                      color: Color(0xFF0F2557),
                                                      fontFamily: 'monospace',
                                                    ),
                                                  ),
                                                )
                                              : const Text(
                                                  '—',
                                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w600),
                                                ),
                                          ),
                                        ),
                                      ),
                                      // Role
                                      DataCell(
                                        SizedBox(
                                          width: 80,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF3B82F6).withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                role.toUpperCase(),
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF3B82F6),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Registration Date
                                      DataCell(
                                        SizedBox(
                                          width: 140,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            child: Text(
                                              _formatDate(regDate),
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF475569),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Actions
                                      DataCell(
                                        SizedBox(
                                          width: 180,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // Approve
                                                Container(
                                                  height: 32,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFECFDF5),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: const Color(0xFF6EE7B7)),
                                                  ),
                                                  child: TextButton.icon(
                                                    onPressed: () => _handleApprove(customer, customerId),
                                                    icon: const Icon(Icons.check, size: 14, color: Color(0xFF047857)),
                                                    label: const Text(
                                                      'Approve',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                        color: Color(0xFF047857),
                                                      ),
                                                    ),
                                                    style: TextButton.styleFrom(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                                      minimumSize: Size.zero,
                                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                // Reject
                                                Container(
                                                  height: 32,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFFEF2F2),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: const Color(0xFFFCA5A5)),
                                                  ),
                                                  child: TextButton.icon(
                                                    onPressed: () => _handleReject(customer, customerId),
                                                    icon: const Icon(Icons.close, size: 14, color: Color(0xFF991B1B)),
                                                    label: const Text(
                                                      'Reject',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                        color: Color(0xFF991B1B),
                                                      ),
                                                    ),
                                                    style: TextButton.styleFrom(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                                      minimumSize: Size.zero,
                                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

          if (totalItems > 0)
            _buildPaginationBar(
              startIndex: startIndex,
              endIndex: endIndex,
              totalItems: totalItems,
              totalPages: totalPages,
            ),
        ],
      ),
    );
  }

  Widget _buildPaginationBar({
    required int startIndex,
    required int endIndex,
    required int totalItems,
    required int totalPages,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(10),
          bottomRight: Radius.circular(10),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            'Showing ${startIndex + 1}-$endIndex of $totalItems',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filledTonal(
                onPressed: _currentPage > 1
                    ? () => setState(() => _currentPage--)
                    : null,
                icon: const Icon(Icons.chevron_left, size: 18),
                tooltip: 'Previous Page',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFEFF6FF),
                  foregroundColor: const Color(0xFF1A3FC4),
                  padding: const EdgeInsets.all(6),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Page $_currentPage of $totalPages',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F2557),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                onPressed: _currentPage < totalPages
                    ? () => setState(() => _currentPage++)
                    : null,
                icon: const Icon(Icons.chevron_right, size: 18),
                tooltip: 'Next Page',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFEFF6FF),
                  foregroundColor: const Color(0xFF1A3FC4),
                  padding: const EdgeInsets.all(6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(56.0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Color(0xFF10B981),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Pending Approvals',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchController.text.isNotEmpty || _activeFilters.isNotEmpty
              ? 'No pending customers match your search or filter criteria.'
              : 'All customer registrations have been processed.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
