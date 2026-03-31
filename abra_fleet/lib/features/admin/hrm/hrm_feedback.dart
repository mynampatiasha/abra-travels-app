// ============================================================================
// HRM FEEDBACK SCREEN - REDESIGNED
// ============================================================================
// Modern Table-Based Feedback Management Interface
// Author: Abra Fleet Management System
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'package:abra_fleet/core/services/hrm_feedback_service.dart';

class HRMFeedbackScreen extends StatefulWidget {
  const HRMFeedbackScreen({Key? key}) : super(key: key);

  @override
  State<HRMFeedbackScreen> createState() => _HRMFeedbackScreenState();
}

class _HRMFeedbackScreenState extends State<HRMFeedbackScreen> with SingleTickerProviderStateMixin {
  // ============================================================================
  // COLORS - Modern Blue/Purple Theme
  // ============================================================================
  
  static const Color primaryBlue = Color(0xFF3B82F6);
  static const Color primaryPurple = Color(0xFF8B5CF6);
  static const Color darkText = Color(0xFF1E293B);
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color successGreen = Color(0xFF10B981);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color dangerRed = Color(0xFFEF4444);
  static const Color cardWhite = Color(0xFFFFFFFF);
  static const Color borderGray = Color(0xFFE2E8F0);
  static const Color textGray = Color(0xFF64748B);
  
  // ============================================================================
  // STATE VARIABLES
  // ============================================================================
  
  final HRMFeedbackService _service = HRMFeedbackService();
  
  bool _isLoading = true;
  bool _isAdmin = false;
  String? _errorMessage;
  
  // Admin Dashboard Data
  List<Map<String, dynamic>> _allFeedbacks = [];
  Map<String, dynamic> _statistics = {};
  Map<String, dynamic> _pagination = {};
  Map<String, dynamic> _userNames = {};
  
  // Personal Feedback Data
  List<Map<String, dynamic>> _myFeedbacks = [];
  Map<String, dynamic> _myStatistics = {};
  
  // Filters
  String _selectedSource = 'all';
  String? _selectedName;
  String _selectedType = 'all';
  String? _dateFrom;
  String? _dateTo;
  String _searchQuery = '';
  int _currentPage = 1;
  
  // Personal Filters
  String? _myDateFrom;
  String? _myDateTo;
  
  // Form Controllers
  final _feedbackTypeController = TextEditingController();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  final _employeeSearchController = TextEditingController();
  int _selectedRating = 5;
  
  // Employees for ticket assignment
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filteredEmployees = [];
  bool _loadingEmployees = false;
  
