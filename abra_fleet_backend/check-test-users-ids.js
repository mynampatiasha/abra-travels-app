// check-test-users-ids.js - Check test users and their specific IDs
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function checkTestUsersIds() {
  const client = new MongoClient(process.env.MONGODB_URI);
  await client.connect();
  const db = client.db('abra_fleet');
  
  console.log('🔍 CHECKING TEST USERS AND THEIR IDs:');
  console.log('═'.repeat(50));
  
  const testUsers = [
    { collection: 'drivers', email: 'testdriver@abrafleet.com', idField: 'driverId' },
    { collection: 'customers', email: 'testcustomer@abrafleet.com', idField: 'customerId' },
    { collection: 'clients', email: 'testclient@abrafleet.com', idField: 'clientId' },
    { collection: 'employee_admins', email: 'testemployee@abrafleet.com', idField: 'employeeId' }
  ];
  
  for (const testUser of testUsers) {
    const user = await db.collection(testUser.collection).findOne({ email: testUser.email });
    if (user) {
      console.log(`\n📋 ${testUser.collection.toUpperCase()}:`);
      console.log(`   Email: ${user.email}`);
      console.log(`   User ID: ${user._id}`);
      console.log(`   ${testUser.idField}: ${user[testUser.idField] || 'MISSING'}`);
      console.log(`   Role: ${user.role || 'MISSING'}`);
    } else {
      console.log(`\n❌ ${testUser.collection}: User not found`);
    }
  }
  
  await client.close();
}

checkTestUsersIds().catch(console.error);