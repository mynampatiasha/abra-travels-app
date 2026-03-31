import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import '../../../core/services/driver_service.dart';

/// CSV Import Dialog for Drivers
/// With Download Template functionality similar to HR Employee and Items Billing
class CsvImportDialog extends StatefulWidget {
  final DriverService driverService;
  final VoidCallback onImportComplete;

  const CsvImportDialog({
    Key? key,
    required this.driverService,
    required this.onImportComplete,
  }) : super(key: key);

  @override
  State<CsvImportDialog> createState() => _CsvImportDialogState();
}

class _CsvImportDialogState extends State<CsvImportDialog> {
  String? _selectedFileName;
  List<List<dynamic>>? _csvData;
  bool _isProcessing = false;
  bool _isDownloading = false;
  Map<String, dynamic>? _importResult;

  /// Download CSV Template with sample data
  Future<void> _downloadTemplate() async {
    setState(() => _isDownloading = true);
    
    try {
      // Create CSV template with headers and sample data
      List<List<dynamic>> templateData = [
        // Headers
        [
          'First Name*',
          'Last Name*',
          'Email*',
          'Phone*',
          'Employee ID',
          'Date of Birth (YYYY-MM-DD)',
          'Blood Group',
          'Gender',
          'Street Address',
          'City',
          'State',
          'Postal Code',
          'Country',
          'License Number',
          'License Type',
          'License Issue Date (YYYY-MM-DD)',
          'License Expiry Date (YYYY-MM-DD)',
          'Issuing Authority',
          'Emergency Contact Name',
          'Emergency Contact Phone',
          'Emergency Contact Relationship',
          'Join Date (YYYY-MM-DD)',
          'Salary',
          'Employment Type',
          'Bank Name',
          'Account Number',
          'IFSC Code',
          'Account Holder Name',
          'Status (active/inactive)',
        ],
        // Example row 1
        [
          'Rajesh',
          'Kumar',
          'rajesh.kumar@example.com',
          '+919876543210',
          'DRV001',
          '1990-05-15',
          'O+',
          'Male',
          '123 MG Road',
          'Bangalore',
          'Karnataka',
          '560001',
          'India',
          'KA0120200012345',
          'LMV',
          '2020-01-15',
          '2040-01-14',
          'RTO Bangalore',
          'Priya Kumar',
          '+919876543211',
          'Spouse',
          '2022-01-10',
          '35000',
          'Full-time',
          'HDFC Bank',
          '12345678901234',
          'HDFC0001234',
          'Rajesh Kumar',
          'active',
        ],
        // Example row 2
        [
          'Amit',
          'Singh',
          'amit.singh@example.com',
          '+919876543220',
          'DRV002',
          '1988-08-20',
          'A+',
          'Male',
          '456 Brigade Road',
          'Bangalore',
          'Karnataka',
          '560025',
          'India',
          'KA0120190098765',
          'HMV',
          '2019-06-10',
          '2039-06-09',
          'RTO Bangalore',
          'Sunita Singh',
          '+919876543221',
          'Spouse',
          '2021-03-15',
          '40000',
          'Full-time',
          'ICICI Bank',
          '98765432109876',
          'ICIC0009876',
          'Amit Singh',
          'active',
        ],
        // Instructions row
        [
          'INSTRUCTIONS:',
          '1. Fields marked with * are required',
          '2. Date format: YYYY-MM-DD (e.g., 2024-01-15)',
          '3. Phone format: +91XXXXXXXXXX',
          '4. Gender: Male/Female/Other',
          '5. License Type: LMV/HMV/MCWG/etc.',
          '6. Employment Type: Full-time/Part-time/Contract',
          '7. Status: active or inactive (default: active)',
          '8. Delete this instruction row before uploading',
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
        ],
      ];
      
      // Convert to CSV string
      String csvString = const ListToCsvConverter().convert(templateData);
      
      // Download based on platform
      if (kIsWeb) {
        // Web download
        final bytes = utf8.encode(csvString);
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download = 'driver_import_template.csv';
        html.document.body?.children.add(anchor);
        anchor.click();
        html.document.body?.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
      } else {
        // Mobile/Desktop download
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/driver_import_template.csv');
        await file.writeAsString(csvString);
        
        if (mounted) {
          _showSuccessSnackbar('Template downloaded to: ${file.path}');
        }
      }
      
      setState(() => _isDownloading = false);
      
      if (kIsWeb && mounted) {
        _showSuccessSnackbar('Template downloaded successfully!');
      }
    } catch (e) {
      setState(() => _isDownloading = false);
      _showErrorDialog('Failed to download template: $e');
    }
  }

