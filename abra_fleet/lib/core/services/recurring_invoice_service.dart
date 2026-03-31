// ============================================================================
// RECURRING INVOICE SERVICE - API Communication Layer
// ============================================================================
// File: lib/services/recurring_invoice_service.dart
// Handles all recurring invoice operations
// ============================================================================

import 'dart:convert';
import 'package:abra_fleet/core/services/api_service.dart';

class RecurringInvoiceService {
  // Use ApiService singleton for all API calls
  static final ApiService _api = ApiService();
  
  // Base endpoint for recurring invoices
  static const String _baseEndpoint = '/api/invoices/recurring';
  
  // ============================================================================
  // RECURRING INVOICE API METHODS
  // ============================================================================
  
  /// Get all recurring invoice profiles with optional filters
  static Future<RecurringInvoiceListResponse> getRecurringInvoices({
    String? status,
    String? customerId,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      // Build query parameters
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };
      
      if (status != null) queryParams['status'] = status;
      if (customerId != null) queryParams['customerId'] = customerId;
      
      print('📤 GET: $_baseEndpoint with filters: $queryParams');
      
      final data = await _api.get(_baseEndpoint, queryParams: queryParams);
      
      print('✅ Recurring invoices fetched: ${data['data'].length}');
      
      return RecurringInvoiceListResponse.fromJson(data);
    } catch (e) {
      print('❌ Error fetching recurring invoices: $e');
      rethrow;
    }
  }
  
  /// Get single recurring invoice profile by ID
  static Future<RecurringInvoice> getRecurringInvoice(String profileId) async {
    try {
      print('📤 GET: $_baseEndpoint/$profileId');
      
      final data = await _api.get('$_baseEndpoint/$profileId');
      
      print('✅ Recurring invoice fetched: ${data['data']['profileName']}');
      
      return RecurringInvoice.fromJson(data['data']);
    } catch (e) {
      print('❌ Error fetching recurring invoice: $e');
      rethrow;
    }
  }
  
  /// Create new recurring invoice profile
  static Future<RecurringInvoice> createRecurringInvoice(Map<String, dynamic> profileData) async {
    try {
      print('📤 POST: $_baseEndpoint');
      print('📦 Data: ${json.encode(profileData)}');
      
      final data = await _api.post(_baseEndpoint, body: profileData);
      
      print('✅ Recurring invoice created: ${data['data']['profileName']}');
      
      return RecurringInvoice.fromJson(data['data']);
    } catch (e) {
      print('❌ Error creating recurring invoice: $e');
      rethrow;
    }
  }
  
  /// Update existing recurring invoice profile
  static Future<RecurringInvoice> updateRecurringInvoice(
    String profileId,
    Map<String, dynamic> profileData,
  ) async {
    try {
      print('📤 PUT: $_baseEndpoint/$profileId');
      print('📦 Data: ${json.encode(profileData)}');
      
      final data = await _api.put('$_baseEndpoint/$profileId', body: profileData);
      
      print('✅ Recurring invoice updated: ${data['data']['profileName']}');
      
      return RecurringInvoice.fromJson(data['data']);
    } catch (e) {
      print('❌ Error updating recurring invoice: $e');
      rethrow;
    }
  }
  
  /// Pause recurring invoice profile
  static Future<RecurringInvoice> pauseRecurringInvoice(String profileId) async {
    try {
      print('📤 POST: $_baseEndpoint/$profileId/pause');
      
      final data = await _api.post('$_baseEndpoint/$profileId/pause');
      
      print('✅ Recurring invoice paused: ${data['data']['profileName']}');
      
      return RecurringInvoice.fromJson(data['data']);
    } catch (e) {
      print('❌ Error pausing recurring invoice: $e');
      rethrow;
    }
  }
  
  /// Resume recurring invoice profile
  static Future<RecurringInvoice> resumeRecurringInvoice(String profileId) async {
    try {
      print('📤 POST: $_baseEndpoint/$profileId/resume');
      
      final data = await _api.post('$_baseEndpoint/$profileId/resume');
      
      print('✅ Recurring invoice resumed: ${data['data']['profileName']}');
      
      return RecurringInvoice.fromJson(data['data']);
    } catch (e) {
      print('❌ Error resuming recurring invoice: $e');
      rethrow;
    }
  }
  
  /// Stop recurring invoice profile permanently
  static Future<RecurringInvoice> stopRecurringInvoice(String profileId) async {
    try {
      print('📤 POST: $_baseEndpoint/$profileId/stop');
      
      final data = await _api.post('$_baseEndpoint/$profileId/stop');
      
      print('✅ Recurring invoice stopped: ${data['data']['profileName']}');
      
      return RecurringInvoice.fromJson(data['data']);
    } catch (e) {
      print('❌ Error stopping recurring invoice: $e');
      rethrow;
    }
  }
  
  /// Manually generate invoice from recurring profile
  static Future<ManualInvoiceResponse> generateManualInvoice(String profileId) async {
    try {
      print('📤 POST: $_baseEndpoint/$profileId/generate');
      
      final data = await _api.post('$_baseEndpoint/$profileId/generate');
      
      print('✅ Manual invoice generated from profile');
      
      return ManualInvoiceResponse.fromJson(data['data']);
    } catch (e) {
      print('❌ Error generating manual invoice: $e');
      rethrow;
    }
  }
  
  /// Get child invoices generated from a recurring profile
  static Future<ChildInvoicesResponse> getChildInvoices(String profileId) async {
    try {
      print('📤 GET: $_baseEndpoint/$profileId/child-invoices');
      
      final data = await _api.get('$_baseEndpoint/$profileId/child-invoices');
      
      print('✅ Child invoices fetched: ${data['data']['invoices'].length}');
      
      return ChildInvoicesResponse.fromJson(data['data']);
    } catch (e) {
      print('❌ Error fetching child invoices: $e');
      rethrow;
    }
  }
  
  /// Delete recurring invoice profile
  static Future<void> deleteRecurringInvoice(String profileId) async {
    try {
      print('📤 DELETE: $_baseEndpoint/$profileId');
      
      await _api.delete('$_baseEndpoint/$profileId');
      
      print('✅ Recurring invoice deleted');
    } catch (e) {
      print('❌ Error deleting recurring invoice: $e');
      rethrow;
    }
  }
  
  /// Get recurring invoice statistics
  static Future<RecurringInvoiceStats> getStats() async {
    try {
      print('📤 GET: $_baseEndpoint/stats');
      
      final data = await _api.get('$_baseEndpoint/stats');
      
      print('✅ Recurring invoice stats fetched');
      
      return RecurringInvoiceStats.fromJson(data['data']);
    } catch (e) {
      print('❌ Error fetching recurring invoice stats: $e');
      rethrow;
    }
  }
}

