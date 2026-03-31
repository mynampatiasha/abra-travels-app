// ============================================================================
// VEHICLE MASTER SCREEN - REDESIGNED - COMPLETE STANDALONE VERSION
// UI Similar to driver_list_page.dart with matching cell spacing & padding
// Advanced Filters: 2 Rows (Country/State/City + Vehicle-specific)
// Export: Excel, PDF, WhatsApp
// Horizontal Scrolling: Cursor-based
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ============================================================================
// COLOR SCHEME - Same as driver_list_page.dart
// ============================================================================
const Color primaryColor = Color(0xFF1B7FA8);
const Color darkPrimaryColor = Color(0xFF0D5A7A);
const Color accentColor = Color(0xFF2D3E50);
const Color lightBackgroundColor = Color(0xFFF5F9FA);
const Color cardBackgroundColor = Colors.white;
const Color borderColor = Color(0xFFE0E0E0);
const Color textPrimaryColor = Color(0xFF2D3E50);
const Color textSecondaryColor = Color(0xFF6B7280);

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

  Map<String, dynamic> toMap() {
    return {
      'Vehicle ID': vehicleId,
      'Registration Number': registration,
      'Vehicle Type': type,
      'Make & Model': model,
      'Year of Manufacture': year,
      'Engine Type': engineType,
      'Engine Capacity (CC)': engineCapacity,
      'Seating Capacity': seatingCapacity,
      'Seat Availability': seatingCapacity,
      'Mileage (km/l)': mileage,
      'Status': status,
      'Vendor': vendor ?? 'Own Fleet',
      'Assigned Driver': assignedDriverName ?? 'Not Assigned',
      'Assigned Customers': assignedCustomersCount.toString(),
      'Last Service Date': lastServiceDate,
      'Next Service Due': nextServiceDue,
      'Onboarded Date': onboardedDate?.toString().split(' ')[0] ?? '-',
      'Document Status': hasExpiredDocuments ? 'Expired' : hasExpiringSoonDocuments ? 'Expiring' : documents.isNotEmpty ? 'Valid' : 'None',
      'Country': country ?? '-',
      'State': state ?? '-',
      'City': city ?? '-',
    };
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
      try {
        onboarded = DateTime.parse(data['onboardedDate']);
      } catch (e) {
        onboarded = null;
      }
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
          if (data['seatCapacity'] != null) {
            return data['seatCapacity'].toString();
          }
          if (data['seatingCapacity'] != null) {
            return data['seatingCapacity'].toString();
          }
          if (data['capacity'] != null) {
            final capacity = data['capacity'];
            if (capacity is Map && capacity['passengers'] != null) {
              return capacity['passengers'].toString();
            } else if (capacity is num) {
              return capacity.toString();
            } else {
              return capacity.toString();
            }
          }
          return '4';
        } catch (e) {
          return '4';
        }
      })(),
      mileage: (data['specifications']?['mileage'] ?? data['mileage'] ?? '').toString(),
      lastServiceDate: data['maintenance']?['lastServiceDate'] != null 
          ? DateTime.parse(data['maintenance']['lastServiceDate']).toString().split(' ')[0]
          : '-',
      nextServiceDue: data['maintenance']?['nextServiceDue'] != null 
          ? DateTime.parse(data['maintenance']['nextServiceDue']).toString().split(' ')[0]
          : '-',
      assignedDriverName: driverName,
      assignedDriverId: driverId,
      onboardedDate: onboarded,
      documents: vehicleDocs,
      vendor: data['vendor'],
      assignedCustomersCount: assignedCount,
      maintenanceScheduleCount: maintenanceCount,
      country: data['location']?['country'],
      state: data['location']?['state'],
      city: data['location']?['city'],
    );
  }
}

// ============================================================================
// MAIN WIDGET
// ============================================================================
class VehicleMasterScreenRedesigned extends StatefulWidget {
  const VehicleMasterScreenRedesigned({Key? key}) : super(key: key);

  @override
  State<VehicleMasterScreenRedesigned> createState() => _VehicleMasterScreenRedesignedState();
}

class _VehicleMasterScreenRedesignedState extends State<VehicleMasterScreenRedesigned> with TickerProviderStateMixin {
  // Services
  final VehicleService _vehicleService = VehicleService();
  
