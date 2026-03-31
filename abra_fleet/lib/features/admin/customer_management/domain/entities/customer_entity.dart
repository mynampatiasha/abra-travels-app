// lib/features/admin/customer_management/domain/entities/customer_entity.dart

// Firebase removed - using DateTime instead of Timestamp

class CustomerEntity {
  final String id;
  final String name;
  final String email;
  final String? phoneNumber;
  final String? companyName;
  final String? address;
  final String? department;
  final String? branch; // Add branch field
  final String? employeeId;
  final String role;
  final String status;
  final DateTime registrationDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;

  CustomerEntity({
    required this.id,
    required this.name,
    required this.email,
    this.phoneNumber,
    this.companyName,
    this.address,
    this.department,
    this.branch, // Add branch field
    this.employeeId,
    this.role = 'customer',
    this.status = 'Active',
    DateTime? registrationDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.createdBy,
  })  : registrationDate = registrationDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      if (phoneNumber != null) 'phone': phoneNumber, // ✅ Send as 'phone' to match backend
      if (phoneNumber != null) 'phoneNumber': phoneNumber, // ✅ Also keep phoneNumber for compatibility
      if (companyName != null) 'companyName': companyName,
      if (address != null) 'address': address,
      if (department != null) 'department': department,
      if (branch != null) 'branch': branch, // Add branch field
      if (employeeId != null) 'employeeId': employeeId,
      'role': role,
      'status': status,
      'registrationDate': registrationDate,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      if (createdBy != null) 'createdBy': createdBy,
    };
  }

  // ✅ FIX 1: Add fromJson factory (calls fromMap)
  factory CustomerEntity.fromJson(Map<String, dynamic> json) {
    return CustomerEntity.fromMap(json);
  }

  // Create from Firestore document
  factory CustomerEntity.fromMap(Map<String, dynamic> map) {
    return CustomerEntity(
      id: map['id'] as String,
      name: map['name'] as String,
      email: map['email'] as String,
      phoneNumber: (map['phoneNumber'] ?? map['phone']) as String?, // ✅ Check both phoneNumber and phone
      companyName: map['companyName'] as String?,
      address: map['address'] as String?,
      department: map['department'] as String?,
      branch: map['branch'] as String?, // Add branch field
      employeeId: map['employeeId'] as String?,
      role: (map['role'] as String?) ?? 'customer',
      status: (map['status'] as String?) ?? 'Active',
      registrationDate: _parseDateTime(map['registrationDate']) ?? DateTime.now(),
      createdAt: _parseDateTime(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updatedAt']) ?? DateTime.now(),
      createdBy: map['createdBy'] as String?,
    );
  }

  // Helper method to parse DateTime from various formats
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  // Create a copy with updated fields
  CustomerEntity copyWith({
    String? id,
    String? name,
    String? email,
    String? phoneNumber,
    String? companyName,
    String? address,
    String? department,
    String? branch, // Add branch field
    String? employeeId,
    String? role,
    String? status,
    DateTime? registrationDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
  }) {
    return CustomerEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      companyName: companyName ?? this.companyName,
      address: address ?? this.address,
      department: department ?? this.department,
      branch: branch ?? this.branch, // Add branch field
      employeeId: employeeId ?? this.employeeId,
      role: role ?? this.role,
      status: status ?? this.status,
      registrationDate: registrationDate ?? this.registrationDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
  
    return other is CustomerEntity &&
        other.id == id &&
        other.name == name &&
        other.email == email &&
        other.phoneNumber == phoneNumber &&
        other.companyName == companyName &&
        other.address == address &&
        other.department == department &&
        other.branch == branch && // Add branch field
        other.employeeId == employeeId &&
        other.role == role &&
        other.status == status &&
        other.registrationDate == registrationDate;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        email.hashCode ^
        phoneNumber.hashCode ^
        companyName.hashCode ^
        address.hashCode ^
        department.hashCode ^
        branch.hashCode ^ // Add branch field
        employeeId.hashCode ^
        role.hashCode ^
        status.hashCode ^
        registrationDate.hashCode;
  }

  static CustomerEntity? getCustomerFromListById(List<CustomerEntity> customers, String id) {
    try {
      return customers.firstWhere((customer) => customer.id == id);
    } catch (e) {
      return null;
    }
  }
}