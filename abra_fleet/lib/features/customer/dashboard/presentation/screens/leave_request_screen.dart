// lib/features/customer/dashboard/presentation/screens/leave_request_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:abra_fleet/features/customer/dashboard/data/repositories/roster_repository.dart';
import 'package:abra_fleet/core/services/backend_connection_manager.dart';
import 'package:abra_fleet/core/services/geocoding_service.dart';

class LeaveRequestScreen extends StatefulWidget {
  const LeaveRequestScreen({super.key});

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> {
  late final RosterRepository _rosterRepository;
  final _geocodingService = GeocodingService();
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSubmitting = false;
  List<Map<String, dynamic>> _affectedTrips = [];
  final Map<String, String> _addressCache = {};

  @override
  void initState() {
    super.initState();
    _rosterRepository = RosterRepository(
      apiService: BackendConnectionManager().apiService,
    );
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select leave start date',
    );
    
    if (picked != null) {
      setState(() {
        _startDate = picked;
        // Reset end date if it's before start date
        if (_endDate != null && _endDate!.isBefore(_startDate!)) {
          _endDate = null;
        }
      });
    }
  }

  Future<void> _selectEndDate() async {
    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select start date first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate!.add(const Duration(days: 1)),
      firstDate: _startDate!,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select leave end date',
    );
    
    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
      await _checkAffectedTrips();
    }
  }

  Future<void> _checkAffectedTrips() async {
    if (_startDate == null || _endDate == null) return;

    try {
      // Get all rosters to check which ones are affected
      final rosters = await _rosterRepository.getMyRosters();
      
      final affected = rosters.where((roster) {
        final rosterStartDate = DateTime.parse(roster['dateRange']['from']);
        final rosterEndDate = DateTime.parse(roster['dateRange']['to']);
        
        // Check if roster overlaps with leave period
        return (rosterStartDate.isBefore(_endDate!) || rosterStartDate.isAtSameMomentAs(_endDate!)) &&
               (rosterEndDate.isAfter(_startDate!) || rosterEndDate.isAtSameMomentAs(_startDate!)) &&
               ['pending_assignment', 'assigned', 'scheduled'].contains(roster['status']);
      }).toList();

      setState(() {
        _affectedTrips = affected;
      });
    } catch (e) {
      debugPrint('Error checking affected trips: $e');
    }
  }

  Future<void> _submitLeaveRequest() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select both start and end dates'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final result = await _rosterRepository.submitLeaveRequest(
        startDate: _startDate!,
        endDate: _endDate!,
        reason: _reasonController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Leave request submitted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit leave request: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }

  Future<String> _getAddress(String location) async {
    if (_addressCache.containsKey(location)) {
      return _addressCache[location]!;
    }
    
    final address = await _geocodingService.getAddressFromLocation(location);
    setState(() {
      _addressCache[location] = address;
    });
    return address;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Leave'),
        backgroundColor: const Color(0xFF0D47A1), // App's specified primary color
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline, color: Color(0xFF0D47A1)), // App's specified primary color
                          const SizedBox(width: 8),
                          const Text(
                            'Leave Request Information',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Submit a leave request to inform your organization that you will not need transportation during specific dates.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 20),

              // Date Selection
              const Text(
                'Leave Period',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Start Date
              Card(
                child: ListTile(
                  leading: const Icon(Icons.calendar_today, color: Colors.green),
                  title: const Text('Start Date'),
                  subtitle: Text(_startDate != null 
                    ? _formatDate(_startDate!) 
                    : 'Select start date'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: _selectStartDate,
                ),
              ),

              const SizedBox(height: 8),

              // End Date
              Card(
                child: ListTile(
                  leading: const Icon(Icons.calendar_today, color: Colors.red),
                  title: const Text('End Date'),
                  subtitle: Text(_endDate != null 
                    ? _formatDate(_endDate!) 
                    : 'Select end date'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: _selectEndDate,
                ),
              ),

              const SizedBox(height: 20),

              // Reason Field
              const Text(
                'Reason (Optional)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'e.g., Going on vacation, Medical leave, Personal work...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.edit_note),
                ),
              ),

              const SizedBox(height: 20),

              // Affected Trips Section
              if (_affectedTrips.isNotEmpty) ...[
                const Text(
                  'Affected Trips',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                
                Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber, color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            Text(
                              '${_affectedTrips.length} trip(s) will be affected',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...(_affectedTrips.take(3).map((trip) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.trip_origin, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FutureBuilder<String>(
                                  future: _getAddress(trip['officeLocation'] ?? ''),
                                  builder: (context, snapshot) {
                                    final address = snapshot.data ?? trip['officeLocation'] ?? 'Unknown';
                                    return Text(
                                      '${trip['rosterType']?.toString().toUpperCase()} - $address',
                                      style: const TextStyle(fontSize: 14),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ))),
                        if (_affectedTrips.length > 3)
                          Text(
                            'and ${_affectedTrips.length - 3} more...',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitLeaveRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1), // App's specified primary color
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isSubmitting
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Submitting...'),
                        ],
                      )
                    : const Text(
                        'Submit Leave Request',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                ),
              ),

              const SizedBox(height: 20),

              // Info Card
              Card(
                color: const Color(0xFF0D47A1).withOpacity(0.1), // App's specified primary color with opacity
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.lightbulb_outline, color: Color(0xFF0D47A1)), // App's specified primary color
                          const SizedBox(width: 8),
                          const Text(
                            'What happens next?',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '• Your organization will be notified about your leave request\n'
                        '• All affected trips will be marked as pending approval\n'
                        '• You will receive a notification once your request is reviewed\n'
                        '• You can track the status in "My Leave Requests"',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}