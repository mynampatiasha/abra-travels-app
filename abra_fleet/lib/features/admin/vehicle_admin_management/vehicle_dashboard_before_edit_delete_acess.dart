import 'package:flutter/material.dart';

// --- UI Constants ---
const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kPrimaryDarkColor = Color(0xFF002171);
const Color kTextPrimaryColor = Color(0xFF212121);
const Color kTextSecondaryColor = Color(0xFF757575);
const Color kLightBgColor = Color(0xFFF8F9FA);

const Color kIconBlue = Color(0xFF2962FF);
const Color kIconGreen = Color(0xFF00C853);
const Color kIconRed = Color(0xFFD50000);
const Color kIconOrange = Color(0xFFFF6D00);

// --- Main Vehicle Dashboard Widget ---
class VehicleDashboard extends StatelessWidget {
  // Callback to request navigation from the parent (AdminMainShell).
  final void Function(int) onNavigateRequest;

  const VehicleDashboard({
    Key? key,
    required this.onNavigateRequest,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildStatsGrid(),
              const SizedBox(height: 32),
              _buildNavigationGrid(context),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the main header section of the dashboard.
  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vehicle Management Dashboard',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: kPrimaryColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Route: /admin/vehicle-management',
          style: TextStyle(
            fontSize: 14,
            color: kTextSecondaryColor,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  /// Builds the modern statistics cards.
  Widget _buildStatsGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 250,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        childAspectRatio: 1.1,
      ),
      itemCount: 4,
      itemBuilder: (context, index) {
        final List<Map<String, dynamic>> stats = [
          {'value': '25', 'title': 'Total Vehicles', 'subtitle': 'Fleet Status', 'icon': Icons.directions_car_filled_rounded, 'color': kIconBlue},
          {'value': '8', 'title': 'Active Trips', 'subtitle': 'In Progress', 'icon': Icons.route_rounded, 'color': kIconGreen},
          {'value': '3', 'title': 'Maintenance Due', 'subtitle': 'Pending', 'icon': Icons.build_rounded, 'color': kIconRed},
          {'value': '2', 'title': 'Compliance Alerts', 'subtitle': 'Action Required', 'icon': Icons.gavel_rounded, 'color': kIconOrange},
        ];
        return ModernStatCard(
          value: stats[index]['value'],
          title: stats[index]['title'],
          subtitle: stats[index]['subtitle'],
          icon: stats[index]['icon'],
          iconColor: stats[index]['color'],
          onTap: () {
            print('${stats[index]['title']} tapped');
          },
        );
      },
    );
  }

  /// Builds the grid of navigation cards that send requests to the main shell.
  Widget _buildNavigationGrid(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisSpacing: 25,
        crossAxisSpacing: 25,
        childAspectRatio: 2.0,
      ),
      // The indices here MUST match the screen order in admin_main_shell.dart
      itemCount: 5,
      itemBuilder: (context, index) {
        final List<Map<String, dynamic>> navItems = [
          {'icon': Icons.assignment_ind_rounded, 'title': 'Vehicle Master', 'description': 'Add, edit, and manage vehicle information, specifications, and basic details.', 'index': 11},
          {'icon': Icons.route_rounded, 'title': 'Trip Operations', 'description': 'Live trip monitoring, route tracking, real-time operations, and customer management.', 'index': 12},
          {'icon': Icons.construction_rounded, 'title': 'Maintenance Management', 'description': 'Schedule maintenance, track service history, manage repairs, and monitor vehicle health.', 'index': 13},
          {'icon': Icons.analytics_rounded, 'title': 'Reports & Analytics', 'description': 'Performance reports, analytics, business intelligence, and comprehensive fleet insights.', 'index': 14},
        ];
        return _NavCard(
          icon: navItems[index]['icon'],
          title: navItems[index]['title'],
          description: navItems[index]['description'],
          onTap: () {
            // Instead of Navigator.push, call the callback with the target index.
            final int targetIndex = navItems[index]['index'];
            onNavigateRequest(targetIndex);
          },
        );
      },
    );
  }
}

// --- Reusable Modern Stat Card Widget ---
class ModernStatCard extends StatelessWidget {
  final String value;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const ModernStatCard({Key? key, required this.value, required this.title, required this.subtitle, required this.icon, required this.iconColor, required this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16.0), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), spreadRadius: 2, blurRadius: 10, offset: const Offset(0, 5))]),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned(top: -20, right: -30, child: Container(width: 100, height: 100, decoration: BoxDecoration(color: iconColor.withOpacity(0.08), shape: BoxShape.circle))),
              Positioned(bottom: 30, right: 50, child: Container(width: 20, height: 20, decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle))),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(padding: const EdgeInsets.all(12.0), decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 24)),
                    const Spacer(),
                    Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: kTextPrimaryColor)),
                    const SizedBox(height: 4),
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kTextPrimaryColor)),
                    Text(subtitle, style: const TextStyle(fontSize: 14, color: kTextSecondaryColor)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Reusable Navigation Card Widget ---
class _NavCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _NavCard({
    Key? key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2.0,
      shadowColor: Colors.black.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.0),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: kPrimaryColor,
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: Icon(
                      icon,
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: kTextPrimaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 14,
                  color: kTextSecondaryColor,
                  height: 1.5,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}