// ============================================================================
// VEHICLE MASTER - CHUNK 1 OF 4
// Paste all 4 chunks into ONE file: vehicle_master.dart
// Chunk 1: lines 1 to 443 of 1768
// ============================================================================
// ============================================================================
// VEHICLE MASTER SCREEN - CHUNK 1 OF 4
// Paste all 4 chunks into a single file: vehicle_master.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:abra_fleet/features/admin/vehicle_admin_management/vehicle_master/add_vehicle.dart';
import 'package:abra_fleet/features/admin/vehicle_admin_management/vehicle_master/bulk_import_vehicles.dart';
import 'package:abra_fleet/features/admin/vehicle_admin_management/maintainace_managemnt/maintainance_management.dart';
import 'package:abra_fleet/core/services/vehicle_service.dart';
import 'package:abra_fleet/core/services/document_storage_service.dart';
import 'package:abra_fleet/features/admin/widgets/country_state_city_filter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:excel/excel.dart' as excel;
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html show AnchorElement, Blob, Url;
import 'package:country_state_city_picker/country_state_city_picker.dart';
import 'package:abra_fleet/app/config/api_config.dart';

// ============================================================================
// COLOR SCHEME - Matches Driver List page style but with vehicle #0a1759 brand
// ============================================================================
const Color _primaryColor = Color(0xFF0a1759);
const Color _darkPrimaryColor = Color(0xFF060e3a);
const Color _accentColor = Color(0xFF1a2f7a);
const Color _lightBg = Color(0xFFF5F7FA);
const Color _cardBg = Colors.white;
const Color _borderColor = Color(0xFFE0E0E0);
const Color _textPrimary = Color(0xFF0a1759);
const Color _textSecondary = Color(0xFF6B7280);
const Color _headerColor = Color(0xFF0a1759);

// ============================================================================
// VEHICLE DATA MODEL
// ============================================================================
class _VehicleData {
  final String id;
  final String vehicleId;
  final String registration;
  final String type;
  final String model;
  final String status;
  final String year;
  final String engineType;
  final String engineCapacity;
  final String seatingCapacity;
  final String mileage;
  final String lastServiceDate;
  final String nextServiceDue;
  final String? assignedDriverName;
  final String? assignedDriverId;
  final DateTime? onboardedDate;
  final List<Map<String, dynamic>> documents;
  final String? vendor;
  final int assignedCustomersCount;
  final int maintenanceScheduleCount;
  final String? country;
  final String? state;
  final String? city;

  const _VehicleData({
    required this.id,
    required this.vehicleId,
    required this.registration,
    required this.type,
    required this.model,
    required this.status,
    required this.year,
    required this.engineType,
    required this.engineCapacity,
    required this.seatingCapacity,
    required this.mileage,
    required this.lastServiceDate,
    required this.nextServiceDue,
    this.assignedDriverName,
    this.assignedDriverId,
    this.onboardedDate,
    this.documents = const [],
    this.vendor,
    this.assignedCustomersCount = 0,
    this.maintenanceScheduleCount = 0,
    this.country,
    this.state,
    this.city,
  });

  bool get hasExpiredDocuments {
    final now = DateTime.now();
    return documents.any((doc) {
      final expiryDate = doc['expiryDate'];
      return expiryDate != null && DateTime.parse(expiryDate).isBefore(now);
    });
  }

  bool get hasExpiringSoonDocuments {
    final now = DateTime.now();
    final thirtyDaysFromNow = now.add(const Duration(days: 30));
    return documents.any((doc) {
      final expiryDate = doc['expiryDate'];
      if (expiryDate == null) return false;
      final expiry = DateTime.parse(expiryDate);
      return expiry.isAfter(now) && expiry.isBefore(thirtyDaysFromNow);
    });
  }

  factory _VehicleData.fromBackend(Map<String, dynamic> data) {
    String mongoId = '';
    if (data['_id'] != null) {
      if (data['_id'] is Map) {
        mongoId = data['_id']['\$oid'] ?? '';
      } else {
        mongoId = data['_id'].toString();
      }
    }

    String? driverName;
    String? driverId;
    if (data['assignedDriver'] != null) {
      final driver = data['assignedDriver'];
      driverName = driver['name'] ?? driver['personalInfo']?['firstName'] ?? 'Unknown Driver';
      driverId = driver['driverId'];
    }

    List<Map<String, dynamic>> vehicleDocs = [];
    if (data['documents'] != null && data['documents'] is List) {
      vehicleDocs = (data['documents'] as List).map((doc) => Map<String, dynamic>.from(doc)).toList();
    }

    DateTime? onboarded;
    if (data['onboardedDate'] != null) {
      try { onboarded = DateTime.parse(data['onboardedDate']); } catch (e) { onboarded = null; }
    }

    int assignedCount = 0;
    if (data['assignedCustomers'] != null && data['assignedCustomers'] is List) {
      assignedCount = (data['assignedCustomers'] as List).length;
    }

    int maintenanceCount = 0;
    if (data['maintenanceScheduleCount'] != null) {
      maintenanceCount = int.tryParse(data['maintenanceScheduleCount'].toString()) ?? 0;
    }

    return _VehicleData(
      id: mongoId,
      vehicleId: data['vehicleId'] ?? '',
      registration: data['registrationNumber'] ?? '',
      type: (data['type'] ?? '').toString().toUpperCase(),
      model: '${data['make'] ?? ''} ${data['model'] ?? ''}'.trim(),
      status: (data['status'] ?? 'active').toString().toUpperCase(),
      year: (data['year'] ?? data['yearOfManufacture'] ?? '').toString(),
      engineType: data['specifications']?['engineType'] ?? data['engineType'] ?? '',
      engineCapacity: (data['specifications']?['engineCapacity'] ?? data['engineCapacity'] ?? '').toString(),
      seatingCapacity: (() {
        try {
          if (data['seatCapacity'] != null) return data['seatCapacity'].toString();
          if (data['seatingCapacity'] != null) return data['seatingCapacity'].toString();
          if (data['capacity'] != null) {
            final capacity = data['capacity'];
            if (capacity is Map && capacity['passengers'] != null) return capacity['passengers'].toString();
            else if (capacity is num) return capacity.toString();
            else return capacity.toString();
          }
          return '4';
        } catch (e) { return '4'; }
      })(),
      mileage: (data['specifications']?['mileage'] ?? data['mileage'] ?? '').toString(),
      lastServiceDate: data['maintenance']?['lastServiceDate'] != null
          ? DateTime.parse(data['maintenance']['lastServiceDate']).toString().split(' ')[0] : '-',
      nextServiceDue: data['maintenance']?['nextServiceDue'] != null
          ? DateTime.parse(data['maintenance']['nextServiceDue']).toString().split(' ')[0] : '-',
      assignedDriverName: driverName,
      assignedDriverId: driverId,
      onboardedDate: onboarded,
      documents: vehicleDocs,
      vendor: data['vendor'],
      assignedCustomersCount: assignedCount,
      maintenanceScheduleCount: maintenanceCount,
      country: data['country'],
      state: data['state'],
      city: data['city'],
    );
  }

