import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';

class RecentActivity {
  final String id;
  final String type;
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final String icon;
  final String color;
  final String priority;
  final String timeAgo;

  RecentActivity({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.icon,
    required this.color,
    required this.priority,
    required this.timeAgo,
  });

  factory RecentActivity.fromJson(Map<String, dynamic> json) {
    return RecentActivity(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      title: json['title'] ?? '',
      subtitle: json['subtitle'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
      icon: json['icon'] ?? 'info',
      color: json['color'] ?? 'blue',
      priority: json['priority'] ?? 'medium',
      timeAgo: json['timeAgo'] ?? '',
    );
  }
}

class RecentActivitiesService {
  static Future<List<RecentActivity>> fetchRecentActivities() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/recent-activities'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final activitiesList = data['activities'] as List<dynamic>;
          return activitiesList
              .map((activity) => RecentActivity.fromJson(activity))
              .toList();
        }
      }

      // Return empty list if API fails
      return [];
    } catch (e) {
      print('Error fetching recent activities: $e');
      return [];
    }
  }
}