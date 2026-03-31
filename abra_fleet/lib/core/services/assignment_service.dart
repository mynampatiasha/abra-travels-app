// File: lib/core/services/assignment_service.dart
// Assignment Service - Handles roster and vehicle assignments

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:abra_fleet/core/services/api_service.dart';

class AssignmentService {
  final ApiService _apiService;

  AssignmentService({required ApiService apiService}) : _apiService = apiService;

  // Getter for apiService to maintain compatibility
  ApiService get apiService => _apiService;

  /// Debug method to test endpoint connectivity
  Future<Map<String, dynamic>> debugTestEndpoint() async {
    try {
      debugPrint('\n' + '🧪' * 80);
      debugPrint('🧪 ASSIGNMENT SERVICE DEBUG TEST');
      debugPrint('🧪' * 80);
      
      final baseUrl = _apiService.baseUrl;
      debugPrint('🌐 Base URL: $baseUrl');
      
      // Test 1: Health check
      debugPrint('\n📡 Test 1: Health Check');
      try {
        final healthResponse = await _apiService.get('/health');
        debugPrint('✅ Health check successful: ${healthResponse['message']}');
      } catch (e) {
        debugPrint('❌ Health check failed: $e');
      }
      
      // Test 2: Assignment endpoint availability
      debugPrint('\n📡 Test 2: Assignment Endpoint Test');
      try {
        final testUrl = '$baseUrl/api/assignment/assign-group';
        debugPrint('🎯 Testing URL: $testUrl');
        
        final testResponse = await http.head(Uri.parse(testUrl));
        debugPrint('📊 HEAD response: ${testResponse.statusCode}');
        
        if (testResponse.statusCode == 404) {
          debugPrint('❌ ENDPOINT NOT FOUND - This is the root cause!');
        } else {
          debugPrint('✅ Endpoint exists (status: ${testResponse.statusCode})');
        }
      } catch (e) {
        debugPrint('❌ Endpoint test failed: $e');
      }
      
      // Test 3: Actual POST request
      debugPrint('\n📡 Test 3: POST Request Test');
      try {
        final result = await _apiService.post('/api/assignment/assign-group', body: {
          'rosterIds': ['507f1f77bcf86cd799439011'],
          'vehicleId': '507f1f77bcf86cd799439013'
        });
        debugPrint('✅ POST request successful: ${result['message']}');
        return result;
      } catch (e) {
        debugPrint('❌ POST request failed: $e');
        if (e.toString().contains('404')) {
          debugPrint('❌ 404 ERROR CONFIRMED - Endpoint does not exist');
        } else if (e.toString().contains('401')) {
          debugPrint('✅ 401 ERROR - Endpoint exists, authentication issue');
        }
        return {'success': false, 'error': e.toString()};
      }
      
    } catch (e) {
      debugPrint('❌ Debug test failed: $e');
      return {'success': false, 'error': e.toString()};
    } finally {
      debugPrint('🧪' * 80 + '\n');
    }
  }

  /// Get pending rosters with auto-grouping
  Future<Map<String, dynamic>> getPendingRosters() async {
    try {
      debugPrint('🔍 AssignmentService: Getting pending rosters...');
      
      final result = await _apiService.get('/api/assignment/pending-rosters');
      
      debugPrint('✅ AssignmentService: Got ${result['data']?['totalPending'] ?? 0} pending rosters');
      return result;
      
    } catch (e) {
      debugPrint('❌ AssignmentService: Failed to get pending rosters: $e');
      rethrow;
    }
  }

