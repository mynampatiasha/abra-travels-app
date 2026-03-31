import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:abra_fleet/core/services/vehicle_service.dart'; // ADD THIS IMPORT

class BulkImportVehiclesScreen extends StatefulWidget {
  final VoidCallback onCancel;
  final VoidCallback onImportComplete;

  const BulkImportVehiclesScreen({
    super.key,
    required this.onCancel,
    required this.onImportComplete,
  });

  @override
  State<BulkImportVehiclesScreen> createState() => _BulkImportVehiclesScreenState();
}

class _BulkImportVehiclesScreenState extends State<BulkImportVehiclesScreen> {
  static const Color primaryColor = Color(0xFF0D47A1);
  
  // ADD THIS LINE - Initialize VehicleService
  final _vehicleService = VehicleService();
  
  FilePickerResult? _selectedFileResult;
  String? _selectedFileName;
  int? _selectedFileSize;
  
  bool _isProcessing = false;
  List<Map<String, dynamic>> _previewData = [];
  List<String> _validationErrors = [];
  int _currentStep = 0;
  int _importedCount = 0;
  int _failedCount = 0; // ADD THIS - Track failed imports
  int _totalCount = 0;
  List<String> _importErrors = []; // ADD THIS - Store import errors

  final List<String> _requiredFields = [
    'Registration Number',
    'Vehicle Type',
    'Make & Model',
    'Year of Manufacture',
    'Engine Type',
    'Engine Capacity (CC)',
    'Seating Capacity',
    'Mileage (km/l)'
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F5F5),
      child: Column(
        children: [
          // Progress indicator
          Container(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                _buildStepIndicator(0, 'Upload', _currentStep >= 0),
                Expanded(child: Container(height: 2, color: _currentStep >= 1 ? primaryColor : Colors.grey.shade300)),
                _buildStepIndicator(1, 'Validate', _currentStep >= 1),
                Expanded(child: Container(height: 2, color: _currentStep >= 2 ? primaryColor : Colors.grey.shade300)),
                _buildStepIndicator(2, 'Import', _currentStep >= 2),
              ],
            ),
          ),

