require('dotenv').config();
const { MongoClient, ObjectId } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI;

async function createTripForPriya() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Get user
    const user = await db.collection('users').findOne({ 
      email: 'priya.sharma@infosys.com' 
    });
    
    // Get roster
    const roster = await db.collection('rosters').findOne({ 
      customerEmail: 'priya.sharma@infosys.com' 
    });
    
    console.log('📋 Found roster:', roster._id);
    
    // Get vehicle
    const vehicle = await db.collection('vehicles').findOne({ 
      vehicleNumber: 'KA01AB1240' 
    });
    
    console.log('🚗 Found vehicle:', vehicle ? vehicle.vehicleNumber : 'Not found');
    
    // Get a driver (any active driver)
    const driver = await db.collection('drivers').findOne({ 
      status: 'active' 
    });
    
    console.log('👤 Found driver:', driver ? driver.name : 'Not found');
    
    // Create trip
    const trip = {
      tripId: `TRIP_${Date.now()}`,
      rosterId: roster._id.toString(),
      customerUid: user.firebaseUid,
      customerName: user.name,
      customerEmail: user.email,
      customerPhone: user.phone || '+91 9876543210',
      vehicleId: vehicle ? vehicle._id.toString() : null,
      vehicleNumber: vehicle ? vehicle.vehicleNumber : 'KA01AB1240',
      driverId: driver ? driver._id.toString() : null,
      driverName: driver ? driver.name : 'Rajesh Kumar',
      driverPhone: driver ? driver.phone : '+91 9876543210',
      pickupLocation: roster.pickupLocation || 'Whitefield, Bangalore',
      pickupLatitude: roster.pickupLatitude || 12.9698,
      pickupLongitude: roster.pickupLongitude || 77.7499,
      dropLocation: roster.dropLocation || 'Koramangala Office, Bangalore',
      dropLatitude: roster.dropLatitude || 12.9352,
      dropLongitude: roster.dropLongitude || 77.6245,
      tripType: roster.rosterType || 'both',
      status: 'ongoing',
      startTime: new Date(),
      scheduledTime: new Date(),
      createdAt: new Date(),
      updatedAt: new Date()
    };
    
    const result = await db.collection('trips').insertOne(trip);
    console.log('\n✅ Created trip:', result.insertedId);
    
    // Update roster status
    await db.collection('rosters').updateOne(
      { _id: roster._id },
      { 
        $set: { 
          status: 'ongoing',
          driverName: trip.driverName,
          driverPhone: trip.driverPhone,
          updatedAt: new Date()
        } 
      }
    );
    console.log('✅ Updated roster status to ongoing');
    
    console.log('\n🎉 SUCCESS! Priya Sharma now has an ongoing trip!');
    console.log('\nTrip Details:');
    console.log('  Trip ID:', trip.tripId);
    console.log('  Vehicle:', trip.vehicleNumber);
    console.log('  Driver:', trip.driverName);
    console.log('  From:', trip.pickupLocation);
    console.log('  To:', trip.dropLocation);
    console.log('  Status:', trip.status);
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    process.exit(0);
  }
}

createTripForPriya();
