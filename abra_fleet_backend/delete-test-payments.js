// Delete test payments and fix real payment field names
require('dotenv').config();
const mongoose = require('mongoose');

async function cleanupPayments() {
  try {
    console.log('\n🧹 Cleaning up payments...\n');
    console.log('='.repeat(80));
    
    const MONGODB_URI = process.env.MONGODB_URI;
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');
    
    const db = mongoose.connection.db;
    
    // 1. Delete test payments
    console.log('1️⃣ Deleting test payments (PAY-2025-*)...');
    const deleteResult = await db.collection('payments_received').deleteMany({
      paymentNumber: { $regex: /^PAY-2025-/ }
    });
    console.log(`   ✅ Deleted ${deleteResult.deletedCount} test payments\n`);
    
    // 2. Fix real payment field names
    console.log('2️⃣ Fixing real payment field names...');
    const realPayments = await db.collection('payments_received').find({}).toArray();
    
    let fixedCount = 0;
    for (const payment of realPayments) {
      const updates = {};
      
      // Fix amount field
      if (!payment.amountReceived && payment.amount) {
        updates.amountReceived = payment.amount;
      }
      
      // Fix date field - handle DD/MM/YYYY format
      if (!payment.paymentDate && payment.date) {
        // Convert DD/MM/YYYY to proper Date object
        const dateParts = payment.date.split('/');
        if (dateParts.length === 3) {
          const day = parseInt(dateParts[0]);
          const month = parseInt(dateParts[1]) - 1; // Month is 0-indexed
          const year = parseInt(dateParts[2]);
          updates.paymentDate = new Date(year, month, day);
        } else {
          updates.paymentDate = new Date(payment.date);
        }
      }
      
      if (Object.keys(updates).length > 0) {
        await db.collection('payments_received').updateOne(
          { _id: payment._id },
          { $set: updates }
        );
        fixedCount++;
        console.log(`   ✅ Fixed payment #${payment.paymentNumber || payment._id}`);
      }
    }
    
    console.log(`\n   Total fixed: ${fixedCount} payments\n`);
    
    // 3. Verify
    console.log('3️⃣ Verifying...');
    const allPayments = await db.collection('payments_received').find({}).toArray();
    
    console.log(`\n📊 Final Status:`);
    console.log(`   Total payments: ${allPayments.length}`);
    
    let totalAmount = 0;
    allPayments.forEach(p => {
      const amount = p.amountReceived || p.amount || 0;
      const date = p.paymentDate || p.date || 'N/A';
      if (amount > 0) {
        totalAmount += amount;
        console.log(`   - Payment #${p.paymentNumber || p._id}: ₹${amount} on ${date}`);
      }
    });
    
    console.log(`\n   Total amount: ₹${totalAmount}`);
    console.log('\n✅ Cleanup complete!\n');
    
    await mongoose.connection.close();
    
  } catch (error) {
    console.error('\n❌ Error:', error);
    process.exit(1);
  }
}

cleanupPayments();
