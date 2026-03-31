// lib/core/widgets/notification_overlay_widget.dart
// Floating Notification Banner - Supports ALL ROLES (Driver, Customer, Admin)

import 'package:flutter/material.dart';

class NotificationOverlayWidget extends StatefulWidget {
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const NotificationOverlayWidget({
    super.key,
    required this.title,
    required this.body,
    required this.data,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<NotificationOverlayWidget> createState() => _NotificationOverlayWidgetState();
}

class _NotificationOverlayWidgetState extends State<NotificationOverlayWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    ));

    _controller.forward();

    // Auto-dismiss after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  // 🔥 COMPLETE: Support ALL notification types (Driver, Customer, Admin)
  IconData _getNotificationIcon() {
    final type = widget.data['type']?.toString() ?? '';
    
    switch (type) {
      // ========== DRIVER NOTIFICATIONS ==========
      case 'trip_assigned':
        return Icons.local_shipping;
      case 'route_assigned':
      case 'route_assigned_driver':
      case 'driver_route_assignment':
        return Icons.route;
      case 'roster_assigned':
        return Icons.calendar_today;
      case 'vehicle_assigned':
        return Icons.directions_car;
      case 'roster_updated':
        return Icons.update;
      case 'roster_cancelled':
        return Icons.event_busy;
      case 'payment_received':
        return Icons.payment;
      case 'shift_reminder':
        return Icons.access_time;
      case 'document_expiring_soon':
        return Icons.description;
      case 'document_expired':
        return Icons.warning;
        
      // ========== CUSTOMER NOTIFICATIONS ==========
      case 'trip_started':
        return Icons.play_circle_filled;
      case 'eta_15min':
      case 'eta_5min':
        return Icons.schedule;
      case 'driver_arrived':
        return Icons.location_on;
      case 'trip_completed':
        return Icons.check_circle;
      case 'trip_delayed':
        return Icons.warning;
      case 'pickup_reminder':
        return Icons.alarm;
      case 'feedback_request':
        return Icons.star_rate;
      case 'feedback_reply':
        return Icons.reply;
      case 'address_change_approved':
        return Icons.home;
      case 'address_change_rejected':
        return Icons.home_work;
      case 'leave_approved':
        return Icons.check_circle;
      case 'leave_rejected':
        return Icons.cancel;
        
      // ========== ADMIN NOTIFICATIONS ==========
      case 'trip_accepted_admin':
        return Icons.thumb_up;
      case 'trip_declined_admin':
        return Icons.thumb_down;
      case 'trip_created_admin':
        return Icons.add_circle;
      case 'sos_alert':
      case 'emergency_alert':
        return Icons.emergency;
      case 'driver_report':
        return Icons.assessment;
      case 'leave_request':
      case 'leave_request_pending':
        return Icons.event_note;
      case 'customer_registration':
      case 'new_user_registered':
        return Icons.person_add;
      case 'vehicle_maintenance':
      case 'maintenance_due':
        return Icons.build;
      case 'roster_pending':
        return Icons.pending_actions;
      case 'roster_assigned_admin':
        return Icons.assignment_turned_in;
        
      // ========== COMMON ==========
      case 'trip_cancelled':
        return Icons.cancel;
      case 'trip_updated':
        return Icons.edit;
      case 'system':
        return Icons.settings;
      case 'broadcast':
        return Icons.campaign;
      case 'test':
        return Icons.bug_report;
        
      default:
        return Icons.notifications;
    }
  }

  // 🔥 COMPLETE: Color based on type and priority
  Color _getNotificationColor() {
    final type = widget.data['type']?.toString() ?? '';
    final priority = widget.data['priority']?.toString() ?? 'normal';
    
    // Priority overrides
    if (priority == 'urgent' || type == 'emergency_alert' || type == 'sos_alert') {
      return Colors.red;
    }
    
    // Type-based colors
    switch (type) {
      // Green - Success/Completion
      case 'trip_completed':
      case 'trip_accepted_admin':
      case 'payment_received':
      case 'leave_approved':
      case 'address_change_approved':
        return Colors.green;
      
      // Orange - Warning/Time-sensitive
      case 'eta_15min':
      case 'eta_5min':
      case 'pickup_reminder':
      case 'shift_reminder':
      case 'document_expiring_soon':
      case 'maintenance_due':
        return Colors.orange;
      
      // Red - Alert/Cancelled
      case 'trip_cancelled':
      case 'trip_declined_admin':
      case 'trip_delayed':
      case 'leave_rejected':
      case 'address_change_rejected':
      case 'document_expired':
        return Colors.red;
      
      // Purple - Feedback
      case 'feedback_request':
      case 'feedback_reply':
        return Colors.purple;
      
      // Amber - Ratings
      case 'rating_received':
        return Colors.amber;
      
      // Teal - Admin actions
      case 'roster_assigned':
      case 'roster_assigned_admin':
      case 'vehicle_assigned':
        return Colors.teal;
      
      // Blue - Default (Trip/Route assignments, updates)
      default:
        return const Color(0xFF0D47A1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: GestureDetector(
              onTap: () {
                _dismiss();
                widget.onTap();
              },
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity! < -300) {
                  _dismiss();
                }
              },
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _getNotificationColor(),
                        _getNotificationColor().withOpacity(0.8),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _getNotificationColor().withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Main content
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            // Icon
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _getNotificationIcon(),
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            
                            // Text content
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.body,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.95),
                                      fontSize: 14,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  
                                  // Action hint
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.touch_app,
                                          color: Colors.white,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Tap to view',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            // Close button
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 20,
                              ),
                              onPressed: _dismiss,
                            ),
                          ],
                        ),
                      ),
                      
                      // Swipe indicator
                      Positioned(
                        bottom: 4,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
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
}