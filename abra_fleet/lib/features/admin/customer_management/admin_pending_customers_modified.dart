import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/core/utils/export_helper.dart';
import 'package:country_state_city/country_state_city.dart' as csc;

// ============================================================================
// MODIFIED PENDING CUSTOMERS SCREEN
// ============================================================================
// Features:
// 1. Row 1: Country, State, City, Local Area filters (from CSC filter)
// 2. Row 2: Date Range, Search, Status filters + Export button
// 3. Color scheme from client_all_trips.dart
// 4. Fully scrollable page
// 5. Export functionality like invoice_list_page.dart
// ============================================================================

class AdminPendingCustomersModifiedPage extends StatefulWidget {
  const AdminPendingCustomersModifiedPage({Key? key}) : super(key: key);

  @override
  State<AdminPendingCustomersModifiedPage> createState() => _AdminPendingCustomersModifiedPageState();
}

class _AdminPendingCustomersModifiedPageState extends State<AdminPendingCustomersModifiedPage> {
  bool _isLoading = false;
  bool _isExporting = false;
  
  static String get _backendUrl => ApiConfig.baseUrl;
  
  List<Map<String, dynamic>> _allPendingCustomers = [];
  List<Map<String, dynamic>> _filteredCustomers = [];

  // ── Row 1: CSC Filters ────────────────────────────────────────────────────
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _filterCountry;
  String? _filterState;
  String? _filterCity;
  String? _filterLocalArea;

  // ── Row 2: Other Filters ──────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatus = 'All';
  final List<String> _statusOptions = ['All', 'Pending', 'Approved', 'Rejected'];


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

