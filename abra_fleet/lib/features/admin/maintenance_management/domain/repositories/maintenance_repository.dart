// File: lib/features/admin/maintenance_management/domain/repositories/maintenance_repository.dart
// Defines the contract for maintenance task data operations.

import 'package:abra_fleet/features/admin/maintenance_management/domain/entities/maintenance_task_entity.dart'; // Import your MaintenanceTask entity

abstract class MaintenanceRepository {
  // Get a list of all maintenance tasks.
  // Optionally, could take filters (e.g., by vehicleId, status).
  Future<List<MaintenanceTaskEntity>> getMaintenanceTasks();

  // Get a specific maintenance task by its ID.
  Future<MaintenanceTaskEntity?> getMaintenanceTaskById(String id);

  // Add a new maintenance task.
  // Returns the newly added task (possibly with a server-generated ID).
  Future<MaintenanceTaskEntity> addMaintenanceTask(MaintenanceTaskEntity task);

  // Update an existing maintenance task.
  Future<void> updateMaintenanceTask(MaintenanceTaskEntity task);

  // Delete a maintenance task by its ID.
  Future<void> deleteMaintenanceTask(String id);
}