  /// Pick CSV file
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        setState(() {
          _selectedFileName = result.files.single.name;
        });

        // Parse CSV
        final bytes = result.files.single.bytes!;
        final csvString = utf8.decode(bytes);
        final List<List<dynamic>> csvTable = const CsvToListConverter().convert(csvString);

        setState(() {
          _csvData = csvTable;
        });

        print('✅ CSV file loaded: $_selectedFileName');
        print('   Total rows: ${csvTable.length}');
      }
    } catch (e) {
      print('❌ Error picking file: $e');
      _showErrorDialog('Failed to load CSV file: $e');
    }
  }

  /// Process and import CSV data
  Future<void> _importDrivers() async {
    if (_csvData == null || _csvData!.length < 2) {
      _showErrorDialog('CSV file is empty or invalid');
      return;
    }

    setState(() {
      _isProcessing = true;
      _importResult = null;
    });

    try {
      // Skip header row
      final dataRows = _csvData!.skip(1).toList();
      
      List<Map<String, dynamic>> driversToImport = [];
      List<String> errors = [];
      int rowNumber = 2; // Start from row 2 (after header)

      for (var row in dataRows) {
        try {
          // Skip empty rows or instruction rows
          if (row.isEmpty || 
              row[0] == null ||
              row[0].toString().trim().isEmpty ||
              row[0].toString().toUpperCase().contains('INSTRUCTION')) {
            rowNumber++;
            continue;
          }

          // Validate required fields
          if (row.length < 4) {
            errors.add('Row $rowNumber: Insufficient columns');
            rowNumber++;
            continue;
          }

          final firstName = _getStringValue(row, 0);
          final lastName = _getStringValue(row, 1);
          final email = _getStringValue(row, 2);
          final phone = _getStringValue(row, 3);

          if (firstName.isEmpty || lastName.isEmpty || email.isEmpty || phone.isEmpty) {
            errors.add('Row $rowNumber: Missing required fields (First Name, Last Name, Email, Phone)');
            rowNumber++;
            continue;
          }

          // Build driver data structure
          final driverData = {
            'driverId': _getStringValue(row, 4), // Employee ID
            'personalInfo': {
              'firstName': firstName,
              'lastName': lastName,
              'email': email,
              'phone': phone,
              'dateOfBirth': _getStringValue(row, 5),
              'bloodGroup': _getStringValue(row, 6),
              'gender': _getStringValue(row, 7),
            },
            'address': {
              'street': _getStringValue(row, 8),
              'city': _getStringValue(row, 9),
              'state': _getStringValue(row, 10),
              'postalCode': _getStringValue(row, 11),
              'country': _getStringValue(row, 12),
            },
            'license': {
              'licenseNumber': _getStringValue(row, 13),
              'licenseType': _getStringValue(row, 14),
              'issueDate': _getStringValue(row, 15),
              'expiryDate': _getStringValue(row, 16),
              'issuingAuthority': _getStringValue(row, 17),
            },
            'emergencyContact': {
              'name': _getStringValue(row, 18),
              'phone': _getStringValue(row, 19),
              'relationship': _getStringValue(row, 20),
            },
            'employment': {
              'joinDate': _getStringValue(row, 21),
              'salary': _getStringValue(row, 22),
              'employmentType': _getStringValue(row, 23),
            },
            'bankDetails': {
              'bankName': _getStringValue(row, 24),
              'accountNumber': _getStringValue(row, 25),
              'ifscCode': _getStringValue(row, 26),
              'accountHolderName': _getStringValue(row, 27),
            },
            'status': _getStringValue(row, 28, defaultValue: 'active'),
          };

          driversToImport.add(driverData);
        } catch (e) {
          errors.add('Row $rowNumber: ${e.toString()}');
        }
        rowNumber++;
      }

      print('📊 Parsed ${driversToImport.length} valid drivers from CSV');
      print('❌ ${errors.length} rows with errors');

      if (driversToImport.isEmpty) {
        setState(() {
          _isProcessing = false;
          _importResult = {
            'success': false,
            'message': 'No valid drivers found in CSV',
            'errors': errors,
          };
        });
        return;
      }

      // Call backend bulk import API
      final result = await widget.driverService.bulkImportDrivers(driversToImport);

      setState(() {
        _isProcessing = false;
        _importResult = {
          'success': true,
          'total': dataRows.length,
          'successCount': result['successCount'] ?? driversToImport.length,
          'failedCount': result['failedCount'] ?? 0,
          'errors': [...errors, ...(result['errors'] ?? [])],
        };
      });

      // Notify parent to refresh
      widget.onImportComplete();
    } catch (e) {
      print('❌ Import error: $e');
      setState(() {
        _isProcessing = false;
        _importResult = {
          'success': false,
          'message': 'Import failed: $e',
        };
      });
    }
  }

  /// Helper to safely get string value from CSV row
  String _getStringValue(List<dynamic> row, int index, {String defaultValue = ''}) {
    if (index >= row.length) return defaultValue;
    final value = row[index];
    if (value == null) return defaultValue;
    return value.toString().trim();
  }

  /// Show error dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('Error'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show success snackbar
  void _showSuccessSnackbar(String message) {
    if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        width: 700,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1e3a8a), Color(0xFF1e40af)],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(15),
                  topRight: Radius.circular(15),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.upload_file, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  const Text(
                    'Import Drivers from CSV',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Instructions
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFe0f2fe),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF0284c7)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.info, color: Color(0xFF075985)),
                              SizedBox(width: 8),
                              Text(
                                'CSV Import Instructions:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF075985),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text('1. Download the CSV template with sample data'),
                          const Text('2. Fill in your driver data following the format'),
                          const Text('3. Upload the completed CSV file'),
                          const Text('4. System will validate and import all records'),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Step 1: Download Template
                    const Text(
                      'Step 1: Download CSV Template',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isDownloading || _isProcessing ? null : _downloadTemplate,
                        icon: _isDownloading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.download),
                        label: Text(_isDownloading ? 'Downloading...' : 'Download Template'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10b981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Step 2: Upload
                    const Text(
                      'Step 2: Upload Filled CSV File',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _isProcessing || _isDownloading ? null : _pickFile,
                      child: Container(
                        padding: const EdgeInsets.all(40),
                        decoration: BoxDecoration(
                          color: const Color(0xFFf8fafc),
                          border: Border.all(
                            color: _selectedFileName != null
                                ? const Color(0xFF10b981)
                                : const Color(0xFFe2e8f0),
                            width: 3,
                            style: BorderStyle.solid,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              _selectedFileName != null ? Icons.check_circle : Icons.cloud_upload,
                              size: 56,
                              color: _selectedFileName != null
                                  ? const Color(0xFF10b981)
                                  : const Color(0xFF94a3b8),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _selectedFileName ?? 'Click to Select CSV File',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _selectedFileName != null
                                    ? const Color(0xFF10b981)
                                    : const Color(0xFF475569),
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _selectedFileName != null
                                  ? '${_csvData!.length - 1} drivers found'
                                  : 'Supports .csv files only',
                              style: const TextStyle(
                                color: Color(0xFF94a3b8),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Import Result
                    if (_importResult != null) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _importResult!['success'] == true
                              ? const Color(0xFFf0fdf4)
                              : const Color(0xFFfef2f2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _importResult!['success'] == true
                                ? const Color(0xFF10b981)
                                : const Color(0xFFef4444),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _importResult!['success'] == true
                                      ? Icons.check_circle
                                      : Icons.error,
                                  color: _importResult!['success'] == true
                                      ? const Color(0xFF10b981)
                                      : const Color(0xFFef4444),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _importResult!['success'] == true
                                      ? 'Import Complete!'
                                      : 'Import Failed',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _importResult!['success'] == true
                                        ? const Color(0xFF10b981)
                                        : const Color(0xFFef4444),
                                  ),
                                ),
                              ],
                            ),
                            if (_importResult!['success'] == true) ...[
                              const SizedBox(height: 8),
                              Text('Total: ${_importResult!['total']}'),
                              Text(
                                'Success: ${_importResult!['successCount']}',
                                style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.w700),
                              ),
                              Text(
                                'Failed: ${_importResult!['failedCount']}',
                                style: const TextStyle(color: Color(0xFFdc2626), fontWeight: FontWeight.w700),
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              Text(_importResult!['message'] ?? 'Unknown error'),
                            ],
                            if (_importResult!['errors'] != null &&
                                (_importResult!['errors'] as List).isNotEmpty) ...[
                              const SizedBox(height: 12),
                              const Text(
                                'Errors:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              ...(_importResult!['errors'] as List).take(5).map(
                                    (error) => Text(
                                      '• $error',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                              if ((_importResult!['errors'] as List).length > 5)
                                Text(
                                  '... and ${(_importResult!['errors'] as List).length - 5} more errors',
                                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(15),
                  bottomRight: Radius.circular(15),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isProcessing || _isDownloading ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: (_selectedFileName != null && !_isProcessing && !_isDownloading)
                        ? _importDrivers
                        : null,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.upload),
                    label: Text(_isProcessing ? 'Importing...' : 'Import Drivers'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10b981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
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
  }
}
