// ============================================================================
// lib/features/driver/screens/stop_otp_verification_screen.dart
// DRIVER — Per-stop passenger OTP verification screen
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import '../../../core/services/otp_service.dart';

// ── Color scheme (matches new_invoice.dart)
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _success    = Color(0xFF10B981);
const Color _warning    = Color(0xFFF59E0B);
const Color _danger     = Color(0xFFDC2626);

// Override reasons
const List<String> _overrideReasons = [
  'Customer phone dead',
  'No network on customer phone',
  'Customer refusing to share OTP',
  'Customer did not receive OTP',
  'Other',
];

class PassengerOTPState {
  final String passengerId;
  final String passengerName;
  final String passengerEmail;
  String otp;
  bool verified;
  int attempts;
  String overrideStatus; // none | requested | approved | rejected
  bool boardedForStepOut;
  bool noShow; // ← NEW: customer didn't arrive

  PassengerOTPState({
    required this.passengerId,
    required this.passengerName,
    this.passengerEmail = '',
    required this.otp,
    this.verified = false,
    this.attempts = 0,
    this.overrideStatus = 'none',
    this.boardedForStepOut = false,
    this.noShow = false,
  });
}

class StopOTPVerificationScreen extends StatefulWidget {
  final String tripGroupId;
  final String stopId;
  final String stopAddress;
  final List<Map<String, dynamic>> passengers;
  final String otpType; // 'step_in' or 'step_out'
  final VoidCallback? onAllVerified;

  const StopOTPVerificationScreen({
    super.key,
    required this.tripGroupId,
    required this.stopId,
    required this.stopAddress,
    required this.passengers,
    this.otpType = 'step_in',
    this.onAllVerified,
  });

  @override
  State<StopOTPVerificationScreen> createState() => _StopOTPVerificationScreenState();
}

class _StopOTPVerificationScreenState extends State<StopOTPVerificationScreen> {
  final OtpService _otpService = OtpService();
  final Map<String, TextEditingController> _otpControllers = {};
  final Map<String, bool> _loadingMap = {};

  late List<PassengerOTPState> _passengerStates;
  bool _isGenerating = true;

  @override
  void initState() {
    super.initState();
    _passengerStates = widget.passengers.map((p) => PassengerOTPState(
      passengerId: p['id']?.toString() ?? p['passengerId']?.toString() ?? '',
      passengerName: p['name']?.toString() ?? 'Passenger',
      passengerEmail: p['email']?.toString() ?? '',
      otp: p['otp']?.toString() ?? '',
    )).toList();

    for (final p in _passengerStates) {
      _otpControllers[p.passengerId] = TextEditingController();
    }

    // If Step-Out, OTPs are already generated during boarding. Skip generation.
    if (widget.otpType == 'step_out') {
      setState(() => _isGenerating = false);
    } else if (_passengerStates.any((p) => p.otp.isNotEmpty)) {
      setState(() => _isGenerating = false);
    } else {
      _generateOTPs();
    }
  }

