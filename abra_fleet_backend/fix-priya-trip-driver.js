require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI;

async function fixPriyaTripDriver() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Update the trip with proper driver info
    const result = await db.collection('trips').updateOne(
      { customerEmail: 'priya.sharma@infosys.com' },
      { 
        $set: { 
          driverName: 'Rajesh Kumar',
          driverPhone: '+91 9876543210',
          updatedAt: new Date()
        } 
      }
    );
    
    console.log('✅ Updated trip:', result.modifiedCount, 'document(s)');
    
    // Verify
    const trip = await db.collection('trips').findOne({ 
      customerEmail: 'priya.sharma@infosys.com' 
    });
    
    console.log('\n📋 Trip Details:');
    console.log('  Trip ID:', trip.tripId);
    console.log('  Customer:', trip.customerName);
    console.log('  Vehicle:', trip.vehicleNumber);
    console.log('  Driver:', trip.driverName);
    console.log('  Driver Phone:', trip.driverPhone);
    console.log('  Status:', trip.status);
    console.log('  From:', trip.pickupLocation);
    console.log('  To:', trip.dropLocation);
    
    console.log('\n🎉 Trip is ready! Priya can now see it in "My Trips"');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    process.exit(0);
  }
}

fixPriyaTripDriver();
