// lib/features/client/presentation/screens/client_profile_page.dart
// Professional Client Profile Page — UI styled to match careers page

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/auth/presentation/screens/welcome_screen.dart';

// ── Color system matching careers page (blues + slate) ──────────────────────
class ClientTheme {
  // Primary blues (matches careers page gradient)
  static const Color primaryDarkest  = Color(0xFF0F172A); // #0f172a
  static const Color primaryDark     = Color(0xFF1E3A8A); // #1e3a8a
  static const Color primaryBlue     = Color(0xFF1E40AF); // #1e40af
  static const Color accentBlue      = Color(0xFF3B82F6); // #3b82f6
  static const Color lightBlue       = Color(0xFF93C5FD); // #93c5fd

  // Backgrounds (matches careers page)
  static const Color backgroundGray  = Color(0xFFF8FAFC); // #f8fafc
  static const Color backgroundLight = Color(0xFFF0F6FF); // #f0f6ff
  static const Color cardWhite       = Color(0xFFFFFFFF);

  // Card header bg (matches .cr-form-hdr: linear-gradient #eff6ff to #dbeafe)
  static const Color cardHeaderBg    = Color(0xFFEFF6FF); // #eff6ff
  static const Color cardHeaderBg2   = Color(0xFFDBEAFE); // #dbeafe
  static const Color cardBorder      = Color(0xFFBFDBFE); // #bfdbfe

  // Text (matches slate palette)
  static const Color textDark        = Color(0xFF1E293B); // #1e293b
  static const Color textMedium      = Color(0xFF334155); // #334155
  static const Color textSlate       = Color(0xFF475569); // #475569
  static const Color textLight       = Color(0xFF64748B); // #64748b
  static const Color textMuted       = Color(0xFF94A3B8); // #94a3b8

  // Input border (matches .cr-input border)
  static const Color inputBorder     = Color(0xFFE2E8F0); // #e2e8f0

  // Status
  static const Color successGreen    = Color(0xFF16A34A); // #16a34a
  static const Color warningOrange   = Color(0xFFF59E0B);
  static const Color dangerRed       = Color(0xFFEF4444);
}

class ClientProfilePage extends StatefulWidget {
  const ClientProfilePage({Key? key}) : super(key: key);

  @override
  State<ClientProfilePage> createState() => _ClientProfilePageState();
}

class _ClientProfilePageState extends State<ClientProfilePage> {
  final ApiService _apiService = ApiService();
  final ImagePicker _imagePicker = ImagePicker();

  Map<String, dynamic>? _clientData;
  bool _isLoading = true;
  bool _isEditMode = false;
  bool _isUploading = false;
  String? _errorMessage;

  File? _selectedImage;
  XFile? _selectedImageWeb;
  Uint8List? _selectedImageBytes;
  String? _profilePhotoUrl;

  final _formKey = GlobalKey<FormState>();
  final _nameController          = TextEditingController();
  final _emailController         = TextEditingController();
  final _phoneController         = TextEditingController();
  final _organizationController  = TextEditingController();
  final _addressController       = TextEditingController();
  final _contactPersonController = TextEditingController();
  final _gstController           = TextEditingController();
  final _panController           = TextEditingController();

