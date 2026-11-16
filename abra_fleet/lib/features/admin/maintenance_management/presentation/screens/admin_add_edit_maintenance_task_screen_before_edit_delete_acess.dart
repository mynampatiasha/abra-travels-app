// File: lib/features/admin/maintenance_management/presentation/screens/admin_add_edit_maintenance_task_screen.dart
// Screen for Admin to add or edit a maintenance task, now using MaintenanceProvider.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:abra_fleet/features/admin/maintenance_management/domain/entities/maintenance_task_entity.dart';
import 'package:abra_fleet/features/admin/maintenance_management/presentation/providers/maintenance_provider.dart';
// Assuming VehicleProvider might be used for a real vehicle dropdown eventually
// import 'package:abra_fleet/features/admin/vehicle_management/presentation/providers/vehicle_provider.dart';
// import 'package:abra_fleet/features/admin/vehicle_management/domain/entities/vehicle_entity.dart';


class AdminAddEditMaintenanceTaskScreen extends StatefulWidget {
  final MaintenanceTaskEntity? task;

  const AdminAddEditMaintenanceTaskScreen({
    super.key,
    this.task,
  });

  @override
  State<AdminAddEditMaintenanceTaskScreen> createState() => _AdminAddEditMaintenanceTaskScreenState();
}

