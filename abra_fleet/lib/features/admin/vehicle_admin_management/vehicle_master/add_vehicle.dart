import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:abra_fleet/core/services/vehicle_service.dart';

class AddVehicleScreen extends StatefulWidget {
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final bool isEditMode;
  final String? vehicleId; // This should be MongoDB _id, not vehicleId
  final Map<String, dynamic>? initialData;

  const AddVehicleScreen({
    super.key,
    required this.onCancel,
    required this.onSave,
    this.isEditMode = false,
    this.vehicleId, // Pass MongoDB _id here
    this.initialData,
  });

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vehicleService = VehicleService();

  static const Color primaryColor = Color(0xFF0D47A1);
  static const Color primaryLightColor = Color(0xFF1976D2);
  static const Color backgroundColor = Color(0xFFF5F5F5);

  // Controllers for text fields
  late TextEditingController _registrationController;
  late TextEditingController _makeModelController;
  late TextEditingController _yearController;
  late TextEditingController _engineCapacityController;
  late TextEditingController _seatingCapacityController;
  late TextEditingController _mileageController;
  late TextEditingController _vendorController;
  
  // Location controllers
  late TextEditingController _countryController;
  late TextEditingController _stateController;
  late TextEditingController _cityController;

  // Dropdown values
  String? _selectedVehicleType;
  String? _selectedEngineType;
  String? _selectedStatus;

  // Loading state
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    
    // Debug: Check what ID we received
    if (widget.isEditMode) {
      print('=== EDIT MODE DEBUG ===');
      print('Vehicle ID received: ${widget.vehicleId}');
      print('Initial data: ${widget.initialData}');
      print('MongoDB _id from data: ${widget.initialData?['_id']}');
      print('Custom vehicleId from data: ${widget.initialData?['vehicleId']}');
      print('=====================');
    }
    
    // Initialize controllers with initial data if in edit mode
    _registrationController = TextEditingController(
      text: widget.initialData?['registrationNumber'] ?? '',
    );
    _makeModelController = TextEditingController(
      text: widget.initialData?['makeModel'] ?? '',
    );
    _yearController = TextEditingController(
      text: widget.initialData?['yearOfManufacture']?.toString() ?? '',
    );
    _engineCapacityController = TextEditingController(
      text: widget.initialData?['engineCapacity']?.toString() ?? '',
    );
    _seatingCapacityController = TextEditingController(
      text: widget.initialData?['seatingCapacity']?.toString() ?? '',
    );
    _mileageController = TextEditingController(
      text: widget.initialData?['mileage']?.toString() ?? '',
    );
    _vendorController = TextEditingController(
      text: widget.initialData?['vendor'] ?? '',
    );
    
    // Initialize location controllers
    _countryController = TextEditingController(
      text: widget.initialData?['country'] ?? '',
    );
    _stateController = TextEditingController(
      text: widget.initialData?['state'] ?? '',
    );
    _cityController = TextEditingController(
      text: widget.initialData?['city'] ?? '',
    );

