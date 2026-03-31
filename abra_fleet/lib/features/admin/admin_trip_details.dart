// lib/screens/admin/admin_trip_details.dart - COMPLETE FILE
// ============================================================================
// ADMIN TRIP DETAILS - Complete Trip Information with All Actions
// ============================================================================
// ✅ PDF download (Web & Mobile)
// ✅ Excel download with customer phone numbers (Web & Mobile) - WORKING
// ✅ Call driver functionality - DIRECT DIALER
// ✅ WhatsApp driver functionality (Web & Mobile)
// ✅ Send alerts to driver
// ✅ Live tracking
// ✅ ALL BUTTONS IN ONE ROW - COMPACT DESIGN
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

// ✅ Excel generation imports - Using ExportHelper like invoice list
import 'package:abra_fleet/core/utils/export_helper.dart';

// ✅ Conditional import for web
import 'dart:typed_data' show Uint8List;

class AdminTripDetails extends StatefulWidget {
  final String tripId;
  final bool isClientView;

  const AdminTripDetails({
    super.key,
    required this.tripId,
    this.isClientView = false,
  });

  @override
  State<AdminTripDetails> createState() => _AdminTripDetailsState();
}

class _AdminTripDetailsState extends State<AdminTripDetails> {
  // ========================================================================
  // STATE VARIABLES
  // ========================================================================
  
  Map<String, dynamic>? _tripDetails;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isDownloading = false;
  
  // Alert dialog controllers
  final TextEditingController _alertMessageController = TextEditingController();
  String _alertPriority = 'high';

  @override
  void initState() {
    super.initState();
    debugPrint('🔍 AdminTripDetails: initState for trip ${widget.tripId}');
    _loadTripDetails();
  }

  @override
  void dispose() {
    _alertMessageController.dispose();
    super.dispose();
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
      'vehicleNumber': rawData['vehicleNumber'] ?? rawData['vehicle']?['vehicleNumber'] ?? rawData['vehicle']?['registrationNumber'] ?? 'Unknown',
      'vehicleName': rawData['vehicleName'] ?? rawData['vehicle']?['vehicleName'] ?? rawData['vehicle']?['name'] ?? '',
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
    return {
      'onTimeStops': 0,
      'delayedStops': 0,
      'averageDelay': 0,
    };
  }
  
  return {
    'onTimeStops': metricsData['onTimeStops'] ?? 0,
    'delayedStops': metricsData['delayedStops'] ?? 0,
    'averageDelay': metricsData['averageDelay'] ?? 0,
  };
}

List<Map<String, dynamic>> _parseStopsList(dynamic stopsData) {
  if (stopsData == null) {
    debugPrint('⚠️  Stops data is null');
    return [];
  }
  
  if (stopsData is! List) {
    debugPrint('⚠️  Stops data is not a list: ${stopsData.runtimeType}');
    return [];
  }
  
  try {
    return (stopsData as List)
        .map((stop) => stop as Map<String, dynamic>)
        .toList();
  } catch (e) {
    debugPrint('⚠️  Error parsing stops: $e');
    return [];
  }
}

List<Map<String, dynamic>> _parseFeedbackList(dynamic feedbackData) {
  if (feedbackData == null) {
    debugPrint('📝 No customer feedback');
    return [];
  }
  
  if (feedbackData is! List) {
    debugPrint('⚠️  Feedback data is not a list: ${feedbackData.runtimeType}');
    return [];
  }
  
  try {
    return (feedbackData as List)
        .map((fb) => fb as Map<String, dynamic>)
        .toList();
  } catch (e) {
    debugPrint('⚠️  Error parsing feedback: $e');
    return [];
  }
}

