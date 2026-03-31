// Contract and Pricing Models for Billing System
// These models ensure data integrity and prevent corruption

class ContractPricing {
  final String contractId;
  final String organizationId;
  final String organizationName;
  final DateTime startDate;
  final DateTime endDate;
  final String status; // 'active', 'expired', 'suspended', 'draft'
  final bool autoRenewal;
  
  final Map<String, VehiclePricing> vehiclePricing;
  final SurchargeRates surcharges;
  final List<VolumeSlab> volumeSlabs;
  final PaymentTerms paymentTerms;
  final AdditionalCharges additionalCharges;
  final SLATerms slaTerms;
  
  final DateTime createdAt;
  final DateTime? lastModifiedAt;
  final String createdBy;
  final String? modifiedBy;

  ContractPricing({
    required this.contractId,
    required this.organizationId,
    required this.organizationName,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.autoRenewal,
    required this.vehiclePricing,
    required this.surcharges,
    required this.volumeSlabs,
    required this.paymentTerms,
    required this.additionalCharges,
    required this.slaTerms,
    required this.createdAt,
    this.lastModifiedAt,
    required this.createdBy,
    this.modifiedBy,
  });

  Map<String, dynamic> toJson() => {
    'contractId': contractId,
    'organizationId': organizationId,
    'organizationName': organizationName,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate.toIso8601String(),
    'status': status,
    'autoRenewal': autoRenewal,
    'vehiclePricing': vehiclePricing.map((k, v) => MapEntry(k, v.toJson())),
    'surcharges': surcharges.toJson(),
    'volumeSlabs': volumeSlabs.map((s) => s.toJson()).toList(),
    'paymentTerms': paymentTerms.toJson(),
    'additionalCharges': additionalCharges.toJson(),
    'slaTerms': slaTerms.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'lastModifiedAt': lastModifiedAt?.toIso8601String(),
    'createdBy': createdBy,
    'modifiedBy': modifiedBy,
  };

  factory ContractPricing.fromJson(Map<String, dynamic> json) => ContractPricing(
    contractId: json['contractId'],
    organizationId: json['organizationId'],
    organizationName: json['organizationName'],
    startDate: DateTime.parse(json['startDate']),
    endDate: DateTime.parse(json['endDate']),
    status: json['status'],
    autoRenewal: json['autoRenewal'],
    vehiclePricing: (json['vehiclePricing'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, VehiclePricing.fromJson(v)),
    ),
    surcharges: SurchargeRates.fromJson(json['surcharges']),
    volumeSlabs: (json['volumeSlabs'] as List).map((s) => VolumeSlab.fromJson(s)).toList(),
    paymentTerms: PaymentTerms.fromJson(json['paymentTerms']),
    additionalCharges: AdditionalCharges.fromJson(json['additionalCharges']),
    slaTerms: SLATerms.fromJson(json['slaTerms']),
    createdAt: DateTime.parse(json['createdAt']),
    lastModifiedAt: json['lastModifiedAt'] != null ? DateTime.parse(json['lastModifiedAt']) : null,
    createdBy: json['createdBy'],
    modifiedBy: json['modifiedBy'],
  );
}

class VehiclePricing {
  final double baseFarePerTrip;
  final double ratePerKm;
  final double ratePerMinuteWaiting;
  final int gracePeriodMinutes;
  final double minimumChargePerTrip;

  VehiclePricing({
    required this.baseFarePerTrip,
    required this.ratePerKm,
    required this.ratePerMinuteWaiting,
    required this.gracePeriodMinutes,
    required this.minimumChargePerTrip,
  });

  Map<String, dynamic> toJson() => {
    'baseFarePerTrip': baseFarePerTrip,
    'ratePerKm': ratePerKm,
    'ratePerMinuteWaiting': ratePerMinuteWaiting,
    'gracePeriodMinutes': gracePeriodMinutes,
    'minimumChargePerTrip': minimumChargePerTrip,
  };

