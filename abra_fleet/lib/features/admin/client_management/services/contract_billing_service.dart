import '../models/contract_models.dart';

/// Service to handle contract-based billing with validation
class ContractBillingService {
  // Sample contracts - in production, fetch from database
  static List<ContractPricing> _contracts = [];

  /// Initialize with sample contracts
  static void initializeSampleContracts() {
    _contracts = [
      ContractPricing(
        contractId: 'CNT-2024-ABC-001',
        organizationId: 'ORG-ABC',
        organizationName: 'ABC Logistics Pvt Ltd',
        startDate: DateTime(2024, 1, 1),
        endDate: DateTime(2025, 12, 31),
        status: 'active',
        autoRenewal: true,
        vehiclePricing: {
          'Truck': VehiclePricing(
            baseFarePerTrip: 50.0,
            ratePerKm: 12.0,
            ratePerMinuteWaiting: 2.0,
            gracePeriodMinutes: 5,
            minimumChargePerTrip: 100.0,
          ),
          'Van': VehiclePricing(
            baseFarePerTrip: 40.0,
            ratePerKm: 10.0,
            ratePerMinuteWaiting: 1.5,
            gracePeriodMinutes: 5,
            minimumChargePerTrip: 80.0,
          ),
        },
        surcharges: SurchargeRates(
          peakHoursPercent: 15.0,
          nightShiftPercent: 25.0,
          weekendPercent: 10.0,
          fuelSurchargePercent: 5.0,
          holidayPercent: 20.0,
        ),
        volumeSlabs: [
          VolumeSlab(minTrips: 0, maxTrips: 500, discountPercent: 0, description: '0-500 trips'),
          VolumeSlab(minTrips: 501, maxTrips: 1000, discountPercent: 8.33, description: '501-1000 trips'),
          VolumeSlab(minTrips: 1001, maxTrips: 1500, discountPercent: 16.67, description: '1001-1500 trips'),
          VolumeSlab(minTrips: 1501, maxTrips: 999999, discountPercent: 25.0, description: '1501+ trips'),
        ],
        paymentTerms: PaymentTerms(
          monthlyMinimum: 70000.0,
          monthlyMaximum: 200000.0,
          paymentDueDays: 30,
          billingCycle: 'Monthly',
          currency: 'INR',
          creditLimit: 500000.0,
          latePenaltyPercent: 2.0,
          freeCancellationPercent: 5.0,
          cancellationPenalty: 50.0,
        ),
        additionalCharges: AdditionalCharges(
          tollCharges: 'actual',
          parkingCharges: 'actual',
          vehicleCleaningCharge: 500.0,
          gpsDeviationPenalty: 100.0,
          loadingUnloadingPerHour: 200.0,
        ),
        slaTerms: SLATerms(
          onTimePickupPercent: 95.0,
          vehicleAvailabilityPercent: 99.0,
          driverRatingMinimum: 4.0,
          responseTimeMinutes: 15,
          slaBreachPenalty: 500.0,
        ),
        createdAt: DateTime.now(),
        createdBy: 'admin',
      ),
    ];
  }

  /// Get all contracts
  static List<ContractPricing> getAllContracts() => _contracts;

  /// Get contract by ID
  static ContractPricing? getContractById(String contractId) {
    try {
      return _contracts.firstWhere((c) => c.contractId == contractId);
    } catch (e) {
      return null;
    }
  }

  /// Get active contracts for an organization
  static List<ContractPricing> getActiveContractsForOrganization(String organizationId) {
    return _contracts.where((c) => 
      c.organizationId == organizationId && 
      c.status == 'active' &&
      DateTime.now().isBefore(c.endDate)
    ).toList();
  }

