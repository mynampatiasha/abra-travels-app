// File: lib/features/auth/domain/entities/user_entity.dart
// Updated user entity with phone number and photoUrl support

class UserEntity {
  final String id; // MongoDB _id
  final String? firebaseUid; // Firebase Auth UID
  final String? email;
  final String? name;
  final String? role;
  final String? phoneNumber;
  final String? photoUrl; // 🔥 ADDED: Photo URL field
  final String? profileImageUrl;
  final String? organizationId;

  const UserEntity({
    required this.id,
    this.firebaseUid,
    this.email,
    this.name,
    this.role,
    this.phoneNumber,
    this.photoUrl, // 🔥 ADDED
    this.profileImageUrl,
    this.organizationId,
  });

  // Empty user constant for unauthenticated state
  static const empty = UserEntity(id: '');

  // Check if user is authenticated
  bool get isEmpty => id.isEmpty;
  bool get isNotEmpty => !isEmpty;
  bool get isAuthenticated => isNotEmpty;

  // Check if user has phone number for notifications
  bool get hasPhoneNumber => phoneNumber != null && phoneNumber!.isNotEmpty;

  // Equality and hashCode for proper comparison
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          firebaseUid == other.firebaseUid &&
          email == other.email &&
          name == other.name &&
          role == other.role &&
          phoneNumber == other.phoneNumber &&
          photoUrl == other.photoUrl &&
          profileImageUrl == other.profileImageUrl &&
          organizationId == other.organizationId;

  @override
  int get hashCode =>
      id.hashCode ^
      firebaseUid.hashCode ^
      email.hashCode ^
      name.hashCode ^
      role.hashCode ^
      phoneNumber.hashCode ^
      photoUrl.hashCode ^
      profileImageUrl.hashCode ^
      organizationId.hashCode;

  // toString for debugging
  @override
  String toString() {
    return 'UserEntity{id: $id, firebaseUid: $firebaseUid, email: $email, name: $name, role: $role, phoneNumber: $phoneNumber, photoUrl: $photoUrl, organizationId: $organizationId}';
  }

  // Copy method for creating modified instances
  UserEntity copyWith({
    String? id,
    String? firebaseUid,
    String? email,
    String? name,
    String? role,
    String? phoneNumber,
    String? photoUrl,
    String? profileImageUrl,
    String? organizationId,
  }) {
    return UserEntity(
      id: id ?? this.id,
      firebaseUid: firebaseUid ?? this.firebaseUid,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      photoUrl: photoUrl ?? this.photoUrl,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      organizationId: organizationId ?? this.organizationId,
    );
  }

  // Factory method to create from MongoDB/Backend API data
  factory UserEntity.fromJson(Map<String, dynamic> json) {
    return UserEntity(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      firebaseUid: json['firebaseUid'],
      email: json['email'],
      name: json['name'],
      role: json['role'],
      phoneNumber: json['phone'] ?? json['phoneNumber'],
      photoUrl: json['photoUrl'] ?? json['profileImageUrl'],
      profileImageUrl: json['profileImageUrl'] ?? json['photoUrl'],
      organizationId: json['organizationId'],
    );
  }

  // Convert to JSON for API requests
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    
    if (id.isNotEmpty) data['id'] = id;
    if (firebaseUid != null) data['firebaseUid'] = firebaseUid;
    if (email != null) data['email'] = email;
    if (name != null) data['name'] = name;
    if (role != null) data['role'] = role;
    if (phoneNumber != null) data['phone'] = phoneNumber;
    if (photoUrl != null) data['photoUrl'] = photoUrl;
    if (profileImageUrl != null) data['profileImageUrl'] = profileImageUrl;
    if (organizationId != null) data['organizationId'] = organizationId;

    return data;
  }
}