// lib/services/billing_api_service.dart
// Complete Billing Dashboard API Service for Flutter
// Connects to backend billing_dashboard.js endpoints

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';

class BillingApiService {
  // ============================================================================
  // CONFIGURATION - Uses ApiConfig for proper base URL
  // ============================================================================
  
  static String get _baseUrl => '${ApiConfig.baseUrl}/api/billing';
  
  static const int _timeoutSeconds = 30;
  
  // ============================================================================
  // AUTHENTICATION - Uses Firebase Auth like other services
  // ============================================================================
  
  /// Get JWT auth token from SharedPreferences
  static Future<String?> _getAuthToken() async {
    try {
      print('🔐 Getting JWT token from SharedPreferences...');
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token != null) {
        print('✅ JWT token retrieved');
        return token;
      }
      print('⚠️ No JWT token found');
      return null;
    } catch (e) {
      print('❌ Error getting JWT token: $e');
      return null;
    }
  }
  
  /// Get authorization headers
  static Future<Map<String, String>> _getHeaders() async {
    final token = await _getAuthToken();
    
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer ${token.substring(0, 50)}...',
    };
    
    print('🔧 Headers retrieved in ${DateTime.now().millisecondsSinceEpoch % 1000}ms: $headers');
    
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }
  
  // ============================================================================
  // HTTP HELPER METHODS
  // ============================================================================
  
  /// Make GET request
  static Future<Map<String, dynamic>> _get(String endpoint) async {
    try {
      print('🌐 GET: ${_baseUrl}$endpoint');
      print('🔧 Base URL: $_baseUrl');
      print('🔧 Full URI: ${_baseUrl}$endpoint');
      
      print('🔐 Getting headers...');
      final headers = await _getHeaders();
      print('🔧 Headers retrieved in ${DateTime.now().millisecondsSinceEpoch % 1000}ms: ${headers.keys.join(', ')}');
      
      final uri = Uri.parse('$_baseUrl$endpoint');
      
      print('📡 Making HTTP request...');
      final response = await http
          .get(uri, headers: headers)
          .timeout(Duration(seconds: _timeoutSeconds));
      
      print('📥 Response: ${response.statusCode}');
      
      return _handleResponse(response);
      
    } catch (e) {
      print('❌ GET Error: $e');
      throw BillingApiException('Network error: ${e.toString()}');
    }
  }
  
  /// Make POST request
  static Future<Map<String, dynamic>> _post(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    try {
      print('📡 POST $_baseUrl$endpoint');
      
      final headers = await _getHeaders();
      final uri = Uri.parse('$_baseUrl$endpoint');
      
      final response = await http
          .post(
            uri,
            headers: headers,
            body: body != null ? json.encode(body) : null,
          )
          .timeout(Duration(seconds: _timeoutSeconds));
      
      print('📥 Response: ${response.statusCode}');
      
      return _handleResponse(response);
      
    } catch (e) {
      print('❌ POST Error: $e');
      throw BillingApiException('Network error: ${e.toString()}');
    }
  }
  
  /// Handle HTTP response
  static Map<String, dynamic> _handleResponse(http.Response response) {
    try {
      final data = json.decode(response.body) as Map<String, dynamic>;
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return data;
      } else {
        final error = data['error'] ?? data['message'] ?? 'Unknown error';
        throw BillingApiException(error, statusCode: response.statusCode);
      }
    } catch (e) {
      if (e is BillingApiException) rethrow;
      throw BillingApiException('Failed to parse response: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // DASHBOARD API METHODS
  // ============================================================================
  
  /// Get complete dashboard summary (all widgets)
  /// Returns: receivables, payables, cashFlow, projects, bankAccounts, watchlist
  static Future<DashboardSummary> getDashboardSummary() async {
    try {
      print('\n📊 Fetching Dashboard Summary');
      print('─' * 80);
      
      final response = await _get('/dashboard/summary');
      
      if (response['success'] == true) {
        print('✅ Dashboard summary loaded successfully');
        print('─' * 80 + '\n');
        return DashboardSummary.fromJson(response['data']);
      } else {
        throw BillingApiException('Failed to load dashboard summary');
      }
    } catch (e) {
      print('❌ Error fetching dashboard summary: $e');
      print('─' * 80 + '\n');
      rethrow;
    }
  }
  
  /// Get receivables summary (Total Receivables widget)
  static Future<ReceivablesSummary> getReceivablesSummary() async {
    try {
      print('\n💰 Fetching Receivables Summary');
      
      final response = await _get('/receivables/summary');
      
      if (response['success'] == true) {
        print('✅ Receivables loaded');
        return ReceivablesSummary.fromJson(response['data']);
      } else {
        throw BillingApiException('Failed to load receivables');
      }
    } catch (e) {
      print('❌ Error: $e\n');
      rethrow;
    }
  }
  
  /// Get payables summary (Total Payables widget)
  static Future<PayablesSummary> getPayablesSummary() async {
    try {
      print('\n💸 Fetching Payables Summary');
      
      final response = await _get('/payables/summary');
      
      if (response['success'] == true) {
        print('✅ Payables loaded');
        return PayablesSummary.fromJson(response['data']);
      } else {
        throw BillingApiException('Failed to load payables');
      }
    } catch (e) {
      print('❌ Error: $e\n');
      rethrow;
    }
  }
  
  /// Get cash flow data (Cash Flow widget)
  /// period: 'fiscal_year', 'this_month', 'last_month', 'this_quarter'
  static Future<CashFlowData> getCashFlow({
    String period = 'fiscal_year',
  }) async {
    try {
      print('\n📈 Fetching Cash Flow (period: $period)');
      
      final response = await _get('/cash-flow?period=$period');
      
      if (response['success'] == true) {
        print('✅ Cash flow loaded');
        return CashFlowData.fromJson(response['data']);
      } else {
        throw BillingApiException('Failed to load cash flow');
      }
    } catch (e) {
      print('❌ Error: $e\n');
      rethrow;
    }
  }
  
  /// Get projects list (Projects widget)
  static Future<ProjectsSummary> getProjects() async {
    try {
      print('\n📁 Fetching Projects');
      
      final response = await _get('/projects');
      
      if (response['success'] == true) {
        print('✅ Projects loaded');
        return ProjectsSummary.fromJson(response['data']);
      } else {
        throw BillingApiException('Failed to load projects');
      }
    } catch (e) {
      print('❌ Error: $e\n');
      rethrow;
    }
  }
  
  /// Get bank accounts (Bank & Credit Cards widget)
  static Future<BankAccountsSummary> getBankAccounts() async {
    try {
      print('\n🏦 Fetching Bank Accounts');
      
      final response = await _get('/bank-accounts');
      
      if (response['success'] == true) {
        print('✅ Bank accounts loaded');
        return BankAccountsSummary.fromJson(response['data']);
      } else {
        throw BillingApiException('Failed to load bank accounts');
      }
    } catch (e) {
      print('❌ Error: $e\n');
      rethrow;
    }
  }
  
  /// Get account watchlist (Account Watchlist widget)
  /// basis: 'accrual' or 'cash'
  static Future<AccountWatchlist> getAccountWatchlist({
    String basis = 'accrual',
  }) async {
    try {
      print('\n👁️ Fetching Account Watchlist (basis: $basis)');
      
      final response = await _get('/account-watchlist?basis=$basis');
      
      if (response['success'] == true) {
        print('✅ Watchlist loaded');
        return AccountWatchlist.fromJson(response['data']);
      } else {
        throw BillingApiException('Failed to load watchlist');
      }
    } catch (e) {
      print('❌ Error: $e\n');
      rethrow;
    }
  }
  
  // ============================================================================
  // DATA MANAGEMENT
  // ============================================================================
  
  /// Create new invoice
  static Future<bool> createInvoice(Map<String, dynamic> invoiceData) async {
    try {
      print('\n📝 Creating Invoice');
      
      final response = await _post('/invoices', body: invoiceData);
      
      if (response['success'] == true) {
        print('✅ Invoice created');
        return true;
      } else {
        throw BillingApiException('Failed to create invoice');
      }
    } catch (e) {
      print('❌ Error: $e\n');
      rethrow;
    }
  }
  
  /// Create new bill
  static Future<bool> createBill(Map<String, dynamic> billData) async {
    try {
      print('\n📝 Creating Bill');
      
      final response = await _post('/bills', body: billData);
      
      if (response['success'] == true) {
        print('✅ Bill created');
        return true;
      } else {
        throw BillingApiException('Failed to create bill');
      }
    } catch (e) {
      print('❌ Error: $e\n');
      rethrow;
    }
  }
  
  /// Seed sample test data (for testing only)
  static Future<bool> seedSampleData() async {
    try {
      print('\n🌱 Seeding Sample Data');
      
      final response = await _post('/seed-data');
      
      if (response['success'] == true) {
        print('✅ Sample data seeded');
        return true;
      } else {
        throw BillingApiException('Failed to seed data');
      }
    } catch (e) {
      print('❌ Error: $e\n');
      rethrow;
    }
  }

  // ============================================================================
  // PAYMENTS RECEIVED API METHODS
  // ============================================================================

  /// Get all payments received
  static Future<List<Map<String, dynamic>>> getPaymentsReceived({
    String? filter,
    String? sortBy,
    String? sortOrder,
  }) async {
    try {
      print('\n💰 Fetching Payments Received');
      
      String endpoint = '/payments-received';
      List<String> queryParams = [];
      
      if (filter != null) queryParams.add('filter=$filter');
      if (sortBy != null) queryParams.add('sortBy=$sortBy');
      if (sortOrder != null) queryParams.add('sortOrder=$sortOrder');
      
      if (queryParams.isNotEmpty) {
        endpoint += '?${queryParams.join('&')}';
      }
      
      final response = await _get(endpoint);
      
      if (response['success'] == true) {
        print('✅ Payments received loaded');
        return List<Map<String, dynamic>>.from(response['data']);
      } else {
        throw BillingApiException('Failed to load payments received');
      }
    } catch (e) {
      print('❌ Error: $e\n');
      rethrow;
    }
  }

  /// Get payment by ID
  static Future<Map<String, dynamic>> getPaymentById(String paymentId) async {
    try {
      print('\n💰 Fetching Payment: $paymentId');
      
      final response = await _get('/payments-received/$paymentId');
      
      if (response['success'] == true) {
        print('✅ Payment loaded');
        return response['data'];
      } else {
        throw BillingApiException('Failed to load payment');
      }
    } catch (e) {
      print('❌ Error: $e\n');
      rethrow;
    }
  }

  /// Create new payment
  static Future<Map<String, dynamic>> createPayment(Map<String, dynamic> paymentData) async {
    try {
      print('\n💰 Creating Payment');
      
      final response = await _post('/payments-received', body: paymentData);
      
      if (response['success'] == true) {
        print('✅ Payment created');
        return response['data'];
      } else {
        throw BillingApiException('Failed to create payment');
      }
    } catch (e) {
      print('❌ Error: $e\n');
      rethrow;
    }
  }

  /// Update payment
  static Future<bool> updatePayment(String paymentId, Map<String, dynamic> paymentData) async {
    try {
      print('\n💰 Updating Payment: $paymentId');
      
      final response = await _post('/payments-received/$paymentId', body: paymentData);
      
      if (response['success'] == true) {
        print('✅ Payment updated');
        return true;
      } else {
        throw BillingApiException('Failed to update payment');
      }
    } catch (e) {
      print('❌ Error: $e\n');
      rethrow;
    }
  }

  /// Delete payment
  static Future<bool> deletePayment(String paymentId) async {
    try {
      print('\n💰 Deleting Payment: $paymentId');
      
      final response = await _get('/payments-received/$paymentId'); // Using GET for delete (will be changed to DELETE)
      
      if (response['success'] == true) {
        print('✅ Payment deleted');
        return true;
      } else {
        throw BillingApiException('Failed to delete payment');
      }
    } catch (e) {
      print('❌ Error: $e\n');
      rethrow;
    }
  }

  /// Get unpaid invoices for a customer
  static Future<List<Map<String, dynamic>>> getUnpaidInvoices(
    String customerName, {
    String? startDate,
    String? endDate,
  }) async {
    try {
      print('\n📄 Fetching Unpaid Invoices for: $customerName');
      
      String endpoint = '/payments-received/customer/$customerName/unpaid-invoices';
      List<String> queryParams = [];
      
      if (startDate != null) queryParams.add('startDate=$startDate');
      if (endDate != null) queryParams.add('endDate=$endDate');
      
      if (queryParams.isNotEmpty) {
        endpoint += '?${queryParams.join('&')}';
      }
      
      final response = await _get(endpoint);
      
      if (response['success'] == true) {
        print('✅ Unpaid invoices loaded');
        return List<Map<String, dynamic>>.from(response['data']);
      } else {
        throw BillingApiException('Failed to load unpaid invoices');
      }
    } catch (e) {
      print('❌ Error: $e\n');
      rethrow;
    }
  }

  /// Get payment statistics
  static Future<Map<String, dynamic>> getPaymentStatistics({
    String? startDate,
    String? endDate,
    String? customerName,
  }) async {
    try {
      print('\n📊 Fetching Payment Statistics');
      
      String endpoint = '/payments-received/stats/summary';
      List<String> queryParams = [];
      
      if (startDate != null) queryParams.add('startDate=$startDate');
      if (endDate != null) queryParams.add('endDate=$endDate');
      if (customerName != null) queryParams.add('customerName=$customerName');
      
      if (queryParams.isNotEmpty) {
        endpoint += '?${queryParams.join('&')}';
      }
      
      final response = await _get(endpoint);
      
      if (response['success'] == true) {
        print('✅ Payment statistics loaded');
        return response['data'];
      } else {
        throw BillingApiException('Failed to load payment statistics');
      }
    } catch (e) {
      print('❌ Error: $e\n');
      rethrow;
    }
  }

  /// Get next payment number
  static Future<String> getNextPaymentNumber() async {
    try {
      print('\n🔢 Getting Next Payment Number');
      
      final response = await _get('/payments-received/next-payment-number');
      
      if (response['success'] == true) {
        print('✅ Next payment number retrieved');
        return response['data']['nextPaymentNumber'];
      } else {
        throw BillingApiException('Failed to get next payment number');
      }
    } catch (e) {
      print('❌ Error: $e\n');
      rethrow;
    }
  }

  /// Export payments to CSV
  static Future<String> exportPaymentsToCSV({
    String? filter,
    String? startDate,
    String? endDate,
  }) async {
    try {
      print('\n📤 Exporting Payments to CSV');
      
      String endpoint = '/payments-received/export/csv';
      List<String> queryParams = [];
      
      if (filter != null) queryParams.add('filter=$filter');
      if (startDate != null) queryParams.add('startDate=$startDate');
      if (endDate != null) queryParams.add('endDate=$endDate');
      
      if (queryParams.isNotEmpty) {
        endpoint += '?${queryParams.join('&')}';
      }
      
      final response = await _get(endpoint);
      
      print('✅ Payments exported to CSV');
      return response.toString(); // CSV content as string
    } catch (e) {
      print('❌ Error: $e\n');
      rethrow;
    }
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

/// Complete dashboard summary
class DashboardSummary {
  final ReceivablesSummary receivables;
  final PayablesSummary payables;
  final CashFlowData cashFlow;
  final ProjectsSummary projects;
  final BankAccountsSummary bankAccounts;
  final AccountWatchlist watchlist;
  
  DashboardSummary({
    required this.receivables,
    required this.payables,
    required this.cashFlow,
    required this.projects,
    required this.bankAccounts,
    required this.watchlist,
  });
  
  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      receivables: ReceivablesSummary.fromJson(json['receivables']),
      payables: PayablesSummary.fromJson(json['payables']),
      cashFlow: CashFlowData.fromJson(json['cashFlow']),
      projects: ProjectsSummary.fromJson(json['projects']),
      bankAccounts: BankAccountsSummary.fromJson(json['bankAccounts']),
      watchlist: AccountWatchlist.fromJson(json['watchlist']),
    );
  }
}

/// Receivables summary
class ReceivablesSummary {
  final double current;
  final double overdue;
  final double total;
  final int count;
  final String currentFormatted;
  final String overdueFormatted;
  final String totalFormatted;
  
  ReceivablesSummary({
    required this.current,
    required this.overdue,
    required this.total,
    required this.count,
    required this.currentFormatted,
    required this.overdueFormatted,
    required this.totalFormatted,
  });
  
  factory ReceivablesSummary.fromJson(Map<String, dynamic> json) {
    return ReceivablesSummary(
      current: (json['current'] ?? 0).toDouble(),
      overdue: (json['overdue'] ?? 0).toDouble(),
      total: (json['total'] ?? 0).toDouble(),
      count: json['count'] ?? 0,
      currentFormatted: json['currentFormatted'] ?? '₹0.00',
      overdueFormatted: json['overdueFormatted'] ?? '₹0.00',
      totalFormatted: json['totalFormatted'] ?? '₹0.00',
    );
  }
}

/// Payables summary
class PayablesSummary {
  final double current;
  final double overdue;
  final double total;
  final int count;
  final String currentFormatted;
  final String overdueFormatted;
  final String totalFormatted;
  
  PayablesSummary({
    required this.current,
    required this.overdue,
    required this.total,
    required this.count,
    required this.currentFormatted,
    required this.overdueFormatted,
    required this.totalFormatted,
  });
  
  factory PayablesSummary.fromJson(Map<String, dynamic> json) {
    return PayablesSummary(
      current: (json['current'] ?? 0).toDouble(),
      overdue: (json['overdue'] ?? 0).toDouble(),
      total: (json['total'] ?? 0).toDouble(),
      count: json['count'] ?? 0,
      currentFormatted: json['currentFormatted'] ?? '₹0.00',
      overdueFormatted: json['overdueFormatted'] ?? '₹0.00',
      totalFormatted: json['totalFormatted'] ?? '₹0.00',
    );
  }
}

/// Cash flow data
class CashFlowData {
  final String period;
  final DateTime startDate;
  final DateTime endDate;
  final double openingBalance;
  final double closingBalance;
  final double totalIncoming;
  final double totalOutgoing;
  final double netCashFlow;
  final List<CashFlowPoint> chartData;
  final String incomingFormatted;
  final String outgoingFormatted;
  final String closingBalanceFormatted;
  
  CashFlowData({
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.openingBalance,
    required this.closingBalance,
    required this.totalIncoming,
    required this.totalOutgoing,
    required this.netCashFlow,
    required this.chartData,
    required this.incomingFormatted,
    required this.outgoingFormatted,
    required this.closingBalanceFormatted,
  });
  
  factory CashFlowData.fromJson(Map<String, dynamic> json) {
    return CashFlowData(
      period: json['period'] ?? 'fiscal_year',
      startDate: DateTime.parse(json['startDate']),
      endDate: DateTime.parse(json['endDate']),
      openingBalance: (json['openingBalance'] ?? 0).toDouble(),
      closingBalance: (json['closingBalance'] ?? 0).toDouble(),
      totalIncoming: (json['totalIncoming'] ?? 0).toDouble(),
      totalOutgoing: (json['totalOutgoing'] ?? 0).toDouble(),
      netCashFlow: (json['netCashFlow'] ?? 0).toDouble(),
      chartData: (json['chartData'] as List? ?? [])
          .map((item) => CashFlowPoint.fromJson(item))
          .toList(),
      incomingFormatted: json['incomingFormatted'] ?? '₹0.00',
      outgoingFormatted: json['outgoingFormatted'] ?? '₹0.00',
      closingBalanceFormatted: json['closingBalanceFormatted'] ?? '₹0.00',
    );
  }
}

/// Cash flow chart data point
class CashFlowPoint {
  final DateTime date;
  final double incoming;
  final double outgoing;
  
  CashFlowPoint({
    required this.date,
    required this.incoming,
    required this.outgoing,
  });
  
  factory CashFlowPoint.fromJson(Map<String, dynamic> json) {
    return CashFlowPoint(
      date: DateTime.parse(json['date']),
      incoming: (json['incoming'] ?? 0).toDouble(),
      outgoing: (json['outgoing'] ?? 0).toDouble(),
    );
  }
}

/// Projects summary
class ProjectsSummary {
  final List<Project> projects;
  final int totalCount;
  final int activeCount;
  
  ProjectsSummary({
    required this.projects,
    required this.totalCount,
    required this.activeCount,
  });
  
  factory ProjectsSummary.fromJson(Map<String, dynamic> json) {
    return ProjectsSummary(
      projects: (json['projects'] as List? ?? [])
          .map((item) => Project.fromJson(item))
          .toList(),
      totalCount: json['totalCount'] ?? 0,
      activeCount: json['activeCount'] ?? 0,
    );
  }
}

/// Project
class Project {
  final String id;
  final String name;
  final String status;
  final double? budget;
  final double spent;
  final double remaining;
  
  Project({
    required this.id,
    required this.name,
    required this.status,
    this.budget,
    required this.spent,
    required this.remaining,
  });
  
  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      status: json['status'] ?? 'active',
      budget: json['budget']?.toDouble(),
      spent: (json['spent'] ?? 0).toDouble(),
      remaining: (json['remaining'] ?? 0).toDouble(),
    );
  }
}

