// ============================================================================
// FLEET BANKING DASHBOARD - Main Screen WITH DYNAMIC CARDS & EDIT
// ============================================================================
// File: lib/screens/banking/banking_dashboard.dart
// Features:
// - Dynamic Summary Cards for ALL account types (not just 3)
// - Click-to-edit balance functionality on cards
// - Real-time account data from backend
// - Full CRUD operations (Create, Read, Update, Delete)
// - Trend Bar Graph with filters
// - Active Accounts Table
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:universal_html/html.dart' as html;
import '../app_top_bar.dart';
import 'add_account_dialog.dart';
import 'import_transactions_dialog.dart';
import 'reconciliation_page.dart';
import 'reconciliation_billing.dart'; // <-- ADD THIS LINE
import 'package:abra_fleet/core/services/add_account_service.dart';

// ============================================================================
// MODELS
// ============================================================================

class AccountTypeSummary {
  final String accountType;
  final String displayName;
  final IconData icon;
  final Color color;
  final double totalBalance;
  final int accountCount;
  final List<String> accountIds; // For quick access to accounts

  AccountTypeSummary({
    required this.accountType,
    required this.displayName,
    required this.icon,
    required this.color,
    required this.totalBalance,
    required this.accountCount,
    required this.accountIds,
  });
}

class FleetAccount {
  final String id;
  final String accountType;
  final String accountName;
  final String? accountDetails;
  final String? holderName;
  final double currentBalance;
  final double openingBalance;
  final bool isActive;
  final DateTime? createdAt;
  final Map<String, dynamic>? typeSpecificFields;
  final Map<String, dynamic>? linkedBankDetails;
  final Map<String, dynamic>? customFields;

  FleetAccount({
    required this.id,
    required this.accountType,
    required this.accountName,
    this.accountDetails,
    this.holderName,
    required this.currentBalance,
    required this.openingBalance,
    required this.isActive,
    this.createdAt,
    this.typeSpecificFields,
    this.linkedBankDetails,
    this.customFields,
  });

  factory FleetAccount.fromJson(Map<String, dynamic> json) {
    String? accountDetails;
    
    // Generate account details based on type
    switch (json['accountType']) {
      case 'FUEL_CARD':
        accountDetails = json['typeSpecificFields']?['cardNumber'];
        break;
      case 'BANK':
        accountDetails = json['typeSpecificFields']?['accountNumber'];
        break;
      case 'FASTAG':
        accountDetails = json['typeSpecificFields']?['fastagNumber'];
        break;
    }

    return FleetAccount(
      id: json['_id'] ?? json['id'] ?? '',
      accountType: json['accountType'] ?? '',
      accountName: json['accountName'] ?? '',
      accountDetails: accountDetails,
      holderName: json['holderName'],
      currentBalance: (json['currentBalance'] ?? 0).toDouble(),
      openingBalance: (json['openingBalance'] ?? 0).toDouble(),
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : null,
      typeSpecificFields: json['typeSpecificFields'],
      linkedBankDetails: json['linkedBankDetails'],
      customFields: json['customFields'],
    );
  }
}

class ExpenseTrend {
  final DateTime date;
  final double fuelExpense;
  final double maintenanceExpense;
  final double tollExpense;

  ExpenseTrend({
    required this.date,
    required this.fuelExpense,
    required this.maintenanceExpense,
    required this.tollExpense,
  });
}

// ============================================================================
// BANKING DASHBOARD PAGE
// ============================================================================

class BankingDashboardPage extends StatefulWidget {
  const BankingDashboardPage({Key? key}) : super(key: key);

  @override
  State<BankingDashboardPage> createState() => _BankingDashboardPageState();
}

class _BankingDashboardPageState extends State<BankingDashboardPage> {
  final AddAccountService _accountService = AddAccountService();
  
  bool _isLoading = false;
  String? _errorMessage;

  // Data
  List<FleetAccount> _accounts = [];
  List<AccountTypeSummary> _accountTypeSummaries = [];
  List<ExpenseTrend> _trendData = [];
  List<ExpenseTrend> _filteredTrendData = [];
  
