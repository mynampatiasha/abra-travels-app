// lib/features/admin/rosters/pending_rosters_screen.dart
// COMPLETE VERSION - All original features + New assignment system

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:abra_fleet/core/services/assignment_service.dart';
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:abra_fleet/features/admin/customer_management/notification/rosters/vehicle_selection_dialog.dart';
import 'package:abra_fleet/features/admin/customer_management/notification/rosters/group_details_dialog.dart';

import 'package:intl/intl.dart';

class PendingRostersScreen extends StatefulWidget {
  final Function(Map<String, dynamic>)? onRosterTapped;

  const PendingRostersScreen({
    super.key,
    this.onRosterTapped,
  });

  @override
  State<PendingRostersScreen> createState() => _PendingRostersScreenState();
}

class _PendingRostersScreenState extends State<PendingRostersScreen> {
  // ==========================================
  // STATE VARIABLES
  // ==========================================
  
  // Assignment Service
  late final AssignmentService _assignmentService;
  
  // Data Source
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _individuals = [];
  int _totalPending = 0;
  
  // UI State
  bool _isLoading = true;
  String? _errorMessage;
  final ScrollController _scrollController = ScrollController();
  bool _showFilters = true; // Changed to true by default
  
  // Filter State
  String _searchQuery = '';
  String _selectedRosterType = 'All';
  String _selectedOrganization = 'All Organizations';
  String _selectedPriority = 'All';
  DateTimeRange? _selectedDateRange;
  String _selectedSortOrder = 'Priority First';
  List<String> _availableOrganizations = ['All Organizations'];
  
  // View Mode
  bool _showGrouped = true; // Toggle between grouped and flat view
  
  // Auto-refresh timer
  Timer? _refreshTimer;

  // Theme Constants
  final Color _themeColor = const Color(0xFF10B981);
  final Color _neutralBg = const Color(0xFFF8FAFC);
  final Color _cardBorder = const Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    debugPrint('🚀 PendingRostersScreen: initState() called');
    
    // Initialize AssignmentService with ApiService
    _assignmentService = AssignmentService(apiService: ApiService());
    
    _loadPendingRosters();
    
