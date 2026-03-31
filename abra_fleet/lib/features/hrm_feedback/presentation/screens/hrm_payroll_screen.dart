// lib/features/hrm_feedback/presentation/screens/hrm_payroll_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
// ignore: avoid_web_libraries_in_flutter
import 'package:universal_html/html.dart' as html;

import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/core/services/safe_api_service.dart';
import 'package:abra_fleet/core/services/error_handler_service.dart';

class HrmPayrollScreen extends StatefulWidget {
  const HrmPayrollScreen({super.key});

  @override
  State<HrmPayrollScreen> createState() => _HrmPayrollScreenState();
}

class _HrmPayrollScreenState extends State<HrmPayrollScreen> with ErrorHandlerMixin {
  final SafeApiService _safeApi = SafeApiService();
  
  List<Map<String, dynamic>> _payrollEntries = [];
  List<Map<String, dynamic>> _employees = [];
  Set<String> _selectedPayrollIds = {};
  bool _isLoading = true;
  bool _isLoadingEmployees = false;
  bool _selectAll = false;

  @override
  void initState() {
    super.initState();
    _fetchPayrollEntries();
  }

  Future<void> _fetchPayrollEntries() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _safeApi.safeGet(
        '/api/hrm/payroll',
        context: 'Fetch Payroll Entries',
        fallback: {'success': false, 'data': []},
      );