  /// Generate invoice from contract and trips
  static Map<String, dynamic> generateInvoiceFromContract({
    required String contractId,
    required List<Map<String, dynamic>> trips,
    required DateTime billingPeriodStart,
    required DateTime billingPeriodEnd,
  }) {
    final contract = getContractById(contractId);
    if (contract == null) {
      throw Exception('Contract not found: $contractId');
    }

    // Validate contract is active
    if (contract.status != 'active') {
      throw Exception('Contract is not active: ${contract.status}');
    }

    // Validate billing period is within contract period
    if (billingPeriodStart.isBefore(contract.startDate) || 
        billingPeriodEnd.isAfter(contract.endDate)) {
      throw Exception('Billing period outside contract validity');
    }

    double totalAmount = 0;
    List<Map<String, dynamic>> chargeBreakdown = [];
    Map<String, double> vehicleTypeCosts = {};

    // Calculate charges for each trip based on contract pricing
    for (var trip in trips) {
      String vehicleType = trip['vehicleType'] ?? 'Unknown';
      double distance = (trip['distance'] ?? 0).toDouble();
      int waitingMinutes = trip['waitingMinutes'] ?? 0;
      DateTime tripDateTime = trip['datetime'] ?? DateTime.now();

      var pricing = contract.vehiclePricing[vehicleType];
      if (pricing == null) {
        throw Exception('No pricing found for vehicle type: $vehicleType');
      }

      double tripCost = 0;

      // Base fare
      tripCost += pricing.baseFarePerTrip;

      // Distance charge
      tripCost += distance * pricing.ratePerKm;

      // Waiting charge (after grace period)
      if (waitingMinutes > pricing.gracePeriodMinutes) {
        tripCost += (waitingMinutes - pricing.gracePeriodMinutes) * pricing.ratePerMinuteWaiting;
      }

      // Apply surcharges
      if (_isPeakHour(tripDateTime)) {
        tripCost += tripCost * (contract.surcharges.peakHoursPercent / 100);
      }
      if (_isNightShift(tripDateTime)) {
        tripCost += tripCost * (contract.surcharges.nightShiftPercent / 100);
      }
      if (_isWeekend(tripDateTime)) {
        tripCost += tripCost * (contract.surcharges.weekendPercent / 100);
      }

      // Ensure minimum charge
      if (tripCost < pricing.minimumChargePerTrip) {
        tripCost = pricing.minimumChargePerTrip;
      }

      vehicleTypeCosts[vehicleType] = (vehicleTypeCosts[vehicleType] ?? 0) + tripCost;
      totalAmount += tripCost;
    }

    // Apply volume-based discount
    int totalTrips = trips.length;
    var applicableSlab = _getApplicableVolumeSlab(contract, totalTrips);
    double discountAmount = 0;
    if (applicableSlab != null && applicableSlab.discountPercent > 0) {
      discountAmount = totalAmount * (applicableSlab.discountPercent / 100);
      totalAmount -= discountAmount;
      chargeBreakdown.add({
        'type': 'Volume Discount',
        'description': '${applicableSlab.discountPercent}% off for $totalTrips trips',
        'amount': -discountAmount,
      });
    }

    // Apply minimum commitment
    bool minimumApplied = false;
    if (totalAmount < contract.paymentTerms.monthlyMinimum) {
      double minimumCharge = contract.paymentTerms.monthlyMinimum - totalAmount;
      chargeBreakdown.add({
        'type': 'Minimum Commitment',
        'description': 'Monthly minimum billing guarantee',
        'amount': minimumCharge,
      });
      totalAmount = contract.paymentTerms.monthlyMinimum;
      minimumApplied = true;
    }

    // Check maximum limit
    if (totalAmount > contract.paymentTerms.monthlyMaximum) {
      throw Exception('Invoice amount exceeds monthly maximum: ${contract.paymentTerms.monthlyMaximum}');
    }

    // Calculate GST (18%)
    double gstAmount = totalAmount * 0.18;
    double totalWithGst = totalAmount + gstAmount;

    // Calculate due date
    DateTime dueDate = billingPeriodEnd.add(Duration(days: contract.paymentTerms.paymentDueDays));

    // Generate invoice
    return {
      'id': _generateInvoiceNumber(),
      'contractId': contractId,
      'organizationId': contract.organizationId,
      'organizationName': contract.organizationName,
      'agreementId': contractId,
      'agreementStartDate': contract.startDate.toIso8601String(),
      'agreementEndDate': contract.endDate.toIso8601String(),
      'billingCycle': contract.paymentTerms.billingCycle,
      'paymentTerms': 'Net ${contract.paymentTerms.paymentDueDays}',
      'billingPeriodStart': billingPeriodStart.toIso8601String(),
      'billingPeriodEnd': billingPeriodEnd.toIso8601String(),
      'amount': totalAmount,
      'gstAmount': gstAmount,
      'totalAmount': totalWithGst,
      'amountPaid': 0.0,
      'status': 'Pending',
      'date': billingPeriodEnd.toIso8601String(),
      'dueDate': dueDate.toIso8601String(),
      'paidDate': null,
      'paymentMode': null,
      'trips': totalTrips,
      'chargeBreakdown': chargeBreakdown,
      'pricingReference': {
        'contractId': contractId,
        'volumeSlabApplied': applicableSlab?.toJson(),
        'minimumCommitmentApplied': minimumApplied,
        'discountAmount': discountAmount,
      },
      'vehicleTypeCosts': vehicleTypeCosts,
      'createdAt': DateTime.now().toIso8601String(),
    };
  }

