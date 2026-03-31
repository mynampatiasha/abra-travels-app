// lib/core/services/floating_notification_service.dart
// ============================================================================
// FLOATING NOTIFICATION SERVICE - SHOWS IN-APP NOTIFICATIONS
// ============================================================================
import 'package:flutter/material.dart';
import 'dart:async';

class FloatingNotificationService {
  static FloatingNotificationService? _instance;
  
  OverlayEntry? _currentOverlay;
  Timer? _dismissTimer;

  FloatingNotificationService._internal();

  factory FloatingNotificationService() {
    _instance ??= FloatingNotificationService._internal();
    return _instance!;
  }

  /// Show floating notification
  void showFloatingNotification({
    required BuildContext context,
    required String title,
    required String body,
    required String icon,
    required String type,
    required String priority,
    required Color backgroundColor,
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onTap,
    VoidCallback? onDismiss,
  }) {
    // Remove any existing notification
    _removeCurrentNotification();

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    _currentOverlay = OverlayEntry(
      builder: (context) => _FloatingNotificationWidget(
        title: title,
        body: body,
        icon: icon,
        type: type,
        priority: priority,
        backgroundColor: backgroundColor,
        onTap: () {
          _removeCurrentNotification();
          onTap?.call();
        },
        onDismiss: () {
          _removeCurrentNotification();
          onDismiss?.call();
        },
      ),
    );

    overlay.insert(_currentOverlay!);

    // Auto-dismiss after duration
    _dismissTimer = Timer(duration, () {
      _removeCurrentNotification();
      onDismiss?.call();
    });
  }

  /// Remove current notification
  void _removeCurrentNotification() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    
    _currentOverlay?.remove();
    _currentOverlay = null;
  }

  /// Dispose service
  void dispose() {
    _removeCurrentNotification();
  }
}

class _FloatingNotificationWidget extends StatefulWidget {
  final String title;
  final String body;
  final String icon;
  final String type;
  final String priority;
  final Color backgroundColor;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  const _FloatingNotificationWidget({
    required this.title,
    required this.body,
    required this.icon,
    required this.type,
    required this.priority,
    required this.backgroundColor,
    this.onTap,
    this.onDismiss,
  });

  @override
  State<_FloatingNotificationWidget> createState() => _FloatingNotificationWidgetState();
}

class _FloatingNotificationWidgetState extends State<_FloatingNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _dismiss() {
    _animationController.reverse().then((_) {
      widget.onDismiss?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: widget.backgroundColor.withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _getBorderColor(),
                  width: 2,
                ),
              ),
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Icon
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Text(
                            widget.icon,
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      
                      // Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.body.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                widget.body,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 12,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      
                      // Dismiss button
                      IconButton(
                        onPressed: _dismiss,
                        icon: Icon(
                          Icons.close,
                          color: Colors.white.withOpacity(0.8),
                          size: 20,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getBorderColor() {
    switch (widget.priority) {
      case 'urgent':
        return Colors.red.shade300;
      case 'high':
        return Colors.orange.shade300;
      default:
        return Colors.blue.shade300;
    }
  }
}