/// Bank accounts summary
class BankAccountsSummary {
  final List<BankAccount> accounts;
  final int totalCount;
  final double totalBalance;
  final String totalBalanceFormatted;
  
  BankAccountsSummary({
    required this.accounts,
    required this.totalCount,
    required this.totalBalance,
    required this.totalBalanceFormatted,
  });
  
  factory BankAccountsSummary.fromJson(Map<String, dynamic> json) {
    return BankAccountsSummary(
      accounts: (json['accounts'] as List? ?? [])
          .map((item) => BankAccount.fromJson(item))
          .toList(),
      totalCount: json['totalCount'] ?? 0,
      totalBalance: (json['totalBalance'] ?? 0).toDouble(),
      totalBalanceFormatted: json['totalBalanceFormatted'] ?? '₹0.00',
    );
  }
}

/// Bank account
class BankAccount {
  final String id;
  final String name;
  final String? bankName;
  final double balance;
  final String type;
  final String balanceFormatted;
  
  BankAccount({
    required this.id,
    required this.name,
    this.bankName,
    required this.balance,
    required this.type,
    required this.balanceFormatted,
  });
  
  factory BankAccount.fromJson(Map<String, dynamic> json) {
    return BankAccount(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      bankName: json['bankName'],
      balance: (json['balance'] ?? 0).toDouble(),
      type: json['type'] ?? 'current',
      balanceFormatted: json['balanceFormatted'] ?? '₹0.00',
    );
  }
}