  // Overall stats
  double _totalBalance = 0;
  int _activeAccounts = 0;
  int _totalAccounts = 0;
  
  // Filters
  String _selectedPeriod = 'Last 7 Days';
  final List<String> _periodOptions = [
    'Today',
    'Last 7 Days',
    'Last 30 Days',
    'This Month',
    'Last Month',
    'Custom Range',
  ];
  
  DateTime? _customFromDate;
  DateTime? _customToDate;
  
  // Trend Graph Filters
  String _selectedTrendFilter = 'Daily';
  final List<String> _trendFilterOptions = [
    'Daily',
    'Weekly',
    'Monthly',
    'Date Range',
  ];
  
  DateTime? _trendFromDate;
  DateTime? _trendToDate;
  
  // For bar chart interaction
  int _touchedIndex = -1;

  // Account type configuration
  final Map<String, Map<String, dynamic>> _accountTypeConfig = {
    'FUEL_CARD': {
      'displayName': 'Fuel Card',
      'icon': Icons.local_gas_station,
      'color': Colors.blue,
    },
    'BANK': {
      'displayName': 'Bank Account',
      'icon': Icons.account_balance,
      'color': Colors.green,
    },
    'FASTAG': {
      'displayName': 'FASTag',
      'icon': Icons.toll,
      'color': Colors.orange,
    },
    'PETTY_CASH': {
      'displayName': 'Petty Cash',
      'icon': Icons.payments,
      'color': Colors.purple,
    },
    'DRIVER_ADVANCE': {
      'displayName': 'Driver Advance',
      'icon': Icons.person,
      'color': Colors.indigo,
    },
    'OTHER': {
      'displayName': 'Other',
      'icon': Icons.account_balance_wallet,
      'color': Colors.grey,
    },
  };

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Fetch real accounts from backend
      final accountsData = await _accountService.getAllAccounts();
      
      setState(() {
        _accounts = accountsData.map((json) => FleetAccount.fromJson(json)).toList();
        _calculateSummaries();
        
        // For now, keep mock trend data (will be replaced with actual transaction data)
        _trendData = _getMockTrendData();
        _applyTrendFilter();
        
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
      _showErrorSnackbar('Failed to load accounts: $e');
    }
  }

  void _calculateSummaries() {
    // Group accounts by type
    Map<String, List<FleetAccount>> groupedAccounts = {};
    _totalBalance = 0;
    _activeAccounts = 0;
    _totalAccounts = _accounts.length;
    
    for (var account in _accounts) {
      if (!groupedAccounts.containsKey(account.accountType)) {
        groupedAccounts[account.accountType] = [];
      }
      groupedAccounts[account.accountType]!.add(account);
      
      if (account.isActive) {
        _activeAccounts++;
        _totalBalance += account.currentBalance;
      }
    }
    
    // Create summaries for each account type
    _accountTypeSummaries = [];
    groupedAccounts.forEach((type, accounts) {
      double totalBalance = 0;
      List<String> accountIds = [];
      
      for (var account in accounts) {
        if (account.isActive) {
          totalBalance += account.currentBalance;
        }
        accountIds.add(account.id);
      }
      
      final config = _accountTypeConfig[type] ?? _accountTypeConfig['OTHER']!;
      
      _accountTypeSummaries.add(AccountTypeSummary(
        accountType: type,
        displayName: config['displayName'] ?? type,
        icon: config['icon'] ?? Icons.account_balance_wallet,
        color: config['color'] ?? Colors.grey,
        totalBalance: totalBalance,
        accountCount: accounts.length,
        accountIds: accountIds,
      ));
    });
    
    // Sort by balance (highest first)
    _accountTypeSummaries.sort((a, b) => b.totalBalance.compareTo(a.totalBalance));
  }

