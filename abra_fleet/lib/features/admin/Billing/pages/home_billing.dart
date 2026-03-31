// ============================================================================
// HOME BILLING DASHBOARD - WITH CLICKABLE CHARTS
// ============================================================================
// File: lib/screens/home_billing.dart
// New Features:
// 1. Clickable Income/Expense bars - tap to view detailed report
// 2. Navigate to monthly breakdown with all calculations
// 3. Interactive chart with touch detection
// ============================================================================

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:abra_fleet/core/services/billing_api_service.dart';
import 'new_invoice.dart';
import 'new_recurring_invoice.dart';
import 'new_payment_page.dart';
import 'income_expense_report.dart'; // ✅ NOW ACTIVE - API method implemented

class HomeBilling extends StatefulWidget {
  const HomeBilling({Key? key}) : super(key: key);

  @override
  State<HomeBilling> createState() => _HomeBillingState();
}

class _HomeBillingState extends State<HomeBilling> {
  bool _isLoading = false;
  String _userName = 'Admin';
  
  // Data from API
  ReceivablesSummary? _receivablesData;
  PayablesSummary? _payablesData;
  CashFlowData? _cashFlowData;
  IncomeExpenseData? _incomeExpenseData;
  ProjectsSummary? _projectsData;
  BankAccountsSummary? _bankAccountsData;
  AccountWatchlist? _watchlistData;
  
