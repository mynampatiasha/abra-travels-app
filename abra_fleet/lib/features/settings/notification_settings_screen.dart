// lib/features/settings/notification_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:abra_fleet/core/services/notification_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  late final NotificationService _notificationService;
  bool _customSoundEnabled = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _notificationService = NotificationService.instance;
    _loadCurrentSettings();
  }

  void _loadCurrentSettings() {
    setState(() {
      _customSoundEnabled = _notificationService.isCustomSoundEnabled;
    });
  }

  Future<void> _toggleCustomSound(bool enabled) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _notificationService.setCustomSoundEnabled(enabled);
      setState(() {
        _customSoundEnabled = enabled;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled 
                ? 'Custom notification sounds enabled' 
                : 'Custom notification sounds disabled'
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update setting: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Card
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.notifications_active, color: Colors.blue.shade600),
                      const SizedBox(width: 8),
                      const Text(
                        'Notification Preferences',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Customize how you receive notifications for different types of alerts.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),

          // Custom Sound Setting
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Leave Request Notifications',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  SwitchListTile(
                    title: const Text('Custom Sound'),
                    subtitle: const Text(
                      'Play special notification sound for leave request related notifications'
                    ),
                    value: _customSoundEnabled,
                    onChanged: _isLoading ? null : _toggleCustomSound,
                    activeColor: const Color(0xFF0D47A1),
                    secondary: Icon(
                      _customSoundEnabled ? Icons.volume_up : Icons.volume_off,
                      color: _customSoundEnabled ? const Color(0xFF0D47A1) : Colors.grey,
                    ),
                  ),
                  
                  if (_customSoundEnabled) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 16),
                              const SizedBox(width: 8),
                              const Text(
                                'Custom Sound Enabled',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'You will hear a special notification sound for:\n'
                            '• Leave request submissions\n'
                            '• Leave approvals and rejections\n'
                            '• Trip cancellation notifications\n'
                            '• Administrative leave alerts',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Notification Types Info
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Notification Types',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  _buildNotificationTypeItem(
                    '🏖️', 
                    'Leave Request Submitted', 
                    'When you submit a new leave request'
                  ),
                  _buildNotificationTypeItem(
                    '✅', 
                    'Leave Request Approved', 
                    'When your organization approves your leave'
                  ),
                  _buildNotificationTypeItem(
                    '❌', 
                    'Leave Request Rejected', 
                    'When your organization rejects your leave'
                  ),
                  _buildNotificationTypeItem(
                    '📋', 
                    'Administrative Action Required', 
                    'When admin needs to process approved leave'
                  ),
                  _buildNotificationTypeItem(
                    '🚫', 
                    'Trip Cancelled', 
                    'When your assigned trip is cancelled due to leave'
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Additional Settings Info
          Card(
            color: Colors.grey.shade50,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline, color: Colors.orange.shade600),
                      const SizedBox(width: 8),
                      const Text(
                        'Tips',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '• Custom sounds help you quickly identify important leave-related notifications\n'
                    '• You can disable custom sounds if you prefer standard notification sounds\n'
                    '• Changes take effect immediately for new notifications\n'
                    '• System notifications and other alerts will use default sounds',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationTypeItem(String icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}