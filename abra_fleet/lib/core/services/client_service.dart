// lib/core/services/client_service.dart
// ✅ COMPLETE MERGED VERSION
// ─────────────────────────────────────────────────────────────────────────────
// Contains EVERY original method unchanged + new additions:
//   NEW → updateClientStatus()     — status-only update
//   NEW → deleteDocument()         — remove a single document
//   NEW → getClientCustomers()     — categorised customer fetch
//   EXTENDED → getAllClients()     — + country/state/city/area/department/date filters
//   EXTENDED → createClient()      — + department/location/documents (multipart)
//   EXTENDED → updateClient()      — + optional newDocuments (multipart)
//   EXTENDED → getClientsPaginated() — + location/date filters
//   KEPT AS-IS → getClientById, getClientProfile, deleteClient,
//                syncCustomerCounts, getClientStatistics
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/core/models/client_model.dart';

class ClientService {
  // ─────────────────────────────────────────────────────────
  // Singleton
  // ─────────────────────────────────────────────────────────
  static final ClientService _instance = ClientService._internal();
  factory ClientService() => _instance;
  ClientService._internal();

  // ✅ FIX: Correct base URL - /api/clients
  String get _baseUrl => '${ApiConfig.baseUrl}/api/clients';

  // ─────────────────────────────────────────────────────────
  // AUTH HELPERS
  // ─────────────────────────────────────────────────────────

