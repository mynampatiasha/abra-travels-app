// lib/features/hrm_feedback/presentation/screens/hrm_customer_feedback_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/models/hrm_feedback_model.dart';
import '../../../../core/services/hrm_feedback_service.dart';

class HrmCustomerFeedbackScreen extends StatefulWidget {
  final String? userName;
  final String? userEmail;

  const HrmCustomerFeedbackScreen({
    Key? key,
    this.userName,
    this.userEmail,
  }) : super(key: key);

  @override
  State<HrmCustomerFeedbackScreen> createState() => _HrmCustomerFeedbackScreenState();
}

class _HrmCustomerFeedbackScreenState extends State<HrmCustomerFeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _feedbackService = HRMFeedbackService();
  
  // Form fields
  final _nameController = TextEditingController();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  String _selectedType = 'general';
  int _selectedRating = 5;
  
  // State management
  bool _isSubmitting = false;
  bool _isLoading = false;
  List<HrmFeedbackModel> _feedbackList = [];
  String _viewMode = 'grid'; // 'grid' or 'table'
  
  // Modal state
  HrmFeedbackModel? _selectedFeedback;
  final _replyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.userName ?? '';
    _loadFeedback();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadFeedback() async {
    setState(() => _isLoading = true);
    
    // For admin HRM portal, fetch all customer feedback
    final result = await _feedbackService.getAllFeedback('customer');
    
    setState(() {
      _feedbackList = result;
      _isLoading = false;
    });
  }

  Future<void> _submitFeedback() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final result = await _feedbackService.submitCustomerFeedback(
      customerName: _nameController.text.trim(),
      feedbackType: _selectedType,
      subject: _subjectController.text.trim(),
      message: _messageController.text.trim(),
      rating: _selectedRating,
    );

    setState(() => _isSubmitting = false);

    if (result['success']) {
      _showSnackBar(result['message'], Colors.green);
      
      // Clear form
      _subjectController.clear();
      _messageController.clear();
      setState(() {
        _selectedType = 'general';
        _selectedRating = 5;
      });
      
      // Reload feedback
      _loadFeedback();
      
      // Scroll to top
      _scrollToTop();
    } else {
      _showSnackBar(result['message'], Colors.red);
    }
  }

  Future<void> _submitReply() async {
    if (_selectedFeedback == null || _replyController.text.trim().isEmpty) {
      _showSnackBar('Please enter a reply message', Colors.red);
      return;
    }

    final result = await _feedbackService.submitUserReply(
      source: 'customer',
      originalFeedbackId: _selectedFeedback!.id,
      userName: _nameController.text.trim(),
      originalSubject: _selectedFeedback!.subject,
      replyMessage: _replyController.text.trim(),
    );

    if (result['success']) {
      _showSnackBar(result['message'], Colors.green);
      Navigator.pop(context); // Close modal
      _replyController.clear();
      _loadFeedback();
    } else {
      _showSnackBar(result['message'], Colors.red);
    }
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
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
          'Feedback & Support',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF3b82f6),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadFeedback,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Feedback',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadFeedback,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              _buildHeaderCard(),
              const SizedBox(height: 20),
              
              // Submit Feedback Form
              _buildFeedbackForm(),
              const SizedBox(height: 20),
              
              // Feedback History
              _buildFeedbackHistory(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3b82f6), Color(0xFF2563eb)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3b82f6).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.people_outline,
            size: 48,
            color: Colors.white,
          ),
          const SizedBox(height: 12),
          const Text(
            'Customer Feedback Management',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'View and manage all feedback submitted by customers',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackForm() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFe2e8f0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Form Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFf8fafc),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(
                bottom: BorderSide(color: const Color(0xFFe2e8f0), width: 2),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.edit_note, color: Color(0xFF3b82f6), size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Submit Feedback',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0f172a),
                  ),
                ),
              ],
            ),
          ),
          
          // Form Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name Field
                  _buildTextField(
                    controller: _nameController,
                    label: 'Your Name',
                    icon: Icons.person,
                    required: true,
                  ),
                  const SizedBox(height: 16),
                  
                  // Feedback Type
                  _buildDropdownField(
                    label: 'Feedback Type',
                    icon: Icons.category,
                    value: _selectedType,
                    items: const [
                      {'value': 'general', 'label': 'General Feedback'},
                      {'value': 'appreciation', 'label': 'Appreciation'},
                      {'value': 'complaint', 'label': 'Complaint'},
                      {'value': 'suggestion', 'label': 'Suggestion'},
                    ],
                    onChanged: (value) => setState(() => _selectedType = value!),
                  ),
                  const SizedBox(height: 16),
                  
                  // Subject
                  _buildTextField(
                    controller: _subjectController,
                    label: 'Subject',
                    icon: Icons.title,
                    required: true,
                  ),
                  const SizedBox(height: 16),
                  
                  // Message
                  _buildTextField(
                    controller: _messageController,
                    label: 'Your Message',
                    icon: Icons.message,
                    required: true,
                    maxLines: 5,
                  ),
                  const SizedBox(height: 16),
                  
                  // Rating
                  _buildRatingSelector(),
                  const SizedBox(height: 24),
                  
                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitFeedback,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3b82f6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
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
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.send),
                                SizedBox(width: 8),
                                Text(
                                  'Submit Feedback',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool required = false,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0f172a),
              ),
            ),
            if (required)
              const Text(
                ' *',
                style: TextStyle(color: Colors.red),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: const Color(0xFF64748b)),
            hintText: 'Enter $label',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFe2e8f0), width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFe2e8f0), width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF3b82f6), width: 2),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          validator: required
              ? (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '$label is required';
                  }
                  return null;
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required IconData icon,
    required String value,
    required List<Map<String, String>> items,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0f172a),
              ),
            ),
            const Text(
              ' *',
              style: TextStyle(color: Colors.red),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: const Color(0xFF64748b)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFe2e8f0), width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFe2e8f0), width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF3b82f6), width: 2),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item['value'],
              child: Text(item['label']!),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildRatingSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Text(
              'Rating',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0f172a),
              ),
            ),
            Text(
              ' *',
              style: TextStyle(color: Colors.red),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(5, (index) {
            final rating = index + 1;
            final isSelected = _selectedRating == rating;
            
            return InkWell(
              onTap: () => setState(() => _selectedRating = rating),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF3b82f6).withOpacity(0.1)
                      : Colors.white,
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF3b82f6)
                        : const Color(0xFFe2e8f0),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      _getStars(rating),
                      style: const TextStyle(
                        fontSize: 18,
                        color: Color(0xFFfbbf24),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$rating Star${rating > 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? const Color(0xFF3b82f6)
                            : const Color(0xFF64748b),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildFeedbackHistory() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFe2e8f0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // History Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFf8fafc),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(
                bottom: BorderSide(color: const Color(0xFFe2e8f0), width: 2),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.history, color: Color(0xFF3b82f6), size: 24),
                const SizedBox(width: 12),
                const Text(
                  'All Customer Feedback',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0f172a),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3b82f6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_feedbackList.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                // View Toggle
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.grid_view,
                        color: _viewMode == 'grid'
                            ? const Color(0xFF3b82f6)
                            : const Color(0xFF64748b),
                      ),
                      onPressed: () => setState(() => _viewMode = 'grid'),
                      tooltip: 'Grid View',
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.list,
                        color: _viewMode == 'table'
                            ? const Color(0xFF3b82f6)
                            : const Color(0xFF64748b),
                      ),
                      onPressed: () => setState(() => _viewMode = 'table'),
                      tooltip: 'List View',
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // History Content
          _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _feedbackList.isEmpty
                  ? _buildEmptyState()
                  : _viewMode == 'grid'
                      ? _buildGridView()
                      : _buildListView(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(
            Icons.inbox,
            size: 64,
            color: const Color(0xFF64748b).withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No customer feedback yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0f172a),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No customers have submitted feedback yet',
            style: TextStyle(
              fontSize: 14,
              color: const Color(0xFF64748b),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.85,
        ),
        itemCount: _feedbackList.length,
        itemBuilder: (context, index) {
          final feedback = _feedbackList[index];
          return _buildFeedbackCard(feedback);
        },
      ),
    );
  }

  Widget _buildFeedbackCard(HrmFeedbackModel feedback) {
    return InkWell(
      onTap: () => _showFeedbackDetailModal(feedback),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFe2e8f0), width: 2),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Type Badge and Rating
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getTypeColor(feedback.feedbackType),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      feedback.feedbackType.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    _getStars(feedback.rating),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFFfbbf24),
                    ),
                  ),
                ],
              ),
            ),
            
            // Subject
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                feedback.subject,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0f172a),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Message Preview
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  feedback.message,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748b),
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            
            // Footer
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: const Color(0xFFe2e8f0)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 12,
                        color: Color(0xFF64748b),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(feedback.dateSubmitted),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF64748b),
                        ),
                      ),
                    ],
                  ),
                  if (feedback.hasAdminResponse)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10b981),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check, size: 10, color: Colors.white),
                          SizedBox(width: 2),
                          Text(
                            'Replied',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
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

  Widget _buildListView() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      itemCount: _feedbackList.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final feedback = _feedbackList[index];
        return ListTile(
          onTap: () => _showFeedbackDetailModal(feedback),
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _getTypeColor(feedback.feedbackType).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.chat_bubble,
              color: _getTypeColor(feedback.feedbackType),
              size: 24,
            ),
          ),
          title: Text(
            feedback.subject,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                feedback.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    _getStars(feedback.rating),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFfbbf24),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '• ${_formatDate(feedback.dateSubmitted)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748b),
                    ),
                  ),
                ],
              ),
            ],
          ),
          trailing: feedback.hasAdminResponse
              ? const Icon(Icons.check_circle, color: Color(0xFF10b981))
              : const Icon(Icons.pending, color: Color(0xFFf59e0b)),
        );
      },
    );
  }

  void _showFeedbackDetailModal(HrmFeedbackModel feedback) {
    setState(() => _selectedFeedback = feedback);
    
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
                  color: const Color(0xFFe2e8f0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Modal Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble, color: Color(0xFF3b82f6)),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Feedback Conversation',
                        style: TextStyle(
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
              
              // Modal Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // User's Message
                    _buildMessageBubble(
                      isUser: true,
                      name: 'You',
                      date: feedback.dateSubmitted,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getTypeColor(feedback.feedbackType),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              feedback.feedbackType.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            feedback.subject,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1e40af),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getStars(feedback.rating),
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFFfbbf24),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            feedback.message,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF0f172a),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Admin Response (if exists)
                    if (feedback.hasAdminResponse) ...[
                      const SizedBox(height: 16),
                      _buildMessageBubble(
                        isUser: false,
                        name: 'Admin Response',
                        date: feedback.responseDate!,
                        content: Text(
                          feedback.adminResponse!,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF0f172a),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              
              // Reply Button (if admin has responded)
              if (feedback.hasAdminResponse)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: const Color(0xFFe2e8f0)),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showReplyModal(feedback);
                      },
                      icon: const Icon(Icons.reply),
                      label: const Text('Reply to Customer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10b981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                )
              else
                // Admin Reply Button (if no response yet)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: const Color(0xFFe2e8f0)),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showAdminReplyModal(feedback);
                      },
                      icon: const Icon(Icons.admin_panel_settings),
                      label: const Text('Send Admin Response'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3b82f6),
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

  Widget _buildMessageBubble({
    required bool isUser,
    required String name,
    required DateTime date,
    required Widget content,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isUser
            ? const Color(0xFF3b82f6).withOpacity(0.05)
            : const Color(0xFF10b981).withOpacity(0.05),
        border: Border.all(
          color: isUser
              ? const Color(0xFF3b82f6).withOpacity(0.2)
              : const Color(0xFF10b981).withOpacity(0.2),
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isUser ? Icons.person : Icons.admin_panel_settings,
                size: 16,
                color: isUser ? const Color(0xFF3b82f6) : const Color(0xFF10b981),
              ),
              const SizedBox(width: 8),
              Text(
                name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isUser ? const Color(0xFF3b82f6) : const Color(0xFF10b981),
                ),
              ),
              const Spacer(),
              Text(
                _formatDate(date),
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748b),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          content,
        ],
      ),
    );
  }

  void _showAdminReplyModal(HrmFeedbackModel feedback) {
    final adminReplyController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, color: Color(0xFF3b82f6)),
            SizedBox(width: 12),
            Text('Send Admin Response'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Customer Feedback:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFf8fafc),
                  border: Border.all(color: const Color(0xFFe2e8f0)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feedback.subject,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      feedback.message,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your Response:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: adminReplyController,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'Type your response to the customer...',
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
            onPressed: () {
              adminReplyController.clear();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              if (adminReplyController.text.trim().isEmpty) {
                _showSnackBar('Please enter a response', Colors.red);
                return;
              }
              
              Navigator.pop(context);
              
              final result = await _feedbackService.adminReplyToFeedback(
                feedbackId: feedback.id,
                feedbackSource: 'customer',
                response: adminReplyController.text.trim(),
              );
              
              if (result['success']) {
                _showSnackBar('Response sent successfully!', Colors.green);
                _loadFeedback(); // Reload to show updated data
              } else {
                _showSnackBar(result['message'] ?? 'Failed to send response', Colors.red);
              }
              
              adminReplyController.clear();
            },
            icon: const Icon(Icons.send),
            label: const Text('Send Response'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3b82f6),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showReplyModal(HrmFeedbackModel feedback) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.reply, color: Color(0xFF3b82f6)),
            SizedBox(width: 12),
            Text('Reply to Admin'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Original Subject:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFf8fafc),
                  border: Border.all(color: const Color(0xFFe2e8f0)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  feedback.subject,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your Reply:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _replyController,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'Type your reply here...',
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
            onPressed: () {
              _replyController.clear();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _submitReply();
            },
            icon: const Icon(Icons.send),
            label: const Text('Send Reply'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3b82f6),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}