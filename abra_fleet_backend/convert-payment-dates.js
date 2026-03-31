// Convert paymentDate from STRING to DATE object
require('dotenv').config();
const mongoose = require('mongoose');

async function convertPaymentDates() {
  try {
    console.log('\n📅 CONVERTING PAYMENT DATES TO DATE OBJECTS...\n');
    console.log('='.repeat(80));
    
    const MONGODB_URI = process.env.MONGODB_URI;
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');
    
    const db = mongoose.connection.db;
    
    const allPayments = await db.collection('payments_received').find({}).toArray();
    console.log(`📦 Found ${allPayments.length} payments\n`);
    
    let convertedCount = 0;
    
    for (const payment of allPayments) {
      console.log(`\n🔍 Payment #${payment.paymentNumber || payment._id}:`);
      console.log(`   paymentDate type: ${typeof payment.paymentDate}`);
      console.log(`   paymentDate value: ${payment.paymentDate}`);
      
      // Check if paymentDate is a string
      if (payment.paymentDate && typeof payment.paymentDate === 'string') {
        // Parse DD/MM/YYYY format
        const parts = payment.paymentDate.split('/');
        
        if (parts.length === 3) {
          const day = parseInt(parts[0]);
          const month = parseInt(parts[1]) - 1; // 0-indexed
          const year = parseInt(parts[2]);
          const dateObj = new Date(year, month, day);
          
          console.log(`   ✅ Converting to: ${dateObj.toISOString()}`);
          
          await db.collection('payments_received').updateOne(
            { _id: payment._id },
            { $set: { paymentDate: dateObj } }
          );
          
          convertedCount++;
        } else {
          console.log(`   ⚠️  Cannot parse date format`);
        }
      } else if (payment.paymentDate instanceof Date) {
        console.log(`   ℹ️  Already a Date object`);
      } else {
        console.log(`   ⚠️  No paymentDate field`);
      }
    }
    
    console.log('\n' + '='.repeat(80));
    console.log(`\n📊 CONVERTED: ${convertedCount} payments\n`);
    
    // Verify
    console.log('🔍 VERIFICATION:\n');
    const verified = await db.collection('payments_received').find({}).toArray();
    
    verified.forEach(p => {
      const dateType = typeof p.paymentDate;
      const isDate = p.paymentDate instanceof Date;
      console.log(`Payment #${p.paymentNumber || p._id}:`);
      console.log(`   Amount: ₹${p.amountReceived}`);
      console.log(`   Date Type: ${dateType} (isDate: ${isDate})`);
      console.log(`   Date Value: ${p.paymentDate}`);
      console.log('');
    });
    
    console.log('✅ DONE! Now restart backend and check Cash Flow.\n');
    
    await mongoose.connection.close();
    
  } catch (error) {
    console.error('\n❌ Error:', error);
    process.exit(1);
  }
}

convertPaymentDates();
