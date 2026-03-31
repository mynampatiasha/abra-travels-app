import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/feedback_service.dart';

class MyFeedbackScreen extends StatefulWidget {
  const MyFeedbackScreen({Key? key}) : super(key: key);

  @override
  State<MyFeedbackScreen> createState() => _MyFeedbackScreenState();
}

class _MyFeedbackScreenState extends State<MyFeedbackScreen> {
  List<dynamic> _feedbackList = [];
  bool _isLoading = true;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _loadFeedback();
  }

  Future<void> _loadFeedback() async {
    setState(() => _isLoading = true);

    try {
      final result = await FeedbackService.getMyFeedback();
      setState(() {
        _feedbackList = result['feedback'] ?? [];
        _total = result['total'] ?? 0;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load feedback: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Feedback'),
        backgroundColor: Colors.blue,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _feedbackList.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadFeedback,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _feedbackList.length,
                    itemBuilder: (context, index) {
                      final feedback = _feedbackList[index];
                      return _buildFeedbackCard(feedback);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.feedback_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No feedback yet',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your trip ratings will appear here',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackCard(Map<String, dynamic> feedback) {
    final rating = feedback['rating'] ?? 0;
    final submittedAt = feedback['submittedAt'] != null
        ? DateTime.parse(feedback['submittedAt'])
        : DateTime.now();
    final quickTags = List<String>.from(feedback['quickTags'] ?? []);
    final comment = feedback['comment'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date and rating
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('MMM dd, yyyy • hh:mm a').format(submittedAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                Row(
                  children: List.generate(5, (index) {
                    return Icon(
                      index < rating ? Icons.star : Icons.star_border,
                      size: 16,
                      color: index < rating ? Colors.amber : Colors.grey[400],
                    );
                  }),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Trip type badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                feedback['tripType'] ?? 'Trip',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            // Quick tags
            if (quickTags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: quickTags.map((tag) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _formatTag(tag),
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                }).toList(),
              ),
            ],

            // Comment
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                comment,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[800],
                ),
              ),
            ],

            // Status
            if (feedback['status'] == 'escalated') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.flag, size: 14, color: Colors.orange[700]),
                  const SizedBox(width: 4),
                  Text(
                    'Under review',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTag(String tag) {
    return tag.split('_').map((word) {
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }
}
