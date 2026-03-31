import 'package:flutter/material.dart';

// lib/features/admin/vehicle_admin_management/trip_operations/send_notifications_screen.dart

const Color kPrimaryColor = Color(0xFF0D47A1);
const Color kTextPrimaryColor = Color(0xFF212121);
const Color kTextSecondaryColor = Color(0xFF757575);
const Color kSuccessColor = Color(0xFF4CAF50);
const Color kWarningColor = Color(0xFFFFC107);
const Color kErrorColor = Color(0xFFF44336);
const Color kInfoColor = Color(0xFF0288D1);

class SendNotificationsScreen extends StatefulWidget {
  const SendNotificationsScreen({Key? key}) : super(key: key);

  @override
  State<SendNotificationsScreen> createState() =>
      _SendNotificationsScreenState();
}

class _SendNotificationsScreenState extends State<SendNotificationsScreen> {
  String _notificationType = 'general';
  String _recipientType = 'all_drivers';
  String _priority = 'normal';
  bool _scheduleNow = true;
  DateTime? _scheduledTime;
  DateTime? _scheduledDate;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  final List<Map<String, dynamic>> _notificationTypes = [
    {
      'id': 'general',
      'title': 'General Message',
      'icon': Icons.notifications_rounded,
      'color': kInfoColor,
    },
    {
      'id': 'safety',
      'title': 'Safety Alert',
      'icon': Icons.safety_check_rounded,
      'color': kWarningColor,
    },
    {
      'id': 'maintenance',
      'title': 'Maintenance',
      'icon': Icons.build_rounded,
      'color': Colors.orange,
    },
    {
      'id': 'emergency',
      'title': 'Emergency',
      'icon': Icons.emergency_rounded,
      'color': kErrorColor,
    },
  ];

  final List<Map<String, dynamic>> _recipientOptions = [
    {
      'id': 'all_drivers',
      'title': 'All Drivers',
      'icon': Icons.group_rounded,
      'count': '42 drivers',
    },
    {
      'id': 'all_staff',
      'title': 'All Staff',
      'icon': Icons.people_rounded,
      'count': '128 staff',
    },
    {
      'id': 'active_trips',
      'title': 'Active Trip Drivers',
      'icon': Icons.directions_car_rounded,
      'count': '8 drivers',
    },
    {
      'id': 'selected',
      'title': 'Selected Recipients',
      'icon': Icons.person_add_rounded,
      'count': 'Custom',
    },
  ];

  final List<Map<String, dynamic>> _priorityLevels = [
    {
      'id': 'low',
      'title': 'Low',
      'icon': Icons.arrow_downward_rounded,
      'color': Colors.blue,
    },
    {
      'id': 'normal',
      'title': 'Normal',
      'icon': Icons.unfold_more_rounded,
      'color': kInfoColor,
    },
    {
      'id': 'high',
      'title': 'High',
      'icon': Icons.arrow_upward_rounded,
      'color': kWarningColor,
    },
    {
      'id': 'urgent',
      'title': 'Urgent',
      'icon': Icons.priority_high_rounded,
      'color': kErrorColor,
    },
  ];

