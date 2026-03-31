class CustomerModel {
  final String id;
  final String customerId;
  final String name;
  final String email;
  final String phone;
  final String companyName;
  final String department;
  final String branch;
  final String employeeId;
  final String status;
  final String role;
  final String? firebaseUid;
  final String? clientId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLogin;
  final String? createdBy;
  final String? registrationMethod;
  final String? assignmentType; // 'explicit', 'domain', 'company'

  CustomerModel({
    required this.id,
    required this.customerId,
    required this.name,
    required this.email,
    required this.phone,
    required this.companyName,
    required this.department,
    required this.branch,
    required this.employeeId,
    required this.status,
    required this.role,
    this.firebaseUid,
    this.clientId,
    required this.createdAt,
    required this.updatedAt,
    this.lastLogin,
    this.createdBy,
    this.registrationMethod,
    this.assignmentType,
  });

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    // Helper function to safely extract string from potentially nested objects
    String _safeString(dynamic value, [String defaultValue = '']) {
      if (value == null) return defaultValue;
      if (value is String) return value;
      if (value is Map) {
        // If it's a map, try to extract a meaningful string value
        return value['name']?.toString() ?? 
               value['value']?.toString() ?? 
               value.toString();
      }
      return value.toString();
    }

    return CustomerModel(
      id: _safeString(json['id'] ?? json['_id']),
      customerId: _safeString(json['customerId']),
      name: _safeString(json['name']),
      email: _safeString(json['email']),
      phone: _safeString(json['phone']),
      companyName: _safeString(json['companyName']),
      department: _safeString(json['department']),
      branch: _safeString(json['branch']),
      employeeId: _safeString(json['employeeId']),
      status: _safeString(json['status'], 'active'),
      role: _safeString(json['role'], 'customer'),
      firebaseUid: json['firebaseUid'] is String ? json['firebaseUid'] : null,
      clientId: json['clientId'] is String ? json['clientId'] : null,
      createdAt: json['createdAt'] != null 
        ? (json['createdAt'] is String 
            ? DateTime.parse(json['createdAt']) 
            : DateTime.now())
        : DateTime.now(),
      updatedAt: json['updatedAt'] != null 
        ? (json['updatedAt'] is String 
            ? DateTime.parse(json['updatedAt']) 
            : DateTime.now())
        : DateTime.now(),
      lastLogin: json['lastLogin'] != null && json['lastLogin'] is String
        ? DateTime.parse(json['lastLogin']) 
        : null,
      createdBy: json['createdBy'] is String ? json['createdBy'] : null,
      registrationMethod: json['registrationMethod'] is String ? json['registrationMethod'] : null,
      assignmentType: json['assignmentType'] is String ? json['assignmentType'] : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customerId': customerId,
      'name': name,
      'email': email,
      'phone': phone,
      'companyName': companyName,
      'department': department,
      'branch': branch,
      'employeeId': employeeId,
      'status': status,
      'role': role,
      'firebaseUid': firebaseUid,
      'clientId': clientId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastLogin': lastLogin?.toIso8601String(),
      'createdBy': createdBy,
      'registrationMethod': registrationMethod,
      'assignmentType': assignmentType,
    };
  }

  CustomerModel copyWith({
    String? id,
    String? customerId,
    String? name,
    String? email,
    String? phone,
    String? companyName,
    String? department,
    String? branch,
    String? employeeId,
    String? status,
    String? role,
    String? firebaseUid,
    String? clientId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastLogin,
    String? createdBy,
    String? registrationMethod,
    String? assignmentType,
  }) {
    return CustomerModel(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      companyName: companyName ?? this.companyName,
      department: department ?? this.department,
      branch: branch ?? this.branch,
      employeeId: employeeId ?? this.employeeId,
      status: status ?? this.status,
      role: role ?? this.role,
      firebaseUid: firebaseUid ?? this.firebaseUid,
      clientId: clientId ?? this.clientId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLogin: lastLogin ?? this.lastLogin,
      createdBy: createdBy ?? this.createdBy,
      registrationMethod: registrationMethod ?? this.registrationMethod,
      assignmentType: assignmentType ?? this.assignmentType,
    );
  }

  @override
  String toString() {
    return 'CustomerModel(id: $id, customerId: $customerId, name: $name, email: $email, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CustomerModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  // Helper getters
  bool get isActive => status.toLowerCase() == 'active';
  bool get isPending => status.toLowerCase() == 'pending';
  bool get isInactive => status.toLowerCase() == 'inactive';
  bool get isDeleted => status.toLowerCase() == 'deleted';
  
  bool get hasFirebaseAccount => firebaseUid != null && firebaseUid!.isNotEmpty;
  bool get isAssignedToClient => clientId != null && clientId!.isNotEmpty;
  bool get hasEmployeeId => employeeId.isNotEmpty;
  
  String get displayName => name.isNotEmpty ? name : email;
  String get displayId => employeeId.isNotEmpty ? employeeId : customerId;
  
  // Assignment type helpers
  bool get isExplicitlyAssigned => assignmentType == 'explicit';
  bool get isDomainMatched => assignmentType == 'domain';
  bool get isCompanyMatched => assignmentType == 'company';
  
  // Status color helpers for UI
  String get statusColor {
    switch (status.toLowerCase()) {
      case 'active':
        return '#4CAF50'; // Green
      case 'pending':
        return '#FF9800'; // Orange
      case 'inactive':
        return '#9E9E9E'; // Grey
      case 'deleted':
        return '#F44336'; // Red
      default:
        return '#9E9E9E';
    }
  }

  // Assignment type color helpers for UI
  String get assignmentTypeColor {
    switch (assignmentType) {
      case 'explicit':
        return '#4CAF50'; // Green
      case 'domain':
        return '#2196F3'; // Blue
      case 'company':
        return '#FF9800'; // Orange
      default:
        return '#9E9E9E'; // Grey
    }
  }

  String get assignmentTypeLabel {
    switch (assignmentType) {
      case 'explicit':
        return 'Explicitly Assigned';
      case 'domain':
        return 'Domain Matched';
      case 'company':
        return 'Company Matched';
      default:
        return 'Not Assigned';
    }
  }
}

