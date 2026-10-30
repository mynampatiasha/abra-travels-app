// ============================================================================
// lib/features/admin/otp_monitoring/otp_override_approval_screen.dart
// ADMIN — Override approval panel
// ✅ Photo full-view (tap to expand)
// ✅ Download proof photo button
// ✅ Driver name resolved (not raw ID)
// ✅ All override info displayed
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:universal_html/html.dart' as html;
import '../../../core/services/otp_service.dart';
import '../../../app/config/api_config.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _success    = Color(0xFF10B981);
const Color _warning    = Color(0xFFF59E0B);
const Color _danger     = Color(0xFFDC2626);

class OtpOverrideApprovalScreen extends StatefulWidget {
  final Map<String, dynamic> otpRecord;
  const OtpOverrideApprovalScreen({super.key, required this.otpRecord});

  @override
  State<OtpOverrideApprovalScreen> createState() => _OtpOverrideApprovalScreenState();
}

class _OtpOverrideApprovalScreenState extends State<OtpOverrideApprovalScreen> {
  final OtpService _otpService = OtpService();
  final TextEditingController _notesController = TextEditingController();
  bool _approving = false;
  bool _rejecting = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String _getPhotoUrl(String path) {
    if (path.startsWith('http')) return path;
    final base = ApiConfig.baseUrl.replaceAll(RegExp(r'/$'), '');
    return '$base$path';
  }