  Map<String, dynamic> toMap() {
    final seatCapacity = int.tryParse(seatingCapacity) ?? 4;
    final driverSeats = assignedDriverName != null ? 1 : 0;
    final availableSeats = seatCapacity - driverSeats - assignedCustomersCount;
    return {
      'Vehicle ID': vehicleId,
      'Registration Number': registration,
      'Vehicle Type': type,
      'Make & Model': model,
      'Year of Manufacture': year,
      'Engine Type': engineType,
      'Engine Capacity (CC)': engineCapacity,
      'Seating Capacity': seatingCapacity,
      'Seat Availability': '$availableSeats/$seatCapacity',
      'Mileage (km/l)': mileage,
      'Status': status,
      'Vendor': vendor ?? 'Own Fleet',
      'Assigned Driver': assignedDriverName ?? 'Not Assigned',
      'Assigned Customers': assignedCustomersCount.toString(),
      'Last Service Date': lastServiceDate,
      'Next Service Due': nextServiceDue,
      'Onboarded Date': onboardedDate != null ? onboardedDate.toString().split(' ')[0] : 'Not Onboarded',
      'Document Status': hasExpiredDocuments
          ? 'Has Expired Documents'
          : hasExpiringSoonDocuments ? 'Expiring Soon' : documents.isNotEmpty ? 'All Valid' : 'No Documents',
      'Country': country ?? 'Not Set',
      'State': state ?? 'Not Set',
      'City': city ?? 'Not Set',
    };
  }
}

// ============================================================================
// MAIN WIDGET
// ============================================================================
class VehicleMasterScreen extends StatefulWidget {
  const VehicleMasterScreen({super.key});

  @override
  State<VehicleMasterScreen> createState() => _VehicleMasterScreenState();
}

class _VehicleMasterScreenState extends State<VehicleMasterScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {

  // Services
  final VehicleService _vehicleService = VehicleService();
  final DocumentStorageService _documentStorageService = DocumentStorageService();

  // Overlay stack
  List<Widget> _overlayStack = [];

  // Data
  List<_VehicleData> _vehicleData = [];
  List<_VehicleData> _filteredVehicleData = [];

  // Loading
  bool _isLoading = true;
  String? _errorMessage;

  // Basic filter states
  String _selectedStatusFilter = '';
  String _selectedDocumentFilter = '';
  String _selectedVendorFilter = '';
  String _selectedDriverFilter = '';

  // Advanced filter states
  bool _showAdvancedFilters = false;
  late AnimationController _filterAnimationController;
  late Animation<double> _filterAnimation;
  String? _selectedCountry;
  String? _selectedState;
  String? _selectedCity;
  String _selectedEngineTypeFilter = '';
  String _selectedVehicleTypeFilter = '';
  DateTime? _startDate;
  DateTime? _endDate;

  // Search
  final TextEditingController _searchController = TextEditingController();

  // Horizontal scroll
  final ScrollController _horizontalScrollController = ScrollController();

  // Auto-refresh
  Timer? _refreshTimer;
  DateTime? _lastRefreshTime;

  // Total count
  int _totalVehicles = 0;

