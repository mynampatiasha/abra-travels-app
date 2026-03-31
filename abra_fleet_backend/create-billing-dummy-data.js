const { MongoClient } = require('mongodb');

// MongoDB connection
const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function createBillingDummyData() {
  let client;
  
  try {
    console.log('🚀 Creating comprehensive billing dummy data...');
    console.log('='.repeat(60));
    
    client = new MongoClient(MONGODB_URI);
    await client.connect();
    const db = client.db('abra_fleet');
    
    // Clear existing data
    console.log('🧹 Clearing existing billing data...');
    await db.collection('contracts').deleteMany({});
    await db.collection('invoices').deleteMany({});
    await db.collection('audit_logs').deleteMany({ entityType: { $in: ['contract', 'invoice'] } });
    
    // ==================== CONTRACTS ====================
    console.log('📋 Creating contracts...');
    
    const contracts = [
      {
        contractId: 'CNT-2024-ABC-001',
        organizationId: 'ORG-ABC',
        organizationName: 'ABC Logistics Pvt Ltd',
        startDate: new Date('2024-01-01'),
        endDate: new Date('2025-12-31'),
        status: 'active',
        autoRenewal: true,
        
        // Vehicle Pricing Configuration
        vehiclePricing: {
          'Truck': {
            baseFarePerTrip: 50.0,
            ratePerKm: 12.0,
            ratePerMinuteWaiting: 2.0,
            gracePeriodMinutes: 5,
            minimumChargePerTrip: 100.0
          },
          'Van': {
            baseFarePerTrip: 40.0,
            ratePerKm: 10.0,
            ratePerMinuteWaiting: 1.5,
            gracePeriodMinutes: 5,
            minimumChargePerTrip: 80.0
          },
          'Car': {
            baseFarePerTrip: 30.0,
            ratePerKm: 8.0,
            ratePerMinuteWaiting: 1.0,
            gracePeriodMinutes: 3,
            minimumChargePerTrip: 60.0
          }
        },
        
        // Surcharge Configuration
        surcharges: {
          peakHoursPercent: 15.0,
          nightShiftPercent: 25.0,
          weekendPercent: 10.0,
          fuelSurchargePercent: 5.0
        },
        
        // Volume-based Pricing Slabs
        volumeSlabs: [
          { minTrips: 0, maxTrips: 500, ratePerKm: 12.0, discountPercent: 0.0 },
          { minTrips: 501, maxTrips: 1000, ratePerKm: 11.0, discountPercent: 8.33 },
          { minTrips: 1001, maxTrips: 1500, ratePerKm: 10.0, discountPercent: 16.67 },
          { minTrips: 1501, maxTrips: 999999, ratePerKm: 9.0, discountPercent: 25.0 }
        ],
        
        // Payment Terms
        paymentTerms: {
          monthlyMinimum: 70000.0,
          monthlyMaximum: 500000.0,
          paymentDueDays: 30,
          billingCycle: 'Monthly',
          currency: 'INR',
          creditLimit: 500000.0,
          latePenaltyPercent: 2.0,
          freeCancellationPercent: 5.0,
          cancellationPenalty: 50.0
        },
        
        // Additional Charges
        additionalCharges: {
          tollCharges: 'actual',
          parkingCharges: 'actual',
          vehicleCleaning: 500.0,
          gpsDeviationPenalty: 100.0
        },
        
        // SLA Terms
        slaTerms: {
          onTimePickupPercent: 95.0,
          vehicleAvailabilityPercent: 99.0,
          driverRatingMinimum: 4.0,
          responseTimeMinutes: 15,
          slaBreachPenalty: 500.0
        },
        
        createdAt: new Date('2023-12-15'),
        createdBy: 'ADMIN-001',
        lastModifiedAt: new Date('2023-12-15')
      },
      
      {
        contractId: 'CNT-2024-XYZ-005',
        organizationId: 'ORG-XYZ',
        organizationName: 'XYZ Transport Solutions',
        startDate: new Date('2024-03-15'),
        endDate: new Date('2025-03-14'),
        status: 'active',
        autoRenewal: false,
        
        vehiclePricing: {
          'Car': {
            baseFarePerTrip: 30.0,
            ratePerKm: 8.0,
            ratePerMinuteWaiting: 1.0,
            gracePeriodMinutes: 3,
            minimumChargePerTrip: 60.0
          },
          'Bike': {
            baseFarePerTrip: 20.0,
            ratePerKm: 5.0,
            ratePerMinuteWaiting: 0.5,
            gracePeriodMinutes: 2,
            minimumChargePerTrip: 30.0
          }
        },
        
        surcharges: {
          peakHoursPercent: 12.0,
          nightShiftPercent: 20.0,
          weekendPercent: 8.0,
          fuelSurchargePercent: 4.0
        },
        
        volumeSlabs: [
          { minTrips: 0, maxTrips: 1000, ratePerKm: 8.0, discountPercent: 0.0 },
          { minTrips: 1001, maxTrips: 999999, ratePerKm: 7.5, discountPercent: 6.25 }
        ],
        
        paymentTerms: {
          monthlyMinimum: 50000.0,
          monthlyMaximum: 300000.0,
          paymentDueDays: 15,
          billingCycle: 'Weekly',
          currency: 'INR',
          creditLimit: 300000.0,
          latePenaltyPercent: 1.5,
          freeCancellationPercent: 3.0,
          cancellationPenalty: 30.0
        },
        
        additionalCharges: {
          tollCharges: 'actual',
          parkingCharges: 'actual',
          vehicleCleaning: 300.0,
          gpsDeviationPenalty: 75.0
        },
        
        slaTerms: {
          onTimePickupPercent: 92.0,
          vehicleAvailabilityPercent: 98.0,
          driverRatingMinimum: 3.8,
          responseTimeMinutes: 20,
          slaBreachPenalty: 300.0
        },
        
        createdAt: new Date('2024-03-01'),
        createdBy: 'ADMIN-001',
        lastModifiedAt: new Date('2024-03-01')
      },
      
      {
        contractId: 'CNT-2024-DEF-010',
        organizationId: 'ORG-DEF',
        organizationName: 'DEF Manufacturing Ltd',
        startDate: new Date('2024-06-01'),
        endDate: new Date('2025-05-31'),
        status: 'active',
        autoRenewal: true,
        
        vehiclePricing: {
          'Heavy Truck': {
            baseFarePerTrip: 100.0,
            ratePerKm: 18.0,
            ratePerMinuteWaiting: 3.0,
            gracePeriodMinutes: 10,
            minimumChargePerTrip: 200.0
          },
          'Trailer': {
            baseFarePerTrip: 150.0,
            ratePerKm: 25.0,
            ratePerMinuteWaiting: 5.0,
            gracePeriodMinutes: 15,
            minimumChargePerTrip: 300.0
          }
        },
        
        surcharges: {
          peakHoursPercent: 20.0,
          nightShiftPercent: 30.0,
          weekendPercent: 15.0,
          fuelSurchargePercent: 8.0
        },
        
        volumeSlabs: [
          { minTrips: 0, maxTrips: 200, ratePerKm: 25.0, discountPercent: 0.0 },
          { minTrips: 201, maxTrips: 500, ratePerKm: 23.0, discountPercent: 8.0 },
          { minTrips: 501, maxTrips: 999999, ratePerKm: 20.0, discountPercent: 20.0 }
        ],
        
        paymentTerms: {
          monthlyMinimum: 150000.0,
          monthlyMaximum: 800000.0,
          paymentDueDays: 45,
          billingCycle: 'Monthly',
          currency: 'INR',
          creditLimit: 800000.0,
          latePenaltyPercent: 2.5,
          freeCancellationPercent: 2.0,
          cancellationPenalty: 100.0
        },
        
        additionalCharges: {
          tollCharges: 'actual',
          parkingCharges: 'actual',
          vehicleCleaning: 800.0,
          gpsDeviationPenalty: 200.0
        },
        
        slaTerms: {
          onTimePickupPercent: 98.0,
          vehicleAvailabilityPercent: 99.5,
          driverRatingMinimum: 4.2,
          responseTimeMinutes: 10,
          slaBreachPenalty: 1000.0
        },
        
        createdAt: new Date('2024-05-15'),
        createdBy: 'ADMIN-001',
        lastModifiedAt: new Date('2024-05-15')
      }
    ];
    
    await db.collection('contracts').insertMany(contracts);
    console.log(`✅ Created ${contracts.length} contracts`);
    
    // ==================== INVOICES ====================
    console.log('🧾 Creating invoices...');
    
    const invoices = [
      {
        id: 'INV-2024-001',
        organizationId: 'ORG-ABC',
        organizationName: 'ABC Logistics Pvt Ltd',
        contractId: 'CNT-2024-ABC-001',
        agreementStartDate: new Date('2024-01-01'),
        agreementEndDate: new Date('2025-12-31'),
        billingCycle: 'Monthly',
        billingPeriodStart: new Date('2024-12-01'),
        billingPeriodEnd: new Date('2024-12-31'),
        paymentTerms: 'Net 30',
        amount: 245680.50,
        gstAmount: 44222.49,
        totalAmount: 289902.99,
        amountPaid: 289902.99,
        status: 'Paid',
        date: new Date('2024-12-01'),
        dueDate: new Date('2024-12-31'),
        paidDate: new Date('2024-12-25'),
        paymentMode: 'Bank Transfer',
        transactionRef: 'TXN-2024-12-25-001',
        trips: 156,
        totalDistance: 12450.5,
        totalFuelConsumed: 1850.25,
        totalIdleTime: 45.5,
        vehicles: [
          { type: 'Truck', count: 8, distance: 8500.0, trips: 100, cost: 170000.0 },
          { type: 'Van', count: 5, distance: 3950.5, trips: 56, cost: 75680.50 }
        ],
        pricingApplied: {
          volumeSlabApplied: '1001-1500 trips @ ₹10/km',
          discountPercent: 16.67,
          minimumCommitmentApplied: false
        },
        charges: {
          baseCharges: 180000.0,
          perKmCharges: 45680.50,
          fuelSurcharge: 12000.0,
          tollCharges: 4500.0,
          waitingCharges: 2500.0,
          loadingUnloadingCharges: 1000.0
        },
        generatedBy: 'SYSTEM-AUTO',
        approvedBy: 'ADMIN-001',
        approvedAt: new Date('2024-12-02'),
        createdAt: new Date('2024-12-01')
      },
      
      {
        id: 'INV-2024-002',
        organizationId: 'ORG-XYZ',
        organizationName: 'XYZ Transport Solutions',
        contractId: 'CNT-2024-XYZ-005',
        agreementStartDate: new Date('2024-03-15'),
        agreementEndDate: new Date('2025-03-14'),
        billingCycle: 'Weekly',
        billingPeriodStart: new Date('2024-12-01'),
        billingPeriodEnd: new Date('2024-12-07'),
        paymentTerms: 'Net 15',
        amount: 125000.00,
        gstAmount: 22500.00,
        totalAmount: 147500.00,
        amountPaid: 75000.00,
        status: 'Partially Paid',
        date: new Date('2024-12-08'),
        dueDate: new Date('2024-12-23'),
        paidDate: new Date('2024-12-10'),
        paymentMode: 'Cheque',
        transactionRef: 'CHQ-2024-12-10-456',
        trips: 89,
        totalDistance: 6780.0,
        totalFuelConsumed: 980.5,
        totalIdleTime: 28.0,
        vehicles: [
          { type: 'Car', count: 12, distance: 6780.0, trips: 89, cost: 125000.0 }
        ],
        pricingApplied: {
          volumeSlabApplied: '0-1000 trips @ ₹8/km',
          discountPercent: 0.0,
          minimumCommitmentApplied: false
        },
        charges: {
          baseCharges: 95000.0,
          perKmCharges: 20340.0,
          fuelSurcharge: 6500.0,
          tollCharges: 2160.0,
          waitingCharges: 800.0,
          loadingUnloadingCharges: 200.0
        },
        generatedBy: 'SYSTEM-AUTO',
        approvedBy: 'ADMIN-001',
        approvedAt: new Date('2024-12-08'),
        createdAt: new Date('2024-12-08')
      },
      
      {
        id: 'INV-2024-003',
        organizationId: 'ORG-ABC',
        organizationName: 'ABC Logistics Pvt Ltd',
        contractId: 'CNT-2024-ABC-001',
        agreementStartDate: new Date('2024-01-01'),
        agreementEndDate: new Date('2025-12-31'),
        billingCycle: 'Monthly',
        billingPeriodStart: new Date('2024-11-01'),
        billingPeriodEnd: new Date('2024-11-30'),
        paymentTerms: 'Net 30',
        amount: 485000.00,
        gstAmount: 87300.00,
        totalAmount: 572300.00,
        amountPaid: 0.0,
        status: 'Overdue',
        date: new Date('2024-11-01'),
        dueDate: new Date('2024-12-01'),
        paidDate: null,
        paymentMode: null,
        transactionRef: null,
        trips: 234,
        totalDistance: 18950.8,
        totalFuelConsumed: 2845.5,
        totalIdleTime: 67.5,
        vehicles: [
          { type: 'Truck', count: 15, distance: 15200.0, trips: 180, cost: 380000.0 },
          { type: 'Van', count: 6, distance: 3750.8, trips: 54, cost: 105000.0 }
        ],
        pricingApplied: {
          volumeSlabApplied: '1001-1500 trips @ ₹10/km',
          discountPercent: 16.67,
          minimumCommitmentApplied: false
        },
        charges: {
          baseCharges: 350000.0,
          perKmCharges: 94754.0,
          fuelSurcharge: 25000.0,
          tollCharges: 8500.0,
          waitingCharges: 4500.0,
          loadingUnloadingCharges: 2246.0
        },
        generatedBy: 'SYSTEM-AUTO',
        approvedBy: 'ADMIN-001',
        approvedAt: new Date('2024-11-02'),
        createdAt: new Date('2024-11-01')
      },
      
      {
        id: 'INV-2024-004',
        organizationId: 'ORG-DEF',
        organizationName: 'DEF Manufacturing Ltd',
        contractId: 'CNT-2024-DEF-010',
        agreementStartDate: new Date('2024-06-01'),
        agreementEndDate: new Date('2025-05-31'),
        billingCycle: 'Monthly',
        billingPeriodStart: new Date('2024-12-01'),
        billingPeriodEnd: new Date('2024-12-31'),
        paymentTerms: 'Net 45',
        amount: 680000.00,
        gstAmount: 122400.00,
        totalAmount: 802400.00,
        amountPaid: 400000.00,
        status: 'Partially Paid',
        date: new Date('2024-12-01'),
        dueDate: new Date('2025-01-15'),
        paidDate: new Date('2024-12-15'),
        paymentMode: 'Bank Transfer',
        transactionRef: 'TXN-2024-12-15-789',
        trips: 45,
        totalDistance: 8950.0,
        totalFuelConsumed: 2150.0,
        totalIdleTime: 89.5,
        vehicles: [
          { type: 'Heavy Truck', count: 3, distance: 5200.0, trips: 25, cost: 420000.0 },
          { type: 'Trailer', count: 2, distance: 3750.0, trips: 20, cost: 260000.0 }
        ],
        pricingApplied: {
          volumeSlabApplied: '0-200 trips @ ₹25/km',
          discountPercent: 0.0,
          minimumCommitmentApplied: false
        },
        charges: {
          baseCharges: 500000.0,
          perKmCharges: 125000.0,
          fuelSurcharge: 35000.0,
          tollCharges: 12000.0,
          waitingCharges: 6000.0,
          loadingUnloadingCharges: 2000.0
        },
        generatedBy: 'SYSTEM-AUTO',
        approvedBy: 'ADMIN-001',
        approvedAt: new Date('2024-12-02'),
        createdAt: new Date('2024-12-01')
      },
      
      {
        id: 'INV-2024-005',
        organizationId: 'ORG-XYZ',
        organizationName: 'XYZ Transport Solutions',
        contractId: 'CNT-2024-XYZ-005',
        agreementStartDate: new Date('2024-03-15'),
        agreementEndDate: new Date('2025-03-14'),
        billingCycle: 'Weekly',
        billingPeriodStart: new Date('2024-12-08'),
        billingPeriodEnd: new Date('2024-12-14'),
        paymentTerms: 'Net 15',
        amount: 95000.00,
        gstAmount: 17100.00,
        totalAmount: 112100.00,
        amountPaid: 0.0,
        status: 'Pending',
        date: new Date('2024-12-15'),
        dueDate: new Date('2024-12-30'),
        paidDate: null,
        paymentMode: null,
        transactionRef: null,
        trips: 67,
        totalDistance: 5240.0,
        totalFuelConsumed: 756.0,
        totalIdleTime: 22.0,
        vehicles: [
          { type: 'Car', count: 10, distance: 4200.0, trips: 52, cost: 75000.0 },
          { type: 'Bike', count: 8, distance: 1040.0, trips: 15, cost: 20000.0 }
        ],
        pricingApplied: {
          volumeSlabApplied: '0-1000 trips @ ₹8/km',
          discountPercent: 0.0,
          minimumCommitmentApplied: false
        },
        charges: {
          baseCharges: 70000.0,
          perKmCharges: 15680.0,
          fuelSurcharge: 5000.0,
          tollCharges: 2320.0,
          waitingCharges: 1500.0,
          loadingUnloadingCharges: 500.0
        },
        generatedBy: 'SYSTEM-AUTO',
        approvedBy: 'ADMIN-001',
        approvedAt: new Date('2024-12-15'),
        createdAt: new Date('2024-12-15')
      }
    ];
    
    await db.collection('invoices').insertMany(invoices);
    console.log(`✅ Created ${invoices.length} invoices`);
    
    // ==================== AUDIT LOGS ====================
    console.log('📝 Creating audit logs...');
    
    const auditLogs = [
      {
        id: 'AUDIT-' + Date.now() + '-001',
        entityType: 'contract',
        entityId: 'CNT-2024-ABC-001',
        action: 'created',
        userId: 'ADMIN-001',
        userName: 'Admin User',
        timestamp: new Date('2023-12-15'),
        changes: { status: 'active', organizationId: 'ORG-ABC' },
        remarks: 'Initial contract creation for ABC Logistics'
      },
      {
        id: 'AUDIT-' + Date.now() + '-002',
        entityType: 'invoice',
        entityId: 'INV-2024-001',
        action: 'created',
        userId: 'SYSTEM-AUTO',
        userName: 'System Auto',
        timestamp: new Date('2024-12-01'),
        changes: { amount: 245680.50, status: 'Pending' },
        remarks: 'Auto-generated monthly invoice'
      },
      {
        id: 'AUDIT-' + Date.now() + '-003',
        entityType: 'invoice',
        entityId: 'INV-2024-001',
        action: 'payment_recorded',
        userId: 'ADMIN-001',
        userName: 'Admin User',
        timestamp: new Date('2024-12-25'),
        changes: { amountPaid: 289902.99, status: 'Paid' },
        remarks: 'Full payment received via bank transfer'
      },
      {
        id: 'AUDIT-' + Date.now() + '-004',
        entityType: 'contract',
        entityId: 'CNT-2024-XYZ-005',
        action: 'created',
        userId: 'ADMIN-001',
        userName: 'Admin User',
        timestamp: new Date('2024-03-01'),
        changes: { status: 'active', organizationId: 'ORG-XYZ' },
        remarks: 'Contract created for XYZ Transport Solutions'
      },
      {
        id: 'AUDIT-' + Date.now() + '-005',
        entityType: 'invoice',
        entityId: 'INV-2024-002',
        action: 'payment_recorded',
        userId: 'ADMIN-001',
        userName: 'Admin User',
        timestamp: new Date('2024-12-10'),
        changes: { amountPaid: 75000.00, status: 'Partially Paid' },
        remarks: 'Partial payment received via cheque'
      }
    ];
    
    await db.collection('audit_logs').insertMany(auditLogs);
    console.log(`✅ Created ${auditLogs.length} audit log entries`);
    
    // ==================== SUMMARY ====================
    console.log('\n' + '='.repeat(60));
    console.log('🎉 BILLING DUMMY DATA CREATION COMPLETE!');
    console.log('='.repeat(60));
    console.log(`📋 Contracts: ${contracts.length}`);
    console.log(`🧾 Invoices: ${invoices.length}`);
    console.log(`📝 Audit Logs: ${auditLogs.length}`);
    console.log('');
    console.log('📊 Contract Summary:');
    contracts.forEach(contract => {
      console.log(`   • ${contract.contractId} - ${contract.organizationName} (${contract.status})`);
    });
    console.log('');
    console.log('💰 Invoice Summary:');
    invoices.forEach(invoice => {
      console.log(`   • ${invoice.id} - ₹${invoice.totalAmount.toLocaleString()} (${invoice.status})`);
    });
    console.log('');
    console.log('🔗 Backend API Endpoints Available:');
    console.log('   • GET /api/billing/contracts - Get all contracts');
    console.log('   • GET /api/billing/invoices - Get all invoices');
    console.log('   • POST /api/billing/invoices/generate - Generate new invoice');
    console.log('   • PATCH /api/billing/invoices/:id/payment - Record payment');
    console.log('');
    console.log('✅ Ready to connect frontend with backend!');
    console.log('='.repeat(60));
    
  } catch (error) {
    console.error('❌ Error creating billing dummy data:', error);
    throw error;
  } finally {
    if (client) {
      await client.close();
    }
  }
}

// Run the script
if (require.main === module) {
  createBillingDummyData()
    .then(() => {
      console.log('✅ Script completed successfully');
      process.exit(0);
    })
    .catch((error) => {
      console.error('❌ Script failed:', error);
      process.exit(1);
    });
}

module.exports = { createBillingDummyData };