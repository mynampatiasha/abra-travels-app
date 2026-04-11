// lib/features/profile/presentation/screens/customer_profile_screen.dart
// COMPLETE FILE - Profile with inline editing and photo upload

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// Firebase removed - using HTTP API
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/auth/presentation/screens/welcome_screen.dart';
import 'package:abra_fleet/core/services/backend_connection_manager.dart';
import 'package:abra_fleet/app/config/api_config.dart';
//import 'package:abra_fleet/features/hrm_feedback/presentation/screens/hrm_customer_feedback_screen.dart';
import 'package:abra_fleet/features/admin/hrm/hrm_feedback.dart';

class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({super.key});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  Map<String, dynamic>? _profileData;
  bool _isLoading = true;
  bool _isEditMode = false;
  bool _isUploading = false;
  String? _errorMessage;
  File? _selectedImage;
  XFile? _selectedImageWeb; // For web platform
  Uint8List? _selectedImageBytes; // For web platform
  String? _profilePhotoUrl;

  // Text controllers for editing
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _altPhoneController = TextEditingController();
  final _companyController = TextEditingController();
  final _employeeIdController = TextEditingController();
  final _designationController = TextEditingController();
  
  String? _selectedDepartment;
  final List<String> _departments = [
    'Engineering',
    'Human Resources',
    'Finance',
    'Sales',
    'Marketing',
    'Operations',
    'IT Support',
    'Customer Service',
    'Product Management',
    'Legal',
    'Administration',
    'Research & Development',
  ];

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fetchProfileData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _altPhoneController.dispose();
    _companyController.dispose();
    _employeeIdController.dispose();
    _designationController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfileData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authRepo = Provider.of<AuthRepository>(context, listen: false);
      final currentUser = authRepo.currentUser;

      if (currentUser.id.isEmpty) {
        throw Exception('No user logged in');
      }

      debugPrint('📱 Fetching profile for user: ${currentUser.id}');
      debugPrint('📱 Current user data: ${currentUser.toString()}');

      // Fetch profile from HTTP API - customer stats profile endpoint
      final apiService = ApiService();
      debugPrint('🌐 Making API call to: /api/customer/stats/profile');
      
      final response = await apiService.get('/api/customer/stats/profile');
      
      debugPrint('📥 API Response received: ${response.toString()}');
      debugPrint('📥 Response success: ${response['success']}');
      debugPrint('📥 Response data: ${response['data']}');
      
      if (response['success'] == true && response['data'] != null) {
        final data = response['data'] as Map<String, dynamic>;
        _profileData = data;
        _profilePhotoUrl = data['photoUrl'] as String?;
        
        debugPrint('📋 Profile data fields:');
        debugPrint('   Name: ${data['name']}');
        debugPrint('   Email: ${data['email']}');
        debugPrint('   Phone: ${data['phoneNumber']}');
        debugPrint('   Alt Phone: ${data['alternativePhone']}');
        debugPrint('   Company: ${data['companyName']}');
        debugPrint('   Department: ${data['department']}');
        debugPrint('   Employee ID: ${data['employeeId']}');
        debugPrint('   Designation: ${data['designation']}');
        
        // Populate controllers with null safety
        _nameController.text = (data['name'] as String?) ?? '';
        _phoneController.text = (data['phoneNumber'] as String?) ?? '';
        _altPhoneController.text = (data['alternativePhone'] as String?) ?? '';
        _companyController.text = (data['companyName'] as String?) ?? '';
        _employeeIdController.text = (data['employeeId'] as String?) ?? '';
        _designationController.text = (data['designation'] as String?) ?? '';
        _selectedDepartment = data['department'] as String?;
        
        debugPrint('✅ Profile data loaded from HTTP API');
        debugPrint('✅ Controllers populated successfully');
      } else {
        debugPrint('❌ API response indicates failure or no data');
        debugPrint('❌ Response: ${response.toString()}');
        throw Exception('No profile data found: ${response['message'] ?? 'Unknown error'}');
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching profile: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load profile: $e';
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      // For web, only show gallery option since camera access is limited
      ImageSource source = ImageSource.gallery;
      
      if (!kIsWeb) {
        // Show dialog to choose between camera and gallery on mobile
        final ImageSource? selectedSource = await showDialog<ImageSource>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Choose Photo Source'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.camera_alt, color: Color(0xFF4F46E5)),
                    title: const Text('Camera'),
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library, color: Color(0xFF4F46E5)),
                    title: const Text('Gallery'),
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                  ),
                ],
              ),
            );
          },
        );
        
        if (selectedSource == null) return;
        source = selectedSource;
      }

      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          if (kIsWeb) {
            _selectedImageWeb = image;
            _selectedImage = null;
            // Load image bytes for web display
            image.readAsBytes().then((bytes) {
              setState(() {
                _selectedImageBytes = bytes;
              });
            });
          } else {
            _selectedImage = File(image.path);
            _selectedImageWeb = null;
            _selectedImageBytes = null;
          }
        });
        
        // Show confirmation dialog
        final bool? confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Upload Photo'),
            content: const Text('Do you want to upload this photo as your profile picture?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                ),
                child: const Text('Upload'),
              ),
            ],
          ),
        );

        if (confirm == true) {
          await _uploadProfilePhoto();
        } else {
          setState(() {
            _selectedImage = null;
            _selectedImageWeb = null;
            _selectedImageBytes = null;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadProfilePhoto() async {
    if (_selectedImage == null && _selectedImageWeb == null) return;

    setState(() {
      _isUploading = true;
    });

    try {
            final prefs = await SharedPreferences.getInstance();            final token = prefs.getString('jwt_token');            final userDataString = prefs.getString('user_data');            final userData = userDataString != null ? jsonDecode(userDataString) : null;            final userId = userData?['id'];
      if (token == null || token.isEmpty) throw Exception('No user logged in');

      // Get auth token
      // Token already retrieved above
      if (token == null) throw Exception('Failed to get auth token');

      // Create multipart request
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/auth/upload-photo');

      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      
      // Add file based on platform
      if (kIsWeb && _selectedImageWeb != null) {
        // Web platform - use XFile directly
        final bytes = await _selectedImageWeb!.readAsBytes();
        request.files.add(
          http.MultipartFile.fromBytes(
            'photo',
            bytes,
            filename: _selectedImageWeb!.name,
          ),
        );
      } else if (!kIsWeb && _selectedImage != null) {
        // Mobile platform - use File path
        request.files.add(
          await http.MultipartFile.fromPath('photo', _selectedImage!.path),
        );
      } else {
        throw Exception('No image selected for upload');
      }

      debugPrint('📤 Uploading photo to: $uri');

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('📥 Response status: ${response.statusCode}');
      debugPrint('📥 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        
        if (responseData['success'] == true) {
          final newPhotoUrl = responseData['photoUrl'];
          
          // Photo URL already updated via HTTP API on the backend
          // No additional update needed here

          setState(() {
            _profilePhotoUrl = newPhotoUrl;
            _selectedImage = null;
            _selectedImageWeb = null;
            _selectedImageBytes = null;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Profile photo updated successfully!'),
                backgroundColor: Colors.green,
              ),
            );
          }

          // Refresh profile data
          await _fetchProfileData();
        } else {
          throw Exception(responseData['message'] ?? 'Upload failed');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error uploading photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    setState(() {
      _isLoading = true;
    });

    try {
            final prefs = await SharedPreferences.getInstance();            final token = prefs.getString('jwt_token');            final userDataString = prefs.getString('user_data');            final userData = userDataString != null ? jsonDecode(userDataString) : null;            final userId = userData?['id'];
      if (token == null || token.isEmpty) throw Exception('No user logged in');

      // Prepare phone numbers
      String phone = _phoneController.text.trim();
      if (phone.isNotEmpty && !phone.startsWith('+')) {
        phone = '+91$phone';
      }

      String? altPhone = _altPhoneController.text.trim();
      if (altPhone != null && altPhone.isNotEmpty && !altPhone.startsWith('+')) {
        altPhone = '+91$altPhone';
      }

      // Update profile via HTTP API - customer stats profile endpoint
      final apiService = ApiService();
      await apiService.put('/api/customer/stats/profile', body: {
        'name': _nameController.text.trim(),
        'phoneNumber': phone,
        'alternativePhone': altPhone.isEmpty ? null : altPhone,
        'companyName': _companyController.text.trim(),
        'department': _selectedDepartment,
        'employeeId': _employeeIdController.text.trim().isEmpty 
            ? null 
            : _employeeIdController.text.trim(),
        'designation': _designationController.text.trim().isEmpty 
            ? null 
            : _designationController.text.trim(),
      });

      // Also update MongoDB via backend
      try {
        final authRepo = Provider.of<AuthRepository>(context, listen: false);
        await authRepo.updateUserProfile(
          userId: userId,
          name: _nameController.text.trim(),
          phoneNumber: phone,
        );
      } catch (e) {
        debugPrint('⚠️ MongoDB update failed (non-critical): $e');
      }

      setState(() {
        _isEditMode = false;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Profile updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Refresh profile data
      await _fetchProfileData();
    } catch (e) {
      debugPrint('❌ Error saving profile: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _cancelEdit() {
    setState(() {
      _isEditMode = false;
      // Reset controllers to original values
      _nameController.text = _profileData?['name'] ?? '';
      _phoneController.text = _profileData?['phoneNumber'] ?? '';
      _altPhoneController.text = _profileData?['alternativePhone'] ?? '';
      _companyController.text = _profileData?['companyName'] ?? '';
      _employeeIdController.text = _profileData?['employeeId'] ?? '';
      _designationController.text = _profileData?['designation'] ?? '';
      _selectedDepartment = _profileData?['department'];
    });
  }

  Future<void> _deleteAccount() async {
    // Step 1: confirmation dialog
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null || token.isEmpty) throw Exception('Not authenticated');

      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/delete-account'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        // Clear all local session data
        await prefs.clear();

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            (route) => false,
          );
        }
      } else {
        throw Exception(responseData['message'] ?? 'Failed to delete account');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleLogout() async {
    try {
      final authRepo = Provider.of<AuthRepository>(context, listen: false);
      await authRepo.signOut();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const WelcomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error signing out: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getInitials(String? name) {
    if (name == null || name.isEmpty) return 'C';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorView()
              : _buildProfileContent(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchProfileData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileContent() {
    final name = _profileData?['name'] as String? ?? 'Customer';
    final email = _profileData?['email'] as String? ?? 'N/A';
    final role = _profileData?['role'] as String? ?? 'customer';
    final status = _profileData?['status'] as String? ?? 'Active';

    return RefreshIndicator(
      onRefresh: _fetchProfileData,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Photo Section (without background)
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // Profile Photo with Camera Icon
                    Stack(
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey[100],
                            border: Border.all(color: Colors.grey[300]!, width: 2),
                          ),
                          child: ClipOval(
                            child: _isUploading
                                ? const Center(
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFF4F46E5),
                                      ),
                                    ),
                                  )
                                : _selectedImageBytes != null
                                    ? Image.memory(
                                        _selectedImageBytes!,
                                        fit: BoxFit.cover,
                                        width: 120,
                                        height: 120,
                                      )
                                : _selectedImage != null
                                    ? Image.file(
                                        _selectedImage!,
                                        fit: BoxFit.cover,
                                        width: 120,
                                        height: 120,
                                      )
                                    : (_profilePhotoUrl != null && _profilePhotoUrl!.isNotEmpty)
                                        ? Image.network(
                                            '${ApiConfig.baseUrl}$_profilePhotoUrl',
                                            fit: BoxFit.cover,
                                            width: 120,
                                            height: 120,
                                            errorBuilder: (context, error, stackTrace) {
                                              return Center(
                                                child: Text(
                                                  _getInitials(name),
                                                  style: const TextStyle(
                                                    fontSize: 48,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF4F46E5),
                                                  ),
                                                ),
                                              );
                                            },
                                          )
                                        : Center(
                                            child: Text(
                                              _getInitials(name),
                                              style: const TextStyle(
                                                fontSize: 48,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF4F46E5),
                                              ),
                                            ),
                                          ),
                          ),
                        ),
                        // Camera Icon Button
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _isUploading ? null : _pickImage,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF4F46E5),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // User Name
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Role Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF4F46E5).withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        role.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4F46E5),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
                  // Account Status (if pending)
                  if (status.toLowerCase() == 'pending')
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.hourglass_empty, color: Colors.orange[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Account Pending Approval',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.orange[900],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Your account is awaiting admin approval',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Edit/Save Button
                  if (!_isEditMode)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => setState(() => _isEditMode = true),
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit Profile'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _saveProfile,
                            icon: const Icon(Icons.check),
                            label: const Text('Save Changes'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _cancelEdit,
                            icon: const Icon(Icons.close),
                            label: const Text('Cancel'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey[700],
                              side: BorderSide(color: Colors.grey[400]!),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 24),

                  // Personal Information Section
                  _buildSectionCard(
                    title: 'Personal Information',
                    icon: Icons.person_outline,
                    children: [
                      _buildInfoField(
                        icon: Icons.email_outlined,
                        label: 'Email',
                        value: email,
                      ),
                      _buildEditableField(
                        icon: Icons.person,
                        label: 'Full Name',
                        controller: _nameController,
                      ),
                      _buildEditableField(
                        icon: Icons.phone_outlined,
                        label: 'Phone Number',
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                      ),
                      _buildEditableField(
                        icon: Icons.phone_android_outlined,
                        label: 'Alternative Phone',
                        controller: _altPhoneController,
                        keyboardType: TextInputType.phone,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Organization Information Section
                  _buildSectionCard(
                    title: 'Organization Information',
                    icon: Icons.business_outlined,
                    children: [
                      _buildEditableField(
                        icon: Icons.business_center_outlined,
                        label: 'Company Name',
                        controller: _companyController,
                      ),
                      _buildDepartmentField(),
                      _buildEditableField(
                        icon: Icons.badge_outlined,
                        label: 'Employee ID',
                        controller: _employeeIdController,
                      ),
                      _buildEditableField(
                        icon: Icons.work_outline,
                        label: 'Designation',
                        controller: _designationController,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ============================================================
                  // FEEDBACK & SUPPORT SECTION - ADD THIS ENTIRE BLOCK
                  // ============================================================
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3b82f6), Color(0xFF2563eb)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3b82f6).withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.feedback,
                          size: 48,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Feedback & Support',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Share your thoughts and help us improve',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => HRMFeedbackScreen(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF3b82f6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.message),
                              SizedBox(width: 8),
                              Text(
                                'Submit Feedback',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ============================================================
                  // END OF FEEDBACK SECTION
                  // ============================================================

                  const SizedBox(height: 24),

                  // Logout Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _handleLogout,
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: const Text(
                        'Logout',
                        style: TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Delete Account Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _deleteAccount,
                      icon: const Icon(Icons.delete_forever, color: Colors.white),
                      label: const Text(
                        'Delete Account',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
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
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF4F46E5), size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoField({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: const Color(0xFF4F46E5),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF1E293B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) {
    if (!_isEditMode) {
      return _buildInfoField(
        icon: icon,
        label: label,
        value: controller.text.isEmpty ? 'Not provided' : controller.text,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: const Color(0xFF4F46E5),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              decoration: InputDecoration(
                labelText: label,
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentField() {
    if (!_isEditMode) {
      return _buildInfoField(
        icon: Icons.category_outlined,
        label: 'Department',
        value: _selectedDepartment ?? 'Not provided',
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.category_outlined,
              size: 20,
              color: Color(0xFF4F46E5),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedDepartment,
              decoration: InputDecoration(
                labelText: 'Department',
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              items: _departments.map((dept) {
                return DropdownMenuItem(
                  value: dept,
                  child: Text(dept),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedDepartment = value;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
