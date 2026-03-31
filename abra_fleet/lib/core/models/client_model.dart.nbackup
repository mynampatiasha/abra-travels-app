class ClientModel {
  final String id;
  final String clientId;
  final String name;
  final String email;
  final String phone;
  final String companyName;
  final String organizationName;
  final String status;
  final String role;
  final String? firebaseUid;
  final String? userId;
  final String? address;
  final String? contactPerson;
  final String? gstNumber;
  final String? panNumber;
  final int totalCustomers;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLogin;
  final String? createdBy;
  final String? registrationMethod;

  ClientModel({
    required this.id,
    required this.clientId,
    required this.name,
    required this.email,
    required this.phone,
    required this.companyName,
    required this.organizationName,
    required this.status,
    required this.role,
    this.firebaseUid,
    this.userId,
    this.address,
    this.contactPerson,
    this.gstNumber,
    this.panNumber,
    required this.totalCustomers,
    required this.createdAt,
    required this.updatedAt,
    this.lastLogin,
    this.createdBy,
    this.registrationMethod,
  });

  factory ClientModel.fromJson(Map<String, dynamic> json) {
    return ClientModel(
      id: json['id'] ?? json['_id'] ?? '',
      clientId: json['clientId'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      companyName: json['companyName'] ?? '',
      organizationName: json['organizationName'] ?? '',
      status: json['status'] ?? 'active',
      role: json['role'] ?? 'client',
      firebaseUid: json['firebaseUid'],
      userId: json['userId'],
      address: json['address'],
      contactPerson: json['contactPerson'],
      gstNumber: json['gstNumber'],
      panNumber: json['panNumber'],
      totalCustomers: json['totalCustomers'] ?? 0,
      createdAt: json['createdAt'] != null 
        ? DateTime.parse(json['createdAt']) 
        : DateTime.now(),
      updatedAt: json['updatedAt'] != null 
        ? DateTime.parse(json['updatedAt']) 
        : DateTime.now(),
      lastLogin: json['lastLogin'] != null 
        ? DateTime.parse(json['lastLogin']) 
        : null,
      createdBy: json['createdBy'],
      registrationMethod: json['registrationMethod'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clientId': clientId,
      'name': name,
      'email': email,
      'phone': phone,
      'companyName': companyName,
      'organizationName': organizationName,
      'status': status,
      'role': role,
      'firebaseUid': firebaseUid,
      'userId': userId,
      'address': address,
      'contactPerson': contactPerson,
      'gstNumber': gstNumber,
      'panNumber': panNumber,
      'totalCustomers': totalCustomers,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastLogin': lastLogin?.toIso8601String(),
      'createdBy': createdBy,
      'registrationMethod': registrationMethod,
    };
  }

  ClientModel copyWith({
    String? id,
    String? clientId,
    String? name,
    String? email,
    String? phone,
    String? companyName,
    String? organizationName,
    String? status,
    String? role,
    String? firebaseUid,
    String? userId,
    String? address,
    String? contactPerson,
    String? gstNumber,
    String? panNumber,
    int? totalCustomers,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastLogin,
    String? createdBy,
    String? registrationMethod,
  }) {
    return ClientModel(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      companyName: companyName ?? this.companyName,
      organizationName: organizationName ?? this.organizationName,
      status: status ?? this.status,
      role: role ?? this.role,
      firebaseUid: firebaseUid ?? this.firebaseUid,
      userId: userId ?? this.userId,
      address: address ?? this.address,
      contactPerson: contactPerson ?? this.contactPerson,
      gstNumber: gstNumber ?? this.gstNumber,
      panNumber: panNumber ?? this.panNumber,
      totalCustomers: totalCustomers ?? this.totalCustomers,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLogin: lastLogin ?? this.lastLogin,
      createdBy: createdBy ?? this.createdBy,
      registrationMethod: registrationMethod ?? this.registrationMethod,
    );
  }

  @override
  String toString() {
    return 'ClientModel(id: $id, clientId: $clientId, name: $name, email: $email, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ClientModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  // Helper getters
  bool get isActive => status.toLowerCase() == 'active';
  bool get isPending => status.toLowerCase() == 'pending';
  bool get isInactive => status.toLowerCase() == 'inactive';
  bool get isDeleted => status.toLowerCase() == 'deleted';
  
  bool get hasFirebaseAccount => firebaseUid != null && firebaseUid!.isNotEmpty;
  bool get hasCustomers => totalCustomers > 0;
  
  String get displayName => name.isNotEmpty ? name : email;
  String get displayCompany => companyName.isNotEmpty ? companyName : organizationName;
  
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
}

// Client summary model for dashboard
class ClientSummary {
  final int total;
  final int active;
  final int inactive;
  final int pending;
  final int deleted;
  final int withCustomers;
  final int withoutCustomers;

  ClientSummary({
    required this.total,
    required this.active,
    required this.inactive,
    required this.pending,
    required this.deleted,
    required this.withCustomers,
    required this.withoutCustomers,
  });

  factory ClientSummary.fromJson(Map<String, dynamic> json) {
    return ClientSummary(
      total: json['total'] ?? 0,
      active: json['active'] ?? 0,
      inactive: json['inactive'] ?? 0,
      pending: json['pending'] ?? 0,
      deleted: json['deleted'] ?? 0,
      withCustomers: json['withCustomers'] ?? 0,
      withoutCustomers: json['withoutCustomers'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total': total,
      'active': active,
      'inactive': inactive,
      'pending': pending,
      'deleted': deleted,
      'withCustomers': withCustomers,
      'withoutCustomers': withoutCustomers,
    };
  }
}

// Client analytics model
class ClientAnalytics {
  final int totalTrips;
  final int activeTrips;
  final int completedTrips;
  final int cancelledTrips;
  final double totalDistance;
  final double totalRevenue;
  final int totalCustomers;
  final int activeCustomers;
  final Map<String, dynamic> monthlyStats;

  ClientAnalytics({
    required this.totalTrips,
    required this.activeTrips,
    required this.completedTrips,
    required this.cancelledTrips,
    required this.totalDistance,
    required this.totalRevenue,
    required this.totalCustomers,
    required this.activeCustomers,
    required this.monthlyStats,
  });

  factory ClientAnalytics.fromJson(Map<String, dynamic> json) {
    return ClientAnalytics(
      totalTrips: json['totalTrips'] ?? 0,
      activeTrips: json['activeTrips'] ?? 0,
      completedTrips: json['completedTrips'] ?? 0,
      cancelledTrips: json['cancelledTrips'] ?? 0,
      totalDistance: (json['totalDistance'] ?? 0).toDouble(),
      totalRevenue: (json['totalRevenue'] ?? 0).toDouble(),
      totalCustomers: json['totalCustomers'] ?? 0,
      activeCustomers: json['activeCustomers'] ?? 0,
      monthlyStats: json['monthlyStats'] ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalTrips': totalTrips,
      'activeTrips': activeTrips,
      'completedTrips': completedTrips,
      'cancelledTrips': cancelledTrips,
      'totalDistance': totalDistance,
      'totalRevenue': totalRevenue,
      'totalCustomers': totalCustomers,
      'activeCustomers': activeCustomers,
      'monthlyStats': monthlyStats,
    };
  }
}