// ============================================================================
// DATA MODELS FOR RECURRING INVOICES
// ============================================================================

/// Recurring Invoice Profile Model
class RecurringInvoice {
  final String id;
  final String profileName;
  final String customerId;
  final String customerName;
  final String customerEmail;
  final String customerPhone;
  // Recurrence Settings
  final int repeatEvery;
  final String repeatUnit; // 'day', 'week', 'month', 'year'
  final DateTime startDate;
  final DateTime? endDate;
  final int? maxOccurrences;
  final DateTime nextInvoiceDate;
  
  // Invoice Template
  final String? orderNumber;
  final String terms;
  final String? salesperson;
  final String? subject;
  final List<RecurringInvoiceItem> items;
  final String? customerNotes;
  final String? termsAndConditions;
  
  // Tax Settings
  final double tdsRate;
  final double tcsRate;
  final double gstRate;
  
  // Automation Settings
  final String invoiceCreationMode; // 'draft' or 'auto_send'
  final bool autoApplyPayments;
  final bool autoApplyCreditNotes;
  final bool suspendOnFailure;
  final bool disableAutoSaveCard;
  
  // Calculated Amounts (from template)
  final double subTotal;
  final double totalAmount;
  
  // Status & Tracking
  final String status; // 'ACTIVE', 'PAUSED', 'STOPPED'
  final List<String> childInvoiceIds;
  final DateTime? lastGeneratedDate;
  final int totalInvoicesGenerated;
  
