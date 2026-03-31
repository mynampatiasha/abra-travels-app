// Fix the roster by adding the correct customerId
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = process.env.MONGODB_DB_NAME || 'abra_fleet';

async function fixRoster() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db(DB_NAME);
    
    // Get customer's Firebase UID
    const customer = await db.collection('users').findOne({
      email: 'customer123@abrafleet.com'
    });
    
    if (!customer) {
      console.log('❌ Customer not found');
      return;
    }
    
    console.log(`✅ Customer Firebase UID: ${customer.firebaseUid}\n`);
    
    // Update the roster
    const result = await db.collection('rosters').updateOne(
      {
        customerEmail: 'customer123@abrafleet.com',
        status: 'ongoing'
      },
      {
        $set: {
          customerId: customer.firebaseUid
        }
      }
    );
    
    if (result.modifiedCount > 0) {
      console.log('✅ Roster updated successfully!\n');
      
      // Verify the update
      const updatedRoster = await db.collection('rosters').findOne({
        customerEmail: 'customer123@abrafleet.com',
        status: 'ongoing'
      });
      
      console.log('📋 Updated Roster:');
      console.log(`   customerEmail: ${updatedRoster.customerEmail}`);
      console.log(`   customerId: ${updatedRoster.customerId}`);
      console.log(`   status: ${updatedRoster.status}`);
      console.log(`   vehicleNumber: ${updatedRoster.vehicleNumber}`);
      console.log(`   driverName: ${updatedRoster.driverName}\n`);
      
      console.log('✅ The app should now be able to fetch this active trip!');
      console.log(`   Endpoint: GET /api/rosters/active-trip/${customer.firebaseUid}`);
      
    } else {
      console.log('⚠️  No roster was updated');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

fixRoster();
