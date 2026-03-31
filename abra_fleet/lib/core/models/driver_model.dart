// lib/core/models/driver_model.dart
// ============================================================================
// DRIVER MODEL - JWT Authentication Only (NO FIREBASE)
// ============================================================================
// This model represents driver data structure for JWT-based authentication
// - Removed Firebase UID field (uid)
// - Uses MongoDB _id as primary identifier
// - Compatible with centralized driver system
// ============================================================================

class DriverModel {
  final String? id;                    // MongoDB _id
  final String driverId;               // Unique driver identifier
  final String name;                   // Flat name field for easy access
  final String email;                  // Flat email field for easy access
  final String phone;                  // Flat phone field for easy access
  final PersonalInfo personalInfo;     // Detailed personal information
  final License license;               // License information
  final EmergencyContact? emergencyContact;
  final Address? address;
  final Employment? employment;
  final BankDetails? bankDetails;
  final String status;                 // Driver status (active, inactive, on_leave)
  final String? assignedVehicle;       // Assigned vehicle ID
  final List<Document>? documents;     // Driver documents
  final DateTime? joinedDate;          // Date when driver joined
  final DateTime createdAt;            // Record creation date
  final DateTime updatedAt;            // Last update date

  DriverModel({
    this.id,
    required this.driverId,
    required this.name,
    required this.email,
    required this.phone,
    required this.personalInfo,
    required this.license,
    this.emergencyContact,
    this.address,
    this.employment,
    this.bankDetails,
    required this.status,
    this.assignedVehicle,
    this.documents,
    this.joinedDate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DriverModel.fromJson(Map<String, dynamic> json) {
    return DriverModel(
      id: json['_id']?.toString(),
      driverId: json['driverId'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      personalInfo: PersonalInfo.fromJson(json['personalInfo'] ?? {}),
      license: License.fromJson(json['license'] ?? {}),
      emergencyContact: json['emergencyContact'] != null 
          ? EmergencyContact.fromJson(json['emergencyContact'])
          : null,
      address: json['address'] != null 
          ? Address.fromJson(json['address'])
          : null,
      employment: json['employment'] != null 
          ? Employment.fromJson(json['employment'])
          : null,
      bankDetails: json['bankDetails'] != null 
          ? BankDetails.fromJson(json['bankDetails'])
          : null,
      status: json['status'] ?? 'active',
      assignedVehicle: json['assignedVehicle'],
      documents: json['documents'] != null
          ? (json['documents'] as List).map((doc) => Document.fromJson(doc)).toList()
          : null,
      joinedDate: json['joinedDate'] != null 
          ? DateTime.parse(json['joinedDate'])
          : null,
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updatedAt'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) '_id': id,
      'driverId': driverId,
      'name': name,
      'email': email,
      'phone': phone,
      'personalInfo': personalInfo.toJson(),
      'license': license.toJson(),
      if (emergencyContact != null) 'emergencyContact': emergencyContact!.toJson(),
      if (address != null) 'address': address!.toJson(),
      if (employment != null) 'employment': employment!.toJson(),
      if (bankDetails != null) 'bankDetails': bankDetails!.toJson(),
      'status': status,
      if (assignedVehicle != null) 'assignedVehicle': assignedVehicle,
      if (documents != null) 'documents': documents!.map((doc) => doc.toJson()).toList(),
      if (joinedDate != null) 'joinedDate': joinedDate!.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  DriverModel copyWith({
    String? id,
    String? driverId,
    String? name,
    String? email,
    String? phone,
    PersonalInfo? personalInfo,
    License? license,
    EmergencyContact? emergencyContact,
    Address? address,
    Employment? employment,
    BankDetails? bankDetails,
    String? status,
    String? assignedVehicle,
    List<Document>? documents,
    DateTime? joinedDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DriverModel(
      id: id ?? this.id,
      driverId: driverId ?? this.driverId,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      personalInfo: personalInfo ?? this.personalInfo,
      license: license ?? this.license,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      address: address ?? this.address,
      employment: employment ?? this.employment,
      bankDetails: bankDetails ?? this.bankDetails,
      status: status ?? this.status,
      assignedVehicle: assignedVehicle ?? this.assignedVehicle,
      documents: documents ?? this.documents,
      joinedDate: joinedDate ?? this.joinedDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class PersonalInfo {
  final String firstName;
  final String lastName;
  final String phone;
  final String email;
  final String? dateOfBirth;
  final String? bloodGroup;
  final String? gender;

  PersonalInfo({
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.email,
    this.dateOfBirth,
    this.bloodGroup,
    this.gender,
  });

  factory PersonalInfo.fromJson(Map<String, dynamic> json) {
    return PersonalInfo(
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'] ?? '',
      dateOfBirth: json['dateOfBirth'],
      bloodGroup: json['bloodGroup'],
      gender: json['gender'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'phone': phone,
      'email': email,
      if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
      if (bloodGroup != null) 'bloodGroup': bloodGroup,
      if (gender != null) 'gender': gender,
    };
  }
}

class License {
  final String licenseNumber;
  final String type;
  final DateTime issueDate;
  final DateTime expiryDate;
  final String? issuingAuthority;

  License({
    required this.licenseNumber,
    required this.type,
    required this.issueDate,
    required this.expiryDate,
    this.issuingAuthority,
  });

  factory License.fromJson(Map<String, dynamic> json) {
    return License(
      licenseNumber: json['licenseNumber'] ?? '',
      type: json['type'] ?? '',
      issueDate: DateTime.parse(json['issueDate'] ?? DateTime.now().toIso8601String()),
      expiryDate: DateTime.parse(json['expiryDate'] ?? DateTime.now().toIso8601String()),
      issuingAuthority: json['issuingAuthority'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'licenseNumber': licenseNumber,
      'type': type,
      'issueDate': issueDate.toIso8601String(),
      'expiryDate': expiryDate.toIso8601String(),
      if (issuingAuthority != null) 'issuingAuthority': issuingAuthority,
    };
  }
}

class EmergencyContact {
  final String name;
  final String relationship;
  final String phone;

  EmergencyContact({
    required this.name,
    required this.relationship,
    required this.phone,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      name: json['name'] ?? '',
      relationship: json['relationship'] ?? '',
      phone: json['phone'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'relationship': relationship,
      'phone': phone,
    };
  }
}

class Address {
  final String? street;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;

  Address({
    this.street,
    this.city,
    this.state,
    this.postalCode,
    this.country,
  });

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      street: json['street'],
      city: json['city'],
      state: json['state'],
      postalCode: json['postalCode'],
      country: json['country'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (street != null) 'street': street,
      if (city != null) 'city': city,
      if (state != null) 'state': state,
      if (postalCode != null) 'postalCode': postalCode,
      if (country != null) 'country': country,
    };
  }
}

class Employment {
  final String? joinDate;
  final String? employmentType;
  final double? salary;
  final String? employeeId;

  Employment({
    this.joinDate,
    this.employmentType,
    this.salary,
    this.employeeId,
  });

  factory Employment.fromJson(Map<String, dynamic> json) {
    return Employment(
      joinDate: json['joinDate'],
      employmentType: json['employmentType'],
      salary: json['salary']?.toDouble(),
      employeeId: json['employeeId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (joinDate != null) 'joinDate': joinDate,
      if (employmentType != null) 'employmentType': employmentType,
      if (salary != null) 'salary': salary,
      if (employeeId != null) 'employeeId': employeeId,
    };
  }
}

class BankDetails {
  final String? bankName;
  final String? accountHolderName;
  final String? accountNumber;
  final String? ifscCode;

  BankDetails({
    this.bankName,
    this.accountHolderName,
    this.accountNumber,
    this.ifscCode,
  });

  factory BankDetails.fromJson(Map<String, dynamic> json) {
    return BankDetails(
      bankName: json['bankName'],
      accountHolderName: json['accountHolderName'] ?? json['accountHolder'],
      accountNumber: json['accountNumber'],
      ifscCode: json['ifscCode'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (bankName != null) 'bankName': bankName,
      if (accountHolderName != null) 'accountHolderName': accountHolderName,
      if (accountNumber != null) 'accountNumber': accountNumber,
      if (ifscCode != null) 'ifscCode': ifscCode,
    };
  }
}

class Document {
  final String? id;
  final String documentType;
  final String documentName;
  final String documentUrl;
  final DateTime? expiryDate;
  final DateTime uploadedAt;

  Document({
    this.id,
    required this.documentType,
    required this.documentName,
    required this.documentUrl,
    this.expiryDate,
    required this.uploadedAt,
  });

  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      id: json['_id']?.toString(),
      documentType: json['documentType'] ?? '',
      documentName: json['documentName'] ?? '',
      documentUrl: json['documentUrl'] ?? '',
      expiryDate: json['expiryDate'] != null 
          ? DateTime.parse(json['expiryDate'])
          : null,
      uploadedAt: DateTime.parse(json['uploadedAt'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) '_id': id,
      'documentType': documentType,
      'documentName': documentName,
      'documentUrl': documentUrl,
      if (expiryDate != null) 'expiryDate': expiryDate!.toIso8601String(),
      'uploadedAt': uploadedAt.toIso8601String(),
    };
  }
}