// Customer summary model for dashboard
class CustomerSummary {
  final int total;
  final int active;
  final int inactive;
  final int pending;
  final int deleted;
  final int assignedToClients;
  final int unassigned;
  final int withEmployeeId;
  final int withoutEmployeeId;

  CustomerSummary({
    required this.total,
    required this.active,
    required this.inactive,
    required this.pending,
    required this.deleted,
    required this.assignedToClients,
    required this.unassigned,
    required this.withEmployeeId,
    required this.withoutEmployeeId,
  });

  factory CustomerSummary.fromJson(Map<String, dynamic> json) {
    return CustomerSummary(
      total: json['total'] ?? 0,
      active: json['active'] ?? 0,
      inactive: json['inactive'] ?? 0,
      pending: json['pending'] ?? 0,
      deleted: json['deleted'] ?? 0,
      assignedToClients: json['assignedToClients'] ?? 0,
      unassigned: json['unassigned'] ?? 0,
      withEmployeeId: json['withEmployeeId'] ?? 0,
      withoutEmployeeId: json['withoutEmployeeId'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total': total,
      'active': active,
      'inactive': inactive,
      'pending': pending,
      'deleted': deleted,
      'assignedToClients': assignedToClients,
      'unassigned': unassigned,
      'withEmployeeId': withEmployeeId,
      'withoutEmployeeId': withoutEmployeeId,
    };
  }
}

// Customer analytics model
class CustomerAnalytics {
  final int totalTrips;
  final int activeTrips;
  final int completedTrips;
  final int cancelledTrips;
  final double totalDistance;
  final double averageRating;
  final Map<String, dynamic> monthlyStats;
  final Map<String, dynamic> departmentStats;

  CustomerAnalytics({
    required this.totalTrips,
    required this.activeTrips,
    required this.completedTrips,
    required this.cancelledTrips,
    required this.totalDistance,
    required this.averageRating,
    required this.monthlyStats,
    required this.departmentStats,
  });

  factory CustomerAnalytics.fromJson(Map<String, dynamic> json) {
    return CustomerAnalytics(
      totalTrips: json['totalTrips'] ?? 0,
      activeTrips: json['activeTrips'] ?? 0,
      completedTrips: json['completedTrips'] ?? 0,
      cancelledTrips: json['cancelledTrips'] ?? 0,
      totalDistance: (json['totalDistance'] ?? 0).toDouble(),
      averageRating: (json['averageRating'] ?? 0).toDouble(),
      monthlyStats: json['monthlyStats'] ?? {},
      departmentStats: json['departmentStats'] ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalTrips': totalTrips,
      'activeTrips': activeTrips,
      'completedTrips': completedTrips,
      'cancelledTrips': cancelledTrips,
      'totalDistance': totalDistance,
      'averageRating': averageRating,
      'monthlyStats': monthlyStats,
      'departmentStats': departmentStats,
    };
  }
}

// Customer trip model
class CustomerTrip {
  final String id;
  final String tripId;
  final String customerId;
  final String pickupLocation;
  final String dropLocation;
  final String status;
  final DateTime scheduledTime;
  final DateTime? startTime;
  final DateTime? endTime;
  final double? distance;
  final String? driverName;
  final String? vehicleNumber;
  final double? rating;

  CustomerTrip({
    required this.id,
    required this.tripId,
    required this.customerId,
    required this.pickupLocation,
    required this.dropLocation,
    required this.status,
    required this.scheduledTime,
    this.startTime,
    this.endTime,
    this.distance,
    this.driverName,
    this.vehicleNumber,
    this.rating,
  });

  factory CustomerTrip.fromJson(Map<String, dynamic> json) {
    return CustomerTrip(
      id: json['id'] ?? json['_id'] ?? '',
      tripId: json['tripId'] ?? '',
      customerId: json['customerId'] ?? '',
      pickupLocation: json['pickupLocation'] ?? '',
      dropLocation: json['dropLocation'] ?? '',
      status: json['status'] ?? '',
      scheduledTime: DateTime.parse(json['scheduledTime']),
      startTime: json['startTime'] != null ? DateTime.parse(json['startTime']) : null,
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      distance: json['distance']?.toDouble(),
      driverName: json['driverName'],
      vehicleNumber: json['vehicleNumber'],
      rating: json['rating']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tripId': tripId,
      'customerId': customerId,
      'pickupLocation': pickupLocation,
      'dropLocation': dropLocation,
      'status': status,
      'scheduledTime': scheduledTime.toIso8601String(),
      'startTime': startTime?.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'distance': distance,
      'driverName': driverName,
      'vehicleNumber': vehicleNumber,
      'rating': rating,
    };
  }

  // Helper getters
  bool get isActive => status.toLowerCase() == 'active';
  bool get isCompleted => status.toLowerCase() == 'completed';
  bool get isCancelled => status.toLowerCase() == 'cancelled';
  bool get isPending => status.toLowerCase() == 'pending';
  
  bool get hasRating => rating != null && rating! > 0;
  bool get isOngoing => startTime != null && endTime == null;
  
  Duration? get tripDuration {
    if (startTime != null && endTime != null) {
      return endTime!.difference(startTime!);
    }
    return null;
  }
}