// Check if Asha's customers exist in database
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function checkAshaCustomers() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Get Asha's rosters
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);
    
    const rosters = await db.collection('rosters').find({
      driverId: 'AMATisPyRgQc39FXypD4iu7unVs1',
      scheduledDate: { $gte: today, $lt: tomorrow }
    }).toArray();
    
    console.log(`\n📋 Found ${rosters.length} rosters for Asha today`);
    
    for (const roster of rosters) {
      console.log('\n' + '='.repeat(80));
      console.log(`Roster ID: ${roster._id}`);
      console.log(`Customer ID in roster: ${roster.customerId}`);
      console.log(`Customer Name in roster: ${roster.customerName || 'N/A'}`);
      console.log(`Customer Email in roster: ${roster.customerEmail || 'N/A'}`);
      console.log(`Pickup: ${roster.pickupLocation || roster.loginPickupAddress || 'N/A'}`);
      console.log(`Drop: ${roster.dropLocation || roster.officeLocation || 'N/A'}`);
      
      // Try to find customer in customers collection
      let customer = null;
      
      // Try by uid
      if (roster.customerId) {
        customer = await db.collection('customers').findOne({
          uid: roster.customerId
        });
        if (customer) {
          console.log('✅ Found customer by UID');
        }
      }
      
      // Try by _id
      if (!customer && roster.customerId) {
        try {
          const { ObjectId } = require('mongodb');
          customer = await db.collection('customers').findOne({
            _id: new ObjectId(roster.customerId)
          });
          if (customer) {
            console.log('✅ Found customer by _id (ObjectId)');
          }
        } catch (e) {
          // Not a valid ObjectId
        }
      }
      
      // Try by email
      if (!customer && roster.customerEmail) {
        customer = await db.collection('customers').findOne({
          email: roster.customerEmail
        });
        if (customer) {
          console.log('✅ Found customer by email');
        }
      }
      
      if (customer) {
        console.log(`\n👤 Customer Details:`);
        console.log(`   Name: ${customer.name}`);
        console.log(`   Email: ${customer.email}`);
        console.log(`   Phone: ${customer.phone}`);
        console.log(`   UID: ${customer.uid || 'N/A'}`);
        console.log(`   _id: ${customer._id}`);
      } else {
        console.log('❌ Customer NOT found in customers collection');
        console.log('   This is why "Unknown Customer" appears in the app');
      }
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('\n💡 SOLUTION:');
    console.log('   The test data customers need to be created in the customers collection');
    console.log('   OR the roster needs to have customerName/customerEmail fields populated');
    console.log('   The backend now falls back to roster fields if customer not found');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkAshaCustomers();
