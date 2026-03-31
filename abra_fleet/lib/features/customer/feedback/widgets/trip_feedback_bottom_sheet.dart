import 'package:flutter/material.dart';
import '../../../../core/services/feedback_service.dart';

class TripFeedbackBottomSheet extends StatefulWidget {
  final String tripId;
  final String? driverName;
  final String? vehicleNumber;
  final String feedbackType;

  const TripFeedbackBottomSheet({
    Key? key,
    required this.tripId,
    this.driverName,
    this.vehicleNumber,
    this.feedbackType = 'post_trip',
  }) : super(key: key);

  @override
  State<TripFeedbackBottomSheet> createState() => _TripFeedbackBottomSheetState();
}

class _TripFeedbackBottomSheetState extends State<TripFeedbackBottomSheet> {
  int _rating = 0;
  final List<String> _selectedTags = [];
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;

  final List<Map<String, dynamic>> _quickTags = [
    {'label': 'On Time', 'icon': Icons.access_time, 'value': 'on_time'},
    {'label': 'Clean Vehicle', 'icon': Icons.cleaning_services, 'value': 'clean_vehicle'},
    {'label': 'Safe Driving', 'icon': Icons.security, 'value': 'safe_driving'},
    {'label': 'Friendly Driver', 'icon': Icons.sentiment_satisfied, 'value': 'friendly_driver'},
    {'label': 'Late', 'icon': Icons.schedule, 'value': 'late'},
    {'label': 'Rash Driving', 'icon': Icons.warning, 'value': 'rash_driving'},
    {'label': 'AC Issue', 'icon': Icons.ac_unit, 'value': 'ac_issue'},
    {'label': 'Dirty Vehicle', 'icon': Icons.dirty_lens, 'value': 'dirty_vehicle'},
  ];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a rating')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await FeedbackService.submitFeedback(
        tripId: widget.tripId,
        rating: _rating,
        quickTags: _selectedTags,
        comment: _commentController.text,
        feedbackType: widget.feedbackType,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thank you for your feedback!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit feedback: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Text(
              widget.feedbackType == 'weekly_detailed'
                  ? 'Rate This Week\'s Service'
                  : 'How was your trip?',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            if (widget.driverName != null || widget.vehicleNumber != null) ...[
              const SizedBox(height: 8),
              Text(
                '${widget.driverName ?? ''} ${widget.vehicleNumber != null ? '• ${widget.vehicleNumber}' : ''}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 24),

            // Star Rating
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return GestureDetector(
                  onTap: () => setState(() => _rating = index + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      index < _rating ? Icons.star : Icons.star_border,
                      size: 40,
                      color: index < _rating ? Colors.amber : Colors.grey[400],
                    ),
                  ),
                );
              }),
            ),

            if (_rating > 0) ...[
              const SizedBox(height: 8),
              Text(
                _getRatingText(_rating),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 24),

            // Quick Tags
            Text(
              'Quick feedback (optional)',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickTags.map((tag) {
                final isSelected = _selectedTags.contains(tag['value']);
                return FilterChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tag['icon'] as IconData,
                        size: 16,
                        color: isSelected ? Colors.white : Colors.grey[700],
                      ),
                      const SizedBox(width: 4),
                      Text(tag['label'] as String),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedTags.add(tag['value'] as String);
                      } else {
                        _selectedTags.remove(tag['value']);
                      }
                    });
                  },
                  selectedColor: Colors.blue,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[700],
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Comment field
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add a comment (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),

            const SizedBox(height: 20),

            // Submit button
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitFeedback,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Submit Feedback',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),

            const SizedBox(height: 12),

            // Skip button
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Skip',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 5:
        return 'Excellent!';
      case 4:
        return 'Good';
      case 3:
        return 'Average';
      case 2:
        return 'Below Average';
      case 1:
        return 'Poor';
      default:
        return '';
    }
  }
}
