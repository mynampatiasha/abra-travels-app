const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function createCustomer123TripsData() {
  let client;
  
  try {
    console.log('='.repeat(60));
    console.log('CREATING 30 TRIPS DATA FOR CUSTOMER123');
    console.log('='.repeat(60));

    // Connect to MongoDB
    console.log('\n1. Connecting to MongoDB...');
    client = new MongoClient(MONGODB_URI);
    await client.connect();
    const db = client.db('abra_fleet');
    console.log('✓ Connected to MongoDB');

    // Customer123 Firebase UID
    const customerUID = 'b5aoloVR7xYI6SICibCIWecBaf82';
    
    // Clear existing trips for customer123 to avoid duplicates
    console.log('\n2. Clearing existing trips for customer123...');
    const deleteResult = await db.collection('trips').deleteMany({ customerId: customerUID });
    console.log(`✓ Deleted ${deleteResult.deletedCount} existing trips`);

    // Create base date (December 1, 2024)
    const baseDate = new Date('2024-12-01');
    const today = new Date('2024-12-24'); // Simulate today is Dec 24

    console.log('\n3. Creating 30 trips data...');

    const trips = [];
    
    // Demo drivers and vehicles
    const drivers = [
      { id: 'DRV-123456', name: 'Rajesh Kumar', phone: '+91-9876543210' },
      { id: 'DRV-234567', name: 'Suresh Patel', phone: '+91-9876543211' },
      { id: 'DRV-345678', name: 'Mahesh Singh', phone: '+91-9876543212' }
    ];
    
    const vehicles = [
      { id: 'VH-123456', number: 'KA-01-AB-1234' },
      { id: 'VH-234567', number: 'KA-01-CD-5678' },
      { id: 'VH-345678', number: 'KA-01-EF-9012' }
    ];

    // Create 30 trips
    for (let i = 1; i <= 30; i++) {
      const tripDate = new Date(baseDate);
      tripDate.setDate(baseDate.getDate() + (i - 1));
      
      const driver = drivers[(i - 1) % drivers.length];
      const vehicle = vehicles[(i - 1) % vehicles.length];
      
      let status;
      let completedAt = null;
      
      // Determine status based on date
      if (tripDate < today) {
        // Past dates - completed
        status = 'completed';
        completedAt = new Date(tripDate);
        completedAt.setHours(18, 30, 0, 0); // Completed at 6:30 PM
      } else if (tripDate.toDateString() === today.toDateString()) {
        // Today - ongoing
        status = 'ongoing';
      } else {
        // Future dates - scheduled
        status = 'scheduled';
      }

      const trip = {
        tripId: `TRP-${String(i).padStart(4, '0')}`,
        customerId: customerUID,
        customerInfo: {
          email: 'customer123@abrafleet.com',
          name: 'Customer 123',
          phone: '+91-9876543210'
        },
        rosterId: i <= 10 ? 'RST-1001' : 'RST-1002', // First 10 trips belong to first roster
        rosterType: 'both',
        status: status,
        scheduledDate: tripDate,
        scheduledTime: '09:00',
        pickupLocation: {
          address: 'Koramangala, Bangalore',
          coordinates: [77.6309, 12.9352],
          type: 'Point'
        },
        dropoffLocation: {
          address: 'Electronic City, Bangalore', 
          coordinates: [77.6648, 12.8456],
          type: 'Point'
        },
        driverId: driver.id,
        driverName: driver.name,
        driverPhone: driver.phone,
        vehicleId: vehicle.id,
        vehicleNumber: vehicle.number,
        distance: 15.5,
        estimatedDuration: 45,
        createdAt: new Date(tripDate.getTime() - (24 * 60 * 60 * 1000)), // Created 1 day before
        updatedAt: completedAt || new Date(),
        completedAt: completedAt,
        // Additional trip details
        pickupTime: status === 'completed' ? '09:15' : null,
        dropoffTime: status === 'completed' ? '10:00' : null,
        actualDistance: status === 'completed' ? 16.2 : null,
        fare: 250,
        paymentStatus: status === 'completed' ? 'paid' : 'pending'
      };

      trips.push(trip);
    }

    // Insert trips into database
    console.log('\n4. Inserting trips into database...');
    const insertResult = await db.collection('trips').insertMany(trips);
    console.log(`✓ Inserted ${insertResult.insertedCount} trips`);

    // Update rosters to reflect the trip assignments
    console.log('\n5. Updating rosters...');
    
    // Update first roster (days 1-10, all completed)
    await db.collection('rosters').updateOne(
      { rosterId: 'RST-1001', userId: customerUID },
      {
        $set: {
          status: 'completed',
          totalTrips: 10,
          completedTrips: 10,
          scheduledTrips: 0,
          dateRange: {
            from: '2024-12-01',
            to: '2024-12-10'
          },
          driverName: drivers[0].name,
          driverPhone: drivers[0].phone,
          vehicleNumber: vehicles[0].number,
          lastUpdated: new Date()
        }
      },
      { upsert: true }
    );

    // Update second roster (days 11-30, mixed status)
    await db.collection('rosters').updateOne(
      { rosterId: 'RST-1002', userId: customerUID },
      {
        $set: {
          status: 'ongoing',
          totalTrips: 20,
          completedTrips: 13, // Days 11-23 completed
          ongoingTrips: 1,    // Day 24 ongoing
          scheduledTrips: 6,  // Days 25-30 scheduled
          dateRange: {
            from: '2024-12-11',
            to: '2024-12-30'
          },
          driverName: drivers[1].name,
          driverPhone: drivers[1].phone,
          vehicleNumber: vehicles[1].number,
          lastUpdated: new Date()
        }
      },
      { upsert: true }
    );

    console.log('✓ Updated rosters');

    // Verify the data
    console.log('\n6. Verifying created data...');
    
    const totalTrips = await db.collection('trips').countDocuments({ customerId: customerUID });
    const completedTrips = await db.collection('trips').countDocuments({ 
      customerId: customerUID, 
      status: 'completed' 
    });
    const ongoingTrips = await db.collection('trips').countDocuments({ 
      customerId: customerUID, 
      status: 'ongoing' 
    });
    const scheduledTrips = await db.collection('trips').countDocuments({ 
      customerId: customerUID, 
      status: 'scheduled' 
    });

    console.log(`✓ Total trips: ${totalTrips}`);
    console.log(`✓ Completed trips: ${completedTrips}`);
    console.log(`✓ Ongoing trips: ${ongoingTrips}`);
    console.log(`✓ Scheduled trips: ${scheduledTrips}`);

    console.log('\n' + '='.repeat(60));
    console.log('✅ 30 TRIPS DATA CREATED SUCCESSFULLY!');
    console.log('='.repeat(60));
    console.log('\nBreakdown:');
    console.log('• Roster 1 (Days 1-10): 10 completed trips');
    console.log('• Roster 2 (Days 11-30): 13 completed + 1 ongoing + 6 scheduled trips');
    console.log('\nCustomer123 now has comprehensive trip data for demo!');

  } catch (error) {
    console.error('\n' + '='.repeat(60));
    console.error('❌ ERROR CREATING TRIPS DATA:');
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

createCustomer123TripsData();