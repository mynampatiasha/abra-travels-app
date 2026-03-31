// ============================================================================
// CREATE TEST PAYMENTS - For Cash Flow Chart Testing
// ============================================================================

const mongoose = require('mongoose');

async function createTestPayments() {
  try {
    console.log('\n💰 Creating Test Payments for Cash Flow...\n');
    console.log('='.repeat(80));
    
    // Use environment variable or default
    require('dotenv').config();
    const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet_management';
    
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');
    
    const db = mongoose.connection.db;
    
    // Get current fiscal year dates
    const now = new Date();
    const currentYear = now.getFullYear();
    const currentMonth = now.getMonth();
    
    let fiscalYearStart;
    if (currentMonth >= 3) {
      fiscalYearStart = new Date(currentYear, 3, 1); // April 1 this year
    } else {
      fiscalYearStart = new Date(currentYear - 1, 3, 1); // April 1 last year
    }
    
    // Create payments spread across the fiscal year
    const testPayments = [
      {
        paymentNumber: 'PAY-2025-001',
        amountReceived: 5000,
        paymentDate: new Date(fiscalYearStart.getFullYear(), 3, 15), // April
        paymentMode: 'Bank Transfer',
        reference: 'TXN123456',
        status: 'paid',
        notes: 'Test payment for April',
        createdAt: new Date(),
        updatedAt: new Date()
      },
      {
        paymentNumber: 'PAY-2025-002',
        amountReceived: 7500,
        paymentDate: new Date(fiscalYearStart.getFullYear(), 4, 20), // May
        paymentMode: 'Cash',
        reference: 'CASH-001',
        status: 'paid',
        notes: 'Test payment for May',
        createdAt: new Date(),
        updatedAt: new Date()
      },
      {
        paymentNumber: 'PAY-2025-003',
        amountReceived: 10000,
        paymentDate: new Date(fiscalYearStart.getFullYear(), 5, 10), // June
        paymentMode: 'UPI',
        reference: 'UPI-789012',
        status: 'paid',
        notes: 'Test payment for June',
        createdAt: new Date(),
        updatedAt: new Date()
      },
      {
        paymentNumber: 'PAY-2025-004',
        amountReceived: 8500,
        paymentDate: new Date(fiscalYearStart.getFullYear(), 6, 5), // July
        paymentMode: 'Bank Transfer',
        reference: 'TXN789456',
        status: 'paid',
        notes: 'Test payment for July',
        createdAt: new Date(),
        updatedAt: new Date()
      },
      {
        paymentNumber: 'PAY-2025-005',
        amountReceived: 12000,
        paymentDate: new Date(fiscalYearStart.getFullYear(), 7, 25), // August
        paymentMode: 'Cheque',
        reference: 'CHQ-456789',
        status: 'paid',
        notes: 'Test payment for August',
        createdAt: new Date(),
        updatedAt: new Date()
      },
      {
        paymentNumber: 'PAY-2025-006',
        amountReceived: 6500,
        paymentDate: new Date(fiscalYearStart.getFullYear(), 8, 12), // September
        paymentMode: 'UPI',
        reference: 'UPI-345678',
        status: 'paid',
        notes: 'Test payment for September',
        createdAt: new Date(),
        updatedAt: new Date()
      }
    ];
    
    console.log('📝 Creating payments...\n');
    
    // Check if payments already exist
    for (const payment of testPayments) {
      const existing = await db.collection('payments_received').findOne({
        paymentNumber: payment.paymentNumber
      });
      
      if (existing) {
        console.log(`   ⚠️  Payment ${payment.paymentNumber} already exists, skipping...`);
      } else {
        await db.collection('payments_received').insertOne(payment);
        console.log(`   ✅ Created ${payment.paymentNumber} - ₹${payment.amountReceived} on ${payment.paymentDate.toISOString().split('T')[0]}`);
      }
    }
    
    // Summary
    const totalPayments = await db.collection('payments_received').countDocuments();
    const totalAmount = await db.collection('payments_received').aggregate([
      { $match: { status: 'paid' } },
      { $group: { _id: null, total: { $sum: '$amountReceived' } } }
    ]).toArray();
    
    console.log('\n' + '='.repeat(80));
    console.log('\n📊 Summary:');
    console.log(`   Total payments in database: ${totalPayments}`);
    console.log(`   Total amount received: ₹${totalAmount[0]?.total || 0}`);
    console.log('\n✅ Test payments created successfully!\n');
    
    await mongoose.connection.close();
    
  } catch (error) {
    console.error('\n❌ Error creating test payments:', error);
    process.exit(1);
  }
}

createTestPayments();
