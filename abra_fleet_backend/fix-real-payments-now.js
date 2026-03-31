// FIX REAL PAYMENTS - Convert field names and date format
require('dotenv').config();
const mongoose = require('mongoose');

async function fixRealPayments() {
  try {
    console.log('\n🔧 FIXING REAL PAYMENTS NOW...\n');
    console.log('='.repeat(80));
    
    const MONGODB_URI = process.env.MONGODB_URI;
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');
    
    const db = mongoose.connection.db;
    
    // Get all payments
    const allPayments = await db.collection('payments_received').find({}).toArray();
    console.log(`📦 Found ${allPayments.length} payments\n`);
    
    let fixedCount = 0;
    
    for (const payment of allPayments) {
      console.log(`\n🔍 Checking payment #${payment.paymentNumber || payment._id}:`);
      console.log(`   Current fields:`, {
        amount: payment.amount,
        amountReceived: payment.amountReceived,
        date: payment.date,
        paymentDate: payment.paymentDate
      });
      
      const updates = {};
      let needsUpdate = false;
      
      // Fix 1: amount → amountReceived
      if (!payment.amountReceived && payment.amount) {
        updates.amountReceived = payment.amount;
        needsUpdate = true;
        console.log(`   ✅ Will add amountReceived: ${payment.amount}`);
      }
      
      // Fix 2: date string → paymentDate Date object
      if (!payment.paymentDate && payment.date) {
        // Parse DD/MM/YYYY format
        const dateStr = payment.date.toString();
        const parts = dateStr.split('/');
        
        if (parts.length === 3) {
          const day = parseInt(parts[0]);
          const month = parseInt(parts[1]) - 1; // 0-indexed
          const year = parseInt(parts[2]);
          const dateObj = new Date(year, month, day);
          
          updates.paymentDate = dateObj;
          needsUpdate = true;
          console.log(`   ✅ Will add paymentDate: ${dateObj.toISOString()}`);
        } else {
          console.log(`   ⚠️  Cannot parse date: ${dateStr}`);
        }
      }
      
      // Apply updates
      if (needsUpdate) {
        await db.collection('payments_received').updateOne(
          { _id: payment._id },
          { $set: updates }
        );
        fixedCount++;
        console.log(`   ✅ FIXED!`);
      } else {
        console.log(`   ℹ️  Already correct`);
      }
    }
    
    console.log('\n' + '='.repeat(80));
    console.log(`\n📊 SUMMARY: Fixed ${fixedCount} out of ${allPayments.length} payments\n`);
    
    // Verify the fix
    console.log('🔍 VERIFICATION:\n');
    const verifiedPayments = await db.collection('payments_received').find({}).toArray();
    
    verifiedPayments.forEach(p => {
      console.log(`Payment #${p.paymentNumber || p._id}:`);
      console.log(`   amountReceived: ₹${p.amountReceived || 'MISSING'}`);
      console.log(`   paymentDate: ${p.paymentDate ? p.paymentDate.toISOString().split('T')[0] : 'MISSING'}`);
      console.log('');
    });
    
    console.log('✅ ALL DONE! Now test the Cash Flow.\n');
    
    await mongoose.connection.close();
    
  } catch (error) {
    console.error('\n❌ Error:', error);
    process.exit(1);
  }
}

fixRealPayments();
