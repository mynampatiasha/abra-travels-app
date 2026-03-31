import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:abra_fleet/core/services/individual_trip_service.dart';

class DriverTripResponseScreen extends StatefulWidget {
  final String tripId;
  final String tripNumber;
  final Map<String, dynamic> tripData;

  const DriverTripResponseScreen({
    super.key,
    required this.tripId,
    required this.tripNumber,
    required this.tripData,
  });

  @override
  State<DriverTripResponseScreen> createState() => _DriverTripResponseScreenState();
}

class _DriverTripResponseScreenState extends State<DriverTripResponseScreen> {
  final IndividualTripService _tripService = IndividualTripService();
  final TextEditingController _notesController = TextEditingController();
  
  String? _selectedResponse; // 'accept' or 'decline'
  bool _isLoading = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submitResponse() async {
    if (_selectedResponse == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select Accept or Decline'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      print('📱 Submitting driver response: $_selectedResponse');
      print('📝 Notes: ${_notesController.text}');
      
      // Call the backend API
      await _tripService.respondToTrip(
        tripId: widget.tripId,
        response: _selectedResponse!,
        notes: _notesController.text.trim(),
      );

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedResponse == 'accept'
                ? '✅ Trip accepted! Admin has been notified.'
                : '❌ Trip declined. Admin has been notified.',
          ),
          backgroundColor: _selectedResponse == 'accept' ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );

      // Navigate back to notifications or individual trips
      Navigator.of(context).pop();
      
      // If accepted, navigate to individual trips screen
      if (_selectedResponse == 'accept') {
        Navigator.of(context).pushReplacementNamed('/driver/individual-trips');
      }

    } catch (e) {
      if (!mounted) return;
      
      setState(() => _isLoading = false);
      
      print('❌ Error submitting response: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit response: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  String _formatPickupTime(String? pickupTime) {
    if (pickupTime == null) return 'N/A';
    try {
      final dateTime = DateTime.parse(pickupTime);
      return DateFormat('M/d/yyyy h:mm a').format(dateTime);
    } catch (e) {
      return pickupTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Response', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0D47A1),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Submitting response...'),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Trip Details Header (Blue Card)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.local_shipping, color: Colors.white, size: 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'New Trip Assignment',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.tripNumber,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _buildWhiteInfoRow(
                          Icons.directions_car,
                          'Vehicle:',
                          widget.tripData['vehicleNumber']?.toString() ?? 'N/A',
                        ),
                        const SizedBox(height: 12),
                        _buildWhiteInfoRow(
                          Icons.straighten,
                          'Distance:',
                          '${widget.tripData['distance']?.toString() ?? 'N/A'} km',
                        ),
                        const SizedBox(height: 12),
                        _buildWhiteInfoRow(
                          Icons.access_time,
                          'Pickup:',
                          _formatPickupTime(widget.tripData['pickupTime']?.toString()),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Your Response Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your Response:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Accept / Decline Buttons
                        Row(
                          children: [
                            Expanded(
                              child: _buildResponseButton(
                                label: 'Accept Trip',
                                icon: Icons.check_circle,
                                isSelected: _selectedResponse == 'accept',
                                onTap: () {
                                  setState(() {
                                    _selectedResponse = 'accept';
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildResponseButton(
                                label: 'Decline Trip',
                                icon: Icons.cancel,
                                isSelected: _selectedResponse == 'decline',
                                onTap: () {
                                  setState(() {
                                    _selectedResponse = 'decline';
                                  });
                                },
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Additional Notes Section
                        const Text(
                          'Additional Notes (Optional):',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _notesController,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'Add any notes or comments (optional)...',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 2),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submitResponse,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[400],
              disabledBackgroundColor: Colors.grey[300],
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: Text(
              'Select Response',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _selectedResponse != null ? Colors.white : Colors.grey[600],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWhiteInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResponseButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey[300] : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.grey[400]! : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 40,
              color: isSelected ? Colors.grey[700] : Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.grey[800] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}