  // Audit
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;

  RecurringInvoice({
    required this.id,
    required this.profileName,
    required this.customerId,
    required this.customerName,
    required this.customerEmail,
     required this.customerPhone,
    required this.repeatEvery,
    required this.repeatUnit,
    required this.startDate,
    this.endDate,
    this.maxOccurrences,
    required this.nextInvoiceDate,
    this.orderNumber,
    required this.terms,
    this.salesperson,
    this.subject,
    required this.items,
    this.customerNotes,
    this.termsAndConditions,
    required this.tdsRate,
    required this.tcsRate,
    required this.gstRate,
    required this.invoiceCreationMode,
    required this.autoApplyPayments,
    required this.autoApplyCreditNotes,
    required this.suspendOnFailure,
    required this.disableAutoSaveCard,
    required this.subTotal,
    required this.totalAmount,
    required this.status,
    required this.childInvoiceIds,
    this.lastGeneratedDate,
    required this.totalInvoicesGenerated,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
  });

  factory RecurringInvoice.fromJson(Map<String, dynamic> json) {
    return RecurringInvoice(
      id: json['_id'] ?? json['id'],
      profileName: json['profileName'],
      customerId: json['customerId'],
      customerName: json['customerName'],
      customerEmail: json['customerEmail'],
      customerPhone: json['customerPhone'] ?? '',
      repeatEvery: json['repeatEvery'],
      repeatUnit: json['repeatUnit'],
      startDate: DateTime.parse(json['startDate']),
      endDate: json['endDate'] != null ? DateTime.parse(json['endDate']) : null,
      maxOccurrences: json['maxOccurrences'],
      nextInvoiceDate: DateTime.parse(json['nextInvoiceDate']),
      orderNumber: json['orderNumber'],
      terms: json['terms'],
      salesperson: json['salesperson'],
      subject: json['subject'],
      items: (json['items'] as List)
          .map((item) => RecurringInvoiceItem.fromJson(item))
          .toList(),
      customerNotes: json['customerNotes'],
      termsAndConditions: json['termsAndConditions'],
      tdsRate: (json['tdsRate'] ?? 0).toDouble(),
      tcsRate: (json['tcsRate'] ?? 0).toDouble(),
      gstRate: (json['gstRate'] ?? 18).toDouble(),
      invoiceCreationMode: json['invoiceCreationMode'] ?? 'draft',
      autoApplyPayments: json['autoApplyPayments'] ?? false,
      autoApplyCreditNotes: json['autoApplyCreditNotes'] ?? false,
      suspendOnFailure: json['suspendOnFailure'] ?? false,
      disableAutoSaveCard: json['disableAutoSaveCard'] ?? true,
      subTotal: (json['subTotal'] ?? 0).toDouble(),
      totalAmount: (json['totalAmount'] ?? 0).toDouble(),
      status: json['status'] ?? 'ACTIVE',
      childInvoiceIds: List<String>.from(json['childInvoices'] ?? []),
      lastGeneratedDate: json['lastGeneratedDate'] != null
          ? DateTime.parse(json['lastGeneratedDate'])
          : null,
      totalInvoicesGenerated: json['totalInvoicesGenerated'] ?? 0,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      createdBy: json['createdBy'],
    );
  }
}

/// Recurring Invoice Item Model
class RecurringInvoiceItem {
  final String itemDetails;
  final double quantity;
  final double rate;
  final double discount;
  final String discountType;
  final double amount;

  RecurringInvoiceItem({
    required this.itemDetails,
    required this.quantity,
    required this.rate,
    required this.discount,
    required this.discountType,
    required this.amount,
  });