  // Data
  List<_VehicleData> _vehicleData = [];
  List<_VehicleData> _filteredVehicleData = [];
  
  // Loading & Error States
  bool _isLoading = false;
  String? _errorMessage;
  
  // Search & Filters
  final TextEditingController _searchController = TextEditingController();
  String _selectedStatusFilter = 'All';
  String _selectedDocumentFilter = 'All';
  String _selectedVendorFilter = 'All';
  String _selectedDriverFilter = 'All';
  String _selectedTypeFilter = 'All';
  
  // Advanced Filters
  bool _showAdvancedFilters = false;
  String? _selectedCountry;
  String? _selectedState;
  String? _selectedCity;
  String? _selectedArea;
  DateTime? _startDate;
  DateTime? _endDate;
  
  // Scroll Controllers
  final ScrollController _horizontalScrollController = ScrollController();
  
  // Animation
  late AnimationController _filterAnimationController;
  late Animation<double> _filterAnimation;

  @override
  void initState() {
    super.initState();
    _filterAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _filterAnimation = CurvedAnimation(
      parent: _filterAnimationController,
      curve: Curves.easeInOut,
    );
    _searchController.addListener(_applyFilters);
    _loadVehicles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _horizontalScrollController.dispose();
    _filterAnimationController.dispose();
    super.dispose();
  }

  // ============================================================================
  // DATA LOADING
  // ============================================================================
  Future<void> _loadVehicles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _vehicleService.getAllVehicles();
      
