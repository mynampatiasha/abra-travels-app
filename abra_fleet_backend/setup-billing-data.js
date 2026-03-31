const { MongoClient } = require('mongodb');
require('dotenv').config();

async function setupBillingData() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Clear existing data
    console.log('\n🗑️  Clearing existing billing data...');
    await db.collection('contracts').deleteMany({});
    await db.collection('invoices').deleteMany({});
    await db.collection('audit_logs').deleteMany({ entityType: { $in: ['contract', 'invoice'] } });
    
    // Insert sample contracts
    console.log('\n📝 Creating sample contracts...');
    
    const contracts = [
      {
        contractId: 'CNT-2024-ABC-001',
        organizationId: 'ORG-ABC',
        organizationName: 'ABC Logistics Pvt Ltd',
        startDate: new Date('2024-01-01'),
        endDate: new Date('2025-12-31'),
        status: 'active',
        autoRenewal: true,
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
            gracePeriodMinutes: 5,
            minimumChargePerTrip: 60.0
          }
        },
        surcharges: {
          peakHoursPercent: 15.0,
          nightShiftPercent: 25.0,
          weekendPercent: 10.0,
          fuelSurchargePercent: 5.0,
          holidayPercent: 20.0
        },
        volumeSlabs: [
          { minTrips: 0, maxTrips: 500, discountPercent: 0, description: '0-500 trips' },
          { minTrips: 501, maxTrips: 1000, discountPercent: 8.33, description: '501-1000 trips' },
          { minTrips: 1001, maxTrips: 1500, discountPercent: 16.67, description: '1001-1500 trips' },
          { minTrips: 1501, maxTrips: 999999, discountPercent: 25.0, description: '1501+ trips' }
        ],
        paymentTerms: {
          monthlyMinimum: 70000.0,
          monthlyMaximum: 200000.0,
          paymentDueDays: 30,
          billingCycle: 'Monthly',
          currency: 'INR',
          creditLimit: 500000.0,
          latePenaltyPercent: 2.0,
          freeCancellationPercent: 5.0,
          cancellationPenalty: 50.0
        },
        additionalCharges: {
          tollCharges: 'actual',
          parkingCharges: 'actual',
          vehicleCleaningCharge: 500.0,
          gpsDeviationPenalty: 100.0,
          loadingUnloadingPerHour: 200.0
        },
        slaTerms: {
          onTimePickupPercent: 95.0,
          vehicleAvailabilityPercent: 99.0,
          driverRatingMinimum: 4.0,
          responseTimeMinutes: 15,
          slaBreachPenalty: 500.0
        },
        createdAt: new Date(),
        createdBy: 'admin'
      },
      {
        contractId: 'CNT-2024-XYZ-002',
        organizationId: 'ORG-XYZ',
        organizationName: 'XYZ Transport Solutions',
        startDate: new Date('2024-03-15'),
        endDate: new Date('2025-03-14'),
        status: 'active',
        autoRenewal: false,
        vehiclePricing: {
          'Car': {
            baseFarePerTrip: 35.0,
            ratePerKm: 9.0,
            ratePerMinuteWaiting: 1.2,
            gracePeriodMinutes: 5,
            minimumChargePerTrip: 70.0
          },
          'Bike': {
            baseFarePerTrip: 20.0,
            ratePerKm: 5.0,
            ratePerMinuteWaiting: 0.5,
            gracePeriodMinutes: 3,
            minimumChargePerTrip: 40.0
          }
        },
        surcharges: {
          peakHoursPercent: 12.0,
          nightShiftPercent: 20.0,
          weekendPercent: 8.0,
          fuelSurchargePercent: 4.0,
          holidayPercent: 15.0
        },
        volumeSlabs: [
          { minTrips: 0, maxTrips: 300, discountPercent: 0, description: '0-300 trips' },
          { minTrips: 301, maxTrips: 600, discountPercent: 5.0, description: '301-600 trips' },
          { minTrips: 601, maxTrips: 999999, discountPercent: 10.0, description: '601+ trips' }
        ],
        paymentTerms: {
          monthlyMinimum: 50000.0,
          monthlyMaximum: 150000.0,
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
          vehicleCleaningCharge: 300.0,
          gpsDeviationPenalty: 75.0,
          loadingUnloadingPerHour: 150.0
        },
        slaTerms: {
          onTimePickupPercent: 90.0,
          vehicleAvailabilityPercent: 95.0,
          driverRatingMinimum: 3.5,
          responseTimeMinutes: 20,
          slaBreachPenalty: 300.0
        },
        createdAt: new Date(),
        createdBy: 'admin'
      },
      {
        contractId: 'CNT-2023-GFS-003',
        organizationId: 'ORG-GFS',
        organizationName: 'Global Freight Services',
        startDate: new Date('2023-06-01'),
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
            ratePerKm: 22.0,
            ratePerMinuteWaiting: 4.0,
            gracePeriodMinutes: 10,
            minimumChargePerTrip: 300.0
          }
        },
        surcharges: {
          peakHoursPercent: 18.0,
          nightShiftPercent: 30.0,
          weekendPercent: 12.0,
          fuelSurchargePercent: 8.0,
          holidayPercent: 25.0
        },
        volumeSlabs: [
          { minTrips: 0, maxTrips: 200, discountPercent: 0, description: '0-200 trips' },
          { minTrips: 201, maxTrips: 400, discountPercent: 10.0, description: '201-400 trips' },
          { minTrips: 401, maxTrips: 999999, discountPercent: 15.0, description: '401+ trips' }
        },
        paymentTerms: {
          monthlyMinimum: 150000.0,
          monthlyMaximum: 500000.0,
          paymentDueDays: 45,
          billingCycle: 'Monthly',
          currency: 'INR',
          creditLimit: 1000000.0,
          latePenaltyPercent: 2.5,
          freeCancellationPercent: 2.0,
          cancellationPenalty: 100.0
        },
        additionalCharges: {
          tollCharges: 'actual',
          parkingCharges: 'actual',
          vehicleCleaningCharge: 800.0,
          gpsDeviationPenalty: 150.0,
          loadingUnloadingPerHour: 300.0
        },
        slaTerms: {
          onTimePickupPercent: 98.0,
          vehicleAvailabilityPercent: 99.5,
          driverRatingMinimum: 4.5,
          responseTimeMinutes: 10,
          slaBreachPenalty: 1000.0
        },
        createdAt: new Date(),
        createdBy: 'admin'
      }
    ];
    
    const contractResult = await db.collection('contracts').insertMany(contracts);
    console.log(`✅ Created ${contractResult.insertedCount} contracts`);
    
    // Insert sample invoices
    console.log('\n💰 Creating sample invoices...');
    
    const invoices = [
      {
        id: 'INV-2024-001',
        contractId: 'CNT-2024-ABC-001',
        organizationId: 'ORG-ABC',
        organizationName: 'ABC Logistics Pvt Ltd',
        agreementId: 'CNT-2024-ABC-001',
        agreementStartDate: new Date('2024-01-01'),
        agreementEndDate: new Date('2025-12-31'),
        billingCycle: 'Monthly',
        paymentTerms: 'Net 30',
        billingPeriodStart: new Date('2024-12-01'),
        billingPeriodEnd: new Date('2024-12-31'),
        amount: 245680.50,
        gstAmount: 44222.49,
        totalAmount: 289902.99,
        amountPaid: 289902.99,
        status: 'Paid',
        date: new Date('2024-12-01'),
        dueDate: new Date('2024-12-31'),
        paidDate: new Date('2024-12-25'),
        paymentMode: 'Bank Transfer',
        trips: 156,
        totalDistance: 12450.5,
        totalFuelConsumed: 1850.25,
        totalIdleTime: 45.5,
        vehicles: [
          { type: 'Truck', count: 8, distance: 8500.0, cost: 170000.0 },
          { type: 'Van', count: 5, distance: 3950.5, cost: 75680.50 }
        ],
        chargeBreakdown: [
          { type: 'Base Charges', description: 'Base fare for trips', amount: 180000.0 },
          { type: 'Distance Charges', description: 'Per km charges', amount: 45680.50 },
          { type: 'Fuel Surcharge', description: '5% fuel surcharge', amount: 12000.0 },
          { type: 'Volume Discount', description: '8.33% off for 156 trips', amount: -12000.0 }
        ],
        pricingReference: {
          contractId: 'CNT-2024-ABC-001',
          volumeSlabApplied: { minTrips: 0, maxTrips: 500, discountPercent: 0 },
          minimumCommitmentApplied: false,
          discountAmount: 12000.0
        },
        vehicleTypeCosts: {
          'Truck': 170000.0,
          'Van': 75680.50
        },
        createdAt: new Date('2024-12-01')
      },
      {
        id: 'INV-2024-002',
        contractId: 'CNT-2024-XYZ-002',
        organizationId: 'ORG-XYZ',
        organizationName: 'XYZ Transport Solutions',
        agreementId: 'CNT-2024-XYZ-002',
        agreementStartDate: new Date('2024-03-15'),
        agreementEndDate: new Date('2025-03-14'),
        billingCycle: 'Weekly',
        paymentTerms: 'Net 15',
        billingPeriodStart: new Date('2024-12-01'),
        billingPeriodEnd: new Date('2024-12-07'),
        amount: 125000.00,
        gstAmount: 22500.00,
        totalAmount: 147500.00,
        amountPaid: 75000.00,
        status: 'Partially Paid',
        date: new Date('2024-12-03'),
        dueDate: new Date('2024-12-18'),
        paidDate: new Date('2024-12-10'),
        paymentMode: 'Cheque',
        trips: 89,
        totalDistance: 6780.0,
        totalFuelConsumed: 980.5,
        totalIdleTime: 28.0,
        vehicles: [
          { type: 'Car', count: 12, distance: 6780.0, cost: 125000.0 }
        ],
        chargeBreakdown: [
          { type: 'Base Charges', description: 'Base fare for trips', amount: 95000.0 },
          { type: 'Distance Charges', description: 'Per km charges', amount: 20340.0 },
          { type: 'Fuel Surcharge', description: '4% fuel surcharge', amount: 6500.0 },
          { type: 'Peak Hour Surcharge', description: '12% peak hour charges', amount: 3160.0 }
        ],
        pricingReference: {
          contractId: 'CNT-2024-XYZ-002',
          volumeSlabApplied: { minTrips: 0, maxTrips: 300, discountPercent: 0 },
          minimumCommitmentApplied: false,
          discountAmount: 0
        },
        vehicleTypeCosts: {
          'Car': 125000.0
        },
        createdAt: new Date('2024-12-03')
      },
      {
        id: 'INV-2024-003',
        contractId: 'CNT-2023-GFS-003',
        organizationId: 'ORG-GFS',
        organizationName: 'Global Freight Services',
        agreementId: 'CNT-2023-GFS-003',
        agreementStartDate: new Date('2023-06-01'),
        agreementEndDate: new Date('2025-05-31'),
        billingCycle: 'Monthly',
        paymentTerms: 'Net 45',
        billingPeriodStart: new Date('2024-11-01'),
        billingPeriodEnd: new Date('2024-11-30'),
        amount: 485000.00,
        gstAmount: 87300.00,
        totalAmount: 572300.00,
        amountPaid: 0.0,
        status: 'Overdue',
        date: new Date('2024-11-01'),
        dueDate: new Date('2024-12-16'),
        paidDate: null,
        paymentMode: null,
        trips: 234,
        totalDistance: 18950.8,
        totalFuelConsumed: 2845.5,
        totalIdleTime: 67.5,
        vehicles: [
          { type: 'Heavy Truck', count: 15, distance: 15200.0, cost: 380000.0 },
          { type: 'Trailer', count: 6, distance: 3750.8, cost: 105000.0 }
        ],
        chargeBreakdown: [
          { type: 'Base Charges', description: 'Base fare for trips', amount: 350000.0 },
          { type: 'Distance Charges', description: 'Per km charges', amount: 94754.0 },
          { type: 'Fuel Surcharge', description: '8% fuel surcharge', amount: 25000.0 },
          { type: 'Night Shift Surcharge', description: '30% night charges', amount: 15246.0 }
        ],
        pricingReference: {
          contractId: 'CNT-2023-GFS-003',
          volumeSlabApplied: { minTrips: 201, maxTrips: 400, discountPercent: 10.0 },
          minimumCommitmentApplied: false,
          discountAmount: 48500.0
        },
        vehicleTypeCosts: {
          'Heavy Truck': 380000.0,
          'Trailer': 105000.0
        },
        createdAt: new Date('2024-11-01')
      },
      {
        id: 'INV-2024-004',
        contractId: 'CNT-2024-ABC-001',
        organizationId: 'ORG-ABC',
        organizationName: 'ABC Logistics Pvt Ltd',
        agreementId: 'CNT-2024-ABC-001',
        agreementStartDate: new Date('2024-01-01'),
        agreementEndDate: new Date('2025-12-31'),
        billingCycle: 'Monthly',
        paymentTerms: 'Net 30',
        billingPeriodStart: new Date('2024-11-01'),
        billingPeriodEnd: new Date('2024-11-30'),
        amount: 168500.00,
        gstAmount: 30330.00,
        totalAmount: 198830.00,
        amountPaid: 0.0,
        status: 'Pending',
        date: new Date('2024-12-05'),
        dueDate: new Date('2025-01-04'),
        paidDate: null,
        paymentMode: null,
        trips: 142,
        totalDistance: 9450.0,
        totalFuelConsumed: 1420.75,
        totalIdleTime: 38.5,
        vehicles: [
          { type: 'Van', count: 10, distance: 9450.0, cost: 168500.0 }
        ],
        chargeBreakdown: [
          { type: 'Base Charges', description: 'Base fare for trips', amount: 125000.0 },
          { type: 'Distance Charges', description: 'Per km charges', amount: 28350.0 },
          { type: 'Fuel Surcharge', description: '5% fuel surcharge', amount: 10000.0 },
          { type: 'Weekend Surcharge', description: '10% weekend charges', amount: 5150.0 }
        ],
        pricingReference: {
          contractId: 'CNT-2024-ABC-001',
          volumeSlabApplied: { minTrips: 0, maxTrips: 500, discountPercent: 0 },
          minimumCommitmentApplied: false,
          discountAmount: 0
        },
        vehicleTypeCosts: {
          'Van': 168500.0
        },
        createdAt: new Date('2024-12-05')
      }
    ];
    
    const invoiceResult = await db.collection('invoices').insertMany(invoices);
    console.log(`✅ Created ${invoiceResult.insertedCount} invoices`);
    
    // Create audit logs
    console.log('\n📋 Creating audit logs...');
    const auditLogs = [];
    
    contracts.forEach(contract => {
      auditLogs.push({
        id: `AUDIT-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
        entityType: 'contract',
        entityId: contract.contractId,
        action: 'created',
        userId: 'admin',
        userName: 'System Admin',
        timestamp: contract.createdAt,
        changes: contract,
        remarks: 'Initial contract setup'
      });
    });
    
    invoices.forEach(invoice => {
      auditLogs.push({
        id: `AUDIT-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
        entityType: 'invoice',
        entityId: invoice.id,
        action: 'created',
        userId: 'admin',
        userName: 'System Admin',
        timestamp: invoice.createdAt,
        changes: invoice,
        remarks: 'Invoice generated from contract'
      });
    });
    
    const auditResult = await db.collection('audit_logs').insertMany(auditLogs);
    console.log(`✅ Created ${auditResult.insertedCount} audit log entries`);
    
    // Summary
    console.log('\n' + '='.repeat(60));
    console.log('✅ BILLING DATA SETUP COMPLETE!');
    console.log('='.repeat(60));
    console.log(`\n📊 Summary:`);
    console.log(`   - Contracts: ${contractResult.insertedCount}`);
    console.log(`   - Invoices: ${invoiceResult.insertedCount}`);
    console.log(`   - Audit Logs: ${auditResult.insertedCount}`);
    console.log(`\n🔗 API Endpoints:`);
    console.log(`   - GET  http://localhost:3000/api/billing/contracts`);
    console.log(`   - GET  http://localhost:3000/api/billing/invoices`);
    console.log(`   - POST http://localhost:3000/api/billing/invoices/generate`);
    console.log('\n');
    
  } catch (error) {
    console.error('❌ Error setting up billing data:', error);
  } finally {
    await client.close();
    console.log('👋 Disconnected from MongoDB\n');
  }
}

// Run the setup
setupBillingData();
