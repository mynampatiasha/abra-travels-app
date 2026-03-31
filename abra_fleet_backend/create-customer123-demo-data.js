// create-customer123-demo-data.js
// Creates comprehensive demo data for customer123@abrafleet.com
// Includes duplicate rosters and 20 trips (18 completed, 1 ongoing, 1 pending)

const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = process.env.DB_NAME || 'abra_fleet';

// Demo customer details
const DEMO_CUSTOMER = {
  email: 'customer123@abrafleet.com',
  name: 'Demo Customer',
  phone: '+91-9876543210',
  firebaseUid: 'demo_customer_uid_123456789', // Simulated Firebase UID
  organizationName: 'Abra Travels Demo Org'
};

// Sample drivers with proper DRV- format
const DEMO_DRIVERS = [
  {
    driverId: 'DRV-123456',
    name: 'Rajesh Kumar',
    phone: '+91-9123456789',
    email: 'rajesh.kumar@abrafleet.com'
  },
  {
    driverId: 'DRV-234567', 
    name: 'Suresh Reddy',
    phone: '+91-9234567890',
    email: 'suresh.reddy@abrafleet.com'
  },
  {
    driverId: 'DRV-345678',
    name: 'Mahesh Singh',
    phone: '+91-9345678901', 
    email: 'mahesh.singh@abrafleet.com'
  }
];

// Sample vehicles with proper VH format
const DEMO_VEHICLES = [
  {
    vehicleId: 'VH123456',
    registrationNumber: 'KA01AB1234',
    make: 'Toyota',
    model: 'Innova',
    type: 'van',
    capacity: { passengers: 7 },
    status: 'active'
  },
  {
    vehicleId: 'VH234567',
    registrationNumber: 'KA02CD5678', 
    make: 'Mahindra',
    model: 'Bolero',
    type: 'suv',
    capacity: { passengers: 8 },
    status: 'active'
  },
  {
    vehicleId: 'VH345678',
    registrationNumber: 'KA03EF9012',
    make: 'Tata',
    model: 'Winger',
    type: 'mini_bus', 
    capacity: { passengers: 12 },
    status: 'active'
  }
];

// Office locations in Bangalore
const OFFICE_LOCATIONS = [
  {
    name: 'Koramangala Office',
    coordinates: { latitude: 12.9352, longitude: 77.6245 },
    address: 'Koramangala 5th Block, Bangalore, Karnataka 560095'
  },
  {
    name: 'Electronic City Office',
    coordinates: { latitude: 12.8456, longitude: 77.6603 },
    address: 'Electronic City Phase 1, Bangalore, Karnataka 560100'
  },
  {
    name: 'Whitefield Office', 
    coordinates: { latitude: 12.9698, longitude: 77.7500 },
    address: 'Whitefield Main Road, Bangalore, Karnataka 560066'
  }
];

// Pickup/Drop locations
const PICKUP_LOCATIONS = [
  {
    address: 'HSR Layout Sector 1, Bangalore',
    coordinates: { latitude: 12.9116, longitude: 77.6370 }
  },
  {
    address: 'BTM Layout 2nd Stage, Bangalore', 
    coordinates: { latitude: 12.9165, longitude: 77.6101 }
  },
  {
    address: 'Jayanagar 4th Block, Bangalore',
    coordinates: { latitude: 12.9279, longitude: 77.5937 }
  }
];