  // ============================================================================
  // LIFECYCLE
  // ============================================================================
  @override
  void initState() {
    super.initState();
    _filterAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _filterAnimation = CurvedAnimation(
      parent: _filterAnimationController,
      curve: Curves.easeInOut,
    );
    _loadVehicles();
    _searchController.addListener(_applyFilters);
    WidgetsBinding.instance.addObserver(this);
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _refreshTimer?.cancel();
    _filterAnimationController.dispose();
    _horizontalScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadVehicles();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && !_isLoading) _loadVehicles();
    });
  }

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

  // ============================================================================
  // API
  // ============================================================================
  Future<void> _loadVehicles() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final response = await _vehicleService.getVehicles(limit: 100);
      if (response['success'] == true) {
        final List<dynamic> vehiclesData = response['data'] ?? [];
        setState(() {
          _vehicleData = vehiclesData.map((v) => _VehicleData.fromBackend(v)).toList();
          _totalVehicles = _vehicleData.length;
          _applyFilters();
          _isLoading = false;
          _lastRefreshTime = DateTime.now();
        });
      } else {
        setState(() { _errorMessage = response['message'] ?? 'Failed to load vehicles'; _isLoading = false; });
      }
    } catch (e) {
      setState(() { _errorMessage = 'Error loading vehicles: $e'; _isLoading = false; });
    }
  }

  // ============================================================================
  // FILTER LOGIC
  // ============================================================================
  void _applyFilters() {
    final searchQuery = _searchController.text.toLowerCase().trim();
    _filteredVehicleData = _vehicleData.where((vehicle) {
      if (searchQuery.isNotEmpty) {
        final seatCapacity = int.tryParse(vehicle.seatingCapacity) ?? 4;
        final availableSeats = seatCapacity - (vehicle.assignedDriverName != null ? 1 : 0) - vehicle.assignedCustomersCount;
        final matchesSearch =
            vehicle.vehicleId.toLowerCase().contains(searchQuery) ||
            vehicle.registration.toLowerCase().contains(searchQuery) ||
            vehicle.type.toLowerCase().contains(searchQuery) ||
            vehicle.model.toLowerCase().contains(searchQuery) ||
            vehicle.status.toLowerCase().contains(searchQuery) ||
            vehicle.year.toLowerCase().contains(searchQuery) ||
            vehicle.engineType.toLowerCase().contains(searchQuery) ||
            (vehicle.vendor?.toLowerCase().contains(searchQuery) ?? false) ||
            (vehicle.assignedDriverName?.toLowerCase().contains(searchQuery) ?? false) ||
            availableSeats.toString().contains(searchQuery);
        if (!matchesSearch) return false;
      }
      if (_selectedStatusFilter.isNotEmpty && vehicle.status.toUpperCase() != _selectedStatusFilter.toUpperCase()) return false;
      if (_selectedVendorFilter == 'Own Fleet' && vehicle.vendor != null && vehicle.vendor!.isNotEmpty) return false;
      else if (_selectedVendorFilter == 'Vendor' && (vehicle.vendor == null || vehicle.vendor!.isEmpty)) return false;
      if (_selectedDriverFilter == 'Assigned' && vehicle.assignedDriverName == null) return false;
      else if (_selectedDriverFilter == 'Not Assigned' && vehicle.assignedDriverName != null) return false;
      if (_selectedDocumentFilter == 'Expired' && !vehicle.hasExpiredDocuments) return false;
      else if (_selectedDocumentFilter == 'Expiring Soon' && !vehicle.hasExpiringSoonDocuments) return false;
      else if (_selectedDocumentFilter == 'All Valid' && (vehicle.hasExpiredDocuments || vehicle.hasExpiringSoonDocuments)) return false;
      else if (_selectedDocumentFilter == 'No Documents' && vehicle.documents.isNotEmpty) return false;
      if (_selectedEngineTypeFilter.isNotEmpty && vehicle.engineType.toLowerCase() != _selectedEngineTypeFilter.toLowerCase()) return false;
      if (_selectedVehicleTypeFilter.isNotEmpty && vehicle.type.toLowerCase() != _selectedVehicleTypeFilter.toLowerCase()) return false;
      if (_selectedCountry != null && (vehicle.country == null || !vehicle.country!.toLowerCase().contains(_selectedCountry!.toLowerCase()))) return false;
      if (_selectedState != null && (vehicle.state == null || !vehicle.state!.toLowerCase().contains(_selectedState!.toLowerCase()))) return false;
      if (_selectedCity != null && (vehicle.city == null || !vehicle.city!.toLowerCase().contains(_selectedCity!.toLowerCase()))) return false;
      return true;
    }).toList();
    setState(() {});
  }

  void _clearAllFilters() {
    setState(() {
      _selectedStatusFilter = '';
      _selectedDocumentFilter = '';
      _selectedVendorFilter = '';
      _selectedDriverFilter = '';
      _selectedEngineTypeFilter = '';
      _selectedVehicleTypeFilter = '';
      _selectedCountry = null;
      _selectedState = null;
      _selectedCity = null;
      _startDate = null;
      _endDate = null;
      _searchController.clear();
      _applyFilters();
    });
  }

  bool _hasActiveFilters() {
    return _selectedStatusFilter.isNotEmpty ||
        _selectedDocumentFilter.isNotEmpty ||
        _selectedVendorFilter.isNotEmpty ||
        _selectedDriverFilter.isNotEmpty ||
        _selectedEngineTypeFilter.isNotEmpty ||
        _selectedVehicleTypeFilter.isNotEmpty ||
        _selectedCountry != null ||
        _searchController.text.isNotEmpty;
  }

  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedStatusFilter.isNotEmpty) count++;
    if (_selectedDocumentFilter.isNotEmpty) count++;
    if (_selectedVendorFilter.isNotEmpty) count++;
    if (_selectedDriverFilter.isNotEmpty) count++;
    if (_selectedEngineTypeFilter.isNotEmpty) count++;
    if (_selectedVehicleTypeFilter.isNotEmpty) count++;
    if (_selectedCountry != null) count++;
    if (_selectedState != null) count++;
    if (_selectedCity != null) count++;
    if (_startDate != null && _endDate != null) count++;
    return count;
  }

// ============================================================================
// VEHICLE MASTER SCREEN - CHUNK 2 OF 4
// Paste after Chunk 1 (remove the closing brace of chunk 1 first - the last })
// ============================================================================

  // ============================================================================
  // EXCEL EXPORT
  // ============================================================================
