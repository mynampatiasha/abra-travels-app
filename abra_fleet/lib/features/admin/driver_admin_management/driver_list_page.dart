// lib/features/admin/driver_admin_management/driver_list_page.dart
// COMPLETE FILE WITH ALL FIXES - PART 1 of 3

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/gestures.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/core/services/driver_service.dart';
import 'package:abra_fleet/core/services/vehicle_service.dart';
import 'package:abra_fleet/features/admin/widgets/country_state_city_filter.dart';
import 'package:abra_fleet/features/admin/driver_admin_management/driver_admin_management_dialogs.dart';
import 'package:abra_fleet/features/admin/driver_admin_management/csv_import_dialog.dart'; // ✅ NEW: For Export/Import dialogs
import 'package:abra_fleet/features/admin/driver_admin_management/driver_details_page.dart'; // ✅ NEW: For driver details page
import 'package:abra_fleet/core/utils/export_helper.dart'; // ✅ NEW: For Excel export
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:country_picker/country_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import 'package:csv/csv.dart'; // ✅ NEW: For CSV export
import 'package:abra_fleet/core/utils/file_helper.dart'; // ✅ NEW: For File operations

class DriverListPage extends StatefulWidget {
  final AuthRepository authRepository;
  final DriverService driverService;
  final VehicleService vehicleService;
  final String? initialDocumentFilter;
  final bool isEmbedded;

  const DriverListPage({
    Key? key,
    required this.authRepository,
    required this.driverService,
    required this.vehicleService,
    this.initialDocumentFilter,
    this.isEmbedded = false,
  }) : super(key: key);

  @override
  State<DriverListPage> createState() => _DriverListPageState();
}

class _DriverListPageState extends State<DriverListPage> with SingleTickerProviderStateMixin {
  // 🎨 COLOR SCHEME
  static const Color primaryColor = Color(0xFF1B7FA8);
  static const Color darkPrimaryColor = Color(0xFF0D5A7A);
  static const Color accentColor = Color(0xFF2D3E50);
  static const Color lightBackgroundColor = Color(0xFFF5F9FA);
  static const Color cardBackgroundColor = Colors.white;
  static const Color borderColor = Color(0xFFE0E0E0);
  static const Color textPrimaryColor = Color(0xFF2D3E50);
  static const Color textSecondaryColor = Color(0xFF6B7280);
  
  // 📊 STATE VARIABLES
  List<Map<String, dynamic>> _drivers = [];
  List<Map<String, dynamic>> _allDrivers = [];
  List<Map<String, dynamic>> _vehicles = [];
  bool _isLoading = false;
  String _selectedStatus = 'active'; // Default to active drivers only
  String _searchQuery = '';
  String _selectedVehicleFilter = '';
  String _selectedDocumentFilter = '';
  final TextEditingController _searchController = TextEditingController();
  
  Map<String, dynamic> _activeFilters = {};
  int _totalDrivers = 0;

  // ✅ ADVANCED FILTERS STATE
  bool _showAdvancedFilters = false;
  late AnimationController _filterAnimationController;
  late Animation<double> _filterAnimation;
  
  DateTime? _selectedDate;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedCountry;
  String? _selectedState;
  String? _selectedCity;

  // ✅ Horizontal scroll controller
  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    
    // ✅ Initialize filter animation
    _filterAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _filterAnimation = CurvedAnimation(
      parent: _filterAnimationController,
      curve: Curves.easeInOut,
    );
    
