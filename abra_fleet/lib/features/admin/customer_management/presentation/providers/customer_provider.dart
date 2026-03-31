// lib/features/admin/customer_management/presentation/providers/customer_provider.dart
// JWT + MongoDB - NO Firestore

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:abra_fleet/core/exceptions/auth_exception.dart';
import 'package:abra_fleet/features/admin/customer_management/domain/entities/customer_entity.dart';
import 'package:abra_fleet/core/services/customer_service.dart';
import 'package:abra_fleet/core/models/customer_model.dart';
import 'package:http/http.dart' as http;
import 'package:abra_fleet/app/config/api_config.dart';

enum DataState { initial, loading, loaded, error }

class CustomerProvider extends ChangeNotifier {
  static final String _baseUrl = ApiConfig.baseUrl;
  final CustomerService _customerService = CustomerService();
  
  List<CustomerEntity> _customers = [];
  DataState _state = DataState.initial;
  String? _errorMessage;
  List<String> _companies = [];

  List<CustomerEntity> get customers => _customers;
  DataState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == DataState.loading;
  List<String> get companies => _companies;

  Future<String?> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  Future<String?> _getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString != null) {
      final userData = jsonDecode(userDataString);
      return userData['id'];
    }
    return null;
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getAuthToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> initialize() async {
    await _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCompanies = prefs.getStringList('custom_companies') ?? [];
      _companies = [
        'All Organizations',
        'Tech Corp',
        'Finance Group',
        'Healthcare Solutions',
        'Retail Chain',
        'Manufacturing Ltd',
        ...savedCompanies,
      ];
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading companies: $e');
    }
  }

  Future<bool> addCompany(String companyName) async {
    try {
      if (_companies.contains(companyName)) return false;
      final defaultCount = 6;
      if (_companies.length > defaultCount) {
        _companies.insert(defaultCount, companyName);
      } else {
        _companies.add(companyName);
      }
      final prefs = await SharedPreferences.getInstance();
      final customCompanies = _companies.sublist(defaultCount);
      await prefs.setStringList('custom_companies', customCompanies);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error adding company: $e');
      return false;
    }
  }

  Future<bool> removeCompany(String companyName) async {
    try {
      _companies.remove(companyName);
      final prefs = await SharedPreferences.getInstance();
      final defaultCount = 6;
      final customCompanies = _companies.length > defaultCount
          ? _companies.sublist(defaultCount)
          : <String>[];
      await prefs.setStringList('custom_companies', customCompanies);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error removing company: $e');
      return false;
    }
  }

  String _generateEmployeeId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 10000).toString().padLeft(4, '0');
    return 'EMP$random';
  }

  Future<void> fetchCustomers({
    String? status,
    String? search,
    String? organization,
    String? department,
  }) async {
    try {
      print('\n🔍 FETCHING CUSTOMERS VIA CUSTOMER SERVICE');
      print('─' * 80);
      
      _state = DataState.loading;
      _errorMessage = null;
      notifyListeners();

      // Use the new CustomerService instead of direct API calls
      final customerModels = await _customerService.getAllCustomers(
        status: status,
        search: search,
        organization: organization,
        department: department,
        limit: 100,
      );

      print('✅ Received ${customerModels.length} customers from service');

      // Convert CustomerModel to CustomerEntity for compatibility
      _customers.clear();
      for (var customerModel in customerModels) {
        try {
          final customerEntity = CustomerEntity(
            id: customerModel.id ?? '',
            name: customerModel.name ?? 'Unknown',
            email: customerModel.email ?? '',
            phoneNumber: customerModel.phone ?? '',
            companyName: customerModel.companyName ?? '',
            department: customerModel.department ?? '',
            branch: customerModel.branch ?? '',
            employeeId: customerModel.employeeId ?? '',
            status: customerModel.status ?? 'active',
            role: customerModel.role ?? 'customer',
            createdAt: customerModel.createdAt,
            updatedAt: customerModel.updatedAt,
          );
          _customers.add(customerEntity);
        } catch (e) {
          debugPrint('❌ Error converting customer model to entity: $e');
        }
      }

      _state = DataState.loaded;
      print('✅ Successfully loaded ${_customers.length} customers in provider');
      notifyListeners();
    } catch (e) {
      print('❌ Error fetching customers: $e');
      _errorMessage = 'Error: ${e.toString()}';
      _state = DataState.error;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> createCustomer({
    required String name,
    required String email,
    required String phone,
    String? company,
    String? address,
    String? department,
    String? branch,
    String? employeeId,
    required String password,
  }) async {
    _state = DataState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      print('\n➕ CREATING CUSTOMER VIA CUSTOMER SERVICE');
      print('─' * 80);

      // Use the new CustomerService instead of direct API calls
      final customerModel = await _customerService.createCustomer(
        name: name.trim(),
        email: email.trim(),
        phone: phone.trim(),
        companyName: company?.trim(),
        department: department?.trim(),
        branch: branch?.trim(),
        employeeId: employeeId?.trim() ?? _generateEmployeeId(),
        password: password.trim(),
        status: 'active',
      );

      print('✅ Customer created successfully: ${customerModel.name}');

      // Refresh the customer list
      await fetchCustomers();
      _state = DataState.loaded;
      notifyListeners();
      
      return {
        'success': true,
        'customerName': customerModel.name ?? name.trim(),
        'companyName': customerModel.companyName ?? company?.trim() ?? 'N/A',
      };
    } on AuthException catch (e) {
      print('❌ Auth error creating customer: ${e.message}');
      _errorMessage = e.getUserMessage();
      _state = DataState.error;
      notifyListeners();
      return {'success': false, 'error': _errorMessage};
    } catch (e) {
      print('❌ Error creating customer: $e');
      _errorMessage = 'Failed to create customer: $e';
      _state = DataState.error;
      notifyListeners();
      return {'success': false, 'error': _errorMessage};
    }
  }

  Future<bool> updateCustomer(CustomerEntity customer) async {
    _state = DataState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      print('\n✏️ UPDATING CUSTOMER VIA CUSTOMER SERVICE');
      print('─' * 80);

      // Use the new CustomerService instead of direct API calls
      final updatedCustomer = await _customerService.updateCustomer(
        customerId: customer.id,
        name: customer.name,
        email: customer.email,
        phone: customer.phoneNumber,
        companyName: customer.companyName,
        department: customer.department,
        branch: customer.branch,
        employeeId: customer.employeeId,
        status: customer.status,
      );

      print('✅ Customer updated successfully: ${updatedCustomer.name}');

      // Update the local list
      final index = _customers.indexWhere((c) => c.id == customer.id);
      if (index != -1) {
        _customers[index] = CustomerEntity(
          id: updatedCustomer.id ?? customer.id,
          name: updatedCustomer.name ?? customer.name,
          email: updatedCustomer.email ?? customer.email,
          phoneNumber: updatedCustomer.phone ?? customer.phoneNumber,
          companyName: updatedCustomer.companyName ?? customer.companyName,
          department: updatedCustomer.department ?? customer.department,
          branch: updatedCustomer.branch ?? customer.branch,
          employeeId: updatedCustomer.employeeId ?? customer.employeeId,
          status: updatedCustomer.status ?? customer.status,
          role: updatedCustomer.role ?? customer.role,
          createdAt: updatedCustomer.createdAt ?? customer.createdAt,
          updatedAt: updatedCustomer.updatedAt ?? customer.updatedAt,
        );
      }

      _state = DataState.loaded;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      print('❌ Auth error updating customer: ${e.message}');
      _errorMessage = e.getUserMessage();
      _state = DataState.error;
      notifyListeners();
      return false;
    } catch (e) {
      print('❌ Error updating customer: $e');
      _errorMessage = 'Failed to update customer: $e';
      _state = DataState.error;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteCustomer(String customerId) async {
    _state = DataState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      print('\n🗑️ DELETING CUSTOMER VIA CUSTOMER SERVICE');
      print('─' * 80);

      // Use the new CustomerService instead of direct API calls
      final success = await _customerService.deleteCustomer(customerId);

      if (success) {
        print('✅ Customer deleted successfully');
        
        // Remove from local list
        _customers.removeWhere((c) => c.id == customerId);
        _state = DataState.loaded;
        notifyListeners();
        return true;
      } else {
        throw Exception('Failed to delete customer');
      }
    } on AuthException catch (e) {
      print('❌ Auth error deleting customer: ${e.message}');
      _errorMessage = e.getUserMessage();
      _state = DataState.error;
      notifyListeners();
      return false;
    } catch (e) {
      print('❌ Error deleting customer: $e');
      _errorMessage = 'Failed to delete customer: $e';
      _state = DataState.error;
      notifyListeners();
      return false;
    }
  }

  CustomerEntity? getCustomerFromListById(String id) {
    try {
      return _customers.firstWhere((customer) => customer.id == id);
    } catch (e) {
      return null;
    }
  }

  // TODO: Implement password update in CustomerService
  Future<bool> updateCustomerPassword(String customerId, String newPassword) async {
    try {
      if (newPassword.trim().isEmpty || newPassword.trim().length < 6) {
        _errorMessage = 'Password must be at least 6 characters';
        return false;
      }

      print('\n🔑 UPDATING CUSTOMER PASSWORD - NOT IMPLEMENTED YET');
      print('─' * 80);

      // TODO: Add updateCustomerPassword method to CustomerService
      // final success = await _customerService.updateCustomerPassword(
      //   customerId: customerId,
      //   newPassword: newPassword.trim(),
      // );

      _errorMessage = 'Password update not implemented yet';
      return false;

      // if (success) {
      //   print('✅ Customer password updated successfully');
      //   return true;
      // } else {
      //   throw Exception('Failed to update password');
      // }
    } on AuthException catch (e) {
      print('❌ Auth error updating password: ${e.message}');
      _errorMessage = e.getUserMessage();
      return false;
    } catch (e) {
      print('❌ Error updating password: $e');
      _errorMessage = 'Failed to update password: $e';
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    if (_state == DataState.error) {
      _state = DataState.loaded;
      notifyListeners();
    }
  }

  Future<void> refreshCustomers() async {
    await fetchCustomers();
  }

  Future<bool> addCustomer(Map<String, dynamic> customerData) async {
    try {
      final userId = await _getUserId();
      final headers = await _getHeaders();

      final response = await http.post(
        Uri.parse('$_baseUrl/api/admin/customers/unified'),
        headers: headers,
        body: json.encode({
          ...customerData,
          'employeeId': customerData['employeeId'] ?? _generateEmployeeId(),
          'role': 'customer',
          'status': 'Active',
          'createdBy': userId,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _customers.add(CustomerEntity.fromMap(data['data']));
          notifyListeners();
          return true;
        }
      }
      return false;
    } catch (e) {
      _errorMessage = 'Failed to add customer: $e';
      _state = DataState.error;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateCustomerFromId(String customerId, Map<String, dynamic> customerData) async {
    try {
      final existing = getCustomerFromListById(customerId);
      if (existing == null) {
        _errorMessage = 'Customer not found';
        return false;
      }

      final updated = existing.copyWith(
        name: customerData['name'],
        email: customerData['email'],
        phoneNumber: customerData['phoneNumber'],
        status: customerData['status'],
        companyName: customerData['companyName'],
        address: customerData['streetAddress'] ?? customerData['address'],
        department: customerData['department'],
        employeeId: customerData['employeeId'],
        updatedAt: DateTime.now(),
      );

      return await updateCustomer(updated);
    } catch (e) {
      _errorMessage = 'Failed to update customer: $e';
      return false;
    }
  }

  Future<Map<String, dynamic>> cleanupDuplicateEmployees() async {
    // API endpoint not available yet
    return {'success': false, 'error': 'Not implemented'};
  }

  Future<void> fetchCustomersByOrganization(String organizationDomain) async {
    try {
      _state = DataState.loading;
      _errorMessage = null;
      notifyListeners();

      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/api/admin/customers/unified?org=$organizationDomain'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _customers.clear();
          for (var customerData in data['data']) {
            _customers.add(CustomerEntity.fromMap(customerData));
          }
          _state = DataState.loaded;
          notifyListeners();
          return;
        }
      }
      throw Exception('Failed to fetch customers');
    } catch (e) {
      _errorMessage = 'Error: ${e.toString()}';
      _state = DataState.error;
      notifyListeners();
    }
  }

  Future<void> updateExistingCustomersWithMissingFields() async {
    // Not implemented in API yet
  }

  Future<List<Map<String, dynamic>>> fetchPendingCustomers() async {
    // Not implemented in API yet
    return [];
  }

  Future<bool> approveCustomer(String customerId) async {
    // Not implemented in API yet
    return false;
  }

  Future<bool> rejectCustomer(String customerId, String reason) async {
    // Not implemented in API yet
    return false;
  }

  Future<bool> bulkApproveCustomers(List<String> customerIds) async {
    // Not implemented in API yet
    return false;
  }

  Future<int> getPendingCustomersCount() async {
    // Not implemented in API yet
    return 0;
  }

  Stream<int> pendingCustomersCountStream() async* {
    while (true) {
      yield await getPendingCustomersCount();
      await Future.delayed(Duration(seconds: 30));
    }
  }
}