    // Set dropdown values
    if (widget.isEditMode && widget.initialData != null) {
      // Normalize all dropdown values to match available options
      final vehicleTypeFromData = widget.initialData!['vehicleType']?.toString();
      final engineTypeFromData = widget.initialData!['engineType']?.toString();
      final statusFromData = widget.initialData!['status']?.toString() ?? 'active';
      
      // Only set if value exists in dropdown options
      const vehicleTypes = ['Bus', 'Van', 'Car', 'Truck', 'Mini Bus'];
      const engineTypes = ['Diesel', 'Petrol', 'CNG', 'Electric', 'Hybrid'];
      
      _selectedVehicleType = vehicleTypes.contains(vehicleTypeFromData) ? vehicleTypeFromData : null;
      _selectedEngineType = engineTypes.contains(engineTypeFromData) ? engineTypeFromData : null;
      _selectedStatus = _normalizeStatus(statusFromData);
    } else {
      // Default status for new vehicles
      _selectedStatus = 'Active';
    }
  }

  @override
  void dispose() {
    _registrationController.dispose();
    _makeModelController.dispose();
    _yearController.dispose();
    _engineCapacityController.dispose();
    _seatingCapacityController.dispose();
    _mileageController.dispose();
    _vendorController.dispose();
    _countryController.dispose();
    _stateController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  // Helper method to normalize status from backend to match dropdown
  String _normalizeStatus(String status) {
    final normalized = status.toLowerCase();
    switch (normalized) {
      case 'active':
        return 'Active';
      case 'inactive':
        return 'Inactive';
      case 'maintenance':
      case 'under_maintenance':
        return 'Maintenance';
      default:
        return 'Active';
    }
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSubmitting = true);
      
      try {
        // Split make and model from the combined field
        final makeModelParts = _makeModelController.text.trim().split(' ');
        final make = makeModelParts.isNotEmpty ? makeModelParts[0] : '';
        final model = makeModelParts.length > 1 
            ? makeModelParts.sublist(1).join(' ') 
            : makeModelParts[0];
        
        // Parse all values with proper type casting
        final registrationNumber = _registrationController.text.trim().toUpperCase();
        final vehicleType = _selectedVehicleType ?? 'Car';
        final yearOfManufacture = int.parse(_yearController.text);
        final engineType = _selectedEngineType ?? 'Diesel';
        final engineCapacity = double.parse(_engineCapacityController.text);
        final seatingCapacity = int.parse(_seatingCapacityController.text);
        final mileage = double.parse(_mileageController.text);
        final status = _selectedStatus ?? 'Active';
        final vendor = _vendorController.text.trim().isNotEmpty ? _vendorController.text.trim() : null;
        
        // Location data
        final country = _countryController.text.trim().isNotEmpty ? _countryController.text.trim() : null;
        final state = _stateController.text.trim().isNotEmpty ? _stateController.text.trim() : null;
        final city = _cityController.text.trim().isNotEmpty ? _cityController.text.trim() : null;

        print('=== SUBMITTING FORM ===');
        print('Mode: ${widget.isEditMode ? "EDIT" : "CREATE"}');
        print('Vehicle ID for update: ${widget.vehicleId}');
        print('Registration: $registrationNumber');
        print('Make: $make, Model: $model');
        print('Year: $yearOfManufacture');
        print('Vendor: $vendor');
        print('Status: $status');
        print('=====================');

        Map<String, dynamic> response;
        
        if (widget.isEditMode) {
          // For edit mode - also split make and model
          final vehicleData = {
            'registrationNumber': registrationNumber,
            'vehicleType': vehicleType,
            'make': make,
            'model': model,
            'yearOfManufacture': yearOfManufacture,
            'engineType': engineType,
            'engineCapacity': engineCapacity,
            'seatingCapacity': seatingCapacity,
            'mileage': mileage,
            'status': status,
            if (vendor != null) 'vendor': vendor,
            if (country != null) 'country': country,
            if (state != null) 'state': state,
            if (city != null) 'city': city,
          };
          
          print('Update payload: $vehicleData');
          
          response = await _vehicleService.updateVehicle(
            widget.vehicleId!,
            vehicleData,
          );
        } else {
          // For create mode - send separate make and model
          response = await _vehicleService.createVehicle(
            registrationNumber: registrationNumber,
            vehicleType: vehicleType,
            make: make,
            model: model,
            yearOfManufacture: yearOfManufacture,
            engineType: engineType,
            engineCapacity: engineCapacity,
            seatingCapacity: seatingCapacity,
            mileage: mileage,
            status: status,
            vendor: vendor,
            country: country,
            state: state,
            city: city,
          );
        }

        print('=== API RESPONSE ===');
        print('Success: ${response['success']}');
        print('Message: ${response['message']}');
        print('Errors: ${response['errors']}');
        print('===================');

        if (response['success']) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        response['message'] ?? 'Vehicle ${widget.isEditMode ? 'updated' : 'created'} successfully',
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
            widget.onSave();
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(response['message'] ?? 'Operation failed'),
                    ),
                  ],
                ),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          }
        }
      } catch (e) {
        print('=== ERROR ===');
        print('Error submitting form: $e');
        print('=============');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Error: ${e.toString()}'),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isSubmitting = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Section 1: Basic Information
              _buildSectionCard(
                title: 'Basic Information',
                icon: Icons.directions_car_filled,
                child: Column(
                  children: [
                    _buildTextFormField(
                      controller: _registrationController,
                      label: 'Registration Number *',
                      hint: 'e.g., KA01AB1234',
                      icon: Icons.confirmation_number_outlined,
                      enabled: !widget.isEditMode,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Registration number is required';
                        }
                        final regExp = RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z]{1,2}[0-9]{4}$');
                        if (!regExp.hasMatch(value.toUpperCase())) {
                          return 'Invalid format (e.g., KA01AB1234)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildDropdownFormField(
                      value: _selectedVehicleType,
                      items: const ['Bus', 'Van', 'Car', 'Truck', 'Mini Bus'],
                      label: 'Vehicle Type *',
                      hint: 'Select a vehicle type',
                      icon: Icons.category_outlined,
                      onChanged: (value) => setState(() => _selectedVehicleType = value),
                    ),
                    const SizedBox(height: 16),
                    _buildTextFormField(
                      controller: _makeModelController,
                      label: 'Make & Model *',
                      hint: 'e.g., Tata Starbus Urban',
                      icon: Icons.branding_watermark_outlined,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Make & Model is required';
                        }
                        if (value.length < 2 || value.length > 100) {
                          return 'Must be between 2-100 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildTextFormField(
                      controller: _yearController,
                      label: 'Year of Manufacture *',
                      hint: 'e.g., 2023',
                      icon: Icons.calendar_today_outlined,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Year is required';
                        }
                        final year = int.tryParse(value);
                        if (year == null || year < 1990 || year > DateTime.now().year) {
                          return 'Year must be between 1990 and ${DateTime.now().year}';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildTextFormField(
                      controller: _vendorController,
                      label: 'Vendor (Optional)',
                      hint: 'e.g., ABC Transport Services',
                      icon: Icons.business_outlined,
                      validator: null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Section 2: Technical Specifications
              _buildSectionCard(
                title: 'Technical Specifications',
                icon: Icons.miscellaneous_services_rounded,
                child: Column(
                  children: [
                    _buildDropdownFormField(
                      value: _selectedEngineType,
                      items: const ['Diesel', 'Petrol', 'CNG', 'Electric', 'Hybrid'],
                      label: 'Engine Type *',
                      hint: 'Select an engine type',
                      icon: Icons.local_gas_station_outlined,
                      onChanged: (value) => setState(() => _selectedEngineType = value),
                    ),
                    const SizedBox(height: 16),
                    _buildTextFormField(
                      controller: _engineCapacityController,
                      label: 'Engine Capacity (CC) *',
                      hint: 'e.g., 2200',
                      icon: Icons.power_input_outlined,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Engine capacity is required';
                        }
                        final capacity = double.tryParse(value);
                        if (capacity == null || capacity < 100 || capacity > 10000) {
                          return 'Must be between 100-10000 CC';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildTextFormField(
                      controller: _seatingCapacityController,
                      label: 'Seating Capacity *',
                      hint: 'e.g., 40',
                      icon: Icons.people_alt_outlined,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Seating capacity is required';
                        }
                        final capacity = int.tryParse(value);
                        if (capacity == null || capacity < 1 || capacity > 100) {
                          return 'Must be between 1-100';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildTextFormField(
                      controller: _mileageController,
                      label: 'Mileage (km/l) *',
                      hint: 'e.g., 12.5',
                      icon: Icons.speed_outlined,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Mileage is required';
                        }
                        final mileage = double.tryParse(value);
                        if (mileage == null || mileage < 0 || mileage > 50) {
                          return 'Must be between 0-50 km/l';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildDropdownFormField(
                      value: _selectedStatus,
                      items: const ['Active', 'Inactive', 'Maintenance'],
                      label: 'Status ${widget.isEditMode ? '*' : ''}',
                      hint: 'Select status',
                      icon: Icons.info_outlined,
                      onChanged: (value) => setState(() => _selectedStatus = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Section 3: Location Information
              _buildSectionCard(
                title: 'Location Information',
                icon: Icons.location_on_outlined,
                child: Column(
                  children: [
                    _buildTextFormField(
                      controller: _countryController,
                      label: 'Country (Optional)',
                      hint: 'e.g., India',
                      icon: Icons.public_outlined,
                      validator: null,
                    ),
                    const SizedBox(height: 16),
                    _buildTextFormField(
                      controller: _stateController,
                      label: 'State (Optional)',
                      hint: 'e.g., Karnataka',
                      icon: Icons.map_outlined,
                      validator: null,
                    ),
                    const SizedBox(height: 16),
                    _buildTextFormField(
                      controller: _cityController,
                      label: 'City (Optional)',
                      hint: 'e.g., Bangalore',
                      icon: Icons.location_city_outlined,
                      validator: null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Info card
              Card(
                color: Colors.blue.shade50,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.isEditMode 
                            ? 'Note: Make changes to the vehicle details and click Update to save.'
                            : 'Note: You can upload compliance documents after creating the vehicle from the vehicle details page.',
                          style: TextStyle(
                            color: Colors.blue.shade900,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      side: BorderSide(color: Colors.grey.shade400),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submitForm,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(widget.isEditMode ? Icons.update_rounded : Icons.save_alt_rounded),
                    label: Text(_isSubmitting 
                      ? (widget.isEditMode ? 'Updating...' : 'Saving...') 
                      : (widget.isEditMode ? 'Update Vehicle' : 'Save Vehicle')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryLightColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(icon, color: primaryColor, size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.black12),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: primaryColor),
        filled: !enabled,
        fillColor: enabled ? null : Colors.grey.shade100,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildDropdownFormField({
    required String? value,
    required List<String> items,
    required String label,
    required String hint,
    required IconData icon,
    required void Function(String?) onChanged,
  }) {
    // Ensure the value is in the items list, or set to null
    final validValue = (value != null && items.contains(value)) ? value : null;
    
    return DropdownButtonFormField<String>(
      value: validValue,
      items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: primaryColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
      ),
      validator: (value) => value == null ? 'Please select $label' : null,
    );
  }
}