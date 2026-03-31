// File: lib/features/client/client_sos_alerts.dart
// Client SOS Alerts with Organization-based Filtering and Resolved Alerts with Proof

import 'package:flutter/material.dart';

// Firebase removed - using HTTP API
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// ignore: avoid_web_libraries_in_flutter
import 'package:universal_html/html.dart' as html;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/core/services/api_service.dart';

class ClientSOSAlerts extends StatefulWidget {
  const ClientSOSAlerts({Key? key}) : super(key: key);

  @override
  State<ClientSOSAlerts> createState() => _ClientSOSAlertsState();
}

class _ClientSOSAlertsState extends State<ClientSOSAlerts> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _clientOrganizationDomain;
  String _statusFilter = 'All';
  String _timeFilter = 'All Time';
  
  // Tab Controller for Active/Resolved tabs
  late TabController _tabController;
  
  // Active alerts from Firebase Realtime Database
  List<SOSAlert> _activeAlerts = [];
  
  // Resolved alerts from MongoDB backend
  List<ResolvedSOSAlert> _resolvedAlerts = [];
  
  bool _isLoadingActive = true;
  bool _isLoadingResolved = true;
  StreamSubscription? _sosSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeData();
  }

 Future<void> _initializeData() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token != null && token.isNotEmpty) {
      // Get email from JWT user data
      final userDataString = prefs.getString('user_data');
      final userData = userDataString != null ? jsonDecode(userDataString) : null;
      final userEmail = userData?['email'];
      
      if (userEmail != null) {
        final emailParts = userEmail.split('@');
        if (emailParts.length == 2) {
          _clientOrganizationDomain = '@${emailParts[1]}';
        }
      }
      debugPrint('🚨 Client SOS domain: $_clientOrganizationDomain');
      
      // Setup both active and resolved alerts
      _setupActiveSOSListener();
      _fetchResolvedAlerts();
    }
  } catch (e) {
    debugPrint('❌ Error initializing SOS alerts: $e');
    if (mounted) {
      setState(() {
        _isLoadingActive = false;
        _isLoadingResolved = false;
      });
    }
  }
}