  void _applyTrendFilter() {
    setState(() {
      switch (_selectedTrendFilter) {
        case 'Daily':
          _filteredTrendData = _trendData.where((data) {
            return data.date.isAfter(DateTime.now().subtract(const Duration(days: 7)));
          }).toList();
          break;
        case 'Weekly':
          _filteredTrendData = _aggregateWeekly(_trendData);
          break;
        case 'Monthly':
          _filteredTrendData = _aggregateMonthly(_trendData);
          break;
        case 'Date Range':
          if (_trendFromDate != null && _trendToDate != null) {
            _filteredTrendData = _trendData.where((data) {
              return data.date.isAfter(_trendFromDate!) &&
                  data.date.isBefore(_trendToDate!.add(const Duration(days: 1)));
            }).toList();
          } else {
            _filteredTrendData = _trendData;
          }
          break;
        default:
          _filteredTrendData = _trendData;
      }
    });
  }

  List<ExpenseTrend> _aggregateWeekly(List<ExpenseTrend> data) {
    Map<int, List<ExpenseTrend>> weeklyData = {};
    
    for (var trend in data) {
      int weekNumber = _getWeekNumber(trend.date);
      if (!weeklyData.containsKey(weekNumber)) {
        weeklyData[weekNumber] = [];
      }
      weeklyData[weekNumber]!.add(trend);
    }
    
    List<ExpenseTrend> aggregated = [];
    weeklyData.forEach((week, trends) {
      double totalFuel = trends.fold(0, (sum, t) => sum + t.fuelExpense);
      double totalMaintenance = trends.fold(0, (sum, t) => sum + t.maintenanceExpense);
      double totalToll = trends.fold(0, (sum, t) => sum + t.tollExpense);
      
      aggregated.add(ExpenseTrend(
        date: trends.first.date,
        fuelExpense: totalFuel,
        maintenanceExpense: totalMaintenance,
        tollExpense: totalToll,
      ));
    });
    
    return aggregated;
  }

  List<ExpenseTrend> _aggregateMonthly(List<ExpenseTrend> data) {
    Map<String, List<ExpenseTrend>> monthlyData = {};
    
    for (var trend in data) {
      String monthKey = DateFormat('yyyy-MM').format(trend.date);
      if (!monthlyData.containsKey(monthKey)) {
        monthlyData[monthKey] = [];
      }
      monthlyData[monthKey]!.add(trend);
    }
    
    List<ExpenseTrend> aggregated = [];
    monthlyData.forEach((month, trends) {
      double totalFuel = trends.fold(0, (sum, t) => sum + t.fuelExpense);
      double totalMaintenance = trends.fold(0, (sum, t) => sum + t.maintenanceExpense);
      double totalToll = trends.fold(0, (sum, t) => sum + t.tollExpense);
      
      aggregated.add(ExpenseTrend(
        date: trends.first.date,
        fuelExpense: totalFuel,
        maintenanceExpense: totalMaintenance,
        tollExpense: totalToll,
      ));
    });
    
    return aggregated;
  }

  int _getWeekNumber(DateTime date) {
    int dayOfYear = int.parse(DateFormat("D").format(date));
    return ((dayOfYear - date.weekday + 10) / 7).floor();
  }

