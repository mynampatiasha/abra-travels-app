import 'package:flutter/material.dart';

const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kDangerColor = Color(0xFFC62828);
const Color kDangerBgColor = Color(0xFFFFEBEE);
const Color kSecondaryTextColor = Color(0xFF757575);
const Color kSuccessColor = Color(0xFF2E7D32);
const Color kWarningColor = Color(0xFFF57C00);
const Color kInfoColor = Color(0xFF0288D1);

class ComplianceManagementScreen extends StatefulWidget {
  const ComplianceManagementScreen({super.key});

  @override
  State<ComplianceManagementScreen> createState() =>
      _ComplianceManagementScreenState();
}

class _ComplianceManagementScreenState extends State<ComplianceManagementScreen> {
  List<Widget> _overlayStack = [];

  void _pushOverlay(Widget overlay) {
    setState(() {
      _overlayStack.add(overlay);
    });
  }

  void _popOverlay() {
    if (_overlayStack.isNotEmpty) {
      setState(() {
        _overlayStack.removeLast();
      });
    }
  }

  void _clearAllOverlays() {
    setState(() {
      _overlayStack.clear();
    });
  }

  void _showSnackBar(String message, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showUploadDocumentsScreen() {
    _pushOverlay(
      _buildOverlayWrapper(
        title: 'Upload Documents',
        child: UploadDocumentsScreen(onBack: _popOverlay),
      ),
    );
  }

  void _showSetRemindersScreen() {
    _pushOverlay(
      _buildOverlayWrapper(
        title: 'Set Reminders',
        child: SetRemindersScreen(onBack: _popOverlay),
      ),
    );
  }

  void _showComplianceReportScreen() {
    _pushOverlay(
      _buildOverlayWrapper(
        title: 'Compliance Report',
        child: ComplianceReportScreen(onBack: _popOverlay),
      ),
    );
  }

  void _showSendAlertsScreen() {
    _pushOverlay(
      _buildOverlayWrapper(
        title: 'Send Alerts',
        child: SendAlertsScreen(onBack: _popOverlay),
      ),
    );
  }

  Widget _buildOverlayWrapper({
    required String title,
    required Widget child,
  }) {
    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.95,
          height: MediaQuery.of(context).size.height * 0.90,
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _popOverlay,
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      title == 'Upload Documents'
                          ? Icons.upload_file_rounded
                          : title == 'Set Reminders'
                              ? Icons.notifications_active_rounded
                              : title == 'Compliance Report'
                                  ? Icons.assessment_rounded
                                  : Icons.email_rounded,
                      color: kPrimaryColor,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _clearAllOverlays,
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.grey[100],
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBreadcrumb(),
                const SizedBox(height: 20),
                Card(
                  elevation: 4.0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(25.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildCardHeader(),
                        const SizedBox(height: 8),
                        const Text(
                          'Route: /admin/vehicle-management/compliance',
                          style: TextStyle(color: kSecondaryTextColor, fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 24),
                        _buildAlertBox(),
                        const SizedBox(height: 24),
                        _buildActionButtons(),
                        const SizedBox(height: 30),
                        _buildDashboardGrid(),
                        const SizedBox(height: 30),
                        _buildKeyFeatures(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ..._overlayStack,
      ],
    );
  }

  Widget _buildBreadcrumb() {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        const Text(
          'Vehicle Management',
          style: TextStyle(fontSize: 16, color: Colors.blueAccent),
        ),
        const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
        Text(
          'Compliance Management',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: kPrimaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildCardHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: kPrimaryColor, size: 28),
            const SizedBox(width: 12),
            const Text(
              'Compliance Management',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Divider(color: Colors.grey.shade300),
      ],
    );
  }

  Widget _buildAlertBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kDangerBgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: kDangerColor, width: 5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: kDangerColor, size: 24),
              const SizedBox(width: 10),
              const Text(
                'Critical Compliance Alerts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildFeatureListItem(
            text: '2 vehicles with expiring insurance (within 30 days)',
            color: kDangerColor,
          ),
          _buildFeatureListItem(
            text: '1 PUC certificate expired (immediate action required)',
            color: kDangerColor,
          ),
          _buildFeatureListItem(
            text: '3 permit renewals due this month',
            color: kDangerColor,
            hasDivider: false,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildActionButton(
          icon: Icons.upload_file_rounded,
          label: 'Upload Documents',
          onPressed: _showUploadDocumentsScreen,
          color: kPrimaryColor,
        ),
        _buildActionButton(
          icon: Icons.notifications_active_rounded,
          label: 'Set Reminders',
          onPressed: _showSetRemindersScreen,
          color: kWarningColor,
        ),
        _buildActionButton(
          icon: Icons.assessment_rounded,
          label: 'Compliance Report',
          onPressed: _showComplianceReportScreen,
          color: kInfoColor,
        ),
        _buildActionButton(
          icon: Icons.email_rounded,
          label: 'Send Alerts',
          onPressed: _showSendAlertsScreen,
          color: kSuccessColor,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildDashboardGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 2 : 1;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
          childAspectRatio: 2.5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildMetricCard('87%', 'Compliance Score', kPrimaryColor),
            _buildMetricCard('5', 'Documents Expiring', kPrimaryColor),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard(String number, String label, Color primaryColor) {
    return GestureDetector(
      onTap: () {
        _showSnackBar('$label: $number', kPrimaryColor);
      },
      child: Card(
        elevation: 2.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                number,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: kSecondaryTextColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeyFeatures() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Compliance Features:',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        _buildFeatureListItem(
          text: 'Automated document expiry tracking and alerts',
          color: kPrimaryColor,
        ),
        _buildFeatureListItem(
          text: 'Digital document storage and management',
          color: kPrimaryColor,
        ),
        _buildFeatureListItem(
          text: 'Compliance scoring and risk assessment',
          color: kPrimaryColor,
        ),
        _buildFeatureListItem(
          text: 'Renewal reminder system with notifications',
          color: kPrimaryColor,
          hasDivider: false,
        ),
      ],
    );
  }

  Widget _buildFeatureListItem({required String text, required Color color, bool hasDivider = true}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.arrow_right, color: color, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: const TextStyle(fontSize: 16, height: 1.4)),
              ),
            ],
          ),
        ),
        if (hasDivider) Divider(height: 1, color: Colors.grey.shade200),
      ],
    );
  }
}

