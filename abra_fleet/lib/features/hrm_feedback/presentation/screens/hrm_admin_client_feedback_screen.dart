// lib/features/hrm_feedback/presentation/screens/hrm_admin_client_feedback_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/models/hrm_feedback_model.dart';
import '../../../../core/services/hrm_feedback_service.dart';

class HrmAdminClientFeedbackScreen extends StatefulWidget {
  const HrmAdminClientFeedbackScreen({super.key});

  @override
  State<HrmAdminClientFeedbackScreen> createState() => _HrmAdminClientFeedbackScreenState();
}

class _HrmAdminClientFeedbackScreenState extends State<HrmAdminClientFeedbackScreen> {
  final _feedbackService = HRMFeedbackService();
  
  // State management
  bool _isLoading = false;
  List<HrmFeedbackModel> _feedbackList = [];
  String _viewMode = 'grid'; // 'grid' or 'list'
  String _filterType = 'all';
  String _filterStatus = 'all';
  
  // Modal state
  HrmFeedbackModel? _selectedFeedback;
  final _adminReplyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFeedback();
  }

  @override
  void dispose() {
    _adminReplyController.dispose();
    super.dispose();
  }

  Future<void> _loadFeedback() async {
    setState(() => _isLoading = true);
    
    // Fetch ONLY client/employee feedback for admin HRM view
    final result = await _feedbackService.getAllFeedbackDetailed(
      source: 'employee',
      type: _filterType != 'all' ? _filterType : null,
      status: _filterStatus != 'all' ? _filterStatus : null,
      page: 1,
      limit: 100,
    );
    
    setState(() {
      if (result['success'] == true) {
        _feedbackList = result['feedback'] ?? [];
      } else {
        _feedbackList = [];
      }
      _isLoading = false;
    });
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _getStars(int rating) {
    return '★' * rating + '☆' * (5 - rating);
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'appreciation':
        return const Color(0xFF10b981);
      case 'complaint':
        return const Color(0xFFef4444);
      case 'suggestion':
        return const Color(0xFF3b82f6);
      default:
        return const Color(0xFF64748b);
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM d, y - h:mm a').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFf8fafc),
      appBar: AppBar(
        title: const Text(
          'Client Feedback Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF9333EA),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFeedback,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadFeedback,
        child: Column(
          children: [
            // Header Stats & Filters
            _buildHeaderSection(),
            
            // Feedback List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _feedbackList.isEmpty
                      ? _buildEmptyState()
                      : _viewMode == 'grid'
                          ? _buildGridView()
                          : _buildListView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Stats Row
          Row(
            children: [
              _buildStatCard('Total', _feedbackList.length, const Color(0xFF9333EA)),
              const SizedBox(width: 12),
              _buildStatCard('Pending', _feedbackList.where((f) => f.status == 'pending').length, Colors.orange),
              const SizedBox(width: 12),
              _buildStatCard('Responded', _feedbackList.where((f) => f.status == 'responded').length, Colors.green),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Filters Row
          Row(
            children: [
              // Type Filter
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _filterType,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Types')),
                    DropdownMenuItem(value: 'general', child: Text('General')),
                    DropdownMenuItem(value: 'appreciation', child: Text('Appreciation')),
                    DropdownMenuItem(value: 'complaint', child: Text('Complaint')),
                    DropdownMenuItem(value: 'suggestion', child: Text('Suggestion')),
                  ],
                  onChanged: (value) {
                    setState(() => _filterType = value!);
                    _loadFeedback();
                  },
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Status Filter
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _filterStatus,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Status')),
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'responded', child: Text('Responded')),
                  ],
                  onChanged: (value) {
                    setState(() => _filterStatus = value!);
                    _loadFeedback();
                  },
                ),
              ),
              
              const SizedBox(width: 12),
              
              // View Toggle
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.grid_view,
                      color: _viewMode == 'grid' ? const Color(0xFF9333EA) : Colors.grey,
                    ),
                    onPressed: () => setState(() => _viewMode = 'grid'),
                    tooltip: 'Grid View',
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.list,
                      color: _viewMode == 'list' ? const Color(0xFF9333EA) : Colors.grey,
                    ),
                    onPressed: () => setState(() => _viewMode = 'list'),
                    tooltip: 'List View',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          const Text(
            'No client feedback found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'No clients have submitted feedback yet',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.8,
        ),
        itemCount: _feedbackList.length,
        itemBuilder: (context, index) {
          final feedback = _feedbackList[index];
          return _buildFeedbackCard(feedback);
        },
      ),
    );
  }

  Widget _buildListView() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _feedbackList.length,
      itemBuilder: (context, index) {
        final feedback = _feedbackList[index];
        return _buildFeedbackListTile(feedback);
      },
    );
  }

  Widget _buildFeedbackCard(HrmFeedbackModel feedback) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showFeedbackDetailModal(feedback),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getTypeColor(feedback.feedbackType),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      feedback.feedbackType.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    _getStars(feedback.rating),
                    style: const TextStyle(fontSize: 12, color: Colors.amber),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              // Client Name
              Text(
                feedback.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 4),
              
              // Subject
              Text(
                feedback.subject,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9333EA),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 4),
              
              // Message Preview
              Expanded(
                child: Text(
                  feedback.message,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('MMM dd').format(feedback.dateSubmitted),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: feedback.hasAdminResponse ? Colors.green : Colors.orange,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      feedback.hasAdminResponse ? 'REPLIED' : 'PENDING',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeedbackListTile(HrmFeedbackModel feedback) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getTypeColor(feedback.feedbackType).withOpacity(0.1),
          child: Icon(
            Icons.business,
            color: _getTypeColor(feedback.feedbackType),
          ),
        ),
        title: Text(
          feedback.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              feedback.subject,
              style: const TextStyle(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              feedback.message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(_getStars(feedback.rating)),
                const SizedBox(width: 8),
                Text('• ${_formatDate(feedback.dateSubmitted)}'),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: feedback.hasAdminResponse ? Colors.green : Colors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                feedback.hasAdminResponse ? 'REPLIED' : 'PENDING',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        onTap: () => _showFeedbackDetailModal(feedback),
      ),
    );
  }

  void _showFeedbackDetailModal(HrmFeedbackModel feedback) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Icon(Icons.business, color: Color(0xFF9333EA)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Client Feedback Details',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              
              const Divider(height: 1),
              
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Client Info
                    _buildInfoSection('Client Information', [
                      _buildInfoRow('Name', feedback.name),
                      _buildInfoRow('Email', feedback.email),
                      _buildInfoRow('Type', feedback.feedbackType),
                      _buildInfoRow('Rating', _getStars(feedback.rating)),
                      _buildInfoRow('Date', _formatDate(feedback.dateSubmitted)),
                    ]),
                    
                    const SizedBox(height: 20),
                    
                    // Feedback Content
                    _buildInfoSection('Feedback Content', [
                      _buildInfoRow('Subject', feedback.subject),
                      _buildMessageRow('Message', feedback.message),
                    ]),
                    
                    // Admin Response (if exists)
                    if (feedback.hasAdminResponse) ...[
                      const SizedBox(height: 20),
                      _buildInfoSection('Admin Response', [
                        _buildInfoRow('Response Date', _formatDate(feedback.responseDate!)),
                        _buildMessageRow('Response', feedback.adminResponse!),
                      ]),
                    ],
                  ],
                ),
              ),
              
              // Action Button
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey[300]!)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showAdminReplyModal(feedback);
                    },
                    icon: Icon(feedback.hasAdminResponse ? Icons.edit : Icons.reply),
                    label: Text(feedback.hasAdminResponse ? 'Update Response' : 'Send Response'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9333EA),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF9333EA),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageRow(String label, String message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Text(
            message,
            style: const TextStyle(height: 1.5),
          ),
        ),
      ],
    );
  }

  void _showAdminReplyModal(HrmFeedbackModel feedback) {
    _adminReplyController.text = feedback.adminResponse ?? '';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.admin_panel_settings, color: Color(0xFF9333EA)),
            const SizedBox(width: 12),
            Text(feedback.hasAdminResponse ? 'Update Response' : 'Send Response'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Client: ${feedback.name}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Subject: ${feedback.subject}'),
              const SizedBox(height: 16),
              TextField(
                controller: _adminReplyController,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'Your Response',
                  hintText: 'Type your response to the client...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_adminReplyController.text.trim().isEmpty) {
                _showSnackBar('Please enter a response', Colors.red);
                return;
              }
              
              Navigator.pop(context);
              
              final result = await _feedbackService.adminReplyToFeedback(
                feedbackId: feedback.id,
                feedbackSource: 'employee',
                response: _adminReplyController.text.trim(),
              );
              
              if (result['success']) {
                _showSnackBar('Response sent successfully!', Colors.green);
                _loadFeedback();
              } else {
                _showSnackBar(result['message'] ?? 'Failed to send response', Colors.red);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9333EA),
              foregroundColor: Colors.white,
            ),
            child: const Text('Send Response'),
          ),
        ],
      ),
    );
  }
}