  SharedPreferences? _prefs;
  String? _token;
  String? _clientId;

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _organizationController.dispose();
    _addressController.dispose();
    _contactPersonController.dispose();
    _gstController.dispose();
    _panController.dispose();
    super.dispose();
  }

  // ── Auth ─────────────────────────────────────────────────────────────────────
  Future<void> _initializeAuth() async {
    _prefs = await SharedPreferences.getInstance();
    _token = _prefs?.getString('jwt_token');
    final userDataString = _prefs?.getString('user_data');
    if (userDataString != null) {
      final userData = jsonDecode(userDataString);
      _clientId = userData['id'];
    }
    await _fetchClientProfile();
  }

  Future<void> _fetchClientProfile() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      if (_token == null || _token!.isEmpty) throw Exception('Not authenticated. Please login again.');
      final response = await _apiService.get('/api/clients/profile');
      if (response['success'] == true && response['data'] != null) {
        final data = response['data'] as Map<String, dynamic>;
        if (data['id'] != null && _prefs != null) {
          final userDataString = _prefs!.getString('user_data');
          if (userDataString != null) {
            final userData = jsonDecode(userDataString);
            userData['id'] = data['id'];
            await _prefs!.setString('user_data', jsonEncode(userData));
            _clientId = data['id'];
          }
        }
        if (!mounted) return;
        setState(() {
          _clientData = data;
          _profilePhotoUrl = data['photoUrl'] as String?;
          _nameController.text          = data['name'] ?? '';
          _emailController.text         = data['email'] ?? '';
          _phoneController.text         = data['phoneNumber'] ?? data['phone'] ?? '';
          _organizationController.text  = data['organizationName'] ?? data['companyName'] ?? '';
          _addressController.text       = data['address'] ?? '';
          _contactPersonController.text = data['contactPerson'] ?? '';
          _gstController.text           = data['gstNumber'] ?? '';
          _panController.text           = data['panNumber'] ?? '';
          _isLoading = false;
        });
      } else {
        throw Exception(response['message'] ?? 'Failed to load profile');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoading = false; _errorMessage = 'Failed to load profile: $e'; });
    }
  }

  Future<void> _updateClientProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.put('/api/clients/$_clientId', body: {
        'name':          _nameController.text.trim(),
        'email':         _emailController.text.trim(),
        'phoneNumber':   _phoneController.text.trim(),
        'address':       _addressController.text.trim(),
        'contactPerson': _contactPersonController.text.trim(),
        'gstNumber': _gstController.text.trim().isEmpty ? null : _gstController.text.trim(),
        'panNumber': _panController.text.trim().isEmpty ? null : _panController.text.trim(),
      });
      if (response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ Profile updated successfully!'),
            backgroundColor: ClientTheme.successGreen,
          ));
          setState(() => _isEditMode = false);
          await _fetchClientProfile();
        }
      } else {
        throw Exception(response['message'] ?? 'Update failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to update profile: $e'),
          backgroundColor: ClientTheme.dangerRed,
        ));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      ImageSource source = ImageSource.gallery;
      if (!kIsWeb) {
        final ImageSource? selectedSource = await showDialog<ImageSource>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Choose Photo Source'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: ClientTheme.primaryBlue),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: ClientTheme.primaryBlue),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ]),
          ),
        );
        if (selectedSource == null) return;
        source = selectedSource;
      }
      final XFile? image = await _imagePicker.pickImage(
          source: source, maxWidth: 800, maxHeight: 800, imageQuality: 85);
      if (image != null) {
        setState(() {
          if (kIsWeb) {
            _selectedImageWeb = image; _selectedImage = null;
            image.readAsBytes().then((bytes) => setState(() => _selectedImageBytes = bytes));
          } else {
            _selectedImage = File(image.path); _selectedImageWeb = null; _selectedImageBytes = null;
          }
        });
        final bool? confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Upload Photo'),
            content: const Text('Do you want to upload this photo as your profile picture?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: ClientTheme.primaryBlue),
                child: const Text('Upload'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await _uploadProfilePhoto();
        } else {
          setState(() { _selectedImage = null; _selectedImageWeb = null; _selectedImageBytes = null; });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to pick image: $e'),
          backgroundColor: ClientTheme.dangerRed,
        ));
      }
    }
  }

  Future<void> _uploadProfilePhoto() async {
    if (_selectedImage == null && _selectedImageWeb == null) return;
    setState(() => _isUploading = true);
    try {
      if (_token == null || _token!.isEmpty) throw Exception('No authentication token found');
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/auth/upload-photo');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_token';
      if (kIsWeb && _selectedImageWeb != null) {
        final bytes = await _selectedImageWeb!.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes('photo', bytes, filename: _selectedImageWeb!.name));
      } else if (!kIsWeb && _selectedImage != null) {
        request.files.add(await http.MultipartFile.fromPath('photo', _selectedImage!.path));
      } else {
        throw Exception('No image selected for upload');
      }
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          setState(() {
            _profilePhotoUrl = responseData['photoUrl'];
            _selectedImage = null; _selectedImageWeb = null; _selectedImageBytes = null;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('✅ Profile photo updated successfully!'),
              backgroundColor: ClientTheme.successGreen,
            ));
          }
          await _fetchClientProfile();
        } else {
          throw Exception(responseData['message'] ?? 'Upload failed');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to upload photo: $e'),
          backgroundColor: ClientTheme.dangerRed,
        ));
      }
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final currentPasswordController = TextEditingController();
    final newPasswordController     = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoading           = false;
    bool showCurrentPassword = false;
    bool showNewPassword     = false;
    bool showConfirmPassword = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change Password'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: currentPasswordController,
                  obscureText: !showCurrentPassword,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(showCurrentPassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setDialogState(() => showCurrentPassword = !showCurrentPassword),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Current password is required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: newPasswordController,
                  obscureText: !showNewPassword,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(showNewPassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setDialogState(() => showNewPassword = !showNewPassword),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'New password is required';
                    if (v.length < 6) return 'Password must be at least 6 characters';
                    if (v == currentPasswordController.text) return 'New password must be different';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: confirmPasswordController,
                  obscureText: !showConfirmPassword,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(showConfirmPassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setDialogState(() => showConfirmPassword = !showConfirmPassword),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => v != newPasswordController.text ? 'Passwords do not match' : null,
                ),
                if (isLoading) ...[const SizedBox(height: 16), const CircularProgressIndicator()],
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: ClientTheme.primaryBlue),
              onPressed: isLoading ? null : () async {
                if (formKey.currentState!.validate()) {
                  setDialogState(() => isLoading = true);
                  bool success = await _handlePasswordChange(
                      currentPasswordController.text, newPasswordController.text);
                  if (success && mounted) Navigator.pop(context);
                  else setDialogState(() => isLoading = false);
                }
              },
              child: const Text('Update Password'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _handlePasswordChange(String currentPassword, String newPassword) async {
    try {
      if (_token == null || _token!.isEmpty) throw Exception('User not authenticated');
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/change-password'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'currentPassword': currentPassword, 'newPassword': newPassword}),
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ Password updated successfully!'),
            backgroundColor: ClientTheme.successGreen,
          ));
        }
        return true;
      } else {
        throw Exception('Failed to update password');
      }
    } catch (e) {
      if (mounted) {
        String msg = 'Failed to update password';
        if (e.toString().contains('wrong-password')) msg = 'Current password is incorrect';
        if (e.toString().contains('weak-password'))  msg = 'New password is too weak';
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: ClientTheme.dangerRed));
      }
      return false;
    }
  }

  Future<void> _handleLogout() async {
    try {
      final authRepo = Provider.of<AuthRepository>(context, listen: false);
      await authRepo.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error signing out: $e'),
          backgroundColor: ClientTheme.dangerRed,
        ));
      }
    }
  }

  void _cancelEdit() {
    setState(() {
      _isEditMode = false;
      if (_clientData != null) {
        _nameController.text          = _clientData!['name'] ?? '';
        _emailController.text         = _clientData!['email'] ?? '';
        _phoneController.text         = _clientData!['phoneNumber'] ?? _clientData!['phone'] ?? '';
        _organizationController.text  = _clientData!['organizationName'] ?? _clientData!['companyName'] ?? '';
        _addressController.text       = _clientData!['address'] ?? '';
        _contactPersonController.text = _clientData!['contactPerson'] ?? '';
        _gstController.text           = _clientData!['gstNumber'] ?? '';
        _panController.text           = _clientData!['panNumber'] ?? '';
      }
    });
  }

  String _getInitials(String? name) {
    if (name == null || name.isEmpty) return 'C';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ClientTheme.backgroundGray,
      appBar: AppBar(
        title: const Text('Organization Profile',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [ClientTheme.primaryDarkest, ClientTheme.primaryDark, ClientTheme.primaryBlue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchClientProfile,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: ClientTheme.primaryBlue))
          : _errorMessage != null
              ? _buildErrorView()
              : _buildProfileContent(),
    );
  }

  // ── Error view ───────────────────────────────────────────────────────────────
  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, size: 64, color: ClientTheme.dangerRed),
          const SizedBox(height: 16),
          Text(_errorMessage ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: ClientTheme.textDark)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchClientProfile,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: ClientTheme.primaryBlue,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Main scrollable content ───────────────────────────────────────────────────
  Widget _buildProfileContent() {
    final name   = _clientData?['name']   as String? ?? 'Organization';
    final email  = _clientData?['email']  as String? ?? 'N/A';
    final status = _clientData?['status'] as String? ?? 'active';

    return RefreshIndicator(
      color: ClientTheme.primaryBlue,
      onRefresh: _fetchClientProfile,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        // ✅ Centered, max-width — no full-stretch on wide screens
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── Hero profile card ────────────────────────────────────────
                  _buildProfileHeroCard(name, email, status),
                  const SizedBox(height: 20),

                  // ── Edit / Save / Cancel buttons ─────────────────────────────
                  if (!_isEditMode) _buildEditButton() else _buildSaveCancelButtons(),
                  const SizedBox(height: 24),

                  // ── Step 1: Organization Info ────────────────────────────────
                  _buildStepCard(
                    stepNumber: '1',
                    icon: Icons.business,
                    title: 'Organization Information',
                    subtitle: 'Your company and address details',
                    children: [
                      _buildFormField(
                        controller: _nameController,
                        label: 'Organization Name',
                        icon: Icons.business_center,
                        isRequired: true,
                        validator: (v) => (v?.isEmpty ?? true) ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 16),
                      _buildFormField(
                        controller: _organizationController,
                        label: 'Company / Brand Name',
                        icon: Icons.badge,
                      ),
                      const SizedBox(height: 16),
                      _buildFormField(
                        controller: _addressController,
                        label: 'Registered Address',
                        icon: Icons.location_on,
                        maxLines: 3,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Step 2: Contact Info ─────────────────────────────────────
                  _buildStepCard(
                    stepNumber: '2',
                    icon: Icons.contact_phone,
                    title: 'Contact Information',
                    subtitle: 'Email, phone and contact person',
                    children: [
                      _buildFormField(
                        controller: _emailController,
                        label: 'Email Address',
                        icon: Icons.email,
                        enabled: false,
                        isRequired: true,
                        validator: (v) => (v?.isEmpty ?? true) ? 'Email is required' : null,
                      ),
                      const SizedBox(height: 16),
                      _buildFormField(
                        controller: _phoneController,
                        label: 'Phone Number',
                        icon: Icons.phone,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),
                      _buildFormField(
                        controller: _contactPersonController,
                        label: 'Contact Person',
                        icon: Icons.person,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Step 3: Tax & Compliance ─────────────────────────────────
                  _buildStepCard(
                    stepNumber: '3',
                    icon: Icons.receipt_long,
                    title: 'Tax & Compliance',
                    subtitle: 'GST and PAN details',
                    children: [
                      _buildFormField(
                        controller: _gstController,
                        label: 'GST Number',
                        icon: Icons.receipt,
                        hintText: 'Enter GST number (optional)',
                      ),
                      const SizedBox(height: 16),
                      _buildFormField(
                        controller: _panController,
                        label: 'PAN Number',
                        icon: Icons.credit_card,
                        hintText: 'Enter PAN number (optional)',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Step 4: Account Settings ─────────────────────────────────
                  _buildStepCard(
                    stepNumber: '4',
                    icon: Icons.settings,
                    title: 'Account Settings',
                    subtitle: 'Password and security options',
                    children: [
                      _buildSettingsListTile(
                        icon: Icons.lock_outline,
                        iconColor: ClientTheme.accentBlue,
                        title: 'Change Password',
                        subtitle: 'Update your account password',
                        onTap: _showChangePasswordDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── Logout button ────────────────────────────────────────────
                  _buildLogoutButton(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // WIDGET BUILDERS
  // ════════════════════════════════════════════════════════════════════════════

  /// Hero card — dark gradient matching careers hero section
  Widget _buildProfileHeroCard(String name, String email, String status) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [ClientTheme.primaryDarkest, ClientTheme.primaryDark, ClientTheme.primaryBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: ClientTheme.primaryBlue.withOpacity(0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(children: [

          // Avatar with camera overlay
          Stack(children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.15),
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: ClipOval(
                child: _isUploading
                    ? const Center(
                        child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(Colors.white)))
                    : _selectedImageBytes != null
                        ? Image.memory(_selectedImageBytes!, fit: BoxFit.cover)
                        : _selectedImage != null
                            ? Image.file(_selectedImage!, fit: BoxFit.cover)
                            : (_profilePhotoUrl != null && _profilePhotoUrl!.isNotEmpty)
                                ? Image.network(
                                    '${ApiConfig.baseUrl}$_profilePhotoUrl',
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Center(
                                      child: Text(_getInitials(name),
                                          style: const TextStyle(
                                              fontSize: 38, fontWeight: FontWeight.bold, color: Colors.white)),
                                    ),
                                  )
                                : Center(
                                    child: Text(_getInitials(name),
                                        style: const TextStyle(
                                            fontSize: 38, fontWeight: FontWeight.bold, color: Colors.white)),
                                  ),
              ),
            ),
            Positioned(
              bottom: 0, right: 0,
              child: GestureDetector(
                onTap: _isUploading ? null : _pickImage,
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, color: Colors.white,
                    border: Border.all(color: ClientTheme.primaryBlue, width: 2),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6)],
                  ),
                  child: const Icon(Icons.camera_alt, color: ClientTheme.primaryBlue, size: 16),
                ),
              ),
            ),
          ]),

          const SizedBox(height: 16),
          Text(name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
            textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(email,
            style: TextStyle(fontSize: 13.5, color: Colors.white.withOpacity(0.85)),
            textAlign: TextAlign.center),
          const SizedBox(height: 14),

          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(
              color: status.toLowerCase() == 'active'
                  ? ClientTheme.successGreen
                  : ClientTheme.warningOrange,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                status.toLowerCase() == 'active' ? Icons.check_circle : Icons.hourglass_empty,
                color: Colors.white, size: 15),
              const SizedBox(width: 6),
              Text(status.toUpperCase(),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1.2)),
            ]),
          ),
        ]),
      ),
    );
  }

  /// Step card — matches .cr-form-card + .cr-form-hdr from careers page exactly
  Widget _buildStepCard({
    required String stepNumber,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: ClientTheme.cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ClientTheme.cardBorder, width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header — light blue gradient bg + border-bottom (matches .cr-form-hdr)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [ClientTheme.cardHeaderBg, ClientTheme.cardHeaderBg2],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            border: Border(bottom: BorderSide(color: ClientTheme.cardBorder, width: 2)),
          ),
          child: Row(children: [
            // Gradient icon box — matches .cr-form-hdr-icon
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [ClientTheme.primaryDark, ClientTheme.accentBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Title — bold dark blue (matches .cr-form-hdr h3)
                Text('Step $stepNumber — $title',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: ClientTheme.primaryDark)),
                const SizedBox(height: 2),
                // Subtitle — accent blue bold (matches .cr-form-hdr p)
                Text(subtitle,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600, color: ClientTheme.accentBlue)),
              ]),
            ),
          ]),
        ),

        // Body
        Padding(
          padding: const EdgeInsets.all(22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ]),
    );
  }

  /// Form field — matches .cr-input (2px slate border, 10px radius, slate label)
  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hintText,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool enabled = true,
    bool isRequired = false,
  }) {
    final bool isActive = enabled && _isEditMode;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // Label row — matches .cr-label style
      Row(children: [
        Text(label,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: ClientTheme.textMedium)),
        if (isRequired) ...[
          const SizedBox(width: 3),
          const Text('*', style: TextStyle(color: ClientTheme.dangerRed, fontSize: 13)),
        ] else ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Text('Optional',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: ClientTheme.textLight)),
          ),
        ],
      ]),
      const SizedBox(height: 7),

      TextFormField(
        controller: controller,
        enabled: isActive,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        style: TextStyle(
            fontSize: 14,
            color: isActive ? ClientTheme.textDark : ClientTheme.textLight),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: ClientTheme.textMuted, fontSize: 13.5),
          prefixIcon: Icon(icon,
              color: isActive ? ClientTheme.primaryBlue : ClientTheme.textMuted, size: 20),
          filled: true,
          fillColor: isActive ? Colors.white : ClientTheme.backgroundGray,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          // Matches .cr-input: 2px border, 10px radius
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: ClientTheme.inputBorder, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: ClientTheme.inputBorder, width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: ClientTheme.primaryDark, width: 2),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: ClientTheme.inputBorder, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: ClientTheme.dangerRed, width: 2),
          ),
        ),
      ),
    ]);
  }

  /// Settings list tile (for account settings card body)
  Widget _buildSettingsListTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: ClientTheme.backgroundGray,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: ClientTheme.textDark)),
                const SizedBox(height: 2),
                Text(subtitle,
                  style: const TextStyle(fontSize: 12.5, color: ClientTheme.textLight)),
              ]),
            ),
            const Icon(Icons.arrow_forward_ios, size: 15, color: ClientTheme.textMuted),
          ]),
        ),
      ),
    );
  }

  /// Edit Profile button — gradient matching careers .cr-submit-btn
  Widget _buildEditButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [ClientTheme.accentBlue, ClientTheme.primaryBlue],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(
            color: ClientTheme.accentBlue.withOpacity(0.35),
            blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _isEditMode = true),
          borderRadius: BorderRadius.circular(13),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.edit, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Edit Profile',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
            ]),
          ),
        ),
      ),
    );
  }

  /// Save Changes + Cancel buttons
  Widget _buildSaveCancelButtons() {
    return Row(children: [
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: ClientTheme.successGreen,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: ClientTheme.successGreen.withOpacity(0.3),
                  blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _updateClientProfile,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 15),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.check, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Save Changes',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                ]),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ClientTheme.inputBorder, width: 2),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _cancelEdit,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 15),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.close, color: ClientTheme.textLight, size: 18),
                  SizedBox(width: 8),
                  Text('Cancel',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ClientTheme.textLight)),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  /// Logout button — red outlined style
  Widget _buildLogoutButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: ClientTheme.dangerRed, width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _handleLogout,
          borderRadius: BorderRadius.circular(13),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.logout, color: ClientTheme.dangerRed, size: 20),
              SizedBox(width: 10),
              Text('Logout',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ClientTheme.dangerRed)),
            ]),
          ),
        ),
      ),
    );
  }
}