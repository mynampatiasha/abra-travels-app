// Check existing trips for customer123
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function checkTrips() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    const customerId = 'b5aoloVR7xYI6SICibCIWecBaf82'; // customer123@abrafleet.com
    
    console.log('🔍 Checking trips for customer123@abrafleet.com...\n');
    
    // Find all trips for this customer
    const allTrips = await db.collection('rosters').find({
      customerId: customerId
    }).toArray();
    
    console.log(`📊 Total trips found: ${allTrips.length}\n`);
    
    if (allTrips.length > 0) {
      allTrips.forEach((trip, index) => {
        console.log(`${index + 1}. Trip ID: ${trip._id}`);
        console.log(`   Status: ${trip.status}`);
        console.log(`   Readable ID: ${trip.readableId || 'N/A'}`);
        console.log(`   Vehicle: ${trip.vehicleNumber || 'N/A'}`);
        console.log(`   Driver: ${trip.driverName || 'N/A'}`);
        console.log(`   Date: ${trip.startDate || 'N/A'}`);
        console.log(`   Created: ${trip.createdAt || 'N/A'}`);
        console.log('');
      });
      
      // Check specifically for active trips
      const activeTrips = allTrips.filter(trip => 
        ['scheduled', 'ongoing', 'in_progress', 'started', 'approved'].includes(trip.status)
      );
      
      console.log(`🎯 Active/Scheduled trips: ${activeTrips.length}`);
      if (activeTrips.length > 0) {
        console.log('✅ The Track My Vehicle feature should work!');
        activeTrips.forEach(trip => {
          console.log(`   - ${trip.status}: ${trip.readableId} (${trip.vehicleNumber})`);
        });
      } else {
        console.log('❌ No active trips found. Creating one...');
        
        // Create an active trip
        const newTrip = {
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
          readableId: `DEMO-TRIP-${Date.now()}`,
          createdAt: new Date(),
          updatedAt: new Date(),
          organizationId: 'customer123_org',
          distance: 15.2,
          estimatedDuration: 30
        };
        
        const result = await db.collection('rosters').insertOne(newTrip);
        console.log(`✅ Created new active trip: ${result.insertedId}`);
      }
    } else {
      console.log('❌ No trips found for this customer. Creating demo trip...');
      
      // Create a demo trip
      const demoTrip = {
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
        readableId: `DEMO-TRIP-${Date.now()}`,
        createdAt: new Date(),
        updatedAt: new Date(),
        organizationId: 'customer123_org',
        distance: 15.2,
        estimatedDuration: 30
      };
      
      const result = await db.collection('rosters').insertOne(demoTrip);
      console.log(`✅ Created demo trip: ${result.insertedId}`);
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkTrips();