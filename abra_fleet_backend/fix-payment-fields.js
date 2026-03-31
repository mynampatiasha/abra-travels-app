// ============================================================================
// FIX PAYMENT FIELDS - Map old field names to correct ones
// ============================================================================

const mongoose = require('mongoose');

async function fixPaymentFields() {
  try {
    console.log('\n🔧 Fixing Payment Fields...\n');
    console.log('='.repeat(80));
    
    await mongoose.connect('mongodb://localhost:27017/abra_fleet_management');
    console.log('✅ Connected to MongoDB\n');
    
    const db = mongoose.connection.db;
    
    // Get all payments
    const payments = await db.collection('payments_received').find({}).toArray();
    console.log(`📦 Found ${payments.length} payments in database\n`);
    
    let fixedCount = 0;
    let alreadyCorrect = 0;
    
    for (const payment of payments) {
      const updates = {};
      let needsUpdate = false;
      
      // Check and fix amountReceived
      if (!payment.amountReceived) {
        if (payment.amount) {
          updates.amountReceived = payment.amount;
          needsUpdate = true;
          console.log(`   Mapping 'amount' → 'amountReceived' for payment ${payment.paymentNumber || payment._id}`);
        } else if (payment.totalAmount) {
          updates.amountReceived = payment.totalAmount;
          needsUpdate = true;
          console.log(`   Mapping 'totalAmount' → 'amountReceived' for payment ${payment.paymentNumber || payment._id}`);
        } else {
          console.log(`   ⚠️  No amount field found for payment ${payment.paymentNumber || payment._id}`);
        }
      }
      
      // Check and fix paymentDate
      if (!payment.paymentDate) {
        if (payment.date) {
          updates.paymentDate = payment.date;
          needsUpdate = true;
          console.log(`   Mapping 'date' → 'paymentDate' for payment ${payment.paymentNumber || payment._id}`);
        } else if (payment.createdAt) {
          updates.paymentDate = payment.createdAt;
          needsUpdate = true;
          console.log(`   Mapping 'createdAt' → 'paymentDate' for payment ${payment.paymentNumber || payment._id}`);
        } else {
          console.log(`   ⚠️  No date field found for payment ${payment.paymentNumber || payment._id}`);
        }
      }
      
      // Apply updates if needed
      if (needsUpdate && Object.keys(updates).length > 0) {
        await db.collection('payments_received').updateOne(
          { _id: payment._id },
          { $set: updates }
        );
        fixedCount++;
        console.log(`   ✅ Fixed payment ${payment.paymentNumber || payment._id}\n`);
      } else if (!needsUpdate) {
        alreadyCorrect++;
      }
    }
    
    console.log('='.repeat(80));
    console.log('\n📊 Summary:');
    console.log(`   Total payments: ${payments.length}`);
    console.log(`   Fixed: ${fixedCount}`);
    console.log(`   Already correct: ${alreadyCorrect}`);
    console.log(`   Issues: ${payments.length - fixedCount - alreadyCorrect}`);
    
    // Verify the fix
    console.log('\n🔍 Verifying fixes...');
    const verifyPayments = await db.collection('payments_received').find({}).limit(3).toArray();
    
    verifyPayments.forEach((payment, index) => {
      console.log(`\n   Payment ${index + 1}:`);
      console.log(`      Payment Number: ${payment.paymentNumber || 'N/A'}`);
      console.log(`      Amount Received: ₹${payment.amountReceived || 'MISSING'}`);
      console.log(`      Payment Date: ${payment.paymentDate || 'MISSING'}`);
      console.log(`      Status: ${payment.status}`);
    });
    
    console.log('\n✅ Fix complete!\n');
    
    await mongoose.connection.close();
    
  } catch (error) {
    console.error('\n❌ Error fixing payment fields:', error);
    process.exit(1);
  }
}

fixPaymentFields();