  @override
  void dispose() {
    for (final c in _otpControllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _generateOTPs() async {
    try {
      final customers = widget.passengers.map((p) => {
        'id': p['id']?.toString() ?? p['passengerId']?.toString() ?? '',
        'name': p['name']?.toString() ?? '',
        'email': p['email']?.toString() ?? '',
        'phone': p['phone']?.toString() ?? '',
      }).toList();

      final otps = await _otpService.generateStepInOTPs(
        tripGroupId: widget.tripGroupId,
        stopId: widget.stopId,
        customers: customers,
      );

      setState(() {
        for (final otpData in otps) {
          final idx = _passengerStates.indexWhere(
            (p) => p.passengerId == otpData['passengerId']?.toString(),
          );
          if (idx != -1) {
            _passengerStates[idx].otp = otpData['otp']?.toString() ?? '';
            _passengerStates[idx].verified = otpData['verified'] == true;
            _passengerStates[idx].attempts = otpData['attempts'] is int ? otpData['attempts'] : 0;
            _passengerStates[idx].overrideStatus = otpData['overrideStatus']?.toString() ?? 'none';
          }
        }
        _isGenerating = false;
      });

      // Auto-check in case overrides were approved while dialog was closed
      _checkAllVerified();
    } catch (e) {
      setState(() => _isGenerating = false);
      if (mounted) {
        _showSnack('Failed to generate OTPs: $e', _danger);
      }
    }
  }

  Future<void> _verifyOTP(PassengerOTPState passenger) async {
    final entered = _otpControllers[passenger.passengerId]?.text.trim() ?? '';
    if (entered.length != 6) {
      _showSnack('Enter a 6-digit OTP', _warning);
      return;
    }

    setState(() => _loadingMap[passenger.passengerId] = true);

    try {
      final result = await _otpService.verifyOTP(
        tripGroupId: widget.tripGroupId,
        stopId: widget.stopId,
        passengerId: passenger.passengerId,
        otp: entered,
      );

      setState(() {
        passenger.attempts++;
        if (result['success'] == true) {
          passenger.verified = true;
          _otpControllers[passenger.passengerId]?.clear();
          _showSnack('✅ ${passenger.passengerName} verified!', _success);
          _checkAllVerified();
        } else {
          passenger.attempts = 3 - ((result['attemptsRemaining'] ?? 0) as num).toInt();
          _showSnack(result['message'] ?? 'Incorrect OTP', _danger);
        }
      });
    } catch (e) {
      _showSnack('Verification failed: $e', _danger);
    } finally {
      setState(() => _loadingMap[passenger.passengerId] = false);
    }
  }

  Future<void> _resendOTP(PassengerOTPState passenger) async {
    setState(() => _loadingMap['resend_${passenger.passengerId}'] = true);

    try {
      await _otpService.resendOTP(
        tripGroupId: widget.tripGroupId,
        stopId: widget.stopId,
        passengerId: passenger.passengerId,
      );

      setState(() {
        passenger.attempts = 0;
        _otpControllers[passenger.passengerId]?.clear();
      });

      _showSnack('New OTP sent to ${passenger.passengerName}', _success);
    } catch (e) {
      _showSnack('Failed to resend OTP: $e', _danger);
    } finally {
      setState(() => _loadingMap['resend_${passenger.passengerId}'] = false);
    }
  }

  Future<void> _requestOverride(PassengerOTPState passenger) async {
    String? selectedReason;
    XFile? pickedPhoto;
    Uint8List? photoPreviewBytes;

    final ImagePicker picker = ImagePicker();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _warning.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.warning_amber_rounded, color: _warning),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Override Request', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Passenger info
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _navyDark.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: _navyMid, size: 18),
                      const SizedBox(width: 8),
                      Text(passenger.passengerName,
                          style: const TextStyle(fontWeight: FontWeight.w600, color: _navyDark)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Reason dropdown — required
                const Text('Reason *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navyDark)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedReason,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    hintText: 'Select reason',
                  ),
                  items: _overrideReasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) => setDialogState(() => selectedReason = v),
                ),
                const SizedBox(height: 16),

