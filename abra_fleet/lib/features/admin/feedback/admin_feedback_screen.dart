import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/services/feedback_service.dart';

class AdminFeedbackScreen extends StatefulWidget {
  final String? organizationId;

  const AdminFeedbackScreen({Key? key, this.organizationId}) : super(key: key);

  @override
  State<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends State<AdminFeedbackScreen> {
  List<dynamic> _feedbackList = [];
  bool _isLoading = true;
  int _total = 0;
  int? _filterRating;
  String? _filterStatus;

  @override
  void initState() {
    super.initState();
    _loadFeedback();
  }

  Future<void> _loadFeedback() async {
    setState(() => _isLoading = true);

    try {
      final result = await FeedbackService.getAllFeedback(
        organizationId: widget.organizationId,
        rating: _filterRating,
        status: _filterStatus,
      );

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
        title: const Text('Customer Feedback'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatsBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _feedbackList.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadFeedback,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _feedbackList.length,
                          itemBuilder: (context, index) {
                            return _buildFeedbackCard(_feedbackList[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    final avgRating = _feedbackList.isEmpty
        ? 0.0
        : _feedbackList.fold<double>(
                0, (sum, item) => sum + (item['rating'] ?? 0)) /
            _feedbackList.length;

    final lowRatings =
        _feedbackList.where((f) => (f['rating'] ?? 0) <= 2).length;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blue[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            'Total',
            _total.toString(),
            Icons.feedback,
            Colors.blue,
          ),
          _buildStatItem(
            'Avg Rating',
            avgRating.toStringAsFixed(1),
            Icons.star,
            Colors.amber,
          ),
          _buildStatItem(
            'Low Ratings',
            lowRatings.toString(),
            Icons.warning,
            Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
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
    final status = feedback['status'] ?? 'submitted';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('MMM dd, yyyy • hh:mm a').format(submittedAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Trip ID: ${feedback['tripId']?.toString().substring(0, 8) ?? 'N/A'}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: List.generate(5, (index) {
                    return Icon(
                      index < rating ? Icons.star : Icons.star_border,
                      size: 18,
                      color: index < rating ? Colors.amber : Colors.grey[400],
                    );
                  }),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Status badge
            Row(
              children: [
                _buildStatusBadge(status),
                const SizedBox(width: 8),
                if (feedback['tripDelay'] != null && feedback['tripDelay'] > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Delayed ${feedback['tripDelay']}m',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange[700],
                      ),
                    ),
                  ),
              ],
            ),

            if (quickTags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: quickTags.map((tag) {
                  return Chip(
                    label: Text(
                      _formatTag(tag),
                      style: const TextStyle(fontSize: 11),
                    ),
                    backgroundColor: Colors.grey[200],
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                }).toList(),
              ),
            ],

            if (comment.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  comment,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;

    switch (status) {
      case 'escalated':
        color = Colors.red;
        label = 'Escalated';
        break;
      case 'reviewed':
        color = Colors.green;
        label = 'Reviewed';
        break;
      default:
        color = Colors.blue;
        label = 'New';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Feedback'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int?>(
              value: _filterRating,
              decoration: const InputDecoration(labelText: 'Rating'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All')),
                ...List.generate(5, (i) => i + 1).map((rating) {
                  return DropdownMenuItem(
                    value: rating,
                    child: Text('$rating Star${rating > 1 ? 's' : ''}'),
                  );
                }),
              ],
              onChanged: (value) => setState(() => _filterRating = value),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              value: _filterStatus,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: null, child: Text('All')),
                DropdownMenuItem(value: 'submitted', child: Text('New')),
                DropdownMenuItem(value: 'escalated', child: Text('Escalated')),
                DropdownMenuItem(value: 'reviewed', child: Text('Reviewed')),
              ],
              onChanged: (value) => setState(() => _filterStatus = value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _filterRating = null;
                _filterStatus = null;
              });
              Navigator.pop(context);
              _loadFeedback();
            },
            child: const Text('Clear'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _loadFeedback();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  String _formatTag(String tag) {
    return tag.split('_').map((word) {
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }
}