  /// Find matching vehicles for roster(s)
  Future<Map<String, dynamic>> findMatchingVehicles({
    List<String>? rosterIds,
    String? rosterId,
  }) async {
    try {
      debugPrint('\n' + '🔍' * 80);
      debugPrint('🔍 AssignmentService: Finding matching vehicles...');
      debugPrint('🔍' * 80);
      debugPrint('📋 Roster IDs: ${rosterIds ?? (rosterId != null ? [rosterId] : [])}');
      debugPrint('📊 Count: ${rosterIds?.length ?? 1}');
      
      final body = <String, dynamic>{};
      if (rosterIds != null) {
        body['rosterIds'] = rosterIds;
      }
      if (rosterId != null) {
        body['rosterId'] = rosterId;
      }
      
      debugPrint('\n📤 Making API request to /api/assignment/find-matches');
      debugPrint('📦 Request body: $body');
      
      final result = await _apiService.post('/api/assignment/find-matches', body: body);
      
      debugPrint('\n📥 API RESPONSE RECEIVED:');
      debugPrint('   Response Type: ${result.runtimeType}');
      debugPrint('   Response Keys: ${result.keys.toList()}');
      debugPrint('   Success: ${result['success']}');
      
      if (result['data'] != null) {
        final data = result['data'];
        debugPrint('\n📊 VEHICLE DATA STRUCTURE:');
        debugPrint('   Data Keys: ${data.keys.toList()}');
        debugPrint('   Best Match: ${data['bestMatch'] != null ? 'Found' : 'None'}');
        debugPrint('   Alternatives: ${data['alternatives']?.length ?? 0}');
        debugPrint('   All Options: ${data['allOptions']?.length ?? 0}');
        debugPrint('   Stats: ${data['stats']}');
        
        if (data['allOptions'] != null && data['allOptions'].isNotEmpty) {
          debugPrint('\n🚗 SAMPLE VEHICLE STRUCTURE:');
          final sampleVehicle = data['allOptions'][0];
          debugPrint('   Sample Keys: ${sampleVehicle.keys.toList()}');
          debugPrint('   Vehicle ID: ${sampleVehicle['vehicleId']}');
          debugPrint('   Vehicle Reg: ${sampleVehicle['vehicleReg']}');
          debugPrint('   Total Score: ${sampleVehicle['totalScore']}');
        }
      } else {
        debugPrint('   ⚠️ No data field in response');
      }
      
      debugPrint('\n✅ AssignmentService: Found ${result['data']?['allOptions']?.length ?? 0} vehicle options');
      debugPrint('🔍' * 80 + '\n');
      
      return result;
      
    } catch (e, stackTrace) {
      debugPrint('\n❌ AssignmentService: Failed to find matching vehicles');
      debugPrint('❌' * 80);
      debugPrint('❌ Error Type: ${e.runtimeType}');
      debugPrint('❌ Error Message: $e');
      debugPrint('❌ Stack Trace: $stackTrace');
      debugPrint('❌ Request: rosterIds=$rosterIds, rosterId=$rosterId');
      debugPrint('❌' * 80);
      rethrow;
    }
  }

  /// Assign single roster to vehicle
  Future<Map<String, dynamic>> assignRoster({
    required String rosterId,
    required String vehicleId,
  }) async {
    try {
      debugPrint('🚗 AssignmentService: Assigning single roster...');
      debugPrint('   Roster ID: $rosterId');
      debugPrint('   Vehicle ID: $vehicleId');
      
      final body = {
        'rosterId': rosterId,
        'vehicleId': vehicleId,
      };
      
      final result = await _apiService.post('/api/assignment/assign', body: body);
      
      debugPrint('✅ AssignmentService: Single roster assigned successfully');
      return result;
      
    } catch (e) {
      debugPrint('❌ AssignmentService: Failed to assign single roster: $e');
      rethrow;
    }
  }