// VEHICLE MASTER - CHUNK 2 OF 4
// Paste all 4 chunks into ONE file: vehicle_master.dart
// Chunk 2: lines 444 to 886 of 1768
// ============================================================================
  // ============================================================================
  Future<void> _exportToExcel() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(_primaryColor)),
                SizedBox(height: 16),
                Text('Generating Excel file...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _primaryColor)),
              ],
            ),
          ),
        ),
      );

      var excelFile = excel.Excel.createExcel();
      var sheet = excelFile['Vehicles'];
      final headers = ['Vehicle ID','Registration Number','Vehicle Type','Make & Model','Year of Manufacture','Engine Type','Engine Capacity (CC)','Seating Capacity','Seat Availability','Mileage (km/l)','Status','Vendor','Assigned Driver','Assigned Customers','Last Service Date','Next Service Due','Onboarded Date','Document Status'];

      for (var i = 0; i < headers.length; i++) {
        var cell = sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = excel.TextCellValue(headers[i]);
        cell.cellStyle = excel.CellStyle(bold: true, backgroundColorHex: excel.ExcelColor.fromHexString('#0a1759'), fontColorHex: excel.ExcelColor.white);
      }
      for (var i = 0; i < _vehicleData.length; i++) {
        final vehicleMap = _vehicleData[i].toMap();
        for (var j = 0; j < headers.length; j++) {
          var cell = sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: j, rowIndex: i + 1));
          cell.value = excel.TextCellValue((vehicleMap[headers[j]] ?? '').toString());
        }
      }
      for (var i = 0; i < headers.length; i++) sheet.setColumnWidth(i, 20);

      var fileBytes = excelFile.save();
      if (fileBytes == null) throw Exception('Failed to generate Excel file');
      if (mounted) Navigator.pop(context);

      if (kIsWeb) {
        final blob = html.Blob([fileBytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', 'Vehicles_Export_${DateTime.now().millisecondsSinceEpoch}.xlsx')
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/Vehicles_Export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Excel file saved to: $filePath'), backgroundColor: _primaryColor, duration: const Duration(seconds: 5),
              action: SnackBarAction(label: 'Open', textColor: Colors.white, onPressed: () async {
                final uri = Uri.file(filePath);
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              }),
            ),
          );
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully exported ${_vehicleData.length} vehicles to Excel'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error exporting: $e'), backgroundColor: Colors.red));
    }
  }

  // ============================================================================
  // OVERLAY MANAGEMENT
  // ============================================================================
  void _pushOverlay(Widget overlay) => setState(() => _overlayStack.add(overlay));
  void _popOverlay() { if (_overlayStack.isNotEmpty) setState(() => _overlayStack.removeLast()); }
  void _clearAllOverlays() => setState(() => _overlayStack.clear());

  Widget _buildOverlayWrapper({required String title, required Widget child, double? width, double? height}) {
    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: width ?? MediaQuery.of(context).size.width * 0.9,
          height: height ?? MediaQuery.of(context).size.height * 0.85,
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))]),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [_primaryColor, _accentColor]),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    IconButton(onPressed: _popOverlay, icon: const Icon(Icons.arrow_back, color: Colors.white), tooltip: 'Back'),
                    const SizedBox(width: 12),
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(onPressed: _clearAllOverlays, child: const Text('Cancel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16))),
                  ],
                ),
              ),
              Expanded(child: ClipRRect(borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)), child: child)),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // NAVIGATION
  // ============================================================================
  void _showAddVehicleScreen() {
    _pushOverlay(_buildOverlayWrapper(
      title: 'Add New Vehicle',
      child: AddVehicleScreen(onCancel: _popOverlay, onSave: () { _popOverlay(); _loadVehicles(); }),
    ));
  }

  void _showBulkImportScreen() {
    _pushOverlay(_buildOverlayWrapper(
      title: 'Bulk Import Vehicles',
      child: BulkImportVehiclesScreen(onCancel: _popOverlay, onImportComplete: () { _popOverlay(); _loadVehicles(); }),
    ));
  }

  void _navigateToMaintenanceManagement(String vehicleId, String vehicleNumber) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const MaintenanceManagementScreen())).then((_) => _loadVehicles());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Opening maintenance for $vehicleNumber'), duration: const Duration(seconds: 2), backgroundColor: _primaryColor));
  }

  // ============================================================================
  // VEHICLE DETAILS
  // ============================================================================
  void _showVehicleDetails(String mongoId) {
    final vehicle = _vehicleData.firstWhere((v) => v.id == mongoId);
    _pushOverlay(_buildOverlayWrapper(
      title: 'Vehicle Details',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(gradient: LinearGradient(colors: [_primaryColor, _accentColor]), borderRadius: BorderRadius.all(Radius.circular(12))),
                          child: const Icon(Icons.directions_car, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: Text(vehicle.registration, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _primaryColor))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow('Vehicle ID:', vehicle.vehicleId),
                    _buildDetailRow('Type:', vehicle.type),
                    _buildDetailRow('Model:', vehicle.model),
                    _buildDetailRow('Year:', vehicle.year),
                    _buildDetailRow('Vendor:', vehicle.vendor ?? 'Own Fleet'),
                    _buildDetailRow('Engine Type:', vehicle.engineType),
                    _buildDetailRow('Engine Capacity:', '${vehicle.engineCapacity} CC'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _primaryColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.airline_seat_recline_normal, color: _primaryColor, size: 24),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Seating Capacity', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
                              Text('${vehicle.seatingCapacity} seats total', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _primaryColor)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow('Mileage:', '${vehicle.mileage} km/l'),
                    _buildDetailRow('Status:', vehicle.status),
                    _buildDetailRow('Assigned Driver:', vehicle.assignedDriverName ?? 'Not Assigned'),
                    _buildDetailRow('Assigned Customers:', '${vehicle.assignedCustomersCount}'),
                    _buildDetailRow('Last Service:', vehicle.lastServiceDate),
                    _buildDetailRow('Next Service Due:', vehicle.nextServiceDue),
                    if (vehicle.onboardedDate != null)
                      _buildDetailRow('Onboarded:', vehicle.onboardedDate.toString().split(' ')[0]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Vehicle Documents', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _primaryColor)),
                        ElevatedButton.icon(
                          onPressed: () => _showAddDocumentDialog(vehicle.id, false),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Document'),
                          style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (vehicle.documents.isEmpty)
                      const Padding(padding: EdgeInsets.all(16.0), child: Text('No vehicle documents uploaded', style: TextStyle(color: Colors.grey)))
                    else
                      ...vehicle.documents.map((doc) => _buildDocumentTile(doc, vehicle.id, false)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: () async { await _loadVehicles(); _popOverlay(); _showVehicleDetails(vehicle.id); },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                  style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white),
                ),
                const SizedBox(width: 12),
                TextButton(onPressed: _popOverlay, child: const Text('Close')),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () { _popOverlay(); _showEditVehicle(vehicle.id); },
                  style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
                  child: const Text('Edit Vehicle', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    ));
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, color: _primaryColor))),
        ],
      ),
    );
  }

  // ============================================================================
  // DOCUMENT MANAGEMENT
  // ============================================================================
  Widget _buildDocumentTile(Map<String, dynamic> doc, String vehicleId, bool isDriverDoc) {
    final expiryDate = doc['expiryDate'] != null ? DateTime.parse(doc['expiryDate']) : null;
    final isExpired = expiryDate != null && expiryDate.isBefore(DateTime.now());
    final isExpiringSoon = expiryDate != null && expiryDate.isAfter(DateTime.now()) && expiryDate.isBefore(DateTime.now().add(const Duration(days: 30)));
    Color statusColor = isExpired ? Colors.red : isExpiringSoon ? Colors.orange : Colors.green;
    String statusText = isExpired ? 'Expired' : isExpiringSoon ? 'Expiring Soon' : 'Valid';
    final documentUrl = doc['documentUrl'] as String?;
    final hasRealDocument = documentUrl != null && !documentUrl.contains('placeholder') && documentUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: statusColor.withOpacity(0.3)), borderRadius: BorderRadius.circular(8), color: statusColor.withOpacity(0.05)),
      child: Row(
        children: [
          Icon(Icons.description, color: statusColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doc['documentName'] ?? doc['documentType'] ?? 'Unknown Document', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text('Type: ${doc['documentType'] ?? 'N/A'}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                if (expiryDate != null) Text('Expires: ${expiryDate.toString().split(' ')[0]}', style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Chip(
            label: Text(statusText, style: TextStyle(color: statusColor, fontSize: 11)),
            backgroundColor: statusColor.withOpacity(0.1),
            side: BorderSide(color: statusColor.withOpacity(0.3)),
          ),
          if (hasRealDocument) IconButton(icon: const Icon(Icons.download, size: 20), color: _primaryColor, onPressed: () => _viewDocument(documentUrl), tooltip: 'Download'),
          IconButton(icon: const Icon(Icons.delete, size: 20), color: Colors.red.shade700, onPressed: () => _deleteDocument(vehicleId, doc['id'], isDriverDoc), tooltip: 'Delete'),
        ],
      ),
    );
  }

  Future<void> _viewDocument(String documentUrl) async {
    try {
      String fullUrl = documentUrl;
      if (documentUrl.startsWith('/api/')) fullUrl = '${ApiConfig.baseUrl}$documentUrl';
      final Uri url = Uri.parse(fullUrl);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else if (kIsWeb) {
        await launchUrl(url, mode: LaunchMode.platformDefault);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot open document.'), backgroundColor: Colors.orange));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _showAddDocumentDialog(String vehicleId, bool isDriverDoc) async {
    final documentNameController = TextEditingController();
    DateTime? selectedExpiryDate;
    String? selectedDocumentType;
    File? selectedFile;
    Uint8List? selectedFileBytes;
    String? selectedFileName;
    final documentTypes = ['Registration', 'Insurance', 'Permit', 'Fitness Certificate', 'Pollution Certificate', 'Other'];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add Vehicle Document'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedDocumentType,
                  decoration: const InputDecoration(labelText: 'Document Type *', border: OutlineInputBorder()),
                  items: documentTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                  onChanged: (value) => setState(() => selectedDocumentType = value),
                ),
                const SizedBox(height: 16),
                TextField(controller: documentNameController, decoration: const InputDecoration(labelText: 'Document Name *', border: OutlineInputBorder(), hintText: 'e.g., DL-2024-12345')),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [const Icon(Icons.upload_file, color: _primaryColor), const SizedBox(width: 8), const Text('Upload Document File', style: TextStyle(fontWeight: FontWeight.bold))]),
                      const SizedBox(height: 8),
                      if (selectedFileName != null)
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade200)),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: Text(selectedFileName!, overflow: TextOverflow.ellipsis)),
                              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() { selectedFile = null; selectedFileName = null; }), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                            ],
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: () async {
                            FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'], withData: true);
                            if (result != null) {
                              final pickedFile = result.files.single;
                              setState(() {
                                selectedFileName = pickedFile.name;
                                if (kIsWeb) { selectedFileBytes = pickedFile.bytes; selectedFile = null; }
                                else if (pickedFile.path != null) { selectedFile = File(pickedFile.path!); selectedFileBytes = null; }
                              });
                            }
                          },
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: const Text('Choose File'),
                          style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Expiry Date (Optional)'),
                  subtitle: Text(selectedExpiryDate != null ? selectedExpiryDate.toString().split(' ')[0] : 'No expiry date set'),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () async {
                      final date = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 365)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)));
                      if (date != null) setState(() => selectedExpiryDate = date);
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (selectedDocumentType == null || documentNameController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fields')));
                  return;
                }
                Navigator.pop(context);
                await _addDocumentWithFile(vehicleId, selectedDocumentType!, documentNameController.text, selectedExpiryDate, isDriverDoc, selectedFile, selectedFileBytes, selectedFileName);
              },
              style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
              // ============================================================================
