// check-customer-organization.js
require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function checkCustomerOrganization() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    // Find all customers with @abrafleet.com
    const customers = await db.collection('users').find({
      email: { $regex: /@abrafleet\.com$/i },
      role: 'customer'
    }).toArray();
    
    console.log(`\n📊 Found ${customers.length} customers with @abrafleet.com:`);
    
    if (customers.length === 0) {
      console.log('❌ No customers found with @abrafleet.com domain');
      return;
    }
    
    // Show all customers
    customers.forEach((customer, index) => {
      console.log(`\n--- Customer ${index + 1} ---`);
      console.log('Name:', customer.name);
      console.log('Email:', customer.email);
      console.log('Company Name:', customer.companyName);
      console.log('Organization Name:', customer.organizationName);
      console.log('Firebase UID:', customer.firebaseUid);
    });
    
    // Check the first customer
    const customer = customers[0];
    
    if (!customer) {
      console.log('❌ No customer to check');
      return;
    }
    
    console.log('\n📋 Customer Details:');
    console.log('Name:', customer.name);
    console.log('Email:', customer.email);
    console.log('Role:', customer.role);
    console.log('Company Name:', customer.companyName);
    console.log('Organization Name:', customer.organizationName);
    console.log('Firebase UID:', customer.firebaseUid);
    
    // Check if organization fields are missing
    if (!customer.companyName && !customer.organizationName) {
      console.log('\n⚠️  PROBLEM FOUND: Customer has no organization set!');
      console.log('This is why leave requests fail.');
      
      // Find a client/admin to get the organization name
      const client = await db.collection('users').findOne({
        email: { $regex: /@abrafleet\.com$/i },
        role: { $in: ['admin', 'client'] }
      });
      
      if (client) {
        const orgName = client.companyName || client.organizationName;
        console.log(`\n✅ Found organization from admin/client: ${orgName}`);
        console.log('\nTo fix, run:');
        console.log(`db.users.updateOne(
  { email: 'customer123@abrafleet.com' },
  { $set: { 
    companyName: '${orgName}',
    organizationName: '${orgName}'
  }}
)`);
      }
    } else {
      console.log('\n✅ Customer has organization set correctly');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkCustomerOrganization();
