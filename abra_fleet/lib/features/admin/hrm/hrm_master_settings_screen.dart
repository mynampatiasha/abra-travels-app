// ============================================================================
// HRM MASTER SETTINGS SCREEN
// ============================================================================
// Complete UI for managing Departments, Positions, Locations, Timings, 
// Companies, and Leave Hierarchy
// Author: Abra Fleet Management System
// ============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/core/services/hrm_master_settings_service.dart';

class HRMMasterSettingsScreen extends StatefulWidget {
  const HRMMasterSettingsScreen({Key? key}) : super(key: key);

  @override
  State<HRMMasterSettingsScreen> createState() => _HRMMasterSettingsScreenState();
}

class _HRMMasterSettingsScreenState extends State<HRMMasterSettingsScreen> with SingleTickerProviderStateMixin {
  // ============================================================================
  // STATE VARIABLES
  // ============================================================================
  
  late TabController _tabController;
  final HRMMasterSettingsService _service = HRMMasterSettingsService();
  
  // Loading states
  bool _isLoading = false;
  
  // Data lists
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _positions = [];
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _timings = [];
  List<Map<String, dynamic>> _companies = [];
  List<Map<String, dynamic>> _hierarchies = [];
  
  // Search
  String _searchQuery = '';
  
  // User role check
  bool _isSuperAdmin = false;
  
