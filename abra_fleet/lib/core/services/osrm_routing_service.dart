// lib/core/services/osrm_routing_service.dart
// OSRM (OpenStreetMap Routing Machine) integration for accurate road routing
// 100% FREE - No API key required, no limits!

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class OSRMRoutingService {
  // Public OSRM server (free, no API key needed)
  static const String _baseUrl = 'https://router.project-osrm.org';
  
  /// Get route between two points with actual road distance and duration
  /// Returns: {distance: km, duration: minutes, geometry: polyline}
  static Future<Map<String, dynamic>> getRoute({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    try {
      // OSRM uses lng,lat format (opposite of lat,lng!)
      final url = '$_baseUrl/route/v1/driving/$startLng,$startLat;$endLng,$endLat?overview=full&geometries=geojson';
      
      debugPrint('🗺️ OSRM Request: $startLat,$startLng → $endLat,$endLng');
      
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('OSRM request timeout');
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final distanceMeters = route['distance'] as num;
          final durationSeconds = route['duration'] as num;
          
          final distanceKm = distanceMeters / 1000;
          final durationMinutes = (durationSeconds / 60).ceil();
          
          debugPrint('✅ OSRM Response: ${distanceKm.toStringAsFixed(1)} km, $durationMinutes min');
          
          return {
            'distance': distanceKm,
            'duration': durationMinutes,
            'geometry': route['geometry'],
            'success': true,
          };
        } else {
          throw Exception('No route found: ${data['code']}');
        }
      } else {
        throw Exception('OSRM API error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ OSRM Error: $e');
      // Fallback to straight-line distance if OSRM fails
      return _fallbackToStraightLine(startLat, startLng, endLat, endLng);
    }
  }
  
  /// Get route for multiple waypoints (optimized order)
  /// Returns: {distance: km, duration: minutes, waypoints: [...]}
  static Future<Map<String, dynamic>> getRouteWithWaypoints({
    required double startLat,
    required double startLng,
    required List<Map<String, double>> waypoints, // [{lat, lng}, ...]
    required double endLat,
    required double endLng,
  }) async {
    try {
      // Build coordinates string: start;waypoint1;waypoint2;...;end
      final coords = StringBuffer();
      coords.write('$startLng,$startLat');
      
      for (final waypoint in waypoints) {
        coords.write(';${waypoint['lng']},${waypoint['lat']}');
      }
      
      coords.write(';$endLng,$endLat');
      
      final url = '$_baseUrl/route/v1/driving/$coords?overview=full&geometries=geojson';
      
      debugPrint('🗺️ OSRM Multi-waypoint Request: ${waypoints.length} stops');
      
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('OSRM request timeout');
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final distanceMeters = route['distance'] as num;
          final durationSeconds = route['duration'] as num;
          
          final distanceKm = distanceMeters / 1000;
          final durationMinutes = (durationSeconds / 60).ceil();
          
          debugPrint('✅ OSRM Multi-waypoint Response: ${distanceKm.toStringAsFixed(1)} km, $durationMinutes min');
          
          return {
            'distance': distanceKm,
            'duration': durationMinutes,
            'geometry': route['geometry'],
            'legs': route['legs'], // Individual segments
            'success': true,
          };
        } else {
          throw Exception('No route found: ${data['code']}');
        }
      } else {
        throw Exception('OSRM API error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ OSRM Multi-waypoint Error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
  
  /// Fallback: Calculate straight-line distance using Haversine formula
  static Map<String, dynamic> _fallbackToStraightLine(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    debugPrint('⚠️ Using fallback straight-line distance');
    
    const R = 6371; // Earth's radius in km
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
              math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
              math.sin(dLng / 2) * math.sin(dLng / 2);
              
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final distance = R * c;
    
    // Estimate duration: assume 25 km/h average speed
    final duration = ((distance / 25) * 60).ceil();
    
    return {
      'distance': distance,
      'duration': duration,
      'success': true,
      'fallback': true,
    };
  }
  
  static double _toRadians(double degrees) {
    return degrees * (math.pi / 180);
  }
}
