const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const client = new MongoClient(process.env.MONGODB_URI);

async function simpleSetup() {
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Skip creating collections explicitly - they'll be created when we insert data
    console.log('\n📝 Inserting sample data (collections will be created automatically)...');
    
    // 1. INSERT SAMPLE VEHICLES
    console.log('Creating vehicles...');
    const sampleVehicles = [
      {
        vehicleId: "VH001",
        registrationNumber: "KA-01-AB-1234",
        make: "Toyota",
        model: "Hiace",
        year: 2022,
        type: "van",
        status: "active",
        currentLocation: {
          type: "Point",
          coordinates: [77.5946, 12.9716] // Bangalore
        },
        fuelLevel: 80,
        createdAt: new Date(),
        updatedAt: new Date()
      },
      {
        vehicleId: "VH002",
        registrationNumber: "KA-02-CD-5678",
        make: "Mahindra",
        model: "Bolero",
        year: 2021,
        type: "suv",
        status: "active",
        currentLocation: {
          type: "Point",
          coordinates: [77.6410, 12.9082] // HSR Layout
        },
        fuelLevel: 65,
        createdAt: new Date(),
        updatedAt: new Date()
      },
      {
        vehicleId: "VH003",
        registrationNumber: "KA-03-EF-9012",
        make: "Tata",
        model: "Ace",
        year: 2023,
        type: "truck",
        status: "maintenance",
        currentLocation: {
          type: "Point",
          coordinates: [77.5762, 12.9719] // Koramangala
        },
        fuelLevel: 45,
        createdAt: new Date(),
        updatedAt: new Date()
      }
    ];
    
    try {
      const vehicleResults = await db.collection('vehicles').insertMany(sampleVehicles);
      console.log(`✅ Inserted ${vehicleResults.insertedCount} vehicles`);
    } catch (error) {
      if (error.code === 11000) {
        console.log('ℹ️  Some vehicles already exist, skipping duplicates');
      } else {
        console.error('Error inserting vehicles:', error.message);
      }
    }
    
    // 2. INSERT SAMPLE DRIVERS
    console.log('Creating drivers...');
    const sampleDrivers = [
      {
        driverId: "DR001",
        personalInfo: {
          firstName: "Rajesh",
          lastName: "Kumar",
          phone: "+91-9876543210",
          email: "rajesh.kumar@abrafleet.com"
        },
        currentStatus: "available",
        currentLocation: {
          type: "Point",
          coordinates: [77.5946, 12.9716]
        },
        ratings: {
          overall: 4.5
        },
        createdAt: new Date(),
        updatedAt: new Date()
      },
      {
        driverId: "DR002",
        personalInfo: {
          firstName: "Priya",
          lastName: "Sharma",
          phone: "+91-9876543211",
          email: "priya.sharma@abrafleet.com"
        },
        currentStatus: "on-trip",
        currentLocation: {
          type: "Point",
          coordinates: [77.6410, 12.9082]
        },
        ratings: {
          overall: 4.7
        },
        createdAt: new Date(),
        updatedAt: new Date()
      },
      {
        driverId: "DR003",
        personalInfo: {
          firstName: "Amit",
          lastName: "Patel",
          phone: "+91-9876543212",
          email: "amit.patel@abrafleet.com"
        },
        currentStatus: "off-duty",
        currentLocation: {
          type: "Point",
          coordinates: [77.5762, 12.9719]
        },
        ratings: {
          overall: 4.3
        },
        createdAt: new Date(),
        updatedAt: new Date()
      }
    ];
    
    try {
      const driverResults = await db.collection('drivers').insertMany(sampleDrivers);
      console.log(`✅ Inserted ${driverResults.insertedCount} drivers`);
    } catch (error) {
      if (error.code === 11000) {
        console.log('ℹ️  Some drivers already exist, skipping duplicates');
      } else {
        console.error('Error inserting drivers:', error.message);
      }
    }
    
    // 3. INSERT LOCATION TRACKING DATA
    console.log('Creating location tracking records...');
    const sampleLocations = [
      {
        vehicleId: "VH001",
        driverId: "DR001",
        location: {
          type: "Point",
          coordinates: [77.5946, 12.9716]
        },
        speed: 0,
        heading: 0,
        timestamp: new Date(),
        isActive: true,
        fuelLevel: 80,
        engineStatus: "off",
        createdAt: new Date()
      },
      {
        vehicleId: "VH002",
        driverId: "DR002",
        location: {
          type: "Point",
          coordinates: [77.6410, 12.9082]
        },
        speed: 45,
        heading: 180,
        timestamp: new Date(),
        isActive: true,
        fuelLevel: 65,
        engineStatus: "on",
        createdAt: new Date()
      }
    ];
    
    try {
      const locationResults = await db.collection('locationTracking').insertMany(sampleLocations);
      console.log(`✅ Inserted ${locationResults.insertedCount} location records`);
    } catch (error) {
      console.error('Error inserting location data:', error.message);
    }
    
    // 4. INSERT SAMPLE TRIP
    console.log('Creating trip records...');
    const sampleTrips = [
      {
        tripId: "TR001",
        vehicleId: "VH002",
        driverId: "DR002",
        status: "in-progress",
        tripType: "delivery",
        startLocation: {
          address: "HSR Layout, Bangalore",
          coordinates: {
            type: "Point",
            coordinates: [77.6410, 12.9082]
          },
          timestamp: new Date()
        },
        endLocation: {
          address: "Electronic City, Bangalore",
          coordinates: {
            type: "Point",
            coordinates: [77.6648, 12.8456]
          },
          timestamp: null
        },
        plannedRoute: {
          distance: 15.5,
          estimatedDuration: 35
        },
        createdAt: new Date(),
        updatedAt: new Date()
      },
      {
        tripId: "TR002",
        vehicleId: "VH001",
        driverId: "DR001",
        status: "completed",
        tripType: "pickup",
        startLocation: {
          address: "MG Road, Bangalore",
          coordinates: {
            type: "Point",
            coordinates: [77.5946, 12.9716]
          },
          timestamp: new Date(Date.now() - 2 * 60 * 60 * 1000) // 2 hours ago
        },
        endLocation: {
          address: "Koramangala, Bangalore",
          coordinates: {
            type: "Point",
            coordinates: [77.5762, 12.9719]
          },
          timestamp: new Date(Date.now() - 1 * 60 * 60 * 1000) // 1 hour ago
        },
        actualRoute: {
          distance: 8.2,
          duration: 25
        },
        createdAt: new Date(Date.now() - 2 * 60 * 60 * 1000),
        updatedAt: new Date(Date.now() - 1 * 60 * 60 * 1000)
      }
    ];
    
    try {
      const tripResults = await db.collection('trips').insertMany(sampleTrips);
      console.log(`✅ Inserted ${tripResults.insertedCount} trips`);
    } catch (error) {
      if (error.code === 11000) {
        console.log('ℹ️  Some trips already exist, skipping duplicates');
      } else {
        console.error('Error inserting trips:', error.message);
      }
    }
    
    // 5. VERIFY DATA
    console.log('\n📊 Database Summary:');
    const vehicleCount = await db.collection('vehicles').countDocuments();
    const driverCount = await db.collection('drivers').countDocuments();
    const locationCount = await db.collection('locationTracking').countDocuments();
    const tripCount = await db.collection('trips').countDocuments();
    
    console.log(`🚗 Vehicles: ${vehicleCount}`);
    console.log(`👨‍💼 Drivers: ${driverCount}`);
    console.log(`📍 Location Records: ${locationCount}`);
    console.log(`🛣️  Trips: ${tripCount}`);
    
    // 6. TEST SOME QUERIES
    console.log('\n🔍 Testing queries...');
    
    // Find available vehicles
    const availableVehicles = await db.collection('vehicles').find({ status: "active" }).toArray();
    console.log(`📋 Available vehicles: ${availableVehicles.length}`);
    
    // Find available drivers
    const availableDrivers = await db.collection('drivers').find({ currentStatus: "available" }).toArray();
    console.log(`📋 Available drivers: ${availableDrivers.length}`);
    
    // Find active trips
    const activeTrips = await db.collection('trips').find({ status: "in-progress" }).toArray();
    console.log(`📋 Active trips: ${activeTrips.length}`);
    
    console.log('\n🎉 Simple fleet database setup complete!');
    console.log('\n📋 Next steps:');
    console.log('1. Start your server: node index.js');
    console.log('2. Test API: http://localhost:3000/test-db');
    console.log('3. View collections: http://localhost:3000/collections');
    console.log('4. Build API routes for CRUD operations');
    
  } catch (error) {
    console.error('❌ Database setup failed:', error);
  } finally {
    await client.close();
    console.log('✅ Database connection closed');
  }
}

// Run the setup
simpleSetup();