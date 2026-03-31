// lib/core/services/driver_service.dart
// ✅ COMPLETE - Driver Service with Document Upload/Download/Delete

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:abra_fleet/core/services/download_helper.dart' as download_helper;

// Conditional import for File type
import 'dart:io' if (dart.library.html) 'dart:html' as html;

class DriverService {
  final ApiService _apiService = ApiService();

  // ============================================================================
  // DRIVER CRUD OPERATIONS
  // ============================================================================
  
  /// Get all drivers with optional filters
  Future<Map<String, dynamic>> getDrivers({
    int? limit,
    int? skip,
    String? search,
    String? status,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (limit != null) queryParams['limit'] = limit.toString();
      if (skip != null) queryParams['skip'] = skip.toString();
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (status != null && status.isNotEmpty) queryParams['status'] = status;
      
      final response = await _apiService.get(
        '/api/admin/drivers',
        queryParams: queryParams,
      );
      
      return response;
    } catch (e) {
      print('❌ Error getting drivers: $e');
      throw Exception('Error getting drivers: $e');
    }
  }

  /// Get all drivers (alias for getDrivers with no limit)
  Future<Map<String, dynamic>> getAllDrivers({
    String? search,
    String? status,
  }) async {
    return getDrivers(search: search, status: status);
  }

  /// Get driver statistics
  Future<Map<String, dynamic>> getDriverStats() async {
    try {
      final response = await _apiService.get('/api/admin/drivers/stats');
      return response;
    } catch (e) {
      print('❌ Error getting driver stats: $e');
      throw Exception('Error getting driver stats: $e');
    }
  }

  /// Create a new driver
  Future<Map<String, dynamic>> createDriver(Map<String, dynamic> driverData) async {
    try {
      final response = await _apiService.post(
        '/api/admin/drivers',
        body: driverData,
      );
      return response;
    } catch (e) {
      print('❌ Error creating driver: $e');
      throw Exception('Error creating driver: $e');
    }
  }

  /// Add driver (alias for createDriver)
  Future<Map<String, dynamic>> addDriver(Map<String, dynamic> driverData) async {
    return createDriver(driverData);
  }

  /// Update driver
  Future<Map<String, dynamic>> updateDriver(
    String driverId,
    Map<String, dynamic> driverData,
  ) async {
    try {
      final response = await _apiService.put(
        '/api/admin/drivers/$driverId',
        body: driverData,
      );
      return response;
    } catch (e) {
      print('❌ Error updating driver: $e');
      throw Exception('Error updating driver: $e');
    }
  }

  /// Delete driver
  Future<Map<String, dynamic>> deleteDriver(String driverId) async {
    try {
      final response = await _apiService.delete('/api/admin/drivers/$driverId');
      return response;
    } catch (e) {
      print('❌ Error deleting driver: $e');
      throw Exception('Error deleting driver: $e');
    }
  }

  /// Send password reset email
  Future<Map<String, dynamic>> sendPasswordResetEmail(String driverId) async {
    try {
      final response = await _apiService.post(
        '/api/admin/drivers/$driverId/reset-password',
        body: {},
      );
      return response;
    } catch (e) {
      print('❌ Error sending password reset email: $e');
      throw Exception('Error sending password reset email: $e');
    }
  }

  /// Bulk import drivers
  Future<Map<String, dynamic>> bulkImportDrivers(List<Map<String, dynamic>> drivers) async {
    try {
      final response = await _apiService.post(
        '/api/admin/drivers/bulk-import',
        body: {'drivers': drivers},
      );
      return response;
    } catch (e) {
      print('❌ Error bulk importing drivers: $e');
      throw Exception('Error bulk importing drivers: $e');
    }
  }

  // ============================================================================
  // VEHICLE ASSIGNMENT
  // ============================================================================
  
  /// Assign vehicle to driver
  Future<Map<String, dynamic>> assignVehicle(String driverId, String vehicleId) async {
    try {
      final response = await _apiService.post(
        '/api/admin/drivers/$driverId/assign-vehicle',
        body: {'vehicleId': vehicleId},
      );
      return response;
    } catch (e) {
      print('❌ Error assigning vehicle: $e');
      throw Exception('Error assigning vehicle: $e');
    }
  }

  /// Unassign vehicle from driver
  Future<Map<String, dynamic>> unassignVehicle(String driverId) async {
    try {
      final response = await _apiService.post(
        '/api/admin/drivers/$driverId/unassign-vehicle',
        body: {},
      );
      return response;
    } catch (e) {
      print('❌ Error unassigning vehicle: $e');
      throw Exception('Error unassigning vehicle: $e');
    }
  }

