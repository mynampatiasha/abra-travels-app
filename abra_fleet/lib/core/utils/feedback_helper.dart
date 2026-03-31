import 'package:flutter/material.dart';
import '../services/feedback_service.dart';
import '../../features/customer/feedback/widgets/trip_feedback_bottom_sheet.dart';

class FeedbackHelper {
  // Check and show feedback prompt if eligible
  static Future<void> checkAndShowFeedbackPrompt(
    BuildContext context,
    String tripId, {
    String? driverName,
    String? vehicleNumber,
  }) async {
    try {
      final eligibility = await FeedbackService.checkFeedbackEligibility(tripId);

      if (eligibility['eligible'] == true) {
        final feedbackType = eligibility['feedbackType'] ?? 'post_trip';
        
        // Show feedback prompt after a short delay
        Future.delayed(const Duration(seconds: 2), () {
          if (context.mounted) {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              isDismissible: true,
              backgroundColor: Colors.transparent,
              builder: (context) => TripFeedbackBottomSheet(
                tripId: tripId,
                driverName: driverName,
                vehicleNumber: vehicleNumber,
                feedbackType: feedbackType,
              ),
            );

            // Auto-dismiss after 15 seconds if not interacted
            Future.delayed(const Duration(seconds: 15), () {
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            });
          }
        });
      }
    } catch (e) {
      print('Error checking feedback eligibility: $e');
      // Silently fail - don't interrupt user experience
    }
  }

  // Show feedback prompt manually (from trip history)
  static void showFeedbackPrompt(
    BuildContext context,
    String tripId, {
    String? driverName,
    String? vehicleNumber,
    String feedbackType = 'post_trip',
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TripFeedbackBottomSheet(
        tripId: tripId,
        driverName: driverName,
        vehicleNumber: vehicleNumber,
        feedbackType: feedbackType,
      ),
    );
  }

  // Get rating color
  static Color getRatingColor(int rating) {
    if (rating >= 4) return Colors.green;
    if (rating == 3) return Colors.orange;
    return Colors.red;
  }

  // Get rating emoji
  static String getRatingEmoji(int rating) {
    switch (rating) {
      case 5:
        return '😊';
      case 4:
        return '🙂';
      case 3:
        return '😐';
      case 2:
        return '😕';
      case 1:
        return '😞';
      default:
        return '';
    }
  }
}