                // Photo — REQUIRED
                const Text('Proof Photo *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navyDark)),
                const SizedBox(height: 6),
                const Text(
                  'A photo is required to submit an override request.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 8),

                // Photo preview
                if (photoPreviewBytes != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      photoPreviewBytes!,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Camera + File upload buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final img = await picker.pickImage(
                            source: ImageSource.camera,
                            imageQuality: 75,
                            maxWidth: 1200,
                          );
                          if (img != null) {
                            final bytes = await img.readAsBytes();
                            setDialogState(() {
                              pickedPhoto = img;
                              photoPreviewBytes = bytes;
                            });
                          }
                        },
                        icon: const Icon(Icons.camera_alt, size: 16),
                        label: const Text('Camera', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _navyLight,
                          side: const BorderSide(color: _navyLight),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final img = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 75,
                            maxWidth: 1200,
                          );
                          if (img != null) {
                            final bytes = await img.readAsBytes();
                            setDialogState(() {
                              pickedPhoto = img;
                              photoPreviewBytes = bytes;
                            });
                          }
                        },
                        icon: const Icon(Icons.upload_file, size: 16),
                        label: const Text('Upload', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _navyMid,
                          side: const BorderSide(color: _navyMid),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),

                // Validation hint
                if (pickedPhoto == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      '⚠️ Photo is required',
                      style: TextStyle(color: _danger, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: (selectedReason == null || pickedPhoto == null)
                  ? null // disabled until both are filled
                  : () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navyLight,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Submit Request'),
            ),
          ],
        ),
      ),
    ).then((confirmed) async {
      if (confirmed == true && selectedReason != null && pickedPhoto != null) {
        setState(() => _loadingMap['override_${passenger.passengerId}'] = true);
        try {
          await _otpService.requestOverride(
            tripGroupId: widget.tripGroupId,
            stopId: widget.stopId,
            passengerId: passenger.passengerId,
            reason: selectedReason!,
            photo: pickedPhoto!, // ← XFile, bytes-based, web-safe
          );
          setState(() => passenger.overrideStatus = 'requested');
          _showSnack('Override request sent to admin', _warning);
        } catch (e) {
          _showSnack('Failed to request override: $e', _danger);
        } finally {
          setState(() => _loadingMap['override_${passenger.passengerId}'] = false);
        }
      }
    });
  }

  Future<void> _boardPassenger(PassengerOTPState passenger) async {
    setState(() => _loadingMap['board_${passenger.passengerId}'] = true);
    try {
      await _otpService.boardPassenger(
        tripGroupId: widget.tripGroupId,
        stopId: widget.stopId,
        passengerId: passenger.passengerId,
      );
      setState(() => passenger.boardedForStepOut = true);
      _showSnack('${passenger.passengerName} marked as boarded. Drop-off OTP sent.', _success);
      _checkAllVerified();
    } catch (e) {
      _showSnack('Failed to mark as boarded: $e', _danger);
    } finally {
      setState(() => _loadingMap['board_${passenger.passengerId}'] = false);
    }
  }

  // ── No-Show: customer didn't arrive at pickup
  Future<void> _markNoShow(PassengerOTPState passenger) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.person_off, color: Colors.grey),
          SizedBox(width: 10),
          Text('Mark as No-Show?', style: TextStyle(fontSize: 16)),
        ]),
        content: Text(
          '${passenger.passengerName} will be marked as No-Show.\n\nThis means the customer did not arrive at the pickup point. Admin will be notified.',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Confirm No-Show'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loadingMap['noshow_${passenger.passengerId}'] = true);
    try {
      await _otpService.markNoShow(
        tripGroupId: widget.tripGroupId,
        stopId: widget.stopId,
        passengerId: passenger.passengerId,
        passengerName: passenger.passengerName,
        passengerEmail: passenger.passengerEmail,
      );
      setState(() {
        passenger.noShow = true;
        passenger.overrideStatus = 'no_show';
      });
      _showSnack('${passenger.passengerName} marked as No-Show. Admin notified.', Colors.grey.shade700);
      _checkAllVerified();
    } catch (e) {
      _showSnack('Failed to mark no-show: $e', _danger);
    } finally {
      setState(() => _loadingMap['noshow_${passenger.passengerId}'] = false);
    }
  }

  void _checkAllVerified() {
    final allDone = _passengerStates.every((p) {
      if (p.noShow) return true;
      if (widget.otpType == 'step_in') {
        return (p.verified || p.overrideStatus == 'approved') && p.boardedForStepOut;
      }
      return p.verified || p.overrideStatus == 'approved';
    });
    if (allDone) widget.onAllVerified?.call();
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  Color _statusColor(PassengerOTPState p) {
    if (p.noShow) return Colors.grey.shade600;
    if (p.verified || p.overrideStatus == 'approved') return _success;
    if (p.attempts >= 3 || p.overrideStatus == 'requested') return _warning;
    return _navyLight;
  }

  IconData _statusIcon(PassengerOTPState p) {
    if (p.noShow) return Icons.person_off;
    if (p.verified || p.overrideStatus == 'approved') return Icons.check_circle;
    if (p.overrideStatus == 'requested') return Icons.pending;
    if (p.attempts >= 3) return Icons.error;
    return Icons.person;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;
    final verified = _passengerStates.where(
      (p) => p.verified || p.overrideStatus == 'approved' || p.noShow,
    ).length;
    final total = _passengerStates.length;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7FA),
      ),
      child: Column(
        children: [
          // ── Navy gradient header
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_navyDark, _navyMid],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            padding: EdgeInsets.fromLTRB(16, isMobile ? 14 : 18, 16, isMobile ? 14 : 18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.otpType == 'step_in'
                        ? Icons.directions_bus
                        : Icons.flag_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.otpType == 'step_in'
                            ? 'Boarding Verification'
                            : 'Drop-Off Verification',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: isMobile ? 15 : 17,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.stopAddress,
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Text(
                    '$verified/$total Done',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),

          // ── Body
          Expanded(
            child: _isGenerating
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: _navyLight),
                        const SizedBox(height: 16),
                        Text(
                          'Generating OTPs and notifying passengers...',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _navyMid, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.all(isMobile ? 12 : 16),
                    itemCount: _passengerStates.length,
                    itemBuilder: (_, i) =>
                        _buildPassengerCard(_passengerStates[i], isMobile),
                  ),
          ),

          // ── Bottom bar
          _buildBottomBar(isMobile),
        ],
      ),
    );
  }

  Widget _buildPassengerCard(PassengerOTPState passenger, bool isMobile) {
    final isNoShow = passenger.noShow;
    final isVerified = passenger.verified || passenger.overrideStatus == 'approved';
    final isOverrideRequested = passenger.overrideStatus == 'requested';
    final maxAttemptsReached = passenger.attempts >= 3;
    final isLoading = _loadingMap[passenger.passengerId] == true;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _statusColor(passenger).withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _statusColor(passenger).withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _statusColor(passenger).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_statusIcon(passenger), color: _statusColor(passenger), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        passenger.passengerName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _navyDark),
                      ),
                      const SizedBox(height: 2),
                      _buildStatusBadge(passenger),
                    ],
                  ),
                ),
                if (!isVerified)
                  Text(
                    '${passenger.attempts}/3',
                    style: TextStyle(
                      color: passenger.attempts >= 2 ? _danger : _navyMid,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),

            if (isVerified) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _success.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: _success, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      passenger.overrideStatus == 'approved' ? 'Override Approved' : 'OTP Verified ✓',
                      style: const TextStyle(color: _success, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),              // Show "Board" button for step_in verified passengers
              if (widget.otpType == 'step_in' && !passenger.boardedForStepOut) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _loadingMap['board_${passenger.passengerId}'] == true
                        ? null
                        : () => _boardPassenger(passenger),
                    icon: _loadingMap['board_${passenger.passengerId}'] == true
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.directions_bus, size: 18),
                    label: const Text('Mark as Boarded'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _navyMid,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
              if (passenger.boardedForStepOut)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _navyAccent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.directions_bus, color: _navyAccent, size: 16),
                      SizedBox(width: 6),
                      Text('Boarded — Drop-off OTP sent', style: TextStyle(color: _navyAccent, fontSize: 12)),
                    ],
                  ),
                ),
            ] else if (isOverrideRequested) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _warning.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.pending, color: _warning, size: 18),
                    SizedBox(width: 8),
                    Expanded(child: Text('Override request sent — awaiting admin approval', style: TextStyle(color: _warning, fontSize: 12))),
                  ],
                ),
              ),
            ] else if (isNoShow) ...[
              // ── No-Show state
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person_off, color: Colors.grey.shade600, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Marked as No-Show — passenger did not arrive',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 14),
              // ── No-Show button (always visible — driver can mark before attempting OTP)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _loadingMap['noshow_${passenger.passengerId}'] == true
                      ? null
                      : () => _markNoShow(passenger),
                  icon: _loadingMap['noshow_${passenger.passengerId}'] == true
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.person_off, size: 14, color: Colors.grey.shade600),
                  label: Text(
                    'Customer Not Here',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ),
              // OTP input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _otpControllers[passenger.passengerId],
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        hintText: 'Enter 6-digit OTP',
                        counterText: '',
                        filled: true,
                        fillColor: const Color(0xFFF5F7FA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: _navyLight.withOpacity(0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _navyLight, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        prefixIcon: const Icon(Icons.lock_outline, color: _navyLight, size: 18),
                      ),
                      onSubmitted: (_) => _verifyOTP(passenger),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : () => _verifyOTP(passenger),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _navyLight,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: isLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Verify', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),

              // Resend / Override buttons (after max attempts)
              if (maxAttemptsReached) ...[
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 340;
                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _loadingMap['resend_${passenger.passengerId}'] == true
                                ? null
                                : () => _resendOTP(passenger),
                            icon: _loadingMap['resend_${passenger.passengerId}'] == true
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.refresh, size: 16),
                            label: const Text('Resend OTP', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _navyLight,
                              side: const BorderSide(color: _navyLight),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            onPressed: _loadingMap['override_${passenger.passengerId}'] == true
                                ? null
                                : () => _requestOverride(passenger),
                            icon: _loadingMap['override_${passenger.passengerId}'] == true
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.admin_panel_settings, size: 16),
                            label: const Text('Override', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _warning,
                              side: const BorderSide(color: _warning),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _loadingMap['resend_${passenger.passengerId}'] == true
                                ? null
                                : () => _resendOTP(passenger),
                            icon: _loadingMap['resend_${passenger.passengerId}'] == true
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.refresh, size: 16),
                            label: const Text('Resend OTP', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _navyLight,
                              side: const BorderSide(color: _navyLight),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _loadingMap['override_${passenger.passengerId}'] == true
                                ? null
                                : () => _requestOverride(passenger),
                            icon: _loadingMap['override_${passenger.passengerId}'] == true
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.admin_panel_settings, size: 16),
                            label: const Text('Override', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _warning,
                              side: const BorderSide(color: _warning),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(PassengerOTPState p) {
    String label;
    Color color;

    if (p.noShow) { label = 'No-Show'; color = Colors.grey.shade600; }
    else if (p.verified) { label = 'Verified'; color = _success; }
    else if (p.overrideStatus == 'approved') { label = 'Override Approved'; color = _success; }
    else if (p.overrideStatus == 'requested') { label = 'Override Pending'; color = _warning; }
    else if (p.attempts >= 3) { label = 'Max Attempts'; color = _danger; }
    else if (p.attempts > 0) { label = 'Attempt ${p.attempts}/3'; color = _warning; }
    else { label = 'Pending'; color = _navyLight; }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildBottomBar(bool isMobile) {
    final verified = _passengerStates.where((p) => p.verified || p.overrideStatus == 'approved' || p.noShow).length;
    final total = _passengerStates.length;
    final allDone = verified == total;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, isMobile ? 20 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total > 0 ? verified / total : 0,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(allDone ? _success : _navyLight),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '$verified of $total passengers verified',
                style: TextStyle(
                  color: allDone ? _success : _navyMid,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (allDone)
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('All Done — Proceed'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