  /// Validate invoice against contract
  static List<String> validateInvoiceAgainstContract(
    Map<String, dynamic> invoice,
    ContractPricing contract,
  ) {
    List<String> errors = [];

    // Check if invoice is within contract period
    DateTime invoiceDate = DateTime.parse(invoice['date']);
    if (invoiceDate.isBefore(contract.startDate) || invoiceDate.isAfter(contract.endDate)) {
      errors.add('Invoice date outside contract period');
    }

    // Check if total amount exceeds maximum
    if (invoice['totalAmount'] > contract.paymentTerms.monthlyMaximum) {
      errors.add('Invoice exceeds monthly maximum: ${contract.paymentTerms.monthlyMaximum}');
    }

    // Verify contract is active
    if (contract.status != 'active') {
      errors.add('Contract is not active: ${contract.status}');
    }

    return errors;
  }

  /// Add new contract
  static void addContract(ContractPricing contract) {
    _contracts.add(contract);
  }

  /// Update existing contract
  static bool updateContract(ContractPricing updatedContract) {
    int index = _contracts.indexWhere((c) => c.contractId == updatedContract.contractId);
    if (index != -1) {
      _contracts[index] = updatedContract;
      return true;
    }
    return false;
  }

  /// Helper: Check if time is peak hour (8-10 AM, 5-8 PM)
  static bool _isPeakHour(DateTime dateTime) {
    int hour = dateTime.hour;
    return (hour >= 8 && hour < 10) || (hour >= 17 && hour < 20);
  }

  /// Helper: Check if time is night shift (10 PM - 6 AM)
  static bool _isNightShift(DateTime dateTime) {
    int hour = dateTime.hour;
    return hour >= 22 || hour < 6;
  }

  /// Helper: Check if date is weekend
  static bool _isWeekend(DateTime dateTime) {
    return dateTime.weekday == DateTime.saturday || dateTime.weekday == DateTime.sunday;
  }

  /// Helper: Get applicable volume slab
  static VolumeSlab? _getApplicableVolumeSlab(ContractPricing contract, int tripCount) {
    for (var slab in contract.volumeSlabs) {
      if (tripCount >= slab.minTrips && tripCount <= slab.maxTrips) {
        return slab;
      }
    }
    return null;
  }

  /// Helper: Generate invoice number
  static String _generateInvoiceNumber() {
    return 'INV-${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
  }

  /// Log audit entry
  static void logAuditEntry(AuditLog entry) {
    // In production, save to database
    print('Audit Log: ${entry.action} on ${entry.entityType} ${entry.entityId} by ${entry.userName}');
  }
}
