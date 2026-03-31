// File: lib/features/admin/customer_management/widgets/detailed_error_dialog.dart
// User-friendly error dialog for non-technical admins

import 'package:flutter/material.dart';

class DetailedErrorDialog extends StatelessWidget {
  final String title;
  final String message;
  final Map<String, dynamic>? details;
  final String? suggestion;

  const DetailedErrorDialog({
    super.key,
    required this.title,
    required this.message,
    this.details,
    this.suggestion,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Main message
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),

                    if (details != null) ...[
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 16),
                      
                      // Details section
                      _buildDetailsSection(details!),
                    ],

                    if (suggestion != null) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.lightbulb_outline, 
                                 color: Colors.blue.shade700, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Solution',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    suggestion!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.blue.shade900,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsSection(Map<String, dynamic> details) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Details',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...details.entries.map((entry) => _buildDetailItem(entry.key, entry.value)),
      ],
    );
  }

  Widget _buildDetailItem(String key, dynamic value) {
    // Format key to be more readable
    final formattedKey = _formatKey(key);
    
    // Handle different value types
    if (value is Map) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formattedKey,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: (value as Map<String, dynamic>).entries
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_formatKey(e.key)}: ',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  _formatValue(e.value),
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      );
    } else if (value is List) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formattedKey,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            ...value.map((item) => Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontSize: 14)),
                      Expanded(
                        child: Text(
                          _formatValue(item),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 180,
              child: Text(
                formattedKey,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            Expanded(
              child: Text(
                _formatValue(value),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }
  }

  String _formatKey(String key) {
    // Convert camelCase or snake_case to Title Case
    return key
        .replaceAllMapped(
          RegExp(r'([A-Z])'),
          (match) => ' ${match.group(1)}',
        )
        .replaceAll('_', ' ')
        .trim()
        .split(' ')
        .map((word) => word.isEmpty
            ? ''
            : word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'N/A';
    if (value is String) return value;
    if (value is num) return value.toString();
    if (value is bool) return value ? 'Yes' : 'No';
    if (value is Map) {
      return value.entries
          .map((e) => '${_formatKey(e.key.toString())}: ${_formatValue(e.value)}')
          .join(', ');
    }
    if (value is List) {
      return value.map((item) => _formatValue(item)).join(', ');
    }
    return value.toString();
  }

  /// Show error dialog from API response
  static void showFromApiError(
    BuildContext context,
    Map<String, dynamic> errorResponse,
  ) {
    final message = errorResponse['message'] ?? 'An error occurred';
    final error = errorResponse['error'];
    final details = errorResponse['details'];
    
    String title = '❌ Operation Failed';
    String? suggestion;
    
    // Customize based on error type
    if (error == 'COMPATIBILITY_CONFLICT') {
      title = '🚫 Vehicle Compatibility Issue';
      suggestion = details?['suggestion'] ?? 
                  'Please select a different vehicle or choose customers from the same company.';
    } else if (error == 'VEHICLE_FULL') {
      title = '💺 Vehicle is Full';
      suggestion = details?['suggestion'] ?? 
                  'Please select a vehicle with more capacity or split customers into multiple routes.';
    } else if (error == 'INSUFFICIENT_CAPACITY') {
      title = '💺 Insufficient Capacity';
      suggestion = details?['suggestion'];
    } else if (error == 'FEASIBILITY_FAILED') {
      title = '⏰ Driver Cannot Reach On Time';
      suggestion = details?['suggestion'];
    }
    
    showDialog(
      context: context,
      builder: (context) => DetailedErrorDialog(
        title: title,
        message: message,
        details: details,
        suggestion: suggestion,
      ),
    );
  }
}
