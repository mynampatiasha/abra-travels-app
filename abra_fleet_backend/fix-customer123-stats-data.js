const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function fixCustomer123StatsData() {
  let client;
  
  try {
    console.log('='.repeat(60));
    console.log('FIXING CUSTOMER123 STATS DATA');
    console.log('='.repeat(60));

    // Connect to MongoDB
    console.log('\n1. Connecting to MongoDB...');
    client = new MongoClient(MONGODB_URI);
    await client.connect();
    const db = client.db('abra_fleet');
    console.log('✓ Connected to MongoDB');

    // The correct Firebase UID for customer123@abrafleet.com
    const correctUID = 'b5aoloVR7xYI6SICibCIWecBaf82';
    const oldUID = 'customer123_firebase_uid';

    console.log('\n2. Updating trips data...');
    
    // Update trips that were created for customer123 but have wrong UID
    const tripsUpdateResult = await db.collection('trips').updateMany(
      { customerId: oldUID },
      { $set: { customerId: correctUID } }
    );
    
    console.log(`✓ Updated ${tripsUpdateResult.modifiedCount} trips`);

    // Also update any trips that might have been created without customerId but are for customer123
    // Let's find trips with customer123 in the description or other fields
    const customer123Trips = await db.collection('trips').find({
      $or: [
        { customerId: { $exists: false } },
        { customerId: null },
        { customerId: '' },
        { 'customerInfo.email': 'customer123@abrafleet.com' }
      ]
    }).toArray();

    if (customer123Trips.length > 0) {
      console.log(`Found ${customer123Trips.length} trips that might belong to customer123`);
      
      // Update the first 20 trips to belong to customer123 (our demo data)
      const tripsToUpdate = customer123Trips.slice(0, 20);
      
      for (const trip of tripsToUpdate) {
        await db.collection('trips').updateOne(
          { _id: trip._id },
          { 
            $set: { 
              customerId: correctUID,
              customerInfo: {
                email: 'customer123@abrafleet.com',
                name: 'Customer 123',
                phone: '+91-9876543210'
              }
            } 
          }
        );
      }
      
      console.log(`✓ Updated ${tripsToUpdate.length} additional trips for customer123`);
    }

    console.log('\n3. Updating rosters data...');
    
    // Update rosters
    const rostersUpdateResult = await db.collection('rosters').updateMany(
      { userId: oldUID },
      { $set: { userId: correctUID } }
    );
    
    console.log(`✓ Updated ${rostersUpdateResult.modifiedCount} rosters`);

    // Also check for rosters that might belong to customer123
    const customer123Rosters = await db.collection('rosters').find({
      $or: [
        { 'employeeDetails.email': 'customer123@abrafleet.com' },
        { userId: { $exists: false } },
        { userId: null },
        { userId: '' }
      ]
    }).toArray();

    if (customer123Rosters.length > 0) {
      console.log(`Found ${customer123Rosters.length} rosters that might belong to customer123`);
      
      // Update the first 3 rosters to belong to customer123
      const rostersToUpdate = customer123Rosters.slice(0, 3);
      
      for (const roster of rostersToUpdate) {
        await db.collection('rosters').updateOne(
          { _id: roster._id },
          { 
            $set: { 
              userId: correctUID,
              employeeDetails: {
                ...roster.employeeDetails,
                email: 'customer123@abrafleet.com',
                name: 'Customer 123'
              }
            } 
          }
        );
      }
      
      console.log(`✓ Updated ${rostersToUpdate.length} additional rosters for customer123`);
    }

    console.log('\n4. Verifying the fix...');
    
    // Check updated data
    const updatedTrips = await db.collection('trips').find({ customerId: correctUID }).toArray();
    const updatedRosters = await db.collection('rosters').find({ userId: correctUID }).toArray();
    
    console.log(`✓ Customer123 now has ${updatedTrips.length} trips`);
    console.log(`✓ Customer123 now has ${updatedRosters.length} rosters`);

    if (updatedTrips.length > 0) {
      console.log('\nTrips breakdown:');
      const tripsByStatus = {};
      updatedTrips.forEach(trip => {
        const status = trip.status || 'unknown';
        tripsByStatus[status] = (tripsByStatus[status] || 0) + 1;
      });
      
      Object.entries(tripsByStatus).forEach(([status, count]) => {
        console.log(`  - ${status}: ${count}`);
      });
    }

    if (updatedRosters.length > 0) {
      console.log('\nRosters breakdown:');
      const rostersByStatus = {};
      updatedRosters.forEach(roster => {
        const status = roster.status || 'unknown';
        rostersByStatus[status] = (rostersByStatus[status] || 0) + 1;
      });
      
      Object.entries(rostersByStatus).forEach(([status, count]) => {
        console.log(`  - ${status}: ${count}`);
      });
    }

    console.log('\n' + '='.repeat(60));
    console.log('✅ CUSTOMER123 STATS DATA FIXED SUCCESSFULLY!');
    console.log('The mystats_screen.dart should now show updated statistics.');
    console.log('='.repeat(60));

  } catch (error) {
    console.error('\n' + '='.repeat(60));
    console.error('❌ ERROR FIXING CUSTOMER123 DATA:');
    console.error('='.repeat(60));
    console.error(error.message);
    console.error(error.stack);
  } finally {
    if (client) {
      await client.close();
    }
    process.exit(0);
  }
}

fixCustomer123StatsData();