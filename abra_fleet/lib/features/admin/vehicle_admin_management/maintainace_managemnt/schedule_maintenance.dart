import 'package:flutter/material.dart';
import 'package:abra_fleet/core/services/maintenance_service.dart';
import 'package:abra_fleet/core/services/vehicle_service.dart';
import 'package:abra_fleet/core/services/vendor_service.dart';

const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kTextPrimaryColor = Color(0xFF212121);
const Color kTextSecondaryColor = Color(0xFF757575);
const Color kWarningColor = Color(0xFFF57C00);
const Color kWarningBackgroundColor = Color(0xFFFFF8E1);
const Color kSuccessColor = Color(0xFF4CAF50);
const Color kErrorColor = Color(0xFFF44336);
const Color kInfoColor = Color(0xFF0288D1);

// ============ DATA MODEL FOR VENDOR ============
class Vendor {
  final String id;
  final String name;
  final String contactEmail;
  final String phone;
  final String location;

  Vendor({
    required this.id,
    required this.name,
    required this.contactEmail,
    required this.phone,
    required this.location,
  });

  factory Vendor.fromJson(Map<String, dynamic> json) {
    return Vendor(
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      contactEmail: json['email'] ?? '',
      phone: json['phone'] ?? '',
      location: json['location'] ?? '',
    );
  }
}

// ============ DATA MODEL FOR VEHICLE ============
class Vehicle {
  final String id;
  final String registrationNumber;
  final String makeModel;
  final String vehicleType;
  final int seatingCapacity;
  final String status;

  Vehicle({
    required this.id,
    required this.registrationNumber,
    required this.makeModel,
    required this.vehicleType,
    required this.seatingCapacity,
    required this.status,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    int seatingCapacity = 0;
    
    try {
      if (json['seatCapacity'] != null) {
        seatingCapacity = json['seatCapacity'];
      } else if (json['seatingCapacity'] != null) {
        seatingCapacity = json['seatingCapacity'];
      } else if (json['capacity'] != null) {
        final capacity = json['capacity'];
        if (capacity is Map && capacity['passengers'] != null) {
          seatingCapacity = capacity['passengers'];
        } else if (capacity is num) {
          seatingCapacity = capacity.toInt();
        } else {
          seatingCapacity = int.tryParse(capacity.toString()) ?? 4;
        }
      } else {
        seatingCapacity = 4;
      }
    } catch (e) {
      print('Error parsing seating capacity: $e');
      seatingCapacity = 4;
    }
    
    return Vehicle(
      id: json['_id'] ?? json['id'] ?? '',
      registrationNumber: json['registrationNumber'] ?? json['vehicleNumber'] ?? '',
      makeModel: json['makeModel'] ?? '${json['make'] ?? ''} ${json['model'] ?? ''}'.trim(),
      vehicleType: json['vehicleType'] ?? json['type'] ?? '',
      seatingCapacity: seatingCapacity,
      status: json['status'] ?? 'active',
    );
  }
}

// ============ SCHEDULE MAINTENANCE SCREEN (ENHANCED WITH SEARCHABLE DROPDOWN) ============
class ScheduleMaintenanceScreen extends StatefulWidget {
  final VoidCallback onBack;
  const ScheduleMaintenanceScreen({required this.onBack, Key? key})
      : super(key: key);

  @override
  State<ScheduleMaintenanceScreen> createState() =>
      _ScheduleMaintenanceScreenState();
}

class _ScheduleMaintenanceScreenState extends State<ScheduleMaintenanceScreen> {
  int _currentStep = 0;
  final _formKey = GlobalKey<FormState>();
  final MaintenanceService _maintenanceService = MaintenanceService();
  final VehicleService _vehicleService = VehicleService();
  final VendorService _vendorService = VendorService();
  bool _isSubmitting = false;
  bool _isLoadingVehicles = true;
  bool _isLoadingVendors = true;

  // Form Data
  String? _selectedVehicle;
  String? _selectedType;
  DateTime? _selectedDate;
  final _descriptionController = TextEditingController();
  bool _assignToVendor = true;
  Vendor? _selectedVendor;
  String _selectedPriority = 'medium';
  final _estimatedCostController = TextEditingController();

