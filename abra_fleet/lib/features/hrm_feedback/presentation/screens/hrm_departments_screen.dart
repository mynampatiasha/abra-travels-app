import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:abra_fleet/core/services/backend_connection_manager.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

class HrmDepartmentsScreen extends StatefulWidget {
  const HrmDepartmentsScreen({super.key});

  @override
  State<HrmDepartmentsScreen> createState() => _HrmDepartmentsScreenState();
}

class _HrmDepartmentsScreenState extends State<HrmDepartmentsScreen> {
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _filteredDepartments = [];
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchDepartments();
  }

  Future<void> _fetchDepartments() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final connectionManager = Provider.of<BackendConnectionManager>(
        context,
        listen: false,
      );

      final response = await connectionManager.apiService.get('/api/hrm/departments');

      if (response != null && response['success'] == true) {
        setState(() {
          _departments = List<Map<String, dynamic>>.from(response['data'] ?? []);
          _filterDepartments();
        });
      }
    } catch (e) {
      print('❌ Error fetching departments: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load departments: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterDepartments() {
    setState(() {
      _filteredDepartments = _departments.where((department) {
        final matchesSearch = _searchQuery.isEmpty ||
            department['name']?.toLowerCase().contains(_searchQuery.toLowerCase()) == true;

        return matchesSearch;
      }).toList();
    });
  }

  Future<void> _showAddDepartmentDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.business, color: Colors.green[700]),
            const SizedBox(width: 12),
            const Text('Add New Department'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Department Name *',
                    prefixIcon: Icon(Icons.business),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter department name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    prefixIcon: Icon(Icons.description),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context);
                await _addDepartment(
                  name: nameController.text,
                  description: descriptionController.text,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save Department'),
          ),
        ],
      ),
    );
  }

  Future<void> _addDepartment({
    required String name,
    required String description,
  }) async {
    try {
      final connectionManager = Provider.of<BackendConnectionManager>(
        context,
        listen: false,
      );

      final response = await connectionManager.apiService.post(
        '/api/hrm/departments',
        body: {
          'name': name,
          'description': description,
        },
      );

      if (response != null && response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Department added successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchDepartments();
        }
      }
    } catch (e) {
      print('❌ Error adding department: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add department: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showEditDepartmentDialog(Map<String, dynamic> department) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: department['name']);
    final descriptionController = TextEditingController(
      text: department['description'] ?? '',
    );

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.edit, color: Colors.blue[700]),
            const SizedBox(width: 12),
            const Text('Edit Department'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Department Name *',
                    prefixIcon: Icon(Icons.business),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter department name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    prefixIcon: Icon(Icons.description),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context);
                await _updateDepartment(
                  id: department['_id'],
                  name: nameController.text,
                  description: descriptionController.text,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Update Department'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateDepartment({
    required String id,
    required String name,
    required String description,
  }) async {
    try {
      final connectionManager = Provider.of<BackendConnectionManager>(
        context,
        listen: false,
      );

      final response = await connectionManager.apiService.put(
        '/api/hrm/departments/$id',
        body: {
          'name': name,
          'description': description,
        },
      );

      if (response != null && response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Department updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchDepartments();
        }
      }
    } catch (e) {
      print('❌ Error updating department: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update department: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteDepartment(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete $name?'),
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
      final connectionManager = Provider.of<BackendConnectionManager>(
        context,
        listen: false,
      );

      final response = await connectionManager.apiService.delete(
        '/api/hrm/departments/$id',
      );

      if (response != null && response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Department deleted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchDepartments();
        }
      }
    } catch (e) {
      print('❌ Error deleting department: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete department: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportToCSV() async {
    try {
      final connectionManager = Provider.of<BackendConnectionManager>(
        context,
        listen: false,
      );

      final response = await connectionManager.apiService.get(
        '/api/hrm/departments/export/csv',
      );

      if (response != null && response['success'] == true) {
        final data = response['data'] as List<dynamic>;
        final filename = response['filename'] as String;

        // Convert to CSV format
        if (data.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No data to export'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        // Get headers from first item
        final headers = (data[0] as Map<String, dynamic>).keys.toList();
        
        // Build CSV content
        final csvContent = StringBuffer();
        csvContent.writeln(headers.map((h) => '"$h"').join(','));
        
        for (var row in data) {
          final values = headers.map((header) {
            final value = row[header]?.toString() ?? '';
            return '"$value"';
          }).join(',');
          csvContent.writeln(values);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Exported $filename successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Show download dialog
          _showDownloadDialog(csvContent.toString(), filename);
        }
      }
    } catch (e) {
      print('❌ Error exporting to CSV: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDownloadDialog(String csvContent, String filename) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Successful'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File: $filename'),
            const SizedBox(height: 16),
            const Text('CSV content has been generated.'),
            const SizedBox(height: 8),
            const Text(
              'In a web browser, this would download automatically.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              // Copy CSV content to clipboard
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('CSV data ready for download'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          // Header Section
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.business, size: 32, color: Colors.blue[700]),
                    const SizedBox(width: 12),
                    const Text(
                      'Departments List',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _showAddDepartmentDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Add New Department'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _exportToCSV,
                      icon: const Icon(Icons.download),
                      label: const Text('Export to CSV'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Search Bar
                SizedBox(
                  width: 400,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search departments...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                        _filterDepartments();
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          
          // Departments Table
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredDepartments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.business_outlined, size: 80, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No departments found',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        margin: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: SingleChildScrollView(
                          child: DataTable(
                            headingRowColor: MaterialStateProperty.all(
                              Colors.grey[100],
                            ),
                            columns: const [
                              DataColumn(label: Text('Department ID', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Department Name', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Edit', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Delete', style: TextStyle(fontWeight: FontWeight.bold))),
                            ],
                            rows: _filteredDepartments.map((department) {
                              return DataRow(
                                cells: [
                                  DataCell(Text(department['_id'].toString().substring(0, 8))),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue[50],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        department['name'] ?? '',
                                        style: TextStyle(
                                          color: Colors.blue[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () => _showEditDepartmentDialog(department),
                                    ),
                                  ),
                                  DataCell(
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteDepartment(
                                        department['_id'],
                                        department['name'] ?? '',
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}