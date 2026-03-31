import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/services/billing_api_service.dart';

// ============================================================================
// DATA MODELS
// ============================================================================

class Contract {
  String contractId;
  String organizationId;
  String organizationName;
  DateTime startDate;
  DateTime endDate;
  String status; // 'draft', 'active', 'expired', 'terminated'
  bool autoRenewal;
  Map<String, VehiclePricing> vehiclePricing;
  SurchargeRates surcharges;
  List<VolumeSlab> volumeSlabs;
  PaymentTerms terms;
  AdditionalCharges additionalCharges;
  SLATerms sla;
  DateTime createdAt;
  String createdBy;

  Contract({
    required this.contractId,
    required this.organizationId,
    required this.organizationName,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.autoRenewal,
    required this.vehiclePricing,
    required this.surcharges,
    required this.volumeSlabs,
    required this.terms,
    required this.additionalCharges,
    required this.sla,
    required this.createdAt,
    required this.createdBy,
  });
}

class VehiclePricing {
  double baseFarePerTrip;
  double ratePerKm;
  double ratePerMinuteWaiting;
  int gracePeriodMinutes;

  VehiclePricing({
    required this.baseFarePerTrip,
    required this.ratePerKm,
    required this.ratePerMinuteWaiting,
    required this.gracePeriodMinutes,
  });
}

class SurchargeRates {
  double peakHoursPercent;
  double nightShiftPercent;
  double weekendPercent;
  double fuelSurchargePercent;

  SurchargeRates({
    required this.peakHoursPercent,
    required this.nightShiftPercent,
    required this.weekendPercent,
    required this.fuelSurchargePercent,
  });
}

class VolumeSlab {
  int minTrips;
  int maxTrips;
  double ratePerKm;
  double discountPercent;

  VolumeSlab({
    required this.minTrips,
    required this.maxTrips,
    required this.ratePerKm,
    required this.discountPercent,
  });
}

class PaymentTerms {
  double monthlyMinimum;
  double monthlyMaximum;
  int paymentDueDays;
  String billingCycle; // 'Weekly', 'Bi-Weekly', 'Monthly'
  String currency;
  double creditLimit;
  double latePenaltyPercent;
  double freeCancellationPercent;
  double cancellationPenalty;

  PaymentTerms({
    required this.monthlyMinimum,
    required this.monthlyMaximum,
    required this.paymentDueDays,
    required this.billingCycle,
    required this.currency,
    required this.creditLimit,
    required this.latePenaltyPercent,
    required this.freeCancellationPercent,
    required this.cancellationPenalty,
  });
}

class AdditionalCharges {
  String tollCharges; // 'actual' or fixed amount
  String parkingCharges;
  double vehicleCleaning;
  double gpsDeviationPenalty;

  AdditionalCharges({
    required this.tollCharges,
    required this.parkingCharges,
    required this.vehicleCleaning,
    required this.gpsDeviationPenalty,
  });
}

class SLATerms {
  double onTimePickupPercent;
  double vehicleAvailabilityPercent;
  double driverRatingMinimum;
  int responseTimeMinutes;
  double slaBreachPenalty;

  SLATerms({
    required this.onTimePickupPercent,
    required this.vehicleAvailabilityPercent,
    required this.driverRatingMinimum,
    required this.responseTimeMinutes,
    required this.slaBreachPenalty,
  });
}

class AuditLog {
  String id;
  String entityType;
  String entityId;
  String action;
  String userId;
  String userName;
  DateTime timestamp;
  Map<String, dynamic> changes;
  String? remarks;

  AuditLog({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.userId,
    required this.userName,
    required this.timestamp,
    required this.changes,
    this.remarks,
  });
}

// ============================================================================
// MAIN BILLING PAGE
// ============================================================================

class BillingInvoicesPage extends StatefulWidget {
  @override
  _BillingInvoicesPageState createState() => _BillingInvoicesPageState();
}