// ============ UPLOAD DOCUMENTS SCREEN ============
class UploadDocumentsScreen extends StatefulWidget {
  final VoidCallback onBack;
  const UploadDocumentsScreen({required this.onBack, Key? key}) : super(key: key);

  @override
  State<UploadDocumentsScreen> createState() => _UploadDocumentsScreenState();
}

class _UploadDocumentsScreenState extends State<UploadDocumentsScreen> {
  final List<String> _documentTypes = ['Insurance', 'PUC', 'Permit', 'Registration', 'Pollution Certificate'];
  String? _selectedType;
  String? _selectedFile;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Document Type', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              isExpanded: true,
              hint: const Text('Select document type'),
              value: _selectedType,
              onChanged: (String? value) => setState(() => _selectedType = value),
              items: _documentTypes
                  .map((type) => DropdownMenuItem<String>(
                        value: type,
                        child: Text(type),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey.shade50,
            ),
            child: Column(
              children: [
                Icon(Icons.cloud_upload_rounded, size: 48, color: kPrimaryColor),
                const SizedBox(height: 12),
                const Text('Drag and drop or click to upload', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('PDF, JPG, PNG (Max 5MB)', style: TextStyle(fontSize: 12, color: kSecondaryTextColor)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_rounded),
              label: const Text('Upload Document'),
              onPressed: () {
                if (_selectedType != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Document uploaded: $_selectedType'),
                      backgroundColor: kSuccessColor,
                    ),
                  );
                  widget.onBack();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============ SET REMINDERS SCREEN ============
class SetRemindersScreen extends StatefulWidget {
  final VoidCallback onBack;
  const SetRemindersScreen({required this.onBack, Key? key}) : super(key: key);

  @override
  State<SetRemindersScreen> createState() => _SetRemindersScreenState();
}

class _SetRemindersScreenState extends State<SetRemindersScreen> {
  final List<String> _vehicles = ['KA01AB1234', 'KA02CD5678', 'KA03EF9012'];
  final List<String> _documentTypes = ['Insurance', 'PUC', 'Permit'];
  String? _selectedVehicle;
  String? _selectedDoc;
  DateTime? _reminderDate;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select Vehicle', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              isExpanded: true,
              hint: const Text('Choose vehicle'),
              value: _selectedVehicle,
              onChanged: (String? value) => setState(() => _selectedVehicle = value),
              items: _vehicles
                  .map((v) => DropdownMenuItem<String>(value: v, child: Text(v)))
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Document Type', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _documentTypes
                .map((doc) => FilterChip(
                      label: Text(doc),
                      selected: _selectedDoc == doc,
                      onSelected: (selected) => setState(() => _selectedDoc = selected ? doc : null),
                      selectedColor: kPrimaryColor,
                      labelStyle: TextStyle(color: _selectedDoc == doc ? Colors.white : null),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          const Text('Reminder Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _reminderDate = picked);
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: kPrimaryColor),
                  const SizedBox(width: 12),
                  Text(_reminderDate != null
                      ? '${_reminderDate!.day}/${_reminderDate!.month}/${_reminderDate!.year}'
                      : 'Select Date'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_rounded),
              label: const Text('Set Reminder'),
              onPressed: () {
                if (_selectedVehicle != null && _selectedDoc != null && _reminderDate != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Reminder set for $_selectedDoc on ${_reminderDate!.day}/${_reminderDate!.month}'),
                      backgroundColor: kSuccessColor,
                    ),
                  );
                  widget.onBack();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============ COMPLIANCE REPORT SCREEN ============
class ComplianceReportScreen extends StatelessWidget {
  final VoidCallback onBack;
  const ComplianceReportScreen({required this.onBack, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Compliance Report', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kInfoColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Overall Compliance: 87%', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('Fleet Status: Good', style: TextStyle(color: kSecondaryTextColor)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Vehicle Compliance Status', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildComplianceItem('KA01AB1234', 95, kSuccessColor),
          const SizedBox(height: 8),
          _buildComplianceItem('KA02CD5678', 78, kWarningColor),
          const SizedBox(height: 8),
          _buildComplianceItem('KA03EF9012', 85, kSuccessColor),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.download_rounded),
              label: const Text('Download Report'),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Report downloaded!'),
                    backgroundColor: kSuccessColor,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComplianceItem(String vehicle, int score, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(vehicle, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('$score%', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ============ SEND ALERTS SCREEN ============
class SendAlertsScreen extends StatefulWidget {
  final VoidCallback onBack;
  const SendAlertsScreen({required this.onBack, Key? key}) : super(key: key);

  @override
  State<SendAlertsScreen> createState() => _SendAlertsScreenState();
}

class _SendAlertsScreenState extends State<SendAlertsScreen> {
  final TextEditingController _messageController = TextEditingController();
  String _recipientType = 'all_drivers';
  String _priority = 'normal';

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Alert Type', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['Compliance', 'Reminder', 'Urgent', 'General']
                .map((type) => Chip(label: Text(type)))
                .toList(),
          ),
          const SizedBox(height: 16),
          const Text('Recipients', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['All Drivers', 'Managers', 'Selected']
                .map((recipient) => FilterChip(
                      label: Text(recipient),
                      selected: _recipientType == recipient.toLowerCase().replaceAll(' ', '_'),
                      onSelected: (selected) => setState(() =>
                          _recipientType = recipient.toLowerCase().replaceAll(' ', '_')),
                      selectedColor: kPrimaryColor,
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          const Text('Priority', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['Low', 'Normal', 'High', 'Urgent']
                .map((p) => FilterChip(
                      label: Text(p),
                      selected: _priority == p.toLowerCase(),
                      onSelected: (selected) =>
                          setState(() => _priority = p.toLowerCase()),
                      selectedColor: kWarningColor,
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          const Text('Message', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _messageController,
            decoration: InputDecoration(
              hintText: 'Enter alert message',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            maxLines: 4,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send Alert'),
              onPressed: () {
                if (_messageController.text.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Alert sent successfully!'),
                      backgroundColor: kSuccessColor,
                    ),
                  );
                  widget.onBack();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kSuccessColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}