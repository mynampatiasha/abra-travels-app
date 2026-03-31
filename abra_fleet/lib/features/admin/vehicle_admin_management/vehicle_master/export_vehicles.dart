import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show File;

// Conditional import for web
import 'export_vehicles_web.dart' if (dart.library.io) 'export_vehicles_stub.dart' as web_helper;

class ExportVehiclesScreen extends StatefulWidget {
  final VoidCallback onCancel;
  final List<Map<String, dynamic>>? vehicleData;

  const ExportVehiclesScreen({
    super.key,
    required this.onCancel,
    this.vehicleData,
  });

  @override
  State<ExportVehiclesScreen> createState() => _ExportVehiclesScreenState();
}

class _ExportVehiclesScreenState extends State<ExportVehiclesScreen> {
  static const Color primaryColor = Color(0xFF0D47A1);
  static const Color accentColor = Color(0xFF1565C0);
  static const Color successColor = Color(0xFF2E7D32);
  static const Color warningColor = Color(0xFFE65100);
  
  String _selectedFormat = 'CSV';
  bool _includeHeaders = true;
  bool _isExporting = false;
  int _exportedCount = 0;
  int _totalCount = 0;
  String? _exportContent;
  
  String _selectedVehicleType = 'All';
  String _selectedYearRange = 'All';
  bool _activeVehiclesOnly = false;

  final List<String> _exportFormats = ['CSV', 'JSON', 'Excel'];
  final List<String> _vehicleTypes = ['All', 'Bus', 'Car', 'Truck', 'Van', 'Motorcycle'];
  final List<String> _yearRanges = ['All', '2020-2024', '2015-2019', '2010-2014', 'Before 2010'];

  final List<String> _exportFields = [
    'Registration Number',
    'Vehicle Type',
    'Make & Model',
    'Year of Manufacture',
    'Engine Type',
    'Engine Capacity (CC)',
    'Seating Capacity',
    'Mileage (km/l)',
    'Status',
    'Country',
    'State',
    'City',
    'Last Service Date',
    'Next Service Due'
  ];

  List<String> _selectedFields = [];

