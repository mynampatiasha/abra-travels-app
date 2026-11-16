// lib/core/widgets/app_error_dialog.dart
// ============================================================================
// 🔌 CORPORATE APP ERROR DIALOG (Disconnected Cables & Try Again)
// ============================================================================
// Enterprise-grade dialog with animated disconnected cables, sparks,
// and a prominent 'Try Again' button. Replaces raw developer exceptions.
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';

class AppErrorDialog extends StatefulWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryButtonText;
  final VoidCallback? onDismiss;

  const AppErrorDialog({
    Key? key,
    this.title = 'Connection Lost',
    this.message = 'Unable to connect to Corporate Travels servers. Please check your internet or try again.',
    this.onRetry,
    this.retryButtonText = 'Try Again',
    this.onDismiss,
  }) : super(key: key);

  /// Displays the corporate network / server unreachable error modal
  static Future<void> show(
    BuildContext context, {
    String title = 'Connection Lost',
    String message = 'Unable to connect to Corporate Travels servers. Please check your internet or try again.',
    VoidCallback? onRetry,
    String retryButtonText = 'Try Again',
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (BuildContext dialogContext) {
        return AppErrorDialog(
          title: title,
          message: message,
          onRetry: onRetry,
          retryButtonText: retryButtonText,
        );
      },
    );
  }

  /// Convenience method for Network / Timeout / Server downtime
  static Future<void> showNetworkError(
    BuildContext context, {
    VoidCallback? onRetry,
    String? customMessage,
  }) {
    return show(
      context,
      title: 'Connection Lost',
      message: customMessage ??
          'We couldn\'t reach the Corporate Travels server. Please check your connection or try again.',
      onRetry: onRetry,
    );
  }

  /// Shows an elegant corporate floating banner / pill (replaces harsh red snackbars)
  static void showBanner(
    BuildContext context, {
    required String message,
    bool isError = true,
    IconData? icon,
    Duration duration = const Duration(seconds: 4),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isError ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isError
                  ? const Color(0xFFEF4444).withOpacity(0.5)
                  : const Color(0xFF3B82F6).withOpacity(0.5),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isError
                      ? const Color(0xFFEF4444).withOpacity(0.15)
                      : const Color(0xFF10B981).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon ?? (isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded),
                  color: isError ? const Color(0xFFF87171) : const Color(0xFF34D399),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  State<AppErrorDialog> createState() => _AppErrorDialogState();
}

class _AppErrorDialogState extends State<AppErrorDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  bool _isRetrying = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleRetry() async {
    if (_isRetrying) return;
    setState(() => _isRetrying = true);

    try {
      if (widget.onRetry != null) {
        widget.onRetry!();
      }
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isRetrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: const Color(0xFF0E1E38),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withOpacity(0.15),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: const Color(0xFF3B82F6).withOpacity(0.12),
                blurRadius: 40,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top close button
                Align(
                  alignment: Alignment.topRight,
                  child: InkWell(
                    onTap: () {
                      if (widget.onDismiss != null) {
                        widget.onDismiss!();
                      }
                      Navigator.of(context, rootNavigator: true).pop();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white.withOpacity(0.4),
                        size: 20,
                      ),
                    ),
                  ),
                ),

                // ANIMATED DISCONNECTED CABLES WITH SPARKS
                SizedBox(
                  height: 120,
                  width: 220,
                  child: AnimatedBuilder(
                    animation: _animController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _DisconnectedCablesPainter(
                          animationValue: _animController.value,
                          isConnecting: _isRetrying,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Title
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),

                // Friendly message
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Colors.white.withOpacity(0.72),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // TRY AGAIN BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isRetrying ? null : _handleRetry,
                    style: ElevatedButton.styleFrom(
                      elevation: 4,
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      shadowColor: const Color(0xFF2563EB).withOpacity(0.4),
                    ),
                    child: _isRetrying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            widget.retryButtonText,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter that draws the two disconnected cables and electrical spark burst
class _DisconnectedCablesPainter extends CustomPainter {
  final double animationValue;
  final bool isConnecting;

  _DisconnectedCablesPainter({
    required this.animationValue,
    required this.isConnecting,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Movement: cables gently float apart, or slide together on retry
    final floatOffset = isConnecting
        ? -14.0
        : math.sin(animationValue * 2 * math.pi) * 5.0;

    final leftOffset = -22.0 - floatOffset;
    final rightOffset = 22.0 + floatOffset;

    // Cable Wire Paint
    final wirePaint = Paint()
      ..color = const Color(0xFF3B82F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    final plugBodyPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;

    final plugBorderPaint = Paint()
      ..color = const Color(0xFF60A5FA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final prongPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.fill;

    // 1. LEFT CABLE & SOCKET
    final leftX = centerX + leftOffset;
    // Left wire
    final leftPath = Path()
      ..moveTo(0, centerY)
      ..quadraticBezierTo(leftX - 35, centerY + 6, leftX - 18, centerY);
    canvas.drawPath(leftPath, wirePaint);

    // Left socket body
    final socketRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(leftX - 8, centerY), width: 24, height: 26),
      const Radius.circular(6),
    );
    canvas.drawRRect(socketRect, plugBodyPaint);
    canvas.drawRRect(socketRect, plugBorderPaint);

    // Socket collar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(leftX + 4, centerY), width: 4, height: 18),
        const Radius.circular(2),
      ),
      prongPaint,
    );

    // 2. RIGHT CABLE & PLUG
    final rightX = centerX + rightOffset;
    // Metal prongs
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(rightX - 8, centerY - 5), width: 10, height: 4),
        const Radius.circular(1.5),
      ),
      prongPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(rightX - 8, centerY + 5), width: 10, height: 4),
        const Radius.circular(1.5),
      ),
      prongPaint,
    );

    // Right plug head
    final plugRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(rightX + 8, centerY), width: 24, height: 26),
      const Radius.circular(6),
    );
    canvas.drawRRect(plugRect, plugBodyPaint);
    canvas.drawRRect(plugRect, plugBorderPaint);

    // Right wire
    final rightPath = Path()
      ..moveTo(rightX + 20, centerY)
      ..quadraticBezierTo(size.width - 20, centerY - 6, size.width, centerY);
    canvas.drawPath(rightPath, wirePaint);

    // 3. ELECTRICAL SPARK BURST (Center)
    final sparkPulse = math.sin(animationValue * 4 * math.pi).abs();
    if (sparkPulse > 0.15 && !isConnecting) {
      final glowPaint = Paint()
        ..color = const Color(0xFFFBBF24).withOpacity(sparkPulse * 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(Offset(centerX, centerY), 12 * sparkPulse + 4, glowPaint);

      final sparkPaint = Paint()
        ..color = const Color(0xFFFBBF24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      // Small lightning spark
      final sparkPath = Path()
        ..moveTo(centerX + 2, centerY - 10)
        ..lineTo(centerX - 3, centerY - 1)
        ..lineTo(centerX + 3, centerY)
        ..lineTo(centerX - 2, centerY + 10);
      canvas.drawPath(sparkPath, sparkPaint);

      // Micro spark rays
      final rayPaint = Paint()
        ..color = const Color(0xFFF59E0B)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(centerX - 8, centerY - 7), Offset(centerX - 13, centerY - 11), rayPaint);
      canvas.drawLine(Offset(centerX + 8, centerY - 7), Offset(centerX + 13, centerY - 11), rayPaint);
      canvas.drawLine(Offset(centerX - 7, centerY + 8), Offset(centerX - 12, centerY + 12), rayPaint);
      canvas.drawLine(Offset(centerX + 7, centerY + 8), Offset(centerX + 12, centerY + 12), rayPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DisconnectedCablesPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isConnecting != isConnecting;
  }
}
