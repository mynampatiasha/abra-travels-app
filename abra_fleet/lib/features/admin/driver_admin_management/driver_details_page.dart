// lib/features/admin/driver_admin_management/driver_details_page.dart
// ✅ COMPLETE - Driver Details with Document Upload/Download/Delete

import 'dart:io' if (dart.library.html) 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:abra_fleet/core/services/driver_service.dart';

class DriverDetailsPage extends StatefulWidget {
  final Map<String, dynamic> driver;

  const DriverDetailsPage({
    Key? key,
    required this.driver,
  }) : super(key: key);

  @override
  State<DriverDetailsPage> createState() => _DriverDetailsPageState();
}

class _DriverDetailsPageState extends State<DriverDetailsPage> {
  final DriverService _driverService = DriverService();
  bool _isLoading = false;
  List<dynamic> _documents = [];

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  void _loadDocuments() {
    setState(() {
      _documents = widget.driver['documents'] ?? [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FA),
      appBar: AppBar(
        title: Text(widget.driver['name'] ?? _getNestedValue(widget.driver, 'personalInfo.name', 'Driver Details')),
        backgroundColor: const Color(0xFF1B7FA8),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Driver',
            onPressed: () {
              // Navigate back and pass a flag to open edit dialog
              Navigator.pop(context, {'action': 'edit', 'driver': widget.driver});
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Personal Information Card
            _buildSectionCard(
              title: 'Personal Information',
              icon: Icons.person,
              children: [
                _buildInfoRow('Driver ID', widget.driver['driverId'] ?? 'N/A'),
                _buildInfoRow('Name', widget.driver['name'] ?? _getNestedValue(widget.driver, 'personalInfo.name', 'N/A')),
                _buildInfoRow('Email', widget.driver['email'] ?? _getNestedValue(widget.driver, 'personalInfo.email', 'N/A')),
                _buildInfoRow('Phone', widget.driver['phone'] ?? _getNestedValue(widget.driver, 'personalInfo.phone', 'N/A')),
                _buildInfoRow('Status', widget.driver['status'] ?? 'inactive', isStatus: true),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // License Information Card
            _buildSectionCard(
              title: 'License Information',
              icon: Icons.credit_card,
              children: [
                _buildInfoRow('License Number', _getNestedValue(widget.driver, 'license.licenseNumber')),
                _buildInfoRow('License Expiry', _formatDate(widget.driver['licenseExpiry']?.toString() ?? _getNestedValue(widget.driver, 'license.expiryDate'))),
                _buildInfoRow('License Type', _getNestedValue(widget.driver, 'license.licenseType')),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Vehicle Information Card
            _buildSectionCard(
              title: 'Vehicle Information',
              icon: Icons.directions_car,
              children: [
                _buildInfoRow('Vehicle Number', widget.driver['vehicleNumber'] ?? _getNestedValue(widget.driver, 'assignedVehicle.vehicleNumber', 'Not Assigned')),
                _buildInfoRow('Vehicle Type', _getNestedValue(widget.driver, 'assignedVehicle.vehicleType', 'N/A')),
                _buildInfoRow('Vehicle Model', _getNestedValue(widget.driver, 'assignedVehicle.model', 'N/A')),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Statistics Card
            _buildSectionCard(
              title: 'Statistics',
              icon: Icons.analytics,
              children: [
                _buildInfoRow('Total Trips', widget.driver['totalTrips']?.toString() ?? '0'),
                _buildInfoRow('Rating', _getRating(widget.driver)),
                _buildInfoRow('Feedback Count', _getFeedbackCount(widget.driver)),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // ✅ NEW: Documents Card
            _buildDocumentsCard(),
            
            const SizedBox(height: 20),
            
            // Emergency Contact Card (if available)
            if (widget.driver['emergencyContact'] != null)
              _buildSectionCard(
                title: 'Emergency Contact',
                icon: Icons.emergency,
                children: [
                  _buildInfoRow('Name', _getNestedValue(widget.driver, 'emergencyContact.name')),
                  _buildInfoRow('Phone', _getNestedValue(widget.driver, 'emergencyContact.phone')),
                  _buildInfoRow('Relationship', _getNestedValue(widget.driver, 'emergencyContact.relationship')),
                ],
              ),
            
            const SizedBox(height: 20),
            
            // Address Card (if available)
            if (widget.driver['address'] != null)
              _buildSectionCard(
                title: 'Address',
                icon: Icons.location_on,
                children: [
                  _buildInfoRow('Street', _getNestedValue(widget.driver, 'address.street')),
                  _buildInfoRow('City', _getNestedValue(widget.driver, 'address.city')),
                  _buildInfoRow('State', _getNestedValue(widget.driver, 'address.state')),
                  _buildInfoRow('Country', _getNestedValue(widget.driver, 'address.country')),
                  _buildInfoRow('Postal Code', _getNestedValue(widget.driver, 'address.postalCode')),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // DOCUMENTS CARD
  // ============================================================================
  
  Widget _buildDocumentsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header with Add Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1B7FA8).withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.folder, color: Color(0xFF1B7FA8), size: 24),
                    const SizedBox(width: 12),
                    Text(
                      'Documents (${_documents.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D3E50),
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _showAddDocumentDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Document'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B7FA8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          
          // Documents List
          Padding(
            padding: const EdgeInsets.all(16),
            child: _documents.isEmpty
                ? Center(
                    child: Column(
                      children: [
                        Icon(Icons.description, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text(
                          'No documents uploaded',
                          style: TextStyle(color: Colors.grey[600], fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Click "Add Document" to upload driver documents',
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: _documents.map((doc) => _buildDocumentTile(doc)).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentTile(dynamic doc) {
    final documentName = doc['documentName'] ?? 'Unnamed Document';
    final documentType = doc['documentType'] ?? 'Unknown';
    final fileName = doc['fileName'] ?? '';
    final expiryDate = doc['expiryDate'] != null 
        ? DateTime.tryParse(doc['expiryDate'].toString()) 
        : null;
    
    // Determine status
    final status = DriverService.getDocumentStatus(expiryDate);
    Color statusColor;
    String statusText;
    
    switch (status) {
      case DocumentStatus.expired:
        statusColor = Colors.red;
        statusText = 'EXPIRED';
        break;
      case DocumentStatus.expiring:
        statusColor = Colors.orange;
        statusText = 'Expiring Soon';
        break;
      case DocumentStatus.valid:
        statusColor = Colors.green;
        statusText = 'Valid';
        break;
      case DocumentStatus.noExpiry:
        statusColor = Colors.grey;
        statusText = 'No Expiry';
        break;
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Document Icon
          Icon(
            _getDocumentIcon(fileName),
            size: 32,
            color: const Color(0xFF1B7FA8),
          ),
          const SizedBox(width: 12),
          
          // Document Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  documentName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  documentType,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                if (expiryDate != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Action Buttons
          IconButton(
            icon: const Icon(Icons.download, color: Color(0xFF1B7FA8)),
            onPressed: () => _downloadDocument(doc),
            tooltip: 'Download',
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _confirmDeleteDocument(doc),
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }

  IconData _getDocumentIcon(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      case 'doc':
      case 'docx':
        return Icons.description;
      default:
        return Icons.attach_file;
    }
  }

  // ============================================================================
  // ADD DOCUMENT DIALOG
  // ============================================================================
  
  Future<void> _showAddDocumentDialog() async {
    final documentNameController = TextEditingController();
    DateTime? selectedExpiryDate;
    String? selectedDocumentType;
    dynamic selectedFile; // Changed from File? for web compatibility
    Uint8List? selectedFileBytes;
    String? selectedFileName;

    final documentTypes = [
      'License',
      'Medical Certificate',
      'Background Check',
      'Training Certificate',
      'ID Proof',
      'Other'
    ];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Driver Document'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Document Type Dropdown
                DropdownButtonFormField<String>(
                  value: selectedDocumentType,
                  decoration: InputDecoration(
                    labelText: 'Document Type *',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: documentTypes.map((type) {
                    return DropdownMenuItem(value: type, child: Text(type));
                  }).toList(),
                  onChanged: (value) {
                    setState(() => selectedDocumentType = value);
                  },
                ),
                const SizedBox(height: 16),
                
                // Document Name
                TextField(
                  controller: documentNameController,
                  decoration: InputDecoration(
                    labelText: 'Document Name *',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'e.g., DL-2024-12345',
                  ),
                ),
                const SizedBox(height: 16),
                
                // File Upload
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.upload_file, color: const Color(0xFF1B7FA8).withOpacity(0.8)),
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
                            backgroundColor: const Color(0xFF1B7FA8),
                            foregroundColor: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Expiry Date
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Expiry Date (Optional)'),
                  subtitle: Text(
                    selectedExpiryDate != null
                        ? DateFormat('dd/MM/yyyy').format(selectedExpiryDate!)
                        : 'No expiry date set',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today, color: Color(0xFF1B7FA8)),
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
                await _uploadDocument(
                  selectedDocumentType!,
                  documentNameController.text,
                  selectedExpiryDate,
                  selectedFile,
                  selectedFileBytes,
                  selectedFileName,
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B7FA8)),
              child: const Text('Add Document'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // DOCUMENT OPERATIONS
  // ============================================================================
  
  Future<void> _uploadDocument(
    String documentType,
    String documentName,
    DateTime? expiryDate,
    dynamic file, // Changed from File? for web compatibility
    Uint8List? fileBytes,
    String? fileName,
  ) async {
    try {
      setState(() => _isLoading = true);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF1B7FA8)),
        ),
      );

      final response = await _driverService.uploadDriverDocument(
        driverId: widget.driver['driverId'] ?? widget.driver['_id'],
        file: file,
        bytes: fileBytes,
        fileName: fileName ?? 'document.pdf',
        documentType: documentType,
        documentName: documentName,
        expiryDate: expiryDate,
      );

      Navigator.pop(context); // Close loading dialog

      if (response['success'] == true) {
        // Add new document to list
        setState(() {
          _documents.add(response['data']);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Document uploaded successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception(response['message'] ?? 'Failed to upload document');
      }
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadDocument(dynamic doc) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF1B7FA8)),
        ),
      );

      await _driverService.downloadDriverDocument(
        documentUrl: doc['documentUrl'] ?? '',
        fileName: doc['fileName'] ?? 'document.pdf',
      );

      Navigator.pop(context); // Close loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Document downloaded successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error downloading: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmDeleteDocument(dynamic doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document'),
        content: Text('Are you sure you want to delete "${doc['documentName']}"?'),
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
      await _deleteDocument(doc);
    }
  }

  Future<void> _deleteDocument(dynamic doc) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF1B7FA8)),
        ),
      );

      await _driverService.deleteDriverDocument(
        driverId: widget.driver['driverId'] ?? widget.driver['_id'],
        documentId: doc['id'],
      );

      Navigator.pop(context); // Close loading dialog

      // Remove document from list
      setState(() {
        _documents.removeWhere((d) => d['id'] == doc['id']);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Document deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error deleting: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================
  
  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1B7FA8).withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF1B7FA8), size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D3E50),
                  ),
                ),
              ],
            ),
          ),
          
          // Section Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isStatus = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: isStatus
                ? _buildStatusBadge(value)
                : Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF2D3E50),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    String displayText;

    switch (status.toLowerCase()) {
      case 'active':
        bgColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
        displayText = 'Active';
        break;
      case 'on_leave':
        bgColor = Colors.orange.shade50;
        textColor = Colors.orange.shade700;
        displayText = 'On Leave';
        break;
      case 'inactive':
        bgColor = Colors.red.shade50;
        textColor = Colors.red.shade700;
        displayText = 'Inactive';
        break;
      default:
        bgColor = Colors.grey.shade50;
        textColor = Colors.grey.shade700;
        displayText = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        displayText,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  String _getNestedValue(Map<String, dynamic> map, String path, [String defaultValue = 'N/A']) {
    final keys = path.split('.');
    dynamic value = map;
    
    for (final key in keys) {
      if (value is Map && value.containsKey(key)) {
        value = value[key];
      } else {
        return defaultValue;
      }
    }
    
    return value?.toString() ?? defaultValue;
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

  String _getFeedbackCount(Map<String, dynamic> driver) {
    final stats = driver['feedbackStats'];
    if (stats is Map) {
      final count = stats['totalFeedback'] ?? stats['count'];
      if (count != null) return count.toString();
    }
    return '0';
  }

  // ✏️ SHOW EDIT DRIVER DIALOG
  Future<void> _showEditDriverDialog() async {
    const primaryColor = Color(0xFF1B7FA8);
    const textPrimaryColor = Color(0xFF2C3E50);
    const textSecondaryColor = Color(0xFF7F8C8D);
    const borderColor = Color(0xFFE0E0E0);

    final nameController = TextEditingController(
      text: widget.driver['name'] ?? _getNestedValue(widget.driver, 'personalInfo.name', '')
    );
    final emailController = TextEditingController(
      text: widget.driver['email'] ?? _getNestedValue(widget.driver, 'personalInfo.email', '')
    );
    final phoneController = TextEditingController(
      text: widget.driver['phone'] ?? _getNestedValue(widget.driver, 'personalInfo.phone', '')
    );
    
    final validStatuses = ['active', 'on_leave', 'inactive'];
    String driverStatus = widget.driver['status']?.toString().toLowerCase() ?? 'active';
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
                      'Driver ID: ${widget.driver['driverId'] ?? 'N/A'}',
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

  // 🔄 UPDATE DRIVER
  Future<void> _updateDriver(Map<String, dynamic> updates) async {
    setState(() => _isLoading = true);

    try {
      final driverId = widget.driver['driverId'] ?? widget.driver['_id']?.toString();
      if (driverId == null) {
        throw Exception('Driver ID not found');
      }

      await _driverService.updateDriver(driverId, updates);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Driver updated successfully'),
            backgroundColor: Colors.green,
          ),
        );

        // Update local driver data
        setState(() {
          widget.driver['name'] = updates['name'];
          widget.driver['email'] = updates['email'];
          widget.driver['phone'] = updates['phone'];
          widget.driver['status'] = updates['status'];
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error updating driver: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

