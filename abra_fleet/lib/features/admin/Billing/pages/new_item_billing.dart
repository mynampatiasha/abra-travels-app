// ============================================================================
// NEW ITEM BILLING - FINAL CORRECTED VERSION
// ============================================================================
// ✅ FIXED: "Add Vendor" button now appears INSIDE the vendor selector dialog
// Just like the customer selector in invoice screen!
// ============================================================================

import 'package:flutter/material.dart';
import '../../../../core/services/item_billing_service.dart';

class NewItemBilling extends StatefulWidget {
  final Map<String, dynamic>? itemToEdit;
  
  const NewItemBilling({super.key, this.itemToEdit});

  @override
  State<NewItemBilling> createState() => _NewItemBillingState();
}

class _NewItemBillingState extends State<NewItemBilling> {
  final _formKey = GlobalKey<FormState>();
  final ItemBillingService _service = ItemBillingService();
  
  // Form Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _unitController = TextEditingController();
  final TextEditingController _sellingPriceController = TextEditingController();
  final TextEditingController _costPriceController = TextEditingController();
  final TextEditingController _salesDescriptionController = TextEditingController();
  final TextEditingController _purchaseDescriptionController = TextEditingController();
  
  // Form State
  String _itemType = 'Goods';
  bool _isSellable = true;
  bool _isPurchasable = true;
  String _salesAccount = 'Sales';
  String _purchaseAccount = 'Cost of Goods Sold';
  String? _selectedVendor;
  
  // Loading states
  bool _isLoading = false;
  bool _isSaving = false;
  
  // Dropdown options
  final List<String> _units = ['pcs', 'dz', 'kg', 'ltr', 'box', 'carton', 'unit', 'hour'];
  final List<String> _salesAccounts = ['Sales', 'Service Revenue', 'Other Income'];
  final List<String> _purchaseAccounts = ['Cost of Goods Sold', 'Purchases', 'Direct Expenses'];
  List<Map<String, dynamic>> _vendors = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // Load vendors with error handling
      try {
        final vendors = await _service.fetchVendors();
        setState(() => _vendors = vendors);
      } catch (e) {
        print('⚠️ Error loading vendors: $e');
        setState(() => _vendors = []);
      }
      
