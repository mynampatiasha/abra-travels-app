// Check what fields the roster actually has
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = process.env.MONGODB_DB_NAME || 'abra_fleet';

async function checkFields() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db(DB_NAME);
    
    // Find the roster for customer123
    const roster = await db.collection('rosters').findOne({
      customerEmail: 'customer123@abrafleet.com',
      status: 'ongoing'
    });
    
    if (!roster) {
      console.log('❌ No ongoing roster found');
      return;
    }
    
    console.log('✅ Found ongoing roster\n');
    console.log('📋 Key Fields:');
    console.log(`   _id: ${roster._id}`);
    console.log(`   customerEmail: ${roster.customerEmail}`);
    console.log(`   customerId: ${roster.customerId || 'NOT SET'}`);
    console.log(`   status: ${roster.status}`);
    console.log(`   vehicleNumber: ${roster.vehicleNumber}`);
    console.log(`   driverName: ${roster.driverName}\n`);
    
    // Check if customerId matches the Firebase UID
    const expectedUid = 'b5aoloVR7xYI6SICibCIWecBaf82';
    
    if (roster.customerId === expectedUid) {
      console.log('✅ customerId matches Firebase UID');
    } else {
      console.log('❌ customerId does NOT match Firebase UID');
      console.log(`   Expected: ${expectedUid}`);
      console.log(`   Actual: ${roster.customerId || 'NOT SET'}\n`);
      
      console.log('🔧 Need to update the roster with correct customerId');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

checkFields();