  // ── Colors from client_all_trips.dart ──────────────────────────────────────
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
    _fetchCountries();
    // Load customers after a brief delay to ensure widget is mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPendingCustomers();
    });
  }

  @override
  void dispose() {
    _closeAllOverlays();
    _searchController.dispose();
    _localCtrl.dispose();
    _scCountry.dispose();
    _scState.dispose();
    _scCity.dispose();
    super.dispose();
  }


  // ============================================================================
  // DATA LOADING
  // ============================================================================

  Future<void> _loadPendingCustomers() async {
    setState(() => _isLoading = true);
    try {
      debugPrint('🔄 Loading pending customers...');
      final response = await ApiService().get('/api/customers', queryParams: {
        'isPendingApproval': 'true',
      });
      final customers = List<Map<String, dynamic>>.from(response['customers'] ?? response['data'] ?? []);
      debugPrint('✅ Loaded ${customers.length} pending customers');
      setState(() {
        _allPendingCustomers = customers;
        _applyFilters();
        debugPrint('✅ After filtering: ${_filteredCustomers.length} customers');
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading pending customers: $e');
      setState(() => _isLoading = false);
      _showErrorSnackBar('Failed to load customers: $e');
    }
  }

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
  // FILTER LOGIC
  // ============================================================================

  void _applyFilters() {
    debugPrint('🔍 Applying filters...');
    debugPrint('   Total customers: ${_allPendingCustomers.length}');
    debugPrint('   Search query: "$_searchQuery"');
    debugPrint('   Status filter: $_selectedStatus');
    debugPrint('   Country: $_filterCountry, State: $_filterState, City: $_filterCity');
    
    setState(() {
      _filteredCustomers = _allPendingCustomers.where((customer) {
        // Search filter
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          final matchesName = (customer['name']?.toString().toLowerCase().contains(q) ?? false);
          final matchesEmail = (customer['email']?.toString().toLowerCase().contains(q) ?? false);
          final matchesPhone = (customer['phoneNumber']?.toString().toLowerCase().contains(q) ?? false);
          final matchesCompany = (customer['companyName']?.toString().toLowerCase().contains(q) ?? false);
          if (!matchesName && !matchesEmail && !matchesPhone && !matchesCompany) return false;
        }

        // Status filter
        if (_selectedStatus != 'All') {
          final status = customer['status']?.toString() ?? 'Pending';
          if (status.toLowerCase() != _selectedStatus.toLowerCase()) return false;
        }

        // Date range filter
        if (_fromDate != null || _toDate != null) {
          final created = _parseDate(customer['registrationDate'] ?? customer['createdAt']);
          if (created != null) {
            if (_fromDate != null && created.isBefore(_fromDate!)) return false;
            if (_toDate != null && created.isAfter(_toDate!.add(const Duration(days: 1)))) return false;
          }
        }

        // Country filter
        if (_filterCountry != null && _filterCountry!.isNotEmpty) {
          if (customer['country']?.toString() != _filterCountry) return false;
        }

        // State filter
        if (_filterState != null && _filterState!.isNotEmpty) {
          if (customer['state']?.toString() != _filterState) return false;
        }

        // City filter
        if (_filterCity != null && _filterCity!.isNotEmpty) {
          final customerCity = customer['city']?.toString() ?? '';
          if (!customerCity.toLowerCase().contains(_filterCity!.toLowerCase())) return false;
        }

        // Local area filter
        if (_filterLocalArea != null && _filterLocalArea!.isNotEmpty) {
          final customerArea = customer['area']?.toString() ?? '';
          if (!customerArea.toLowerCase().contains(_filterLocalArea!.toLowerCase())) return false;
        }

        return true;
      }).toList();
      
      debugPrint('✅ Filtered customers: ${_filteredCustomers.length}');
    });
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


  // ============================================================================
  // EXPORT TO EXCEL
  // ============================================================================

  Future<void> _exportToExcel() async {
    if (_filteredCustomers.isEmpty) {
      _showErrorSnackBar('No customers to export');
      return;
    }

    setState(() => _isExporting = true);
    _showSuccessSnackBar('Preparing Excel export...');

    try {
      List<List<dynamic>> csvData = [
        [
          'Name', 'Email', 'Phone', 'Company', 'Department', 
          'Employee ID', 'Role', 'Status', 'Country', 'State', 
          'City', 'Area', 'Registration Date',
        ],
      ];

      for (final customer in _filteredCustomers) {
        csvData.add([
          customer['name'] ?? '',
          customer['email'] ?? '',
          customer['phoneNumber'] ?? customer['phone'] ?? '',
          customer['companyName'] ?? customer['company'] ?? '',
          customer['department'] ?? '',
          customer['employeeId'] ?? '',
          (customer['role'] ?? 'customer').toUpperCase(),
          customer['status'] ?? 'Pending',
          customer['country'] ?? '',
          customer['state'] ?? '',
          customer['city'] ?? '',
          customer['area'] ?? '',
          _formatExportDate(customer['registrationDate'] ?? customer['createdAt']),
        ]);
      }

      await ExportHelper.exportToExcel(
        data: csvData,
        filename: 'pending_customers_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
      );

      _showSuccessSnackBar('✅ Excel exported with ${_filteredCustomers.length} customers!');
    } catch (e) {
      _showErrorSnackBar('Export failed: $e');
    } finally {
      setState(() => _isExporting = false);
    }
  }

  String _formatExportDate(dynamic d) {
    if (d == null) return '';
    try {
      return DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(d.toString()).toLocal());
    } catch (_) {
      return d.toString();
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
  // ACTIONS (Approve/Reject)
  // ============================================================================

  Future<String?> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

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
        await ApiService().put('/api/customers/$customerId', body: {
          'status': 'Active',
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
          debugPrint('Email notification error: $emailError');
        }

        if (mounted) {
          _showSuccessSnackBar('${customer['name']} has been approved successfully!');
          _loadPendingCustomers();
        }
      } catch (e) {
        if (mounted) {
          _showErrorSnackBar('Failed to approve customer: $e');
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
        final rejectionReason = reasonController.text.trim();
        
        await ApiService().put('/api/customers/$customerId', body: {
          'status': 'Rejected',
          'isPendingApproval': false,
          'rejectionReason': rejectionReason,
          'rejectedAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        });

        // Send rejection email
        try {
          final token = await _getAuthToken();
          if (token != null) {
            await http.post(
              Uri.parse('$_backendUrl/api/customer-approval/reject'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({
                'customerId': customerId,
                'customerEmail': customer['email'],
                'customerName': customer['name'],
                'reason': rejectionReason,
              }),
            );
          }
        } catch (emailError) {
          debugPrint('Email notification error: $emailError');
        }

        if (mounted) {
          _showErrorSnackBar('${customer['name']} has been rejected.');
          _loadPendingCustomers();
        }
      } catch (e) {
        if (mounted) {
          _showErrorSnackBar('Failed to reject customer: $e');
        }
      }
    }

    reasonController.dispose();
  }


  // ============================================================================
  // UI HELPERS
  // ============================================================================

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ]),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ]),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      DateTime date;
      if (timestamp is String) {
        date = DateTime.parse(timestamp);
      } else if (timestamp is int) {
        date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else if (timestamp is DateTime) {
        date = timestamp;
      } else {
        return 'N/A';
      }
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      debugPrint('Error formatting date: $e');
      return 'N/A';
    }
  }

  BoxDecoration _boxDec({required bool active, bool disabled = false}) =>
      BoxDecoration(
        color: disabled ? _kDisabledBg : active ? _kActiveBg : _kBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: disabled ? _kBorder : active ? _kPrimary : _kBorder,
          width: active && !disabled ? 1.5 : 1.0,
        ),
      );

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_fromDate ?? now) : (_toDate ?? _fromDate ?? now),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _kPrimary),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
        if (_toDate != null && _fromDate!.isAfter(_toDate!)) _toDate = null;
      } else {
        _toDate = picked;
      }
    });
    _applyFilters();
  }

  void _clearAllFilters() {
    _closeAllOverlays();
    setState(() {
      _fromDate = null;
      _toDate = null;
      _filterCountry = null;
      _countryIso = null;
      _filterState = null;
      _stateIso = null;
      _filterCity = null;
      _states = [];
      _cities = [];
      _localCtrl.clear();
      _filterLocalArea = null;
      _searchController.clear();
      _searchQuery = '';
      _selectedStatus = 'All';
    });
    _applyFilters();
  }

  bool get _hasFilters =>
      _fromDate != null ||
      _toDate != null ||
      (_filterCountry?.isNotEmpty ?? false) ||
      (_filterState?.isNotEmpty ?? false) ||
      (_filterCity?.isNotEmpty ?? false) ||
      _localCtrl.text.trim().isNotEmpty ||
      _searchQuery.isNotEmpty ||
      _selectedStatus != 'All';


  // ============================================================================
  // BUILD METHOD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _kPrimary,
        title: const Text(
          'Pending Customer Approvals',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0.3),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPendingCustomers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoCard(),
                  const SizedBox(height: 24),
                  _buildRow1CSCFilters(),
                  const SizedBox(height: 16),
                  _buildRow2OtherFilters(),
                  const SizedBox(height: 24),
                  _buildPendingApprovalsTable(),
                ],
              ),
            ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(_kPrimary)),
        SizedBox(height: 20),
        Text('Loading pending customers...',
            style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.info_outline, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              'These customers have registered and are waiting for admin approval to access the system.',
              style: TextStyle(fontSize: 14, color: Color(0xFF1E293B), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }


  // ============================================================================
  // ROW 1: CSC FILTERS (Country, State, City, Local Area)
  // ============================================================================

  Widget _buildRow1CSCFilters() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Icon(Icons.location_on, size: 18, color: _kPrimary),
            const SizedBox(width: 8),
            const Text('Location Filters',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _kText)),
            if (_hasFilters) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _clearAllFilters,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close, size: 12, color: Color(0xFFF87171)),
                      SizedBox(width: 4),
                      Text('Clear All',
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFF87171),
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              _fieldWrap(
                label: 'Country',
                width: 170,
                child: CompositedTransformTarget(
                  link: _lkCountry,
                  child: GestureDetector(
                    onTap: () {
                      if (_ovCountry != null) {
                        _closeAllOverlays();
                        setState(() {});
                      } else {
                        _openCountry();
                      }
                    },
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: _boxDec(active: _filterCountry != null || _ovCountry != null),
                      child: _dropRow(
                        value: _filterCountry ?? 'All Countries',
                        hasValue: _filterCountry != null,
                        isOpen: _ovCountry != null,
                        isLoading: _loadingCountries,
                        onClear: _filterCountry != null
                            ? () {
                                setState(() {
                                  _filterCountry = null;
                                  _countryIso = null;
                                  _filterState = null;
                                  _stateIso = null;
                                  _filterCity = null;
                                  _states = [];
                                  _cities = [];
                                });
                                _applyFilters();
                              }
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              _fieldWrap(
                label: 'State',
                width: 170,
                child: CompositedTransformTarget(
                  link: _lkState,
                  child: GestureDetector(
                    onTap: _filterCountry == null
                        ? null
                        : () {
                            if (_ovState != null) {
                              _closeAllOverlays();
                              setState(() {});
                            } else {
                              _openState();
                            }
                          },
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: _boxDec(
                        active: _filterState != null || _ovState != null,
                        disabled: _filterCountry == null,
                      ),
                      child: _dropRow(
                        value: _filterState ??
                            (_filterCountry == null ? 'Select Country first' : 'All States'),
                        hasValue: _filterState != null,
                        isOpen: _ovState != null,
                        isLoading: _loadingStates,
                        isDisabled: _filterCountry == null,
                        onClear: _filterState != null
                            ? () {
                                setState(() {
                                  _filterState = null;
                                  _stateIso = null;
                                  _filterCity = null;
                                  _cities = [];
                                });
                                _applyFilters();
                              }
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              _fieldWrap(
                label: 'City',
                width: 170,
                child: CompositedTransformTarget(
                  link: _lkCity,
                  child: GestureDetector(
                    onTap: _filterState == null
                        ? null
                        : () {
                            if (_ovCity != null) {
                              _closeAllOverlays();
                              setState(() {});
                            } else {
                              _openCity();
                            }
                          },
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: _boxDec(
                        active: _filterCity != null || _ovCity != null,
                        disabled: _filterState == null,
                      ),
                      child: _dropRow(
                        value: _filterCity ??
                            (_filterState == null ? 'Select State first' : 'All Cities'),
                        hasValue: _filterCity != null,
                        isOpen: _ovCity != null,
                        isLoading: _loadingCities,
                        isDisabled: _filterState == null,
                        onClear: _filterCity != null
                            ? () {
                                setState(() => _filterCity = null);
                                _applyFilters();
                              }
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              _fieldWrap(
                label: 'Local Area / Landmark',
                width: 190,
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _localCtrl,
                    onChanged: (v) {
                      setState(() => _filterLocalArea = v.trim().isEmpty ? null : v.trim());
                      _applyFilters();
                    },
                    style: const TextStyle(fontSize: 14, color: _kText),
                    decoration: InputDecoration(
                      hintText: 'Enter area...',
                      hintStyle: const TextStyle(fontSize: 14, color: _kHint),
                      prefixIcon: const Icon(Icons.pin_drop_outlined, size: 16, color: _kHint),
                      suffixIcon: _localCtrl.text.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                setState(() {
                                  _localCtrl.clear();
                                  _filterLocalArea = null;
                                });
                                _applyFilters();
                              },
                              child: const Icon(Icons.close, size: 15, color: _kHint),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
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
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fieldWrap({required String label, required double width, required Widget child}) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kText)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _dropRow({
    required String value,
    required bool hasValue,
    required bool isOpen,
    required bool isLoading,
    bool isDisabled = false,
    VoidCallback? onClear,
  }) {
    return Row(children: [
      Icon(Icons.arrow_drop_down,
          size: 18, color: isDisabled ? _kHint : hasValue ? _kPrimary : _kHint),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          value,
          style: TextStyle(
            fontSize: 14,
            color: isDisabled ? _kHint : hasValue ? _kText : _kHint,
            fontWeight: hasValue ? FontWeight.w500 : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (isLoading)
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary),
        )
      else if (hasValue && onClear != null)
        GestureDetector(
          onTap: onClear,
          child: const Icon(Icons.close, size: 15, color: _kHint),
        ),
    ]);
  }


  // ============================================================================
  // ROW 2: OTHER FILTERS (Date Range, Search, Status) + EXPORT BUTTON
  // ============================================================================

  Widget _buildRow2OtherFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(children: [
        // Date Range: From Date
        _fieldWrap(
          label: 'From Date',
          width: 145,
          child: GestureDetector(
            onTap: () => _pickDate(true),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: _boxDec(active: _fromDate != null),
              child: Row(children: [
                Icon(Icons.calendar_today_outlined,
                    size: 15, color: _fromDate != null ? _kPrimary : _kHint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _fromDate != null ? _fmt(_fromDate!) : 'Select',
                    style: TextStyle(
                      fontSize: 14,
                      color: _fromDate != null ? _kText : _kHint,
                      fontWeight: _fromDate != null ? FontWeight.w500 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_fromDate != null)
                  GestureDetector(
                    onTap: () {
                      setState(() => _fromDate = null);
                      _applyFilters();
                    },
                    child: const Icon(Icons.close, size: 15, color: _kHint),
                  ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Date Range: To Date
        _fieldWrap(
          label: 'To Date',
          width: 145,
          child: GestureDetector(
            onTap: () => _pickDate(false),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: _boxDec(active: _toDate != null),
              child: Row(children: [
                Icon(Icons.event_outlined, size: 15, color: _toDate != null ? _kPrimary : _kHint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _toDate != null ? _fmt(_toDate!) : 'Select',
                    style: TextStyle(
                      fontSize: 14,
                      color: _toDate != null ? _kText : _kHint,
                      fontWeight: _toDate != null ? FontWeight.w500 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_toDate != null)
                  GestureDetector(
                    onTap: () {
                      setState(() => _toDate = null);
                      _applyFilters();
                    },
                    child: const Icon(Icons.close, size: 15, color: _kHint),
                  ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Search Bar
        SizedBox(
          width: 220,
          height: 42,
          child: TextField(
            controller: _searchController,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search customers…',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 15),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                        _applyFilters();
                      })
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            onChanged: (v) {
              setState(() => _searchQuery = v.toLowerCase());
              _applyFilters();
            },
          ),
        ),
        const SizedBox(width: 12),
        // Status Filter Chips
        Expanded(
          child: SizedBox(
            height: 42,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _statusOptions.length,
              itemBuilder: (context, index) {
                final status = _statusOptions[index];
                final isSelected = _selectedStatus == status;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(status,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: isSelected ? Colors.white : const Color(0xFF424242))),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedStatus = status;
                        _applyFilters();
                      });
                    },
                    selectedColor: _kPrimary,
                    backgroundColor: Colors.grey.shade100,
                    checkmarkColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected ? _kPrimary : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Export Excel Button
        ElevatedButton.icon(
          onPressed: _isLoading || _isExporting ? null : _exportToExcel,
          icon: _isExporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.file_download, size: 18),
          label: Text(_isExporting ? 'Exporting...' : 'Export Excel',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF27AE60),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ]),
    );
  }


  // ============================================================================
  // TABLE
  // ============================================================================

  Widget _buildPendingApprovalsTable() {
    return Container(
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
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'Pending Customer Approvals',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_filteredCustomers.length}',
                        style: const TextStyle(
                          color: Color(0xFFF59E0B),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Table Content
          if (_filteredCustomers.isEmpty)
            _buildEmptyState()
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 24,
                horizontalMargin: 24,
                headingRowColor: MaterialStateProperty.all(const Color(0xFFF8FAFC)),
                columns: const [
                  DataColumn(
                    label: Text('NAME',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  ),
                  DataColumn(
                    label: Text('EMAIL',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  ),
                  DataColumn(
                    label: Text('PHONE',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  ),
                  DataColumn(
                    label: Text('COMPANY',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  ),
                  DataColumn(
                    label: Text('DEPARTMENT',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  ),
                  DataColumn(
                    label: Text('EMPLOYEE ID',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  ),
                  DataColumn(
                    label: Text('ROLE',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  ),
                  DataColumn(
                    label: Text('REGISTRATION DATE',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  ),
                  DataColumn(
                    label: Text('ACTIONS',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  ),
                ],
                rows: _filteredCustomers.map<DataRow>((customer) {
                  final customerId = customer['_id'] ?? customer['id'] ?? '';

                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          customer['name'] ?? 'N/A',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      DataCell(
                        Text(
                          customer['email'] ?? 'N/A',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      DataCell(Text(customer['phoneNumber'] ?? cus