  factory RecurringInvoiceItem.fromJson(Map<String, dynamic> json) {
    return RecurringInvoiceItem(
      itemDetails: json['itemDetails'] ?? '',
      quantity: (json['quantity'] ?? 0).toDouble(),
      rate: (json['rate'] ?? 0).toDouble(),
      discount: (json['discount'] ?? 0).toDouble(),
      discountType: json['discountType'] ?? 'percentage',
      amount: (json['amount'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'itemDetails': itemDetails,
      'quantity': quantity,
      'rate': rate,
      'discount': discount,
      'discountType': discountType,
      'amount': amount,
    };
  }
}

/// Recurring Invoice List Response
class RecurringInvoiceListResponse {
  final List<RecurringInvoice> recurringInvoices;
  final Pagination pagination;

  RecurringInvoiceListResponse({
    required this.recurringInvoices,
    required this.pagination,
  });

  factory RecurringInvoiceListResponse.fromJson(Map<String, dynamic> json) {
    return RecurringInvoiceListResponse(
      recurringInvoices: (json['data'] as List)
          .map((profile) => RecurringInvoice.fromJson(profile))
          .toList(),
      pagination: Pagination.fromJson(json['pagination']),
    );
  }
}

/// Pagination Model
class Pagination {
  final int total;
  final int page;
  final int limit;
  final int pages;

  Pagination({
    required this.total,
    required this.page,
    required this.limit,
    required this.pages,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(
      total: json['total'],
      page: json['page'],
      limit: json['limit'],
      pages: json['pages'],
    );
  }
}

/// Manual Invoice Generation Response
class ManualInvoiceResponse {
  final String invoiceId;
  final String invoiceNumber;
  final String message;

  ManualInvoiceResponse({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.message,
  });

  factory ManualInvoiceResponse.fromJson(Map<String, dynamic> json) {
    return ManualInvoiceResponse(
      invoiceId: json['invoiceId'],
      invoiceNumber: json['invoiceNumber'],
      message: json['message'] ?? 'Invoice generated successfully',
    );
  }
}

/// Child Invoices Response
class ChildInvoicesResponse {
  final List<ChildInvoice> invoices;
  final int total;

  ChildInvoicesResponse({
    required this.invoices,
    required this.total,
  });

  factory ChildInvoicesResponse.fromJson(Map<String, dynamic> json) {
    return ChildInvoicesResponse(
      invoices: (json['invoices'] as List)
          .map((invoice) => ChildInvoice.fromJson(invoice))
          .toList(),
      total: json['total'] ?? 0,
    );
  }
}

/// Child Invoice Model (simplified)
class ChildInvoice {
  final String id;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final DateTime dueDate;
  final double totalAmount;
  final String status;
  final DateTime createdAt;

  ChildInvoice({
    required this.id,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.dueDate,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
  });

  factory ChildInvoice.fromJson(Map<String, dynamic> json) {
    return ChildInvoice(
      id: json['_id'] ?? json['id'],
      invoiceNumber: json['invoiceNumber'],
      invoiceDate: DateTime.parse(json['invoiceDate']),
      dueDate: DateTime.parse(json['dueDate']),
      totalAmount: (json['totalAmount'] ?? 0).toDouble(),
      status: json['status'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

/// Recurring Invoice Statistics
class RecurringInvoiceStats {
  final int totalProfiles;
  final int activeProfiles;
  final int pausedProfiles;
  final int stoppedProfiles;
  final int totalInvoicesGenerated;
  final double totalRecurringRevenue;

  RecurringInvoiceStats({
    required this.totalProfiles,
    required this.activeProfiles,
    required this.pausedProfiles,
    required this.stoppedProfiles,
    required this.totalInvoicesGenerated,
    required this.totalRecurringRevenue,
  });

  factory RecurringInvoiceStats.fromJson(Map<String, dynamic> json) {
    return RecurringInvoiceStats(
      totalProfiles: json['totalProfiles'] ?? 0,
      activeProfiles: json['activeProfiles'] ?? 0,
      pausedProfiles: json['pausedProfiles'] ?? 0,
      stoppedProfiles: json['stoppedProfiles'] ?? 0,
      totalInvoicesGenerated: json['totalInvoicesGenerated'] ?? 0,
      totalRecurringRevenue: (json['totalRecurringRevenue'] ?? 0).toDouble(),
    );
  }
}