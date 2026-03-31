import 'package:flutter/material.dart';
import '../core/services/driver_trip_service.dart';

class CustomerFeedbackDialog extends StatefulWidget {
  final String tripId;
  final String driverId;
  final String driverName;

  const CustomerFeedbackDialog({
    Key? key,
    required this.tripId,
    required this.driverId,
    required this.driverName,
  }) : super(key: key);

  @override
  State<CustomerFeedbackDialog> createState() => _CustomerFeedbackDialogState();
}

class _CustomerFeedbackDialogState extends State<CustomerFeedbackDialog> {
  int _rating = 0;
  final TextEditingController _feedbackController = TextEditingController();
  String _rideAgain = 'not_specified';
  bool _isSubmitting = false;
  
  final DriverTripService _tripService = DriverTripService();

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a rating'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _tripService.submitFeedback(
        tripId: widget.tripId,
        driverId: widget.driverId,
        rating: _rating,
        feedback: _feedbackController.text.trim(),
        rideAgain: _rideAgain,
      );

      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Thank you for your feedback!'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit feedback: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.star_rounded, size: 64, color: Colors.amber),
                    const SizedBox(height: 12),
                    const Text(
                      'Rate Your Ride',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'How was your experience with ${widget.driverName}?',
                      style: const TextStyle(fontSize: 14, color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              // Body
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Rating Stars
                    const Text(
                      'Your Rating',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) {
                          return IconButton(
                            iconSize: 48,
                            icon: Icon(
                              index < _rating ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                            ),
                            onPressed: () {
                              setState(() => _rating = index + 1);
                            },
                          );
                        }),
                      ),
                    ),
                    if (_rating > 0)
                      Center(
                        child: Text(
                          _getRatingText(_rating),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _getRatingColor(_rating),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),

                    // Feedback Text
                    const Text(
                      'Comments (Optional)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _feedbackController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Share your experience...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Ride Again?
                    const Text(
                      'Would you ride with this driver again?',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildRideAgainButton('yes', '👍 Yes', Colors.green),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildRideAgainButton('no', '👎 No', Colors.red),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitFeedback,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D47A1),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'SUBMIT FEEDBACK',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Center(
                        child: Text(
                          'Skip for now',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRideAgainButton(String value, String label, Color color) {
    final isSelected = _rideAgain == value;
    return OutlinedButton(
      onPressed: () => setState(() => _rideAgain = value),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        backgroundColor: isSelected ? color.withOpacity(0.1) : null,
        side: BorderSide(
          color: isSelected ? color : Colors.grey[300]!,
          width: isSelected ? 2 : 1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? color : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 5: return 'Excellent!';
      case 4: return 'Good!';
      case 3: return 'Average';
      case 2: return 'Poor';
      case 1: return 'Very Poor';
      default: return '';
    }
  }

  Color _getRatingColor(int rating) {
    if (rating >= 4) return Colors.green;
    if (rating == 3) return Colors.orange;
    return Colors.red;
  }
}