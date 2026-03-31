// lib/features/admin/rosters/assignment_dialog.dart

import 'package:flutter/material.dart';
import 'package:abra_fleet/core/services/assignment_service.dart';
import 'package:abra_fleet/features/admin/rosters/vehicle_selection_dialog.dart';

/// Simple assignment dialog that shows vehicle selection
/// This is a convenience wrapper for the VehicleSelectionDialog
class AssignmentDialog extends StatelessWidget {
  final List<String> rosterIds;
  final AssignmentService assignmentService;
  final VoidCallback onAssignmentSuccess;
  final String? title;

  const AssignmentDialog({
    super.key,
    required this.rosterIds,
    required this.assignmentService,
    required this.onAssignmentSuccess,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    return VehicleSelectionDialog(
      rosterIds: rosterIds,
      assignmentService: assignmentService,
      onAssignmentSuccess: onAssignmentSuccess,
    );
  }
  
  /// Show assignment dialog
  static Future<bool?> show(
    BuildContext context, {
    required List<String> rosterIds,
    required AssignmentService assignmentService,
    required VoidCallback onAssignmentSuccess,
    String? title,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AssignmentDialog(
        rosterIds: rosterIds,
        assignmentService: assignmentService,
        onAssignmentSuccess: onAssignmentSuccess,
        title: title,
      ),
    );
  }
}