class _BillingInvoicesPageState extends State<BillingInvoicesPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedFilter = 'All';
  String _searchQuery = '';
  DateTimeRange? _selectedDateRange;
  String _selectedVehicleType = 'All';
  
  // Current logged in admin user (in real app, get from auth)
  final String _currentUserId = 'ADMIN-001';
  final String _currentUserName = 'Admin User';
  
  // ✅ BACKEND DATA - Replace dummy data with API calls
  List<Map<String, dynamic>> _contracts = [];
  List<Map<String, dynamic>> _invoices = [];
  List<Map<String, dynamic>> _auditLogs = [];
  
  // ✅ Loading states
  bool _isRefreshing = false;
  bool _isLoading = true;
  String? _errorMessage;

  // ============================================================================
  // CONTRACTS DATA - Foundation for all billing
  // ============================================================================
  
  final List<Map<String, dynamic>> _contracts = [
    {
      'contractId': 'CNT-2024-ABC-001',
      'organizationId': 'ORG-ABC',
      'organizationName': 'ABC Logistics Pvt Ltd',
      'startDate': '2024-01-01',
      'endDate': '2025-12-31',
      'status': 'active',
      'autoRenewal': true,
      'createdAt': '2023-12-15',
      'createdBy': 'ADMIN-001',
      
      // Negotiated Vehicle Pricing
      'vehiclePricing': {
        'Truck': {
          'baseFare': 50.0,
          'ratePerKm': 12.0,
          'waitingRate': 2.0,
          'gracePeriodMinutes': 5,
        },
        'Van': {
          'baseFare': 40.0,
          'ratePerKm': 10.0,
          'waitingRate': 1.5,
          'gracePeriodMinutes': 5,
        },
      },
      
      // Surcharge Configuration
      'surcharges': {
        'peakHours': 15.0,
        'nightShift': 25.0,
        'weekend': 10.0,
        'fuelSurcharge': 5.0,
      },
      
      // Volume-based Pricing Slabs
      'volumeSlabs': [
        {'minTrips': 0, 'maxTrips': 500, 'ratePerKm': 12.0, 'discount': 0.0},
        {'minTrips': 501, 'maxTrips': 1000, 'ratePerKm': 11.0, 'discount': 8.33},
        {'minTrips': 1001, 'maxTrips': 1500, 'ratePerKm': 10.0, 'discount': 16.67},
        {'minTrips': 1501, 'maxTrips': 999999, 'ratePerKm': 9.0, 'discount': 25.0},
      ],
      
      // Payment Terms
      'terms': {
        'monthlyMinimum': 70000.0,
        'monthlyMaximum': 500000.0,
        'paymentDueDays': 30,
        'billingCycle': 'Monthly',
        'currency': 'INR',
        'creditLimit': 500000.0,
        'latePenaltyPercent': 2.0,
        'freeCancellationPercent': 5.0,
        'cancellationPenalty': 50.0,
      },
      
      // Additional Charges
      'additionalCharges': {
        'tollCharges': 'actual',
        'parkingCharges': 'actual',
        'vehicleCleaning': 500.0,
        'gpsDeviationPenalty': 100.0,
      },
      
      // SLA Terms
      'sla': {
        'onTimePickupPercent': 95.0,
        'vehicleAvailabilityPercent': 99.0,
        'driverRatingMinimum': 4.0,
        'responseTimeMinutes': 15,
        'slaBreachPenalty': 500.0,
      },
    },
    {
      'contractId': 'CNT-2024-XYZ-005',
      'organizationId': 'ORG-XYZ',
      'organizationName': 'XYZ Transport Solutions',
      'startDate': '2024-03-15',
      'endDate': '2025-03-14',
      'status': 'active',
      'autoRenewal': false,
      'createdAt': '2024-03-01',
      'createdBy': 'ADMIN-001',
      
      'vehiclePricing': {
        'Car': {
          'baseFare': 30.0,
          'ratePerKm': 8.0,
          'waitingRate': 1.0,
          'gracePeriodMinutes': 3,
        },
      },
      
      'surcharges': {
        'peakHours': 12.0,
        'nightShift': 20.0,
        'weekend': 8.0,
        'fuelSurcharge': 4.0,
      },
      
      'volumeSlabs': [
        {'minTrips': 0, 'maxTrips': 1000, 'ratePerKm': 8.0, 'discount': 0.0},
        {'minTrips': 1001, 'maxTrips': 999999, 'ratePerKm': 7.5, 'discount': 6.25},
      ],
      
      'terms': {
        'monthlyMinimum': 50000.0,
        'monthlyMaximum': 300000.0,
        'paymentDueDays': 15,
        'billingCycle': 'Weekly',
        'currency': 'INR',
        'creditLimit': 300000.0,
        'latePenaltyPercent': 1.5,
        'freeCancellationPercent': 3.0,
        'cancellationPenalty': 30.0,
      },
      
      'additionalCharges': {
        'tollCharges': 'actual',
        'parkingCharges': 'actual',
        'vehicleCleaning': 300.0,
        'gpsDeviationPenalty': 75.0,
      },
      
      'sla': {
        'onTimePickupPercent': 92.0,
        'vehicleAvailabilityPercent': 98.0,
        'driverRatingMinimum': 3.8,
        'responseTimeMinutes': 20,
        'slaBreachPenalty': 300.0,
      },
    },
  ];

  // ============================================================================
  // INVOICES DATA - Generated from contracts
  // ============================================================================
  
  final List<Map<String, dynamic>> _invoices = [
    {
      'id': 'INV-2024-001',
      'organizationId': 'ORG-ABC',
      'organizationName': 'ABC Logistics Pvt Ltd',
      'contractId': 'CNT-2024-ABC-001',
      'agreementStartDate': '2024-01-01',
      'agreementEndDate': '2025-12-31',
      'billingCycle': 'Monthly',
      'billingPeriodStart': '2024-12-01',
      'billingPeriodEnd': '2024-12-31',
      'paymentTerms': 'Net 30',
      'amount': 245680.50,
      'gstAmount': 44222.49,
      'totalAmount': 289902.99,
      'amountPaid': 289902.99,
      'status': 'Paid',
      'date': '2024-12-01',
      'dueDate': '2024-12-31',
      'paidDate': '2024-12-25',
      'paymentMode': 'Bank Transfer',
      'transactionRef': 'TXN-2024-12-25-001',
      'trips': 156,
      'totalDistance': 12450.5,
      'totalFuelConsumed': 1850.25,
      'totalIdleTime': 45.5,
      'vehicles': [
        {'type': 'Truck', 'count': 8, 'distance': 8500.0, 'trips': 100, 'cost': 170000.0},
        {'type': 'Van', 'count': 5, 'distance': 3950.5, 'trips': 56, 'cost': 75680.50},
      ],
      'pricingApplied': {
        'volumeSlabApplied': '1001-1500 trips @ ₹10/km',
        'discountPercent': 16.67,
        'minimumCommitmentApplied': false,
      },
      'charges': {
        'baseCharges': 180000.0,
        'perKmCharges': 45680.50,
        'fuelSurcharge': 12000.0,
        'tollCharges': 4500.0,
        'waitingCharges': 2500.0,
        'loadingUnloadingCharges': 1000.0,
      },
      'generatedBy': 'SYSTEM-AUTO',
      'approvedBy': 'ADMIN-001',
      'approvedAt': '2024-12-02',
    },
    {
      'id': 'INV-2024-002',
      'organizationId': 'ORG-XYZ',
      'organizationName': 'XYZ Transport Solutions',
      'contractId': 'CNT-2024-XYZ-005',
      'agreementStartDate': '2024-03-15',
      'agreementEndDate': '2025-03-14',
      'billingCycle': 'Weekly',
      'billingPeriodStart': '2024-12-01',
      'billingPeriodEnd': '2024-12-07',
      'paymentTerms': 'Net 15',
      'amount': 125000.00,
      'gstAmount': 22500.00,
      'totalAmount': 147500.00,
      'amountPaid': 75000.00,
      'status': 'Partially Paid',
      'date': '2024-12-08',
      'dueDate': '2024-12-23',
      'paidDate': '2024-12-10',
      'paymentMode': 'Cheque',
      'transactionRef': 'CHQ-2024-12-10-456',
      'trips': 89,
      'totalDistance': 6780.0,
      'totalFuelConsumed': 980.5,
      'totalIdleTime': 28.0,
      'vehicles': [
        {'type': 'Car', 'count': 12, 'distance': 6780.0, 'trips': 89, 'cost': 125000.0},
      ],
      'pricingApplied': {
        'volumeSlabApplied': '0-1000 trips @ ₹8/km',
        'discountPercent': 0.0,
        'minimumCommitmentApplied': false,
      },
      'charges': {
        'baseCharges': 95000.0,
        'perKmCharges': 20340.0,
        'fuelSurcharge': 6500.0,
        'tollCharges': 2160.0,
        'waitingCharges': 800.0,
        'loadingUnloadingCharges': 200.0,
      },
      'generatedBy': 'SYSTEM-AUTO',
      'approvedBy': 'ADMIN-001',
      'approvedAt': '2024-12-08',
    },
    {
      'id': 'INV-2024-003',
      'organizationId': 'ORG-ABC',
      'organizationName': 'ABC Logistics Pvt Ltd',
      'contractId': 'CNT-2024-ABC-001',
      'agreementStartDate': '2024-01-01',
      'agreementEndDate': '2025-12-31',
      'billingCycle': 'Monthly',
      'billingPeriodStart': '2024-11-01',
      'billingPeriodEnd': '2024-11-30',
      'paymentTerms': 'Net 30',
      'amount': 485000.00,
      'gstAmount': 87300.00,
      'totalAmount': 572300.00,
      'amountPaid': 0.0,
      'status': 'Overdue',
      'date': '2024-11-01',
      'dueDate': '2024-12-01',
      'paidDate': null,
      'paymentMode': null,
      'transactionRef': null,
      'trips': 234,
      'totalDistance': 18950.8,
      'totalFuelConsumed': 2845.5,
      'totalIdleTime': 67.5,
      'vehicles': [
        {'type': 'Truck', 'count': 15, 'distance': 15200.0, 'trips': 180, 'cost': 380000.0},
        {'type': 'Van', 'count': 6, 'distance': 3750.8, 'trips': 54, 'cost': 105000.0},
      ],
      'pricingApplied': {
        'volumeSlabApplied': '1001-1500 trips @ ₹10/km',
        'discountPercent': 16.67,
        'minimumCommitmentApplied': false,
      },
      'charges': {
        'baseCharges': 350000.0,
        'perKmCharges': 94754.0,
        'fuelSurcharge': 25000.0,
        'tollCharges': 8500.0,
        'waitingCharges': 4500.0,
        'loadingUnloadingCharges': 2246.0,
      },
      'generatedBy': 'SYSTEM-AUTO',
      'approvedBy': 'ADMIN-001',
      'approvedAt': '2024-11-02',
    },
  ];

  List<Map<String, dynamic>> get _filteredInvoices {
    return _invoices.where((invoice) {
      final matchesStatus = _selectedFilter == 'All' || invoice['status'] == _selectedFilter;
      final matchesSearch = invoice['organizationName'].toLowerCase().contains(_searchQuery.toLowerCase()) ||
          invoice['id'].toLowerCase().contains(_searchQuery.toLowerCase()) ||
          invoice['contractId'].toLowerCase().contains(_searchQuery.toLowerCase());
      
      bool matchesDate = true;
      if (_selectedDateRange != null) {
        final invoiceDate = DateTime.parse(invoice['date']);
        matchesDate = invoiceDate.isAfter(_selectedDateRange!.start.subtract(Duration(days: 1))) &&
                      invoiceDate.isBefore(_selectedDateRange!.end.add(Duration(days: 1)));
      }
      
      bool matchesVehicle = true;
      if (_selectedVehicleType != 'All') {
        matchesVehicle = (invoice['vehicles'] as List).any((v) => v['type'] == _selectedVehicleType);
      }
      
      return matchesStatus && matchesSearch && matchesDate && matchesVehicle;
    }).toList();
  }

  List<Map<String, dynamic>> get _activeContracts {
    return _contracts.where((c) => c['status'] == 'active').toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ✅ BACKEND CONNECTION - Load data from API
  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Future.wait([
        _loadContracts(),
        _loadInvoices(),
      ]);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load billing data: ${e.toString()}';
      });
      debugPrint('❌ Error loading initial data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadContracts() async {
    try {
      final contracts = await BillingApiService.getAllContracts();
      setState(() {
        _contracts = contracts;
      });
      debugPrint('✅ Loaded ${contracts.length} contracts from backend');
    } catch (e) {
      debugPrint('❌ Error loading contracts: $e');
      rethrow;
    }
  }

  Future<void> _loadInvoices() async {
    try {
      final invoices = await BillingApiService.getAllInvoices();
      setState(() {
        _invoices = invoices;
      });
      debugPrint('✅ Loaded ${invoices.length} invoices from backend');
    } catch (e) {
      debugPrint('❌ Error loading invoices: $e');
      rethrow;
    }
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    return formatter.format(amount);
  }

  // ✅ BACKEND REFRESH - Refresh all data from API
  Future<void> _refreshAllData() async {
    if (_isRefreshing) return; // Prevent multiple simultaneous refreshes
    
    setState(() => _isRefreshing = true);
    
    try {
      await Future.wait([
        _loadContracts(),
        _loadInvoices(),
      ]);
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Billing data refreshed successfully'),
              ],
            ),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error refreshing billing data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Text('Refresh failed: ${e.toString()}'),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  // ============================================================================
  // AUDIT LOGGING
  // ============================================================================
  
  void _logAuditEntry({
    required String entityType,
    required String entityId,
    required String action,
    required Map<String, dynamic> changes,
    String? remarks,
  }) {
    final log = {
      'id': 'AUDIT-${DateTime.now().millisecondsSinceEpoch}',
      'entityType': entityType,
      'entityId': entityId,
      'action': action,
      'userId': _currentUserId,
      'userName': _currentUserName,
      'timestamp': DateTime.now(),
      'changes': changes,
      'remarks': remarks,
    };
    
    setState(() {
      _auditLogs.add(log);
    });
    
    print('Audit Log: ${log['action']} on ${log['entityType']} ${log['entityId']} by ${log['userName']}');
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  List<Map<String, dynamic>> get _filteredInvoices {
    return _invoices.where((invoice) {
      final matchesStatus = _selectedFilter == 'All' || invoice['status'] == _selectedFilter;
      final matchesSearch = invoice['organizationName'].toLowerCase().contains(_searchQuery.toLowerCase()) ||
          invoice['id'].toLowerCase().contains(_searchQuery.toLowerCase()) ||
          invoice['contractId'].toLowerCase().contains(_searchQuery.toLowerCase());
      
      bool matchesDate = true;
      if (_selectedDateRange != null) {
        final invoiceDate = DateTime.parse(invoice['date'].toString());
        matchesDate = invoiceDate.isAfter(_selectedDateRange!.start.subtract(Duration(days: 1))) &&
                      invoiceDate.isBefore(_selectedDateRange!.end.add(Duration(days: 1)));
      }
      
      bool matchesVehicle = true;
      if (_selectedVehicleType != 'All') {
        matchesVehicle = (invoice['vehicles'] as List).any((v) => v['type'] == _selectedVehicleType);
      }
      
      return matchesStatus && matchesSearch && matchesDate && matchesVehicle;
    }).toList();
  }

  List<Map<String, dynamic>> get _activeContracts {
    return _contracts.where((c) => c['status'] == 'active').toList();
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    return formatter.format(amount);
  }

  // ============================================================================
  // CONTRACT VALIDATION & INVOICE GENERATION
  // ============================================================================
  
  Map<String, dynamic>? _getContractById(String contractId) {
    try {
      return _contracts.firstWhere((c) => c['contractId'] == contractId);
    } catch (e) {
      return null;
    }
  }

  bool _validateInvoiceAgainstContract(
    Map<String, dynamic> invoice,
    Map<String, dynamic> contract,
  ) {
    List<String> errors = [];
    
    // Check if invoice is within contract period
    DateTime invoiceDate = DateTime.parse(invoice['date']);
    DateTime contractStart = DateTime.parse(contract['startDate']);
    DateTime contractEnd = DateTime.parse(contract['endDate']);
    
    if (invoiceDate.isBefore(contractStart) || invoiceDate.isAfter(contractEnd)) {
      errors.add('Invoice date outside contract period');
    }
    
    // Check if total amount exceeds maximum
    final terms = contract['terms'] as Map<String, dynamic>;
    if (invoice['totalAmount'] > terms['monthlyMaximum']) {
      errors.add('Invoice exceeds monthly maximum: ${_formatCurrency(terms['monthlyMaximum'])}');
    }
    
    // Check billing cycle match
    if (invoice['billingCycle'] != terms['billingCycle']) {
      errors.add('Billing cycle mismatch');
    }
    
    if (errors.isNotEmpty) {
      _showValidationErrors(errors);
      return false;
    }
    
    return true;
  }

  void _showValidationErrors(List<String> errors) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('Validation Errors'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: errors.map((error) => Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: TextStyle(color: Colors.red)),
                Expanded(child: Text(error)),
              ],
            ),
          )).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // UI BUILD METHODS
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    // ✅ LOADING STATE
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading billing data...', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );
    }

    // ✅ ERROR STATE
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                'Error Loading Data',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red[700]),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadInitialData,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildInvoicesTab(),
                _buildContractsTab(),
                _buildPaymentAnalyticsTab(),
                _buildAuditLogsTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _showGenerateInvoiceDialog(),
              icon: Icon(Icons.add),
              label: Text('New Invoice'),
              backgroundColor: Colors.blue[700],
            )
          : _tabController.index == 1
              ? FloatingActionButton.extended(
                  onPressed: () => _showCreateContractDialog(),
                  icon: Icon(Icons.add),
                  label: Text('New Contract'),
                  backgroundColor: Colors.green[700],
                )
              : null,
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, size: 32, color: Colors.blue[700]),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin Billing Portal',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    Text(
                      'Contract-Based Invoice & Payment Management',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.verified_user, size: 16, color: Colors.green[700]),
                    SizedBox(width: 6),
                    Text(
                      'Admin',
                      style: TextStyle(
                        color: Colors.green[700],
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              
              // ✅ NEW: Refresh Button
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.2)),
                ),
                child: IconButton(
                  icon: _isRefreshing 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
                        ),
                      )
                    : const Icon(Icons.refresh, color: Color(0xFF8B5CF6)),
                  onPressed: _isRefreshing ? null : _refreshAllData,
                  tooltip: "Refresh Data",
                ),
              ),
              
              IconButton(
                icon: Icon(Icons.download, color: Colors.blue[700]),
                onPressed: () => _exportAllData(),
                tooltip: 'Export All Data',
              ),
              IconButton(
                icon: Icon(Icons.filter_list, color: Colors.blue[700]),
                onPressed: () => _showAdvancedFilters(),
                tooltip: 'Advanced Filters',
              ),
            ],
          ),
          SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search by invoice, organization, or contract ID...',
              hintStyle: TextStyle(color: Colors.grey[400]),
              prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
          SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.blue[700],
        unselectedLabelColor: Colors.grey[600],
        indicatorColor: Colors.blue[700],
        indicatorWeight: 3,
        tabs: [
          Tab(icon: Icon(Icons.receipt), text: 'Invoices'),
          Tab(icon: Icon(Icons.description), text: 'Contracts'),
          Tab(icon: Icon(Icons.analytics), text: 'Analytics'),
          Tab(icon: Icon(Icons.history), text: 'Audit Logs'),
        ],
      ),
    );
  }

  // ============================================================================
  // INVOICES TAB
  // ============================================================================

  Widget _buildInvoicesTab() {
    return Column(
      children: [
        _buildComprehensiveSummary(),
        _buildFilterChips(),
        Expanded(child: _buildInvoicesList()),
      ],
    );
  }

  Widget _buildComprehensiveSummary() {
    double totalRevenue = _invoices.fold(0.0, (sum, inv) => sum + (inv['totalAmount'] as num).toDouble());
    double totalPaid = _invoices.fold(0.0, (sum, inv) => sum + (inv['amountPaid'] as num).toDouble());
    double totalPending = totalRevenue - totalPaid;
    int totalTrips = _invoices.fold(0, (sum, inv) => sum + (inv['trips'] as int));
    double totalDistance = _invoices.fold(0.0, (sum, inv) => sum + (inv['totalDistance'] as num).toDouble());

    return Container(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryCard(
              'Total Revenue',
              _formatCurrency(totalRevenue),
              Icons.account_balance_wallet,
              Colors.blue,
              'Including GST',
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _buildSummaryCard(
              'Amount Paid',
              _formatCurrency(totalPaid),
              Icons.check_circle,
              Colors.green,
              '${((totalPaid/totalRevenue)*100).toStringAsFixed(1)}% of total',
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _buildSummaryCard(
              'Pending Amount',
              _formatCurrency(totalPending),
              Icons.pending,
              Colors.orange,
              'Outstanding dues',
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _buildSummaryCard(
              'Total Distance',
              '${totalDistance.toStringAsFixed(0)} km',
              Icons.route,
              Colors.purple,
              '$totalTrips trips completed',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color, String subtitle) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500),
          ),
          SizedBox(height: 1),
          Text(
            subtitle,
            style: TextStyle(fontSize: 9, color: Colors.grey[500]),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = ['All', 'Paid', 'Partially Paid', 'Pending', 'Overdue'];

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ...filters.map((filter) {
              final isSelected = _selectedFilter == filter;
              final count = filter == 'All' 
                ? _invoices.length 
                : _invoices.where((inv) => inv['status'] == filter).length;
              
              return Padding(
                padding: EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text('$filter ($count)'),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedFilter = filter;
                    });
                  },
                  backgroundColor: Colors.white,
                  selectedColor: Colors.blue.withOpacity(0.2),
                  checkmarkColor: Colors.blue[700],
                  side: BorderSide(color: isSelected ? Colors.blue : Colors.grey[300]!),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.blue[700] : Colors.grey[700],
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            }).toList(),
            SizedBox(width: 8),
            ActionChip(
              avatar: Icon(Icons.date_range, size: 18),
              label: Text(_selectedDateRange == null ? 'Date Range' : 'Filtered'),
              onPressed: () => _selectDateRange(),
              backgroundColor: _selectedDateRange != null ? Colors.blue.withOpacity(0.1) : Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoicesList() {
    if (_filteredInvoices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey[300]),
            SizedBox(height: 16),
            Text(
              'No invoices found',
              style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 8),
            Text(
              'Try adjusting your filters',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _filteredInvoices.length,
      itemBuilder: (context, index) {
        return _buildInvoiceCard(_filteredInvoices[index]);
      },
    );
  }

  Widget _buildInvoiceCard(Map<String, dynamic> invoice) {
    Color statusColor;
    IconData statusIcon;
    switch (invoice['status']) {
      case 'Paid':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'Partially Paid':
        statusColor = Colors.blue;
        statusIcon = Icons.hourglass_bottom;
        break;
      case 'Pending':
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        break;
      case 'Overdue':
        statusColor = Colors.red;
        statusIcon = Icons.warning;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.info;
    }

    final contract = _getContractById(invoice['contractId']);
    final hasContract = contract != null;

    return Card(
      margin: EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: statusColor.withOpacity(0.3), width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showInvoiceDetails(invoice),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              invoice['id'],
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[700],
                              ),
                            ),
                            SizedBox(width: 8),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(statusIcon, size: 14, color: statusColor),
                                  SizedBox(width: 4),
                                  Text(
                                    invoice['status'],
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (hasContract) ...[
                              SizedBox(width: 8),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.green[200]!),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified, size: 12, color: Colors.green[700]),
                                    SizedBox(width: 4),
                                    Text(
                                      'Contract Valid',
                                      style: TextStyle(
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: 6),
                        Text(
                          invoice['organizationName'],
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                        ),
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.description, size: 14, color: Colors.grey[500]),
                            SizedBox(width: 4),
                            Text(
                              'Contract: ${invoice['contractId']}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        if (invoice['pricingApplied'] != null) ...[
                          Row(
                            children: [
                              Icon(Icons.local_offer, size: 14, color: Colors.orange[700]),
                              SizedBox(width: 4),
                              Text(
                                invoice['pricingApplied']['volumeSlabApplied'],
                                style: TextStyle(fontSize: 11, color: Colors.orange[700], fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              Divider(height: 24, thickness: 1),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total Amount', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                        SizedBox(height: 4),
                        Text(
                          _formatCurrency(invoice['totalAmount']),
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue[700]),
                        ),
                        Text('(Inc. GST)', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                  Container(
                    height: 50,
                    width: 1,
                    color: Colors.grey[300],
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Amount Paid', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                          SizedBox(height: 4),
                          Text(
                            _formatCurrency(invoice['amountPaid']),
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green[700]),
                          ),
                          if (invoice['amountPaid'] < invoice['totalAmount'])
                            Text(
                              'Due: ${_formatCurrency(invoice['totalAmount'] - invoice['amountPaid'])}',
                              style: TextStyle(fontSize: 10, color: Colors.red[600]),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Billing Period: ${DateFormat('dd MMM').format(DateTime.parse(invoice['billingPeriodStart']))} - ${DateFormat('dd MMM yyyy').format(DateTime.parse(invoice['billingPeriodEnd']))}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildCompactInfo('Trips', '${invoice['trips']}', Icons.local_shipping, Colors.blue),
                        ),
                        Expanded(
                          child: _buildCompactInfo('Distance', '${invoice['totalDistance'].toStringAsFixed(0)} km', Icons.route, Colors.purple),
                        ),
                        Expanded(
                          child: _buildCompactInfo('Fuel', '${invoice['totalFuelConsumed'].toStringAsFixed(0)} L', Icons.local_gas_station, Colors.orange),
                        ),
                        Expanded(
                          child: _buildCompactInfo('Idle', '${invoice['totalIdleTime'].toStringAsFixed(1)} hrs', Icons.timer, Colors.red),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]),
                        SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Issued', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                            Text(
                              DateFormat('dd MMM yyyy').format(DateTime.parse(invoice['date'])),
                              style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.event, size: 14, color: Colors.grey[500]),
                        SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Due Date', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                            Text(
                              DateFormat('dd MMM yyyy').format(DateTime.parse(invoice['dueDate'])),
                              style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (invoice['paidDate'] != null)
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, size: 14, color: Colors.green),
                          SizedBox(width: 6),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Paid On', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                              Text(
                                DateFormat('dd MMM yyyy').format(DateTime.parse(invoice['paidDate'])),
                                style: TextStyle(fontSize: 12, color: Colors.green[700], fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _viewContract(invoice),
                    icon: Icon(Icons.description, size: 18),
                    label: Text('View Contract'),
                    style: TextButton.styleFrom(foregroundColor: Colors.blue[700]),
                  ),
                  SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _showInvoiceDetails(invoice),
                    icon: Icon(Icons.visibility, size: 18),
                    label: Text('View Details'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactInfo(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, size: 16, color: color),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[800]),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
        ),
      ],
    );
  }

  // ============================================================================
  // CONTRACTS TAB
  // ============================================================================

  Widget _buildContractsTab() {
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Contract Management', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Text(
                '${_activeContracts.length} Active',
                style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        ..._contracts.map((contract) => _buildContractCard(contract)).toList(),
      ],
    );
  }

  Widget _buildContractCard(Map<String, dynamic> contract) {
    final startDate = DateTime.parse(contract['startDate']);
    final endDate = DateTime.parse(contract['endDate']);
    final daysRemaining = endDate.difference(DateTime.now()).inDays;
    final isExpiringSoon = daysRemaining <= 30 && daysRemaining > 0;
    final isExpired = daysRemaining < 0;
    final isActive = contract['status'] == 'active';

    // Count invoices for this contract
    final invoiceCount = _invoices.where((inv) => inv['contractId'] == contract['contractId']).length;
    final totalRevenue = _invoices
        .where((inv) => inv['contractId'] == contract['contractId'])
        .fold(0.0, (sum, inv) => sum + (inv['totalAmount'] as num).toDouble());

    return Card(
      margin: EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isExpired 
              ? Colors.red.withOpacity(0.3) 
              : isExpiringSoon 
                  ? Colors.orange.withOpacity(0.3) 
                  : Colors.blue.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.all(20),
        childrenPadding: EdgeInsets.fromLTRB(20, 0, 20, 20),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contract['contractId'],
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue[700]),
                  ),
                  SizedBox(height: 6),
                  Text(
                    contract['organizationName'],
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800]),
                  ),
                ],
              ),
            ),
            if (isExpired)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    Icon(Icons.error, size: 14, color: Colors.red),
                    SizedBox(width: 4),
                    Text('Expired', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              )
            else if (isExpiringSoon)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    Icon(Icons.warning, size: 14, color: Colors.orange),
                    SizedBox(width: 4),
                    Text('$daysRemaining days left', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              )
            else if (isActive)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 14, color: Colors.green),
                    SizedBox(width: 4),
                    Text('Active', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
        children: [
          Divider(),
          SizedBox(height: 12),
          
          // Contract Details
          _buildContractSection('Basic Information', [
            {'label': 'Start Date', 'value': DateFormat('dd MMM yyyy').format(startDate), 'icon': Icons.start},
            {'label': 'End Date', 'value': DateFormat('dd MMM yyyy').format(endDate), 'icon': Icons.event},
            {'label': 'Billing Cycle', 'value': contract['terms']['billingCycle'], 'icon': Icons.repeat},
            {'label': 'Payment Terms', 'value': 'Net ${contract['terms']['paymentDueDays']}', 'icon': Icons.payment},
          ]),
          
          SizedBox(height: 16),
          
          // Revenue Stats
          _buildContractSection('Revenue Statistics', [
            {'label': 'Total Invoices', 'value': '$invoiceCount', 'icon': Icons.receipt_long},
            {'label': 'Total Revenue', 'value': _formatCurrency(totalRevenue), 'icon': Icons.attach_money},
            {'label': 'Monthly Minimum', 'value': _formatCurrency(contract['terms']['monthlyMinimum']), 'icon': Icons.trending_up},
            {'label': 'Credit Limit', 'value': _formatCurrency(contract['terms']['creditLimit']), 'icon': Icons.account_balance},
          ]),
          
          SizedBox(height: 16),
          
          // Pricing Details - Expandable
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_offer, color: Colors.blue[700]),
                    SizedBox(width: 8),
                    Text(
                      'Vehicle Pricing',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue[700]),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                ...(contract['vehiclePricing'] as Map<String, dynamic>).entries.map((entry) {
                  final vehicleType = entry.key;
                  final pricing = entry.value as Map<String, dynamic>;
                  return Container(
                    margin: EdgeInsets.only(bottom: 8),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vehicleType,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: Text('Base Fare: ${_formatCurrency(pricing['baseFare'])}', style: TextStyle(fontSize: 12))),
                            Expanded(child: Text('Per KM: ${_formatCurrency(pricing['ratePerKm'])}', style: TextStyle(fontSize: 12))),
                          ],
                        ),
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(child: Text('Waiting: ${_formatCurrency(pricing['waitingRate'])}/min', style: TextStyle(fontSize: 12))),
                            Expanded(child: Text('Grace: ${pricing['gracePeriodMinutes']} min', style: TextStyle(fontSize: 12))),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
          
          SizedBox(height: 16),
          
          // Volume Slabs
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.trending_down, color: Colors.orange[700]),
                    SizedBox(width: 8),
                    Text(
                      'Volume Discount Slabs',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange[700]),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                ...(contract['volumeSlabs'] as List).map((slab) {
                  return Container(
                    margin: EdgeInsets.only(bottom: 8),
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${slab['minTrips']} - ${slab['maxTrips'] > 9999 ? '∞' : slab['maxTrips']} trips',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${_formatCurrency(slab['ratePerKm'])}/km',
                            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${slab['discount'].toStringAsFixed(1)}% off',
                            style: TextStyle(fontSize: 11, color: Colors.green[700], fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
          
          SizedBox(height: 20),
          
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _editContract(contract),
                  icon: Icon(Icons.edit, size: 18),
                  label: Text('Edit Contract'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue[700],
                    side: BorderSide(color: Colors.blue[700]!),
                    padding: EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _downloadContractPDF(contract),
                  icon: Icon(Icons.picture_as_pdf, size: 18),
                  label: Text('Download PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContractSection(String title, List<Map<String, dynamic>> items) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[800]),
          ),
          SizedBox(height: 12),
          ...items.map((item) => Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(item['icon'], size: 16, color: Colors.grey[600]),
                SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: Text(
                    item['label'],
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    item['value'],
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[800]),
                  ),
                ),
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }

  // ============================================================================
  // PAYMENT ANALYTICS TAB
  // ============================================================================

  Widget _buildPaymentAnalyticsTab() {
    double totalRevenue = _invoices.fold(0.0, (sum, inv) => sum + (inv['totalAmount'] as num).toDouble());
    double totalPaid = _invoices.fold(0.0, (sum, inv) => sum + (inv['amountPaid'] as num).toDouble());
    double totalPending = totalRevenue - totalPaid;
    double totalDistance = _invoices.fold(0.0, (sum, inv) => sum + (inv['totalDistance'] as num).toDouble());
    double totalFuel = _invoices.fold(0.0, (sum, inv) => sum + (inv['totalFuelConsumed'] as num).toDouble());
    int totalTrips = _invoices.fold(0, (sum, inv) => sum + (inv['trips'] as int));
    
    double avgRevenuePerTrip = totalTrips > 0 ? totalRevenue / totalTrips : 0;
    double avgRevenuePerKm = totalDistance > 0 ? totalRevenue / totalDistance : 0;

    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        Text('Payment & Fleet Analytics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        SizedBox(height: 16),
        _buildAnalyticsSection(
          'Payment Overview',
          Icons.payment,
          Colors.green,
          [
            _buildAnalyticsCard('Total Revenue', _formatCurrency(totalRevenue), Icons.currency_rupee, Colors.blue),
            _buildAnalyticsCard('Amount Received', _formatCurrency(totalPaid), Icons.check_circle, Colors.green),
            _buildAnalyticsCard('Outstanding', _formatCurrency(totalPending), Icons.pending_actions, Colors.orange),
            _buildAnalyticsCard('Collection Rate', '${((totalPaid/totalRevenue)*100).toStringAsFixed(1)}%', Icons.trending_up, Colors.purple),
          ],
        ),
        SizedBox(height: 20),
        _buildAnalyticsSection(
          'Fleet Performance',
          Icons.directions_car,
          Colors.blue,
          [
            _buildAnalyticsCard('Total Distance', '${totalDistance.toStringAsFixed(0)} km', Icons.route, Colors.purple),
            _buildAnalyticsCard('Total Trips', '$totalTrips', Icons.local_shipping, Colors.blue),
            _buildAnalyticsCard('Fuel Consumed', '${totalFuel.toStringAsFixed(0)} L', Icons.local_gas_station, Colors.orange),
            _buildAnalyticsCard('Avg Distance/Trip', '${(totalDistance/totalTrips).toStringAsFixed(1)} km', Icons.speed, Colors.teal),
          ],
        ),
        SizedBox(height: 20),
        _buildAnalyticsSection(
          'Revenue Insights',
          Icons.analytics,
          Colors.orange,
          [
            _buildAnalyticsCard('Revenue/Trip', _formatCurrency(avgRevenuePerTrip), Icons.trip_origin, Colors.indigo),
            _buildAnalyticsCard('Revenue/km', _formatCurrency(avgRevenuePerKm), Icons.straighten, Colors.cyan),
            _buildAnalyticsCard('Avg Invoice Value', _formatCurrency(totalRevenue/_invoices.length), Icons.receipt, Colors.pink),
            _buildAnalyticsCard('GST Collected', _formatCurrency(_invoices.fold(0.0, (sum, inv) => sum + (inv['gstAmount'] as num).toDouble())), Icons.account_balance, Colors.deepOrange),
          ],
        ),
        SizedBox(height: 20),
        _buildVehicleTypeDistribution(),
        SizedBox(height: 20),
        _buildOrganizationRevenue(),
      ],
    );
  }

  Widget _buildAnalyticsSection(String title, IconData icon, Color color, List<Widget> cards) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 24),
            SizedBox(width: 8),
            Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])),
          ],
        ),
        SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.2,
          children: cards,
        ),
      ],
    );
  }

  Widget _buildAnalyticsCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.1), blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
          SizedBox(height: 2),
          Text(title, style: TextStyle(fontSize: 11, color: Colors.grey[600]), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildVehicleTypeDistribution() {
    Map<String, Map<String, dynamic>> vehicleStats = {};
    
    for (var invoice in _invoices) {
      for (var vehicle in invoice['vehicles']) {
        String type = vehicle['type'];
        if (!vehicleStats.containsKey(type)) {
          vehicleStats[type] = {'count': 0, 'distance': 0.0, 'cost': 0.0, 'trips': 0};
        }
        vehicleStats[type]!['count'] += vehicle['count'] as int;
        vehicleStats[type]!['distance'] += (vehicle['distance'] as num).toDouble();
        vehicleStats[type]!['cost'] += (vehicle['cost'] as num).toDouble();
        vehicleStats[type]!['trips'] += vehicle['trips'] as int;
      }
    }

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart, color: Colors.purple[700]),
              SizedBox(width: 8),
              Text('Vehicle Type Distribution', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 16),
          ...vehicleStats.entries.map((entry) {
            return Container(
              margin: EdgeInsets.only(bottom: 12),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(entry.key, style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${entry.value['count']} units', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${entry.value['trips']} trips', style: TextStyle(fontSize: 12)),
                      Text('${entry.value['distance'].toStringAsFixed(0)} km', style: TextStyle(fontSize: 12)),
                      Text(_formatCurrency(entry.value['cost']), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue[700])),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildOrganizationRevenue() {
    Map<String, Map<String, dynamic>> orgStats = {};
    
    for (var invoice in _invoices) {
      String orgName = invoice['organizationName'];
      if (!orgStats.containsKey(orgName)) {
        orgStats[orgName] = {
          'totalRevenue': 0.0,
          'totalPaid': 0.0,
          'invoiceCount': 0,
          'contractId': invoice['contractId'],
        };
      }
      orgStats[orgName]!['totalRevenue'] += (invoice['totalAmount'] as num).toDouble();
      orgStats[orgName]!['totalPaid'] += (invoice['amountPaid'] as num).toDouble();
      orgStats[orgName]!['invoiceCount'] += 1;
    }

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.business, color: Colors.indigo[700]),
              SizedBox(width: 8),
              Text('Organization-wise Revenue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 16),
          ...orgStats.entries.map((entry) {
            double collectionRate = (entry.value['totalPaid'] / entry.value['totalRevenue']) * 100;
            return Container(
              margin: EdgeInsets.only(bottom: 12),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          entry.key,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                      Text(
                        _formatCurrency(entry.value['totalRevenue']),
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[700]),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Contract: ${entry.value['contractId']}', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      Text('${entry.value['invoiceCount']} invoices', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: collectionRate / 100,
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            collectionRate > 80 ? Colors.green : collectionRate > 50 ? Colors.orange : Colors.red,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        '${collectionRate.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: collectionRate > 80 ? Colors.green : collectionRate > 50 ? Colors.orange : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Collected: ${_formatCurrency(entry.value['totalPaid'])}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // ============================================================================
  // AUDIT LOGS TAB
  // ============================================================================

  Widget _buildAuditLogsTab() {
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(Icons.history, color: Colors.purple[700], size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Audit Trail', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Text('Complete history of all system activities', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.purple[50],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.purple[200]!),
              ),
              child: Text(
                '${_auditLogs.length} entries',
                style: TextStyle(color: Colors.purple[700], fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
        SizedBox(height: 20),
        if (_auditLogs.isEmpty)
          Center(
            child: Column(
              children: [
                SizedBox(height: 60),
                Icon(Icons.history, size: 80, color: Colors.grey[300]),
                SizedBox(height: 16),
                Text('No audit logs yet', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                SizedBox(height: 8),
                Text('Activity will be tracked here', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          )
        else
          ..._auditLogs.reversed.map((log) => _buildAuditLogCard(log)).toList(),
      ],
    );
  }

  Widget _buildAuditLogCard(Map<String, dynamic> log) {
    Color actionColor;
    IconData actionIcon;
    
    switch (log['action']) {
      case 'created':
        actionColor = Colors.green;
        actionIcon = Icons.add_circle;
        break;
      case 'modified':
        actionColor = Colors.blue;
        actionIcon = Icons.edit;
        break;
      case 'approved':
        actionColor = Colors.purple;
        actionIcon = Icons.check_circle;
        break;
      case 'cancelled':
      case 'deleted':
        actionColor = Colors.red;
        actionIcon = Icons.cancel;
        break;
      case 'payment_recorded':
        actionColor = Colors.green;
        actionIcon = Icons.payment;
        break;
      default:
        actionColor = Colors.grey;
        actionIcon = Icons.info;
    }

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: actionColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(actionIcon, color: actionColor, size: 20),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        log['action'].toString().toUpperCase(),
                        style: TextStyle(fontWeight: FontWeight.bold, color: actionColor, fontSize: 12),
                      ),
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          log['entityType'].toString(),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    'ID: ${log['entityId']}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'By ${log['userName']} (${log['userId']})',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  SizedBox(height: 4),
                  Text(
                    DateFormat('dd MMM yyyy, hh:mm a').format(log['timestamp'] as DateTime),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                  if (log['remarks'] != null) ...[
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        log['remarks'].toString(),
                        style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // DIALOG ACTIONS
  // ============================================================================

  void _showGenerateInvoiceDialog() {
    String? selectedOrgId;
    String? selectedContractId;
    DateTime selectedStartDate = DateTime.now().subtract(Duration(days: 30));
    DateTime selectedEndDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final selectedContract = selectedContractId != null 
              ? _getContractById(selectedContractId!) 
              : null;

          return AlertDialog(
            title: Text('Generate New Invoice'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select Contract', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    hint: Text('Choose contract'),
                    value: selectedContractId,
                    items: _activeContracts.map((contract) {
                      return DropdownMenuItem<String>(
                        value: contract['contractId'],
                        child: Text(
                          '${contract['contractId']} - ${contract['organizationName']}',
                          style: TextStyle(fontSize: 13),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedContractId = value;
                        if (value != null) {
                          final contract = _getContractById(value);
                          selectedOrgId = contract?['organizationId'];
                        }
                      });
                    },
                  ),
                  if (selectedContract != null) ...[
                    SizedBox(height: 16),
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Contract Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          SizedBox(height: 8),
                          Text('Billing Cycle: ${selectedContract['terms']['billingCycle']}', style: TextStyle(fontSize: 11)),
                          Text('Payment Terms: Net ${selectedContract['terms']['paymentDueDays']} days', style: TextStyle(fontSize: 11)),
                          Text('Min Amount: ${_formatCurrency(selectedContract['terms']['monthlyMinimum'])}', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    Text('Billing Period', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              labelText: 'Start Date',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.calendar_today, size: 18),
                              contentPadding: EdgeInsets.all(12),
                            ),
                            readOnly: true,
                            controller: TextEditingController(
                              text: DateFormat('dd MMM yyyy').format(selectedStartDate),
                            ),
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: selectedStartDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (date != null) {
                                setDialogState(() {
                                  selectedStartDate = date;
                                });
                              }
                            },
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              labelText: 'End Date',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.calendar_today, size: 18),
                              contentPadding: EdgeInsets.all(12),
                            ),
                            readOnly: true,
                            controller: TextEditingController(
                              text: DateFormat('dd MMM yyyy').format(selectedEndDate),
                            ),
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: selectedEndDate,
                                firstDate: selectedStartDate,
                                lastDate: DateTime.now(),
                              );
                              if (date != null) {
                                setDialogState(() {
                                  selectedEndDate = date;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selectedContractId == null
                    ? null
                    : () {
                        Navigator.pop(context);
                        _generateInvoice(selectedContractId!, selectedStartDate, selectedEndDate);
                      },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700]),
                child: Text('Generate Invoice'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _generateInvoice(String contractId, DateTime startDate, DateTime endDate) {
    final contract = _getContractById(contractId);
    if (contract == null) return;

    // Log audit entry
    _logAuditEntry(
      entityType: 'invoice',
      entityId: 'INV-${DateTime.now().millisecondsSinceEpoch}',
      action: 'created',
      changes: {
        'contractId': contractId,
        'billingPeriod': '${DateFormat('dd-MM-yyyy').format(startDate)} to ${DateFormat('dd-MM-yyyy').format(endDate)}',
      },
      remarks: 'Invoice generated from contract $contractId',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Invoice generated successfully from contract $contractId'),
        backgroundColor: Colors.green,
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Colors.white,
          onPressed: () {
            _tabController.animateTo(0);
          },
        ),
      ),
    );
  }

  void _showCreateContractDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Create New Contract'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: 'Organization Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Contract Duration (Years)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Pricing configuration will be set in the next step',
                  style: TextStyle(fontSize: 12, color: Colors.blue[900]),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _logAuditEntry(
                entityType: 'contract',
                entityId: 'CNT-${DateTime.now().millisecondsSinceEpoch}',
                action: 'created',
                changes: {'status': 'draft'},
                remarks: 'New contract created',
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Contract created successfully!'), backgroundColor: Colors.green),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
            child: Text('Create'),
          ),
        ],
      ),
    );
  }

  void _editContract(Map<String, dynamic> contract) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Contract'),
        content: Text('Edit functionality for ${contract['contractId']}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _logAuditEntry(
                entityType: 'contract',
                entityId: contract['contractId'],
                action: 'modified',
                changes: {'field': 'updated'},
                remarks: 'Contract details updated',
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Contract updated!'), backgroundColor: Colors.blue),
              );
            },
            child: Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  void _viewContract(Map<String, dynamic> invoice) {
    final contract = _getContractById(invoice['contractId']);
    if (contract == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Contract not found'), backgroundColor: Colors.red),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(contract['contractId']),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Organization: ${contract['organizationName']}', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Valid: ${contract['startDate']} to ${contract['endDate']}'),
              Text('Status: ${contract['status']}'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Close')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _downloadContractPDF(contract);
            },
            child: Text('Download PDF'),
          ),
        ],
      ),
    );
  }

  void _showInvoiceDetails(Map<String, dynamic> invoice) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.all(24),
          child: ListView(
            controller: controller,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invoice['id'],
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue[700]),
                        ),
                        SizedBox(height: 4),
                        Text(invoice['organizationName'], style: TextStyle(fontSize: 16, color: Colors.grey[700])),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _getStatusColor(invoice['status']).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      invoice['status'],
                      style: TextStyle(
                        color: _getStatusColor(invoice['status']),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              Divider(height: 32, thickness: 2),
              
              // Contract Information
              Text('Contract Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue[700])),
              SizedBox(height: 8),
              _buildDetailRow('Contract ID', invoice['contractId']),
              _buildDetailRow('Billing Cycle', invoice['billingCycle']),
              _buildDetailRow('Payment Terms', invoice['paymentTerms']),
              _buildDetailRow('Billing Period', '${DateFormat('dd MMM').format(DateTime.parse(invoice['billingPeriodStart']))} - ${DateFormat('dd MMM yyyy').format(DateTime.parse(invoice['billingPeriodEnd']))}'),
              
              if (invoice['pricingApplied'] != null) ...[
                Divider(height: 32),
                Text('Pricing Applied', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange[700])),
                SizedBox(height: 8),
                _buildDetailRow('Volume Slab', invoice['pricingApplied']['volumeSlabApplied']),
                _buildDetailRow('Discount', '${invoice['pricingApplied']['discountPercent']}%'),
                _buildDetailRow('Minimum Applied', invoice['pricingApplied']['minimumCommitmentApplied'] ? 'Yes' : 'No'),
              ],
              
              Divider(height: 32),
              Text('Cost Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green[700])),
              SizedBox(height: 8),
              _buildBreakdownItem('Base Charges', invoice['charges']['baseCharges']),
              _buildBreakdownItem('Per KM Charges', invoice['charges']['perKmCharges']),
              _buildBreakdownItem('Fuel Surcharge', invoice['charges']['fuelSurcharge']),
              _buildBreakdownItem('Toll Charges', invoice['charges']['tollCharges']),
              _buildBreakdownItem('Waiting Charges', invoice['charges']['waitingCharges']),
              _buildBreakdownItem('Loading/Unloading', invoice['charges']['loadingUnloadingCharges']),
              
              Divider(height: 24, thickness: 2),
              _buildBreakdownItem('Subtotal', invoice['amount'], bold: true),
              _buildBreakdownItem('GST (18%)', invoice['gstAmount'], bold: true, color: Colors.grey[700]!),
              Divider(height: 24, thickness: 2),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total Amount', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Text(
                    _formatCurrency(invoice['totalAmount']),
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.blue[700]),
                  ),
                ],
              ),
              SizedBox(height: 24),
              
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _downloadInvoicePDF(invoice),
                      icon: Icon(Icons.download),
                      label: Text('Download PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _shareInvoice(invoice),
                      icon: Icon(Icons.share),
                      label: Text('Share'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue[700],
                        padding: EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.blue[700]!),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              
              if (invoice['amountPaid'] < invoice['totalAmount']) ...[
                SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _recordPayment(invoice);
                  },
                  icon: Icon(Icons.payment),
                  label: Text('Record Payment'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownItem(String label, double amount, {bool bold = false, Color? color}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color ?? Colors.grey[700],
              fontSize: 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            _formatCurrency(amount),
            style: TextStyle(
              fontSize: 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: color ?? Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Paid': return Colors.green;
      case 'Partially Paid': return Colors.blue;
      case 'Pending': return Colors.orange;
      case 'Overdue': return Colors.red;
      default: return Colors.grey;
    }
  }

  void _recordPayment(Map<String, dynamic> invoice) {
    final amountDue = invoice['totalAmount'] - invoice['amountPaid'];
    final paymentAmountController = TextEditingController(text: amountDue.toStringAsFixed(2));
    String? selectedPaymentMode = 'Bank Transfer';
    final transactionRefController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Record Payment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Invoice: ${invoice['id']}', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Amount Due: ${_formatCurrency(amountDue)}', style: TextStyle(color: Colors.red[700])),
              SizedBox(height: 16),
              TextField(
                controller: paymentAmountController,
                decoration: InputDecoration(
                  labelText: 'Payment Amount',
                  border: OutlineInputBorder(),
                  prefixText: '₹ ',
                ),
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Payment Mode',
                  border: OutlineInputBorder(),
                ),
                value: selectedPaymentMode,
                items: ['Bank Transfer', 'Cheque', 'Cash', 'Online Payment', 'UPI']
                    .map((mode) => DropdownMenuItem(value: mode, child: Text(mode)))
                    .toList(),
                onChanged: (value) {
                  selectedPaymentMode = value;
                },
              ),
              SizedBox(height: 16),
              TextField(
                controller: transactionRefController,
                decoration: InputDecoration(
                  labelText: 'Transaction Reference',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final paymentAmount = double.tryParse(paymentAmountController.text) ?? 0;
              if (paymentAmount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Please enter a valid payment amount'), backgroundColor: Colors.red),
                );
                return;
              }
              
              Navigator.pop(context);
              
              try {
                // ✅ BACKEND CALL - Record payment via API
                await BillingApiService.recordPayment(
                  invoiceId: invoice['id'],
                  amountPaid: paymentAmount,
                  paymentMode: selectedPaymentMode!,
                  paidDate: DateTime.now(),
                );
                
                // Refresh data to get updated invoice
                await _loadInvoices();
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Payment recorded successfully!'), backgroundColor: Colors.green),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to record payment: $e'), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('Record Payment'),
          ),
        ],
      ),
    );
  }

  void _downloadInvoicePDF(Map<String, dynamic> invoice) async {
    _logAuditEntry(
      entityType: 'invoice',
      entityId: invoice['id'],
      action: 'downloaded',
      changes: {'format': 'PDF'},
      remarks: 'Invoice PDF downloaded',
    );
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading invoice ${invoice['id']} as PDF...'), backgroundColor: Colors.blue),
    );
  }

  void _downloadContractPDF(Map<String, dynamic> contract) async {
    _logAuditEntry(
      entityType: 'contract',
      entityId: contract['contractId'],
      action: 'downloaded',
      changes: {'format': 'PDF'},
      remarks: 'Contract PDF downloaded',
    );
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading contract ${contract['contractId']} as PDF...'), backgroundColor: Colors.blue),
    );
  }

  void _shareInvoice(Map<String, dynamic> invoice) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Share Invoice'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.email, color: Colors.blue),
              title: Text('Email'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Sending invoice via email...')),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.message, color: Colors.green),
              title: Text('WhatsApp'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Sharing invoice via WhatsApp...')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue[700]!,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
      });
    }
  }

  void _showAdvancedFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Advanced Filters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            Text('Vehicle Type', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['All', 'Truck', 'Van', 'Car', 'Bike', 'Heavy Truck', 'Trailer'].map((type) {
                return ChoiceChip(
                  label: Text(type),
                  selected: _selectedVehicleType == type,
                  onSelected: (selected) {
                    setState(() {
                      _selectedVehicleType = type;
                    });
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
            SizedBox(height: 30),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _selectedVehicleType = 'All';
                        _selectedFilter = 'All';
                        _selectedDateRange = null;
                        _searchQuery = '';
                      });
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(color: Colors.red.withOpacity(0.5)),
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Clear Filters'),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _exportAllData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Export Data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.table_chart, color: Colors.green),
              title: Text('Export as Excel'),
              subtitle: Text('All invoice and contract data'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Exporting to Excel...'), backgroundColor: Colors.green),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.picture_as_pdf, color: Colors.red),
              title: Text('Export as PDF'),
              subtitle: Text('Summary report'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Exporting to PDF...'), backgroundColor: Colors.red),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.insert_drive_file, color: Colors.blue),
              title: Text('Export as CSV'),
              subtitle: Text('Raw data export'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Exporting to CSV...'), backgroundColor: Colors.blue),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}