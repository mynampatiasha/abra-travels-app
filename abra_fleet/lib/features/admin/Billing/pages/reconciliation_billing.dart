// ============================================================================
// RECONCILIATION BILLING PAGE - COMPLETE WITH OPENING BALANCE SUPPORT
// ============================================================================
// File: lib/screens/banking/reconciliation_billing.dart
// 
// NEW FEATURES:
// ✅ Opening Balance Integration
// ✅ Three-Balance Reconciliation (Account, Provider, System)
// ✅ Debit/Credit Column Mapping
// ✅ Expected Closing Balance Calculation
// ✅ Enhanced Balance Summary Cards
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data'; 
import 'package:abra_fleet/core/services/reconciliation_billing_service.dart';
import 'package:abra_fleet/core/services/add_account_service.dart';

class ReconciliationBillingPage extends StatefulWidget {
  final String accountId;
  final String accountName;
  final String accountType;

  const ReconciliationBillingPage({
    Key? key,
    required this.accountId,
    required this.accountName,
    required this.accountType,
  }) : super(key: key);

  @override
  State<ReconciliationBillingPage> createState() => _ReconciliationBillingPageState();
}

class _ReconciliationBillingPageState extends State<ReconciliationBillingPage> {
  final ReconciliationBillingService _reconciliationService = ReconciliationBillingService();
  final AddAccountService _accountService = AddAccountService(); // ← ADD THIS

  bool _isLoading = false;
  bool _isAutoMatching = false;

  // Session
  ReconciliationSessionModel? _session;

  // Date Range
  DateTime _periodStart = DateTime.now().subtract(const Duration(days: 30));
  DateTime _periodEnd = DateTime.now();

  // Data
  List<ProviderTransactionModel> _providerTransactions = [];
  List<Map<String, dynamic>> _systemExpenses = [];
  
  // ✅ NEW: Opening Balance
 // Opening Balance
  double _openingBalance = 0.0;

  // ✅ Phase 3: Opening Balance Verification
  bool _openingBalanceVerified = false;
  double? _statementOpeningBalance;
  double? _openingBalanceDifference;
  String _openingBalanceSeverity = 'none';
  String _openingBalanceMessage = '';
   // Phase 4: Closing Balance Verification
  double? _statementClosingBalance;
  Map<String, dynamic>? _closingBalanceCheckResult;
  // Phase 5: Carry Forward + Adjustment
  final Set<String> _selectedUnmatchedIds = {};
  bool _isResolvingUnmatched = false;

  // Filters
  String _selectedFilter = 'All';
  final List<String> _filterOptions = ['All', 'Matched', 'Unmatched', 'Pending'];

  // Selected items for manual matching
  String? _selectedProviderTxnId;
  String? _selectedSystemExpenseId;

  // Statistics
  double _providerBalance = 0;
  double _systemBalance = 0;
  int _totalMatched = 0;
  int _totalUnmatched = 0;
  int _totalPending = 0;

  @override
  void initState() {
    super.initState();
    _initializeReconciliation();
  }

 Future<void> _initializeReconciliation() async {
    await _startOrGetSession();
    await _loadOpeningBalance();
    _showOpeningBalanceEntryDialog();
  }

  // ✅ NEW METHOD: Load Opening Balance from PaymentAccount
  Future<void> _loadOpeningBalance() async {
    try {
      print('🔍 Loading opening balance for account: ${widget.accountId}');
      final accountData = await _accountService.getAccountById(widget.accountId);
      
      setState(() {
        _openingBalance = (accountData['currentBalance'] ?? 0.0).toDouble();
      });
      
      print('✅ Opening balance loaded: ₹$_openingBalance');
    } catch (e) {
      print('⚠️ Error loading opening balance: $e');
      // Set default to 0 if account balance can't be loaded
      setState(() {
        _openingBalance = 0.0;
      });
    }
  }