  factory VehiclePricing.fromJson(Map<String, dynamic> json) => VehiclePricing(
    baseFarePerTrip: json['baseFarePerTrip'].toDouble(),
    ratePerKm: json['ratePerKm'].toDouble(),
    ratePerMinuteWaiting: json['ratePerMinuteWaiting'].toDouble(),
    gracePeriodMinutes: json['gracePeriodMinutes'],
    minimumChargePerTrip: json['minimumChargePerTrip'].toDouble(),
  );
}

class SurchargeRates {
  final double peakHoursPercent;
  final double nightShiftPercent;
  final double weekendPercent;
  final double fuelSurchargePercent;
  final double holidayPercent;

  SurchargeRates({
    required this.peakHoursPercent,
    required this.nightShiftPercent,
    required this.weekendPercent,
    required this.fuelSurchargePercent,
    required this.holidayPercent,
  });

  Map<String, dynamic> toJson() => {
    'peakHoursPercent': peakHoursPercent,
    'nightShiftPercent': nightShiftPercent,
    'weekendPercent': weekendPercent,
    'fuelSurchargePercent': fuelSurchargePercent,
    'holidayPercent': holidayPercent,
  };

  factory SurchargeRates.fromJson(Map<String, dynamic> json) => SurchargeRates(
    peakHoursPercent: json['peakHoursPercent'].toDouble(),
    nightShiftPercent: json['nightShiftPercent'].toDouble(),
    weekendPercent: json['weekendPercent'].toDouble(),
    fuelSurchargePercent: json['fuelSurchargePercent'].toDouble(),
    holidayPercent: json['holidayPercent'].toDouble(),
  );
}

class VolumeSlab {
  final int minTrips;
  final int maxTrips;
  final double discountPercent;
  final String description;

  VolumeSlab({
    required this.minTrips,
    required this.maxTrips,
    required this.discountPercent,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
    'minTrips': minTrips,
    'maxTrips': maxTrips,
    'discountPercent': discountPercent,
    'description': description,
  };

  factory VolumeSlab.fromJson(Map<String, dynamic> json) => VolumeSlab(
    minTrips: json['minTrips'],
    maxTrips: json['maxTrips'],
    discountPercent: json['discountPercent'].toDouble(),
    description: json['description'],
  );
}

class PaymentTerms {
  final double monthlyMinimum;
  final double monthlyMaximum;
  final int paymentDueDays;
  final String billingCycle; // 'Monthly', 'Weekly', 'Bi-Weekly'
  final String currency;
  final double creditLimit;
  final double latePenaltyPercent;
  final double freeCancellationPercent;
  final double cancellationPenalty;

  PaymentTerms({
    required this.monthlyMinimum,
    required this.monthlyMaximum,
    required this.paymentDueDays,
    required this.billingCycle,
    required this.currency,
    required this.creditLimit,
    required this.latePenaltyPercent,
    required this.freeCancellationPercent,
    required this.cancellationPenalty,
  });

  Map<String, dynamic> toJson() => {
    'monthlyMinimum': monthlyMinimum,
    'monthlyMaximum': monthlyMaximum,
    'paymentDueDays': paymentDueDays,
    'billingCycle': billingCycle,
    'currency': currency,
    'creditLimit': creditLimit,
    'latePenaltyPercent': latePenaltyPercent,
    'freeCancellationPercent': freeCancellationPercent,
    'cancellationPenalty': cancellationPenalty,
  };

