// Check actual payment fields in database
const mongoose = require('mongoose');

async function checkPaymentFields() {
  try {
    await mongoose.connect('mongodb://localhost:27017/abra_fleet_management');
    console.log('✅ Connected to MongoDB\n');
    
    const db = mongoose.connection.db;
    const payments = await db.collection('payments_received').find({}).limit(3).toArray();
    
    console.log(`Found ${payments.length} payments\n`);
    
    payments.forEach((payment, index) => {
      console.log(`Payment ${index + 1}:`);
      console.log(JSON.stringify(payment, null, 2));
      console.log('\n' + '='.repeat(80) + '\n');
    });
    
    await mongoose.connection.close();
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
}

checkPaymentFields();