  // ============================================================================
  // DOCUMENT UPLOAD
  // ============================================================================
  
  /// Upload driver document with web and mobile support
  Future<Map<String, dynamic>> uploadDriverDocument({
    required String driverId,
    dynamic file,            // For mobile (dart:io File) or web (dart:html File)
    Uint8List? bytes,        // For web
    required String fileName,
    required String documentType,
    required String documentName,
    DateTime? expiryDate,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/admin/drivers/$driverId/documents');
      
      var request = http.MultipartRequest('POST', uri);
      
      // Add authorization header
      final token = await _apiService.getToken();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      
      // Add file based on platform
      if (kIsWeb && bytes != null) {
        // Web: Use bytes
        request.files.add(http.MultipartFile.fromBytes(
          'document',
          bytes,
          filename: fileName,
        ));
      } else if (!kIsWeb && file != null) {
        // Mobile: Use file path
        final filePath = file.path as String;
        request.files.add(await http.MultipartFile.fromPath(
          'document',
          filePath,
          filename: fileName,
        ));
      } else {
        throw Exception('No file provided for upload');
      }
      
      // Add form fields
      request.fields['documentType'] = documentType;
      request.fields['documentName'] = documentName;
      if (expiryDate != null) {
        request.fields['expiryDate'] = expiryDate.toIso8601String();
      }
      
      print('📤 Uploading document: $documentName ($documentType)');
      
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      print('📥 Upload response status: ${response.statusCode}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = json.decode(responseBody);
        print('✅ Document uploaded successfully');
        return result;
      } else {
        print('❌ Upload failed: ${response.statusCode}');
        print('Response: $responseBody');
        throw Exception('Upload failed: ${response.statusCode} - $responseBody');
      }
    } catch (e) {
      print('❌ Error uploading document: $e');
      throw Exception('Error uploading document: $e');
    }
  }

  // ============================================================================
  // DOCUMENT DOWNLOAD
  // ============================================================================
  
  /// Download driver document with web and mobile support
  Future<void> downloadDriverDocument({
    required String documentUrl,
    required String fileName,
  }) async {
    try {
      print('📥 Downloading document: $fileName');
      print('URL: $documentUrl');
      
      // Build full URL
      final fullUrl = documentUrl.startsWith('http') 
          ? documentUrl 
          : '${ApiConfig.baseUrl}$documentUrl';
      
      print('Full URL: $fullUrl');
      
      final response = await http.get(Uri.parse(fullUrl));
      
      if (response.statusCode == 200) {
        // Use platform-specific download helper
        download_helper.downloadFile(response.bodyBytes, fileName);
        print('✅ Download complete');
      } else {
        print('❌ Download failed: ${response.statusCode}');
        throw Exception('Download failed: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error downloading document: $e');
      throw Exception('Error downloading document: $e');
    }
  }

  // ============================================================================
  // DOCUMENT DELETE
  // ============================================================================
  
  /// Delete driver document
  Future<Map<String, dynamic>> deleteDriverDocument({
    required String driverId,
    required String documentId,
  }) async {
    try {
      print('🗑️ Deleting document: $documentId for driver: $driverId');
      
      final response = await _apiService.delete(
        '/api/admin/drivers/$driverId/documents/$documentId',
      );
      
      print('✅ Document deleted successfully');
      return response;
    } catch (e) {
      print('❌ Error deleting document: $e');
      throw Exception('Error deleting document: $e');
    }
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================
  
  /// Get document icon based on file extension
  static String getDocumentIcon(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return 'pdf';
      case 'jpg':
      case 'jpeg':
      case 'png':
        return 'image';
      case 'doc':
      case 'docx':
        return 'doc';
      default:
        return 'file';
    }
  }

  /// Get document status based on expiry date
  static DocumentStatus getDocumentStatus(DateTime? expiryDate) {
    if (expiryDate == null) return DocumentStatus.noExpiry;
    
    final now = DateTime.now();
    final daysUntilExpiry = expiryDate.difference(now).inDays;
    
    if (daysUntilExpiry < 0) return DocumentStatus.expired;
    if (daysUntilExpiry <= 30) return DocumentStatus.expiring;
    return DocumentStatus.valid;
  }
}

// ============================================================================
// ENUMS
// ============================================================================

enum DocumentStatus {
  valid,      // More than 30 days until expiry
  expiring,   // 1-30 days until expiry
  expired,    // Past expiry date
  noExpiry,   // No expiry date set
}