      // If editing, populate form with existing data
      if (widget.itemToEdit != null) {
        _populateFormWithData(widget.itemToEdit!);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to load data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _populateFormWithData(Map<String, dynamic> data) {
    _nameController.text = data['name'] ?? '';
    _unitController.text = data['unit'] ?? '';
    _sellingPriceController.text = data['sellingPrice']?.toString() ?? '';
    _costPriceController.text = data['costPrice']?.toString() ?? '';
    _salesDescriptionController.text = data['salesDescription'] ?? '';
    _purchaseDescriptionController.text = data['purchaseDescription'] ?? '';
    
    // Handle preferredVendor - it can be either a String (ID) or Map (populated object)
    String? vendorId;
    if (data['preferredVendor'] != null) {
      if (data['preferredVendor'] is String) {
        vendorId = data['preferredVendor'] as String;
      } else if (data['preferredVendor'] is Map) {
        vendorId = (data['preferredVendor'] as Map)['_id']?.toString();
      }
    }
    
    setState(() {
      _itemType = data['type'] ?? 'Goods';
      _isSellable = data['isSellable'] ?? true;
      _isPurchasable = data['isPurchasable'] ?? true;
      _salesAccount = data['salesAccount'] ?? 'Sales';
      _purchaseAccount = data['purchaseAccount'] ?? 'Cost of Goods Sold';
      _selectedVendor = vendorId;
    });
  }

  Future<void> _saveItem() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final itemData = {
        'name': _nameController.text.trim(),
        'type': _itemType,
        'unit': _unitController.text.trim(),
        'isSellable': _isSellable,
        'isPurchasable': _isPurchasable,
        'sellingPrice': _isSellable ? double.tryParse(_sellingPriceController.text) : null,
        'salesAccount': _isSellable ? _salesAccount : null,
        'salesDescription': _isSellable ? _salesDescriptionController.text.trim() : null,
        'costPrice': _isPurchasable ? double.tryParse(_costPriceController.text) : null,
        'purchaseAccount': _isPurchasable ? _purchaseAccount : null,
        'purchaseDescription': _isPurchasable ? _purchaseDescriptionController.text.trim() : null,
        'preferredVendor': _selectedVendor,
      };

      String result;
      if (widget.itemToEdit != null) {
        final itemId = widget.itemToEdit!['_id'];
        result = await _service.updateItem(itemId, itemData);
      } else {
        result = await _service.createItem(itemData);
      }

      if (mounted) {
        _showSuccessSnackBar(result);
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to save item: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _unitController.dispose();
    _sellingPriceController.dispose();
    _costPriceController.dispose();
    _salesDescriptionController.dispose();
    _purchaseDescriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.itemToEdit != null ? 'Edit Item' : 'New Item',
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTypeSection(),
                    const SizedBox(height: 24),
                    _buildTextField(
                      label: 'Name',
                      controller: _nameController,
                      isRequired: true,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildUnitDropdown(),
                    const SizedBox(height: 32),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildSalesInformation()),
                        const SizedBox(width: 32),
                        Expanded(child: _buildPurchaseInformation()),
                      ],
                    ),
                    const SizedBox(height: 32),
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTypeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Type',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Select whether this is a physical good or a service',
              child: Icon(
                Icons.help_outline,
                size: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildRadioOption('Goods'),
            const SizedBox(width: 24),
            _buildRadioOption('Service'),
          ],
        ),
      ],
    );
  }

  Widget _buildRadioOption(String value) {
    return InkWell(
      onTap: () => setState(() => _itemType = value),
      child: Row(
        children: [
          Radio<String>(
            value: value,
            groupValue: _itemType,
            onChanged: (val) => setState(() => _itemType = val!),
            activeColor: Colors.blue,
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    bool isRequired = false,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            if (isRequired)
              const Text(
                '*',
                style: TextStyle(color: Colors.red, fontSize: 14),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: Colors.blue, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnitDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Unit',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Select or type a unit of measurement',
              child: Icon(
                Icons.help_outline,
                size: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _unitController.text.isEmpty ? null : _unitController.text,
          decoration: InputDecoration(
            hintText: 'Select or type to add',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          items: _units.map((unit) {
            return DropdownMenuItem<String>(
              value: unit,
              child: Text(unit),
            );
          }).toList(),
          onChanged: (value) {
            setState(() => _unitController.text = value ?? '');
          },
        ),
      ],
    );
  }

  Widget _buildSalesInformation() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Sales Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Checkbox(
                value: _isSellable,
                onChanged: (value) {
                  setState(() => _isSellable = value ?? true);
                },
                activeColor: Colors.blue,
              ),
              const Text('Sellable', style: TextStyle(fontSize: 14)),
            ],
          ),
          if (_isSellable) ...[
            const SizedBox(height: 16),
            _buildPriceField(
              label: 'Selling Price',
              controller: _sellingPriceController,
              isRequired: true,
            ),
            const SizedBox(height: 16),
            _buildAccountDropdown(
              label: 'Account',
              value: _salesAccount,
              items: _salesAccounts,
              isRequired: true,
              onChanged: (value) {
                setState(() => _salesAccount = value!);
              },
            ),
            const SizedBox(height: 16),
            _buildTextField(
              label: 'Description',
              controller: _salesDescriptionController,
              maxLines: 3,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPurchaseInformation() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Purchase Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Checkbox(
                value: _isPurchasable,
                onChanged: (value) {
                  setState(() => _isPurchasable = value ?? true);
                },
                activeColor: Colors.blue,
              ),
              const Text('Purchasable', style: TextStyle(fontSize: 14)),
            ],
          ),
          if (_isPurchasable) ...[
            const SizedBox(height: 16),
            _buildPriceField(
              label: 'Cost Price',
              controller: _costPriceController,
              isRequired: true,
            ),
            const SizedBox(height: 16),
            _buildAccountDropdown(
              label: 'Account',
              value: _purchaseAccount,
              items: _purchaseAccounts,
              isRequired: true,
              onChanged: (value) {
                setState(() => _purchaseAccount = value!);
              },
            ),
            const SizedBox(height: 16),
            _buildTextField(
              label: 'Description',
              controller: _purchaseDescriptionController,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            _buildVendorDropdown(),
          ],
        ],
      ),
    );
  }

  Widget _buildPriceField({
    required String label,
    required TextEditingController controller,
    bool isRequired = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            if (isRequired)
              const Text(
                '*',
                style: TextStyle(color: Colors.red, fontSize: 14),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  bottomLeft: Radius.circular(4),
                ),
              ),
              child: const Text('INR', style: TextStyle(fontSize: 14)),
            ),
            Expanded(
              child: TextFormField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: isRequired
                    ? (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Price is required';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Enter valid number';
                        }
                        return null;
                      }
                    : null,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(4),
                      bottomRight: Radius.circular(4),
                    ),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(4),
                      bottomRight: Radius.circular(4),
                    ),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAccountDropdown({
    required String label,
    required String value,
    required List<String> items,
    required bool isRequired,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            if (isRequired)
              const Text(
                '*',
                style: TextStyle(color: Colors.red, fontSize: 14),
              ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(item),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  // ✅ CORRECTED: Vendor Dropdown (no button here, just dropdown)
  Widget _buildVendorDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Preferred Vendor',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _showVendorSelector,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedVendor != null 
                        ? (_vendors.firstWhere(
                            (v) => v['_id'] == _selectedVendor,
                            orElse: () => {'name': 'Unknown'}
                          )['name'] ?? 'Unknown')
                        : 'Select vendor (optional)',
                    style: TextStyle(
                      color: _selectedVendor != null 
                          ? Colors.black87 
                          : Colors.grey[600],
                    ),
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ✅ CORRECTED: Vendor Selector Dialog with "Add Vendor" button INSIDE
  Future<void> _showVendorSelector() async {
    final TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> filteredVendors = _vendors;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Text('Select Vendor'),
                const Spacer(),
                // ✅ "ADD VENDOR" BUTTON IS NOW INSIDE THE DIALOG!
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(context); // Close vendor selector
                    await _showAddVendorDialog(); // Open add vendor dialog
                    // Vendors list will auto-refresh after adding
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Vendor'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF4285F4),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              height: 300,
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search vendors...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        if (value.isEmpty) {
                          filteredVendors = _vendors;
                        } else {
                          filteredVendors = _vendors.where((vendor) {
                            return (vendor['name'] ?? '')
                                .toLowerCase()
                                .contains(value.toLowerCase());
                          }).toList();
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: filteredVendors.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.business, size: 48, color: Colors.grey[400]),
                                const SizedBox(height: 8),
                                Text(
                                  _vendors.isEmpty 
                                      ? 'No vendors yet' 
                                      : 'No vendors found',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                                const SizedBox(height: 16),
                                if (_vendors.isEmpty)
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      Navigator.pop(context);
                                      await _showAddVendorDialog();
                                    },
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Add Your First Vendor'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF4285F4),
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredVendors.length,
                            itemBuilder: (context, index) {
                              final vendor = filteredVendors[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF4285F4),
                                  child: Text(
                                    (vendor['name'] ?? 'V')[0].toUpperCase(),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                title: Text(vendor['name'] ?? ''),
                                subtitle: vendor['email'] != null
                                    ? Text(vendor['email'])
                                    : null,
                                onTap: () {
                                  setState(() {
                                    _selectedVendor = vendor['_id'];
                                  });
                                  Navigator.pop(context);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedVendor = null;
                  });
                  Navigator.pop(context);
                },
                child: const Text('Clear Selection'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Add New Vendor Dialog (remains the same)
  Future<void> _showAddVendorDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    bool isCreating = false;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Add New Vendor'),
            content: SizedBox(
              width: 400,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Vendor Name *',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          prefixIcon: const Icon(Icons.business),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Vendor name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailController,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          prefixIcon: const Icon(Icons.email),
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneController,
                        decoration: InputDecoration(
                          labelText: 'Phone',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          prefixIcon: const Icon(Icons.phone),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: addressController,
                        decoration: InputDecoration(
                          labelText: 'Address',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          prefixIcon: const Icon(Icons.location_on),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isCreating ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isCreating ? null : () async {
                  if (!formKey.currentState!.validate()) {
                    return;
                  }
                  
                  setDialogState(() {
                    isCreating = true;
                  });
                  
                  try {
                    final vendorData = {
                      'name': nameController.text.trim(),
                      if (emailController.text.trim().isNotEmpty)
                        'email': emailController.text.trim(),
                      if (phoneController.text.trim().isNotEmpty)
                        'phone': phoneController.text.trim(),
                      if (addressController.text.trim().isNotEmpty)
                        'address': addressController.text.trim(),
                    };
                    
                    final vendor = await _service.createVendor(vendorData);
                    
                    // Reload vendors
                    await _loadData();
                    
                    setState(() {
                      _selectedVendor = vendor['_id'];
                    });
                    
                    Navigator.pop(context);
                    _showSuccessSnackBar('Vendor "${vendor['name']}" added successfully');
                    
                  } catch (e) {
                    setDialogState(() {
                      isCreating = false;
                    });
                    _showErrorSnackBar('Failed to create vendor: $e');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4285F4),
                  foregroundColor: Colors.white,
                ),
                child: isCreating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Add Vendor'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        ElevatedButton(
          onPressed: _isSaving ? null : _saveItem,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  'Save',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
        ),
        const SizedBox(width: 16),
        OutlinedButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            side: BorderSide(color: Colors.grey[400]!),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: const Text(
            'Cancel',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}