  factory PaymentTerms.fromJson(Map<String, dynamic> json) => PaymentTerms(
    monthlyMinimum: json['monthlyMinimum'].toDouble(),
    monthlyMaximum: json['monthlyMaximum'].toDouble(),
    paymentDueDays: json['paymentDueDays'],
    billingCycle: json['billingCycle'],
    currency: json['currency'],
    creditLimit: json['creditLimit'].toDouble(),
    latePenaltyPercent: json['latePenaltyPercent'].toDouble(),
    freeCancellationPercent: json['freeCancellationPercent'].toDouble(),
    cancellationPenalty: json['cancellationPenalty'].toDouble(),
  );
}

class AdditionalCharges {
  final String tollCharges; // 'actual' or fixed amount
  final String parkingCharges; // 'actual' or fixed amount
  final double vehicleCleaningCharge;
  final double gpsDeviationPenalty;
  final double loadingUnloadingPerHour;

  AdditionalCharges({
    required this.tollCharges,
    required this.parkingCharges,
    required this.vehicleCleaningCharge,
    required this.gpsDeviationPenalty,
    required this.loadingUnloadingPerHour,
  });

  Map<String, dynamic> toJson() => {
    'tollCharges': tollCharges,
    'parkingCharges': parkingCharges,
    'vehicleCleaningCharge': vehicleCleaningCharge,
    'gpsDeviationPenalty': gpsDeviationPenalty,
    'loadingUnloadingPerHour': loadingUnloadingPerHour,
  };

  factory AdditionalCharges.fromJson(Map<String, dynamic> json) => AdditionalCharges(
    tollCharges: json['tollCharges'],
    parkingCharges: json['parkingCharges'],
    vehicleCleaningCharge: json['vehicleCleaningCharge'].toDouble(),
    gpsDeviationPenalty: json['gpsDeviationPenalty'].toDouble(),
    loadingUnloadingPerHour: json['loadingUnloadingPerHour'].toDouble(),
  );
}

class SLATerms {
  final double onTimePickupPercent;
  final double vehicleAvailabilityPercent;
  final double driverRatingMinimum;
  final int responseTimeMinutes;
  final double slaBreachPenalty;

  SLATerms({
    required this.onTimePickupPercent,
    required this.vehicleAvailabilityPercent,
    required this.driverRatingMinimum,
    required this.responseTimeMinutes,
    required this.slaBreachPenalty,
  });

  Map<String, dynamic> toJson() => {
    'onTimePickupPercent': onTimePickupPercent,
    'vehicleAvailabilityPercent': vehicleAvailabilityPercent,
    'driverRatingMinimum': driverRatingMinimum,
    'responseTimeMinutes': responseTimeMinutes,
    'slaBreachPenalty': slaBreachPenalty,
  };

  factory SLATerms.fromJson(Map<String, dynamic> json) => SLATerms(
    onTimePickupPercent: json['onTimePickupPercent'].toDouble(),
    vehicleAvailabilityPercent: json['vehicleAvailabilityPercent'].toDouble(),
    driverRatingMinimum: json['driverRatingMinimum'].toDouble(),
    responseTimeMinutes: json['responseTimeMinutes'],
    slaBreachPenalty: json['slaBreachPenalty'].toDouble(),
  );
}

class AuditLog {
  final String id;
  final String entityType; // 'contract', 'invoice', 'payment'
  final String entityId;
  final String action; // 'created', 'modified', 'approved', 'cancelled'
  final String userId;
  final String userName;
  final DateTime timestamp;
  final Map<String, dynamic> changes;
  final String? remarks;

  AuditLog({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.userId,
    required this.userName,
    required this.timestamp,
    required this.changes,
    this.remarks,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'entityType': entityType,
    'entityId': entityId,
    'action': action,
    'userId': userId,
    'userName': userName,
    'timestamp': timestamp.toIso8601String(),
    'changes': changes,
    'remarks': remarks,
  };

  factory AuditLog.fromJson(Map<String, dynamic> json) => AuditLog(
    id: json['id'],
    entityType: json['entityType'],
    entityId: json['entityId'],
    action: json['action'],
    userId: json['userId'],
    userName: json['userName'],
    timestamp: DateTime.parse(json['timestamp']),
    changes: json['changes'],
    remarks: json['remarks'],
  );
}