      if (response['success'] == true && mounted) {
        setState(() {
          _payrollEntries = List<Map<String, dynamic>>.from(response['data'] ?? []);
        });
      }
    } catch (e) {
      handleSilentError(e, context: 'Fetch Payroll Entries');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchEmployees() async {
    if (_employees.isNotEmpty) return;
    
    setState(() {
      _isLoadingEmployees = true;
    });

    try {
      final response = await _safeApi.safeGet(
        '/api/hrm/employees',
        queryParams: {'status': 'active'},
        context: 'Fetch Employees',
        fallback: {'success': false, 'data': []},
      );

      if (response['success'] == true && mounted) {
        setState(() {
          _employees = List<Map<String, dynamic>>.from(response['data'] ?? []);
        });
      }
    } catch (e) {
      handleSilentError(e, context: 'Fetch Employees');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingEmployees = false;
        });
      }
    }
  }

  Future<void> _deletePayrollEntry(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text('Confirm Delete'),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete this payroll entry? This action cannot be undone.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await _safeApi.safeDelete(
        '/api/hrm/payroll/$id',
        context: 'Delete Payroll Entry',
        fallback: {'success': false},
      );

      if (response['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Payroll entry deleted successfully'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
        _fetchPayrollEntries();
        _selectedPayrollIds.remove(id);
      }
    } catch (e) {
      handleSilentError(e, context: 'Delete Payroll Entry');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete payroll entry'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAddPayrollDialog() async {
    await _fetchEmployees();
    
    if (!mounted) return;

    final formKey = GlobalKey<FormState>();
    String? selectedEmployeeId;
    double amount = 0.0;
    DateTime? payDate;
    String comment = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.monetization_on, color: Colors.green.shade700, size: 24),
              ),
              const SizedBox(width: 12),
              const Text('Add New Payroll Entry'),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose Employee',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  _isLoadingEmployees
                      ? const Center(child: CircularProgressIndicator())
                      : DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          hint: const Text('Select Employee'),
                          value: selectedEmployeeId,
                          items: _employees.map((emp) {
                            return DropdownMenuItem<String>(
                              value: emp['_id'].toString(),
                              child: Text(emp['name'] ?? 'Unknown'),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedEmployeeId = value;
                            });
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please select an employee';
                            }
                            return null;
                          },
                        ),
                  const SizedBox(height: 16),

                  const Text(
                    'Salary Amount (Rs.)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Enter salary amount',
                      prefixIcon: Icon(Icons.currency_rupee, color: Colors.green.shade700, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter salary amount';
                      }
                      final parsed = double.tryParse(value);
                      if (parsed == null || parsed <= 0) {
                        return 'Please enter a valid amount';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      amount = double.tryParse(value) ?? 0.0;
                    },
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Pay Date',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: Colors.green.shade700,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setDialogState(() {
                          payDate = picked;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: Colors.green.shade700, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            payDate != null
                                ? DateFormat('dd-MM-yyyy').format(payDate!)
                                : 'Select Pay Date',
                            style: TextStyle(
                              color: payDate != null ? Colors.black : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Comment (Optional)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Enter any comments or notes',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    onChanged: (value) {
                      comment = value;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
              label: const Text('Cancel'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  if (payDate == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please select pay date'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }

                  try {
                    final response = await _safeApi.safePost(
                      '/api/hrm/payroll',
                      body: {
                        'employee_id': selectedEmployeeId,
                        'amount': amount,
                        'pay_date': payDate!.toIso8601String(),
                        'comment': comment.trim(),
                      },
                      context: 'Add Payroll Entry',
                      fallback: {'success': false},
                    );

                    if (response['success'] == true && mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.white),
                              SizedBox(width: 12),
                              Text('Payroll entry added successfully'),
                            ],
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                      _fetchPayrollEntries();
                    }
                  } catch (e) {
                    handleSilentError(e, context: 'Add Payroll Entry');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Failed to add payroll entry'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditPayrollDialog(Map<String, dynamic> payroll) async {
    await _fetchEmployees();
    
    if (!mounted) return;

    final formKey = GlobalKey<FormState>();
    String selectedEmployeeId = payroll['employee_id'].toString();
    double amount = (payroll['amount'] as num).toDouble();
    DateTime payDate = DateTime.parse(payroll['pay_date']);
    String comment = payroll['comment'] ?? '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.edit_note, color: Colors.purple.shade700, size: 24),
              ),
              const SizedBox(width: 12),
              const Text('Edit Payroll Entry'),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose Employee',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  _isLoadingEmployees
                      ? const Center(child: CircularProgressIndicator())
                      : DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          value: selectedEmployeeId,
                          items: _employees.map((emp) {
                            return DropdownMenuItem<String>(
                              value: emp['_id'].toString(),
                              child: Text(emp['name'] ?? 'Unknown'),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() {
                                selectedEmployeeId = value;
                              });
                            }
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please select an employee';
                            }
                            return null;
                          },
                        ),
                  const SizedBox(height: 16),

                  const Text(
                    'Salary Amount (Rs.)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: amount.toStringAsFixed(2),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Enter salary amount',
                      prefixIcon: Icon(Icons.currency_rupee, color: Colors.purple.shade700, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter salary amount';
                      }
                      final parsed = double.tryParse(value);
                      if (parsed == null || parsed <= 0) {
                        return 'Please enter a valid amount';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      amount = double.tryParse(value) ?? 0.0;
                    },
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Pay Date',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: payDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: Colors.purple.shade700,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setDialogState(() {
                          payDate = picked;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: Colors.purple.shade700, size: 20),
                          const SizedBox(width: 12),
                          Text(DateFormat('dd-MM-yyyy').format(payDate)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Comment (Optional)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: comment,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Enter any comments or notes',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    onChanged: (value) {
                      comment = value;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
              label: const Text('Cancel'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  try {
                    final response = await _safeApi.safePut(
                      '/api/hrm/payroll/${payroll['_id']}',
                      body: {
                        'employee_id': selectedEmployeeId,
                        'amount': amount,
                        'pay_date': payDate.toIso8601String(),
                        'comment': comment.trim(),
                      },
                      context: 'Update Payroll Entry',
                      fallback: {'success': false},
                    );

                    if (response['success'] == true && mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.white),
                              SizedBox(width: 12),
                              Text('Payroll entry updated successfully'),
                            ],
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                      _fetchPayrollEntries();
                    }
                  } catch (e) {
                    handleSilentError(e, context: 'Update Payroll Entry');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Failed to update payroll entry'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              icon: const Icon(Icons.update),
              label: const Text('Update'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _exportSelectedToExcel() {
    if (_selectedPayrollIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one payroll entry to export'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final selectedEntries = _payrollEntries
          .where((entry) => _selectedPayrollIds.contains(entry['_id'].toString()))
          .toList();

      // Build Excel HTML
      final StringBuffer htmlContent = StringBuffer();
      htmlContent.write('''
        <html xmlns:o="urn:schemas-microsoft-com:office:office"
              xmlns:x="urn:schemas-microsoft-com:office:excel"
              xmlns="http://www.w3.org/TR/REC-html40">
        <head><meta charset="UTF-8"></head>
        <body>
        <table border="1">
          <tr>
            <th>Payroll ID</th>
            <th>Employee Name</th>
            <th>Salary Amount (Rs.)</th>
            <th>Pay Date</th>
            <th>Comment</th>
          </tr>
      ''');

      for (var entry in selectedEntries) {
        final id = entry['_id']?.toString() ?? '';
        final employeeName = entry['employee_name'] ?? 'Unknown';
        final amount = (entry['amount'] as num?)?.toStringAsFixed(2) ?? '0.00';
        final payDate = entry['pay_date'] != null
            ? DateFormat('dd-MM-yyyy').format(DateTime.parse(entry['pay_date']))
            : '';
        final comment = entry['comment'] ?? '';

        htmlContent.write('''
          <tr>
            <td>$id</td>
            <td>$employeeName</td>
            <td>$amount</td>
            <td>$payDate</td>
            <td>$comment</td>
          </tr>
        ''');
      }

      htmlContent.write('</table></body></html>');

      if (kIsWeb) {
        final bytes = utf8.encode(htmlContent.toString());
        final blob = html.Blob([bytes], 'application/vnd.ms-excel');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', 'selected_payroll_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xls')
          ..click();
        html.Url.revokeObjectUrl(url);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.download_done, color: Colors.white),
                const SizedBox(width: 12),
                Text('Exported ${selectedEntries.length} payroll entries'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Excel export is only available on web'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      handleSilentError(e, context: 'Export Excel');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to export Excel'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _toggleSelectAll() {
    setState(() {
      _selectAll = !_selectAll;
      if (_selectAll) {
        _selectedPayrollIds = _payrollEntries
            .map((entry) => entry['_id'].toString())
            .toSet();
      } else {
        _selectedPayrollIds.clear();
      }
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedPayrollIds.contains(id)) {
        _selectedPayrollIds.remove(id);
        _selectAll = false;
      } else {
        _selectedPayrollIds.add(id);
        if (_selectedPayrollIds.length == _payrollEntries.length) {
          _selectAll = true;
        }
      }
    });
  }

  String _formatCurrency(num amount) {
    final formatter = NumberFormat.currency(
      symbol: '₹ ',
      decimalDigits: 2,
      locale: 'en_IN',
    );
    return formatter.format(amount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.account_balance_wallet, color: Colors.orange.shade700, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Payroll Management',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage employee salary payments',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_selectedPayrollIds.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_selectedPayrollIds.length} selected',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _showAddPayrollDialog,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Add Payroll'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _exportSelectedToExcel,
                  icon: const Icon(Icons.file_download),
                  label: const Text('Export Selected'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _payrollEntries.isEmpty
                    ? _buildEmptyState()
                    : _buildPayrollTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No Payroll Entries Found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Click "Add Payroll" to create a payroll entry',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayrollTable() {
    return Container(
      margin: const EdgeInsets.all(24),
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 50,
                  child: Checkbox(
                    value: _selectAll,
                    onChanged: (value) => _toggleSelectAll(),
                    activeColor: Colors.orange.shade700,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Payroll ID',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Employee Name',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Salary Amount',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Pay Date',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Comment',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Actions',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(0),
              itemCount: _payrollEntries.length,
              itemBuilder: (context, index) {
                final payroll = _payrollEntries[index];
                final isEven = index % 2 == 0;
                final id = payroll['_id'].toString();
                final isSelected = _selectedPayrollIds.contains(id);
                
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? Colors.orange.shade50 
                        : (isEven ? Colors.white : Colors.grey.shade50),
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 50,
                        child: Checkbox(
                          value: isSelected,
                          onChanged: (value) => _toggleSelection(id),
                          activeColor: Colors.orange.shade700,
                        ),
                      ),
                      
                      Expanded(
                        flex: 1,
                        child: Text(
                          id.substring(0, 8),
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(Icons.person, size: 16, color: Colors.blue.shade700),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                payroll['employee_name'] ?? 'Unknown',
                                style: const TextStyle(fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Icon(Icons.currency_rupee, size: 14, color: Colors.green.shade600),
                            const SizedBox(width: 4),
                            Text(
                              _formatCurrency(payroll['amount'] ?? 0),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Text(
                              payroll['pay_date'] != null
                                  ? DateFormat('dd-MM-yyyy').format(DateTime.parse(payroll['pay_date']))
                                  : 'N/A',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      
                      Expanded(
                        flex: 2,
                        child: Text(
                          payroll['comment'] ?? '-',
                          style: const TextStyle(fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      
                      Expanded(
                        flex: 2,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: () => _showEditPayrollDialog(payroll),
                              icon: const Icon(Icons.edit_note),
                              color: Colors.purple.shade700,
                              tooltip: 'Edit',
                              iconSize: 22,
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => _deletePayrollEntry(id),
                              icon: const Icon(Icons.delete_outline),
                              color: Colors.red.shade700,
                              tooltip: 'Delete',
                              iconSize: 22,
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}