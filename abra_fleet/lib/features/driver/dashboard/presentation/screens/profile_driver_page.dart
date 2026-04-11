// lib/features/driver/dashboard/presentation/screens/profile_driver_page.dart
// JWT + MongoDB VERSION (NO FIREBASE)
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/auth/presentation/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:http_parser/http_parser.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:abra_fleet/features/admin/hrm/hrm_feedback.dart';

// UI Constants
const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kWarningColor = Color(0xFFF59E0B);
const Color kDangerColor = Color(0xFFDC2626);
const Color kSuccessColor = Color(0xFF16A34A);
const Color kScaffoldBackgroundColor = Color(0xFFF1F5F9);
const Color kCardBackgroundColor = Colors.white;
const Color kPrimaryTextColor = Color(0xFF1E293B);
const Color kSecondaryTextColor = Color(0xFF64748B);
const Color kSecondaryButtonColor = Color(0xFF4B5563);

enum DocumentType { profilePhoto, dailyVerificationPhoto, license, medicalCertificate }

class DocumentStatus {
  final bool uploaded;
  final bool isRequired;
  final bool verified;
  final DateTime? lastUpload;
  final DateTime? expiryDate;
  final String? dailyPhotoUrl;

  DocumentStatus({
    this.uploaded = false,
    this.isRequired = false,
    this.verified = false,
    this.lastUpload,
    this.expiryDate,
    this.dailyPhotoUrl,
  });

  factory DocumentStatus.fromJson(Map<String, dynamic> json) {
    return DocumentStatus(
      uploaded: json['uploaded'] ?? false,
      isRequired: json['isRequired'] ?? false,
      verified: json['verified'] ?? false,
      lastUpload: json['lastUpload'] != null ? DateTime.parse(json['lastUpload']) : null,
      expiryDate: json['expiryDate'] != null ? DateTime.parse(json['expiryDate']) : null,
      dailyPhotoUrl: json['dailyPhotoUrl'],
    );
  }
}

class ProfileDriverPage extends StatefulWidget {
  const ProfileDriverPage({Key? key}) : super(key: key);

  @override
  State<ProfileDriverPage> createState() => _ProfileDriverPageState();
}

class _ProfileDriverPageState extends State<ProfileDriverPage> {
  Future<Map<String, dynamic>>? _driverProfileFuture; // Changed from late to nullable
  Future<Map<String, DocumentStatus>>? _documentStatusFuture;

  bool _isUploading = false;
  String _uploadingMessage = '';
  final ImagePicker _imagePicker = ImagePicker();
  final DocumentService _documentService = DocumentService();

  // Controllers and state for editing driver info
  final _infoFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isEditingInfo = false;