// VEHICLE MASTER - CHUNK 3 OF 4
// Paste all 4 chunks into ONE file: vehicle_master.dart
// Chunk 3: lines 887 to 1329 of 1768
// ============================================================================
              child: const Text('Add Document', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addDocumentWithFile(String vehicleId, String documentType, String documentName, DateTime? expiryDate, bool isDriverDoc, File? file, Uint8List? fileBytes, String? fileName) async {
    if (isDriverDoc) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Driver documents managed in Driver Management'), backgroundColor: Colors.orange)); return; }
    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(_primaryColor))));
      final response = await _vehicleService.uploadVehicleDocumentToMongoDB(vehicleId: vehicleId, file: file, bytes: fileBytes, fileName: fileName ?? 'document.pdf', documentType: documentType, documentName: documentName, expiryDate: expiryDate, isDriverDoc: false);
      Navigator.pop(context);
      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message'] ?? 'Document uploaded'), backgroundColor: Colors.green));
        _loadVehicles();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message'] ?? 'Failed to upload'), backgroundColor: Colors.red));
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteDocument(String vehicleId, String documentId, bool isDriverDoc) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Delete Document'),
      content: const Text('Are you sure you want to delete this document?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete', style: TextStyle(color: Colors.white)))],
    ));
    if (confirmed != true) return;
    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
      final response = await _vehicleService.deleteVehicleDocument(vehicleId, documentId, isDriverDoc);
      Navigator.pop(context);
      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message'] ?? 'Document deleted'), backgroundColor: Colors.green));
        _loadVehicles();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message'] ?? 'Failed to delete'), backgroundColor: Colors.red));
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  // ============================================================================
  // EDIT VEHICLE
  // ============================================================================
  void _showEditVehicle(String mongoId) {
    final vehicle = _vehicleData.firstWhere((v) => v.id == mongoId);
    String normalizeVehicleType(String type) {
      const typeMap = {'BUS': 'Bus', 'VAN': 'Van', 'CAR': 'Car', 'TRUCK': 'Truck', 'MINI BUS': 'Mini Bus'};
      return typeMap[type.toUpperCase()] ?? 'Car';
    }
    _pushOverlay(_buildOverlayWrapper(
      title: 'Edit Vehicle',
      child: AddVehicleScreen(
        onCancel: _popOverlay,
        onSave: () { _popOverlay(); _loadVehicles(); },
        isEditMode: true,
        vehicleId: vehicle.id,
        initialData: {
          'registrationNumber': vehicle.registration,
          'vehicleType': normalizeVehicleType(vehicle.type),
          'makeModel': vehicle.model,
          'yearOfManufacture': int.tryParse(vehicle.year) ?? DateTime.now().year,
          'engineType': vehicle.engineType,
          'engineCapacity': double.tryParse(vehicle.engineCapacity) ?? 0.0,
          'seatingCapacity': int.tryParse(vehicle.seatingCapacity) ?? 0,
          'mileage': double.tryParse(vehicle.mileage) ?? 0.0,
          'status': vehicle.status,
          'vendor': vehicle.vendor,
        },
      ),
    ));
  }

  // ============================================================================
  // DELETE VEHICLE
  // ============================================================================
  Future<void> _deleteVehicle(String mongoId, String registrationNumber) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Delete Vehicle'),
      content: Text('Are you sure you want to delete vehicle $registrationNumber? This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Delete')),
      ],
    ));
    if (confirmed != true) return;
    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
      final response = await _vehicleService.deleteVehicle(mongoId);
      Navigator.pop(context);
      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message'] ?? 'Vehicle deleted'), backgroundColor: Colors.green));
        _loadVehicles();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message'] ?? 'Failed to delete'), backgroundColor: Colors.red));
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

