import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:abra_fleet/core/services/roster_service.dart';
import 'package:abra_fleet/core/services/route_optimization_service.dart';
import 'package:abra_fleet/core/services/vehicle_service.dart';
import 'package:abra_fleet/features/admin/customer_management/widgets/vehicle_confirmation_dialog.dart';
import 'package:abra_fleet/features/admin/customer_management/widgets/route_optimization_dialog.dart';
import 'package:abra_fleet/features/admin/customer_management/widgets/route_optimization_input_dialog.dart';
import 'package:abra_fleet/features/admin/customer_management/widgets/detailed_error_dialog.dart';
import 'package:abra_fleet/core/utils/export_helper.dart';
import 'package:country_state_city/country_state_city.dart' as csc;
import 'package:intl/intl.dart';

class PendingRostersScreen extends StatefulWidget {
  final RosterService rosterService;
  final Function(Map<String, dynamic>)? onRosterTapped;

  const PendingRostersScreen({
    super.key,
    required this.rosterService,
    this.onRosterTapped,
  });

  @override
  State<PendingRostersScreen> createState() => _PendingRostersScreenState();
}

class _PendingRostersScreenState extends State<PendingRostersScreen> {
  // ==========================================
  // STATE VARIABLES
  // ==========================================
  
  // Data Source
  List<Map<String, dynamic>> _allPendingRosters = [];
  List<Map<String, dynamic>> _filteredRosters = [];
  List<String> _availableOrganizations = ['All Organizations'];
  Set<String> _selectedRosterIds = {}; // For bulk selection
  List<Map<String, dynamic>> _availableDrivers = []; // Available drivers for optimization
  
  // Route Optimization - handled directly in this class

  // UI State
  bool _isLoading = true;
  bool _isOptimizing = false; // New loading state for optimization
  bool _isExporting = false; // Export loading state
  String? _errorMessage;
  final ScrollController _scrollController = ScrollController();
  bool _showFilters = true; 

  // Filter State
  String _searchQuery = '';
  String _selectedRosterType = 'All';
  String _selectedOrganization = 'All Organizations';
  String _selectedPriority = 'All';
  String _selectedSortOrder = 'Priority First';
  DateTimeRange? _selectedDateRange; // Date range filter

  // ── Row 1: CSC Filters ────────────────────────────────────────────────────
  String? _filterCountry;
  String? _filterState;
  String? _filterCity;
  String? _filterLocalArea;
  
  // ── CSC Data ───────────────────────────────────────────────────────────────
  List<csc.Country> _countries = [];
  List<csc.State> _states = [];
  List<csc.City> _cities = [];
  bool _loadingCountries = true;
  bool _loadingStates = false;
  bool _loadingCities = false;
  String? _countryIso;
  String? _stateIso;

  // ── Overlay for dropdowns ──────────────────────────────────────────────────
  final LayerLink _lkCountry = LayerLink();
  final LayerLink _lkState = LayerLink();
  final LayerLink _lkCity = LayerLink();
  OverlayEntry? _ovCountry;
  OverlayEntry? _ovState;
  OverlayEntry? _ovCity;
  final TextEditingController _scCountry = TextEditingController();
  final TextEditingController _scState = TextEditingController();
  final TextEditingController _scCity = TextEditingController();
  final TextEditingController _localCtrl = TextEditingController();

  // Theme Constants - from client_all_trips.dart
  final Color _themeColor = const Color(0xFF1A237E); // Primary color
  final Color _neutralBg = const Color(0xFFF8FAFC);
  final Color _cardBorder = const Color(0xFFE2E8F0);
  static const Color _kPrimary = Color(0xFF1A237E);
  static const Color _kBorder = Color(0xFFE2E8F0);
  static const Color _kBg = Color(0xFFF8FAFC);
  static const Color _kText = Color(0xFF0D1B2A);
  static const Color _kHint = Color(0xFF4A5568);
  static const Color _kActiveBg = Color(0xFFE2E8F0);
  static const Color _kDisabledBg = Color(0xFFF1F5F9);

  @override
  void initState() {
    super.initState();
    // debugPrint('🚀 PendingRostersScreen: initState() called');
    // debugPrint('🔧 PendingRostersScreen: Initializing with RosterService: ${widget.rosterService.runtimeType}');
    
    _loadPendingRosters();
    _fetchCountries();
    
    // debugPrint('✅ PendingRostersScreen: initState() completed');
  }

  @override
  void dispose() {
    // debugPrint('🗑️ PendingRostersScreen: dispose() called');
    _scrollController.dispose();
    _closeAllOverlays();
    _localCtrl.dispose();
    _scCountry.dispose();
    _scState.dispose();
    _scCity.dispose();
    super.dispose();
  }

  /// 🔥 SAFE STRING EXTRACTION - Prevents JsonMap type errors
  String _safeStringExtract(dynamic value) {
    if (value == null) return '';
    
    if (value is String) {
      return value.trim();
    } else if (value is Map) {
      // If it's a Map (including JsonMap), try to extract a meaningful string value
      try {
        if (value.containsKey('name')) {
          return _safeStringExtract(value['name']);
        } else if (value.containsKey('value')) {
          return _safeStringExtract(value['value']);
        } else if (value.containsKey('address')) {
          return _safeStringExtract(value['address']);
        } else if (value.containsKey('text')) {
          return _safeStringExtract(value['text']);
        } else if (value.containsKey('email')) {
          return _safeStringExtract(value['email']);
        } else {
          // Convert Map to string representation as last resort
          return value.toString();
        }
      } catch (e) {
        // If Map access fails (JsonMap type error), convert to string
        // debugPrint('⚠️ Map access error: $e, converting to string');
        return value.toString();
      }
    } else if (value is List) {
      // If it's a List, join elements or return first element
      if (value.isNotEmpty) {
        return _safeStringExtract(value.first);
      }
      return '';
    } else {
      // Convert any other type to string
      return value.toString();
    }
  }

  /// 🔥 SAFE NESTED ACCESS - Prevents JsonMap type errors when accessing nested data
  String _safeNestedAccess(Map<dynamic, dynamic> data, String key, [String? nestedKey]) {
    try {
      final value = data[key];
      if (nestedKey != null && value is Map) {
        return _safeStringExtract(value[nestedKey]);
      }
      return _safeStringExtract(value);
    } catch (e) {
      // debugPrint('⚠️ Nested access error for $key${nestedKey != null ? '.$nestedKey' : ''}: $e');
      return '';
    }
  }

  // ==========================================
  // HELPER: SAFE SNACKBAR DISPLAY
  // ==========================================
  
  void _showSnackBar(String message, {Color? backgroundColor}) {
    // Check if widget is still mounted
    if (!mounted) {
      // debugPrint('⚠️ Cannot show SnackBar: Widget not mounted');
      return;
    }
    
    // Use WidgetsBinding to ensure we're in a safe state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      try {
        // Use maybeOf to avoid errors if no ScaffoldMessenger found
        final scaffold = ScaffoldMessenger.maybeOf(context);
        if (scaffold != null) {
          scaffold.showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: backgroundColor,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          // debugPrint('⚠️ No ScaffoldMessenger found in context');
        }
      } catch (e) {
        // debugPrint('❌ Error showing SnackBar: $e');
      }
    });
  }

  // ============================================================================
  // CSC DATA FETCHING
  // ============================================================================

  Future<void> _fetchCountries() async {
    try {
      final list = await csc.getAllCountries();
      if (!mounted) return;
      setState(() {
        _countries = list..sort((a, b) => a.name.compareTo(b.name));
        _loadingCountries = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCountries = false);
    }
  }

  Future<void> _fetchStates(String iso) async {
    setState(() {
      _loadingStates = true;
      _states = [];
      _cities = [];
      _filterState = null;
      _stateIso = null;
      _filterCity = null;
    });
    try {
      final list = await csc.getStatesOfCountry(iso);
      if (!mounted) return;
      setState(() {
        _states = list..sort((a, b) => a.name.compareTo(b.name));
        _loadingStates = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingStates = false);
    }
  }

  Future<void> _fetchCities(String countryIso, String stateIso) async {
    setState(() {
      _loadingCities = true;
      _cities = [];
      _filterCity = null;
    });
    try {
      final list = await csc.getStateCities(countryIso, stateIso);
      if (!mounted) return;
      setState(() {
        _cities = list..sort((a, b) => a.name.compareTo(b.name));
        _loadingCities = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCities = false);
    }
  }

  // ============================================================================
  // OVERLAY MANAGEMENT (for CSC dropdowns)
  // ============================================================================

  void _closeAllOverlays() {
    _ovCountry?.remove(); _ovCountry = null;
    _ovState?.remove(); _ovState = null;
    _ovCity?.remove(); _ovCity = null;
    _scCountry.clear();
    _scState.clear();
    _scCity.clear();
  }

  void _openCountry() {
    _closeAllOverlays();
    _ovCountry = _buildOverlay<csc.Country>(
      link: _lkCountry,
      items: _countries,
      selLabel: _filterCountry,
      ctrl: _scCountry,
      loading: _loadingCountries,
      empty: 'No countries found',
      label: (c) => c.name,
      onPick: (c) {
        _closeAllOverlays();
        setState(() {
          _filterCountry = c.name;
          _countryIso = c.isoCode;
        });
        _fetchStates(c.isoCode);
        _applyFilters();
      },
      onClose: () {
        _closeAllOverlays();
        if (mounted) setState(() {});
      },
    );
    Overlay.of(context).insert(_ovCountry!);
    setState(() {});
  }

  void _openState() {
    _closeAllOverlays();
    _ovState = _buildOverlay<csc.State>(
      link: _lkState,
      items: _states,
      selLabel: _filterState,
      ctrl: _scState,
      loading: _loadingStates,
      empty: 'No states found',
      label: (s) => s.name,
      onPick: (s) {
        _closeAllOverlays();
        setState(() {
          _filterState = s.name;
          _stateIso = s.isoCode;
        });
        _fetchCities(_countryIso!, s.isoCode);
        _applyFilters();
      },
      onClose: () {
        _closeAllOverlays();
        if (mounted) setState(() {});
      },
    );
    Overlay.of(context).insert(_ovState!);
    setState(() {});
  }

  void _openCity() {
    _closeAllOverlays();
    _ovCity = _buildOverlay<csc.City>(
      link: _lkCity,
      items: _cities,
      selLabel: _filterCity,
      ctrl: _scCity,
      loading: _loadingCities,
      empty: 'No cities found',
      label: (c) => c.name,
      onPick: (c) {
        _closeAllOverlays();
        setState(() => _filterCity = c.name);
        _applyFilters();
      },
      onClose: () {
        _closeAllOverlays();
        if (mounted) setState(() {});
      },
    );
    Overlay.of(context).insert(_ovCity!);
    setState(() {});
  }

  OverlayEntry _buildOverlay<T>({
    required LayerLink link,
    required List<T> items,
    required String? selLabel,
    required TextEditingController ctrl,
    required bool loading,
    required String empty,
    required String Function(T) label,
    required void Function(T) onPick,
    required VoidCallback onClose,
  }) {
    late OverlayEntry ov;
    ov = OverlayEntry(builder: (_) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onClose,
        child: Stack(children: [
          Positioned.fill(child: Container(color: Colors.transparent)),
          CompositedTransformFollower(
            link: link,
            showWhenUnlinked: false,
            offset: const Offset(0, 42),
            child: GestureDetector(
              onTap: () {},
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(10),
                shadowColor: Colors.black26,
                child: Container(
                  width: 240,
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: TextField(
                          controller: ctrl,
                          autofocus: true,
                          style: const TextStyle(fontSize: 14, color: _kText),
                          decoration: InputDecoration(
                            hintText: 'Search...',
                            hintStyle: const TextStyle(fontSize: 14, color: _kHint),
                            prefixIcon: const Icon(Icons.search, size: 18, color: _kHint),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            filled: true,
                            fillColor: _kBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: _kBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: _kBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: _kPrimary, width: 1.5),
                            ),
                          ),
                          onChanged: (_) => ov.markNeedsBuild(),
                        ),
                      ),
                      const Divider(height: 1),
                      if (loading)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: SizedBox(
                            width: 24, height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        )
                      else
                        Flexible(
                          child: Builder(builder: (_) {
                            final q = ctrl.text.toLowerCase().trim();
                            final filtered = q.isEmpty
                                ? items
                                : items.where((i) => label(i).toLowerCase().contains(q)).toList();
                            if (filtered.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(empty, style: const TextStyle(fontSize: 14, color: _kHint)),
                              );
                            }
                            return ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final item = filtered[i];
                                final lbl = label(item);
                                final isSel = lbl == selLabel;
                                return InkWell(
                                  onTap: () => onPick(item),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    color: isSel ? _kActiveBg : Colors.transparent,
                                    child: Row(children: [
                                      Expanded(
                                        child: Text(lbl,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: _kText,
                                              fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                                            )),
                                      ),
                                      if (isSel) const Icon(Icons.check, size: 16, color: _kPrimary),
                                    ]),
                                  ),
                                );
                              },
                            );
                          }),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ]),
      );
    });
    return ov;
  }

  // ============================================================================
  // EXPORT TO EXCEL
  // ============================================================================

  Future<void> _exportToExcel() async {
    if (_filteredRosters.isEmpty) {
      _showSnackBar('No rosters to export', backgroundColor: Colors.orange);
      return;
    }

    setState(() => _isExporting = true);
    _showSnackBar('Preparing Excel export...');

    try {
      List<List<dynamic>> csvData = [
        [
          'Roster ID', 'Customer Name', 'Email', 'Phone', 'Organization',
          'Roster Type', 'Priority', 'Pickup Location', 'Drop Location',
          'Pickup Time', 'Drop Time', 'Roster Date', 'Status',
        ],
      ];

      for (final roster in _filteredRosters) {
        csvData.add([
          roster['rosterId'] ?? roster['_id'] ?? '',
          _safeStringExtract(roster['customerName']),
          _safeStringExtract(roster['email']),
          _safeStringExtract(roster['phoneNumber']),
          _safeStringExtract(roster['organizationId']),
          _safeStringExtract(roster['rosterType']),
          _safeStringExtract(roster['priority']),
          _safeStringExtract(roster['pickupLocation']),
          _safeStringExtract(roster['dropLocation']),
          _safeStringExtract(roster['pickupTime']),
          _safeStringExtract(roster['dropTime']),
          _formatExportDate(roster['rosterDate']),
          _safeStringExtract(roster['status']),
        ]);
      }

      await ExportHelper.exportToExcel(
        data: csvData,
        filename: 'pending_rosters_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
      );

      _showSnackBar('✅ Excel exported with ${_filteredRosters.length} rosters!');
    } catch (e) {
      _showSnackBar('Export failed: $e', backgroundColor: Colors.red);
    } finally {
      setState(() => _isExporting = false);
    }
  }

  String _formatExportDate(dynamic d) {
    if (d == null) return '';
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(d.toString()).toLocal());
    } catch (_) {
      return d.toString();
    }
  }



  // Smart Grouping Dialog
  // ==========================================
// FIXED SMART GROUPING - FRONTEND ONLY
// Replace _showSmartGroupingDialog() in pending_rosters_screen.dart
// ==========================================

