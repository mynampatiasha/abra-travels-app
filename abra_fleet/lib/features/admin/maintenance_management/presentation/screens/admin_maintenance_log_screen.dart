// File: lib/features/admin/maintenance_management/presentation/screens/admin_maintenance_log_screen.dart
// Screen for Admin to view and manage maintenance tasks, with navigation to Add/Edit and Details screens.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // For date formatting

// Import the MaintenanceTask entity
import 'package:abra_fleet/features/admin/maintenance_management/domain/entities/maintenance_task_entity.dart';
// Import the Provider
import 'package:abra_fleet/features/admin/maintenance_management/presentation/providers/maintenance_provider.dart';
// Import the Add/Edit screen
import 'package:abra_fleet/features/admin/maintenance_management/presentation/screens/admin_add_edit_maintenance_task_screen.dart';
// Import the Details screen
import 'package:abra_fleet/features/admin/maintenance_management/presentation/screens/admin_maintenance_task_details_screen.dart';


class AdminMaintenanceLogScreen extends StatefulWidget {
  const AdminMaintenanceLogScreen({super.key});

  @override
  State<AdminMaintenanceLogScreen> createState() => _AdminMaintenanceLogScreenState();
}

class _AdminMaintenanceLogScreenState extends State<AdminMaintenanceLogScreen> {
  String _searchTerm = '';
  String? _selectedStatusFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MaintenanceProvider>(context, listen: false).fetchMaintenanceTasks();
    });
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

  List<MaintenanceTaskEntity> _getFilteredTasks(List<MaintenanceTaskEntity> allTasks) {
    List<MaintenanceTaskEntity> tempTasks = List.from(allTasks);

    if (_selectedStatusFilter != null && _selectedStatusFilter != 'All') {
      tempTasks = tempTasks.where((task) => _getDisplayStringForStatusEnum(task.status) == _selectedStatusFilter).toList();
    }

    if (_searchTerm.isNotEmpty) {
      tempTasks = tempTasks
          .where((task) =>
      task.vehicleName.toLowerCase().contains(_searchTerm.toLowerCase()) ||
          task.taskDescription.toLowerCase().contains(_searchTerm.toLowerCase()) ||
          (task.assignedMechanic?.toLowerCase().contains(_searchTerm.toLowerCase()) ?? false))
          .toList();
    }
    tempTasks.sort((a, b) {
      int statusCompare = _compareStatus(a.status, b.status);
      if (statusCompare != 0) return statusCompare;
      return a.scheduledDate.compareTo(b.scheduledDate);
    });
    return tempTasks;
  }

  int _statusOrder(MaintenanceStatus status) {
    switch (status) {
      case MaintenanceStatus.overdue: return 0;
      case MaintenanceStatus.inProgress: return 1;
      case MaintenanceStatus.upcoming: return 2;
      case MaintenanceStatus.completed: return 3;
      case MaintenanceStatus.cancelled: return 4;
      default: return 5;
    }
  }

  int _compareStatus(MaintenanceStatus a, MaintenanceStatus b) {
    return _statusOrder(a).compareTo(_statusOrder(b));
  }

  void _onSearchChanged(String searchTerm) {
    setState(() {
      _searchTerm = searchTerm;
    });
  }

  void _filterByStatus(String? statusDisplayString) {
    setState(() {
      _selectedStatusFilter = statusDisplayString;
    });
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

  void _navigateToAddEditScreen(BuildContext context, {MaintenanceTaskEntity? task}) async {
    final maintenanceProvider = Provider.of<MaintenanceProvider>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminAddEditMaintenanceTaskScreen(task: task),
      ),
    );

    if (result != null && mounted) {
      bool success = false;
      String message = '';

      if (result is MaintenanceTaskEntity) {
        if (task != null) {
          success = await maintenanceProvider.updateMaintenanceTask(result);
          message = success ? 'Task "${result.taskDescription}" updated.' : 'Failed to update task.';
        } else {
          success = await maintenanceProvider.addMaintenanceTask(result);
          message = success ? 'Task "${result.taskDescription}" added.' : 'Failed to add task.';
        }
      } else if (result is Map && result['deleted'] == true && result['id'] != null) {
        success = await maintenanceProvider.deleteMaintenanceTask(result['id']);
        message = success ? 'Task deleted.' : 'Failed to delete task.';
      }

      if (message.isNotEmpty) {
        scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(message + (maintenanceProvider.errorMessage != null ? " Error: ${maintenanceProvider.errorMessage}" : "")),
              backgroundColor: success ? (result is Map && result['deleted'] == true ? Colors.blueAccent : Colors.green) : Colors.redAccent,
            )
        );
      }
    }
  }

  void _navigateToDetailsScreen(BuildContext context, MaintenanceTaskEntity task) async {
    final maintenanceProvider = Provider.of<MaintenanceProvider>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final resultFromDetails = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminMaintenanceTaskDetailsScreen(taskId: task.id), // Ensure taskId is passed
      ),
    );

    if (resultFromDetails != null && mounted) {
      bool success = false;
      String message = '';
      if (resultFromDetails is Map && resultFromDetails['deleted'] == true && resultFromDetails['id'] != null) {
        success = await maintenanceProvider.deleteMaintenanceTask(resultFromDetails['id']);
        message = success ? 'Task deleted from details.' : 'Failed to delete task.';
      } else if (resultFromDetails is MaintenanceTaskEntity) {
        success = await maintenanceProvider.updateMaintenanceTask(resultFromDetails);
        message = success ? 'Task "${resultFromDetails.taskDescription}" updated from details.' : 'Failed to update task.';
      }
      if (message.isNotEmpty) {
        scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(message + (maintenanceProvider.errorMessage != null ? " Error: ${maintenanceProvider.errorMessage}" : "")),
              backgroundColor: success ? Colors.blueAccent : Colors.redAccent,
            )
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final DateFormat dateFormat = DateFormat('MMM dd, yyyy hh:mm a'); // Corrected DateFormat pattern
    final DateFormat shortDateFormat = DateFormat('MMM dd, yyyy'); // Corrected DateFormat pattern

    final List<String> statusOptionsForFilter = [
      'All',
      ...MaintenanceStatus.values.map((statusEnum) => _getDisplayStringForStatusEnum(statusEnum)).toList()
    ];

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search tasks (vehicle, description)...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      filled: true,
                      fillColor: Theme.of(context).inputDecorationTheme.fillColor ?? Colors.white,
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: Colors.grey.shade400),
                    color: Theme.of(context).inputDecorationTheme.fillColor ?? Colors.white,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedStatusFilter ?? 'All',
                      hint: const Text("Status"),
                      icon: const Icon(Icons.filter_list_rounded),
                      items: statusOptionsForFilter.map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value, style: textTheme.bodyMedium),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        _filterByStatus(newValue);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Consumer<MaintenanceProvider>(
              builder: (context, maintenanceProvider, child) {
                if (maintenanceProvider.isLoading && maintenanceProvider.tasks.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                // Assuming DataState enum is available from MaintenanceProvider
                if (maintenanceProvider.state == DataState.error && maintenanceProvider.tasks.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text('Error: ${maintenanceProvider.errorMessage ?? "Could not load tasks."}', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => maintenanceProvider.fetchMaintenanceTasks(),
                          child: const Text('Retry'),
                        )
                      ],
                    ),
                  );
                }

                final displayedTasks = _getFilteredTasks(maintenanceProvider.tasks);

                if (displayedTasks.isEmpty) {
                  return Center(
                    child: Text(
                      _searchTerm.isEmpty && (_selectedStatusFilter == null || _selectedStatusFilter == 'All')
                          ? 'No maintenance tasks found. Tap + to add one.'
                          : 'No tasks match your criteria.',
                      style: textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => maintenanceProvider.fetchMaintenanceTasks(),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80.0),
                    itemCount: displayedTasks.length,
                    itemBuilder: (context, index) {
                      final task = displayedTasks[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                        elevation: 2.0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                        child: ListTile(
                          leading: Hero(
                            tag: 'maintenance_icon_${task.id}',
                            child: CircleAvatar(
                              backgroundColor: _getStatusColor(task.status).withOpacity(0.15),
                              child: Icon(_getStatusIcon(task.status), color: _getStatusColor(task.status), size: 24),
                            ),
                          ),
                          title: Text(
                            task.taskDescription,
                            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Vehicle: ${task.vehicleName}',
                                style: textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Scheduled: ${dateFormat.format(task.scheduledDate)}',
                                style: textTheme.bodySmall,
                              ),
                              if (task.completionDate != null)
                                Text(
                                  'Completed: ${shortDateFormat.format(task.completionDate!)}',
                                  style: textTheme.bodySmall?.copyWith(color: Colors.green.shade800),
                                ),
                              Row(
                                children: [
                                  Chip(
                                    avatar: Icon(_getStatusIcon(task.status), size: 14, color: _getStatusColor(task.status)),
                                    label: Text(_getDisplayStringForStatusEnum(task.status), style: textTheme.labelSmall?.copyWith(color: _getStatusColor(task.status))),
                                    backgroundColor: _getStatusColor(task.status).withOpacity(0.1),
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                    labelPadding: const EdgeInsets.only(left: 2.0),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const SizedBox(width: 6),
                                  Chip(
                                    label: Text(task.priorityDisplay, style: textTheme.labelSmall),
                                    backgroundColor: Colors.grey.shade200,
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              )
                            ],
                          ),
                          isThreeLine: true,
                          onTap: () {
                            _navigateToDetailsScreen(context, task);
                          },
                          onLongPress: () {
                            _navigateToAddEditScreen(context, task: task);
                          },
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: "add_maintenance_fab",
        icon: const Icon(Icons.add_comment_rounded),
        label: const Text('New Task'),
        onPressed: () {
          _navigateToAddEditScreen(context);
        },
      ),
    );
  }
}
