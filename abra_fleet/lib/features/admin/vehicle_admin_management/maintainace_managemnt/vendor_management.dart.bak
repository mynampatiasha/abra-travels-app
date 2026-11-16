import 'package:flutter/material.dart';
import 'package:abra_fleet/core/services/vendor_service.dart';

// Simple Vendor Data Model
class VendorData {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String location;
  final List<String> vehicles;
  final DateTime? createdAt;

  VendorData({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.location,
    this.vehicles = const [],
    this.createdAt,
  });

  factory VendorData.fromBackend(Map<String, dynamic> data) {
    String mongoId = '';
    if (data['_id'] != null) {
      if (data['_id'] is Map) {
        mongoId = data['_id']['\$oid'] ?? '';
      } else {
        mongoId = data['_id'].toString();
      }
    }

    List<String> vehicleList = [];
    if (data['vehicles'] != null && data['vehicles'] is List) {
      vehicleList = List<String>.from(data['vehicles']);
    }

    return VendorData(
      id: mongoId,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      location: data['location'] ?? '',
      vehicles: vehicleList,
      createdAt: data['createdAt'] != null ? DateTime.tryParse(data['createdAt']) : null,
    );
  }
}

// ============ VENDOR MANAGEMENT SCREEN ============
class VendorManagementScreen extends StatefulWidget {
  const VendorManagementScreen({Key? key}) : super(key: key);

  @override
  State<VendorManagementScreen> createState() => _VendorManagementScreenState();
}

class _VendorManagementScreenState extends State<VendorManagementScreen> {
  final VendorService _vendorService = VendorService();
  bool _isLoading = true;
  String? _errorMessage;
  List<VendorData> _allVendors = [];
  List<VendorData> _filteredVendors = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadVendors();
    _searchController.addListener(_applySearch);
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadVendors() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _vendorService.getVendors();
      