  void _downloadPhoto(String photoPath) {
    final url = _getPhotoUrl(photoPath);
    if (kIsWeb) {
      html.AnchorElement(href: url)
        ..setAttribute('download', 'override_proof_${DateTime.now().millisecondsSinceEpoch}.jpg')
        ..click();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo URL: $url'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  void _openPhotoFullView(String photoPath) {
    final url = _getPhotoUrl(photoPath);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PhotoFullViewScreen(
          photoUrl: url,
          onDownload: () => _downloadPhoto(photoPath),
        ),
      ),
    );
  }

  Future<void> _processOverride(bool approved) async {
    setState(() { if (approved) _approving = true; else _rejecting = true; });
    try {
      await _otpService.processOverride(
        tripGroupId: widget.otpRecord['tripGroupId']?.toString() ?? '',
        stopId: widget.otpRecord['stopId']?.toString() ?? '',
        passengerId: widget.otpRecord['passengerId']?.toString() ?? '',
        approved: approved,
        adminNotes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(approved ? '✅ Override approved' : '❌ Override rejected'),
          backgroundColor: approved ? _success : _danger,
          behavior: SnackBarBehavior.floating,
        ));
        Navigator.pop(context, approved);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'), backgroundColor: _danger, behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() { _approving = false; _rejecting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.otpRecord;
    final isWeb = MediaQuery.of(context).size.width > 700;
    final requestedAt = DateTime.tryParse(record['overrideRequestedAt']?.toString() ?? '')?.toLocal();
    final photoPath = record['overridePhoto']?.toString();
    final driverName  = record['driverName']?.toString()  ?? '';
    final driverPhone = record['driverPhone']?.toString() ?? '';
    final driverEmail = record['driverEmail']?.toString() ?? '';
    final driverCode  = record['driverCode']?.toString()  ?? '';
    final vehicleNumber = record['vehicleNumber']?.toString() ?? '';
    final vehicleModel  = record['vehicleModel']?.toString()  ?? '';
    final stopAddress   = record['stopAddress']?.toString()   ?? '';
    final tripNumber    = record['tripNumber']?.toString()    ?? '';
    final scheduledDate = record['scheduledDate']?.toString() ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _navyDark,
        foregroundColor: Colors.white,
        title: const Text('Override Approval', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isWeb ? 640 : double.infinity),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header
                _buildInfoCard(
                  icon: Icons.warning_amber_rounded,
                  iconColor: _warning,
                  title: 'Override Request',
                  subtitle: requestedAt != null
                      ? 'Requested at ${DateFormat('dd MMM yyyy, hh:mm a').format(requestedAt)}'
                      : 'Pending review',
                ),
                const SizedBox(height: 16),

                // ── Passenger details
                _buildSection('Passenger Details', [
                  _buildRow('Name', record['passengerName']?.toString() ?? '-'),
                  if ((record['companyName'] ?? '').toString().isNotEmpty)
                    _buildRow('Company', record['companyName'].toString()),
                  if ((record['employeeId'] ?? '').toString().isNotEmpty)
                    _buildRow('Employee ID', record['employeeId'].toString()),
                  _buildRow('Email', record['passengerEmail']?.toString() ?? '-'),
                  _buildRow('Phone', record['passengerPhone']?.toString() ?? '-'),
                  _buildRow('OTP Type', record['type'] == 'step_in' ? 'Step-In (Boarding)' : 'Step-Out (Drop-Off)'),
                  _buildRow('Failed Attempts', '${record['attempts'] ?? 0}/3'),
                ]),
                const SizedBox(height: 16),

                // ── Driver information
                _buildSection('Driver Information', [
                  _buildRow('Name', driverName.isNotEmpty ? driverName : '-'),
                  if (driverPhone.isNotEmpty) _buildRow('Phone', driverPhone),
                  if (driverEmail.isNotEmpty) _buildRow('Email', driverEmail),
                  if (driverCode.isNotEmpty)  _buildRow('Driver ID', driverCode),
                  if (vehicleNumber.isNotEmpty)
                    _buildRow('Vehicle Assigned', vehicleModel.isNotEmpty ? '$vehicleNumber ($vehicleModel)' : vehicleNumber),
                ]),
                const SizedBox(height: 16),

                // ── Trip details
                _buildSection('Trip Details', [
                  if (tripNumber.isNotEmpty)
                    _buildRow('Trip Number', tripNumber),
                  if (scheduledDate.isNotEmpty)
                    _buildRow('Trip Date', scheduledDate),
                  if (stopAddress.isNotEmpty)
                    _buildRow('Stop Location', stopAddress)
                  else
                    _buildRow('Stop ID', record['stopId']?.toString() ?? '-'),
                  if (vehicleNumber.isNotEmpty)
                    _buildRow('Vehicle', vehicleModel.isNotEmpty ? '$vehicleNumber ($vehicleModel)' : vehicleNumber),
                  _buildRow('Trip Group ID', record['tripGroupId']?.toString() ?? '-'),
                  if (requestedAt != null)
                    _buildRow('Requested At', DateFormat('dd MMM yyyy, hh:mm a').format(requestedAt)),
                ]),
                const SizedBox(height: 16),

                // ── Override reason
                _buildSection('Override Reason', [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _warning.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _warning.withOpacity(0.3)),
                    ),
                    child: Text(
                      record['overrideReason']?.toString() ?? 'No reason provided',
                      style: const TextStyle(color: _navyDark, fontSize: 14),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),

                // ── Proof photo with full-view + download
                if (photoPath != null && photoPath.isNotEmpty) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Proof Photo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _navyMid)),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
                        ),
                        child: Column(
                          children: [
                            // Photo with tap-to-expand
                            GestureDetector(
                              onTap: () => _openPhotoFullView(photoPath),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                    child: Image.network(
                                      _getPhotoUrl(photoPath),
                                      height: 220,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        height: 120,
                                        color: Colors.grey.shade100,
                                        child: const Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.broken_image, size: 40, color: Colors.grey),
                                              SizedBox(height: 8),
                                              Text('Photo unavailable', style: TextStyle(color: Colors.grey)),
                                            ],
                                          ),
                                        ),
                                      ),
                                      loadingBuilder: (_, child, progress) => progress == null
                                          ? child
                                          : Container(
                                              height: 120,
                                              alignment: Alignment.center,
                                              child: const CircularProgressIndicator(color: _navyLight),
                                            ),
                                    ),
                                  ),
                                  // Tap to expand hint
                                  Positioned(
                                    top: 8, right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.55),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.fullscreen, color: Colors.white, size: 14),
                                          SizedBox(width: 4),
                                          Text('Full View', style: TextStyle(color: Colors.white, fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Action buttons row
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _openPhotoFullView(photoPath),
                                      icon: const Icon(Icons.fullscreen, size: 16),
                                      label: const Text('Full View', style: TextStyle(fontSize: 12)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _navyLight,
                                        side: const BorderSide(color: _navyLight),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => _downloadPhoto(photoPath),
                                      icon: const Icon(Icons.download, size: 16, color: Colors.white),
                                      label: const Text('Download', style: TextStyle(fontSize: 12, color: Colors.white)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _navyMid,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        elevation: 0,
                                      ),
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
                  const SizedBox(height: 16),
                ],

                // ── Admin notes
                _buildSection('Admin Notes (optional)', [
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Add notes for this decision...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _navyLight.withOpacity(0.3))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navyLight, width: 1.5)),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),

                // ── Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _rejecting || _approving ? null : () => _processOverride(false),
                        icon: _rejecting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _danger))
                            : const Icon(Icons.close, size: 18),
                        label: const Text('Reject Override'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _danger,
                          side: const BorderSide(color: _danger),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _approving || _rejecting ? null : () => _processOverride(true),
                        icon: _approving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check, size: 18),
                        label: const Text('Approve Override'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({required IconData icon, required Color iconColor, required String title, required String subtitle}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _warning.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: _warning.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navyDark)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _navyMid)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(color: _navyDark, fontWeight: FontWeight.w500, fontSize: 13))),
        ],
      ),
    );
  }
}

// ============================================================================
// Full-screen photo viewer
// ============================================================================
class _PhotoFullViewScreen extends StatelessWidget {
  final String photoUrl;
  final VoidCallback onDownload;

  const _PhotoFullViewScreen({required this.photoUrl, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Proof Photo', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            onPressed: onDownload,
            tooltip: 'Download Photo',
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          minScale: 0.5,
          maxScale: 5.0,
          child: Image.network(
            photoUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('Photo unavailable', style: TextStyle(color: Colors.grey)),
              ],
            ),
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : const Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
        ),
      ),
    );
  }
}