  String? _errorMessage;
  String _selectedCashFlowPeriod = 'This Fiscal Year';
  String _selectedIncomeExpensePeriod = 'This Fiscal Year';
  String _selectedIncomeExpenseBasis = 'Accrual';
  String _selectedAccountBasis = 'Accrual';

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadDashboardData();
  }

  void _loadUserData() {
    setState(() {
      _userName = 'Admin';
    });
    debugPrint('👤 Billing User loaded: $_userName');
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      print('📊 Loading billing dashboard data...');
      
      final dashboardSummary = await BillingApiService.getDashboardSummary(
        basis: _selectedIncomeExpenseBasis.toLowerCase(),
      );
      
      setState(() {
        _receivablesData = dashboardSummary.receivables;
        _payablesData = dashboardSummary.payables;
        _cashFlowData = dashboardSummary.cashFlow;
        _incomeExpenseData = dashboardSummary.incomeExpense;
        _projectsData = dashboardSummary.projects;
        _bankAccountsData = dashboardSummary.bankAccounts;
        _watchlistData = dashboardSummary.watchlist;
        _isLoading = false;
      });
      
      print('✅ Dashboard data loaded successfully');
      print('   Monthly data points: ${_cashFlowData?.monthlyData.length ?? 0}');
      
    } catch (e) {
      print('❌ Error loading dashboard data: $e');
      
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load dashboard data: ${e.toString()}'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _loadDashboardData,
            ),
          ),
        );
      }
    }
  }
  
  Future<void> _refreshCashFlow() async {
    try {
      final period = _periodStringToApi(_selectedCashFlowPeriod);
      final cashFlow = await BillingApiService.getCashFlow(period: period);
      
      if (mounted) {
        setState(() {
          _cashFlowData = cashFlow;
        });
      }
    } catch (error) {
      print('❌ Error refreshing cash flow: $error');
    }
  }
  
  Future<void> _refreshIncomeExpense() async {
    try {
      final period = _periodStringToApi(_selectedIncomeExpensePeriod);
      final basis = _selectedIncomeExpenseBasis.toLowerCase();
      final incomeExpense = await BillingApiService.getIncomeExpense(
        period: period,
        basis: basis,
      );
      
      if (mounted) {
        setState(() {
          _incomeExpenseData = incomeExpense;
        });
      }
    } catch (error) {
      print('❌ Error refreshing income and expense: $error');
    }
  }
  
  Future<void> _refreshWatchlist() async {
    try {
      final basis = _selectedAccountBasis.toLowerCase();
      final watchlist = await BillingApiService.getAccountWatchlist(basis: basis);
      
      if (mounted) {
        setState(() {
          _watchlistData = watchlist;
        });
      }
    } catch (error) {
      print('❌ Error refreshing watchlist: $error');
    }
  }
  
  String _periodStringToApi(String displayPeriod) {
    switch (displayPeriod) {
      case 'This Month':
        return 'this_month';
      case 'Last Month':
        return 'last_month';
      case 'This Quarter':
        return 'this_quarter';
      case 'This Fiscal Year':
      default:
        return 'fiscal_year';
    }
  }
  
  // ✅ NEW - Handle chart bar clicks
  void _handleIncomeExpenseBarClick(MonthlyDataPoint dataPoint, bool isIncome) {
    print('📊 Bar clicked: ${dataPoint.month} - ${isIncome ? 'Income' : 'Expense'}');
    
    // Navigate to detailed report screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IncomeExpenseReportScreen(
          month: dataPoint.month,
          type: isIncome ? 'income' : 'expense',
          amount: isIncome ? dataPoint.income : dataPoint.expense,
          basis: _selectedIncomeExpenseBasis.toLowerCase(),
        ),
      ),
    );
  }
  
  void _handleReceivablesNewAction(String action) {
    switch (action) {
      case 'new_invoice':
        _navigateToNewInvoice();
        break;
      case 'new_recurring_invoice':
        _navigateToNewRecurringInvoice();
        break;
      case 'new_customer_payment':
        _navigateToNewCustomerPayment();
        break;
    }
  }
  
  void _handlePayablesNewAction(String action) {
    switch (action) {
      case 'new_bill':
        _navigateToNewBill();
        break;
      case 'new_vendor_payment':
        _navigateToNewVendorPayment();
        break;
      case 'new_recurring_bill':
        _navigateToNewRecurringBill();
        break;
    }
  }
  
  void _navigateToNewInvoice() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NewInvoiceScreen()),
    ).then((result) {
      if (result == true) {
        _loadDashboardData();
      }
    });
  }
  
  void _navigateToNewRecurringInvoice() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NewRecurringInvoiceScreen()),
    ).then((result) {
      if (result == true) {
        _loadDashboardData();
      }
    });
  }
  
  void _navigateToNewCustomerPayment() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NewPaymentPage()),
    ).then((result) {
      if (result == true) {
        _loadDashboardData();
      }
    });
  }

  void _navigateToNewBill() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('New Bill feature coming soon!'),
        backgroundColor: Color(0xFFF39C12),
      ),
    );
  }
  
  void _navigateToNewVendorPayment() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Vendor Payment feature coming soon!'),
        backgroundColor: Color(0xFFF39C12),
      ),
    );
  }
  
  void _navigateToNewRecurringBill() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Recurring Bill feature coming soon!'),
        backgroundColor: Color(0xFFF39C12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F7FA),
      child: Column(
        children: [
          // Header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Icon(Icons.dashboard_outlined, size: 32, color: Colors.grey[700]),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dashboard',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Welcome back, $_userName',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    Icons.refresh,
                    color: _isLoading ? Colors.grey : Colors.blue[700],
                  ),
                  onPressed: _isLoading ? null : _loadDashboardData,
                  tooltip: 'Refresh Dashboard',
                ),
              ],
            ),
          ),

          // Dashboard content
          Expanded(
            child: _buildDashboardContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardContent() {
    if (_isLoading && _receivablesData == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading dashboard data...',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }
    
    if (_errorMessage != null && _receivablesData == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'Failed to load dashboard',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadDashboardData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ROW 1: Receivables and Payables
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildTotalReceivablesCard()),
              const SizedBox(width: 24),
              Expanded(child: _buildTotalPayablesCard()),
            ],
          ),
          const SizedBox(height: 24),
          
          // ROW 2: Income/Expense - WITH CLICKABLE CHART
          _buildIncomeExpenseCard(),
          const SizedBox(height: 24),
          
          // ROW 3: Cash Flow
          _buildCashFlowCard(),
          const SizedBox(height: 24),

          // ROW 4: Projects and Bank Cards
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildProjectsCard()),
              const SizedBox(width: 24),
              Expanded(child: _buildBankCardsCard()),
            ],
          ),
          const SizedBox(height: 24),

          // Row 5: Account Watchlist
          _buildAccountWatchlistCard(),
        ],
      ),
    );
  }

  // ✅ INCOME AND EXPENSE CARD - WITH CLICKABLE CHART
  Widget _buildIncomeExpenseCard() {
    final data = _incomeExpenseData;
    final income = data?.totalIncomeFormatted ?? '₹0.00';
    final expense = data?.totalExpenseFormatted ?? '₹0.00';
    final monthlyData = data?.monthlyData ?? [];
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text(
                  'Income and Expense',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedIncomeExpensePeriod,
                    underline: const SizedBox(),
                    isDense: true,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    items: ['This Fiscal Year', 'This Month', 'Last Month', 'This Quarter']
                        .map((String value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            ))
                        .toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedIncomeExpensePeriod = newValue!;
                      });
                      _refreshIncomeExpense();
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                // Summary row with Accrual/Cash toggle
                Row(
                  children: [
                    // Income
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.green[600],
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Total Income',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            income,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Expense
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.red[600],
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Total Expenses',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            expense,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.red[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Accrual/Cash toggle
                    Row(
                      children: [
                        _buildBasisButton('Accrual', _selectedIncomeExpenseBasis == 'Accrual'),
                        const SizedBox(width: 4),
                        _buildBasisButton('Cash', _selectedIncomeExpenseBasis == 'Cash'),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // ✅ CLICKABLE Monthly bar chart
                Container(
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[200]!),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: GestureDetector(
                    onTapDown: (details) {
                      _handleChartTap(details.localPosition, monthlyData);
                    },
                    child: CustomPaint(
                      size: const Size(double.infinity, 250),
                      painter: MonthlyIncomeExpenseChartPainter(
                        monthlyData: monthlyData,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                
                // Disclaimer
                Text(
                  '* Income and expense values displayed are exclusive of taxes.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ Handle tap on chart to detect which bar was clicked
  void _handleChartTap(Offset tapPosition, List<MonthlyDataPoint> monthlyData) {
    if (monthlyData.isEmpty) return;
    
    const double padding = 40.0;
    final double chartWidth = MediaQuery.of(context).size.width - (48 + 40) * 2; // Account for card padding
    final double barGroupWidth = chartWidth / monthlyData.length;
    final double barWidth = (barGroupWidth / 3).clamp(8.0, 25.0);
    final double barSpacing = barWidth / 2;
    
    // Determine which month was tapped
    final int monthIndex = ((tapPosition.dx - padding) / barGroupWidth).floor();
    
    if (monthIndex >= 0 && monthIndex < monthlyData.length) {
      final dataPoint = monthlyData[monthIndex];
      final double monthCenterX = padding + (monthIndex * barGroupWidth) + (barGroupWidth / 2);
      
      // Determine if income or expense bar was tapped
      final double incomeBarLeft = monthCenterX - barWidth - barSpacing / 2;
      final double incomeBarRight = incomeBarLeft + barWidth;
      final double expenseBarLeft = monthCenterX + barSpacing / 2;
      final double expenseBarRight = expenseBarLeft + barWidth;
      
      if (tapPosition.dx >= incomeBarLeft && tapPosition.dx <= incomeBarRight) {
        // Income bar tapped
        _handleIncomeExpenseBarClick(dataPoint, true);
      } else if (tapPosition.dx >= expenseBarLeft && tapPosition.dx <= expenseBarRight) {
        // Expense bar tapped
        _handleIncomeExpenseBarClick(dataPoint, false);
      }
    }
  }

  // CASH FLOW CARD - (Same as before)
  Widget _buildCashFlowCard() {
    final data = _cashFlowData;
    final incoming = data?.incomingFormatted ?? '₹0.00';
    final outgoing = data?.outgoingFormatted ?? '₹0.00';
    final closing = data?.closingBalanceFormatted ?? '₹0.00';
    final monthlyData = data?.monthlyData ?? [];
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text(
                  'Cash Flow',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedCashFlowPeriod,
                    underline: const SizedBox(),
                    isDense: true,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    items: ['This Fiscal Year', 'This Month', 'Last Month', 'This Quarter']
                        .map((String value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            ))
                        .toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedCashFlowPeriod = newValue!;
                      });
                      _refreshCashFlow();
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Cash as on ${data != null ? _formatDate(data.endDate) : "01/04/2025"}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        closing,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[200]!),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: CustomPaint(
                    size: const Size(double.infinity, 200),
                    painter: MonthlyCashFlowChartPainter(
                      monthlyData: monthlyData,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Legend
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildLegendItem('Incoming', incoming, Colors.green[600]!),
                    const SizedBox(width: 32),
                    _buildLegendItem('Outgoing', outgoing, Colors.red[600]!),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasisButton(String label, bool isSelected) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedIncomeExpenseBasis = label;
        });
        _refreshIncomeExpense();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[700] : Colors.grey[200],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, String value, Color color) {
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
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }
  
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  // [Include all other card widgets from previous version - Receivables, Payables, Projects, Bank Cards, Watchlist]
  // ... (keeping the code concise, but they should all be included)
  
  Widget _buildTotalReceivablesCard() {
    final data = _receivablesData;
    final current = data?.currentFormatted ?? '₹0.00';
    final overdue = data?.overdueFormatted ?? '₹0.00';
    final total = data?.totalFormatted ?? '₹0.00';
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text(
                  'Total Receivables',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  onSelected: _handleReceivablesNewAction,
                  itemBuilder: (BuildContext context) => [
                    const PopupMenuItem<String>(
                      value: 'new_invoice',
                      child: Row(
                        children: [
                          Icon(Icons.receipt_outlined, size: 18, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('New Invoice'),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'new_recurring_invoice',
                      child: Row(
                        children: [
                          Icon(Icons.repeat, size: 18, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('New Recurring Invoice'),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'new_customer_payment',
                      child: Row(
                        children: [
                          Icon(Icons.payment, size: 18, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('New Customer Payment'),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue[700],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.add, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'New',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down, color: Colors.white, size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Unpaid Invoices $total',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildAmountSection('CURRENT', current, Colors.grey[700]!),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildAmountSection('OVERDUE', overdue, Colors.red[700]!),
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

  Widget _buildTotalPayablesCard() {
    final data = _payablesData;
    final current = data?.currentFormatted ?? '₹0.00';
    final overdue = data?.overdueFormatted ?? '₹0.00';
    final total = data?.totalFormatted ?? '₹0.00';
    final overdueAmount = data?.overdue ?? 0.0;
    final totalAmount = data?.total ?? 0.0;
    
    final progressValue = totalAmount > 0 ? (overdueAmount / totalAmount).clamp(0.0, 1.0) : 0.0;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text(
                  'Total Payables',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  onSelected: _handlePayablesNewAction,
                  itemBuilder: (BuildContext context) => [
                    const PopupMenuItem<String>(
                      value: 'new_bill',
                      child: Row(
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 18, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('New Bill'),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'new_vendor_payment',
                      child: Row(
                        children: [
                          Icon(Icons.payment_outlined, size: 18, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('New Vendor Payment'),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'new_recurring_bill',
                      child: Row(
                        children: [
                          Icon(Icons.repeat, size: 18, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('New Recurring Bill'),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue[700],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.add, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'New',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down, color: Colors.white, size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Unpaid Bills $total',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progressValue,
                    minHeight: 8,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange[600]!),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildAmountSection('CURRENT', current, Colors.grey[700]!),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildAmountSection('OVERDUE', overdue, Colors.red[700]!),
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

  Widget _buildAmountSection(String label, String amount, Color amountColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[500],
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Flexible(
              child: Text(
                amount,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: amountColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: Colors.grey[400], size: 24),
          ],
        ),
      ],
    );
  }

  Widget _buildProjectsCard() {
    final data = _projectsData;
    final hasProjects = data != null && data.projects.isNotEmpty;
    
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Projects',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
          ),
          Expanded(
            child: hasProjects
                ? ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: data!.projects.length,
                    itemBuilder: (context, index) {
                      final project = data.projects[index];
                      return ListTile(
                        title: Text(project.name),
                        subtitle: Text(project.status),
                        trailing: Text('₹${(project.remaining ?? 0.0).toStringAsFixed(2)}'),
                      );
                    },
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_outlined, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () {},
                          child: Text(
                            'Add Project(s) to this watchlist',
                            style: TextStyle(color: Colors.blue[700], fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBankCardsCard() {
    final data = _bankAccountsData;
    final hasAccounts = data != null && data.accounts.isNotEmpty;
    
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Bank and Credit Cards',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
          ),
          Expanded(
            child: hasAccounts
                ? ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: data!.accounts.length,
                    itemBuilder: (context, index) {
                      final account = data.accounts[index];
                      return ListTile(
                        title: Text(account.name),
                        subtitle: Text(account.bankName ?? account.type),
                        trailing: Text(account.balanceFormatted),
                      );
                    },
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.account_balance_outlined,
                            size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text(
                          'Yet to add Bank and Credit Card details',
                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {},
                          child: Text(
                            'Add Bank Account',
                            style: TextStyle(color: Colors.blue[700], fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountWatchlistCard() {
    final data = _watchlistData;
    final hasAccounts = data != null && data.accounts.isNotEmpty;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text(
                  'Account Watchlist',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedAccountBasis,
                    underline: const SizedBox(),
                    isDense: true,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    items: ['Accrual', 'Cash'].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedAccountBasis = newValue!;
                      });
                      _refreshWatchlist();
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            child: hasAccounts
                ? Column(
                    children: data!.accounts.map((account) {
                      return ListTile(
                        title: Text(account.name),
                        subtitle: Text(account.type),
                        trailing: Text(account.balanceFormatted),
                      );
                    }).toList(),
                  )
                : Center(
                    child: Column(
                      children: [
                        Icon(Icons.remove_red_eye_outlined,
                            size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text(
                          'No accounts added to watchlist',
                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CUSTOM PAINTERS - MONTHLY CHARTS
// ============================================================================

class MonthlyIncomeExpenseChartPainter extends CustomPainter {
  final List<MonthlyDataPoint> monthlyData;

  MonthlyIncomeExpenseChartPainter({
    required this.monthlyData,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (monthlyData.isEmpty) {
      _drawEmptyState(canvas, size);
      return;
    }

    double maxValue = 0;
    for (var data in monthlyData) {
      maxValue = math.max(maxValue, math.max(data.income, data.expense));
    }
    
    if (maxValue == 0) {
      maxValue = 1000;
    }

    final padding = 40.0;
    final chartWidth = size.width - padding * 2;
    final chartHeight = size.height - padding * 2;
    final barGroupWidth = chartWidth / monthlyData.length;
    final barWidth = (barGroupWidth / 3).clamp(8.0, 25.0);
    final barSpacing = barWidth / 2;

    _drawGridLines(canvas, size, padding);

    for (int i = 0; i < monthlyData.length; i++) {
      final data = monthlyData[i];
      final x = padding + (i * barGroupWidth) + (barGroupWidth / 2);
      
      final incomeHeight = (data.income / maxValue) * chartHeight;
      final incomeY = size.height - padding - incomeHeight;
      
      if (incomeHeight > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              x - barWidth - barSpacing / 2,
              incomeY,
              barWidth,
              incomeHeight,
            ),
            const Radius.circular(3),
          ),
          Paint()..color = Colors.green[600]!,
        );
      }
      
      final expenseHeight = (data.expense / maxValue) * chartHeight;
      final expenseY = size.height - padding - expenseHeight;
      
      if (expenseHeight > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              x + barSpacing / 2,
              expenseY,
              barWidth,
              expenseHeight,
            ),
            const Radius.circular(3),
          ),
          Paint()..color = Colors.red[600]!,
        );
      }
      
      final monthLabel = data.month.split(' ')[0];
      final textPainter = TextPainter(
        text: TextSpan(
          text: monthLabel,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 10,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          x - textPainter.width / 2,
          size.height - padding + 10,
        ),
      );
    }
  }

  void _drawGridLines(Canvas canvas, Size size, double padding) {
    final paint = Paint()
      ..color = Colors.grey[200]!
      ..strokeWidth = 1;

    for (int i = 0; i <= 5; i++) {
      final y = padding + (i * (size.height - padding * 2) / 5);
      canvas.drawLine(
        Offset(padding, y),
        Offset(size.width - padding, y),
        paint,
      );
    }
  }

  void _drawEmptyState(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'No data available',
        style: TextStyle(
          color: Colors.grey[400],
          fontSize: 14,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(MonthlyIncomeExpenseChartPainter oldDelegate) {
    return oldDelegate.monthlyData != monthlyData;
  }
}

class MonthlyCashFlowChartPainter extends CustomPainter {
  final List<MonthlyDataPoint> monthlyData;

  MonthlyCashFlowChartPainter({
    required this.monthlyData,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (monthlyData.isEmpty) {
      _drawEmptyState(canvas, size);
      return;
    }

    double minValue = 0;
    double maxValue = 0;
    
    for (var data in monthlyData) {
      final balance = data.net;
      minValue = math.min(minValue, balance);
      maxValue = math.max(maxValue, balance);
    }
    
    final range = maxValue - minValue;
    if (range == 0) {
      maxValue = 1000;
      minValue = 0;
    } else {
      maxValue += range * 0.1;
      minValue -= range * 0.1;
      if (minValue > 0) minValue = 0;
    }

    final padding = 50.0;
    final chartWidth = size.width - padding * 2;
    final chartHeight = size.height - padding * 2;

    _drawYAxisAndGrid(canvas, size, padding, minValue, maxValue, chartHeight);
    _drawAreaFill(canvas, size, padding, chartWidth, chartHeight, minValue, maxValue);
    _drawBalanceLine(canvas, size, padding, chartWidth, chartHeight, minValue, maxValue);
    _drawXAxisLabels(canvas, size, padding, chartWidth);
  }

  void _drawYAxisAndGrid(Canvas canvas, Size size, double padding,
      double minValue, double maxValue, double chartHeight) {
    final gridPaint = Paint()
      ..color = Colors.grey[200]!
      ..strokeWidth = 1;

    final textStyle = TextStyle(
      color: Colors.grey[600],
      fontSize: 10,
    );

    for (int i = 0; i <= 5; i++) {
      final y = padding + (i * chartHeight / 5);
      
      canvas.drawLine(
        Offset(padding, y),
        Offset(size.width - padding, y),
        gridPaint,
      );
      
      final value = maxValue - (i * (maxValue - minValue) / 5);
      final labelText = _formatCurrency(value);
      
      final textPainter = TextPainter(
        text: TextSpan(
          text: labelText,
          style: textStyle,
        ),
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          5,
          y - textPainter.height / 2,
        ),
      );
    }
  }

  void _drawAreaFill(Canvas canvas, Size size, double padding, double chartWidth,
      double chartHeight, double minValue, double maxValue) {
    if (monthlyData.length < 2) return;
    
    final path = Path();
    final valueRange = maxValue - minValue;
    
    final firstX = padding;
    final bottomY = size.height - padding;
    path.moveTo(firstX, bottomY);
    
    final firstBalance = monthlyData[0].net;
    final firstDataY = size.height - padding - ((firstBalance - minValue) / valueRange) * chartHeight;
    path.lineTo(firstX, firstDataY);
    
    for (int i = 0; i < monthlyData.length; i++) {
      final balance = monthlyData[i].net;
      final x = padding + (i * chartWidth / (monthlyData.length - 1));
      final y = size.height - padding - ((balance - minValue) / valueRange) * chartHeight;
      path.lineTo(x, y);
    }
    
    final lastX = padding + chartWidth;
    path.lineTo(lastX, bottomY);
    path.close();
    
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.blue[100]!.withOpacity(0.4)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawBalanceLine(Canvas canvas, Size size, double padding, double chartWidth,
      double chartHeight, double minValue, double maxValue) {
    if (monthlyData.length < 2) return;
    
    final path = Path();
    final valueRange = maxValue - minValue;
    bool started = false;

    for (int i = 0; i < monthlyData.length; i++) {
      final balance = monthlyData[i].net;
      final x = padding + (i * chartWidth / (monthlyData.length - 1));
      final y = size.height - padding - ((balance - minValue) / valueRange) * chartHeight;

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
      
      canvas.drawCircle(
        Offset(x, y),
        4,
        Paint()
          ..color = Colors.blue[700]!
          ..style = PaintingStyle.fill,
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.blue[700]!
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawXAxisLabels(Canvas canvas, Size size, double padding, double chartWidth) {
    for (int i = 0; i < monthlyData.length; i++) {
      final data = monthlyData[i];
      final x = padding + (i * chartWidth / (monthlyData.length - 1));
      
      if (i % 1 == 0 || monthlyData.length <= 6) {
        final parts = data.month.split(' ');
        final monthLabel = parts.isNotEmpty ? parts[0] : data.month;
        final yearLabel = parts.length > 1 ? parts[1] : '';
        
        final textPainter = TextPainter(
          text: TextSpan(
            children: [
              TextSpan(
                text: monthLabel,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (yearLabel.isNotEmpty)
                TextSpan(
                  text: '\n$yearLabel',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 8,
                  ),
                ),
            ],
          ),
          textAlign: TextAlign.center,
          textDirection: ui.TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(
            x - textPainter.width / 2,
            size.height - padding + 10,
          ),
        );
      }
    }
  }

  String _formatCurrency(double value) {
    if (value.abs() >= 100000) {
      return '${(value / 1000).toStringAsFixed(0)}K';
    } else if (value.abs() >= 10000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    } else {
      return value.toStringAsFixed(0);
    }
  }

  void _drawEmptyState(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'No cash flow data available',
        style: TextStyle(
          color: Colors.grey[400],
          fontSize: 14,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(MonthlyCashFlowChartPainter oldDelegate) {
    return oldDelegate.monthlyData != monthlyData;
  }
}