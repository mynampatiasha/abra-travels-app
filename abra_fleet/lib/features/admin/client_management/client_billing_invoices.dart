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
  
  // Sample invoice data with comprehensive fleet details
  final List<Map<String, dynamic>> _invoices = [
    {
      'id': 'INV-2024-001',
      'organizationName': 'ABC Logistics Pvt Ltd',
      'agreementId': 'AGR-2024-ABC-001',
      'agreementStartDate': '2024-01-01',
      'agreementEndDate': '2025-12-31',
      'billingCycle': 'Monthly',
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
      'trips': 156,
      'totalDistance': 12450.5,
      'totalFuelConsumed': 1850.25,
      'totalIdleTime': 45.5,
      'vehicles': [
        {'type': 'Truck', 'count': 8, 'distance': 8500.0, 'cost': 170000.0},
        {'type': 'Van', 'count': 5, 'distance': 3950.5, 'cost': 75680.50},
      ],
      'charges': {
        'baseCharges': 180000.0,
        'perKmCharges': 45680.50,
        'fuelSurcharge': 12000.0,
        'tollCharges': 4500.0,
        'waitingCharges': 2500.0,
        'loadingUnloadingCharges': 1000.0,
      },
    },
    {
      'id': 'INV-2024-002',
      'organizationName': 'XYZ Transport Solutions',
      'agreementId': 'AGR-2024-XYZ-005',
      'agreementStartDate': '2024-03-15',
      'agreementEndDate': '2025-03-14',
      'billingCycle': 'Weekly',
      'paymentTerms': 'Net 15',
      'amount': 125000.00,
      'gstAmount': 22500.00,
      'totalAmount': 147500.00,
      'amountPaid': 75000.00,
      'status': 'Partially Paid',
      'date': '2024-12-03',
      'dueDate': '2024-12-18',
      'paidDate': '2024-12-10',
      'paymentMode': 'Cheque',
      'trips': 89,
      'totalDistance': 6780.0,
      'totalFuelConsumed': 980.5,
      'totalIdleTime': 28.0,
      'vehicles': [
        {'type': 'Car', 'count': 12, 'distance': 6780.0, 'cost': 125000.0},
      ],
      'charges': {
        'baseCharges': 95000.0,
        'perKmCharges': 20340.0,
        'fuelSurcharge': 6500.0,
        'tollCharges': 2160.0,
        'waitingCharges': 800.0,
        'loadingUnloadingCharges': 200.0,
      },
    },
    {
      'id': 'INV-2024-003',
      'organizationName': 'Global Freight Services',
      'agreementId': 'AGR-2023-GFS-012',
      'agreementStartDate': '2023-06-01',
      'agreementEndDate': '2025-05-31',
      'billingCycle': 'Monthly',
      'paymentTerms': 'Net 45',
      'amount': 485000.00,
      'gstAmount': 87300.00,
      'totalAmount': 572300.00,
      'amountPaid': 0.0,
      'status': 'Overdue',
      'date': '2024-11-01',
      'dueDate': '2024-12-16',
      'paidDate': null,
      'paymentMode': null,
      'trips': 234,
      'totalDistance': 18950.8,
      'totalFuelConsumed': 2845.5,
      'totalIdleTime': 67.5,
      'vehicles': [
        {'type': 'Heavy Truck', 'count': 15, 'distance': 15200.0, 'cost': 380000.0},
        {'type': 'Trailer', 'count': 6, 'distance': 3750.8, 'cost': 105000.0},
      ],
      'charges': {
        'baseCharges': 350000.0,
        'perKmCharges': 94754.0,
        'fuelSurcharge': 25000.0,
        'tollCharges': 8500.0,
        'waitingCharges': 4500.0,
        'loadingUnloadingCharges': 2246.0,
      },
    },
    {
      'id': 'INV-2024-004',
      'organizationName': 'QuickShip Express Ltd',
      'agreementId': 'AGR-2024-QSE-008',
      'agreementStartDate': '2024-02-01',
      'agreementEndDate': '2026-01-31',
      'billingCycle': 'Bi-Weekly',
      'paymentTerms': 'Net 30',
      'amount': 168500.00,
      'gstAmount': 30330.00,
      'totalAmount': 198830.00,
      'amountPaid': 198830.00,
      'status': 'Paid',
      'date': '2024-12-05',
      'dueDate': '2025-01-04',
      'paidDate': '2024-12-28',
      'paymentMode': 'Online Payment',
      'trips': 142,
      'totalDistance': 9450.0,
      'totalFuelConsumed': 1420.75,
      'totalIdleTime': 38.5,
      'vehicles': [
        {'type': 'Van', 'count': 10, 'distance': 9450.0, 'cost': 168500.0},
      ],
      'charges': {
        'baseCharges': 125000.0,
        'perKmCharges': 28350.0,
        'fuelSurcharge': 10000.0,
        'tollCharges': 3200.0,
        'waitingCharges': 1500.0,
        'loadingUnloadingCharges': 450.0,
      },
    },
    {
      'id': 'INV-2024-005',
      'organizationName': 'Metro Delivery Corporation',
      'agreementId': 'AGR-2024-MDC-015',
      'agreementStartDate': '2024-07-01',
      'agreementEndDate': '2025-06-30',
      'billingCycle': 'Monthly',
      'paymentTerms': 'Net 30',
      'amount': 95800.00,
      'gstAmount': 17244.00,
      'totalAmount': 113044.00,
      'amountPaid': 0.0,
      'status': 'Pending',
      'date': '2024-12-07',
      'dueDate': '2025-01-06',
      'paidDate': null,
      'paymentMode': null,
      'trips': 67,
      'totalDistance': 4250.5,
      'totalFuelConsumed': 680.25,
      'totalIdleTime': 22.0,
      'vehicles': [
        {'type': 'Bike', 'count': 8, 'distance': 2150.0, 'cost': 32250.0},
        {'type': 'Car', 'count': 5, 'distance': 2100.5, 'cost': 63550.0},
      ],
      'charges': {
        'baseCharges': 70000.0,
        'perKmCharges': 17002.0,
        'fuelSurcharge': 6000.0,
        'tollCharges': 1800.0,
        'waitingCharges': 800.0,
        'loadingUnloadingCharges': 198.0,
      },
    },
  ];

  List<Map<String, dynamic>> get _filteredInvoices {
    return _invoices.where((invoice) {
      final matchesStatus = _selectedFilter == 'All' || invoice['status'] == _selectedFilter;
      final matchesSearch = invoice['organizationName'].toLowerCase().contains(_searchQuery.toLowerCase()) ||
          invoice['id'].toLowerCase().contains(_searchQuery.toLowerCase()) ||
          invoice['agreementId'].toLowerCase().contains(_searchQuery.toLowerCase());
      
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    return formatter.format(amount);
  }

  @override
  Widget build(BuildContext context) {
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
                _buildPaymentAnalyticsTab(),
                _buildAgreementsTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showGenerateInvoiceDialog(),
        icon: Icon(Icons.add),
        label: Text('New Invoice'),
        backgroundColor: Colors.blue[700],
      ),
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
                      'Client Billing Portal',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    Text(
                      'Invoice & Payment Management',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
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
              hintText: 'Search by invoice, organization, or agreement ID...',
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
          Tab(icon: Icon(Icons.analytics), text: 'Analytics'),
          Tab(icon: Icon(Icons.description), text: 'Agreements'),
        ],
      ),
    );
  }

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
                              'Agreement: ${invoice['agreementId']}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
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
                child: Row(
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
                    onPressed: () => _viewAgreement(invoice),
                    icon: Icon(Icons.description, size: 18),
                    label: Text('Agreement'),
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
          vehicleStats[type] = {'count': 0, 'distance': 0.0, 'cost': 0.0};
        }
        vehicleStats[type]!['count'] += vehicle['count'] as int;
        vehicleStats[type]!['distance'] += (vehicle['distance'] as num).toDouble();
        vehicleStats[type]!['cost'] += (vehicle['cost'] as num).toDouble();
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
            return Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(flex: 2, child: Text(entry.key, style: TextStyle(fontWeight: FontWeight.w600))),
                  Expanded(child: Text('${entry.value['count']} units', style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
                  Expanded(child: Text('${entry.value['distance'].toStringAsFixed(0)} km', style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
                  Expanded(child: Text(_formatCurrency(entry.value['cost']), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue[700]))),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildAgreementsTab() {
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        Text('Active Agreements', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        SizedBox(height: 16),
        ..._getUniqueAgreements().map((agreement) => _buildAgreementCard(agreement)).toList(),
      ],
    );
  }

  List<Map<String, dynamic>> _getUniqueAgreements() {
    Map<String, Map<String, dynamic>> uniqueAgreements = {};
    
    for (var invoice in _invoices) {
      String agreementId = invoice['agreementId'];
      if (!uniqueAgreements.containsKey(agreementId)) {
        uniqueAgreements[agreementId] = {
          'agreementId': invoice['agreementId'],
          'organizationName': invoice['organizationName'],
          'startDate': invoice['agreementStartDate'],
          'endDate': invoice['agreementEndDate'],
          'billingCycle': invoice['billingCycle'],
          'paymentTerms': invoice['paymentTerms'],
          'totalInvoices': 0,
          'totalRevenue': 0.0,
        };
      }
      uniqueAgreements[agreementId]!['totalInvoices'] = (uniqueAgreements[agreementId]!['totalInvoices'] as int) + 1;
      uniqueAgreements[agreementId]!['totalRevenue'] = (uniqueAgreements[agreementId]!['totalRevenue'] as num).toDouble() + (invoice['totalAmount'] as num).toDouble();
    }
    
    return uniqueAgreements.values.toList();
  }

  Widget _buildAgreementCard(Map<String, dynamic> agreement) {
    final startDate = DateTime.parse(agreement['startDate']);
    final endDate = DateTime.parse(agreement['endDate']);
    final daysRemaining = endDate.difference(DateTime.now()).inDays;
    final isExpiringSoon = daysRemaining <= 30 && daysRemaining > 0;
    final isExpired = daysRemaining < 0;

    return Card(
      margin: EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isExpired ? Colors.red.withOpacity(0.3) : isExpiringSoon ? Colors.orange.withOpacity(0.3) : Colors.blue.withOpacity(0.3),
          width: 2,
        ),
      ),
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
                      Text(agreement['agreementId'], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue[700])),
                      SizedBox(height: 6),
                      Text(agreement['organizationName'], style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
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
                else
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
            Divider(height: 24),
            Row(
              children: [
                Expanded(child: _buildAgreementDetail('Start Date', DateFormat('dd MMM yyyy').format(startDate), Icons.start)),
                Expanded(child: _buildAgreementDetail('End Date', DateFormat('dd MMM yyyy').format(endDate), Icons.event)),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildAgreementDetail('Billing Cycle', agreement['billingCycle'], Icons.repeat)),
                Expanded(child: _buildAgreementDetail('Payment Terms', agreement['paymentTerms'], Icons.payment)),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildAgreementDetail('Total Invoices', '${agreement['totalInvoices']}', Icons.receipt_long)),
                Expanded(child: _buildAgreementDetail('Total Revenue', _formatCurrency(agreement['totalRevenue']), Icons.attach_money)),
              ],
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _viewAgreementDocument(agreement),
                  icon: Icon(Icons.description, size: 18),
                  label: Text('View Agreement'),
                  style: TextButton.styleFrom(foregroundColor: Colors.blue[700]),
                ),
                SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _renewAgreement(agreement),
                  icon: Icon(Icons.refresh, size: 18),
                  label: Text('Renew'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700], foregroundColor: Colors.white, elevation: 0),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgreementDetail(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[800])),
          ],
        ),
      ],
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
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          padding: EdgeInsets.all(24),
          child: ListView(
            controller: controller,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(invoice['id'], style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue[700])),
                        SizedBox(height: 4),
                        Text(invoice['organizationName'], style: TextStyle(fontSize: 16, color: Colors.grey[700])),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: _getStatusColor(invoice['status']).withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                    child: Text(invoice['status'], style: TextStyle(color: _getStatusColor(invoice['status']), fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ],
              ),
              Divider(height: 32, thickness: 2),
              _buildSectionTitle('Agreement Details', Icons.description),
              _buildDetailRow('Agreement ID', invoice['agreementId']),
              _buildDetailRow('Billing Cycle', invoice['billingCycle']),
              _buildDetailRow('Payment Terms', invoice['paymentTerms']),
              Divider(height: 32),
              _buildSectionTitle('Important Dates', Icons.calendar_today),
              _buildDetailRow('Invoice Date', DateFormat('dd MMM yyyy').format(DateTime.parse(invoice['date']))),
              _buildDetailRow('Due Date', DateFormat('dd MMM yyyy').format(DateTime.parse(invoice['dueDate']))),
              if (invoice['paidDate'] != null) _buildDetailRow('Paid Date', DateFormat('dd MMM yyyy').format(DateTime.parse(invoice['paidDate']))),
              if (invoice['paymentMode'] != null) _buildDetailRow('Payment Mode', invoice['paymentMode']),
              Divider(height: 32),
              _buildSectionTitle('Fleet Performance', Icons.local_shipping),
              _buildDetailRow('Total Trips', '${invoice['trips']}'),
              _buildDetailRow('Total Distance', '${invoice['totalDistance'].toStringAsFixed(2)} km'),
              _buildDetailRow('Fuel Consumed', '${invoice['totalFuelConsumed'].toStringAsFixed(2)} Liters'),
              _buildDetailRow('Idle Time', '${invoice['totalIdleTime'].toStringAsFixed(1)} hours'),
              _buildDetailRow('Avg Distance/Trip', '${(invoice['totalDistance']/invoice['trips']).toStringAsFixed(2)} km'),
              _buildDetailRow('Avg Fuel/Trip', '${(invoice['totalFuelConsumed']/invoice['trips']).toStringAsFixed(2)} L'),
              Divider(height: 32),
              _buildSectionTitle('Vehicle Breakdown', Icons.directions_car),
              ...((invoice['vehicles'] as List).map((vehicle) {
                return Container(
                  margin: EdgeInsets.only(bottom: 12),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(vehicle['type'], style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          Text('${vehicle['count']} units', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Distance: ${vehicle['distance'].toStringAsFixed(1)} km', style: TextStyle(fontSize: 12)),
                          Text(_formatCurrency(vehicle['cost']), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue[700])),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList()),
              Divider(height: 32),
              _buildSectionTitle('Cost Breakdown', Icons.account_balance_wallet),
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
                  Text(_formatCurrency(invoice['totalAmount']), style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.blue[700])),
                ],
              ),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Amount Paid', style: TextStyle(fontSize: 16, color: Colors.green[700], fontWeight: FontWeight.w600)),
                  Text(_formatCurrency(invoice['amountPaid']), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green[700])),
                ],
              ),
              if (invoice['amountPaid'] < invoice['totalAmount']) ...[
                SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Amount Due', style: TextStyle(fontSize: 16, color: Colors.red[700], fontWeight: FontWeight.w600)),
                    Text(_formatCurrency(invoice['totalAmount'] - invoice['amountPaid']), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red[700])),
                  ],
                ),
              ],
              SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _downloadInvoice(invoice),
                      icon: Icon(Icons.download),
                      label: Text('Download PDF'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700], foregroundColor: Colors.white, padding: EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _shareInvoice(invoice),
                      icon: Icon(Icons.share),
                      label: Text('Share'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.blue[700], padding: EdgeInsets.symmetric(vertical: 14), side: BorderSide(color: Colors.blue[700]!), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    ),
                  ),
                ],
              ),
              if (invoice['amountPaid'] < invoice['totalAmount']) ...[
                SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => _recordPayment(invoice),
                  icon: Icon(Icons.payment),
                  label: Text('Record Payment'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white, padding: EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blue[700]),
          SizedBox(width: 8),
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue[700])),
        ],
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
          Expanded(child: Text(value, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14), textAlign: TextAlign.right)),
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
          Text(label, style: TextStyle(color: color ?? Colors.grey[700], fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(_formatCurrency(amount), style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: color ?? Colors.grey[800])),
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

  void _showGenerateInvoiceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Generate New Invoice'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(decoration: InputDecoration(labelText: 'Organization Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.business))),
              SizedBox(height: 16),
              TextField(decoration: InputDecoration(labelText: 'Agreement ID', border: OutlineInputBorder(), prefixIcon: Icon(Icons.description))),
              SizedBox(height: 16),
              TextField(decoration: InputDecoration(labelText: 'Billing Period', border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_today), suffixIcon: Icon(Icons.arrow_drop_down)), readOnly: true),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invoice generated successfully!'), backgroundColor: Colors.green));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700]),
            child: Text('Generate'),
          ),
        ],
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
          data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: Colors.blue[700]!, onPrimary: Colors.white, onSurface: Colors.black)),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDateRange) {
      setState(() { _selectedDateRange = picked; });
    }
  }

  void _viewAgreement(Map<String, dynamic> invoice) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(children: [Icon(Icons.description, color: Colors.blue[700]), SizedBox(width: 8), Text('Agreement Details')]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Agreement ID', invoice['agreementId']),
              _buildDetailRow('Organization', invoice['organizationName']),
              _buildDetailRow('Start Date', invoice['agreementStartDate']),
              _buildDetailRow('End Date', invoice['agreementEndDate']),
              _buildDetailRow('Billing Cycle', invoice['billingCycle']),
              _buildDetailRow('Payment Terms', invoice['paymentTerms']),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Close')),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _downloadInvoicePDF(invoice);
            },
            icon: Icon(Icons.download),
            label: Text('Download'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700]),
          ),
        ],
      ),
    );
  }

  void _viewAgreementDocument(Map<String, dynamic> agreement) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(children: [Icon(Icons.description, color: Colors.blue[700]), SizedBox(width: 8), Expanded(child: Text('Agreement Document'))]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(agreement['agreementId'], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue[700])),
              SizedBox(height: 16),
              _buildDetailRow('Organization', agreement['organizationName']),
              _buildDetailRow('Valid From', agreement['startDate']),
              _buildDetailRow('Valid Until', agreement['endDate']),
              _buildDetailRow('Billing Cycle', agreement['billingCycle']),
              _buildDetailRow('Payment Terms', agreement['paymentTerms']),
              _buildDetailRow('Total Invoices', '${agreement['totalInvoices']}'),
              _buildDetailRow('Total Revenue', _formatCurrency(agreement['totalRevenue'])),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue[200]!)),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue[700], size: 20),
                    SizedBox(width: 8),
                    Expanded(child: Text('Full agreement document with terms and conditions is available for download', style: TextStyle(fontSize: 12, color: Colors.blue[900]))),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Close')),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _downloadAgreementPDF(agreement);
            },
            icon: Icon(Icons.download),
            label: Text('Download PDF'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700]),
          ),
        ],
      ),
    );
  }

  void _renewAgreement(Map<String, dynamic> agreement) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Renew Agreement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Do you want to renew the agreement ${agreement['agreementId']}?'),
            SizedBox(height: 16),
            TextField(decoration: InputDecoration(labelText: 'New End Date', border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today)), readOnly: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Agreement renewal initiated'), backgroundColor: Colors.green));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('Renew'),
          ),
        ],
      ),
    );
  }

  void _downloadInvoice(Map<String, dynamic> invoice) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloading invoice ${invoice['id']} as PDF...'), action: SnackBarAction(label: 'View', onPressed: () {})));
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
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sending invoice via email...')));
              },
            ),
            ListTile(
              leading: Icon(Icons.message, color: Colors.green),
              title: Text('WhatsApp'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sharing invoice via WhatsApp...')));
              },
            ),
            ListTile(
              leading: Icon(Icons.link, color: Colors.orange),
              title: Text('Copy Link'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invoice link copied to clipboard')));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _recordPayment(Map<String, dynamic> invoice) {
    final amountDue = invoice['totalAmount'] - invoice['amountPaid'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Record Payment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Invoice: ${invoice['id']}', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Amount Due: ${_formatCurrency(amountDue)}'),
              SizedBox(height: 16),
              TextField(decoration: InputDecoration(labelText: 'Payment Amount', border: OutlineInputBorder(), prefixText: '₹ '), keyboardType: TextInputType.number),
              SizedBox(height: 16),
              TextField(decoration: InputDecoration(labelText: 'Payment Date', border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today)), readOnly: true),
              SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: 'Payment Mode', border: OutlineInputBorder()),
                items: ['Bank Transfer', 'Cheque', 'Cash', 'Online Payment', 'UPI'].map((mode) => DropdownMenuItem(value: mode, child: Text(mode))).toList(),
                onChanged: (value) {},
              ),
              SizedBox(height: 16),
              TextField(decoration: InputDecoration(labelText: 'Transaction Reference', border: OutlineInputBorder())),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                invoice['amountPaid'] = invoice['totalAmount'];
                invoice['status'] = 'Paid';
                invoice['paidDate'] = DateFormat('yyyy-MM-dd').format(DateTime.now());
              });
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment recorded successfully!'), backgroundColor: Colors.green));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('Record Payment'),
          ),
        ],
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
              subtitle: Text('All invoice data with details'),
              onTap: () {
                Navigator.pop(context);
                _exportToExcel();
              },
            ),
            ListTile(
              leading: Icon(Icons.picture_as_pdf, color: Colors.red),
              title: Text('Export as PDF'),
              subtitle: Text('Summary report'),
              onTap: () {
                Navigator.pop(context);
                _exportToPDF();
              },
            ),
            ListTile(
              leading: Icon(Icons.insert_drive_file, color: Colors.blue),
              title: Text('Export as CSV'),
              subtitle: Text('Raw data export'),
              onTap: () {
                Navigator.pop(context);
                _exportToCSV();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportToCSV() async {
    try {
      List<List<dynamic>> rows = [];
      
      // Header row
      rows.add([
        'Invoice ID',
        'Organization',
        'Agreement ID',
        'Date',
        'Due Date',
        'Status',
        'Amount',
        'GST',
        'Total Amount',
        'Amount Paid',
        'Trips',
        'Distance (km)',
        'Fuel (L)',
      ]);
      
      // Data rows
      for (var invoice in _filteredInvoices) {
        rows.add([
          invoice['id'],
          invoice['organizationName'],
          invoice['agreementId'],
          invoice['date'],
          invoice['dueDate'],
          invoice['status'],
          invoice['amount'],
          invoice['gstAmount'],
          invoice['totalAmount'],
          invoice['amountPaid'],
          invoice['trips'],
          invoice['totalDistance'],
          invoice['totalFuelConsumed'],
        ]);
      }
      
      String csv = const ListToCsvConverter().convert(rows);
      await _saveAndShareFile(csv, 'billing_invoices_${DateTime.now().millisecondsSinceEpoch}.csv', 'text/csv');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV exported successfully!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting CSV: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _exportToExcel() async {
    try {
      var excel = excel_pkg.Excel.createExcel();
      var sheet = excel['Invoices'];
      
      // Header row with styling
      sheet.appendRow([
        excel_pkg.TextCellValue('Invoice ID'),
        excel_pkg.TextCellValue('Organization'),
        excel_pkg.TextCellValue('Agreement ID'),
        excel_pkg.TextCellValue('Date'),
        excel_pkg.TextCellValue('Due Date'),
        excel_pkg.TextCellValue('Status'),
        excel_pkg.TextCellValue('Amount'),
        excel_pkg.TextCellValue('GST'),
        excel_pkg.TextCellValue('Total Amount'),
        excel_pkg.TextCellValue('Amount Paid'),
        excel_pkg.TextCellValue('Trips'),
        excel_pkg.TextCellValue('Distance (km)'),
        excel_pkg.TextCellValue('Fuel (L)'),
      ]);
      
      // Data rows
      for (var invoice in _filteredInvoices) {
        sheet.appendRow([
          excel_pkg.TextCellValue(invoice['id'].toString()),
          excel_pkg.TextCellValue(invoice['organizationName'].toString()),
          excel_pkg.TextCellValue(invoice['agreementId'].toString()),
          excel_pkg.TextCellValue(invoice['date'].toString()),
          excel_pkg.TextCellValue(invoice['dueDate'].toString()),
          excel_pkg.TextCellValue(invoice['status'].toString()),
          excel_pkg.DoubleCellValue((invoice['amount'] as num).toDouble()),
          excel_pkg.DoubleCellValue((invoice['gstAmount'] as num).toDouble()),
          excel_pkg.DoubleCellValue((invoice['totalAmount'] as num).toDouble()),
          excel_pkg.DoubleCellValue((invoice['amountPaid'] as num).toDouble()),
          excel_pkg.IntCellValue(invoice['trips'] as int),
          excel_pkg.DoubleCellValue((invoice['totalDistance'] as num).toDouble()),
          excel_pkg.DoubleCellValue((invoice['totalFuelConsumed'] as num).toDouble()),
        ]);
      }
      
      var fileBytes = excel.encode();
      if (fileBytes != null) {
        await _saveAndShareFile(
          String.fromCharCodes(fileBytes),
          'billing_invoices_${DateTime.now().millisecondsSinceEpoch}.xlsx',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          isBytes: true,
          bytes: fileBytes,
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel exported successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting Excel: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _exportToPDF() async {
    try {
      final pdf = pw.Document();
      
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Text('Billing Invoices Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 20),
              pw.Table.fromTextArray(
                headers: [
                  'Invoice ID',
                  'Organization',
                  'Date',
                  'Status',
                  'Total Amount (INR)',
                  'Paid (INR)',
                  'Trips',
                ],
                data: _filteredInvoices.map((invoice) => [
                  invoice['id'],
                  invoice['organizationName'],
                  invoice['date'],
                  invoice['status'],
                  (invoice['totalAmount'] as num).toDouble().toStringAsFixed(2),
                  (invoice['amountPaid'] as num).toDouble().toStringAsFixed(2),
                  invoice['trips'].toString(),
                ]).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                cellAlignment: pw.Alignment.centerLeft,
              ),
            ];
          },
        ),
      );
      
      final bytes = await pdf.save();
      await _saveAndShareFile(
        String.fromCharCodes(bytes),
        'billing_invoices_${DateTime.now().millisecondsSinceEpoch}.pdf',
        'application/pdf',
        isBytes: true,
        bytes: bytes,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF exported successfully!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting PDF: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _saveAndShareFile(String content, String fileName, String mimeType, {bool isBytes = false, List<int>? bytes}) async {
    try {
      if (kIsWeb) {
        // For web, trigger download
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File ready for download: $fileName')),
        );
      } else {
        // For mobile/desktop, save and share
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$fileName');
        
        if (isBytes && bytes != null) {
          await file.writeAsBytes(bytes);
        } else {
          await file.writeAsString(content);
        }
        
        // Share the file
        await Share.shareXFiles(
          [XFile(file.path, mimeType: mimeType)],
          subject: 'Billing Invoices Export',
          text: 'Here is your billing invoices export',
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving file: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _downloadInvoicePDF(Map<String, dynamic> invoice) async {
    try {
      final pdf = pw.Document();
      
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('INVOICE', style: pw.TextStyle(fontSize: 32, fontWeight: pw.FontWeight.bold)),
                        pw.Text(invoice['id'], style: pw.TextStyle(fontSize: 16, color: PdfColors.blue700)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Date: ${invoice['date']}'),
                        pw.Text('Due Date: ${invoice['dueDate']}'),
                      ],
                    ),
                  ],
                ),
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 20),
                
                pw.Text('BILL TO:', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text(invoice['organizationName'], style: pw.TextStyle(fontSize: 16)),
                pw.Text('Agreement: ${invoice['agreementId']}'),
                pw.SizedBox(height: 20),
                
                pw.Table.fromTextArray(
                  headers: ['Description', 'Amount (INR)'],
                  data: [
                    ['Base Charges', (invoice['charges']['baseCharges'] as num).toDouble().toStringAsFixed(2)],
                    ['Per KM Charges', (invoice['charges']['perKmCharges'] as num).toDouble().toStringAsFixed(2)],
                    ['Fuel Surcharge', (invoice['charges']['fuelSurcharge'] as num).toDouble().toStringAsFixed(2)],
                    ['Toll Charges', (invoice['charges']['tollCharges'] as num).toDouble().toStringAsFixed(2)],
                    ['Waiting Charges', (invoice['charges']['waitingCharges'] as num).toDouble().toStringAsFixed(2)],
                    ['Loading/Unloading', (invoice['charges']['loadingUnloadingCharges'] as num).toDouble().toStringAsFixed(2)],
                  ],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 20),
                
                pw.Divider(),
                _buildPdfRow('Subtotal:', (invoice['amount'] as num).toDouble().toStringAsFixed(2) + ' INR'),
                _buildPdfRow('GST (18%):', (invoice['gstAmount'] as num).toDouble().toStringAsFixed(2) + ' INR'),
                pw.Divider(thickness: 2),
                _buildPdfRow('TOTAL:', (invoice['totalAmount'] as num).toDouble().toStringAsFixed(2) + ' INR'),
                _buildPdfRow('Amount Paid:', (invoice['amountPaid'] as num).toDouble().toStringAsFixed(2) + ' INR'),
                _buildPdfRow('Balance Due:', ((invoice['totalAmount'] as num).toDouble() - (invoice['amountPaid'] as num).toDouble()).toStringAsFixed(2) + ' INR'),
                
                pw.SizedBox(height: 30),
                pw.Text('TRIP SUMMARY', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                _buildPdfRow('Total Trips:', '${invoice['trips']}'),
                _buildPdfRow('Total Distance:', '${(invoice['totalDistance'] as num).toDouble().toStringAsFixed(2)} km'),
                _buildPdfRow('Fuel Consumed:', '${(invoice['totalFuelConsumed'] as num).toDouble().toStringAsFixed(2)} L'),
                
                pw.Spacer(),
                pw.Divider(),
                pw.Text('Thank you for your business!', style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
              ],
            );
          },
        ),
      );
      
      final bytes = await pdf.save();
      await _saveAndShareFile(
        String.fromCharCodes(bytes),
        'invoice_${invoice['id']}_${DateTime.now().millisecondsSinceEpoch}.pdf',
        'application/pdf',
        isBytes: true,
        bytes: bytes,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invoice PDF downloaded successfully!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error downloading invoice: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _downloadAgreementPDF(Map<String, dynamic> agreement) async {
    try {
      final pdf = pw.Document();
      
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('SERVICE AGREEMENT', style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                pw.Text(agreement['agreementId'], style: pw.TextStyle(fontSize: 16, color: PdfColors.blue700)),
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 20),
                
                pw.Text('AGREEMENT DETAILS', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                _buildPdfRow('Organization:', agreement['organizationName']),
                _buildPdfRow('Agreement ID:', agreement['agreementId']),
                _buildPdfRow('Start Date:', agreement['startDate']),
                _buildPdfRow('End Date:', agreement['endDate']),
                _buildPdfRow('Billing Cycle:', agreement['billingCycle']),
                _buildPdfRow('Payment Terms:', agreement['paymentTerms']),
                _buildPdfRow('Total Invoices:', '${agreement['totalInvoices']}'),
                _buildPdfRow('Total Revenue:', '${(agreement['totalRevenue'] as num).toDouble().toStringAsFixed(2)} INR'),
                
                pw.SizedBox(height: 30),
                pw.Text('TERMS AND CONDITIONS', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                pw.Text('1. Service Provider agrees to provide fleet management services as per the agreed terms.'),
                pw.SizedBox(height: 5),
                pw.Text('2. Payment shall be made according to the billing cycle mentioned above.'),
                pw.SizedBox(height: 5),
                pw.Text('3. This agreement is valid from the start date to the end date mentioned above.'),
                pw.SizedBox(height: 5),
                pw.Text('4. Any modifications to this agreement must be made in writing and signed by both parties.'),
                
                pw.Spacer(),
                pw.Divider(),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Service Provider', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 30),
                        pw.Text('_____________________'),
                        pw.Text('Signature & Date'),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Client', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 30),
                        pw.Text('_____________________'),
                        pw.Text('Signature & Date'),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
      
      final bytes = await pdf.save();
      await _saveAndShareFile(
        String.fromCharCodes(bytes),
        'agreement_${agreement['agreementId']}_${DateTime.now().millisecondsSinceEpoch}.pdf',
        'application/pdf',
        isBytes: true,
        bytes: bytes,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Agreement PDF downloaded successfully!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error downloading agreement: $e'), backgroundColor: Colors.red),
      );
    }
  }

  pw.Widget _buildPdfRow(String label, String value) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        children: [
          pw.Container(
            width: 150,
            child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ),
          pw.Expanded(
            child: pw.Text(value),
          ),
        ],
      ),
    );
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
                    setState(() { _selectedVehicleType = type; });
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
            SizedBox(height: 20),
            Text('Invoice Status', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['All', 'Paid', 'Partially Paid', 'Pending', 'Overdue'].map((status) {
                return ChoiceChip(
                  label: Text(status),
                  selected: _selectedFilter == status,
                  onSelected: (selected) {
                    setState(() {
                      _selectedFilter = status;
                    });
                    Navigator.pop(context);
                  },
                  backgroundColor: Colors.white,
                  selectedColor: Colors.blue.withOpacity(0.2),
                  labelStyle: TextStyle(
                    color: _selectedFilter == status ? Colors.blue[700] : Colors.black87,
                    fontWeight: _selectedFilter == status ? FontWeight.bold : FontWeight.normal,
                  ),
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('All filters cleared')),
                      );
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
}