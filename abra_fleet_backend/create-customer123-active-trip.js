// Create active trip for customer123@abrafleet.com for demo
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function createActiveTrip() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    const customerId = 'b5aoloVR7xYI6SICibCIWecBaf82'; // customer123@abrafleet.com
    
    console.log('🚀 Creating active trip for customer123@abrafleet.com...\n');
    
    // Create an active trip
    const activeTrip = {
      customerId: customerId,
      customerEmail: 'customer123@abrafleet.com',
      customerName: 'Customer 123',
      status: 'ongoing',
      tripType: 'pickup',
      vehicleNumber: 'KA01AB1234',
      vehicleType: 'Sedan',
      vehicleMake: 'Toyota',
      vehicleModel: 'Camry',
      driverName: 'Rajesh Kumar',
      driverEmail: 'rajesh@abrafleet.com',
      driverPhone: '+91 9876543210',
      pickupLocation: 'Electronic City, Bangalore',
      dropLocation: 'Koramangala, Bangalore',
      pickupTime: '09:00 AM',
      dropTime: '09:30 AM',
      startDate: new Date().toISOString().split('T')[0],
      tripStartTime: new Date().toISOString(),
      pickupCoordinates: {
        latitude: 12.8456,
        longitude: 77.6632
      },
      dropCoordinates: {
        latitude: 12.9352,
        longitude: 77.6245
      },
      readableId: `TRIP-${Date.now()}`,
      createdAt: new Date(),
      updatedAt: new Date(),
      organizationId: 'customer123_org',
      distance: 15.2,
      estimatedDuration: 30
    };
    
    const result = await db.collection('rosters').insertOne(activeTrip);
    
    console.log('✅ Active trip created successfully!');
    console.log(`   Trip ID: ${result.insertedId}`);
    console.log(`   Readable ID: ${activeTrip.readableId}`);
    console.log(`   Status: ${activeTrip.status}`);
    console.log(`   Vehicle: ${activeTrip.vehicleNumber} (${activeTrip.vehicleMake} ${activeTrip.vehicleModel})`);
    console.log(`   Driver: ${activeTrip.driverName} (${activeTrip.driverPhone})`);
    console.log(`   Route: ${activeTrip.pickupLocation} → ${activeTrip.dropLocation}`);
    
    console.log('\n🎯 Now the customer can track this trip!');
    console.log(`   Customer ID: ${customerId}`);
    console.log(`   API Endpoint: GET /api/rosters/active-trip/${customerId}`);
    
    // Also create a scheduled trip for tomorrow
    const scheduledTrip = {
      ...activeTrip,
      status: 'scheduled',
      startDate: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString().split('T')[0],
      tripStartTime: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      readableId: `TRIP-${Date.now() + 1}`,
      pickupTime: '10:00 AM',
      dropTime: '10:30 AM'
    };
    
    const scheduledResult = await db.collection('rosters').insertOne(scheduledTrip);
    
    console.log('\n✅ Scheduled trip also created!');
    console.log(`   Trip ID: ${scheduledResult.insertedId}`);
    console.log(`   Status: ${scheduledTrip.status}`);
    console.log(`   Date: ${scheduledTrip.startDate}`);
    
  } catch (error) {
    console.error('❌ Error creating trips:', error);
  } finally {
    await client.close();
  }
}

createActiveTrip();