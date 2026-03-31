// lib/core/services/document_storage_service.dart
// HTTP-based document upload service (replaces Firebase Storage)

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DocumentStorageService {
  final ApiService _apiService = ApiService();

  /// Upload vehicle document
  Future<String> uploadVehicleDocument({
    required String vehicleId,
    required String documentType,
    File? file,
    Uint8List? bytes,
    required String fileName,
  }) async {
    try {
      final uri = Uri.parse('${_apiService.baseUrl}/api/vehicles/$vehicleId/documents');
      
      var request = http.MultipartRequest('POST', uri);
      
      // Get JWT token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      
      request.fields['documentType'] = documentType;
      
      if (bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'document',
          bytes,
          filename: fileName,
          contentType: MediaType('application', 'octet-stream'),
        ));
      } else if (file != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'document',
          file.path,
          filename: fileName,
        ));
      }
      
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        return data['url'];
      } else {
        throw Exception('Upload failed: $responseBody');
      }
    } catch (e) {
      debugPrint('Error uploading vehicle document: $e');
      rethrow;
    }
  }

  /// Upload driver document
  Future<String> uploadDriverDocument({
    required String driverId,
    required String documentType,
    File? file,
    Uint8List? bytes,
    required String fileName,
  }) async {
    try {
      final uri = Uri.parse('${_apiService.baseUrl}/api/drivers/$driverId/documents');
      
      var request = http.MultipartRequest('POST', uri);
      
      // Get JWT token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      
      request.fields['documentType'] = documentType;
      
      if (bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'document',
          bytes,
          filename: fileName,
          contentType: MediaType('application', 'octet-stream'),
        ));
      } else if (file != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'document',
          file.path,
          filename: fileName,
        ));
      }
      
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        return data['url'];
      } else {
        throw Exception('Upload failed: $responseBody');
      }
    } catch (e) {
      debugPrint('Error uploading driver document: $e');
      rethrow;
    }
  }

  /// Delete document (generic)
  Future<void> deleteDocument(String documentUrl) async {
    // Implementation depends on your backend
    // You might need to call DELETE /api/documents/:id
    debugPrint('Delete document: $documentUrl');
  }

  /// Get document metadata
  Future<Map<String, dynamic>?> getDocumentMetadata(String documentUrl) async {
    // Implementation depends on your backend
    return null;
  }
}