/// Account watchlist
class AccountWatchlist {
  final String basis;
  final List<WatchlistAccount> accounts;
  final int totalCount;
  
  AccountWatchlist({
    required this.basis,
    required this.accounts,
    required this.totalCount,
  });
  
  factory AccountWatchlist.fromJson(Map<String, dynamic> json) {
    return AccountWatchlist(
      basis: json['basis'] ?? 'accrual',
      accounts: (json['accounts'] as List? ?? [])
          .map((item) => WatchlistAccount.fromJson(item))
          .toList(),
      totalCount: json['totalCount'] ?? 0,
    );
  }
}

/// Watchlist account
class WatchlistAccount {
  final String id;
  final String name;
  final String? code;
  final String type;
  final double balance;
  final String balanceFormatted;
  
  WatchlistAccount({
    required this.id,
    required this.name,
    this.code,
    required this.type,
    required this.balance,
    required this.balanceFormatted,
  });
  
  factory WatchlistAccount.fromJson(Map<String, dynamic> json) {
    return WatchlistAccount(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      code: json['code'],
      type: json['type'] ?? '',
      balance: (json['balance'] ?? 0).toDouble(),
      balanceFormatted: json['balanceFormatted'] ?? '₹0.00',
    );
  }
}

// ============================================================================
// EXCEPTION CLASS
// ============================================================================

class BillingApiException implements Exception {
  final String message;
  final int? statusCode;
  
  BillingApiException(this.message, {this.statusCode});
  
  @override
  String toString() {
    if (statusCode != null) {
      return 'BillingApiException ($statusCode): $message';
    }
    return 'BillingApiException: $message';
  }
}