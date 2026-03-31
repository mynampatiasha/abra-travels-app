import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:http/http.dart' as http;
import '../admin/vehicle_admin_management/trip_operations/route_selection_page.dart';

class StartClientTripPage extends StatefulWidget {
  const StartClientTripPage({Key? key}) : super(key: key);

  @override
  _StartClientTripPageState createState() => _StartClientTripPageState();
}

class _StartClientTripPageState extends State<StartClientTripPage> {
  // Form controllers
  final TextEditingController _clientNameController = TextEditingController();
  final TextEditingController _clientEmailController = TextEditingController();
  final TextEditingController _clientPhoneController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  
  // Route data
  LatLng? _startPoint;
  LatLng? _endPoint;
  String? _startAddress;
  String? _endAddress;
  
  // Time selection
  DateTime? _selectedPickupTime;
  DateTime? _selectedDropTime;
  
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedPickupTime = DateTime.now().add(const Duration(minutes: 30));
    _loadClientInfo();
  }

  @override
  void dispose() {
    _clientNameController.dispose();
    _clientEmailController.dispose();
    _clientPhoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadClientInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user_data');
      
      if (userJson != null) {
        final userData = json.decode(userJson);
        setState(() {
          _clientNameController.text = userData['name'] ?? '';
          _clientEmailController.text = userData['email'] ?? '';
          _clientPhoneController.text = userData['phone'] ?? userData['phoneNumber'] ?? '';
        });
      }
    } catch (e) {
      print('Error loading client info: $e');
    }
  }

  Future<void> _selectPickupTime() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedPickupTime ?? DateTime.now().add(const Duration(minutes: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1A237E),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF212121),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedPickupTime ?? DateTime.now().add(const Duration(minutes: 30))),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF1A237E),
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: Color(0xFF212121),
              ),
            ),
            child: child!,
          );
        },
      );

      if (pickedTime != null) {
        setState(() {
          _selectedPickupTime = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  Future<void> _selectDropTime() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDropTime ?? (_selectedPickupTime?.add(const Duration(hours: 1)) ?? DateTime.now().add(const Duration(hours: 1))),
      firstDate: _selectedPickupTime ?? DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1A237E),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF212121),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDropTime ?? (_selectedPickupTime?.add(const Duration(hours: 1)) ?? DateTime.now().add(const Duration(hours: 1)))),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF1A237E),
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: Color(0xFF212121),
              ),
            ),
            child: child!,
          );
        },
      );

      if (pickedTime != null) {
        setState(() {
          _selectedDropTime = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  Future<void> _openRouteSelection() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => RouteSelectionPage(
          initialStartPoint: _startPoint,
          initialEndPoint: _endPoint,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _startPoint = result['startPoint'] as LatLng?;
        _endPoint = result['endPoint'] as LatLng?;
        _startAddress = result['startAddress'] as String?;
        _endAddress = result['endAddress'] as String?;
      });
    }
  }

  double _calculateRouteDistance() {
    if (_startPoint == null || _endPoint == null) return 0;
    
    final distance = Distance();
    return distance.as(
      LengthUnit.Kilometer,
      _startPoint!,
      _endPoint!,
    );
  }

  Future<void> _submitTripRequest() async {
    // Validation
    if (_clientNameController.text.trim().isEmpty) {
      _showErrorSnackBar('Please enter your name');
      return;
    }

    if (_clientEmailController.text.trim().isEmpty) {
      _showErrorSnackBar('Please enter your email');
      return;
    }

    if (_clientPhoneController.text.trim().isEmpty) {
      _showErrorSnackBar('Please enter your phone number');
      return;
    }

    if (_startPoint == null || _endPoint == null) {
      _showErrorSnackBar('Please select pickup and drop locations');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      
      if (token == null || token.isEmpty) {
        throw Exception('Please login to create a trip request');
      }

      final tripData = {
        'clientName': _clientNameController.text.trim(),
        'clientEmail': _clientEmailController.text.trim(),
        'clientPhone': _clientPhoneController.text.trim(),
        'startPoint': {
          'latitude': _startPoint!.latitude,
          'longitude': _startPoint!.longitude,
          'address': _startAddress ?? 'Pickup Location',
        },
        'endPoint': {
          'latitude': _endPoint!.latitude,
          'longitude': _endPoint!.longitude,
          'address': _endAddress ?? 'Drop Location',
        },
        'distance': _calculateRouteDistance(),
        'scheduledPickupTime': (_selectedPickupTime ?? DateTime.now().add(const Duration(minutes: 30))).toIso8601String(),
        'scheduledDropTime': _selectedDropTime?.toIso8601String(),
        'notes': _notesController.text.trim(),
      };

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/client-trips/create'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(tripData),
      );

      final responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        if (mounted) {
          _showSuccessDialog(responseData['data']);
        }
      } else {
        throw Exception(responseData['message'] ?? 'Failed to create trip request');
      }
      
    } catch (e) {
      print('❌ Error creating trip request: $e');
      
      if (mounted) {
        _showErrorSnackBar('Failed to create trip request: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showSuccessDialog(Map<String, dynamic> tripData) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.check_circle, color: Colors.green.shade700, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Trip Request Sent!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.confirmation_number, color: Colors.blue.shade700, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Trip Number',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tripData['tripNumber'] ?? 'N/A',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _buildInfoRow(Icons.account_circle, 'Client', tripData['client']['name']),
              _buildInfoRow(Icons.email, 'Email', tripData['client']['email']),
              _buildInfoRow(Icons.phone, 'Phone', tripData['client']['phone']),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              _buildInfoRow(Icons.straighten, 'Distance', '${tripData['trip']['distance'].toStringAsFixed(1)} km'),
              _buildInfoRow(Icons.access_time, 'Duration', '${tripData['trip']['estimatedDuration']} min'),
              _buildInfoRow(Icons.schedule, 'Pickup Time', _formatDateTime(tripData['trip']['pickupTime'])),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'What Happens Next?',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...((tripData['nextSteps'] as List).map((step) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.green.shade700,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              step.toString(),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.green.shade900,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ))),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(true); // Go back to trips list with success flag
              _clearForm();
            },
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Create Another'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog only
              _clearForm();
            },
          ),
        ],
      ),
    );
  }

  void _clearForm() {
    setState(() {
      _clientNameController.clear();
      _clientEmailController.clear();
      _clientPhoneController.clear();
      _notesController.clear();
      _startPoint = null;
      _endPoint = null;
      _startAddress = null;
      _endAddress = null;
      _selectedPickupTime = DateTime.now().add(const Duration(minutes: 30));
      _selectedDropTime = null;
    });
    _loadClientInfo();
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF212121),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null) return 'N/A';
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateTimeStr;
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF1A237E),
        title: const Text(
          'Request New Trip',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              'Your Information',
              'Please provide your contact details',
              Icons.account_circle,
              Colors.blue,
            ),
            const SizedBox(height: 16),
            _buildClientDetailsCard(),
            const SizedBox(height: 28),
            _buildSectionHeader(
              'Trip Route',
              'Select your pickup and drop locations',
              Icons.map,
              Colors.green,
            ),
            const SizedBox(height: 16),
            _buildRouteSelectionButton(),
            const SizedBox(height: 28),
            _buildSectionHeader(
              'Schedule',
              'When do you need the trip?',
              Icons.schedule,
              Colors.orange,
            ),
            const SizedBox(height: 16),
            _buildTimeSelectionCard(),
            const SizedBox(height: 28),
            _buildSectionHeader(
              'Additional Notes',
              'Any special requirements? (Optional)',
              Icons.notes,
              Colors.purple,
            ),
            const SizedBox(height: 16),
            _buildNotesField(),
            if (_startPoint != null && _endPoint != null) ...[
              const SizedBox(height: 28),
              _buildRouteInfoCard(),
            ],
            const SizedBox(height: 32),
            _buildSubmitButton(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle, IconData icon, MaterialColor color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color.shade700, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF212121),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClientDetailsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildTextField(
              controller: _clientNameController,
              label: 'Full Name',
              hint: 'Enter your full name',
              icon: Icons.person,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 18),
            _buildTextField(
              controller: _clientEmailController,
              label: 'Email Address',
              hint: 'Enter your email',
              icon: Icons.email,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 18),
            _buildTextField(
              controller: _clientPhoneController,
              label: 'Phone Number',
              hint: 'Enter your phone number',
              icon: Icons.phone,
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF424242),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: Icon(icon, color: const Color(0xFF1A237E), size: 22),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildRouteSelectionButton() {
    final bool hasRoute = _startPoint != null && _endPoint != null;
    
    return InkWell(
      onTap: _openRouteSelection,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasRoute ? Colors.green.shade300 : Colors.grey.shade200,
            width: hasRoute ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: hasRoute ? Colors.green.shade100 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      hasRoute ? Icons.check_circle : Icons.map,
                      color: hasRoute ? Colors.green.shade700 : Colors.grey.shade600,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasRoute ? 'Route Selected' : 'Select Route on Map',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: hasRoute ? Colors.green.shade900 : const Color(0xFF212121),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasRoute ? 'Tap to view or change route' : 'Search or pin locations on map',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey.shade400,
                    size: 28,
                  ),
                ],
              ),
              if (hasRoute) ...[
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 16),
                _buildLocationRow(
                  'Pickup Location',
                  Icons.trip_origin,
                  Colors.green,
                  _startAddress ?? 'Location selected',
                  _startPoint!,
                ),
                const SizedBox(height: 14),
                _buildLocationRow(
                  'Drop Location',
                  Icons.location_on,
                  Colors.red,
                  _endAddress ?? 'Location selected',
                  _endPoint!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationRow(
    String label,
    IconData icon,
    Color color,
    String address,
    LatLng point,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  address,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF212121),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSelectionCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildTimeRow(
              'Pickup Time',
              Icons.schedule,
              Colors.blue,
              _selectedPickupTime,
              _selectPickupTime,
              true,
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            _buildTimeRow(
              'Drop Time (Optional)',
              Icons.schedule_outlined,
              Colors.orange,
              _selectedDropTime,
              _selectDropTime,
              false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeRow(
    String label,
    IconData icon,
    MaterialColor color,
    DateTime? selectedTime,
    VoidCallback onSelect,
    bool isRequired,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color.shade700, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF424242),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                selectedTime != null
                    ? '${selectedTime.day}/${selectedTime.month}/${selectedTime.year} at ${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}'
                    : isRequired
                        ? 'Not selected'
                        : 'Will be calculated',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: onSelect,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            selectedTime != null ? 'Change' : 'Select',
            style: TextStyle(
              color: color.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotesField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: TextField(
          controller: _notesController,
          maxLines: 4,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: 'E.g., extra luggage, wheelchair accessible, pet-friendly...',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2),
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ),
    );
  }

  Widget _buildRouteInfoCard() {
    final distance = _calculateRouteDistance();
    final estimatedTime = (distance / 40 * 60).round();
    
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.blue.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route, color: Colors.blue.shade700, size: 22),
              const SizedBox(width: 10),
              Text(
                'Trip Summary',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  Icons.straighten,
                  'Distance',
                  '${distance.toStringAsFixed(1)} km',
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildSummaryItem(
                  Icons.access_time,
                  'Est. Time',
                  '$estimatedTime min',
                  Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    IconData icon,
    String label,
    String value,
    MaterialColor color,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, color: color.shade700, size: 26),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color.shade900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    final bool canSubmit = _clientNameController.text.trim().isNotEmpty &&
                            _clientEmailController.text.trim().isNotEmpty &&
                            _clientPhoneController.text.trim().isNotEmpty &&
                            _startPoint != null &&
                            _endPoint != null;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: (canSubmit && !_isSubmitting) ? _submitTripRequest : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          disabledForegroundColor: Colors.grey.shade500,
          elevation: canSubmit ? 2 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send, size: 22),
                  SizedBox(width: 12),
                  Text(
                    'Submit Trip Request',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}