  Future<void> _refreshData() async {
    await _loadDashboardData();
    _showSuccessSnackbar('Data refreshed successfully');
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Banking'),
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildTopBar(),
                      _buildSummaryCards(),
                      _buildTrendGraph(),
                      _buildActiveAccountsTable(),
                    ],
                  ),
                ),
    );
  }

  // ============================================================================
  // TOP BAR
  // ============================================================================

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Row(
        children: [
          // Back Arrow
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 24),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
          const SizedBox(width: 8),
          
          // Title
          const Text(
            'Fleet Banking Overview',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50),
            ),
          ),
          
          const Spacer(),
          
          // Period Filter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              value: _selectedPeriod,
              underline: const SizedBox(),
              icon: const Icon(Icons.arrow_drop_down),
              items: _periodOptions.map((period) {
                return DropdownMenuItem(
                  value: period,
                  child: Text(
                    period,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedPeriod = value!;
                });
                if (value != 'Custom Range') {
                  _loadDashboardData();
                } else {
                  _showCustomDateRangePicker();
                }
              },
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Refresh Button
          IconButton(
            icon: const Icon(Icons.refresh, size: 24),
            onPressed: _isLoading ? null : _refreshData,
            tooltip: 'Refresh',
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey[200],
              padding: const EdgeInsets.all(12),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Add Account Button
          ElevatedButton.icon(
            onPressed: _showAddAccountDialog,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Add Account'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Import Transactions Button
          ElevatedButton.icon(
            onPressed: _showImportTransactionsDialog,
            icon: const Icon(Icons.upload_file, size: 20),
            label: const Text('Import Transactions'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27AE60),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // SUMMARY CARDS - DYNAMIC FOR ALL ACCOUNT TYPES
  // ============================================================================

  Widget _buildSummaryCards() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overall stats row
          Row(
            children: [
              _buildOverallStatCard(
                'Total Balance',
                '₹${_totalBalance.toStringAsFixed(2)}',
                Icons.account_balance_wallet,
                Colors.indigo,
              ),
              const SizedBox(width: 16),
              _buildOverallStatCard(
                'Active Accounts',
                '$_activeAccounts of $_totalAccounts',
                Icons.verified,
                Colors.teal,
              ),
              const SizedBox(width: 16),
              _buildOverallStatCard(
                'All Accounts',
                '$_totalAccounts accounts',
                Icons.list,
                Colors.orange,
              ),
            ],
          ),
          
          if (_accountTypeSummaries.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            
            // Section Header
            Row(
              children: [
                const Text(
                  'Balance by Account Type',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C3E50),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Click on any card to edit balances',
                  child: Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Dynamic account type cards in a single row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _accountTypeSummaries.map((summary) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: _buildAccountTypeSummaryCard(summary),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOverallStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountTypeSummaryCard(AccountTypeSummary summary) {
    return InkWell(
      onTap: () => _showAccountTypeDetails(summary),
      child: Container(
        width: 280, // Fixed width for horizontal scrolling
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: summary.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: summary.color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: summary.color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(summary.icon, size: 28, color: summary.color),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: summary.color.withOpacity(0.3)),
                  ),
                  child: Text(
                    '${summary.accountCount} ${summary.accountCount == 1 ? 'account' : 'accounts'}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: summary.color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              summary.displayName,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '₹${summary.totalBalance.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: summary.color,
                    ),
                  ),
                ),
                Icon(
                  Icons.edit,
                  size: 16,
                  color: summary.color.withOpacity(0.6),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // ACCOUNT TYPE DETAILS DIALOG (Click to Edit)
  // ============================================================================

  void _showAccountTypeDetails(AccountTypeSummary summary) {
    // Get all accounts of this type
    final accountsOfType = _accounts.where((acc) => 
      summary.accountIds.contains(acc.id)
    ).toList();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          width: 700,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: summary.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(summary.icon, color: summary.color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.displayName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2C3E50),
                          ),
                        ),
                        Text(
                          'Total: ₹${summary.totalBalance.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: summary.color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Accounts List
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: accountsOfType.length,
                  separatorBuilder: (context, index) => const Divider(height: 24),
                  itemBuilder: (context, index) {
                    final account = accountsOfType[index];
                    return _buildAccountDetailRow(account, summary.color);
                  },
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Add Account Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showAddAccountDialog();
                  },
                  icon: const Icon(Icons.add),
                  label: Text('Add New ${summary.displayName}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: summary.color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountDetailRow(FleetAccount account, Color themeColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: themeColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: themeColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.accountName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    if (account.accountDetails != null)
                      Text(
                        account.accountDetails!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: account.isActive ? Colors.green[100] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  account.isActive ? 'Active' : 'Inactive',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: account.isActive ? Colors.green[800] : Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildBalanceField(
                  'Current Balance',
                  account.currentBalance,
                  themeColor,
                  () => _quickEditBalance(account, 'current'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildBalanceField(
                  'Opening Balance',
                  account.openingBalance,
                  Colors.grey[600]!,
                  () => _quickEditBalance(account, 'opening'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showEditAccountDialog(account);
                },
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _confirmDeleteAccount(account);
                },
                icon: const Icon(Icons.delete, size: 16),
                label: const Text('Delete'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceField(String label, double amount, Color color, VoidCallback onEdit) {
    return InkWell(
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Icon(Icons.edit, size: 12, color: Colors.grey[400]),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '₹${amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // QUICK EDIT BALANCE DIALOG
  // ============================================================================

  void _quickEditBalance(FleetAccount account, String balanceType) {
    final controller = TextEditingController(
      text: balanceType == 'current' 
          ? account.currentBalance.toStringAsFixed(2)
          : account.openingBalance.toStringAsFixed(2)
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${balanceType == 'current' ? 'Current' : 'Opening'} Balance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              account.accountName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: controller,
              decoration: InputDecoration(
                labelText: '${balanceType == 'current' ? 'Current' : 'Opening'} Balance',
                prefixIcon: const Icon(Icons.currency_rupee),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newBalance = double.tryParse(controller.text);
              if (newBalance != null) {
                try {
                  final updateData = {
                    'accountName': account.accountName,
                    'holderName': account.holderName,
                    if (balanceType == 'current')
                      'currentBalance': newBalance
                    else
                      'openingBalance': newBalance,
                    if (balanceType == 'current')
                      'openingBalance': account.openingBalance
                    else
                      'currentBalance': account.currentBalance,
                  };

                  await _accountService.updateAccount(account.id, updateData);
                  
                  Navigator.pop(context);
                  _showSuccessSnackbar('Balance updated successfully');
                  _refreshData();
                } catch (e) {
                  _showErrorSnackbar('Failed to update balance: $e');
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // TREND GRAPH (BAR CHART)
  // ============================================================================

  Widget _buildTrendGraph() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Expense Trends',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
              ),
              const Spacer(),
              
              // Trend Filter Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: _selectedTrendFilter,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.arrow_drop_down, size: 20),
                  items: _trendFilterOptions.map((filter) {
                    return DropdownMenuItem(
                      value: filter,
                      child: Text(
                        filter,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedTrendFilter = value!;
                    });
                    if (value == 'Date Range') {
                      _showTrendDateRangePicker();
                    } else {
                      _applyTrendFilter();
                    }
                  },
                ),
              ),
              
              const SizedBox(width: 16),
              _buildLegendItem('Fuel', Colors.blue),
              const SizedBox(width: 16),
              _buildLegendItem('Maintenance', Colors.orange),
              const SizedBox(width: 16),
              _buildLegendItem('Toll', Colors.green),
            ],
          ),
          const SizedBox(height: 24),
          
          // Bar Chart
          SizedBox(
            height: 300,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: _getMaxYValue(),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: Colors.blueGrey.withOpacity(0.9),
                    tooltipPadding: const EdgeInsets.all(8),
                    tooltipMargin: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      String expenseType;
                      switch (rodIndex) {
                        case 0:
                          expenseType = 'Fuel';
                          break;
                        case 1:
                          expenseType = 'Maintenance';
                          break;
                        case 2:
                          expenseType = 'Toll';
                          break;
                        default:
                          expenseType = '';
                      }
                      return BarTooltipItem(
                        '$expenseType\n₹${rod.toY.toStringAsFixed(0)}',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                  touchCallback: (FlTouchEvent event, barTouchResponse) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          barTouchResponse == null ||
                          barTouchResponse.spot == null) {
                        _touchedIndex = -1;
                        return;
                      }
                      _touchedIndex = barTouchResponse.spot!.touchedBarGroupIndex;
                    });
                  },
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= 0 && value.toInt() < _filteredTrendData.length) {
                          final date = _filteredTrendData[value.toInt()].date;
                          String dateLabel;
                          
                          switch (_selectedTrendFilter) {
                            case 'Daily':
                              dateLabel = DateFormat('dd MMM').format(date);
                              break;
                            case 'Weekly':
                              dateLabel = 'Week ${_getWeekNumber(date)}';
                              break;
                            case 'Monthly':
                              dateLabel = DateFormat('MMM yyyy').format(date);
                              break;
                            case 'Date Range':
                              dateLabel = DateFormat('dd MMM').format(date);
                              break;
                            default:
                              dateLabel = DateFormat('dd MMM').format(date);
                          }
                          
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              dateLabel,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '₹${(value / 1000).toStringAsFixed(0)}K',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 5000,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey[200]!,
                      strokeWidth: 1,
                    );
                  },
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: Colors.grey[300]!),
                ),
                barGroups: _filteredTrendData.asMap().entries.map((entry) {
                  final index = entry.key;
                  final data = entry.value;
                  final isTouched = index == _touchedIndex;
                  
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: data.fuelExpense,
                        color: Colors.blue,
                        width: isTouched ? 20 : 16,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: _getMaxYValue(),
                          color: Colors.grey[200],
                        ),
                      ),
                      BarChartRodData(
                        toY: data.maintenanceExpense,
                        color: Colors.orange,
                        width: isTouched ? 20 : 16,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                      ),
                      BarChartRodData(
                        toY: data.tollExpense,
                        color: Colors.green,
                        width: isTouched ? 20 : 16,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                      ),
                    ],
                    barsSpace: 4,
                  );
                }).toList(),
              ),
            ),
          ),
          
          // Display selected data details
          if (_touchedIndex >= 0 && _touchedIndex < _filteredTrendData.length)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Details for ${DateFormat('dd MMM yyyy').format(_filteredTrendData[_touchedIndex].date)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildExpenseDetail(
                        'Fuel',
                        _filteredTrendData[_touchedIndex].fuelExpense,
                        Colors.blue,
                      ),
                      _buildExpenseDetail(
                        'Maintenance',
                        _filteredTrendData[_touchedIndex].maintenanceExpense,
                        Colors.orange,
                      ),
                      _buildExpenseDetail(
                        'Toll',
                        _filteredTrendData[_touchedIndex].tollExpense,
                        Colors.green,
                      ),
                      _buildExpenseDetail(
                        'Total',
                        _filteredTrendData[_touchedIndex].fuelExpense +
                            _filteredTrendData[_touchedIndex].maintenanceExpense +
                            _filteredTrendData[_touchedIndex].tollExpense,
                        Colors.purple,
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExpenseDetail(String label, double amount, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '₹${amount.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  double _getMaxYValue() {
    if (_filteredTrendData.isEmpty) return 25000;
    
    double max = 0;
    for (var data in _filteredTrendData) {
      double dayMax = [data.fuelExpense, data.maintenanceExpense, data.tollExpense]
          .reduce((a, b) => a > b ? a : b);
      if (dayMax > max) max = dayMax;
    }
    
    // Round up to nearest 5000
    return ((max / 5000).ceil() * 5000).toDouble();
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  void _showTrendDateRangePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _trendFromDate != null && _trendToDate != null
          ? DateTimeRange(start: _trendFromDate!, end: _trendToDate!)
          : null,
    );
    
    if (picked != null) {
      setState(() {
        _trendFromDate = picked.start;
        _trendToDate = picked.end;
      });
      _applyTrendFilter();
    }
  }

  // ============================================================================
  // ACTIVE ACCOUNTS TABLE
  // ============================================================================

  Widget _buildActiveAccountsTable() {
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF34495E),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                _buildTableHeader('Account Type', flex: 2),
                _buildTableHeader('Account Name', flex: 2),
                _buildTableHeader('Holder Name', flex: 2),
                _buildTableHeader('Current Balance', flex: 2),
                _buildTableHeader('Opening Balance', flex: 2),
                _buildTableHeader('Status', flex: 1),
                _buildTableHeader('Actions', flex: 2),
              ],
            ),
          ),
          
          // Table Rows
          if (_accounts.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No accounts found',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Click "Add Account" to create your first account',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _accounts.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: Colors.grey[200],
              ),
              itemBuilder: (context, index) {
                return _buildAccountRow(_accounts[index]);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildAccountRow(FleetAccount account) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // Account Type
          Expanded(
            flex: 2,
            child: Row(
              children: [
                _getAccountIcon(account.accountType),
                const SizedBox(width: 8),
                Text(
                  _formatAccountType(account.accountType),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          
          // Account Name
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.accountName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C3E50),
                  ),
                ),
                if (account.accountDetails != null)
                  Text(
                    account.accountDetails!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
          
          // Holder Name
          Expanded(
            flex: 2,
            child: Text(
              account.holderName ?? '-',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ),
          
          // Current Balance
          Expanded(
            flex: 2,
            child: Text(
              '₹${account.currentBalance.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF27AE60),
              ),
            ),
          ),
          
          // Opening Balance
          Expanded(
            flex: 2,
            child: Text(
              '₹${account.openingBalance.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ),
          
          // Status
          Expanded(
            flex: 1,
            child: _buildStatusBadge(account.isActive),
          ),
          
          // Actions
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // Edit Button
                IconButton(
                  onPressed: () => _showEditAccountDialog(account),
                  icon: const Icon(Icons.edit, size: 18),
                  tooltip: 'Edit Account',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.blue[50],
                    foregroundColor: Colors.blue[700],
                  ),
                ),
                const SizedBox(width: 8),
                
                // Delete Button
                IconButton(
                  onPressed: () => _confirmDeleteAccount(account),
                  icon: const Icon(Icons.delete, size: 18),
                  tooltip: 'Delete Account',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red[50],
                    foregroundColor: Colors.red[700],
                  ),
                ),
                const SizedBox(width: 8),
                
                // Toggle Status Button
                IconButton(
                  onPressed: () => _toggleAccountStatus(account),
                  icon: Icon(
                    account.isActive ? Icons.block : Icons.check_circle,
                    size: 18,
                  ),
                  tooltip: account.isActive ? 'Deactivate' : 'Activate',
                  style: IconButton.styleFrom(
                    backgroundColor: account.isActive 
                        ? Colors.orange[50] 
                        : Colors.green[50],
                    foregroundColor: account.isActive 
                        ? Colors.orange[700] 
                        : Colors.green[700],
                  ),
                ),
                const SizedBox(width: 8),
                
                // Reconcile Button
                IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ReconciliationBillingPage(  // <-- NEW
                          accountId: account.id,
                          accountName: account.accountName,
                          accountType: account.accountType,
                        ),
                      ),
                    ).then((result) {
                      if (result == true) {
                        _refreshData(); // Refresh dashboard after reconciliation
                      }
                    });
                  },
                  icon: const Icon(Icons.compare_arrows, size: 18),
                  tooltip: 'Reconcile Account',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.purple[50],
                    foregroundColor: Colors.purple[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? Colors.green[100] : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? Icons.check_circle : Icons.cancel,
            size: 14,
            color: isActive ? Colors.green[800] : Colors.grey[600],
          ),
          const SizedBox(width: 4),
          Text(
            isActive ? 'Active' : 'Inactive',
            style: TextStyle(
              color: isActive ? Colors.green[800] : Colors.grey[600],
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _getAccountIcon(String accountType) {
    final config = _accountTypeConfig[accountType] ?? _accountTypeConfig['OTHER']!;
    final icon = config['icon'] as IconData;
    final color = config['color'] as Color;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }

  String _formatAccountType(String accountType) {
    final config = _accountTypeConfig[accountType];
    return config?['displayName'] ?? accountType;
  }

  // ============================================================================
  // ACTIONS
  // ============================================================================

  void _showAddAccountDialog() async {
    final result = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AddAccountDialog(),
    );
    
    if (result != null) {
      _refreshData();
    }
  }

  void _showEditAccountDialog(FleetAccount account) async {
    final result = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => EditAccountDialog(account: account),
    );
    
    if (result != null) {
      _refreshData();
    }
  }

  void _confirmDeleteAccount(FleetAccount account) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: Text(
          'Are you sure you want to delete "${account.accountName}"?\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteAccount(account);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount(FleetAccount account) async {
    try {
      setState(() => _isLoading = true);
      
      final success = await _accountService.deleteAccount(account.id);
      
      if (success) {
        _showSuccessSnackbar('Account deleted successfully');
        _refreshData();
      }
    } catch (e) {
      _showErrorSnackbar('Failed to delete account: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleAccountStatus(FleetAccount account) async {
    try {
      setState(() => _isLoading = true);
      
      await _accountService.updateAccountStatus(account.id, !account.isActive);
      
      _showSuccessSnackbar(
        account.isActive 
            ? 'Account deactivated successfully' 
            : 'Account activated successfully'
      );
      _refreshData();
    } catch (e) {
      _showErrorSnackbar('Failed to update account status: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showImportTransactionsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ImportTransactionsDialog(),
    );
  }

  void _showCustomDateRangePicker() async {
    _showErrorSnackbar('Custom date range - Coming soon!');
  }

  // ============================================================================
  // ERROR STATE
  // ============================================================================

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text(
            'Error Loading Banking Data',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Unknown error',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _refreshData,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // MOCK DATA
  // ============================================================================

  List<ExpenseTrend> _getMockTrendData() {
    final now = DateTime.now();
    List<ExpenseTrend> data = [];
    
    for (int i = 29; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      data.add(ExpenseTrend(
        date: date,
        fuelExpense: 10000 + (i * 300) + (i % 3 * 1500),
        maintenanceExpense: 4000 + (i * 150) + (i % 4 * 800),
        tollExpense: 800 + (i * 50) + (i % 2 * 200),
      ));
    }
    
    return data;
  }
}

// ============================================================================
// EDIT ACCOUNT DIALOG
// ============================================================================

class EditAccountDialog extends StatefulWidget {
  final FleetAccount account;
  
  const EditAccountDialog({Key? key, required this.account}) : super(key: key);

  @override
  State<EditAccountDialog> createState() => _EditAccountDialogState();
}

class _EditAccountDialogState extends State<EditAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final AddAccountService _accountService = AddAccountService();
  
  late TextEditingController _accountNameController;
  late TextEditingController _holderNameController;
  late TextEditingController _openingBalanceController;
  late TextEditingController _currentBalanceController;
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _accountNameController = TextEditingController(text: widget.account.accountName);
    _holderNameController = TextEditingController(text: widget.account.holderName ?? '');
    _openingBalanceController = TextEditingController(
      text: widget.account.openingBalance.toStringAsFixed(2)
    );
    _currentBalanceController = TextEditingController(
      text: widget.account.currentBalance.toStringAsFixed(2)
    );
  }

  @override
  void dispose() {
    _accountNameController.dispose();
    _holderNameController.dispose();
    _openingBalanceController.dispose();
    _currentBalanceController.dispose();
    super.dispose();
  }

  Future<void> _updateAccount() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final updateData = {
        'accountName': _accountNameController.text.trim(),
        'holderName': _holderNameController.text.trim().isNotEmpty 
            ? _holderNameController.text.trim() 
            : null,
        'openingBalance': double.parse(_openingBalanceController.text.trim()),
        'currentBalance': double.parse(_currentBalanceController.text.trim()),
      };

      await _accountService.updateAccount(widget.account.id, updateData);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3498DB).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.edit,
                      color: Color(0xFF3498DB),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Edit Account',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Account Type (Read-only)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'Account Type: ${_formatAccountType(widget.account.accountType)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Account Name
              TextFormField(
                controller: _accountNameController,
                decoration: InputDecoration(
                  labelText: 'Account Name *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.label),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter account name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Holder Name
              TextFormField(
                controller: _holderNameController,
                decoration: InputDecoration(
                  labelText: 'Holder Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),

              // Opening Balance
              TextFormField(
                controller: _openingBalanceController,
                decoration: InputDecoration(
                  labelText: 'Opening Balance',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.currency_rupee),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter opening balance';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Current Balance
              TextFormField(
                controller: _currentBalanceController,
                decoration: InputDecoration(
                  labelText: 'Current Balance',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.account_balance_wallet),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter current balance';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _updateAccount,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3498DB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Update Account'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatAccountType(String accountType) {
    const accountTypeConfig = {
      'FUEL_CARD': 'Fuel Card',
      'BANK': 'Bank Account',
      'FASTAG': 'FASTag',
      'PETTY_CASH': 'Petty Cash',
      'DRIVER_ADVANCE': 'Driver Advance',
    };
    return accountTypeConfig[accountType] ?? accountType;
  }
}