// Create trip data in trips collection for tracking system
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

async function createTrackingTripData() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    const customerId = 'b5aoloVR7xYI6SICibCIWecBaf82'; // customer123@abrafleet.com
    const driverId = 'drivertest@abrafleet.com'; // Demo driver
    
    console.log('🚀 Creating tracking trip data for customer123@abrafleet.com...\n');
    
    // Get the roster data
    const roster = await db.collection('rosters').findOne({
      customerId: customerId,
      status: 'ongoing'
    });
    
    if (!roster) {
      console.log('❌ No ongoing roster found');
      return;
    }
    
    console.log('✅ Found roster:', roster.readableId);
    
    // Create corresponding trip in trips collection
    const tripData = {
      _id: new ObjectId(),
      tripNumber: roster.readableId,
      tripId: roster._id.toString(),
      rosterId: roster._id,
      customerId: customerId,
      customerName: roster.customerName || 'Customer 123',
      customerEmail: roster.customerEmail || 'customer123@abrafleet.com',
      driverId: driverId,
      driverName: roster.driverName || 'Rajesh Kumar',
      driverEmail: roster.driverEmail || 'rajesh@abrafleet.com',
      driverPhone: roster.driverPhone || '+91 9876543210',
      vehicleId: 'vehicle_001',
      vehicleNumber: roster.vehicleNumber || 'KA01AB1234',
      vehicleType: roster.vehicleType || 'Sedan',
      status: 'started', // For tracking system
      tripType: roster.tripType || 'pickup',
      pickupLocation: {
        address: roster.pickupLocation || 'Electronic City, Bangalore',
        coordinates: roster.pickupCoordinates || {
          latitude: 12.8456,
          longitude: 77.6632
        }
      },
      dropLocation: {
        address: roster.dropLocation || 'Koramangala, Bangalore', 
        coordinates: roster.dropCoordinates || {
          latitude: 12.9352,
          longitude: 77.6245
        }
      },
      scheduledPickupTime: roster.pickupTime || '09:00 AM',
      scheduledDropTime: roster.dropTime || '09:30 AM',
      startTime: new Date(),
      scheduledDate: roster.startDate || new Date().toISOString().split('T')[0],
      currentLocation: {
        type: 'Point',
        coordinates: [77.6632, 12.8456] // [longitude, latitude] - GeoJSON format
      },
      customers: [
        {
          customerId: customerId,
          customerName: roster.customerName || 'Customer 123',
          pickupAddress: roster.pickupLocation || 'Electronic City, Bangalore',
          dropAddress: roster.dropLocation || 'Koramangala, Bangalore',
          lat: roster.pickupCoordinates?.latitude || 12.8456,
          lng: roster.pickupCoordinates?.longitude || 77.6632,
          status: 'assigned'
        }
      ],
      createdAt: new Date(),
      updatedAt: new Date()
    };
    
    // Insert trip data
    const result = await db.collection('trips').insertOne(tripData);
    
    console.log('✅ Trip data created successfully!');
    console.log(`   Trip ID: ${result.insertedId}`);
    console.log(`   Trip Number: ${tripData.tripNumber}`);
    console.log(`   Status: ${tripData.status}`);
    console.log(`   Driver: ${tripData.driverName}`);
    console.log(`   Vehicle: ${tripData.vehicleNumber}`);
    console.log(`   Customer: ${tripData.customerName}`);
    
    // Also create/update driver data with location
    const driverData = {
      _id: driverId,
      name: tripData.driverName,
      email: tripData.driverEmail,
      phone: tripData.driverPhone,
      currentLocation: {
        type: 'Point',
        coordinates: [77.6632, 12.8456] // Driver's current location
      },
      locationData: {
        latitude: 12.8456,
        longitude: 77.6632,
        speed: 25.5, // km/h
        heading: 45, // degrees
        accuracy: 5, // meters
        isOnline: true,
        lastSeen: new Date()
      },
      lastLocationUpdate: new Date(),
      status: 'active',
      updatedAt: new Date()
    };
    
    await db.collection('users').updateOne(
      { _id: driverId },
      { $set: driverData },
      { upsert: true }
    );
    
    console.log('✅ Driver location data updated!');
    console.log(`   Driver ID: ${driverId}`);
    console.log(`   Location: ${driverData.locationData.latitude}, ${driverData.locationData.longitude}`);
    console.log(`   Speed: ${driverData.locationData.speed} km/h`);
    console.log(`   Status: Online`);
    
    console.log('\n🎯 Tracking system is now ready!');
    console.log(`   Trip Tracking URL: GET /api/tracking/trip/${tripData.tripNumber}/location`);
    console.log(`   Driver Tracking URL: GET /api/tracking/driver/${driverId}/location`);
    
  } catch (error) {
    console.error('❌ Error creating tracking data:', error);
  } finally {
    await client.close();
  }
}

createTrackingTripData();