  // ============================================================================
  // LIFECYCLE METHODS
  // ============================================================================
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _searchQuery = '';
        });
      }
    });
    _checkUserRole();
    _loadData();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  // ============================================================================
  // USER ROLE CHECK
  // ============================================================================
  
  Future<void> _checkUserRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('user_role') ?? '';
      final modulesString = prefs.getString('user_modules') ?? '';
      
      setState(() {
        _isSuperAdmin = role == 'super_admin' || modulesString.contains('system');
      });
    } catch (e) {
      print('❌ Error checking user role: $e');
    }
  }
  
  // ============================================================================
  // DATA LOADING
  // ============================================================================
  
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      await Future.wait([
        _loadDepartments(),
        _loadPositions(),
        _loadLocations(),
        _loadTimings(),
        _loadCompanies(),
        _loadHierarchies(),
      ]);
    } catch (e) {
      _showErrorSnackbar('Failed to load data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _loadDepartments() async {
    try {
      final departments = await _service.getDepartments();
      setState(() {
        _departments = departments;
      });
    } catch (e) {
      print('❌ Error loading departments: $e');
      rethrow;
    }
  }
  
  Future<void> _loadPositions() async {
    try {
      final positions = await _service.getPositions();
      setState(() {
        _positions = positions;
      });
    } catch (e) {
      print('❌ Error loading positions: $e');
      rethrow;
    }
  }
  
  Future<void> _loadLocations() async {
    try {
      final locations = await _service.getLocations();
      setState(() {
        _locations = locations;
      });
    } catch (e) {
      print('❌ Error loading locations: $e');
      rethrow;
    }
  }
  
  Future<void> _loadTimings() async {
    try {
      final timings = await _service.getTimings();
      setState(() {
        _timings = timings;
      });
    } catch (e) {
      print('❌ Error loading timings: $e');
      rethrow;
    }
  }
  
  Future<void> _loadCompanies() async {
    try {
      final companies = await _service.getCompanies();
      setState(() {
        _companies = companies;
      });
    } catch (e) {
      print('❌ Error loading companies: $e');
      rethrow;
    }
  }
  
  Future<void> _loadHierarchies() async {
    try {
      final hierarchies = await _service.getLeaveHierarchies();
      setState(() {
        _hierarchies = hierarchies;
      });
    } catch (e) {
      print('❌ Error loading hierarchies: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // SNACKBAR HELPERS
  // ============================================================================
  
  void _showSuccessSnackbar(String message) {
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
  
  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
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
  
  // ============================================================================
  // EXPORT METHODS
  // ============================================================================
  
  Future<void> _exportCurrentTab() async {
    try {
      String csvData;
      String fileName;
      
      switch (_tabController.index) {
        case 0:
          csvData = await _service.exportDepartments();
          fileName = 'departments_export_${DateTime.now().millisecondsSinceEpoch}.csv';
          break;
        case 1:
          csvData = await _service.exportPositions();
          fileName = 'positions_export_${DateTime.now().millisecondsSinceEpoch}.csv';
          break;
        case 2:
          csvData = await _service.exportLocations();
          fileName = 'locations_export_${DateTime.now().millisecondsSinceEpoch}.csv';
          break;
        case 3:
          csvData = await _service.exportTimings();
          fileName = 'timings_export_${DateTime.now().millisecondsSinceEpoch}.csv';
          break;
        case 4:
          csvData = await _service.exportCompanies();
          fileName = 'companies_export_${DateTime.now().millisecondsSinceEpoch}.csv';
          break;
        case 5:
          csvData = await _service.exportLeaveHierarchy();
          fileName = 'hierarchy_export_${DateTime.now().millisecondsSinceEpoch}.csv';
          break;
        default:
          return;
      }
      
      // Save file
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(csvData);
      
      _showSuccessSnackbar('Exported to: ${file.path}');
    } catch (e) {
      _showErrorSnackbar('Export failed: $e');
    }
  }
  
  // ============================================================================
  // IMPORT METHODS
  // ============================================================================
  
  Future<void> _importCSV() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final file = File(result.files.single.path!);
      final csvString = await file.readAsString();
      
      // Parse CSV
      final csvData = const CsvToListConverter().convert(csvString);
      
      if (csvData.isEmpty || csvData.length < 2) {
        _showErrorSnackbar('CSV file is empty or invalid');
        return;
      }
      
      // Skip header row
      final rows = csvData.skip(1).toList();
      
      // Convert to department objects (example for departments tab)
      if (_tabController.index == 0) {
        final departments = rows.map((row) {
          return {'name': row[1].toString()};
        }).toList();
        
        final result = await _service.importDepartments(departments);
        
        _showSuccessSnackbar(
          'Import complete: ${result['imported']} imported, ${result['failed']} failed'
        );
        
        await _loadDepartments();
      }
    } catch (e) {
      _showErrorSnackbar('Import failed: $e');
    }
  }
  
  // ============================================================================
  // DEPARTMENT DIALOGS
  // ============================================================================
  
  void _showAddDepartmentDialog() {
    final nameController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Department', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'Department Name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.business),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                _showErrorSnackbar('Department name is required');
                return;
              }
              
              try {
                await _service.createDepartment(nameController.text.trim());
                Navigator.pop(context);
                _showSuccessSnackbar('Department created successfully');
                await _loadDepartments();
              } catch (e) {
                _showErrorSnackbar('Failed to create department: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF334155),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
  
  void _showEditDepartmentDialog(Map<String, dynamic> department) {
    final nameController = TextEditingController(text: department['name']);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Department', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'Department Name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.business),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                _showErrorSnackbar('Department name is required');
                return;
              }
              
              try {
                await _service.updateDepartment(
                  department['_id'],
                  nameController.text.trim(),
                );
                Navigator.pop(context);
                _showSuccessSnackbar('Department updated successfully');
                await _loadDepartments();
              } catch (e) {
                _showErrorSnackbar('Failed to update department: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF334155),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _deleteDepartment(Map<String, dynamic> department) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Department', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${department['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      try {
        await _service.deleteDepartment(department['_id']);
        _showSuccessSnackbar('Department deleted successfully');
        await _loadDepartments();
        await _loadPositions();
      } catch (e) {
        _showErrorSnackbar('Failed to delete department: $e');
      }
    }
  }
  
  // ============================================================================
  // POSITION DIALOGS
  // ============================================================================
  
  void _showAddPositionDialog({String? departmentId}) {
    final titleController = TextEditingController();
    String? selectedDepartmentId = departmentId;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add Position', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedDepartmentId,
                decoration: InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.business),
                ),
                items: _departments.map((dept) {
                  return DropdownMenuItem<String>(
                    value: dept['_id'],
                    child: Text(dept['name']),
                  );
                }).toList(),
                onChanged: (value) {
                  setDialogState(() {
                    selectedDepartmentId = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: 'Position Title',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.person),
                ),
                textCapitalization: TextCapitalization.words,
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
                if (titleController.text.trim().isEmpty) {
                  _showErrorSnackbar('Position title is required');
                  return;
                }
                
                if (selectedDepartmentId == null) {
                  _showErrorSnackbar('Please select a department');
                  return;
                }
                
                try {
                  await _service.createPosition(
                    titleController.text.trim(),
                    selectedDepartmentId!,
                  );
                  Navigator.pop(context);
                  _showSuccessSnackbar('Position created successfully');
                  await _loadPositions();
                  await _loadDepartments();
                } catch (e) {
                  _showErrorSnackbar('Failed to create position: $e');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF334155),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showEditPositionDialog(Map<String, dynamic> position) {
    final titleController = TextEditingController(text: position['title']);
    String? selectedDepartmentId = position['departmentId']?['_id'] ?? position['departmentId'];
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Position', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedDepartmentId,
                decoration: InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.business),
                ),
                items: _departments.map((dept) {
                  return DropdownMenuItem<String>(
                    value: dept['_id'],
                    child: Text(dept['name']),
                  );
                }).toList(),
                onChanged: (value) {
                  setDialogState(() {
                    selectedDepartmentId = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: 'Position Title',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.person),
                ),
                textCapitalization: TextCapitalization.words,
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
                if (titleController.text.trim().isEmpty) {
                  _showErrorSnackbar('Position title is required');
                  return;
                }
                
                if (selectedDepartmentId == null) {
                  _showErrorSnackbar('Please select a department');
                  return;
                }
                
                try {
                  await _service.updatePosition(
                    position['_id'],
                    titleController.text.trim(),
                    selectedDepartmentId!,
                  );
                  Navigator.pop(context);
                  _showSuccessSnackbar('Position updated successfully');
                  await _loadPositions();
                  await _loadDepartments();
                } catch (e) {
                  _showErrorSnackbar('Failed to update position: $e');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF334155),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _deletePosition(Map<String, dynamic> position) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Position', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${position['title']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      try {
        await _service.deletePosition(position['_id']);
        _showSuccessSnackbar('Position deleted successfully');
        await _loadPositions();
        await _loadDepartments();
        await _loadHierarchies();
      } catch (e) {
        _showErrorSnackbar('Failed to delete position: $e');
      }
    }
  }
  
  // ============================================================================
  // LOCATION DIALOGS
  // ============================================================================
  
  void _showAddLocationDialog() {
    final nameController = TextEditingController();
    final latController = TextEditingController();
    final lngController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Location', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Location Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.place),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: latController,
              decoration: InputDecoration(
                labelText: 'Latitude (Optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.my_location),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: lngController,
              decoration: InputDecoration(
                labelText: 'Longitude (Optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.location_on),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
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
              if (nameController.text.trim().isEmpty) {
                _showErrorSnackbar('Location name is required');
                return;
              }
              
              try {
                await _service.createLocation(
                  nameController.text.trim(),
                  latController.text.trim(),
                  lngController.text.trim(),
                );
                Navigator.pop(context);
                _showSuccessSnackbar('Location created successfully');
                await _loadLocations();
              } catch (e) {
                _showErrorSnackbar('Failed to create location: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF334155),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
  
  void _showEditLocationDialog(Map<String, dynamic> location) {
    final nameController = TextEditingController(text: location['locationName']);
    final latController = TextEditingController(text: location['latitude'] ?? '');
    final lngController = TextEditingController(text: location['longitude'] ?? '');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Location', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Location Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.place),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: latController,
              decoration: InputDecoration(
                labelText: 'Latitude (Optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.my_location),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: lngController,
              decoration: InputDecoration(
                labelText: 'Longitude (Optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.location_on),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
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
              if (nameController.text.trim().isEmpty) {
                _showErrorSnackbar('Location name is required');
                return;
              }
              
              try {
                await _service.updateLocation(
                  location['_id'],
                  nameController.text.trim(),
                  latController.text.trim(),
                  lngController.text.trim(),
                );
                Navigator.pop(context);
                _showSuccessSnackbar('Location updated successfully');
                await _loadLocations();
              } catch (e) {
                _showErrorSnackbar('Failed to update location: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF334155),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _deleteLocation(Map<String, dynamic> location) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Location', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${location['locationName']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      try {
        await _service.deleteLocation(location['_id']);
        _showSuccessSnackbar('Location deleted successfully');
        await _loadLocations();
      } catch (e) {
        _showErrorSnackbar('Failed to delete location: $e');
      }
    }
  }
  
  // ============================================================================
  // TIMING DIALOGS
  // ============================================================================
  
  void _showAddTimingDialog() {
    final startController = TextEditingController();
    final endController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Timing', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: startController,
              decoration: InputDecoration(
                labelText: 'Start Time (e.g., 09:00 AM)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.access_time),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: endController,
              decoration: InputDecoration(
                labelText: 'End Time (e.g., 06:00 PM)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.access_time),
              ),
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
              if (startController.text.trim().isEmpty || endController.text.trim().isEmpty) {
                _showErrorSnackbar('Both start and end time are required');
                return;
              }
              
              try {
                await _service.createTiming(
                  startController.text.trim(),
                  endController.text.trim(),
                );
                Navigator.pop(context);
                _showSuccessSnackbar('Timing created successfully');
                await _loadTimings();
              } catch (e) {
                _showErrorSnackbar('Failed to create timing: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF334155),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
  
  void _showEditTimingDialog(Map<String, dynamic> timing) {
    final startController = TextEditingController(text: timing['startTime']);
    final endController = TextEditingController(text: timing['endTime']);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Timing', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: startController,
              decoration: InputDecoration(
                labelText: 'Start Time (e.g., 09:00 AM)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.access_time),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: endController,
              decoration: InputDecoration(
                labelText: 'End Time (e.g., 06:00 PM)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.access_time),
              ),
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
              if (startController.text.trim().isEmpty || endController.text.trim().isEmpty) {
                _showErrorSnackbar('Both start and end time are required');
                return;
              }
              
              try {
                await _service.updateTiming(
                  timing['_id'],
                  startController.text.trim(),
                  endController.text.trim(),
                );
                Navigator.pop(context);
                _showSuccessSnackbar('Timing updated successfully');
                await _loadTimings();
              } catch (e) {
                _showErrorSnackbar('Failed to update timing: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF334155),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _deleteTiming(Map<String, dynamic> timing) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Timing', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${timing['startTime']} - ${timing['endTime']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      try {
        await _service.deleteTiming(timing['_id']);
        _showSuccessSnackbar('Timing deleted successfully');
        await _loadTimings();
      } catch (e) {
        _showErrorSnackbar('Failed to delete timing: $e');
      }
    }
  }
  
  // ============================================================================
  // COMPANY DIALOGS
  // ============================================================================
  
  void _showAddCompanyDialog() {
    final nameController = TextEditingController();
    File? selectedLogo;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add Company', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Company Name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.business),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.image,
                  );
                  
                  if (result != null && result.files.isNotEmpty) {
                    setDialogState(() {
                      selectedLogo = File(result.files.single.path!);
                    });
                  }
                },
                icon: const Icon(Icons.upload_file),
                label: Text(selectedLogo == null ? 'Upload Logo (Optional)' : 'Logo Selected'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
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
                if (nameController.text.trim().isEmpty) {
                  _showErrorSnackbar('Company name is required');
                  return;
                }
                
                try {
                  await _service.createCompany(
                    nameController.text.trim(),
                    logoFile: selectedLogo,
                  );
                  Navigator.pop(context);
                  _showSuccessSnackbar('Company created successfully');
                  await _loadCompanies();
                } catch (e) {
                  _showErrorSnackbar('Failed to create company: $e');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF334155),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showEditCompanyDialog(Map<String, dynamic> company) {
    final nameController = TextEditingController(text: company['companyName']);
    File? selectedLogo;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Company', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Company Name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.business),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              if (company['logoUrl'] != null && selectedLogo == null)
                Container(
                  height: 100,
                  width: 100,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Image.network(
                    company['logoUrl'],
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.error),
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.image,
                  );
                  
                  if (result != null && result.files.isNotEmpty) {
                    setDialogState(() {
                      selectedLogo = File(result.files.single.path!);
                    });
                  }
                },
                icon: const Icon(Icons.upload_file),
                label: Text(selectedLogo == null ? 'Change Logo (Optional)' : 'New Logo Selected'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
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
                if (nameController.text.trim().isEmpty) {
                  _showErrorSnackbar('Company name is required');
                  return;
                }
                
                try {
                  await _service.updateCompany(
                    company['_id'],
                    nameController.text.trim(),
                    logoFile: selectedLogo,
                  );
                  Navigator.pop(context);
                  _showSuccessSnackbar('Company updated successfully');
                  await _loadCompanies();
                } catch (e) {
                  _showErrorSnackbar('Failed to update company: $e');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF334155),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _deleteCompany(Map<String, dynamic> company) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Company', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${company['companyName']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      try {
        await _service.deleteCompany(company['_id']);
        _showSuccessSnackbar('Company deleted successfully');
        await _loadCompanies();
      } catch (e) {
        _showErrorSnackbar('Failed to delete company: $e');
      }
    }
  }
  
  // ============================================================================
  // HIERARCHY DIALOG
  // ============================================================================
  
  void _showHierarchyDialog(Map<String, dynamic> hierarchyData) {
    String? approver1Id = hierarchyData['approver1']?['_id'];
    String? approver2Id = hierarchyData['approver2']?['_id'];
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Set Hierarchy - ${hierarchyData['title']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: approver1Id,
                decoration: InputDecoration(
                  labelText: 'Approver 1 (Line Manager)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.person),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('-- None --'),
                  ),
                  ..._positions.where((p) => p['_id'] != hierarchyData['_id']).map((pos) {
                    final deptName = pos['departmentId'] is Map 
                        ? pos['departmentId']['name'] ?? 'N/A'
                        : 'N/A';
                    return DropdownMenuItem<String>(
                      value: pos['_id'],
                      child: Text('${pos['title']} ($deptName)'),
                    );
                  }).toList(),
                ],
                onChanged: (value) {
                  setDialogState(() {
                    approver1Id = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: approver2Id,
                decoration: InputDecoration(
                  labelText: 'Approver 2 (Optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('-- None --'),
                  ),
                  ..._positions.where((p) => p['_id'] != hierarchyData['_id']).map((pos) {
                    final deptName = pos['departmentId'] is Map 
                        ? pos['departmentId']['name'] ?? 'N/A'
                        : 'N/A';
                    return DropdownMenuItem<String>(
                      value: pos['_id'],
                      child: Text('${pos['title']} ($deptName)'),
                    );
                  }).toList(),
                ],
                onChanged: (value) {
                  setDialogState(() {
                    approver2Id = value;
                  });
                },
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
                try {
                  await _service.saveLeaveHierarchy(
                    hierarchyData['_id'],
                    approver1Id,
                    approver2Id,
                  );
                  Navigator.pop(context);
                  _showSuccessSnackbar('Hierarchy saved successfully');
                  await _loadHierarchies();
                } catch (e) {
                  _showErrorSnackbar('Failed to save hierarchy: $e');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF334155),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _clearHierarchy(Map<String, dynamic> hierarchyData) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear Hierarchy', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to clear the hierarchy for "${hierarchyData['title']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      try {
        await _service.clearLeaveHierarchy(hierarchyData['_id']);
        _showSuccessSnackbar('Hierarchy cleared successfully');
        await _loadHierarchies();
      } catch (e) {
        _showErrorSnackbar('Failed to clear hierarchy: $e');
      }
    }
  }
  
  // ============================================================================
  // BUILD METHODS - TAB VIEWS
  // ============================================================================
  
  Widget _buildDepartmentsTab() {
    final filteredDepartments = _departments.where((dept) {
      if (_searchQuery.isEmpty) return true;
      return dept['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
    
    if (filteredDepartments.isEmpty) {
      return _buildEmptyState(
        icon: Icons.business_center,
        title: _searchQuery.isEmpty ? 'No Departments Yet' : 'No Results Found',
        subtitle: _searchQuery.isEmpty
            ? 'Create your first department to get started'
            : 'Try adjusting your search',
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredDepartments.length,
      itemBuilder: (context, index) {
        final department = filteredDepartments[index];
        return _buildDepartmentCard(department);
      },
    );
  }
  
  Widget _buildDepartmentCard(Map<String, dynamic> department) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.all(16),
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF334155).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.business, color: Color(0xFF334155)),
          ),
          title: Text(
            department['name'],
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0EA5E9).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${department['positionCount'] ?? 0} Positions',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF0EA5E9),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Color(0xFF334155)),
                onPressed: () => _showEditDepartmentDialog(department),
                tooltip: 'Edit',
              ),
              if (_isSuperAdmin)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                  onPressed: () => _deleteDepartment(department),
                  tooltip: 'Delete',
                ),
            ],
          ),
          children: [
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _service.getPositionsByDepartment(department['_id']),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No positions in this department',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _showAddPositionDialog(departmentId: department['_id']),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Position'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF334155),
                        ),
                      ),
                    ],
                  );
                }
                
                final positions = snapshot.data!;
                
                return Column(
                  children: [
                    ...positions.map((position) => _buildPositionItem(position)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _showAddPositionDialog(departmentId: department['_id']),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Position'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF334155),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPositionItem(Map<String, dynamic> position) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.person, size: 20, color: Color(0xFF334155)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              position['title'],
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: const Color(0xFF334155),
            onPressed: () => _showEditPositionDialog(position),
            tooltip: 'Edit',
          ),
          if (_isSuperAdmin)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: const Color(0xFFEF4444),
              onPressed: () => _deletePosition(position),
              tooltip: 'Delete',
            ),
        ],
      ),
    );
  }
  
  Widget _buildPositionsTab() {
    final filteredPositions = _positions.where((pos) {
      if (_searchQuery.isEmpty) return true;
      final title = pos['title'].toString().toLowerCase();
      final deptName = pos['departmentId'] is Map
          ? (pos['departmentId']['name'] ?? '').toString().toLowerCase()
          : '';
      return title.contains(_searchQuery.toLowerCase()) ||
          deptName.contains(_searchQuery.toLowerCase());
    }).toList();
    
    if (filteredPositions.isEmpty) {
      return _buildEmptyState(
        icon: Icons.work_outline,
        title: _searchQuery.isEmpty ? 'No Positions Yet' : 'No Results Found',
        subtitle: _searchQuery.isEmpty
            ? 'Add positions from departments or create new ones'
            : 'Try adjusting your search',
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredPositions.length,
      itemBuilder: (context, index) {
        final position = filteredPositions[index];
        final deptName = position['departmentId'] is Map
            ? position['departmentId']['name'] ?? 'N/A'
            : 'N/A';
        
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF334155).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.person, color: Color(0xFF334155)),
            ),
            title: Text(
              position['title'],
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.business, size: 14, color: Color(0xFF64748B)),
                  const SizedBox(width: 4),
                  Text(
                    deptName,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  color: const Color(0xFF334155),
                  onPressed: () => _showEditPositionDialog(position),
                  tooltip: 'Edit',
                ),
                if (_isSuperAdmin)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color: const Color(0xFFEF4444),
                    onPressed: () => _deletePosition(position),
                    tooltip: 'Delete',
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildLocationsTab() {
    final filteredLocations = _locations.where((loc) {
      if (_searchQuery.isEmpty) return true;
      return loc['locationName'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
    
    if (filteredLocations.isEmpty) {
      return _buildEmptyState(
        icon: Icons.place_outlined,
        title: _searchQuery.isEmpty ? 'No Locations Yet' : 'No Results Found',
        subtitle: _searchQuery.isEmpty
            ? 'Add work locations to get started'
            : 'Try adjusting your search',
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredLocations.length,
      itemBuilder: (context, index) {
        final location = filteredLocations[index];
        
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF334155).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.place, color: Color(0xFF334155)),
            ),
            title: Text(
              location['locationName'],
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            subtitle: location['latitude']?.isNotEmpty == true
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.map, size: 14, color: Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text(
                          '${location['latitude']}, ${location['longitude']}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  color: const Color(0xFF334155),
                  onPressed: () => _showEditLocationDialog(location),
                  tooltip: 'Edit',
                ),
                if (_isSuperAdmin)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color: const Color(0xFFEF4444),
                    onPressed: () => _deleteLocation(location),
                    tooltip: 'Delete',
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildTimingsTab() {
    final filteredTimings = _timings.where((timing) {
      if (_searchQuery.isEmpty) return true;
      return timing['startTime'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
          timing['endTime'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
    
    if (filteredTimings.isEmpty) {
      return _buildEmptyState(
        icon: Icons.access_time,
        title: _searchQuery.isEmpty ? 'No Timings Yet' : 'No Results Found',
        subtitle: _searchQuery.isEmpty
            ? 'Add office timings to get started'
            : 'Try adjusting your search',
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredTimings.length,
      itemBuilder: (context, index) {
        final timing = filteredTimings[index];
        
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF334155).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.access_time, color: Color(0xFF334155)),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    timing['startTime'],
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 16, color: Color(0xFF64748B)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    timing['endTime'],
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  color: const Color(0xFF334155),
                  onPressed: () => _showEditTimingDialog(timing),
                  tooltip: 'Edit',
                ),
                if (_isSuperAdmin)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color: const Color(0xFFEF4444),
                    onPressed: () => _deleteTiming(timing),
                    tooltip: 'Delete',
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildCompaniesTab() {
    final filteredCompanies = _companies.where((company) {
      if (_searchQuery.isEmpty) return true;
      return company['companyName'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
    
    if (filteredCompanies.isEmpty) {
      return _buildEmptyState(
        icon: Icons.domain,
        title: _searchQuery.isEmpty ? 'No Companies Yet' : 'No Results Found',
        subtitle: _searchQuery.isEmpty
            ? 'Add companies to get started'
            : 'Try adjusting your search',
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredCompanies.length,
      itemBuilder: (context, index) {
        final company = filteredCompanies[index];
        
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: company['logoUrl'] != null
                ? Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        company['logoUrl'],
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: const Color(0xFFF8FAFC),
                          child: const Icon(Icons.business, color: Color(0xFF64748B)),
                        ),
                      ),
                    ),
                  )
                : Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.business, color: Color(0xFF334155)),
                  ),
            title: Text(
              company['companyName'],
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                company['logoUrl'] != null ? 'Logo Available' : 'No Logo',
                style: TextStyle(
                  fontSize: 12,
                  color: company['logoUrl'] != null
                      ? const Color(0xFF10B981)
                      : const Color(0xFF64748B),
                ),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  color: const Color(0xFF334155),
                  onPressed: () => _showEditCompanyDialog(company),
                  tooltip: 'Edit',
                ),
                if (_isSuperAdmin)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color: const Color(0xFFEF4444),
                    onPressed: () => _deleteCompany(company),
                    tooltip: 'Delete',
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildLeaveHierarchyTab() {
    final filteredHierarchies = _hierarchies.where((h) {
      if (_searchQuery.isEmpty) return true;
      final title = h['title'].toString().toLowerCase();
      final dept = h['departmentName'].toString().toLowerCase();
      return title.contains(_searchQuery.toLowerCase()) ||
          dept.contains(_searchQuery.toLowerCase());
    }).toList();
    
    if (filteredHierarchies.isEmpty) {
      return _buildEmptyState(
        icon: Icons.account_tree,
        title: _searchQuery.isEmpty ? 'No Hierarchy Set' : 'No Results Found',
        subtitle: _searchQuery.isEmpty
            ? 'Set leave approval hierarchy for positions'
            : 'Try adjusting your search',
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredHierarchies.length,
      itemBuilder: (context, index) {
        final hierarchy = filteredHierarchies[index];
        
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF334155).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.person, color: Color(0xFF334155)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hierarchy['title'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hierarchy['departmentName'],
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      color: const Color(0xFF334155),
                      onPressed: () => _showHierarchyDialog(hierarchy),
                      tooltip: 'Set Hierarchy',
                    ),
                    if (_isSuperAdmin && (hierarchy['approver1'] != null || hierarchy['approver2'] != null))
                      IconButton(
                        icon: const Icon(Icons.clear),
                        color: const Color(0xFFEF4444),
                        onPressed: () => _clearHierarchy(hierarchy),
                        tooltip: 'Clear Hierarchy',
                      ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Approver 1',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hierarchy['approver1']?['title'] ?? 'Not Set',
                            style: TextStyle(
                              fontSize: 13,
                              color: hierarchy['approver1'] != null
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFF94A3B8),
                              fontStyle: hierarchy['approver1'] != null
                                  ? FontStyle.normal
                                  : FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Approver 2',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFF59E0B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hierarchy['approver2']?['title'] ?? 'Not Set',
                            style: TextStyle(
                              fontSize: 13,
                              color: hierarchy['approver2'] != null
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFF94A3B8),
                              fontStyle: hierarchy['approver2'] != null
                                  ? FontStyle.normal
                                  : FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: const Color(0xFFCBD5E1)),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF94A3B8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  // ============================================================================
  // BUILD METHOD - MAIN UI
  // ============================================================================
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Master Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF334155),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _exportCurrentTab,
            tooltip: 'Export CSV',
          ),
          if (_tabController.index == 0)
            IconButton(
              icon: const Icon(Icons.file_upload_outlined),
              onPressed: _importCSV,
              tooltip: 'Import CSV',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: const Color(0xFF0EA5E9),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: const [
            Tab(icon: Icon(Icons.business), text: 'Departments'),
            Tab(icon: Icon(Icons.list), text: 'All Positions'),
            Tab(icon: Icon(Icons.place), text: 'Locations'),
            Tab(icon: Icon(Icons.access_time), text: 'Timings'),
            Tab(icon: Icon(Icons.domain), text: 'Companies'),
            Tab(icon: Icon(Icons.account_tree), text: 'Hierarchy'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search bar moved outside AppBar
          Container(
            color: const Color(0xFF334155),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF334155)))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildDepartmentsTab(),
                      _buildPositionsTab(),
                      _buildLocationsTab(),
                      _buildTimingsTab(),
                      _buildCompaniesTab(),
                      _buildLeaveHierarchyTab(),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: _tabController.index != 5
          ? FloatingActionButton.extended(
              onPressed: () {
                switch (_tabController.index) {
                  case 0:
                    _showAddDepartmentDialog();
                    break;
                  case 1:
                    _showAddPositionDialog();
                    break;
                  case 2:
                    _showAddLocationDialog();
                    break;
                  case 3:
                    _showAddTimingDialog();
                    break;
                  case 4:
                    _showAddCompanyDialog();
                    break;
                }
              },
              backgroundColor: const Color(0xFF334155),
              icon: const Icon(Icons.add),
              label: Text(_getAddButtonText()),
            )
          : null,
    );
  }
  
  String _getAddButtonText() {
    switch (_tabController.index) {
      case 0:
        return 'Add Department';
      case 1:
        return 'Add Position';
      case 2:
        return 'Add Location';
      case 3:
        return 'Add Timing';
      case 4:
        return 'Add Company';
      default:
        return 'Add';
    }
  }
}