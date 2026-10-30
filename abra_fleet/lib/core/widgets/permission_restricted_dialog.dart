// lib/core/widgets/permission_restricted_dialog.dart
// ============================================================================
// 🔐 PERMISSION RESTRICTED OVERLAY DIALOG
// ============================================================================
// Displays an elegant overlay modal card when an employee user lacks
// 'edit_delete' permissions to perform an edit or delete action.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:abra_fleet/core/services/permission_service.dart';

class PermissionRestrictedDialog extends StatelessWidget {
  final String moduleName;

  const PermissionRestrictedDialog({
    Key? key,
    required this.moduleName,
  }) : super(key: key);

  /// Show the permission restricted overlay card dialog
  static Future<void> show(
    BuildContext context, {
    String moduleName = 'records',
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return PermissionRestrictedDialog(moduleName: moduleName);
      },
    );
  }

  /// Helper to check edit/delete permission and automatically show the dialog if restricted
  /// Returns `true` if user has permission, `false` if restricted (and dialog was displayed).
  static Future<bool> checkAndWarn(
    BuildContext context, {
    required String permissionKey,
    String moduleName = 'records',
  }) async {
    final canEdit = await PermissionService().canEditDelete(permissionKey);
    if (!canEdit && context.mounted) {
      show(context, moduleName: moduleName);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon Header with gentle amber tint
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7), // Amber 100
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFDE68A), // Amber 200
                      width: 2,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.lock_person_rounded,
                      color: Color(0xFFD97706), // Amber 600
                      size: 38,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                const Text(
                  'Access Restricted',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B), // Slate 800
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 12),

                // Message Box
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC), // Slate 50
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    'You do not have permission to edit or delete $moduleName. Please contact your admin team.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF475569), // Slate 600
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Action Button
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D47A1), // Brand Navy/Blue
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Understood',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