  // Tab Controller
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeScreen();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _feedbackTypeController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    _employeeSearchController.dispose();
    super.dispose();
  }
  
  // ============================================================================
  // INITIALIZATION
  // ============================================================================
  
  Future<void> _initializeScreen() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      _isAdmin = await _service.isAdmin();
      
      if (_isAdmin) {
        await Future.wait([
          _loadAllFeedbacks(),
          _loadStatistics(),
          _loadUserNames(),
          _loadEmployees(),
          _loadMyFeedbacks(),
          _loadMyStatistics(),
        ]);
      } else {
        await Future.wait([
          _loadMyFeedbacks(),
          _loadMyStatistics(),
        ]);
      }
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }
  
  // ============================================================================
  // DATA LOADING METHODS
  // ============================================================================
  
  Future<void> _loadAllFeedbacks() async {
    try {
      final result = await _service.getAllFeedback(
        source: _selectedSource,
        nameFilter: _selectedName,
        type: _selectedType,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        page: _currentPage,
      );
      
      setState(() {
        _allFeedbacks = List<Map<String, dynamic>>.from(result['feedbacks'] ?? []);
        _pagination = result['pagination'] ?? {};
      });
    } catch (e) {
      _showErrorSnackBar('Failed to load feedback: ${e.toString()}');
    }
  }
  
  Future<void> _loadStatistics() async {
    try {
      final stats = await _service.getFeedbackStatistics(
        source: _selectedSource,
        nameFilter: _selectedName,
        type: _selectedType,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );
      
      setState(() {
        _statistics = stats;
      });
    } catch (e) {
      _showErrorSnackBar('Failed to load statistics: ${e.toString()}');
    }
  }
  
  Future<void> _loadUserNames() async {
    try {
      final names = await _service.getUserNames(source: _selectedSource);
      setState(() {
        _userNames = names;
      });
    } catch (e) {
      _showErrorSnackBar('Failed to load user names: ${e.toString()}');
    }
  }
  
  Future<void> _loadEmployees() async {
    try {
      setState(() => _loadingEmployees = true);
      final employees = await _service.getEmployeesForTicket();
      setState(() {
        _employees = employees;
        _filteredEmployees = employees;
        _loadingEmployees = false;
      });
    } catch (e) {
      setState(() => _loadingEmployees = false);
    }
  }
  
  Future<void> _loadMyFeedbacks() async {
    try {
      final feedbacks = await _service.getMyFeedback(
        dateFrom: _myDateFrom,
        dateTo: _myDateTo,
      );
      setState(() {
        _myFeedbacks = feedbacks;
      });
    } catch (e) {
      _showErrorSnackBar('Failed to load my feedback: ${e.toString()}');
    }
  }
  
  Future<void> _loadMyStatistics() async {
    try {
      final stats = await _service.getMyFeedbackStatistics(
        dateFrom: _myDateFrom,
        dateTo: _myDateTo,
      );
      setState(() {
        _myStatistics = stats;
      });
    } catch (e) {
      _showErrorSnackBar('Failed to load statistics: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // FEEDBACK SUBMISSION
  // ============================================================================
  
  Future<void> _submitFeedback() async {
    if (_feedbackTypeController.text.isEmpty ||
        _subjectController.text.isEmpty ||
        _messageController.text.isEmpty) {
      _showErrorSnackBar('Please fill in all fields');
      return;
    }
    
    _showLoadingDialog();
    
    try {
      await _service.submitFeedback(
        feedbackType: _feedbackTypeController.text,
        subject: _subjectController.text,
        message: _messageController.text,
        rating: _selectedRating,
      );
      
      Navigator.of(context).pop(); 
      _showSuccessSnackBar('Feedback submitted successfully!');
      
      _feedbackTypeController.clear();
      _subjectController.clear();
      _messageController.clear();
      setState(() {
        _selectedRating = 5;
      });
      
      await _loadMyFeedbacks();
      await _loadMyStatistics();
      
      if (_isAdmin) {
        await _loadAllFeedbacks();
        await _loadStatistics();
      }
    } catch (e) {
      Navigator.of(context).pop();
      _showErrorSnackBar('Failed to submit feedback: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // FILTER HANDLERS
  // ============================================================================
  
  Future<void> _applyFilters() async {
    setState(() {
      _currentPage = 1;
    });
    await Future.wait([
      _loadAllFeedbacks(),
      _loadStatistics(),
      _loadUserNames(),
    ]);
  }
  
  Future<void> _applyPersonalFilters() async {
    await Future.wait([
      _loadMyFeedbacks(),
      _loadMyStatistics(),
    ]);
  }
  
  void _resetFilters() {
    setState(() {
      _selectedSource = 'all';
      _selectedName = null;
      _selectedType = 'all';
      _dateFrom = null;
      _dateTo = null;
      _searchQuery = '';
      _currentPage = 1;
    });
    _applyFilters();
  }
  
  // ============================================================================
  // CONVERSATION METHODS
  // ============================================================================
  
  Future<void> _openConversation(String feedbackId) async {
    _showLoadingDialog();
    try {
      final conversation = await _service.getConversation(feedbackId);
      Navigator.of(context).pop(); 
      _showConversationDialog(
        conversation['conversation'] ?? [],
        conversation['subject'] ?? '',
        conversation['threadId'] ?? feedbackId,
      );
    } catch (e) {
      Navigator.of(context).pop();
      _showErrorSnackBar('Failed to load conversation: ${e.toString()}');
    }
  }
  
  Future<void> _sendReply(String threadId, String message) async {
    if (message.trim().isEmpty) {
      _showErrorSnackBar('Please enter a message');
      return;
    }
    try {
      await _service.sendReply(
        threadId: threadId,
        message: message,
      );
      _showSuccessSnackBar('Reply sent successfully!');
      final conversation = await _service.getConversation(threadId);
      Navigator.of(context).pop(); 
      _showConversationDialog(
        conversation['conversation'] ?? [],
        conversation['subject'] ?? '',
        threadId,
      );
    } catch (e) {
      _showErrorSnackBar('Failed to send reply: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // TICKET METHODS
  // ============================================================================
  
  Future<void> _createTicket(String feedbackId, Map<String, dynamic> feedback) async {
    String? selectedEmployee;
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: cardWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 600),
          padding: const EdgeInsets.all(24),
          child: StatefulBuilder(
            builder: (context, setDialogState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [primaryBlue, primaryPurple]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.confirmation_number, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Create Ticket', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: darkText)),
                    ),
                    IconButton(icon: const Icon(Icons.close, color: textGray), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderGray)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person, size: 16, color: primaryBlue),
                          const SizedBox(width: 8),
                          Expanded(child: Text('From: ${feedback['submitterName']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.subject, size: 16, color: primaryPurple),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Subject: ${feedback['subject']}', style: const TextStyle(fontSize: 13, color: textGray))),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderGray)),
                  child: TextField(
                    controller: _employeeSearchController,
                    style: const TextStyle(color: darkText),
                    decoration: InputDecoration(
                      hintText: 'Search employees...',
                      hintStyle: const TextStyle(color: textGray),
                      prefixIcon: const Icon(Icons.search, color: primaryBlue),
                      suffixIcon: _employeeSearchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, color: textGray), onPressed: () { setDialogState(() { _employeeSearchController.clear(); _filteredEmployees = _employees; }); }) : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    onChanged: (value) { setDialogState(() => _filterEmployees(value)); },
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _loadingEmployees
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation<Color>(primaryBlue)))
                      : _filteredEmployees.isEmpty
                          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.search_off, size: 64, color: borderGray), SizedBox(height: 16), Text('No employees found', style: TextStyle(color: textGray, fontSize: 16, fontWeight: FontWeight.w500))]))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: _filteredEmployees.length,
                              itemBuilder: (context, index) {
                                final employee = _filteredEmployees[index];
                                final isSelected = selectedEmployee == employee['id'].toString();
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(color: isSelected ? primaryBlue.withOpacity(0.1) : lightBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: isSelected ? primaryBlue : borderGray, width: isSelected ? 2 : 1)),
                                  child: ListTile(
                                    onTap: () { setDialogState(() { selectedEmployee = employee['id'].toString(); }); },
                                    leading: CircleAvatar(backgroundColor: isSelected ? primaryBlue : borderGray, child: Text((employee['name'] ?? 'U')[0].toUpperCase(), style: TextStyle(color: isSelected ? Colors.white : textGray, fontWeight: FontWeight.bold))),
                                    title: Text(employee['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                    subtitle: employee['email'] != null ? Text(employee['email'], style: const TextStyle(color: textGray, fontSize: 12)) : null,
                                    trailing: isSelected ? const Icon(Icons.check_circle, color: primaryBlue) : null,
                                  ),
                                );
                              },
                            ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [primaryBlue, primaryPurple]), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: primaryBlue.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))]),
                  child: ElevatedButton(
                    onPressed: () async {
                      if (selectedEmployee == null) { _showErrorSnackBar('Please select an employee'); return; }
                      Navigator.of(context).pop(); 
                      _showLoadingDialog();
                      try {
                        await _service.createTicket(feedbackId: feedbackId, assignedTo: selectedEmployee!);
                        Navigator.of(context).pop(); 
                        _showSuccessSnackBar('Ticket created successfully!');
                        await _loadAllFeedbacks();
                      } catch (e) {
                        Navigator.of(context).pop();
                        _showErrorSnackBar('Failed to create ticket: ${e.toString()}');
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    child: const Text('Create Ticket', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  void _filterEmployees(String query) {
    if (query.isEmpty) {
      setState(() => _filteredEmployees = _employees);
      return;
    }
    setState(() {
      _filteredEmployees = _employees.where((emp) {
        final name = (emp['name'] ?? '').toString().toLowerCase();
        final email = (emp['email'] ?? '').toString().toLowerCase();
        return name.contains(query.toLowerCase()) || email.contains(query.toLowerCase());
      }).toList();
    });
  }
  
  // ============================================================================
  // UI HELPER METHODS
  // ============================================================================
  
  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: cardWhite, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))]),
          child: Column(mainAxisSize: MainAxisSize.min, children: const [CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation<Color>(primaryBlue)), SizedBox(height: 16), Text('Loading...', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: darkText))]),
        ),
      ),
    );
  }
  
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Row(children: [const Icon(Icons.check_circle, color: Colors.white), const SizedBox(width: 12), Expanded(child: Text(message))]), backgroundColor: successGreen, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), margin: const EdgeInsets.all(16)));
  }
  
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Row(children: [const Icon(Icons.error, color: Colors.white), const SizedBox(width: 12), Expanded(child: Text(message))]), backgroundColor: dangerRed, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), margin: const EdgeInsets.all(16)));
  }
  
  void _showConversationDialog(List<dynamic> messages, String subject, String threadId) {
    final TextEditingController replyController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: cardWhite,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [primaryBlue, primaryPurple]), borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24))),
                child: Row(children: [const Icon(Icons.chat_bubble, color: Colors.white), const SizedBox(width: 12), const Expanded(child: Text('Conversation', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))), IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.of(context).pop())]),
              ),
              if (subject.isNotEmpty) Container(width: double.infinity, padding: const EdgeInsets.all(16), color: lightBg, child: Row(children: [const Icon(Icons.subject, size: 16, color: primaryBlue), const SizedBox(width: 8), Expanded(child: Text(subject, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)))])) ,
              Expanded(
                child: Container(
                  color: const Color(0xFFF1F5F9),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isAdminMsg = msg['isAdmin'] == true;
                      return Align(
                        alignment: isAdminMsg ? Alignment.centerLeft : Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(gradient: isAdminMsg ? null : const LinearGradient(colors: [primaryBlue, primaryPurple]), color: isAdminMsg ? cardWhite : null, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))]),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(msg['sender'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isAdminMsg ? primaryBlue : Colors.white))), Text(_formatDate(msg['date']), style: TextStyle(fontSize: 10, color: isAdminMsg ? textGray : Colors.white70))]), const SizedBox(height: 8), Text(msg['message'] ?? '', style: TextStyle(fontSize: 14, color: isAdminMsg ? darkText : Colors.white)), if (msg['rating'] != null && msg['rating'] > 0) ...[const SizedBox(height: 8), Row(children: List.generate(5, (i) => Icon(i < msg['rating'] ? Icons.star : Icons.star_border, color: warningOrange, size: 16)))]]),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: cardWhite, border: Border(top: BorderSide(color: borderGray))),
                child: Row(children: [Expanded(child: Container(decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderGray)), child: TextField(controller: replyController, maxLines: 3, minLines: 1, style: const TextStyle(color: darkText), decoration: const InputDecoration(hintText: 'Type your reply...', hintStyle: TextStyle(color: textGray), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12))))), const SizedBox(width: 12), Container(width: 50, height: 50, decoration: BoxDecoration(gradient: const LinearGradient(colors: [primaryBlue, primaryPurple]), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: primaryBlue.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]), child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 22), onPressed: () => _sendReply(threadId, replyController.text)))]),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  String _formatDate(dynamic date) {
    try {
      if (date == null) return '';
      DateTime parsedDate;
      if (date is String) { parsedDate = DateTime.parse(date); }
      else if (date is DateTime) { parsedDate = date; }
      else { return ''; }
      return DateFormat('MMM dd, HH:mm').format(parsedDate);
    } catch (e) { return ''; }
  }
  
  String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
  
  // ============================================================================
  // BUILD METHOD
  // ============================================================================
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBg,
      body: _isLoading
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation<Color>(primaryBlue)), SizedBox(height: 16), Text('Loading...', style: TextStyle(fontWeight: FontWeight.w600, color: darkText))]))
          : _errorMessage != null
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.error_outline, size: 64, color: dangerRed), const SizedBox(height: 16), Text(_errorMessage!, style: const TextStyle(color: dangerRed)), const SizedBox(height: 16), ElevatedButton(onPressed: _initializeScreen, style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Retry', style: TextStyle(color: Colors.white)))]))
              : _isAdmin ? _buildAdminView() : _buildUserView(),
    );
  }
  
  // ============================================================================
  // ADMIN VIEW
  // ============================================================================
  
  Widget _buildAdminView() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),
          _buildStatisticsCards(),
          const SizedBox(height: 20),
          _buildChartsSection(),
          const SizedBox(height: 20),
          _buildAdminFilters(),
          const SizedBox(height: 20),
          _buildFeedbackTable(_allFeedbacks, isAdmin: true),
          if (_pagination['totalPages'] != null && _pagination['totalPages'] > 1) _buildPagination(),
          const SizedBox(height: 32),
          _buildPersonalSectionDivider(),
          const SizedBox(height: 20),
          _buildPersonalStatistics(),
          const SizedBox(height: 20),
          _buildPersonalFilters(),
          const SizedBox(height: 20),
          _buildSubmitFeedbackForm(),
          const SizedBox(height: 20),
          _buildFeedbackTable(_myFeedbacks, isAdmin: false),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
  
  Widget _buildUserView() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),
          _buildPersonalStatistics(),
          const SizedBox(height: 20),
          _buildPersonalFilters(),
          const SizedBox(height: 20),
          _buildSubmitFeedbackForm(),
          const SizedBox(height: 20),
          _buildFeedbackTable(_myFeedbacks, isAdmin: false),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
  
  // ============================================================================
  // ADMIN FILTERS
  // ============================================================================
  
  Widget _buildAdminFilters() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: cardWhite, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [Icon(Icons.filter_list, color: primaryBlue, size: 24), SizedBox(width: 12), Text('Filters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText))]),
          const SizedBox(height: 20),
          Container(decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderGray)), child: TextField(style: const TextStyle(color: darkText), decoration: const InputDecoration(hintText: 'Search feedback...', hintStyle: TextStyle(color: textGray), prefixIcon: Icon(Icons.search, color: primaryBlue), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14)), onChanged: (value) { setState(() { _searchQuery = value; }); }, onSubmitted: (_) => _applyFilters())),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Container(decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderGray)), child: DropdownButtonFormField<String>(value: _selectedSource, dropdownColor: cardWhite, style: const TextStyle(color: darkText, fontSize: 14), decoration: const InputDecoration(labelText: 'Source', labelStyle: TextStyle(color: textGray, fontSize: 12), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8)), items: const [DropdownMenuItem(value: 'all', child: Text('All Sources')), DropdownMenuItem(value: 'customers', child: Text('Customers')), DropdownMenuItem(value: 'drivers', child: Text('Drivers')), DropdownMenuItem(value: 'clients', child: Text('Clients')), DropdownMenuItem(value: 'employee_admins', child: Text('Admins'))], onChanged: (value) { setState(() { _selectedSource = value!; _selectedName = null; }); _loadUserNames(); }))),
            const SizedBox(width: 12),
            Expanded(child: Container(decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderGray)), child: DropdownButtonFormField<String>(value: _selectedType, dropdownColor: cardWhite, style: const TextStyle(color: darkText, fontSize: 14), decoration: const InputDecoration(labelText: 'Type', labelStyle: TextStyle(color: textGray, fontSize: 12), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8)), items: const [DropdownMenuItem(value: 'all', child: Text('All Types')), DropdownMenuItem(value: 'suggestion', child: Text('Suggestion')), DropdownMenuItem(value: 'complaint', child: Text('Complaint')), DropdownMenuItem(value: 'appreciation', child: Text('Appreciation')), DropdownMenuItem(value: 'general', child: Text('General'))], onChanged: (value) { setState(() { _selectedType = value!; }); })))
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Container(decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderGray)), child: DropdownButtonFormField<String>(value: _selectedName, dropdownColor: cardWhite, style: const TextStyle(color: darkText, fontSize: 14), decoration: const InputDecoration(labelText: 'Name', labelStyle: TextStyle(color: textGray, fontSize: 12), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8)), items: [const DropdownMenuItem(value: null, child: Text('All People')), ..._buildNameFilterItems()], onChanged: (value) { setState(() { _selectedName = value; }); }))),
            const SizedBox(width: 12),
            Expanded(child: InkWell(onTap: () async { final date = await showDatePicker(context: context, initialDate: _dateFrom != null ? DateTime.parse(_dateFrom!) : DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now()); if (date != null) { setState(() { _dateFrom = DateFormat('yyyy-MM-dd').format(date); }); } }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderGray)), child: Row(children: [const Icon(Icons.calendar_today, size: 16, color: primaryBlue), const SizedBox(width: 8), Expanded(child: Text(_dateFrom ?? 'From Date', style: TextStyle(fontSize: 14, color: _dateFrom != null ? darkText : textGray)))])))),
            const SizedBox(width: 12),
            Expanded(child: InkWell(onTap: () async { final date = await showDatePicker(context: context, initialDate: _dateTo != null ? DateTime.parse(_dateTo!) : DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now()); if (date != null) { setState(() { _dateTo = DateFormat('yyyy-MM-dd').format(date); }); } }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderGray)), child: Row(children: [const Icon(Icons.calendar_today, size: 16, color: primaryPurple), const SizedBox(width: 8), Expanded(child: Text(_dateTo ?? 'To Date', style: TextStyle(fontSize: 14, color: _dateTo != null ? darkText : textGray)))]))))
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: Container(height: 48, decoration: BoxDecoration(gradient: const LinearGradient(colors: [primaryBlue, primaryPurple]), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: primaryBlue.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]), child: ElevatedButton.icon(onPressed: _applyFilters, icon: const Icon(Icons.check, color: Colors.white, size: 20), label: const Text('Apply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))))),
            const SizedBox(width: 12),
            Container(height: 48, decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderGray, width: 2)), child: ElevatedButton.icon(onPressed: _resetFilters, icon: const Icon(Icons.refresh, color: textGray, size: 20), label: const Text('Reset', style: TextStyle(color: textGray, fontWeight: FontWeight.w600)), style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))))
          ])
        ],
      ),
    );
  }
  
  List<DropdownMenuItem<String>> _buildNameFilterItems() {
    List<DropdownMenuItem<String>> items = [];
    final customers = _userNames['customers'] ?? [];
    final drivers = _userNames['drivers'] ?? [];
    final clients = _userNames['clients'] ?? [];
    final employeeAdmins = _userNames['employeeAdmins'] ?? [];
    if (_selectedSource == 'all') {
      if (customers.isNotEmpty) { items.add(const DropdownMenuItem(enabled: false, child: Text('Customers', style: TextStyle(fontWeight: FontWeight.bold, color: textGray, fontSize: 12)))); items.addAll(customers.map<DropdownMenuItem<String>>((name) => DropdownMenuItem(value: name, child: Text('  $name'))).toList()); }
      if (drivers.isNotEmpty) { items.add(const DropdownMenuItem(enabled: false, child: Text('Drivers', style: TextStyle(fontWeight: FontWeight.bold, color: textGray, fontSize: 12)))); items.addAll(drivers.map<DropdownMenuItem<String>>((name) => DropdownMenuItem(value: name, child: Text('  $name'))).toList()); }
      if (clients.isNotEmpty) { items.add(const DropdownMenuItem(enabled: false, child: Text('Clients', style: TextStyle(fontWeight: FontWeight.bold, color: textGray, fontSize: 12)))); items.addAll(clients.map<DropdownMenuItem<String>>((name) => DropdownMenuItem(value: name, child: Text('  $name'))).toList()); }
      if (employeeAdmins.isNotEmpty) { items.add(const DropdownMenuItem(enabled: false, child: Text('Admins', style: TextStyle(fontWeight: FontWeight.bold, color: textGray, fontSize: 12)))); items.addAll(employeeAdmins.map<DropdownMenuItem<String>>((name) => DropdownMenuItem(value: name, child: Text('  $name'))).toList()); }
    } else if (_selectedSource == 'customers') { items.addAll(customers.map<DropdownMenuItem<String>>((name) => DropdownMenuItem(value: name, child: Text(name))).toList()); }
    else if (_selectedSource == 'drivers') { items.addAll(drivers.map<DropdownMenuItem<String>>((name) => DropdownMenuItem(value: name, child: Text(name))).toList()); }
    else if (_selectedSource == 'clients') { items.addAll(clients.map<DropdownMenuItem<String>>((name) => DropdownMenuItem(value: name, child: Text(name))).toList()); }
    else if (_selectedSource == 'employee_admins') { items.addAll(employeeAdmins.map<DropdownMenuItem<String>>((name) => DropdownMenuItem(value: name, child: Text(name))).toList()); }
    return items;
  }
  
  // ============================================================================
  // STATISTICS CARDS
  // ============================================================================
  
  Widget _buildStatisticsCards() {
    final bySource = _statistics['bySource'] ?? {};
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(children: [Expanded(child: _buildStatCard('Customers', bySource['customers'] ?? 0, Icons.people, primaryBlue)), const SizedBox(width: 12), Expanded(child: _buildStatCard('Drivers', bySource['drivers'] ?? 0, Icons.local_shipping, successGreen))]),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: _buildStatCard('Clients', bySource['clients'] ?? 0, Icons.business, warningOrange)), const SizedBox(width: 12), Expanded(child: _buildStatCard('Admins', bySource['employeeAdmins'] ?? 0, Icons.admin_panel_settings, primaryPurple))])
        ],
      ),
    );
  }
  
  Widget _buildStatCard(String label, int count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: cardWhite, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 5))]),
      child: Row(children: [Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color, size: 28)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(count.toString(), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)), const SizedBox(height: 2), Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textGray))]))]),
    );
  }
  
  // ============================================================================
  // CHARTS SECTION
  // ============================================================================
  
  Widget _buildChartsSection() {
    final byType = _statistics['byType']?['overall'] ?? {};
    final total = (byType['suggestion'] ?? 0) + (byType['complaint'] ?? 0) + (byType['appreciation'] ?? 0) + (byType['general'] ?? 0);
    if (total == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: cardWhite, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [Icon(Icons.pie_chart, color: primaryBlue, size: 24), SizedBox(width: 12), Text('Feedback Distribution', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText))]),
          const SizedBox(height: 24),
          SizedBox(height: 200, child: PieChart(PieChartData(sections: [PieChartSectionData(value: (byType['suggestion'] ?? 0).toDouble(), color: primaryBlue, title: '${(((byType['suggestion'] ?? 0) / total) * 100).toStringAsFixed(0)}%', radius: 85, titleStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)), PieChartSectionData(value: (byType['complaint'] ?? 0).toDouble(), color: dangerRed, title: '${(((byType['complaint'] ?? 0) / total) * 100).toStringAsFixed(0)}%', radius: 85, titleStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)), PieChartSectionData(value: (byType['appreciation'] ?? 0).toDouble(), color: const Color(0xFFEC4899), title: '${(((byType['appreciation'] ?? 0) / total) * 100).toStringAsFixed(0)}%', radius: 85, titleStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)), PieChartSectionData(value: (byType['general'] ?? 0).toDouble(), color: textGray, title: '${(((byType['general'] ?? 0) / total) * 100).toStringAsFixed(0)}%', radius: 85, titleStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white))], sectionsSpace: 3, centerSpaceRadius: 45))),
          const SizedBox(height: 24),
          Wrap(spacing: 20, runSpacing: 12, children: [_buildLegendItem('Suggestions', primaryBlue, byType['suggestion'] ?? 0), _buildLegendItem('Complaints', dangerRed, byType['complaint'] ?? 0), _buildLegendItem('Appreciation', const Color(0xFFEC4899), byType['appreciation'] ?? 0), _buildLegendItem('General', textGray, byType['general'] ?? 0)])
        ],
      ),
    );
  }
  
  Widget _buildLegendItem(String label, Color color, int value) {
    return Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 14, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))), const SizedBox(width: 8), Text('$label: $value', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: darkText))]);
  }
  
  // ============================================================================
  // FEEDBACK TABLE - UPDATED TO HORIZONTAL SCROLLABLE DATA TABLE
  // ============================================================================
  
  Widget _buildFeedbackTable(List<Map<String, dynamic>> feedbacks, {required bool isAdmin}) {
    if (feedbacks.isEmpty) {
      return Container(margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.all(40), decoration: BoxDecoration(color: cardWhite, borderRadius: BorderRadius.circular(20), border: Border.all(color: borderGray, width: 2)), child: Column(children: [Icon(Icons.inbox, size: 64, color: borderGray.withOpacity(0.5)), const SizedBox(height: 16), const Text('No feedback found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText)), const SizedBox(height: 8), Text(isAdmin ? 'No feedback matches your filters.' : 'Be the first to share your thoughts!', style: const TextStyle(color: textGray, fontSize: 14))]));
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: cardWhite, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(padding: const EdgeInsets.all(20), decoration: const BoxDecoration(gradient: LinearGradient(colors: [primaryBlue, primaryPurple]), borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))), child: Row(children: const [Icon(Icons.feedback, color: Colors.white, size: 24), SizedBox(width: 12), Text('Feedback Management', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))])),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: borderGray),
              child: DataTable(
                headingRowColor: MaterialStateProperty.all(lightBg),
                dataRowHeight: 80,
                horizontalMargin: 20,
                columnSpacing: 20,
                columns: [
                  const DataColumn(label: Text('SOURCE', style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(label: Text('TYPE', style: TextStyle(fontWeight: FontWeight.bold))),
                  if (isAdmin) const DataColumn(label: Text('SUBMITTER', style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(label: Text('DATE', style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(label: Text('SUBJECT/MESSAGE', style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(label: Text('RATING', style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(label: Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(label: Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: feedbacks.map((feedback) => _buildFeedbackDataRow(feedback, isAdmin)).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  DataRow _buildFeedbackDataRow(Map<String, dynamic> feedback, bool isAdmin) {
    final hasTicket = feedback['ticketNumber'] != null && feedback['ticketNumber'].toString().isNotEmpty;
    final ticketStatus = feedback['ticketStatus']?.toString().toLowerCase() ?? '';
    Color? rowColor;
    if (hasTicket) {
      if (['closed', 'resolved', 'completed'].contains(ticketStatus)) { rowColor = successGreen.withOpacity(0.05); }
      else { rowColor = warningOrange.withOpacity(0.05); }
    }

    return DataRow(
      color: MaterialStateProperty.all(rowColor),
      cells: [
        DataCell(Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: _getSourceColor(feedback['source']), borderRadius: BorderRadius.circular(8)), child: Text(_formatSource(feedback['source'] ?? ''), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)))),
        DataCell(Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: _getTypeColor(feedback['feedbackType']), borderRadius: BorderRadius.circular(8)), child: Text(_formatType(feedback['feedbackType'] ?? ''), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)))),
        if (isAdmin) DataCell(Text(feedback['submitterName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
        DataCell(Text(_formatDate(feedback['dateSubmitted']))),
        DataCell(Container(width: 250, child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(feedback['subject'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis), Text(_truncateText(feedback['message'] ?? '', 50), style: const TextStyle(fontSize: 11, color: textGray))]))),
        DataCell(Row(children: List.generate(5, (i) => Icon(i < (feedback['rating'] ?? 0) ? Icons.star : Icons.star_border, color: warningOrange, size: 16)))),
        DataCell(Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: feedback['hasConversation'] == true ? successGreen : warningOrange, borderRadius: BorderRadius.circular(8)), child: Text(feedback['hasConversation'] == true ? 'Responded' : 'Pending', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))),
        DataCell(Row(children: [
          IconButton(icon: const Icon(Icons.chat_bubble_outline, color: primaryBlue), onPressed: () => _openConversation(feedback['id'].toString())),
          if (isAdmin) 
            hasTicket 
              ? Tooltip(message: 'Ticket #$ticketStatus', child: const Icon(Icons.confirmation_number, color: warningOrange))
              : IconButton(icon: const Icon(Icons.assignment_outlined, color: primaryPurple), onPressed: () => _createTicket(feedback['id'].toString(), feedback))
        ])),
      ],
    );
  }
  
  Color _getSourceColor(String? source) {
    switch (source?.toLowerCase()) {
      case 'customers': return primaryBlue;
      case 'drivers': return successGreen;
      case 'clients': return warningOrange;
      case 'employee_admins': return primaryPurple;
      default: return textGray;
    }
  }
  
  Color _getTypeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'suggestion': return primaryBlue;
      case 'complaint': return dangerRed;
      case 'appreciation': return const Color(0xFFEC4899);
      default: return textGray;
    }
  }
  
  String _formatSource(String source) {
    switch (source.toLowerCase()) {
      case 'customers': return 'Customer';
      case 'drivers': return 'Driver';
      case 'clients': return 'Client';
      case 'employee_admins': return 'Admin';
      default: return source;
    }
  }
  
  String _formatType(String type) => type.isEmpty ? '' : type[0].toUpperCase() + type.substring(1);
  
  Widget _buildPagination() {
    final currentPage = _pagination['currentPage'] ?? 1;
    final totalPages = _pagination['totalPages'] ?? 1;
    return Container(margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Container(decoration: BoxDecoration(gradient: currentPage > 1 ? const LinearGradient(colors: [primaryBlue, primaryPurple]) : null, color: currentPage > 1 ? null : borderGray, borderRadius: BorderRadius.circular(12)), child: IconButton(onPressed: currentPage > 1 ? () { setState(() { _currentPage = currentPage - 1; }); _loadAllFeedbacks(); } : null, icon: const Icon(Icons.chevron_left, color: Colors.white))), const SizedBox(width: 20), Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), decoration: BoxDecoration(color: cardWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: primaryBlue, width: 2)), child: Text('Page $currentPage of $totalPages', style: const TextStyle(fontWeight: FontWeight.bold, color: primaryBlue, fontSize: 14))), const SizedBox(width: 20), Container(decoration: BoxDecoration(gradient: currentPage < totalPages ? const LinearGradient(colors: [primaryBlue, primaryPurple]) : null, color: currentPage < totalPages ? null : borderGray, borderRadius: BorderRadius.circular(12)), child: IconButton(onPressed: currentPage < totalPages ? () { setState(() { _currentPage = currentPage + 1; }); _loadAllFeedbacks(); } : null, icon: const Icon(Icons.chevron_right, color: Colors.white)))]));
  }
  
  Widget _buildPersonalSectionDivider() {
    return Container(margin: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: [Container(height: 4, decoration: BoxDecoration(gradient: const LinearGradient(colors: [primaryBlue, primaryPurple]), borderRadius: BorderRadius.circular(2)), ), const SizedBox(height: 12), Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), decoration: BoxDecoration(gradient: const LinearGradient(colors: [primaryBlue, primaryPurple]), borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: primaryBlue.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))]), child: const Text('MY PERSONAL FEEDBACK', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.5)))]));
  }
  
  Widget _buildPersonalStatistics() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(children: [
        Row(children: [Expanded(child: _buildStatCard('Total', _myStatistics['totalCount'] ?? 0, Icons.chat_bubble, primaryBlue)), const SizedBox(width: 12), Expanded(child: _buildStatCard('Responded', _myStatistics['respondedCount'] ?? 0, Icons.check_circle, successGreen))]),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: _buildStatCard('Pending', _myStatistics['pendingCount'] ?? 0, Icons.access_time, warningOrange)), const SizedBox(width: 12), const Expanded(child: SizedBox())])
      ]),
    );
  }
  
  Widget _buildPersonalFilters() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: cardWhite, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))]),
      child: Row(children: [
        Expanded(child: InkWell(onTap: () async { final date = await showDatePicker(context: context, initialDate: _myDateFrom != null ? DateTime.parse(_myDateFrom!) : DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now()); if (date != null) { setState(() { _myDateFrom = DateFormat('yyyy-MM-dd').format(date); }); } }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderGray)), child: Row(children: [const Icon(Icons.calendar_today, size: 16, color: primaryBlue), const SizedBox(width: 8), Expanded(child: Text(_myDateFrom ?? 'From Date', style: TextStyle(fontSize: 14, color: _myDateFrom != null ? darkText : textGray)))])))),
        const SizedBox(width: 12),
        Expanded(child: InkWell(onTap: () async { final date = await showDatePicker(context: context, initialDate: _myDateTo != null ? DateTime.parse(_myDateTo!) : DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now()); if (date != null) { setState(() { _myDateTo = DateFormat('yyyy-MM-dd').format(date); }); } }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderGray)), child: Row(children: [const Icon(Icons.calendar_today, size: 16, color: primaryPurple), const SizedBox(width: 8), Expanded(child: Text(_myDateTo ?? 'To Date', style: TextStyle(fontSize: 14, color: _myDateTo != null ? darkText : textGray)))])))),
        const SizedBox(width: 12),
        Container(height: 50, width: 50, decoration: BoxDecoration(gradient: const LinearGradient(colors: [primaryBlue, primaryPurple]), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: primaryBlue.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]), child: IconButton(onPressed: _applyPersonalFilters, icon: const Icon(Icons.filter_list, color: Colors.white)))
      ]),
    );
  }
  
  Widget _buildSubmitFeedbackForm() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: cardWhite, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [Icon(Icons.edit, color: primaryBlue, size: 24), SizedBox(width: 12), Text('Submit New Feedback', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText))]),
        const SizedBox(height: 20),
        Container(decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderGray)), child: DropdownButtonFormField<String>(dropdownColor: cardWhite, style: const TextStyle(color: darkText, fontSize: 14), decoration: const InputDecoration(labelText: 'Feedback Type *', labelStyle: TextStyle(color: textGray, fontSize: 13), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12)), hint: const Text('Select Type'), items: const [DropdownMenuItem(value: 'suggestion', child: Text('💡 Suggestion')), DropdownMenuItem(value: 'complaint', child: Text('⚠️ Complaint')), DropdownMenuItem(value: 'general', child: Text('📝 General Feedback')), DropdownMenuItem(value: 'appreciation', child: Text('🎉 Appreciation'))], onChanged: (value) { _feedbackTypeController.text = value ?? ''; })),
        const SizedBox(height: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Rating *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: darkText)), const SizedBox(height: 8), Row(children: List.generate(5, (i) => IconButton(onPressed: () => setState(() => _selectedRating = i + 1), icon: Icon(i < _selectedRating ? Icons.star : Icons.star_border, color: warningOrange, size: 36))))]),
        const SizedBox(height: 16),
        Container(decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderGray)), child: TextField(controller: _subjectController, style: const TextStyle(color: darkText), decoration: const InputDecoration(labelText: 'Subject *', labelStyle: TextStyle(color: textGray, fontSize: 13), hintText: 'Brief subject', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12)))),
        const SizedBox(height: 16),
        Container(decoration: BoxDecoration(color: lightBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderGray)), child: TextField(controller: _messageController, maxLines: 5, style: const TextStyle(color: darkText), decoration: const InputDecoration(labelText: 'Message *', labelStyle: TextStyle(color: textGray, fontSize: 13), hintText: 'Provide detailed feedback', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12)))),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, height: 54, child: Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: [primaryBlue, primaryPurple]), borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: primaryBlue.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))]), child: ElevatedButton.icon(onPressed: _submitFeedback, icon: const Icon(Icons.send, color: Colors.white, size: 20), label: const Text('Submit Feedback', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))))
      ]),
    );
  }
}