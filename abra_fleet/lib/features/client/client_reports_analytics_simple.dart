import 'package:flutter/material.dart';

class ClientReportsAnalyticsSimple extends StatefulWidget {
  const ClientReportsAnalyticsSimple({Key? key}) : super(key: key);

  @override
  State<ClientReportsAnalyticsSimple> createState() => _ClientReportsAnalyticsSimpleState();
}

class _ClientReportsAnalyticsSimpleState extends State<ClientReportsAnalyticsSimple> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFf8fafc),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
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
                    Icons.analytics_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Reports & Analytics',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Comprehensive insights and analytics dashboard',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Coming Soon Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFe2e8f0)),
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
                  Icon(
                    Icons.construction,
                    size: 64,
                    color: const Color(0xFF64748b).withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Advanced Analytics Coming Soon',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0f172a),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We are working on comprehensive analytics and reporting features. This section will include detailed insights, charts, and performance metrics.',
                    style: TextStyle(
                      fontSize: 14,
                      color: const Color(0xFF64748b),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  
                  // Feature Preview Cards
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _buildFeatureCard(
                        icon: Icons.bar_chart,
                        title: 'Trip Analytics',
                        description: 'Detailed trip statistics and trends',
                      ),
                      _buildFeatureCard(
                        icon: Icons.pie_chart,
                        title: 'Revenue Reports',
                        description: 'Financial insights and revenue tracking',
                      ),
                      _buildFeatureCard(
                        icon: Icons.people_alt,
                        title: 'Customer Insights',
                        description: 'Customer behavior and satisfaction metrics',
                      ),
                      _buildFeatureCard(
                        icon: Icons.timeline,
                        title: 'Performance Metrics',
                        description: 'Driver and vehicle performance analysis',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFf8fafc),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 32,
            color: const Color(0xFF3b82f6),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0f172a),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748b),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}