  /// Assign group of rosters to vehicle
  Future<Map<String, dynamic>> assignGroup({
    required List<String> rosterIds,
    required String vehicleId,
  }) async {
    try {
      debugPrint('🚌 AssignmentService: Assigning group...');
      debugPrint('   Roster IDs: $rosterIds');
      debugPrint('   Vehicle ID: $vehicleId');
      
      // Debug: Check the base URL being used
      final baseUrl = _apiService.baseUrl;
      debugPrint('🌐 Base URL: $baseUrl');
      debugPrint('🎯 Full URL: $baseUrl/api/assignment/assign-group');
      
      // Debug: Validate inputs
      debugPrint('\n🔍 INPUT VALIDATION:');
      debugPrint('   Roster IDs count: ${rosterIds.length}');
      debugPrint('   Vehicle ID: "$vehicleId"');
      debugPrint('   Vehicle ID length: ${vehicleId.length}');
      debugPrint('   Vehicle ID is ObjectId: ${RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(vehicleId)}');
      
      for (int i = 0; i < rosterIds.length; i++) {
        final rosterId = rosterIds[i];
        debugPrint('   Roster ${i + 1}: "$rosterId" (length: ${rosterId.length})');
        debugPrint('   Roster ${i + 1} is ObjectId: ${RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(rosterId)}');
      }
      
      final body = {
        'rosterIds': rosterIds,
        'vehicleId': vehicleId,
      };
      
      debugPrint('\n📤 Making POST request to /api/assignment/assign-group');
      debugPrint('📦 Request body: ${jsonEncode(body)}');
      debugPrint('🌐 Full request URL: $baseUrl/api/assignment/assign-group');
      
      // Debug: Test endpoint availability first
      debugPrint('\n🧪 TESTING ENDPOINT AVAILABILITY...');
      try {
        final testUri = Uri.parse('$baseUrl/api/assignment/assign-group');
        debugPrint('   Testing: $testUri');
        
        final headResponse = await http.head(testUri).timeout(const Duration(seconds: 5));
        debugPrint('   HEAD response: ${headResponse.statusCode}');
        
        if (headResponse.statusCode == 404) {
          debugPrint('   ❌ ENDPOINT NOT FOUND (404) - This is the root cause!');
          debugPrint('   ❌ The /api/assignment/assign-group endpoint does not exist on the server');
          debugPrint('   ❌ Check if assignment_routes.js is properly loaded in the backend');
        } else if (headResponse.statusCode == 405) {
          debugPrint('   ⚠️ Method not allowed (405) - Endpoint exists but HEAD not supported');
          debugPrint('   ✅ This is normal, endpoint likely exists');
        } else {
          debugPrint('   ✅ Endpoint appears to be available (status: ${headResponse.statusCode})');
        }
      } catch (testError) {
        debugPrint('   ❌ Endpoint test failed: $testError');
      }
      
      debugPrint('\n📡 MAKING ACTUAL POST REQUEST...');
      final result = await _apiService.post('/api/assignment/assign-group', body: body);
      
      debugPrint('✅ AssignmentService: Group assigned successfully');
      debugPrint('📋 Result: ${result['message']}');
      return result;
      
    } catch (e) {
      debugPrint('❌ AssignmentService: Failed to assign group: $e');
      debugPrint('❌ Error type: ${e.runtimeType}');
      debugPrint('❌ Error details: ${e.toString()}');
      
      // Debug: Analyze the error
      if (e.toString().contains('404')) {
        debugPrint('❌ 404 ERROR ANALYSIS:');
        debugPrint('   - The endpoint /api/assignment/assign-group does not exist');
        debugPrint('   - Backend server is running but route is not registered');
        debugPrint('   - Check if assignment_routes.js is loaded in index.js');
        debugPrint('   - Verify the route definition in assignment_routes.js');
      } else if (e.toString().contains('Connection refused')) {
        debugPrint('❌ CONNECTION ERROR ANALYSIS:');
        debugPrint('   - Backend server is not running');
        debugPrint('   - Wrong port or host configuration');
        debugPrint('   - Network connectivity issue');
      }
      
      rethrow;
    }
  }

  /// Get available vehicles
  Future<Map<String, dynamic>> getAvailableVehicles() async {
    try {
      debugPrint('🚗 AssignmentService: Getting available vehicles...');
      
      final result = await _apiService.get('/api/assignment/available-vehicles');
      
      debugPrint('✅ AssignmentService: Got ${result['data']?['stats']?['available'] ?? 0} available vehicles');
      return result;
      
    } catch (e) {
      debugPrint('❌ AssignmentService: Failed to get available vehicles: $e');
      rethrow;
    }
  }

  /// Unassign roster from vehicle
  Future<Map<String, dynamic>> unassignRoster({
    required String rosterId,
    String? reason,
  }) async {
    try {
      debugPrint('❌ AssignmentService: Unassigning roster...');
      debugPrint('   Roster ID: $rosterId');
      debugPrint('   Reason: ${reason ?? 'Not specified'}');
      
      final body = {
        'rosterId': rosterId,
        if (reason != null) 'reason': reason,
      };
      
      final result = await _apiService.post('/api/assignment/unassign', body: body);
      
      debugPrint('✅ AssignmentService: Roster unassigned successfully');
      return result;
      
    } catch (e) {
      debugPrint('❌ AssignmentService: Failed to unassign roster: $e');
      rethrow;
    }
  }
}