// File: lib/features/driver/screens/driver_trip_response.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:intl/intl.dart';

class DriverTripResponseScreen extends StatefulWidget {
  final String tripId;
  final String tripNumber;
  final Map<String, dynamic> tripData;

  const DriverTripResponseScreen({
    Key? key,
    required this.tripId,
    required this.tripNumber,
    required this.tripData,
  }) : super(key: key);

  @override
  State<DriverTripResponseScreen> createState() =>
      _DriverTripResponseScreenState();
}

class _DriverTripResponseScreenState extends State<DriverTripResponseScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _notesController = TextEditingController();
  bool _isSubmitting = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(
        parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
        parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _animController.dispose();
    super.dispose();
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return 'N/A';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return DateFormat('MMM dd, yyyy • hh:mm a').format(dt);
    } catch (_) {
      return isoString;
    }
  }

  Future<void> _submitResponse(String response) async {
    // Show confirmation dialog first
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(
            response == 'accept' ? Icons.check_circle : Icons.cancel,
            color: response == 'accept' ? Colors.green : Colors.red,
            size: 26,
          ),
          const SizedBox(width: 10),
          Text(
            response == 'accept' ? 'Accept Trip?' : 'Decline Trip?',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              response == 'accept'
                  ? 'You are about to accept trip ${widget.tripNumber}. The admin will be notified and will confirm with the client.'
                  : 'You are about to decline trip ${widget.tripNumber}. The admin will be notified to reassign.',
              style: TextStyle(
                  fontSize: 14, color: Colors.grey.shade800),
            ),
            if (_notesController.text.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.note, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _notesController.text.trim(),
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  response == 'accept' ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
                response == 'accept' ? 'Yes, Accept' : 'Yes, Decline'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      if (token == null) throw Exception('Not authenticated');

      final apiResponse = await http.post(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/client-trips/${widget.tripId}/driver-response'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'response': response,
          'notes': _notesController.text.trim(),
        }),
      );

      final responseData = json.decode(apiResponse.body);

      if (apiResponse.statusCode == 200 &&
          responseData['success'] == true) {
        if (mounted) {
          _showSuccessDialog(response);
        }
      } else {
        throw Exception(
            responseData['message'] ?? 'Failed to submit response');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text('Error: ${e.toString()}')),
          ]),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _showSuccessDialog(String response) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: response == 'accept'
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                response == 'accept'
                    ? Icons.check_circle
                    : Icons.info,
                size: 56,
                color: response == 'accept'
                    ? Colors.green
                    : Colors.orange,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              response == 'accept'
                  ? 'Trip Accepted!'
                  : 'Trip Declined',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              response == 'accept'
                  ? 'Admin has been notified. They will confirm the trip and notify the client.'
                  : 'Admin has been notified. They will assign a different driver.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: Colors.grey.shade700),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close success dialog
              Navigator.of(context).pop(true); // Return to notifications
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: response == 'accept'
                  ? Colors.green
                  : Colors.orange,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Done', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.tripData;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A237E),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Trip Assignment',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18)),
            Text(widget.tripNumber,
                style: const TextStyle(
                    fontSize: 13, color: Colors.white70)),
          ],
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.blue.shade700,
                        Colors.blue.shade900
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.directions_car,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('New Client Trip Assigned',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 3),
                            Text(
                                'Please review and respond to this assignment.',
                                style: TextStyle(
                                    color:
                                        Colors.white.withOpacity(0.85),
                                    fontSize: 12)),
                          ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),

                // Trip Details Card
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('📋 Trip Details'),
                      const SizedBox(height: 12),
                      _tripDetailRow(Icons.confirmation_number,
                          'Trip Number', widget.tripNumber,
                          highlight: true),
                      _tripDetailRow(Icons.straighten, 'Distance',
                          '${data['distance']?.toString() ?? 'N/A'} km'),
                      _tripDetailRow(
                          Icons.timer,
                          'Est. Duration',
                          '${data['estimatedDuration']?.toString() ?? 'N/A'} minutes'),
                      _tripDetailRow(Icons.access_time, 'Pickup Time',
                          _formatTime(data['pickupTime']?.toString())),
                      _tripDetailRow(Icons.directions_car, 'Vehicle',
                          data['vehicleNumber']?.toString() ?? 'N/A'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Client Info
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('👤 Client Information'),
                      const SizedBox(height: 12),
                      _tripDetailRow(Icons.person, 'Client Name',
                          data['clientName']?.toString() ?? 'N/A'),
                      _tripDetailRow(Icons.phone, 'Client Phone',
                          data['clientPhone']?.toString() ?? 'N/A'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Locations
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('📍 Locations'),
                      const SizedBox(height: 12),
                      // Pickup
                      _locationTile(
                        icon: Icons.location_on,
                        color: Colors.green,
                        label: 'Pickup Location',
                        address: data['pickupAddress']?.toString() ?? 'N/A',
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        const SizedBox(width: 18),
                        Container(
                            width: 2,
                            height: 20,
                            color: Colors.grey.shade300),
                      ]),
                      const SizedBox(height: 4),
                      // Drop
                      _locationTile(
                        icon: Icons.flag,
                        color: Colors.red,
                        label: 'Drop Location',
                        address: data['dropAddress']?.toString() ?? 'N/A',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Notes field
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('📝 Notes (Optional)'),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _notesController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: _isSubmitting
                              ? ''
                              : 'Add a note (e.g. reason for decline, ETA comment...)',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.all(12),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Action Buttons
                if (!_isSubmitting) ...[
                  // ACCEPT
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _submitResponse('accept'),
                      icon: const Icon(Icons.check_circle, size: 22),
                      label: const Text('Accept Trip',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // DECLINE
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _submitResponse('decline'),
                      icon: Icon(Icons.cancel, size: 22, color: Colors.red.shade700),
                      label: Text('Decline Trip',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: Colors.red.shade400, width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ] else ...[
                  Center(
                    child: Column(children: [
                      const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF1A237E))),
                      const SizedBox(height: 12),
                      Text('Submitting your response...',
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade600)),
                    ]),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A237E)));
  }

  Widget _tripDetailRow(IconData icon, String label, String value,
      {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: highlight ? Colors.blue.shade50 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon,
              size: 16,
              color: highlight ? Colors.blue.shade700 : Colors.grey.shade700),
        ),
        const SizedBox(width: 10),
        SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600))),
        Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        highlight ? FontWeight.bold : FontWeight.w500,
                    color: highlight
                        ? Colors.blue.shade900
                        : Colors.grey.shade900))),
      ]),
    );
  }

  Widget _locationTile({
    required IconData icon,
    required MaterialColor color,
    required String label,
    required String address,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.shade200),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color.shade700, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: color.shade900)),
                const SizedBox(height: 3),
                Text(address,
                    style: TextStyle(
                        fontSize: 13,
                        color: color.shade800,
                        height: 1.4)),
              ]),
        ),
      ]),
    );
  }
}