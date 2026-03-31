// lib/features/hrm_feedback/presentation/screens/unified_feedback_management_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/models/hrm_feedback_model.dart';
import '../../../../core/services/hrm_feedback_service.dart';

class UnifiedFeedbackManagementScreen extends StatefulWidget {
  const UnifiedFeedbackManagementScreen({super.key});

  @override
  State<UnifiedFeedbackManagementScreen> createState() => _UnifiedFeedbackManagementScreenState();
}

class _UnifiedFeedbackManagementScreenState extends State<UnifiedFeedbackManagementScreen> {
  final _feedbackService = HRMFeedbackService();
  
  // State management
  bool _isLoading = false;
  List<HrmFeedbackModel> _allFeedbackList = [];
  List<HrmFeedbackModel> _filteredFeedbackList = [];
  String _viewMode = 'grid'; // 'grid' or 'list'
  
  // Filter states
  String _filterSource = 'all'; // 'all', 'customer', 'driver', 'client'
  String _filterType = 'all';
  String _filterStatus = 'all';
  DateTimeRange? _dateRange;
  
  // Modal state
  HrmFeedbackModel? _selectedFeedback;
  final _adminReplyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAllFeedback();
  }

  @override
  void dispose() {
    _adminReplyController.dispose();
    super.dispose();
  }

  Future<void> _loadAllFeedback() async {
    setState(() => _isLoading = true);
    
    try {
      // Fetch all feedback from all sources
      final List<HrmFeedbackModel> allFeedback = [];
      
      // Fetch customer feedback
      final customerResult = await _feedbackService.getAllFeedbackDetailed(
        source: 'customer',
        page: 1,
        limit: 100,
      );
      if (customerResult['success'] == true) {
        final customerFeedback = (customerResult['feedback'] as List<HrmFeedbackModel>)
            .map((f) => f.copyWith(source: 'customer'))
            .toList();
        allFeedback.addAll(customerFeedback);
      }
      
      // Fetch driver feedback
      final driverResult = await _feedbackService.getAllFeedbackDetailed(
        source: 'driver',
        page: 1,
        limit: 100,
      );
      if (driverResult['success'] == true) {
        final driverFeedback = (driverResult['feedback'] as List<HrmFeedbackModel>)
            .map((f) => f.copyWith(source: 'driver'))
            .toList();
        allFeedback.addAll(driverFeedback);
      }
      
      // Fetch client/employee feedback
      final clientResult = await _feedbackService.getAllFeedbackDetailed(
        source: 'employee',
        page: 1,
        limit: 100,
      );
      if (clientResult['success'] == true) {
        final clientFeedback = (clientResult['feedback'] as List<HrmFeedbackModel>)
            .map((f) => f.copyWith(source: 'client'))
            .toList();
        allFeedback.addAll(clientFeedback);
      }
      
      // Sort by date (most recent first)
      allFeedback.sort((a, b) => b.dateSubmitted.compareTo(a.dateSubmitted));
      
      setState(() {
        _allFeedbackList = allFeedback;
        _applyFilters();
      });
    } catch (e) {
      debugPrint('Error loading feedback: $e');
      setState(() {
        _allFeedbackList = [];
        _filteredFeedbackList = [];
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    List<HrmFeedbackModel> filtered = List.from(_allFeedbackList);
    
    // Apply source filter
    if (_filterSource != 'all') {
      filtered = filtered.where((f) => f.source == _filterSource).toList();
    }
    
    // Apply type filter
    if (_filterType != 'all') {
      filtered = filtered.where((f) => f.feedbackType.toLowerCase() == _filterType.toLowerCase()).toList();
    }
    
    // Apply status filter
    if (_filterStatus != 'all') {
      if (_filterStatus == 'pending') {
        filtered = filtered.where((f) => !f.hasAdminResponse).toList();
      } else if (_filterStatus == 'responded') {
        filtered = filtered.where((f) => f.hasAdminResponse).toList();
      }
    }
    
    // Apply date range filter
    if (_dateRange != null) {
      filtered = filtered.where((f) {
        return f.dateSubmitted.isAfter(_dateRange!.start.subtract(const Duration(days: 1))) &&
               f.dateSubmitted.isBefore(_dateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }
    
    setState(() {
      _filteredFeedbackList = filtered;
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

  Color _getSourceColor(String source) {
    switch (source.toLowerCase()) {
      case 'customer':
        return const Color(0xFF3b82f6); // Blue
      case 'driver':
        return const Color(0xFF10b981); // Green
      case 'client':
        return const Color(0xFF9333EA); // Purple
      default:
        return const Color(0xFF64748b); // Gray
    }
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

  IconData _getSourceIcon(String source) {
    switch (source.toLowerCase()) {
      case 'customer':
        return Icons.person;
      case 'driver':
        return Icons.drive_eta;
      case 'client':
        return Icons.business;
      default:
        return Icons.feedback;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFf8fafc),
      appBar: AppBar(
        title: const Text(
          'Unified Feedback Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1e293b),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllFeedback,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAllFeedback,
        child: Column(
          children: [
            // Header Stats & Filters
            _buildHeaderSection(),
            
            // Feedback List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredFeedbackList.isEmpty
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
              _buildStatCard('Total', _filteredFeedbackList.length, const Color(0xFF1e293b)),
              const SizedBox(width: 8),
              _buildStatCard('Customer', _filteredFeedbackList.where((f) => f.source == 'customer').length, const Color(0xFF3b82f6)),
              const SizedBox(width: 8),
              _buildStatCard('Driver', _filteredFeedbackList.where((f) => f.source == 'driver').length, const Color(0xFF10b981)),
              const SizedBox(width: 8),
              _buildStatCard('Client', _filteredFeedbackList.where((f) => f.source == 'client').length, const Color(0xFF9333EA)),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // First Filter Row
          Row(
            children: [
              // Source Filter
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _filterSource,
                  decoration: const InputDecoration(
                    labelText: 'Source',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Sources')),
                    DropdownMenuItem(value: 'customer', child: Text('Customer')),
                    DropdownMenuItem(value: 'driver', child: Text('Driver')),
                    DropdownMenuItem(value: 'client', child: Text('Client')),
                  ],
                  onChanged: (value) {
                    setState(() => _filterSource = value!);
                    _applyFilters();
                  },
                ),
              ),
              
              const SizedBox(width: 12),
              
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
                    _applyFilters();
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
                    _applyFilters();
                  },
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Second Filter Row - Date Range and View Toggle
          Row(
            children: [
              // Date Range Filter
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: _showDateRangePicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[400]!),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.date_range, size: 20, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _dateRange == null
                                ? 'Select Date Range'
                                : '${DateFormat('MMM dd').format(_dateRange!.start)} - ${DateFormat('MMM dd').format(_dateRange!.end)}',
                            style: TextStyle(
                              fontSize: 14,
                              color: _dateRange == null ? Colors.grey[600] : Colors.black87,
                            ),
                          ),
                        ),
                        if (_dateRange != null)
                          InkWell(
                            onTap: () {
                              setState(() => _dateRange = null);
                              _applyFilters();
                            },
                            child: const Icon(Icons.clear, size: 18, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 12),
              
              // View Toggle
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.grid_view,
                      color: _viewMode == 'grid' ? const Color(0xFF1e293b) : Colors.grey,
                    ),
                    onPressed: () => setState(() => _viewMode = 'grid'),
                    tooltip: 'Grid View',
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.list,
                      color: _viewMode == 'list' ? const Color(0xFF1e293b) : Colors.grey,
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
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDateRangePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1e293b),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() => _dateRange = picked);
      _applyFilters();
    }
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
            'No feedback found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _filterSource == 'all' 
                ? 'No feedback matches your current filters'
                : 'No ${_filterSource} feedback found',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _filterSource = 'all';
                _filterType = 'all';
                _filterStatus = 'all';
                _dateRange = null;
              });
              _applyFilters();
            },
            icon: const Icon(Icons.clear_all),
            label: const Text('Clear Filters'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1e293b),
              foregroundColor: Colors.white,
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
          childAspectRatio: 0.75,
        ),
        itemCount: _filteredFeedbackList.length,
        itemBuilder: (context, index) {
          final feedback = _filteredFeedbackList[index];
          return _buildFeedbackCard(feedback);
        },
      ),
    );
  }

  Widget _buildListView() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredFeedbackList.length,
      itemBuilder: (context, index) {
        final feedback = _filteredFeedbackList[index];
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
              // Header with Source and Type
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getSourceColor(feedback.source),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getSourceIcon(feedback.source),
                          size: 10,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          feedback.source.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              // Rating
              Text(
                _getStars(feedback.rating),
                style: const TextStyle(fontSize: 12, color: Colors.amber),
              ),
              
              const SizedBox(height: 4),
              
              // Name
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
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _getSourceColor(feedback.source),
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
          backgroundColor: _getSourceColor(feedback.source).withOpacity(0.1),
          child: Icon(
            _getSourceIcon(feedback.source),
            color: _getSourceColor(feedback.source),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                feedback.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getSourceColor(feedback.source),
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
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: _getTypeColor(feedback.feedbackType),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    feedback.feedbackType.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
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
                    Icon(
                      _getSourceIcon(feedback.source),
                      color: _getSourceColor(feedback.source),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${feedback.source.toUpperCase()} Feedback Details',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getSourceColor(feedback.source),
                        borderRadius: BorderRadius.circular(8),
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
                    // Feedback Info
                    _buildInfoSection('${feedback.source.toUpperCase()} Information', [
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
                      backgroundColor: _getSourceColor(feedback.source),
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
            color: Color(0xFF1e293b),
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
            Icon(Icons.admin_panel_settings, color: _getSourceColor(feedback.source)),
            const SizedBox(width: 12),
            Text(feedback.hasAdminResponse ? 'Update Response' : 'Send Response'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getSourceColor(feedback.source),
                      borderRadius: BorderRadius.circular(8),
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
                  Expanded(
                    child: Text(
                      feedback.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Subject: ${feedback.subject}'),
              const SizedBox(height: 16),
              TextField(
                controller: _adminReplyController,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'Your Response',
                  hintText: 'Type your response to the ${feedback.source}...',
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
              
              // Determine the correct source for the API call
              String apiSource = feedback.source;
              if (feedback.source == 'client') {
                apiSource = 'employee'; // API expects 'employee' for client feedback
              }
              
              final result = await _feedbackService.adminReplyToFeedback(
                feedbackId: feedback.id,
                feedbackSource: apiSource,
                response: _adminReplyController.text.trim(),
              );
              
              if (result['success']) {
                _showSnackBar('Response sent successfully!', Colors.green);
                _loadAllFeedback();
              } else {
                _showSnackBar(result['message'] ?? 'Failed to send response', Colors.red);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _getSourceColor(feedback.source),
              foregroundColor: Colors.white,
            ),
            child: const Text('Send Response'),
          ),
        ],
      ),
    );
  }
}

// Extension to add copyWith method to HrmFeedbackModel
extension HrmFeedbackModelExtension on HrmFeedbackModel {
  HrmFeedbackModel copyWith({
    String? id,
    String? name,
    String? email,
    String? feedbackType,
    String? subject,
    String? message,
    int? rating,
    DateTime? dateSubmitted,
    String? status,
    String? adminResponse,
    DateTime? responseDate,
    String? parentFeedbackId,
    String? source,
  }) {
    return HrmFeedbackModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      feedbackType: feedbackType ?? this.feedbackType,
      subject: subject ?? this.subject,
      message: message ?? this.message,
      rating: rating ?? this.rating,
      dateSubmitted: dateSubmitted ?? this.dateSubmitted,
      status: status ?? this.status,
      adminResponse: adminResponse ?? this.adminResponse,
      responseDate: responseDate ?? this.responseDate,
      parentFeedbackId: parentFeedbackId ?? this.parentFeedbackId,
      source: source ?? this.source,
    );
  }
}