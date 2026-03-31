// lib/features/admin/driver_admin_management/driver_list_page_new.dart
// Clean card-based driver list matching vehicle master format

import 'package:flutter/material.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/core/services/driver_service.dart';
import 'package:abra_fleet/core/services/vehicle_service.dart';

class DriverListPageNew extends StatefulWidget {
  final AuthRepository authRepository;
  final DriverService driverService;
  final VehicleService vehicleService;
  final String? initialDocumentFilter;

  const DriverListPageNew({
    Key? key,
    required this.authRepository,
    required this.driverService,
    required this.vehicleService,
    this.initialDocumentFilter,
  }) : super(key: key);

  @override
  State<DriverListPageNew> createState() => _DriverListPageNewState();
}

class _DriverListPageNewState extends State<DriverListPageNew> {
  List<Map<String, dynamic>> _drivers = [];
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _filteredDrivers = [];
  bool _isLoading = false;
  String _selectedStatus = 'All';
  String _selectedVehicleFilter = 'All';
  String _selectedDocumentFilter = 'All';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialDocumentFilter != null) {
      _selectedDocumentFilter = widget.initialDocumentFilter!;
    }
    _fetchDrivers();
    _fetchVehicles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchDrivers() async {
    setState(() => _isLoading = true);

    try {
      final response = await widget.driverService.getDrivers(
        status: _selectedStatus != 'All' ? _selectedStatus.toLowerCase() : null,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        page: 1,
        limit: 100,
        fullDetails: true,
      );

      if (response['success'] == true) {
        setState(() {
          _drivers = List<Map<String, dynamic>>.from(response['data'] ?? []);
          _applyFilters();
        });
      }
    } catch (e) {
      print('[DriverListPage] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load drivers: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchVehicles() async {
    try {
      final response = await widget.vehicleService.getVehicles(limit: 100);
      if (response['success'] == true) {
        setState(() {
          _vehicles = List<Map<String, dynamic>>.from(response['data'] ?? []);
        });
      }
    } catch (e) {
      print('[DriverListPage] Error fetching vehicles: $e');
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> filtered = List.from(_drivers);

    // Vehicle filter
    if (_selectedVehicleFilter == 'With Vehicle') {
      filtered = filtered.where((d) => d['assignedVehicle'] != null).toList();
    } else if (_selectedVehicleFilter == 'No Vehicle') {
      filtered = filtered.where((d) => d['assignedVehicle'] == null).toList();
    }

    // Document filter
    if (_selectedDocumentFilter == 'Expired') {
      filtered = filtered.where((d) => _hasExpiredDocuments(d)).toList();
    } else if (_selectedDocumentFilter == 'Expiring Soon') {
      filtered = filtered.where((d) => _hasExpiringSoonDocuments(d)).toList();
    } else if (_selectedDocumentFilter == 'All Valid') {
      filtered = filtered.where((d) => !_hasExpiredDocuments(d) && !_hasExpiringSoonDocuments(d) && _hasDocuments(d)).toList();
    } else if (_selectedDocumentFilter == 'No Documents') {
      filtered = filtered.where((d) => !_hasDocuments(d)).toList();
    }

    setState(() {
      _filteredDrivers = filtered;
    });
  }

  bool _hasDocuments(Map<String, dynamic> driver) {
    final documents = (driver['documents'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    return documents.isNotEmpty;
  }

  bool _hasExpiredDocuments(Map<String, dynamic> driver) {
    final documents = (driver['documents'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final now = DateTime.now();
    return documents.any((doc) {
      final expiryDate = doc['expiryDate'];
      if (expiryDate != null) {
        try {
          return DateTime.parse(expiryDate).isBefore(now);
        } catch (e) {
          return false;
        }
      }
      return false;
    });
  }

  bool _hasExpiringSoonDocuments(Map<String, dynamic> driver) {
    final documents = (driver['documents'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final now = DateTime.now();
    final thirtyDaysFromNow = now.add(const Duration(days: 30));
    return documents.any((doc) {
      final expiryDate = doc['expiryDate'];
      if (expiryDate != null) {
        try {
          final expiry = DateTime.parse(expiryDate);
          return expiry.isAfter(now) && expiry.isBefore(thirtyDaysFromNow);
        } catch (e) {
          return false;
        }
      }
      return false;
    });
  }

  void _clearFilters() {
    setState(() {
      _selectedStatus = 'All';
      _selectedVehicleFilter = 'All';
      _selectedDocumentFilter = 'All';
      _searchQuery = '';
      _searchController.clear();
    });
    _fetchDrivers();
  }

  Widget _buildDocumentStatusIndicator(Map<String, dynamic> driver) {
    final hasExpired = _hasExpiredDocuments(driver);
    final hasExpiringSoon = _hasExpiringSoonDocuments(driver);
    final hasDocuments = _hasDocuments(driver);

    if (hasExpired) {
      return Tooltip(
        message: 'Has expired documents',
        child: Icon(Icons.error, color: Colors.red.shade700, size: 20),
      );
    } else if (hasExpiringSoon) {
      return Tooltip(
        message: 'Documents expiring soon',
        child: Icon(Icons.warning, color: Colors.orange.shade700, size: 20),
      );
    } else if (hasDocuments) {
      return Tooltip(
        message: 'All documents valid',
        child: Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
      );
    } else {
      return Tooltip(
        message: 'No documents uploaded',
        child: Icon(Icons.info_outline, color: Colors.grey.shade600, size: 20),
      );
    }
  }

  Widget _buildStatusChip(String status) {
    Color bgColor;
    Color textColor;

    switch (status.toLowerCase()) {
      case 'active':
        bgColor = Colors.green.shade100;
        textColor = Colors.green.shade800;
        break;
      case 'on_leave':
        bgColor = Colors.orange.shade100;
        textColor = Colors.orange.shade800;
        break;
      case 'inactive':
        bgColor = Colors.red.shade100;
        textColor = Colors.red.shade800;
        break;
      default:
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade800;
    }

    return Chip(
      label: Text(status.toUpperCase(), style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold)),
      backgroundColor: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  Widget _buildDriverCard(Map<String, dynamic> driver) {
    final vehicle = driver['assignedVehicle'];
    final hasVehicle = vehicle != null;

    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driver['name'] ?? 'Unknown',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${driver['driverId'] ?? 'N/A'}',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    _buildDocumentStatusIndicator(driver),
                    const SizedBox(width: 12),
                    _buildStatusChip(driver['status'] ?? 'inactive'),
                  ],
                ),
              ],
            ),
            const Divider(height: 24),
            
            // Driver Details
            _buildInfoRow(Icons.email, 'Email', driver['email'] ?? 'N/A'),
            _buildInfoRow(Icons.phone, 'Phone', driver['phone'] ?? 'N/A'),
            _buildInfoRow(
              Icons.directions_car,
              'Vehicle',
              hasVehicle
                  ? '${vehicle['registrationNumber'] ?? vehicle['make']} ${vehicle['model'] ?? ''}'
                  : 'Not Assigned',
            ),
            
            const Divider(height: 24),
            
            // Action Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildActionButton(
                  icon: Icons.directions_car,
                  label: hasVehicle ? 'Change Vehicle' : 'Assign Vehicle',
                  color: hasVehicle ? Colors.orange.shade700 : Colors.blue.shade700,
                  onPressed: () {
                    // TODO: Implement vehicle assignment
                  },
                ),
                _buildActionButton(
                  icon: Icons.visibility,
                  label: 'View Details',
                  color: Colors.blue.shade700,
                  onPressed: () {
                    // TODO: Implement view details
                  },
                ),
                _buildActionButton(
                  icon: Icons.edit,
                  label: 'Edit',
                  color: Colors.orange.shade700,
                  onPressed: () {
                    // TODO: Implement edit
                  },
                ),
                _buildActionButton(
                  icon: Icons.email,
                  label: 'Send Email',
                  color: Colors.purple.shade700,
                  onPressed: () {
                    // TODO: Implement send email
                  },
                ),
                _buildActionButton(
                  icon: Icons.delete,
                  label: 'Delete',
                  color: Colors.red.shade700,
                  onPressed: () {
                    // TODO: Implement delete
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(label + ':', style: TextStyle(color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildFilterChip(String label, String currentValue, List<String> options, Function(String) onSelected) {
    return PopupMenuButton<String>(
      child: Chip(
        avatar: const Icon(Icons.filter_list, size: 18),
        label: Text('$label: $currentValue'),
        backgroundColor: currentValue != 'All' ? Colors.blue.shade100 : Colors.grey.shade200,
      ),
      onSelected: onSelected,
      itemBuilder: (context) => options.map((option) {
        return PopupMenuItem<String>(
          value: option,
          child: Row(
            children: [
              if (option == currentValue) const Icon(Icons.check, size: 18, color: Colors.blue),
              if (option == currentValue) const SizedBox(width: 8),
              Text(option),
            ],
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayData = _filteredDrivers.isEmpty && _selectedStatus == 'All' && _selectedVehicleFilter == 'All' && _selectedDocumentFilter == 'All'
        ? _drivers
        : _filteredDrivers;

    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.95,
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFF1565C0),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    const Text(
                      'Driver Management',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Filters
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Column(
                  children: [
                    // Search Bar
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by name, email, phone, or driver ID...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onChanged: (value) {
                        setState(() => _searchQuery = value);
                      },
                      onSubmitted: (value) => _fetchDrivers(),
                    ),
                    const SizedBox(height: 12),
                    
                    // Filter Chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterChip(
                          'Status',
                          _selectedStatus,
                          ['All', 'Active', 'On Leave', 'Inactive'],
                          (value) {
                            setState(() => _selectedStatus = value);
                            _fetchDrivers();
                          },
                        ),
                        _buildFilterChip(
                          'Vehicle',
                          _selectedVehicleFilter,
                          ['All', 'With Vehicle', 'No Vehicle'],
                          (value) {
                            setState(() => _selectedVehicleFilter = value);
                            _applyFilters();
                          },
                        ),
                        _buildFilterChip(
                          'Documents',
                          _selectedDocumentFilter,
                          ['All', 'Expired', 'Expiring Soon', 'All Valid', 'No Documents'],
                          (value) {
                            setState(() => _selectedDocumentFilter = value);
                            _applyFilters();
                          },
                        ),
                        ElevatedButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.clear, size: 18),
                          label: const Text('Clear Filters'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade300,
                            foregroundColor: Colors.black87,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            await _fetchDrivers();
                            await _fetchVehicles();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Data refreshed'),
                                  duration: Duration(seconds: 1),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Refresh'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Showing ${displayData.length} driver(s)',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),

              // Driver List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : displayData.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.person_off, size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                Text('No drivers found', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: displayData.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) => _buildDriverCard(displayData[index]),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
