// lib/core/models/client_model.dart
// ✅ COMPLETE MERGED VERSION
// ALL original fields, getters, helpers, ClientSummary, ClientAnalytics KEPT
// NEW additions: ClientLocation, ClientDocument, branch, department, location, documents

// ─────────────────────────────────────────────────────────────────────────────
// NEW: ClientDocument
// ─────────────────────────────────────────────────────────────────────────────

class ClientDocument {
  final String  id;
  final String  documentName;
  final String  documentType;
  final String? expiryDate;
  final String  fileName;
  final String  originalName;
  final String? filePath;
  final int     fileSize;
  final String  mimeType;
  final DateTime uploadedAt;

  ClientDocument({
    required this.id,
    required this.documentName,
    required this.documentType,
    this.expiryDate,
    required this.fileName,
    required this.originalName,
    this.filePath,
    required this.fileSize,
    required this.mimeType,
    required this.uploadedAt,
  });

  factory ClientDocument.fromJson(Map<String, dynamic> json) {
    return ClientDocument(
      id:           json['id']           ?? '',
      documentName: json['documentName'] ?? json['originalName'] ?? 'Document',
      documentType: json['documentType'] ?? 'other',
      expiryDate:   json['expiryDate']?.toString(),
      fileName:     json['fileName']     ?? '',
      originalName: json['originalName'] ?? '',
      filePath:     json['filePath']?.toString(),
      fileSize:     (json['fileSize']    ?? 0) as int,
      mimeType:     json['mimeType']     ?? '',
      uploadedAt: json['uploadedAt'] != null
          ? DateTime.tryParse(json['uploadedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id':           id,
    'documentName': documentName,
    'documentType': documentType,
    'expiryDate':   expiryDate,
    'fileName':     fileName,
    'originalName': originalName,
    'filePath':     filePath,
    'fileSize':     fileSize,
    'mimeType':     mimeType,
    'uploadedAt':   uploadedAt.toIso8601String(),
  };

  String get humanReadableSize {
    if (fileSize < 1024)            return '${fileSize}B';
    if (fileSize < 1024 * 1024)     return '${(fileSize / 1024).toStringAsFixed(1)}KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  bool get isExpired {
    if (expiryDate == null) return false;
    final exp = DateTime.tryParse(expiryDate!);
    if (exp == null) return false;
    return exp.isBefore(DateTime.now());
  }

  bool get expiresWithin30Days {
    if (expiryDate == null) return false;
    final exp = DateTime.tryParse(expiryDate!);
    if (exp == null) return false;
    return exp.isAfter(DateTime.now()) &&
        exp.isBefore(DateTime.now().add(const Duration(days: 30)));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NEW: ClientLocation
// ─────────────────────────────────────────────────────────────────────────────

class ClientLocation {
  final String country;
  final String state;
  final String city;
  final String area;

  const ClientLocation({
    this.country = '',
    this.state   = '',
    this.city    = '',
    this.area    = '',
  });

  factory ClientLocation.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ClientLocation();
    return ClientLocation(
      country: json['country']?.toString() ?? '',
      state:   json['state']?.toString()   ?? '',
      city:    json['city']?.toString()    ?? '',
      area:    json['area']?.toString()    ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'country': country,
    'state':   state,
    'city':    city,
    'area':    area,
  };

  String get displayAddress {
    final parts = [area, city, state, country].where((p) => p.isNotEmpty).toList();
    return parts.join(', ');
  }

  bool get hasLocation => country.isNotEmpty || state.isNotEmpty || city.isNotEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
// ClientModel — ALL original fields kept + new fields added
// ─────────────────────────────────────────────────────────────────────────────

class ClientModel {
  // ── ORIGINAL fields ──
  final String   id;
  final String   clientId;
  final String   name;
  final String   email;
  final String   phone;
  final String   companyName;
  final String   organizationName;
  final String   status;
  final String   role;
  final String?  firebaseUid;
  final String?  userId;
  final String?  address;
  final String?  contactPerson;
  final String?  gstNumber;
  final String?  panNumber;
  final int      totalCustomers;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLogin;
  final String?  createdBy;
  final String?  registrationMethod;

  // ── NEW fields ──
  final String?            branch;
  final String?            department;
  final String             phoneNumber;
  final bool               isActive;
  final ClientLocation     location;
  final List<ClientDocument> documents;

  ClientModel({
    // ── ORIGINAL required ──
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
    // ── NEW optional ──
    this.branch,
    this.department,
    String?            phoneNumber,
    bool?              isActive,
    ClientLocation?    location,
    List<ClientDocument>? documents,
  })  : phoneNumber = phoneNumber ?? phone,
        isActive    = isActive    ?? (status == 'active'),
        location    = location    ?? const ClientLocation(),
        documents   = documents   ?? const [];

  factory ClientModel.fromJson(Map<String, dynamic> json) {
    return ClientModel(
      // ── ORIGINAL ──
      id:                 json['id']                 ?? json['_id'] ?? '',
      clientId:           json['clientId']           ?? '',
      name:               json['name']               ?? '',
      email:              json['email']              ?? '',
      phone:              json['phone']              ?? json['phoneNumber'] ?? '',
      companyName:        json['companyName']        ?? '',
      organizationName:   json['organizationName']   ?? '',
      status:             json['status']             ?? 'active',
      role:               json['role']               ?? 'client',
      firebaseUid:        json['firebaseUid'],
      userId:             json['userId'],
      address:            json['address'],
      contactPerson:      json['contactPerson'],
      gstNumber:          json['gstNumber'],
      panNumber:          json['panNumber'],
      totalCustomers:     json['totalCustomers']     ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      lastLogin: json['lastLogin'] != null
          ? DateTime.tryParse(json['lastLogin'].toString())
          : null,
      createdBy:          json['createdBy'],
      registrationMethod: json['registrationMethod'],
      // ── NEW ──
      branch:      json['branch'],
      department:  json['department'],
      phoneNumber: json['phoneNumber'] ?? json['phone'] ?? '',
      isActive:    json['isActive'] as bool? ?? (json['status'] == 'active'),
      location:    ClientLocation.fromJson(json['location'] as Map<String, dynamic>?),
      documents:   (json['documents'] as List<dynamic>? ?? [])
          .map((d) => ClientDocument.fromJson(d as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      // ── ORIGINAL ──
      'id':                 id,
      'clientId':           clientId,
      'name':               name,
      'email':              email,
      'phone':              phone,
      'companyName':        companyName,
      'organizationName':   organizationName,
      'status':             status,
      'role':               role,
      'firebaseUid':        firebaseUid,
      'userId':             userId,
      'address':            address,
      'contactPerson':      contactPerson,
      'gstNumber':          gstNumber,
      'panNumber':          panNumber,
      'totalCustomers':     totalCustomers,
      'createdAt':          createdAt.toIso8601String(),
      'updatedAt':          updatedAt.toIso8601String(),
      'lastLogin':          lastLogin?.toIso8601String(),
      'createdBy':          createdBy,
      'registrationMethod': registrationMethod,
      // ── NEW ──
      'branch':      branch,
      'department':  department,
      'phoneNumber': phoneNumber,
      'isActive':    isActive,
      'location':    location.toJson(),
      'documents':   documents.map((d) => d.toJson()).toList(),
    };
  }

  ClientModel copyWith({
    // ── ORIGINAL ──
    String?   id,
    String?   clientId,
    String?   name,
    String?   email,
    String?   phone,
    String?   companyName,
    String?   organizationName,
    String?   status,
    String?   role,
    String?   firebaseUid,
    String?   userId,
    String?   address,
    String?   contactPerson,
    String?   gstNumber,
    String?   panNumber,
    int?      totalCustomers,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastLogin,
    String?   createdBy,
    String?   registrationMethod,
    // ── NEW ──
    String?              branch,
    String?              department,
    String?              phoneNumber,
    bool?                isActive,
    ClientLocation?      location,
    List<ClientDocument>? documents,
  }) {
    return ClientModel(
      id:                 id                 ?? this.id,
      clientId:           clientId           ?? this.clientId,
      name:               name               ?? this.name,
      email:              email              ?? this.email,
      phone:              phone              ?? this.phone,
      companyName:        companyName        ?? this.companyName,
      organizationName:   organizationName   ?? this.organizationName,
      status:             status             ?? this.status,
      role:               role               ?? this.role,
      firebaseUid:        firebaseUid        ?? this.firebaseUid,
      userId:             userId             ?? this.userId,
      address:            address            ?? this.address,
      contactPerson:      contactPerson      ?? this.contactPerson,
      gstNumber:          gstNumber          ?? this.gstNumber,
      panNumber:          panNumber          ?? this.panNumber,
      totalCustomers:     totalCustomers     ?? this.totalCustomers,
      createdAt:          createdAt          ?? this.createdAt,
      updatedAt:          updatedAt          ?? this.updatedAt,
      lastLogin:          lastLogin          ?? this.lastLogin,
      createdBy:          createdBy          ?? this.createdBy,
      registrationMethod: registrationMethod ?? this.registrationMethod,
      branch:             branch             ?? this.branch,
      department:         department         ?? this.department,
      phoneNumber:        phoneNumber        ?? this.phoneNumber,
      isActive:           isActive           ?? this.isActive,
      location:           location           ?? this.location,
      documents:          documents          ?? this.documents,
    );
  }

  // ── ORIGINAL toString, ==, hashCode ──

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

  // ── ORIGINAL helper getters ──

  bool get isPending  => status.toLowerCase() == 'pending';
  bool get isInactive => status.toLowerCase() == 'inactive';
  bool get isDeleted  => status.toLowerCase() == 'deleted';

  bool get hasFirebaseAccount => firebaseUid != null && firebaseUid!.isNotEmpty;
  bool get hasCustomers       => totalCustomers > 0;

  String get displayName    => name.isNotEmpty    ? name    : email;
  String get displayCompany => companyName.isNotEmpty ? companyName : organizationName;

  // Status color helpers for UI
  String get statusColor {
    switch (status.toLowerCase()) {
      case 'active':    return '#4CAF50'; // Green
      case 'pending':   return '#FF9800'; // Orange
      case 'inactive':  return '#9E9E9E'; // Grey
      case 'deleted':   return '#F44336'; // Red
      case 'suspended': return '#F44336'; // Red
      default:          return '#9E9E9E';
    }
  }

  // ── NEW document helpers ──
  int get activeDocumentCount   => documents.where((d) => !d.isExpired).length;
  int get expiredDocumentCount  => documents.where((d) => d.isExpired).length;
  int get expiringDocumentCount => documents.where((d) => d.expiresWithin30Days).length;
}

// ─────────────────────────────────────────────────────────────────────────────
// ORIGINAL: ClientSummary — UNCHANGED
// ─────────────────────────────────────────────────────────────────────────────

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
      total:           json['total']           ?? 0,
      active:          json['active']          ?? 0,
      inactive:        json['inactive']        ?? 0,
      pending:         json['pending']         ?? 0,
      deleted:         json['deleted']         ?? 0,
      withCustomers:   json['withCustomers']   ?? 0,
      withoutCustomers:json['withoutCustomers']?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total':           total,
      'active':          active,
      'inactive':        inactive,
      'pending':         pending,
      'deleted':         deleted,
      'withCustomers':   withCustomers,
      'withoutCustomers':withoutCustomers,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ORIGINAL: ClientAnalytics — UNCHANGED
// ─────────────────────────────────────────────────────────────────────────────

class ClientAnalytics {
  final int    totalTrips;
  final int    activeTrips;
  final int    completedTrips;
  final int    cancelledTrips;
  final double totalDistance;
  final double totalRevenue;
  final int    totalCustomers;
  final int    activeCustomers;
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
      totalTrips:     json['totalTrips']     ?? 0,
      activeTrips:    json['activeTrips']    ?? 0,
      completedTrips: json['completedTrips'] ?? 0,
      cancelledTrips: json['cancelledTrips'] ?? 0,
      totalDistance:  (json['totalDistance'] ?? 0).toDouble(),
      totalRevenue:   (json['totalRevenue']  ?? 0).toDouble(),
      totalCustomers: json['totalCustomers'] ?? 0,
      activeCustomers:json['activeCustomers']?? 0,
      monthlyStats:   json['monthlyStats']   ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalTrips':     totalTrips,
      'activeTrips':    activeTrips,
      'completedTrips': completedTrips,
      'cancelledTrips': cancelledTrips,
      'totalDistance':  totalDistance,
      'totalRevenue':   totalRevenue,
      'totalCustomers': totalCustomers,
      'activeCustomers':activeCustomers,
      'monthlyStats':   monthlyStats,
    };
  }
}