// Firebase removed - using HTTP API
import 'package:intl/intl.dart';

///admin/dashboard/presentation/screens/sos_alert.dart

class SOSAlert {
  final String id;
  final String customerName;
  final String customerEmail;
  final String customerPhone;
  final String address;
  
  // Driver fields
  final String driverId;
  final String driverName;
  final String driverPhone;
  
  // Vehicle fields
  final String vehicleReg;
  final String vehicleMake;
  final String vehicleModel;
  
  // Trip fields
  final String tripId;
  final String pickupLocation;
  final String dropLocation;
  
  // Location fields
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  
  // Status fields
  final String status;
  final String notes;
  
  // Police notification fields
  final String? policeEmailContacted;
  final String? emailSentStatus;
  final String? policeCity;
  
  // 🆕 RESOLUTION PROOF FIELDS
  final String? resolutionPhoto;        // Photo URL from Firebase Storage
  final String? resolutionNotes;        // Detailed resolution notes
  final DateTime? resolutionTimestamp;  // When was it resolved
  final String? resolvedBy;             // Which admin resolved it
  final double? resolutionLatitude;     // Where was it resolved
  final double? resolutionLongitude;

  SOSAlert({
    required this.id,
    required this.customerName,
    this.customerEmail = '',
    this.customerPhone = '',
    required this.address,
    
    // Driver fields
    this.driverId = 'unknown',
    this.driverName = 'N/A',
    this.driverPhone = 'N/A',
    
    // Vehicle fields
    this.vehicleReg = 'N/A',
    this.vehicleMake = 'N/A',
    this.vehicleModel = 'N/A',
    
    // Trip fields
    this.tripId = 'N/A',
    this.pickupLocation = 'N/A',
    this.dropLocation = 'N/A',
    
    // Location
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    
    // Status
    required this.status,
    this.notes = '',
    
    // Police notification
    this.policeEmailContacted,
    this.emailSentStatus,
    this.policeCity,
    
    // 🆕 Resolution proof
    this.resolutionPhoto,
    this.resolutionNotes,
    this.resolutionTimestamp,
    this.resolvedBy,
    this.resolutionLatitude,
    this.resolutionLongitude,
  });

  factory SOSAlert.fromMap(Map<String, dynamic> data, String id) {
  final gpsData = (data['gps'] ?? {}) as Map<dynamic, dynamic>;

  return SOSAlert(
    id: id,
    customerName: data['customerName'] ?? 'N/A',
    customerEmail: data['customerEmail'] ?? '',
    customerPhone: data['customerPhone'] ?? '',
    address: data['address'] ?? 'Address not available',
    
    // Driver fields
    driverId: data['driverId'] ?? 'unknown',
    driverName: data['driverName'] ?? 'N/A',
    driverPhone: data['driverPhone'] ?? 'N/A',
    
    // Vehicle fields
    vehicleReg: data['vehicleReg'] ?? 'N/A',
    vehicleMake: data['vehicleMake'] ?? 'N/A',
    vehicleModel: data['vehicleModel'] ?? 'N/A',
    
    // Trip fields
    tripId: data['tripId'] ?? 'N/A',
    pickupLocation: data['pickupLocation'] ?? 'N/A',
    dropLocation: data['dropLocation'] ?? 'N/A',
    
    // Location
    timestamp: data['timestamp'] is String 
        ? DateTime.tryParse(data['timestamp']) ?? DateTime.now()
        : DateTime.now(),
    latitude: (gpsData['latitude'] ?? 0.0).toDouble(),
    longitude: (gpsData['longitude'] ?? 0.0).toDouble(),
    
    // Status
    status: data['status'] ?? 'ACTIVE',
    notes: data['adminNotes'] ?? '',
    
    // Police notification
    policeEmailContacted: data['policeEmailContacted'],
    emailSentStatus: data['emailSentStatus'],
    policeCity: data['policeCity'],
    
    // Resolution proof
    resolutionPhoto: data['resolutionPhoto'],
    resolutionNotes: data['resolutionNotes'],
    resolutionTimestamp: data['resolutionTimestamp'] != null 
        ? DateTime.tryParse(data['resolutionTimestamp']) 
        : null,
    resolvedBy: data['resolvedBy'],
    resolutionLatitude: data['resolutionLatitude'] != null 
        ? (data['resolutionLatitude'] as num).toDouble() 
        : null,
    resolutionLongitude: data['resolutionLongitude'] != null 
        ? (data['resolutionLongitude'] as num).toDouble() 
        : null,
  );
}

  // Helper method to check if police were notified
  bool get wasPoliceNotified => emailSentStatus == 'sent';
  
  // Helper method to get full vehicle info
  String get vehicleFullName => '$vehicleMake $vehicleModel ($vehicleReg)';
  
  // 🆕 Helper to check if resolution has proof
  bool get hasResolutionProof => resolutionPhoto != null || resolutionNotes != null;
  
  // Helper to format resolution timestamp
  String get formattedResolutionTime {
    if (resolutionTimestamp == null) return 'N/A';
    return DateFormat('MMM dd, yyyy hh:mm a').format(resolutionTimestamp!);
  }
}