    // Auto-refresh every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadPendingRosters(silent: true);
    });
  }

  @override
  void dispose() {
    debugPrint('🗑️ PendingRostersScreen: dispose() called');
    _scrollController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// 🔥 SAFE STRING EXTRACTION
  String _safeStringExtract(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is Map) {
      try {
        if (value.containsKey('name')) return _safeStringExtract(value['name']);
        if (value.containsKey('value')) return _safeStringExtract(value['value']);
        if (value.containsKey('address')) return _safeStringExtract(value['address']);
        if (value.containsKey('text')) return _safeStringExtract(value['text']);
        if (value.containsKey('email')) return _safeStringExtract(value['email']);
        return value.toString();
      } catch (e) {
        return value.toString();
      }
    }
    if (value is List) {
      if (value.isNotEmpty) {
        return _safeStringExtract(value.first);
      }
      return '';
    }
    return value.toString();
  }

  /// 🔥 SAFE NESTED ACCESS
  String _safeNestedAccess(Map<dynamic, dynamic> data, String key, [String? nestedKey]) {
    try {
      final value = data[key];
      if (nestedKey != null && value is Map) {
        return _safeStringExtract(value[nestedKey]);
      }
      return _safeStringExtract(value);
    } catch (e) {
      debugPrint('⚠️ Nested access error for $key${nestedKey != null ? '.$nestedKey' : ''}: $e');
      return '';
    }
  }

  // ==========================================
  // SAFE SNACKBAR DISPLAY
  // ==========================================
  
  void _showSnackBar(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      try {
        final scaffold = ScaffoldMessenger.maybeOf(context);
        if (scaffold != null) {
          scaffold.showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: backgroundColor ?? _themeColor,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        debugPrint('❌ Error showing SnackBar: $e');
      }
    });
  }

  // ==========================================
  // LOAD PENDING ROSTERS
  // ==========================================
  
  Future<void> _loadPendingRosters({bool silent = false}) async {
    debugPrint('\n' + '📋'*40);
    debugPrint('LOADING PENDING ROSTERS (Silent: $silent)');
    debugPrint('📋'*40);
    
    try {
      if (!silent) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }

      final result = await _assignmentService.getPendingRosters();
      
      if (result['success'] == true) {
        // ✅ FIX: Access data from result['data'] not result directly
        final data = result['data'] ?? {};
        final groups = List<Map<String, dynamic>>.from(data['groups'] ?? []);
        final individuals = List<Map<String, dynamic>>.from(data['individuals'] ?? []);
        final totalPending = data['totalPending'] ?? 0;
        
        // Extract organizations
        final organizations = <String>{'All Organizations'};
        
        // From groups
        for (final group in groups) {
          final domain = _safeStringExtract(group['emailDomain']);
          if (domain.isNotEmpty && domain != 'unknown') {
            organizations.add(domain);
          }
        }
        
        // From individuals
        for (final roster in individuals) {
          final email = _safeStringExtract(roster['customerEmail']);
          if (email.isNotEmpty && email.contains('@')) {
            final domain = email.split('@')[1];
            organizations.add(domain);
          }
        }
        
        setState(() {
          _groups = groups;
          _individuals = individuals;
          _totalPending = totalPending;
          _availableOrganizations = organizations.toList()..sort();
          _isLoading = false;
        });
        
        debugPrint('✅ Loaded: ${groups.length} groups, ${individuals.length} individuals');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading pending rosters: $e');
      debugPrint('Stack trace: $stackTrace');
      
      if (!silent) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
        
        _showSnackBar('Failed to load pending rosters', backgroundColor: Colors.red);
      }
    }
    
    debugPrint('📋'*40 + '\n');
  }

  // ==========================================
  // ASSIGNMENT ACTIONS
  // ==========================================
  
  void _showAssignmentDialog(List<String> rosterIds, {String? groupName}) {
    // 🔍 COMPREHENSIVE ASSIGNMENT DIALOG DEBUGGING
    debugPrint('\n' + '📋' * 80);
    debugPrint('📋 ASSIGNMENT DIALOG DEBUG - START');
    debugPrint('📋' * 80);
    debugPrint('📍 Location: PendingRostersScreen._showAssignmentDialog()');
    debugPrint('⏰ Timestamp: ${DateTime.now().toIso8601String()}');
    debugPrint('📋 Roster IDs: $rosterIds');
    debugPrint('📊 Roster Count: ${rosterIds.length}');
    debugPrint('🏷️ Group Name: ${groupName ?? 'N/A'}');
    debugPrint('🔧 Assignment Service: ${_assignmentService.runtimeType}');
    debugPrint('🔧 Assignment Service API Service: ${_assignmentService.apiService.runtimeType}');
    debugPrint('🌐 Assignment Service Base URL: ${_assignmentService.apiService.baseUrl}');
    debugPrint('🏗️ Context Available: ${context != null}');
    debugPrint('🏗️ Widget Mounted: $mounted');
    
    // Debug: Check environment variables
    debugPrint('\n🔧 ENVIRONMENT CHECK:');
    debugPrint('   API_BASE_URL from .env: ${const String.fromEnvironment('API_BASE_URL', defaultValue: 'NOT_SET')}');
    debugPrint('   Current API Service Base URL: ${_assignmentService.apiService.baseUrl}');
    
    // Debug: Validate roster IDs
    debugPrint('\n📋 ROSTER IDS VALIDATION:');
    for (int i = 0; i < rosterIds.length; i++) {
      final rosterId = rosterIds[i];
      debugPrint('   ${i + 1}. "$rosterId" (length: ${rosterId.length}, type: ${rosterId.runtimeType})');
      
      // Check if it's a valid ObjectId format
      final isValidObjectId = RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(rosterId);
      debugPrint('      Valid ObjectId format: $isValidObjectId');
    }
    
    debugPrint('📋' * 80);
    
    debugPrint('\n📤 SHOWING VEHICLE SELECTION DIALOG...');
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        debugPrint('   🏗️ Building VehicleSelectionDialog...');
        debugPrint('   📋 Passing Roster IDs: $rosterIds');
        debugPrint('   🔧 Passing Assignment Service: ${_assignmentService.runtimeType}');
        debugPrint('   🌐 Assignment Service Base URL: ${_assignmentService.apiService.baseUrl}');
        
        return VehicleSelectionDialog(
          rosterIds: rosterIds,
          assignmentService: _assignmentService,
          onAssignmentSuccess: () {
            debugPrint('\n✅ ASSIGNMENT SUCCESS CALLBACK TRIGGERED');
            debugPrint('   🔄 Refreshing pending rosters...');
            
            // Refresh the list after successful assignment
            _loadPendingRosters();
            
            debugPrint('   ✅ Refresh initiated');
          },
        );
      },
    );
    
    debugPrint('   ✅ Dialog shown successfully');
    debugPrint('📋' * 80 + '\n');
  }

  // ==========================================
  // FILTER FUNCTIONALITY
  // ==========================================
  
  List<Map<String, dynamic>> _getFilteredGroups() {
    List<Map<String, dynamic>> filtered = List.from(_groups);
    
    // Apply organization filter
    if (_selectedOrganization != 'All Organizations') {
      filtered = filtered.where((group) {
        final domain = _safeStringExtract(group['emailDomain']);
        return domain == _selectedOrganization;
      }).toList();
    }
    
    // Apply roster type filter
    if (_selectedRosterType != 'All') {
      filtered = filtered.where((group) {
        final type = _safeStringExtract(group['rosterType']).toLowerCase();
        return type == _selectedRosterType.toLowerCase();
      }).toList();
    }
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((group) {
        final location = _safeStringExtract(group['officeLocation']).toLowerCase();
        final domain = _safeStringExtract(group['emailDomain']).toLowerCase();
        final query = _searchQuery.toLowerCase();
        return location.contains(query) || domain.contains(query);
      }).toList();
    }
    
    // Apply date range filter
    if (_selectedDateRange != null) {
      filtered = filtered.where((group) {
        try {
          final dateStr = _safeStringExtract(group['startDate']);
          if (dateStr.isNotEmpty) {
            final date = DateTime.parse(dateStr);
            return date.isAfter(_selectedDateRange!.start.subtract(const Duration(days: 1))) &&
                   date.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
          }
        } catch (e) {
          debugPrint('⚠️ Error parsing date for group: $e');
        }
        return false;
      }).toList();
    }
    
    // Apply sorting
    _applySortingToGroups(filtered);
    
    return filtered;
  }
  
  List<Map<String, dynamic>> _getFilteredIndividuals() {
    List<Map<String, dynamic>> filtered = List.from(_individuals);
    
    // Apply organization filter
    if (_selectedOrganization != 'All Organizations') {
      filtered = filtered.where((roster) {
        final email = _safeStringExtract(roster['customerEmail']);
        if (email.isNotEmpty && email.contains('@')) {
          final domain = email.split('@')[1];
          return domain == _selectedOrganization;
        }
        return false;
      }).toList();
    }
    
    // Apply roster type filter
    if (_selectedRosterType != 'All') {
      filtered = filtered.where((roster) {
        final type = _safeStringExtract(roster['rosterType']).toLowerCase();
        return type == _selectedRosterType.toLowerCase();
      }).toList();
    }
    
    // Apply priority filter
    if (_selectedPriority != 'All') {
      filtered = filtered.where((roster) {
        final priority = _safeStringExtract(roster['priority']).toLowerCase();
        return priority == _selectedPriority.toLowerCase();
      }).toList();
    }
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((roster) {
        final customerName = _safeStringExtract(roster['customerName']).toLowerCase();
        final customerEmail = _safeStringExtract(roster['customerEmail']).toLowerCase();
        final officeLocation = _safeStringExtract(roster['officeLocation']).toLowerCase();
        final query = _searchQuery.toLowerCase();
        
        return customerName.contains(query) || 
               customerEmail.contains(query) || 
               officeLocation.contains(query);
      }).toList();
    }
    
    // Apply date range filter
    if (_selectedDateRange != null) {
      filtered = filtered.where((roster) {
        try {
          final dateStr = _safeStringExtract(roster['createdAt']);
          if (dateStr.isNotEmpty) {
            final date = DateTime.parse(dateStr);
            return date.isAfter(_selectedDateRange!.start.subtract(const Duration(days: 1))) &&
                   date.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
          }
        } catch (e) {
          debugPrint('⚠️ Error parsing date for roster: $e');
        }
        return false;
      }).toList();
    }
    
    // Apply sorting
    _applySortingToIndividuals(filtered);
    
    return filtered;
  }

  void _applySortingToGroups(List<Map<String, dynamic>> groups) {
    switch (_selectedSortOrder) {
      case 'Newest First':
        groups.sort((a, b) {
          try {
            final dateA = DateTime.parse(_safeStringExtract(a['startDate']));
            final dateB = DateTime.parse(_safeStringExtract(b['startDate']));
            return dateB.compareTo(dateA);
          } catch (e) {
            return 0;
          }
        });
        break;
        
      case 'Oldest First':
        groups.sort((a, b) {
          try {
            final dateA = DateTime.parse(_safeStringExtract(a['startDate']));
            final dateB = DateTime.parse(_safeStringExtract(b['startDate']));
            return dateA.compareTo(dateB);
          } catch (e) {
            return 0;
          }
        });
        break;
        
      case 'Largest First':
        groups.sort((a, b) {
          final countA = a['employeeCount'] ?? 0;
          final countB = b['employeeCount'] ?? 0;
          return countB.compareTo(countA);
        });
        break;
        
      case 'Smallest First':
        groups.sort((a, b) {
          final countA = a['employeeCount'] ?? 0;
          final countB = b['employeeCount'] ?? 0;
          return countA.compareTo(countB);
        });
        break;
    }
  }
  
  void _applySortingToIndividuals(List<Map<String, dynamic>> rosters) {
    switch (_selectedSortOrder) {
      case 'Priority First':
        rosters.sort((a, b) {
          final priorityA = _safeStringExtract(a['priority']).toLowerCase();
          final priorityB = _safeStringExtract(b['priority']).toLowerCase();
          
          final priorityOrder = {'high': 3, 'medium': 2, 'low': 1};
          final orderA = priorityOrder[priorityA] ?? 0;
          final orderB = priorityOrder[priorityB] ?? 0;
          
          return orderB.compareTo(orderA);
        });
        break;
        
      case 'Newest First':
        rosters.sort((a, b) {
          try {
            final dateA = DateTime.parse(_safeStringExtract(a['createdAt']));
            final dateB = DateTime.parse(_safeStringExtract(b['createdAt']));
            return dateB.compareTo(dateA);
          } catch (e) {
            return 0;
          }
        });
        break;
        
      case 'Oldest First':
        rosters.sort((a, b) {
          try {
            final dateA = DateTime.parse(_safeStringExtract(a['createdAt']));
            final dateB = DateTime.parse(_safeStringExtract(b['createdAt']));
            return dateA.compareTo(dateB);
          } catch (e) {
            return 0;
          }
        });
        break;
        
      case 'Name A-Z':
        rosters.sort((a, b) {
          final nameA = _safeStringExtract(a['customerName']).toLowerCase();
          final nameB = _safeStringExtract(b['customerName']).toLowerCase();
          return nameA.compareTo(nameB);
        });
        break;
        
      case 'Name Z-A':
        rosters.sort((a, b) {
          final nameA = _safeStringExtract(a['customerName']).toLowerCase();
          final nameB = _safeStringExtract(b['customerName']).toLowerCase();
          return nameB.compareTo(nameA);
        });
        break;
    }
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _selectedRosterType = 'All';
      _selectedOrganization = 'All Organizations';
      _selectedPriority = 'All';
      _selectedDateRange = null;
      _selectedSortOrder = 'Priority First';
    });
  }

  bool _hasActiveFilters() {
    return _searchQuery.isNotEmpty ||
           _selectedRosterType != 'All' ||
           _selectedOrganization != 'All Organizations' ||
           _selectedPriority != 'All' ||
           _selectedDateRange != null;
  }

  // ==========================================
  // DATE RANGE PICKER
  // ==========================================
  
  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _themeColor,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
      });
    }
  }

  // ==========================================
  // ROSTER DETAILS DIALOG
  // ==========================================
  
  void _showRosterDetailsDialog(Map<String, dynamic> roster) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 500,
          constraints: const BoxConstraints(maxHeight: 600),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: _themeColor, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Roster Details',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 32),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow('Customer Name', _safeStringExtract(roster['customerName'])),
                      _buildDetailRow('Email', _safeStringExtract(roster['customerEmail'])),
                      _buildDetailRow('Phone', _safeStringExtract(roster['customerPhone'])),
                      _buildDetailRow('Office Location', _safeStringExtract(roster['officeLocation'])),
                      _buildDetailRow('Roster Type', _safeStringExtract(roster['rosterType'])),
                      _buildDetailRow('Start Time', _safeStringExtract(roster['startTime'])),
                      _buildDetailRow('End Time', _safeStringExtract(roster['endTime'])),
                      _buildDetailRow('Start Date', _safeStringExtract(roster['startDate'])),
                      _buildDetailRow('End Date', _safeStringExtract(roster['endDate'])),
                      _buildDetailRow('Priority', _safeStringExtract(roster['priority'])),
                      _buildDetailRow('Status', _safeStringExtract(roster['status'])),
                      _buildDetailRow('Created At', _safeStringExtract(roster['createdAt'])),
                      
                      const SizedBox(height: 16),
                      const Text(
                        'Pickup Location:',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow('Address', _safeNestedAccess(roster, 'locations', 'pickup')),
                      
                      const SizedBox(height: 16),
                      const Text(
                        'Drop Location:',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow('Address', _safeNestedAccess(roster, 'locations', 'drop')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    final rosterId = roster['_id']?.toString();
                    if (rosterId != null) {
                      _showAssignmentDialog([rosterId]);
                    }
                  },
                  icon: const Icon(Icons.local_shipping),
                  label: const Text('Assign Vehicle'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _themeColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : 'N/A',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // MAIN UI BUILDER
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final filteredGroups = _getFilteredGroups();
    final filteredIndividuals = _getFilteredIndividuals();
    final totalFiltered = filteredGroups.length + filteredIndividuals.length;
    
    return Scaffold(
      backgroundColor: _neutralBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with Stats
          _buildHeader(filteredGroups.length, filteredIndividuals.length),

          // Filter Bar (if enabled)
          if (_showFilters) _buildFilterBar(),

          // Active Filter Chips
          if (_hasActiveFilters()) _buildActiveFiltersRow(),

          // Main Content
          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : _errorMessage != null
                    ? _buildErrorState()
                    : totalFiltered == 0
                        ? _buildEmptyState()
                        : _buildRosterList(filteredGroups, filteredIndividuals),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // HEADER & STATS
  // ==========================================

  Widget _buildHeader(int groupCount, int individualCount) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pending Rosters',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              Row(
                children: [
                  // Debug Test Button (temporary)
                  ElevatedButton.icon(
                    onPressed: () async {
                      debugPrint('🧪 Running assignment service debug test...');
                      try {
                        final result = await _assignmentService.debugTestEndpoint();
                        _showSnackBar('Debug test completed. Check console for details.');
                      } catch (e) {
                        _showSnackBar('Debug test failed: $e', backgroundColor: Colors.red);
                      }
                    },
                    icon: const Icon(Icons.bug_report, size: 18),
                    label: const Text('Debug Test'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Refresh Button
                  IconButton(
                    onPressed: () => _loadPendingRosters(),
                    icon: Icon(Icons.refresh, color: _themeColor),
                    tooltip: 'Refresh',
                  ),
                  const SizedBox(width: 8),
                  // Toggle Filter Button
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _showFilters = !_showFilters);
                    },
                    icon: Icon(
                      _showFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
                      size: 18,
                    ),
                    label: Text(_showFilters ? 'Hide Filters' : 'Show Filters'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _themeColor,
                      side: BorderSide(color: _themeColor),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Stats Row
          Row(
            children: [
              _buildStatCard('Total', '$_totalPending', Icons.folder_open, const Color(0xFF475569)),
              const SizedBox(width: 12),
              _buildStatCard('Groups', '$groupCount', Icons.groups, _themeColor),
              const SizedBox(width: 12),
              _buildStatCard('Individual', '$individualCount', Icons.person, const Color(0xFF3B82F6)),
              const SizedBox(width: 12),
              _buildStatCard('Organizations', '${_availableOrganizations.length - 1}', Icons.business, const Color(0xFF8B5CF6)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // FILTER BAR
  // ==========================================

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Row 1: Search and Organization
          Row(
            children: [
              // Search Field
              Expanded(
                flex: 2,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by name, email, location...',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _cardBorder),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),

              // Organization Dropdown
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Organization',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: _cardBorder),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _availableOrganizations.contains(_selectedOrganization)
                            ? _selectedOrganization
                            : 'All Organizations',
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                          style: const TextStyle(fontSize: 14, color: Color(0xFF334155)),
                          items: _availableOrganizations.map((String val) {
                            return DropdownMenuItem(value: val, child: Text(val));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedOrganization = val;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Row 2: Filter Chips and Controls
          Row(
            children: [
              // Roster Type Chips
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Roster Type',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['All', 'Login', 'Logout', 'Both'].map((type) {
                        final isSelected = _selectedRosterType == type;
                        return FilterChip(
                          label: Text(type),
                          selected: isSelected,
                          onSelected: (val) {
                            setState(() {
                              _selectedRosterType = type;
                            });
                          },
                          selectedColor: _themeColor,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : const Color(0xFF334155),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          backgroundColor: const Color(0xFFF1F5F9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isSelected ? _themeColor : _cardBorder,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // Priority Chips (for individuals)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Priority',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['All', 'High', 'Medium', 'Low'].map((priority) {
                        final isSelected = _selectedPriority == priority;
                        return FilterChip(
                          label: Text(priority),
                          selected: isSelected,
                          onSelected: (val) {
                            setState(() {
                              _selectedPriority = priority;
                            });
                          },
                          selectedColor: _themeColor,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : const Color(0xFF334155),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          backgroundColor: const Color(0xFFF1F5F9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isSelected ? _themeColor : _cardBorder,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Row 3: Sort and Date Range
          Row(
            children: [
              // Sort Dropdown
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sort By',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: _cardBorder),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedSortOrder,
                          isExpanded: true,
                          icon: const Icon(Icons.sort, size: 18),
                          style: const TextStyle(fontSize: 14, color: Color(0xFF334155)),
                          items: [
                            'Priority First',
                            'Newest First',
                            'Oldest First',
                            'Name A-Z',
                            'Name Z-A',
                            'Largest First',
                            'Smallest First',
                          ].map((String val) {
                            return DropdownMenuItem(value: val, child: Text(val));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedSortOrder = val;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // Date Range Button
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Date Range',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _selectDateRange,
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        _selectedDateRange == null
                            ? 'Select Date Range'
                            : '${DateFormat('MM/dd').format(_selectedDateRange!.start)} - ${DateFormat('MM/dd').format(_selectedDateRange!.end)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF334155),
                        side: BorderSide(color: _cardBorder),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFiltersRow() {
    return Container(
      color: Colors.white,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            'Active Filters:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF94A3B8),
            ),
          ),
          if (_selectedOrganization != 'All Organizations')
            _buildFilterChip(
              'Org: $_selectedOrganization',
              () => setState(() { _selectedOrganization = 'All Organizations'; })
            ),
          if (_searchQuery.isNotEmpty)
            _buildFilterChip(
              'Search: "$_searchQuery"',
              () => setState(() { _searchQuery = ''; })
            ),
          if (_selectedRosterType != 'All')
            _buildFilterChip(
              'Type: $_selectedRosterType',
              () => setState(() { _selectedRosterType = 'All'; })
            ),
          if (_selectedPriority != 'All')
            _buildFilterChip(
              'Priority: $_selectedPriority',
              () => setState(() { _selectedPriority = 'All'; })
            ),
          if (_selectedDateRange != null)
            _buildFilterChip(
              'Date: ${DateFormat('MM/dd').format(_selectedDateRange!.start)} - ${DateFormat('MM/dd').format(_selectedDateRange!.end)}',
              () => setState(() { _selectedDateRange = null; })
            ),
            
          InkWell(
            onTap: _clearFilters,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                'Clear All',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onDeleted) {
    return Chip(
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF1E293B),
          fontWeight: FontWeight.w500,
        )
      ),
      backgroundColor: const Color(0xFFF1F5F9),
      deleteIcon: const Icon(Icons.close, size: 16, color: Color(0xFF64748B)),
      onDeleted: onDeleted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  // ==========================================
  // ROSTER LIST
  // ==========================================

  Widget _buildRosterList(List<Map<String, dynamic>> groups, List<Map<String, dynamic>> individuals) {
    return RefreshIndicator(
      onRefresh: () => _loadPendingRosters(),
      color: _themeColor,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(20),
        children: [
          // Groups Section
          if (groups.isNotEmpty) ...[
            _buildSectionHeader('📦 Groups (${groups.length})'),
            const SizedBox(height: 12),
            ...groups.map((group) => _buildGroupCard(group)),
            const SizedBox(height: 24),
          ],
          
          // Individuals Section
          if (individuals.isNotEmpty) ...[
            _buildSectionHeader('📄 Individual Rosters (${individuals.length})'),
            const SizedBox(height: 12),
            ...individuals.map((roster) => _buildRosterCard(roster)),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1E293B),
      ),
    );
  }

  // ==========================================
  // GROUP CARD
  // ==========================================

  Widget _buildGroupCard(Map<String, dynamic> group) {
  final emailDomain = _safeStringExtract(group['emailDomain']);
  final officeLocation = _safeStringExtract(group['officeLocation']);
  final rosterType = _safeStringExtract(group['rosterType']);
  final startTime = _safeStringExtract(group['startTime']);
  final employeeCount = group['employeeCount'] ?? 0;
  final rosterIds = List<String>.from(group['rosterIds'] ?? []);
  
  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _cardBorder),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.02),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        // ✅ NEW: Open group details dialog when tapped
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => GroupDetailsDialog(
              group: group,
              assignmentService: _assignmentService,
              onAssignmentSuccess: _loadPendingRosters,
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Group Icon
                  Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: _themeColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.groups,
                      color: _themeColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Group Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$officeLocation - $startTime',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '@$emailDomain • $employeeCount passengers',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Roster Type Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getRosterTypeColor(rosterType).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _getRosterTypeColor(rosterType)),
                    ),
                    child: Text(
                      rosterType.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _getRosterTypeColor(rosterType),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              
              // Passenger Count Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people, size: 16, color: _themeColor),
                    const SizedBox(width: 8),
                    Text(
                      '$employeeCount passengers in this group',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Action Buttons
              Row(
                children: [
                  // View Details Button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => GroupDetailsDialog(
                            group: group,
                            assignmentService: _assignmentService,
                            onAssignmentSuccess: _loadPendingRosters,
                          ),
                        );
                      },
                      icon: const Icon(Icons.visibility, size: 18),
                      label: const Text('View Details'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _themeColor,
                        side: BorderSide(color: _themeColor),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Assign Vehicle Button
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => _showAssignmentDialog(
                        rosterIds,
                        groupName: '$officeLocation - $startTime',
                      ),
                      icon: const Icon(Icons.local_shipping),
                      label: const Text('Assign Vehicle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _themeColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
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
}

  // ==========================================
  // INDIVIDUAL ROSTER CARD
  // ==========================================

  Widget _buildRosterCard(Map<String, dynamic> roster) {
    final rosterId = roster['_id']?.toString() ?? '';
    final customerName = _safeStringExtract(roster['customerName']) != '' 
        ? _safeStringExtract(roster['customerName'])
        : _safeNestedAccess(roster, 'employeeDetails', 'name') != ''
        ? _safeNestedAccess(roster, 'employeeDetails', 'name')
        : 'Unknown Customer';
    
    final customerEmail = _safeStringExtract(roster['customerEmail']) != ''
        ? _safeStringExtract(roster['customerEmail'])
        : _safeNestedAccess(roster, 'employeeDetails', 'email');
    
    final officeLocation = _safeStringExtract(roster['officeLocation']) != ''
        ? _safeStringExtract(roster['officeLocation'])
        : 'Unknown Location';
    
    final rosterType = _safeStringExtract(roster['rosterType']) != ''
        ? _safeStringExtract(roster['rosterType'])
        : 'both';
    
    final startTime = _safeStringExtract(roster['startTime']) != ''
        ? _safeStringExtract(roster['startTime'])
        : 'N/A';
    
    final endTime = _safeStringExtract(roster['endTime']) != ''
        ? _safeStringExtract(roster['endTime'])
        : 'N/A';
    
    final startDate = _safeStringExtract(roster['startDate']);
    String dateDisplay = 'N/A';
    if (startDate.isNotEmpty) {
      try {
        final date = DateTime.parse(startDate);
        dateDisplay = DateFormat('MMM dd, yyyy').format(date);
      } catch (e) {
        dateDisplay = startDate;
      }
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showRosterDetailsDialog(roster),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Roster Type Icon
                    Container(
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        color: _getRosterTypeColor(rosterType).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _getRosterTypeIcon(rosterType),
                        color: _getRosterTypeColor(rosterType),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    
                    // Customer Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customerName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          if (customerEmail.isNotEmpty)
                            Text(
                              customerEmail,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: Color(0xFF94A3B8)
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  officeLocation,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // Roster Type Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getRosterTypeColor(rosterType).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _getRosterTypeColor(rosterType)),
                      ),
                      child: Text(
                        rosterType.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _getRosterTypeColor(rosterType),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                
                // Time and Date Information
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 16, color: const Color(0xFF94A3B8)),
                    const SizedBox(width: 8),
                    Text(
                      dateDisplay,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF334155)),
                    ),
                    const SizedBox(width: 24),
                    Icon(Icons.access_time, size: 16, color: const Color(0xFF94A3B8)),
                    const SizedBox(width: 8),
                    Text(
                      '$startTime - $endTime',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF334155)),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Assign Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showAssignmentDialog([rosterId]),
                    icon: const Icon(Icons.local_shipping),
                    label: const Text('Assign Vehicle'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getRosterTypeIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('login')) return Icons.arrow_forward;
    if (t.contains('logout')) return Icons.arrow_back;
    if (t.contains('both')) return Icons.swap_horiz;
    return Icons.swap_horiz;
  }

  Color _getRosterTypeColor(String type) {
    final t = type.toLowerCase();
    if (t.contains('login')) return _themeColor;
    if (t.contains('logout')) return const Color(0xFF3B82F6);
    if (t.contains('both')) return const Color(0xFF8B5CF6);
    return const Color(0xFF8B5CF6);
  }

  // ==========================================
  // STATE WIDGETS
  // ==========================================

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: _themeColor),
          const SizedBox(height: 16),
          const Text(
            'Loading pending rosters...',
            style: TextStyle(fontSize: 16, color: Color(0xFF64748B)),
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
          Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
          const SizedBox(height: 16),
          const Text(
            'Failed to load pending rosters',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Unknown error occurred',
            style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _loadPendingRosters(),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _themeColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: _themeColor),
          const SizedBox(height: 16),
          const Text(
            'No pending rosters',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'All rosters have been assigned!',
            style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _loadPendingRosters(),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _themeColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