void _setupActiveSOSListener() {
  // Poll active SOS alerts from backend API every 5 seconds
  _sosSubscription = Stream.periodic(const Duration(seconds: 5))
      .asyncMap((_) async {
    try {
      final apiService = ApiService();
      // ✅ FIXED: Use correct endpoint with status filter
      final response = await apiService.get('/api/sos', queryParams: {
        'status': 'ACTIVE',
        'limit': '100'
      });
      return response;
    } catch (e) {
      debugPrint('❌ Error fetching active SOS alerts: $e');
      return {'success': false, 'data': []};
    }
  }).listen((response) {
    if (!mounted) return;
    
    final List<dynamic>? data = response['data'] as List<dynamic>?;

    if (data == null || data.isEmpty) {
      setState(() {
        _activeAlerts = [];
        _isLoadingActive = false;
      });
      return;
    }

    List<SOSAlert> alerts = [];

    for (var alertData in data) {
      try {
        if (alertData is Map<String, dynamic>) {
          final customerEmail = alertData['customerEmail'] as String?;
          final status = alertData['status'] as String?;
          
          // Filter by organization domain and only show active/pending alerts
          if (customerEmail != null && 
              _clientOrganizationDomain != null &&
              customerEmail.endsWith(_clientOrganizationDomain!) &&
              (status == 'ACTIVE' || status == 'Pending')) {
            final id = alertData['_id'] ?? alertData['id'] ?? '';
            alerts.add(SOSAlert.fromMap(id, alertData));
          }
        }
      } catch (e) {
        debugPrint('❌ Error parsing active SOS alert: $e');
      }
    }

    // Sort by timestamp (newest first)
    alerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    setState(() {
      _activeAlerts = alerts;
      _isLoadingActive = false;
    });
    
    debugPrint('🚨 Loaded ${alerts.length} active SOS alerts for organization');
  });
}

  Future<void> _fetchResolvedAlerts() async {
    if (!mounted) return;
    setState(() => _isLoadingResolved = true);

    try {
      debugPrint('📥 Fetching resolved SOS alerts for organization: $_clientOrganizationDomain');
      
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        throw Exception('User not authenticated');
      }
            
      // Fetch from backend API with status filter and organization filter
      final url = Uri.parse('${ApiConfig.baseUrl}/api/sos?status=Resolved&limit=100');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('📡 Resolved alerts response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          final List<dynamic> alertsJson = data['data'];
          
          // Filter by organization domain
          final List<ResolvedSOSAlert> organizationAlerts = alertsJson
              .map((json) => ResolvedSOSAlert.fromJson(json))
              .where((alert) => _clientOrganizationDomain != null && 
                               alert.customerEmail.endsWith(_clientOrganizationDomain!))
              .toList();
          
          // Sort by resolved date (most recent first)
          organizationAlerts.sort((a, b) {
            final aDate = a.resolvedAt ?? a.timestamp;
            final bDate = b.resolvedAt ?? b.timestamp;
            return bDate.compareTo(aDate);
          });
          
          debugPrint('✅ Loaded ${organizationAlerts.length} resolved alerts for organization');
          
          if (mounted) {
            setState(() => _resolvedAlerts = organizationAlerts);
          }
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        throw Exception('Failed to load resolved alerts: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error fetching resolved alerts: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load resolved alerts: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingResolved = false);
      }
    }
  }

  List<SOSAlert> _getFilteredActiveAlerts() {
    List<SOSAlert> filtered = _activeAlerts;

    // Status filter
    if (_statusFilter != 'All') {
      filtered = filtered.where((alert) => alert.status == _statusFilter).toList();
    }

    // Time filter
    if (_timeFilter != 'All Time') {
      final now = DateTime.now();
      filtered = filtered.where((alert) {
        switch (_timeFilter) {
          case 'This Week':
            final weekAgo = now.subtract(const Duration(days: 7));
            return alert.timestamp.isAfter(weekAgo);
          case 'This Month':
            return alert.timestamp.month == now.month && alert.timestamp.year == now.year;
          default:
            return true;
        }
      }).toList();
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((alert) {
        return alert.customerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            alert.customerEmail.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            alert.address.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    return filtered;
  }

  List<ResolvedSOSAlert> _getFilteredResolvedAlerts() {
    List<ResolvedSOSAlert> filtered = _resolvedAlerts;

    // Time filter
    if (_timeFilter != 'All Time') {
      final now = DateTime.now();
      filtered = filtered.where((alert) {
        final alertDate = alert.resolvedAt ?? alert.timestamp;
        switch (_timeFilter) {
          case 'This Week':
            final weekAgo = now.subtract(const Duration(days: 7));
            return alertDate.isAfter(weekAgo);
          case 'This Month':
            return alertDate.month == now.month && alertDate.year == now.year;
          default:
            return true;
        }
      }).toList();
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((alert) {
        return alert.customerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            alert.customerEmail.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            alert.address.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    return filtered;
  }

  Future<void> _refreshAllData() async {
    try {
      // Show loading state
      setState(() {
        _isLoadingActive = true;
        _isLoadingResolved = true;
      });

      // Refresh both active and resolved alerts
      _setupActiveSOSListener();
      await _fetchResolvedAlerts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Text('SOS alerts refreshed successfully'),
              ],
            ),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error refreshing SOS alerts: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text('Error refreshing: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Stats Grid
            Padding(
              padding: const EdgeInsets.all(24),
              child: _buildStatsGrid(),
            ),
            
            // Filter Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildFilterButton(),
            ),
            
            const SizedBox(height: 24),
            
            // Tab Bar with Refresh Button
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header with Refresh Button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'SOS Alerts',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _refreshAllData,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Refresh'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Tab Bar
                  TabBar(
                    controller: _tabController,
                    labelColor: const Color(0xFF2563EB),
                    unselectedLabelColor: const Color(0xFF64748B),
                    indicatorColor: const Color(0xFF2563EB),
                    indicatorWeight: 3,
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 18),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Active (${_activeAlerts.length})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle, size: 18),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Resolved (${_resolvedAlerts.length})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Tab Content
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              height: 500, // Fixed height to prevent overflow
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildActiveAlertsTab(),
                  _buildResolvedAlertsTab(),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    final activeAlerts = _activeAlerts.where((a) => a.status == 'ACTIVE' || a.status == 'Pending').length;
    final resolvedAlerts = _resolvedAlerts.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive layout based on screen width
        final screenWidth = constraints.maxWidth;
        final isSmallScreen = screenWidth < 600;
        final isMediumScreen = screenWidth < 900;
        
        if (isSmallScreen) {
          // Single column for small screens
          return Column(
            children: [
              _buildStatCard(
                icon: Icons.warning_amber_rounded,
                iconColor: const Color(0xFFEF4444),
                iconBgColor: const Color(0xFFEF4444).withOpacity(0.1),
                value: activeAlerts.toString(),
                label: 'Active Alerts',
                width: double.infinity,
              ),
              const SizedBox(height: 16),
              _buildStatCard(
                icon: Icons.check_circle,
                iconColor: const Color(0xFF10B981),
                iconBgColor: const Color(0xFF10B981).withOpacity(0.1),
                value: resolvedAlerts.toString(),
                label: 'Resolved',
                width: double.infinity,
              ),
              const SizedBox(height: 16),
              _buildStatCard(
                icon: Icons.shield_outlined,
                iconColor: const Color(0xFF2563EB),
                iconBgColor: const Color(0xFF2563EB).withOpacity(0.1),
                value: (activeAlerts + resolvedAlerts).toString(),
                label: 'Total Alerts',
                width: double.infinity,
              ),
            ],
          );
        } else if (isMediumScreen) {
          // Two columns for medium screens
          final cardWidth = (screenWidth - 16) / 2;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _buildStatCard(
                icon: Icons.warning_amber_rounded,
                iconColor: const Color(0xFFEF4444),
                iconBgColor: const Color(0xFFEF4444).withOpacity(0.1),
                value: activeAlerts.toString(),
                label: 'Active Alerts',
                width: cardWidth,
              ),
              _buildStatCard(
                icon: Icons.check_circle,
                iconColor: const Color(0xFF10B981),
                iconBgColor: const Color(0xFF10B981).withOpacity(0.1),
                value: resolvedAlerts.toString(),
                label: 'Resolved',
                width: cardWidth,
              ),
              _buildStatCard(
                icon: Icons.shield_outlined,
                iconColor: const Color(0xFF2563EB),
                iconBgColor: const Color(0xFF2563EB).withOpacity(0.1),
                value: (activeAlerts + resolvedAlerts).toString(),
                label: 'Total Alerts',
                width: cardWidth,
              ),
            ],
          );
        } else {
          // Three columns for large screens with proper spacing
          final cardWidth = (screenWidth - 40) / 3;
          return Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.warning_amber_rounded,
                  iconColor: const Color(0xFFEF4444),
                  iconBgColor: const Color(0xFFEF4444).withOpacity(0.1),
                  value: activeAlerts.toString(),
                  label: 'Active Alerts',
                  width: double.infinity,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.check_circle,
                  iconColor: const Color(0xFF10B981),
                  iconBgColor: const Color(0xFF10B981).withOpacity(0.1),
                  value: resolvedAlerts.toString(),
                  label: 'Resolved',
                  width: double.infinity,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.shield_outlined,
                  iconColor: const Color(0xFF2563EB),
                  iconBgColor: const Color(0xFF2563EB).withOpacity(0.1),
                  value: (activeAlerts + resolvedAlerts).toString(),
                  label: 'Total Alerts',
                  width: double.infinity,
                ),
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String value,
    required String label,
    required double width,
  }) {
    return Container(
      width: width == double.infinity ? null : width,
      constraints: width == double.infinity ? null : BoxConstraints(minWidth: 200),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
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

  Widget _buildFilterButton() {
    final hasActiveFilters = _searchQuery.isNotEmpty || _statusFilter != 'All' || _timeFilter != 'All Time';
    
    return Container(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _showFilterOverlay,
        icon: Icon(
          Icons.filter_list,
          size: 20,
          color: hasActiveFilters ? Colors.white : const Color(0xFF64748B),
        ),
        label: Text(
          hasActiveFilters ? 'Filters Applied' : 'Filters',
          style: TextStyle(
            color: hasActiveFilters ? Colors.white : const Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: hasActiveFilters ? const Color(0xFF2563EB) : Colors.white,
          foregroundColor: hasActiveFilters ? Colors.white : const Color(0xFF64748B),
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: hasActiveFilters ? const Color(0xFF2563EB) : Colors.grey[300]!,
            ),
          ),
        ),
      ),
    );
  }

  void _showFilterOverlay() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.filter_list,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Filter SOS Alerts',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                
                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search Bar
                        const Text(
                          'Search',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _searchController,
                          onChanged: (value) => setState(() => _searchQuery = value),
                          decoration: InputDecoration(
                            hintText: 'Search by employee name, email, or location...',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFF2563EB)),
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      setState(() {
                                        _searchController.clear();
                                        _searchQuery = '';
                                      });
                                    },
                                  )
                                : null,
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Status Filter
                        _buildFilterChipGroup(
                          label: 'Status',
                          options: ['All', 'ACTIVE', 'Pending', 'Resolved', 'Escalated'],
                          selectedValue: _statusFilter,
                          onSelected: (value) => setState(() => _statusFilter = value),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Time Filter
                        _buildFilterChipGroup(
                          label: 'Time Period',
                          options: ['All Time', 'This Week', 'This Month'],
                          selectedValue: _timeFilter,
                          onSelected: (value) => setState(() => _timeFilter = value),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Footer
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey[200]!),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                              _statusFilter = 'All';
                              _timeFilter = 'All Time';
                            });
                          },
                          child: const Text(
                            'Clear All',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Apply Filters',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChipGroup({
    required String label,
    required List<String> options,
    required String selectedValue,
    required Function(String) onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: options.map((option) {
            final isSelected = selectedValue == option;
            return FilterChip(
              label: Text(option),
              selected: isSelected,
              onSelected: (selected) => onSelected(option),
              backgroundColor: Colors.white,
              selectedColor: const Color(0xFF2563EB).withOpacity(0.1),
              checkmarkColor: const Color(0xFF2563EB),
              labelStyle: TextStyle(
                color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
              side: BorderSide(
                color: isSelected ? const Color(0xFF2563EB) : Colors.grey[300]!,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildActiveAlertsTab() {
    final filteredAlerts = _getFilteredActiveAlerts();
    
    if (_isLoadingActive) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _isLoadingActive = true);
        await Future.delayed(const Duration(milliseconds: 500));
        _setupActiveSOSListener();
      },
      child: filteredAlerts.isEmpty
          ? _buildEmptyActiveState()
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: filteredAlerts.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                return _buildActiveAlertCard(filteredAlerts[index]);
              },
            ),
    );
  }

  Widget _buildResolvedAlertsTab() {
    final filteredAlerts = _getFilteredResolvedAlerts();
    
    if (_isLoadingResolved) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return RefreshIndicator(
      onRefresh: _fetchResolvedAlerts,
      child: filteredAlerts.isEmpty
          ? _buildEmptyResolvedState()
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: filteredAlerts.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _buildResolvedAlertCard(filteredAlerts[index]);
              },
            ),
    );
  }

  Widget _buildEmptyActiveState() {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
        Icon(
          Icons.check_circle_outline,
          size: 64,
          color: Colors.grey[400],
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            _searchQuery.isNotEmpty
                ? 'No active alerts match your search'
                : 'No active SOS alerts from your organization',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'All employees are safe',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyResolvedState() {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
        Icon(
          Icons.history,
          size: 64,
          color: Colors.grey[400],
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            _searchQuery.isNotEmpty
                ? 'No resolved alerts match your search'
                : 'No resolved SOS alerts found',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Resolved alerts will appear here',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveAlertCard(SOSAlert alert) {
    return InkWell(
      onTap: () => _showActiveAlertDetails(alert),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _getStatusColor(alert.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getStatusIcon(alert.status),
                color: _getStatusColor(alert.status),
                size: 24,
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Alert Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          alert.customerName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      _buildStatusBadge(alert.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.email, size: 14, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Text(
                        alert.customerEmail,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 14, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          alert.address,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 14, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Text(
                        _formatTimestamp(alert.timestamp),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  // Driver information if available
                  if (alert.driverName != null && alert.driverName!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.drive_eta, size: 14, color: Color(0xFF10B981)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Driver: ${alert.driverName}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF10B981),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (alert.vehicleReg != null && alert.vehicleReg!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.directions_car, size: 14, color: Color(0xFF2563EB)),
                        const SizedBox(width: 6),
                        Text(
                          'Vehicle: ${alert.vehicleReg}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF2563EB),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Action Button
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 16),
              color: const Color(0xFF64748B),
              onPressed: () => _showActiveAlertDetails(alert),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResolvedAlertCard(ResolvedSOSAlert alert) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.shade200, width: 1),
      ),
      child: InkWell(
        onTap: () => _showResolvedAlertDetails(alert),
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
                    child: Icon(Icons.check_circle, color: Colors.green.shade700, size: 24),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_camera, size: 14, color: Colors.blue.shade700),
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
                _buildInfoRow(Icons.person, 'Driver: ${alert.driverName}'),
                const SizedBox(height: 4),
              ],
              if (alert.vehicleReg != null) ...[
                _buildInfoRow(Icons.directions_car, 'Vehicle: ${alert.vehicleReg}'),
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
                  if (alert.hasCoordinates)
                    TextButton.icon(
                      onPressed: () => _showResolvedMapDialog(alert),
                      icon: const Icon(Icons.map, size: 16),
                      label: const Text('View on Map'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.green[700],
                      ),
                    ),
                  if (alert.hasCoordinates) const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _showResolvedAlertDetails(alert),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('View Details'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue[700],
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

  Widget _buildStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _getStatusColor(status).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: _getStatusColor(status),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'ACTIVE':
      case 'Pending':
        return const Color(0xFFEF4444);
      case 'In Progress':
        return const Color(0xFFF59E0B);
      case 'Resolved':
        return const Color(0xFF10B981);
      case 'Escalated':
        return const Color(0xFF8B5CF6);
      default:
        return const Color(0xFF64748B);
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'ACTIVE':
      case 'Pending':
        return Icons.warning_amber_rounded;
      case 'In Progress':
        return Icons.pending_actions;
      case 'Resolved':
        return Icons.check_circle;
      case 'Escalated':
        return Icons.priority_high;
      default:
        return Icons.info;
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM dd, yyyy • hh:mm a').format(timestamp);
    }
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

  Future<void> _downloadImage(String imageUrl, String filename) async {
    try {
      debugPrint('📥 Downloading image: $imageUrl');
      
      if (kIsWeb) {
        // Show loading message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⏳ Preparing download...'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 2),
            ),
          );
        }

        // Fetch the image as bytes
        final response = await http.get(Uri.parse(imageUrl));
        
        if (response.statusCode == 200) {
          // Convert bytes to blob
          final blob = html.Blob([response.bodyBytes]);
          final url = html.Url.createObjectUrlFromBlob(blob);
          
          // Create anchor element for download
          final anchor = html.AnchorElement(href: url)
            ..setAttribute('download', filename)
            ..style.display = 'none';
          
          // Trigger download
          html.document.body?.append(anchor);
          anchor.click();
          
          // Cleanup
          html.document.body?.children.remove(anchor);
          html.Url.revokeObjectUrl(url);
          
          debugPrint('✅ Download triggered for web');
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Download started! Check your downloads folder.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          throw Exception('Failed to fetch image: ${response.statusCode}');
        }
      } else {
        // For mobile/desktop, you would use different approach
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

  void _showActiveAlertDetails(SOSAlert alert) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.favorite,
                color: Color(0xFF2563EB),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'We Care About You',
                style: TextStyle(
                  fontSize: 18,
                  color: Color(0xFF2563EB),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Caring Message
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF2563EB).withOpacity(0.1),
                      const Color(0xFF1D4ED8).withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF2563EB).withOpacity(0.2),
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.family_restroom,
                      color: Color(0xFF2563EB),
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '💙 Dear Valued Organization Partner,',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your employee is in SAFE HANDS! 🤝 Abra Travels Management has immediately activated our emergency response protocol. Our dedicated team is actively coordinating with local authorities and emergency services to ensure your employee\'s safety and well-being. Rest assured, we are treating this with the highest priority and will keep you updated every step of the way.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF475569),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    // Additional reassurance badges
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF10B981).withOpacity(0.3),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                color: Color(0xFF10B981),
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Emergency Protocol Active',
                                style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF2563EB).withOpacity(0.3),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.support_agent,
                                color: Color(0xFF2563EB),
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '24/7 Support Team',
                                style: TextStyle(
                                  color: Color(0xFF2563EB),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF10B981).withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.security,
                            color: Color(0xFF10B981),
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Your safety is our priority',
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Alert Details
              const Text(
                'Alert Details:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              
              // Employee Information Section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF2563EB).withOpacity(0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person, color: const Color(0xFF2563EB), size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          'EMPLOYEE INFORMATION',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2563EB),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow('Name', alert.customerName),
                    _buildDetailRow('Email', alert.customerEmail),
                    _buildDetailRow('Status', alert.status),
                    _buildDetailRow('Alert Time', DateFormat('MMM dd, yyyy • hh:mm a').format(alert.timestamp)),
                  ],
                ),
              ),
              
              const SizedBox(height: 12),
              
              // Driver & Vehicle Information Section
              if (alert.driverName != null || alert.vehicleReg != null || alert.tripId != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF10B981).withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.drive_eta, color: const Color(0xFF10B981), size: 18),
                          const SizedBox(width: 8),
                          const Text(
                            'DRIVER & VEHICLE DETAILS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (alert.driverName != null && alert.driverName!.isNotEmpty)
                        _buildDetailRow('Driver Name', alert.driverName!),
                      if (alert.driverPhone != null && alert.driverPhone!.isNotEmpty)
                        _buildDetailRow('Driver Phone', alert.driverPhone!),
                      if (alert.vehicleReg != null && alert.vehicleReg!.isNotEmpty)
                        _buildDetailRow('Vehicle Registration', alert.vehicleReg!),
                      if (alert.tripId != null && alert.tripId!.isNotEmpty)
                        _buildDetailRow('Trip ID', alert.tripId!),
                    ],
                  ),
                ),
              
              if (alert.driverName != null || alert.vehicleReg != null || alert.tripId != null)
                const SizedBox(height: 12),
              
              // Location Information Section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withOpacity(0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on, color: const Color(0xFFEF4444), size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          'LOCATION INFORMATION',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFEF4444),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow('Address', alert.address),
                    if (alert.latitude != null && alert.longitude != null)
                      _buildDetailRow('Coordinates', '${alert.latitude!.toStringAsFixed(6)}, ${alert.longitude!.toStringAsFixed(6)}'),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (alert.latitude != null && alert.longitude != null)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showMapDialog(alert);
              },
              icon: const Icon(Icons.map, size: 16),
              label: const Text('View on Map'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
              ),
            ),
        ],
      ),
    );
  }

  void _showMapDialog(SOSAlert alert) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SOS Alert Location',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            alert.customerName,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              
              // Map
              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(alert.latitude!, alert.longitude!),
                    initialZoom: 16.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.abra_fleet',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(alert.latitude!, alert.longitude!),
                          width: 120,
                          height: 80,
                          child: Column(
                            children: [
                              Icon(
                                Icons.location_on,
                                color: Colors.red.shade700,
                                size: 40,
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.black54),
                                ),
                                child: Text(
                                  alert.customerName,
                                  style: TextStyle(
                                    color: Colors.red[900],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Footer with location details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            alert.address,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          'Alert Time: ${DateFormat('MMM dd, yyyy • hh:mm a').format(alert.timestamp)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showResolvedAlertDetails(ResolvedSOSAlert alert) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
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
                    Icon(Icons.check_circle, color: Colors.green.shade700, size: 32),
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
                            _formatDateTime(alert.resolvedAt ?? alert.timestamp),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Map button in header if coordinates are available
                    if (alert.hasCoordinates) ...[
                      IconButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _showResolvedMapDialog(alert);
                        },
                        icon: const Icon(Icons.map),
                        tooltip: 'View on Map',
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
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
                      _buildDetailSection('Employee Information', [
                        _buildDetailRow('Name', alert.customerName),
                        if (alert.customerEmail.isNotEmpty)
                          _buildDetailRow('Email', alert.customerEmail),
                        if (alert.customerPhone.isNotEmpty)
                          _buildDetailRow('Phone', alert.customerPhone),
                      ]),
                      const SizedBox(height: 16),
                      if (alert.driverName != null || alert.vehicleReg != null) ...[
                        _buildDetailSection('Trip Information', [
                          if (alert.driverName != null)
                            _buildDetailRow('Driver', alert.driverName!),
                          if (alert.driverPhone != null)
                            _buildDetailRow('Driver Phone', alert.driverPhone!),
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                alert.resolution!['photoFilename'] ?? 'sos_proof.jpg',
                              ),
                              icon: const Icon(Icons.download, size: 16),
                              label: const Text('Download'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Resolution Photo
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
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.broken_image, size: 48, color: Colors.grey),
                                        SizedBox(height: 8),
                                        Text('Failed to load image'),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              loadingBuilder: (context, child, loadingProgress) {
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
                        // Resolution Notes
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

  void _showResolvedMapDialog(ResolvedSOSAlert alert) {
    // Extract coordinates from the alert - you may need to adjust this based on your data structure
    double? latitude;
    double? longitude;
    
    // Try to get coordinates from resolution data or main alert data
    if (alert.resolution != null) {
      latitude = alert.resolution!['latitude']?.toDouble();
      longitude = alert.resolution!['longitude']?.toDouble();
    }
    
    // If no coordinates found, show error
    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location coordinates not available for this alert'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Now we know latitude and longitude are not null
    final double lat = latitude;
    final double lng = longitude;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Resolved SOS Location',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            alert.customerName,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              
              // Map
              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(lat, lng),
                    initialZoom: 16.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.abra_fleet',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(lat, lng),
                          width: 120,
                          height: 80,
                          child: Column(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.green.shade700,
                                size: 40,
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.black54),
                                ),
                                child: Text(
                                  alert.customerName,
                                  style: TextStyle(
                                    color: Colors.green[900],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Footer with location details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 16, color: Colors.green[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            alert.address,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.check_circle, size: 16, color: Colors.green[700]),
                        const SizedBox(width: 8),
                        Text(
                          'Resolved: ${_formatDateTime(alert.resolvedAt ?? alert.timestamp)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF64748B),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _sosSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }
}

// Resolved SOS Alert Model (similar to admin's ResolvedSOSAlert)
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
      notes: json['resolution']?['notes']?.toString() ?? json['notes']?.toString() ?? '',
    );
  }

  bool get hasResolutionProof => resolution != null && 
      resolution!['photoUrl'] != null && 
      resolution!['notes'] != null;
      
  bool get hasCoordinates => resolution != null && 
      resolution!['latitude'] != null && 
      resolution!['longitude'] != null;
}

// SOS Alert Model
class SOSAlert {
  final String id;
  final String customerId;
  final String customerName;
  final String customerEmail;
  final String address;
  final String status;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  
  // Driver information
  final String? driverName;
  final String? driverPhone;
  final String? vehicleReg;
  final String? tripId;
  final String? liveTrackingUrl; // ✅ ADDED: Live tracking URL from SOS alert

  SOSAlert({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.customerEmail,
    required this.address,
    required this.status,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.driverName,
    this.driverPhone,
    this.vehicleReg,
    this.tripId,
    this.liveTrackingUrl, // ✅ ADDED: Live tracking URL parameter
  });

  factory SOSAlert.fromMap(String id, Map<String, dynamic> map) {
    return SOSAlert(
      id: id,
      customerId: map['customerId'] ?? '',
      customerName: map['customerName'] ?? 'Unknown',
      customerEmail: map['customerEmail'] ?? '',
      address: map['address'] ?? 'Location not available',
      status: map['status'] ?? 'Pending',
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : DateTime.now(),
      latitude: map['gps']?['latitude']?.toDouble(),
      longitude: map['gps']?['longitude']?.toDouble(),
      driverName: map['driverName'],
      driverPhone: map['driverPhone'],
      vehicleReg: map['vehicleReg'],
      tripId: map['tripId'],
      liveTrackingUrl: map['liveTrackingUrl'], // ✅ ADDED: Parse live tracking URL
    );
  }
}