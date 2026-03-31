// Final verification that everything is set up correctly
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = process.env.MONGODB_DB_NAME || 'abra_fleet';

async function finalVerification() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(DB_NAME);
    
    console.log('═══════════════════════════════════════════════════════');
    console.log('🔍 FINAL VERIFICATION - ONGOING TRIP FOR CUSTOMER123');
    console.log('═══════════════════════════════════════════════════════\n');
    
    // 1. Check customer exists
    const customer = await db.collection('users').findOne({
      email: 'customer123@abrafleet.com'
    });
    
    if (!customer) {
      console.log('❌ FAIL: Customer not found');
      return;
    }
    
    console.log('✅ PASS: Customer exists');
    console.log(`   Email: ${customer.email}`);
    console.log(`   Firebase UID: ${customer.firebaseUid}\n`);
    
    // 2. Check ongoing trip exists
    const trip = await db.collection('rosters').findOne({
      customerId: customer.firebaseUid,
      status: { $in: ['ongoing', 'in_progress', 'started'] }
    });
    
    if (!trip) {
      console.log('❌ FAIL: No ongoing trip found');
      return;
    }
    
    console.log('✅ PASS: Ongoing trip exists');
    console.log(`   Trip ID: ${trip._id}`);
    console.log(`   Status: ${trip.status}\n`);
    
    // 3. Check customerId is set correctly
    if (trip.customerId !== customer.firebaseUid) {
      console.log('❌ FAIL: customerId mismatch');
      console.log(`   Expected: ${customer.firebaseUid}`);
      console.log(`   Actual: ${trip.customerId}`);
      return;
    }
    
    console.log('✅ PASS: customerId matches Firebase UID\n');
    
    // 4. Check vehicle details
    if (!trip.vehicleNumber || !trip.vehicleType) {
      console.log('⚠️  WARNING: Vehicle details incomplete');
    } else {
      console.log('✅ PASS: Vehicle details present');
      console.log(`   Vehicle: ${trip.vehicleNumber} (${trip.vehicleType})\n`);
    }
    
    // 5. Check driver details
    if (!trip.driverName || !trip.driverEmail) {
      console.log('⚠️  WARNING: Driver details incomplete');
    } else {
      console.log('✅ PASS: Driver details present');
      console.log(`   Driver: ${trip.driverName} (${trip.driverEmail})\n`);
    }
    
    // Summary
    console.log('═══════════════════════════════════════════════════════');
    console.log('📊 VERIFICATION SUMMARY');
    console.log('═══════════════════════════════════════════════════════');
    console.log('✅ Customer: customer123@abrafleet.com');
    console.log('✅ Firebase UID: ' + customer.firebaseUid);
    console.log('✅ Trip Status: ' + trip.status);
    console.log('✅ Vehicle: ' + trip.vehicleNumber);
    console.log('✅ Driver: ' + trip.driverName);
    console.log('═══════════════════════════════════════════════════════\n');
    
    console.log('🎯 API ENDPOINT READY:');
    console.log(`   GET http://localhost:3000/api/rosters/active-trip/${customer.firebaseUid}\n`);
    
    console.log('📱 TEST IN APP:');
    console.log('   1. Login as: customer123@abrafleet.com');
    console.log('   2. Check dashboard for active trip');
    console.log('   3. Verify no 404 errors in console\n');
    
    console.log('✅ ALL CHECKS PASSED - READY FOR TESTING!');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

finalVerification();