  void _showOpeningBalanceEntryDialog() {
    final controller = TextEditingController(
      text: _openingBalance > 0 ? _openingBalance.toStringAsFixed(2) : '',
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.account_balance_wallet, color: Colors.purple),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Enter Statement Opening Balance',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Enter the opening balance shown on your bank/provider statement for this period. System balance is ₹${_openingBalance.toStringAsFixed(2)}.',
                      style: TextStyle(fontSize: 12, color: Colors.blue[900]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Statement Opening Balance *',
                prefixIcon: const Icon(Icons.currency_rupee),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                hintText: 'e.g. ${_openingBalance.toStringAsFixed(2)}',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // User skipped — load data anyway without verification
              _loadReconciliationData();
            },
            child: Text(
              'Skip',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final value = double.tryParse(controller.text);
              if (value == null) return;
              Navigator.pop(context);
              await _verifyOpeningBalance(value);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Verify & Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyOpeningBalance(double statementBalance) async {
    try {
      final result = await _reconciliationService.verifyOpeningBalance(
        accountId: widget.accountId,
        statementOpeningBalance: statementBalance,
      );

      if (result['success']) {
        final data = result['data'];
        setState(() {
          _statementOpeningBalance = statementBalance;
          _openingBalanceDifference = (data['difference'] as num).toDouble();
          _openingBalanceSeverity = data['severity'] ?? 'none';
          _openingBalanceMessage = data['message'] ?? '';
          _openingBalanceVerified = true;
        });

        print('✅ Opening balance verified: ${data['isMatched'] ? 'MATCHED' : 'MISMATCH'}');
      }
    } catch (e) {
      print('⚠️ Opening balance verification failed: $e');
      setState(() {
        _openingBalanceVerified = false;
      });
    } finally {
      // Always load reconciliation data regardless of verification result
      await _loadReconciliationData();
    }
  }

  Future<void> _startOrGetSession() async {
    setState(() => _isLoading = true);

    try {
      // Check if session exists
      final sessions = await _reconciliationService.getAllSessions(
        accountId: widget.accountId,
      );

      // Find active session for current period
      final existingSession = sessions.where((s) =>
        s.periodStart.isAtSameMomentAs(_periodStart) &&
        s.periodEnd.isAtSameMomentAs(_periodEnd) &&
        s.status != 'LOCKED'
      ).firstOrNull;

      if (existingSession != null) {
        setState(() {
          _session = existingSession;
          _isLoading = false;
        });
      } else {
        // Create new session
        final newSession = await _reconciliationService.startReconciliationSession(
          accountId: widget.accountId,
          accountName: widget.accountName,
          accountType: widget.accountType,
          periodStart: _periodStart,
          periodEnd: _periodEnd,
        );

        setState(() {
          _session = newSession;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Failed to initialize reconciliation: $e');
    }
  }

  Future<void> _loadReconciliationData() async {
    setState(() => _isLoading = true);

    try {
      // Load provider transactions
      final providerTxns = await _reconciliationService.getProviderTransactions(
        accountId: widget.accountId,
        startDate: _periodStart,
        endDate: _periodEnd,
      );

      // Load system expenses
      final systemExps = await _reconciliationService.getSystemExpenses(
        accountId: widget.accountId,
        startDate: _periodStart,
        endDate: _periodEnd,
      );

      // Calculate statistics
      _providerBalance = providerTxns.fold(0.0, (sum, txn) => sum + txn.amount);
      _systemBalance = systemExps.fold(0.0, (sum, exp) => sum + (exp['total'] ?? 0).toDouble());
      _totalMatched = providerTxns.where((t) => t.reconciliationStatus == 'MATCHED').length;
      _totalUnmatched = providerTxns.where((t) => t.reconciliationStatus == 'UNMATCHED').length;
      _totalPending = providerTxns.where((t) => t.reconciliationStatus == 'PENDING').length;

      setState(() {
        _providerTransactions = providerTxns;
        _systemExpenses = systemExps;
        _isLoading = false;
      });

      // Refresh session stats
      if (_session != null) {
        _refreshSessionStats();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Failed to load reconciliation data: $e');
    }
  }

  Future<void> _refreshSessionStats() async {
    if (_session == null) return;

    try {
      final updatedSession = await _reconciliationService.getSessionDetails(_session!.id);
      if (updatedSession != null) {
        setState(() {
          _session = updatedSession;
        });
      }
    } catch (e) {
      print('Error refreshing session stats: $e');
    }
  }

  List<ProviderTransactionModel> get _filteredProviderTransactions {
    if (_selectedFilter == 'All') return _providerTransactions;
    if (_selectedFilter == 'Matched') {
      return _providerTransactions.where((t) => t.reconciliationStatus == 'MATCHED').toList();
    }
    if (_selectedFilter == 'Unmatched') {
      return _providerTransactions.where((t) => t.reconciliationStatus == 'UNMATCHED').toList();
    }
    if (_selectedFilter == 'Pending') {
      return _providerTransactions.where((t) => t.reconciliationStatus == 'PENDING').toList();
    }
    return _providerTransactions;
  }

  List<Map<String, dynamic>> get _filteredSystemExpenses {
    if (_selectedFilter == 'All') return _systemExpenses;
    if (_selectedFilter == 'Matched') {
      return _systemExpenses.where((e) => e['providerTransactionId'] != null).toList();
    }
    if (_selectedFilter == 'Unmatched') {
      return _systemExpenses.where((e) => e['providerTransactionId'] == null).toList();
    }
    return _systemExpenses;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : widget.accountType == 'PETTY_CASH'
              ? _buildPettyCashReconciliation()
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildEnhancedBalanceSummary(),
                      _buildOpeningBalanceAlertCard(),
                      _buildFiltersBar(),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildProviderTransactionsList()),
                            Container(
                              width: 80,
                              color: Colors.grey[100],
                              child: _buildMatchingCenter(),
                            ),
                            Expanded(child: _buildSystemExpensesList()),
                          ],
                        ),
                      ),
                      _buildActionBar(),
                    ],
                  ),
                ),
    );
  }

  // ============================================================================
  // APP BAR
  // ============================================================================

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF2C3E50),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reconciliation',
            style: TextStyle(color: Colors.white, fontSize: 20),
          ),
          Text(
            '${widget.accountName} (${DateFormat('dd MMM').format(_periodStart)} - ${DateFormat('dd MMM yyyy').format(_periodEnd)})',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          onPressed: () async {
            await _loadOpeningBalance(); // ← REFRESH OPENING BALANCE TOO
            await _loadReconciliationData();
          },
          tooltip: 'Refresh',
        ),
        IconButton(
          icon: const Icon(Icons.date_range, color: Colors.white),
          onPressed: _showDateRangePicker,
          tooltip: 'Change Period',
        ),
         IconButton(
          icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
          onPressed: _generateReport,
          tooltip: 'View Report',
        ),
        if (widget.accountType != 'PETTY_CASH')
          IconButton(
            icon: const Icon(Icons.upload_file, color: Colors.white),
            onPressed: _showImportDialog,
            tooltip: 'Import Statement',
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ============================================================================
  // ✅ ENHANCED BALANCE SUMMARY WITH 4 BALANCES
  // ============================================================================

  Widget _buildEnhancedBalanceSummary() {
    final providerSystemDifference = _providerBalance - _systemBalance;
    final expectedClosingBalance = _openingBalance - _systemBalance;
    final isBalanced = providerSystemDifference.abs() < 0.01;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ✅ FOUR-BALANCE ROW
          Row(
            children: [
              Expanded(
                child: _buildBalanceCard(
                  'Opening Balance',
                  _openingBalance,
                  Icons.account_balance_wallet,
                  Colors.purple,
                  'Account balance',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildBalanceCard(
                  'Provider Balance',
                  _providerBalance,
                  Icons.cloud_download,
                  Colors.blue,
                  '${_providerTransactions.length} transactions',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildBalanceCard(
                  'System Balance',
                  _systemBalance,
                  Icons.receipt_long,
                  Colors.green,
                  '${_systemExpenses.length} expenses',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildBalanceCard(
                  'Expected Closing',
                  expectedClosingBalance,
                  Icons.trending_down,
                  Colors.teal,
                  'Opening - System',
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // ✅ RECONCILIATION STATUS ROW
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                // Status indicator
                Row(
                  children: [
                    Icon(
                      isBalanced ? Icons.check_circle : Icons.warning_amber,
                      color: isBalanced ? Colors.green : Colors.orange,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isBalanced 
                              ? '✅ Provider & System Balanced' 
                              : '⚠️ Reconciliation Required',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isBalanced ? Colors.green[700] : Colors.orange[700],
                            ),
                          ),
                          Text(
                            isBalanced
                              ? 'Provider and system expenses are reconciled'
                              : 'Difference: ₹${providerSystemDifference.abs().toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Statistics row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem('Matched', _totalMatched, Colors.green),
                    _buildStatDivider(),
                    _buildStatItem('Unmatched', _totalUnmatched, Colors.orange),
                    _buildStatDivider(),
                    _buildStatItem('Pending', _totalPending, Colors.blue),
                    _buildStatDivider(),
                    _buildStatItem('Variance', providerSystemDifference.abs(), Colors.red, isAmount: true),
                  ],
                ),
              ],
            ),
          ),
          
          // ✅ CALCULATION BREAKDOWN (Optional - can be collapsed)
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text(
              'Calculation Breakdown',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCalculationRow('Opening Balance', _openingBalance),
                    _buildCalculationRow('Less: System Expenses', -_systemBalance),
                    const Divider(),
                    _buildCalculationRow('Expected Closing Balance', expectedClosingBalance, isBold: true),
                    const SizedBox(height: 12),
                    _buildCalculationRow('Provider Transactions', _providerBalance),
                    _buildCalculationRow('Difference (Provider - System)', providerSystemDifference, 
                      color: isBalanced ? Colors.green : Colors.red),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalculationRow(String label, double amount, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isBold ? 14 : 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: color ?? Colors.grey[800],
              ),
            ),
          ),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isBold ? 16 : 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color ?? Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(
    String label,
    double amount,
    IconData icon,
    Color color,
    String subtitle,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20), // Smaller icon
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8), // Reduced spacing
          Text(
            label,
            style: TextStyle(
              fontSize: 11, // Smaller font
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 18, // Smaller amount
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10, // Smaller subtitle
              color: Colors.grey[600],
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, dynamic value, Color color, {bool isAmount = false}) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isAmount ? '₹${(value as double).toStringAsFixed(2)}' : value.toString(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildStatDivider() {
    return Container(height: 40, width: 1, color: Colors.grey[300]);
  }

  Widget _buildOpeningBalanceAlertCard() {
    if (!_openingBalanceVerified || _openingBalanceDifference == null) {
      return const SizedBox.shrink();
    }

    final isMatched = _openingBalanceDifference!.abs() < 0.01;

    if (isMatched) return const SizedBox.shrink();

    Color cardColor;
    Color borderColor;
    Color iconColor;
    IconData alertIcon;

    switch (_openingBalanceSeverity) {
      case 'high':
        cardColor = Colors.red[50]!;
        borderColor = Colors.red[300]!;
        iconColor = Colors.red[700]!;
        alertIcon = Icons.error;
        break;
      case 'medium':
        cardColor = Colors.orange[50]!;
        borderColor = Colors.orange[300]!;
        iconColor = Colors.orange[700]!;
        alertIcon = Icons.warning_amber;
        break;
      default:
        cardColor = Colors.yellow[50]!;
        borderColor = Colors.yellow[600]!;
        iconColor = Colors.yellow[800]!;
        alertIcon = Icons.info_outline;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(alertIcon, color: iconColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _openingBalanceSeverity == 'high'
                      ? '🔴 CRITICAL — Opening Balance Mismatch'
                      : _openingBalanceSeverity == 'medium'
                          ? '🟠 WARNING — Opening Balance Mismatch'
                          : '🟡 INFO — Opening Balance Difference',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                  ),
                ),
              ),
              TextButton(
                onPressed: _showOpeningBalanceEntryDialog,
                child: Text(
                  'Re-enter',
                  style: TextStyle(fontSize: 12, color: iconColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _openingBalanceMessage,
            style: TextStyle(fontSize: 13, color: iconColor),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildAlertDetailChip(
                'System Balance',
                '₹${_openingBalance.toStringAsFixed(2)}',
                Colors.blue,
              ),
              const SizedBox(width: 8),
              _buildAlertDetailChip(
                'Statement Balance',
                '₹${_statementOpeningBalance!.toStringAsFixed(2)}',
                Colors.green,
              ),
              const SizedBox(width: 8),
              _buildAlertDetailChip(
                'Difference',
                '₹${_openingBalanceDifference!.abs().toStringAsFixed(2)}',
                iconColor,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 14, color: iconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Suggested: Check for missing transactions or timing differences before proceeding. You can still continue reconciliation.',
                    style: TextStyle(fontSize: 11, color: iconColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertDetailChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // FILTERS BAR (Unchanged)
  // ============================================================================

  Widget _buildFiltersBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          const Text(
            'Filter:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C3E50),
            ),
          ),
          const SizedBox(width: 12),
          ..._filterOptions.map((filter) {
            final isSelected = _selectedFilter == filter;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(filter),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedFilter = filter;
                  });
                },
                backgroundColor: Colors.grey[100],
                selectedColor: const Color(0xFF3498DB).withOpacity(0.2),
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? const Color(0xFF3498DB) : Colors.grey[700],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // ============================================================================
  // PROVIDER TRANSACTIONS LIST (Unchanged from your working version)
  // ============================================================================

 Widget _buildProviderTransactionsList() {
    return Container(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[700],
              border: Border(bottom: BorderSide(color: Colors.blue[800]!)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.account_balance, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Provider Transactions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_filteredProviderTransactions.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_selectedUnmatchedIds.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        '${_selectedUnmatchedIds.length} selected',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _isResolvingUnmatched ? null : () => _bulkResolveUnmatched('carry-forward'),
                        icon: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white),
                        label: const Text('Carry All', style: TextStyle(color: Colors.white, fontSize: 11)),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.purple.withOpacity(0.5),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _isResolvingUnmatched ? null : () => _bulkResolveUnmatched('adjustment'),
                        icon: const Icon(Icons.tune, size: 12, color: Colors.white),
                        label: const Text('Adjust All', style: TextStyle(color: Colors.white, fontSize: 11)),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.orange.withOpacity(0.5),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          _filteredProviderTransactions.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(50),
                  child: _buildEmptyState('No provider transactions'),
                )
              : Column(
                  children: _filteredProviderTransactions.map((transaction) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: _buildProviderTransactionCard(transaction),
                    );
                  }).toList(),
                ),
        ],
      ),
    );
  }



Widget _buildProviderTransactionCard(ProviderTransactionModel transaction) {
    final isSelected = _selectedProviderTxnId == transaction.id;
    final isMatched = transaction.reconciliationStatus == 'MATCHED';
    final isPending = transaction.reconciliationStatus == 'PENDING';
    final isCarriedForward = transaction.reconciliationStatus == 'CARRIED_FORWARD';
    final isUnmatched = transaction.reconciliationStatus == 'UNMATCHED';
    final isSelectedForBulk = _selectedUnmatchedIds.contains(transaction.id);

    Color statusColor;
    if (isMatched) {
      statusColor = Colors.green;
    } else if (isPending) {
      statusColor = Colors.orange;
    } else if (isCarriedForward) {
      statusColor = Colors.purple;
    } else {
      statusColor = Colors.grey;
    }

    return InkWell(
      onTap: () {
        if (!isMatched && !isCarriedForward) {
          setState(() {
            _selectedProviderTxnId = isSelected ? null : transaction.id;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isCarriedForward
              ? Colors.purple[50]
              : isSelected
                  ? Colors.blue[50]
                  : isMatched
                      ? Colors.green[50]
                      : isSelectedForBulk
                          ? Colors.orange[50]
                          : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isCarriedForward
                ? Colors.purple[200]!
                : isSelected
                    ? const Color(0xFF3498DB)
                    : isMatched
                        ? Colors.green[200]!
                        : isSelectedForBulk
                            ? Colors.orange[300]!
                            : Colors.grey[300]!,
            width: isSelected || isSelectedForBulk ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Bulk select checkbox for unmatched
                if (isUnmatched) ...[
                  Checkbox(
                    value: isSelectedForBulk,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedUnmatchedIds.add(transaction.id);
                        } else {
                          _selectedUnmatchedIds.remove(transaction.id);
                        }
                      });
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat('dd MMM yyyy').format(transaction.transactionDate),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isMatched
                                      ? Icons.check_circle
                                      : isPending
                                          ? Icons.pending
                                          : isCarriedForward
                                              ? Icons.arrow_forward_ios
                                              : Icons.circle_outlined,
                                  size: 12,
                                  color: statusColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isCarriedForward ? 'CARRIED FWD' : transaction.reconciliationStatus,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '₹${transaction.amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                      if (transaction.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          transaction.description!,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (transaction.location != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.location_on, size: 12, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                transaction.location!,
                                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // UNMATCHED — show carry forward and adjustment buttons
            if (isUnmatched) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _carryForwardTransaction(transaction),
                      icon: const Icon(Icons.arrow_forward, size: 14),
                      label: const Text('Carry Forward', style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.purple,
                        side: const BorderSide(color: Colors.purple),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showAdjustmentDialog(transaction),
                      icon: const Icon(Icons.tune, size: 14),
                      label: const Text('Adjustment', style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange[700],
                        side: BorderSide(color: Colors.orange[700]!),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            if (isPending && transaction.matchConfidence != null) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.psychology, size: 14, color: Colors.orange[700]),
                  const SizedBox(width: 6),
                  Text(
                    'Auto-match confidence: ${transaction.matchConfidence}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[700],
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _acceptMatch(transaction),
                    child: const Text('Accept', style: TextStyle(fontSize: 11)),
                  ),
                  TextButton(
                    onPressed: () => _rejectMatch(transaction),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Reject', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ],

            if (isMatched) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.link, size: 14, color: Colors.green[700]),
                  const SizedBox(width: 6),
                  Text(
                    transaction.isAdjustment == true
                        ? 'Resolved as adjustment'
                        : 'Matched with system expense',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.green[700],
                    ),
                  ),
                  const Spacer(),
                  if (transaction.isAdjustment != true)
                    TextButton(
                      onPressed: () => _unmatchTransaction(transaction),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Unmatch', style: TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            ],

            if (isCarriedForward) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.arrow_forward_ios, size: 14, color: Colors.purple[700]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      transaction.carriedForwardNotes ?? 'Carried forward to next period',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.purple[700],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    final isFullyReconciled = _totalUnmatched == 0 && _totalPending == 0;
    final isSubmittedForApproval = _session?.approvalStatus == 'PENDING_APPROVAL';
    final isRejected = _session?.approvalStatus == 'REJECTED';
    final requiresApproval = _session?.requiresApproval == true;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Rejection alert
          if (isRejected) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.cancel, color: Colors.red[700], size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reconciliation Rejected',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[700], fontSize: 13),
                        ),
                        if (_session?.rejectionReason != null)
                          Text(
                            'Reason: ${_session!.rejectionReason}',
                            style: TextStyle(fontSize: 12, color: Colors.red[700]),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Pending approval alert
          if (isSubmittedForApproval) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.hourglass_top, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Submitted for approval. Waiting for approver to review.',
                      style: TextStyle(fontSize: 13, color: Colors.blue[700]),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => _showApprovalDialog(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Review & Approve', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isFullyReconciled
                          ? '✓ All transactions reconciled'
                          : 'Reconciliation in progress',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isFullyReconciled ? Colors.green[700] : Colors.orange[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isFullyReconciled
                          ? 'Ready to finalize reconciliation'
                          : '$_totalUnmatched unmatched + $_totalPending pending',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isAutoMatching ? null : _performAutoMatch,
                icon: _isAutoMatching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_fix_high),
                label: Text(_isAutoMatching ? 'Matching...' : 'Auto-Match All'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3498DB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
              const SizedBox(width: 12),

              // Show Submit for Approval OR Mark as Reconciled based on requiresApproval setting
              if (requiresApproval && !isSubmittedForApproval)
                ElevatedButton.icon(
                  onPressed: isFullyReconciled ? _submitForApproval : null,
                  icon: const Icon(Icons.send),
                  label: const Text('Submit for Approval'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                )
              else if (!requiresApproval && !isSubmittedForApproval)
                ElevatedButton.icon(
                  onPressed: isFullyReconciled ? _markAsReconciled : null,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Mark as Reconciled'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF27AE60),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

Future<bool?> _showMatchConfirmationDialog(Map<String, dynamic> result) {
  final details = result['details'];
  final warnings = result['warnings'] as List? ?? [];
  
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange[700], size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Confirm Match',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Main message
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Text(
                result['message'] ?? 'Large mismatch detected!',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange[900],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Transaction details comparison
            const Text(
              'Transaction Details:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _buildComparisonRow(
                    'Bank Amount',
                    '₹${details['bankAmount']}',
                    Colors.blue,
                  ),
                  const SizedBox(height: 8),
                  _buildComparisonRow(
                    'System Amount',
                    '₹${details['systemAmount']}',
                    Colors.green,
                  ),
                  const Divider(height: 20),
                  _buildComparisonRow(
                    'Difference',
                    '₹${details['difference']}',
                    Colors.red,
                    isBold: true,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Date comparison
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _buildComparisonRow(
                    'Bank Date',
                    details['bankDate'],
                    Colors.blue,
                  ),
                  const SizedBox(height: 8),
                  _buildComparisonRow(
                    'System Date',
                    details['systemDate'],
                    Colors.green,
                  ),
                  const Divider(height: 20),
                  _buildComparisonRow(
                    'Date Difference',
                    '${details['dateDifference']} days',
                    Colors.red,
                    isBold: true,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Warnings
            if (warnings.isNotEmpty) ...[
              const Text(
                'Warnings:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...warnings.map((warning) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber,
                      size: 16,
                      color: warning['severity'] == 'high' 
                        ? Colors.red 
                        : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        warning['message'],
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              )).toList(),
              const SizedBox(height: 12),
            ],
            
            // Suggestion
            if (result['suggestion'] != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        result['suggestion'],
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange[700],
            foregroundColor: Colors.white,
          ),
          child: const Text('Force Match'),
        ),
      ],
    ),
  );
}

Widget _buildComparisonRow(String label, String value, Color color, {bool isBold = false}) {
  return Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: isBold ? 14 : 13,
          fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
          color: color,
        ),
      ),
    ],
  );
}

String _parseErrorMessage(dynamic error) {
  final errorString = error.toString();
  
  // Try to extract message from ApiException
  final messageMatch = RegExp(r'"message":"([^"]+)"').firstMatch(errorString);
  if (messageMatch != null) {
    return messageMatch.group(1) ?? errorString;
  }
  
  return errorString;
}

void _showWarningSnackbar(String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: Colors.orange[700],
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ),
  );
}

Future<void> _performManualMatch() async {
  if (_selectedProviderTxnId == null || _selectedSystemExpenseId == null) {
    return;
  }

  try {
    final result = await _reconciliationService.manualMatch(
      providerTxnId: _selectedProviderTxnId!,
      expenseId: _selectedSystemExpenseId!,
    );

    // ✅ CHECK IF CONFIRMATION IS REQUIRED
    if (result['requiresConfirmation'] == true) {
      // Show confirmation dialog with details
      final confirmed = await _showMatchConfirmationDialog(result);
      
      if (confirmed == true) {
        // Retry with forceMatch: true
        final forceResult = await _reconciliationService.manualMatch(
          providerTxnId: _selectedProviderTxnId!,
          expenseId: _selectedSystemExpenseId!,
          forceMatch: true, // ← Override validation
        );

        if (forceResult['success']) {
          _showSuccessSnackbar('Transactions matched successfully (forced)');
          setState(() {
            _selectedProviderTxnId = null;
            _selectedSystemExpenseId = null;
          });
          await _loadReconciliationData();
        }
      }
    } else if (result['success']) {
      // ✅ NORMAL SUCCESS
      final warnings = result['warnings'] as List?;
      if (warnings != null && warnings.isNotEmpty) {
        _showWarningSnackbar('Matched with ${warnings.length} warning(s)');
      } else {
        _showSuccessSnackbar('Transactions matched successfully');
      }
      
      setState(() {
        _selectedProviderTxnId = null;
        _selectedSystemExpenseId = null;
      });
      await _loadReconciliationData();
    }
  } catch (e) {
    _showErrorSnackbar('Failed to match: ${_parseErrorMessage(e)}');
  }
}

  Future<void> _acceptMatch(ProviderTransactionModel transaction) async {
    try {
      final success = await _reconciliationService.acceptMatch(transaction.id);
      if (success) {
        _showSuccessSnackbar('Match accepted');
        await _loadReconciliationData();
      }
    } catch (e) {
      _showErrorSnackbar('Failed to accept match: $e');
    }
  }

  Future<void> _rejectMatch(ProviderTransactionModel transaction) async {
    try {
      final success = await _reconciliationService.rejectMatch(transaction.id);
      if (success) {
        _showSuccessSnackbar('Match rejected');
        await _loadReconciliationData();
      }
    } catch (e) {
      _showErrorSnackbar('Failed to reject match: $e');
    }
  }

  Future<void> _unmatchTransaction(ProviderTransactionModel transaction) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unmatch Transaction'),
        content: const Text('Are you sure you want to unmatch this transaction?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Unmatch'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final success = await _reconciliationService.unmatchTransaction(transaction.id);
        if (success) {
          _showSuccessSnackbar('Transaction unmatched');
          await _loadReconciliationData();
        }
      } catch (e) {
        _showErrorSnackbar('Failed to unmatch: $e');
      }
    }
  }

  Future<void> _carryForwardTransaction(ProviderTransactionModel transaction) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.arrow_forward_ios, color: Colors.purple[700]),
            const SizedBox(width: 12),
            const Text('Carry Forward'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '₹${transaction.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('dd MMM yyyy').format(transaction.transactionDate),
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  if (transaction.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      transaction.description!,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'This transaction will be moved to the next reconciliation period. It will automatically appear when you start the next session.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.arrow_forward_ios, size: 16),
            label: const Text('Carry Forward'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      setState(() => _isResolvingUnmatched = true);
      final result = await _reconciliationService.carryForwardTransaction(transaction.id);
      setState(() => _isResolvingUnmatched = false);

      if (result['success'] == true) {
        _showSuccessSnackbar(result['message'] ?? 'Transaction carried forward to next period.');
        await _loadReconciliationData();
      } else {
        _showErrorSnackbar(result['message'] ?? 'Failed to carry forward. Please try again.');
      }
    } catch (e) {
      setState(() => _isResolvingUnmatched = false);
      _showErrorSnackbar('Failed to carry forward. Please check your connection and try again.');
      print('❌ Carry forward error: $e');
    }
  }

  Future<void> _showAdjustmentDialog(ProviderTransactionModel transaction) async {
    final reasonController = TextEditingController();
    final notesController = TextEditingController();
    String selectedType = 'WRITE_OFF';

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.tune, color: Colors.orange[700]),
              const SizedBox(width: 12),
              const Text('Create Adjustment'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '₹${transaction.amount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[700],
                              ),
                            ),
                            Text(
                              DateFormat('dd MMM yyyy').format(transaction.transactionDate),
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Adjustment Type *',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'WRITE_OFF', child: Text('Write Off')),
                    DropdownMenuItem(value: 'TIMING_DIFFERENCE', child: Text('Timing Difference')),
                    DropdownMenuItem(value: 'BANK_CHARGE', child: Text('Bank Charge')),
                    DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                  ],
                  onChanged: (val) => setDialogState(() => selectedType = val ?? 'WRITE_OFF'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: reasonController,
                  decoration: InputDecoration(
                    labelText: 'Reason *',
                    hintText: 'e.g. Bank charge not recorded in system',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesController,
                  decoration: InputDecoration(
                    labelText: 'Additional Notes (Optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'An adjustment expense entry of ₹${transaction.amount.toStringAsFixed(2)} will be created in your system to keep the books balanced.',
                          style: TextStyle(fontSize: 11, color: Colors.blue[900]),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                if (reasonController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a reason for the adjustment.'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('Create Adjustment'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[700],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      setState(() => _isResolvingUnmatched = true);
      final result = await _reconciliationService.createAdjustment(
        transaction.id,
        reason: reasonController.text.trim(),
        notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
        adjustmentType: selectedType,
      );
      setState(() => _isResolvingUnmatched = false);

      if (result['success'] == true) {
        _showSuccessSnackbar(result['message'] ?? 'Adjustment created successfully.');
        await _loadReconciliationData();
      } else {
        _showErrorSnackbar(result['message'] ?? 'Failed to create adjustment. Please try again.');
      }
    } catch (e) {
      setState(() => _isResolvingUnmatched = false);
      _showErrorSnackbar('Failed to create adjustment. Please check your connection and try again.');
      print('❌ Adjustment error: $e');
    }
  }

  Future<void> _bulkResolveUnmatched(String action) async {
    if (_selectedUnmatchedIds.isEmpty) {
      _showErrorSnackbar('No transactions selected. Please select at least one unmatched transaction.');
      return;
    }

    String? reason;

    if (action == 'adjustment') {
      final reasonController = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Bulk Adjustment Reason'),
          content: TextFormField(
            controller: reasonController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Reason *',
              hintText: 'e.g. Bank charges for the period',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            maxLines: 2,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (reasonController.text.trim().isEmpty) return;
                Navigator.pop(context, reasonController.text.trim());
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[700], foregroundColor: Colors.white),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (reason == null) return;
    }

    try {
      setState(() => _isResolvingUnmatched = true);
      final result = await _reconciliationService.bulkResolve(
        transactionIds: _selectedUnmatchedIds.toList(),
        action: action,
        reason: reason,
      );
      setState(() {
        _isResolvingUnmatched = false;
        _selectedUnmatchedIds.clear();
      });

      if (result['success'] == true) {
        _showSuccessSnackbar(result['message'] ?? 'Bulk resolve completed.');
        await _loadReconciliationData();
      } else {
        _showErrorSnackbar(result['message'] ?? 'Bulk resolve failed. Please try again.');
      }
    } catch (e) {
      setState(() => _isResolvingUnmatched = false);
      _showErrorSnackbar('Bulk resolve failed. Please check your connection and try again.');
      print('❌ Bulk resolve error: $e');
    }
  }

  Future<void> _generateReport() async {
    if (_session == null) {
      _showErrorSnackbar('No active session found. Please refresh and try again.');
      return;
    }

    try {
      setState(() => _isLoading = true);
      final result = await _reconciliationService.getReconciliationReport(_session!.id);
      setState(() => _isLoading = false);

      if (result['success'] != true) {
        _showErrorSnackbar(result['message'] ?? 'Failed to generate report.');
        return;
      }

      final data = result['data'];
      await _showReportDialog(data);

    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Failed to generate report. Please try again.');
      print('❌ Report error: $e');
    }
  }

  Future<void> _submitForApproval() async {
    if (_session == null) {
      _showErrorSnackbar('No active session found. Please refresh and try again.');
      return;
    }

    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.send, color: Colors.blue),
            SizedBox(width: 12),
            Text('Submit for Approval'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will submit the reconciliation for review. The approver will need to verify and lock it.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: notesController,
              decoration: InputDecoration(
                labelText: 'Notes for approver (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700], foregroundColor: Colors.white),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      setState(() => _isLoading = true);
      final result = await _reconciliationService.submitForApproval(
        _session!.id,
        notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
      );
      setState(() => _isLoading = false);

      if (result['success'] == true) {
        _showSuccessSnackbar(result['message'] ?? 'Submitted for approval successfully.');
        await _refreshSessionStats();
        setState(() {});
      } else {
        _showErrorSnackbar(result['message'] ?? 'Failed to submit for approval. Please try again.');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Failed to submit. Please check your connection and try again.');
      print('❌ Submit for approval error: $e');
    }
  }

  Future<void> _showApprovalDialog() async {
    if (_session == null) return;

    final notesController = TextEditingController();
    final rejectionController = TextEditingController();
    String selectedAction = 'approve';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.verified_user, color: Color(0xFF2C3E50)),
              SizedBox(width: 12),
              Text('Review Reconciliation'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    children: [
                      _buildClosingBalanceRow('Account', widget.accountName, Colors.grey[800]!),
                      const SizedBox(height: 8),
                      _buildClosingBalanceRow('Period',
                        '${DateFormat('dd MMM').format(_session!.periodStart)} – ${DateFormat('dd MMM yyyy').format(_session!.periodEnd)}',
                        Colors.grey[800]!),
                      const SizedBox(height: 8),
                      _buildClosingBalanceRow('Submitted by', _session!.submittedBy ?? 'N/A', Colors.blue[700]!),
                      const SizedBox(height: 8),
                      _buildClosingBalanceRow('Matched', '${_session!.totalMatched} transactions', Colors.green[700]!),
                      const SizedBox(height: 8),
                      _buildClosingBalanceRow('Variance', '₹${_session!.balanceDifference.toStringAsFixed(2)}',
                        _session!.balanceDifference > 0 ? Colors.orange[700]! : Colors.green[700]!),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Your Decision *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setDialogState(() => selectedAction = 'approve'),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: selectedAction == 'approve' ? Colors.green[50] : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selectedAction == 'approve' ? Colors.green[400]! : Colors.grey[300]!,
                              width: selectedAction == 'approve' ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green[700], size: 28),
                              const SizedBox(height: 6),
                              Text('Approve', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[700])),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setDialogState(() => selectedAction = 'reject'),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: selectedAction == 'reject' ? Colors.red[50] : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selectedAction == 'reject' ? Colors.red[400]! : Colors.grey[300]!,
                              width: selectedAction == 'reject' ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.cancel, color: Colors.red[700], size: 28),
                              const SizedBox(height: 6),
                              Text('Reject', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[700])),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (selectedAction == 'approve')
                  TextFormField(
                    controller: notesController,
                    decoration: InputDecoration(
                      labelText: 'Approval Notes (Optional)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    maxLines: 2,
                  )
                else
                  TextFormField(
                    controller: rejectionController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Rejection Reason *',
                      hintText: 'Explain why this is being rejected',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    maxLines: 2,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedAction == 'reject' && rejectionController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a rejection reason.'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'action': selectedAction,
                  'notes': notesController.text.trim(),
                  'rejectionReason': rejectionController.text.trim(),
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: selectedAction == 'approve' ? Colors.green[700] : Colors.red[700],
                foregroundColor: Colors.white,
              ),
              child: Text(selectedAction == 'approve' ? 'Approve & Lock' : 'Reject'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    try {
      setState(() => _isLoading = true);
      final apiResult = await _reconciliationService.processApproval(
        _session!.id,
        action: result['action'],
        approvalNotes: result['notes'].isEmpty ? null : result['notes'],
        rejectionReason: result['rejectionReason'].isEmpty ? null : result['rejectionReason'],
      );
      setState(() => _isLoading = false);

      if (apiResult['success'] == true) {
        _showSuccessSnackbar(apiResult['message'] ?? 'Decision recorded successfully.');
        if (result['action'] == 'approve') {
          Navigator.pop(context, true);
        } else {
          await _refreshSessionStats();
          setState(() {});
        }
      } else {
        _showErrorSnackbar(apiResult['message'] ?? 'Failed to process decision. Please try again.');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Failed to process. Please check your connection and try again.');
      print('❌ Approval error: $e');
    }
  }

  Future<void> _showReportDialog(Map<String, dynamic> data) async {
    final session = _session!;
    final summary = data['summary'] as Map<String, dynamic>;
    final fmt = NumberFormat('#,##0.00');

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          width: 650,
          constraints: const BoxConstraints(maxHeight: 700),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFF2C3E50),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Reconciliation Report',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${widget.accountName} · ${DateFormat('dd MMM').format(session.periodStart)} – ${DateFormat('dd MMM yyyy').format(session.periodEnd)}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary cards
                      Row(
                        children: [
                          _buildReportSummaryCard('Matched', summary['matched'], Colors.green, '₹${fmt.format(summary['matchedAmount'])}'),
                          const SizedBox(width: 10),
                          _buildReportSummaryCard('Adjustments', summary['adjustments'], Colors.orange, '₹${fmt.format(summary['adjustmentAmount'])}'),
                          const SizedBox(width: 10),
                          _buildReportSummaryCard('Carried Fwd', summary['carriedForward'], Colors.purple, '₹${fmt.format(summary['carriedForwardAmount'])}'),
                          const SizedBox(width: 10),
                          _buildReportSummaryCard('Unmatched', summary['unmatched'], Colors.red, ''),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Balance summary
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Balance Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            _buildReportRow('Opening Balance (System)', session.providerBalance, Colors.blue),
                            _buildReportRow('Total Matched', session.systemBalance, Colors.green),
                            _buildReportRow('Adjustments', (summary['adjustmentAmount'] as num).toDouble(), Colors.orange),
                            const Divider(height: 20),
                            _buildReportRow('Closing Balance', session.balanceDifference, Colors.teal, isBold: true),
                            if (session.isLocked) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.lock, size: 14, color: Colors.grey),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Locked on ${session.lockedAt != null ? DateFormat('dd MMM yyyy hh:mm a').format(session.lockedAt!) : 'N/A'} by ${session.lockedBy ?? 'system'}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: session.isLocked ? Colors.green[50] : Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: session.isLocked ? Colors.green[300]! : Colors.orange[300]!),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              session.isLocked ? Icons.lock : Icons.lock_open,
                              size: 16,
                              color: session.isLocked ? Colors.green[700] : Colors.orange[700],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              session.isLocked ? 'Reconciliation Locked & Finalized' : 'Reconciliation In Progress',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: session.isLocked ? Colors.green[700] : Colors.orange[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportSummaryCard(String label, dynamic count, Color color, String amount) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text(
              count.toString(),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
            ),
            if (amount.isNotEmpty)
              Text(amount, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildReportRow(String label, double amount, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isBold ? 14 : 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: Colors.grey[800],
              ),
            ),
          ),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isBold ? 16 : 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

 Future<void> _markAsReconciled() async {
    // ── STEP 1: Ask user to enter closing balance from statement ──────────────
    final closingBalanceResult = await _showClosingBalanceEntryDialog();

    if (closingBalanceResult == null) {
      // User cancelled — do nothing
      return;
    }

    final double statementClosingBalance = closingBalanceResult;

    // ── STEP 2: Attempt finalization ──────────────────────────────────────────
    if (_session == null) {
      _showErrorSnackbar('No active reconciliation session found. Please refresh and try again.');
      return;
    }

    try {
      setState(() => _isLoading = true);

      final result = await _reconciliationService.finalizeSession(
        _session!.id,
        statementClosingBalance: statementClosingBalance,
      );

      setState(() => _isLoading = false);

      // ── STEP 3: Handle response ───────────────────────────────────────────
      if (result['success'] == true) {
        // ✅ Finalized successfully
        _showSuccessSnackbar(result['message'] ?? 'Reconciliation completed and locked successfully.');
        Navigator.pop(context, true);

      } else if (result['requiresConfirmation'] == true) {
        // ⚠️ Closing balance mismatch — show confirmation dialog
        final closingCheck = result['closingBalanceCheck'];

        setState(() {
          _statementClosingBalance = statementClosingBalance;
          _closingBalanceCheckResult = closingCheck;
        });

        final confirmed = await _showClosingBalanceMismatchDialog(
          result['message'] ?? 'Closing balance mismatch detected.',
          closingCheck,
        );

        if (confirmed == true) {
          // User acknowledged — force finalize
          setState(() => _isLoading = true);

          final forceResult = await _reconciliationService.finalizeSession(
            _session!.id,
            statementClosingBalance: statementClosingBalance,
            forceFinalize: true,
          );

          setState(() => _isLoading = false);

          if (forceResult['success'] == true) {
            _showSuccessSnackbar(forceResult['message'] ?? 'Reconciliation locked with acknowledged difference.');
            Navigator.pop(context, true);
          } else {
            _showErrorSnackbar(forceResult['message'] ?? 'Finalization failed. Please try again.');
          }
        }
        // If not confirmed — user went back, do nothing

      } else if (result['unmatchedCount'] != null && result['unmatchedCount'] > 0) {
        _showErrorSnackbar(result['message'] ?? '${result['unmatchedCount']} unmatched transactions remaining. Please match all transactions first.');

      } else if (result['pendingCount'] != null && result['pendingCount'] > 0) {
        _showErrorSnackbar(result['message'] ?? '${result['pendingCount']} transactions are still pending. Please accept or reject all pending matches first.');

      } else {
        _showErrorSnackbar(result['message'] ?? 'Finalization failed. Please check all transactions and try again.');
      }

    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Finalization failed. Please check your connection and try again.');
      print('❌ Finalize error: $e');
    }
  }

  Future<double?> _showClosingBalanceEntryDialog() async {
    final controller = TextEditingController();

    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.lock_outline, color: Colors.teal),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Enter Statement Closing Balance',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.teal[700], size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Enter the closing balance shown at the end of your bank/provider statement for this period. This will be verified against your system balance before locking.',
                      style: TextStyle(fontSize: 12, color: Colors.teal[900]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Statement Closing Balance *',
                prefixIcon: const Icon(Icons.currency_rupee),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                hintText: 'e.g. 45000.00',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid amount before continuing.'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              Navigator.pop(context, value);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('Verify & Finalize'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showClosingBalanceMismatchDialog(
    String message,
    Map<String, dynamic> closingCheck,
  ) {
    final difference = (closingCheck['difference'] as num).toDouble();
    final systemBalance = (closingCheck['systemClosingBalance'] as num).toDouble();
    final statementBalance = (closingCheck['statementClosingBalance'] as num).toDouble();
    final severity = closingCheck['severity'] ?? 'medium';

    Color severityColor;
    String severityLabel;
    IconData severityIcon;

    switch (severity) {
      case 'high':
        severityColor = Colors.red[700]!;
        severityLabel = '🔴 CRITICAL — Large Closing Balance Mismatch';
        severityIcon = Icons.error;
        break;
      case 'medium':
        severityColor = Colors.orange[700]!;
        severityLabel = '🟠 WARNING — Closing Balance Mismatch';
        severityIcon = Icons.warning_amber;
        break;
      default:
        severityColor = Colors.yellow[800]!;
        severityLabel = '🟡 INFO — Small Closing Balance Difference';
        severityIcon = Icons.info_outline;
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(severityIcon, color: severityColor, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Closing Balance Mismatch',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: severityColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: severityColor.withOpacity(0.3)),
                ),
                child: Text(
                  severityLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: severityColor,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    _buildClosingBalanceRow(
                      'System Closing Balance',
                      '₹${systemBalance.toStringAsFixed(2)}',
                      Colors.blue[700]!,
                    ),
                    const SizedBox(height: 10),
                    _buildClosingBalanceRow(
                      'Statement Closing Balance',
                      '₹${statementBalance.toStringAsFixed(2)}',
                      Colors.green[700]!,
                    ),
                    const Divider(height: 24),
                    _buildClosingBalanceRow(
                      'Difference',
                      '₹${difference.abs().toStringAsFixed(2)}',
                      severityColor,
                      isBold: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline, size: 16, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          'What you can do:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Go back and check for missing transactions\n'
                      '• Verify the closing balance you entered is correct\n'
                      '• If the difference is due to timing, you can acknowledge and proceed',
                      style: TextStyle(fontSize: 12, color: Colors.blue[900]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go Back & Fix'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: severityColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Acknowledge & Lock'),
          ),
        ],
      ),
    );
  }

  Widget _buildClosingBalanceRow(
    String label,
    String value,
    Color color, {
    bool isBold = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: Colors.grey[800],
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  void _showImportDialog() {
    showDialog(
      context: context,
      builder: (context) => ImportStatementDialog(
        accountId: widget.accountId,
        onImportComplete: () {
          _loadReconciliationData();
        },
      ),
    );
  }

  void _showPettyCashCountDialog() {
    showDialog(
      context: context,
      builder: (context) => PettyCashCountDialog(
        accountId: widget.accountId,
        accountName: widget.accountName,
        periodStart: _periodStart,
        periodEnd: _periodEnd,
        onCountSubmitted: () {
          Navigator.pop(context, true);
        },
      ),
    );
  }

  void _showDateRangePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _periodStart, end: _periodEnd),
    );

    if (picked != null) {
      setState(() {
        _periodStart = picked.start;
        _periodEnd = picked.end;
      });
      _initializeReconciliation();
    }
  }

  // ============================================================================
  // SYSTEM EXPENSES LIST
  // ============================================================================

  Widget _buildSystemExpensesList() {
    return Container(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green[700],
              border: Border(bottom: BorderSide(color: Colors.green[800]!)),
            ),
            child: Row(
              children: [
                const Icon(Icons.receipt_long, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'System Expenses',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_filteredSystemExpenses.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _filteredSystemExpenses.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(50),
                  child: _buildEmptyState('No system expenses'),
                )
              : Column(
                  children: _filteredSystemExpenses.map((expense) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: _buildSystemExpenseCard(expense),
                    );
                  }).toList(),
                ),
        ],
      ),
    );
  }

  Widget _buildSystemExpenseCard(Map<String, dynamic> expense) {
    final expenseId = expense['_id'] ?? expense['id'] ?? '';
    final isSelected = _selectedSystemExpenseId == expenseId;
    final isMatched = expense['providerTransactionId'] != null;

    return InkWell(
      onTap: () {
        if (!isMatched) {
          setState(() {
            _selectedSystemExpenseId = isSelected ? null : expenseId;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.green[50]
              : (isMatched ? Colors.green[50] : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF27AE60)
                : (isMatched ? Colors.green[200]! : Colors.grey[300]!),
            width: isSelected ? 2 : 1,
          ),
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
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat('dd MMM yyyy').format(DateTime.parse(expense['date'])),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          const Spacer(),
                          if (isMatched)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle, size: 12, color: Colors.green[700]),
                                  const SizedBox(width: 4),
                                  Text(
                                    'MATCHED',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '₹${(expense['total'] ?? 0).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        expense['expenseAccount'] ?? 'No account',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      if (expense['vendor'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Vendor: ${expense['vendor']}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (isMatched) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.link, size: 14, color: Colors.green[700]),
                  const SizedBox(width: 6),
                  Text(
                    'Matched with provider transaction',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.green[700],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // MATCHING CENTER
  // ============================================================================

  Widget _buildMatchingCenter() {
    final canMatch = _selectedProviderTxnId != null && _selectedSystemExpenseId != null;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (canMatch)
            ElevatedButton(
              onPressed: _performManualMatch,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3498DB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
                shape: const CircleBorder(),
              ),
              child: const Icon(Icons.compare_arrows, size: 28),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.compare_arrows, size: 28, color: Colors.grey[500]),
            ),
          const SizedBox(height: 12),
          Text(
            canMatch ? 'Match' : 'Select\nboth',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: canMatch ? const Color(0xFF3498DB) : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // PETTY CASH RECONCILIATION
  // ============================================================================

 Widget _buildPettyCashReconciliation() {
  return _PettyCashInlinePage(
    accountId: widget.accountId,
    accountName: widget.accountName,
    periodStart: _periodStart,
    periodEnd: _periodEnd,
  );
}

  // ============================================================================
  // AUTO MATCH METHOD
  // ============================================================================

  Future<void> _performAutoMatch() async {
    setState(() => _isAutoMatching = true);

    try {
      final result = await _reconciliationService.runAutoMatch(
        accountId: widget.accountId,
        startDate: _periodStart,
        endDate: _periodEnd,
      );

      if (result['success']) {
        final data = result['data'];
        _showSuccessSnackbar(
          'Auto-match complete: ${data['matchedCount']} matched, ${data['pendingCount']} pending',
        );
        await _loadReconciliationData();
      }
    } catch (e) {
      _showErrorSnackbar('Auto-match failed: $e');
    } finally {
      setState(() => _isAutoMatching = false);
    }
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        ],
      ),
    );
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
}

// ============================================================================
// ✅ UPDATED IMPORT STATEMENT DIALOG WITH CORRECT COLUMN MAPPINGS
// ============================================================================

class ImportStatementDialog extends StatefulWidget {
  final String accountId;
  final VoidCallback onImportComplete;

  const ImportStatementDialog({
    Key? key,
    required this.accountId,
    required this.onImportComplete,
  }) : super(key: key);

  @override
  State<ImportStatementDialog> createState() => _ImportStatementDialogState();
}

class _ImportStatementDialogState extends State<ImportStatementDialog> {
  final ReconciliationBillingService _service = ReconciliationBillingService();

  bool _isUploading = false;
  File? _selectedFile;
  String? _fileName;
  Uint8List? _selectedFileBytes;

  // Column mappings
  final Map<String, String> _columnMappings = {};
  List<String> _availableColumns = [];
  bool _showColumnMapping = false;

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final pickedFile = result.files.first;
        
        File file;
        if (kIsWeb) {
          if (pickedFile.bytes != null) {
            file = File(pickedFile.name);
            _selectedFileBytes = pickedFile.bytes;
          } else {
            throw Exception('No bytes available from picked file');
          }
        } else {
          file = File(pickedFile.path!);
          _selectedFileBytes = null;
        }
        
        setState(() {
          _selectedFile = file;
          _fileName = pickedFile.name;
          _showColumnMapping = false;
        });

        _showColumnMappingDialog();
      }
    } catch (e) {
      print('❌ File picker error: $e');
      _showErrorSnackbar('Failed to pick file: $e');
    }
  }

  void _showColumnMappingDialog() {
    // ✅ UPDATED: Column list matches your actual Excel file
    _availableColumns = [
      'Transaction Date',    // ← Matches Excel Row 7
      'Value Date',          // ← Matches Excel Row 7
      'Description',         // ← Matches Excel Row 7  
      'Reference Number',    // ← Matches Excel Row 7
      'Debit',              // ← Matches Excel Row 7 ✅
      'Credit',             // ← Matches Excel Row 7 ✅
      'Balance',            // ← Matches Excel Row 7
      'Date',               // ← Alternative
      'Amount',             // ← Fallback
      'Location',
      'Card Number',
    ];

    showDialog(
      context: context,
      builder: (context) => ColumnMappingDialog(
        availableColumns: _availableColumns,
        onMappingComplete: (mappings) {
          setState(() {
            _columnMappings.addAll(mappings);
            _showColumnMapping = true;
          });
        },
      ),
    );
  }

  Future<void> _uploadFile() async {
    if (_selectedFile == null && _selectedFileBytes == null) {
      _showErrorSnackbar('Please select a file');
      return;
    }

    if (_columnMappings.isEmpty) {
      _showErrorSnackbar('Please map columns');
      return;
    }

    setState(() => _isUploading = true);

    try {
      if (kIsWeb && _selectedFileBytes != null) {
        print('🌐 Web upload: Using bytes directly');
        
        final result = await _service.importProviderStatementBytes(
          accountId: widget.accountId,
          fileBytes: _selectedFileBytes!,
          fileName: _fileName!,
          columnMappings: _columnMappings,
          dateFormat: 'DD/MM/YYYY',
        );

        if (result['success']) {
          final data = result['data'];
          _showSuccessSnackbar(
            'Imported ${data['imported']} transactions successfully!',
          );
          Navigator.pop(context);
          widget.onImportComplete();
        }
      } else if (_selectedFile != null) {
        print('📱 Mobile upload: Using file path');
        
        final result = await _service.importProviderStatement(
          accountId: widget.accountId,
          file: _selectedFile!,
          columnMappings: _columnMappings,
          dateFormat: 'DD/MM/YYYY',
        );

        if (result['success']) {
          final data = result['data'];
          _showSuccessSnackbar(
            'Imported ${data['imported']} transactions successfully!',
          );
          Navigator.pop(context);
          widget.onImportComplete();
        }
      } else {
        throw Exception('No file available');
      }
    } catch (e) {
      print('❌ Upload error: $e');
      _showErrorSnackbar('Import failed: $e');
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.upload_file, color: Color(0xFF3498DB), size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Import Provider Statement',
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
            OutlinedButton.icon(
              onPressed: _isUploading ? null : _pickFile,
              icon: const Icon(Icons.file_upload),
              label: Text(_fileName ?? 'Select Excel/CSV File'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              ),
            ),
            if (_showColumnMapping) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Columns mapped successfully',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: _showColumnMappingDialog,
                      child: const Text('Edit', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_selectedFile != null && _showColumnMapping && !_isUploading)
                    ? _uploadFile
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3498DB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Import Statement'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}

// ============================================================================
// ✅ UPDATED COLUMN MAPPING DIALOG WITH DEBIT/CREDIT SUPPORT
// ============================================================================

class ColumnMappingDialog extends StatefulWidget {
  final List<String> availableColumns;
  final Function(Map<String, String>) onMappingComplete;

  const ColumnMappingDialog({
    Key? key,
    required this.availableColumns,
    required this.onMappingComplete,
  }) : super(key: key);

  @override
  State<ColumnMappingDialog> createState() => _ColumnMappingDialogState();
}

class _ColumnMappingDialogState extends State<ColumnMappingDialog> {
  // ✅ UPDATED: Support both debit and credit columns
  final Map<String, String?> _mappings = {
    'dateColumn': null,
    'debitColumn': null,      // ✅ FOR DEBIT AMOUNTS
    'creditColumn': null,     // ✅ FOR CREDIT AMOUNTS
    'descriptionColumn': null,
    'referenceColumn': null,
    'locationColumn': null,
    'cardNumberColumn': null,
  };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Map Your Statement Columns',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C3E50),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Match your file columns to the required fields',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            _buildMappingRow('Date *', 'dateColumn', true),
            _buildMappingRow('Debit *', 'debitColumn', true),     // ✅ REQUIRED
            _buildMappingRow('Credit', 'creditColumn', false),    // ✅ OPTIONAL
            _buildMappingRow('Description', 'descriptionColumn', false),
            _buildMappingRow('Reference', 'referenceColumn', false),
            _buildMappingRow('Location', 'locationColumn', false),
            _buildMappingRow('Card Number', 'cardNumberColumn', false),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSubmit() ? _submitMapping : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3498DB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Confirm Mapping'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMappingRow(String label, String key, bool required) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: required ? Colors.black : Colors.grey[700],
              ),
            ),
          ),
          const Icon(Icons.arrow_forward, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _mappings[key],
              decoration: InputDecoration(
                hintText: 'Select column',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Skip')),
                ...widget.availableColumns.map((col) {
                  return DropdownMenuItem(value: col, child: Text(col));
                }).toList(),
              ],
              onChanged: (value) {
                setState(() {
                  _mappings[key] = value;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _canSubmit() {
    // ✅ UPDATED: Require date and debit columns
    return _mappings['dateColumn'] != null && _mappings['debitColumn'] != null;
  }

  void _submitMapping() {
    final result = <String, String>{};
    _mappings.forEach((key, value) {
      if (value != null) {
        result[key] = value;
      }
    });
    Navigator.pop(context);
    widget.onMappingComplete(result);
  }
}

// ============================================================================
// PETTY CASH COUNT DIALOG (Unchanged from your working version)
// ============================================================================

class PettyCashCountDialog extends StatefulWidget {
  final String accountId;
  final String accountName;
  final DateTime periodStart;
  final DateTime periodEnd;
  final VoidCallback onCountSubmitted;

  const PettyCashCountDialog({
    Key? key,
    required this.accountId,
    required this.accountName,
    required this.periodStart,
    required this.periodEnd,
    required this.onCountSubmitted,
  }) : super(key: key);

  @override
  State<PettyCashCountDialog> createState() => _PettyCashCountDialogState();
}

class _PettyCashCountDialogState extends State<PettyCashCountDialog> {
  final ReconciliationBillingService _service = ReconciliationBillingService();
  final TextEditingController _cashCountController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  
  bool _isSubmitting = false;
  bool _isLoadingSummary = true;
  bool _showSummary = false;
  
  // Summary data
  double _openingBalance = 0;
  double _totalExpenses = 0;
  double _expectedBalance = 0;
  int _expenseCount = 0;
  
  // Reconciliation result
  ReconciliationSessionModel? _reconciliationResult;

  @override
  void initState() {
    super.initState();
    _loadPettyCashSummary();
  }

  Future<void> _loadPettyCashSummary() async {
    setState(() => _isLoadingSummary = true);

    try {
      final summary = await _service.getPettyCashSummary(
        accountId: widget.accountId,
        startDate: widget.periodStart,
        endDate: widget.periodEnd,
      );

      if (summary['success']) {
        final data = summary['data'];
        setState(() {
          _openingBalance = (data['openingBalance'] ?? 0).toDouble();
          _totalExpenses = (data['totalExpenses'] ?? 0).toDouble();
          _expectedBalance = (data['expectedBalance'] ?? 0).toDouble();
          _expenseCount = data['expenseCount'] ?? 0;
          _isLoadingSummary = false;
        });
      }
    } catch (e) {
      print('Error loading petty cash summary: $e');
      setState(() => _isLoadingSummary = false);
    }
  }

  Future<void> _submitCount() async {
    final cashCount = double.tryParse(_cashCountController.text);
    if (cashCount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid amount'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final result = await _service.submitPettyCashCount(
        accountId: widget.accountId,
        accountName: widget.accountName,
        periodStart: widget.periodStart,
        periodEnd: widget.periodEnd,
        physicalCashCount: cashCount,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
      );

      setState(() {
        _reconciliationResult = result;
        _showSummary = true;
        _isSubmitting = false;
      });

    } catch (e) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit count: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 550,
        constraints: const BoxConstraints(maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: _isLoadingSummary
            ? _buildLoadingView()
            : _showSummary
                ? _buildSummaryView()
                : _buildInputView(),
      ),
    );
  }

  Widget _buildLoadingView() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Loading summary...'),
      ],
    );
  }

  Widget _buildInputView() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.payments, color: Colors.purple, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Petty Cash Count',
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
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Column(
              children: [
                _buildSummaryRow('Opening Balance', _openingBalance, Icons.account_balance_wallet),
                const Divider(height: 20),
                _buildSummaryRow('Expenses Paid', _totalExpenses, Icons.receipt_long),
                const SizedBox(height: 8),
                Text(
                  '($_expenseCount expense${_expenseCount != 1 ? 's' : ''})',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                const Divider(height: 20),
                _buildSummaryRow('Expected Balance', _expectedBalance, Icons.calculate, 
                  color: Colors.blue[700]!, isBold: true),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          Text(
            'Enter Physical Cash Count',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _cashCountController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Actual Cash Counted *',
              hintText: 'Enter amount (e.g., ${_expectedBalance.toStringAsFixed(0)})',
              prefixIcon: const Icon(Icons.currency_rupee),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: Colors.white,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
          ),
          
          const SizedBox(height: 16),
          
          TextFormField(
            controller: _notesController,
            decoration: InputDecoration(
              labelText: 'Notes (Optional)',
              hintText: 'Add any comments about the count',
              prefixIcon: const Icon(Icons.note),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: Colors.white,
            ),
            maxLines: 2,
          ),
          
          const SizedBox(height: 24),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitCount,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Submit Count', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryView() {
    if (_reconciliationResult == null) return const SizedBox();

    final physicalCount = _reconciliationResult!.physicalCashCount ?? 0;
    final variance = _reconciliationResult!.balanceDifference;
    final hasVariance = variance.abs() > 0.01;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.check_circle, color: Colors.green, size: 32),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reconciliation Complete',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF27AE60),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Cash count submitted successfully',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          
          const Text(
            'Reconciliation Summary',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              children: [
                _buildComparisonRow('Opening Balance', _openingBalance, Colors.blue),
                const SizedBox(height: 8),
                _buildComparisonRow('Less: Expenses', _totalExpenses, Colors.red, isNegative: true),
                const Divider(height: 24),
                _buildComparisonRow('Expected Balance', _expectedBalance, Colors.blue[700]!),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app, color: Colors.purple, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Physical Count:',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        '₹${physicalCount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: hasVariance ? Colors.orange[50] : Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasVariance ? Colors.orange[300]! : Colors.green[300]!,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      hasVariance ? Icons.warning_amber : Icons.check_circle,
                      color: hasVariance ? Colors.orange[700] : Colors.green[700],
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasVariance ? 'Variance Detected' : 'Perfectly Balanced',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: hasVariance ? Colors.orange[700] : Colors.green[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasVariance 
                                ? 'There is a difference between expected and actual'
                                : 'Physical count matches expected balance',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${variance > 0 ? '+' : ''}₹${variance.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: hasVariance ? Colors.orange[700] : Colors.green[700],
                      ),
                    ),
                  ],
                ),
                if (hasVariance) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          variance > 0 
                              ? 'You have ₹${variance.toStringAsFixed(2)} more cash than expected'
                              : 'You are short by ₹${variance.abs().toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.blue[700]),
                    const SizedBox(width: 6),
                    Text(
                      'Period: ${DateFormat('dd MMM').format(widget.periodStart)} - ${DateFormat('dd MMM yyyy').format(widget.periodEnd)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.receipt, size: 14, color: Colors.blue[700]),
                    const SizedBox(width: 6),
                    Text(
                      'Total expenses: $_expenseCount transaction${_expenseCount != 1 ? 's' : ''}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                widget.onCountSubmitted();
              },
              icon: const Icon(Icons.check),
              label: const Text('Done', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF27AE60),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount, IconData icon, {Color? color, bool isBold = false}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color ?? Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: Colors.grey[800],
            ),
          ),
        ),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color ?? Colors.grey[800],
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonRow(String label, double amount, Color color, {bool isNegative = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          '${isNegative ? '-' : ''}₹${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _cashCountController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}

// ============================================================================
// PETTY CASH INLINE PAGE
// ============================================================================

class _PettyCashInlinePage extends StatefulWidget {
  final String accountId;
  final String accountName;
  final DateTime periodStart;
  final DateTime periodEnd;

  const _PettyCashInlinePage({
    required this.accountId,
    required this.accountName,
    required this.periodStart,
    required this.periodEnd,
  });

  @override
  State<_PettyCashInlinePage> createState() => _PettyCashInlinePageState();
}

class _PettyCashInlinePageState extends State<_PettyCashInlinePage> {
  final ReconciliationBillingService _service = ReconciliationBillingService();
  final TextEditingController _cashCountController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _submitted = false;

  double _openingBalance = 0;
  double _totalExpenses = 0;
  double _expectedBalance = 0;
  int _expenseCount = 0;
  List<Map<String, dynamic>> _expenses = [];

  double? _physicalCount;
  double? _variance;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _cashCountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final summary = await _service.getPettyCashSummary(
        accountId: widget.accountId,
        startDate: widget.periodStart,
        endDate: widget.periodEnd,
      );

      if (summary['success'] == true) {
        final data = summary['data'];
        setState(() {
          _openingBalance = (data['openingBalance'] ?? 0).toDouble();
          _totalExpenses = (data['totalExpenses'] ?? 0).toDouble();
          _expectedBalance = (data['expectedBalance'] ?? 0).toDouble();
          _expenseCount = data['expenseCount'] ?? 0;
          _expenses = List<Map<String, dynamic>>.from(data['expenses'] ?? []);
        });
      }
    } catch (e) {
      print('Error loading petty cash: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    final count = double.tryParse(_cashCountController.text.trim());
    if (count == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid cash count amount'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _service.submitPettyCashCount(
        accountId: widget.accountId,
        accountName: widget.accountName,
        periodStart: widget.periodStart,
        periodEnd: widget.periodEnd,
        physicalCashCount: count,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      setState(() {
        _physicalCount = count;
        _variance = count - _expectedBalance; // ✅ CORRECT formula
        _submitted = true;
        _isSubmitting = false;
      });
    } catch (e) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBalanceSummary(),
          const SizedBox(height: 24),
          _buildExpensesList(),
          const SizedBox(height: 24),
          _buildCashCountSection(),
          if (_submitted) ...[
            const SizedBox(height: 24),
            _buildResult(),
          ],
        ],
      ),
    );
  }

  Widget _buildBalanceSummary() {
    return Row(
      children: [
        _buildSummaryCard('Opening Balance', _openingBalance,
            Icons.account_balance_wallet, Colors.purple),
        const SizedBox(width: 16),
        _buildSummaryCard('Total Expenses', _totalExpenses,
            Icons.receipt_long, Colors.red,
            subtitle: '$_expenseCount expense${_expenseCount != 1 ? 's' : ''}'),
        const SizedBox(width: 16),
        _buildSummaryCard('Expected Closing', _expectedBalance,
            Icons.calculate, Colors.blue,
            subtitle: 'Opening − Expenses'),
      ],
    );
  }

  Widget _buildSummaryCard(
    String label,
    double amount,
    IconData icon,
    Color color, {
    String? subtitle,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text(
              '₹${amount.toStringAsFixed(2)}',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle,
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExpensesList() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red[700],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.receipt_long,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text('Petty Cash Expenses',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$_expenseCount',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
              ],
            ),
          ),

          // Table header
          if (_expenses.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              color: Colors.grey[100],
              child: Row(
                children: [
                  _tableHeader('DATE', flex: 2),
                  _tableHeader('DESCRIPTION', flex: 4),
                  _tableHeader('VENDOR', flex: 3),
                  _tableHeader('AMOUNT', flex: 2, right: true),
                ],
              ),
            ),

          // Rows
          if (_expenses.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.receipt, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text('No expenses found for this period',
                        style: TextStyle(
                            color: Colors.grey[500], fontSize: 14)),
                  ],
                ),
              ),
            )
          else
            ...(_expenses.asMap().entries.map((entry) {
              final i = entry.key;
              final e = entry.value;
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: i.isEven ? Colors.white : Colors.grey[50],
                  border: Border(
                      bottom: BorderSide(color: Colors.grey[100]!)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(_fmtDate(e['date']),
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[700])),
                    ),
                    Expanded(
                      flex: 4,
                      child: Text(
                        e['expenseAccount'] ??
                            e['description'] ??
                            '-',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        e['vendor'] ?? '-',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '₹${(e['total'] ?? 0).toStringAsFixed(2)}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
            }).toList()),

          // Total row
          if (_expenses.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                border:
                    Border(top: BorderSide(color: Colors.red[200]!)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    flex: 9,
                    child: Text('Total Expenses',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '₹${_totalExpenses.toStringAsFixed(2)}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[700]),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tableHeader(String text,
      {int flex = 1, bool right = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
            letterSpacing: 0.5),
      ),
    );
  }

  String _fmtDate(dynamic date) {
    if (date == null) return '-';
    try {
      return DateFormat('dd MMM yyyy')
          .format(DateTime.parse(date.toString()));
    } catch (_) {
      return date.toString();
    }
  }

  Widget _buildCashCountSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.calculate,
                    color: Colors.purple, size: 24),
              ),
              const SizedBox(width: 12),
              const Text('Physical Cash Count',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C3E50))),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _cashCountController,
                  enabled: !_submitted,
                  decoration: InputDecoration(
                    labelText: 'Actual Cash Counted *',
                    hintText: 'Enter amount you physically counted',
                    prefixIcon: const Icon(Icons.currency_rupee),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor:
                        _submitted ? Colors.grey[100] : Colors.white,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _notesController,
                  enabled: !_submitted,
                  decoration: InputDecoration(
                    labelText: 'Notes (Optional)',
                    hintText: 'Any comments about this count',
                    prefixIcon: const Icon(Icons.note),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor:
                        _submitted ? Colors.grey[100] : Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (!_submitted)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle),
                label: Text(
                    _isSubmitting
                        ? 'Submitting...'
                        : 'Submit Cash Count',
                    style: const TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700]),
                  const SizedBox(width: 10),
                  Text('Cash count submitted successfully',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.green[700])),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _submitted = false;
                        _cashCountController.clear();
                        _notesController.clear();
                      });
                    },
                    child: const Text('Re-submit'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final variance = _variance!;
    final hasVariance = variance.abs() > 0.01;
    final isOver = variance > 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasVariance ? Colors.orange[300]! : Colors.green[300]!,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasVariance ? Icons.warning_amber : Icons.check_circle,
                color: hasVariance
                    ? Colors.orange[700]
                    : Colors.green[700],
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasVariance
                          ? 'Variance Detected'
                          : 'Perfectly Balanced ✓',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: hasVariance
                              ? Colors.orange[700]
                              : Colors.green[700]),
                    ),
                    Text(
                      hasVariance
                          ? isOver
                              ? 'You have ₹${variance.toStringAsFixed(2)} MORE cash than expected'
                              : 'You are SHORT by ₹${variance.abs().toStringAsFixed(2)}'
                          : 'Physical count matches expected balance',
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: hasVariance
                      ? Colors.orange.withOpacity(0.1)
                      : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: hasVariance
                          ? Colors.orange[300]!
                          : Colors.green[300]!),
                ),
                child: Text(
                  '${isOver ? '+' : ''}₹${variance.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: hasVariance
                          ? Colors.orange[700]
                          : Colors.green[700]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          _resultRow('Opening Balance',
              '₹${_openingBalance.toStringAsFixed(2)}', Colors.purple),
          const SizedBox(height: 8),
          _resultRow('Less: Expenses ($_expenseCount)',
              '- ₹${_totalExpenses.toStringAsFixed(2)}', Colors.red),
          const Divider(height: 20),
          _resultRow(
              'Expected Closing Balance',
              '₹${_expectedBalance.toStringAsFixed(2)}',
              Colors.blue,
              bold: true),
          const SizedBox(height: 8),
          _resultRow(
              'Physical Count Entered',
              '₹${_physicalCount!.toStringAsFixed(2)}',
              Colors.purple,
              bold: true),
          const Divider(height: 20),
          _resultRow(
            'Variance (Physical − Expected)',
            '${isOver ? '+' : ''}₹${variance.toStringAsFixed(2)}',
            hasVariance ? Colors.orange[700]! : Colors.green[700]!,
            bold: true,
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value, Color color,
      {bool bold = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: bold ? 14 : 13,
                  fontWeight:
                      bold ? FontWeight.bold : FontWeight.normal,
                  color: Colors.grey[800])),
        ),
        Text(value,
            style: TextStyle(
                fontSize: bold ? 16 : 14,
                fontWeight:
                    bold ? FontWeight.bold : FontWeight.w600,
                color: color)),
      ],
    );
  }
}

// Extension for firstOrNull
extension ListExtension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}