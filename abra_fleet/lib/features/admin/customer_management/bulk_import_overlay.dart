import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:abra_fleet/features/admin/customer_management/presentation/providers/customer_provider.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'dart:io';

class BulkImportOverlay extends StatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onImported;

  const BulkImportOverlay({
    Key? key,
    required this.onClose,
    required this.onImported,
  }) : super(key: key);

  @override
  State<BulkImportOverlay> createState() => _BulkImportOverlayState();
}

class _BulkImportOverlayState extends State<BulkImportOverlay> {
  FilePickerResult? _selectedFileResult;
  String? _fileName;
  int? _selectedFileSize;
  List<Map<String, dynamic>>? _parsedData;
  
  bool _isLoading = false;
  bool _isImporting = false;
  int _currentStep = 0;
  String? _errorMessage;
  List<String> _validationErrors = [];
  
  // Import results
  int _successCount = 0;
  int _failedCount = 0;
  int _totalCount = 0;
  List<String> _errors = [];

  final List<String> _requiredFields = [
    'name',
    'email',
    'phoneNumber',
    'companyName',
    'department',
    'branch',
    'status'
  ];

  final List<String> _optionalFields = [
    'employeeId',
    'designation',
    'alternativePhone',
    'emergencyContactName',
    'emergencyContactPhone'
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.5),
      child: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.75,
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xFF0D47A1), // Match client_main_shell primary color
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.upload_file, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    const Text(
                      'Bulk Import Customers',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),

              // Stepper
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    _buildStepIndicator(0, 'Upload', Icons.upload_file),
                    _buildStepConnector(0),
                    _buildStepIndicator(1, 'Validate', Icons.check_circle_outline),
                    _buildStepConnector(1),
                    _buildStepIndicator(2, 'Import', Icons.cloud_done),
                  ],
                ),
              ),

              const Divider(thickness: 2, height: 1),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: _buildStepContent(),
                ),
              ),

              // Footer
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300),
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: _buildFooterActions(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label, IconData icon) {
    final isActive = step == _currentStep;
    final isCompleted = step < _currentStep;

    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: isCompleted
                ? const Color(0xFF10B981)
                : isActive
                    ? const Color(0xFF0D47A1) // Match client_main_shell primary color
                    : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isCompleted ? Icons.check : icon,
            color: Colors.white,
            size: 30,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? const Color(0xFF0D47A1) : Colors.grey, // Match primary color
          ),
        ),
      ],
    );
  }

  Widget _buildStepConnector(int step) {
    final isCompleted = step < _currentStep;
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 30),
        color: isCompleted ? const Color(0xFF10B981) : Colors.grey.shade300,
      ),
    );
  }

  Widget _buildStepContent() {
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
        // Instructions
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: const Color(0xFF2563EB)),
                  const SizedBox(width: 8),
                  const Text(
                    'File Format Requirements',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Upload a CSV file with the following columns:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              _buildRequirementItem('name - Full name of the customer', true),
              _buildRequirementItem('email - Valid email address', true),
              _buildRequirementItem('phoneNumber - Contact number', true),
              _buildRequirementItem('companyName - Company/Organization name', true),
              _buildRequirementItem('department - Department name', true),
              _buildRequirementItem('branch - Branch location (e.g., Bangalore, Chennai)', true),
              _buildRequirementItem('status - Active, Inactive, or Pending', true),
              const SizedBox(height: 8),
              const Text(
                'Optional fields:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              _buildRequirementItem('employeeId - Employee identification', false),
              _buildRequirementItem('designation - Job title/position', false),
              _buildRequirementItem('alternativePhone - Secondary contact', false),
              _buildRequirementItem('emergencyContactName - Emergency contact name', false),
              _buildRequirementItem('emergencyContactPhone - Emergency contact number', false),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // Download Template
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _downloadTemplate,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download CSV Template'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0D47A1), // Match client_main_shell primary color
                side: const BorderSide(color: Color(0xFF0D47A1)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _showSampleData,
              icon: const Icon(Icons.visibility, size: 18),
              label: const Text('View Sample Data'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2563EB),
                side: const BorderSide(color: Color(0xFF2563EB)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 32),

        // Upload Area
        if (_selectedFileResult == null) ...[
          GestureDetector(
            onTap: _pickFile,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFF0D47A1), // Match client_main_shell primary color
                  width: 2,
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFF0D47A1).withOpacity(0.05),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.cloud_upload,
                    size: 64,
                    color: const Color(0xFF0D47A1), // Match primary color
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Click to browse or drag and drop',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Supports: CSV files only',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.green.shade300),
              borderRadius: BorderRadius.circular(12),
              color: Colors.green.shade50,
            ),
            child: Row(
              children: [
                Icon(Icons.insert_drive_file, color: Colors.green.shade700, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fileName ?? 'Unknown file',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedFileSize != null 
                            ? '${(_selectedFileSize! / 1024).toStringAsFixed(1)} KB'
                            : 'Unknown size',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _selectedFileResult = null;
                    _fileName = null;
                    _selectedFileSize = null;
                    _errorMessage = null;
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
              onPressed: _isLoading ? null : _validateFile,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D47A1), // Match client_main_shell primary color
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Validate File',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],

        if (_errorMessage != null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRequirementItem(String text, bool required) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            required ? Icons.check_circle : Icons.info_outline,
            size: 16,
            color: required ? const Color(0xFF10B981) : const Color(0xFF0D47A1), // Match primary color
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildValidationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_validationErrors.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700, size: 24),
                    const SizedBox(width: 12),
                    Text(
                      'Validation Errors (${_validationErrors.length})',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _validationErrors.map((error) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.fiber_manual_record, size: 8, color: Colors.red.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  error,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => setState(() {
                    _currentStep = 0;
                    _validationErrors.clear();
                  }),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Go Back & Fix File'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],

        if (_parsedData != null && _parsedData!.isNotEmpty && _validationErrors.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: const Color(0xFF10B981), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'File Validated Successfully',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Found ${_parsedData!.length} customers to import',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          const Text(
            'Preview (First 5 records)',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 16),

          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: MaterialStateProperty.all(
                  const Color(0xFFF8FAFC),
                ),
                headingRowHeight: 56,
                dataRowHeight: 60,
                columnSpacing: 40,
                columns: [
                  DataColumn(
                    label: SizedBox(
                      width: 120,
                      child: Text(
                        'Name',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: SizedBox(
                      width: 150,
                      child: Text(
                        'Email',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: SizedBox(
                      width: 120,
                      child: Text(
                        'Phone',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: SizedBox(
                      width: 130,
                      child: Text(
                        'Company',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: SizedBox(
                      width: 120,
                      child: Text(
                        'Department',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: SizedBox(
                      width: 120,
                      child: Text(
                        'Branch',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: SizedBox(
                      width: 90,
                      child: Text(
                        'Status',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
                rows: _parsedData!.take(5).map((record) {
                  return DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: Text(
                            record['name'] ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 150,
                          child: Text(
                            record['email'] ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: Text(
                            record['phoneNumber'] ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 130,
                          child: Text(
                            record['companyName'] ?? 'N/A',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: Text(
                            record['department'] ?? 'N/A',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: Text(
                            record['branch'] ?? 'N/A',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 90,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getStatusColor(record['status'] ?? 'Pending').withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              record['status'] ?? 'Pending',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _getStatusColor(record['status'] ?? 'Pending'),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return const Color(0xFF10B981);
      case 'inactive':
        return const Color(0xFFEF4444);
      case 'pending':
        return const Color(0xFFF59E0B);
      default:
        return Colors.grey;
    }
  }

  Widget _buildImportStep() {
    if (_isImporting) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              strokeWidth: 6,
              color: Color(0xFF0D47A1), // Match client_main_shell primary color
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Importing customers...',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Progress: $_successCount / ${_parsedData?.length ?? 0} customers',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          if (_failedCount > 0)
            Text(
              'Failed: $_failedCount',
              style: TextStyle(
                fontSize: 14,
                color: Colors.red.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 100),
            child: LinearProgressIndicator(
              value: _parsedData != null && _parsedData!.isNotEmpty
                  ? _successCount / _parsedData!.length
                  : 0,
              backgroundColor: Colors.grey.shade300,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0D47A1)), // Match primary color
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      );
    }

    // Show results
    return Column(
      children: [
        Icon(
          _failedCount == 0 ? Icons.check_circle : Icons.warning,
          size: 80,
          color: _failedCount == 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
        ),
        const SizedBox(height: 24),
        Text(
          _failedCount == 0 ? 'Import Completed!' : 'Import Completed with Errors',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _failedCount == 0
              ? 'All customers have been imported successfully'
              : 'Some customers could not be imported',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 32),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildResultCard(
              'Successful',
              _successCount.toString(),
              const Color(0xFF10B981),
              Icons.check_circle,
            ),
            const SizedBox(width: 24),
            _buildResultCard(
              'Failed',
              _failedCount.toString(),
              const Color(0xFFEF4444),
              Icons.error,
            ),
            const SizedBox(width: 24),
            _buildResultCard(
              'Total',
              _totalCount.toString(),
              const Color(0xFF0D47A1), // Match client_main_shell primary color
              Icons.people,
            ),
          ],
        ),

        if (_errors.isNotEmpty) ...[
          const SizedBox(height: 32),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700, size: 24),
                    const SizedBox(width: 12),
                    Text(
                      'Import Errors (${_errors.length})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _errors.map((error) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.fiber_manual_record, size: 8, color: Colors.red.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  error,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResultCard(String label, String value, Color color, IconData icon) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterActions() {
    if (_currentStep == 2 && !_isImporting) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton.icon(
            onPressed: widget.onImported,
            icon: const Icon(Icons.check_circle),
            label: const Text('Done'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (_currentStep > 0)
          OutlinedButton.icon(
            onPressed: _isLoading || _isImporting ? null : () {
              setState(() => _currentStep--);
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: _isLoading || _isImporting ? null : widget.onClose,
          icon: const Icon(Icons.close),
          label: const Text('Cancel'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: _isLoading || _isImporting || (_currentStep == 0 && _parsedData == null)
              ? null
              : _handleNext,
          icon: Icon(_currentStep == 1 ? Icons.cloud_upload : Icons.arrow_forward),
          label: Text(
            _currentStep == 1 ? 'Start Import' : 'Next',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D47A1), // Match client_main_shell primary color
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedFileResult = result;
          _fileName = result.files.first.name;
          _selectedFileSize = kIsWeb 
              ? result.files.first.bytes?.length 
              : result.files.first.size;
          _errorMessage = null;
          _validationErrors.clear();
          _parsedData = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading file: ${e.toString()}';
      });
    }
  }

  Future<void> _validateFile() async {
    if (_selectedFileResult == null) return;

    setState(() => _isLoading = true);

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
          _isLoading = false;
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
          _isLoading = false;
          _currentStep = 1;
        });
        return;
      }

      List<String> headers = csvData[0];
      List<String> errors = [];
      
      // Check for required fields
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

        // Validate data content
        errors.addAll(_validateDataContent(parsedData));
      }

      setState(() {
        _isLoading = false;
        _validationErrors = errors;
        _parsedData = parsedData;
        _currentStep = 1;
      });

    } catch (e) {
      setState(() {
        _isLoading = false;
        _validationErrors = ['Error parsing file: $e'];
        _parsedData = null;
        _currentStep = 1;
      });
    }
  }

  List<String> _validateDataContent(List<Map<String, dynamic>> data) {
  List<String> errors = [];

  for (int i = 0; i < data.length; i++) {
    Map<String, dynamic> row = data[i];
    String rowNumber = 'Row ${i + 2}';

    // Validate name
    String name = row['name']?.toString() ?? '';
    if (name.isEmpty) {
      errors.add('$rowNumber: Name is required');
    }

    // Validate email
    String email = row['email']?.toString() ?? '';
    if (email.isEmpty) {
      errors.add('$rowNumber: Email is required');
    } else if (!RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$').hasMatch(email)) {
      errors.add('$rowNumber: Invalid email format ($email)');
    }

    // Validate phone number
    String phone = row['phoneNumber']?.toString() ?? '';
    if (phone.isEmpty) {
      errors.add('$rowNumber: Phone number is required');
    }

    // Validate company name
    String company = row['companyName']?.toString() ?? '';
    if (company.isEmpty) {
      errors.add('$rowNumber: Company name is required');
    }

    // Validate department
    String department = row['department']?.toString() ?? '';
    if (department.isEmpty) {
      errors.add('$rowNumber: Department is required');
    }

    // Validate branch
    String branch = row['branch']?.toString() ?? '';
    if (branch.isEmpty) {
      errors.add('$rowNumber: Branch is required');
    }

    // Validate status
    String status = row['status']?.toString() ?? '';
    List<String> validStatuses = ['Active', 'Inactive', 'Pending'];
    if (status.isEmpty) {
      errors.add('$rowNumber: Status is required');
    } else if (!validStatuses.contains(status)) {
      errors.add('$rowNumber: Invalid status. Must be one of: ${validStatuses.join(', ')}');
    }

    // Stop at 20 errors
    if (errors.length >= 20) {
      errors.add('... and more errors. Please fix the above issues first.');
      break;
    }
  }

  return errors;
}

  void _downloadTemplate() {
    List<List<String>> csvData = [
      _requiredFields + _optionalFields,
      [
        'John Doe',
        'john.doe@example.com',
        '+1234567890',
        'Tech Corp',
        'Engineering',
        'Bangalore',
        'Active',
        'EMP001',
        'Senior Developer',
        '+1234567891',
        'Jane Doe',
        '+1234567892'
      ],
      [
        'Alice Smith',
        'alice.smith@example.com',
        '+1234567893',
        'Innovation Inc',
        'Marketing',
        'Chennai',
        'Active',
        'EMP002',
        'Marketing Manager',
        '',
        '',
        ''
      ],
      [
        'Bob Johnson',
        'bob.johnson@example.com',
        '+1234567894',
        'Solutions Ltd',
        'Sales',
        'Mumbai',
        'Pending',
        '',
        'Sales Executive',
        '',
        '',
        ''
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
            maxWidth: MediaQuery.of(context).size.width * 0.7,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.download, color: const Color(0xFF0D47A1)), // Match primary color
                    const SizedBox(width: 12),
                    const Text(
                      'CSV Template',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
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
                    padding: const EdgeInsets.all(16),
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
                      backgroundColor: const Color(0xFF0D47A1), // Match client_main_shell primary color
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
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
            maxWidth: MediaQuery.of(context).size.width * 0.8,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.table_view, color: const Color(0xFF0D47A1)), // Match primary color
                    const SizedBox(width: 12),
                    const Text(
                      'Sample Data Format',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D47A1).withOpacity(0.1), // Match primary color
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Sample CSV Format:',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            border: TableBorder.all(color: Colors.grey.shade300),
                            headingRowColor: MaterialStateProperty.all(Colors.grey.shade100),
                            columns: (_requiredFields + _optionalFields).map((field) => DataColumn(
                              label: SizedBox(
                                width: 100,
                                child: Text(
                                  field,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )).toList(),
                            rows: [
                              DataRow(cells: [
                                const DataCell(Text('John Doe', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('john.doe@example.com', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('+1234567890', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('Tech Corp', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('Engineering', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('Bangalore', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('Active', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('EMP001', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('Senior Developer', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('+1234567891', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('Jane Doe', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('+1234567892', style: TextStyle(fontSize: 12))),
                              ]),
                              DataRow(cells: [
                                const DataCell(Text('Alice Smith', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('alice.smith@example.com', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('+1234567893', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('Innovation Inc', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('Marketing', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('Chennai', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('Active', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('EMP002', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('Marketing Manager', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('', style: TextStyle(fontSize: 12))),
                                const DataCell(Text('', style: TextStyle(fontSize: 12))),
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Field Requirements:',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                              const SizedBox(height: 12),
                              _buildFieldRequirement('name', 'Full name of the customer (Required)', true),
                              _buildFieldRequirement('email', 'Valid email address (Required)', true),
                              _buildFieldRequirement('phoneNumber', 'Contact phone number (Required)', true),
                              _buildFieldRequirement('companyName', 'Company/Organization name (Required)', true),
                              _buildFieldRequirement('department', 'Department name (Required)', true),
                              _buildFieldRequirement('branch', 'Branch location like Bangalore, Chennai (Required)', true),
                              _buildFieldRequirement('status', 'Active, Inactive, or Pending (Required)', true),
                              const SizedBox(height: 8),
                              const Text(
                                'Optional Fields:',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              const SizedBox(height: 8),
                              _buildFieldRequirement('employeeId', 'Employee identification number', false),
                              _buildFieldRequirement('designation', 'Job title or position', false),
                              _buildFieldRequirement('alternativePhone', 'Secondary contact number', false),
                              _buildFieldRequirement('emergencyContactName', 'Emergency contact name', false),
                              _buildFieldRequirement('emergencyContactPhone', 'Emergency contact phone', false),
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
                      backgroundColor: const Color(0xFF0D47A1), // Match client_main_shell primary color
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
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

  Widget _buildFieldRequirement(String field, String requirement, bool isRequired) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isRequired ? Icons.check_circle : Icons.info_outline,
            size: 14,
            color: isRequired ? const Color(0xFF10B981) : const Color(0xFF0D47A1), // Match primary color
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black87, fontSize: 13),
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

  Future<void> _handleNext() async {
    if (_currentStep < 1) {
      setState(() => _currentStep++);
    } else if (_currentStep == 1) {
      await _performImport();
    }
  }

  Future<void> _performImport() async {
    setState(() {
      _isImporting = true;
      _currentStep = 2;
      _successCount = 0;
      _failedCount = 0;
      _totalCount = _parsedData?.length ?? 0;
      _errors.clear();
    });

    try {
      final provider = Provider.of<CustomerProvider>(context, listen: false);

      for (int i = 0; i < _parsedData!.length; i++) {
        try {
          final record = _parsedData![i];
          
          final result = await provider.createCustomer(
            name: record['name']?.toString() ?? '',
            email: record['email']?.toString() ?? '',
            phone: record['phoneNumber']?.toString() ?? '',
            company: record['companyName']?.toString() ?? '',
            address: null,
            department: record['department']?.toString(),
            branch: record['branch']?.toString(), // Add branch field
            employeeId: record['employeeId']?.toString(),
            password: 'Customer@123',
          );

if (result['success'] == true) {
  setState(() => _successCount++);
          } else {
            setState(() {
              _failedCount++;
              _errors.add('Row ${i + 2}: ${provider.errorMessage ?? "Failed to import customer"}');
            });
          }
        } catch (e) {
          setState(() {
            _failedCount++;
            _errors.add('Row ${i + 2}: Error - ${e.toString()}');
          });
        }

        // Small delay to show progress
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }
}