  final List<Map<String, dynamic>> _recentNotifications = [
    {
      'title': 'Trip Delay Alert',
      'message': 'Vehicle ABC123 delayed by 15 minutes on Route A',
      'recipients': 'All Drivers',
      'sent': '2 mins ago',
      'status': 'delivered',
      'icon': Icons.warning_rounded,
      'color': kWarningColor,
    },
    {
      'title': 'Maintenance Reminder',
      'message': 'Vehicle XYZ789 maintenance due in 500 km',
      'recipients': '1 Driver',
      'sent': '1 hour ago',
      'status': 'delivered',
      'icon': Icons.build_rounded,
      'color': Colors.orange,
    },
    {
      'title': 'Safety Protocol Update',
      'message': 'New safety guidelines effective immediately',
      'recipients': 'All Staff',
      'sent': '3 hours ago',
      'status': 'sent',
      'icon': Icons.security_rounded,
      'color': kSuccessColor,
    },
    {
      'title': 'Vehicle Check-in Required',
      'message': 'Please complete your pre-trip vehicle inspection',
      'recipients': 'Active Trip Drivers',
      'sent': '5 hours ago',
      'status': 'sent',
      'icon': Icons.directions_car_rounded,
      'color': kInfoColor,
    },
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() {
        _scheduledDate = picked;
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _scheduledTime = DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  void _sendNotification() {
    if (_titleController.text.isEmpty || _messageController.text.isEmpty) {
      _showSnackBar('Please fill in all fields!', kErrorColor);
      return;
    }

    _showSnackBar(
      'Notification sent to $_recipientType! ✅',
      kSuccessColor,
    );

    // Clear fields
    _titleController.clear();
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Notification Type Selection
                _buildSectionTitle('Notification Type'),
                const SizedBox(height: 12),
                _buildNotificationTypeSelector(),
                const SizedBox(height: 24),

                // Message Composer
                _buildSectionTitle('Compose Message'),
                const SizedBox(height: 12),
                _buildMessageComposer(),
                const SizedBox(height: 24),

                // Recipients Selection
                _buildSectionTitle('Select Recipients'),
                const SizedBox(height: 12),
                _buildRecipientsSelector(),
                const SizedBox(height: 24),

                // Priority Level
                _buildSectionTitle('Priority Level'),
                const SizedBox(height: 12),
                _buildPrioritySelector(),
                const SizedBox(height: 24),

                // Schedule Options
                _buildSectionTitle('Schedule'),
                const SizedBox(height: 12),
                _buildScheduleOptions(),
                const SizedBox(height: 24),

                // Send Button
                _buildSendButton(),
                const SizedBox(height: 24),

                // Recent Notifications
                _buildSectionTitle('Recent Notifications'),
                const SizedBox(height: 12),
                _buildRecentNotificationsList(),
                const SizedBox(height: 24),
              ],
            ),
          ),
          // Custom Bottom Action Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildCustomBottomBar(),
          ),
        ],
      ),
    );
  }

  /// Section Title Widget
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: kTextPrimaryColor,
      ),
    );
  }

  /// Notification Type Selector
  Widget _buildNotificationTypeSelector() {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _notificationTypes.length,
        itemBuilder: (context, index) {
          final type = _notificationTypes[index];
          final isSelected = _notificationType == type['id'];

          return GestureDetector(
            onTap: () {
              setState(() {
                _notificationType = type['id'];
              });
              _showSnackBar('${type['title']} selected', type['color']);
            },
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? type['color'] : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: type['color'],
                  width: isSelected ? 0 : 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isSelected ? 0.15 : 0.05),
                    blurRadius: 8,
                  )
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    type['icon'],
                    color: isSelected ? Colors.white : type['color'],
                    size: 28,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    type['title'],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : kTextPrimaryColor,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Message Composer
  Widget _buildMessageComposer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
          )
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Title',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kTextSecondaryColor,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              hintText: 'Enter notification title',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: kPrimaryColor, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            maxLength: 50,
            buildCounter: (context,
                {required currentLength,
                required isFocused,
                required maxLength}) {
              return Text(
                '$currentLength/$maxLength',
                style: const TextStyle(fontSize: 12, color: kTextSecondaryColor),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Message',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kTextSecondaryColor,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _messageController,
            decoration: InputDecoration(
              hintText: 'Enter notification message',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: kPrimaryColor, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            maxLines: 4,
            maxLength: 500,
            buildCounter: (context,
                {required currentLength,
                required isFocused,
                required maxLength}) {
              return Text(
                '$currentLength/$maxLength',
                style: const TextStyle(fontSize: 12, color: kTextSecondaryColor),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Recipients Selector
  Widget _buildRecipientsSelector() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.2,
      children: _recipientOptions.map((option) {
        final isSelected = _recipientType == option['id'];
        return GestureDetector(
          onTap: () {
            setState(() {
              _recipientType = option['id'];
            });
            _showSnackBar('${option['title']} selected', kPrimaryColor);
          },
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? kPrimaryColor : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: kPrimaryColor.withOpacity(0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isSelected ? 0.15 : 0.05),
                  blurRadius: 8,
                )
              ],
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  option['icon'],
                  color: isSelected ? Colors.white : kPrimaryColor,
                  size: 28,
                ),
                const SizedBox(height: 8),
                Text(
                  option['title'],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : kTextPrimaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  option['count'],
                  style: TextStyle(
                    fontSize: 10,
                    color: isSelected ? Colors.white70 : kTextSecondaryColor,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Priority Level Selector
  Widget _buildPrioritySelector() {
    return SizedBox(
      height: 70,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _priorityLevels.length,
        itemBuilder: (context, index) {
          final level = _priorityLevels[index];
          final isSelected = _priority == level['id'];

          return GestureDetector(
            onTap: () {
              setState(() {
                _priority = level['id'];
              });
              _showSnackBar('${level['title']} priority set', level['color']);
            },
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? level['color'] : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: level['color'],
                  width: isSelected ? 0 : 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    level['icon'],
                    color: isSelected ? Colors.white : level['color'],
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    level['title'],
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : kTextPrimaryColor,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Schedule Options
  Widget _buildScheduleOptions() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
          )
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Checkbox(
                      value: _scheduleNow,
                      onChanged: (value) {
                        setState(() {
                          _scheduleNow = value ?? true;
                        });
                      },
                      activeColor: kPrimaryColor,
                    ),
                    const Text(
                      'Send Now',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kTextPrimaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Checkbox(
                      value: !_scheduleNow,
                      onChanged: (value) {
                        setState(() {
                          _scheduleNow = !(value ?? false);
                        });
                      },
                      activeColor: kPrimaryColor,
                    ),
                    const Text(
                      'Schedule',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kTextPrimaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!_scheduleNow) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _selectDate(context),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.grey.shade300,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: kPrimaryColor, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            _scheduledDate != null
                                ? '${_scheduledDate!.day}/${_scheduledDate!.month}/${_scheduledDate!.year}'
                                : 'Select Date',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _selectTime(context),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.grey.shade300,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.access_time, color: kPrimaryColor, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            _scheduledTime != null
                                ? '${_scheduledTime!.hour}:${_scheduledTime!.minute.toString().padLeft(2, '0')}'
                                : 'Select Time',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Send Button
  Widget _buildSendButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.send_rounded, size: 20),
        label: const Text(
          'Send Notification',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        onPressed: _sendNotification,
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 4,
        ),
      ),
    );
  }

  /// Recent Notifications List
  Widget _buildRecentNotificationsList() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
          )
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _recentNotifications.length,
        separatorBuilder: (_, __) => Divider(height: 1),
        itemBuilder: (context, index) {
          final notif = _recentNotifications[index];
          return Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: notif['color'].withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    notif['icon'],
                    color: notif['color'],
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notif['title'],
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: kTextPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notif['message'],
                        style: const TextStyle(
                          fontSize: 12,
                          color: kTextSecondaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.people_outline, size: 12, color: kTextSecondaryColor),
                          const SizedBox(width: 4),
                          Text(
                            notif['recipients'],
                            style: const TextStyle(
                              fontSize: 11,
                              color: kTextSecondaryColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: notif['status'] == 'delivered'
                                  ? kSuccessColor.withOpacity(0.1)
                                  : kInfoColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              notif['status'].toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: notif['status'] == 'delivered'
                                    ? kSuccessColor
                                    : kInfoColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  notif['sent'],
                  style: const TextStyle(
                    fontSize: 11,
                    color: kTextSecondaryColor,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Custom Bottom Action Bar
  Widget _buildCustomBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildBottomBarButton(
            icon: Icons.library_books_rounded,
            label: 'Templates',
            onPressed: () {
              _showSnackBar('Opening notification templates... 📋', kInfoColor);
            },
          ),
          _buildBottomBarButton(
            icon: Icons.schedule_rounded,
            label: 'History',
            onPressed: () {
              _showSnackBar('Opening notification history... 📜', kPrimaryColor);
            },
          ),
          _buildBottomBarButton(
            icon: Icons.analytics_rounded,
            label: 'Analytics',
            onPressed: () {
              _showSnackBar('Opening notification analytics... 📊', kSuccessColor);
            },
          ),
          _buildBottomBarButton(
            icon: Icons.settings_rounded,
            label: 'Settings',
            onPressed: () {
              _showSnackBar('Opening notification settings... ⚙️', Colors.purple);
            },
          ),
        ],
      ),
    );
  }

  /// Bottom Bar Button
  Widget _buildBottomBarButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: kPrimaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: kPrimaryColor.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: kPrimaryColor, size: 18),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                color: kPrimaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}