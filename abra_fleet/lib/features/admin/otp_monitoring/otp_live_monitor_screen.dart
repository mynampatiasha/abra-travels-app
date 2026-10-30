// ============================================================================
// lib/features/admin/otp_monitoring/otp_live_monitor_screen.dart
// ADMIN — Live OTP verification status per passenger (green/yellow/red)
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/otp_service.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _success    = Color(0xFF10B981);
const Color _warning    = Color(0xFFF59E0B);
const Color _danger     = Color(0xFFDC2626);

class OtpLiveMonitorScreen extends StatefulWidget {
  final String tripGroupId;
  final String stopId;
  final String stopAddress;

  const OtpLiveMonitorScreen({
    super.key,
    required this.tripGroupId,
    required this.stopId,
    required this.stopAddress,
  });

  @override
  State<OtpLiveMonitorScreen> createState() => _OtpLiveMonitorScreenState();
}

class _OtpLiveMonitorScreenState extends State<OtpLiveMonitorScreen> {
  final OtpService _otpService = OtpService();
  List<Map<String, dynamic>> _statusList = [];
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    // Auto-refresh every 10 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadStatus());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final data = await _otpService.getStopOTPStatus(
        tripGroupId: widget.tripGroupId,
        stopId: widget.stopId,
      );
      if (mounted) setState(() { _statusList = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _rowColor(Map<String, dynamic> item) {
    if (item['verified'] == true || item['overrideStatus'] == 'approved') return _success;
    if ((item['attempts'] ?? 0) >= 3 || item['overrideStatus'] == 'requested') return _warning;
    return _danger;
  }

  String _statusLabel(Map<String, dynamic> item) {
    if (item['verified'] == true) return 'Verified';
    if (item['overrideStatus'] == 'approved') return 'Override Approved';
    if (item['overrideStatus'] == 'requested') return 'Override Pending';
    if ((item['attempts'] ?? 0) >= 3) return 'Max Attempts';
    if ((item['attempts'] ?? 0) > 0) return 'Attempt ${item['attempts']}/3';
    return 'Pending';
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _navyDark,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Live OTP Monitor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(widget.stopAddress, style: const TextStyle(fontSize: 11, color: Colors.white70), overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () { setState(() => _loading = true); _loadStatus(); },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _navyLight))
          : _statusList.isEmpty
              ? _buildEmpty()
              : isWeb ? _buildWebTable() : _buildMobileList(),
    );
  }

  Widget _buildEmpty() => const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_clock, size: 64, color: Colors.grey),
        SizedBox(height: 16),
        Text('No OTP records for this stop', style: TextStyle(color: Colors.grey, fontSize: 16)),
      ],
    ),
  );

  Widget _buildMobileList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _statusList.length,
      itemBuilder: (_, i) {
        final item = _statusList[i];
        final color = _rowColor(item);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.4)),
            boxShadow: [BoxShadow(color: color.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 12, height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            title: Text(item['passengerName'] ?? 'Passenger', style: const TextStyle(fontWeight: FontWeight.bold, color: _navyDark)),
            subtitle: Text(
              '${item['type'] == 'step_in' ? 'Step-In' : 'Step-Out'} • Attempts: ${item['attempts'] ?? 0}',
              style: const TextStyle(fontSize: 12, color: _navyMid),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(_statusLabel(item), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWebTable() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Card(
          margin: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
          child: Column(
            children: [
              // Legend
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _legendDot(_success, 'Verified'),
                    const SizedBox(width: 16),
                    _legendDot(_warning, 'Pending / Override'),
                    const SizedBox(width: 16),
                    _legendDot(_danger, 'Failed'),
                    const Spacer(),
                    Text('${_statusList.length} passengers', style: const TextStyle(color: _navyMid, fontSize: 13)),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Table header
              Container(
                color: _navyDark.withOpacity(0.04),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: const Row(
                  children: [
                    SizedBox(width: 16),
                    Expanded(flex: 3, child: Text('Passenger', style: TextStyle(fontWeight: FontWeight.bold, color: _navyDark))),
                    Expanded(flex: 2, child: Text('Type', style: TextStyle(fontWeight: FontWeight.bold, color: _navyDark))),
                    Expanded(flex: 1, child: Text('Attempts', style: TextStyle(fontWeight: FontWeight.bold, color: _navyDark))),
                    Expanded(flex: 2, child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, color: _navyDark))),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: _statusList.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final item = _statusList[i];
                    final color = _rowColor(item);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Expanded(flex: 3, child: Text(item['passengerName'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500, color: _navyDark))),
                          Expanded(flex: 2, child: Text(item['type'] == 'step_in' ? 'Step-In' : 'Step-Out', style: const TextStyle(color: _navyMid))),
                          Expanded(flex: 1, child: Text('${item['attempts'] ?? 0}/3', style: TextStyle(color: (item['attempts'] ?? 0) >= 3 ? _danger : _navyMid))),
                          Expanded(
                            flex: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                              child: Text(_statusLabel(item), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) => Row(
    children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
    ],
  );
}