class _AdminAddEditMaintenanceTaskScreenState extends State<AdminAddEditMaintenanceTaskScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _taskDescriptionController;
  late TextEditingController _notesController;
  late TextEditingController _costController;
  late TextEditingController _assignedMechanicController;

  String? _selectedVehicleId;
  String _currentVehicleName = '';

  DateTime _selectedScheduledDate = DateTime.now().add(const Duration(days: 1));
  DateTime? _selectedCompletionDate;
  MaintenanceStatus _selectedStatus = MaintenanceStatus.upcoming;
  MaintenancePriority _selectedPriority = MaintenancePriority.medium;

  bool _isEditMode = false;
  bool _isSaving = false;

  // Mock vehicle list for dropdown (replace with actual data source, e.g., from VehicleProvider)
  final List<Map<String, String>> _mockVehicles = [
    {'id': 'v001', 'name': 'Cargo Van 1'},
    {'id': 'v002', 'name': 'Sedan Alpha'},
    {'id': 'v003', 'name': 'Pickup Truck 03'},
    {'id': 'v004', 'name': 'Minibus Bravo'},
    {'id': 'v005', 'name': 'Delivery Bike 1'},
    {'id': 'v006', 'name': 'Heavy Truck Zeta'},
  ];


  @override
  void initState() {
    super.initState();
    _isEditMode = widget.task != null;

    _taskDescriptionController = TextEditingController(text: widget.task?.taskDescription ?? '');
    _selectedVehicleId = widget.task?.vehicleId;
    if (_isEditMode && _selectedVehicleId != null) {
      final vehicle = _mockVehicles.firstWhere((v) => v['id'] == _selectedVehicleId, orElse: () => {'name': 'Unknown Vehicle'});
      _currentVehicleName = vehicle['name'] ?? 'Unknown Vehicle';
    }

    _notesController = TextEditingController(text: widget.task?.notes ?? '');
    _costController = TextEditingController(text: widget.task?.cost?.toString() ?? '');
    _assignedMechanicController = TextEditingController(text: widget.task?.assignedMechanic ?? '');
    _selectedScheduledDate = widget.task?.scheduledDate ?? DateTime.now().add(const Duration(days: 1));
    _selectedCompletionDate = widget.task?.completionDate;
    _selectedStatus = widget.task?.status ?? MaintenanceStatus.upcoming;
    _selectedPriority = widget.task?.priority ?? MaintenancePriority.medium;
  }

  @override
  void dispose() {
    _taskDescriptionController.dispose();
    _notesController.dispose();
    _costController.dispose();
    _assignedMechanicController.dispose();
    super.dispose();
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

  Future<void> _selectDate(BuildContext context, bool isScheduledDate) async {
    final DateTime initial = isScheduledDate
        ? _selectedScheduledDate
        : (_selectedCompletionDate ?? DateTime.now());
    final DateTime first = DateTime(2000);
    final DateTime last = DateTime(2101);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) {
      setState(() {
        if (isScheduledDate) {
          _selectedScheduledDate = picked;
        } else {
          _selectedCompletionDate = picked;
        }
      });
    }
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedVehicleId == null || _currentVehicleName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a vehicle.'), backgroundColor: Colors.redAccent),
        );
        return;
      }
      setState(() => _isSaving = true);

      final maintenanceProvider = Provider.of<MaintenanceProvider>(context, listen: false);
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);

      final String id = widget.task?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
      final taskData = MaintenanceTaskEntity(
        id: id,
        vehicleId: _selectedVehicleId!,
        vehicleName: _currentVehicleName,
        taskDescription: _taskDescriptionController.text.trim(),
        scheduledDate: _selectedScheduledDate,
        completionDate: _selectedCompletionDate,
        status: _selectedStatus,
        priority: _selectedPriority,
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
        cost: double.tryParse(_costController.text.trim()),
        assignedMechanic: _assignedMechanicController.text.trim().isNotEmpty ? _assignedMechanicController.text.trim() : null,
      );

      bool success = false;
      String actionMessage = '';

      if (_isEditMode) {
        success = await maintenanceProvider.updateMaintenanceTask(taskData);
        actionMessage = success ? 'Task "${taskData.taskDescription}" updated.' : 'Failed to update task.';
      } else {
        success = await maintenanceProvider.addMaintenanceTask(taskData);
        actionMessage = success ? 'Task "${taskData.taskDescription}" added.' : 'Failed to add task.';
      }

      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(actionMessage + (maintenanceProvider.errorMessage != null ? " Error: ${maintenanceProvider.errorMessage}" : "")),
            backgroundColor: success ? Colors.green : Colors.redAccent,
          ),
        );
        setState(() => _isSaving = false);
        if (success) {
          navigator.pop(); // Pop only on success
        }
      }
    }
  }

  Future<void> _deleteTask() async {
    if (!_isEditMode || widget.task == null) return;

    final maintenanceProvider = Provider.of<MaintenanceProvider>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete this task: "${widget.task!.taskDescription}"?'),
          actions: <Widget>[
            TextButton(child: const Text('Cancel'), onPressed: () => navigator.pop(false)),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              child: const Text('Delete'),
              onPressed: () => navigator.pop(true),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true && mounted) {
      setState(() => _isSaving = true);
      bool success = await maintenanceProvider.deleteMaintenanceTask(widget.task!.id);
      String message = success ? 'Task "${widget.task!.taskDescription}" deleted.' : 'Failed to delete task.';

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(message + (maintenanceProvider.errorMessage != null ? " Error: ${maintenanceProvider.errorMessage}" : "")),
          backgroundColor: success ? Colors.blueAccent : Colors.redAccent,
        ),
      );
      setState(() => _isSaving = false);
      if (success) {
        navigator.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final DateFormat dateFormat = DateFormat('MMM dd, yyyy'); // Corrected DateFormat

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Maintenance Task' : 'New Maintenance Task'),
        centerTitle: true,
        actions: [
          if (_isEditMode)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              tooltip: 'Delete Task',
              onPressed: _isSaving ? null : _deleteTask,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DropdownButtonFormField<String>(
                value: _selectedVehicleId,
                hint: const Text('Select Vehicle*'),
                decoration: const InputDecoration(labelText: 'Vehicle*', prefixIcon: Icon(Icons.directions_car_rounded)),
                items: _mockVehicles.map((vehicle) {
                  return DropdownMenuItem<String>(
                    value: vehicle['id'],
                    child: Text(vehicle['name']!),
                  );
                }).toList(),
                onChanged: _isSaving ? null : (String? newValue) {
                  setState(() {
                    _selectedVehicleId = newValue;
                    _currentVehicleName = newValue != null
                        ? _mockVehicles.firstWhere((v) => v['id'] == newValue)['name']!
                        : '';
                  });
                },
                validator: (value) => value == null ? 'Please select a vehicle' : null,
              ),
              const SizedBox(height: 16.0),

              TextFormField(
                controller: _taskDescriptionController,
                decoration: const InputDecoration(labelText: 'Task Description*'),
                validator: (value) => value == null || value.isEmpty ? 'Please enter task description' : null,
                maxLines: 2,
                textInputAction: TextInputAction.next,
                enabled: !_isSaving,
              ),
              const SizedBox(height: 16.0),

              TextFormField(
                decoration: InputDecoration(
                    labelText: 'Scheduled Date*',
                    prefixIcon: const Icon(Icons.calendar_today_outlined),
                    suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar_outlined), onPressed: _isSaving ? null : () => _selectDate(context, true))
                ),
                readOnly: true,
                controller: TextEditingController(text: dateFormat.format(_selectedScheduledDate)),
                onTap: _isSaving ? null : () => _selectDate(context, true),
                validator: (value) => _selectedScheduledDate == null ? 'Please select a scheduled date' : null, // Should not be null due to init
                enabled: !_isSaving,
              ),
              const SizedBox(height: 16.0),

              DropdownButtonFormField<MaintenanceStatus>(
                value: _selectedStatus,
                decoration: const InputDecoration(labelText: 'Status*'),
                items: MaintenanceStatus.values.map((MaintenanceStatus status) {
                  return DropdownMenuItem<MaintenanceStatus>(
                    value: status,
                    child: Text(_getDisplayStringForStatusEnum(status)),
                  );
                }).toList(),
                onChanged: _isSaving ? null : (MaintenanceStatus? newValue) {
                  if (newValue != null) setState(() => _selectedStatus = newValue);
                },
                validator: (value) => value == null ? 'Please select a status' : null,
              ),
              const SizedBox(height: 16.0),

              DropdownButtonFormField<MaintenancePriority>(
                value: _selectedPriority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: MaintenancePriority.values.map((MaintenancePriority priority) {
                  return DropdownMenuItem<MaintenancePriority>(
                    value: priority,
                    child: Text(_getDisplayStringForPriorityEnum(priority)),
                  );
                }).toList(),
                onChanged: _isSaving ? null : (MaintenancePriority? newValue) {
                  if (newValue != null) setState(() => _selectedPriority = newValue);
                },
              ),
              const SizedBox(height: 16.0),

              TextFormField(
                controller: _assignedMechanicController,
                decoration: const InputDecoration(labelText: 'Assigned To / Workshop'),
                textInputAction: TextInputAction.next,
                enabled: !_isSaving,
              ),
              const SizedBox(height: 16.0),

              TextFormField(
                controller: _costController,
                decoration: const InputDecoration(labelText: 'Cost (\$) (Optional)', prefixIcon: Icon(Icons.attach_money_rounded)),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                enabled: !_isSaving,
              ),
              const SizedBox(height: 16.0),

              TextFormField(
                decoration: InputDecoration(
                    labelText: 'Completion Date (Optional)',
                    prefixIcon: const Icon(Icons.event_available_rounded),
                    suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar_outlined), onPressed: _isSaving ? null : () => _selectDate(context, false))
                ),
                readOnly: true,
                controller: TextEditingController(text: _selectedCompletionDate != null ? dateFormat.format(_selectedCompletionDate!) : ''),
                onTap: _isSaving ? null : () => _selectDate(context, false),
                enabled: !_isSaving,
              ),
              const SizedBox(height: 16.0),

              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes (Optional)'),
                maxLines: 3,
                textInputAction: TextInputAction.done,
                enabled: !_isSaving,
              ),
              const SizedBox(height: 32.0),

              ElevatedButton.icon(
                icon: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(_isEditMode ? Icons.save_alt_rounded : Icons.add_task_rounded),
                label: Text(_isEditMode ? 'Save Changes' : 'Add Task'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: _isSaving ? null : _submitForm,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