List<dynamic> _parseLocationHistory(dynamic locationData) {
  if (locationData == null || locationData is! List) {
    return [];
  }
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

    final url = '${ApiConfig.baseUrl}/api/admin/trips/${widget.tripId}/details';

    debugPrint('🔍 Fetching trip details: $url');

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

        debugPrint('✅ Trip details loaded');
        debugPrint('   Trip: ${_tripDetails!['tripNumber']}');
        debugPrint('   Vehicle: ${_safeGetNestedValue(_tripDetails, ['vehicle', 'vehicleNumber'], 'N/A')}');
        debugPrint('   Driver: ${_safeGetNestedValue(_tripDetails, ['driver', 'name'], 'N/A')}');
        debugPrint('   Stops: ${(_tripDetails!['stops'] as List).length}');
      } else {
        throw Exception(data['message'] ?? 'Failed to load trip details');
      }
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

  Future<void> _sendAlert() async {
    try {
      final message = _alertMessageController.text.trim();
      
      if (message.isEmpty) {
        _showSnackBar('Please enter alert message', isError: true);
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final token = await _getToken();
      if (token == null) {
        throw Exception('No authentication token found');
      }

      final url = '${ApiConfig.baseUrl}/api/admin/trips/${widget.tripId}/send-alert';

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'message': message,
          'priority': _alertPriority,
        }),
      );

      if (mounted) Navigator.pop(context);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          if (mounted) Navigator.pop(context);
          _alertMessageController.clear();
          final driverName = _safeGetNestedValue(_tripDetails, ['driver', 'name'], 'driver');
          _showSnackBar('Alert sent to $driverName');
        } else {
          throw Exception(data['message'] ?? 'Failed to send alert');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      _showSnackBar('Failed to send alert: $e', isError: true);
    }
  }

  // ========================================================================
  // PDF DOWNLOAD
  // ========================================================================
  
  Future<void> _downloadTripReport() async {
    try {
      setState(() => _isDownloading = true);

      final token = await _getToken();
      if (token == null) throw Exception('No authentication token found');

      final url = '${ApiConfig.baseUrl}/api/admin/trips/${widget.tripId}/report';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final reportData = data['data'] as Map<String, dynamic>;
          final pdf = await _generatePdfReport(reportData);
          await _savePdf(pdf, reportData['tripInfo']['tripNumber']);
          _showSnackBar('Trip report downloaded successfully');
        } else {
          throw Exception(data['message'] ?? 'Failed to generate report');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _showSnackBar('Failed to generate report: $e', isError: true);
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  Future<pw.Document> _generatePdfReport(Map<String, dynamic> data) async {
    final pdf = pw.Document();
    
    final tripInfo = data['tripInfo'] as Map<String, dynamic>;
    final vehicleInfo = data['vehicleInfo'] as Map<String, dynamic>;
    final driverInfo = data['driverInfo'] as Map<String, dynamic>;
    final routeSummary = data['routeSummary'] as Map<String, dynamic>;
    final stops = data['stops'] as List<dynamic>;
    final performance = data['performance'] as Map<String, dynamic>;
    final feedback = data['customerFeedback'] as List<dynamic>;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('TRIP REPORT', style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 8),
                  pw.Text('Trip Number: ${tripInfo['tripNumber']}',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text('Generated: ${DateFormat('MMM dd, yyyy - HH:mm').format(DateTime.parse(data['reportGeneratedAt']))}',
                      style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                  pw.Divider(thickness: 2),
                ],
              ),
            ),
            
            pw.SizedBox(height: 20),
            
            _buildPdfSection('TRIP INFORMATION', [
              ['Status', _capitalizeStatus(tripInfo['status'])],
              ['Type', tripInfo['tripType'] ?? 'N/A'],
              ['Scheduled Date', tripInfo['scheduledDate'] ?? 'N/A'],
              ['Scheduled Time', '${tripInfo['startTime']} - ${tripInfo['endTime']}'],
              if (tripInfo['actualStartTime'] != null)
                ['Actual Start', _formatDateTime(tripInfo['actualStartTime'])],
              if (tripInfo['actualEndTime'] != null)
                ['Actual End', _formatDateTime(tripInfo['actualEndTime'])],
            ]),
            
            pw.SizedBox(height: 20),
            
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _buildPdfSection('VEHICLE', [
                    ['Number', vehicleInfo['vehicleNumber'] ?? 'Unknown'],
                    ['Name', vehicleInfo['vehicleName'] ?? 'N/A'],
                    ['Registration', vehicleInfo['registrationNumber'] ?? 'N/A'],
                    ['Make/Model', '${vehicleInfo['manufacturer']} ${vehicleInfo['model']}'],
                    ['Capacity', vehicleInfo['capacity']?.toString() ?? 'N/A'],
                  ]),
                ),
                pw.SizedBox(width: 20),
                pw.Expanded(
                  child: _buildPdfSection('DRIVER', [
                    ['Name', driverInfo['name'] ?? 'Unknown'],
                    ['Phone', driverInfo['phone'] ?? 'N/A'],
                    ['Email', driverInfo['email'] ?? 'N/A'],
                    ['License', driverInfo['licenseNumber'] ?? driverInfo['license'] ?? 'N/A'],
                  ]),
                ),
              ],
            ),
            
            pw.SizedBox(height: 20),
            
            _buildPdfSection('ROUTE SUMMARY', [
              ['Total Stops', routeSummary['totalStops'].toString()],
              ['Completed Stops', routeSummary['completedStops'].toString()],
              ['Cancelled Stops', routeSummary['cancelledStops'].toString()],
              ['Total Distance', '${routeSummary['totalDistance']} km'],
              ['Estimated Time', routeSummary['totalTime']?.toString() ?? 'N/A'],
              ['Start Odometer', routeSummary['startOdometer']?.toString() ?? 'N/A'],
              ['End Odometer', routeSummary['endOdometer']?.toString() ?? 'N/A'],
              ['Actual Distance', '${routeSummary['actualDistance']} km'],
            ]),
            
            pw.SizedBox(height: 20),
            
            _buildPdfSection('PERFORMANCE METRICS', [
              ['On-Time Stops', performance['onTimeStops'].toString()],
              ['Average Rating', performance['averageRating']?.toString() ?? 'N/A'],
              ['Total Feedback', performance['totalFeedback'].toString()],
            ]),
            
            pw.SizedBox(height: 20),
            
            pw.Header(level: 1, child: pw.Text('ROUTE STOPS', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(height: 10),
            _buildStopsTable(stops),
            
            if (feedback.isNotEmpty) ...[
              pw.SizedBox(height: 30),
              pw.Header(level: 1, child: pw.Text('CUSTOMER FEEDBACK', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
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
                          pw.Text(fbData['customerName'] ?? 'Anonymous', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
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
          decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: rows.map((row) {
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Row(
                  children: [
                    pw.SizedBox(width: 120, child: pw.Text('${row[0]}:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
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
            final dt = DateTime.parse(stopData['arrivedAt'].toString());
            actualTime = DateFormat('HH:mm').format(dt);
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
    } catch (e) {
      throw e;
    }
  }

  // ========================================================================
  // ✅ FIXED: EXCEL DOWNLOAD - Using ExportHelper (Same as Invoice List)
  // ========================================================================

  Future<void> _downloadExcel() async {
    if (_tripDetails == null) {
      _showSnackBar('No trip data available', isError: true);
      return;
    }
    
    try {
      setState(() => _isDownloading = true);
      
      _showSnackBar('Preparing Excel export...');
      
      final vehicle = _tripDetails!['vehicle'] as Map<String, dynamic>;
      final driver = _tripDetails!['driver'] as Map<String, dynamic>;
      final stops = _tripDetails!['stops'] as List<dynamic>;
      
      print('📊 Exporting trip data to Excel...');
      print('   Trip: ${_tripDetails!['tripNumber']}');
      print('   Vehicle: ${vehicle['vehicleNumber']}');
      print('   Driver: ${driver['name']}');
      print('   Stops: ${stops.length}');

      // Prepare CSV data exactly like invoice list page
      List<List<dynamic>> csvData = [
        // Headers
        [
          'Trip Number',
          'Status',
          'Type',
          'Scheduled Date',
          'Scheduled Time',
          'Vehicle Number',
          'Vehicle Name',
          'Driver Name',
          'Driver Phone',
          'Total Stops',
          'Completed Stops',
          '',
          'STOP DETAILS',
          '',
          '',
          '',
          '',
          '',
        ],
      ];

      // Trip summary row
      csvData.add([
        _tripDetails!['tripNumber'],
        _capitalizeStatus(_tripDetails!['status']),
        _tripDetails!['tripType'],
        _tripDetails!['scheduledDate'],
        '${_tripDetails!['startTime']} - ${_tripDetails!['endTime']}',
        vehicle['vehicleNumber'],
        vehicle['vehicleName'],
        driver['name'],
        driver['phone'],
        _tripDetails!['totalStops'].toString(),
        _tripDetails!['completedStops'].toString(),
        '',
        '',
        '',
        '',
        '',
        '',
        '',
      ]);

      // Empty row
      csvData.add(['', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '']);

      // Stop headers
      csvData.add([
        '#',
        'Type',
        'Customer Name',
        'Customer Phone',
        'Address',
        'Est. Time',
        'Actual Time',
        'Status',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
      ]);

      // Add stops
      for (var stop in stops) {
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
            final dt = DateTime.parse(stopData['arrivedAt'].toString());
            actualTime = DateFormat('HH:mm').format(dt);
          } catch (e) {
            actualTime = 'N/A';
          }
        }

        print('   Stop ${stopData['sequence']}: ${stopData['type']} - $customerName - $customerPhone');

        csvData.add([
          stopData['sequence']?.toString() ?? '?',
          (stopData['type'] ?? 'N/A').toUpperCase(),
          customerName,
          customerPhone,
          stopData['address'] ?? stopData['location']?['address'] ?? 'N/A',
          stopData['estimatedTime'] ?? 'N/A',
          actualTime,
          _capitalizeStatus(stopData['status'] ?? 'pending'),
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
        ]);
      }

      print('📦 Total rows to export: ${csvData.length}');

      // Use ExportHelper - exactly like invoice list page
      final filePath = await ExportHelper.exportToExcel(
        data: csvData,
        filename: 'trip_report_${_tripDetails!['tripNumber']}',
      );

      _showSnackBar('✅ Excel file downloaded with ${stops.length} stops!');
    } catch (e) {
      print('❌ Excel Export Error: $e');
      _showSnackBar('Failed to export Excel: $e', isError: true);
    } finally {
      setState(() => _isDownloading = false);
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
          content: const Text('This trip has not started yet. Live tracking will be available once the driver starts the trip.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
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

  // ✅ FIXED: Direct Call - Opens Phone Dialer Immediately
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

    try {
      final uri = Uri.parse('tel:$phone');
      
      if (kIsWeb) {
        // For web, copy number to clipboard
        await Clipboard.setData(ClipboardData(text: phone));
        _showSnackBar('Phone number copied: $phone');
      } else {
        // For mobile, directly open phone dialer
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
          debugPrint('✅ Phone dialer opened for: $phone');
        } else {
          _showSnackBar('Cannot open phone dialer', isError: true);
        }
      }
    } catch (e) {
      debugPrint('❌ Error opening phone dialer: $e');
      _showSnackBar('Failed to open phone dialer: $e', isError: true);
    }
  }

  // WhatsApp method
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

    phone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    
    if (!phone.startsWith('+')) {
      if (phone.length == 10) {
        phone = '+91$phone';
      }
    }

    final String whatsappUrl;
    
    if (kIsWeb) {
      whatsappUrl = 'https://web.whatsapp.com/send?phone=$phone';
    } else {
      whatsappUrl = 'whatsapp://send?phone=$phone';
    }

    try {
      final uri = Uri.parse(whatsappUrl);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
      } else {
        final webUri = Uri.parse('https://wa.me/$phone');
        if (await canLaunchUrl(webUri)) {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
        } else {
          _showSnackBar('WhatsApp is not installed', isError: true);
        }
      }
    } catch (e) {
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
            _buildActionButtons(),  // ✅ COMPACT ROW DESIGN
            const SizedBox(height: 8),
            _buildProgressSection(),
            const SizedBox(height: 8),
            _buildVehicleDriverInfo(),
            const SizedBox(height: 8),
            if (_tripDetails!['metrics'] != null)
              _buildMetricsSection(),
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
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
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
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _getStatusText(status),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
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
                  DateFormat('EEEE, MMM dd, yyyy').format(
                    DateTime.parse(scheduledDate),
                  ),
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
              Text(
                'Scheduled: $startTime - $endTime',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
          
          if (actualStartTime != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.play_circle, size: 18, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Started: ${_formatDateTime(actualStartTime)}',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ✅ COMPACT ACTION BUTTONS IN ONE ROW
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
              onPressed: _isDownloading ? null : _downloadTripReport,
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
          const SizedBox(width: 8),
          
          // Send Alert Button
          Expanded(
            child: _buildCompactButton(
              onPressed: _showSendAlertDialog,
              icon: Icons.warning,
              label: 'Alert',
              backgroundColor: Colors.red[700]!,
            ),
          ),
        ],
      ),
    );
  }

  // ✅ Helper method for compact buttons
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Trip Progress',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${progress.toInt()}%',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _getStatusColor(_tripDetails!['status']),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                _getStatusColor(_tripDetails!['status']),
              ),
              minHeight: 10,
            ),
          ),
          
          const SizedBox(height: 12),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Current stop: $currentStopIndex of $totalStops',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
              Text(
                'Completed: $completedStops/$totalStops',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.directions_car, color: Colors.blue),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle['vehicleNumber'] ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (vehicle['model'] != null && vehicle['model'] != 'N/A')
                      Text(
                        '${vehicle['manufacturer'] ?? ''} ${vehicle['model']}'.trim(),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
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
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.person, color: Colors.green),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driver['name'] ?? 'Unknown Driver',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (driver['phone'] != null && driver['phone'].toString().isNotEmpty)
                      Text(
                        driver['phone'],
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
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
    final averageDelay = metrics['averageDelay'] ?? 0;

    return Container(
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
          const Text(
            'Performance Metrics',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          
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
                  subtitle: averageDelay > 0 ? '+$averageDelay min avg' : '0 min',
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
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
          ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Route Stops',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${stops.length} stop${stops.length != 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          if (stops.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No stops found'),
              ),
            )
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
        border: Border.all(
          color: isCurrent ? Colors.blue : Colors.grey.shade300,
          width: isCurrent ? 2 : 1,
        ),
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
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'CURRENT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          if (type == 'pickup') ...[
            Text(
              customer['name'] ?? 'Unknown',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            if (customer['phone'] != null && customer['phone'].toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.phone, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    customer['phone'],
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ] else ...[
            const Text(
              'Office Drop',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          
          if (location['address'] != null && location['address'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    location['address'],
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
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
                        Text(
                          'Estimated',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stop['estimatedTime'] ?? 'N/A',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    
                    if (stop['arrivedAt'] != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Actual',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDateTime(stop['arrivedAt']),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
          const Text(
            'Customer Feedback',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          
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
                child: Text(
                  feedback['customerName'] ?? 'Anonymous',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Row(
                children: List.generate(5, (index) {
                  return Icon(
                    index < rating ? Icons.star : Icons.star_border,
                    size: 16,
                    color: Colors.amber,
                  );
                }),
              ),
            ],
          ),
          
          if (feedback['feedback'] != null && feedback['feedback'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              feedback['feedback'],
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
          ],
          
          const SizedBox(height: 8),
          
          Text(
            'Submitted: ${_formatDateTime(feedback['submittedAt'])}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // DIALOG METHODS
  // ========================================================================

  void _showSendAlertDialog() {
    if (_tripDetails == null) {
      _showSnackBar('Trip details not loaded', isError: true);
      return;
    }
    
    final driverName = _safeGetNestedValue(_tripDetails, ['driver', 'name'], 'Unknown Driver');
    
    _alertMessageController.clear();
    _alertPriority = 'high';
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.red),
                SizedBox(width: 8),
                Text('Send Alert to Driver'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sending to: $driverName',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                TextField(
                  controller: _alertMessageController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Alert Message *',
                    hintText: 'e.g., Customer waiting, please hurry',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                const Text(
                  'Priority:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                
                DropdownButtonFormField<String>(
                  value: _alertPriority,
                  items: const [
                    DropdownMenuItem(
                      value: 'urgent',
                      child: Row(
                        children: [
                          Icon(Icons.error, color: Colors.red, size: 18),
                          SizedBox(width: 8),
                          Text('🔴 Urgent'),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'high',
                      child: Row(
                        children: [
                          Icon(Icons.warning, color: Colors.orange, size: 18),
                          SizedBox(width: 8),
                          Text('🟠 High'),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'normal',
                      child: Row(
                        children: [
                          Icon(Icons.info, color: Colors.blue, size: 18),
                          SizedBox(width: 8),
                          Text('🟢 Normal'),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _alertPriority = value!;
                    });
                  },
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
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
                onPressed: _sendAlert,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Send Alert'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ========================================================================
  // UTILITY METHODS
  // ========================================================================

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
      final DateTime dt = dateTime is String
          ? DateTime.parse(dateTime)
          : dateTime as DateTime;
      
      return DateFormat('HH:mm').format(dt);
    } catch (e) {
      return 'N/A';
    }
  }
}