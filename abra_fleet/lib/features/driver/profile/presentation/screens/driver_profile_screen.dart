// ============================================================================
// COMPLETE UPDATED: lib/features/driver/profile/presentation/screens/driver_profile_screen.dart
// Driver Profile Screen with Full Attendance Integration
// ============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../auth/domain/repositories/auth_repository.dart';
import '../../../../admin/driver_management/domain/entities/driver_entity.dart';
import '../../../../admin/driver_management/presentation/providers/driver_provider.dart';

// 🆕 ATTENDANCE IMPORT
import 'driver_attendance_widget.dart';
import 'edit_driver_profile_screen.dart';
import 'driver_documents_screen.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({Key? key}) : super(key: key);

  @override
  State<DriverProfileScreen> createState() => DriverProfileScreenState();
}

class DriverProfileScreenState extends State<DriverProfileScreen> {
  // 🆕 ATTENDANCE KEY - Used to call auto-mark methods from trip screen
  final GlobalKey<DriverAttendanceWidgetState> attendanceKey = 
      GlobalKey<DriverAttendanceWidgetState>();

  Driver? _currentDriver;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDriverProfile();
  }

  Future<void> _loadDriverProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authUser = Provider.of<AuthRepository>(context, listen: false).currentUser;
      if (!authUser.isAuthenticated) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Not authenticated';
        });
        return;
      }

      // Call the driver profile API endpoint
      final response = await Provider.of<DriverProvider>(context, listen: false)
          .getDriverProfile();
      
      if (response != null) {
        setState(() {
          _currentDriver = response;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load profile';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading profile: $e';
      });
    }
  }

  Future<void> _refreshProfile() async {
    await _loadDriverProfile();
    
    // 🆕 REFRESH ATTENDANCE DATA
    attendanceKey.currentState?.loadAllData();
  }

  @override
  Widget build(BuildContext context) {
    final authUser = Provider.of<AuthRepository>(context).currentUser;

    if (!authUser.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Driver Profile'),
          backgroundColor: Colors.blue,
        ),
        body: const Center(
          child: Text('Please log in to view your profile'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Profile'),
        backgroundColor: Colors.blue,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshProfile,
            tooltip: 'Refresh Profile',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshProfile,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _refreshProfile,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _currentDriver == null
                    ? const Center(child: Text('No profile data available'))
                    : SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                          children: [
                            // Profile Header
                            _buildProfileHeader(_currentDriver!, authUser),

                            const SizedBox(height: 16.0),

                            // My Information Card
                            _buildMyInformationCard(_currentDriver!),

                  const SizedBox(height: 24.0),
                  const Divider(),
                  const SizedBox(height: 10.0),

                  // ========================================================
                  // 🆕 ATTENDANCE WIDGET - ALL 4 CARDS
                  // ========================================================
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: DriverAttendanceWidget(
                      key: attendanceKey,
                      driverId: authUser.id,
                      driverName: _currentDriver!.name,
                    ),
                  ),

                  const SizedBox(height: 24.0),
                  const Divider(),
                  const SizedBox(height: 10.0),
                  // ========================================================

                  // Profile Options
                  _buildProfileOption(
                    context,
                    icon: Icons.edit_note_rounded,
                    title: 'Edit My Details',
                    subtitle: 'Update your contact or personal info',
                    onTap: () async {
                      // Navigate to edit profile screen
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditDriverProfileScreen(driver: _currentDriver!),
                        ),
                      );
                      if (result != null && mounted) {
                        _refreshProfile();
                      }
                    },
                  ),

                  _buildProfileOption(
                    context,
                    icon: Icons.description_rounded,
                    title: 'My Documents',
                    subtitle: 'View or upload your documents',
                    onTap: () async {
                      // Navigate to documents screen
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DriverDocumentsScreen(
                            driverId: authUser.id,
                            driverName: _currentDriver!.name,
                          ),
                        ),
                      );
                      _refreshProfile();
                    },
                  ),

                  // _buildProfileOption(
                  //   context,
                  //   icon: Icons.notifications_rounded,
                  //   title: 'Notification Settings',
                  //   subtitle: 'Manage your notifications',
                  //   onTap: () {
                  //     // Navigate to notification settings
                  //     ScaffoldMessenger.of(context).showSnackBar(
                  //       const SnackBar(content: Text('Notification settings coming soon')),
                  //     );
                  //   },
                  // ),

                  // _buildProfileOption(
                  //   context,
                  //   icon: Icons.lock_rounded,
                  //   title: 'Change Password',
                  //   subtitle: 'Update your account password',
                  //   onTap: () {
                  //     // Navigate to change password screen
                  //     ScaffoldMessenger.of(context).showSnackBar(
                  //       const SnackBar(content: Text('Change password feature coming soon')),
                  //     );
                  //   },
                  // ),

                  // _buildProfileOption(
                  //   context,
                  //   icon: Icons.help_rounded,
                  //   title: 'Help & Support',
                  //   subtitle: 'Get help or contact support',
                  //   onTap: () {
                  //     // Navigate to help screen
                  //     ScaffoldMessenger.of(context).showSnackBar(
                  //       const SnackBar(content: Text('Help & support feature coming soon')),
                  //     );
                  //   },
                  // ),

                  const SizedBox(height: 16.0),
                  const Divider(),
                  const SizedBox(height: 16.0),

                  // Logout Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Logout'),
                              content: const Text('Are you sure you want to logout?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  child: const Text('Logout'),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true && mounted) {
                            await Provider.of<AuthRepository>(context, listen: false).signOut();
                            if (mounted) {
                              Navigator.of(context).pushReplacementNamed('/login');
                            }
                          }
                        },
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Logout'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24.0),
                ],
              ),
            ),
      ),
    );
  }

  // =========================================================================
  // PROFILE HEADER
  // =========================================================================
  Widget _buildProfileHeader(Driver driver, dynamic authUser) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade700, Colors.blue.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
      child: Column(
        children: [
          // Profile Photo
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 50,
              backgroundColor: Colors.white,
              backgroundImage: authUser.photoUrl != null
                  ? NetworkImage(authUser.photoUrl!)
                  : null,
              child: authUser.photoUrl == null
                  ? Text(
                      driver.name.isNotEmpty ? driver.name[0].toUpperCase() : 'D',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    )
                  : null,
            ),
          ),

          const SizedBox(height: 16),

          // Name
          Text(
            driver.name,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 4),

          // Email
          Text(
            driver.email,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),

          const SizedBox(height: 8),

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: driver.status == 'Active' ? Colors.green : Colors.orange,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Driver Profile (${driver.status})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // MY INFORMATION CARD
  // =========================================================================
  Widget _buildMyInformationCard(Driver driver) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_rounded, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'My Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            _buildInfoRow(
              Icons.phone_rounded,
              'Phone Number',
              driver.phoneNumber.isNotEmpty ? driver.phoneNumber : 'Not provided',
            ),

            const SizedBox(height: 16),

            _buildInfoRow(
              Icons.credit_card_rounded,
              'License Number',
              driver.licenseNumber ?? 'Not provided',
            ),

            const SizedBox(height: 16),

            _buildInfoRow(
              Icons.calendar_today_rounded,
              'License Expiry',
              driver.licenseExpiryDate != null
                  ? _formatDate(driver.licenseExpiryDate!)
                  : 'Not provided',
            ),

            const SizedBox(height: 16),

            _buildInfoRow(
              Icons.directions_car_rounded,
              'Assigned Vehicle',
              driver.assignedVehicleId ?? 'Not assigned',
            ),

            if (driver.address != null && driver.address!.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildInfoRow(
                Icons.location_on_rounded,
                'Address',
                driver.address!,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // PROFILE OPTION ITEM
  // =========================================================================
  Widget _buildProfileOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.blue.shade700, size: 24),
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // HELPER WIDGETS
  // =========================================================================
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

// ============================================================================
// 🆕 PUBLIC METHOD: Access attendance from trip screen
// ============================================================================
// To call auto-mark attendance from DriverLiveTripScreen:
//
// In _startTrip() method:
// final profileState = context.findAncestorStateOfType<_DriverProfileScreenState>();
// if (profileState != null) {
//   await profileState._attendanceKey.currentState?.autoMarkAttendance(_currentTripId!);
// }
//
// In _completeTrip() method:
// final profileState = context.findAncestorStateOfType<_DriverProfileScreenState>();
// if (profileState != null) {
//   await profileState._attendanceKey.currentState?.completeAttendance(_currentTripId!);
// }
// ============================================================================