// lib/features/hrm_feedback/presentation/screens/hrm_leave_requests_screen.dart

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

class HrmLeaveRequestsScreen extends StatefulWidget {
  const HrmLeaveRequestsScreen({super.key});

  @override
  State<HrmLeaveRequestsScreen> createState() => _HrmLeaveRequestsScreenState();
}

class _HrmLeaveRequestsScreenState extends State<HrmLeaveRequestsScreen> with ErrorHandlerMixin {
  final SafeApiService _safeApi = SafeApiService();
  
  List<Map<String, dynamic>> _leaveRequests = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _employees = <Map<String, dynamic>>[];
  bool _isLoading = true;
  bool _isLoadingEmployees = false;

  @override
  void initState() {
    super.initState();
    _fetchLeaveRequests();
  }

  Future<void> _fetchLeaveRequests() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _safeApi.safeGet(
        '/api/hrm/leaves',
        context: 'Fetch Leave Requests',
        fallback: {'success': false, 'data': []},
      );

      if (response['success'] == true && mounted) {
        final data = response['data'];
        setState(() {
          _leaveRequests = data != null 
              ? List<Map<String, dynamic>>.from(data)
              : <Map<String, dynamic>>[];
        });
      } else if (mounted) {
        setState(() {
          _leaveRequests = <Map<String, dynamic>>[];
        });
      }
    } catch (e) {
      handleSilentError(e, context: 'Fetch Leave Requests');
      if (mounted) {
        setState(() {
          _leaveRequests = <Map<String, dynamic>>[];
        });
      }
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
        final data = response['data'];
        setState(() {
          _employees = data != null 
              ? List<Map<String, dynamic>>.from(data)
              : <Map<String, dynamic>>[];
        });
      } else if (mounted) {
        setState(() {
          _employees = <Map<String, dynamic>>[];
        });
      }
    } catch (e) {
      handleSilentError(e, context: 'Fetch Employees');
      if (mounted) {
        setState(() {
          _employees = <Map<String, dynamic>>[];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingEmployees = false;
        });
      }
    }
  }

  Future<void> _deleteLeaveRequest(String id) async {
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
          'Are you sure you want to delete this leave request? This action cannot be undone.',
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
        '/api/hrm/leaves/$id',
        context: 'Delete Leave Request',
        fallback: {'success': false},
      );

      if (response['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Leave request deleted successfully'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
        _fetchLeaveRequests();
      }
    } catch (e) {
      handleSilentError(e, context: 'Delete Leave Request');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete leave request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAddLeaveDialog() async {
    await _fetchEmployees();
    
    if (!mounted) return;

    final formKey = GlobalKey<FormState>();
    String? selectedEmployeeId;
    DateTime? startDate;
    DateTime? endDate;
    String reason = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.add_task, color: Colors.teal.shade700, size: 24),
              ),
              const SizedBox(width: 12),
              const Text('Add New Leave Request'),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info banner explaining the workflow
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'New leave requests will be set to "Pending". Use Edit to approve/reject.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
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
                          items: _employees.where((emp) => emp != null).map((emp) {
                            return DropdownMenuItem<String>(
                              value: emp['_id']?.toString() ?? '',
                              child: Text(emp['name']?.toString() ?? 'Unknown'),
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
                    'Start Date',
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
                                primary: Colors.teal.shade700,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setDialogState(() {
                          startDate = picked;
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
                          Icon(Icons.calendar_today, color: Colors.teal.shade700, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            startDate != null
                                ? DateFormat('dd-MM-yyyy').format(startDate!)
                                : 'Select Start Date',
                            style: TextStyle(
                              color: startDate != null ? Colors.black : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'End Date',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: startDate ?? DateTime.now(),
                        firstDate: startDate ?? DateTime(2020),
                        lastDate: DateTime(2030),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: Colors.teal.shade700,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setDialogState(() {
                          endDate = picked;
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
                          Icon(Icons.event, color: Colors.teal.shade700, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            endDate != null
                                ? DateFormat('dd-MM-yyyy').format(endDate!)
                                : 'Select End Date',
                            style: TextStyle(
                              color: endDate != null ? Colors.black : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Reason',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Enter reason for leave',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a reason';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      reason = value;
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
                  if (startDate == null || endDate == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please select start and end dates'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }

                  try {
                    final response = await _safeApi.safePost(
                      '/api/hrm/leaves',
                      body: {
                        'employee_id': selectedEmployeeId,
                        'start_date': startDate!.toIso8601String(),
                        'end_date': endDate!.toIso8601String(),
                        'reason': reason.trim(),
                        'status': 'pending', // ✅ AUTOMATICALLY SET TO PENDING
                      },
                      context: 'Add Leave Request',
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
                              Text('Leave request added with Pending status'),
                            ],
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                      _fetchLeaveRequests();
                    }
                  } catch (e) {
                    handleSilentError(e, context: 'Add Leave Request');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Failed to add leave request'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('Save as Pending'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditLeaveDialog(Map<String, dynamic> leave) async {
    await _fetchEmployees();
    
    if (!mounted) return;

    final formKey = GlobalKey<FormState>();
    String selectedEmployeeId = leave['employee_id'].toString();
    DateTime startDate = DateTime.parse(leave['start_date']);
    DateTime endDate = DateTime.parse(leave['end_date']);
    String reason = leave['reason'] ?? '';
    String status = leave['status'] ?? 'pending';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.edit_note, color: Colors.blue.shade700, size: 24),
              ),
              const SizedBox(width: 12),
              const Text('Edit Leave Request'),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info banner for editing
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.admin_panel_settings, color: Colors.amber.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You can now approve or reject this leave request by changing the status below.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
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
                          items: _employees.where((emp) => emp != null).map((emp) {
                            return DropdownMenuItem<String>(
                              value: emp['_id']?.toString() ?? '',
                              child: Text(emp['name']?.toString() ?? 'Unknown'),
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
                    'Start Date',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: startDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: Colors.blue.shade700,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setDialogState(() {
                          startDate = picked;
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
                          Icon(Icons.calendar_today, color: Colors.blue.shade700, size: 20),
                          const SizedBox(width: 12),
                          Text(DateFormat('dd-MM-yyyy').format(startDate)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'End Date',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: endDate,
                        firstDate: startDate,
                        lastDate: DateTime(2030),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: Colors.blue.shade700,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setDialogState(() {
                          endDate = picked;
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
                          Icon(Icons.event, color: Colors.blue.shade700, size: 20),
                          const SizedBox(width: 12),
                          Text(DateFormat('dd-MM-yyyy').format(endDate)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Reason',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: reason,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Enter reason for leave',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a reason';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      reason = value;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ✅ STATUS FIELD - ONLY IN EDIT DIALOG
                  const Text(
                    'Status (Approve/Reject)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    value: status,
                    items: const [
                      DropdownMenuItem(
                        value: 'pending',
                        child: Row(
                          children: [
                            Icon(Icons.pending, color: Colors.orange, size: 18),
                            SizedBox(width: 8),
                            Text('Pending'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'approved',
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green, size: 18),
                            SizedBox(width: 8),
                            Text('Approved'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'rejected',
                        child: Row(
                          children: [
                            Icon(Icons.cancel, color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Text('Rejected'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          status = value;
                        });
                      }
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
                      '/api/hrm/leaves/${leave['_id']}',
                      body: {
                        'employee_id': selectedEmployeeId,
                        'start_date': startDate.toIso8601String(),
                        'end_date': endDate.toIso8601String(),
                        'reason': reason.trim(),
                        'status': status,
                      },
                      context: 'Update Leave Request',
                      fallback: {'success': false},
                    );

                    if (response['success'] == true && mounted) {
                      Navigator.pop(context);
                      
                      // Show different message based on status change
                      String message = 'Leave request updated successfully';
                      if (status == 'approved') {
                        message = '✅ Leave request approved successfully';
                      } else if (status == 'rejected') {
                        message = '❌ Leave request rejected';
                      }
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              Icon(
                                status == 'approved' ? Icons.check_circle : 
                                status == 'rejected' ? Icons.cancel : Icons.update,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 12),
                              Text(message),
                            ],
                          ),
                          backgroundColor: status == 'approved' ? Colors.green : 
                                          status == 'rejected' ? Colors.red : Colors.blue,
                        ),
                      );
                      _fetchLeaveRequests();
                    }
                  } catch (e) {
                    handleSilentError(e, context: 'Update Leave Request');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Failed to update leave request'),
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
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _exportToCSV() {
    if (_leaveRequests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No data to export'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final List<String> csvRows = [];
      csvRows.add('"Request ID","Employee Name","Start Date","End Date","Reason","Status"');
      
      for (var leave in _leaveRequests) {
        if (leave == null) continue; // Skip null entries
        
        final id = leave['_id']?.toString() ?? '';
        final employeeName = leave['employee_name']?.toString() ?? 'Unknown';
        final startDate = leave['start_date'] != null 
            ? DateFormat('yyyy-MM-dd').format(DateTime.parse(leave['start_date'].toString()))
            : '';
        final endDate = leave['end_date'] != null 
            ? DateFormat('yyyy-MM-dd').format(DateTime.parse(leave['end_date'].toString()))
            : '';
        final reason = (leave['reason']?.toString() ?? '').replaceAll('"', '""');
        final status = leave['status']?.toString() ?? '';
        
        csvRows.add('"$id","$employeeName","$startDate","$endDate","$reason","$status"');
      }
      
      final csvString = csvRows.join('\n');
      
      if (kIsWeb) {
        final bytes = utf8.encode(csvString);
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', 'leave_requests_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv')
          ..click();
        html.Url.revokeObjectUrl(url);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.download_done, color: Colors.white),
                SizedBox(width: 12),
                Text('Leave requests exported successfully'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('CSV export is only available on web'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      handleSilentError(e, context: 'Export CSV');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to export CSV'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Icons.check_circle;
      case 'pending':
        return Icons.pending;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.help;
    }
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
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.event_note, color: Colors.purple.shade700, size: 28),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Leave Requests',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Manage employee leave requests - Add as Pending, Edit to Approve/Reject',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF757575),
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showAddLeaveDialog,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Add New Leave'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
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
                  onPressed: _exportToCSV,
                  icon: const Icon(Icons.file_download),
                  label: const Text('Export CSV'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade700,
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
                : _leaveRequests.isEmpty
                    ? _buildEmptyState()
                    : _buildLeaveRequestsTable(),
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
          Icon(Icons.event_busy, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No Leave Requests Found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Click "Add New Leave" to create a leave request',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveRequestsTable() {
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
                Expanded(
                  flex: 1,
                  child: Text(
                    'Request ID',
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
                    'Start Date',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'End Date',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Reason',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Status',
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
              itemCount: _leaveRequests.length,
              itemBuilder: (context, index) {
                final leave = _leaveRequests[index];
                if (leave == null) {
                  return const SizedBox.shrink(); // Skip null entries
                }
                
                final isEven = index % 2 == 0;
                
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isEven ? Colors.white : Colors.grey.shade50,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: Text(
                          leave['_id']?.toString().substring(0, 8) ?? 'N/A',
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
                                leave['employee_name'] ?? 'Unknown',
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
                            Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Text(
                              leave['start_date'] != null
                                  ? DateFormat('dd-MM-yyyy').format(DateTime.parse(leave['start_date']))
                                  : 'N/A',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Icon(Icons.event, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Text(
                              leave['end_date'] != null
                                  ? DateFormat('dd-MM-yyyy').format(DateTime.parse(leave['end_date']))
                                  : 'N/A',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      
                      Expanded(
                        flex: 3,
                        child: Text(
                          leave['reason'] ?? 'N/A',
                          style: const TextStyle(fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _getStatusColor(leave['status'] ?? '').withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getStatusIcon(leave['status'] ?? ''),
                                size: 14,
                                color: _getStatusColor(leave['status'] ?? ''),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  (leave['status'] ?? 'pending').toString().toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _getStatusColor(leave['status'] ?? ''),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      Expanded(
                        flex: 2,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Tooltip(
                              message: 'Edit to Approve/Reject',
                              child: IconButton(
                                onPressed: () => _showEditLeaveDialog(leave),
                                icon: const Icon(Icons.edit_note),
                                color: Colors.blue.shade700,
                                tooltip: 'Edit',
                                iconSize: 22,
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => _deleteLeaveRequest(leave['_id'].toString()),
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