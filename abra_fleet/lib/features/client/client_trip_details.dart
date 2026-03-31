// lib/features/client/presentation/screens/client_trip_details.dart
// ============================================================================
// CLIENT TRIP DETAILS - Complete Trip Information for Client Users
// ============================================================================
// ✅ Auto-filters by client domain (via API)
// ✅ PDF & Excel download
// ✅ Call driver functionality
// ✅ WhatsApp driver functionality (Web & Mobile)
// ✅ Live tracking (if trip started)
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/features/admin/admin_live_location_whole_vehicles.dart';

// PDF generation imports
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Excel generation imports
import 'package:excel/excel.dart' as excel_pkg;
import 'dart:typed_data';

class ClientTripDetails extends StatefulWidget {
  final String tripId;

  const ClientTripDetails({
    super.key,
    required this.tripId,
  });

  @override
  State<ClientTripDetails> createState() => _ClientTripDetailsState();
}

class _ClientTripDetailsState extends State<ClientTripDetails> {
  // ========================================================================
  // STATE VARIABLES
  // ========================================================================
  
  Map<String, dynamic>? _tripDetails;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    debugPrint('🔍 ClientTripDetails: initState for trip ${widget.tripId}');
    _loadTripDetails();
  }

  // ========================================================================
  // API METHODS
  // ========================================================================

  Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (e) {
      debugPrint('❌ Error getting token: $e');
      return null;
    }
  }

  Map<String, dynamic> _parseAndValidateTripData(Map<String, dynamic> rawData) {
    return {
      '_id': rawData['_id'],
      'tripNumber': rawData['tripNumber'] ?? 'N/A',
      'tripGroupId': rawData['tripGroupId'],
      'tripType': rawData['tripType'] ?? 'unknown',
      
      'vehicle': {
        '_id': rawData['vehicle']?['_id'] ?? rawData['vehicleId'],
        'vehicleNumber': rawData['vehicleNumber'] ?? rawData['vehicle']?['vehicleNumber'] ?? 'Unknown',
        'vehicleName': rawData['vehicleName'] ?? rawData['vehicle']?['vehicleName'] ?? '',
        'registrationNumber': rawData['vehicle']?['registrationNumber'] ?? rawData['vehicleNumber'] ?? 'N/A',
        'capacity': rawData['vehicle']?['capacity']?.toString() ?? 'N/A',
        'fuelType': rawData['vehicle']?['fuelType'] ?? 'N/A',
        'manufacturer': rawData['vehicle']?['manufacturer'] ?? 'N/A',
        'model': rawData['vehicle']?['model'] ?? 'N/A',
      },
      
      'driver': {
        '_id': rawData['driver']?['_id'] ?? rawData['driverId'],
        'driverId': rawData['driver']?['driverId'] ?? rawData['driverId']?.toString() ?? 'N/A',
        'name': rawData['driverName'] ?? rawData['driver']?['name'] ?? 'Unknown Driver',
        'phone': rawData['driverPhone'] ?? rawData['driver']?['phone'] ?? '',
        'email': rawData['driverEmail'] ?? rawData['driver']?['email'] ?? '',
        'licenseNumber': rawData['driver']?['licenseNumber'] ?? 'N/A',
        'experience': rawData['driver']?['experience']?.toString() ?? 'N/A',
      },
      
      'scheduledDate': rawData['scheduledDate'] ?? '',
      'startTime': rawData['startTime'] ?? '',
      'endTime': rawData['endTime'] ?? '',
      'actualStartTime': rawData['actualStartTime'],
      'actualEndTime': rawData['actualEndTime'],
      
      'status': rawData['status'] ?? 'assigned',
      'currentStopIndex': rawData['currentStopIndex'] ?? 0,
      'progress': rawData['progress'] ?? 0,
      
      'totalStops': rawData['totalStops'] ?? 0,
      'completedStops': rawData['completedStops'] ?? 0,
      'pickupStops': rawData['pickupStops'] ?? 0,
      'dropStops': rawData['dropStops'] ?? 0,
      
      'totalDistance': rawData['totalDistance'] ?? 0,
      'totalTime': rawData['totalTime'] ?? 0,
      'estimatedDuration': rawData['estimatedDuration'] ?? 0,
      
      'metrics': _parseMetrics(rawData['metrics']),
      
      'startOdometer': rawData['startOdometer'],
      'endOdometer': rawData['endOdometer'],
      'actualDistance': rawData['actualDistance'] ?? 0,
      
      'stops': _parseStopsList(rawData['stops']),
      'customerFeedback': _parseFeedbackList(rawData['customerFeedback']),
      
      'currentLocation': rawData['currentLocation'],
      'locationHistory': _parseLocationHistory(rawData['locationHistory']),
      
      'assignedAt': rawData['assignedAt'],
      'createdAt': rawData['createdAt'],
      'updatedAt': rawData['updatedAt'],
    };
  }

  Map<String, dynamic> _parseMetrics(dynamic metricsData) {
    if (metricsData == null || metricsData is! Map<String, dynamic>) {
      return {'onTimeStops': 0, 'delayedStops': 0, 'averageDelay': 0};
    }
    return {
      'onTimeStops': metricsData['onTimeStops'] ?? 0,
      'delayedStops': metricsData['delayedStops'] ?? 0,
      'averageDelay': metricsData['averageDelay'] ?? 0,
    };
  }

  List<Map<String, dynamic>> _parseStopsList(dynamic stopsData) {
    if (stopsData == null || stopsData is! List) return [];
    try {
      return (stopsData as List).map((stop) => stop as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('⚠️  Error parsing stops: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> _parseFeedbackList(dynamic feedbackData) {
    if (feedbackData == null || feedbackData is! List) return [];
    try {
      return (feedbackData as List).map((fb) => fb as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('⚠️  Error parsing feedback: $e');
      return [];
    }
  }

  List<dynamic> _parseLocationHistory(dynamic locationData) {
    if (locationData == null || locationData is! List) return [];
    return locationData as List;
  }

  dynamic _safeGetNestedValue(Map<String, dynamic>? map, List<String> keys, dynamic defaultValue) {
    if (map == null) return defaultValue;
    dynamic current = map;
    for (final key in keys) {
      if (current is Map<String, dynamic> && current.containsKey(key)) {
        current = current[key];
      } else {
        return defaultValue;
      }
    }
    return current ?? defaultValue;
  }

  Future<void> _loadTripDetails() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final token = await _getToken();
      if (token == null) {
        throw Exception('No authentication token found');
      }

      // ✅ USE CLIENT ENDPOINT
      final url = '${ApiConfig.baseUrl}/api/client/trips/${widget.tripId}/details';
      
      debugPrint('🔍 Fetching client trip details: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final tripData = data['data'] as Map<String, dynamic>;
          
          setState(() {
            _tripDetails = _parseAndValidateTripData(tripData);
            _isLoading = false;
          });

          debugPrint('✅ Client trip details loaded');
          debugPrint('   Trip: ${_tripDetails!['tripNumber']}');
          debugPrint('   Vehicle: ${_safeGetNestedValue(_tripDetails, ['vehicle', 'vehicleNumber'], 'N/A')}');
          debugPrint('   Driver: ${_safeGetNestedValue(_tripDetails, ['driver', 'name'], 'N/A')}');
        } else {
          throw Exception(data['message'] ?? 'Failed to load trip details');
        }
      } else if (response.statusCode == 403) {
        throw Exception('Access denied. This trip does not belong to your organization.');
      } else if (response.statusCode == 404) {
        throw Exception('Trip not found');
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading trip details: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Failed to load trip details: $e';
        _isLoading = false;
      });
    }
  }

  // ========================================================================
  // DOWNLOAD METHODS - PDF & EXCEL
  // ========================================================================

  Future<void> _downloadPDF() async {
    if (_tripDetails == null) return;
    
    try {
      setState(() => _isDownloading = true);
      
      debugPrint('📊 Generating PDF report...');
      
      final pdf = await _generatePdfReport();
      await _savePdf(pdf, _tripDetails!['tripNumber']);
      
      _showSnackBar('PDF downloaded successfully');
    } catch (e) {
      debugPrint('❌ Error generating PDF: $e');
      _showSnackBar('Failed to generate PDF: $e', isError: true);
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  Future<void> _downloadExcel() async {
    if (_tripDetails == null) return;
    
    try {
      setState(() => _isDownloading = true);
      
      debugPrint('📊 Generating Excel report...');
      
      final excelFile = await _generateExcelReport();
      await _saveExcel(excelFile, _tripDetails!['tripNumber']);
      
      _showSnackBar('Excel downloaded successfully');
    } catch (e) {
      debugPrint('❌ Error generating Excel: $e');
      _showSnackBar('Failed to generate Excel: $e', isError: true);
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  // ========================================================================
  // PDF GENERATION
  // ========================================================================

  Future<pw.Document> _generatePdfReport() async {
    final pdf = pw.Document();
    
    final vehicle = _tripDetails!['vehicle'] as Map<String, dynamic>;
    final driver = _tripDetails!['driver'] as Map<String, dynamic>;
    final stops = _tripDetails!['stops'] as List<dynamic>;
    final metrics = _tripDetails!['metrics'] as Map<String, dynamic>;
    final feedback = _tripDetails!['customerFeedback'] as List<dynamic>;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            // Header
            pw.Header(
              level: 0,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('TRIP REPORT', style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 8),
                  pw.Text('Trip Number: ${_tripDetails!['tripNumber']}',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text('Generated: ${DateFormat('MMM dd, yyyy - HH:mm').format(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                  pw.Divider(thickness: 2),
                ],
              ),
            ),
            
            pw.SizedBox(height: 20),
            
            // Trip Information
            _buildPdfSection('TRIP INFORMATION', [
              ['Status', _capitalizeStatus(_tripDetails!['status'])],
              ['Type', _tripDetails!['tripType'] ?? 'N/A'],
              ['Scheduled Date', _tripDetails!['scheduledDate'] ?? 'N/A'],
              ['Scheduled Time', '${_tripDetails!['startTime']} - ${_tripDetails!['endTime']}'],
              if (_tripDetails!['actualStartTime'] != null)
                ['Actual Start', _formatDateTime(_tripDetails!['actualStartTime'])],
              if (_tripDetails!['actualEndTime'] != null)
                ['Actual End', _formatDateTime(_tripDetails!['actualEndTime'])],
            ]),
            
            pw.SizedBox(height: 20),
            
            // Vehicle and Driver
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _buildPdfSection('VEHICLE', [
                    ['Number', vehicle['vehicleNumber'] ?? 'Unknown'],
                    ['Name', vehicle['vehicleName'] ?? 'N/A'],
                    ['Registration', vehicle['registrationNumber'] ?? 'N/A'],
                    ['Make/Model', '${vehicle['manufacturer']} ${vehicle['model']}'],
                    ['Capacity', vehicle['capacity']?.toString() ?? 'N/A'],
                  ]),
                ),
                pw.SizedBox(width: 20),
                pw.Expanded(
                  child: _buildPdfSection('DRIVER', [
                    ['Name', driver['name'] ?? 'Unknown'],
                    ['Phone', driver['phone'] ?? 'N/A'],
                    ['Email', driver['email'] ?? 'N/A'],
                    ['License', driver['licenseNumber'] ?? 'N/A'],
                  ]),
                ),
              ],
            ),
            
            pw.SizedBox(height: 20),
            
            // Route Summary
            _buildPdfSection('ROUTE SUMMARY', [
              ['Total Stops', _tripDetails!['totalStops'].toString()],
              ['Completed Stops', _tripDetails!['completedStops'].toString()],
              ['Total Distance', '${_tripDetails!['totalDistance']} km'],
              ['Estimated Time', _tripDetails!['totalTime']?.toString() ?? 'N/A'],
            ]),
            
            pw.SizedBox(height: 20),
            
            // Performance Metrics
            _buildPdfSection('PERFORMANCE METRICS', [
              ['On-Time Stops', metrics['onTimeStops'].toString()],
              ['Delayed Stops', metrics['delayedStops'].toString()],
              ['Average Delay', '${metrics['averageDelay']} min'],
            ]),
            
            pw.SizedBox(height: 20),
            
            // Stops Table
            pw.Header(
              level: 1,
              child: pw.Text('ROUTE STOPS', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 10),
            
            _buildStopsTable(stops),
            
            // Customer Feedback
            if (feedback.isNotEmpty) ...[
              pw.SizedBox(height: 30),
              pw.Header(
                level: 1,
                child: pw.Text('CUSTOMER FEEDBACK', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 10),
              
              ...feedback.map((fb) {
                final fbData = fb as Map<String, dynamic>;
                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 12),
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(fbData['customerName'] ?? 'Anonymous',
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          pw.Text('Rating: ${fbData['rating']}/5'),
                        ],
                      ),
                      if (fbData['feedback'] != null && fbData['feedback'].toString().isNotEmpty) ...[
                        pw.SizedBox(height: 4),
                        pw.Text(fbData['feedback']),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ],
          ];
        },
      ),
    );
    
    return pdf;
  }

  pw.Widget _buildPdfSection(String title, List<List<String>> rows) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: rows.map((row) {
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Row(
                  children: [
                    pw.SizedBox(
                      width: 120,
                      child: pw.Text('${row[0]}:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Expanded(child: pw.Text(row[1])),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildStopsTable(List<dynamic> stops) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: {
        0: const pw.FixedColumnWidth(25),
        1: const pw.FixedColumnWidth(45),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FixedColumnWidth(75),
        4: const pw.FlexColumnWidth(3),
        5: const pw.FixedColumnWidth(45),
        6: const pw.FixedColumnWidth(45),
        7: const pw.FixedColumnWidth(55),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blue900),
          children: [
            _buildTableCell('#', isHeader: true),
            _buildTableCell('Type', isHeader: true),
            _buildTableCell('Customer', isHeader: true),
            _buildTableCell('Phone', isHeader: true),
            _buildTableCell('Address', isHeader: true),
            _buildTableCell('Est.', isHeader: true),
            _buildTableCell('Actual', isHeader: true),
            _buildTableCell('Status', isHeader: true),
          ],
        ),
        ...stops.map((stop) {
          final stopData = stop as Map<String, dynamic>;
          
          String customerName = 'Office Drop';
          String customerPhone = '-';
          
          if (stopData['type'] == 'pickup') {
            customerName = stopData['customerName'] ?? stopData['customer']?['name'] ?? 'N/A';
            customerPhone = stopData['customerPhone'] ?? stopData['customer']?['phone'] ?? '-';
            if (customerPhone.isEmpty) customerPhone = '-';
          }
          
          String actualTime = 'N/A';
          if (stopData['arrivedAt'] != null) {
            try {
              final arrivedAtStr = stopData['arrivedAt'].toString();
              if (arrivedAtStr.isNotEmpty && arrivedAtStr != 'null') {
                final dt = DateTime.parse(arrivedAtStr);
                actualTime = DateFormat('HH:mm').format(dt);
              }
            } catch (e) {
              actualTime = 'N/A';
            }
          }
          
          return pw.TableRow(
            children: [
              _buildTableCell(stopData['sequence']?.toString() ?? '?'),
              _buildTableCell((stopData['type']?.toString() ?? 'N/A').toUpperCase()),
              _buildTableCell(customerName),
              _buildTableCell(customerPhone),
              _buildTableCell(stopData['address'] ?? stopData['location']?['address'] ?? 'N/A'),
              _buildTableCell(stopData['estimatedTime'] ?? 'N/A'),
              _buildTableCell(actualTime),
              _buildTableCell(_capitalizeStatus(stopData['status'] ?? 'pending')),
            ],
          );
        }).toList(),
      ],
    );
  }

  pw.Widget _buildTableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 10 : 9,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader ? PdfColors.white : PdfColors.black,
        ),
      ),
    );
  }

  Future<void> _savePdf(pw.Document pdf, String tripNumber) async {
    final fileName = 'trip_report_$tripNumber.pdf';
    
    try {
      final bytes = await pdf.save();
      
      if (kIsWeb) {
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      } else {
        await Printing.layoutPdf(onLayout: (format) async => bytes, name: fileName);
      }
      
      debugPrint('✅ PDF ready: $fileName');
    } catch (e) {
      debugPrint('❌ PDF error: $e');
      throw e;
    }
  }

  // ========================================================================
  // EXCEL GENERATION
  // ========================================================================

  Future<excel_pkg.Excel> _generateExcelReport() async {
    final excel = excel_pkg.Excel.createExcel();
    final sheet = excel['Trip Report'];
    
    final vehicle = _tripDetails!['vehicle'] as Map<String, dynamic>;
    final driver = _tripDetails!['driver'] as Map<String, dynamic>;
    final stops = _tripDetails!['stops'] as List<dynamic>;
    
    int row = 0;
    
    // ✅ TITLE
    sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
      ..value = excel_pkg.TextCellValue('TRIP REPORT - ${_tripDetails!['tripNumber']}')
      ..cellStyle = excel_pkg.CellStyle(
        bold: true,
        fontSize: 16,
        horizontalAlign: excel_pkg.HorizontalAlign.Center,
      );
    sheet.merge(
      excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      excel_pkg.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row),
    );
    row += 2;
    
    // ✅ TRIP INFO
    _addSectionHeader(sheet, row, 'TRIP INFORMATION');
    row++;
    _addDataRow(sheet, row++, 'Trip Number', _tripDetails!['tripNumber']);
    _addDataRow(sheet, row++, 'Status', _capitalizeStatus(_tripDetails!['status']));
    _addDataRow(sheet, row++, 'Type', _tripDetails!['tripType']);
    _addDataRow(sheet, row++, 'Scheduled Date', _tripDetails!['scheduledDate']);
    _addDataRow(sheet, row++, 'Scheduled Time', '${_tripDetails!['startTime']} - ${_tripDetails!['endTime']}');
    row++;
    
    // ✅ VEHICLE INFO
    _addSectionHeader(sheet, row, 'VEHICLE INFORMATION');
    row++;
    _addDataRow(sheet, row++, 'Vehicle Number', vehicle['vehicleNumber']);
    _addDataRow(sheet, row++, 'Vehicle Name', vehicle['vehicleName']);
    _addDataRow(sheet, row++, 'Registration', vehicle['registrationNumber']);
    _addDataRow(sheet, row++, 'Manufacturer', vehicle['manufacturer']);
    _addDataRow(sheet, row++, 'Model', vehicle['model']);
    row++;
    
    // ✅ DRIVER INFO
    _addSectionHeader(sheet, row, 'DRIVER INFORMATION');
    row++;
    _addDataRow(sheet, row++, 'Name', driver['name']);
    _addDataRow(sheet, row++, 'Phone', driver['phone']);
    _addDataRow(sheet, row++, 'Email', driver['email']);
    _addDataRow(sheet, row++, 'License', driver['licenseNumber']);
    row++;
    
    // ✅ STOPS TABLE
    _addSectionHeader(sheet, row, 'ROUTE STOPS');
    row++;
    
    // Headers
    final headers = ['#', 'Type', 'Customer', 'Phone', 'Address', 'Est. Time', 'Actual Time', 'Status'];
    for (int i = 0; i < headers.length; i++) {
      sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row))
        ..value = excel_pkg.TextCellValue(headers[i])
        ..cellStyle = excel_pkg.CellStyle(
          bold: true,
          backgroundColorHex: excel_pkg.ExcelColor.blue,
          fontColorHex: excel_pkg.ExcelColor.white,
        );
    }
    row++;
    
    // Data rows
    for (var stop in stops) {
      final stopData = stop as Map<String, dynamic>;
      
      String customerName = stopData['type'] == 'pickup'
          ? (stopData['customerName'] ?? stopData['customer']?['name'] ?? 'N/A')
          : 'Office Drop';
      
      String customerPhone = stopData['type'] == 'pickup'
          ? (stopData['customerPhone'] ?? stopData['customer']?['phone'] ?? '-')
          : '-';
      
      String actualTime = 'N/A';
      if (stopData['arrivedAt'] != null) {
        try {
          final dt = DateTime.parse(stopData['arrivedAt'].toString());
          actualTime = DateFormat('HH:mm').format(dt);
        } catch (e) {
          actualTime = 'N/A';
        }
      }
      
      sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = 
        excel_pkg.TextCellValue(stopData['sequence']?.toString() ?? '?');
      sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = 
        excel_pkg.TextCellValue((stopData['type'] ?? 'N/A').toUpperCase());
      sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = 
        excel_pkg.TextCellValue(customerName);
      sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = 
        excel_pkg.TextCellValue(customerPhone);
      sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = 
        excel_pkg.TextCellValue(stopData['address'] ?? stopData['location']?['address'] ?? 'N/A');
      sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = 
        excel_pkg.TextCellValue(stopData['estimatedTime'] ?? 'N/A');
      sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value = 
        excel_pkg.TextCellValue(actualTime);
      sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row)).value = 
        excel_pkg.TextCellValue(_capitalizeStatus(stopData['status'] ?? 'pending'));
      
      row++;
    }
    
    // Note: setColWidth is not available in excel 4.0.x
    // Column widths will use default values
    // sheet.setColWidth(0, 8);  // #
    // sheet.setColWidth(1, 12); // Type
    // sheet.setColWidth(2, 25); // Customer
    // sheet.setColWidth(3, 15); // Phone
    // sheet.setColWidth(4, 40); // Address
    // sheet.setColWidth(5, 12); // Est. Time
    // sheet.setColWidth(6, 12); // Actual Time
    // sheet.setColWidth(7, 12); // Status
    
    return excel;
  }

  void _addSectionHeader(excel_pkg.Sheet sheet, int row, String title) {
    sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
      ..value = excel_pkg.TextCellValue(title)
      ..cellStyle = excel_pkg.CellStyle(
        bold: true,
        fontSize: 14,
        backgroundColorHex: excel_pkg.ExcelColor.lightBlue,
      );
    sheet.merge(
      excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      excel_pkg.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row),
    );
  }

  void _addDataRow(excel_pkg.Sheet sheet, int row, String label, dynamic value) {
    sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
      ..value = excel_pkg.TextCellValue(label)
      ..cellStyle = excel_pkg.CellStyle(bold: true);
    sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = 
      excel_pkg.TextCellValue(value?.toString() ?? 'N/A');
  }

  Future<void> _saveExcel(excel_pkg.Excel excel, String tripNumber) async {
    final fileName = 'trip_report_$tripNumber.xlsx';
    
    try {
      final bytes = excel.encode();
      
      if (bytes == null) {
        throw Exception('Failed to encode Excel file');
      }
      
      if (kIsWeb) {
        // Web: Trigger download
        await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: fileName);
      } else {
        // Mobile: Share or save
        await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: fileName);
      }
      
      debugPrint('✅ Excel ready: $fileName');
    } catch (e) {
      debugPrint('❌ Excel error: $e');
      throw e;
    }
  }

  // ========================================================================
  // ACTION METHODS
  // ========================================================================

  void _trackLive() {
    if (_tripDetails == null) {
      _showSnackBar('Trip details not loaded', isError: true);
      return;
    }

    final status = _tripDetails!['status']?.toString() ?? '';
    
    if (status == 'assigned' || status == 'scheduled') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue),
              SizedBox(width: 8),
              Text('Trip Not Started'),
            ],
          ),
          content: const Text(
            'This trip has not started yet. Live tracking will be available once the driver starts the trip.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final vehicle = _tripDetails!['vehicle'] as Map<String, dynamic>?;
    
    if (vehicle == null) {
      _showSnackBar('Vehicle information not available', isError: true);
      return;
    }

    String? vehicleId;
    
    if (vehicle['_id'] != null) {
      final id = vehicle['_id'];
      if (id is Map && id.containsKey('\$oid')) {
        vehicleId = id['\$oid'].toString();
      } else {
        vehicleId = id.toString();
      }
    }

    if (vehicleId == null || vehicleId.isEmpty) {
      _showSnackBar('Vehicle ID not found', isError: true);
      return;
    }

    Navigator.pushNamed(
      context,
      AdminLiveLocationWholeVehicles.routeName,
      arguments: {
        'vehicleId': vehicleId,
        'tripId': widget.tripId,
        'autoCenter': true,
      },
    );
  }

  Future<void> _callDriver() async {
    if (_tripDetails == null) {
      _showSnackBar('Trip details not loaded', isError: true);
      return;
    }

    final driver = _tripDetails!['driver'] as Map<String, dynamic>?;
    final phone = driver?['phone']?.toString() ?? '';
    
    if (phone.isEmpty || phone == 'null') {
      _showSnackBar('Driver phone number not available', isError: true);
      return;
    }

    debugPrint('📞 Calling driver: $phone');

    if (kIsWeb) {
      // WEB: Copy to clipboard
      await Clipboard.setData(ClipboardData(text: phone));
      _showSnackBar('Phone number copied: $phone');
    } else {
      // MOBILE: Direct call
      final uri = Uri.parse('tel:$phone');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _showSnackBar('Cannot open phone dialer', isError: true);
      }
    }
  }

  // ✅ NEW: WhatsApp method
  Future<void> _whatsappDriver() async {
    if (_tripDetails == null) {
      _showSnackBar('Trip details not loaded', isError: true);
      return;
    }

    final driver = _tripDetails!['driver'] as Map<String, dynamic>?;
    String phone = driver?['phone']?.toString() ?? '';
    
    if (phone.isEmpty || phone == 'null') {
      _showSnackBar('Driver phone number not available', isError: true);
      return;
    }

    debugPrint('💬 Opening WhatsApp for driver: $phone');

    // ✅ Clean phone number (remove spaces, dashes, etc.)
    phone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    
    // ✅ Add country code if not present (assuming India +91)
    if (!phone.startsWith('+')) {
      if (phone.length == 10) {
        phone = '+91$phone';  // ✅ Change to your country code
      }
    }

    // ✅ WhatsApp URL format
    final String whatsappUrl;
    
    if (kIsWeb) {
      // WEB: Use web.whatsapp.com
      whatsappUrl = 'https://web.whatsapp.com/send?phone=$phone';
    } else {
      // MOBILE: Use whatsapp:// scheme
      whatsappUrl = 'whatsapp://send?phone=$phone';
    }

    debugPrint('🔗 WhatsApp URL: $whatsappUrl');

    try {
      final uri = Uri.parse(whatsappUrl);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
        );
      } else {
        // Fallback: Try web version even on mobile
        final webUri = Uri.parse('https://wa.me/$phone');
        if (await canLaunchUrl(webUri)) {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
        } else {
          _showSnackBar('WhatsApp is not installed', isError: true);
        }
      }
    } catch (e) {
      debugPrint('❌ Error opening WhatsApp: $e');
      _showSnackBar('Failed to open WhatsApp: $e', isError: true);
    }
  }

  // ========================================================================
  // UI BUILD METHODS
  // ========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0D47A1),
      foregroundColor: Colors.white,
      elevation: 2,
      title: Text(
        _tripDetails?['tripNumber'] ?? 'Trip Details',
        style: const TextStyle(fontSize: 18),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadTripDetails,
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading trip details...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadTripDetails,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_tripDetails == null) {
      return const Center(
        child: Text('No trip data available'),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTripDetails,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTripOverview(),
            const SizedBox(height: 8),
            _buildActionButtons(),
            const SizedBox(height: 8),
            _buildProgressSection(),
            const SizedBox(height: 8),
            _buildVehicleDriverInfo(),
            const SizedBox(height: 8),
            if (_tripDetails!['metrics'] != null) _buildMetricsSection(),
            const SizedBox(height: 8),
            _buildStopsSection(),
            const SizedBox(height: 8),
            if (_tripDetails!['customerFeedback'] != null &&
                (_tripDetails!['customerFeedback'] as List).isNotEmpty)
              _buildFeedbackSection(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildTripOverview() {
    final status = _tripDetails!['status']?.toString() ?? 'assigned';
    final startTime = _tripDetails!['startTime'] ?? '00:00';
    final endTime = _tripDetails!['endTime'] ?? '00:00';
    final actualStartTime = _tripDetails!['actualStartTime'];
    final scheduledDate = _tripDetails!['scheduledDate'] ?? '';
    
    Color statusColor = _getStatusColor(status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tripDetails!['tripNumber'] ?? 'N/A',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          
          const SizedBox(height: 8),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: statusColor, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  _getStatusText(status),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: statusColor),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          if (scheduledDate.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.event, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, MMM dd, yyyy').format(DateTime.parse(scheduledDate)),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          
          Row(
            children: [
              const Icon(Icons.schedule, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              Text('Scheduled: $startTime - $endTime', style: const TextStyle(fontSize: 14)),
            ],
          ),
          
          if (actualStartTime != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.play_circle, size: 18, color: Colors.green),
                const SizedBox(width: 8),
                Text('Started: ${_formatDateTime(actualStartTime)}', style: const TextStyle(fontSize: 14)),
              ],
            ),
          ],
        ],
      ),
    );
  }
