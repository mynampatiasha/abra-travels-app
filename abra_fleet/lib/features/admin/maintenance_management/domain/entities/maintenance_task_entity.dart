// File: lib/features/admin/maintenance_management/domain/entities/maintenance_task_entity.dart
// Defines the data structure for a Maintenance Task.

// Consider using 'equatable' for value comparison if needed.
// import 'package:equatable/equatable.dart';

enum MaintenanceStatus { upcoming, inProgress, completed, overdue, cancelled }
enum MaintenancePriority { low, medium, high, critical }

// class MaintenanceTaskEntity extends Equatable {
class MaintenanceTaskEntity {
  final String id; // Unique identifier for the maintenance task
  final String vehicleId; // ID of the vehicle requiring maintenance
  final String vehicleName; // Name/identifier of the vehicle (for display)
  final String taskDescription; // e.g., "Oil Change", "Tire Rotation", "Engine Check"
  final DateTime scheduledDate;
  final DateTime? completionDate;
  final MaintenanceStatus status;
  final MaintenancePriority priority;
  final String? notes;
  final double? cost; // Cost of the maintenance task
  final String? assignedMechanic; // Name or ID of the mechanic/workshop

  MaintenanceTaskEntity({
    required this.id,
    required this.vehicleId,
    required this.vehicleName,
    required this.taskDescription,
    required this.scheduledDate,
    this.completionDate,
    required this.status,
    this.priority = MaintenancePriority.medium, // Default priority
    this.notes,
    this.cost,
    this.assignedMechanic,
  });

  // @override
  // List<Object?> get props => [
  //   id, vehicleId, vehicleName, taskDescription, scheduledDate, completionDate,
  //   status, priority, notes, cost, assignedMechanic
  // ];

  @override
  String toString() {
    return 'MaintenanceTask(id: $id, vehicle: $vehicleName, task: $taskDescription, status: $status)';
  }

  // Helper to get a display string for status
  String get statusDisplay {
    switch (status) {
      case MaintenanceStatus.upcoming: return 'Upcoming';
      case MaintenanceStatus.inProgress: return 'In Progress';
      case MaintenanceStatus.completed: return 'Completed';
      case MaintenanceStatus.overdue: return 'Overdue';
      case MaintenanceStatus.cancelled: return 'Cancelled';
      default: return 'Unknown';
    }
  }

  // Helper to get a display string for priority
  String get priorityDisplay {
    switch (priority) {
      case MaintenancePriority.low: return 'Low';
      case MaintenancePriority.medium: return 'Medium';
      case MaintenancePriority.high: return 'High';
      case MaintenancePriority.critical: return 'Critical';
      default: return 'Unknown';
    }
  }

  // Optional: copyWith method
  MaintenanceTaskEntity copyWith({
    String? id,
    String? vehicleId,
    String? vehicleName,
    String? taskDescription,
    DateTime? scheduledDate,
    DateTime? completionDate, // Use ValueGetter for explicit null setting if needed
    MaintenanceStatus? status,
    MaintenancePriority? priority,
    String? notes,         // Use ValueGetter for explicit null setting if needed
    double? cost,          // Use ValueGetter for explicit null setting if needed
    String? assignedMechanic, // Use ValueGetter for explicit null setting if needed
  }) {
    return MaintenanceTaskEntity(
      id: id ?? this.id,
      vehicleId: vehicleId ?? this.vehicleId,
      vehicleName: vehicleName ?? this.vehicleName,
      taskDescription: taskDescription ?? this.taskDescription,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      completionDate: completionDate ?? this.completionDate,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      notes: notes ?? this.notes,
      cost: cost ?? this.cost,
      assignedMechanic: assignedMechanic ?? this.assignedMechanic,
    );
  }
}