  /// Get JWT token from SharedPreferences
  Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (e) {
      debugPrint('❌ Error getting JWT token: $e');
      return null;
    }
  }

  /// JSON headers (Content-Type + Authorization)
  Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${token ?? ''}',
    };
  }

  // ─────────────────────────────────────────────────────────
  // ✅ ORIGINAL + EXTENDED: getAllClients
  //    New optional params: country, state, city, area, department,
  //                         startDate, endDate
  //    All original params kept unchanged.
  // ─────────────────────────────────────────────────────────

  /// Fetch all clients from MongoDB
  ///
  /// Parameters:
  /// - [page]: Page number for pagination (default: 1)
  /// - [limit]: Number of items per page (default: 50)
  /// - [status]: Filter by status ('active', 'inactive', 'pending', or null for all)
  /// - [search]: Search query for name, email, phone, or clientId
  /// - [organization]: Filter by organization name
  /// - [country]: Filter by country  ← NEW
  /// - [state]: Filter by state      ← NEW
  /// - [city]: Filter by city        ← NEW
  /// - [area]: Filter by area        ← NEW
  /// - [department]: Filter by dept  ← NEW
  /// - [startDate]: Onboarded from   ← NEW
  /// - [endDate]: Onboarded to       ← NEW
  ///
  /// Returns: List of ClientModel objects
  Future<List<ClientModel>> getAllClients({
    int page = 1,
    int limit = 50,
    String? status,
    String? search,
    String? organization,
    // ── NEW location + date params ──
    String? country,
    String? state,
    String? city,
    String? area,
    String? department,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      debugPrint('📥 Fetching clients from MongoDB...');
      debugPrint('   - Page: $page, Limit: $limit');
      if (status       != null) debugPrint('   - Status filter: $status');
      if (search       != null) debugPrint('   - Search query: $search');
      if (organization != null) debugPrint('   - Organization filter: $organization');
      if (country      != null) debugPrint('   - Country: $country');
      if (state        != null) debugPrint('   - State: $state');
      if (city         != null) debugPrint('   - City: $city');

      // Build query parameters
      final queryParams = <String, String>{
        'page':  page.toString(),
        'limit': limit.toString(),
      };

      if (status       != null && status.isNotEmpty)       queryParams['status']       = status;
      if (search       != null && search.isNotEmpty)       queryParams['search']       = search;
      if (organization != null && organization.isNotEmpty) queryParams['organization'] = organization;
      if (country      != null && country.isNotEmpty)      queryParams['country']      = country;
      if (state        != null && state.isNotEmpty)        queryParams['state']        = state;
      if (city         != null && city.isNotEmpty)         queryParams['city']         = city;
      if (area         != null && area.isNotEmpty)         queryParams['area']         = area;
      if (department   != null && department.isNotEmpty)   queryParams['department']   = department;
      if (startDate    != null) queryParams['startDate'] = startDate.toIso8601String();
      if (endDate      != null) queryParams['endDate']   = endDate.toIso8601String();

      final uri      = Uri.parse(_baseUrl).replace(queryParameters: queryParams);
      final headers  = await _getHeaders();
      final response = await http.get(uri, headers: headers);

      debugPrint('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final List<dynamic> clientsJson = data['data'];
          final clients = clientsJson
              .map((j) => ClientModel.fromJson(j as Map<String, dynamic>))
              .toList();

          debugPrint('✅ Loaded ${clients.length} clients from MongoDB');

          // Log pagination info if available
          if (data['pagination'] != null) {
            debugPrint('📊 Pagination: ${data['pagination']}');
          }

          return clients;
        } else {
          debugPrint('⚠️ Unexpected response format: $data');
          return [];
        }
      } else if (response.statusCode == 401) {
        debugPrint('❌ Unauthorized: Invalid or expired token');
        throw Exception('Unauthorized: Please login again');
      } else {
        debugPrint('❌ Failed to fetch clients: ${response.statusCode}');
        debugPrint('   Response: ${response.body}');
        throw Exception('Failed to fetch clients: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error fetching clients: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────
  // ✅ ORIGINAL: getClientById
  // ─────────────────────────────────────────────────────────

  /// Get a single client by ID
  ///
  /// Parameters:
  /// - [clientId]: The client ID (MongoDB _id or custom clientId)
  ///
  /// Returns: ClientModel object or null if not found
  Future<ClientModel?> getClientById(String clientId) async {
    try {
      debugPrint('📥 Fetching client by ID: $clientId');

      final uri      = Uri.parse('$_baseUrl/$clientId');
      final headers  = await _getHeaders();
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final client = ClientModel.fromJson(data['data'] as Map<String, dynamic>);
          debugPrint('✅ Client found: ${client.name}');
          return client;
        }
      } else if (response.statusCode == 404) {
        debugPrint('⚠️ Client not found: $clientId');
        return null;
      } else {
        debugPrint('❌ Failed to fetch client: ${response.statusCode}');
        throw Exception('Failed to fetch client: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error fetching client: $e');
      rethrow;
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────
  // ✅ ORIGINAL: getClientProfile (JWT email-based)
  // ─────────────────────────────────────────────────────────

  /// FIX: Get client profile using JWT email (email-based - avoids ID mismatch)
  ///
  /// Returns: ClientModel object or null if not found
  Future<ClientModel?> getClientProfile() async {
    try {
      debugPrint('📥 Fetching client profile via JWT email...');

      final uri      = Uri.parse('$_baseUrl/profile');
      final headers  = await _getHeaders();
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final client = ClientModel.fromJson(data['data'] as Map<String, dynamic>);
          debugPrint('✅ Client profile found: ${client.name}');
          return client;
        }
      } else if (response.statusCode == 404) {
        debugPrint('⚠️ Client profile not found');
        return null;
      } else {
        debugPrint('❌ Failed to fetch client profile: ${response.statusCode}');
        throw Exception('Failed to fetch client profile: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error fetching client profile: $e');
      rethrow;
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────
  // ✅ ORIGINAL + EXTENDED: createClient
  //    New optional params: department, country, state, city, area, documents
  //    All original params (branch, gstNumber, panNumber, companyName,
  //    organizationName) kept unchanged.
  // ─────────────────────────────────────────────────────────

  /// Create a new client
  ///
  /// Parameters:
  /// - [name]: Client company name
  /// - [email]: Client email (unique)
  /// - [password]: Client password
  /// - [phone]: Client phone number
  /// - [address]: Client address
  /// - [contactPerson]: Contact person name
  /// - [branch]: Branch name (optional)
  /// - [gstNumber]: GST number (optional)
  /// - [panNumber]: PAN number (optional)
  /// - [companyName]: Company name (optional, defaults to name)
  /// - [organizationName]: Organization name (optional, defaults to name)
  /// - [department]: Department            ← NEW
  /// - [country]: Country                  ← NEW
  /// - [state]: State                      ← NEW
  /// - [city]: City                        ← NEW
  /// - [area]: Area / locality             ← NEW
  /// - [documents]: File attachments       ← NEW
  ///
  /// Returns: Created ClientModel object
  Future<ClientModel> createClient({
    required String name,
    required String email,
    required String password,
    required String phone,
    required String address,
    required String contactPerson,
    // ── original optional ──
    String? branch,
    String? gstNumber,
    String? panNumber,
    String? companyName,
    String? organizationName,
    // ── NEW optional ──
    String? department,
    String? country,
    String? state,
    String? city,
    String? area,
    List<ClientUploadDocument>? documents,
  }) async {
    try {
      debugPrint('➕ Creating new client: $name');

      // No documents → original JSON POST behaviour
      if (documents == null || documents.isEmpty) {
        final uri     = Uri.parse(_baseUrl);
        final headers = await _getHeaders();

        final body = json.encode({
          'name':             name,
          'email':            email,
          'password':         password,
          'phone':            phone,
          'phoneNumber':      phone,
          'address':          address,
          'contactPerson':    contactPerson,
          'branch':           branch,
          'gstNumber':        gstNumber,
          'panNumber':        panNumber,
          'companyName':      companyName      ?? name,
          'organizationName': organizationName ?? name,
          'department':       department,
          'country':          country,
          'state':            state,
          'city':             city,
          'area':             area,
          'role':             'client',
          'status':           'active',
        });

        final response = await http.post(uri, headers: headers, body: body);
        return _parseClientResponse(response, 'create');

      } else {
        // With documents → multipart POST
        final token   = await _getToken();
        final request = http.MultipartRequest('POST', Uri.parse(_baseUrl))
          ..headers['Authorization'] = 'Bearer ${token ?? ''}'
          ..fields['name']             = name
          ..fields['email']            = email
          ..fields['password']         = password
          ..fields['phoneNumber']      = phone
          ..fields['address']          = address
          ..fields['contactPerson']    = contactPerson
          ..fields['branch']           = branch           ?? ''
          ..fields['department']       = department        ?? ''
          ..fields['gstNumber']        = gstNumber         ?? ''
          ..fields['panNumber']        = panNumber         ?? ''
          ..fields['companyName']      = companyName       ?? name
          ..fields['organizationName'] = organizationName  ?? name
          ..fields['country']          = country           ?? ''
          ..fields['state']            = state             ?? ''
          ..fields['city']             = city              ?? ''
          ..fields['area']             = area              ?? '';

        final meta = documents.map((d) => {
          'documentName': d.documentName,
          'documentType': d.documentType,
          'expiryDate':   d.expiryDate ?? '',
        }).toList();
        request.fields['documentMetadata'] = json.encode(meta);

        for (final doc in documents) {
          if (doc.bytes != null) {
            request.files.add(http.MultipartFile.fromBytes(
              'documents', doc.bytes!,
              filename:    doc.filename,
              contentType: MediaType.parse(doc.mimeType ?? 'application/octet-stream'),
            ));
          } else if (doc.path != null) {
            request.files.add(await http.MultipartFile.fromPath(
              'documents', doc.path!,
              contentType: MediaType.parse(doc.mimeType ?? 'application/octet-stream'),
            ));
          }
        }

        final streamed = await request.send();
        final response = await http.Response.fromStream(streamed);
        return _parseClientResponse(response, 'create');
      }
    } catch (e) {
      debugPrint('❌ Error creating client: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────
  // ✅ ORIGINAL + EXTENDED: updateClient
  //    New optional param: newDocuments (multipart upload)
  //    Original signature (clientId, updateData) kept unchanged.
  // ─────────────────────────────────────────────────────────

  /// Update an existing client
  ///
  /// Parameters:
  /// - [clientId]: The client ID to update
  /// - [updateData]: Map of fields to update
  /// - [newDocuments]: New files to append to existing documents ← NEW
  ///
  /// Returns: Updated ClientModel object
  Future<ClientModel> updateClient(
    String clientId,
    Map<String, dynamic> updateData, {
    List<ClientUploadDocument>? newDocuments,
  }) async {
    try {
      debugPrint('🔄 Updating client: $clientId');
      debugPrint('   Update data: $updateData');

      // No new documents → original JSON PUT behaviour
      if (newDocuments == null || newDocuments.isEmpty) {
        final uri      = Uri.parse('$_baseUrl/$clientId');
        final headers  = await _getHeaders();
        final response = await http.put(uri, headers: headers, body: json.encode(updateData));
        return _parseClientResponse(response, 'update');

      } else {
        // With new documents → multipart PUT
        final token   = await _getToken();
        final request = http.MultipartRequest('PUT', Uri.parse('$_baseUrl/$clientId'))
          ..headers['Authorization'] = 'Bearer ${token ?? ''}';

        updateData.forEach((k, v) {
          if (v != null) request.fields[k] = v.toString();
        });

        final meta = newDocuments.map((d) => {
          'documentName': d.documentName,
          'documentType': d.documentType,
          'expiryDate':   d.expiryDate ?? '',
        }).toList();
        request.fields['documentMetadata'] = json.encode(meta);

        for (final doc in newDocuments) {
          if (doc.bytes != null) {
            request.files.add(http.MultipartFile.fromBytes(
              'documents', doc.bytes!,
              filename:    doc.filename,
              contentType: MediaType.parse(doc.mimeType ?? 'application/octet-stream'),
            ));
          } else if (doc.path != null) {
            request.files.add(await http.MultipartFile.fromPath(
              'documents', doc.path!,
              contentType: MediaType.parse(doc.mimeType ?? 'application/octet-stream'),
            ));
          }
        }

        final streamed = await request.send();
        final response = await http.Response.fromStream(streamed);
        return _parseClientResponse(response, 'update');
      }
    } catch (e) {
      debugPrint('❌ Error updating client: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────
  // ✅ ORIGINAL: deleteClient
  // ─────────────────────────────────────────────────────────

  /// Delete a client
  ///
  /// Parameters:
  /// - [clientId]: The client ID to delete
  ///
  /// Returns: true if successful
  Future<bool> deleteClient(String clientId) async {
    try {
      debugPrint('🗑️ Deleting client: $clientId');

      final uri      = Uri.parse('$_baseUrl/$clientId');
      final headers  = await _getHeaders();
      final response = await http.delete(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          debugPrint('✅ Client deleted successfully');
          return true;
        } else {
          throw Exception(data['message'] ?? 'Failed to delete client');
        }
      } else if (response.statusCode == 404) {
        debugPrint('❌ Client not found: $clientId');
        throw Exception('Client not found');
      } else {
        final error = json.decode(response.body);
        debugPrint('❌ Failed to delete client: ${error['message']}');
        throw Exception(error['message'] ?? 'Failed to delete client');
      }
    } catch (e) {
      debugPrint('❌ Error deleting client: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────
  // ✅ NEW: updateClientStatus — status-only update
  // ─────────────────────────────────────────────────────────

  /// Update ONLY the status of a client without modifying other fields
  ///
  /// Parameters:
  /// - [clientId]: The client ID
  /// - [status]: One of 'active' | 'inactive' | 'suspended'
  Future<void> updateClientStatus(String clientId, String status) async {
    try {
      debugPrint('🔄 Updating client status: $clientId → $status');

      final uri      = Uri.parse('$_baseUrl/$clientId/status');
      final headers  = await _getHeaders();
      final response = await http.put(
        uri,
        headers: headers,
        body: json.encode({ 'status': status }),
      );

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        debugPrint('✅ Status updated to $status');
      } else {
        throw Exception(data['message'] ?? 'Failed to update status');
      }
    } catch (e) {
      debugPrint('❌ Error updating client status: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────
  // ✅ NEW: deleteDocument
  // ─────────────────────────────────────────────────────────

  /// Delete a specific document attached to a client
  ///
  /// Parameters:
  /// - [clientId]: The client ID
  /// - [docId]: The document ID to remove
  Future<void> deleteDocument(String clientId, String docId) async {
    try {
      debugPrint('🗑️ Deleting document $docId from client $clientId');

      final uri      = Uri.parse('$_baseUrl/$clientId/documents/$docId');
      final headers  = await _getHeaders();
      final response = await http.delete(uri, headers: headers);

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        debugPrint('✅ Document deleted successfully');
      } else {
        throw Exception(data['message'] ?? 'Failed to delete document');
      }
    } catch (e) {
      debugPrint('❌ Error deleting document: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────
  // ✅ NEW: getClientCustomers — categorised customer list
  // ─────────────────────────────────────────────────────────

  /// Get all customers for a specific client, organised by assignment category
  ///
  /// Returns: Map with keys: customers, totalCount, categories, clientInfo
  Future<Map<String, dynamic>> getClientCustomers(String clientId) async {
    try {
      debugPrint('🔍 Loading customers for client: $clientId');

      final uri      = Uri.parse('$_baseUrl/$clientId/customers');
      final headers  = await _getHeaders();
      final response = await http.get(uri, headers: headers);

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        debugPrint('✅ Loaded ${data['totalCount']} customers');
        return data as Map<String, dynamic>;
      }
      throw Exception(data['message'] ?? 'Failed to fetch customers');
    } catch (e) {
      debugPrint('❌ Error fetching client customers: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────
  // ✅ ORIGINAL: syncCustomerCounts
  // ─────────────────────────────────────────────────────────

  /// Sync customer counts for all clients.
  /// This triggers a backend process to update totalCustomers for each client.
  ///
  /// Returns: Map with sync results
  Future<Map<String, dynamic>> syncCustomerCounts({
    bool forceRefresh = false,
  }) async {
    try {
      debugPrint('🔄 Syncing customer counts...');

      // ✅ FIX: Correct URL for sync endpoint
      final uri      = Uri.parse('${ApiConfig.baseUrl}/api/clients/sync-customer-counts');
      final headers  = await _getHeaders();
      final response = await http.post(
        uri,
        headers: headers,
        body: json.encode({ 'forceRefresh': forceRefresh }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          debugPrint('✅ Customer counts synced successfully');
          debugPrint('   Total customers: ${data['totalCustomers']}');
          debugPrint('   Clients updated: ${data['updated']}');
          return data as Map<String, dynamic>;
        } else {
          throw Exception(data['message'] ?? 'Failed to sync customer counts');
        }
      } else {
        debugPrint('❌ Failed to sync customer counts: ${response.statusCode}');
        throw Exception('Failed to sync customer counts');
      }
    } catch (e) {
      debugPrint('❌ Error syncing customer counts: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────
  // ✅ ORIGINAL: getClientStatistics
  // ─────────────────────────────────────────────────────────

  /// Get client statistics summary
  ///
  /// Returns: Map with client statistics (total, active, inactive, pending …)
  Future<Map<String, dynamic>> getClientStatistics() async {
    try {
      debugPrint('📊 Fetching client statistics...');

      final uri      = Uri.parse(_baseUrl);
      final headers  = await _getHeaders();
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['summary'] != null) {
          debugPrint('✅ Client statistics fetched');
          return data['summary'] as Map<String, dynamic>;
        } else {
          return { 'total': 0, 'active': 0, 'inactive': 0, 'pending': 0 };
        }
      } else {
        debugPrint('❌ Failed to fetch statistics: ${response.statusCode}');
        return { 'total': 0, 'active': 0, 'inactive': 0, 'pending': 0 };
      }
    } catch (e) {
      debugPrint('❌ Error fetching statistics: $e');
      return { 'total': 0, 'active': 0, 'inactive': 0, 'pending': 0 };
    }
  }

  // ─────────────────────────────────────────────────────────
  // ✅ ORIGINAL + EXTENDED: getClientsPaginated
  //    New optional params: country, state, city, area,
  //                         department, startDate, endDate
  //    Original params (page, limit, status, search) unchanged.
  // ─────────────────────────────────────────────────────────

  /// Get clients with pagination info
  ///
  /// Returns: Map with clients list and pagination data
  Future<Map<String, dynamic>> getClientsPaginated({
    int page  = 1,
    int limit = 50,
    String? status,
    String? search,
    // ── NEW location + date params ──
    String? country,
    String? state,
    String? city,
    String? area,
    String? department,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      debugPrint('📥 Fetching clients with pagination...');

      final queryParams = <String, String>{
        'page':  page.toString(),
        'limit': limit.toString(),
      };

      if (status     != null && status.isNotEmpty)     queryParams['status']     = status;
      if (search     != null && search.isNotEmpty)     queryParams['search']     = search;
      if (country    != null && country.isNotEmpty)    queryParams['country']    = country;
      if (state      != null && state.isNotEmpty)      queryParams['state']      = state;
      if (city       != null && city.isNotEmpty)       queryParams['city']       = city;
      if (area       != null && area.isNotEmpty)       queryParams['area']       = area;
      if (department != null && department.isNotEmpty) queryParams['department'] = department;
      if (startDate  != null) queryParams['startDate'] = startDate.toIso8601String();
      if (endDate    != null) queryParams['endDate']   = endDate.toIso8601String();

      final uri      = Uri.parse(_baseUrl).replace(queryParameters: queryParams);
      final headers  = await _getHeaders();
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List<dynamic> clientsJson = data['data'] ?? [];
          final clients = clientsJson
              .map((j) => ClientModel.fromJson(j as Map<String, dynamic>))
              .toList();
          return {
            'clients':    clients,
            'pagination': data['pagination'] ?? {},
            'summary':    data['summary']    ?? {},
          };
        }
      }

      return {
        'clients':    <ClientModel>[],
        'pagination': {},
        'summary':    {},
      };
    } catch (e) {
      debugPrint('❌ Error fetching paginated clients: $e');
      return {
        'clients':    <ClientModel>[],
        'pagination': {},
        'summary':    {},
      };
    }
  }

  // ─────────────────────────────────────────────────────────
  // PRIVATE HELPER
  // ─────────────────────────────────────────────────────────

  /// Parse a create/update response into a ClientModel, or throw a clean error.
  ClientModel _parseClientResponse(http.Response response, String operation) {
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = json.decode(response.body);
      if (data['success'] == true && data['data'] != null) {
        debugPrint('✅ Client $operation successful');
        return ClientModel.fromJson(data['data'] as Map<String, dynamic>);
      }
      throw Exception(data['message'] ?? 'Failed to $operation client');
    } else if (response.statusCode == 409) {
      throw Exception('A client with this email already exists');
    } else if (response.statusCode == 404) {
      throw Exception('Client not found');
    } else {
      final error = json.decode(response.body);
      debugPrint('❌ Failed to $operation client: ${error['message']}');
      throw Exception(error['message'] ?? 'Failed to $operation client');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ClientUploadDocument
// Model used when passing file bytes / paths into createClient or updateClient
// ─────────────────────────────────────────────────────────────────────────────

class ClientUploadDocument {
  final String     documentName;
  final String     documentType;
  final String?    expiryDate;
  final String     filename;
  final String?    path;
  final Uint8List? bytes;
  final String?    mimeType;

  const ClientUploadDocument({
    required this.documentName,
    required this.documentType,
    this.expiryDate,
    required this.filename,
    this.path,
    this.bytes,
    this.mimeType,
  });
}