    if (widget.initialDocumentFilter != null) {
      _selectedDocumentFilter = widget.initialDocumentFilter!;
    }
    _fetchDrivers();
    _fetchVehicles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _filterAnimationController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  // 🔄 FETCH DRIVERS FROM BACKEND
  Future<void> _fetchDrivers() async {
    print('[DriverListPage] 🔄 Starting _fetchDrivers...');
    
    setState(() => _isLoading = true);

    try {
      final response = await widget.driverService.getDrivers(
        status: _selectedStatus.isNotEmpty ? _selectedStatus : null,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        limit: 1000,
      );

      if (response['success'] == true) {
        List<Map<String, dynamic>> driversList = [];
        final data = response['data'];
        
        if (data is List) {
          driversList = List<Map<String, dynamic>>.from(data);
        } else if (data is Map) {
          if (data['drivers'] is List) {
            driversList = List<Map<String, dynamic>>.from(data['drivers']);
          } else if (data['items'] is List) {
            driversList = List<Map<String, dynamic>>.from(data['items']);
          } else {
            driversList = [Map<String, dynamic>.from(data)];
          }
        }
        
        print('[DriverListPage] ✅ Parsed ${driversList.length} drivers');
        print('[DriverListPage] 📊 First driver feedback: ${driversList.isNotEmpty ? driversList[0]['feedbackStats'] : 'none'}');
        
        setState(() {
          _allDrivers = driversList;
          _drivers = _applyLocalFilters(driversList);
          _totalDrivers = driversList.length;
        });
      } else {
        throw Exception(response['message'] ?? 'Failed to fetch drivers');
      }
    } catch (e) {
      print('[DriverListPage] ❌ Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load drivers: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 🚗 FETCH VEHICLES FROM BACKEND
  Future<void> _fetchVehicles() async {
    try {
      final response = await widget.vehicleService.getVehicles(limit: 100);
      
      if (response['success'] == true) {
        List<Map<String, dynamic>> vehiclesList = [];
        final data = response['data'];
        
        if (data is List) {
          vehiclesList = List<Map<String, dynamic>>.from(data);
        } else if (data is Map) {
          if (data['vehicles'] is List) {
            vehiclesList = List<Map<String, dynamic>>.from(data['vehicles']);
          } else if (data['items'] is List) {
            vehiclesList = List<Map<String, dynamic>>.from(data['items']);
          }
        }
        
        setState(() {
          _vehicles = vehiclesList;
        });
      }
    } catch (e) {
      print('[DriverListPage] Error fetching vehicles: $e');
    }
  }

  // 🔍 HELPER: Get value from nested object safely
  String _getNestedValue(Map<String, dynamic> obj, String path, [String defaultValue = 'N/A']) {
    try {
      final parts = path.split('.');
      dynamic value = obj;
      
      for (final part in parts) {
        if (value is Map) {
          value = value[part];
        } else {
          return defaultValue;
        }
      }
      
      return value?.toString() ?? defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  // 🔍 FILTER DRIVERS
  List<Map<String, dynamic>> get _filteredDrivers {
    List<Map<String, dynamic>> filtered = List.from(_drivers);

    if (_selectedVehicleFilter == 'assigned') {
      filtered = filtered.where((d) => d['assignedVehicle'] != null || (d['vehicleNumber'] != null && d['vehicleNumber'] != 'N/A')).toList();
    } else if (_selectedVehicleFilter == 'unassigned') {
      filtered = filtered.where((d) => d['assignedVehicle'] == null && (d['vehicleNumber'] == null || d['vehicleNumber'] == 'N/A')).toList();
    }

    if (_selectedDocumentFilter.isNotEmpty) {
      if (_selectedDocumentFilter == 'expired') {
        filtered = filtered.where((d) => _hasExpiredDocuments(d)).toList();
      } else if (_selectedDocumentFilter == 'expiring_soon') {
        filtered = filtered.where((d) => _hasExpiringSoonDocuments(d)).toList();
      } else if (_selectedDocumentFilter == 'all_valid') {
        filtered = filtered.where((d) => !_hasExpiredDocuments(d) && !_hasExpiringSoonDocuments(d) && _hasDocuments(d)).toList();
      } else if (_selectedDocumentFilter == 'no_documents') {
        filtered = filtered.where((d) => !_hasDocuments(d)).toList();
      }
    }

    return filtered;
  }

  bool _hasDocuments(Map<String, dynamic> driver) {
    final documentsData = driver['documents'];
    if (documentsData == null) return false;
    
    List<Map<String, dynamic>> documents = [];
    if (documentsData is List) {
      documents = documentsData.map((doc) {
        if (doc is Map<String, dynamic>) return doc;
        if (doc is Map) return Map<String, dynamic>.from(doc);
        return <String, dynamic>{};
      }).toList();
    }
    
    return documents.isNotEmpty;
  }

  bool _hasExpiredDocuments(Map<String, dynamic> driver) {
    final documentsData = driver['documents'];
    if (documentsData == null) return false;
    
    List<Map<String, dynamic>> documents = [];
    if (documentsData is List) {
      documents = documentsData.map((doc) {
        if (doc is Map<String, dynamic>) return doc;
        if (doc is Map) return Map<String, dynamic>.from(doc);
        return <String, dynamic>{};
      }).toList();
    }
    
    final now = DateTime.now();
    return documents.any((doc) {
      final expiryDate = doc['expiryDate'];
      if (expiryDate != null) {
        try {
          return DateTime.parse(expiryDate).isBefore(now);
        } catch (e) {
          return false;
        }
      }
      return false;
    });
  }

  bool _hasExpiringSoonDocuments(Map<String, dynamic> driver) {
    final documentsData = driver['documents'];
    if (documentsData == null) return false;
    
    List<Map<String, dynamic>> documents = [];
    if (documentsData is List) {
      documents = documentsData.map((doc) {
        if (doc is Map<String, dynamic>) return doc;
        if (doc is Map) return Map<String, dynamic>.from(doc);
        return <String, dynamic>{};
      }).toList();
    }
    
    final now = DateTime.now();
    final thirtyDaysFromNow = now.add(const Duration(days: 30));
    
    return documents.any((doc) {
      final expiryDate = doc['expiryDate'];
      if (expiryDate != null) {
        try {
          final expiry = DateTime.parse(expiryDate);
          return expiry.isAfter(now) && expiry.isBefore(thirtyDaysFromNow);
        } catch (e) {
          return false;
        }
      }
      return false;
    });
  }

  void _clearFilters() {
    setState(() {
      _selectedStatus = '';
      _selectedVehicleFilter = '';
      _selectedDocumentFilter = '';
      _searchQuery = '';
      _searchController.clear();
      _selectedDate = null;
      _startDate = null;
      _endDate = null;
      _selectedCountry = null;
      _selectedState = null;
      _selectedCity = null;
      _activeFilters = {};
    });
    _fetchDrivers();
  }

  // 🎯 APPLY LOCAL FILTERS
  List<Map<String, dynamic>> _applyLocalFilters(List<Map<String, dynamic>> drivers) {
    if (_activeFilters.isEmpty) return drivers;
    
    return drivers.where((driver) {
      if (_activeFilters.containsKey('startDate') && _activeFilters.containsKey('endDate')) {
        final startDate = _activeFilters['startDate'] as DateTime;
        final endDate = _activeFilters['endDate'] as DateTime;
        final driverDate = driver['createdAt'] != null 
            ? DateTime.parse(driver['createdAt'].toString())
            : null;
        if (driverDate == null || 
            driverDate.isBefore(startDate) || 
            driverDate.isAfter(endDate)) {
          return false;
        }
      }
      
      if (_activeFilters.containsKey('state')) {
        final state = _activeFilters['state'] as String;
        final driverState = _getNestedValue(driver, 'address.state', '');
        if (driverState.toLowerCase() != state.toLowerCase()) {
          return false;
        }
      }
      
      if (_activeFilters.containsKey('city')) {
        final city = _activeFilters['city'] as String;
        final driverCity = _getNestedValue(driver, 'address.city', '');
        if (!driverCity.toLowerCase().contains(city.toLowerCase())) {
          return false;
        }
      }
      
      if (_activeFilters.containsKey('country')) {
        final country = _activeFilters['country'] as String;
        final driverCountry = _getNestedValue(driver, 'address.country', '');
        if (driverCountry.toLowerCase() != country.toLowerCase()) {
          return false;
        }
      }
      
      return true;
    }).toList();
  }

  void _handleFilterApplied(Map<String, dynamic> filters) {
    setState(() {
      _activeFilters = filters;
      _drivers = _applyLocalFilters(_allDrivers);
    });
  }

  void _handleFilterCleared() {
    setState(() {
      _activeFilters = {};
      _drivers = List.from(_allDrivers);
    });
  }

  // ✅ TOGGLE ADVANCED FILTERS
  void _toggleAdvancedFilters() {
    setState(() {
      _showAdvancedFilters = !_showAdvancedFilters;
      if (_showAdvancedFilters) {
        _filterAnimationController.forward();
      } else {
        _filterAnimationController.reverse();
      }
    });
  }

  // ✅ NEW: SHOW ADD DRIVER DIALOG
  Future<void> _showAddDriverDialog() async {
    final result = await showDialog(
      context: context,
      builder: (context) => AddDriverDialog(driverService: widget.driverService),
    );
    
    if (result == true) {
      _fetchDrivers();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Driver added successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ✅ NEW: SHOW BULK IMPORT DIALOG
  Future<void> _showBulkImportDialog() async {
    await showDialog(
      context: context,
      builder: (context) => CsvImportDialog(
        driverService: widget.driverService,
        onImportComplete: () {
          // Refresh driver list after successful import
          _fetchDrivers();
        },
      ),
    );
  }

  // ✅ NEW: EXPORT TO EXCEL
  Future<void> _exportToExcel() async {
    try {
      if (_filteredDrivers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No drivers to export'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preparing Excel export...'),
          backgroundColor: Colors.blue,
        ),
      );

      // Prepare data for export
      List<List<dynamic>> csvData = [
        // Headers
        [
          'Driver ID',
          'Name',
          'Email',
          'Phone',
          'Status',
          'License Number',
          'License Expiry',
          'Assigned Vehicle',
          'Vehicle Number',
          'Address',
          'City',
          'State',
          'Country',
          'Pincode',
          'Date of Birth',
          'Joining Date',
          'Emergency Contact',
          'Blood Group',
          'Total Feedback',
          'Average Rating',
        ],
      ];

      print('📊 Exporting ${_filteredDrivers.length} drivers...');

      // Add data rows
      for (var driver in _filteredDrivers) {
        final documents = (driver['documents'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        final licenseDoc = documents.firstWhere(
          (doc) => doc['type']?.toString().toLowerCase() == 'license',
          orElse: () => <String, dynamic>{},
        );

        final feedbackStats = driver['feedbackStats'] as Map<String, dynamic>?;
        final totalFeedback = feedbackStats?['totalFeedback'] ?? 0;
        final averageRating = feedbackStats?['averageRating'] ?? 0.0;

        csvData.add([
          driver['driverId'] ?? 'N/A',
          driver['name'] ?? 'N/A',
          driver['email'] ?? 'N/A',
          driver['phoneNumber'] ?? 'N/A',
          driver['status'] ?? 'N/A',
          licenseDoc['documentNumber'] ?? 'N/A',
          licenseDoc['expiryDate'] != null 
              ? DateFormat('dd/MM/yyyy').format(DateTime.parse(licenseDoc['expiryDate']))
              : 'N/A',
          driver['assignedVehicle']?['registrationNumber'] ?? 'N/A',
          driver['vehicleNumber'] ?? 'N/A',
          _getNestedValue(driver, 'address.street', 'N/A'),
          _getNestedValue(driver, 'address.city', 'N/A'),
          _getNestedValue(driver, 'address.state', 'N/A'),
          _getNestedValue(driver, 'address.country', 'N/A'),
          _getNestedValue(driver, 'address.pincode', 'N/A'),
          driver['dateOfBirth'] != null 
              ? DateFormat('dd/MM/yyyy').format(DateTime.parse(driver['dateOfBirth']))
              : 'N/A',
          driver['joiningDate'] != null 
              ? DateFormat('dd/MM/yyyy').format(DateTime.parse(driver['joiningDate']))
              : 'N/A',
          driver['emergencyContact'] ?? 'N/A',
          driver['bloodGroup'] ?? 'N/A',
          totalFeedback.toString(),
          averageRating.toStringAsFixed(2),
        ]);
      }

      // Use ExportHelper to export
      await ExportHelper.exportToExcel(
        data: csvData,
        filename: 'drivers_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Excel file downloaded with ${_filteredDrivers.length} drivers!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Export Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ✅ APPLY ADVANCED FILTERS
  void _applyAdvancedFilters() {
    final filters = <String, dynamic>{};

    if (_selectedDate != null) filters['date'] = _selectedDate;
    if (_startDate != null) filters['startDate'] = _startDate;
    if (_endDate != null) filters['endDate'] = _endDate;
    if (_selectedCountry != null && _selectedCountry!.isNotEmpty) {
      filters['country'] = _selectedCountry;
    }
    if (_selectedState != null && _selectedState!.isNotEmpty) {
      filters['state'] = _selectedState;
    }
    if (_selectedCity != null && _selectedCity!.isNotEmpty) {
      filters['city'] = _selectedCity;
    }

    _handleFilterApplied(filters);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text('Advanced filters applied: ${filters.length} active'),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ✅ DATE PICKER
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: primaryColor,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  // ✅ DATE RANGE PICKER
  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: primaryColor,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedDate != null) count++;
    if (_startDate != null && _endDate != null) count++;
    if (_selectedCountry != null && _selectedCountry!.isNotEmpty) count++;
    if (_selectedState != null && _selectedState!.isNotEmpty) count++;
    if (_selectedCity != null && _selectedCity!.isNotEmpty) count++;
    return count;
  }

  // PART 2 CONTINUES WITH VEHICLE ASSIGNMENT AND DIALOGS...
  // PART 2 of 3: VEHICLE ASSIGNMENT + DRIVER DETAILS + EDIT/DELETE

  // 🚗 GET AVAILABLE VEHICLES
  List<Map<String, dynamic>> _getAvailableVehicles(String? currentDriverId) {
    final assignedVehicleIds = _drivers
        .where((driver) => 
            driver['assignedVehicle'] != null && 
            driver['driverId'] != currentDriverId)
        .map((driver) => driver['assignedVehicle']?['vehicleId'] ?? driver['assignedVehicle']?['_id'])
        .where((id) => id != null)
        .toSet();

    final available = _vehicles.where((vehicle) {
      final vehicleId = vehicle['vehicleId'] ?? vehicle['_id'];
      final status = vehicle['status']?.toString().toUpperCase() ?? '';
      
      final isNotAssigned = !assignedVehicleIds.contains(vehicleId);
      final isActive = status == 'ACTIVE';
      
      return isNotAssigned && isActive;
    }).toList();

    return available;
  }

  // 🚗 SHOW VEHICLE ASSIGNMENT DIALOG
  Future<void> _showVehicleAssignmentDialog(Map<String, dynamic> driver) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: primaryColor)),
    );

    await _fetchVehicles();
    
    if (!mounted) return;
    Navigator.pop(context);

    final currentVehicle = driver['assignedVehicle'];
    final currentVehicleId = currentVehicle?['_id'] ?? currentVehicle?['vehicleId'];
    final availableVehicles = _getAvailableVehicles(driver['driverId']);

    if (currentVehicle != null && !availableVehicles.any((v) => 
        (v['_id'] ?? v['vehicleId']) == currentVehicleId)) {
      availableVehicles.insert(0, currentVehicle);
    }

    String? selectedVehicleId = currentVehicleId;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.directions_car, color: primaryColor, size: 24),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Assign Vehicle', style: TextStyle(fontSize: 18, color: textPrimaryColor)),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Driver: ${driver['name'] ?? 'N/A'}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textPrimaryColor),
                ),
                const SizedBox(height: 8),
                Text(
                  'Driver ID: ${driver['driverId'] ?? 'N/A'}',
                  style: const TextStyle(color: textSecondaryColor, fontSize: 14),
                ),
                const SizedBox(height: 24),
                if (availableVehicles.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No available vehicles. All active vehicles are assigned.',
                            style: TextStyle(color: Colors.orange.shade900),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Select Vehicle:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: textPrimaryColor)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedVehicleId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: lightBackgroundColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: borderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: primaryColor, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        ),
                        hint: const Text('Select a vehicle'),
                        items: [
                          const DropdownMenuItem<String>(value: 'UNASSIGN', child: Text('Unassign Vehicle')),
                          ...availableVehicles.map((vehicle) {
                            final vehicleId = vehicle['_id'] ?? vehicle['vehicleId'];
                            final isCurrentVehicle = vehicleId == currentVehicleId;
                            
                            return DropdownMenuItem<String>(
                              value: vehicleId,
                              child: Row(
                                children: [
                                  if (isCurrentVehicle)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: primaryColor.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('CURRENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: primaryColor)),
                                    ),
                                  if (isCurrentVehicle) const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${vehicle['registrationNumber']} - ${vehicle['make']} ${vehicle['model']}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            selectedVehicleId = value;
                          });
                        },
                      ),
                      if (selectedVehicleId != null && selectedVehicleId != 'UNASSIGN') ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: primaryColor.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Vehicle Details:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textPrimaryColor)),
                              const SizedBox(height: 8),
                              ...availableVehicles
                                  .where((v) => (v['_id'] ?? v['vehicleId']) == selectedVehicleId)
                                  .map((vehicle) {
                                        int? seatCapacity;
                                        try {
                                          if (vehicle['seatCapacity'] != null) {
                                            seatCapacity = int.tryParse(vehicle['seatCapacity'].toString());
                                          } else if (vehicle['seatingCapacity'] != null) {
                                            seatCapacity = int.tryParse(vehicle['seatingCapacity'].toString());
                                          } else if (vehicle['capacity'] != null) {
                                            final capacity = vehicle['capacity'];
                                            if (capacity is Map && capacity['passengers'] != null) {
                                              seatCapacity = int.tryParse(capacity['passengers'].toString());
                                            } else if (capacity is num) {
                                              seatCapacity = capacity.toInt();
                                            } else {
                                              seatCapacity = int.tryParse(capacity.toString());
                                            }
                                          }
                                        } catch (e) {
                                          seatCapacity = null;
                                        }
                                        
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            _buildDetailText('Type', vehicle['type']?.toString() ?? 'N/A'),
                                            _buildDetailText('Year', vehicle['year']?.toString() ?? 'N/A'),
                                            _buildDetailText('Capacity', seatCapacity != null ? '$seatCapacity seats' : 'N/A'),
                                          ],
                                        );
                                      })
                                  .toList(),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: textSecondaryColor)),
            ),
            ElevatedButton(
              onPressed: availableVehicles.isEmpty ? null : () => Navigator.pop(context, selectedVehicleId),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await _assignVehicleToDriver(driver['driverId'], result);
    }
  }

  Widget _buildDetailText(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontSize: 12, color: textSecondaryColor)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimaryColor)),
        ],
      ),
    );
  }

  // 🚗 ASSIGN VEHICLE TO DRIVER
  Future<void> _assignVehicleToDriver(String driverId, String? vehicleId) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator(color: primaryColor)),
      );

      Map<String, dynamic> response;
      
      if (vehicleId == 'UNASSIGN' || vehicleId == null) {
        response = await widget.driverService.unassignVehicle(driverId);
      } else {
        response = await widget.driverService.assignVehicle(driverId, vehicleId);
      }

      if (!mounted) return;
      Navigator.pop(context);

      if (response['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              vehicleId == 'UNASSIGN' || vehicleId == null
                  ? 'Vehicle unassigned successfully'
                  : 'Vehicle assigned successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
        
        await Future.wait([_fetchDrivers(), _fetchVehicles()]);
      } else {
        throw Exception(response['message'] ?? 'Failed to assign vehicle');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 👁️ NAVIGATE TO DRIVER DETAILS PAGE
  Future<void> _showDriverDetails(Map<String, dynamic> driver) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DriverDetailsPage(
          driver: driver,
        ),
      ),
    );
    
    // Check if user wants to edit the driver
    if (result != null && result is Map && result['action'] == 'edit') {
      await _showEditDriverDialog(result['driver']);
    }
    
    // Refresh driver list when returning
    await _fetchDrivers();
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textPrimaryColor)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label + ':', style: const TextStyle(fontWeight: FontWeight.w600, color: textSecondaryColor)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14, color: textPrimaryColor)),
          ),
        ],
      ),
    );
  }

  // CONTINUES TO PART 3...
  // PART 3 of 3: EDIT/DELETE + DOCUMENTS + UI BUILDERS + BUILD METHOD

  // ✏️ SHOW EDIT DRIVER DIALOG
  Future<void> _showEditDriverDialog(Map<String, dynamic> driver) async {
    final nameController = TextEditingController(
      text: driver['name'] ?? _getNestedValue(driver, 'personalInfo.name', '')
    );
    final emailController = TextEditingController(
      text: driver['email'] ?? _getNestedValue(driver, 'personalInfo.email', '')
    );
    final phoneController = TextEditingController(
      text: driver['phone'] ?? _getNestedValue(driver, 'personalInfo.phone', '')
    );
    
    final validStatuses = ['active', 'on_leave', 'inactive'];
    String driverStatus = driver['status']?.toString().toLowerCase() ?? 'active';
    String selectedStatus = validStatuses.contains(driverStatus) ? driverStatus : 'active';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.edit, color: primaryColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Edit Driver', style: TextStyle(color: textPrimaryColor)),
                    Text(
                      'Driver ID: ${driver['driverId'] ?? 'N/A'}',
                      style: const TextStyle(fontSize: 12, color: textSecondaryColor, fontWeight: FontWeight.normal),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Name *',
                      labelStyle: const TextStyle(color: textSecondaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: primaryColor, width: 2),
                      ),
                      prefixIcon: const Icon(Icons.person, color: primaryColor),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    decoration: InputDecoration(
                      labelText: 'Email *',
                      labelStyle: const TextStyle(color: textSecondaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: primaryColor, width: 2),
                      ),
                      prefixIcon: const Icon(Icons.email, color: primaryColor),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: phoneController,
                    decoration: InputDecoration(
                      labelText: 'Phone *',
                      labelStyle: const TextStyle(color: textSecondaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: primaryColor, width: 2),
                      ),
                      prefixIcon: const Icon(Icons.phone, color: primaryColor),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    decoration: InputDecoration(
                      labelText: 'Status *',
                      labelStyle: const TextStyle(color: textSecondaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: primaryColor, width: 2),
                      ),
                      prefixIcon: const Icon(Icons.info, color: primaryColor),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(value: 'on_leave', child: Text('On Leave')),
                      DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        selectedStatus = value ?? 'active';
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: textSecondaryColor)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty || 
                    emailController.text.isEmpty || 
                    phoneController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill all required fields'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                
                Navigator.pop(context, true);
                
                await _updateDriver(
                  driver['driverId'],
                  {
                    'name': nameController.text,
                    'email': emailController.text,
                    'phone': phoneController.text,
                    'status': selectedStatus,
                  },
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
  }

  // 💾 UPDATE DRIVER
  Future<void> _updateDriver(String driverId, Map<String, dynamic> updateData) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator(color: primaryColor)),
      );

      final response = await widget.driverService.updateDriver(
        driverId,
        {
          'personalInfo': {
            'name': updateData['name'],
            'email': updateData['email'],
            'phone': updateData['phone'],
          },
          'status': updateData['status'],
        },
      );

      if (!mounted) return;
      Navigator.pop(context);

      if (response != null && response['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Driver updated successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        await _fetchDrivers();
      } else {
        throw Exception(response?['message'] ?? 'Failed to update driver');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // 🗑️ DELETE DRIVER
  Future<void> _deleteDriver(String? driverId, String driverName) async {
    if (driverId == null || driverId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Driver ID is missing. Cannot delete driver.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red, size: 24),
            SizedBox(width: 12),
            Text('Delete Driver'),
          ],
        ),
        content: Text('Are you sure you want to delete driver "$driverName"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: textSecondaryColor)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator(color: primaryColor)),
      );

      final response = await widget.driverService.deleteDriver(driverId);

      if (!mounted) return;
      Navigator.pop(context);

      if (response == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Driver deleted successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        await _fetchDrivers();
      } else {
        throw Exception('Failed to delete driver');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // 📧 SEND PASSWORD RESET EMAIL
  Future<void> _sendPasswordResetEmail(Map<String, dynamic> driver) async {
    final email = driver['email'] ?? _getNestedValue(driver, 'personalInfo.email', '');
    final name = driver['name'] ?? _getNestedValue(driver, 'personalInfo.name', 'Unknown');
    
    if (email == null || email.isEmpty || email == 'N/A') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Driver does not have an email address'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.email, color: primaryColor, size: 24),
            SizedBox(width: 12),
            Text('Send Password Reset Email'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Send password reset email to:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: primaryColor.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textPrimaryColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: const TextStyle(color: textSecondaryColor, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'The driver will receive an email with a link to reset their password.',
              style: TextStyle(color: textSecondaryColor, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: textSecondaryColor)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Send Email'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: primaryColor),
              SizedBox(height: 16),
              Text(
                'Sending password reset email...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );

      final response = await widget.driverService.sendPasswordResetEmail(driver['driverId']);

      Navigator.pop(context);

      if (response == true) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 28),
                SizedBox(width: 12),
                Expanded(child: Text('Email Sent!')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Password reset email sent to:',
                  style: TextStyle(color: textSecondaryColor, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textPrimaryColor),
                ),
                const SizedBox(height: 8),
                Text(
                  'Driver: $name',
                  style: const TextStyle(color: textSecondaryColor, fontSize: 14),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        throw Exception('Failed to send email');
      }
    } catch (e) {
      Navigator.pop(context);
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 28),
              SizedBox(width: 12),
              Text('Error'),
            ],
          ),
          content: Text('Failed to send password reset email: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  // 📄 SHOW ADD DOCUMENT DIALOG
  Future<void> _showAddDocumentDialog(String driverId) async {
    final documentNameController = TextEditingController();
    DateTime? selectedExpiryDate;
    String? selectedDocumentType;
    dynamic selectedFile; // Changed from File? for web compatibility
    Uint8List? selectedFileBytes;
    String? selectedFileName;

    final documentTypes = ['License', 'Medical Certificate', 'Background Check', 'Training Certificate', 'ID Proof', 'Other'];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Driver Document', style: TextStyle(color: textPrimaryColor)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedDocumentType,
                  decoration: InputDecoration(
                    labelText: 'Document Type *',
                    labelStyle: const TextStyle(color: textSecondaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: primaryColor, width: 2),
                    ),
                  ),
                  items: documentTypes.map((type) {
                    return DropdownMenuItem(value: type, child: Text(type));
                  }).toList(),
                  onChanged: (value) {
                    setState(() => selectedDocumentType = value);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: documentNameController,
                  decoration: InputDecoration(
                    labelText: 'Document Name *',
                    labelStyle: const TextStyle(color: textSecondaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'e.g., DL-2024-12345',
                  ),
                ),
                const SizedBox(height: 16),
                
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: borderColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.upload_file, color: primaryColor.withOpacity(0.8)),
                          const SizedBox(width: 8),
                          const Text('Upload Document File', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (selectedFileName != null)
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: Text(selectedFileName!, overflow: TextOverflow.ellipsis)),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  setState(() {
                                    selectedFile = null;
                                    selectedFileBytes = null;
                                    selectedFileName = null;
                                  });
                                },
                              ),
                            ],
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: () async {
                            try {
                              FilePickerResult? result = await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
                                withData: true,
                              );

                              if (result != null) {
                                final pickedFile = result.files.single;
                                setState(() {
                                  selectedFileName = pickedFile.name;
                                  if (kIsWeb) {
                                    selectedFileBytes = pickedFile.bytes;
                                  } else {
                                    // For mobile/desktop, store path instead of File object
                                    if (pickedFile.path != null) {
                                      selectedFile = pickedFile.path;
                                    }
                                  }
                                });
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error picking file: $e')),
                              );
                            }
                          },
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: const Text('Choose File'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Expiry Date (Optional)'),
                  subtitle: Text(
                    selectedExpiryDate != null
                        ? selectedExpiryDate.toString().split(' ')[0]
                        : 'No expiry date set',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today, color: primaryColor),
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(const Duration(days: 365)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (date != null) {
                        setState(() => selectedExpiryDate = date);
                      }
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
                if (selectedDocumentType == null || documentNameController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all required fields')),
                  );
                  return;
                }

                Navigator.pop(context);
                await _addDocumentWithFile(
                  driverId,
                  selectedDocumentType!,
                  documentNameController.text,
                  selectedExpiryDate,
                  selectedFile,
                  selectedFileBytes,
                  selectedFileName,
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              child: const Text('Add Document'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addDocumentWithFile(
    String driverId,
    String documentType,
    String documentName,
    DateTime? expiryDate,
    dynamic file, // Changed from File? to dynamic for web compatibility
    Uint8List? fileBytes,
    String? fileName,
  ) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: primaryColor),
        ),
      );

      final response = await widget.driverService.uploadDriverDocument(
        driverId: driverId,
        file: file,
        bytes: fileBytes,
        fileName: fileName ?? 'document.pdf',
        documentType: documentType,
        documentName: documentName,
        expiryDate: expiryDate,
      );

      Navigator.pop(context);

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document uploaded successfully'), backgroundColor: Colors.green),
        );
        _fetchDrivers();
      } else {
        throw Exception(response['message'] ?? 'Failed to upload document');
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildDocumentTile(Map<String, dynamic> doc, String driverId) {
    final expiryDate = doc['expiryDate'] != null ? DateTime.parse(doc['expiryDate']) : null;
    final isExpired = expiryDate != null && expiryDate.isBefore(DateTime.now());
    final isExpiringSoon = expiryDate != null && 
        expiryDate.isAfter(DateTime.now()) && 
        expiryDate.isBefore(DateTime.now().add(const Duration(days: 30)));
    
    Color statusColor = Colors.green;
    String statusText = 'Valid';
    
    if (isExpired) {
      statusColor = Colors.red;
      statusText = 'Expired';
    } else if (isExpiringSoon) {
      statusColor = Colors.orange;
      statusText = 'Expiring Soon';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: statusColor.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
        color: statusColor.withOpacity(0.05),
      ),
      child: Row(
        children: [
          Icon(Icons.description, color: statusColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doc['documentName'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Type: ${doc['documentType'] ?? 'N/A'}', style: const TextStyle(fontSize: 12)),
                if (expiryDate != null)
                  Text('Expires: ${expiryDate.toString().split(' ')[0]}', 
                    style: TextStyle(color: statusColor, fontSize: 12)),
              ],
            ),
          ),
          Chip(
            label: Text(statusText, style: TextStyle(color: statusColor, fontSize: 11)),
            backgroundColor: statusColor.withOpacity(0.1),
          ),
        ],
      ),
    );
  }

  // 🎨 UI HELPER WIDGETS
  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;

    switch (status.toLowerCase()) {
      case 'active':
        bgColor = Colors.green.shade100;
        textColor = Colors.green.shade800;
        break;
      case 'on_leave':
        bgColor = Colors.orange.shade100;
        textColor = Colors.orange.shade800;
        break;
      case 'inactive':
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade800;
        break;
      default:
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade800;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildDocumentStatusIndicator(Map<String, dynamic> driver) {
    final documentsData = driver['documents'];
    if (documentsData == null) {
      return Tooltip(
        message: 'No documents uploaded',
        child: Icon(Icons.info_outline, color: Colors.grey.shade600, size: 16),
      );
    }
    
    List<Map<String, dynamic>> documents = [];
    if (documentsData is List) {
      documents = documentsData.map((doc) {
        if (doc is Map<String, dynamic>) return doc;
        if (doc is Map) return Map<String, dynamic>.from(doc);
        return <String, dynamic>{};
      }).toList();
    }
    
    if (documents.isEmpty) {
      return Tooltip(
        message: 'No documents uploaded',
        child: Icon(Icons.info_outline, color: Colors.grey.shade600, size: 16),
      );
    }

    final now = DateTime.now();
    bool hasExpiredDocuments = false;
    bool hasExpiringSoonDocuments = false;

    for (final doc in documents) {
      final expiryDate = doc['expiryDate'];
      if (expiryDate != null) {
        try {
          final expiry = DateTime.parse(expiryDate);
          if (expiry.isBefore(now)) {
            hasExpiredDocuments = true;
          } else if (expiry.isBefore(now.add(const Duration(days: 30)))) {
            hasExpiringSoonDocuments = true;
          }
        } catch (e) {}
      }
    }

    Widget icon;
    String message;
    
    if (hasExpiredDocuments) {
      icon = Icon(Icons.error, color: Colors.red.shade700, size: 16);
      message = 'Has expired documents';
    } else if (hasExpiringSoonDocuments) {
      icon = Icon(Icons.warning, color: Colors.orange.shade700, size: 16);
      message = 'Documents expiring soon';
    } else {
      icon = Icon(Icons.check_circle, color: Colors.green.shade700, size: 16);
      message = 'All documents valid';
    }

    return Tooltip(message: message, child: icon);
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

  // ============================================================================
  // EXPORT/IMPORT METHODS
  // ============================================================================
  
  Future<void> _exportDriversToCSV() async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: primaryColor),
        ),
      );

      // Prepare CSV data
      String csvData = 'Driver ID,Name,Email,Phone,Status,License Number,License Expiry,Vehicle,Country,State,City\n';
      
      for (var driver in _filteredDrivers) {
        csvData += '${driver['driverId'] ?? ''},';
        csvData += '${driver['name'] ?? ''},';
        csvData += '${driver['email'] ?? ''},';
        csvData += '${driver['phoneNumber'] ?? ''},';
        csvData += '${driver['status'] ?? ''},';
        csvData += '${driver['licenseNumber'] ?? ''},';
        csvData += '${driver['licenseExpiry'] ?? ''},';
        csvData += '${driver['assignedVehicle'] ?? 'Not Assigned'},';
        // ❌ REMOVED: Trips and Rating columns from CSV export
        csvData += '${driver['country'] ?? ''},';
        csvData += '${driver['state'] ?? ''},';
        csvData += '${driver['city'] ?? ''}\n';
      }

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      // Download CSV
      if (kIsWeb) {
        // Web download
        final bytes = utf8.encode(csvData);
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download = 'drivers_export_${DateTime.now().millisecondsSinceEpoch}.csv';
        html.document.body?.children.add(anchor);
        anchor.click();
        html.document.body?.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
      } else {
        // Mobile/Desktop download - File operations not available on web
        // This code path won't execute on web due to kIsWeb check above
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File export is only supported on web platform'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully exported ${_filteredDrivers.length} drivers'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting drivers: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _importDriversFromCSV() async {
    try {
      // Pick CSV file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null) return;

      // Show loading dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(color: primaryColor),
          ),
        );
      }

      // Read file content
      String csvContent;
      if (kIsWeb) {
        final bytes = result.files.first.bytes!;
        csvContent = utf8.decode(bytes);
      } else {
        // For mobile/desktop - File operations not available on web
        // This code path won't execute on web due to kIsWeb check above
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File import is only supported on web platform'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Parse CSV
      final lines = csvContent.split('\n');
      if (lines.length < 2) {
        throw Exception('CSV file is empty or invalid');
      }

      // Skip header row
      int successCount = 0;
      int errorCount = 0;

      for (int i = 1; i < lines.length; i++) {
        if (lines[i].trim().isEmpty) continue;
        
        final fields = lines[i].split(',');
        if (fields.length < 5) continue;

        try {
          // Generate a unique driver ID
          final driverId = 'DRV${DateTime.now().millisecondsSinceEpoch}${i}';
          
          // Structure driver data according to createDriver method signature
          final personalInfo = {
            'name': fields[1].trim(),
            'email': fields[2].trim(),
            'phoneNumber': fields[3].trim(),
          };
          
          final license = {
            'licenseNumber': fields.length > 5 ? fields[5].trim() : '',
            'licenseExpiry': fields.length > 6 ? fields[6].trim() : '',
          };
          
          final status = fields[4].trim().toLowerCase();

          // Call API to create driver with proper structure
          final response = await widget.driverService.createDriver({
            'driverId': driverId,
            'personalInfo': personalInfo,
            'license': license,
            'status': status,
          });
          
          if (response['success'] == true) {
            successCount++;
          } else {
            errorCount++;
          }
        } catch (e) {
          errorCount++;
        }
      }

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      // Refresh driver list
      await _fetchDrivers();

      // Show result
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import complete: $successCount success, $errorCount errors'),
            backgroundColor: successCount > 0 ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing drivers: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ✅ FIXED-WIDTH HEADER CELL FOR SYNCHRONIZED SCROLLING
  Widget _buildHeaderCellFixed(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
    );
  }

  // ✅ COMPLETE _buildDriverRow METHOD (Original with Expanded)
  Widget _buildDriverRow(Map<String, dynamic> driver) {
    final vehicle = driver['assignedVehicle'];
    final hasVehicle = vehicle != null || (driver['vehicleNumber'] != null && driver['vehicleNumber'] != 'N/A');

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DriverDetailsPage(driver: driver),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                driver['driverId'] ?? 'N/A',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                driver['name'] ?? _getNestedValue(driver, 'personalInfo.name', 'N/A'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                driver['email'] ?? _getNestedValue(driver, 'personalInfo.email', 'N/A'),
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                driver['phone'] ?? _getNestedValue(driver, 'personalInfo.phone', 'N/A'),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            Expanded(
              flex: 2,
              child: _buildStatusBadge(driver['status'] ?? 'inactive'),
            ),
            Expanded(
              flex: 2,
              child: Text(
                _getNestedValue(driver, 'license.licenseNumber'),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                _formatDate(driver['licenseExpiry']?.toString() ?? 
                  _getNestedValue(driver, 'license.expiryDate')),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Expanded(
              flex: 3,
              child: hasVehicle
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.directions_car, size: 16, color: Colors.green.shade700),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              driver['vehicleNumber']?.toString() ??
                              vehicle?['registrationNumber']?.toString() ??
                              vehicle?['vehicleNumber']?.toString() ??
                              '${vehicle?['make'] ?? ''} ${vehicle?['model'] ?? ''}'.trim(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade900,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  : TextButton.icon(
                      onPressed: () => _showVehicleAssignmentDialog(driver),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Assign'),
                      style: TextButton.styleFrom(foregroundColor: primaryColor),
                    ),
            ),
            Expanded(
              flex: 1,
              child: Center(child: _buildDocumentStatusIndicator(driver)),
            ),
            Expanded(
              flex: 1,
              child: Center(child: _buildDocumentStatusIndicator(driver)),
            ),
            SizedBox(
              width: 220,
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  Tooltip(
                    message: hasVehicle ? 'Change Vehicle' : 'Assign Vehicle',
                    child: IconButton(
                      icon: const Icon(Icons.directions_car, size: 18),
                      color: hasVehicle ? Colors.orange : primaryColor,
                      onPressed: () => _showVehicleAssignmentDialog(driver),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                  Tooltip(
                    message: 'View Details',
                    child: IconButton(
                      icon: const Icon(Icons.visibility, size: 18),
                      color: primaryColor,
                      onPressed: () => _showDriverDetails(driver),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                  Tooltip(
                    message: 'Edit Driver',
                    child: IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      color: Colors.orange.shade700,
                      onPressed: () => _showEditDriverDialog(driver),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                  Tooltip(
                    message: 'Delete Driver',
                    child: IconButton(
                      icon: const Icon(Icons.delete, size: 18),
                      color: Colors.red.shade700,
                      onPressed: () {
                        final driverId = driver['driverId'] ?? driver['_id']?.toString() ?? driver['id']?.toString();
                        if (driverId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Error: Driver ID not found'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        _deleteDriver(driverId, driver['name'] ?? 'Unknown');
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                  Tooltip(
                    message: 'Send Password Reset Email',
                    child: IconButton(
                      icon: const Icon(Icons.email, size: 18),
                      color: Colors.purple.shade700,
                      onPressed: () => _sendPasswordResetEmail(driver),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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

  // ✅ NEW: FIXED-WIDTH DRIVER ROW FOR SYNCHRONIZED SCROLLING
  Widget _buildDriverRowFixed(Map<String, dynamic> driver) {
    final vehicle = driver['assignedVehicle'];
    final hasVehicle = vehicle != null || (driver['vehicleNumber'] != null && driver['vehicleNumber'] != 'N/A');

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DriverDetailsPage(driver: driver),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18), // More padding
        child: Row(
          children: [
            SizedBox(
              width: 150,
              child: Text(
                driver['driverId'] ?? 'N/A',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            SizedBox(
              width: 150,
              child: Text(
                driver['name'] ?? _getNestedValue(driver, 'personalInfo.name', 'N/A'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              width: 220,
              child: Text(
                driver['email'] ?? _getNestedValue(driver, 'personalInfo.email', 'N/A'),
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 130,
              child: Text(
                driver['phone'] ?? _getNestedValue(driver, 'personalInfo.phone', 'N/A'),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            SizedBox(
              width: 120,
              child: _buildStatusBadge(driver['status'] ?? 'inactive'),
            ),
            SizedBox(
              width: 140,
              child: Text(
                _getNestedValue(driver, 'license.licenseNumber'),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            SizedBox(
              width: 130,
              child: Text(
                _formatDate(driver['licenseExpiry']?.toString() ?? 
                  _getNestedValue(driver, 'license.expiryDate')),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            SizedBox(
              width: 200,
              child: hasVehicle
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.directions_car, size: 16, color: Colors.green.shade700),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              driver['vehicleNumber']?.toString() ??
                              vehicle?['registrationNumber']?.toString() ??
                              vehicle?['vehicleNumber']?.toString() ??
                              '${vehicle?['make'] ?? ''} ${vehicle?['model'] ?? ''}'.trim(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade900,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  : TextButton.icon(
                      onPressed: () => _showVehicleAssignmentDialog(driver),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Assign'),
                      style: TextButton.styleFrom(foregroundColor: primaryColor),
                    ),
            ),
            SizedBox(
              width: 70,
              child: Center(child: _buildDocumentStatusIndicator(driver)),
            ),
            SizedBox(
              width: 220,
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  Tooltip(
                    message: hasVehicle ? 'Change Vehicle' : 'Assign Vehicle',
                    child: IconButton(
                      icon: const Icon(Icons.directions_car, size: 18),
                      color: hasVehicle ? Colors.orange : primaryColor,
                      onPressed: () => _showVehicleAssignmentDialog(driver),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                  Tooltip(
                    message: 'View Details',
                    child: IconButton(
                      icon: const Icon(Icons.visibility, size: 18),
                      color: primaryColor,
                      onPressed: () => _showDriverDetails(driver),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                  Tooltip(
                    message: 'Edit Driver',
                    child: IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      color: Colors.orange.shade700,
                      onPressed: () => _showEditDriverDialog(driver),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                  Tooltip(
                    message: 'Delete Driver',
                    child: IconButton(
                      icon: const Icon(Icons.delete, size: 18),
                      color: Colors.red.shade700,
                      onPressed: () {
                        final driverId = driver['driverId'] ?? driver['_id']?.toString() ?? driver['id']?.toString();
                        if (driverId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Error: Driver ID not found'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        _deleteDriver(driverId, driver['name'] ?? 'Unknown');
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                  Tooltip(
                    message: 'Send Password Reset Email',
                    child: IconButton(
                      icon: const Icon(Icons.email, size: 18),
                      color: Colors.purple.shade700,
                      onPressed: () => _sendPasswordResetEmail(driver),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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

  // ✅ HELPER METHODS
  String _getRating(Map<String, dynamic> driver) {
    final topLevel = driver['rating'];
    if (topLevel != null && topLevel.toString() != 'null') {
      final parsed = double.tryParse(topLevel.toString());
      if (parsed != null && parsed > 0) return parsed.toStringAsFixed(1);
    }
    
    final stats = driver['feedbackStats'];
    if (stats is Map) {
      final avg = stats['averageRating'];
      if (avg != null) {
        final parsed = double.tryParse(avg.toString());
        if (parsed != null && parsed > 0) return parsed.toStringAsFixed(1);
      }
    }
    return 'N/A';
  }

  String _formatDate(String? rawDate) {
    if (rawDate == null || rawDate == 'N/A' || rawDate.isEmpty) return 'N/A';
    try {
      if (rawDate.length == 10 && rawDate.contains('-')) return rawDate;
      return rawDate.split('T')[0];
    } catch (e) {
      return rawDate;
    }
  }

  // ✅ BUILD METHOD WITH ADVANCED FILTERS
  @override
  Widget build(BuildContext context) {
    if (widget.isEmbedded) {
      return _buildContent(context);
    }
    
    return Scaffold(
      backgroundColor: lightBackgroundColor,
      appBar: AppBar(
        title: const Text('Driver Management'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back',
        ),
      ),
      body: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final activeFilterCount = _getActiveFilterCount();
    
    return Container(
      color: lightBackgroundColor,
      child: Column(
        children: [
          // SEARCH AND BASIC FILTERS
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: cardBackgroundColor,
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search by name, email, phone, or driver ID...',
                          prefixIcon: const Icon(Icons.search, size: 20, color: primaryColor),
                          filled: true,
                          fillColor: lightBackgroundColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: borderColor),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onChanged: (value) => _searchQuery = value,
                        onSubmitted: (value) => _fetchDrivers(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<String>(
                        value: _selectedStatus.isEmpty ? 'active' : _selectedStatus,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: lightBackgroundColor,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        hint: const Text('Status'),
                        items: const [
                          DropdownMenuItem(value: '', child: Text('All Status')),
                          DropdownMenuItem(value: 'active', child: Text('Active')),
                          DropdownMenuItem(value: 'on_leave', child: Text('On Leave')),
                          DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedStatus = value ?? '');
                          _fetchDrivers();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<String>(
                        value: _selectedVehicleFilter.isEmpty ? null : _selectedVehicleFilter,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: lightBackgroundColor,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        hint: const Text('Vehicle'),
                        items: const [
                          DropdownMenuItem(value: '', child: Text('All Drivers')),
                          DropdownMenuItem(value: 'assigned', child: Text('With Vehicle')),
                          DropdownMenuItem(value: 'unassigned', child: Text('No Vehicle')),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedVehicleFilter = value ?? '');
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<String>(
                        value: _selectedDocumentFilter.isEmpty ? null : _selectedDocumentFilter,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: lightBackgroundColor,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        hint: const Text('Documents'),
                        items: const [
                          DropdownMenuItem(value: '', child: Text('All Documents')),
                          DropdownMenuItem(value: 'expired', child: Text('Expired')),
                          DropdownMenuItem(value: 'expiring_soon', child: Text('Expiring Soon')),
                          DropdownMenuItem(value: 'all_valid', child: Text('All Valid')),
                          DropdownMenuItem(value: 'no_documents', child: Text('No Documents')),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedDocumentFilter = value ?? '');
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _fetchDrivers,
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Search'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: const Text('Clear Filters'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryColor,
                        side: const BorderSide(color: primaryColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await _fetchDrivers();
                        await _fetchVehicles();
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh'),
                    ),
                    const SizedBox(width: 8),
                    // ✅ ADVANCED FILTERS BUTTON
                    ElevatedButton.icon(
                      onPressed: _toggleAdvancedFilters,
                      icon: AnimatedRotation(
                        turns: _showAdvancedFilters ? 0.5 : 0,
                        duration: const Duration(milliseconds: 300),
                        child: const Icon(Icons.tune, size: 18),
                      ),
                      label: Text(_showAdvancedFilters ? 'Hide Advanced' : 'Advanced Filters'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _showAdvancedFilters ? darkPrimaryColor : primaryColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ✅ ADD DRIVER BUTTON
                    ElevatedButton.icon(
                      onPressed: _showAddDriverDialog,
                      icon: const Icon(Icons.person_add, size: 18),
                      label: const Text('Add Driver'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ✅ BULK IMPORT BUTTON
                    ElevatedButton.icon(
                      onPressed: _showBulkImportDialog,
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: const Text('Bulk Import'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade600,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ✅ EXPORT BUTTON
                    ElevatedButton.icon(
                      onPressed: _exportToExcel,
                      icon: const Icon(Icons.file_download, size: 18),
                      label: const Text('Export Excel'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    if (activeFilterCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: primaryColor),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.filter_list, size: 16, color: primaryColor),
                            const SizedBox(width: 6),
                            Text(
                              '$activeFilterCount active',
                              style: const TextStyle(color: primaryColor, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(width: 12),
                    Text(
                      'Total: $_totalDrivers drivers',
                      style: const TextStyle(color: textPrimaryColor, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ✅ ADVANCED FILTERS EXPANDABLE SECTION
          SizeTransition(
            sizeFactor: _filterAnimation,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: const Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.filter_list, size: 20, color: primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Advanced Filters',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textPrimaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // ✅ USE CountryStateCityFilter WIDGET
                  CountryStateCityFilter(
                    initialFromDate: _startDate,
                    initialToDate: _endDate,
                    initialCountry: _selectedCountry,
                    initialState: _selectedState,
                    initialCity: _selectedCity,
                    onFilterApplied: (filterData) {
                      setState(() {
                        _startDate = filterData['fromDate'];
                        _endDate = filterData['toDate'];
                        _selectedCountry = filterData['country'];
                        _selectedState = filterData['state'];
                        _selectedCity = filterData['city'];
                      });
                      _handleFilterApplied(filterData);
                      
                      // Show success message
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(Icons.check_circle, color: Colors.white),
                              const SizedBox(width: 8),
                              Text('Advanced filters applied'),
                            ],
                          ),
                          backgroundColor: Colors.green.shade600,
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // ✅ TABLE WITH SYNCHRONIZED HORIZONTAL SCROLLING (FIXED)
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: primaryColor))
                : _filteredDrivers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_off, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text('No drivers found', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
                          ],
                        ),
                      )
                    : Container(
                        margin: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: Column(
                          children: [
                            // ✅ HEADER AND BODY WITH SYNCHRONIZED HORIZONTAL SCROLL
                            Expanded(
                              child: Scrollbar(
                                controller: _horizontalScrollController,
                                thumbVisibility: true,
                                child: Listener(
                                  onPointerSignal: (pointerSignal) {
                                    if (pointerSignal is PointerScrollEvent) {
                                      final newOffset = _horizontalScrollController.offset + pointerSignal.scrollDelta.dx;
                                      _horizontalScrollController.jumpTo(
                                        newOffset.clamp(
                                          0.0,
                                          _horizontalScrollController.position.maxScrollExtent,
                                        ),
                                      );
                                    }
                                  },
                                  child: SingleChildScrollView(
                                    controller: _horizontalScrollController,
                                    scrollDirection: Axis.horizontal,
                                    physics: const ClampingScrollPhysics(),
                                    child: SizedBox(
                                      width: 2000, // Fixed width for all columns
                                      child: Column(
                                        children: [
                                          // HEADER ROW
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
                                                SizedBox(width: 150, child: _buildHeaderCellFixed('DRIVER ID')),
                                                SizedBox(width: 150, child: _buildHeaderCellFixed('NAME')),
                                                SizedBox(width: 220, child: _buildHeaderCellFixed('EMAIL')),
                                                SizedBox(width: 130, child: _buildHeaderCellFixed('PHONE')),
                                                SizedBox(width: 120, child: _buildHeaderCellFixed('STATUS')),
                                                SizedBox(width: 140, child: _buildHeaderCellFixed('LICENSE NO.')),
                                                SizedBox(width: 130, child: _buildHeaderCellFixed('LICENSE EXPIRY')),
                                                SizedBox(width: 200, child: _buildHeaderCellFixed('VEHICLE')),
                                                // ❌ REMOVED: Trips and Rating columns
                                                SizedBox(width: 70, child: _buildHeaderCellFixed('DOCS')),
                                                SizedBox(width: 220, child: _buildHeaderCellFixed('ACTIONS')),
                                              ],
                                            ),
                                          ),
                                          
                                          // DATA ROWS
                                          Expanded(
                                            child: ListView.separated(
                                              itemCount: _filteredDrivers.length,
                                              separatorBuilder: (context, index) => Divider(
                                                height: 1,
                                                color: Colors.grey[200],
                                              ),
                                              itemBuilder: (context, index) {
                                                return _buildDriverRowFixed(_filteredDrivers[index]);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
          ),

          // FOOTER
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: cardBackgroundColor,
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${_filteredDrivers.length} drivers',
                  style: const TextStyle(fontSize: 14, color: textSecondaryColor, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Total: $_totalDrivers drivers',
                  style: const TextStyle(fontSize: 14, color: textPrimaryColor, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // EXPORT/IMPORT METHODS (NEW - Moved from driver_admin_management_screen.dart)
  // ============================================================================
  
  // Show Export Dialog
  Future<void> _showExportDialog() async {
    await showDialog(
      context: context,
      builder: (context) => ExportDriversDialog(driverService: widget.driverService),
    );
  }

  // Show Import Dialog
  Future<void> _showImportDialog() async {
    final result = await showDialog(
      context: context,
      builder: (context) => ImportDriversDialog(driverService: widget.driverService),
    );
    
    if (result == true) {
      // Refresh driver list after import
      _fetchDrivers();
    }
  }
}