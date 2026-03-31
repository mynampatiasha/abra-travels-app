// lib/features/hrm_feedback/domain/models/hrm_feedback_model.dart

class HrmFeedbackModel {
  final String id;
  final String email;
  final String name;
  final String feedbackType;
  final String subject;
  final String message;
  final int rating;
  final DateTime dateSubmitted;
  final String status;
  final String? adminResponse;
  final DateTime? responseDate;
  final String? parentFeedbackId;
  final String source; // 'customer', 'employee', or 'driver'

  HrmFeedbackModel({
    required this.id,
    required this.email,
    required this.name,
    required this.feedbackType,
    required this.subject,
    required this.message,
    required this.rating,
    required this.dateSubmitted,
    required this.status,
    this.adminResponse,
    this.responseDate,
    this.parentFeedbackId,
    required this.source,
  });

  factory HrmFeedbackModel.fromJson(Map<String, dynamic> json) {
    return HrmFeedbackModel(
      id: json['_id'] ?? json['id'] ?? '',
      email: json['customer_email'] ?? json['employee_email'] ?? json['driver_email'] ?? '',
      name: json['customer_name'] ?? json['employee_name'] ?? json['driver_name'] ?? '',
      feedbackType: json['feedback_type'] ?? 'general',
      subject: json['subject'] ?? '',
      message: json['message'] ?? '',
      rating: json['rating'] ?? 5,
      dateSubmitted: json['date_submitted'] != null
          ? DateTime.parse(json['date_submitted'])
          : DateTime.now(),
      status: json['status'] ?? 'pending',
      adminResponse: json['admin_response'],
      responseDate: json['response_date'] != null
          ? DateTime.parse(json['response_date'])
          : null,
      parentFeedbackId: json['parent_feedback_id'],
      source: json['source'] ?? 'customer',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      if (source == 'customer')
        'customer_email': email
      else if (source == 'employee')
        'employee_email': email
      else
        'driver_email': email,
      if (source == 'customer')
        'customer_name': name
      else if (source == 'employee')
        'employee_name': name
      else
        'driver_name': name,
      'feedback_type': feedbackType,
      'subject': subject,
      'message': message,
      'rating': rating,
      'date_submitted': dateSubmitted.toIso8601String(),
      'status': status,
      'admin_response': adminResponse,
      'response_date': responseDate?.toIso8601String(),
      'parent_feedback_id': parentFeedbackId,
      'source': source,
    };
  }

  bool get hasAdminResponse => adminResponse != null && adminResponse!.isNotEmpty;
}

class HrmFeedbackStats {
  final int total;
  final int pending;
  final int responded;
  final Map<String, int> byType;
  final double avgRating;
  final int recentCount;

  HrmFeedbackStats({
    required this.total,
    required this.pending,
    required this.responded,
    required this.byType,
    required this.avgRating,
    required this.recentCount,
  });

  factory HrmFeedbackStats.fromJson(Map<String, dynamic> json) {
    return HrmFeedbackStats(
      total: json['total'] ?? 0,
      pending: json['pending'] ?? 0,
      responded: json['responded'] ?? 0,
      byType: Map<String, int>.from(json['by_type'] ?? {}),
      avgRating: (json['avg_rating'] ?? 0).toDouble(),
      recentCount: json['recent_count'] ?? 0,
    );
  }
}