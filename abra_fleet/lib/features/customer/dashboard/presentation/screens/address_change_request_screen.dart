import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../../../core/services/roster_service.dart';
import '../../../../../core/services/api_service.dart';
import 'location_picker_screen.dart';

class AddressChangeRequestScreen extends StatefulWidget {
  const AddressChangeRequestScreen({Key? key}) : super(key: key);

  @override
  State<AddressChangeRequestScreen> createState() => _AddressChangeRequestScreenState();
}

class _AddressChangeRequestScreenState extends State<AddressChangeRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  late final RosterService _rosterService;
  
  String? _currentPickupAddress;
  String? _newPickupAddress;
  LatLng? _newPickupLatLng;
  
  String? _currentDropAddress;
  String? _newDropAddress;
  LatLng? _newDropLatLng;
  
  bool _isLoading = false;
  bool _isLoadingCurrentAddresses = true;
  int _affectedTripsCount = 0;

  @override
  void initState() {
    super.initState();
    _rosterService = RosterService(apiService: ApiService());
    _loadCurrentAddresses();
  }

  Future<void> _loadCurrentAddresses() async {
    setState(() => _isLoadingCurrentAddresses = true);
    
    try {
      final response = await _rosterService.getCurrentAddresses();
      
      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        setState(() {
          _currentPickupAddress = data['pickupLocation'] ?? 'Not set';
          _currentDropAddress = data['dropLocation'] ?? 'Not set';
        });
      }
    } catch (e) {
      print('Error loading current addresses: $e');
      // Set default values on error
      if (mounted) {
        setState(() {
          _currentPickupAddress = 'Not set';
          _currentDropAddress = 'Not set';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingCurrentAddresses = false);
      }
    }
  }

  Future<void> _pickLocation(bool isPickup) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          title: isPickup ? 'Select New Pickup Location' : 'Select New Drop Location',
          initialLocation: isPickup ? _newPickupLatLng : _newDropLatLng,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        if (isPickup) {
          _newPickupAddress = result['address'];
          _newPickupLatLng = result['latLng'];
        } else {
          _newDropAddress = result['address'];
          _newDropLatLng = result['latLng'];
        }
      });
    }
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    if (_newPickupAddress == null || _newDropAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select both new pickup and drop locations'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await _rosterService.submitAddressChangeRequest(
        currentPickupAddress: _currentPickupAddress ?? '',
        newPickupAddress: _newPickupAddress!,
        newPickupLat: _newPickupLatLng?.latitude,
        newPickupLng: _newPickupLatLng?.longitude,
        currentDropAddress: _currentDropAddress ?? '',
        newDropAddress: _newDropAddress!,
        newDropLat: _newDropLatLng?.latitude,
        newDropLng: _newDropLatLng?.longitude,
        reason: _reasonController.text.trim(),
      );

      if (response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Address change request submitted successfully!',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Processing will take ${response['data']?['estimatedProcessingDays'] ?? '4-5 working days'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception(response['message'] ?? 'Failed to submit request');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Address Change'),
        backgroundColor: const Color(0xFF2196F3),
      ),
      body: _isLoadingCurrentAddresses
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info Card
                    Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue.shade700),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Processing Time',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Address changes take 4 to 5 working days to process',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.blue.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Current Addresses Section
                    Text(
                      'Current Addresses',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    
                    _buildAddressCard(
                      'Current Pickup',
                      _currentPickupAddress ?? 'Not set',
                      Icons.location_on,
                      Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    
                    _buildAddressCard(
                      'Current Drop',
                      _currentDropAddress ?? 'Not set',
                      Icons.location_on,
                      Colors.grey,
                    ),
                    
                    const SizedBox(height: 24),

                    // New Addresses Section
                    Text(
                      'New Addresses',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),

                    // New Pickup Location
                    _buildLocationSelector(
                      'New Pickup Location',
                      _newPickupAddress,
                      () => _pickLocation(true),
                      Icons.my_location,
                      Colors.green,
                    ),
                    const SizedBox(height: 12),

                    // New Drop Location
                    _buildLocationSelector(
                      'New Drop Location',
                      _newDropAddress,
                      () => _pickLocation(false),
                      Icons.location_on,
                      Colors.red,
                    ),
                    const SizedBox(height: 24),

                    // Reason
                    Text(
                      'Reason for Change (Optional)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _reasonController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'e.g., Moved to a new house, Office location changed',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submitRequest,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2196F3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'Submit Request',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAddressCard(String label, String address, IconData icon, Color color) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
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

  Widget _buildLocationSelector(
    String label,
    String? address,
    VoidCallback onTap,
    IconData icon,
    Color color,
  ) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          color: address != null ? Colors.green.shade50 : Colors.white,
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address ?? 'Tap to select location on map',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: address != null ? Colors.black87 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey.shade600,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }
}