// Smart Grouping Dialog (FIXED - Groups locally without backend call)
Future<void> _showSmartGroupingDialog() async {
  // debugPrint('\n' + '🔍'*40);
  // debugPrint('SHOWING SMART GROUPING DIALOG (FRONTEND GROUPING)');
  // debugPrint('🔍'*40);
  // debugPrint('📊 Grouping ${_filteredRosters.length} rosters from _filteredRosters');
  
  if (_filteredRosters.isEmpty) {
    _showSnackBar('No pending rosters available for grouping', backgroundColor: Colors.orange);
    return;
  }
  
  try {
    setState(() => _isLoading = true);
    
    // ✅ FIX: Group rosters LOCALLY on frontend (no backend call)
    final groups = _groupRostersLocally(_filteredRosters);
    
    setState(() => _isLoading = false);
    
    if (groups.isEmpty) {
      _showSnackBar('No groups found. All rosters have unique criteria.', backgroundColor: Colors.orange);
      return;
    }
    
    // debugPrint('✅ Found ${groups.length} groups from ${_filteredRosters.length} rosters');
    
    // Show groups dialog
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 800,
          constraints: const BoxConstraints(maxHeight: 700),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.group_work, color: Colors.purple[600], size: 32),
                  const SizedBox(width: 12),
                  const Text(
                    'Smart Grouping Results',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Found ${groups.length} groups of employees with matching schedules and locations',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const Divider(height: 32),
              Expanded(
                child: ListView.builder(
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    final employeeCount = group['employeeCount'] ?? 0;
                    final emailDomain = group['emailDomain'] ?? 'Unknown';
                    final organization = emailDomain.replaceAll('@', '');
                    final loginTime = group['loginTime'] ?? 'Unknown';
                    final logoutTime = group['logoutTime'] ?? 'Unknown';
                    final loginLocation = group['loginLocation'] ?? 'Unknown';
                    final logoutLocation = group['logoutLocation'] ?? 'Unknown';
                    final rosterType = group['rosterType'] ?? 'both';
                    final employees = List<Map<String, dynamic>>.from(group['employees'] ?? []);
                    final rosterIds = List<String>.from(group['rosterIds'] ?? []);
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.purple[100]!),
                      ),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.purple[600],
                          child: Text(
                            '$employeeCount',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          '$employeeCount employees from $organization',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.login, size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text('$loginTime @ $loginLocation', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                              ],
                            ),
                            Row(
                              children: [
                                Icon(Icons.logout, size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text('$logoutTime @ $logoutLocation', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                              ],
                            ),
                            Row(
                              children: [
                                Icon(Icons.directions_car, size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text('Type: $rosterType', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                              ],
                            ),
                          ],
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Employees in this group:',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(height: 8),
                                ...employees.map((emp) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Icon(Icons.person, size: 16, color: Colors.grey[600]),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${emp['name']} (${emp['email']})',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _optimizeGroupedRosters(rosterIds, employeeCount);
                                    },
                                    icon: const Icon(Icons.route),
                                    label: Text('Optimize Route for $employeeCount Employees'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.amber[700],
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    
  } catch (e) {
    setState(() => _isLoading = false);
    // debugPrint('❌ Error showing smart grouping: $e');
    _showSnackBar('Failed to group rosters: ${e.toString()}', backgroundColor: Colors.red);
  }
}

// ✅ NEW: Local grouping function (no backend call)
List<Map<String, dynamic>> _groupRostersLocally(List<Map<String, dynamic>> rosters) {
  // debugPrint('\n' + '🔍'*40);
  // debugPrint('GROUPING ROSTERS LOCALLY');
  // debugPrint('🔍'*40);
  // debugPrint('Input: ${rosters.length} rosters');
  
  final groups = <String, Map<String, dynamic>>{};
  
  for (final roster in rosters) {
    try {
      // Extract email domain (e.g., @wipro.com, @infosys.com)
      final email = _safeStringExtract(roster['customerEmail']) != '' ? 
                   _safeStringExtract(roster['customerEmail']) :
                   _safeNestedAccess(roster, 'employeeDetails', 'email');
      
      if (email.isEmpty || !email.contains('@')) {
        // debugPrint('⚠️ Skipping roster with invalid email: $email');
        continue;
      }
      
      final emailDomain = '@' + email.split('@')[1].toLowerCase();
      
      // Extract times
      final loginTime = _safeStringExtract(roster['startTime']) != '' ?
                       _safeStringExtract(roster['startTime']) :
                       (_safeStringExtract(roster['loginTime']) != '' ?
                       _safeStringExtract(roster['loginTime']) :
                       _safeStringExtract(roster['fromTime']));
      
      final logoutTime = _safeStringExtract(roster['endTime']) != '' ?
                        _safeStringExtract(roster['endTime']) :
                        (_safeStringExtract(roster['logoutTime']) != '' ?
                        _safeStringExtract(roster['logoutTime']) :
                        _safeStringExtract(roster['toTime']));
      
      // Extract location
      final location = _safeStringExtract(roster['officeLocation']).toLowerCase();
      
      // Extract roster type
      final rosterType = _safeStringExtract(roster['rosterType']).toLowerCase();
      
      // ✅ FIX: Create group key WITHOUT weekdays
      final groupKey = '$emailDomain|$loginTime|$logoutTime|$location|$rosterType';
      
      // debugPrint('📋 Roster: ${_safeStringExtract(roster['customerName'])}');
      // debugPrint('   Email Domain: $emailDomain');
      // debugPrint('   Times: $loginTime - $logoutTime');
      // debugPrint('   Location: $location');
      // debugPrint('   Type: $rosterType');
      // debugPrint('   Group Key: $groupKey');
      
      // Create or update group
      if (!groups.containsKey(groupKey)) {
        groups[groupKey] = {
          'groupKey': groupKey,
          'emailDomain': emailDomain,
          'loginTime': loginTime,
          'logoutTime': logoutTime,
          'loginLocation': location,
          'logoutLocation': location,
          'rosterType': rosterType,
          'employees': <Map<String, dynamic>>[],
          'rosterIds': <String>[],
          'employeeCount': 0,
        };
      }
      
      final rosterId = _safeStringExtract(roster['_id']) != '' ? 
                      _safeStringExtract(roster['_id']) : 
                      _safeStringExtract(roster['id']);
      
      final customerName = _safeStringExtract(roster['customerName']) != '' ?
                          _safeStringExtract(roster['customerName']) :
                          _safeNestedAccess(roster, 'employeeDetails', 'name');
      
      groups[groupKey]!['employees'].add({
        'name': customerName,
        'email': email,
        'rosterId': rosterId,
      });
      
      groups[groupKey]!['rosterIds'].add(rosterId);
      groups[groupKey]!['employeeCount'] = (groups[groupKey]!['employeeCount'] as int) + 1;
      
    } catch (e) {
      // debugPrint('❌ Error processing roster for grouping: $e');
      continue;
    }
  }
  
  final groupsList = groups.values.toList();
  
  // Sort by employee count (largest first)
  groupsList.sort((a, b) => (b['employeeCount'] as int).compareTo(a['employeeCount'] as int));
  
  // debugPrint('✅ Created ${groupsList.length} groups');
  for (int i = 0; i < groupsList.length; i++) {
    final group = groupsList[i];
    // debugPrint('   Group ${i + 1}: ${group['emailDomain']} - ${group['employeeCount']} employees');
  }
  // debugPrint('🔍'*40 + '\n');
  
  return groupsList;
}

  // Optimize grouped rosters
  Future<void> _optimizeGroupedRosters(List<String> rosterIds, int count) async {
    // debugPrint('\n' + '🎯'*40);
    // debugPrint('OPTIMIZING GROUPED ROSTERS');
    // debugPrint('🎯'*40);
    // debugPrint('Roster IDs: ${rosterIds.length}');
    // debugPrint('Count: $count');
    
    // Filter rosters by IDs
    final groupedRosters = _allPendingRosters.where((roster) {
      final id = roster['_id']?.toString() ?? roster['id']?.toString() ?? '';
      return rosterIds.contains(id);
    }).toList();
    
    // debugPrint('Filtered rosters: ${groupedRosters.length}');
    
    if (groupedRosters.isEmpty) {
      _showSnackBar('No rosters found for this group', backgroundColor: Colors.orange);
      return;
    }
    
    // Temporarily set filtered rosters to this group
    final originalFiltered = _filteredRosters;
    setState(() {
      _filteredRosters = groupedRosters;
    });
    
    // Trigger auto optimization
    await _performAdvancedRouteOptimization(count);
    
    // Restore original filtered rosters
    setState(() {
      _filteredRosters = originalFiltered;
    });
  }

  // NEW: Assign Single Customer using same flow as grouping
  Future<void> _assignSingleCustomer(Map<String, dynamic> roster) async {
    // debugPrint('\n' + '🎯'*40);
    // debugPrint('ASSIGNING SINGLE CUSTOMER');
    // debugPrint('🎯'*40);
    // debugPrint('Customer: ${_safeStringExtract(roster['customerName'])}');
    // debugPrint('Roster ID: ${roster['_id'] ?? roster['id']}');
    
    // Temporarily set filtered rosters to just this one customer
    final originalFiltered = _filteredRosters;
    setState(() {
      _filteredRosters = [roster];
    });
    
    // Trigger auto optimization with count = 1
    await _performAdvancedRouteOptimization(1);
    
    // Restore original filtered rosters
    setState(() {
      _filteredRosters = originalFiltered;
    });
  }

  // NEW: Assign Multiple Customers using same flow as grouping
  Future<void> _assignMultipleCustomers(List<Map<String, dynamic>> selectedRosters) async {
    // debugPrint('\n' + '🎯'*40);
    // debugPrint('ASSIGNING MULTIPLE CUSTOMERS');
    // debugPrint('🎯'*40);
    // debugPrint('Selected customers: ${selectedRosters.length}');
    
    if (selectedRosters.isEmpty) {
      _showSnackBar('No customers selected for assignment', backgroundColor: Colors.orange);
      return;
    }
    
    // Temporarily set filtered rosters to selected customers
    final originalFiltered = _filteredRosters;
    setState(() {
      _filteredRosters = selectedRosters;
    });
    
    // Trigger auto optimization with the count of selected customers
    await _performAdvancedRouteOptimization(selectedRosters.length);
    
    // Restore original filtered rosters
    setState(() {
      _filteredRosters = originalFiltered;
    });
  }

  // Route Optimization Dialog
  void _showRouteOptimizationDialog() {
    // debugPrint('\n' + '🎯'*40);
    // debugPrint('SHOWING ROUTE OPTIMIZATION INPUT DIALOG');
    // debugPrint('🎯'*40);
    // debugPrint('Available rosters: ${_filteredRosters.length}');
    // debugPrint('🎯'*40 + '\n');
    
    if (_filteredRosters.isEmpty) {
      _showSnackBar('No pending rosters available for optimization', backgroundColor: Colors.orange);
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => RouteOptimizationInputDialog(
        maxCustomers: _filteredRosters.length,
        onOptimize: (count, mode) {
          // debugPrint('\n' + '📞'*40);
          // debugPrint('ROUTE OPTIMIZATION CALLBACK RECEIVED');
          // debugPrint('📞'*40);
          // debugPrint('Count: $count');
          // debugPrint('Mode: $mode');
          // debugPrint('📞'*40 + '\n');
          
          if (mode == 'auto') {
            _performAdvancedRouteOptimization(count);
          } else {
            _performManualRouteSelection(count);
          }
        },
      ),
    );
  }

  // 7. NEW: Advanced Route Optimization with TSP Algorithm (AUTO MODE)
Future<void> _performAdvancedRouteOptimization(int count) async {
  debugPrint('\n' + '🤖'*40);
  debugPrint('🚀 AUTO MODE: ADVANCED ROUTE OPTIMIZATION STARTED');
  debugPrint('🤖'*40);
  debugPrint('📊 Input Parameters:');
  debugPrint('   - Requested customer count: $count');
  debugPrint('   - Total filtered rosters: ${_filteredRosters.length}');
  debugPrint('   - Available drivers: ${_availableDrivers.length}');
  debugPrint('-'*80);
  
  List<Map<String, dynamic>> optimalCustomers = []; // Declare outside try block
  
  try {
    setState(() => _isOptimizing = true);
    debugPrint('⏳ UI State: _isOptimizing = true');

    // Step 1: Find optimal customer cluster
    debugPrint('\n📍 STEP 1: FINDING OPTIMAL CUSTOMER CLUSTER');
    debugPrint('-'*80);
    debugPrint('Calling RouteOptimizationService.findOptimalCustomerCluster()...');
    debugPrint('   - Input rosters: ${_filteredRosters.length}');
    debugPrint('   - Requested count: $count');
    
    // 🔥 WRAP IN TRY-CATCH TO HANDLE DATA FORMAT ERRORS
    try {
      optimalCustomers = RouteOptimizationService.findOptimalCustomerCluster(
        _filteredRosters,
        count,
      );
      
      // ✅ NEW: Validate single-organization rule was enforced
      if (optimalCustomers.isNotEmpty) {
        final firstOrg = _getCustomerOrganization(optimalCustomers[0]);
        debugPrint('   ✅ Organization selected: $firstOrg');
        
        // Verify all customers are from same organization
        bool mixedOrgs = false;
        for (final customer in optimalCustomers) {
          final org = _getCustomerOrganization(customer);
          if (org != firstOrg) {
            debugPrint('   ⚠️ WARNING: Mixed organizations detected!');
            debugPrint('      Expected: $firstOrg, Found: $org');
            mixedOrgs = true;
          }
        }
        
        if (!mixedOrgs) {
          debugPrint('   ✅ SINGLE-ORGANIZATION RULE VERIFIED');
        }
      }
      
    } catch (clusterError, stackTrace) {
      debugPrint('❌ ERROR in findOptimalCustomerCluster: $clusterError');
      debugPrint('Stack trace: $stackTrace');
      
      setState(() => _isOptimizing = false);
      
      // Show user-friendly error for data format issues
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 32),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '⚠️ Data Format Error',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'There is a problem with the customer data format that prevents route optimization.',
                    style: TextStyle(fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.error_outline, size: 20, color: Colors.orange[700]),
                            const SizedBox(width: 8),
                            const Text(
                              'Common Causes:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '• Customer location data is missing or invalid\n'
                          '• Latitude/longitude values are in wrong format\n'
                          '• Customer profile is incomplete\n'
                          '• Email addresses are malformed or missing',
                          style: TextStyle(fontSize: 13, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lightbulb_outline, size: 20, color: Colors.blue[700]),
                            const SizedBox(width: 8),
                            const Text(
                              'Solutions:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '1. Check customer profiles for missing location data\n'
                          '2. Verify all customers have valid email addresses\n'
                          '3. Ensure coordinates are in correct format\n'
                          '4. Re-import customer data if needed\n'
                          '5. Contact support if problem persists',
                          style: TextStyle(fontSize: 13, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK, I Understand'),
              ),
            ],
          ),
        );
      }
      return; // Exit the function
    }
    
    debugPrint('✅ CLUSTER FOUND: ${optimalCustomers.length} customers');
    for (int i = 0; i < optimalCustomers.length; i++) {
      final customer = optimalCustomers[i];
      final name = _safeStringExtract(customer['customerName']) != '' ? 
                  _safeStringExtract(customer['customerName']) : 
                  _safeNestedAccess(customer, 'employeeDetails', 'name') != '' ?
                  _safeNestedAccess(customer, 'employeeDetails', 'name') : 'Unknown';
      final id = customer['id'] ?? customer['_id'] ?? 'N/A';
      final org = _getCustomerOrganization(customer);
      debugPrint('   ${i + 1}. $name ($org) - ID: $id');
    }
    debugPrint('-'*80);

    // Step 2: Load COMPATIBLE vehicles (filtered by email domain, timing, capacity)
    debugPrint('\n🚗 STEP 2: LOADING COMPATIBLE VEHICLES');
    debugPrint('-'*80);
    debugPrint('Using existing RosterService instance...');
    
    // Extract roster IDs
    final rosterIds = optimalCustomers.map((c) => c['_id'] as String).toList();
    debugPrint('Calling widget.rosterService.getCompatibleVehicles with ${rosterIds.length} roster IDs...');
    
    final vehiclesResponse = await widget.rosterService.getCompatibleVehicles(rosterIds);
    
    debugPrint('Response received:');
    debugPrint('   - Success: ${vehiclesResponse['success']}');
    debugPrint('   - Compatible count: ${(vehiclesResponse['data']?['compatible'] as List?)?.length ?? 0}');
    debugPrint('   - Incompatible count: ${(vehiclesResponse['data']?['incompatible'] as List?)?.length ?? 0}');
    
    if (vehiclesResponse['success'] != true) {
      debugPrint('❌ FAILED: Vehicle loading unsuccessful');
      throw Exception('Failed to load compatible vehicles');
    }

    final allVehicles = List<Map<String, dynamic>>.from(vehiclesResponse['data']?['compatible'] ?? []);
    final incompatibleVehicles = List<Map<String, dynamic>>.from(vehiclesResponse['data']?['incompatible'] ?? []);
    
    debugPrint('✅ COMPATIBLE VEHICLES: ${allVehicles.length}');
    debugPrint('❌ INCOMPATIBLE VEHICLES: ${incompatibleVehicles.length}');
    
    // 🔥 DEBUG: Print first vehicle structure to understand data format
    if (allVehicles.isNotEmpty) {
      debugPrint('\n🔍 DEBUG: First vehicle structure:');
      debugPrint('   Keys: ${allVehicles[0].keys.toList()}');
      debugPrint('   Full data: ${allVehicles[0]}');
    }
    
    for (int i = 0; i < allVehicles.length && i < 5; i++) {
      try {
        final v = allVehicles[i];
        debugPrint('\n🔍 DEBUG: Processing vehicle $i:');
        debugPrint('   Type: ${v.runtimeType}');
        debugPrint('   Keys: ${v.keys.toList()}');
        
        // 🔥 SAFE ACCESS: Try multiple possible field names
        dynamic nameValue = v['name'];
        debugPrint('   name field type: ${nameValue.runtimeType}, value: $nameValue');
        
        final name = _safeStringExtract(nameValue) != '' ? _safeStringExtract(nameValue) : 
                    (_safeStringExtract(v['vehicleNumber']) != '' ? _safeStringExtract(v['vehicleNumber']) : 
                    (_safeStringExtract(v['registrationNumber']) != '' ? _safeStringExtract(v['registrationNumber']) : 'Unknown'));
        
        final seats = _safeStringExtract(v['seatCapacity']) != '' ? _safeStringExtract(v['seatCapacity']) : 'N/A';
        
        // Handle assignedDriver as either Map or String
        final driverData = v['assignedDriver'];
        debugPrint('   assignedDriver type: ${driverData.runtimeType}, value: $driverData');
        final driver = _safeStringExtract(driverData) != '' ? _safeStringExtract(driverData) : 'No driver';
        final reason = _safeStringExtract(v['compatibilityReason']) != '' ? _safeStringExtract(v['compatibilityReason']) : 'Compatible';
        
        debugPrint('   ${i + 1}. $name - $seats seats - Driver: $driver');
        debugPrint('      ✅ $reason');
      } catch (e, stackTrace) {
        debugPrint('   ❌ ERROR processing vehicle $i: $e');
        debugPrint('   Stack: $stackTrace');
      }
    }
    if (allVehicles.length > 5) {
      debugPrint('   ... and ${allVehicles.length - 5} more compatible vehicles');
    }
    
    if (incompatibleVehicles.isNotEmpty) {
      debugPrint('\n❌ Incompatible vehicles (filtered out):');
      for (int i = 0; i < incompatibleVehicles.length && i < 3; i++) {
        final v = incompatibleVehicles[i];
        final name = _safeStringExtract(v['name']) ?? 
                    _safeStringExtract(v['vehicleNumber']) ?? 
                    'Unknown';
        final reason = _safeStringExtract(v['compatibilityReason']) ?? 'No reason provided';
        debugPrint('   ${i + 1}. $name - $reason');
      }
      if (incompatibleVehicles.length > 3) {
        debugPrint('   ... and ${incompatibleVehicles.length - 3} more incompatible vehicles');
      }
    }
    debugPrint('-'*80);

    // ✅ CHECK: If no compatible vehicles, show helpful error message
    if (allVehicles.isEmpty) {
      setState(() => _isOptimizing = false);
      debugPrint('\n❌ NO COMPATIBLE VEHICLES FOUND');
      debugPrint('   - Incompatible: ${incompatibleVehicles.length}');
      
      // Analyze why vehicles are incompatible
      final reasons = <String>{};
      for (final v in incompatibleVehicles) {
        final reason = _safeStringExtract(v['compatibilityReason']) != '' ? _safeStringExtract(v['compatibilityReason']) : 'Unknown reason';
        
        // 🆕 CHECK FOR CONSECUTIVE TRIP ERRORS
        if (reason.contains('Impossible schedule') || 
            reason.contains('insufficient time') || 
            reason.contains('Short by')) {
          reasons.add('time_conflict');
        } else if (reason.contains('full') || reason.contains('capacity')) {
          reasons.add('full');
        } else if (reason.contains('Company') || reason.contains('company')) {
          reasons.add('company_mismatch');
        } else if (reason.contains('driver') || reason.contains('Driver')) {
          reasons.add('no_driver');
        }
      }
      
      // Build helpful error message
      String errorTitle = '🚗 All Vehicles Are Unavailable';
      String errorMessage = 'Cannot assign customers because all vehicles are currently unavailable.\n\n';
      
      // 🆕 PRIORITIZE CONSECUTIVE TRIP ERROR MESSAGE
      if (reasons.contains('time_conflict')) {
        errorTitle = '⏰ Vehicles Cannot Reach Next Shift On Time';
        errorMessage = 'All available vehicles have time conflicts with existing trips.\n\n';
        errorMessage += '⏰ Problem: Vehicles finish previous trips too late\n';
        errorMessage += '✅ Solutions:\n';
        errorMessage += '   • Wait for current trips to complete\n';
        errorMessage += '   • Adjust shift timing (give more buffer time)\n';
        errorMessage += '   • Use vehicles without prior commitments\n';
        errorMessage += '   • Assign to different time slot\n\n';
      }
      
      if (reasons.contains('full')) {
        errorMessage += '💺 Problem: All vehicles are full\n';
        errorMessage += '✅ Solution: Wait for current trips to complete, or add more vehicles\n\n';
      }
      if (reasons.contains('no_driver')) {
        errorMessage += '👤 Problem: Vehicles don\'t have assigned drivers\n';
        errorMessage += '✅ Solution: Go to Vehicle Management → Assign drivers to vehicles\n\n';
      }
      if (reasons.contains('company_mismatch')) {
        errorMessage += '🏢 Problem: Vehicles are assigned to different companies\n';
        errorMessage += '✅ Solution: Use vehicles that match customer email domains\n\n';
      }
      
      errorMessage += '📋 What to do now:\n';
      errorMessage += '1. Go to Vehicle Management\n';
      errorMessage += '2. Check vehicle status and assignments\n';
      errorMessage += '3. Assign drivers if needed\n';
      errorMessage += '4. Come back and try again';
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    errorTitle,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Text(
                errorMessage,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK, I Understand'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // Step 3: Find best vehicle
    debugPrint('\n🎯 STEP 3: FINDING BEST VEHICLE');
    debugPrint('-'*80);
    debugPrint('Calling RouteOptimizationService.findBestVehicle()...');
    debugPrint('   - Customers: ${optimalCustomers.length}');
    debugPrint('   - Available vehicles: ${allVehicles.length}');
    
    final bestVehicle = RouteOptimizationService.findBestVehicle(
      optimalCustomers,
      allVehicles,
    );

    if (bestVehicle == null) {
      debugPrint('❌ FAILED: No suitable vehicle found');
      debugPrint('Possible reasons:');
      debugPrint('   - No vehicles with sufficient seat capacity');
      debugPrint('   - No vehicles with assigned drivers');
      debugPrint('   - All vehicles are fully booked');
      throw Exception('No suitable vehicle found with sufficient capacity');
    }

    // 🔥 DEBUG: Print bestVehicle structure
    debugPrint('\n🔍 DEBUG: bestVehicle structure:');
    debugPrint('   Type: ${bestVehicle.runtimeType}');
    debugPrint('   Keys: ${bestVehicle.keys.toList()}');
    debugPrint('   Full data: $bestVehicle');
    
    // 🔥 SAFE PARSING: Handle name field which might be String or Map
    dynamic nameValue = bestVehicle['name'];
    debugPrint('   name field type: ${nameValue.runtimeType}, value: $nameValue');
    final vehicleName = nameValue is String ? nameValue : 
                       (nameValue is Map ? (nameValue['value'] ?? nameValue.toString()) : 
                       (bestVehicle['vehicleNumber'] ?? 'Unknown'));
    
    final licensePlate = bestVehicle['licensePlate'] ?? bestVehicle['registrationNumber'] ?? 'N/A';
    
    // 🔥 SAFE PARSING: Handle assignedDriver as either Map or String
    final driverData = bestVehicle['assignedDriver'];
    debugPrint('   assignedDriver type: ${driverData.runtimeType}, value: $driverData');
    final driverName = driverData is Map ? _safeStringExtract(driverData['name']) != '' ? _safeStringExtract(driverData['name']) : 'Unknown' : (driverData?.toString() ?? 'Unknown');
    
    // 🔥 SAFE PARSING: Handle seatCapacity as String or int
    final seatCapacityValue = bestVehicle['seatCapacity'];
    debugPrint('   seatCapacity type: ${seatCapacityValue.runtimeType}, value: $seatCapacityValue');
    final seatCapacity = seatCapacityValue is int ? seatCapacityValue : 
                        (seatCapacityValue is String ? (int.tryParse(seatCapacityValue) ?? 0) : 
                        (seatCapacityValue is double ? seatCapacityValue.toInt() : 0));
    
    debugPrint('✅ BEST VEHICLE FOUND:');
    debugPrint('   - Name: $vehicleName');
    debugPrint('   - License: $licensePlate');
    debugPrint('   - Driver: $driverName');
    debugPrint('   - Seat Capacity: $seatCapacity');
    debugPrint('-'*80);

    setState(() => _isOptimizing = false);
    debugPrint('⏳ UI State: _isOptimizing = false');

    // Step 4: Show vehicle confirmation dialog (NEW STEP)
    debugPrint('\n🚗 STEP 4: SHOWING VEHICLE CONFIRMATION DIALOG');
    debugPrint('-'*80);
    if (mounted) {
      debugPrint('✅ Widget mounted - Opening VehicleConfirmationDialog');
      debugPrint('   - Vehicle: $vehicleName');
      debugPrint('   - Customers: ${optimalCustomers.length}');
      debugPrint('🤖'*40);
      debugPrint('WAITING FOR ADMIN CONFIRMATION');
      debugPrint('🤖'*40 + '\n');
      _showVehicleConfirmationDialog(bestVehicle, optimalCustomers);
    } else {
      debugPrint('⚠️ Widget not mounted - Cannot show dialog');
    }
  } catch (e, stackTrace) {
    debugPrint('\n' + '❌'*40);
    debugPrint('AUTO MODE OPTIMIZATION FAILED');
    debugPrint('❌'*40);
    debugPrint('Error: $e');
    debugPrint('Stack trace:');
    debugPrint(stackTrace.toString());
    debugPrint('❌'*40 + '\n');
    
    setState(() => _isOptimizing = false);
    debugPrint('⏳ UI State: _isOptimizing = false');
    
    // Extract ACTUAL backend error message
    String errorMessage = 'Optimization failed';
    String errorTitle = '❌ Route Optimization Failed';
    
    final errorStr = e.toString();
    
    // Extract the real backend error message (not generic wrapper)
    if (errorStr.contains('ApiException:')) {
      errorMessage = errorStr.replaceFirst('ApiException: ', '').trim();
    } else if (errorStr.contains('Exception:')) {
      errorMessage = errorStr.replaceFirst('Exception: ', '').trim();
    } else {
      errorMessage = errorStr;
    }
    
    // Check for specific error types and provide actionable guidance with SOLUTIONS
    String actionGuidance = 'Try selecting a different vehicle or adjust the timing';
    
    // 🆕 HANDLE CONSECUTIVE TRIP ERROR SPECIFICALLY
    if (errorStr.contains('INSUFFICIENT_TIME_BETWEEN_TRIPS') || 
        errorStr.contains('Impossible schedule') ||
        errorStr.contains('cannot reach next shift') || 
        errorStr.contains('FEASIBILITY_FAILED')) {
      errorTitle = '⏰ Vehicle Cannot Reach Next Shift On Time';
      actionGuidance = 'Solutions:\n'
          '• Click "Try Another Vehicle" to find an alternative\n'
          '• Adjust the shift timing (give more buffer time)\n'
          '• Use a different vehicle that\'s available earlier\n'
          '• Assign this shift to a vehicle without prior commitments';
    } else if (errorStr.contains('No suitable vehicle') || errorStr.contains('No compatible vehicles')) {
      errorTitle = '🚗 No Compatible Vehicles Available';
      actionGuidance = 'Solutions:\n'
          '• Assign drivers to vehicles in Vehicle Management\n'
          '• Check if vehicles match customer company (email domain)\n'
          '• Use vehicles with larger capacity\n'
          '• Split customers into multiple routes';
    } else if (errorStr.contains('Failed to load compatible vehicles')) {
      errorTitle = '⚠️ Vehicle Loading Failed';
      actionGuidance = 'Solutions:\n'
          '• Check if backend server is running\n'
          '• Verify network connection\n'
          '• Restart the backend server';
    } else if (errorStr.contains('No vehicles with assigned drivers')) {
      errorTitle = '👤 No Drivers Assigned';
      actionGuidance = 'Solutions:\n'
          '• Go to Vehicle Management\n'
          '• Assign active drivers to vehicles\n'
          '• Ensure drivers are available';
    } else if (errorStr.contains('Insufficient capacity') || errorStr.contains('seat capacity') || errorStr.contains('full')) {
      errorTitle = '💺 Vehicle is Full';
      actionGuidance = 'Solutions:\n'
          '• Click "Try Another Vehicle" to find an alternative\n'
          '• Reduce number of customers in this route\n'
          '• Use a vehicle with more seats\n'
          '• Split into multiple routes';
    } else if (errorStr.contains('compatibility violation') || errorStr.contains('COMPATIBILITY_CONFLICT')) {
      errorTitle = '🏢 Vehicle Already Assigned to Different Company';
      actionGuidance = 'Solutions:\n'
          '• Click "Try Another Vehicle" to find one for this company\n'
          '• Use a vehicle that\'s free or already serving this company\n'
          '• Vehicles cannot mix customers from different companies';
    }
    
    debugPrint('💡 Showing ACTUAL backend error to admin: $errorTitle');
    debugPrint('📱 Error message: $errorMessage');
    
    // Show detailed error dialog with ACTUAL backend message
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  errorTitle,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  errorMessage,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb_outline, size: 20, color: Colors.blue[700]),
                          const SizedBox(width: 8),
                          Text(
                            'What to do:',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blue[900],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        actionGuidance,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue[900],
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (optimalCustomers.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Automatically try to find another vehicle
                  _tryAlternativeVehicle(optimalCustomers);
                },
                child: const Text('Try Another Vehicle'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    }
  }
}

// ✅ NEW HELPER METHOD: Extract organization from customer
String _getCustomerOrganization(Map<String, dynamic> customer) {
  final email = _safeStringExtract(customer['customerEmail']) ?? 
               _safeStringExtract(customer['employeeDetails']?['email']) ?? 
               _safeStringExtract(customer['email']);
  
  if (email.isNotEmpty && email.contains('@')) {
    return '@' + email.split('@')[1].toLowerCase();
  }
  
  return 'Unknown';
}

  // 7b. NEW: Show Vehicle Confirmation Dialog
  // 7b. NEW: Show Vehicle Confirmation Dialog
  // 7b. NEW: Show Vehicle Confirmation Dialog
  void _showVehicleConfirmationDialog(
  Map<String, dynamic> vehicle,
  List<Map<String, dynamic>> customers,
) {
  // debugPrint('\n' + '🚗'*40);
  // debugPrint('SHOWING VEHICLE CONFIRMATION DIALOG');
  // debugPrint('🚗'*40);
  
  // 🔥 FIX: Use registrationNumber instead of name for vehicle display
  final vehicleName = _safeStringExtract(vehicle['registrationNumber']) ?? 
                     _safeStringExtract(vehicle['vehicleNumber']) ?? 
                     _safeStringExtract(vehicle['name']) ?? 
                     'Unknown Vehicle';
  
  // 🔥 FIX: Safely extract driver name and remove MongoDB ID
  final driverData = vehicle['assignedDriver'];
  String driverName = 'Unknown Driver';
  
  if (driverData is Map) {
    // Extract only the name, ignore MongoDB ObjectId
    driverName = _safeStringExtract(driverData['name']) ?? 'Unknown Driver';
    // debugPrint('   Driver extracted from Map: $driverName');
  } else if (driverData is String && driverData.isNotEmpty) {
    // If it's a string, use it directly (but check if it's not a MongoDB ID)
    if (driverData.length == 24 && RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(driverData)) {
      // This looks like a MongoDB ObjectId, don't display it
      driverName = 'Driver ID: ${driverData.substring(0, 8)}...';
      // debugPrint('   MongoDB ID detected, showing truncated: $driverName');
    } else {
      driverName = driverData;
      // debugPrint('   Driver name from String: $driverName');
    }
  }
  
  // debugPrint('Vehicle Details:');
  // debugPrint('   - Name: $vehicleName');
  // debugPrint('   - Driver: $driverName');
  // debugPrint('   - Customers: ${customers.length}');
  
  // 🔥 CRITICAL FIX: Calculate available seats correctly with SAFE PARSING
  int totalSeats = 4; // default
  
  // Try multiple possible field names for seat capacity
  if (vehicle['capacity'] != null && vehicle['capacity'] is Map) {
    final capacityMap = vehicle['capacity'] as Map;
    final seatingValue = capacityMap['seating'] ?? capacityMap['passengers']; // ✅ FIX: Check passengers too
    if (seatingValue is int) {
      totalSeats = seatingValue;
    } else if (seatingValue is String) {
      totalSeats = int.tryParse(seatingValue) ?? 4;
    }
  } else {
    // ✅ FIX: Check passengers top-level as well
    final seatCapacityValue = vehicle['seatCapacity'] ?? 
                             vehicle['seatingCapacity'] ?? 
                             vehicle['passengers']; 
                             
    if (seatCapacityValue != null) {
      if (seatCapacityValue is int) {
        totalSeats = seatCapacityValue;
      } else if (seatCapacityValue is String) {
        totalSeats = int.tryParse(seatCapacityValue) ?? 4;
      } else if (seatCapacityValue is double) {
        totalSeats = seatCapacityValue.toInt();
      }
    }
  }
  
  final assignedSeats = (vehicle['assignedCustomers'] as List?)?.length ?? 0;
  final driverSeat = 1; // Driver always takes 1 seat
  final availableSeats = totalSeats - driverSeat - assignedSeats;
  final customersToAdd = customers.length;
  final seatsAfterAssignment = availableSeats - customersToAdd;
  
  // debugPrint('   - Total Seats: $totalSeats');
  // debugPrint('   - Driver Seat: $driverSeat');
  // debugPrint('   - Already Assigned: $assignedSeats');
  // debugPrint('   - Available Now: $availableSeats');
  // debugPrint('   - Customers to Add: $customersToAdd');
  // debugPrint('   - Seats After Assignment: $seatsAfterAssignment');
  
  // ✅ CHECK: If vehicle will be overfull after assignment
  if (availableSeats < customersToAdd) {
    // debugPrint('❌ VEHICLE FULL: Cannot assign $customersToAdd customers (only $availableSeats seats available)');
    // debugPrint('🚗'*40 + '\n');
    
    // Show error dialog instead
    _showVehicleFullError(vehicle, customers, availableSeats, totalSeats, assignedSeats);
    return;
  }
  
  // debugPrint('✅ Vehicle has sufficient capacity');
  // debugPrint('🚗'*40 + '\n');
  
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => VehicleConfirmationDialog(
      vehicle: vehicle,
      customers: customers,
      onConfirm: () {
        // debugPrint('✅ Admin confirmed vehicle selection');
        Navigator.of(context).pop();
        _generateRouteAfterConfirmation(vehicle, customers);
      },
      onCancel: () {
        // debugPrint('❌ Admin cancelled vehicle selection');
        Navigator.of(context).pop();
      },
    ),
  );
}

  // 7b-FIX. NEW: Show Vehicle Full Error Dialog
  void _showVehicleFullError(
    Map<String, dynamic> vehicle,
    List<Map<String, dynamic>> customers,
    int availableSeats,
    int totalSeats,
    int assignedSeats,
  ) {
    final vehicleName = _safeStringExtract(vehicle['name']) ?? 
                       _safeStringExtract(vehicle['vehicleNumber']) ?? 
                       'Unknown Vehicle';
    final driverName = _safeNestedAccess(vehicle, 'assignedDriver', 'name') != '' ? 
                      _safeNestedAccess(vehicle, 'assignedDriver', 'name') : 'Unknown Driver';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 32),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Vehicle is Full',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Vehicle Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.directions_car, size: 20, color: Colors.orange[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            vehicleName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.person, size: 18, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text('Driver: $driverName', style: const TextStyle(fontSize: 14)),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Capacity',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$totalSeats seats',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Already Assigned',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$assignedSeats customers',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[700],
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Available',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$availableSeats seats',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: availableSeats > 0 ? Colors.green[700] : Colors.red[700],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Problem Explanation
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.error_outline, size: 20, color: Colors.red[700]),
                        const SizedBox(width: 8),
                        const Text(
                          'Cannot Assign Customers',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You are trying to assign ${customers.length} customers, but this vehicle only has $availableSeats available seats.',
                      style: TextStyle(fontSize: 13, color: Colors.red[900]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Note: 1 seat is reserved for the driver ($driverName)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red[700],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Solution Steps
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline, size: 20, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        const Text(
                          'What You Can Do',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildSolutionStep('1', 'Try Another Vehicle', 
                      'Click the button below to find an alternative vehicle with more capacity'),
                    const SizedBox(height: 8),
                    _buildSolutionStep('2', 'Split the Route', 
                      'Assign fewer customers to this vehicle (max $availableSeats), then create another route'),
                    const SizedBox(height: 8),
                    _buildSolutionStep('3', 'Wait for Trip Completion', 
                      'This vehicle has $assignedSeats customers assigned. After their trip completes, you can assign new customers'),
                    const SizedBox(height: 8),
                    _buildSolutionStep('4', 'Use Larger Vehicle', 
                      'Go to Vehicle Management and add vehicles with more seating capacity'),
                  ],
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
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _tryAlternativeVehicle(customers);
            },
            icon: const Icon(Icons.directions_car, size: 18),
            label: const Text('Try Another Vehicle'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSolutionStep(String number, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.blue[700],
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 7b2. NEW: Try Alternative Vehicle When First One Fails

// 7b2. NEW: Try Alternative Vehicle When First One Fails
  Future<void> _tryAlternativeVehicle(List<Map<String, dynamic>> customers) async {
    // debugPrint('\n' + '🔄'*40);
    // debugPrint('TRYING ALTERNATIVE VEHICLE');
    // debugPrint('🔄'*40);
    // debugPrint('Customers: ${customers.length}');
    
    try {
      setState(() => _isOptimizing = true);
      
      // Load compatible vehicles again
      final rosterIds = customers.map((c) => c['_id'] as String).toList();
      final vehiclesResponse = await widget.rosterService.getCompatibleVehicles(rosterIds);
      
      if (vehiclesResponse['success'] != true) {
        throw Exception('Failed to load compatible vehicles');
      }

      final allVehicles = List<Map<String, dynamic>>.from(vehiclesResponse['data']?['compatible'] ?? []);
      // 🔥 FIX: LOAD incompatibleVehicles
      final incompatibleVehicles = List<Map<String, dynamic>>.from(vehiclesResponse['data']?['incompatible'] ?? []);
      
      // debugPrint('✅ Found ${allVehicles.length} compatible vehicles');
      // debugPrint('❌ Found ${incompatibleVehicles.length} incompatible vehicles');
      
      setState(() => _isOptimizing = false);
      
      // 🔥 CRITICAL: If NO vehicles available, show detailed explanation
      if (allVehicles.isEmpty) {
        // debugPrint('❌ NO ALTERNATIVE VEHICLES AVAILABLE');
        _showNoVehiclesAvailableDialog(customers, incompatibleVehicles);
        return;
      }
      
      // Find next best vehicle (backend already filtered by capacity and company)
      Map<String, dynamic>? alternativeVehicle;
      
      if (allVehicles.isNotEmpty) {
        // Backend already filtered - just take the first compatible vehicle
        alternativeVehicle = allVehicles[0];
        final vehicleName = alternativeVehicle['name'] ?? alternativeVehicle['vehicleNumber'] ?? 'Unknown';
        // debugPrint('✅ Found alternative: $vehicleName');
        // debugPrint('   Backend already verified: driver assigned, sufficient capacity, same company');
      }
      
      if (alternativeVehicle != null) {
        // Show the alternative vehicle to admin
        final vehicleName = _safeStringExtract(alternativeVehicle['name']) ?? 
                           _safeStringExtract(alternativeVehicle['vehicleNumber']) ?? 
                           'Unknown';
        final driverName = _safeNestedAccess(alternativeVehicle, 'assignedDriver', 'name') != '' ? 
                          _safeNestedAccess(alternativeVehicle, 'assignedDriver', 'name') : 'Unknown';
        
        // debugPrint('💡 Suggesting alternative vehicle to admin');
        
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.directions_car, color: Colors.green[600], size: 32),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Alternative Vehicle Found',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'The previous vehicle had a conflict. Here\'s an alternative:',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.directions_car, size: 20, color: Colors.green[700]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                vehicleName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.person, size: 18, color: Colors.grey[600]),
                            const SizedBox(width: 8),
                            Text('Driver: $driverName', style: const TextStyle(fontSize: 14)),
                          ],
                        ),
                        Row(
                          children: [
                            Icon(Icons.event_seat, size: 18, color: Colors.grey[600]),
                            const SizedBox(width: 8),
                            Text(
                              'Capacity: ${alternativeVehicle!['seatCapacity'] ?? alternativeVehicle['seatingCapacity'] ?? 'N/A'} seats',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _showVehicleConfirmationDialog(alternativeVehicle!, customers);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Use This Vehicle'),
                ),
              ],
            ),
          );
        }
      } else {
        _showSnackBar('❌ No suitable alternative vehicles found', backgroundColor: Colors.red);
      }
      
    } catch (e) {
      setState(() => _isOptimizing = false);
      // debugPrint('❌ Error finding alternative vehicle: $e');
      _showSnackBar('Failed to find alternative vehicle: ${e.toString()}', backgroundColor: Colors.red);
    }
  }