      if (response['success'] == true) {
        final List<dynamic> vendorsData = response['data'] ?? [];
        setState(() {
          _allVendors = vendorsData
              .map((vendor) => VendorData.fromBackend(vendor))
              .toList();
          _applySearch();
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response['message'] ?? 'Failed to load vendors';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading vendors: $e';
        _isLoading = false;
      });
    }
  }

  void _applySearch() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredVendors = _allVendors;
      } else {
        _filteredVendors = _allVendors.where((vendor) {
          return vendor.name.toLowerCase().contains(query) ||
                 vendor.phone.toLowerCase().contains(query) ||
                 vendor.email.toLowerCase().contains(query) ||
                 vendor.location.toLowerCase().contains(query) ||
                 vendor.vehicles.any((v) => v.toLowerCase().contains(query));
        }).toList();
      }
    });
  }

  void _showAddVendor() {
    showDialog(
      context: context,
      builder: (context) => AddEditVendorDialog(
        onSave: () {
          Navigator.pop(context);
          _loadVendors();
        },
      ),
    );
  }

  void _showVendorDetails(VendorData vendor) {
    showDialog(
      context: context,
      builder: (context) => VendorDetailDialog(
        vendor: vendor,
        onUpdate: _loadVendors,
        onDelete: () {
          Navigator.pop(context);
          _loadVendors();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: RefreshIndicator(
        onRefresh: _loadVendors,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16.0),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Vendor Management',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _showAddVendor,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Vendor'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D47A1),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Search Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, color: Colors.grey.shade600, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search vendors...',
                              hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: Icon(Icons.clear, color: Colors.grey.shade600, size: 20),
                            onPressed: () => _searchController.clear(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Stats
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Total Vendors',
                          _allVendors.length.toString(),
                          Icons.store,
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'Total Vehicles',
                          _allVendors.fold<int>(0, (sum, v) => sum + v.vehicles.length).toString(),
                          Icons.directions_car,
                          Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content
            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const Spacer(),
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
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadVendors,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_filteredVendors.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.storefront_outlined, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty 
                ? 'No vendors yet. Add your first vendor!' 
                : 'No vendors match your search.',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (_searchController.text.isEmpty)
              ElevatedButton.icon(
                onPressed: _showAddVendor,
                icon: const Icon(Icons.add),
                label: const Text('Add First Vendor'),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredVendors.length,
      itemBuilder: (context, index) {
        final vendor = _filteredVendors[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: InkWell(
            onTap: () => _showVendorDetails(vendor),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.store, color: Colors.blue.shade700, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vendor.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.location_on, size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    vendor.location,
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Icon(Icons.phone, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text(vendor.phone, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                      const SizedBox(width: 16),
                      Icon(Icons.email, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          vendor.email,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (vendor.vehicles.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        Icon(Icons.directions_car, size: 14, color: Colors.green.shade700),
                        const SizedBox(width: 4),
                        Text(
                          '${vendor.vehicles.length} vehicle${vendor.vehicles.length > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============ VENDOR DETAIL DIALOG ============
class VendorDetailDialog extends StatelessWidget {
  final VendorData vendor;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;

  const VendorDetailDialog({
    required this.vendor,
    required this.onUpdate,
    required this.onDelete,
    Key? key,
  }) : super(key: key);

  void _showEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AddEditVendorDialog(
        vendor: vendor,
        onSave: () {
          Navigator.pop(context);
          onUpdate();
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text('Are you sure you want to delete ${vendor.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );

      final vendorService = VendorService();
      final response = await vendorService.deleteVendor(vendor.id);

      Navigator.pop(context);

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vendor deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        onDelete();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Failed to delete vendor'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAddVehicleDialog(BuildContext context) async {
    final controller = TextEditingController();
    
    final vehicleNumber = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Vehicle'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Vehicle Registration Number',
            hintText: 'e.g., KA01AB1234',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (vehicleNumber != null && vehicleNumber.isNotEmpty) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );

      final vendorService = VendorService();
      final response = await vendorService.addVehicleToVendor(
        vendorId: vendor.id,
        vehicleNumber: vehicleNumber,
      );

      Navigator.pop(context);

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vehicle added successfully'),
            backgroundColor: Colors.green,
          ),
        );
        onUpdate();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Failed to add vehicle'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removeVehicle(BuildContext context, String vehicleNumber) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Vehicle'),
        content: Text('Remove $vehicleNumber from this vendor?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );

      final vendorService = VendorService();
      final response = await vendorService.removeVehicleFromVendor(
        vendorId: vendor.id,
        vehicleNumber: vehicleNumber,
      );

      Navigator.pop(context);

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vehicle removed successfully'),
            backgroundColor: Colors.green,
          ),
        );
        onUpdate();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Failed to remove vehicle'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF0D47A1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.store, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      vendor.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.white),
                    onPressed: () => _showEditDialog(context),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white),
                    onPressed: () => _confirmDelete(context),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Contact Information
                    _buildInfoRow(Icons.email, 'Email', vendor.email),
                    _buildInfoRow(Icons.phone, 'Phone', vendor.phone),
                    _buildInfoRow(Icons.location_on, 'Location', vendor.location),
                    const SizedBox(height: 24),
                    // Vehicles Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Vehicles',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0D47A1),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _showAddVehicleDialog(context),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Vehicle'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    if (vendor.vehicles.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(
                          child: Text(
                            'No vehicles added yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      ...vendor.vehicles.map((vehicleNumber) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(Icons.directions_car, color: Colors.green.shade700),
                            title: Text(
                              vehicleNumber,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _removeVehicle(context, vehicleNumber),
                            ),
                          ),
                        );
                      }).toList(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF0D47A1), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============ ADD/EDIT VENDOR DIALOG ============
class AddEditVendorDialog extends StatefulWidget {
  final VendorData? vendor;
  final VoidCallback onSave;

  const AddEditVendorDialog({
    this.vendor,
    required this.onSave,
    Key? key,
  }) : super(key: key);

  @override
  State<AddEditVendorDialog> createState() => _AddEditVendorDialogState();
}

class _AddEditVendorDialogState extends State<AddEditVendorDialog> {
  final _formKey = GlobalKey<FormState>();
  final VendorService _vendorService = VendorService();
  
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _locationController;
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.vendor?.name);
    _emailController = TextEditingController(text: widget.vendor?.email);
    _phoneController = TextEditingController(text: widget.vendor?.phone);
    _locationController = TextEditingController(text: widget.vendor?.location);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _saveVendor() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final isEditing = widget.vendor != null;
      
      Map<String, dynamic> response;
      
      if (isEditing) {
        response = await _vendorService.updateVendor(
          vendorId: widget.vendor!.id,
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          phone: _phoneController.text.trim(),
          location: _locationController.text.trim(),
        );
      } else {
        response = await _vendorService.createVendor(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          phone: _phoneController.text.trim(),
          location: _locationController.text.trim(),
        );
      }

      setState(() => _isLoading = false);

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Vendor saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSave();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Failed to save vendor'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF0D47A1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.store, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.vendor == null ? 'Add New Vendor' : 'Edit Vendor',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Form
            Flexible(
              child: Form(
                key: _formKey,
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(20),
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Vendor Name *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.store),
                      ),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v!.isEmpty) return 'Required';
                        if (!RegExp(r'\S+@\S+\.\S+').hasMatch(v)) return 'Invalid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: 'Location *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                      ),
                      maxLines: 2,
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _saveVendor,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isLoading ? 'Saving...' : 'Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D47A1),
                      foregroundColor: Colors.white,
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
}