          // Main content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: _buildCurrentStepContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label, bool isActive) {
    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: isActive ? primaryColor : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '${step + 1}',
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? primaryColor : Colors.grey.shade600,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildUploadStep();
      case 1:
        return _buildValidationStep();
      case 2:
        return _buildImportStep();
      default:
        return _buildUploadStep();
    }
  }

  Widget _buildUploadStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Instructions Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: primaryColor),
                    const SizedBox(width: 12),
                    const Text(
                      'Import Instructions',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Prepare your CSV file with the following columns:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ..._requiredFields.map((field) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Row(
                    children: [
                      const Icon(Icons.fiber_manual_record, size: 6, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(field, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                )),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _downloadTemplate,
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Download Template'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _showSampleData,
                      icon: const Icon(Icons.visibility, size: 18),
                      label: const Text('View Sample'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 24),
        
        // File Upload Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                if (_selectedFileResult == null) ...[
                  Container(
                    width: double.infinity,
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey.shade50,
                    ),
                    child: InkWell(
                      onTap: _pickFile,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_upload_outlined, size: 48, color: Colors.grey.shade600),
                          const SizedBox(height: 12),
                          const Text(
                            'Click to upload CSV file',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'or drag and drop here',
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.green.shade300),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.green.shade50,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.insert_drive_file, color: Colors.green.shade700, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedFileName ?? 'Unknown file',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                _selectedFileSize != null 
                                    ? '${(_selectedFileSize! / 1024).toStringAsFixed(1)} KB'
                                    : 'Unknown size',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() {
                            _selectedFileResult = null;
                            _selectedFileName = null;
                            _selectedFileSize = null;
                          }),
                          icon: Icon(Icons.close, color: Colors.red.shade600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _validateFile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Validate File', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildValidationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_validationErrors.isNotEmpty) ...[
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Validation Errors (${_validationErrors.length})',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Column(
                        children: _validationErrors.map((error) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.fiber_manual_record, size: 6, color: Colors.red.shade700),
                              const SizedBox(width: 8),
                              Expanded(child: Text(error, style: TextStyle(color: Colors.red.shade700))),
                            ],
                          ),
                        )).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() => _currentStep = 0),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade600,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Go Back & Fix File'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Preview Data
        if (_previewData.isNotEmpty && _validationErrors.isEmpty) ...[
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'File Validated Successfully',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_previewData.length} vehicles found',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Preview (First 5 rows):',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: _requiredFields.map((field) => DataColumn(
                            label: SizedBox(
                              width: 100,
                              child: Text(
                                field, 
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )).toList(),
                          rows: _previewData.take(5).map((row) => DataRow(
                            cells: _requiredFields.map((field) => DataCell(
                              SizedBox(
                                width: 100,
                                child: Text(
                                  row[field]?.toString() ?? '',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            )).toList(),
                          )).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => setState(() => _currentStep = 0),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Back'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: _proceedToImport,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Proceed to Import', style: TextStyle(fontSize: 16)),
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
        ],
      ],
    );
  }

  Widget _buildImportStep() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (_isProcessing) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Importing vehicles...', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              Text('Progress: $_importedCount / $_totalCount vehicles'),
              if (_failedCount > 0) Text('Failed: $_failedCount', style: TextStyle(color: Colors.red.shade700)),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _totalCount > 0 ? _importedCount / _totalCount : 0,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ] else ...[
              Icon(
                _failedCount == 0 ? Icons.check_circle : Icons.warning,
                size: 64,
                color: _failedCount == 0 ? Colors.green.shade600 : Colors.orange.shade600,
              ),
              const SizedBox(height: 16),
              Text(
                _failedCount == 0 ? 'Import Completed Successfully!' : 'Import Completed with Warnings',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('$_importedCount out of $_totalCount vehicles imported successfully.'),
              if (_failedCount > 0) ...[
                const SizedBox(height: 8),
                Text('$_failedCount vehicles failed to import.', style: TextStyle(color: Colors.red.shade700)),
                const SizedBox(height: 16),
                if (_importErrors.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _importErrors.map((error) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(error, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                        )).toList(),
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: widget.onImportComplete,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Back to Vehicle Master', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );

    if (result != null) {
      setState(() {
        _selectedFileResult = result;
        _selectedFileName = result.files.single.name;
        _selectedFileSize = kIsWeb 
            ? result.files.single.bytes?.length 
            : result.files.single.size;
        _currentStep = 0;
        _validationErrors.clear();
        _previewData.clear();
      });
    }
  }

  void _validateFile() async {
    if (_selectedFileResult == null) return;

    setState(() => _isProcessing = true);

    try {
      String fileContent;
      if (kIsWeb) {
        Uint8List bytes = _selectedFileResult!.files.single.bytes!;
        fileContent = utf8.decode(bytes);
      } else {
        File file = File(_selectedFileResult!.files.single.path!);
        fileContent = await file.readAsString();
      }
      
      List<String> lines = fileContent.split('\n');
      
      if (lines.isEmpty) {
        setState(() {
          _validationErrors = ['File is empty'];
          _isProcessing = false;
          _currentStep = 1;
        });
        return;
      }

      List<List<String>> csvData = [];
      for (String line in lines) {
        if (line.trim().isNotEmpty) {
          List<String> row = line.split(',').map((e) => e.trim().replaceAll('"', '')).toList();
          csvData.add(row);
        }
      }

      if (csvData.isEmpty) {
        setState(() {
          _validationErrors = ['No valid data found in file'];
          _isProcessing = false;
          _currentStep = 1;
        });
        return;
      }

      List<String> headers = csvData[0];
      List<String> errors = [];
      
      for (String requiredField in _requiredFields) {
        if (!headers.contains(requiredField)) {
          errors.add('Missing required column: $requiredField');
        }
      }

      List<Map<String, dynamic>> parsedData = [];
      if (errors.isEmpty) {
        for (int i = 1; i < csvData.length; i++) {
          Map<String, dynamic> row = {};
          for (int j = 0; j < headers.length && j < csvData[i].length; j++) {
            row[headers[j]] = csvData[i][j];
          }
          if (row.values.any((value) => value.toString().isNotEmpty)) {
            parsedData.add(row);
          }
        }

        errors.addAll(_validateDataContent(parsedData));
      }

      setState(() {
        _isProcessing = false;
        _validationErrors = errors;
        _previewData = parsedData;
        _currentStep = 1;
      });

    } catch (e) {
      setState(() {
        _isProcessing = false;
        _validationErrors = ['Error parsing file: $e'];
        _previewData = [];
        _currentStep = 1;
      });
    }
  }

  List<String> _validateDataContent(List<Map<String, dynamic>> data) {
    List<String> errors = [];

    for (int i = 0; i < data.length; i++) {
      Map<String, dynamic> row = data[i];
      String rowNumber = 'Row ${i + 2}';

      String regNo = row['Registration Number']?.toString() ?? '';
      if (regNo.isEmpty) {
        errors.add('$rowNumber: Registration Number is required');
      } else if (!RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z]{1,2}[0-9]{4}$').hasMatch(regNo.toUpperCase())) {
        errors.add('$rowNumber: Invalid Registration Number format ($regNo)');
      }

      String vehicleType = row['Vehicle Type']?.toString() ?? '';
      List<String> validTypes = ['Bus', 'Car', 'Truck', 'Van', 'Mini Bus', 'Motorcycle'];
      if (vehicleType.isEmpty) {
        errors.add('$rowNumber: Vehicle Type is required');
      } else if (!validTypes.contains(vehicleType)) {
        errors.add('$rowNumber: Invalid Vehicle Type. Must be one of: ${validTypes.join(', ')}');
      }

      String makeModel = row['Make & Model']?.toString() ?? '';
      if (makeModel.isEmpty) {
        errors.add('$rowNumber: Make & Model is required');
      }

      String yearStr = row['Year of Manufacture']?.toString() ?? '';
      if (yearStr.isEmpty) {
        errors.add('$rowNumber: Year of Manufacture is required');
      } else {
        int? year = int.tryParse(yearStr);
        int currentYear = DateTime.now().year;
        if (year == null || year < 1990 || year > currentYear + 1) {
          errors.add('$rowNumber: Invalid Year of Manufacture. Must be between 1990 and ${currentYear + 1}');
        }
      }

      String engineType = row['Engine Type']?.toString() ?? '';
      if (engineType.isEmpty) {
        errors.add('$rowNumber: Engine Type is required');
      }

      String engineCapacityStr = row['Engine Capacity (CC)']?.toString() ?? '';
      if (engineCapacityStr.isEmpty) {
        errors.add('$rowNumber: Engine Capacity is required');
      } else {
        double? capacity = double.tryParse(engineCapacityStr);
        if (capacity == null || capacity <= 0) {
          errors.add('$rowNumber: Invalid Engine Capacity. Must be a positive number');
        }
      }

      String seatingCapacityStr = row['Seating Capacity']?.toString() ?? '';
      if (seatingCapacityStr.isEmpty) {
        errors.add('$rowNumber: Seating Capacity is required');
      } else {
        int? seating = int.tryParse(seatingCapacityStr);
        if (seating == null || seating <= 0) {
          errors.add('$rowNumber: Invalid Seating Capacity. Must be a positive integer');
        }
      }

      String mileageStr = row['Mileage (km/l)']?.toString() ?? '';
      if (mileageStr.isEmpty) {
        errors.add('$rowNumber: Mileage is required');
      } else {
        double? mileage = double.tryParse(mileageStr);
        if (mileage == null || mileage <= 0) {
          errors.add('$rowNumber: Invalid Mileage. Must be a positive number');
        }
      }

      if (errors.length >= 20) {
        errors.add('... and more errors. Please fix the above issues first.');
        break;
      }
    }

    return errors;
  }

  void _proceedToImport() {
    setState(() {
      _currentStep = 2;
      _isProcessing = true;
      _totalCount = _previewData.length;
      _importedCount = 0;
      _failedCount = 0;
      _importErrors.clear();
    });

    // Start actual import process
    _importVehiclesToDatabase();
  }

  // REPLACE _simulateImportProgress with this ACTUAL import function
  Future<void> _importVehiclesToDatabase() async {
    for (int i = 0; i < _previewData.length; i++) {
      try {
        Map<String, dynamic> vehicleData = _previewData[i];
        
        // Create vehicle using the service
        // Parse make and model safely
        final makeModelStr = vehicleData['Make & Model']?.toString() ?? '';
        final makeModelParts = makeModelStr.trim().split(' ');
        final make = makeModelParts.isNotEmpty ? makeModelParts.first : 'Unknown';
        final model = makeModelParts.length > 1 ? makeModelParts.skip(1).join(' ') : '';
        
        final result = await _vehicleService.createVehicle(
          registrationNumber: vehicleData['Registration Number']?.toString().toUpperCase() ?? '',
          vehicleType: vehicleData['Vehicle Type']?.toString() ?? '',
          make: make,
          model: model,
          yearOfManufacture: int.tryParse(vehicleData['Year of Manufacture']?.toString() ?? '2020') ?? 2020,
          engineType: vehicleData['Engine Type']?.toString() ?? '',
          engineCapacity: double.tryParse(vehicleData['Engine Capacity (CC)']?.toString() ?? '0') ?? 0.0,
          seatingCapacity: int.tryParse(vehicleData['Seating Capacity']?.toString() ?? '0') ?? 0,
          mileage: double.tryParse(vehicleData['Mileage (km/l)']?.toString() ?? '0') ?? 0.0,
          status: 'Active',
        );

        if (result['success']) {
          if (mounted) {
            setState(() {
              _importedCount++;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _failedCount++;
              _importErrors.add('Row ${i + 2}: ${result['message']}');
            });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _failedCount++;
            _importErrors.add('Row ${i + 2}: Error - ${e.toString()}');
          });
        }
      }

      // Small delay to show progress
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    if (mounted) {
      setState(() => _isProcessing = false);
    }
  }

  void _downloadTemplate() {
    List<List<String>> csvData = [
      _requiredFields,
      [
        'KA01AB1234',
        'Bus',
        'Tata Starbus',
        '2022',
        'Diesel',
        '2200',
        '40',
        '12.5'
      ],
      [
        'KA02CD5678',
        'Car',
        'Maruti Swift',
        '2021',
        'Petrol',
        '1200',
        '5',
        '18.5'
      ],
      [
        'KA03EF9012',
        'Truck',
        'Ashok Leyland',
        '2020',
        'Diesel',
        '5900',
        '3',
        '8.2'
      ],
    ];

    String csvContent = csvData.map((row) => row.join(',')).join('\n');
    _showDownloadDialog(csvContent);
  }

  void _showDownloadDialog(String csvContent) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.download, color: primaryColor),
                    const SizedBox(width: 12),
                    const Text(
                      'CSV Template',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Copy the content below and save it as a .csv file:',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        csvContent,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSampleData() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.table_view, color: primaryColor),
                    const SizedBox(width: 12),
                    const Text(
                      'Sample Data Format',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your CSV file should contain the following columns with sample data:',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Sample CSV Format:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            border: TableBorder.all(color: Colors.grey.shade300),
                            headingRowColor: MaterialStateProperty.all(Colors.grey.shade100),
                            columns: _requiredFields.map((field) => DataColumn(
                              label: SizedBox(
                                width: 120,
                                child: Text(
                                  field,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )).toList(),
                            rows: [
                              DataRow(cells: [
                                const DataCell(Text('KA01AB1234')),
                                const DataCell(Text('Bus')),
                                const DataCell(Text('Tata Starbus')),
                                const DataCell(Text('2022')),
                                const DataCell(Text('Diesel')),
                                const DataCell(Text('2200')),
                                const DataCell(Text('40')),
                                const DataCell(Text('12.5')),
                              ]),
                              DataRow(cells: [
                                const DataCell(Text('KA02CD5678')),
                                const DataCell(Text('Car')),
                                const DataCell(Text('Maruti Swift')),
                                const DataCell(Text('2021')),
                                const DataCell(Text('Petrol')),
                                const DataCell(Text('1200')),
                                const DataCell(Text('5')),
                                const DataCell(Text('18.5')),
                              ]),
                              DataRow(cells: [
                                const DataCell(Text('KA03EF9012')),
                                const DataCell(Text('Truck')),
                                const DataCell(Text('Ashok Leyland')),
                                const DataCell(Text('2020')),
                                const DataCell(Text('Diesel')),
                                const DataCell(Text('5900')),
                                const DataCell(Text('3')),
                                const DataCell(Text('8.2')),
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Field Requirements:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              _buildFieldRequirement('Registration Number', 'Format: XX00XX0000 (e.g., KA01AB1234)'),
                              _buildFieldRequirement('Vehicle Type', 'Options: Bus, Car, Truck, Van, Mini Bus, Motorcycle'),
                              _buildFieldRequirement('Make & Model', 'Vehicle manufacturer and model'),
                              _buildFieldRequirement('Year of Manufacture', 'Year between 1990 and current year'),
                              _buildFieldRequirement('Engine Type', 'e.g., Petrol, Diesel, Electric, Hybrid'),
                              _buildFieldRequirement('Engine Capacity (CC)', 'Numeric value in cubic centimeters'),
                              _buildFieldRequirement('Seating Capacity', 'Number of seats (integer)'),
                              _buildFieldRequirement('Mileage (km/l)', 'Fuel efficiency in kilometers per liter'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldRequirement(String field, String requirement) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.fiber_manual_record, size: 6, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black87, fontSize: 12),
                children: [
                  TextSpan(
                    text: '$field: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: requirement),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}