async function createDemoData() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    console.log('🔗 Connecting to MongoDB...');
    await client.connect();
    const db = client.db(DB_NAME);
    
    console.log('✅ Connected to MongoDB');
    console.log('🎯 Creating demo data for customer123@abrafleet.com');
    console.log('================================================================================');

    // 1. Create/Update Customer User
    console.log('\n👤 STEP 1: Creating Customer User...');
    const customerUser = {
      firebaseUid: DEMO_CUSTOMER.firebaseUid,
      email: DEMO_CUSTOMER.email,
      name: DEMO_CUSTOMER.name,
      phone: DEMO_CUSTOMER.phone,
      role: 'customer',
      companyName: DEMO_CUSTOMER.organizationName,
      organizationName: DEMO_CUSTOMER.organizationName,
      status: 'active',
      isApproved: true,
      createdAt: new Date(),
      updatedAt: new Date()
    };

    await db.collection('users').updateOne(
      { email: DEMO_CUSTOMER.email },
      { $set: customerUser },
      { upsert: true }
    );
    console.log('✅ Customer user created/updated');

    // 2. Create Demo Drivers
    console.log('\n🚗 STEP 2: Creating Demo Drivers...');
    for (const driver of DEMO_DRIVERS) {
      const driverDoc = {
        driverId: driver.driverId,
        name: driver.name,
        email: driver.email,
        phone: driver.phone,
        personalInfo: {
          firstName: driver.name.split(' ')[0],
          lastName: driver.name.split(' ').slice(1).join(' '),
          phone: driver.phone,
          email: driver.email
        },
        license: {
          licenseNumber: `DL${driver.driverId.replace('DRV-', '')}`,
          type: 'Commercial',
          issueDate: new Date('2020-01-01'),
          expiryDate: new Date('2025-12-31')
        },
        status: 'active',
        assignedVehicle: null,
        createdAt: new Date(),
        updatedAt: new Date()
      };

      await db.collection('drivers').updateOne(
        { driverId: driver.driverId },
        { $set: driverDoc },
        { upsert: true }
      );
      console.log(`✅ Driver ${driver.driverId} - ${driver.name} created`);
    }

    // 3. Create Demo Vehicles
    console.log('\n🚙 STEP 3: Creating Demo Vehicles...');
    for (const vehicle of DEMO_VEHICLES) {
      const vehicleDoc = {
        vehicleId: vehicle.vehicleId,
        registrationNumber: vehicle.registrationNumber,
        make: vehicle.make,
        model: vehicle.model,
        type: vehicle.type,
        capacity: vehicle.capacity,
        status: vehicle.status,
        assignedDriver: null,
        createdAt: new Date(),
        updatedAt: new Date()
      };

      await db.collection('vehicles').updateOne(
        { vehicleId: vehicle.vehicleId },
        { $set: vehicleDoc },
        { upsert: true }
      );
      console.log(`✅ Vehicle ${vehicle.vehicleId} - ${vehicle.registrationNumber} created`);
    }

    // 4. Create Duplicate Rosters
    console.log('\n📋 STEP 4: Creating Duplicate Rosters...');
    
    // Generate roster IDs
    let rosterCounter = 1001;
    const generateRosterId = () => `RST-${String(rosterCounter++).padStart(4, '0')}`;

    // Create 5 duplicate rosters (same details but different IDs)
    const baseRosterData = {
      userId: DEMO_CUSTOMER.firebaseUid,
      customerName: DEMO_CUSTOMER.name,
      customerEmail: DEMO_CUSTOMER.email,
      rosterType: 'both',
      officeLocation: OFFICE_LOCATIONS[0].name,
      officeLocationCoordinates: OFFICE_LOCATIONS[0].coordinates,
      weeklyOffDays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
      startDate: new Date('2024-01-01'),
      endDate: new Date('2024-12-31'),
      startTime: '09:00',
      endTime: '18:00',
      locations: {
        pickup: {
          coordinates: PICKUP_LOCATIONS[0].coordinates,
          address: PICKUP_LOCATIONS[0].address,
          timestamp: new Date()
        },
        drop: {
          coordinates: OFFICE_LOCATIONS[0].coordinates,
          address: OFFICE_LOCATIONS[0].address,
          timestamp: new Date()
        }
      },
      requestType: 'customer_roster',
      organizationName: DEMO_CUSTOMER.organizationName,
      createdAt: new Date(),
      updatedAt: new Date(),
      createdBy: DEMO_CUSTOMER.firebaseUid
    };

    const duplicateRosters = [];
    
    // Create 3 duplicate rosters with different statuses
    for (let i = 0; i < 3; i++) {
      const roster = {
        ...baseRosterData,
        readableId: generateRosterId(),
        status: i === 0 ? 'pending_assignment' : 'assigned',
        notes: `Duplicate roster #${i + 1} - Same pickup/drop locations and times`
      };

      // Assign driver and vehicle to assigned rosters
      if (roster.status === 'assigned') {
        const driver = DEMO_DRIVERS[i % DEMO_DRIVERS.length];
        const vehicle = DEMO_VEHICLES[i % DEMO_VEHICLES.length];
        
        roster.assignedDriver = {
          driverId: new ObjectId(), // MongoDB ObjectId for driver
          assignedAt: new Date()
        };
        roster.assignedVehicle = {
          vehicleId: new ObjectId(), // MongoDB ObjectId for vehicle  
          assignedAt: new Date()
        };
        roster.assignmentDate = new Date();
        roster.assignedBy = 'admin_demo_user';
      }

      const result = await db.collection('rosters').insertOne(roster);
      roster._id = result.insertedId;
      duplicateRosters.push(roster);
      
      console.log(`✅ Duplicate Roster ${roster.readableId} created - Status: ${roster.status}`);
    }

    // 5. Create 20 Trips (18 completed, 1 ongoing, 1 pending)
    console.log('\n🚌 STEP 5: Creating 20 Demo Trips...');
    
    let tripCounter = 2001;
    const generateTripId = () => `TRP-${String(tripCounter++).padStart(4, '0')}`;

    const trips = [];
    const now = new Date();
    
    // 18 Completed trips (past dates)
    for (let i = 0; i < 18; i++) {
      const driver = DEMO_DRIVERS[i % DEMO_DRIVERS.length];
      const vehicle = DEMO_VEHICLES[i % DEMO_VEHICLES.length];
      const office = OFFICE_LOCATIONS[i % OFFICE_LOCATIONS.length];
      const pickup = PICKUP_LOCATIONS[i % PICKUP_LOCATIONS.length];
      
      const tripDate = new Date(now);
      tripDate.setDate(tripDate.getDate() - (i + 1)); // Past dates
      
      const trip = {
        readableId: generateTripId(),
        customerId: DEMO_CUSTOMER.firebaseUid,
        customerName: DEMO_CUSTOMER.name,
        customerEmail: DEMO_CUSTOMER.email,
        customerPhone: DEMO_CUSTOMER.phone,
        
        // Driver details
        driverId: driver.driverId,
        driverName: driver.name,
        driverPhone: driver.phone,
        driverEmail: driver.email,
        
        // Vehicle details
        vehicleId: vehicle.vehicleId,
        vehicleNumber: vehicle.registrationNumber,
        vehicleType: vehicle.type,
        vehicleMake: vehicle.make,
        vehicleModel: vehicle.model,
        seatCapacity: vehicle.capacity.passengers,
        
        // Trip details
        tripType: i % 2 === 0 ? 'login' : 'logout',
        status: 'completed',
        
        // Locations
        pickupLocation: pickup.address,
        pickupCoordinates: pickup.coordinates,
        dropLocation: office.address,
        dropCoordinates: office.coordinates,
        
        // Times
        scheduledDate: tripDate,
        pickupTime: '09:00',
        dropTime: '09:30',
        tripStartTime: new Date(tripDate.getTime() + 9 * 60 * 60 * 1000), // 9 AM
        tripEndTime: new Date(tripDate.getTime() + 9.5 * 60 * 60 * 1000), // 9:30 AM
        
        // Status tracking
        startedAt: new Date(tripDate.getTime() + 9 * 60 * 60 * 1000),
        completedAt: new Date(tripDate.getTime() + 9.5 * 60 * 60 * 1000),
        
        // Metadata
        distance: Math.floor(Math.random() * 20) + 5, // 5-25 km
        duration: Math.floor(Math.random() * 30) + 15, // 15-45 minutes
        fare: Math.floor(Math.random() * 200) + 100, // ₹100-300
        
        organizationName: DEMO_CUSTOMER.organizationName,
        createdAt: tripDate,
        updatedAt: new Date(),
        createdBy: DEMO_CUSTOMER.firebaseUid
      };
      
      const result = await db.collection('rosters').insertOne(trip);
      trip._id = result.insertedId;
      trips.push(trip);
      
      console.log(`✅ Completed Trip ${trip.readableId} - ${trip.tripType} - ${tripDate.toDateString()}`);
    }
    
    // 1 Ongoing trip (current time)
    const ongoingDriver = DEMO_DRIVERS[0];
    const ongoingVehicle = DEMO_VEHICLES[0];
    const ongoingTrip = {
      readableId: generateTripId(),
      customerId: DEMO_CUSTOMER.firebaseUid,
      customerName: DEMO_CUSTOMER.name,
      customerEmail: DEMO_CUSTOMER.email,
      customerPhone: DEMO_CUSTOMER.phone,
      
      driverId: ongoingDriver.driverId,
      driverName: ongoingDriver.name,
      driverPhone: ongoingDriver.phone,
      driverEmail: ongoingDriver.email,
      
      vehicleId: ongoingVehicle.vehicleId,
      vehicleNumber: ongoingVehicle.registrationNumber,
      vehicleType: ongoingVehicle.type,
      vehicleMake: ongoingVehicle.make,
      vehicleModel: ongoingVehicle.model,
      seatCapacity: ongoingVehicle.capacity.passengers,
      
      tripType: 'login',
      status: 'ongoing',
      
      pickupLocation: PICKUP_LOCATIONS[0].address,
      pickupCoordinates: PICKUP_LOCATIONS[0].coordinates,
      dropLocation: OFFICE_LOCATIONS[0].address,
      dropCoordinates: OFFICE_LOCATIONS[0].coordinates,
      
      scheduledDate: now,
      pickupTime: '09:00',
      dropTime: '09:30',
      tripStartTime: new Date(now.getTime() - 10 * 60 * 1000), // Started 10 minutes ago
      
      startedAt: new Date(now.getTime() - 10 * 60 * 1000),
      
      distance: 12,
      estimatedDuration: 25,
      fare: 150,
      
      organizationName: DEMO_CUSTOMER.organizationName,
      createdAt: new Date(now.getTime() - 15 * 60 * 1000),
      updatedAt: now,
      createdBy: DEMO_CUSTOMER.firebaseUid
    };
    
    const ongoingResult = await db.collection('rosters').insertOne(ongoingTrip);
    ongoingTrip._id = ongoingResult.insertedId;
    trips.push(ongoingTrip);
    console.log(`✅ Ongoing Trip ${ongoingTrip.readableId} - Status: ${ongoingTrip.status}`);
    
    // 1 Pending assignment trip (future date)
    const futureDate = new Date(now);
    futureDate.setDate(futureDate.getDate() + 1); // Tomorrow
    
    const pendingTrip = {
      readableId: generateTripId(),
      customerId: DEMO_CUSTOMER.firebaseUid,
      customerName: DEMO_CUSTOMER.name,
      customerEmail: DEMO_CUSTOMER.email,
      customerPhone: DEMO_CUSTOMER.phone,
      
      // No driver/vehicle assigned yet
      driverId: null,
      driverName: null,
      vehicleId: null,
      vehicleNumber: null,
      
      tripType: 'logout',
      status: 'pending_assignment',
      
      pickupLocation: OFFICE_LOCATIONS[1].address,
      pickupCoordinates: OFFICE_LOCATIONS[1].coordinates,
      dropLocation: PICKUP_LOCATIONS[1].address,
      dropCoordinates: PICKUP_LOCATIONS[1].coordinates,
      
      scheduledDate: futureDate,
      pickupTime: '18:00',
      dropTime: '18:30',
      
      organizationName: DEMO_CUSTOMER.organizationName,
      createdAt: now,
      updatedAt: now,
      createdBy: DEMO_CUSTOMER.firebaseUid
    };
    
    const pendingResult = await db.collection('rosters').insertOne(pendingTrip);
    pendingTrip._id = pendingResult.insertedId;
    trips.push(pendingTrip);
    console.log(`✅ Pending Trip ${pendingTrip.readableId} - Status: ${pendingTrip.status}`);

    // 6. Summary Report
    console.log('\n================================================================================');
    console.log('📊 DEMO DATA CREATION COMPLETE');
    console.log('================================================================================');
    console.log(`👤 Customer: ${DEMO_CUSTOMER.name} (${DEMO_CUSTOMER.email})`);
    console.log(`🔑 Firebase UID: ${DEMO_CUSTOMER.firebaseUid}`);
    console.log(`🏢 Organization: ${DEMO_CUSTOMER.organizationName}`);
    console.log('');
    console.log(`🚗 Drivers Created: ${DEMO_DRIVERS.length}`);
    DEMO_DRIVERS.forEach(d => console.log(`   - ${d.driverId}: ${d.name}`));
    console.log('');
    console.log(`🚙 Vehicles Created: ${DEMO_VEHICLES.length}`);
    DEMO_VEHICLES.forEach(v => console.log(`   - ${v.vehicleId}: ${v.registrationNumber} (${v.make} ${v.model})`));
    console.log('');
    console.log(`📋 Duplicate Rosters: ${duplicateRosters.length}`);
    duplicateRosters.forEach(r => console.log(`   - ${r.readableId}: ${r.status}`));
    console.log('');
    console.log(`🚌 Total Trips: ${trips.length}`);
    console.log(`   - Completed: ${trips.filter(t => t.status === 'completed').length}`);
    console.log(`   - Ongoing: ${trips.filter(t => t.status === 'ongoing').length}`);
    console.log(`   - Pending Assignment: ${trips.filter(t => t.status === 'pending_assignment').length}`);
    console.log('');
    console.log('🎯 READY FOR MANAGER DEMO!');
    console.log('================================================================================');

  } catch (error) {
    console.error('❌ Error creating demo data:', error);
    console.error(error.stack);
  } finally {
    await client.close();
    console.log('✅ Disconnected from MongoDB');
  }
}

// Run the script
if (require.main === module) {
  createDemoData().catch(console.error);
}

module.exports = { createDemoData };