  // Auth data
  SharedPreferences? _prefs;
  String? _token;

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    _prefs = await SharedPreferences.getInstance();
    _token = _prefs?.getString('jwt_token');
    _loadInitialData();
  }

  void _loadInitialData() {
    setState(() {
      _driverProfileFuture = _fetchDriverProfile();
    });
    _driverProfileFuture?.then((driverData) {
      if (driverData.isNotEmpty) {
        setState(() {
          final driverId = driverData['_id'] ?? driverData['id'];
          _documentStatusFuture = _documentService.getDocumentStatus(driverId);
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _fetchDriverProfile() async {
    if (_token == null || _token!.isEmpty) {
      throw Exception('No authenticated user found.');
    }

    final userDataString = _prefs?.getString('user_data');
    if (userDataString == null) throw Exception('User data not found');
    
    final userData = jsonDecode(userDataString);
    final userId = userData['id'];

    try {
      // Use backend API to get driver profile
      final apiService = ApiService();
      final response = await apiService.get('/api/drivers/profile');
      
      if (response['success'] == true && response['data'] != null) {
        final driverData = response['data'] as Map<String, dynamic>;
        return driverData;
      }

      throw Exception('Driver profile not found. Please contact admin.');
    } catch (e) {
      debugPrint('Error fetching driver profile: $e');
      rethrow;
    }
  }

  Future<void> _refreshProfile() async {
    setState(() {
      _driverProfileFuture = _fetchDriverProfile();
    });
    if (_driverProfileFuture != null) {
      await _driverProfileFuture;
    }
  }

  Future<void> _initiateDocumentUpload(DocumentType type, String driverId) async {
    if (type == DocumentType.dailyVerificationPhoto) {
      await _showImageSourceDialog(type, driverId);
    } else if (type == DocumentType.profilePhoto) {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (image == null) return;
      await _performUpload(driverId, type, image, {});
    } else {
      await _showDocumentDetailsDialog(type, driverId);
    }
  }

  Future<void> _showImageSourceDialog(DocumentType type, String driverId) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Upload Daily Verification Photo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Please select a source for your selfie.'),
              if (kIsWeb)
                const Padding(
                  padding: EdgeInsets.only(top: 16.0),
                  child: Text(
                    '⚠️ Note: On the web, choosing "Camera" will open a file picker.',
                    style: TextStyle(fontSize: 12, color: kWarningColor),
                  ),
                ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Camera'),
              onPressed: () {
                Navigator.of(context).pop();
                _pickAndUploadImage(type, driverId, ImageSource.camera);
              },
            ),
            TextButton(
              child: const Text('Gallery'),
              onPressed: () {
                Navigator.of(context).pop();
                _pickAndUploadImage(type, driverId, ImageSource.gallery);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickAndUploadImage(
      DocumentType type, String driverId, ImageSource source) async {
    try {
      ImageSource selectedSource = source;

      if (kIsWeb && source == ImageSource.camera) {
        debugPrint('Web platform detected - using gallery instead of camera');
        selectedSource = ImageSource.gallery;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('On the web, the file picker will be used to select an image.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }

      final XFile? image = await _imagePicker.pickImage(
        source: selectedSource,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (image == null) return;
      await _performUpload(driverId, type, image, {});
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image selection error: ${e.toString()}'),
            backgroundColor: kDangerColor,
          ),
        );
      }
    }
  }

  Future<void> _showDocumentDetailsDialog(DocumentType type, String driverId) async {
    final formKey = GlobalKey<FormState>();
    final numberController = TextEditingController();
    final expiryController = TextEditingController();
    DateTime? selectedDate;
    XFile? selectedFile;
    bool isDialogUploading = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isDialogUploading,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                'Upload ${type == DocumentType.license ? "License" : "Certificate"}',
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: numberController,
                        decoration: InputDecoration(
                          labelText: type == DocumentType.license
                              ? 'License Number'
                              : 'Certificate Number',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'This field is required';
                          }
                          if (type == DocumentType.license) {
                            final RegExp licenseRegex = RegExp(r'^[A-Z0-9-]{5,}$');
                            if (!licenseRegex.hasMatch(value)) {
                              return 'Please enter a valid license number format.';
                            }
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: expiryController,
                        decoration: const InputDecoration(
                          labelText: 'Expiry Date',
                          hintText: 'Select Date',
                        ),
                        readOnly: true,
                        onTap: () async {
                          final now = DateTime.now();
                          selectedDate = await showDatePicker(
                            context: context,
                            initialDate: now,
                            firstDate: now,
                            lastDate: now.add(const Duration(days: 365 * 20)),
                          );
                          if (selectedDate != null) {
                            expiryController.text =
                                DateFormat('yyyy-MM-dd').format(selectedDate!);
                          }
                        },
                        validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.attach_file),
                        label: Text(selectedFile == null ? 'Select File' : 'Change File'),
                        onPressed: () async {
                          final file =
                              await _imagePicker.pickImage(source: ImageSource.gallery);
                          if (file != null) {
                            setDialogState(() => selectedFile = file);
                          }
                        },
                      ),
                      if (selectedFile != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'File: ${selectedFile!.name}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: kSecondaryTextColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (isDialogUploading) ...[
                        const SizedBox(height: 16),
                        const CircularProgressIndicator(),
                        const SizedBox(height: 8),
                        const Text('Uploading...'),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isDialogUploading ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: (formKey.currentState?.validate() ?? false) &&
                          selectedFile != null &&
                          !isDialogUploading
                      ? () async {
                          setDialogState(() => isDialogUploading = true);
                          final fields = {
                            if (type == DocumentType.license)
                              'licenseNumber': numberController.text,
                            if (type == DocumentType.medicalCertificate)
                              'certificateNumber': numberController.text,
                            'expiryDate': selectedDate!.toIso8601String(),
                          };
                          final success = await _performUpload(
                            driverId,
                            type,
                            selectedFile!,
                            fields,
                          );

                          if(success && mounted) {
                             Navigator.of(context).pop();
                          } else {
                             setDialogState(() => isDialogUploading = false);
                          }
                        }
                      : null,
                  child: const Text('Upload'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _performUpload(String driverId, DocumentType type, XFile file,
      Map<String, String> fields) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    setState(() {
      _isUploading = true;
      _uploadingMessage = 'Uploading ${type.name}...';
    });
    try {
      final successMessage =
          await _documentService.uploadDocument(driverId, type, file, fields);

      if (type == DocumentType.dailyVerificationPhoto) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Greeting! Your verification photo is uploaded. You can upload another one tomorrow.',
            ),
            backgroundColor: kSuccessColor,
            duration: Duration(seconds: 4),
          ),
        );
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: kSuccessColor,
          ),
        );
      }

      await _refreshProfile();
      return true;
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Upload failed: ${e.toString()}'),
          backgroundColor: kDangerColor,
        ),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadingMessage = '';
        });
      }
    }
  }

  Future<void> _updateDriverInfo(String driverDocId) async {
    if (!(_infoFormKey.currentState?.validate() ?? false)) {
      return;
    }

    try {
      final apiService = ApiService();
      final response = await apiService.put('/api/drivers/profile/$driverDocId', body: {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
      });

      if (response['success'] == true) {
        await _refreshProfile();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile information updated!'),
              backgroundColor: kSuccessColor,
            ),
          );
          setState(() => _isEditingInfo = false);
        }
      } else {
        throw Exception(response['message'] ?? 'Update failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: $e'),
            backgroundColor: kDangerColor,
          ),
        );
      }
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to permanently delete your account?\n\n'
          'This action cannot be undone. You will not be able to log in with this email again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kDangerColor),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (_token == null || _token!.isEmpty) throw Exception('Not authenticated');

      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/delete-account'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        await _prefs?.clear();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      } else {
        throw Exception(responseData['message'] ?? 'Failed to delete account');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to delete account: $e'),
          backgroundColor: kDangerColor,
        ));
      }
    }
  }

  Future<void> _handleLogout(BuildContext context) async {    final authRepository = Provider.of<AuthRepository>(context, listen: false);

    final confirmLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmLogout == true && context.mounted) {
      await authRepository.signOut();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kScaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: kPrimaryColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refreshProfile,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => _handleLogout(context),
          ),
        ],
      ),
      body: _driverProfileFuture == null
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<Map<String, dynamic>>(
              future: _driverProfileFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final driverData = snapshot.data!;
                final driverDocId = driverData['_id'] ?? driverData['id'];

                return RefreshIndicator(
                  onRefresh: _refreshProfile,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildProfileHeader(driverData, driverDocId),
                        const SizedBox(height: 16),
                        if (_isUploading) ...[
                          Center(
                            child: Text(
                              _uploadingMessage,
                              style: const TextStyle(
                                color: kPrimaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(),
                          const SizedBox(height: 16),
                        ],
                        _buildDriverInfoCard(driverData, driverDocId),
                        const SizedBox(height: 16),
                        // COMMENTED OUT - Document Verification Section
                        // _buildDocumentVerificationCard(driverDocId),
                        // const SizedBox(height: 16),
                        _buildAccountSettingsCard(),
                        const SizedBox(height: 16),
                        // _buildFeedbackCard(), // Commented out - Feedback moved to HRM section
                        // const SizedBox(height: 16),
                        _buildSessionControlCard(context),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildProfileHeader(Map<String, dynamic> data, String driverId) {
    final name = data['name'] ?? 'Driver';
    final profileImageUrl = data['profileImageUrl'] as String?;
    final status = data['status'] ?? 'Active';

    ImageProvider? backgroundImage;
    if (profileImageUrl != null) {
      if (profileImageUrl.startsWith('data:image')) {
        final uriData = Uri.parse(profileImageUrl);
        backgroundImage = MemoryImage(uriData.data!.contentAsBytes());
      } else {
        backgroundImage = NetworkImage(profileImageUrl);
      }
    }

    return Card(
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: kPrimaryColor.withOpacity(0.1),
                  backgroundImage: backgroundImage,
                  child: backgroundImage == null
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'D',
                          style: const TextStyle(fontSize: 36, color: kPrimaryColor),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _isUploading
                        ? null
                        : () =>
                            _initiateDocumentUpload(DocumentType.profilePhoto, driverId),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: kPrimaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              name,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: kPrimaryTextColor,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: kPrimaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                status,
                style: const TextStyle(
                  color: kPrimaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // COMMENTED OUT - Document Verification Card Method
  // Widget _buildDocumentVerificationCard(String driverId) {
  //   return _buildCard(
  //     title: 'Document Verification',
  //     icon: Icons.document_scanner,
  //     child: FutureBuilder<Map<String, DocumentStatus>>(
  //       future: _documentStatusFuture,
  //       builder: (context, snapshot) {
  //         if (snapshot.connectionState == ConnectionState.waiting) {
  //           return const Center(child: CircularProgressIndicator());
  //         }
  //         if (snapshot.hasError || !snapshot.hasData) {
  //           return const Center(child: Text('Could not load document status.'));
  //         }

  //         final statuses = snapshot.data!;
  //         final dailyPhotoStatus =
  //             statuses['dailyVerificationPhoto'] ?? DocumentStatus(isRequired: true);
  //         final licenseStatus = statuses['license'] ?? DocumentStatus(isRequired: true);
  //         final medicalStatus =
  //             statuses['medicalCertificate'] ?? DocumentStatus(isRequired: true);

  //         return Column(
  //           children: [
  //             if (dailyPhotoStatus.isRequired)
  //               _DocumentStatusTile(
  //                 title: 'Daily Verification Photo',
  //                 status: dailyPhotoStatus,
  //                 onUpload: () => _initiateDocumentUpload(
  //                   DocumentType.dailyVerificationPhoto,
  //                   driverId,
  //                 ),
  //               ),
  //             _DocumentStatusTile(
  //               title: 'License',
  //               status: licenseStatus,
  //               onUpload: () =>
  //                   _initiateDocumentUpload(DocumentType.license, driverId),
  //             ),
  //             _DocumentStatusTile(
  //               title: 'Medical Certificate',
  //               status: medicalStatus,
  //               onUpload: () => _initiateDocumentUpload(
  //                 DocumentType.medicalCertificate,
  //                 driverId,
  //               ),
  //             ),
  //           ],
  //         );
  //       },
  //     ),
  //   );
  // }

  Widget _buildCard({
    required String title,
    required Widget child,
    IconData? icon,
    Widget? trailing,
  }) {
    return Card(
      elevation: 2.0,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      color: kCardBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (icon != null)
                      Icon(icon, color: kPrimaryTextColor, size: 22),
                    if (icon != null) const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18.0,
                        fontWeight: FontWeight.bold,
                        color: kPrimaryTextColor,
                      ),
                    ),
                  ],
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 15.0),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildDriverInfoCard(Map<String, dynamic> data, String driverDocId) {
    final name = data['name'] ?? 'N/A';
    final email = data['email'] ?? 'N/A';
    final phone = data['phoneNumber'] ?? 'N/A';
    final licenseNumber = data['licenseNumber'] ?? 'N/A';
    final status = data['status'] ?? 'Active';

    return _buildCard(
      title: 'Driver Information',
      icon: Icons.person,
      trailing: _isEditingInfo
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: kSuccessColor),
                  onPressed: () => _updateDriverInfo(driverDocId),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: kDangerColor),
                  onPressed: () => setState(() => _isEditingInfo = false),
                ),
              ],
            )
          : IconButton(
              icon: const Icon(Icons.edit, color: kPrimaryColor, size: 20),
              onPressed: () {
                setState(() {
                  _isEditingInfo = true;
                  _nameController.text = name;
                  _emailController.text = email;
                  _phoneController.text = phone;
                });
              },
            ),
      child: Form(
        key: _infoFormKey,
        child: Column(
          children: [
            _buildEditableInfoItem(
              label: 'Name',
              value: name,
              controller: _nameController,
              validator: (value) =>
                  (value?.isEmpty ?? true) ? 'Name is required' : null,
            ),
            _buildEditableInfoItem(
              label: 'Email',
              value: email,
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.isEmpty) return 'Email is required';
                if (!RegExp(r'\S+@\S+\.\S+').hasMatch(value)) {
                  return 'Please enter a valid email';
                }
                return null;
              },
            ),
            _buildEditableInfoItem(
              label: 'Phone',
              value: phone,
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                if (value == null || value.isEmpty) return 'Phone is required';
                if (value.length != 10) return 'Must be 10 digits';
                return null;
              },
            ),
            _buildProfileItem(label: 'License Number', value: licenseNumber),
            _buildProfileItem(label: 'Status', value: status, hasDivider: false),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableInfoItem({
    required String label,
    required String value,
    required TextEditingController controller,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: kPrimaryTextColor,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _isEditingInfo
                ? TextFormField(
                    controller: controller,
                    validator: validator,
                    keyboardType: keyboardType,
                    inputFormatters: inputFormatters,
                    textAlign: TextAlign.end,
                    style: const TextStyle(color: kPrimaryTextColor, fontSize: 15),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      errorStyle: TextStyle(fontSize: 10),
                    ),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  )
                : Text(
                    value,
                    textAlign: TextAlign.end,
                    style: const TextStyle(color: kSecondaryTextColor, fontSize: 15),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSettingsCard() {
    return _buildCard(
      title: 'Account Settings',
      icon: Icons.settings,
      child: Column(
        children: [
          _buildSettingsItem(
            icon: Icons.lock,
            label: 'Change Password',
            onTap: () => _showChangePasswordDialog(),
          ),
          // _buildSettingsItem(
          //   icon: Icons.notifications,
          //   label: 'Notifications',
          //   onTap: () => _showNotificationsSettings(),
          // ),
          // _buildSettingsItem(
          //   icon: Icons.privacy_tip,
          //   label: 'Privacy',
          //   onTap: () => _showPrivacySettings(),
          // ),
          // _buildSettingsItem(
          //   icon: Icons.help_outline,
          //   label: 'Help & Support',
          //   onTap: () => _showHelpSupport(),
          // ),
        ],
      ),
    );
  }

  // COMMENTED OUT - Feedback moved to HRM section in hrm_driver_management.dart
  // Widget _buildFeedbackCard() {
  //   return _buildCard(
  //     title: 'Feedback & Support',
  //     icon: Icons.feedback,
  //     child: Column(
  //       children: [
  //         const Text(
  //           'Share your thoughts and help us improve our services',
  //           style: TextStyle(
  //             color: Color(0xFF64748b),
  //             fontSize: 14,
  //             height: 1.5,
  //           ),
  //           textAlign: TextAlign.center,
  //         ),
  //         const SizedBox(height: 16),
  //         SizedBox(
  //           width: double.infinity,
  //           child: ElevatedButton.icon(
  //             icon: const Icon(Icons.message),
  //             onPressed: () {
  //               Navigator.push(
  //                 context,
  //                 MaterialPageRoute(
  //                   builder: (_) => Scaffold(
  //                     appBar: AppBar(
  //                       title: const Text('Feedback & Support'),
  //                       backgroundColor: const Color(0xFF0D47A1),
  //                       foregroundColor: Colors.white,
  //                       elevation: 0,
  //                     ),
  //                     body: HRMFeedbackScreen(),
  //                   ),
  //                 ),
  //               );
  //             },
  //             label: const Text('Submit Feedback'),
  //             style: ElevatedButton.styleFrom(
  //               backgroundColor: const Color(0xFF0D47A1),
  //               foregroundColor: Colors.white,
  //               padding: const EdgeInsets.symmetric(vertical: 14),
  //               shape: RoundedRectangleBorder(
  //                 borderRadius: BorderRadius.circular(10),
  //               ),
  //             ),
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Widget _buildSessionControlCard(BuildContext context) {
    return _buildCard(
      title: 'Session Control',
      icon: Icons.power_settings_new,
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.logout),
              onPressed: () => _handleLogout(context),
              label: const Text('Logout'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kDangerColor,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.delete_forever),
              onPressed: _deleteAccount,
              label: const Text('Delete Account'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[900],
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileItem({
    required String label,
    required String value,
    bool hasDivider = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15.0),
      decoration: BoxDecoration(
        border: Border(
          bottom: hasDivider
              ? BorderSide(color: Colors.grey.shade200)
              : BorderSide.none,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: kPrimaryTextColor,
              fontSize: 15,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: kSecondaryTextColor,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsItem({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10.0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
        child: Row(
          children: [
            Icon(icon, color: kSecondaryTextColor),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: kPrimaryTextColor,
                  fontSize: 15,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showChangePasswordDialog() async {
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool isLoading = false;
  bool showCurrentPassword = false;
  bool showNewPassword = false;
  bool showConfirmPassword = false;

  await showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Change Password'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: currentPasswordController,
                      obscureText: !showCurrentPassword,
                      decoration: InputDecoration(
                        labelText: 'Current Password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            showCurrentPassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setDialogState(
                              () => showCurrentPassword = !showCurrentPassword,
                            );
                          },
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Current password is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: newPasswordController,
                      obscureText: !showNewPassword,
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            showNewPassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setDialogState(
                              () => showNewPassword = !showNewPassword,
                            );
                          },
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'New password is required';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        if (value == currentPasswordController.text) {
                          return 'New password must be different';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmPasswordController,
                      obscureText: !showConfirmPassword,
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            showConfirmPassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setDialogState(
                              () => showConfirmPassword = !showConfirmPassword,
                            );
                          },
                        ),
                      ),
                      validator: (value) {
                        if (value != newPasswordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                    if (isLoading) ...[
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (formKey.currentState!.validate()) {
                          setDialogState(() => isLoading = true);
                          bool success = await _handlePasswordChange(
                            currentPasswordController.text,
                            newPasswordController.text,
                          );
                          if (success && mounted) {
                            Navigator.pop(context);
                          } else {
                            setDialogState(() => isLoading = false);
                          }
                        }
                      },
                child: const Text('Update Password'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<bool> _handlePasswordChange(
    String currentPassword, String newPassword) async {
  try {
    if (_token == null || _token!.isEmpty) {
      throw Exception('User not authenticated');
    }

    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/change-password'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update password');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated successfully!'),
          backgroundColor: kSuccessColor,
        ),
      );
    }
    return true;
  } catch (e) {
    if (mounted) {
      String errorMessage = 'Failed to update password';
      if (e.toString().contains('wrong-password')) {
        errorMessage = 'Current password is incorrect';
      } else if (e.toString().contains('weak-password')) {
        errorMessage = 'New password is too weak';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: kDangerColor,
        ),
      );
    }
    return false;
  }
}

Future<void> _showNotificationsSettings() async {
  bool pushNotifications = true;
  bool emailNotifications = true;
  bool tripAlerts = true;
  bool documentAlerts = true;

  await showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Notification Preferences'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Push Notifications'),
                    subtitle: const Text('Receive app notifications'),
                    value: pushNotifications,
                    onChanged: (value) {
                      setDialogState(() => pushNotifications = value);
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Email Notifications'),
                    subtitle: const Text('Receive email alerts'),
                    value: emailNotifications,
                    onChanged: (value) {
                      setDialogState(() => emailNotifications = value);
                    },
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Trip Alerts'),
                    subtitle: const Text('Notifications about trips'),
                    value: tripAlerts,
                    onChanged: (value) {
                      setDialogState(() => tripAlerts = value);
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Document Alerts'),
                    subtitle: const Text('Expiry and verification updates'),
                    value: documentAlerts,
                    onChanged: (value) {
                      setDialogState(() => documentAlerts = value);
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
                onPressed: () async {
                  await _saveNotificationPreferences(
                    pushNotifications,
                    emailNotifications,
                    tripAlerts,
                    documentAlerts,
                  );
                  if (mounted) Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _saveNotificationPreferences(
  bool push,
  bool email,
  bool trips,
  bool documents,
) async {
  try {
    final userDataString = _prefs?.getString('user_data');
    final userData = userDataString != null ? jsonDecode(userDataString) : null;
    final userId = userData?['id'];
    
    if (_token == null || _token!.isEmpty) return;

    final apiService = ApiService();
    await apiService.put('/api/drivers/notifications/$userId', body: {
      'notificationPreferences': {
        'pushNotifications': push,
        'emailNotifications': email,
        'tripAlerts': trips,
        'documentAlerts': documents,
      },
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification preferences saved!'),
          backgroundColor: kSuccessColor,
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save preferences: $e'),
          backgroundColor: kDangerColor,
        ),
      );
    }
  }
}

Future<void> _showPrivacySettings() async {
  bool dataSharing = false;
  bool locationTracking = true;

  await showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Privacy Settings'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Location Tracking'),
                    subtitle: const Text('Allow app to track your location for trips'),
                    value: locationTracking,
                    onChanged: (value) {
                      setDialogState(() => locationTracking = value);
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Data Sharing'),
                    subtitle: const Text('Allow sharing anonymized data with partners'),
                    value: dataSharing,
                    onChanged: (value) {
                      setDialogState(() => dataSharing = value);
                    },
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Privacy Policy'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                   _showPrivacyPolicyDialog();
                },
                  ),
                  ListTile(
                    title: const Text('Terms of Service'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                  _showTermsOfServiceDialog();
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
                onPressed: () async {
                  await _savePrivacySettings(dataSharing, locationTracking);
                  if (mounted) Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _showPrivacyPolicyDialog() async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Privacy Policy'),
        content: const SingleChildScrollView(
          child: Text(
            '**Privacy Policy for Fleet Management App**\n\n'
            'This Privacy Policy describes how your personal information is collected, used, and shared when you use our Fleet Management mobile application.\n\n'
            '**Information We Collect**\n\n'
            'We collect information about you in a variety of ways when you use our App. This includes:\n'
            '* **Personal Information:** Your name, email address, phone number, and other contact details.\n'
            '* **Vehicle Information:** Details about the vehicles in your fleet, including make, model, year, and vehicle identification number (VIN).\n'
            '* **Location Information:** Real-time location data of your vehicles.\n'
            '* **Usage Data:** Information about how you use our App, such as the features you use and the time, frequency, and duration of your activities.\n\n'
            '**How We Use Your Information**\n\n'
            'We use the information we collect to:\n'
            '* Provide, maintain, and improve our App and services.\n'
            '* Monitor and analyze trends, usage, and activities in connection with our App.\n'
            '* Communicate with you, including to send you technical notices, updates, security alerts, and support and administrative messages.\n\n'
            '**Sharing Your Information**\n\n'
            'We may share your information as follows:\n'
            '* With vendors, consultants, and other service providers who need access to such information to carry out work on our behalf.\n'
            '* In response to a request for information if we believe disclosure is in accordance with, or required by, any applicable law, regulation, or legal process.\n\n'
            '**Your Choices**\n\n'
            'You may update, correct, or delete information about you at any time by logging into your account or contacting us. If you wish to delete your account, please contact us, but note that we may retain certain information as required by law or for legitimate business purposes.\n\n'
            '**Contact Us**\n\n'
            'If you have any questions about this Privacy Policy, please contact us at support@abrafleet.com.',
            textAlign: TextAlign.justify,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

Future<void> _showTermsOfServiceDialog() async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Terms of Service'),
        content: const SingleChildScrollView(
          child: Text(
            '**Terms of Service for Fleet Management App**\n\n'
            'These Terms of Service govern your use of our Fleet Management mobile application.\n\n'
            '**1. Acceptance of Terms**\n\n'
            'By accessing or using our App, you agree to be bound by these Terms. If you disagree with any part of the terms, you may not access the App.\n\n'
            '**2. Description of Service**\n\n'
            'Our App provides fleet management services, including but not limited to, vehicle tracking, driver monitoring, and reporting.\n\n'
            '**3. User Responsibilities**\n\n'
            'You are responsible for your use of the App and for any content you provide, including compliance with applicable laws, rules, and regulations. You are also responsible for safeguarding your account.\n\n'
            '**4. Prohibited Conduct**\n\n'
            'You agree not to use the App for any unlawful purpose or in any way that interrupts, damages, or impairs the service.\n\n'
            '**5. Termination**\n\n'
            'We may terminate or suspend your access to our App immediately, without prior notice or liability, for any reason whatsoever, including without limitation if you breach the Terms.\n\n'
            '**6. Changes to Terms**\n\n'
            'We reserve the right, at our sole discretion, to modify or replace these Terms at any time. We will provide notice of any changes by posting the new Terms of Service on this page.\n\n'
            '**Contact Us**\n\n'
            'If you have any questions about these Terms, please contact us at support@abrafleet.com.',
            textAlign: TextAlign.justify,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

Future<void> _savePrivacySettings(bool dataSharing, bool locationTracking) async {
  try {
    final userDataString = _prefs?.getString('user_data');
    final userData = userDataString != null ? jsonDecode(userDataString) : null;
    final userId = userData?['id'];
    
    if (_token == null || _token!.isEmpty) return;

    final apiService = ApiService();
    await apiService.put('/api/drivers/privacy/$userId', body: {
      'privacySettings': {
        'dataSharing': dataSharing,
        'locationTracking': locationTracking,
      },
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Privacy settings saved!'),
          backgroundColor: kSuccessColor,
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save settings: $e'),
          backgroundColor: kDangerColor,
        ),
      );
    }
  }
}

Future<void> _showHelpSupport() async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('Help & Support'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.contact_support, color: kPrimaryColor),
                title: const Text('Contact Support'),
                subtitle: const Text('Email: support@abrafleet.com'),
                onTap: () {
                  Navigator.pop(dialogContext);
                },
              ),
              ListTile(
                leading: const Icon(Icons.phone, color: kPrimaryColor),
                title: const Text('Call Support'),
                subtitle: const Text('Phone: +91-XXXX-XXXX-XX'),
                onTap: () {
                  Navigator.pop(dialogContext);
                },
              ),
              ListTile(
                leading: const Icon(Icons.article, color: kPrimaryColor),
                title: const Text('FAQ'),
                subtitle: const Text('Frequently asked questions'),
                onTap: () {
                  Navigator.pop(dialogContext);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bug_report, color: kPrimaryColor),
                title: const Text('Report Issue'),
                subtitle: const Text('Report bugs or problems'),
                onTap: () {
                  Navigator.pop(dialogContext);
                  _showReportIssueDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.info, color: kPrimaryColor),
                title: const Text('App Version'),
                subtitle: const Text('v1.0.0'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

Future<void> _showReportIssueDialog() async {
  final issueController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool isSubmitting = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: !isSubmitting,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Report Issue'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: issueController,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Describe the issue',
                        hintText: 'Tell us what went wrong...',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please describe the issue';
                        }
                        if (value.trim().length < 10) {
                          return 'Please provide more details';
                        }
                        return null;
                      },
                    ),
                    if (isSubmitting) ...[
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (formKey.currentState!.validate()) {
                          setDialogState(() => isSubmitting = true);
                          bool success = await _submitIssueReport(issueController.text);
                          if (success && mounted) {
                            Navigator.pop(context);
                          } else {
                             setDialogState(() => isSubmitting = false);
                          }
                        }
                      },
                child: const Text('Submit'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<bool> _submitIssueReport(String issue) async {
  try {
    final userDataString = _prefs?.getString('user_data');
    final userData = userDataString != null ? jsonDecode(userDataString) : null;
    final userId = userData?['id'];
    
    if (_token == null || _token!.isEmpty) return false;

    final apiService = ApiService();
    await apiService.post('/api/support/issues', body: {
      'driverId': userId,
      'email': userData?['email'],
      'issue': issue,
      'status': 'open',
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Issue reported successfully. Our team will contact you soon.'),
          backgroundColor: kSuccessColor,
        ),
      );
    }
    return true;
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit report: $e'),
          backgroundColor: kDangerColor,
        ),
      );
    }
    return false;
  }
}
}

// ============== WIDGET AND SERVICE CLASSES ==============

class _DocumentStatusTile extends StatelessWidget {
  final String title;
  final DocumentStatus status;
  final VoidCallback onUpload;

  const _DocumentStatusTile({
    required this.title,
    required this.status,
    required this.onUpload,
  });

  (String, Color, IconData) _getStatusInfo() {
    if (!status.uploaded) return ('Not Uploaded', kDangerColor, Icons.cancel);
    if (status.verified)
      return ('Verified', kSuccessColor, Icons.check_circle);
    return ('Pending Verification', kWarningColor, Icons.hourglass_top_rounded);
  }
  
  Widget _buildPhotoDisplay(String photoUrl) {
    if (photoUrl.startsWith('data:image')) {
      try {
        final uriData = Uri.parse(photoUrl);
        return Image.memory(
          uriData.data!.contentAsBytes(),
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.person,
            color: kSecondaryTextColor,
            size: 28,
          ),
        );
      } catch (e) {
        return const Icon(
          Icons.person,
          color: kSecondaryTextColor,
          size: 28,
        );
      }
    } else {
      return Image.network(
        photoUrl,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.person,
          color: kSecondaryTextColor,
          size: 28,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (text, color, icon) = _getStatusInfo();

    final bool isDailyPhotoUploadedToday = status.lastUpload != null &&
        DateUtils.isSameDay(status.lastUpload, DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        children: [
          Row(
            children: [
              if (title == 'Daily Verification Photo' &&
                  status.dailyPhotoUrl != null &&
                  isDailyPhotoUploadedToday)
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: _buildPhotoDisplay(status.dailyPhotoUrl!),
                  ),
                )
              else
                Icon(icon, color: color, size: 28),
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
                        color: kPrimaryTextColor,
                      ),
                    ),
                    Text(
                      (title == 'Daily Verification Photo' &&
                              isDailyPhotoUploadedToday)
                          ? 'Uploaded Today'
                          : text,
                      style: TextStyle(
                        color: (title == 'Daily Verification Photo' &&
                                isDailyPhotoUploadedToday)
                            ? kSuccessColor
                            : color,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (status.lastUpload != null &&
                        title == 'Daily Verification Photo')
                      Text(
                        'Last: ${DateFormat.yMMMd().add_jm().format(status.lastUpload!)}',
                        style: const TextStyle(
                          color: kSecondaryTextColor,
                          fontSize: 12,
                        ),
                      ),
                    if (status.expiryDate != null)
                      Text(
                        'Expires: ${DateFormat.yMMMd().format(status.expiryDate!)}',
                        style: TextStyle(
                          color: status.expiryDate!.isBefore(DateTime.now())
                              ? kDangerColor
                              : kSecondaryTextColor,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: (title == 'Daily Verification Photo' &&
                        isDailyPhotoUploadedToday)
                    ? null
                    : onUpload,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      status.uploaded ? kSecondaryButtonColor : kPrimaryColor,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: Text(status.uploaded ? 'Re-upload' : 'Upload'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DocumentService {
  final ApiService _apiService = ApiService();

  Future<Map<String, DocumentStatus>> getDocumentStatus(String driverId) async {
    try {
      final responseData = await _apiService.get('/api/driver-documents/status/$driverId');
      final data = responseData['data'] as Map<String, dynamic>;

      final Map<String, DocumentStatus> statuses = {};

        if (data.containsKey('dailyVerificationPhoto')) {
          final dailyPhotoData = data['dailyVerificationPhoto'] as Map<String, dynamic>;
          statuses['dailyVerificationPhoto'] = DocumentStatus(
            uploaded: dailyPhotoData['uploaded'] ?? false,
            isRequired: dailyPhotoData['isRequired'] ?? true,
            verified: dailyPhotoData['verified'] ?? false,
            lastUpload: dailyPhotoData['lastUpload'] != null 
              ? DateTime.parse(dailyPhotoData['lastUpload'].toString()) 
              : null,
            expiryDate: dailyPhotoData['expiryDate'] != null 
              ? DateTime.parse(dailyPhotoData['expiryDate'].toString()) 
              : null,
            dailyPhotoUrl: dailyPhotoData['dailyPhotoUrl'] as String?,
          );
        }

        if (data.containsKey('license')) {
          final licenseData = data['license'] as Map<String, dynamic>;
          statuses['license'] = DocumentStatus(
            uploaded: licenseData['uploaded'] ?? false,
            isRequired: licenseData['isRequired'] ?? true,
            verified: licenseData['verified'] ?? false,
            expiryDate: licenseData['expiryDate'] != null 
              ? DateTime.parse(licenseData['expiryDate'].toString()) 
              : null,
          );
        }

        if (data.containsKey('medicalCertificate')) {
          final medicalData = data['medicalCertificate'] as Map<String, dynamic>;
          statuses['medicalCertificate'] = DocumentStatus(
            uploaded: medicalData['uploaded'] ?? false,
            isRequired: medicalData['isRequired'] ?? true,
            verified: medicalData['verified'] ?? false,
            expiryDate: medicalData['expiryDate'] != null 
              ? DateTime.parse(medicalData['expiryDate'].toString()) 
              : null,
          );
        }

        return statuses;
    } catch (e) {
      debugPrint('Error getting document status: $e');
      rethrow;
    }
  }

  Future<String> uploadDocument(
    String driverId,
    DocumentType type,
    XFile file,
    Map<String, String> fields,
  ) async {
    try {
      final (endpoint, fileField) = _getEndpointForType(type);
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/driver-documents/$endpoint/$driverId');
      var request = http.MultipartRequest('POST', uri)
        ..fields.addAll(fields);

      try {
        final prefs = await SharedPreferences.getInstance();
        final idToken = prefs.getString('jwt_token');
        if (idToken != null) {
          request.headers['Authorization'] = 'Bearer $idToken';
        }
      } catch (e) {
        debugPrint('❌ Could not get JWT token: $e');
      }

      final mimeType = _getMimeType(file.name);

      if (kIsWeb) {
        request.files.add(
          http.MultipartFile.fromBytes(
            fileField,
            await file.readAsBytes(),
            filename: file.name,
            contentType: MediaType.parse(mimeType),
          ),
        );
      } else {
        request.files.add(
          await http.MultipartFile.fromPath(
            fileField,
            file.path,
            filename: file.name,
            contentType: MediaType.parse(mimeType),
          ),
        );
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final jsonResponse = json.decode(responseBody);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonResponse['message'] ?? 'Upload successful';
      } else {
        throw Exception(
          jsonResponse['message'] ?? 'Failed to upload: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Error uploading document: $e');
      rethrow;
    }
  }

  String _getMimeType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'application/octet-stream';
    }
  }

  (String, String) _getEndpointForType(DocumentType type) {
    switch (type) {
      case DocumentType.profilePhoto:
        return ('upload-profile-photo', 'photo');
      case DocumentType.dailyVerificationPhoto:
        return ('upload-daily-photo', 'photo');
      case DocumentType.license:
        return ('upload-license', 'license');
      case DocumentType.medicalCertificate:
        return ('upload-medical-certificate', 'certificate');
    }
  }
}