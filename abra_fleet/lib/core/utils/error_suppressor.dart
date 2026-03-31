// lib/core/utils/error_suppressor.dart
// ✅ UTILITY TO SUPPRESS ALL ERROR MESSAGES ON SCREEN
// All errors are logged to console only, never shown to users

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// ✅ Suppress error SnackBar and log to console instead
void showErrorInConsole(BuildContext context, String message, {String? errorContext}) {
  // Don't show SnackBar, just log to console
  debugPrint('🔇 [${errorContext ?? 'Error'}] $message');
}

/// ✅ Suppress error dialog and log to console instead
void showErrorDialogInConsole(BuildContext context, String title, String message, {String? errorContext}) {
  // Don't show dialog, just log to console
  debugPrint('🔇 [${errorContext ?? 'Error Dialog'}] $title: $message');
}

/// ✅ Extension to suppress error SnackBars
extension ErrorSuppressionExtension on ScaffoldMessengerState {
  /// Show error in console only, don't display SnackBar
  void showErrorInConsoleOnly(String message, {String? context}) {
    debugPrint('🔇 [${context ?? 'SnackBar'}] $message');
    // Don't call showSnackBar
  }
}

/// ✅ Safe ScaffoldMessenger wrapper that suppresses error messages
class SafeScaffoldMessenger {
  /// Show success message (allowed)
  static void showSuccess(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show info message (allowed)
  static void showInfo(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF3B82F6),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// ✅ Suppress error message - log to console only
  static void showError(BuildContext context, String message, {String? errorContext}) {
    // Don't show SnackBar, just log to console
    debugPrint('🔇 [${errorContext ?? 'Error'}] $message');
  }

  /// ✅ Suppress warning message - log to console only
  static void showWarning(BuildContext context, String message, {String? errorContext}) {
    // Don't show SnackBar, just log to console
    debugPrint('🔇 [${errorContext ?? 'Warning'}] $message');
  }
}

/// ✅ Safe Dialog wrapper that suppresses error dialogs
class SafeDialog {
  /// ✅ Suppress error dialog - log to console only
  static void showError(
    BuildContext context, {
    required String title,
    required String message,
    String? errorContext,
  }) {
    // Don't show dialog, just log to console
    debugPrint('🔇 [${errorContext ?? 'Error Dialog'}] $title: $message');
  }

  /// Show confirmation dialog (allowed)
  static Future<bool?> showConfirmation(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  /// Show success dialog (allowed)
  static void showSuccess(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF10B981)),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
