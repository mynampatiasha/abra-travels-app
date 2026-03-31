const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function fixCustomer123CorrectDates() {
  let client;
  
  try {
    console.log('='.repeat(60));
    console.log('FIXING CUSTOMER123 DATA - CORRECT DATE LOGIC');
    console.log('='.repeat(60));

    // Connect to MongoDB
    console.log('\n1. Connecting to MongoDB...');
    client = new MongoClient(MONGODB_URI);
    await client.connect();
    const db = client.db('abra_fleet');
    console.log('✓ Connected to MongoDB');

    const customerUID = 'b5aoloVR7xYI6SICibCIWecBaf82';
    
    // Today is December 23, 2024
    const today = new Date(2024, 11, 23); // December 23, 2024
    console.log(`Today's date: ${today.toLocaleDateString()}`);
    
    // Clear existing data
    console.log('\n2. Clearing existing data...');
    await db.collection('trips').deleteMany({ customerId: customerUID });
    await db.collection('rosters').deleteMany({ userId: customerUID });
    console.log('✓ Cleared existing trips and rosters');

    // Create the 3 rosters as specified with CORRECT date logic
    console.log('\n3. Creating rosters with correct date logic...');
    
    const rostersToCreate = [
      {
        rosterId: 'RST-2001',
        userId: customerUID,
        customerName: 'Customer 123',
        customerEmail: 'customer123@abrafleet.com',
        rosterType: 'pickup_drop',
        status: 'completed',
        
        // Roster 1: Nov 23, 2024 to Dec 19, 2024 (all completed - past dates)
        fromDate: new Date(2024, 10, 23), // Nov 23, 2024
        toDate: new Date(2024, 11, 19),   // Dec 19, 2024
        
        pickupLocation: 'Pickup Location - Bangalore',
        pickupLatitude: 12.9716,
        pickupLongitude: 77.5946,
        
        officeLocation: 'Office Location - Bangalore',
        officeLatitude: 12.9141,
        officeLongitude: 77.6412,
        
        fromTime: '09:00',
        toTime: '18:00',
        
        driverName: 'Rajesh Kumar',
        driverPhone: '+91 9876543210',
        vehicleNumber: 'KA-01-AB-1234',
        
        weekdays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
        createdAt: new Date(2024, 10, 23),
        updatedAt: new Date(),
        
        employeeData: [{
          name: 'Customer 123',
          email: 'customer123@abrafleet.com',
          phone: '+91 9876543210',
          employeeId: 'EMP-123'
        }]
      },
      {
        rosterId: 'RST-2002',
        userId: customerUID,
        customerName: 'Customer 123',
        customerEmail: 'customer123@abrafleet.com',
        rosterType: 'pickup_drop',
        status: 'ongoing',
        
        // Roster 2: Dec 13, 2024 to Jan 23, 2025 (up to Dec 22, 2024 completed, rest scheduled)
        fromDate: new Date(2024, 11, 13), // Dec 13, 2024
        toDate: new Date(2025, 0, 23),    // Jan 23, 2025
        
        pickupLocation: 'Pickup Location - Bangalore',
        pickupLatitude: 12.9716,
        pickupLongitude: 77.5946,
        
        officeLocation: 'Office Location - Bangalore',
        officeLatitude: 12.9141,
        officeLongitude: 77.6412,
        
        fromTime: '09:00',
        toTime: '18:00',
        
        driverName: 'Suresh Patel',
        driverPhone: '+91 9876543211',
        vehicleNumber: 'KA-02-CD-5678',
        
        weekdays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
        createdAt: new Date(2024, 11, 13),
        updatedAt: new Date(),
        
        employeeData: [{
          name: 'Customer 123',
          email: 'customer123@abrafleet.com',
          phone: '+91 9876543210',
          employeeId: 'EMP-123'
        }]
      },
      {
        rosterId: 'RST-2003',
        userId: customerUID,
        customerName: 'Customer 123',
        customerEmail: 'customer123@abrafleet.com',
        rosterType: 'pickup_drop',
        status: 'assigned',
        
        // Roster 3: Dec 12, 2024 to Jan 13, 2025 (no trips - empty roster)
        fromDate: new Date(2024, 11, 12), // Dec 12, 2024
        toDate: new Date(2025, 0, 13),    // Jan 13, 2025
        
        pickupLocation: 'Pickup Location - Bangalore',
        pickupLatitude: 12.9716,
        pickupLongitude: 77.5946,
        
        officeLocation: 'Office Location - Bangalore',
        officeLatitude: 12.9141,
        officeLongitude: 77.6412,
        
        fromTime: '09:00',
        toTime: '18:00',
        
        driverName: 'Mahesh Singh',
        driverPhone: '+91 9876543212',
        vehicleNumber: 'KA-03-EF-9012',
        
        weekdays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
        createdAt: new Date(2024, 11, 12),
        updatedAt: new Date(),
        
        totalTrips: 0,
        completedTrips: 0,
        ongoingTrips: 0,
        scheduledTrips: 0,
        cancelledTrips: 0,
        
        employeeData: [{
          name: 'Customer 123',
          email: 'customer123@abrafleet.com',
          phone: '+91 9876543210',
          employeeId: 'EMP-123'
        }]
      }
    ];

    // Insert rosters
    await db.collection('rosters').insertMany(rostersToCreate);
    console.log('✓ Created 3 rosters');

    // Create trips for Roster 1 (Nov 23, 2024 to Dec 19, 2024 - all completed)
    console.log('\n4. Creating trips for Roster 1 (all completed - past dates)...');
    const roster1Trips = [];
    const roster1Start = new Date(2024, 10, 23); // Nov 23, 2024
    const roster1End = new Date(2024, 11, 19);   // Dec 19, 2024
    
    let tripCounter = 1;
    for (let d = new Date(roster1Start); d <= roster1End; d.setDate(d.getDate() + 1)) {
      // Skip weekends
      if (d.getDay() === 0 || d.getDay() === 6) continue;
      
      const distance = 15 + (Math.random() * 10); // 15-25 km
      
      roster1Trips.push({
        tripId: `TRP-${Date.now()}-${tripCounter}`,
        customerId: customerUID,
        rosterId: 'RST-2001',
        status: 'completed', // All completed (past dates)
        scheduledDate: new Date(d),
        createdAt: new Date(d),
        distance: Math.round(distance * 10) / 10,
        actualDistance: Math.round((distance + (Math.random() - 0.5) * 2) * 10) / 10,
        driverName: 'Rajesh Kumar',
        driverPhone: '+91 9876543210',
        vehicleNumber: 'KA-01-AB-1234',
        pickupTime: '09:00',
        dropoffTime: '18:00',
        pickupLocation: {
          address: 'Pickup Location',
          coordinates: [77.5946, 12.9716]
        },
        dropoffLocation: {
          address: 'Office Location',
          coordinates: [77.6412, 12.9141]
        }
      });
      tripCounter++;
    }
    
    if (roster1Trips.length > 0) {
      await db.collection('trips').insertMany(roster1Trips);
      console.log(`✓ Created ${roster1Trips.length} completed trips for Roster 1`);
    }

    // Create trips for Roster 2 (Dec 13, 2024 to Jan 23, 2025 - up to Dec 22, 2024 completed, rest scheduled)
    console.log('\n5. Creating trips for Roster 2 (mixed status based on today)...');
    const roster2Trips = [];
    const roster2Start = new Date(2024, 11, 13); // Dec 13, 2024
    const roster2End = new Date(2025, 0, 23);    // Jan 23, 2025
    const completedUntil = new Date(2024, 11, 22); // Dec 22, 2024
    
    for (let d = new Date(roster2Start); d <= roster2End; d.setDate(d.getDate() + 1)) {
      // Skip weekends
      if (d.getDay() === 0 || d.getDay() === 6) continue;
      
      const distance = 15 + (Math.random() * 10); // 15-25 km
      let status;
      
      // Status logic based on date relative to today (Dec 23, 2024)
      if (d < today) {
        status = 'completed'; // Past dates
      } else if (d.toDateString() === today.toDateString()) {
        status = 'ongoing'; // Today
      } else {
        status = 'scheduled'; // Future dates
      }
      
      roster2Trips.push({
        tripId: `TRP-${Date.now()}-${tripCounter}`,
        customerId: customerUID,
        rosterId: 'RST-2002',
        status: status,
        scheduledDate: new Date(d),
        createdAt: new Date(d),
        distance: Math.round(distance * 10) / 10,
        actualDistance: status === 'completed' ? Math.round((distance + (Math.random() - 0.5) * 2) * 10) / 10 : null,
        driverName: 'Suresh Patel',
        driverPhone: '+91 9876543211',
        vehicleNumber: 'KA-02-CD-5678',
        pickupTime: '09:00',
        dropoffTime: '18:00',
        pickupLocation: {
          address: 'Pickup Location',
          coordinates: [77.5946, 12.9716]
        },
        dropoffLocation: {
          address: 'Office Location',
          coordinates: [77.6412, 12.9141]
        }
      });
      tripCounter++;
    }
    
    if (roster2Trips.length > 0) {
      await db.collection('trips').insertMany(roster2Trips);
      const completedCount = roster2Trips.filter(t => t.status === 'completed').length;
      const ongoingCount = roster2Trips.filter(t => t.status === 'ongoing').length;
      const scheduledCount = roster2Trips.filter(t => t.status === 'scheduled').length;
      console.log(`✓ Created ${roster2Trips.length} trips for Roster 2 (${completedCount} completed, ${ongoingCount} ongoing, ${scheduledCount} scheduled)`);
    }

    // Roster 3 has no trips (as specified)
    console.log('\n6. Roster 3 has no trips (as per requirements)');

    // Update roster statistics
    console.log('\n7. Updating roster statistics...');
    
    // Update Roster 1
    await db.collection('rosters').updateOne(
      { rosterId: 'RST-2001' },
      { 
        $set: { 
          totalTrips: roster1Trips.length,
          completedTrips: roster1Trips.length,
          ongoingTrips: 0,
          scheduledTrips: 0,
          cancelledTrips: 0,
          totalDistance: roster1Trips.reduce((sum, trip) => sum + (trip.actualDistance || trip.distance), 0)
        } 
      }
    );
    
    // Update Roster 2
    const roster2Completed = roster2Trips.filter(t => t.status === 'completed').length;
    const roster2Ongoing = roster2Trips.filter(t => t.status === 'ongoing').length;
    const roster2Scheduled = roster2Trips.filter(t => t.status === 'scheduled').length;
    
    await db.collection('rosters').updateOne(
      { rosterId: 'RST-2002' },
      { 
        $set: { 
          totalTrips: roster2Trips.length,
          completedTrips: roster2Completed,
          ongoingTrips: roster2Ongoing,
          scheduledTrips: roster2Scheduled,
          cancelledTrips: 0,
          totalDistance: roster2Trips.reduce((sum, trip) => sum + (trip.actualDistance || trip.distance || 0), 0)
        } 
      }
    );

    // Verify final data with correct logic
    console.log('\n8. Verifying final data with correct date logic...');
    
    const finalTrips = await db.collection('trips').find({ customerId: customerUID }).toArray();
    const finalRosters = await db.collection('rosters').find({ userId: customerUID }).toArray();
    
    const tripStatusCounts = {
      completed: finalTrips.filter(t => t.status === 'completed').length,
      ongoing: finalTrips.filter(t => t.status === 'ongoing').length,
      scheduled: finalTrips.filter(t => t.status === 'scheduled').length,
      cancelled: finalTrips.filter(t => t.status === 'cancelled').length
    };

    // Verify date logic
    let logicalErrors = 0;
    finalTrips.forEach(trip => {
      const tripDate = new Date(trip.scheduledDate);
      const expectedStatus = tripDate < today ? 'completed' : 
                           tripDate.toDateString() === today.toDateString() ? 'ongoing' : 'scheduled';
      
      if (trip.status !== expectedStatus) {
        console.log(`  ⚠️  Trip ${trip.tripId} on ${tripDate.toLocaleDateString()} has status '${trip.status}' but should be '${expectedStatus}'`);
        logicalErrors++;
      }
    });

    console.log('\n' + '='.repeat(60));
    console.log('✅ CORRECT DATE LOGIC IMPLEMENTED!');
    console.log('='.repeat(60));
    console.log(`Today's date: ${today.toLocaleDateString()}`);
    console.log(`Total trips: ${finalTrips.length}`);
    console.log(`Trip status breakdown:`);
    console.log(`  - Completed: ${tripStatusCounts.completed}`);
    console.log(`  - Ongoing: ${tripStatusCounts.ongoing}`);
    console.log(`  - Scheduled: ${tripStatusCounts.scheduled}`);
    console.log(`  - Cancelled: ${tripStatusCounts.cancelled}`);
    
    if (logicalErrors === 0) {
      console.log('✅ All trip statuses are logically correct!');
    } else {
      console.log(`❌ Found ${logicalErrors} logical errors in trip statuses`);
    }
    
    console.log(`\nRoster details:`);
    finalRosters.forEach((roster, index) => {
      console.log(`  ${index + 1}. ${roster.rosterId}: ${roster.status}`);
      console.log(`     - Date range: ${new Date(roster.fromDate).toLocaleDateString()} to ${new Date(roster.toDate).toLocaleDateString()}`);
      console.log(`     - Vehicle: ${roster.vehicleNumber}, Driver: ${roster.driverName}`);
      console.log(`     - Trips: ${roster.totalTrips || 0} (${roster.completedTrips || 0} completed, ${roster.ongoingTrips || 0} ongoing, ${roster.scheduledTrips || 0} scheduled)`);
    });

  } catch (error) {
    console.error('\n' + '='.repeat(60));
    console.error('❌ ERROR IMPLEMENTING CORRECT DATES:');
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

fixCustomer123CorrectDates();