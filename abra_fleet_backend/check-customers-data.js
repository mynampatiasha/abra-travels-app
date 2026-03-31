// Check customer data in database
const mongoose = require('mongoose');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet_management';

async function checkCustomersData() {
  try {
    console.log('\n🔍 Checking Customer Data');
    console.log('='.repeat(80));
    
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB');
    
    const BillingCustomer = mongoose.model('BillingCustomer', new mongoose.Schema({}, { strict: false, collection: 'billing-customers' }));
    
    const customers = await BillingCustomer.find({ isDeleted: { $ne: true } })
      .select('customerId customerDisplayName companyRegistration customerType primaryEmail')
      .limit(10)
      .lean();
    
    console.log(`\n📋 Found ${customers.length} customers:\n`);
    
    customers.forEach((customer, index) => {
      console.log(`${index + 1}. Customer ID: ${customer.customerId}`);
      console.log(`   customerDisplayName: "${customer.customerDisplayName || '(empty)'}"`);
      console.log(`   companyRegistration: "${customer.companyRegistration || '(empty)'}"`);
      console.log(`   Type: ${customer.customerType}`);
      console.log(`   Email: ${customer.primaryEmail}`);
      console.log('');
    });
    
    await mongoose.disconnect();
    console.log('✅ Disconnected from MongoDB');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

checkCustomersData();
