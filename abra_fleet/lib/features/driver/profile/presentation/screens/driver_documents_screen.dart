// lib/features/driver/profile/presentation/screens/driver_documents_screen.dart
// Complete Driver Documents Management Screen

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../../../app/config/api_config.dart';

class DriverDocumentsScreen extends StatefulWidget {
  final String driverId;
  final String driverName;

  const DriverDocumentsScreen({
    Key? key,
    required this.driverId,
    required this.driverName,
  }) : super(key: key);

  @override
  State<DriverDocumentsScreen> createState() => _DriverDocumentsScreenState();
}

class _DriverDocumentsScreenState extends State<DriverDocumentsScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _documentStatus = {};
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadDocumentStatus();
  }

  Future<void> _loadDocumentStatus() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      
      debugPrint('🔍 Loading document status for driver: ${widget.driverId}');
      debugPrint('   Token: ${token?.substring(0, 20)}...');
      
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/driver-documents/status/${widget.driverId}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('📄 Response status: ${response.statusCode}');
      debugPrint('📄 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('✅ Document status loaded: ${data['data']}');
        setState(() {
          _documentStatus = data['data'] ?? {};
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load document status: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error loading document status: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading documents: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _uploadDailyPhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );

      if (image == null) return;

      await _uploadDocument(
        image,
        'upload-daily-photo',
        'Daily Verification Photo',
      );
    } catch (e) {
      debugPrint('Error picking daily photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _uploadProfilePhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (image == null) return;

      await _uploadDocument(
        image,
        'upload-profile-photo',
        'Profile Photo',
      );
    } catch (e) {
      debugPrint('Error picking profile photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _uploadLicense() async {
    try {
      // Show dialog to get license details
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => _LicenseDetailsDialog(),
      );

      if (result == null) return;

      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (image == null) return;

      await _uploadDocument(
        image,
        'upload-license',
        'License',
        additionalData: result,
      );
    } catch (e) {
      debugPrint('Error uploading license: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _uploadMedicalCertificate() async {
    try {
      // Show dialog to get certificate details
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => _MedicalCertificateDialog(),
      );

      if (result == null) return;

      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (image == null) return;

      await _uploadDocument(
        image,
        'upload-medical-certificate',
        'Medical Certificate',
        additionalData: result,
      );
    } catch (e) {
      debugPrint('Error uploading medical certificate: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _uploadDocument(
    XFile image,
    String endpoint,
    String documentName, {
    Map<String, String>? additionalData,
  }) async {
    try {
      debugPrint('📤 Starting upload: $documentName');
      debugPrint('   Endpoint: $endpoint');
      debugPrint('   Driver ID: ${widget.driverId}');
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      debugPrint('   Token: ${token?.substring(0, 20)}...');

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/api/driver-documents/$endpoint/${widget.driverId}'),
      );

      request.headers['Authorization'] = 'Bearer $token';

      // Add the image file
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          endpoint.contains('daily') ? 'photo' : 
          endpoint.contains('profile') ? 'photo' :
          endpoint.contains('license') ? 'license' : 'certificate',
          bytes,
          filename: image.name,
        ));
      } else {
        request.files.add(await http.MultipartFile.fromPath(
          endpoint.contains('daily') ? 'photo' : 
          endpoint.contains('profile') ? 'photo' :
          endpoint.contains('license') ? 'license' : 'certificate',
          image.path,
          filename: image.name,
        ));
      }

      // Add additional data if provided
      if (additionalData != null) {
        additionalData.forEach((key, value) {
          request.fields[key] = value;
        });
        debugPrint('   Additional data: $additionalData');
      }

      debugPrint('   Sending request...');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      debugPrint('   Response status: ${response.statusCode}');
      debugPrint('   Response body: $responseBody');

      Navigator.pop(context); // Close loading dialog

      if (response.statusCode == 200) {
        debugPrint('✅ Upload successful!');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$documentName uploaded successfully!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        
        // Wait a moment for backend to process
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Refresh status
        debugPrint('🔄 Refreshing document status...');
        await _loadDocumentStatus();
        debugPrint('✅ Status refreshed!');
      } else {
        throw Exception('Upload failed: $responseBody');
      }
    } catch (e) {
      debugPrint('❌ Upload error: $e');
      Navigator.pop(context); // Close loading dialog
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload $documentName: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Documents'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDocumentStatus,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDocumentStatus,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Text(
                      'Document Verification',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Upload and manage your verification documents',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                    const SizedBox(height: 24),

                    // Daily Verification Photo
                    _buildDocumentCard(
                      title: 'Daily Verification Photo',
                      subtitle: 'Required daily for trip verification',
                      icon: Icons.camera_alt,
                      iconColor: Colors.blue,
                      status: _documentStatus['dailyVerificationPhoto'],
                      onUpload: _uploadDailyPhoto,
                      showExpiry: true,
                    ),

                    const SizedBox(height: 16),

                    // Profile Photo
                    _buildDocumentCard(
                      title: 'Profile Photo',
                      subtitle: 'Your permanent profile picture',
                      icon: Icons.account_circle,
                      iconColor: Colors.green,
                      status: _documentStatus['dailyVerificationPhoto'],
                      onUpload: _uploadProfilePhoto,
                      showExpiry: false,
                    ),

                    const SizedBox(height: 16),

                    // License
                    _buildDocumentCard(
                      title: 'Driving License',
                      subtitle: 'Upload your valid driving license',
                      icon: Icons.credit_card,
                      iconColor: Colors.orange,
                      status: _documentStatus['license'],
                      onUpload: _uploadLicense,
                      showExpiry: true,
                    ),

                    const SizedBox(height: 16),

                    // Medical Certificate
                    _buildDocumentCard(
                      title: 'Medical Certificate',
                      subtitle: 'Upload your medical fitness certificate',
                      icon: Icons.medical_services,
                      iconColor: Colors.red,
                      status: _documentStatus['medicalCertificate'],
                      onUpload: _uploadMedicalCertificate,
                      showExpiry: true,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildDocumentCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Map<String, dynamic>? status,
    required VoidCallback onUpload,
    required bool showExpiry,
  }) {
    debugPrint('🎨 Building card for: $title');
    debugPrint('   Status data: $status');
    
    final bool isUploaded = status?['uploaded'] == true;
    final bool isVerified = status?['verified'] == true;
    final String? expiryDate = status?['expiryDate'];
    final String? dailyPhotoUrl = status?['dailyPhotoUrl'];
    
    debugPrint('   isUploaded: $isUploaded');
    debugPrint('   isVerified: $isVerified');
    debugPrint('   expiryDate: $expiryDate');
    debugPrint('   dailyPhotoUrl: ${dailyPhotoUrl != null ? "Available" : "null"}');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // Status Icon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isUploaded ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isUploaded ? Icons.check_circle : Icons.cancel,
                    color: isUploaded ? Colors.green : Colors.red,
                    size: 24,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Status Row
            Row(
              children: [
                _buildStatusChip(
                  isUploaded ? 'Uploaded' : 'Not Uploaded',
                  isUploaded ? Colors.green : Colors.red,
                ),
                if (isUploaded && isVerified) ...[
                  const SizedBox(width: 8),
                  _buildStatusChip('Verified', Colors.blue),
                ],
              ],
            ),

            // Expiry Date
            if (showExpiry && expiryDate != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Expires: ${_formatDate(expiryDate)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ],

            // Show daily photo preview if available
            if (dailyPhotoUrl != null && dailyPhotoUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Current Photo:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  base64Decode(dailyPhotoUrl.split(',')[1]),
                  height: 100,
                  width: 100,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint('❌ Error loading image: $error');
                    return Container(
                      height: 100,
                      width: 100,
                      color: Colors.grey[300],
                      child: const Icon(Icons.error),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Upload Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onUpload,
                icon: Icon(isUploaded ? Icons.refresh : Icons.upload),
                label: Text(isUploaded ? 'Update' : 'Upload'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: iconColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }
}

// License Details Dialog
class _LicenseDetailsDialog extends StatefulWidget {
  @override
  State<_LicenseDetailsDialog> createState() => _LicenseDetailsDialogState();
}

class _LicenseDetailsDialogState extends State<_LicenseDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _licenseNumberController = TextEditingController();
  DateTime? _expiryDate;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('License Details'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _licenseNumberController,
              decoration: const InputDecoration(
                labelText: 'License Number',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter license number';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              title: Text(_expiryDate == null
                  ? 'Select Expiry Date'
                  : 'Expiry: ${DateFormat('MMM dd, yyyy').format(_expiryDate!)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 365)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (date != null) {
                  setState(() => _expiryDate = date);
                }
              },
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
          onPressed: () {
            if (_formKey.currentState!.validate() && _expiryDate != null) {
              Navigator.pop(context, {
                'licenseNumber': _licenseNumberController.text,
                'expiryDate': _expiryDate!.toIso8601String(),
              });
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please fill all fields')),
              );
            }
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

// Medical Certificate Dialog
class _MedicalCertificateDialog extends StatefulWidget {
  @override
  State<_MedicalCertificateDialog> createState() => _MedicalCertificateDialogState();
}

class _MedicalCertificateDialogState extends State<_MedicalCertificateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _certificateNumberController = TextEditingController();
  DateTime? _expiryDate;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Medical Certificate Details'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _certificateNumberController,
              decoration: const InputDecoration(
                labelText: 'Certificate Number (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: Text(_expiryDate == null
                  ? 'Select Expiry Date'
                  : 'Expiry: ${DateFormat('MMM dd, yyyy').format(_expiryDate!)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 365)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (date != null) {
                  setState(() => _expiryDate = date);
                }
              },
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
          onPressed: () {
            if (_expiryDate != null) {
              Navigator.pop(context, {
                'certificateNumber': _certificateNumberController.text,
                'expiryDate': _expiryDate!.toIso8601String(),
              });
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please select expiry date')),
              );
            }
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