// 7b3. NEW: Show No Vehicles Available Dialog
  void _showNoVehiclesAvailableDialog(
    List<Map<String, dynamic>> customers,
    List<Map<String, dynamic>> incompatibleVehicles,
  ) {
    // Analyze why vehicles are unavailable
    int fullVehicles = 0;
    int noDriverVehicles = 0;
    int companyMismatch = 0;
    int otherReasons = 0;
    
    for (final v in incompatibleVehicles) {
      final reason = _safeStringExtract(v['compatibilityReason']) != '' ? _safeStringExtract(v['compatibilityReason']) : 'Unknown reason';
      if (reason.contains('full') || reason.contains('capacity') || reason.contains('seats')) {
        fullVehicles++;
      } else if (reason.contains('driver') || reason.contains('Driver')) {
        noDriverVehicles++;
      } else if (reason.contains('Company') || reason.contains('company') || reason.contains('domain')) {
        companyMismatch++;
      } else {
        otherReasons++;
      }
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 32),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No Vehicles Available for Assignment',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cannot assign ${customers.length} customers because all ${incompatibleVehicles.length} vehicles in your fleet are currently unavailable.',
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
              
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              
              // Problem Breakdown
              const Text(
                'Why Vehicles Are Unavailable:',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              
              if (fullVehicles > 0) ...[
                _buildProblemItem(
                  Icons.event_seat,
                  Colors.red,
                  'Full Vehicles',
                  '$fullVehicles vehicles don\'t have enough empty seats',
                ),
                const SizedBox(height: 8),
              ],
              
              if (noDriverVehicles > 0) ...[
                _buildProblemItem(
                  Icons.person_off,
                  Colors.orange,
                  'Missing Drivers',
                  '$noDriverVehicles vehicles don\'t have assigned drivers',
                ),
                const SizedBox(height: 8),
              ],
              
              if (companyMismatch > 0) ...[
                _buildProblemItem(
                  Icons.business,
                  Colors.blue,
                  'Company Mismatch',
                  '$companyMismatch vehicles are assigned to different companies',
                ),
                const SizedBox(height: 8),
              ],
              
              if (otherReasons > 0) ...[
                _buildProblemItem(
                  Icons.info_outline,
                  Colors.grey,
                  'Other Issues',
                  '$otherReasons vehicles have other conflicts',
                ),
              ],
              
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              
              // Solutions
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline, size: 20, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        const Text(
                          'What You Need to Do:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    if (fullVehicles > 0) ...[
                      const Text(
                        '1️⃣ Wait for Current Trips to Complete',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '   • $fullVehicles vehicles will have free seats after current assignments finish',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 8),
                    ],
                    
                    if (noDriverVehicles > 0) ...[
                      const Text(
                        '2️⃣ Assign Drivers to Vehicles',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '   • Go to Vehicle Management → Select vehicle → Assign Driver',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                      Text(
                        '   • $noDriverVehicles vehicles need drivers',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 8),
                    ],
                    
                    if (companyMismatch > 0) ...[
                      const Text(
                        '3️⃣ Use Company-Specific Vehicles',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '   • $companyMismatch vehicles are assigned to different companies',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                      Text(
                        '   • Vehicles can only serve one company at a time',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 8),
                    ],
                    
                    const Text(
                      '4️⃣ Add More Vehicles',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '   • Go to Vehicle Management → Add New Vehicle',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    Text(
                      '   • Ensure new vehicles have assigned drivers',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('I Understand'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to vehicle management (if you have navigation)
              // Navigator.pushNamed(context, '/vehicle-management');
            },
            icon: const Icon(Icons.directions_car, size: 18),
            label: const Text('Go to Vehicle Management'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProblemItem(
    IconData icon,
    Color color,
    String title,
    String description,
  ) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 7c. NEW: Generate Route After Vehicle Confirmation
Future<void> _generateRouteAfterConfirmation(
  Map<String, dynamic> vehicle,
  List<Map<String, dynamic>> customers,
) async {
  // debugPrint('\n' + '🗺️'*40);
  // debugPrint('GENERATING ROUTE AFTER CONFIRMATION');
  // debugPrint('🗺️'*40);
  
  try {
    setState(() => _isOptimizing = true);
    // debugPrint('⏳ UI State: _isOptimizing = true');

    final vehicleName = vehicle['name'] ?? vehicle['vehicleNumber'] ?? 'Unknown';
    
    // Generate route plan with OSRM (async)
    // debugPrint('\n🗺️ GENERATING OPTIMAL ROUTE PLAN WITH OSRM');
    // debugPrint('-'*80);
    final startTime = DateTime.now().add(const Duration(minutes: 30));
    // debugPrint('Calling RouteOptimizationService.generateRoutePlan() [ASYNC]...');
    // debugPrint('   - Vehicle: $vehicleName');
    // debugPrint('   - Customers: ${customers.length}');
    // debugPrint('   - Start time: ${DateFormat('h:mm a').format(startTime)}');
    // debugPrint('   - Using OSRM for actual road distances');
    
    // ✅ ADD AWAIT KEYWORD HERE
    final routePlan = await RouteOptimizationService.generateRoutePlan(
      vehicle: vehicle,
      customers: customers,
      startTime: startTime,
    );

    // debugPrint('✅ ROUTE PLAN GENERATED WITH OSRM:');
    // debugPrint('   - Total distance: ${routePlan['totalDistance']} km (road distance)');
    // debugPrint('   - Total time: ${routePlan['totalTime']} mins (OSRM calculated)');
    // debugPrint('   - Customer count: ${routePlan['customerCount']}');
    // debugPrint('   - Route stops: ${(routePlan['route'] as List).length}');
    // debugPrint('   - Routing method: ${routePlan['routingMethod']}');
    
    final route = routePlan['route'] as List<Map<String, dynamic>>;
    // debugPrint('\n📍 Route Sequence:');
    for (int i = 0; i < route.length; i++) {
      final stop = route[i];
      final customerName = stop['customerName'] ?? 'Unknown';
      final distance = stop['distanceFromPrevious'] ?? 0;
      final time = stop['estimatedTime'] ?? 0;
      // debugPrint('   ${i + 1}. $customerName - ${distance.toStringAsFixed(1)}km, ~${time}min');
    }
    // debugPrint('-'*80);

    setState(() => _isOptimizing = false);
    // debugPrint('⏳ UI State: _isOptimizing = false');

    // Show route plan to admin
    // debugPrint('\n📊 SHOWING ROUTE PLAN TO ADMIN');
    // debugPrint('-'*80);
    if (mounted) {
      // debugPrint('✅ Widget mounted - Opening RouteOptimizationDialog');
      // debugPrint('🗺️'*40);
      // debugPrint('ROUTE GENERATION COMPLETED SUCCESSFULLY');
      // debugPrint('🗺️'*40 + '\n');
      _showRouteOptimizationResult(routePlan);
    } else {
      // debugPrint('⚠️ Widget not mounted - Cannot show dialog');
    }
  } catch (e, stackTrace) {
    // debugPrint('\n' + '❌'*40);
    // debugPrint('ROUTE GENERATION FAILED');
    // debugPrint('❌'*40);
    // debugPrint('Error: $e');
    // debugPrint('Stack trace:');
    // debugPrint(stackTrace.toString());
    // debugPrint('❌'*40 + '\n');
    
    setState(() => _isOptimizing = false);
    // debugPrint('⏳ UI State: _isOptimizing = false');
    
    // Extract detailed error message
    String errorMessage = 'Route generation failed';
    final errorStr = e.toString();
    
    if (errorStr.contains('OSRM') || errorStr.contains('routing')) {
      errorMessage = 'Route calculation failed.\n\n'
          '📋 Possible Issues:\n'
          '• OSRM routing service unavailable\n'
          '• Invalid customer locations\n'
          '• Network connectivity issue';
    } else if (errorStr.contains('ApiException:')) {
      errorMessage = errorStr.replaceFirst('ApiException: ', '');
    } else if (errorStr.contains('Exception:')) {
      errorMessage = errorStr.replaceFirst('Exception: ', '');
    } else {
      errorMessage = errorStr;
    }
    
    // debugPrint('📱 Showing error message to user: $errorMessage');
    _showSnackBar('❌ $errorMessage', backgroundColor: Colors.red);
  }
}

  // 8. Show Route Optimization Result
  void _showRouteOptimizationResult(Map<String, dynamic> routePlan) {
    // debugPrint('\n' + '📊'*40);
    // debugPrint('SHOWING ROUTE OPTIMIZATION RESULT DIALOG');
    // debugPrint('📊'*40);
    // debugPrint('Route Plan Summary:');
    // debugPrint('   - Vehicle: ${routePlan['vehicleName']}');
    // debugPrint('   - Driver: ${routePlan['driverName']}');
    // debugPrint('   - Total Distance: ${routePlan['totalDistance']} km');
    // debugPrint('   - Total Time: ${routePlan['totalTime']} mins');
    // debugPrint('   - Customers: ${routePlan['customerCount']}');
    // debugPrint('📊'*40 + '\n');
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => RouteOptimizationDialog(
        routePlan: routePlan,
        onConfirm: () => _confirmRouteAssignment(routePlan),
        onCancel: () {
          // debugPrint('❌ User cancelled route optimization');
          Navigator.of(context).pop();
        },
      ),
    );
  }

  // 9. Confirm and Execute Route Assignment (UPDATED WITH FULL WORKFLOW)
  // ✅ FIXED: _confirmRouteAssignment method
// Replace the method in pending_rosters_screen.dart (around line 1700)

Future<void> _confirmRouteAssignment(Map<String, dynamic> routePlan) async {
  debugPrint('\n' + '✅'*40);
  debugPrint('USER CONFIRMED ROUTE ASSIGNMENT');
  debugPrint('✅'*40);
  
  // 🔥 FIX: Capture ScaffoldMessenger BEFORE async operations
  final scaffoldMessenger = ScaffoldMessenger.of(context);
  
  Navigator.of(context).pop(); // Close dialog
  debugPrint('📱 Dialog closed');
  
  try {
    setState(() => _isOptimizing = true);
    debugPrint('⏳ UI State: _isOptimizing = true');

    final route = routePlan['route'] as List<Map<String, dynamic>>;
    final vehicleId = routePlan['vehicle']['_id']?.toString() ?? 
                     routePlan['vehicle']['id']?.toString();
    
    final totalDistanceValue = routePlan['totalDistance'];
    final totalDistance = totalDistanceValue is double ? totalDistanceValue : 
                         (totalDistanceValue is int ? totalDistanceValue.toDouble() : 
                         (totalDistanceValue is String ? double.tryParse(totalDistanceValue) ?? 0.0 : 0.0));
    
    final totalTimeValue = routePlan['totalTime'];
    final totalTime = totalTimeValue is int ? totalTimeValue : 
                     (totalTimeValue is String ? int.tryParse(totalTimeValue) ?? 0 : 
                     (totalTimeValue is double ? totalTimeValue.toInt() : 0));
    
    final startTime = routePlan['estimatedCompletion'] as DateTime? ?? DateTime.now();

    debugPrint('📋 Extracting assignment data:');
    debugPrint('   - Route stops: ${route.length}');
    debugPrint('   - Vehicle ID: $vehicleId');

    if (vehicleId == null) {
      debugPrint('❌ ERROR: Vehicle ID not found in route plan');
      throw Exception('Vehicle ID not found');
    }

    // ✅ ENHANCED: Build route data for API with ALL backend-required fields
    final routeData = route.map((stop) {
      final customer = stop['customer'] as Map<String, dynamic>;
      final rosterId = customer['id']?.toString() ?? customer['_id']?.toString() ?? '';
      final customerId = customer['customerId']?.toString() ?? customer['userId']?.toString() ?? '';
      final customerNameValue = stop['customerName'];
      final customerName = customerNameValue?.toString() ?? 'Unknown';
      final customerEmail = customer['customerEmail']?.toString() ?? customer['email']?.toString() ?? '';
      final customerPhone = customer['phone']?.toString() ?? customer['phoneNumber']?.toString() ?? '';
      
      final sequenceValue = stop['sequence'];
      final sequence = sequenceValue is int ? sequenceValue : 
                      (sequenceValue is String ? int.tryParse(sequenceValue) ?? 0 : 
                      (sequenceValue is double ? sequenceValue.toInt() : 0));
      
      // ✅ Extract new backend fields with safe fallbacks
      final pickupTime = stop['pickupTime']?.toString() ?? 
                        (stop['eta'] != null ? DateFormat('HH:mm').format(stop['eta'] as DateTime) : '00:00');
      
      final readyByTime = stop['readyByTime']?.toString() ?? pickupTime;
      
      final distanceToOfficeValue = stop['distanceToOffice'];
      final distanceToOffice = distanceToOfficeValue is double ? distanceToOfficeValue :
                              (distanceToOfficeValue is int ? distanceToOfficeValue.toDouble() :
                              (distanceToOfficeValue is String ? double.tryParse(distanceToOfficeValue) ?? 0.0 : 0.0));
      
      final distanceFromPreviousValue = stop['distanceFromPrevious'];
      final distanceFromPrevious = distanceFromPreviousValue is double ? distanceFromPreviousValue :
                                   (distanceFromPreviousValue is int ? distanceFromPreviousValue.toDouble() :
                                   (distanceFromPreviousValue is String ? double.tryParse(distanceFromPreviousValue) ?? 0.0 : 0.0));
      
      final officeTime = stop['officeTime']?.toString() ?? '';
      
      final estimatedTimeValue = stop['estimatedTime'];
      final estimatedTime = estimatedTimeValue is int ? estimatedTimeValue :
                           (estimatedTimeValue is double ? estimatedTimeValue.toInt() :
                           (estimatedTimeValue is String ? int.tryParse(estimatedTimeValue) ?? 0 : 0));
      
      return {
        // Core identifiers
        'rosterId': rosterId,
        'customerId': customerId,
        'customerName': customerName,
        'customerEmail': customerEmail,
        'customerPhone': customerPhone,
        'sequence': sequence,
        
        // ✅ Time fields (24-hour format: HH:mm)
        'pickupTime': pickupTime,           // 24-hour format
        'readyByTime': readyByTime,         // Ready-by time with buffer
        'eta': (stop['eta'] as DateTime).toIso8601String(),
        'officeTime': officeTime,           // Office arrival/departure time
        
        // ✅ Distance fields (kilometers)
        'distanceFromPrevious': distanceFromPrevious,  // Distance from previous stop
        'distanceToOffice': distanceToOffice,          // Distance from pickup to office
        
        // Location and timing
        'location': stop['location'],
        'estimatedTime': estimatedTime,
      };
    }).toList();

    debugPrint('📝 Route data prepared: ${routeData.length} stops');
    debugPrint('🔍 Sample stop data:');
    if (routeData.isNotEmpty) {
      final sample = routeData[0];
      debugPrint('   - Customer: ${sample['customerName']}');
      debugPrint('   - Pickup Time: ${sample['pickupTime']} (24-hour)');
      debugPrint('   - Ready By: ${sample['readyByTime']} (24-hour)');
      debugPrint('   - Distance to Office: ${sample['distanceToOffice']} km');
      debugPrint('   - Office Time: ${sample['officeTime']}');
    }
    debugPrint('🚀 CALLING BACKEND API: assignOptimizedRoute()');

    /// ✅ FIX: Extract date range from first customer's roster
final firstCustomer = routePlan['route'][0]['customer'] as Map<String, dynamic>;
final startDate = firstCustomer['startDate']?.toString() ?? 
                 DateTime.now().toIso8601String().split('T')[0];
final endDate = firstCustomer['endDate']?.toString() ?? startDate;

debugPrint('📅 RECURRING TRIPS: Creating trips from $startDate to $endDate');

// Call backend API with date range
final result = await widget.rosterService.assignOptimizedRoute(
  vehicleId: vehicleId,
  route: routeData,
  totalDistance: totalDistance,
  totalTime: totalTime,
  startTime: startTime,
  startDate: startDate,  // ✅ NEW
  endDate: endDate,      // ✅ NEW
);

    debugPrint('\n✅ BACKEND API RESPONSE RECEIVED:');
    debugPrint('   - Full result: $result');
    debugPrint('   - Success: ${result['success']}');
    debugPrint('   - Success count: ${result['successCount']}');
    debugPrint('   - Error count: ${result['errorCount']}');
    debugPrint('-'*80);

    setState(() => _isOptimizing = false);
    debugPrint('⏳ UI State: _isOptimizing = false');

    // 🔥🔥🔥 CRITICAL FIX: Only refresh if assignment was SUCCESSFUL
    final successCount = result['successCount'] ?? 
                        result['count'] ?? 
                        (result['data']?['successCount']) ?? 
                        0;
    
    if (successCount > 0) {
      // ✅ ONLY REFRESH AFTER SUCCESSFUL ASSIGNMENT
      debugPrint('🔄 Reloading pending rosters with FORCE REFRESH...');
      await _loadPendingRosters(forceRefresh: true);
      debugPrint('✅ Rosters reloaded and refreshed');
    } else {
      // ⚠️ Don't refresh if assignment failed
      debugPrint('⚠️ Assignment failed - NOT refreshing roster list');
    }

    // ✅ SAFE NOTIFICATION EXTRACTION
    int customerNotifs = 0;
    int driverNotifs = 0;
    
    if (result['notifications'] != null) {
      final notifs = result['notifications'];
      debugPrint('🔔 Extracting notifications from: $notifs');
      
      // Extract customer notifications safely
      if (notifs['customers'] != null) {
        if (notifs['customers'] is Map) {
          customerNotifs = notifs['customers']['sent'] ?? 0;
        } else if (notifs['customers'] is int) {
          customerNotifs = notifs['customers'];
        }
      }
      
      // Extract driver notifications safely
      if (notifs['driver'] != null) {
        if (notifs['driver'] is Map) {
          driverNotifs = notifs['driver']['sent'] ?? 0;
        } else if (notifs['driver'] is int) {
          driverNotifs = notifs['driver'];
        }
      }
    }
    
    debugPrint('\n📊 FINAL COUNTS FOR DISPLAY:');
    debugPrint('   - Success count: $successCount');
    debugPrint('   - Customer notifications: $customerNotifs');
    debugPrint('   - Driver notifications: $driverNotifs');
    
    // 🔥 FIX: Show detailed success message with actual counts
    if (successCount > 0) {
      debugPrint('📱 Showing SUCCESS message to user: $successCount customers assigned');
      debugPrint('✅'*40);
      debugPrint('ROUTE ASSIGNMENT COMPLETED SUCCESSFULLY');
      debugPrint('✅'*40 + '\n');
      
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            '✅ Successfully assigned $successCount customer${successCount != 1 ? 's' : ''} to vehicle!\n'
            '📧 Notifications: $customerNotifs customer${customerNotifs != 1 ? 's' : ''}, $driverNotifs driver\n'
            '📡 Live tracking enabled',
            style: const TextStyle(fontSize: 15),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () {
              // Navigate to assigned trips view
            },
          ),
        ),
      );
    } else {
      // 🔥 FIX: Show warning if no customers were assigned
      debugPrint('⚠️ WARNING: 0 customers were assigned!');
      debugPrint('   - This might indicate a backend issue');
      debugPrint('   - Route data had ${routeData.length} customers');
      
      // 🔥 CHECK FOR SPECIFIC ERROR MESSAGES
      String errorDetails = '';
      if (result['data'] != null && result['data']['failed'] != null) {
        final failed = result['data']['failed'] as List;
        if (failed.isNotEmpty) {
          errorDetails = '\n\nErrors:\n';
          for (final fail in failed) {
            final customerName = fail['customerName'] ?? 'Unknown';
            final error = fail['error'] ?? 'Unknown error';
            errorDetails += '• $customerName: $error\n';
          }
        }
      }
      
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            '⚠️ Assignment completed but 0 customers were assigned$errorDetails\n'
            'Please check the rosters or contact support',
            style: const TextStyle(fontSize: 14),
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 10),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Refresh',
            textColor: Colors.white,
            onPressed: () {
              _loadPendingRosters(forceRefresh: true);
            },
          ),
        ),
      );
    }
    
  } catch (e, stackTrace) {
    debugPrint('\n' + '❌'*40);
    debugPrint('ROUTE ASSIGNMENT FAILED');
    debugPrint('❌'*40);
    debugPrint('Error: $e');
    debugPrint('Stack trace: $stackTrace');
    debugPrint('❌'*40 + '\n');
    
    setState(() => _isOptimizing = false);
    
    // ✅ CRITICAL FIX: DON'T refresh on error - rosters might still be valid
    debugPrint('⚠️ (Error Recovery) NOT refreshing - rosters may still be pending');

    String errorMessage = 'Assignment failed';
    String errorTitle = '❌ Route Assignment Failed';
    final errorStr = e.toString();
    
    if (errorStr.contains('ApiException:')) {
      errorMessage = errorStr.replaceFirst('ApiException: ', '').trim();
    } else if (errorStr.contains('Exception:')) {
      errorMessage = errorStr.replaceFirst('Exception: ', '').trim();
    } else {
      errorMessage = errorStr;
    }
    
    // Check for specific error types and provide actionable guidance
    String actionGuidance = 'Try selecting a different vehicle or adjust the timing';
    
    if (errorStr.contains('Roster not found') || errorStr.contains('already assigned')) {
      errorTitle = '⚠️ Rosters Not Found or Already Assigned';
      actionGuidance = 'Solutions:\n'
          '• Refresh the roster list to see current status\n'
          '• Check if rosters were already assigned\n'
          '• Verify roster IDs are correct';
    } else if (errorStr.contains('No suitable vehicle') || errorStr.contains('No compatible vehicles')) {
      errorTitle = '🚗 No Compatible Vehicles Available';
      actionGuidance = 'Solutions:\n'
          '• Assign drivers to vehicles in Vehicle Management\n'
          '• Check if vehicles match customer company (email domain)\n'
          '• Use vehicles with larger capacity\n'
          '• Split customers into multiple routes';
    }
    
    debugPrint('💡 Showing error to admin: $errorTitle');
    debugPrint('📱 Error message: $errorMessage');
    
    // Show detailed error dialog
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  errorTitle,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  errorMessage,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb_outline, size: 20, color: Colors.blue[700]),
                          const SizedBox(width: 8),
                          Text(
                            'What to do:',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blue[900],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        actionGuidance,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue[900],
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                // Refresh to see actual status
                _loadPendingRosters(forceRefresh: true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
              child: const Text('Refresh List'),
            ),
          ],
        ),
      );
    }
  }
}

  // 9a. NEW: Manual Route Selection (MANUAL MODE)
  Future<void> _performManualRouteSelection(int count) async {
    // debugPrint('\n' + '👤'*40);
    // debugPrint('🎯 MANUAL MODE: ROUTE SELECTION STARTED');
    // debugPrint('👤'*40);
    // debugPrint('📊 Input Parameters:');
    // debugPrint('   - Requested customer count: $count');
    // debugPrint('   - Total filtered rosters: ${_filteredRosters.length}');
    // debugPrint('-'*80);
    
    try {
      setState(() => _isOptimizing = true);
      // debugPrint('⏳ UI State: _isOptimizing = true');

      // Step 1: Find optimal customer cluster (same as auto)
      // debugPrint('\n📍 STEP 1: FINDING CLOSEST CUSTOMERS');
      // debugPrint('-'*80);
      // debugPrint('Calling RouteOptimizationService.findOptimalCustomerCluster()...');
      // debugPrint('   - Input rosters: ${_filteredRosters.length}');
      // debugPrint('   - Requested count: $count');
      
      final optimalCustomers = RouteOptimizationService.findOptimalCustomerCluster(
        _filteredRosters,
        count,
      );
      
      // debugPrint('✅ CUSTOMERS FOUND: ${optimalCustomers.length}');
      for (int i = 0; i < optimalCustomers.length; i++) {
        final customer = optimalCustomers[i];
        final name = customer['customerName'] ?? customer['employeeDetails']?['name'] ?? 'Unknown';
        final id = customer['id'] ?? customer['_id'] ?? 'N/A';
        // debugPrint('   ${i + 1}. $name (ID: $id)');
      }
      // debugPrint('-'*80);

      // Step 2: Load COMPATIBLE vehicles (filtered by email domain, timing, capacity)
      // debugPrint('\n🚗 STEP 2: LOADING COMPATIBLE VEHICLES');
      // debugPrint('-'*80);
      // debugPrint('Using existing RosterService instance...');
      
      // Extract roster IDs
      final rosterIds = optimalCustomers.map((c) => c['_id'] as String).toList();
      // debugPrint('Calling widget.rosterService.getCompatibleVehicles with ${rosterIds.length} roster IDs...');
      
      final vehiclesResponse = await widget.rosterService.getCompatibleVehicles(rosterIds);
      
      // debugPrint('Response received:');
      // debugPrint('   - Success: ${vehiclesResponse['success']}');
      // debugPrint('   - Compatible count: ${(vehiclesResponse['data']?['compatible'] as List?)?.length ?? 0}');
      // debugPrint('   - Incompatible count: ${(vehiclesResponse['data']?['incompatible'] as List?)?.length ?? 0}');
      
      if (vehiclesResponse['success'] != true) {
        // debugPrint('❌ FAILED: Vehicle loading unsuccessful');
        throw Exception('Failed to load compatible vehicles');
      }

      final allVehicles = List<Map<String, dynamic>>.from(vehiclesResponse['data']?['compatible'] ?? []);
final incompatibleVehicles = List<Map<String, dynamic>>.from(vehiclesResponse['data']?['incompatible'] ?? []);

// debugPrint('✅ Found ${allVehicles.length} compatible vehicles');
// debugPrint('❌ Found ${incompatibleVehicles.length} incompatible vehicles');

setState(() => _isOptimizing = false);
      
      for (int i = 0; i < allVehicles.length && i < 5; i++) {
        final v = allVehicles[i];
        final name = _safeStringExtract(v['name']) != '' ? _safeStringExtract(v['name']) : (_safeStringExtract(v['vehicleNumber']) != '' ? _safeStringExtract(v['vehicleNumber']) : 'Unknown');
        final seats = _safeStringExtract(v['seatCapacity']) != '' ? _safeStringExtract(v['seatCapacity']) : 'N/A';
        // Handle assignedDriver as either Map or String
        final driverData = v['assignedDriver'];
        final driver = driverData is Map ? _safeStringExtract(driverData['name']) != '' ? _safeStringExtract(driverData['name']) : 'No driver' : (driverData?.toString() ?? 'No driver');
        final reason = _safeStringExtract(v['compatibilityReason']) != '' ? _safeStringExtract(v['compatibilityReason']) : 'Compatible';
        // debugPrint('   ${i + 1}. $name - $seats seats - Driver: $driver');
        // debugPrint('      ✅ $reason');
      }
      if (allVehicles.length > 5) {
        // debugPrint('   ... and ${allVehicles.length - 5} more compatible vehicles');
      }
      
      if (incompatibleVehicles.isNotEmpty) {
        // debugPrint('\n❌ Incompatible vehicles (hidden from selection):');
        for (int i = 0; i < incompatibleVehicles.length && i < 3; i++) {
          final v = incompatibleVehicles[i];
          final name = _safeStringExtract(v['name']) != '' ? _safeStringExtract(v['name']) : (_safeStringExtract(v['vehicleNumber']) != '' ? _safeStringExtract(v['vehicleNumber']) : 'Unknown');
          final reason = _safeStringExtract(v['compatibilityReason']) != '' ? _safeStringExtract(v['compatibilityReason']) : 'Incompatible';
          // debugPrint('   ${i + 1}. $name - ❌ $reason');
        }
        if (incompatibleVehicles.length > 3) {
          // debugPrint('   ... and ${incompatibleVehicles.length - 3} more incompatible vehicles');
        }
      }
      // debugPrint('-'*80);

      setState(() => _isOptimizing = false);
      // debugPrint('⏳ UI State: _isOptimizing = false');

      // ✅ CHECK: If no compatible vehicles, show helpful error message
      if (allVehicles.isEmpty) {
        // debugPrint('\n❌ NO COMPATIBLE VEHICLES FOUND');
        final compatibleCount = (vehiclesResponse['data']?['compatible'] as List?)?.length ?? 0;
        final incompatibleCount = (vehiclesResponse['data']?['incompatible'] as List?)?.length ?? 0;
        // debugPrint('   - Total vehicles checked: ${compatibleCount + incompatibleCount}');
        // debugPrint('   - Incompatible: ${incompatibleVehicles.length}');
        
        // Analyze why vehicles are incompatible
        final reasons = <String>{};
        for (final v in incompatibleVehicles) {
          final reason = _safeStringExtract(v['compatibilityReason']) != '' ? _safeStringExtract(v['compatibilityReason']) : 'Unknown reason';
          if (reason.contains('full') || reason.contains('capacity')) {
            reasons.add('full');
          } else if (reason.contains('Company') || reason.contains('company')) {
            reasons.add('company_mismatch');
          } else if (reason.contains('driver') || reason.contains('Driver')) {
            reasons.add('no_driver');
          }
        }
        
        // Build helpful error message
        String errorTitle = '🚗 All Vehicles Are Unavailable';
        String errorMessage = 'Cannot assign customers because all vehicles are currently unavailable.\n\n';
        
        if (reasons.contains('full')) {
          errorMessage += '💺 Problem: All vehicles are full\n';
          errorMessage += '✅ Solution: Wait for current trips to complete, or add more vehicles\n\n';
        }
        if (reasons.contains('no_driver')) {
          errorMessage += '👤 Problem: Vehicles don\'t have assigned drivers\n';
          errorMessage += '✅ Solution: Go to Vehicle Management → Assign drivers to vehicles\n\n';
        }
        if (reasons.contains('company_mismatch')) {
          errorMessage += '🏢 Problem: Vehicles are assigned to different companies\n';
          errorMessage += '✅ Solution: Use vehicles that match customer email domains\n\n';
        }
        
        errorMessage += '📋 What to do now:\n';
        errorMessage += '1. Go to Vehicle Management\n';
        errorMessage += '2. Check vehicle status and assignments\n';
        errorMessage += '3. Assign drivers if needed\n';
        errorMessage += '4. Come back and try again';
        
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      errorTitle,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Text(
                  errorMessage,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK, I Understand'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // Step 3: Show manual selection dialog
      // debugPrint('\n📊 STEP 3: SHOWING MANUAL SELECTION DIALOG');
      // debugPrint('-'*80);
      if (mounted) {
        // debugPrint('✅ Widget mounted - Opening Manual Vehicle Selection Dialog');
        // debugPrint('   - Customers to assign: ${optimalCustomers.length}');
        // debugPrint('   - Vehicles available: ${allVehicles.length}');
        // debugPrint('👤'*40);
        // debugPrint('MANUAL MODE PREPARATION COMPLETED');
        // debugPrint('👤'*40 + '\n');
        _showManualVehicleSelectionDialog(optimalCustomers, allVehicles);
      } else {
        // debugPrint('⚠️ Widget not mounted - Cannot show dialog');
      }
    } catch (e, stackTrace) {
      // debugPrint('\n' + '❌'*40);
      // debugPrint('MANUAL MODE SELECTION FAILED');
      // debugPrint('❌'*40);
      // debugPrint('Error: $e');
      // debugPrint('Stack trace:');
      // debugPrint(stackTrace.toString());
      // debugPrint('❌'*40 + '\n');
      
      setState(() => _isOptimizing = false);
      // debugPrint('⏳ UI State: _isOptimizing = false');
      
      // Extract detailed, actionable error message
      String errorMessage = 'Manual selection failed';
      String errorTitle = '❌ Manual Mode Failed';
      
      final errorStr = e.toString();
      
      // Check for specific error types
      if (errorStr.contains('Failed to load compatible vehicles')) {
        errorTitle = '⚠️ Vehicle Loading Failed';
        errorMessage = 'Could not load vehicle list from backend.\n\n'
            '📋 Action Required:\n'
            '• Check backend server is running\n'
            '• Verify network connection\n'
            '• Check backend logs for errors';
      } else if (errorStr.contains('No compatible vehicles')) {
        errorTitle = '🚗 No Compatible Vehicles';
        errorMessage = 'No vehicles match the requirements for these customers.\n\n'
            '📋 Action Required:\n'
            '• Ensure vehicles have assigned drivers\n'
            '• Check vehicle email domains match customer companies\n'
            '• Verify sufficient seat capacity';
      } else if (errorStr.contains('ApiException:')) {
        errorTitle = '⚠️ Backend Error';
        errorMessage = errorStr.replaceFirst('ApiException: ', '');
      } else if (errorStr.contains('Exception:')) {
        errorMessage = errorStr.replaceFirst('Exception: ', '');
      } else {
        errorMessage = errorStr;
      }
      
      // debugPrint('💡 Showing actionable error to admin: $errorTitle');
      
      // Show detailed error dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    errorTitle,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    errorMessage,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 20, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Fix the issue and try again',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue[900],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
    }
  }

  // 9b. Show Manual Vehicle Selection Dialog (ENHANCED)
  void _showManualVehicleSelectionDialog(
    List<Map<String, dynamic>> customers,
    List<Map<String, dynamic>> vehicles,
  ) {
    // debugPrint('\n' + '🚗'*50);
    // debugPrint('SHOWING MANUAL VEHICLE SELECTION DIALOG');
    // debugPrint('🚗'*50);
    // debugPrint('📊 Dialog Data:');
    // debugPrint('   - Customers to assign: ${customers.length}');
    // debugPrint('   - Available vehicles: ${vehicles.length}');
    
    // Debug vehicle data structure
    for (int i = 0; i < vehicles.length && i < 3; i++) {
      final v = vehicles[i];
      // debugPrint('\n   🚗 Vehicle ${i + 1}:');
      // debugPrint('      - Raw data keys: ${v.keys.toList()}');
      // debugPrint('      - _id: ${v['_id']}');
      // debugPrint('      - name: ${v['name']}');
      // debugPrint('      - vehicleNumber: ${v['vehicleNumber']}');
      // debugPrint('      - registrationNumber: ${v['registrationNumber']}');
      // debugPrint('      - seatCapacity: ${v['seatCapacity']}');
      // debugPrint('      - seatingCapacity: ${v['seatingCapacity']}');
      // debugPrint('      - assignedDriver: ${v['assignedDriver']}');
      // debugPrint('      - assignedCustomers: ${v['assignedCustomers']}');
      // debugPrint('      - status: ${v['status']}');
    }
    // debugPrint('🚗'*50 + '\n');
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        Map<String, dynamic>? selectedVehicle;
        
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 600,
                constraints: const BoxConstraints(maxHeight: 700),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade700,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.directions_car, color: Colors.white, size: 28),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Select Compatible Vehicle',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Only showing vehicles compatible with selected customers',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
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
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Customers to assign
                            Text(
                              'Customers to Assign (${customers.length}):',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: customers.map((customer) {
                                  final name = _safeStringExtract(customer['customerName']) != '' ? 
                                             _safeStringExtract(customer['customerName']) : 
                                             (_safeNestedAccess(customer, 'employeeDetails', 'name') != '' ?
                                             _safeNestedAccess(customer, 'employeeDetails', 'name') : 
                                             'Unknown Customer');
                                  final office = _safeStringExtract(customer['officeLocation']) != '' ?
                                               _safeStringExtract(customer['officeLocation']) : 'Unknown Office';
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      children: [
                                        Icon(Icons.person, size: 18, color: Colors.blue.shade700),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              Text(
                                                office,
                                                style: TextStyle(
                                                  color: Colors.grey.shade600,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(height: 24),
                            
                            // Vehicle selection
                            Row(
                              children: [
                                const Text(
                                  'Available Vehicles:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${vehicles.length} found',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            
                            // Vehicle list
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 350),
                              child: vehicles.isEmpty
                                  ? Container(
                                      padding: const EdgeInsets.all(32),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.orange.shade300),
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            Icons.warning_amber_rounded,
                                            size: 48,
                                            color: Colors.orange.shade600,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'No Compatible Vehicles Found',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.orange.shade900,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'All vehicles are either:\n• Already assigned to different companies\n• Don\'t have enough capacity\n• Don\'t have assigned drivers',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.orange.shade700,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Tip: Vehicles can only serve customers from the same company at the same time',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontStyle: FontStyle.italic,
                                              color: Colors.orange.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: vehicles.length,
                                      itemBuilder: (ctx, index) {
                                        final vehicle = vehicles[index];
                                        
                                        // 🔥 ENHANCED VEHICLE DATA EXTRACTION
                                        final vehicleName = vehicle['name'] ?? 
                                                          vehicle['vehicleNumber'] ?? 
                                                          vehicle['vehicleId'] ?? 
                                                          vehicle['makeModel'] ?? 
                                                          'Unknown Vehicle';
                                        
                                        final licensePlate = vehicle['licensePlate'] ?? 
                                                           vehicle['registrationNumber'] ?? 
                                                           'N/A';
                                        
                                        // 🔥 ENHANCED DRIVER EXTRACTION
                                        String driverName = 'No Driver';
                                        String driverStatus = 'unassigned';
                                        if (vehicle['assignedDriver'] != null) {
                                          final driver = vehicle['assignedDriver'];
                                          if (driver is Map) {
                                            // Driver is populated object from backend
                                            driverName = _safeStringExtract(driver['name']) != '' ?
                                                        _safeStringExtract(driver['name']) :
                                                        ('${_safeNestedAccess(driver, 'personalInfo', 'firstName')} ${_safeNestedAccess(driver, 'personalInfo', 'lastName')}').trim();
                                            if (driverName.isEmpty) {
                                              driverName = _safeStringExtract(driver['driverId']) != '' ? 
                                                          _safeStringExtract(driver['driverId']) : 'Unknown Driver';
                                            }
                                            driverStatus = driver['status'] ?? 'active';
                                          } else if (driver is String && driver.isNotEmpty) {
                                            // Driver is just an ID string
                                            driverName = driver;
                                            driverStatus = 'assigned';
                                          }
                                        }
                                        
                                        // 🔥 SAFE SEAT CAPACITY PARSING - Handles String, int, or double
                                        int totalSeats = 4; // default
                                        if (vehicle['seatCapacity'] != null) {
                                          final value = vehicle['seatCapacity'];
                                          if (value is int) {
                                            totalSeats = value;
                                          } else if (value is String) {
                                            totalSeats = int.tryParse(value) ?? 4;
                                          } else if (value is double) {
                                            totalSeats = value.toInt();
                                          }
                                        } else if (vehicle['seatingCapacity'] != null) {
                                          final value = vehicle['seatingCapacity'];
                                          if (value is int) {
                                            totalSeats = value;
                                          } else if (value is String) {
                                            totalSeats = int.tryParse(value) ?? 4;
                                          } else if (value is double) {
                                            totalSeats = value.toInt();
                                          }
                                        } else if (vehicle['capacity'] != null) {
                                          if (vehicle['capacity'] is Map) {
                                            final capacityMap = vehicle['capacity'] as Map;
                                            final passengers = capacityMap['passengers'];
                                            final seating = capacityMap['seating'];
                                            final standing = capacityMap['standing'];
                                            
                                            // Try passengers first
                                            if (passengers != null) {
                                              if (passengers is int) totalSeats = passengers;
                                              else if (passengers is String) totalSeats = int.tryParse(passengers) ?? 4;
                                              else if (passengers is double) totalSeats = passengers.toInt();
                                            } else if (seating != null) {
                                              if (seating is int) totalSeats = seating;
                                              else if (seating is String) totalSeats = int.tryParse(seating) ?? 4;
                                              else if (seating is double) totalSeats = seating.toInt();
                                            } else if (standing != null) {
                                              if (standing is int) totalSeats = standing;
                                              else if (standing is String) totalSeats = int.tryParse(standing) ?? 4;
                                              else if (standing is double) totalSeats = standing.toInt();
                                            }
                                          } else {
                                            final value = vehicle['capacity'];
                                            if (value is int) {
                                              totalSeats = value;
                                            } else if (value is String) {
                                              totalSeats = int.tryParse(value) ?? 4;
                                            } else if (value is double) {
                                              totalSeats = value.toInt();
                                            }
                                          }
                                        }
                                        
                                        final assignedSeats = (vehicle['assignedCustomers'] as List?)?.length ?? 0;
                                        final driverSeat = (driverName != 'No Driver') ? 1 : 0;
                                        final availableSeats = totalSeats - driverSeat - assignedSeats;
                                        final canFit = availableSeats >= customers.length && driverName != 'No Driver';
                                        
                                        final isSelected = selectedVehicle?['_id'] == vehicle['_id'];
                                        
                                        // 🔥 ENHANCED VEHICLE STATUS
                                        final vehicleStatus = vehicle['status']?.toString().toUpperCase() ?? 'UNKNOWN';
                                        final isActive = vehicleStatus == 'ACTIVE';
                                        final canSelect = canFit && isActive;
                                        
                                        // debugPrint('🚗 Vehicle $index: $vehicleName');
                                        // debugPrint('   - License: $licensePlate');
                                        // debugPrint('   - Driver: $driverName ($driverStatus)');
                                        // debugPrint('   - Total seats: $totalSeats');
                                        // debugPrint('   - Assigned: $assignedSeats');
                                        // debugPrint('   - Available: $availableSeats');
                                        // debugPrint('   - Can fit ${customers.length} customers: $canFit');
                                        // debugPrint('   - Status: $vehicleStatus (active: $isActive)');
                                        // debugPrint('   - Can select: $canSelect');
                                        
                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 12),
                                          child: Card(
                                            elevation: isSelected ? 4 : 1,
                                            color: isSelected 
                                                ? Colors.green.shade50 
                                                : (canSelect ? Colors.white : Colors.grey.shade100),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              side: BorderSide(
                                                color: isSelected 
                                                    ? Colors.green.shade300
                                                    : (canSelect ? Colors.grey.shade300 : Colors.grey.shade400),
                                                width: isSelected ? 2 : 1,
                                              ),
                                            ),
                                            child: ListTile(
                                              enabled: canSelect,
                                              contentPadding: const EdgeInsets.all(16),
                                              leading: Container(
                                                width: 50,
                                                height: 50,
                                                decoration: BoxDecoration(
                                                  color: canSelect 
                                                      ? (isSelected ? Colors.green.shade100 : Colors.blue.shade100)
                                                      : Colors.grey.shade300,
                                                  borderRadius: BorderRadius.circular(25),
                                                ),
                                                child: Icon(
                                                  Icons.directions_car,
                                                  color: canSelect 
                                                      ? (isSelected ? Colors.green.shade700 : Colors.blue.shade700)
                                                      : Colors.grey.shade600,
                                                  size: 28,
                                                ),
                                              ),
                                              title: Text(
                                                vehicleName,
                                                style: TextStyle(
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                                  fontSize: 16,
                                                  color: canSelect ? Colors.black87 : Colors.grey.shade600,
                                                ),
                                              ),
                                              subtitle: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.confirmation_number,
                                                        size: 14,
                                                        color: Colors.grey.shade600,
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        licensePlate,
                                                        style: TextStyle(
                                                          color: Colors.grey.shade700,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 16),
                                                      Icon(
                                                        Icons.person,
                                                        size: 14,
                                                        color: driverName != 'No Driver' 
                                                            ? Colors.green.shade600 
                                                            : Colors.red.shade600,
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        driverName,
                                                        style: TextStyle(
                                                          color: driverName != 'No Driver' 
                                                              ? Colors.green.shade700 
                                                              : Colors.red.shade700,
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.airline_seat_recline_normal,
                                                        size: 16,
                                                        color: canFit ? Colors.green.shade600 : Colors.red.shade600,
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        '$availableSeats/$totalSeats seats available',
                                                        style: TextStyle(
                                                          color: canFit ? Colors.green.shade700 : Colors.red.shade700,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 16),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: isActive 
                                                              ? Colors.green.shade100 
                                                              : Colors.orange.shade100,
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: Text(
                                                          vehicleStatus,
                                                          style: TextStyle(
                                                            color: isActive 
                                                                ? Colors.green.shade800 
                                                                : Colors.orange.shade800,
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  if (!canSelect) ...[
                                                    const SizedBox(height: 8),
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.warning,
                                                          size: 14,
                                                          color: Colors.orange.shade600,
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Expanded(
                                                          child: Text(
                                                            !isActive 
                                                                ? 'Vehicle not active'
                                                                : driverName == 'No Driver'
                                                                    ? 'No driver assigned'
                                                                    : 'Insufficient seats (need ${customers.length})',
                                                            style: TextStyle(
                                                              color: Colors.orange.shade700,
                                                              fontSize: 12,
                                                              fontStyle: FontStyle.italic,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              trailing: isSelected
                                                  ? Container(
                                                      width: 32,
                                                      height: 32,
                                                      decoration: BoxDecoration(
                                                        color: Colors.green.shade700,
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: const Icon(
                                                        Icons.check,
                                                        color: Colors.white,
                                                        size: 20,
                                                      ),
                                                    )
                                                  : canSelect
                                                      ? Icon(
                                                          Icons.radio_button_unchecked,
                                                          color: Colors.grey.shade400,
                                                        )
                                                      : Icon(
                                                          Icons.block,
                                                          color: Colors.red.shade400,
                                                        ),
                                              onTap: canSelect
                                                  ? () {
                                                      // debugPrint('✅ User selected vehicle: $vehicleName');
                                                      setDialogState(() => selectedVehicle = vehicle);
                                                    }
                                                  : null,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Actions
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        border: Border(top: BorderSide(color: Colors.grey.shade300)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              // debugPrint('❌ User cancelled vehicle selection');
                              Navigator.of(context).pop();
                            },
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: selectedVehicle == null
                                ? null
                                : () async {
                                    final vehicleName = selectedVehicle!['name'] ?? 
                                                      selectedVehicle!['vehicleNumber'] ?? 
                                                      'Unknown';
                                    debugPrint('✅ User confirmed vehicle selection: $vehicleName');
                                    Navigator.of(context).pop(); // Close vehicle selection dialog
                                    
                                    // ✅ FIX: Show route optimization dialog (same as auto mode)
                                    await _showManualRouteOptimization(customers, selectedVehicle!);
                                  },
                            icon: const Icon(Icons.route),
                            label: const Text('Continue to Route'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
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
      },
    );
  }

  // 9c. Show Manual Route Optimization (NEW METHOD)
  // ✅ This method bridges manual vehicle selection to route optimization dialog
  Future<void> _showManualRouteOptimization(
    List<Map<String, dynamic>> customers,
    Map<String, dynamic> vehicle,
  ) async {
    debugPrint('\n' + '🗺️' * 40);
    debugPrint('MANUAL MODE: GENERATING ROUTE OPTIMIZATION');
    debugPrint('🗺️' * 40);
    
    try {
      setState(() => _isOptimizing = true);
      debugPrint('⏳ UI State: _isOptimizing = true');

      final vehicleId = vehicle['_id']?.toString() ?? vehicle['id']?.toString();
      final vehicleName = vehicle['name'] ?? vehicle['vehicleNumber'] ?? 'Unknown';
      
      debugPrint('📋 Route generation details:');
      debugPrint('   - Vehicle: $vehicleName');
      debugPrint('   - Vehicle ID: $vehicleId');
      debugPrint('   - Customers: ${customers.length}');
      
      if (vehicleId == null) {
        debugPrint('❌ ERROR: Vehicle ID not found');
        throw Exception('Vehicle ID not found');
      }

      // Generate route plan (same as auto mode)
      debugPrint('🗺️ Generating route plan...');
      final startTime = DateTime.now().add(const Duration(minutes: 30));
      
      final routePlan = await RouteOptimizationService.generateRoutePlan(
        vehicle: vehicle,
        customers: customers,
        startTime: startTime,
      );

      debugPrint('✅ Route plan generated successfully');
      debugPrint('   - Total distance: ${routePlan['totalDistance']} km');
      debugPrint('   - Total time: ${routePlan['totalTime']} mins');
      debugPrint('   - Stops: ${routePlan['customerCount']}');

      setState(() => _isOptimizing = false);
      debugPrint('⏳ UI State: _isOptimizing = false');

      // ✅ Show route optimization dialog (SAME AS AUTO MODE)
      if (mounted) {
        debugPrint('📊 Opening RouteOptimizationDialog for manual mode');
        _showRouteOptimizationResult(routePlan);
      }
    } catch (e, stackTrace) {
      debugPrint('\n' + '❌' * 40);
      debugPrint('MANUAL ROUTE GENERATION FAILED');
      debugPrint('❌' * 40);
      debugPrint('Error: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('❌' * 40 + '\n');
      
      setState(() => _isOptimizing = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Route generation failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // 9d. Confirm Manual Assignment (LEGACY - KEPT FOR REFERENCE)
  // NOTE: This method is no longer used after the fix
  // Manual mode now uses _showManualRouteOptimization → RouteOptimizationDialog → _confirmRouteAssignment
  // (Same flow as auto mode)
  // 9c. Confirm Manual Assignment - COMPLETE FIXED VERSION
Future<void> _confirmManualAssignment(
  List<Map<String, dynamic>> customers,
  Map<String, dynamic> vehicle,
) async {
  debugPrint('\n' + '✅' * 40);
  debugPrint('USER CONFIRMED MANUAL ASSIGNMENT');
  debugPrint('✅' * 40);
  
  try {
    setState(() => _isOptimizing = true);
    debugPrint('⏳ UI State: _isOptimizing = true');

    final vehicleId = vehicle['_id']?.toString() ?? vehicle['id']?.toString();
    final vehicleName = vehicle['name'] ?? vehicle['vehicleNumber'] ?? 'Unknown';
    
    debugPrint('📋 Assignment details:');
    debugPrint('   - Vehicle: $vehicleName');
    debugPrint('   - Vehicle ID: $vehicleId');
    debugPrint('   - Customers: ${customers.length}');
    
    if (vehicleId == null) {
      debugPrint('❌ ERROR: Vehicle ID not found');
      throw Exception('Vehicle ID not found');
    }

    // ✅ FIX: Use same flow as auto assignment
    // Generate route plan first
    debugPrint('🗺️ Generating route plan...');
    final startTime = DateTime.now().add(const Duration(minutes: 30));
    
    final routePlan = await RouteOptimizationService.generateRoutePlan(
      vehicle: vehicle,
      customers: customers,
      startTime: startTime,
    );

    debugPrint('✅ Route plan generated');
    debugPrint('   - Total distance: ${routePlan['totalDistance']} km');
    debugPrint('   - Total time: ${routePlan['totalTime']} mins');

    // ✅ Extract route data with all required fields
    final route = routePlan['route'] as List<Map<String, dynamic>>;
    
    final routeData = route.map((stop) {
      final customer = stop['customer'] as Map<String, dynamic>;
      final rosterId = customer['id']?.toString() ?? customer['_id']?.toString() ?? '';
      final customerId = customer['customerId']?.toString() ?? customer['userId']?.toString() ?? '';
      final customerName = stop['customerName']?.toString() ?? 'Unknown';
      final customerEmail = customer['customerEmail']?.toString() ?? customer['email']?.toString() ?? '';
      final customerPhone = customer['phone']?.toString() ?? customer['phoneNumber']?.toString() ?? '';
      
      final sequence = stop['sequence'] is int ? stop['sequence'] : 
                      (stop['sequence'] is String ? int.tryParse(stop['sequence']) ?? 0 : 0);
      
      final pickupTime = stop['pickupTime']?.toString() ?? 
                        (stop['eta'] != null ? DateFormat('HH:mm').format(stop['eta'] as DateTime) : '00:00');
      
      final readyByTime = stop['readyByTime']?.toString() ?? pickupTime;
      
      final distanceToOffice = stop['distanceToOffice'] is double ? stop['distanceToOffice'] :
                              (stop['distanceToOffice'] is int ? (stop['distanceToOffice'] as int).toDouble() :
                              (stop['distanceToOffice'] is String ? double.tryParse(stop['distanceToOffice']) ?? 0.0 : 0.0));
      
      final distanceFromPrevious = stop['distanceFromPrevious'] is double ? stop['distanceFromPrevious'] :
                                   (stop['distanceFromPrevious'] is int ? (stop['distanceFromPrevious'] as int).toDouble() :
                                   (stop['distanceFromPrevious'] is String ? double.tryParse(stop['distanceFromPrevious']) ?? 0.0 : 0.0));
      
      return {
        'rosterId': rosterId,
        'customerId': customerId,
        'customerName': customerName,
        'customerEmail': customerEmail,
        'customerPhone': customerPhone,
        'sequence': sequence,
        'pickupTime': pickupTime,
        'readyByTime': readyByTime,
        'eta': (stop['eta'] as DateTime).toIso8601String(),
        'distanceFromPrevious': distanceFromPrevious,
        'distanceToOffice': distanceToOffice,
        'location': stop['location'],
        'estimatedTime': stop['estimatedTime'] ?? 0,
      };
    }).toList();

    final totalDistance = routePlan['totalDistance'] is double ? routePlan['totalDistance'] : 
                         (routePlan['totalDistance'] is int ? (routePlan['totalDistance'] as int).toDouble() : 
                         double.tryParse(routePlan['totalDistance'].toString()) ?? 0.0);
    
    final totalTime = routePlan['totalTime'] is int ? routePlan['totalTime'] : 
                     (routePlan['totalTime'] is String ? int.tryParse(routePlan['totalTime']) ?? 0 : 
                     (routePlan['totalTime'] as double).toInt());

    debugPrint('🚀 CALLING assignOptimizedRoute (same as auto mode)');

    // ✅ Use assignOptimizedRoute instead of assignRostersToVehicle
    final result = await widget.rosterService.assignOptimizedRoute(
      vehicleId: vehicleId,
      route: routeData,
      totalDistance: totalDistance,
      totalTime: totalTime,
      startTime: startTime,
    );

    debugPrint('✅ BACKEND API RESPONSE RECEIVED:');
    debugPrint('   - Success: ${result['success']}');
    debugPrint('   - Success count: ${result['successCount']}');

    setState(() => _isOptimizing = false);

    // Reload rosters
    await _loadPendingRosters(forceRefresh: true);

    if (mounted) {
      final successCount = result['successCount'] ?? routeData.length;
      debugPrint('✅ Manual assignment completed successfully');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Successfully assigned $successCount customer${successCount != 1 ? 's' : ''} to vehicle!\n'
            '📧 Notifications sent to customers and driver.',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  } catch (e, stackTrace) {
    debugPrint('❌ Manual assignment failed: $e');
    debugPrint('Stack trace: $stackTrace');
    
    setState(() => _isOptimizing = false);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Assignment failed: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}

  // 10. Handle Smart Assign (Old Batch Optimization)
  Future<void> _handleSmartAssign(List<Map<String, dynamic>> targetRosters) async {
    // debugPrint('🚀 _handleSmartAssign: Starting smart assignment for ${targetRosters.length} rosters');
    
    try {
      setState(() => _isOptimizing = true);

      // Simulate calculation delay
      await Future.delayed(const Duration(milliseconds: 800));

      // Run batch optimization
      final assignments = await _batchOptimizeRosters(targetRosters);
      // debugPrint('✅ _handleSmartAssign: Optimization complete - ${assignments.length} assignments found');

      setState(() => _isOptimizing = false);

      if (assignments.isEmpty) {
        // debugPrint('⚠️ _handleSmartAssign: No assignments found');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No suitable drivers found nearby.')),
          );
        }
        return;
      }

      // Show results dialog
      if (mounted) {
        _showOptimizationResultsDialog(assignments);
      }
    } catch (e) {
      // debugPrint('❌ _handleSmartAssign: Error during smart assignment: $e');
      setState(() => _isOptimizing = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during smart assignment: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 11. Show Simple Optimization Results Dialog
  void _showOptimizationResultsDialog(List<Map<String, dynamic>> assignments) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green[600]),
              const SizedBox(width: 12),
              const Text('Optimization Complete'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Found ${assignments.length} optimal driver assignments',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: assignments.length,
                    itemBuilder: (ctx, i) {
                      final assign = assignments[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue[100],
                          child: Icon(Icons.directions_car, color: Colors.blue[700], size: 20),
                        ),
                        title: Text(assign['driverName']),
                        subtitle: Text('→ ${assign['customerName']}'),
                        trailing: Text(
                          '${assign['distance'].toStringAsFixed(1)} km',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      );
                    },
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
                Navigator.pop(context);
                if (!mounted) return;
                setState(() => _isOptimizing = true);
                try {
                  final vehicleId = assignments.first['vehicleId']?.toString();
                  if (vehicleId == null) throw Exception('Vehicle missing in assignment');

                  final routeData = assignments.map((assign) {
                    return {
                      'rosterId': assign['rosterId']?.toString() ?? '',
                      'customerId': assign['customerId']?.toString() ?? '',
                      'customerName': assign['customerName']?.toString() ?? '',
                      'customerEmail': assign['customerEmail']?.toString() ?? '',
                      'customerPhone': assign['customerPhone']?.toString() ?? '',
                      'sequence': assign['sequence'] ?? 0,
                      'pickupTime': assign['pickupTime']?.toString() ?? '',
                      'eta': assign['eta']?.toString() ?? '',
                      'location': assign['location'],
                      'distanceFromPrevious': assign['distanceFromPrevious'] ?? 0,
                      'estimatedTime': assign['estimatedTime'] ?? 0,
                    };
                  }).toList();

                  final totalDistance = assignments.fold<double>(
                    0,
                    (sum, a) => sum + (a['distance'] is num ? (a['distance'] as num).toDouble() : 0.0),
                  );
                  final totalTime = assignments.fold<int>(
                    0,
                    (sum, a) => sum + (a['estimatedTime'] is num ? (a['estimatedTime'] as num).toInt() : 0),
                  );

                  await widget.rosterService.assignOptimizedRoute(
                    vehicleId: vehicleId,
                    route: routeData,
                    totalDistance: totalDistance,
                    totalTime: totalTime,
                    startTime: DateTime.now(),
                  );

                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Assigned ${assignments.length} rosters to drivers'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  await _loadPendingRosters(forceRefresh: true);
                } catch (e) {
                  // debugPrint('Assign failed: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Assignment failed: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isOptimizing = false);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _themeColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm & Assign'),
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // PRIORITY CALCULATION
  // ==========================================

  Map<String, dynamic> _calculatePriority(Map<String, dynamic> roster) {
    final dateStr = roster['startDate']?.toString();
    // debugPrint('⚡ _calculatePriority: Processing roster with startDate: $dateStr');
    
    if (dateStr == null) {
      // debugPrint('⚠️ _calculatePriority: No startDate found, returning normal priority');
      return {'level': 'normal', 'color': Colors.grey, 'label': 'No Date', 'days': 999};
    }

    try {
      final startDate = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final rosterDay = DateTime(startDate.year, startDate.month, startDate.day);
      final daysUntil = rosterDay.difference(today).inDays;

      // debugPrint('⚡ _calculatePriority: startDate=$startDate, today=$today, daysUntil=$daysUntil');

      Map<String, dynamic> priority;
      if (daysUntil < 0) {
        priority = {'level': 'overdue', 'color': const Color(0xFFDC2626), 'label': 'OVERDUE', 'days': daysUntil};
      } else if (daysUntil == 0) {
        priority = {'level': 'urgent', 'color': const Color(0xFFEF4444), 'label': 'TODAY', 'days': daysUntil};
      } else if (daysUntil == 1) {
        priority = {'level': 'urgent', 'color': const Color(0xFFEF4444), 'label': 'TOMORROW', 'days': daysUntil};
      } else if (daysUntil <= 3) {
        priority = {'level': 'high', 'color': const Color(0xFFF59E0B), 'label': 'THIS WEEK', 'days': daysUntil};
      } else if (daysUntil <= 7) {
        priority = {'level': 'medium', 'color': const Color(0xFF3B82F6), 'label': 'NEXT WEEK', 'days': daysUntil};
      } else {
        priority = {'level': 'normal', 'color': const Color(0xFF10B981), 'label': 'FUTURE', 'days': daysUntil};
      }
      
      // debugPrint('✅ _calculatePriority: Calculated priority - ${priority['level']} (${priority['label']})');
      return priority;
    } catch (e) {
      // debugPrint('❌ _calculatePriority: Error parsing date "$dateStr": $e');
      return {'level': 'normal', 'color': Colors.grey, 'label': 'INVALID', 'days': 999};
    }
  }

  // ==========================================
  // DATA LOADING
  // ==========================================

  Future<void> _loadPendingRosters({bool forceRefresh = false}) async {
  if (!mounted) return;

  setState(() {
    _isLoading = true;
    _errorMessage = null;
  });

  try {
    // debugPrint('🔄 PendingRostersScreen: Loading pending rosters... (forceRefresh: $forceRefresh)');
    // debugPrint('🚀 PendingRostersScreen: About to call widget.rosterService.getPendingRosters()...');
    
    final rosters = await widget.rosterService.getPendingRosters(forceRefresh: forceRefresh);
    
    // debugPrint('🚀 PendingRostersScreen: SUCCESSFULLY received response from getPendingRosters()!');
    // debugPrint('📥 PendingRostersScreen: Received ${rosters.length} rosters from API');

    // ✅✅✅ CRITICAL FIX: MUCH STRICTER FILTERING ✅✅✅
    final trulyPendingRosters = rosters.where((roster) {
      try {
        final status = roster['status']?.toString().toLowerCase() ?? '';
        
        // ✅ Check ALL possible assignment indicators
        final hasAssignedDriver = roster['assignedDriverId'] != null && 
                                 roster['assignedDriverId'].toString().isNotEmpty &&
                                 roster['assignedDriverId'].toString() != 'null';
        
        final hasAssignedVehicle = roster['assignedVehicleId'] != null && 
                                  roster['assignedVehicleId'].toString().isNotEmpty &&
                                  roster['assignedVehicleId'].toString() != 'null';
        
        final hasVehicleIdField = roster['vehicleId'] != null && 
                                 roster['vehicleId'].toString().isNotEmpty &&
                                 roster['vehicleId'].toString() != 'null';
        
        final hasDriverIdField = roster['driverId'] != null && 
                                roster['driverId'].toString().isNotEmpty &&
                                roster['driverId'].toString() != 'null';
        
        final hasTripId = roster['tripId'] != null && 
                         roster['tripId'].toString().isNotEmpty &&
                         roster['tripId'].toString() != 'null';

        // ✅✅✅ NEW: Also check vehicleNumber and driverName fields
        final hasVehicleNumber = roster['vehicleNumber'] != null && 
                                roster['vehicleNumber'].toString().isNotEmpty &&
                                roster['vehicleNumber'].toString() != 'null';
        
        final hasDriverName = roster['driverName'] != null && 
                             roster['driverName'].toString().isNotEmpty &&
                             roster['driverName'].toString() != 'null';

        // ✅✅✅ NEW: Check if status is explicitly 'assigned'
        final isAssignedStatus = (status == 'assigned');
        
        // Only include if status is pending AND no assignment fields set
        final isPending = (status == 'pending' || 
                          status == 'pending_assignment' || 
                          status == 'created') &&
                         !hasAssignedDriver &&
                         !hasAssignedVehicle &&
                         !hasVehicleIdField &&
                         !hasDriverIdField &&
                         !hasTripId &&
                         !hasVehicleNumber &&
                         !hasDriverName &&
                         !isAssignedStatus;

        // ✅ Enhanced debug logging
        if (!isPending) {
          // debugPrint('🚫 FILTERED OUT: ${roster['customerName']} (${roster['customerEmail']})');
          // debugPrint('   Status: $status');
          // debugPrint('   vehicleId: ${roster['vehicleId']}');
          // debugPrint('   driverId: ${roster['driverId']}');
          // debugPrint('   tripId: ${roster['tripId']}');
          // debugPrint('   assignedVehicleId: ${roster['assignedVehicleId']}');
          // debugPrint('   assignedDriverId: ${roster['assignedDriverId']}');
          // debugPrint('   vehicleNumber: ${roster['vehicleNumber']}');
          // debugPrint('   driverName: ${roster['driverName']}');
        }
        
        return isPending;
      } catch (e) {
        // debugPrint('❌ Error processing roster: $e');
        // debugPrint('❌ Roster data: ${roster.toString()}');
        return false;
      }
    }).toList();

    // debugPrint('📊 Status Filter: ${rosters.length} → ${trulyPendingRosters.length} truly pending');

    if (mounted) {
      final filteredRosters = _filterOutAdminEmails(trulyPendingRosters);
      // debugPrint('🔍 PendingRostersScreen: After admin email filtering: ${filteredRosters.length} rosters');
      
      final uniqueRosters = _removeDuplicateRosters(List<Map<String, dynamic>>.from(filteredRosters));
      // debugPrint('🧹 PendingRostersScreen: After duplicate removal: ${uniqueRosters.length} rosters');

      setState(() {
        _allPendingRosters = uniqueRosters;
        _extractOrganizations();
        _applyFilters();
        _isLoading = false;
      });
      
      // debugPrint('✅ PendingRostersScreen: Successfully loaded ${_allPendingRosters.length} pending rosters');
      
      if (forceRefresh && mounted) {
        _showSnackBar('✅ Rosters refreshed successfully', backgroundColor: Colors.green);
      }
    }
  } catch (e) {
    // debugPrint('❌❌❌ PendingRostersScreen: CRITICAL ERROR ❌❌❌');
    // debugPrint('❌ PendingRostersScreen: Error loading pending rosters: $e');
    // debugPrint('❌ PendingRostersScreen: Error type: ${e.runtimeType}');
    // debugPrint('❌ PendingRostersScreen: Stack trace: ${StackTrace.current}');
    // debugPrint('❌❌❌ END CRITICAL ERROR ❌❌❌');
    
    if (mounted) {
      setState(() {
        _errorMessage = 'Unable to load pending rosters. Please check your connection.\n\nError: ${e.toString()}';
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load rosters: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _loadPendingRosters(forceRefresh: true),
          ),
        ),
      );
    }
  }
}

  // ✅ FIXED: Filter out admin emails from roster list
  List<Map<String, dynamic>> _filterOutAdminEmails(List<Map<String, dynamic>> rosters) {
    // debugPrint('🔍 _filterOutAdminEmails: Starting with ${rosters.length} rosters');
    
    const adminEmail = 'admin@abrafleet.com';
    final filteredRosters = <Map<String, dynamic>>[];
    int adminRostersFound = 0;
    
    for (var roster in rosters) {
      try {
        final customerEmail = roster['customerEmail']?.toString().toLowerCase() ?? '';
        
        // ✅ FIX: Handle employeeData as List, not Map
        String employeeEmail = '';
        
        // Try employeeDetails first (if it's a Map)
        if (roster['employeeDetails'] is Map) {
          employeeEmail = _safeNestedAccess(roster, 'employeeDetails', 'email').toLowerCase();
        }
        
        // If still empty, try employeeData (which is a List)
        if (employeeEmail.isEmpty && roster['employeeData'] is List) {
          final employeeList = roster['employeeData'] as List;
          if (employeeList.isNotEmpty && employeeList[0] is Map) {
            employeeEmail = employeeList[0]['email']?.toString().toLowerCase() ?? '';
          }
        }
        
        // If still empty, try direct email field
        if (employeeEmail.isEmpty) {
          employeeEmail = roster['email']?.toString().toLowerCase() ?? '';
        }
        
        // debugPrint('🔍 Checking roster - customerEmail: $customerEmail, employeeEmail: $employeeEmail');
        
        // Check if any email matches admin email
        if (customerEmail == adminEmail.toLowerCase() || employeeEmail == adminEmail.toLowerCase()) {
          adminRostersFound++;
          // debugPrint('⚠️ ADMIN EMAIL FOUND - Skipping roster with admin email: $customerEmail / $employeeEmail');
          continue;
        }
        
        filteredRosters.add(roster);
      } catch (e) {
        // debugPrint('❌ Error filtering roster: $e');
        // debugPrint('❌ Roster data: ${roster.toString()}');
        // Skip problematic rosters and continue
        filteredRosters.add(roster);
        continue;
      }
    }
    
    // debugPrint('✅ _filterOutAdminEmails: Filtered out $adminRostersFound admin rosters');
    // debugPrint('📊 _filterOutAdminEmails: Returning ${filteredRosters.length} rosters');
    
    return filteredRosters;
  }

  void _extractOrganizations() {
    // debugPrint('🏢 _extractOrganizations: Starting extraction from ${_allPendingRosters.length} rosters');
    
    final Set<String> orgs = {};
    for (var roster in _allPendingRosters) {
      String? company = roster['companyName'];
      if (company == null || company.isEmpty) company = roster['organization'];
      if (company == null || company.isEmpty) company = roster['officeLocation'];
      
      if (company != null && company.isNotEmpty) {
        orgs.add(company);
        // debugPrint('🏢 Found organization: $company');
      }
    }
    
    final sortedOrgs = orgs.toList()..sort();
    _availableOrganizations = ['All Organizations', ...sortedOrgs];
    
    // debugPrint('✅ _extractOrganizations: Found ${orgs.length} unique organizations');
    // debugPrint('📋 Organizations: ${orgs.join(', ')}');
  }

  List<Map<String, dynamic>> _removeDuplicateRosters(List<Map<String, dynamic>> rosters) {
    // debugPrint('🧹 _removeDuplicateRosters: Starting with ${rosters.length} rosters');
    
    final Set<String> seenKeys = {};
    final List<Map<String, dynamic>> uniqueRosters = [];
    int duplicatesFound = 0;
    
    for (var roster in rosters) {
      try {
        final customerEmail = _safeStringExtract(roster['customerEmail']);
        final employeeEmail = _safeNestedAccess(roster, 'employeeDetails', 'email') != '' ? 
                             _safeNestedAccess(roster, 'employeeDetails', 'email') : 
                             (_safeNestedAccess(roster, 'employeeData', 'email') != '' ? 
                             _safeNestedAccess(roster, 'employeeData', 'email') : 
                             _safeStringExtract(roster['email']));
        final startDate = _safeStringExtract(roster['startDate']);
        final startTime = _safeStringExtract(roster['startTime']);
        final rosterType = _safeStringExtract(roster['rosterType']);
        final officeLocation = _safeStringExtract(roster['officeLocation']);
        final rosterId = _safeStringExtract(roster['_id']);
        
        final email = customerEmail.isNotEmpty ? customerEmail : employeeEmail;
        
        // ✅ FIX: If email is empty, use roster ID to ensure uniqueness
        final uniqueKey = email.isNotEmpty 
            ? '$email|$startDate|$startTime|$rosterType|$officeLocation'
            : 'ID:$rosterId|$startDate|$startTime|$rosterType|$officeLocation';
        
        // debugPrint('🔍 Processing roster - Email: $email, ID: $rosterId, Key: $uniqueKey');
        
        // ✅ FIX: Always check for duplicates, don't skip if email is empty
        if (!seenKeys.contains(uniqueKey)) {
          seenKeys.add(uniqueKey);
          uniqueRosters.add(roster);
          // debugPrint('✅ Added unique roster for: ${email.isNotEmpty ? email : "ID:$rosterId"}');
        } else {
          duplicatesFound++;
          // debugPrint('⚠️ Duplicate found for: ${email.isNotEmpty ? email : "ID:$rosterId"} (Key: $uniqueKey)');
        }
      } catch (e) {
        // debugPrint('❌ Error processing roster for duplicates: $e');
        // debugPrint('❌ Roster data: ${roster.toString()}');
        // Skip problematic rosters
        continue;
      }
    }
    
    // debugPrint('✅ _removeDuplicateRosters: Removed $duplicatesFound duplicates');
    // debugPrint('📊 _removeDuplicateRosters: Returning ${uniqueRosters.length} unique rosters');
    
    return uniqueRosters;
  }

  // ==========================================
  // FILTERING LOGIC
  // ==========================================

  void _applyFilters() {
    // debugPrint('🔍 _applyFilters: Starting with ${_allPendingRosters.length} rosters');
    // debugPrint('🔍 Active filters - Org: $_selectedOrganization, Type: $_selectedRosterType, Priority: $_selectedPriority, Search: "$_searchQuery"');
    
    List<Map<String, dynamic>> tempResults = List.from(_allPendingRosters);
    int initialCount = tempResults.length;

    // Organization Filter
    if (_selectedOrganization != 'All Organizations') {
      // debugPrint('🏢 Applying organization filter: $_selectedOrganization');
      int beforeCount = tempResults.length;
      tempResults = tempResults.where((roster) {
        final company = (roster['companyName'] ?? roster['organization'] ?? roster['officeLocation'] ?? '').toString();
        return company == _selectedOrganization;
      }).toList();
      // debugPrint('🏢 Organization filter: ${beforeCount} → ${tempResults.length} rosters');
    }

    // Roster Type Filter
    if (_selectedRosterType != 'All') {
      // debugPrint('📋 Applying roster type filter: $_selectedRosterType');
      int beforeCount = tempResults.length;
      tempResults = tempResults.where((roster) {
        final type = (roster['rosterType'] ?? '').toString().toLowerCase();
        return type == _selectedRosterType.toLowerCase();
      }).toList();
      // debugPrint('📋 Roster type filter: ${beforeCount} → ${tempResults.length} rosters');
    }

    // Priority Filter
    if (_selectedPriority != 'All') {
      // debugPrint('⚡ Applying priority filter: $_selectedPriority');
      int beforeCount = tempResults.length;
      tempResults = tempResults.where((roster) {
        final priority = _calculatePriority(roster);
        return priority['level'] == _selectedPriority.toLowerCase();
      }).toList();
      // debugPrint('⚡ Priority filter: ${beforeCount} → ${tempResults.length} rosters');
    }

    // Search Query Filter
    if (_searchQuery.isNotEmpty) {
      // debugPrint('🔍 Applying search filter: "$_searchQuery"');
      int beforeCount = tempResults.length;
      final query = _searchQuery.toLowerCase();
      tempResults = tempResults.where((roster) {
        // 🔥 FIX: Use safe access methods to prevent JsonMap errors
        final customerName = _safeStringExtract(roster['customerName']).toLowerCase();
        final employeeName = _safeNestedAccess(roster, 'employeeDetails', 'name').toLowerCase();
        final employeeDataName = _safeNestedAccess(roster, 'employeeData', 'name').toLowerCase();
        final customerEmail = _safeStringExtract(roster['customerEmail']).toLowerCase();
        final email = _safeStringExtract(roster['email']).toLowerCase();
        final employeeEmail = _safeNestedAccess(roster, 'employeeDetails', 'email').toLowerCase();
        final location = _safeStringExtract(roster['officeLocation']).toLowerCase();
        final id = _safeStringExtract(roster['id'] ?? roster['_id']).toLowerCase();
        
        final matches = customerName.contains(query) || 
               employeeName.contains(query) ||
               employeeDataName.contains(query) ||
               customerEmail.contains(query) ||
               email.contains(query) || 
               employeeEmail.contains(query) ||
               location.contains(query) || 
               id.contains(query);
               
        if (matches) {
          // debugPrint('🎯 Search match found: $customerName / $customerEmail');
        }
        
        return matches;
      }).toList();
      // debugPrint('🔍 Search filter: ${beforeCount} → ${tempResults.length} rosters');
    }

    // ── CSC Filters (Country, State, City, Local Area) ────────────────────────
    if (_filterCountry != null && _filterCountry!.isNotEmpty) {
      tempResults = tempResults.where((roster) {
        final rosterCountry = _safeStringExtract(roster['country']);
        return rosterCountry == _filterCountry;
      }).toList();
    }

    if (_filterState != null && _filterState!.isNotEmpty) {
      tempResults = tempResults.where((roster) {
        final rosterState = _safeStringExtract(roster['state']);
        return rosterState == _filterState;
      }).toList();
    }

    if (_filterCity != null && _filterCity!.isNotEmpty) {
      tempResults = tempResults.where((roster) {
        final rosterCity = _safeStringExtract(roster['city']).toLowerCase();
        return rosterCity.contains(_filterCity!.toLowerCase());
      }).toList();
    }

    if (_filterLocalArea != null && _filterLocalArea!.isNotEmpty) {
      tempResults = tempResults.where((roster) {
        final rosterArea = _safeStringExtract(roster['area']).toLowerCase();
        final pickupLoc = _safeStringExtract(roster['pickupLocation']).toLowerCase();
        final dropLoc = _safeStringExtract(roster['dropLocation']).toLowerCase();
        return rosterArea.contains(_filterLocalArea!.toLowerCase()) ||
               pickupLoc.contains(_filterLocalArea!.toLowerCase()) ||
               dropLoc.contains(_filterLocalArea!.toLowerCase());
      }).toList();
    }

    // Sorting
    // debugPrint('📊 Applying sort order: $_selectedSortOrder');
    tempResults.sort((a, b) {
      switch (_selectedSortOrder) {
        case 'Priority First':
          final priorityA = _calculatePriority(a);
          final priorityB = _calculatePriority(b);
          
          // 🔥 SAFE PARSING: Handle String, int, or double for days
          final daysAValue = priorityA['days'];
          final daysA = daysAValue is int ? daysAValue : 
                       (daysAValue is String ? int.tryParse(daysAValue) ?? 0 : 
                       (daysAValue is double ? daysAValue.toInt() : 0));
          
          final daysBValue = priorityB['days'];
          final daysB = daysBValue is int ? daysBValue : 
                       (daysBValue is String ? int.tryParse(daysBValue) ?? 0 : 
                       (daysBValue is double ? daysBValue.toInt() : 0));
          
          return daysA.compareTo(daysB);
        case 'Oldest First':
          final dateA = DateTime.tryParse(a['startDate'] ?? '') ?? DateTime.now();
          final dateB = DateTime.tryParse(b['startDate'] ?? '') ?? DateTime.now();
          return dateA.compareTo(dateB);
        case 'Newest First':
          final dateA = DateTime.tryParse(a['startDate'] ?? '') ?? DateTime.now();
          final dateB = DateTime.tryParse(b['startDate'] ?? '') ?? DateTime.now();
          return dateB.compareTo(dateA);
        case 'Customer A-Z':
          final nameA = (a['customerName'] ?? '').toString().toLowerCase();
          final nameB = (b['customerName'] ?? '').toString().toLowerCase();
          return nameA.compareTo(nameB);
        default:
          return 0;
      }
    });

    setState(() {
      _filteredRosters = tempResults;
    });
    
    // debugPrint('✅ _applyFilters: Final result - ${initialCount} → ${_filteredRosters.length} rosters');
    
    // Log sample of filtered results for debugging
    if (_filteredRosters.isNotEmpty) {
      // debugPrint('📋 Sample filtered rosters:');
      for (int i = 0; i < (_filteredRosters.length > 3 ? 3 : _filteredRosters.length); i++) {
        final roster = _filteredRosters[i];
        final email = _safeStringExtract(roster['customerEmail']) != '' ? 
                     _safeStringExtract(roster['customerEmail']) : 
                     (_safeNestedAccess(roster, 'employeeDetails', 'email') != '' ?
                     _safeNestedAccess(roster, 'employeeDetails', 'email') : 'No email');
        final name = _safeStringExtract(roster['customerName']) != '' ? 
                    _safeStringExtract(roster['customerName']) : 
                    (_safeNestedAccess(roster, 'employeeDetails', 'name') != '' ?
                    _safeNestedAccess(roster, 'employeeDetails', 'name') : 'No name');
        // debugPrint('  ${i + 1}. $name ($email)');
      }
    }
  }

  bool _hasActiveFilters() {
    return _searchQuery.isNotEmpty || 
           _selectedRosterType != 'All' || 
           _selectedOrganization != 'All Organizations' ||
           _selectedPriority != 'All' ||
           _filterCountry != null ||
           _filterState != null ||
           _filterCity != null ||
           _filterLocalArea != null;
  }

  void _clearAllFilters() {
    setState(() {
      _searchQuery = '';
      _selectedRosterType = 'All';
      _selectedOrganization = 'All Organizations';
      _selectedPriority = 'All';
      _selectedSortOrder = 'Priority First';
      _filterCountry = null;
      _filterState = null;
      _filterCity = null;
      _filterLocalArea = null;
      _localCtrl.clear();
      _applyFilters();
    });
  }
  
  // ==========================================
  // BULK SELECTION
  // ==========================================

  void _toggleSelectAll() {
    // debugPrint('☑️ _toggleSelectAll: Current selection: ${_selectedRosterIds.length}/${_filteredRosters.length}');
    
    setState(() {
      if (_selectedRosterIds.length == _filteredRosters.length) {
        // debugPrint('☑️ Deselecting all rosters');
        _selectedRosterIds.clear();
      } else {
        // debugPrint('☑️ Selecting all ${_filteredRosters.length} rosters');
        _selectedRosterIds = _filteredRosters
          .map((r) => (r['id'] ?? r['_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();
      }
    });
    
    // debugPrint('✅ _toggleSelectAll: New selection count: ${_selectedRosterIds.length}');
  }

  void _toggleRosterSelection(String rosterId) {
    // debugPrint('☑️ _toggleRosterSelection: Toggling roster $rosterId');
    
    setState(() {
      if (_selectedRosterIds.contains(rosterId)) {
        // debugPrint('☑️ Deselecting roster: $rosterId');
        _selectedRosterIds.remove(rosterId);
      } else {
        // debugPrint('☑️ Selecting roster: $rosterId');
        _selectedRosterIds.add(rosterId);
      }
    });
    
    // debugPrint('✅ _toggleRosterSelection: Total selected: ${_selectedRosterIds.length}');
  }

  // ==========================================
  // MAIN UI BUILDER
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Rosters'),
        backgroundColor: _themeColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
          tooltip: 'Back to Dashboard',
        ),
        actions: [
          // Export Button in AppBar
          IconButton(
            onPressed: _isExporting ? null : _exportToExcel,
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download),
            tooltip: 'Export to Excel',
          ),
          const SizedBox(width: 8),
        ],
      ),
      backgroundColor: _neutralBg,
      body: Stack(
        children: [
          // ✅ MAKE WHOLE PAGE SCROLLABLE with RefreshIndicator
          RefreshIndicator(
            onRefresh: () => _loadPendingRosters(forceRefresh: true),
            color: _themeColor,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(), // ✅ Ensures pull-to-refresh works even when content is short
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Stats Dashboard
                  _buildStatsDashboard(),

                  // Filter Bar (2 Rows: CSC + Others)
                  _buildInlineFilterBar(),

                  // Active Filter Chips
                  if (_hasActiveFilters()) 
                    _buildActiveFiltersRow(),

                  // Main List Content
                  _isLoading
                      ? _buildLoadingState()
                      : _errorMessage != null
                          ? _buildErrorState()
                          : _filteredRosters.isEmpty
                              ? _buildEmptyState()
                              : _buildRosterList(),
                ],
              ),
            ),
          ),

          // Loading Overlay for Optimization
          if (_isOptimizing)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: _themeColor),
                      const SizedBox(height: 16),
                      const Text(
                        'Optimizing Routes...',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Text(
                        'Finding best drivers nearby',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Floating Bulk Action Button
          if (_selectedRosterIds.isNotEmpty && !_isOptimizing)
            _buildBulkActionButton(),
        ],
      ),
    );
  }

  // ==========================================
  // WIDGETS: DASHBOARD & FILTERS
  // ==========================================

  Widget _buildStatsDashboard() {
    final total = _allPendingRosters.length;
    final loginCount = _allPendingRosters.where((r) => (r['rosterType'] ?? '').toString().toLowerCase() == 'login').length;
    final logoutCount = _allPendingRosters.where((r) => (r['rosterType'] ?? '').toString().toLowerCase() == 'logout').length;
    final bothCount = _allPendingRosters.where((r) => (r['rosterType'] ?? '').toString().toLowerCase() == 'both').length;
    
    // Priority counts
    final urgentCount = _allPendingRosters.where((r) {
      final priority = _calculatePriority(r);
      return priority['level'] == 'urgent' || priority['level'] == 'overdue';
    }).length;

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
                'Pending Roster Overview',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              Row(
                children: [
                  // Refresh Button
                  IconButton(
                    onPressed: () {
                      _loadPendingRosters(forceRefresh: true);
                    },
                    icon: Icon(Icons.refresh, color: _themeColor),
                    tooltip: 'Refresh',
                  ),
                  const SizedBox(width: 8),
                  // Export to Excel Button
                  ElevatedButton.icon(
                    onPressed: _isExporting ? null : _exportToExcel,
                    icon: _isExporting 
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.file_download, size: 18),
                    label: Text(_isExporting ? 'Exporting...' : 'Export Excel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF27AE60),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      elevation: 2,
                    ),
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
                  const SizedBox(width: 8),
                  // Smart Grouping Button (NEW)
                  ElevatedButton.icon(
                    onPressed: _showSmartGroupingDialog,
                    icon: const Icon(Icons.group_work, size: 18),
                    label: const Text('Smart Grouping'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      elevation: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Route Optimization Button (NEW)
                  ElevatedButton.icon(
                    onPressed: _showRouteOptimizationDialog,
                    icon: const Icon(Icons.route, size: 18),
                    label: const Text('Route Optimization'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      elevation: 2,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatCard('Total', '$total', Icons.folder_open, const Color(0xFF475569)),
              const SizedBox(width: 12),
              _buildStatCard('🔥 Urgent', '$urgentCount', Icons.warning, const Color(0xFFEF4444)),
              const SizedBox(width: 12),
              _buildStatCard('Login', '$loginCount', Icons.arrow_forward, _themeColor),
              const SizedBox(width: 12),
              _buildStatCard('Logout', '$logoutCount', Icons.arrow_back, const Color(0xFF3B82F6)),
              const SizedBox(width: 12),
              _buildStatCard('Both', '$bothCount', Icons.swap_horiz, const Color(0xFF8B5CF6)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineFilterBar() {
    if (!_showFilters) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: _cardBorder),
          bottom: BorderSide(color: _cardBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Organization, Type Chips, Priority Chips
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Organization Dropdown
              Expanded(
                flex: 2,
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
                                _applyFilters();
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

              // Roster Type Chips
              Expanded(
                flex: 3,
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
                              _applyFilters();
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

              // Priority Chips
              Expanded(
                flex: 3,
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
                      children: [
                        {'label': 'All', 'value': 'All', 'color': Color(0xFF64748B)},
                        {'label': 'Urgent', 'value': 'Urgent', 'color': Color(0xFFEF4444)},
                        {'label': 'High', 'value': 'High', 'color': Color(0xFFF59E0B)},
                        {'label': 'Normal', 'value': 'Normal', 'color': Color(0xFF10B981)},
                      ].map((priority) {
                        final isSelected = _selectedPriority == priority['value'];
                        return FilterChip(
                          label: Text(priority['label'] as String),
                          selected: isSelected,
                          onSelected: (val) {
                            setState(() {
                              _selectedPriority = priority['value'] as String;
                              _applyFilters();
                            });
                          },
                          selectedColor: priority['color'] as Color,
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
                              color: isSelected ? priority['color'] as Color : _cardBorder,
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

          // Row 2: Search, Date Range, Sort
          Row(
            children: [
              // Search Field
              Expanded(
                flex: 3,
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
                              _applyFilters();
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
                      _applyFilters();
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),

              // Date Range Picker
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2023),
                      lastDate: DateTime(2030),
                      initialDateRange: _selectedDateRange,
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: ColorScheme.light(primary: _themeColor),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedDateRange = picked;
                        _applyFilters();
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: _cardBorder),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month, size: 18, color: Color(0xFF64748B)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedDateRange == null
                                ? 'Date Range'
                                : '${DateFormat('MM/dd').format(_selectedDateRange!.start)} - ${DateFormat('MM/dd').format(_selectedDateRange!.end)}',
                            style: const TextStyle(fontSize: 14, color: Color(0xFF334155)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_selectedDateRange != null)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedDateRange = null;
                                _applyFilters();
                              });
                            },
                            child: const Icon(Icons.clear, size: 16, color: Color(0xFF64748B)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Sort Dropdown
              Expanded(
                flex: 2,
                child: Container(
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
                      items: ['Priority First', 'Newest First', 'Oldest First', 'Customer A-Z']
                        .map((String val) {
                          return DropdownMenuItem(value: val, child: Text(val));
                        }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedSortOrder = val;
                            _applyFilters();
                          });
                        }
                      },
                    ),
                  ),
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
              () => setState(() { _selectedOrganization = 'All Organizations'; _applyFilters(); })
            ),
          if (_searchQuery.isNotEmpty)
            _buildFilterChip(
              'Search: "$_searchQuery"', 
              () => setState(() { _searchQuery = ''; _applyFilters(); })
            ),
          if (_selectedRosterType != 'All')
            _buildFilterChip(
              'Type: $_selectedRosterType', 
              () => setState(() { _selectedRosterType = 'All'; _applyFilters(); })
            ),
          if (_selectedPriority != 'All')
            _buildFilterChip(
              'Priority: $_selectedPriority', 
              () => setState(() { _selectedPriority = 'All'; _applyFilters(); })
            ),
          if (_selectedDateRange != null)
            _buildFilterChip(
              'Date: ${DateFormat('MM/dd').format(_selectedDateRange!.start)} - ${DateFormat('MM/dd').format(_selectedDateRange!.end)}',
              () => setState(() { _selectedDateRange = null; _applyFilters(); })
            ),
            
          InkWell(
            onTap: _clearAllFilters,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: const Text(
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
  // ROSTER LIST & CARD
  // ==========================================

  Widget _buildRosterList() {
    return Column(
      children: [
        // Select All Header
        if (_filteredRosters.isNotEmpty)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Checkbox(
                  value: _selectedRosterIds.length == _filteredRosters.length && _filteredRosters.isNotEmpty,
                  onChanged: (val) => _toggleSelectAll(),
                  activeColor: _themeColor,
                ),
                Text(
                  _selectedRosterIds.isEmpty
                    ? 'Select All (${_filteredRosters.length})'
                    : '${_selectedRosterIds.length} selected',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
                const Spacer(),
                if (_selectedRosterIds.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() => _selectedRosterIds.clear()),
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Clear Selection'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                    ),
                  ),
              ],
            ),
          ),

        // ✅ FIX: Use shrinkWrap and physics instead of Expanded
        // This allows ListView to work inside SingleChildScrollView
        ListView.builder(
          shrinkWrap: true, // ✅ Makes ListView take only the space it needs
          physics: const NeverScrollableScrollPhysics(), // ✅ Disables ListView's own scrolling
          padding: const EdgeInsets.all(20),
          itemCount: _filteredRosters.length,
          itemBuilder: (context, index) {
            final roster = _filteredRosters[index];
            final rosterId = (roster['id'] ?? roster['_id'] ?? '').toString();
            final isSelected = _selectedRosterIds.contains(rosterId);
            return _buildRosterCard(roster, rosterId, isSelected);
          },
        ),
      ],
    );
  }

  Widget _buildRosterCard(Map<String, dynamic> roster, String rosterId, bool isSelected) {
    // debugPrint('🎨 _buildRosterCard: Building card for roster ID: $rosterId');
    
    // Extract data
    String employeeName = 'Unknown Employee';
    String employeeEmail = '';
    String companyName = 'Unknown Company';
    
    // debugPrint('🎨 Raw roster data: ${roster.keys.join(', ')}');
    
    if (roster['employeeDetails'] != null) {
      final details = roster['employeeDetails'];
      employeeName = details['name']?.toString() ?? employeeName;
      employeeEmail = details['email']?.toString() ?? employeeEmail;
      companyName = details['companyName']?.toString() ?? companyName;
      // debugPrint('🎨 From employeeDetails - Name: $employeeName, Email: $employeeEmail, Company: $companyName');
    }
    
    if (employeeName == 'Unknown Employee') {
      employeeName = roster['customerName']?.toString() ?? employeeName;
      // debugPrint('🎨 Using customerName: $employeeName');
    }
    if (employeeEmail.isEmpty) {
      employeeEmail = roster['customerEmail']?.toString() ?? employeeEmail;
      // debugPrint('🎨 Using customerEmail: $employeeEmail');
    }

    String company = 'Unknown Office';
    if (roster['officeLocation'] != null && roster['officeLocation'].toString().isNotEmpty) {
      company = roster['officeLocation'];
      // debugPrint('🎨 Using officeLocation: $company');
    } else if (roster['companyName'] != null) {
      company = roster['companyName'];
      // debugPrint('🎨 Using companyName: $company');
    }

    String subtitle = company;
    if (employeeEmail.isNotEmpty && !employeeName.contains('@')) {
      subtitle = '$company • $employeeEmail';
    }

    final rosterType = (roster['rosterType'] ?? 'both').toString();
    final priority = _calculatePriority(roster);
    
    // debugPrint('🎨 Final card data - Name: $employeeName, Email: $employeeEmail, Company: $company, Type: $rosterType');

    // Date & Time
    String dateDisplay = 'N/A';
    if (roster['startDate'] != null) {
      try {
        final start = DateTime.parse(roster['startDate'].toString());
        dateDisplay = DateFormat('MMM dd, yyyy').format(start);
      } catch (_) {}
    }

    final timeDisplay = '${roster['startTime'] ?? '00:00'} - ${roster['endTime'] ?? '00:00'}';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? _themeColor : _cardBorder,
          width: isSelected ? 2 : 1,
        ),
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
          onTap: () {
            if (_selectedRosterIds.isNotEmpty) {
              _toggleRosterSelection(rosterId);
            } else {
              // Show detailed roster information dialog
              _showRosterDetailsDialog(roster);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Checkbox
                    Checkbox(
                      value: isSelected,
                      onChanged: (val) => _toggleRosterSelection(rosterId),
                      activeColor: _themeColor,
                    ),
                    const SizedBox(width: 8),

                    // Priority Badge
                    // ... (Code continues below)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (priority['color'] as Color).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: priority['color'] as Color),
                      ),
                      child: Text(
                        priority['label'] as String,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: priority['color'] as Color,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Icon Box
                    Container(
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _getRosterTypeIcon(rosterType),
                        color: const Color(0xFF334155),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    
                    // Text Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            employeeName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
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
                                  subtitle,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w400,
                                  ),
                                  maxLines: 2,
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

                const SizedBox(height: 16),
                
                // Action Buttons Row (NEW: Auto Button)
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 16, color: const Color(0xFF94A3B8)),
                          const SizedBox(width: 8),
                          Text(
                            dateDisplay,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF334155)),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.access_time, size: 16, color: const Color(0xFF94A3B8)),
                          const SizedBox(width: 8),
                          Text(
                            timeDisplay,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF334155)),
                          ),
                        ],
                      ),
                    ),

                    // Smart Auto Assign Button (Mini)
                    SizedBox(
                      height: 36,
                      child: ElevatedButton.icon(
                        onPressed: () => _assignSingleCustomer(roster),
                        icon: const Icon(Icons.flash_on, size: 14),
                        label: const Text('Auto'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Manual Assign Button
                    SizedBox(
                      height: 36,
                      child: ElevatedButton.icon(
                        onPressed: () => _showAssignmentModal(roster),
                        icon: const Icon(Icons.person_add, size: 16),
                        label: const Text('Assign'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _themeColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
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

  Widget _buildInfoItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF334155),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  IconData _getRosterTypeIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('login')) return Icons.arrow_forward;
    if (t.contains('logout')) return Icons.arrow_back;
    if (t.contains('both')) return Icons.swap_horiz;
    return Icons.swap_horiz;
  }

  // ==========================================
  // BULK ACTION BUTTON
  // ==========================================

  Widget _buildBulkActionButton() {
    return Positioned(
      bottom: 24,
      right: 24,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        color: _themeColor,
        child: InkWell(
          onTap: _showBulkAssignmentModal,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Text(
                  'Assign Selected (${_selectedRosterIds.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // ASSIGNMENT MODALS & DIALOGS
  // ==========================================

  // Simulated API Call
  Future<void> _saveAssignments(List<Map<String, dynamic>> assignments) async {
    // debugPrint('💾 _saveAssignments: Saving ${assignments.length} assignments');
    
    try {
      setState(() => _isLoading = true);
      
      // Log assignment details
      for (int i = 0; i < assignments.length; i++) {
        final assignment = assignments[i];
        // debugPrint('💾 Assignment ${i + 1}: ${assignment['driverName']} → ${assignment['customerName']} (${assignment['rosterId']})');
      }
      
      // debugPrint('⏳ _saveAssignments: Simulating API call...');
      await Future.delayed(const Duration(seconds: 1)); // Simulating API
      
      setState(() {
        _isLoading = false;
        _selectedRosterIds.clear();
      });
      
      // debugPrint('✅ _saveAssignments: Assignments saved successfully');
      
      // In real app, re-fetch rosters here
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully assigned ${assignments.length} rosters!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // debugPrint('🔄 _saveAssignments: Reloading pending rosters...');
      _loadPendingRosters();
    } catch (e) {
      // debugPrint('❌ _saveAssignments: Error saving assignments: $e');
      setState(() => _isLoading = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save assignments: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ==========================================
  // ROSTER DETAILS DIALOG (NEW)
  // ==========================================

  void _showRosterDetailsDialog(Map<String, dynamic> roster) {
    // debugPrint('📋 _showRosterDetailsDialog: Opening details for roster');
    // debugPrint('📋 Full roster data: ${roster.toString()}');
    
    // Extract all employee/customer details
    final employeeDetails = roster['employeeDetails'] ?? roster['employeeData'] ?? {};
    final customerName = roster['customerName'] ?? employeeDetails['name'] ?? 'Unknown';
    final customerEmail = roster['customerEmail'] ?? roster['email'] ?? employeeDetails['email'] ?? 'N/A';
    
    // ✅ FIX: Enhanced phone number extraction
    String customerPhone = 'N/A';
    if (roster['customerPhone'] != null && roster['customerPhone'].toString().isNotEmpty) {
      customerPhone = roster['customerPhone'].toString();
    } else if (roster['phone'] != null && roster['phone'].toString().isNotEmpty) {
      customerPhone = roster['phone'].toString();
    } else if (roster['phoneNumber'] != null && roster['phoneNumber'].toString().isNotEmpty) {
      customerPhone = roster['phoneNumber'].toString();
    } else if (employeeDetails['phone'] != null && employeeDetails['phone'].toString().isNotEmpty) {
      customerPhone = employeeDetails['phone'].toString();
    } else if (employeeDetails['phoneNumber'] != null && employeeDetails['phoneNumber'].toString().isNotEmpty) {
      customerPhone = employeeDetails['phoneNumber'].toString();
    }
    
    // ✅ FIX: Enhanced employee details extraction
    String employeeId = 'N/A';
    if (roster['employeeId'] != null && roster['employeeId'].toString().isNotEmpty) {
      employeeId = roster['employeeId'].toString();
    } else if (employeeDetails['employeeId'] != null && employeeDetails['employeeId'].toString().isNotEmpty) {
      employeeId = employeeDetails['employeeId'].toString();
    } else if (employeeDetails['id'] != null && employeeDetails['id'].toString().isNotEmpty) {
      employeeId = employeeDetails['id'].toString();
    }
    
    String department = 'N/A';
    if (roster['department'] != null && roster['department'].toString().isNotEmpty) {
      department = roster['department'].toString();
    } else if (employeeDetails['department'] != null && employeeDetails['department'].toString().isNotEmpty) {
      department = employeeDetails['department'].toString();
    }
    
    String companyName = 'N/A';
    if (roster['companyName'] != null && roster['companyName'].toString().isNotEmpty) {
      companyName = roster['companyName'].toString();
    } else if (roster['organization'] != null && roster['organization'].toString().isNotEmpty) {
      companyName = roster['organization'].toString();
    } else if (roster['organizationName'] != null && roster['organizationName'].toString().isNotEmpty) {
      companyName = roster['organizationName'].toString();
    } else if (employeeDetails['companyName'] != null && employeeDetails['companyName'].toString().isNotEmpty) {
      companyName = employeeDetails['companyName'].toString();
    } else if (employeeDetails['organization'] != null && employeeDetails['organization'].toString().isNotEmpty) {
      companyName = employeeDetails['organization'].toString();
    } else {
      // Extract company from email domain
      final email = customerEmail.toLowerCase();
      if (email.contains('@') && email != 'n/a') {
        final domain = email.split('@')[1];
        if (domain == 'tcs.com') {
          companyName = 'Tata Consultancy Services';
        } else if (domain == 'infosys.com') {
          companyName = 'Infosys Limited';
        } else if (domain == 'wipro.com') {
          companyName = 'Wipro Limited';
        } else if (domain == 'hcl.com') {
          companyName = 'HCL Technologies';
        } else if (domain == 'techm.com') {
          companyName = 'Tech Mahindra';
        } else {
          companyName = domain.split('.')[0].toUpperCase();
        }
      }
    }
    
    String address = 'N/A';
    if (roster['address'] != null && roster['address'].toString().isNotEmpty) {
      address = roster['address'].toString();
    } else if (employeeDetails['address'] != null && employeeDetails['address'].toString().isNotEmpty) {
      address = employeeDetails['address'].toString();
    }
    
    final officeLocation = roster['officeLocation'] ?? 'N/A';
    
    // Roster details
    final rosterType = roster['rosterType'] ?? 'both';
    final startDate = roster['startDate'] != null 
        ? DateFormat('MMM dd, yyyy').format(DateTime.parse(roster['startDate'].toString()))
        : 'N/A';
    final endDate = roster['endDate'] != null 
        ? DateFormat('MMM dd, yyyy').format(DateTime.parse(roster['endDate'].toString()))
        : 'N/A';
    final startTime = roster['startTime'] ?? 'N/A';
    final endTime = roster['endTime'] ?? 'N/A';
    final status = roster['status'] ?? 'pending';
    
    // Weekdays
    final weekdays = roster['weekdays'] ?? roster['weeklyOffDays'] ?? [];
    final weekdaysStr = weekdays is List && weekdays.isNotEmpty 
        ? weekdays.join(', ') 
        : 'All days';
    
    // Locations - Check multiple possible field names and provide helpful fallbacks
    String pickupLocation = 'Not specified';
    String dropLocation = 'Not specified';
    
    // Check for pickup location
    if (roster['loginPickupAddress'] != null && roster['loginPickupAddress'].toString().isNotEmpty) {
      pickupLocation = roster['loginPickupAddress'].toString();
    } else if (_safeNestedAccess(roster, 'locations', 'pickup') != '' && 
               _safeNestedAccess(roster, 'locations', 'pickup') != '{}') {
      // Try to access nested location data safely
      try {
        final locations = roster['locations'];
        if (locations is Map && locations['pickup'] is Map) {
          final pickup = locations['pickup'] as Map;
          pickupLocation = _safeStringExtract(pickup['address']);
        }
      } catch (e) {
        // debugPrint('⚠️ Error accessing pickup location: $e');
      }
    } else if (roster['pickupLocation'] != null && roster['pickupLocation'].toString().isNotEmpty) {
      pickupLocation = roster['pickupLocation'].toString();
    } else if (roster['pickupAddress'] != null && roster['pickupAddress'].toString().isNotEmpty) {
      pickupLocation = roster['pickupAddress'].toString();
    } else {
      // Show helpful message based on roster type
      final type = rosterType.toLowerCase();
      if (type == 'login' || type == 'both') {
        pickupLocation = 'Pickup location not provided by employee';
      } else {
        pickupLocation = 'Not applicable for logout-only roster';
      }
    }
    
    // Check for drop location
    if (roster['logoutDropAddress'] != null && roster['logoutDropAddress'].toString().isNotEmpty) {
      dropLocation = roster['logoutDropAddress'].toString();
    } else if (_safeNestedAccess(roster, 'locations', 'drop') != '' && 
               _safeNestedAccess(roster, 'locations', 'drop') != '{}') {
      // Try to access nested location data safely
      try {
        final locations = roster['locations'];
        if (locations is Map && locations['drop'] is Map) {
          final drop = locations['drop'] as Map;
          dropLocation = _safeStringExtract(drop['address']);
        }
      } catch (e) {
        // debugPrint('⚠️ Error accessing drop location: $e');
      }
    } else if (roster['dropLocation'] != null && roster['dropLocation'].toString().isNotEmpty) {
      dropLocation = roster['dropLocation'].toString();
    } else if (roster['dropAddress'] != null && roster['dropAddress'].toString().isNotEmpty) {
      dropLocation = roster['dropAddress'].toString();
    } else {
      // Show helpful message based on roster type
      final type = rosterType.toLowerCase();
      if (type == 'logout' || type == 'both') {
        dropLocation = 'Drop location not provided by employee';
      } else {
        dropLocation = 'Not applicable for login-only roster';
      }
    }
    
    // debugPrint('📍 Pickup Location: $pickupLocation');
    // debugPrint('📍 Drop Location: $dropLocation');
    // debugPrint('📍 loginPickupAddress from roster: ${roster['loginPickupAddress']}');
    // debugPrint('📍 logoutDropAddress from roster: ${roster['logoutDropAddress']}');

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 600,
            constraints: const BoxConstraints(maxHeight: 700),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _themeColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.person_outline,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Employee Roster Details',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              customerName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
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
                        // Employee Information Section
                        _buildDetailSection(
                          'Employee Information',
                          Icons.person,
                          [
                            _buildDetailRow('Full Name', customerName),
                            _buildDetailRow('Email', customerEmail),
                            _buildDetailRow('Phone', customerPhone),
                            _buildDetailRow('Employee ID', employeeId),
                            _buildDetailRow('Department', department),
                            _buildDetailRow('Company', companyName),
                            _buildDetailRow('Address', address),
                          ],
                        ),

                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 24),

                        // Roster Schedule Section
                        _buildDetailSection(
                          'Roster Schedule',
                          Icons.calendar_today,
                          [
                            _buildDetailRow('Roster Type', _formatRosterType(rosterType)),
                            _buildDetailRow('Start Date', startDate),
                            _buildDetailRow('End Date', endDate),
                            _buildDetailRow('Working Days', weekdaysStr),
                            _buildDetailRow('Status', status.toUpperCase()),
                          ],
                        ),

                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 24),

                        // Timings Section
                        _buildDetailSection(
                          'Timings',
                          Icons.access_time,
                          [
                            _buildDetailRow('Login Time', startTime),
                            _buildDetailRow('Logout Time', endTime),
                          ],
                        ),

                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 24),

                        // Assignment Section
                        _buildDetailSection(
                          'Assignment',
                          Icons.assignment,
                          [
                            _buildDetailRow('Driver', roster['assignedDriverName']?.toString() ?? roster['driverName']?.toString() ?? 'Not assigned'),
                            if ((roster['driverPhone']?.toString() ?? '').isNotEmpty)
                              _buildDetailRow('Driver Phone', roster['driverPhone'].toString()),
                            _buildDetailRow('Vehicle', roster['assignedVehicleReg']?.toString() ?? roster['vehicleNumber']?.toString() ?? 'Not assigned'),
                          ],
                        ),

                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 24),

                        // Locations Section
                        _buildDetailSection(
                          'Locations',
                          Icons.location_on,
                          [
                            _buildDetailRow('Office Location', officeLocation),
                            _buildDetailRow('Pickup Location', pickupLocation),
                            _buildDetailRow('Drop Location', dropLocation),
                            if (pickupLocation.contains('not provided') || dropLocation.contains('not provided'))
                              Container(
                                margin: const EdgeInsets.only(top: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, size: 16, color: Colors.amber[700]),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Employee needs to provide pickup/drop locations when creating roster',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.amber[700],
                                          fontStyle: FontStyle.italic,
                                        ),
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
                ),

                // Footer Actions
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        child: const Text('Close'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showAssignmentModal(roster);
                        },
                        icon: const Icon(Icons.person_add, size: 18),
                        label: const Text('Assign Driver'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _themeColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
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

  Widget _buildDetailSection(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: _themeColor),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatRosterType(String type) {
    final t = type.toLowerCase();
    if (t == 'login') return 'Login Only';
    if (t == 'logout') return 'Logout Only';
    if (t == 'both') return 'Login & Logout';
    return type;
  }

  void _showAssignmentModal(Map<String, dynamic> roster) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Manual Assignment'),
          content: const Text('This will open the driver selection modal list.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Assign'),
            ),
          ],
        );
      },
    );
  }

  void _showBulkAssignmentModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Assign ${_selectedRosterIds.length} Rosters', 
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              
              // Smart Assign Option
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.amber,
                  child: Icon(Icons.flash_on, color: Colors.white),
                ),
                title: const Text('Smart Auto-Assign'),
                subtitle: const Text('Automatically find nearest drivers'),
                onTap: () {
                  Navigator.pop(context);
                  // Filter the selected rosters object from IDs
                  final selected = _filteredRosters
                      .where((r) => _selectedRosterIds.contains(r['id'] ?? r['_id']))
                      .toList();
                  _assignMultipleCustomers(selected);
                },
              ),
              const Divider(),
              // Manual Option
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                title: const Text('Assign Single Driver'),
                subtitle: const Text('Assign all selected to one driver'),
                onTap: () {
                   Navigator.pop(context);
                   // Logic for manual single assignment
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // HELPER STATES
  // ==========================================

  Widget _buildLoadingState() {
    return Center(
      child: CircularProgressIndicator(color: _themeColor),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.inbox_outlined, size: 48, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 16),
          const Text(
            'No rosters found',
            style: TextStyle(
              fontSize: 18, 
              fontWeight: FontWeight.bold, 
              color: Color(0xFF1E293B)
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try adjusting your filters or check back later.',
            style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _clearAllFilters,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Clear Filters'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF334155),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadPendingRosters,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }


  /// Batch optimize multiple rosters
  Future<List<Map<String, dynamic>>> _batchOptimizeRosters(
    List<Map<String, dynamic>> rosters,
  ) async {
    // debugPrint('🔄 Batch optimizing ${rosters.length} rosters...');
    
    try {
      // Group rosters by location/organization for better optimization
      final groupedRosters = <String, List<Map<String, dynamic>>>{};
      
      for (var roster in rosters) {
        final key = roster['officeLocation'] ?? roster['organization'] ?? 'default';
        groupedRosters.putIfAbsent(key, () => []).add(roster);
      }
      
      final assignments = <Map<String, dynamic>>[];
      
      // Process each group
      for (var entry in groupedRosters.entries) {
        final groupRosters = entry.value;
        // debugPrint('📍 Processing group "${entry.key}" with ${groupRosters.length} rosters');
        
        // Find optimal customer cluster
        final optimalCustomers = RouteOptimizationService.findOptimalCustomerCluster(
          groupRosters,
          groupRosters.length,
        );
        
        // Load COMPATIBLE vehicles (filtered by email domain, timing, capacity)
        final rosterIds = optimalCustomers.map((c) => c['_id'] as String).toList();
        final vehiclesResponse = await widget.rosterService.getCompatibleVehicles(rosterIds);
        
        if (vehiclesResponse['success'] == true) {
          final vehicles = List<Map<String, dynamic>>.from(vehiclesResponse['data']?['compatible'] ?? []);
          
          // Find best vehicle for this group
          final bestVehicle = RouteOptimizationService.findBestVehicle(
            optimalCustomers,
            vehicles,
          );
          
          if (bestVehicle != null) {
            assignments.add({
              'vehicle': bestVehicle,
              'customers': optimalCustomers,
              'group': entry.key,
            });
          }
        }
      }
      
      // debugPrint('✅ Batch optimization completed: ${assignments.length} assignments');
      return assignments;
    } catch (e) {
      // debugPrint('❌ Batch optimization failed: $e');
      rethrow;
    }
  }
}
