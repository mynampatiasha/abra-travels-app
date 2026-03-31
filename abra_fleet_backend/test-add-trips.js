const { MongoClient } = require('mongodb');
require('dotenv').config();

async function addTestTrips() {
  const uri = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';
  console.log(`Connecting to MongoDB at: ${uri}`);
  
  const client = new MongoClient(uri);

  try {
    await client.connect();
    console.log('Successfully connected to MongoDB');
    
    const db = client.db();
    
    // List all collections for debugging
    const collections = await db.listCollections().toArray();
    console.log('Available collections:', collections.map(c => c.name));
    
    // Get a customer to associate with trips
    const customer = await db.collection('customers').findOne({});
    console.log('Found customer:', customer ? customer.customerId : 'No customers found');
    
    if (!customer) {
      console.error('No customers found in the database. Please create a customer first.');
      return;
    }

    console.log(`Adding test trips for customer: ${customer.customerId}`);

    const testTrips = [
      {
        tripId: `TRIP-${Date.now()}-1`,
        customer: {
          customerId: customer.customerId,
          name: customer.name,
          contactInfo: customer.contactInfo
        },
        startLocation: {
          name: 'Customer Office',
          address: '123 Business St, Commerce City, CA 90210',
          coordinates: { lat: 34.0522, lng: -118.2437 }
        },
        endLocation: {
          name: 'Downtown LA',
          address: '400 S Main St, Los Angeles, CA 90013',
          coordinates: { lat: 34.0500, lng: -118.2500 }
        },
        startTime: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000), // 2 days ago
        endTime: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000 + 2 * 60 * 60 * 1000), // 2 hours later
        status: 'completed',
        distance: 15.5, // km
        duration: 120, // minutes
        driver: {
          driverId: 'DRV-123456',
          name: { firstName: 'John', lastName: 'Driver' }
        },
        vehicle: {
          vehicleId: 'VH-001',
          make: 'Toyota',
          model: 'Camry',
          year: 2022
        },
        fare: 45.50,
        createdAt: new Date(),
        updatedAt: new Date()
      },
      {
        tripId: `TRIP-${Date.now()}-2`,
        customer: {
          customerId: customer.customerId,
          name: customer.name,
          contactInfo: customer.contactInfo
        },
        startLocation: {
          name: 'Customer Office',
          address: '123 Business St, Commerce City, CA 90210',
          coordinates: { lat: 34.0522, lng: -118.2437 }
        },
        endLocation: {
          name: 'LAX Airport',
          address: '1 World Way, Los Angeles, CA 90045',
          coordinates: { lat: 33.9416, lng: -118.4085 }
        },
        startTime: new Date(),
        endTime: null,
        status: 'in_progress',
        distance: 18.7, // km
        duration: 25, // minutes (estimated)
        driver: {
          driverId: 'DRV-789012',
          name: { firstName: 'Jane', lastName: 'Smith' }
        },
        vehicle: {
          vehicleId: 'VH-002',
          make: 'Honda',
          model: 'Accord',
          year: 2023
        },
        fare: 55.75,
        createdAt: new Date(),
        updatedAt: new Date()
      },
      {
        tripId: `TRIP-${Date.now()}-3`,
        customer: {
          customerId: customer.customerId,
          name: customer.name,
          contactInfo: customer.contactInfo
        },
        startLocation: {
          name: 'Customer Home',
          address: '456 Residential Ave, Beverly Hills, CA 90210',
          coordinates: { lat: 34.1030, lng: -118.4105 }
        },
        endLocation: {
          name: 'Santa Monica Pier',
          address: '200 Santa Monica Pier, Santa Monica, CA 90401',
          coordinates: { lat: 34.0086, lng: -118.4981 }
        },
        startTime: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000), // 2 days from now
        endTime: null,
        status: 'scheduled',
        distance: 20.3, // km
        duration: 35, // minutes (estimated)
        driver: {
          driverId: 'DRV-345678',
          name: { firstName: 'Mike', lastName: 'Johnson' }
        },
        vehicle: {
          vehicleId: 'VH-003',
          make: 'Tesla',
          model: 'Model 3',
          year: 2023
        },
        fare: 65.25,
        createdAt: new Date(),
        updatedAt: new Date()
      }
    ];

    // Insert test trips
    const result = await db.collection('trips').insertMany(testTrips);
    console.log(`Added ${result.insertedCount} test trips for customer ${customer.customerId}`);
    
    // Print the trip IDs for reference
    console.log('Test trip IDs:', Object.values(result.insertedIds).map(id => id.toString()));
    
  } catch (error) {
    console.error('Error adding test trips:', error);
  } finally {
    await client.close();
  }
}

// Run the function
addTestTrips();
