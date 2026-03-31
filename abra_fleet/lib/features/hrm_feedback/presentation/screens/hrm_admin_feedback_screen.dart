// lib/features/hrm_feedback/presentation/screens/hrm_admin_feedback_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/models/hrm_feedback_model.dart';
import '../../../../core/services/hrm_feedback_service.dart';

class HrmAdminFeedbackScreen extends StatefulWidget {
  const HrmAdminFeedbackScreen({Key? key}) : super(key: key);

  @override
  State<HrmAdminFeedbackScreen> createState() => _HrmAdminFeedbackScreenState();
}

class _HrmAdminFeedbackScreenState extends State<HrmAdminFeedbackScreen> {
  final _feedbackService = HRMFeedbackService();
  
  // State management
  bool _isLoading = false;
  List<HrmFeedbackModel> _feedbackList = [];
  HrmFeedbackStats? _stats;
  
  // Filters
  String _sourceFilter = 'all';
  String _typeFilter = 'all';
  String _statusFilter = 'all';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  final _nameSearchController = TextEditingController();
  
  // UI state
  String _viewMode = 'grid';
  int _currentPage = 1;
  final int _limit = 20;
  int _totalPages = 1;
  
  // Reply modal
  HrmFeedbackModel? _selectedFeedback;
  final _replyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameSearchController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadFeedback(),
      _loadStats(),
    ]);
  }

  Future<void> _loadFeedback() async {
    setState(() => _isLoading = true);
    
    final result = await _feedbackService.getAllFeedback('all');
    
    setState(() {
      _feedbackList = result;
      _isLoading = false;
    });
  }

  Future<void> _loadStats() async {
    final stats = await _feedbackService.getFeedbackStats(source: _sourceFilter);
    setState(() => _stats = stats);
  }

  Future<void> _submitReply() async {
    if (_selectedFeedback == null || _replyController.text.trim().isEmpty) {
      _showSnackBar('Please enter a response', Colors.red);
      return;
    }

    final result = await _feedbackService.adminReplyToFeedback(
      feedbackId: _selectedFeedback!.id,
      feedbackSource: _selectedFeedback!.source,
      response: _replyController.text.trim(),
    );

    if (result['success']) {
      _showSnackBar(result['message'], Colors.green);
      Navigator.pop(context);
      _replyController.clear();
      _loadData();
    } else {
      _showSnackBar(result['message'], Colors.red);
    }
  }

  void _applyFilters() {
    setState(() => _currentPage = 1);
    _loadData();
  }

  void _resetFilters() {
    setState(() {
      _sourceFilter = 'all';
      _typeFilter = 'all';
      _statusFilter = 'all';
      _dateFrom = null;
      _dateTo = null;
      _nameSearchController.clear();
      _currentPage = 1;
    });
    _loadData();
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
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
          'Feedback Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF6366f1),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Statistics Cards
              _buildStatisticsCards(),
              const SizedBox(height: 20),
              
              // Filters Panel
              _buildFiltersPanel(),
              const SizedBox(height: 20),
              
              // Feedback List
              _buildFeedbackList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatisticsCards() {
    if (_stats == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Statistics Overview',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0f172a),
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _buildStatCard(
              'Total Feedback',
              _stats!.total.toString(),
              Icons.chat_bubble,
              const Color(0xFF3b82f6),
            ),
            _buildStatCard(
              'Pending',
              _stats!.pending.toString(),
              Icons.pending,
              const Color(0xFFf59e0b),
            ),
            _buildStatCard(
              'Responded',
              _stats!.responded.toString(),
              Icons.check_circle,
              const Color(0xFF10b981),
            ),
            _buildStatCard(
              'Avg Rating',
              _stats!.avgRating.toStringAsFixed(1),
              Icons.star,
              const Color(0xFFfbbf24),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFe2e8f0), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748b),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
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
          Row(
            children: [
              const Icon(Icons.filter_list, color: Color(0xFF6366f1)),
              const SizedBox(width: 12),
              const Text(
                'Filters',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0f172a),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _resetFilters,
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Reset'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF64748b),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Source & Type & Status
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  label: 'Source',
                  value: _sourceFilter,
                  items: const [
                    {'value': 'all', 'label': 'All'},
                    {'value': 'customer', 'label': 'Customer'},
                    {'value': 'employee', 'label': 'Employee'},
                  ],
                  onChanged: (value) {
                    setState(() => _sourceFilter = value!);
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdown(
                  label: 'Type',
                  value: _typeFilter,
                  items: const [
                    {'value': 'all', 'label': 'All'},
                    {'value': 'appreciation', 'label': 'Appreciation'},
                    {'value': 'complaint', 'label': 'Complaint'},
                    {'value': 'suggestion', 'label': 'Suggestion'},
                    {'value': 'general', 'label': 'General'},
                  ],
                  onChanged: (value) => setState(() => _typeFilter = value!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  label: 'Status',
                  value: _statusFilter,
                  items: const [
                    {'value': 'all', 'label': 'All'},
                    {'value': 'pending', 'label': 'Pending'},
                    {'value': 'responded', 'label': 'Responded'},
                  ],
                  onChanged: (value) => setState(() => _statusFilter = value!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _nameSearchController,
                  decoration: InputDecoration(
                    labelText: 'Search Name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Date Range
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _dateFrom ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setState(() => _dateFrom = date);
                    }
                  },
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    _dateFrom != null
                        ? DateFormat('MMM d, y').format(_dateFrom!)
                        : 'From Date',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _dateTo ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setState(() => _dateTo = date);
                    }
                  },
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    _dateTo != null
                        ? DateFormat('MMM d, y').format(_dateTo!)
                        : 'To Date',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Apply Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _applyFilters,
              icon: const Icon(Icons.search),
              label: const Text('Apply Filters'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366f1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<Map<String, String>> items,
    required Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      items: items.map((item) {
        return DropdownMenuItem<String>(
          value: item['value'],
          child: Text(item['label']!, style: const TextStyle(fontSize: 14)),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildFeedbackList() {
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
          // List Header
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
                const Icon(Icons.list, color: Color(0xFF6366f1), size: 24),
                const SizedBox(width: 12),
                const Text(
                  'All Feedback',
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
                    color: const Color(0xFF6366f1),
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
                            ? const Color(0xFF6366f1)
                            : const Color(0xFF64748b),
                      ),
                      onPressed: () => setState(() => _viewMode = 'grid'),
                      tooltip: 'Grid View',
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.list,
                        color: _viewMode == 'table'
                            ? const Color(0xFF6366f1)
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
          
          // List Content
          _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _feedbackList.isEmpty
                  ? _buildEmptyState()
                  : Column(
                      children: [
                        _viewMode == 'grid'
                            ? _buildGridView()
                            : _buildListView(),
                        
                        // Pagination
                        if (_totalPages > 1) _buildPagination(),
                      ],
                    ),
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
            'No feedback found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0f172a),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try adjusting your filters',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF64748b),
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
            // Header
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: feedback.source == 'customer'
                              ? const Color(0xFF3b82f6)
                              : const Color(0xFF0D47A1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          feedback.source.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        _getStars(feedback.rating),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFfbbf24),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
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
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Name & Subject
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    feedback.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0f172a),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    feedback.subject,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6366f1),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
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
                    fontSize: 11,
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
                  Text(
                    _formatDate(feedback.dateSubmitted),
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFF64748b),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: feedback.hasAdminResponse
                          ? const Color(0xFF10b981)
                          : const Color(0xFFf59e0b),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      feedback.hasAdminResponse ? 'Replied' : 'Pending',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
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
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: feedback.source == 'customer'
                      ? const Color(0xFF3b82f6)
                      : const Color(0xFF0D47A1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  feedback.source.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  feedback.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                feedback.subject,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Color(0xFF6366f1),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
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
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: feedback.hasAdminResponse
                  ? const Color(0xFF10b981)
                  : const Color(0xFFf59e0b),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              feedback.hasAdminResponse ? 'Replied' : 'Pending',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: const Color(0xFFe2e8f0)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _currentPage > 1
                ? () {
                    setState(() => _currentPage--);
                    _loadFeedback();
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          const SizedBox(width: 16),
          Text(
            'Page $_currentPage of $_totalPages',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: _currentPage < _totalPages
                ? () {
                    setState(() => _currentPage++);
                    _loadFeedback();
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  void _showFeedbackDetailModal(HrmFeedbackModel feedback) {
    setState(() => _selectedFeedback = feedback);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
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
                    const Icon(Icons.chat_bubble, color: Color(0xFF6366f1)),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Feedback Details',
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
                    // User Info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFf8fafc),
                        border: Border.all(color: const Color(0xFFe2e8f0)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: feedback.source == 'customer'
                                      ? const Color(0xFF3b82f6)
                                      : const Color(0xFF0D47A1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  feedback.source.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
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
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            feedback.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            feedback.email,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF64748b),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                _getStars(feedback.rating),
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFFfbbf24),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _formatDate(feedback.dateSubmitted),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748b),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Subject & Message
                    _buildMessageBubble(
                      isUser: true,
                      name: 'Customer Message',
                      date: feedback.dateSubmitted,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            feedback.subject,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6366f1),
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
                        name: 'Your Response',
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
              
              // Reply/Edit Button
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
                    icon: Icon(
                      feedback.hasAdminResponse ? Icons.edit : Icons.reply,
                    ),
                    label: Text(
                      feedback.hasAdminResponse
                          ? 'Edit Response'
                          : 'Reply to Feedback',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366f1),
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

  void _showReplyModal(HrmFeedbackModel feedback) {
    // Pre-fill if editing
    if (feedback.hasAdminResponse) {
      _replyController.text = feedback.adminResponse!;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              feedback.hasAdminResponse ? Icons.edit : Icons.reply,
              color: const Color(0xFF6366f1),
            ),
            const SizedBox(width: 12),
            Text(feedback.hasAdminResponse ? 'Edit Response' : 'Reply to Feedback'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Feedback Info
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
                      'From: ${feedback.name}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Subject: ${feedback.subject}',
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
                controller: _replyController,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: 'Type your response here...',
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
            label: const Text('Send Response'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366f1),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}