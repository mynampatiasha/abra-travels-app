// File: lib/core/services/multi_trip_service.dart
// MULTI-TRIP MANAGEMENT SERVICE (Flutter)

import 'package:flutter/material.dart';
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:abra_fleet/core/services/roster_service.dart';

class MultiTripService {
  final ApiService _apiService;

  MultiTripService({required ApiService apiService}) : _apiService = apiService;

  /// ✅ Assign trip from roster (after route optimization)
  Future<Map<String, dynamic>> assignTripFromRoster({
    required String rosterId,
    required String vehicleId,
    required String driverId,
    required String customerId,
    required String customerName,
    required String customerEmail,
    required String customerPhone,
    required String pickupLocation,
    required String dropLocation,
    required String scheduledDate,
    required String startTime,
    required String endTime,
    required double distance,
    required int estimatedDuration,
    required String tripType, // 'login' or 'logout'
    required int sequence,
    String? organizationId,
    String? organizationName,
  }) async {
    try {
      debugPrint('📦 MultiTripService: Assigning trip from roster $rosterId');
      
      final response = await _apiService.post(
        '/api/trips/assign-from-roster',
        body: {
          'rosterId': rosterId,
          'vehicleId': vehicleId,
          'driverId': driverId,
          'customerId': customerId,
          'customerName': customerName,
          'customerEmail': customerEmail,
          'customerPhone': customerPhone,
          'pickupLocation': pickupLocation,
          'dropLocation': dropLocation,
          'scheduledDate': scheduledDate,
          'startTime': startTime,
          'endTime': endTime,
          'distance': distance,
          'estimatedDuration': estimatedDuration,
          'tripType': tripType,
          'sequence': sequence,
          if (organizationId != null) 'organizationId': organizationId,
          if (organizationName != null) 'organizationName': organizationName,
        },
      );
      
      if (response['success'] == true) {
        debugPrint('✅ Trip assigned: ${response['data']['tripId'] ?? response['data']['tripNumber']}');
        return response;
      } else {
        throw Exception(response['message'] ?? 'Failed to assign trip');
      }
    } catch (e) {
      debugPrint('❌ Error assigning trip: $e');
      rethrow;
    }
  }

  /// ✅ Get vehicle trips for a specific date
  Future<List<Map<String, dynamic>>> getVehicleTripsForDate(String vehicleId, String date) async {
    try {
      debugPrint('📅 MultiTripService: Getting trips for vehicle $vehicleId on $date');
      
      final response = await _apiService.get('/api/trips/vehicle/$vehicleId/date/$date');
      
      if (response['success'] == true) {
        final trips = List<Map<String, dynamic>>.from(response['data'] ?? []);
        debugPrint('✅ Found ${trips.length} trips');
        return trips;
      } else {
        throw Exception(response['message'] ?? 'Failed to get vehicle trips');
      }
    } catch (e) {
      debugPrint('❌ Error getting vehicle trips: $e');
      rethrow;
    }
  }

  /// ✅ Get today's trips for driver (used in driver dashboard)
  Future<Map<String, dynamic>> getDriverTodayTrips(String driverId) async {
    try {
      debugPrint('📱 MultiTripService: Getting today\'s trips for driver $driverId');
      
      final response = await _apiService.get('/api/trips/driver/$driverId/today');
      
      if (response['success'] == true) {
        final trips = List<Map<String, dynamic>>.from(response['data'] ?? []);
        debugPrint('✅ Found ${trips.length} trips today');
        return response;
      } else {
        throw Exception(response['message'] ?? 'Failed to get driver trips');
      }
    } catch (e) {
      debugPrint('❌ Error getting driver trips: $e');
      rethrow;
    }
  }

  /// ✅ Update trip status (assigned → started → in_progress → completed)
  Future<bool> updateTripStatus({
    required String tripId,
    required String status,
    String? notes,
  }) async {
    try {
      debugPrint('🔄 MultiTripService: Updating trip $tripId to $status');
      
      final response = await _apiService.post(
        '/api/trips/$tripId/status',
        body: {
          'status': status,
          if (notes != null) 'notes': notes,
        },
      );
      
      if (response['success'] == true) {
        debugPrint('✅ Trip status updated to $status');
        return true;
      } else {
        throw Exception(response['message'] ?? 'Failed to update trip status');
      }
    } catch (e) {
      debugPrint('❌ Error updating trip status: $e');
      rethrow;
    }
  }

  /// ✅ Share driver location (real-time tracking)
  Future<bool> shareLocation({
    required String tripId,
    required double latitude,
    required double longitude,
    double? speed,
    double? heading,
  }) async {
    try {
      final response = await _apiService.post(
        '/api/trips/$tripId/location',
        body: {
          'latitude': latitude,
          'longitude': longitude,
          if (speed != null) 'speed': speed,
          if (heading != null) 'heading': heading,
        },
      );
      
      return response['success'] == true;
    } catch (e) {
      debugPrint('❌ Error sharing location: $e');
      return false;
    }
  }

