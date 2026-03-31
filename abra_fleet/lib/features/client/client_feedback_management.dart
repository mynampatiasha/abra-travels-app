// lib/features/client/client_feedback_management.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../hrm_feedback/domain/models/hrm_feedback_model.dart';
import '../../core/services/hrm_feedback_service.dart';

class ClientFeedbackManagement extends StatefulWidget {
  final String? userName;
  final String? userEmail;

  const ClientFeedbackManagement({
    Key? key,
    this.userName,
    this.userEmail,
  }) : super(key: key);

  @override
  State<ClientFeedbackManagement> createState() => _ClientFeedbackManagementState();
}

class _ClientFeedbackManagementState extends State<ClientFeedbackManagement>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _feedbackService = HRMFeedbackService();
  
  // Form fields for customer feedback
  final _customerFormKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _customerSubjectController = TextEditingController();
  final _customerMessageController = TextEditingController();
  String _customerSelectedType = 'general';
  int _customerSelectedRating = 5;
  
  // Form fields for driver feedback
  final _driverFormKey = GlobalKey<FormState>();
  final _driverNameController = TextEditingController();
  final _driverSubjectController = TextEditingController();
  final _driverMessageController = TextEditingController();
  String _driverSelectedType = 'general';
  int _driverSelectedRating = 5;
  
  // State management
  bool _isSubmittingCustomer = false;
  bool _isSubmittingDriver = false;
  bool _isLoadingCustomer = false;
  bool _isLoadingDriver = false;
  List<HrmFeedbackModel> _customerFeedbackList = [];
  List<HrmFeedbackModel> _driverFeedbackList = [];
  String _viewMode = 'grid'; // 'grid' or 'table'
  
  // Modal state
  HrmFeedbackModel? _selectedFeedback;
  final _replyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _customerNameController.text = widget.userName ?? '';
    _driverNameController.text = widget.userName ?? '';
    _loadAllFeedback();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customerNameController.dispose();
    _customerSubjectController.dispose();
    _customerMessageController.dispose();
    _driverNameController.dispose();
    _driverSubjectController.dispose();
    _driverMessageController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadAllFeedback() async {
    await Future.wait([
      _loadCustomerFeedback(),
      _loadDriverFeedback(),
    ]);
  }

  Future<void> _loadCustomerFeedback() async {
    setState(() => _isLoadingCustomer = true);
    
    final result = await _feedbackService.getAllFeedback('customer');
    
    setState(() {
      _customerFeedbackList = result;
      _isLoadingCustomer = false;
    });
  }

  Future<void> _loadDriverFeedback() async {
    setState(() => _isLoadingDriver = true);
    
    final result = await _feedbackService.getAllFeedback('driver');
    
    setState(() {
      _driverFeedbackList = result;
      _isLoadingDriver = false;
    });
  }

  Future<void> _submitCustomerFeedback() async {
    if (!_customerFormKey.currentState!.validate()) return;

    setState(() => _isSubmittingCustomer = true);

    final result = await _feedbackService.submitCustomerFeedback(
      customerName: _customerNameController.text.trim(),
      feedbackType: _customerSelectedType,
      subject: _customerSubjectController.text.trim(),
      message: _customerMessageController.text.trim(),
      rating: _customerSelectedRating,
    );

    setState(() => _isSubmittingCustomer = false);

    if (result['success']) {
      _showSnackBar(result['message'], Colors.green);
      
      // Clear form
      _customerSubjectController.clear();
      _customerMessageController.clear();
      setState(() {
        _customerSelectedType = 'general';
        _customerSelectedRating = 5;
      });
      
      // Reload feedback
      _loadCustomerFeedback();
    } else {
      _showSnackBar(result['message'], Colors.red);
    }
  }

  Future<void> _submitDriverFeedback() async {
    if (!_driverFormKey.currentState!.validate()) return;

    setState(() => _isSubmittingDriver = true);

    final result = await _feedbackService.submitDriverFeedback(
      driverName: _driverNameController.text.trim(),
      feedbackType: _driverSelectedType,
      subject: _driverSubjectController.text.trim(),
      message: _driverMessageController.text.trim(),
      rating: _driverSelectedRating,
    );

    setState(() => _isSubmittingDriver = false);

    if (result['success']) {
      _showSnackBar(result['message'], Colors.green);
      
      // Clear form
      _driverSubjectController.clear();
      _driverMessageController.clear();
      setState(() {
        _driverSelectedType = 'general';
        _driverSelectedRating = 5;
      });
      
      // Reload feedback
      _loadDriverFeedback();
    } else {
      _showSnackBar(result['message'], Colors.red);
    }
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
      body: Column(
        children: [
          // Header Card
          _buildHeaderCard(),
          const SizedBox(height: 20),
          
          // Tab Bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFe2e8f0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: const Color(0xFF3b82f6),
                borderRadius: BorderRadius.circular(8),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: const Color(0xFF64748b),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.people, size: 18),
                      const SizedBox(width: 8),
                      const Text('Customer Feedback'),
                      if (_customerFeedbackList.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_customerFeedbackList.length}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.drive_eta, size: 18),
                      const SizedBox(width: 8),
                      const Text('Driver Feedback'),
                      if (_driverFeedbackList.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_driverFeedbackList.length}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Customer Feedback Tab
                _buildCustomerFeedbackTab(),
                
                // Driver Feedback Tab
                _buildDriverFeedbackTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      margin: const EdgeInsets.all(20),
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
            Icons.feedback_rounded,
            size: 48,
            color: Colors.white,
          ),
          const SizedBox(height: 12),
          const Text(
            'Feedback Management',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Manage customer and driver feedback efficiently',
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

  Widget _buildCustomerFeedbackTab() {
    return RefreshIndicator(
      onRefresh: _loadCustomerFeedback,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Submit Customer Feedback Form
            _buildCustomerFeedbackForm(),
            const SizedBox(height: 20),
            
            // Customer Feedback History
            _buildCustomerFeedbackHistory(),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverFeedbackTab() {
    return RefreshIndicator(
      onRefresh: _loadDriverFeedback,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Submit Driver Feedback Form
            _buildDriverFeedbackForm(),
            const SizedBox(height: 20),
            
            // Driver Feedback History
            _buildDriverFeedbackHistory(),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerFeedbackForm() {
    return _buildFeedbackForm(
      formKey: _customerFormKey,
      nameController: _customerNameController,
      subjectController: _customerSubjectController,
      messageController: _customerMessageController,
      selectedType: _customerSelectedType,
      selectedRating: _customerSelectedRating,
      isSubmitting: _isSubmittingCustomer,
      onTypeChanged: (value) => setState(() => _customerSelectedType = value!),
      onRatingChanged: (rating) => setState(() => _customerSelectedRating = rating),
      onSubmit: _submitCustomerFeedback,
      title: 'Submit Customer Feedback',
      icon: Icons.people,
    );
  }

  Widget _buildDriverFeedbackForm() {
    return _buildFeedbackForm(
      formKey: _driverFormKey,
      nameController: _driverNameController,
      subjectController: _driverSubjectController,
      messageController: _driverMessageController,
      selectedType: _driverSelectedType,
      selectedRating: _driverSelectedRating,
      isSubmitting: _isSubmittingDriver,
      onTypeChanged: (value) => setState(() => _driverSelectedType = value!),
      onRatingChanged: (rating) => setState(() => _driverSelectedRating = rating),
      onSubmit: _submitDriverFeedback,
      title: 'Submit Driver Feedback',
      icon: Icons.drive_eta,
    );
  }

  Widget _buildCustomerFeedbackHistory() {
    return _buildFeedbackHistory(
      title: 'Customer Feedback History',
      icon: Icons.history,
      feedbackList: _customerFeedbackList,
      isLoading: _isLoadingCustomer,
      onRefresh: _loadCustomerFeedback,
    );
  }

  Widget _buildDriverFeedbackHistory() {
    return _buildFeedbackHistory(
      title: 'Driver Feedback History',
      icon: Icons.history,
      feedbackList: _driverFeedbackList,
      isLoading: _isLoadingDriver,
      onRefresh: _loadDriverFeedback,
    );
  }

  Widget _buildFeedbackForm({
    required GlobalKey<FormState> formKey,
    required TextEditingController nameController,
    required TextEditingController subjectController,
    required TextEditingController messageController,
    required String selectedType,
    required int selectedRating,
    required bool isSubmitting,
    required Function(String?) onTypeChanged,
    required Function(int) onRatingChanged,
    required VoidCallback onSubmit,
    required String title,
    required IconData icon,
  }) {
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
                Icon(icon, color: const Color(0xFF3b82f6), size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
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
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name Field
                  _buildTextField(
                    controller: nameController,
                    label: 'Name',
                    icon: Icons.person,
                    required: true,
                  ),
                  const SizedBox(height: 16),
                  
                  // Feedback Type
                  _buildDropdownField(
                    label: 'Feedback Type',
                    icon: Icons.category,
                    value: selectedType,
                    items: const [
                      {'value': 'general', 'label': 'General Feedback'},
                      {'value': 'appreciation', 'label': 'Appreciation'},
                      {'value': 'complaint', 'label': 'Complaint'},
                      {'value': 'suggestion', 'label': 'Suggestion'},
                    ],
                    onChanged: onTypeChanged,
                  ),
                  const SizedBox(height: 16),
                  
                  // Subject
                  _buildTextField(
                    controller: subjectController,
                    label: 'Subject',
                    icon: Icons.title,
                    required: true,
                  ),
                  const SizedBox(height: 16),
                  
                  // Message
                  _buildTextField(
                    controller: messageController,
                    label: 'Your Message',
                    icon: Icons.message,
                    required: true,
                    maxLines: 5,
                  ),
                  const SizedBox(height: 16),
                  
                  // Rating
                  _buildRatingSelector(selectedRating, onRatingChanged),
                  const SizedBox(height: 24),
                  
                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSubmitting ? null : onSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3b82f6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: isSubmitting
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

  Widget _buildRatingSelector(int selectedRating, Function(int) onRatingChanged) {
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
            final isSelected = selectedRating == rating;
            
            return InkWell(
              onTap: () => onRatingChanged(rating),
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

  Widget _buildFeedbackHistory({
    required String title,
    required IconData icon,
    required List<HrmFeedbackModel> feedbackList,
    required bool isLoading,
    required VoidCallback onRefresh,
  }) {
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
                Icon(icon, color: const Color(0xFF3b82f6), size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
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
                    '${feedbackList.length}',
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
                    IconButton(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh',
                      color: const Color(0xFF64748b),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // History Content
          isLoading
              ? const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              : feedbackList.isEmpty
                  ? _buildEmptyState()
                  : _viewMode == 'grid'
                      ? _buildGridView(feedbackList)
                      : _buildListView(feedbackList),
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
            'No feedback yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0f172a),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'No feedback has been submitted yet',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF64748b),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView(List<HrmFeedbackModel> feedbackList) {
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
        itemCount: feedbackList.length,
        itemBuilder: (context, index) {
          final feedback = feedbackList[index];
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
                      color: _getTypeColor(feedback.feedbackType).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      feedback.feedbackType.toUpperCase(),
                      style: TextStyle(
                        color: _getTypeColor(feedback.feedbackType),
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
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFe2e8f0)),
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
                        '• ${_formatDate(feedback.dateSubmitted)}',
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

  Widget _buildListView(List<HrmFeedbackModel> feedbackList) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      itemCount: feedbackList.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final feedback = feedbackList[index];
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
                    // Feedback Details
                    _buildMessageBubble(
                      isUser: true,
                      name: feedback.userName ?? 'User',
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
}