      if (response['success'] == true && response['vehicles'] != null) {
        final List<dynamic> vehiclesJson = response['vehicles'];
        setState(() {
          _vehicleData = vehiclesJson.map((json) => _VehicleData.fromBackend(json)).toList();
          _filteredVehicleData = List.from(_vehicleData);
          _isLoading = false;
        });
      } else {
        throw Exception(response['message'] ?? 'Failed to load vehicles');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading vehicles: $e';
        _isLoading = false;
      });
    }
  }

  // ============================================================================
  // FILTER METHODS
  // ============================================================================
  void _applyFilters() {
    setState(() {
      _filteredVehicleData = _vehicleData.where((vehicle) {
        // Search filter
        final searchTerm = _searchController.text.toLowerCase();
        final matchesSearch = searchTerm.isEmpty ||
            vehicle.registration.toLowerCase().contains(searchTerm) ||
            vehicle.model.toLowerCase().contains(searchTerm) ||
            vehicle.type.toLowerCase().contains(searchTerm) ||
            (vehicle.assignedDriverName?.toLowerCase().contains(searchTerm) ?? false);

        if (!matchesSearch) return false;

        // Status filter
        if (_selectedStatusFilter != 'All' && vehicle.status.toUpperCase() != _selectedStatusFilter.toUpperCase()) {
          return false;
        }

        // Type filter
        if (_selectedTypeFilter != 'All' && vehicle.type.toUpperCase() != _selectedTypeFilter.toUpperCase()) {
          return false;
        }

        // Document filter
        if (_selectedDocumentFilter != 'All') {
          if (_selectedDocumentFilter == 'Expired Documents' && !vehicle.hasExpiredDocuments) return false;
          if (_selectedDocumentFilter == 'Expiring Soon' && !vehicle.hasExpiringSoonDocuments) return false;
          if (_selectedDocumentFilter == 'All Valid' && (vehicle.hasExpiredDocuments || vehicle.hasExpiringSoonDocuments || vehicle.documents.isEmpty)) return false;
          if (_selectedDocumentFilter == 'No Documents' && vehicle.documents.isNotEmpty) return false;
        }

        // Vendor filter
        if (_selectedVendorFilter != 'All') {
          if (_selectedVendorFilter == 'Own Fleet' && vehicle.vendor != null) return false;
          if (_selectedVendorFilter == 'Vendor' && vehicle.vendor == null) return false;
        }

        // Driver filter
        if (_selectedDriverFilter != 'All') {
          if (_selectedDriverFilter == 'Assigned' && vehicle.assignedDriverName == null) return false;
          if (_selectedDriverFilter == 'Not Assigned' && vehicle.assignedDriverName != null) return false;
        }

        // Location filters
        if (_selectedCountry != null && _selectedCountry!.isNotEmpty && vehicle.country != _selectedCountry) return false;
        if (_selectedState != null && _selectedState!.isNotEmpty && vehicle.state != _selectedState) return false;
        if (_selectedCity != null && _selectedCity!.isNotEmpty && vehicle.city != _selectedCity) return false;

        // Date filter
        if (_startDate != null && _endDate != null && vehicle.onboardedDate != null) {
          if (vehicle.onboardedDate!.isBefore(_startDate!) || vehicle.onboardedDate!.isAfter(_endDate!)) {
            return false;
          }
        }

        return true;
      }).toList();
    });
  }

  void _updateFilter(String filterType, String value) {
    setState(() {
      switch (filterType) {
        case 'status':
          _selectedStatusFilter = value;
          break;
        case 'type':
          _selectedTypeFilter = value;
          break;
        case 'document':
          _selectedDocumentFilter = value;
          break;
        case 'vendor':
          _selectedVendorFilter = value;
          break;
        case 'driver':
          _selectedDriverFilter = value;
          break;
      }
    });
    _applyFilters();
  }

  void _clearAllFilters() {
    setState(() {
      _searchController.clear();
      _selectedStatusFilter = 'All';
      _selectedDocumentFilter = 'All';
      _selectedVendorFilter = 'All';
      _selectedDriverFilter = 'All';
      _selectedTypeFilter = 'All';
      _selectedCountry = null;
      _selectedState = null;
      _selectedCity = null;
      _selectedArea = null;
      _startDate = null;
      _endDate = null;
    });
    _applyFilters();
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

  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedStatusFilter != 'All') count++;
    if (_selectedDocumentFilter != 'All') count++;
    if (_selectedVendorFilter != 'All') count++;
    if (_selectedDriverFilter != 'All') count++;
    if (_selectedTypeFilter != 'All') count++;
    if (_selectedCountry != null && _selectedCountry!.isNotEmpty) count++;
    if (_selectedState != null && _selectedState!.isNotEmpty) count++;
    if (_selectedCity != null && _selectedCity!.isNotEmpty) count++;
    if (_startDate != null && _endDate != null) count++;
    return count;
  }

  // ============================================================================
  // EXCEL EXPORT
  // ============================================================================
  Future<void> _exportToExcel() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                ),
                SizedBox(height: 16),
                Text(
                  'Generating Excel file...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      var excelFile = excel.Excel.createExcel();
      var sheet = excelFile['Vehicles'];

      final headers = [
        'Vehicle ID',
        'Registration Number',
        'Vehicle Type',
        'Make & Model',
        'Year of Manufacture',
        'Engine Type',
        'Engine Capacity (CC)',
        'Seating Capacity',
        'Seat Availability',
        'Mileage (km/l)',
        'Status',
        'Vendor',
        'Assigned Driver',
        'Assigned Customers',
        'Last Service Date',
        'Next Service Due',
        'Onboarded Date',
        'Document Status',
        'Country',
        'State',
        'City',
      ];

      for (var i = 0; i < headers.length; i++) {
        var cell = sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = excel.TextCellValue(headers[i]);
        cell.cellStyle = excel.CellStyle(
          bold: true,
          backgroundColorHex: excel.ExcelColor.fromHexString('#1B7FA8'),
          fontColorHex: excel.ExcelColor.white,
        );
      }

      for (var i = 0; i < _filteredVehicleData.length; i++) {
        final vehicle = _filteredVehicleData[i];
        final vehicleMap = vehicle.toMap();
        
        for (var j = 0; j < headers.length; j++) {
          var cell = sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: j, rowIndex: i + 1));
          final value = vehicleMap[headers[j]] ?? '';
          cell.value = excel.TextCellValue(value.toString());
        }
      }

      for (var i = 0; i < headers.length; i++) {
        sheet.setColumnWidth(i, 20);
      }

      var fileBytes = excelFile.save();

      if (fileBytes == null) {
        throw Exception('Failed to generate Excel file');
      }

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
            SnackBar(
              content: Text('Excel file saved to: $filePath'),
              backgroundColor: primaryColor,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Open',
                textColor: Colors.white,
                onPressed: () async {
                  final uri = Uri.file(filePath);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
              ),
            ),
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully exported ${_filteredVehicleData.length} vehicles to Excel'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting to Excel: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ============================================================================
  // PDF GENERATION
  // ============================================================================
  Future<void> _generatePDF() async {
    try {
      if (_filteredVehicleData.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No vehicles to export'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                ),
                SizedBox(height: 16),
                Text(
                  'Generating PDF...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final pdf = pw.Document();

      String reportTitle = 'Vehicle Master Report';
      String dateRangeText = 'All Time';
      if (_startDate != null && _endDate != null) {
        dateRangeText = '${DateFormat('MMM dd, yyyy').format(_startDate!)} - ${DateFormat('MMM dd, yyyy').format(_endDate!)}';
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(36),
          header: (pw.Context ctx) => pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.blue900, width: 2)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Fleet Management System',
                    style: pw.TextStyle(fontSize: 10, color: PdfColors.blue900, fontWeight: pw.FontWeight.bold)),
                pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
              ],
            ),
          ),
          footer: (pw.Context ctx) => pw.Container(
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            ),
            child: pw.Center(
              child: pw.Text(
                'CONFIDENTIAL - Fleet Management System Report',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
              ),
            ),
          ),
          build: (pw.Context context) => [
            // Title Header
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue900,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(reportTitle,
                      style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Date Range: $dateRangeText',
                              style: const pw.TextStyle(fontSize: 11, color: PdfColors.white)),
                          pw.SizedBox(height: 4),
                          pw.Text('Total Vehicles: ${_filteredVehicleData.length}',
                              style: const pw.TextStyle(fontSize: 11, color: PdfColors.white)),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('Generated: ${DateFormat('MMM dd, yyyy').format(DateTime.now())}',
                              style: const pw.TextStyle(fontSize: 10, color: PdfColors.white)),
                          pw.SizedBox(height: 4),
                          pw.Text('Time: ${DateFormat('HH:mm').format(DateTime.now())}',
                              style: const pw.TextStyle(fontSize: 10, color: PdfColors.white)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Vehicle Table
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.5),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(1.5),
                3: const pw.FlexColumnWidth(2),
                4: const pw.FlexColumnWidth(1),
                5: const pw.FlexColumnWidth(1.5),
                6: const pw.FlexColumnWidth(1.5),
                7: const pw.FlexColumnWidth(1.5),
              },
              children: [
                // Header Row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    _pdfTableCell('Reg No', isHeader: true),
                    _pdfTableCell('Make & Model', isHeader: true),
                    _pdfTableCell('Type', isHeader: true),
                    _pdfTableCell('Driver', isHeader: true),
                    _pdfTableCell('Status', isHeader: true),
                    _pdfTableCell('Capacity', isHeader: true),
                    _pdfTableCell('Last Service', isHeader: true),
                    _pdfTableCell('Documents', isHeader: true),
                  ],
                ),
                // Data Rows
                ..._filteredVehicleData.map((vehicle) {
                  final docStatus = vehicle.hasExpiredDocuments
                      ? 'Expired'
                      : vehicle.hasExpiringSoonDocuments
                          ? 'Expiring'
                          : vehicle.documents.isNotEmpty
                              ? 'Valid'
                              : 'None';
                  
                  return pw.TableRow(
                    children: [
                      _pdfTableCell(vehicle.registration),
                      _pdfTableCell(vehicle.model),
                      _pdfTableCell(vehicle.type),
                      _pdfTableCell(vehicle.assignedDriverName ?? 'Not Assigned'),
                      _pdfTableCell(vehicle.status),
                      _pdfTableCell(vehicle.seatingCapacity),
                      _pdfTableCell(vehicle.lastServiceDate),
                      _pdfTableCell(docStatus),
                    ],
                  );
                }).toList(),
              ],
            ),
          ],
        ),
      );

      if (mounted) Navigator.pop(context);

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ PDF generated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  pw.Widget _pdfTableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 9 : 8,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader ? PdfColors.black : PdfColors.grey800,
        ),
        textAlign: isHeader ? pw.TextAlign.center : pw.TextAlign.left,
      ),
    );
  }

  // ============================================================================
  // WHATSAPP SHARE
  // ============================================================================
  Future<void> _shareViaWhatsApp() async {
    try {
      if (_filteredVehicleData.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No vehicles to share'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Build WhatsApp message
      String message = '🚗 *Vehicle Master Report*\n\n';
      message += '📅 Generated: ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())}\n';
      
      if (_startDate != null && _endDate != null) {
        message += '📆 Period: ${DateFormat('MMM dd, yyyy').format(_startDate!)} - ${DateFormat('MMM dd, yyyy').format(_endDate!)}\n';
      }
      
      message += '\n━━━━━━━━━━━━━━━━━━━━\n\n';

      // Vehicle Statistics
      message += '📊 *VEHICLE STATISTICS*\n';
      message += '• Total Vehicles: ${_filteredVehicleData.length}\n';
      
      final activeVehicles = _filteredVehicleData.where((v) => v.status.toUpperCase() == 'ACTIVE').length;
      final maintenanceVehicles = _filteredVehicleData.where((v) => v.status.toUpperCase() == 'MAINTENANCE').length;
      final inactiveVehicles = _filteredVehicleData.where((v) => v.status.toUpperCase() == 'INACTIVE').length;
      
      message += '• Active: $activeVehicles\n';
      message += '• Maintenance: $maintenanceVehicles\n';
      message += '• Inactive: $inactiveVehicles\n\n';

      // Document Status
      final expiredDocs = _filteredVehicleData.where((v) => v.hasExpiredDocuments).length;
      final expiringSoon = _filteredVehicleData.where((v) => v.hasExpiringSoonDocuments).length;
      
      message += '📄 *DOCUMENT STATUS*\n';
      message += '• Expired: $expiredDocs\n';
      message += '• Expiring Soon: $expiringSoon\n\n';

      // Driver Assignment
      final assignedDrivers = _filteredVehicleData.where((v) => v.assignedDriverName != null).length;
      final unassignedDrivers = _filteredVehicleData.length - assignedDrivers;
      
      message += '👨‍✈️ *DRIVER ASSIGNMENT*\n';
      message += '• Assigned: $assignedDrivers\n';
      message += '• Unassigned: $unassignedDrivers\n\n';

      message += '━━━━━━━━━━━━━━━━━━━━\n';
      message += '📱 Generated by Abra Fleet Management';

      // URL encode the message
      final encodedMessage = Uri.encodeComponent(message);
      
      // Create WhatsApp URL
      final String whatsappUrl;
      if (kIsWeb) {
        whatsappUrl = 'https://web.whatsapp.com/send?text=$encodedMessage';
      } else {
        whatsappUrl = 'whatsapp://send?text=$encodedMessage';
      }

      print('📱 Opening WhatsApp with vehicle report...');

      final uri = Uri.parse(whatsappUrl);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Opening WhatsApp...'),
              backgroundColor: Color(0xFF25D366),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw 'WhatsApp is not installed or cannot be opened';
      }
    } catch (e) {
      print('❌ WhatsApp Share Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open WhatsApp: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // ============================================================================
  // END OF PART 3
  // Continue with Part 4 (UI Build Methods)
  // ============================================================================

  // ============================================================================
  // MAIN BUILD METHOD
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackgroundColor,
      appBar: AppBar(
        title: const Text('Vehicle Master'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadVehicles,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchAndFilterBar(),
          if (_showAdvancedFilters) _buildAdvancedFiltersSection(),
          _buildExportButtonsRow(),
          Expanded(child: _buildVehicleTable()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddVehicleScreen(),
        backgroundColor: primaryColor,
        icon: const Icon(Icons.add),
        label: const Text('Add Vehicle'),
      ),
    );
  }

  // ============================================================================
  // SEARCH & FILTER BAR
  // ============================================================================
  Widget _buildSearchAndFilterBar() {
    return Container(
      color: cardBackgroundColor,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Search Field
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search vehicles...',
                    prefixIcon: const Icon(Icons.search, color: textSecondaryColor),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              // Status Dropdown
              _buildFilterDropdown(
                value: _selectedStatusFilter,
                items: ['All', 'Active', 'Maintenance', 'Inactive'],
                onChanged: (value) => _updateFilter('status', value!),
                width: 150,
              ),
              const SizedBox(width: 12),
              
              // Type Dropdown
              _buildFilterDropdown(
                value: _selectedTypeFilter,
                items: ['All', 'Sedan', 'SUV', 'Van', 'Bus', 'Truck'],
                onChanged: (value) => _updateFilter('type', value!),
                width: 150,
              ),
              const SizedBox(width: 12),
              
              // Document Dropdown
              _buildFilterDropdown(
                value: _selectedDocumentFilter,
                items: ['All', 'Expired Documents', 'Expiring Soon', 'All Valid', 'No Documents'],
                onChanged: (value) => _updateFilter('document', value!),
                width: 150,
              ),
              const SizedBox(width: 12),
              
              // Search Button
              ElevatedButton.icon(
                onPressed: _applyFilters,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Search'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 8),
              
              // Clear Button
              OutlinedButton.icon(
                onPressed: _clearAllFilters,
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Clear'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: textSecondaryColor,
                  side: const BorderSide(color: borderColor),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 8),
              
              // Refresh Button
              IconButton(
                onPressed: _loadVehicles,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                color: primaryColor,
              ),
              const SizedBox(width: 8),
              
              // Advanced Filters Button
              Stack(
                children: [
                  ElevatedButton.icon(
                    onPressed: _toggleAdvancedFilters,
                    icon: Icon(_showAdvancedFilters ? Icons.expand_less : Icons.expand_more, size: 18),
                    label: const Text('Advanced'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _showAdvancedFilters ? darkPrimaryColor : primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  if (_getActiveFilterCount() > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                        child: Text(
                          '${_getActiveFilterCount()}',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          
          // Total Count
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Total Vehicles: ${_vehicleData.length}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textPrimaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required double width,
  }) {
    return Container(
      width: width,
      child: DropdownButtonFormField<String>(
        value: value,
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: items.map((item) => DropdownMenuItem(value: item, child: Text(item, style: const TextStyle(fontSize: 14)))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  // ============================================================================
  // ADVANCED FILTERS SECTION (2 ROWS)
  // ============================================================================
  Widget _buildAdvancedFiltersSection() {
    return SizeTransition(
      sizeFactor: _filterAnimation,
      child: Container(
        color: Colors.grey[50],
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_alt, size: 20, color: primaryColor),
                const SizedBox(width: 8),
                const Text(
                  'Advanced Filters',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textPrimaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // ROW 1: Country/State/City Filters
            CountryStateCityFilter(
              initialFromDate: _startDate,
              initialToDate: _endDate,
              initialCountry: _selectedCountry,
              initialState: _selectedState,
              initialCity: _selectedCity,
              initialLocalArea: _selectedArea,
              onFilterApplied: (filters) {
                setState(() {
                  _startDate = filters['fromDate'];
                  _endDate = filters['toDate'];
                  _selectedCountry = filters['country'];
                  _selectedState = filters['state'];
                  _selectedCity = filters['city'];
                  _selectedArea = filters['localArea'];
                });
                _applyFilters();
              },
            ),
            
            const SizedBox(height: 16),
            
            // ROW 2: Vehicle-Specific Filters
            Row(
              children: [
                Expanded(
                  child: _buildFilterDropdown(
                    value: _selectedVendorFilter,
                    items: ['All', 'Own Fleet', 'Vendor'],
                    onChanged: (value) => _updateFilter('vendor', value!),
                    width: double.infinity,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildFilterDropdown(
                    value: _selectedDriverFilter,
                    items: ['All', 'Assigned', 'Not Assigned'],
                    onChanged: (value) => _updateFilter('driver', value!),
                    width: double.infinity,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _applyFilters,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Apply Filters'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // EXPORT BUTTONS ROW
  // ============================================================================
  Widget _buildExportButtonsRow() {
    return Container(
      color: cardBackgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Text(
            'Showing ${_filteredVehicleData.length} of ${_vehicleData.length} vehicles',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textPrimaryColor,
            ),
          ),
          const Spacer(),
          
          // Excel Button
          ElevatedButton.icon(
            onPressed: _exportToExcel,
            icon: const Icon(Icons.table_chart, size: 18),
            label: const Text('Excel', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 10),
          
          // PDF Button
          ElevatedButton.icon(
            onPressed: _generatePDF,
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: const Text('PDF', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 10),
          
          // WhatsApp Button
          ElevatedButton.icon(
            onPressed: _shareViaWhatsApp,
            icon: const Icon(Icons.share, size: 18),
            label: const Text('WhatsApp', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // VEHICLE TABLE
  // ============================================================================
  Widget _buildVehicleTable() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: primaryColor),
      );
    }
    
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadVehicles,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
            ),
          ],
        ),
      );
    }
    
    if (_filteredVehicleData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_car_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No vehicles found', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _clearAllFilters,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear Filters'),
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
            ),
          ],
        ),
      );
    }
    
    return Container(
      color: cardBackgroundColor,
      child: Column(
        children: [
          _buildTableHeader(),
          Expanded(child: _buildTableBody()),
        ],
      ),
    );
  }

  // ============================================================================
  // TABLE HEADER
  // ============================================================================
  Widget _buildTableHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF34495E),
      ),
      child: Scrollbar(
        controller: _horizontalScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _horizontalScrollController,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildHeaderCell('REG NO', width: 150),
              _buildHeaderCell('MAKE & MODEL', width: 200),
              _buildHeaderCell('TYPE', width: 120),
              _buildHeaderCell('STATUS', width: 120),
              _buildHeaderCell('DRIVER', width: 180),
              _buildHeaderCell('CAPACITY', width: 100),
              _buildHeaderCell('DOCUMENTS', width: 120),
              _buildHeaderCell('ACTIONS', width: 220),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String text, {required double width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ============================================================================
  // TABLE BODY - FIXED WITH SYNCHRONIZED HORIZONTAL SCROLLING
  // ============================================================================
  Widget _buildTableBody() {
    return Listener(
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
          width: 1310, // Total width of all columns
          child: ListView.separated(
            itemCount: _filteredVehicleData.length,
            separatorBuilder: (context, index) => const Divider(height: 1, color: borderColor),
            itemBuilder: (context, index) {
              final vehicle = _filteredVehicleData[index];
              return _buildTableRowFixed(vehicle);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTableRow(_VehicleData vehicle) {
    return InkWell(
      onTap: () => _showVehicleDetails(vehicle.id),
      child: SingleChildScrollView(
        controller: _horizontalScrollController,
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), // MORE PADDING
          decoration: const BoxDecoration(
            color: cardBackgroundColor,
          ),
          child: Row(
            children: [
              _buildDataCell(vehicle.registration, width: 150),
              _buildDataCell(vehicle.model, width: 200),
              _buildDataCell(vehicle.type, width: 120),
              _buildStatusBadge(vehicle.status, width: 120),
              _buildDataCell(vehicle.assignedDriverName ?? 'Not Assigned', width: 180),
              _buildDataCell(vehicle.seatingCapacity, width: 100),
              _buildDocumentStatusIcon(vehicle, width: 120),
              _buildActionButtons(vehicle, width: 220),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ NEW: FIXED-WIDTH ROW FOR SYNCHRONIZED SCROLLING
  Widget _buildTableRowFixed(_VehicleData vehicle) {
    return InkWell(
      onTap: () => _showVehicleDetails(vehicle.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18), // Match driver list padding
        decoration: const BoxDecoration(
          color: cardBackgroundColor,
        ),
        child: Row(
          children: [
            _buildDataCell(vehicle.registration, width: 150),
            _buildDataCell(vehicle.model, width: 200),
            _buildDataCell(vehicle.type, width: 120),
            _buildStatusBadge(vehicle.status, width: 120),
            _buildDataCell(vehicle.assignedDriverName ?? 'Not Assigned', width: 180),
            _buildDataCell(vehicle.seatingCapacity, width: 100),
            _buildDocumentStatusIcon(vehicle, width: 120),
            _buildActionButtons(vehicle, width: 220),
          ],
        ),
      ),
    );
  }

  Widget _buildDataCell(String text, {required double width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12), // MORE SPACING
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          color: textPrimaryColor,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildStatusBadge(String status, {required double width}) {
    Color bgColor;
    Color textColor;
    
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        bgColor = Colors.green.shade100;
        textColor = Colors.green.shade800;
        break;
      case 'MAINTENANCE':
        bgColor = Colors.orange.shade100;
        textColor = Colors.orange.shade800;
        break;
      case 'INACTIVE':
        bgColor = Colors.grey.shade200;
        textColor = Colors.grey.shade800;
        break;
      default:
        bgColor = Colors.blue.shade100;
        textColor = Colors.blue.shade800;
    }
    
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          status.toUpperCase(),
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildDocumentStatusIcon(_VehicleData vehicle, {required double width}) {
    IconData icon;
    Color color;
    String tooltip;
    
    if (vehicle.hasExpiredDocuments) {
      icon = Icons.error;
      color = Colors.red;
      tooltip = 'Expired Documents';
    } else if (vehicle.hasExpiringSoonDocuments) {
      icon = Icons.warning;
      color = Colors.orange;
      tooltip = 'Expiring Soon';
    } else if (vehicle.documents.isNotEmpty) {
      icon = Icons.check_circle;
      color = Colors.green;
      tooltip = 'All Valid';
    } else {
      icon = Icons.info;
      color = Colors.grey;
      tooltip = 'No Documents';
    }
    
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Tooltip(
        message: tooltip,
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _buildActionButtons(_VehicleData vehicle, {required double width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(
            icon: Icons.visibility,
            color: Colors.blue,
            tooltip: 'View Details',
            onPressed: () => _showVehicleDetails(vehicle.id),
          ),
          _buildActionButton(
            icon: Icons.edit,
            color: Colors.orange,
            tooltip: 'Edit Vehicle',
            onPressed: () => _showEditVehicle(vehicle.id),
          ),
          _buildActionButton(
            icon: Icons.delete,
            color: Colors.red,
            tooltip: 'Delete Vehicle',
            onPressed: () => _deleteVehicle(vehicle.id, vehicle.registration),
          ),
          _buildActionButton(
            icon: Icons.build,
            color: Colors.purple,
            tooltip: 'Maintenance',
            onPressed: () => _navigateToMaintenanceManagement(vehicle.id, vehicle.registration),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }

  // ============================================================================
  // HELPER METHODS FOR DIALOGS
  // ============================================================================
  void _showAddVehicleScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddVehicleScreen(
          onCancel: () => Navigator.pop(context),
          onSave: () {
            Navigator.pop(context);
            _loadVehicles();
          },
        ),
      ),
    );
  }

  void _showBulkImportScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BulkImportVehiclesScreen(
          onCancel: () => Navigator.pop(context),
          onImportComplete: () {
            Navigator.pop(context);
            _loadVehicles();
          },
        ),
      ),
    );
  }

  void _showVehicleDetails(String vehicleId) {
    // Implement vehicle details dialog
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening details for vehicle: $vehicleId')),
    );
  }

  void _showEditVehicle(String vehicleId) {
    final vehicle = _vehicleData.firstWhere((v) => v.id == vehicleId);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddVehicleScreen(
          onCancel: () => Navigator.pop(context),
          onSave: () {
            Navigator.pop(context);
            _loadVehicles();
          },
          isEditMode: true,
          vehicleId: vehicle.id,
          initialData: {
            'registrationNumber': vehicle.registration,
            'vehicleType': vehicle.type,
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
      ),
    );
  }

  Future<void> _deleteVehicle(String vehicleId, String registration) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Vehicle'),
        content: Text('Are you sure you want to delete vehicle $registration?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final response = await _vehicleService.deleteVehicle(vehicleId);
        if (response['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vehicle deleted successfully'), backgroundColor: Colors.green),
          );
          _loadVehicles();
        } else {
          throw Exception(response['message'] ?? 'Failed to delete vehicle');
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _navigateToMaintenanceManagement(String vehicleId, String vehicleNumber) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MaintenanceManagementScreen(),
      ),
    ).then((_) => _loadVehicles());
  }

  bool _hasActiveFilters() {
    return _selectedStatusFilter != 'All' ||
        _selectedDocumentFilter != 'All' ||
        _selectedVendorFilter != 'All' ||
        _selectedDriverFilter != 'All' ||
        _selectedTypeFilter != 'All' ||
        (_selectedCountry != null && _selectedCountry!.isNotEmpty) ||
        (_selectedState != null && _selectedState!.isNotEmpty) ||
        (_selectedCity != null && _selectedCity!.isNotEmpty) ||
        (_startDate != null && _endDate != null);
  }
}

// ============================================================================
// END OF COMPLETE FILE
// ============================================================================