  // Vehicle Data
  List<Vehicle> _vehicles = [];
  List<Vehicle> _filteredVehicles = [];
  Vehicle? _selectedVehicleObject;
  final _vehicleSearchController = TextEditingController();

  // Vendor Data
  List<Vendor> _vendors = [];

  Future<void> _fetchVehicles() async {
  setState(() => _isLoadingVehicles = true);

  try {
    print('🚗 Fetching vehicles from backend...');
    final response = await _vehicleService.getVehicles(limit: 100);

    if (response['success'] == true) {
      final List<dynamic> vehiclesData = response['data'] ?? [];
      final List<Vehicle> fetchedVehicles = vehiclesData.map((data) {
        return Vehicle.fromJson(data);
      }).toList();

      setState(() {
        _vehicles = fetchedVehicles;
        _filteredVehicles = fetchedVehicles;
        _isLoadingVehicles = false;
      });

      print('✅ Successfully fetched ${_vehicles.length} vehicles');
    } else {
      print('❌ Failed to fetch vehicles: ${response['message']}');
      setState(() => _isLoadingVehicles = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load vehicles: ${response['message']}'),
            backgroundColor: kErrorColor,
          ),
        );
      }
    }
  } catch (e) {
    print('❌ Error fetching vehicles: $e');
    setState(() => _isLoadingVehicles = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading vehicles: ${e.toString()}'),
          backgroundColor: kErrorColor,
        ),
      );
    }
  }
}

  // Fetch vendors from backend
  Future<void> _fetchVendors() async {
    setState(() => _isLoadingVendors = true);
    
    try {
      print('🏪 Fetching vendors from backend...');
      final result = await _vendorService.getVendors();

      if (result['success']) {
        final List<dynamic> vendorsData = result['data'] ?? [];
        final List<Vendor> fetchedVendors = vendorsData.map((data) {
          print('🏪 Processing vendor data: ${data['name']} - ${data['email']}');
          return Vendor.fromJson(data);
        }).toList();

        setState(() {
          _vendors = fetchedVendors;
          _isLoadingVendors = false;
        });

        print('✅ Successfully fetched ${_vendors.length} vendors');
        for (var vendor in _vendors) {
          print('   - ${vendor.name} (${vendor.contactEmail}) - ${vendor.location}');
        }
      } else {
        print('❌ Failed to fetch vendors: ${result['message']}');
        setState(() => _isLoadingVendors = false);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load vendors: ${result['message']}'),
              backgroundColor: kErrorColor,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error fetching vendors: $e');
      setState(() => _isLoadingVendors = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading vendors: ${e.toString()}'),
            backgroundColor: kErrorColor,
          ),
        );
      }
    }
  }

  final List<String> _maintenanceTypes = [
    'Oil Change',
    'Filter Replacement',
    'Tire Rotation',
    'Brake Service',
    'General Inspection',
    'AC Service',
    'Engine Diagnostics',
  ];

  @override
  void initState() {
    super.initState();
    _fetchVehicles();
    _fetchVendors();
    _vehicleSearchController.addListener(_filterVehicles);
  }

  // Filter vehicles based on search query
  void _filterVehicles() {
    final query = _vehicleSearchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredVehicles = _vehicles;
      } else {
        _filteredVehicles = _vehicles.where((vehicle) {
          return vehicle.registrationNumber.toLowerCase().contains(query) ||
                 vehicle.makeModel.toLowerCase().contains(query) ||
                 vehicle.vehicleType.toLowerCase().contains(query) ||
                 vehicle.status.toLowerCase().contains(query) ||
                 vehicle.id.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _estimatedCostController.dispose();
    _vehicleSearchController.dispose();
    super.dispose();
  }

  // Show searchable vehicle selection dialog
  Future<void> _showVehicleSelectionDialog() async {
    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Select Vehicle'),
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Search Bar
                    TextField(
                      controller: _vehicleSearchController,
                      decoration: InputDecoration(
                        hintText: 'Search by registration, model, type...',
                        prefixIcon: const Icon(Icons.search, color: kPrimaryColor),
                        suffixIcon: _vehicleSearchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  setDialogState(() {
                                    _vehicleSearchController.clear();
                                  });
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          _filterVehicles();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    
                    // Results count
                    if (_filteredVehicles.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Showing ${_filteredVehicles.length} of ${_vehicles.length} vehicles',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    
                    // Vehicle List
                    Flexible(
                      child: _isLoadingVehicles
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24.0),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : _filteredVehicles.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.search_off,
                                          size: 48,
                                          color: Colors.grey.shade400,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          _vehicleSearchController.text.isNotEmpty
                                              ? 'No vehicles found matching "${_vehicleSearchController.text}"'
                                              : 'No vehicles available',
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 14,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: _filteredVehicles.length,
                                  separatorBuilder: (context, index) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final vehicle = _filteredVehicles[index];
                                    final isSelected = _selectedVehicle == vehicle.id;
                                    
                                    return ListTile(
                                      selected: isSelected,
                                      selectedTileColor: kPrimaryColor.withOpacity(0.1),
                                      leading: CircleAvatar(
                                        backgroundColor: isSelected
                                            ? kPrimaryColor
                                            : vehicle.status.toLowerCase() == 'active'
                                                ? Colors.green.shade100
                                                : Colors.orange.shade100,
                                        child: Icon(
                                          Icons.directions_car,
                                          color: isSelected
                                              ? Colors.white
                                              : vehicle.status.toLowerCase() == 'active'
                                                  ? Colors.green.shade800
                                                  : Colors.orange.shade800,
                                          size: 20,
                                        ),
                                      ),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              vehicle.registrationNumber,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: isSelected ? kPrimaryColor : Colors.black,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: vehicle.status.toLowerCase() == 'active'
                                                  ? Colors.green.shade100
                                                  : Colors.orange.shade100,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              vehicle.status.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: vehicle.status.toLowerCase() == 'active'
                                                    ? Colors.green.shade800
                                                    : Colors.orange.shade800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      subtitle: Text(
                                        '${vehicle.makeModel} • ${vehicle.vehicleType} • ${vehicle.seatingCapacity} seats',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      trailing: isSelected
                                          ? Icon(Icons.check_circle, color: kPrimaryColor)
                                          : null,
                                      onTap: () {
                                        setState(() {
                                          _selectedVehicle = vehicle.id;
                                          _selectedVehicleObject = vehicle;
                                        });
                                        Navigator.of(dialogContext).pop();
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
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.light(primary: kPrimaryColor),
      ),
      child: Stepper(
        type: StepperType.vertical,
        currentStep: _currentStep,
        onStepContinue: () {
          final isLastStep = _currentStep == getSteps().length - 1;

          if (_currentStep == 0 && !_formKey.currentState!.validate()) {
            return;
          }

          if (isLastStep) {
            _submitRequest();
          } else {
            setState(() => _currentStep += 1);
          }
        },
        onStepCancel:
            _currentStep == 0 ? null : () => setState(() => _currentStep -= 1),
        onStepTapped: (step) => setState(() => _currentStep = step),
        steps: getSteps(),
        controlsBuilder: (context, details) {
          final isLastStep = _currentStep == getSteps().length - 1;
          return Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : details.onStepContinue,
                    child: _isSubmitting 
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isLastStep ? 'CONFIRM & SCHEDULE' : 'CONTINUE'),
                  ),
                ),
                const SizedBox(width: 12),
                if (_currentStep != 0)
                  Expanded(
                    child: TextButton(
                      onPressed: _isSubmitting ? null : details.onStepCancel,
                      child: const Text('BACK'),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Step> getSteps() => [
        Step(
          isActive: _currentStep >= 0,
          title: const Text('Service Details'),
          content: _buildServiceDetailsForm(),
        ),
        Step(
          isActive: _currentStep >= 1,
          title: const Text('Assign Vendor'),
          content: _buildVendorSelection(),
        ),
        Step(
          isActive: _currentStep >= 2,
          title: const Text('Preview Notification'),
          content: _buildNotificationPreview(),
        ),
        Step(
          isActive: _currentStep >= 3,
          title: const Text('Confirm & Schedule'),
          content: _buildConfirmation(),
        ),
      ];

  Widget _buildServiceDetailsForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select Vehicle',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          
          // Vehicle Selection Button (opens searchable dialog)
          FormField<String>(
            validator: (value) =>
                _selectedVehicle == null ? 'Please select a vehicle' : null,
            builder: (FormFieldState<String> state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: _isLoadingVehicles ? null : _showVehicleSelectionDialog,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: state.hasError ? kErrorColor : Colors.grey.shade400,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: _isLoadingVehicles
                          ? const Row(
                              children: [
                                SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                SizedBox(width: 12),
                                Text('Loading vehicles...'),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: _selectedVehicleObject != null
                                      ? Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    _selectedVehicleObject!.registrationNumber,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: _selectedVehicleObject!.status.toLowerCase() == 'active'
                                                        ? Colors.green.shade100
                                                        : Colors.orange.shade100,
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    _selectedVehicleObject!.status.toUpperCase(),
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.bold,
                                                      color: _selectedVehicleObject!.status.toLowerCase() == 'active'
                                                          ? Colors.green.shade800
                                                          : Colors.orange.shade800,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${_selectedVehicleObject!.makeModel} • ${_selectedVehicleObject!.vehicleType} • ${_selectedVehicleObject!.seatingCapacity} seats',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        )
                                      : Text(
                                          'Tap to select a vehicle',
                                          style: TextStyle(color: Colors.grey.shade600),
                                        ),
                                ),
                                Icon(
                                  Icons.arrow_drop_down,
                                  color: Colors.grey.shade600,
                                ),
                              ],
                            ),
                    ),
                  ),
                  if (state.hasError)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, left: 12.0),
                      child: Text(
                        state.errorText!,
                        style: TextStyle(color: kErrorColor, fontSize: 12),
                      ),
                    ),
                  if (!_isLoadingVehicles && _vehicles.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0, left: 12.0),
                      child: Text(
                        'Total ${_vehicles.length} vehicles available',
                        style: TextStyle(
                          color: kPrimaryColor,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          
          const SizedBox(height: 16),
          const Text('Maintenance Type',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FormField<String>(
            validator: (value) =>
                _selectedType == null ? 'Please select a maintenance type' : null,
            builder: (FormFieldState<String> state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _maintenanceTypes
                        .map((type) => FilterChip(
                              label: Text(type),
                              selected: _selectedType == type,
                              onSelected: (selected) => setState(() {
                                _selectedType = selected ? type : null;
                                state.didChange(_selectedType);
                              }),
                              selectedColor: kPrimaryColor,
                              labelStyle: TextStyle(
                                  color: _selectedType == type
                                      ? Colors.white
                                      : null),
                            ))
                        .toList(),
                  ),
                  if (state.hasError)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, left: 12.0),
                      child: Text(state.errorText!,
                          style: TextStyle(color: kErrorColor, fontSize: 12)),
                    )
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          const Text('Schedule Date',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FormField<DateTime>(
            validator: (value) =>
                _selectedDate == null ? 'Please select a date' : null,
            builder: (FormFieldState<DateTime> state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 90)),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                        state.didChange(_selectedDate);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              color: kPrimaryColor),
                          const SizedBox(width: 12),
                          Text(_selectedDate != null
                              ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
                              : 'Select a Date'),
                        ],
                      ),
                    ),
                  ),
                  if (state.hasError)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, left: 12.0),
                      child: Text(state.errorText!,
                          style: TextStyle(color: kErrorColor, fontSize: 12)),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          const Text('Additional Notes / Description',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'e.g., Check for rattling noise from the back.',
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          const Text('Priority Level',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(
                border: OutlineInputBorder(), hintText: 'Select priority'),
            value: _selectedPriority,
            onChanged: (value) => setState(() => _selectedPriority = value!),
            items: const [
              DropdownMenuItem(value: 'low', child: Text('Low Priority')),
              DropdownMenuItem(value: 'medium', child: Text('Medium Priority')),
              DropdownMenuItem(value: 'high', child: Text('High Priority')),
              DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Estimated Cost (Optional)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _estimatedCostController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Enter estimated cost in ₹',
              prefixText: '₹ ',
            ),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    );
  }

  Widget _buildVendorSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Assign to a specific vendor'),
          value: _assignToVendor,
          onChanged: (value) => setState(() {
            _assignToVendor = value;
            if (!value) _selectedVendor = null;
          }),
        ),
        const SizedBox(height: 8),
        if (_assignToVendor)
          const Text('Select a Vendor',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        if (_assignToVendor && _isLoadingVendors)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          ),
        if (_assignToVendor && !_isLoadingVendors && _vendors.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'No vendors available. Please add vendors first.',
              style: TextStyle(color: kErrorColor, fontSize: 14),
            ),
          ),
        if (_assignToVendor && !_isLoadingVendors && _vendors.isNotEmpty)
          ..._vendors.map((vendor) => RadioListTile<Vendor>(
                title: Text(vendor.name),
                subtitle: Text('${vendor.location} • ${vendor.contactEmail}'),
                value: vendor,
                groupValue: _selectedVendor,
                onChanged: (value) => setState(() => _selectedVendor = value),
              )),
        if (!_assignToVendor)
          const ListTile(
            leading: Icon(Icons.info_outline, color: kInfoColor),
            title: Text(
                'This service request will be open for all vendors to view and bid on.',
                style: TextStyle(fontSize: 13, color: kTextSecondaryColor)),
          ),
      ],
    );
  }

  Widget _buildNotificationPreview() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Notification Preview',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(height: 24),
          _buildPreviewRow('To:',
              _selectedVendor?.contactEmail ?? 'All Registered Vendors'),
          _buildPreviewRow('Subject:',
              'New Maintenance Request for ${_selectedVehicleObject?.registrationNumber ?? _selectedVehicle ?? 'Vehicle'}'),
          const Divider(height: 24),
          const Text('Message:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Dear ${_selectedVendor?.name ?? 'Vendor'},\n\nA new maintenance service has been requested for vehicle ${_selectedVehicleObject?.registrationNumber ?? _selectedVehicle ?? ''}.\n\nDetails:\n- Service: ${_selectedType ?? ''}\n- Preferred Date: ${_selectedDate != null ? "${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}" : 'Not specified'}\n\nNotes:\n${_descriptionController.text.isNotEmpty ? _descriptionController.text : 'None'}\n\nPlease confirm your availability.\n\nThank you.',
            style: TextStyle(height: 1.5, color: kTextSecondaryColor),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildConfirmation() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Please review the details before confirming.',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const Divider(height: 24),
          _buildPreviewRow('Vehicle:', _selectedVehicleObject?.registrationNumber ?? _selectedVehicle ?? 'N/A'),
          _buildPreviewRow('Service:', _selectedType ?? 'N/A'),
          _buildPreviewRow(
              'Date:',
              _selectedDate != null
                  ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
                  : 'N/A'),
          _buildPreviewRow('Assigned To:',
              _selectedVendor?.name ?? 'Open for all vendors'),
          _buildPreviewRow('Notes:',
              _descriptionController.text.isNotEmpty ? _descriptionController.text : 'None'),
        ],
      ),
    );
  }

  void _submitRequest() async {
    if (_assignToVendor && _selectedVendor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a vendor before confirming.'),
          backgroundColor: kErrorColor,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      double? estimatedCost;
      if (_estimatedCostController.text.isNotEmpty) {
        estimatedCost = double.tryParse(_estimatedCostController.text);
      }

      final result = await _maintenanceService.scheduleMaintenanceWithEmail(
        vehicleId: _selectedVehicle!,
        maintenanceType: _selectedType!,
        scheduledDate: _selectedDate!,
        vendorEmail: _selectedVendor!.contactEmail,
        vendorName: _selectedVendor!.name,
        description: _descriptionController.text.isNotEmpty ? _descriptionController.text : null,
        estimatedCost: estimatedCost,
        priority: _selectedPriority,
      );

      if (result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Maintenance successfully scheduled for ${_selectedVehicleObject?.registrationNumber ?? _selectedVehicle}! Real-time email sent to ${_selectedVendor!.name}.',
            ),
            backgroundColor: kSuccessColor,
            duration: const Duration(seconds: 4),
          ),
        );

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('✅ Maintenance Scheduled'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vehicle: ${_selectedVehicleObject?.registrationNumber ?? _selectedVehicle}'),
                Text('Service: $_selectedType'),
                Text('Date: ${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'),
                Text('Vendor: ${_selectedVendor!.name}'),
                Text('Priority: ${_selectedPriority.toUpperCase()}'),
                const SizedBox(height: 10),
                const Text(
                  '📧 Real-time email notification has been sent to the vendor with all maintenance details.',
                  style: TextStyle(color: kSuccessColor, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onBack();
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Failed to schedule maintenance'),
            backgroundColor: kErrorColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: kErrorColor,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }
}