  /// ✅ Check if vehicle is available for a time slot
  Future<Map<String, dynamic>> checkVehicleAvailability({
    required String vehicleId,
    required String scheduledDate,
    required String startTime,
    required String endTime,
  }) async {
    try {
      debugPrint('🔍 MultiTripService: Checking availability for $vehicleId');
      
      final response = await _apiService.get(
        '/api/trips/check-availability',
        queryParams: {
          'vehicleId': vehicleId,
          'scheduledDate': scheduledDate,
          'startTime': startTime,
          'endTime': endTime,
        },
      );
      
      if (response['success'] == true) {
        final data = response['data'];
        debugPrint('✅ Availability check: ${data['canTakeTrip']} (${data['currentTrips']} trips)');
        return data;
      } else {
        throw Exception(response['message'] ?? 'Failed to check availability');
      }
    } catch (e) {
      debugPrint('❌ Error checking availability: $e');
      rethrow;
    }
  }

  /// ✅ Batch assign multiple trips (used in route optimization)
  Future<Map<String, dynamic>> batchAssignTrips(List<Map<String, dynamic>> trips) async {
    try {
      debugPrint('📦 MultiTripService: Batch assigning ${trips.length} trips');
      
      final response = await _apiService.post(
        '/api/trips/batch-assign',
        body: {
          'trips': trips,
        },
      );
      
      if (response['success'] == true) {
        final stats = response['stats'];
        debugPrint('✅ Batch assignment: ${stats['successful']}/${stats['total']} successful');
        return response;
      } else {
        throw Exception(response['message'] ?? 'Failed to batch assign trips');
      }
    } catch (e) {
      debugPrint('❌ Error batch assigning trips: $e');
      rethrow;
    }
  }

  /// ✅ Get trip statistics
  Future<Map<String, dynamic>> getTripStatistics({
    String? driverId,
    String? vehicleId,
    String? dateFrom,
    String? dateTo,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (driverId != null) queryParams['driverId'] = driverId;
      if (vehicleId != null) queryParams['vehicleId'] = vehicleId;
      if (dateFrom != null) queryParams['dateFrom'] = dateFrom;
      if (dateTo != null) queryParams['dateTo'] = dateTo;

      final response = await _apiService.get(
        '/api/trips/statistics',
        queryParams: queryParams,
      );
      
      if (response['success'] == true) {
        return response['data'];
      } else {
        throw Exception(response['message'] ?? 'Failed to get trip statistics');
      }
    } catch (e) {
      debugPrint('❌ Error getting trip statistics: $e');
      rethrow;
    }
  }
}

/// ✅ Trip Status Constants
class TripStatus {
  static const String assigned = 'assigned';
  static const String started = 'started';
  static const String inProgress = 'in_progress';
  static const String completed = 'completed';
  static const String cancelled = 'cancelled';
  
  static bool isActive(String status) {
    return status == assigned || status == started || status == inProgress;
  }
  
  static String getLabel(String status) {
    switch (status) {
      case assigned:
        return 'Assigned';
      case started:
        return 'Started';
      case inProgress:
        return 'In Progress';
      case completed:
        return 'Completed';
      case cancelled:
        return 'Cancelled';
      default:
        return status;
    }
  }
}

/// ✅ Extension on RosterService for Multi-Trip Integration
extension MultiTripIntegration on RosterService {
  /// Convert roster to trip assignment data
  Map<String, dynamic> rosterToTripData(Map<String, dynamic> roster, {
    required String vehicleId,
    required String driverId,
    required int sequence,
  }) {
    return {
      'rosterId': roster['_id'],
      'vehicleId': vehicleId,
      'driverId': driverId,
      'customerId': roster['customerId'],
      'customerName': roster['customerName'],
      'customerEmail': roster['customerEmail'],
      'customerPhone': roster['customerPhone'],
      'pickupLocation': roster['pickupLocation'],
      'dropLocation': roster['dropLocation'],
      'scheduledDate': roster['scheduledDate'],
      'startTime': roster['startTime'],
      'endTime': roster['endTime'],
      'distance': roster['distance'] ?? 0.0,
      'estimatedDuration': roster['estimatedDuration'] ?? 0,
      'tripType': roster['rosterType'], // 'login' or 'logout'
      'sequence': sequence,
      'organizationId': roster['organizationId'],
      'organizationName': roster['organizationName'],
    };
  }
}

/// ✅ Multi-Trip Dashboard Widget
class MultiTripDashboardCard extends StatelessWidget {
  final String vehicleId;
  final String date;
  final MultiTripService multiTripService;

  const MultiTripDashboardCard({
    super.key,
    required this.vehicleId,
    required this.date,
    required this.multiTripService,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: multiTripService.getVehicleTripsForDate(vehicleId, date),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final trips = snapshot.data ?? [];
        final activeTrips = trips.where((t) => TripStatus.isActive(t['status'])).length;

        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Today\'s Trips',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: activeTrips > 0 ? Colors.green : Colors.grey,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$activeTrips/${trips.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...trips.asMap().entries.map((entry) {
                  final trip = entry.value;
                  return _buildTripItem(trip);
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTripItem(Map<String, dynamic> trip) {
    final status = trip['status'];
    final isActive = TripStatus.isActive(status);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? Colors.blue.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? Colors.blue : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isActive ? Colors.blue : Colors.grey,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${trip['sequence']}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip['customer']['name'],
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${trip['startTime']} - ${trip['endTime']}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? Colors.green : Colors.grey,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              TripStatus.getLabel(status),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}