Widget _buildCompactButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    required Color backgroundColor,
    bool isLoading = false,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 2,
      ),
      child: isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
    );
  }
  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // PDF Button
          Expanded(
            child: _buildCompactButton(
              onPressed: _isDownloading ? null : _downloadPDF,
              icon: Icons.picture_as_pdf,
              label: 'PDF',
              backgroundColor: Colors.red,
              isLoading: _isDownloading,
            ),
          ),
          const SizedBox(width: 8),

          // Excel Button
          Expanded(
            child: _buildCompactButton(
              onPressed: _isDownloading ? null : _downloadExcel,
              icon: Icons.table_chart,
              label: 'Excel',
              backgroundColor: Colors.green,
              isLoading: _isDownloading,
            ),
          ),
          const SizedBox(width: 8),

          // Track Live Button
          Expanded(
            child: _buildCompactButton(
              onPressed: _trackLive,
              icon: Icons.location_on,
              label: 'Track',
              backgroundColor: const Color(0xFF0D47A1),
            ),
          ),
          const SizedBox(width: 8),

          // Call Button
          Expanded(
            child: _buildCompactButton(
              onPressed: _callDriver,
              icon: Icons.phone,
              label: 'Call',
              backgroundColor: Colors.green[700]!,
            ),
          ),
          const SizedBox(width: 8),

          // WhatsApp Button
          Expanded(
            child: _buildCompactButton(
              onPressed: _whatsappDriver,
              icon: Icons.message,
              label: 'WhatsApp',
              backgroundColor: const Color(0xFF25D366),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection() {
    final progress = (_tripDetails!['progress'] ?? 0).toDouble();
    final currentStopIndex = _tripDetails!['currentStopIndex'] ?? 0;
    final totalStops = _tripDetails!['totalStops'] ?? 0;
    final completedStops = _tripDetails!['completedStops'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Trip Progress', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('${progress.toInt()}%',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: _getStatusColor(_tripDetails!['status']))),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor(_tripDetails!['status'])),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Current stop: $currentStopIndex of $totalStops',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
              Text('Completed: $completedStops/$totalStops',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleDriverInfo() {
    final vehicle = _tripDetails!['vehicle'] as Map<String, dynamic>? ?? {};
    final driver = _tripDetails!['driver'] as Map<String, dynamic>? ?? {};

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.directions_car, color: Colors.blue),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vehicle['vehicleNumber'] ?? 'Unknown',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    if (vehicle['model'] != null && vehicle['model'] != 'N/A')
                      Text('${vehicle['manufacturer'] ?? ''} ${vehicle['model']}'.trim(),
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.person, color: Colors.green),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver['name'] ?? 'Unknown Driver',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    if (driver['phone'] != null && driver['phone'].toString().isNotEmpty)
                      Text(driver['phone'], style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.phone, color: Colors.green),
                    onPressed: _callDriver,
                    tooltip: 'Call Driver',
                  ),
                  IconButton(
                    icon: const Icon(Icons.message, color: Color(0xFF25D366)),
                    onPressed: _whatsappDriver,
                    tooltip: 'WhatsApp Driver',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsSection() {
    final metrics = _tripDetails!['metrics'] as Map<String, dynamic>? ?? {};
    final totalStops = _tripDetails!['totalStops'] ?? 0;
    final onTimeStops = metrics['onTimeStops'] ?? 0;
    final delayedStops = metrics['delayedStops'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Performance Metrics', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  icon: Icons.check_circle,
                  label: 'On-Time',
                  value: '$onTimeStops',
                  subtitle: '${totalStops > 0 ? ((onTimeStops / totalStops) * 100).toStringAsFixed(0) : 0}%',
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  icon: Icons.warning,
                  label: 'Delayed',
                  value: '$delayedStops',
                  subtitle: '${metrics['averageDelay'] ?? 0} min avg',
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  icon: Icons.route,
                  label: 'Distance',
                  value: '${(_tripDetails!['totalDistance'] ?? 0).toStringAsFixed(1)}',
                  subtitle: 'km',
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(subtitle, style: TextStyle(fontSize: 11, color: color)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ],
      ),
    );
  }

  Widget _buildStopsSection() {
    final stops = _tripDetails!['stops'] as List<dynamic>? ?? [];
    final currentStopIndex = _tripDetails!['currentStopIndex'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Route Stops', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('${stops.length} stop${stops.length != 1 ? 's' : ''}',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 16),
          if (stops.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No stops found')))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: stops.length,
              itemBuilder: (context, index) {
                final stop = stops[index] as Map<String, dynamic>;
                final isCurrent = index == currentStopIndex;
                return _buildStopItem(stop, isCurrent, index);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStopItem(Map<String, dynamic> stop, bool isCurrent, int index) {
    final type = stop['type']?.toString() ?? 'pickup';
    final status = stop['status']?.toString() ?? 'pending';
    final customer = stop['customer'] as Map<String, dynamic>? ?? {};
    final location = stop['location'] as Map<String, dynamic>? ?? {};
    final timingStatus = stop['timingStatus'] as Map<String, dynamic>?;

    Color statusColor;
    IconData statusIcon;
    
    if (status == 'completed') {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (status == 'arrived') {
      statusColor = Colors.orange;
      statusIcon = Icons.access_time;
    } else if (status == 'cancelled') {
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
    } else {
      statusColor = Colors.grey;
      statusIcon = Icons.circle_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCurrent ? Colors.blue.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isCurrent ? Colors.blue : Colors.grey.shade300, width: isCurrent ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 24),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: type == 'pickup' ? Colors.blue.shade100 : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${stop['sequence']} - ${type.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: type == 'pickup' ? Colors.blue.shade900 : Colors.orange.shade900,
                  ),
                ),
              ),
              const Spacer(),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(4)),
                  child: const Text('CURRENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (type == 'pickup') ...[
            Text(customer['name'] ?? 'Unknown', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (customer['phone'] != null && customer['phone'].toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.phone, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(customer['phone'], style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                ],
              ),
            ],
          ] else ...[
            const Text('Office Drop', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
          if (location['address'] != null && location['address'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(child: Text(location['address'], style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Estimated', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        const SizedBox(height: 4),
                        Text(stop['estimatedTime'] ?? 'N/A', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    if (stop['arrivedAt'] != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Actual', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          const SizedBox(height: 4),
                          Text(_formatDateTime(stop['arrivedAt']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                  ],
                ),
                if (timingStatus != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: timingStatus['type'] == 'on_time'
                          ? Colors.green.shade50
                          : timingStatus['type'] == 'delayed'
                              ? Colors.red.shade50
                              : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          timingStatus['type'] == 'on_time'
                              ? Icons.check
                              : timingStatus['type'] == 'delayed'
                                  ? Icons.warning
                                  : Icons.trending_up,
                          size: 14,
                          color: timingStatus['type'] == 'on_time'
                              ? Colors.green
                              : timingStatus['type'] == 'delayed'
                                  ? Colors.red
                                  : Colors.blue,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timingStatus['type'] == 'on_time'
                              ? 'On-time'
                              : timingStatus['type'] == 'delayed'
                                  ? 'Delayed +${timingStatus['minutes']} min'
                                  : 'Early -${timingStatus['minutes']} min',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: timingStatus['type'] == 'on_time'
                                ? Colors.green
                                : timingStatus['type'] == 'delayed'
                                    ? Colors.red
                                    : Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackSection() {
    final feedbackList = _tripDetails!['customerFeedback'] as List<dynamic>;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Customer Feedback', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...feedbackList.map((feedback) {
            final fb = feedback as Map<String, dynamic>;
            return _buildFeedbackItem(fb);
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildFeedbackItem(Map<String, dynamic> feedback) {
    final rating = feedback['rating'] ?? 0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(feedback['customerName'] ?? 'Anonymous',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              Row(
                children: List.generate(5, (index) {
                  return Icon(index < rating ? Icons.star : Icons.star_border, size: 16, color: Colors.amber);
                }),
              ),
            ],
          ),
          if (feedback['feedback'] != null && feedback['feedback'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(feedback['feedback'], style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          ],
          const SizedBox(height: 8),
          Text('Submitted: ${_formatDateTime(feedback['submittedAt'])}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  // ========================================================================
  // UTILITY METHODS
  // ========================================================================

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'started':
      case 'in_progress':
        return Colors.green;
      case 'assigned':
        return Colors.blue;
      case 'completed':
        return Colors.grey;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'started':
      case 'in_progress':
        return 'ONGOING';
      case 'assigned':
        return 'SCHEDULED';
      case 'completed':
        return 'COMPLETED';
      case 'cancelled':
        return 'CANCELLED';
      default:
        return status.toUpperCase();
    }
  }

  String _capitalizeStatus(String? status) {
    if (status == null || status.isEmpty) return 'N/A';
    return status[0].toUpperCase() + status.substring(1).toLowerCase();
  }

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'N/A';
    
    try {
      final DateTime dt = dateTime is String ? DateTime.parse(dateTime) : dateTime as DateTime;
      return DateFormat('HH:mm').format(dt);
    } catch (e) {
      return 'N/A';
    }
  }
}