// ============================================================================
// VEHICLE MASTER SCREEN - CHUNK 3 OF 4
// Paste after Chunk 2
// ============================================================================

  // ============================================================================
  // MAIN BUILD METHOD
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightBg,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: const Text('Vehicle Master', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: _primaryColor,
        elevation: 0,
        actions: [
          IconButton(onPressed: _loadVehicles, icon: const Icon(Icons.refresh, color: Colors.white), tooltip: 'Refresh'),
        ],
      ),
      body: Stack(
        children: [
          _buildMainContent(),
          ..._overlayStack,
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      children: [
        // ── SEARCH + BASIC FILTERS ROW ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: _cardBg,
            border: Border(bottom: BorderSide(color: _borderColor)),
          ),
          child: Column(
            children: [
              // Row 1: Search + Status + Vendor + Driver + Documents dropdowns
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by ID, registration, model, driver...',
                        prefixIcon: const Icon(Icons.search, size: 20, color: _primaryColor),
                        filled: true,
                        fillColor: _lightBg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _borderColor)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _borderColor)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _primaryColor, width: 2)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchController.clear(); })
                            : null,
                      ),
                      onSubmitted: (_) => _applyFilters(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<String>(
                      value: _selectedStatusFilter.isEmpty ? null : _selectedStatusFilter,
                      decoration: InputDecoration(filled: true, fillColor: _lightBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                      hint: const Text('Status'),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('All Status')),
                        DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                        DropdownMenuItem(value: 'MAINTENANCE', child: Text('Maintenance')),
                        DropdownMenuItem(value: 'INACTIVE', child: Text('Inactive')),
                      ],
                      onChanged: (value) { setState(() => _selectedStatusFilter = value ?? ''); _applyFilters(); },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<String>(
                      value: _selectedVendorFilter.isEmpty ? null : _selectedVendorFilter,
                      decoration: InputDecoration(filled: true, fillColor: _lightBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                      hint: const Text('Vendor'),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('All Vendors')),
                        DropdownMenuItem(value: 'Own Fleet', child: Text('Own Fleet')),
                        DropdownMenuItem(value: 'Vendor', child: Text('Vendor')),
                      ],
                      onChanged: (value) { setState(() => _selectedVendorFilter = value ?? ''); _applyFilters(); },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<String>(
                      value: _selectedDriverFilter.isEmpty ? null : _selectedDriverFilter,
                      decoration: InputDecoration(filled: true, fillColor: _lightBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                      hint: const Text('Driver'),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('All Drivers')),
                        DropdownMenuItem(value: 'Assigned', child: Text('Assigned')),
                        DropdownMenuItem(value: 'Not Assigned', child: Text('Not Assigned')),
                      ],
                      onChanged: (value) { setState(() => _selectedDriverFilter = value ?? ''); _applyFilters(); },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 150,
                    child: DropdownButtonFormField<String>(
                      value: _selectedDocumentFilter.isEmpty ? null : _selectedDocumentFilter,
                      decoration: InputDecoration(filled: true, fillColor: _lightBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                      hint: const Text('Documents'),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('All Documents')),
                        DropdownMenuItem(value: 'Expired', child: Text('Expired')),
                        DropdownMenuItem(value: 'Expiring Soon', child: Text('Expiring Soon')),
                        DropdownMenuItem(value: 'All Valid', child: Text('All Valid')),
                        DropdownMenuItem(value: 'No Documents', child: Text('No Documents')),
                      ],
                      onChanged: (value) { setState(() => _selectedDocumentFilter = value ?? ''); _applyFilters(); },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Row 2: Action buttons
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _applyFilters,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Search'),
                    style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _clearAllFilters,
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('Clear Filters'),
                    style: OutlinedButton.styleFrom(foregroundColor: _primaryColor, side: const BorderSide(color: _primaryColor)),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _loadVehicles,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                    style: OutlinedButton.styleFrom(foregroundColor: _primaryColor, side: const BorderSide(color: _primaryColor)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _toggleAdvancedFilters,
                    icon: AnimatedRotation(
                      turns: _showAdvancedFilters ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: const Icon(Icons.tune, size: 18),
                    ),
                    label: Text(_showAdvancedFilters ? 'Hide Advanced' : 'Advanced Filters'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _showAdvancedFilters ? _darkPrimaryColor : _primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  if (_getActiveFilterCount() > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: _primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: _primaryColor)),
                      child: Row(
                        children: [
                          const Icon(Icons.filter_list, size: 16, color: _primaryColor),
                          const SizedBox(width: 6),
                          Text('${_getActiveFilterCount()} active', style: const TextStyle(color: _primaryColor, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  const SizedBox(width: 12),
                  Text('Total: $_totalVehicles vehicles', style: const TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),

        // ── ADVANCED FILTERS (COLLAPSIBLE) ──
        SizeTransition(
          sizeFactor: _filterAnimation,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.grey.shade50, border: const Border(bottom: BorderSide(color: _borderColor))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.filter_list, size: 20, color: _primaryColor),
                    SizedBox(width: 8),
                    Text('Advanced Filters', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textPrimary)),
                  ],
                ),
                const SizedBox(height: 16),
                
                // ✅ USE CountryStateCityFilter WIDGET (Same as driver_list_page.dart)
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
                    _applyFilters();
                    
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

        // ── STATS + ACTION BUTTONS ROW ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(color: _cardBg, border: Border(bottom: BorderSide(color: _borderColor))),
          child: Row(
            children: [
              _buildStatBadge('Total', _vehicleData.length, Icons.directions_car, _primaryColor),
              const SizedBox(width: 12),
              _buildStatBadge('Active', _vehicleData.where((v) => v.status.toUpperCase() == 'ACTIVE').length, Icons.check_circle, Colors.green.shade700),
              const SizedBox(width: 12),
              _buildStatBadge('Maintenance', _vehicleData.where((v) => v.status.toUpperCase() == 'MAINTENANCE').length, Icons.build, Colors.orange.shade700),
              const SizedBox(width: 12),
              _buildStatBadge('No Driver', _vehicleData.where((v) => v.assignedDriverName == null).length, Icons.person_off, Colors.red.shade700),
              const Spacer(),
              if (_lastRefreshTime != null)
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text('Updated: ${_lastRefreshTime!.hour}:${_lastRefreshTime!.minute.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(width: 16),
                  ],
                ),
              ElevatedButton.icon(
                onPressed: _showAddVehicleScreen,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Add Vehicle'),
                style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _showBulkImportScreen,
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('Bulk Import'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _exportToExcel,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Export Excel'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              ),
            ],
          ),
        ),

        // ── SHOWING COUNT ROW ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: _cardBg,
          // ============================================================================
// VEHICLE MASTER - CHUNK 4 OF 4
// Paste all 4 chunks into ONE file: vehicle_master.dart
// Chunk 4: lines 1330 to 1768 of 1768
// ============================================================================
          child: Row(
            children: [
              Text(
                'Showing ${_filteredVehicleData.isEmpty && !_hasActiveFilters() ? _vehicleData.length : _filteredVehicleData.length} of $_totalVehicles vehicles',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _textPrimary),
              ),
            ],
          ),
        ),

        // ── TABLE ──
        Expanded(child: _buildTableContent()),

        // ── FOOTER ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(color: _cardBg, border: Border(top: BorderSide(color: _borderColor))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Showing ${_filteredVehicleData.isEmpty && !_hasActiveFilters() ? _vehicleData.length : _filteredVehicleData.length} vehicles',
                style: const TextStyle(fontSize: 14, color: _textSecondary, fontWeight: FontWeight.w600),
              ),
              Text('Total: $_totalVehicles vehicles', style: const TextStyle(fontSize: 14, color: _textPrimary, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatBadge(String label, int count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.3))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text('$label: $count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  // ============================================================================
  // TABLE CONTENT
  // ============================================================================
  Widget _buildTableContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(_primaryColor)));
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: Colors.red.shade700), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadVehicles, style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white), child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_vehicleData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('No vehicles found', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton.icon(onPressed: _showAddVehicleScreen, icon: const Icon(Icons.add), label: const Text('Add First Vehicle'), style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white)),
          ],
        ),
      );
    }

    final List<_VehicleData> displayData = _hasActiveFilters() ? _filteredVehicleData : _vehicleData;

    if (displayData.isEmpty && _hasActiveFilters()) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.filter_alt_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('No vehicles match the selected filters', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _clearAllFilters, style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white), child: const Text('Clear Filters')),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Scrollbar(
        controller: _horizontalScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _horizontalScrollController,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: SizedBox(
            width: 2100,
            child: Column(
              children: [
                // TABLE HEADER
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: const BoxDecoration(
                    color: _headerColor,
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
                  ),
                  child: Row(
                    children: [
                      _headerCell('VEHICLE ID', 140),
                      _headerCell('REGISTRATION', 160),
                      _headerCell('TYPE', 100),
                      _headerCell('MODEL', 180),
                      _headerCell('YEAR', 80),
                      _headerCell('VENDOR', 140),
                      _headerCell('SEATS', 80),
                      _headerCell('AVAILABILITY', 130),
                      _headerCell('DRIVER', 160),
                      _headerCell('STATUS', 120),
                      _headerCell('DOCS', 80),
                      _headerCell('MAINTENANCE', 120),
                      _headerCell('ACTIONS', 210),
                    ],
                  ),
                ),
                // TABLE ROWS
                Expanded(
                  child: ListView.separated(
                    itemCount: displayData.length,
                    separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, index) => _buildVehicleRow(displayData[index], index),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerCell(String text, double width) {
    return SizedBox(
      width: width,
      child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

// ============================================================================
// VEHICLE MASTER SCREEN - CHUNK 4 OF 4
// Paste after Chunk 3
// After this chunk, the file is complete - no additional closing braces needed
// ============================================================================

  // ============================================================================
  // VEHICLE DATA ROW
  // ============================================================================
  Widget _buildVehicleRow(_VehicleData vehicle, int index) {
    final seatCapacity = int.tryParse(vehicle.seatingCapacity) ?? 4;
    final driverSeats = vehicle.assignedDriverName != null ? 1 : 0;
    final availableSeats = seatCapacity - driverSeats - vehicle.assignedCustomersCount;

    Color availabilityColor;
    if (availableSeats == 0) availabilityColor = Colors.red.shade700;
    else if (availableSeats <= 1) availabilityColor = Colors.orange.shade700;
    else availabilityColor = Colors.green.shade700;

    final rowColor = index.isEven ? Colors.white : Colors.grey.shade50;

    return InkWell(
      onTap: () => _showVehicleDetails(vehicle.id),
      child: Container(
        color: rowColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // VEHICLE ID
            SizedBox(width: 140, child: Text(vehicle.vehicleId, style: const TextStyle(fontSize: 13, color: _textPrimary))),

            // REGISTRATION
            SizedBox(width: 160, child: Text(vehicle.registration, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textPrimary))),

            // TYPE
            SizedBox(width: 100, child: Text(vehicle.type, style: const TextStyle(fontSize: 13))),

            // MODEL
            SizedBox(width: 180, child: Text(vehicle.model, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),

            // YEAR
            SizedBox(width: 80, child: Text(vehicle.year, style: const TextStyle(fontSize: 13))),

            // VENDOR
            SizedBox(
              width: 140,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    vehicle.vendor != null && vehicle.vendor!.isNotEmpty ? Icons.business : Icons.home_work,
                    size: 14,
                    color: vehicle.vendor != null && vehicle.vendor!.isNotEmpty ? Colors.purple.shade700 : _primaryColor,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      vehicle.vendor ?? 'Own Fleet',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: vehicle.vendor != null && vehicle.vendor!.isNotEmpty ? Colors.purple.shade700 : _primaryColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // SEATS
            SizedBox(
              width: 80,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.airline_seat_recline_normal, size: 14, color: _primaryColor),
                  const SizedBox(width: 4),
                  Text('$seatCapacity', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _primaryColor)),
                ],
              ),
            ),

            // AVAILABILITY
            SizedBox(
              width: 130,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: availabilityColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: availabilityColor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_seat, size: 14, color: availabilityColor),
                    const SizedBox(width: 4),
                    Text('$availableSeats/$seatCapacity', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: availabilityColor)),
                  ],
                ),
              ),
            ),

            // DRIVER
            SizedBox(
              width: 160,
              child: vehicle.assignedDriverName != null
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade200)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person, size: 14, color: Colors.green.shade700),
                          const SizedBox(width: 4),
                          Expanded(child: Text(vehicle.assignedDriverName!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade900), overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    )
                  : Text('Not Assigned', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
            ),

            // STATUS
            SizedBox(width: 120, child: _buildStatusBadge(vehicle.status)),

            // DOCS
            SizedBox(width: 80, child: Center(child: _buildDocumentStatusIcon(vehicle))),

            // MAINTENANCE
            SizedBox(
              width: 120,
              child: InkWell(
                onTap: () => _navigateToMaintenanceManagement(vehicle.id, vehicle.registration),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: vehicle.maintenanceScheduleCount > 0 ? Colors.orange.shade50 : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: vehicle.maintenanceScheduleCount > 0 ? Colors.orange.shade300 : Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.build_circle, size: 16, color: vehicle.maintenanceScheduleCount > 0 ? Colors.orange.shade700 : Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text('${vehicle.maintenanceScheduleCount}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: vehicle.maintenanceScheduleCount > 0 ? Colors.orange.shade700 : Colors.grey.shade600)),
                    ],
                  ),
                ),
              ),
            ),

            // ACTIONS
            SizedBox(
              width: 210,
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                children: [
                  Tooltip(
                    message: 'View Details',
                    child: IconButton(
                      icon: const Icon(Icons.visibility, size: 18),
                      color: _primaryColor,
                      onPressed: () => _showVehicleDetails(vehicle.id),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                  Tooltip(
                    message: 'Edit Vehicle',
                    child: IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      color: Colors.orange.shade700,
                      onPressed: () => _showEditVehicle(vehicle.id),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                  Tooltip(
                    message: 'Add Document',
                    child: IconButton(
                      icon: const Icon(Icons.upload_file, size: 18),
                      color: Colors.blue.shade700,
                      onPressed: () => _showAddDocumentDialog(vehicle.id, false),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                  Tooltip(
                    message: 'Maintenance',
                    child: IconButton(
                      icon: const Icon(Icons.build, size: 18),
                      color: Colors.purple.shade700,
                      onPressed: () => _navigateToMaintenanceManagement(vehicle.id, vehicle.registration),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                  Tooltip(
                    message: 'Delete Vehicle',
                    child: IconButton(
                      icon: const Icon(Icons.delete, size: 18),
                      color: Colors.red.shade700,
                      onPressed: () => _deleteVehicle(vehicle.id, vehicle.registration),
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

  // ============================================================================
  // UI HELPER WIDGETS
  // ============================================================================
  Widget _buildStatusBadge(String status) {
    final String normalized = status.toUpperCase();
    Color bgColor;
    Color textColor;
    switch (normalized) {
      case 'ACTIVE':
        bgColor = Colors.green.shade100;
        textColor = Colors.green.shade800;
        break;
      case 'MAINTENANCE':
        bgColor = Colors.orange.shade100;
        textColor = Colors.orange.shade800;
        break;
      case 'INACTIVE':
        bgColor = Colors.red.shade100;
        textColor = Colors.red.shade800;
        break;
      default:
        bgColor = Colors.grey.shade200;
        textColor = Colors.grey.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6)),
      child: Text(normalized, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }

  Widget _buildDocumentStatusIcon(_VehicleData vehicle) {
    if (vehicle.hasExpiredDocuments) {
      return Tooltip(message: 'Has expired documents', child: Icon(Icons.error, color: Colors.red.shade700, size: 20));
    } else if (vehicle.hasExpiringSoonDocuments) {
      return Tooltip(message: 'Documents expiring soon', child: Icon(Icons.warning, color: Colors.orange.shade700, size: 20));
    } else if (vehicle.documents.isNotEmpty) {
      return Tooltip(message: 'All documents valid', child: Icon(Icons.check_circle, color: Colors.green.shade700, size: 20));
    } else {
      return Tooltip(message: 'No documents uploaded', child: Icon(Icons.info_outline, color: Colors.grey.shade600, size: 20));
    }
  }

} // ✅ END OF _VehicleMasterScreenState CLASS

// ============================================================================
// END OF CHUNK 4 - FILE COMPLETE
// ============================================================================
// HOW TO ASSEMBLE:
// 1. Create vehicle_master.dart
// 2. Paste Chunk 1 (remove last closing brace } at the very end of chunk 1)
// 3. Paste Chunk 2 directly after (remove last closing brace } at the very end)
// 4. Paste Chunk 3 directly after (remove last closing brace } at the very end)
// 5. Paste Chunk 4 directly after - this has the final closing brace
// The file is now complete and ready to use
// ============================================================================