  @override
  void initState() {
    super.initState();
    _selectedFields = List.from(_exportFields);
    _totalCount = _getFilteredData().length;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8F9FA), Color(0xFFE9ECEF)],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: _isExporting ? _buildExportingView() : 
               (_exportContent != null ? _buildExportCompleteView() : _buildExportOptionsView()),
      ),
    );
  }

  Widget _buildExportOptionsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEnhancedSectionCard(
          title: 'Export Format',
          subtitle: 'Choose your preferred file format',
          icon: Icons.file_download_outlined,
          iconColor: primaryColor,
          child: Column(
            children: [
              Row(
                children: _exportFormats.map((format) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedFormat = format),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: _selectedFormat == format ? 
                            const LinearGradient(colors: [primaryColor, accentColor]) : null,
                          color: _selectedFormat == format ? null : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedFormat == format ? Colors.transparent : Colors.grey.shade300,
                            width: 2,
                          ),
                          boxShadow: _selectedFormat == format ? [
                            BoxShadow(
                              color: primaryColor.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ] : null,
                        ),
                        child: Center(
                          child: Text(
                            format,
                            style: TextStyle(
                              color: _selectedFormat == format ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Transform.scale(
                      scale: 1.2,
                      child: Checkbox(
                        value: _includeHeaders,
                        onChanged: (value) => setState(() => _includeHeaders = value ?? true),
                        activeColor: primaryColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Include column headers',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Icon(Icons.info_outline, color: Colors.blue.shade600, size: 20),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        _buildEnhancedSectionCard(
          title: 'Filter Options',
          subtitle: 'Customize your export data',
          icon: Icons.tune,
          iconColor: warningColor,
          child: Column(
            children: [
              _buildFilterRow(
                'Vehicle Type:',
                DropdownButtonFormField<String>(
                  value: _selectedVehicleType,
                  decoration: _getInputDecoration(),
                  items: _vehicleTypes.map((type) => DropdownMenuItem(
                    value: type,
                    child: Text(type, style: const TextStyle(fontWeight: FontWeight.w500)),
                  )).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedVehicleType = value!;
                      _updateTotalCount();
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),

              _buildFilterRow(
                'Year Range:',
                DropdownButtonFormField<String>(
                  value: _selectedYearRange,
                  decoration: _getInputDecoration(),
                  items: _yearRanges.map((range) => DropdownMenuItem(
                    value: range,
                    child: Text(range, style: const TextStyle(fontWeight: FontWeight.w500)),
                  )).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedYearRange = value!;
                      _updateTotalCount();
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _activeVehiclesOnly ? successColor.withOpacity(0.1) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _activeVehiclesOnly ? successColor : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Transform.scale(
                      scale: 1.2,
                      child: Checkbox(
                        value: _activeVehiclesOnly,
                        onChanged: (value) {
                          setState(() {
                            _activeVehiclesOnly = value ?? false;
                            _updateTotalCount();
                          });
                        },
                        activeColor: successColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Active vehicles only',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.check_circle_outline,
                      color: _activeVehiclesOnly ? successColor : Colors.grey.shade400,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        _buildEnhancedSectionCard(
          title: 'Select Fields to Export',
          subtitle: 'Choose which data columns to include',
          icon: Icons.view_column,
          iconColor: Colors.purple.shade600,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildSmallButton(
                      'Select All',
                      Icons.check_box,
                      primaryColor,
                      () => setState(() => _selectedFields = List.from(_exportFields)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSmallButton(
                      'Clear All',
                      Icons.check_box_outline_blank,
                      Colors.grey.shade600,
                      () => setState(() => _selectedFields.clear()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _exportFields.map((field) => FilterChip(
                  label: Text(
                    field,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _selectedFields.contains(field) ? Colors.white : Colors.black87,
                    ),
                  ),
                  selected: _selectedFields.contains(field),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedFields.add(field);
                      } else {
                        _selectedFields.remove(field);
                      }
                    });
                  },
                  backgroundColor: Colors.grey.shade100,
                  selectedColor: primaryColor,
                  checkmarkColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: _selectedFields.contains(field) ? 4 : 0,
                )).toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        _buildEnhancedSectionCard(
          title: 'Export Summary',
          subtitle: 'Review your export configuration',
          icon: Icons.summarize,
          iconColor: successColor,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade50, Colors.indigo.shade50],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildEnhancedSummaryRow('Format:', _selectedFormat, Icons.file_copy),
                _buildEnhancedSummaryRow('Records:', '$_totalCount vehicles', Icons.storage),
                _buildEnhancedSummaryRow('Fields:', '${_selectedFields.length} selected', Icons.view_column),
                if (_selectedVehicleType != 'All') 
                  _buildEnhancedSummaryRow('Vehicle Type:', _selectedVehicleType, Icons.directions_bus),
                if (_selectedYearRange != 'All') 
                  _buildEnhancedSummaryRow('Year Range:', _selectedYearRange, Icons.calendar_today),
                if (_activeVehiclesOnly) 
                  _buildEnhancedSummaryRow('Status:', 'Active only', Icons.check_circle),
              ],
            ),
          ),
        ),

        const SizedBox(height: 32),

        Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: _selectedFields.isEmpty ? null : const LinearGradient(
              colors: [primaryColor, accentColor],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            color: _selectedFields.isEmpty ? Colors.grey.shade300 : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: _selectedFields.isEmpty ? null : [
              BoxShadow(
                color: primaryColor.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: _selectedFields.isEmpty ? null : _startExport,
            icon: const Icon(Icons.download_rounded, size: 24),
            label: const Text(
              'Export Data',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),

        if (_selectedFields.isEmpty)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red.shade600, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Please select at least one field to export',
                  style: TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildExportingView() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade50, Colors.indigo.shade50],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Exporting Data...',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'Processing $_exportedCount of $_totalCount records',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                ),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey.shade200,
                  ),
                  child: LinearProgressIndicator(
                    value: _totalCount > 0 ? _exportedCount / _totalCount : 0,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(primaryColor),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${((_totalCount > 0 ? _exportedCount / _totalCount : 0) * 100).toInt()}% Complete',
                  style: const TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExportCompleteView() {
    return Column(
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade50, Colors.blue.shade50],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: successColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: successColor,
                      size: 50,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Export Complete!',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$_totalCount vehicles exported successfully.',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          'Download',
                          Icons.download_rounded,
                          successColor,
                          _downloadFile,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildActionButton(
                          'Share',
                          Icons.share_rounded,
                          Colors.blue.shade600,
                          _shareFile,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: _buildActionButton(
                      'Close',
                      Icons.close_rounded,
                      Colors.grey.shade600,
                      widget.onCancel,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 20),
        
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.grey.shade100, Colors.grey.shade50],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.preview_rounded, color: primaryColor),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Export Preview',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${_selectedFormat.toUpperCase()} Format',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _exportContent!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEnhancedSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.white, Colors.grey.shade50],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconColor, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterRow(String label, Widget dropdown) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: dropdown),
      ],
    );
  }

  Widget _buildSmallButton(String text, IconData icon, Color color, VoidCallback onPressed) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: color),
        label: Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }

  Widget _buildActionButton(String text, IconData icon, Color color, VoidCallback onPressed) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.8)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildEnhancedSummaryRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: primaryColor, size: 20),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _getInputDecoration() {
    return InputDecoration(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      filled: true,
      fillColor: Colors.grey.shade50,
    );
  }

  List<Map<String, dynamic>> _getFilteredData() {
    List<Map<String, dynamic>> sampleData = [
      {
        'Registration Number': 'KA01AB1234',
        'Vehicle Type': 'Bus',
        'Make & Model': 'Tata Starbus',
        'Year of Manufacture': '2022',
        'Engine Type': 'Diesel',
        'Engine Capacity (CC)': '2200',
        'Seating Capacity': '40',
        'Mileage (km/l)': '12.5',
        'Status': 'Active',
        'Country': 'India',
        'State': 'Karnataka',
        'City': 'Bangalore',
        'Last Service Date': '2024-01-15',
        'Next Service Due': '2024-04-15'
      },
      {
        'Registration Number': 'KA02CD5678',
        'Vehicle Type': 'Car',
        'Make & Model': 'Maruti Swift',
        'Year of Manufacture': '2021',
        'Engine Type': 'Petrol',
        'Engine Capacity (CC)': '1200',
        'Seating Capacity': '5',
        'Mileage (km/l)': '18.5',
        'Status': 'Active',
        'Country': 'India',
        'State': 'Karnataka',
        'City': 'Mysore',
        'Last Service Date': '2024-02-20',
        'Next Service Due': '2024-05-20'
      },
      {
        'Registration Number': 'KA03EF9012',
        'Vehicle Type': 'Truck',
        'Make & Model': 'Ashok Leyland',
        'Year of Manufacture': '2020',
        'Engine Type': 'Diesel',
        'Engine Capacity (CC)': '5900',
        'Seating Capacity': '3',
        'Mileage (km/l)': '8.2',
        'Status': 'Inactive',
        'Country': 'India',
        'State': 'Karnataka',
        'City': 'Hubli',
        'Last Service Date': '2023-12-10',
        'Next Service Due': '2024-03-10'
      },
    ];

    List<Map<String, dynamic>> data = widget.vehicleData ?? sampleData;

    return data.where((vehicle) {
      if (_selectedVehicleType != 'All' && vehicle['Vehicle Type'] != _selectedVehicleType) {
        return false;
      }

      if (_selectedYearRange != 'All') {
        int year = int.tryParse(vehicle['Year of Manufacture']?.toString() ?? '0') ?? 0;
        switch (_selectedYearRange) {
          case '2020-2024':
            if (year < 2020 || year > 2024) return false;
            break;
          case '2015-2019':
            if (year < 2015 || year > 2019) return false;
            break;
          case '2010-2014':
            if (year < 2010 || year > 2014) return false;
            break;
          case 'Before 2010':
            if (year >= 2010) return false;
            break;
        }
      }

      if (_activeVehiclesOnly && vehicle['Status'] != 'Active') {
        return false;
      }

      return true;
    }).toList();
  }

  void _updateTotalCount() {
    setState(() {
      _totalCount = _getFilteredData().length;
    });
  }

  void _startExport() async {
    setState(() {
      _isExporting = true;
      _exportedCount = 0;
    });

    List<Map<String, dynamic>> dataToExport = _getFilteredData();
    
    for (int i = 0; i < dataToExport.length; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        setState(() => _exportedCount = i + 1);
      }
    }

    String exportContent = _generateExportContent(dataToExport);
    
    setState(() {
      _exportContent = exportContent;
      _isExporting = false;
    });
  }

  String _generateExportContent(List<Map<String, dynamic>> data) {
    switch (_selectedFormat) {
      case 'CSV':
        return _generateCSV(data);
      case 'JSON':
        return _generateJSON(data);
      case 'Excel':
        return _generateCSV(data);
      default:
        return _generateCSV(data);
    }
  }

  String _generateCSV(List<Map<String, dynamic>> data) {
    List<List<String>> csvData = [];
    
    if (_includeHeaders) {
      csvData.add(_selectedFields);
    }
    
    for (var vehicle in data) {
      List<String> row = [];
      for (String field in _selectedFields) {
        String value = vehicle[field]?.toString() ?? '';
        if (value.contains(',') || value.contains('\n') || value.contains('"')) {
          value = '"${value.replaceAll('"', '""')}"';
        }
        row.add(value);
      }
      csvData.add(row);
    }
    
    return csvData.map((row) => row.join(',')).join('\n');
  }

  String _generateJSON(List<Map<String, dynamic>> data) {
    List<Map<String, dynamic>> exportData = [];
    
    for (var vehicle in data) {
      Map<String, dynamic> filteredVehicle = {};
      for (String field in _selectedFields) {
        filteredVehicle[field] = vehicle[field];
      }
      exportData.add(filteredVehicle);
    }
    
    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  Future<void> _downloadFile() async {
    if (_exportContent == null) return;

    final String fileName = _generateFileName();
    final bytes = Uint8List.fromList(utf8.encode(_exportContent!));
    final mimeType = _getMimeType();

    try {
      if (kIsWeb) {
        // Web implementation using helper
        web_helper.downloadFileWeb(bytes, fileName, mimeType);
        _showSuccessMessage('File downloaded successfully!');
      } else {
        // Mobile implementation
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(bytes);
        
        await Share.shareXFiles([XFile(file.path)], text: 'Export Vehicles');
        _showSuccessMessage('File saved successfully!');
      }
    } catch (e) {
      _showErrorMessage('Failed to download file: $e');
    }
  }

  Future<void> _shareFile() async {
    if (_exportContent == null) return;

    try {
      final String fileName = _generateFileName();
      
      if (kIsWeb) {
        _showShareDialog();
      } else {
        try {
          final directory = await getTemporaryDirectory();
          final file = File('${directory.path}/$fileName');
          await file.writeAsBytes(utf8.encode(_exportContent!));
          
          await Share.shareXFiles([XFile(file.path)], text: 'Export Vehicles');
          _showSuccessMessage('File shared successfully!');
        } catch (e) {
          _showErrorMessage('Failed to share file: $e');
        }
      }
    } catch (e) {
      _showShareDialog();
    }
  }

  void _showShareDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.share_rounded, color: Colors.blue.shade600, size: 28),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share Export Data',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Choose how to share your exported data',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              Column(
                children: [
                  _buildShareOption(
                    'Download File',
                    'Save to your device',
                    Icons.download_rounded,
                    Colors.green.shade600,
                    () {
                      Navigator.pop(context);
                      _downloadFile();
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildShareOption(
                    'Copy to Clipboard',
                    'Copy data to clipboard',
                    Icons.copy_rounded,
                    Colors.blue.shade600,
                    () {
                      Navigator.pop(context);
                      _copyToClipboard();
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildShareOption(
                    'Email',
                    'Send via email',
                    Icons.email_rounded,
                    Colors.orange.shade600,
                    () {
                      Navigator.pop(context);
                      _openEmailClient();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShareOption(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _copyToClipboard() async {
    if (_exportContent == null) return;
    
    try {
      await Clipboard.setData(ClipboardData(text: _exportContent!));
      _showSuccessMessage('Data copied to clipboard!');
    } catch (e) {
      _showErrorMessage('Failed to copy to clipboard: $e');
    }
  }

  Future<void> _openEmailClient() async {
    if (_exportContent == null) return;
    
    final fileName = _generateFileName();
    final subject = Uri.encodeComponent('Vehicle Export Data - $fileName');
    final body = Uri.encodeComponent(
      'Hello,\n\nPlease find the exported vehicle data.\n\n'
      'File: $fileName\nFormat: ${_selectedFormat.toUpperCase()}\n'
      'Records: $_totalCount vehicles\n\n'
      'Data:\n$_exportContent'
    );
    
    final mailtoUrl = 'mailto:?subject=$subject&body=$body';
    
    try {
      final uri = Uri.parse(mailtoUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        _showSuccessMessage('Email client opened!');
      } else {
        _showErrorMessage('Could not open email client');
      }
    } catch (e) {
      _showErrorMessage('Failed to open email client: $e');
    }
  }

  String _generateFileName() {
    final now = DateTime.now();
    final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    
    String extension = _selectedFormat.toLowerCase();
    if (_selectedFormat == 'Excel') {
      extension = 'csv';
    }
    
    return 'vehicles_export_$timestamp.$extension';
  }

  String _getMimeType() {
    switch (_selectedFormat) {
      case 'CSV':
      case 'Excel':
        return 'text/csv';
      case 'JSON':
        return 'application/json';
      default:
        return 'text/plain';
    }
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        backgroundColor: successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}