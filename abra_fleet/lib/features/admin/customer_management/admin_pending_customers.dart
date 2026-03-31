import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
// Firebase removed - using HTTP API
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:abra_fleet/features/admin/widgets/horizontal_filter_bar.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/app/config/api_config.dart';

class AdminPendingCustomersPage extends StatefulWidget {
  const AdminPendingCustomersPage({Key? key}) : super(key: key);

  @override
  State<AdminPendingCustomersPage> createState() => _AdminPendingCustomersPageState();
}

class _AdminPendingCustomersPageState extends State<AdminPendingCustomersPage> {
  // Firebase removed
  bool _isLoading = false;
  
  // Backend API URL - Uses centralized config
  static String get _backendUrl => ApiConfig.baseUrl;
  
  // Filter state
  Map<String, dynamic> _activeFilters = {};
  List<Map<String, dynamic>> _allPendingCustomers = [];

  // Helper method to get auth token
  Future<String?> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  Future<void> _handleApprove(Map<String, dynamic> customer, String customerId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Approve Customer'),
          content: Text(
            'Are you sure you want to approve ${customer['name']}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              child: const Text('Approve'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        debugPrint('\n' + '='*80);
        debugPrint('🟢 CUSTOMER APPROVAL PROCESS STARTED');
        debugPrint('='*80);
        debugPrint('Customer Name: ${customer['name']}');
        debugPrint('Customer ID: $customerId');
        debugPrint('Customer Email: ${customer['email']}');
        debugPrint('Customer Company: ${customer['companyName'] ?? 'N/A'}');
        debugPrint('-'*80);
        
        // Step 1: Update via HTTP API
        debugPrint('Step 1: Updating customer via HTTP API...');
        await ApiService().put('/api/customers/$customerId', body: {
          'status': 'Active',
          'isPendingApproval': false,
          'approvedAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        });
        debugPrint('✅ Customer updated successfully');
        debugPrint('-'*80);
        
        // Step 2: Send email notification via backend
        debugPrint('Step 2: Sending email notification...');
        try {
          final token = await _getAuthToken();
          debugPrint('Current token: ${token != null ? "exists" : "null"}');
          
          if (token != null) {
            debugPrint('✅ Token obtained (length: ${token.length})');
            
            final requestBody = {
              'customerId': customerId,
              'customerEmail': customer['email'],
              'customerName': customer['name'],
            };
            
            debugPrint('Backend URL: $_backendUrl/api/customer-approval/approve');
            debugPrint('Request body: ${jsonEncode(requestBody)}');
            
            final response = await http.post(
              Uri.parse('$_backendUrl/api/customer-approval/approve'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(requestBody),
            );
            
            debugPrint('Backend response status: ${response.statusCode}');
            debugPrint('Backend response body: ${response.body}');
            
            if (response.statusCode == 200) {
              final responseData = jsonDecode(response.body);
              debugPrint('Response data: $responseData');
              
              if (responseData['emailSent'] == true) {
                debugPrint('✅✅✅ EMAIL SENT SUCCESSFULLY! ✅✅✅');
              } else {
                debugPrint('⚠️⚠️⚠️ EMAIL NOT SENT ⚠️⚠️⚠️');
                debugPrint('Reason: ${responseData['message'] ?? 'Unknown'}');
              }
            } else {
              debugPrint('❌ Backend returned error status: ${response.statusCode}');
              debugPrint('Error body: ${response.body}');
            }
          } else {
            debugPrint('❌ No auth token found!');
          }
        } catch (emailError) {
          debugPrint('❌ Email notification error: $emailError');
          debugPrint('Stack trace: ${StackTrace.current}');
        }
        
        debugPrint('='*80);
        debugPrint('APPROVAL PROCESS COMPLETED');
        debugPrint('='*80 + '\n');

        if (mounted) {
          _showSuccessSnackBar('${customer['name']} has been approved successfully!');
        }
      } catch (e) {
        debugPrint('\n' + '❌'*40);
        debugPrint('APPROVAL PROCESS FAILED');
        debugPrint('Error: $e');
        debugPrint('Stack trace: ${StackTrace.current}');
        debugPrint('❌'*40 + '\n');
        
        if (mounted) {
          _showErrorSnackBar('Failed to approve customer: $e');
        }
      }
    }
  }

  Future<void> _handleBulkApprove(List<Map<String, dynamic>> customers) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Approve All Customers'),
          content: Text(
            'Are you sure you want to approve all ${customers.length} pending customers?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              child: const Text('Approve All'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      
      int successCount = 0;
      int failCount = 0;
      
      try {
        debugPrint('\n' + '='*80);
        debugPrint('🟢 BULK CUSTOMER APPROVAL PROCESS STARTED');
        debugPrint('='*80);
        debugPrint('Total customers to approve: ${customers.length}');
        debugPrint('-'*80);
        
        for (var customer in customers) {
          try {
            final customerId = customer['id'] ?? customer['_id'];
            debugPrint('Approving: ${customer['name']} (ID: $customerId)');
            
            // Update via HTTP API
            await ApiService().put('/api/customers/$customerId', body: {
              'status': 'Active',
              'isPendingApproval': false,
              'approvedAt': DateTime.now().toIso8601String(),
              'updatedAt': DateTime.now().toIso8601String(),
            });
            
            // Send email notification
            try {
              final token = await _getAuthToken();
              if (token != null) {
                await http.post(
                  Uri.parse('$_backendUrl/api/customer-approval/approve'),
                  headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer $token',
                  },
                  body: jsonEncode({
                    'customerId': customerId,
                    'customerEmail': customer['email'],
                    'customerName': customer['name'],
                  }),
                );
              }
            } catch (emailError) {
              debugPrint('⚠️ Email notification failed for ${customer['name']}: $emailError');
            }
            
            successCount++;
            debugPrint('✅ Approved: ${customer['name']}');
          } catch (e) {
            failCount++;
            debugPrint('❌ Failed to approve ${customer['name']}: $e');
          }
        }
        
        debugPrint('='*80);
        debugPrint('BULK APPROVAL COMPLETED');
        debugPrint('Success: $successCount, Failed: $failCount');
        debugPrint('='*80 + '\n');

        if (mounted) {
          if (failCount == 0) {
            _showSuccessSnackBar('All $successCount customers approved successfully!');
          } else {
            _showErrorSnackBar('Approved $successCount customers, $failCount failed');
          }
        }
      } catch (e) {
        debugPrint('\n' + '❌'*40);
        debugPrint('BULK APPROVAL PROCESS FAILED');
        debugPrint('Error: $e');
        debugPrint('❌'*40 + '\n');
        
        if (mounted) {
          _showErrorSnackBar('Bulk approval failed: $e');
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _handleReject(Map<String, dynamic> customer, String customerId) async {
    final TextEditingController reasonController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Reject Customer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Are you sure you want to reject ${customer['name']}?'),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: 'Reason for rejection',
                  hintText: 'Enter reason...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
              ),
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        debugPrint('\n' + '='*80);
        debugPrint('🔴 CUSTOMER REJECTION PROCESS STARTED');
        debugPrint('='*80);
        debugPrint('Customer Name: ${customer['name']}');
        debugPrint('Customer ID: $customerId');
        debugPrint('Customer Email: ${customer['email']}');
        debugPrint('Customer Company: ${customer['companyName'] ?? 'N/A'}');
        
        final rejectionReason = reasonController.text.trim();
        debugPrint('Rejection Reason: ${rejectionReason.isEmpty ? '(No reason provided)' : rejectionReason}');
        debugPrint('-'*80);
        
        // Step 1: Update via HTTP API
        debugPrint('Step 1: Updating customer via HTTP API...');
        await ApiService().put('/api/customers/$customerId', body: {
          'status': 'Rejected',
          'isPendingApproval': false,
          'rejectionReason': rejectionReason,
          'rejectedAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        });
        debugPrint('✅ Customer updated successfully');
        debugPrint('-'*80);
        
        // Step 2: Send rejection email notification via backend
        debugPrint('Step 2: Sending rejection email notification...');
        try {
          final token = await _getAuthToken();
          debugPrint('Current token: ${token != null ? "exists" : "null"}');
          
          if (token != null) {
            debugPrint('✅ Token obtained (length: ${token.length})');
            
            final requestBody = {
              'customerId': customerId,
              'customerEmail': customer['email'],
              'customerName': customer['name'],
              'reason': rejectionReason,
            };
            
            debugPrint('Backend URL: $_backendUrl/api/customer-approval/reject');
            debugPrint('Request body: ${jsonEncode(requestBody)}');
            
            final response = await http.post(
              Uri.parse('$_backendUrl/api/customer-approval/reject'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(requestBody),
            );
            
            debugPrint('Backend response status: ${response.statusCode}');
            debugPrint('Backend response body: ${response.body}');
            
            if (response.statusCode == 200) {
              final responseData = jsonDecode(response.body);
              debugPrint('Response data: $responseData');
              
              if (responseData['emailSent'] == true) {
                debugPrint('✅✅✅ EMAIL SENT SUCCESSFULLY! ✅✅✅');
              } else {
                debugPrint('⚠️⚠️⚠️ EMAIL NOT SENT ⚠️⚠️⚠️');
                debugPrint('Reason: ${responseData['message'] ?? 'Unknown'}');
              }
            } else {
              debugPrint('❌ Backend returned error status: ${response.statusCode}');
              debugPrint('Error body: ${response.body}');
            }
          } else {
            debugPrint('❌ No auth token found!');
          }
        } catch (emailError) {
          debugPrint('❌ Email notification error: $emailError');
          debugPrint('Stack trace: ${StackTrace.current}');
        }
        
        debugPrint('='*80);
        debugPrint('REJECTION PROCESS COMPLETED');
        debugPrint('='*80 + '\n');

        if (mounted) {
          _showErrorSnackBar('${customer['name']} has been rejected.');
        }
      } catch (e) {
        debugPrint('\n' + '❌'*40);
        debugPrint('REJECTION PROCESS FAILED');
        debugPrint('Error: $e');
        debugPrint('Stack trace: ${StackTrace.current}');
        debugPrint('❌'*40 + '\n');
        
        if (mounted) {
          _showErrorSnackBar('Failed to reject customer: $e');
        }
      }
    }

    reasonController.dispose();
  }

Widget _buildPendingApprovalsTable(List<Map<String, dynamic>> pendingCustomers) {
  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFF3F4F6)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Pending Customer Approvals',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${pendingCustomers.length}',
                      style: const TextStyle(
                        color: Color(0xFFF59E0B),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              if (pendingCustomers.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: _isLoading 
                      ? null 
                      : () => _handleBulkApprove(pendingCustomers),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle, size: 16),
                  label: Text(_isLoading ? 'Approving...' : 'Approve All'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Table Content
        if (pendingCustomers.isEmpty)
          _buildEmptyState()
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 24,
              horizontalMargin: 24,
              headingRowColor: MaterialStateProperty.all(
                const Color(0xFFF8FAFC),
              ),
              columns: const [
                DataColumn(
                  label: Text(
                    'NAME',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'EMAIL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'PHONE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'COMPANY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'DEPARTMENT',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'EMPLOYEE ID',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'ROLE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'REGISTRATION DATE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'ACTIONS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
              rows: pendingCustomers.map<DataRow>((customer) {
                final customerId = customer['_id'] ?? customer['id'] ?? '';
                
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        customer['name'] ?? 'N/A',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    DataCell(
                      Text(
                        customer['email'] ?? 'N/A',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    DataCell(Text(customer['phoneNumber'] ?? customer['phone'] ?? 'N/A')),
                    DataCell(Text(customer['companyName'] ?? customer['company'] ?? 'N/A')),
                    DataCell(Text(customer['department'] ?? 'N/A')),
                    DataCell(Text(customer['employeeId'] ?? 'N/A')),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          (customer['role'] ?? 'customer').toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF3B82F6),
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      Text(_formatDate(customer['registrationDate'] ?? customer['createdAt'])),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _handleApprove(customer, customerId),
                            icon: const Icon(Icons.check, size: 14),
                            label: const Text('Approve'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => _handleReject(customer, customerId),
                            icon: const Icon(Icons.close, size: 14),
                            label: const Text('Reject'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    ),
  );
}

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.cancel, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // Load pending customers from HTTP API
  Future<List<Map<String, dynamic>>> _loadPendingCustomers() async {
    try {
      final response = await ApiService().get('/api/customers', queryParams: {
        'isPendingApproval': 'true',
      });
      final customers = List<Map<String, dynamic>>.from(response['customers'] ?? response['data'] ?? []);
      _allPendingCustomers = customers;
      return customers;
    } catch (e) {
      debugPrint('Error loading pending customers: $e');
      return [];
    }
  }
  
  // Apply local filters
  List<Map<String, dynamic>> _applyLocalFilters(List<Map<String, dynamic>> customers) {
    if (_activeFilters.isEmpty) return customers;
    
    return customers.where((customer) {
      // Date range filter
      if (_activeFilters.containsKey('startDate') && _activeFilters.containsKey('endDate')) {
        final startDate = _activeFilters['startDate'] as DateTime;
        final endDate = _activeFilters['endDate'] as DateTime;
        final customerDate = _parseDate(customer['registrationDate'] ?? customer['createdAt']);
        if (customerDate == null || 
            customerDate.isBefore(startDate) || 
            customerDate.isAfter(endDate)) {
          return false;
        }
      }
      
      // State filter
      if (_activeFilters.containsKey('state')) {
        final state = _activeFilters['state'] as String;
        if (customer['state']?.toString().toLowerCase() != state.toLowerCase()) {
          return false;
        }
      }
      
      // City filter
      if (_activeFilters.containsKey('city')) {
        final city = _activeFilters['city'] as String;
        final customerCity = customer['city']?.toString() ?? '';
        if (!customerCity.toLowerCase().contains(city.toLowerCase())) {
          return false;
        }
      }
      
      // Area filter
      if (_activeFilters.containsKey('area')) {
        final area = _activeFilters['area'] as String;
        final customerArea = customer['area']?.toString() ?? '';
        if (!customerArea.toLowerCase().contains(area.toLowerCase())) {
          return false;
        }
      }
      
      return true;
    }).toList();
  }
  
  DateTime? _parseDate(dynamic timestamp) {
    if (timestamp == null) return null;
    
    try {
      if (timestamp is String) {
        return DateTime.parse(timestamp);
      } else if (timestamp is int) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else if (timestamp is DateTime) {
        return timestamp;
      }
    } catch (e) {
      debugPrint('Error parsing date: $e');
    }
    return null;
  }
  
  void _handleFilterApplied(Map<String, dynamic> filters) {
    setState(() {
      _activeFilters = filters;
    });
  }

  void _handleFilterCleared() {
    setState(() {
      _activeFilters = {};
    });
  }

  String _formatDate(dynamic timestamp) {
  if (timestamp == null) return 'N/A';
  
  try {
    DateTime date;
    
    // Handle different timestamp formats
    if (timestamp is String) {
      date = DateTime.parse(timestamp);
    } else if (timestamp is int) {
      date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else if (timestamp is DateTime) {
      date = timestamp;
    } else {
      return 'N/A';
    }
    
    return DateFormat('MMM dd, yyyy').format(date);
  } catch (e) {
    debugPrint('Error formatting date: $e');
    return 'N/A';
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadPendingCustomers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                ],
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final pendingCustomers = snapshot.data ?? [];
          final filteredCustomers = _applyLocalFilters(pendingCustomers);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoCard(),
                const SizedBox(height: 24),
                
                // 🎯 HORIZONTAL FILTER BAR
                AlternativeFilterBar(
                  onFilterApplied: _handleFilterApplied,
                  onFilterCleared: _handleFilterCleared,
                  initialFilters: _activeFilters,
                  showDateFilter: false,
                  showDateRangeFilter: true,
                  showCountryFilter: true,
                  showStateFilter: true,
                  showCityFilter: true,
                  showAreaFilter: true,
                ),
                const SizedBox(height: 24),
                
                _buildPendingApprovalsTable(filteredCustomers),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF2563EB).withOpacity(0.3),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.info_outline,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              'These customers have registered and are waiting for admin approval to access the system.',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF1E293B),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Removed duplicate method - using the one at line 298

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Color(0xFF10B981),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Pending Approvals',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'All customer registrations have been processed.',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}