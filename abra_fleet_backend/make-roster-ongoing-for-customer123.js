// Script to make a roster ongoing for customer123@abrafleet.com for testing
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = process.env.MONGODB_DB_NAME || 'abra_fleet';

async function makeRosterOngoing() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(DB_NAME);
    
    // Find customer123@abrafleet.com
    const customer = await db.collection('users').findOne({
      email: 'customer123@abrafleet.com'
    });
    
    if (!customer) {
      console.log('❌ Customer not found: customer123@abrafleet.com');
      return;
    }
    
    console.log(`✅ Found customer: ${customer.name || customer.email}`);
    console.log(`   Firebase UID: ${customer.firebaseUid}`);
    console.log(`   Organization: ${customer.companyName || 'N/A'}\n`);
    
    // Find an assigned roster for this customer
    const roster = await db.collection('rosters').findOne({
      customerEmail: 'customer123@abrafleet.com',
      status: { $in: ['assigned', 'scheduled'] },
      vehicleId: { $exists: true, $ne: null },
      driverId: { $exists: true, $ne: null }
    });
    
    if (!roster) {
      console.log('❌ No assigned roster found for this customer');
      console.log('   Looking for any roster...\n');
      
      // Try to find any roster
      const anyRoster = await db.collection('rosters').findOne({
        customerEmail: 'customer123@abrafleet.com'
      });
      
      if (anyRoster) {
        console.log(`   Found roster with status: ${anyRoster.status}`);
        console.log(`   Vehicle: ${anyRoster.vehicleNumber || 'Not assigned'}`);
        console.log(`   Driver: ${anyRoster.driverName || 'Not assigned'}`);
      } else {
        console.log('   No rosters found at all for this customer');
      }
      return;
    }
    
    console.log(`✅ Found assigned roster:`);
    console.log(`   ID: ${roster._id}`);
    console.log(`   Readable ID: ${roster.readableId || 'N/A'}`);
    console.log(`   Current Status: ${roster.status}`);
    console.log(`   Vehicle: ${roster.vehicleNumber || 'N/A'}`);
    console.log(`   Driver: ${roster.driverName || 'N/A'}`);
    console.log(`   Trip Type: ${roster.tripType || 'N/A'}`);
    console.log(`   Date: ${roster.startDate || 'N/A'}\n`);
    
    // Update to ongoing status
    const updateResult = await db.collection('rosters').updateOne(
      { _id: roster._id },
      {
        $set: {
          status: 'ongoing',
          tripStartTime: new Date(),
          lastUpdated: new Date()
        }
      }
    );
    
    if (updateResult.modifiedCount > 0) {
      console.log('✅ Successfully updated roster to ONGOING status\n');
      
      // Verify the update
      const updatedRoster = await db.collection('rosters').findOne({
        _id: roster._id
      });
      
      console.log('📋 Updated Roster Details:');
      console.log(`   Status: ${updatedRoster.status}`);
      console.log(`   Trip Start Time: ${updatedRoster.tripStartTime}`);
      console.log(`   Customer: ${updatedRoster.customerName || updatedRoster.customerEmail}`);
      console.log(`   Vehicle: ${updatedRoster.vehicleNumber}`);
      console.log(`   Driver: ${updatedRoster.driverName}\n`);
      
      console.log('✅ Testing Instructions:');
      console.log('   1. Login as customer123@abrafleet.com');
      console.log('   2. Go to "My Trips" or "Active Trips" section');
      console.log('   3. You should see this trip with ONGOING status');
      console.log('   4. The trip should show real-time tracking if available\n');
      
    } else {
      console.log('⚠️  No changes made - roster may already be ongoing');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
  } finally {
    await client.close();
    console.log('\n✅ Database connection closed');
  }
}

// Run the script
makeRosterOngoing().catch(console.error);
