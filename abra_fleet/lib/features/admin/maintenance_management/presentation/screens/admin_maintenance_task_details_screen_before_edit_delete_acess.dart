// File: lib/features/admin/maintenance_management/presentation/screens/admin_maintenance_task_details_screen.dart
// Screen to display detailed information about a specific maintenance task, using MaintenanceProvider.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // For date formatting
// Import the MaintenanceTask entity
import 'package:abra_fleet/features/admin/maintenance_management/domain/entities/maintenance_task_entity.dart';
// Import the Provider
import 'package:abra_fleet/features/admin/maintenance_management/presentation/providers/maintenance_provider.dart';
// Import the Add/Edit screen to navigate to it
import 'package:abra_fleet/features/admin/maintenance_management/presentation/screens/admin_add_edit_maintenance_task_screen.dart';

// Assuming DataState enum is defined in MaintenanceProvider or a shared location
// If not, ensure it's accessible. For this example, we assume 'DataState' is part of MaintenanceProvider.

class AdminMaintenanceTaskDetailsScreen extends StatelessWidget {
  final String taskId; // Now takes taskId to fetch the latest from provider

  const AdminMaintenanceTaskDetailsScreen({super.key, required this.taskId});

  Widget _buildDetailRow(BuildContext context, String label, String? value, {IconData? icon, Color? valueColor}) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
          ] else ...[
            const SizedBox(width: 32), // Placeholder for alignment
          ],
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value ?? 'N/A',
              style: textTheme.bodyLarge?.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(MaintenanceStatus status) {
    switch (status) {
      case MaintenanceStatus.upcoming: return Colors.blue.shade700;
      case MaintenanceStatus.inProgress: return Colors.teal.shade700;
      case MaintenanceStatus.completed: return Colors.green.shade700;
      case MaintenanceStatus.overdue: return Colors.red.shade700;
      case MaintenanceStatus.cancelled: return Colors.grey.shade700;
      default: return Colors.black;
    }
  }

  IconData _getStatusIcon(MaintenanceStatus status) {
    switch (status) {
      case MaintenanceStatus.upcoming: return Icons.event_note_rounded;
      case MaintenanceStatus.inProgress: return Icons.construction_rounded;
      case MaintenanceStatus.completed: return Icons.check_circle_outline_rounded;
      case MaintenanceStatus.overdue: return Icons.warning_amber_rounded;
      case MaintenanceStatus.cancelled: return Icons.cancel_outlined;
      default: return Icons.help_outline_rounded;
    }
  }

  Color _getPriorityColor(MaintenancePriority priority) {
    switch (priority) {
      case MaintenancePriority.critical: return Colors.red.shade900;
      case MaintenancePriority.high: return Colors.orange.shade800;
      case MaintenancePriority.medium: return Colors.amber.shade700;
      case MaintenancePriority.low: return Colors.green.shade600;
      default: return Colors.grey.shade700;
    }
  }

  IconData _getPriorityIcon(MaintenancePriority priority) {
    switch (priority) {
      case MaintenancePriority.critical: return Icons.error_rounded;
      case MaintenancePriority.high: return Icons.priority_high_rounded;
      case MaintenancePriority.medium: return Icons.low_priority_rounded;
      case MaintenancePriority.low: return Icons.arrow_downward_rounded;
      default: return Icons.help_outline_rounded;
    }
  }

  String _getDisplayStringForStatusEnum(MaintenanceStatus status) {
    switch (status) {
      case MaintenanceStatus.upcoming: return 'Upcoming';
      case MaintenanceStatus.inProgress: return 'In Progress';
      case MaintenanceStatus.completed: return 'Completed';
      case MaintenanceStatus.overdue: return 'Overdue';
      case MaintenanceStatus.cancelled: return 'Cancelled';
      default: return status.toString().split('.').last;
    }
  }

  String _getDisplayStringForPriorityEnum(MaintenancePriority priority) {
    switch (priority) {
      case MaintenancePriority.low: return 'Low';
      case MaintenancePriority.medium: return 'Medium';
      case MaintenancePriority.high: return 'High';
      case MaintenancePriority.critical: return 'Critical';
      default: return priority.toString().split('.').last;
    }
  }


  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final DateFormat dateTimeFormat = DateFormat('MMM dd, yyyy hh:mm a');

    return Consumer<MaintenanceProvider>(
      builder: (context, maintenanceProvider, child) {
        final MaintenanceTaskEntity? task = maintenanceProvider.getTaskFromListById(taskId);

        if (maintenanceProvider.isLoading && task == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Loading Task...')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (task == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Task Not Found')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  const Text('Maintenance task details could not be loaded.'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      maintenanceProvider.fetchMaintenanceTasks().then((_) {
                        if (maintenanceProvider.getTaskFromListById(taskId) == null && context.mounted) {
                          Navigator.of(context).pop();
                        }
                      });
                    },
                    child: const Text('Retry Load / Go Back'),
                  )
                ],
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(task.taskDescription, overflow: TextOverflow.ellipsis),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_note_rounded),
                tooltip: 'Edit Task',
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AdminAddEditMaintenanceTaskScreen(task: task),
                    ),
                  );
                  if (result != null && context.mounted) {
                    if (result is Map && result['deleted'] == true) {
                      Navigator.pop(context); // Pop details screen if task was deleted
                    }
                    // If updated, Consumer will rebuild with new data from provider.
                  }
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Column(
                    children: [
                      Hero(
                        tag: 'maintenance_icon_${task.id}',
                        child: Icon(_getStatusIcon(task.status), size: 70, color: _getStatusColor(task.status)),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        task.taskDescription,
                        style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 4.0,
                        alignment: WrapAlignment.center,
                        children: [
                          Chip(
                            avatar: Icon(_getStatusIcon(task.status), size: 16, color: Colors.white),
                            label: Text(
                              _getDisplayStringForStatusEnum(task.status),
                              style: textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            backgroundColor: _getStatusColor(task.status),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          ),
                          Chip(
                            avatar: Icon(_getPriorityIcon(task.priority), size: 16, color: _getPriorityColor(task.priority)),
                            label: Text(
                              _getDisplayStringForPriorityEnum(task.priority),
                              style: textTheme.labelLarge?.copyWith(color: _getPriorityColor(task.priority), fontWeight: FontWeight.bold),
                            ),
                            backgroundColor: _getPriorityColor(task.priority).withOpacity(0.15),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24.0),
                const Divider(),
                _buildDetailRow(context, 'Task ID:', task.id, icon: Icons.vpn_key_outlined),
                _buildDetailRow(context, 'Vehicle:', task.vehicleName, icon: Icons.directions_car_outlined),
                _buildDetailRow(context, 'Vehicle ID:', task.vehicleId, icon: Icons.confirmation_number_outlined),
                _buildDetailRow(
                    context,
                    'Scheduled:',
                    dateTimeFormat.format(task.scheduledDate),
                    icon: Icons.calendar_today_outlined
                ),
                if (task.completionDate != null)
                  _buildDetailRow(
                      context,
                      'Completed:',
                      dateTimeFormat.format(task.completionDate!),
                      icon: Icons.event_available_rounded,
                      valueColor: Colors.green.shade800
                  ),
                if (task.assignedMechanic != null && task.assignedMechanic!.isNotEmpty)
                  _buildDetailRow(context, 'Assigned To:', task.assignedMechanic, icon: Icons.engineering_rounded),
                if (task.cost != null)
                  _buildDetailRow(context, 'Cost:', '\$${task.cost!.toStringAsFixed(2)}', icon: Icons.attach_money_rounded),

                if (task.notes != null && task.notes!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Notes:', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                      padding: const EdgeInsets.all(12),
                      width: double.infinity,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300)
                      ),
                      child: Text(task.notes!, style: textTheme.bodyLarge)
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
